pragma Singleton
pragma ComponentBehavior: Bound

// Pending pacman + AUR updates. Reuses the checker from the waybar days
// (~/.config/waybar/scripts/updates.sh: temp sync db + fakeroot, no root needed, cached in
// $XDG_RUNTIME_DIR/waybar-updates.json) and the upgrade window (update-now.sh).
// Checks at start (cache first, so the count shows instantly), every 4 h, and after an upgrade.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string scripts: Quickshell.env("HOME") + "/.config/waybar/scripts"
    property int count: 0
    property int repo: 0
    property int aur: 0
    property var packages: []            // [{ name, from, to }]
    property string state: "unknown"     // unknown | uptodate | pending | many | offline
    property bool checking: false
    property bool upgrading: false
    property real checkedAt: 0

    function parse(txt) {
        let d;
        try { d = JSON.parse(txt.trim().split("\n").pop() || "{}"); } catch (e) { return; }
        const tip = String(d.tooltip || "");
        if (d.class === "offline" && root.state !== "unknown") return;   // keep the last real result
        root.state = d.class || "unknown";
        const m = tip.match(/repo:\s*(\d+)\s*·\s*aur:\s*(\d+)/);
        root.repo = m ? parseInt(m[1]) : 0;
        root.aur = m ? parseInt(m[2]) : 0;
        root.count = m ? root.repo + root.aur : (parseInt(String(d.text || "").replace(/\D/g, "")) || 0);
        root.packages = tip.split("\n").slice(2).filter(l => l.includes(" -> ")).map(l => {
            const p = l.trim().split(/\s+/);
            return { name: p[0], from: p[1] || "", to: p[3] || "" };
        });
        root.checkedAt = Date.now();
    }

    Process {
        id: cached
        command: ["bash", root.scripts + "/updates.sh", "--cached"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }
    Process {
        id: checker
        command: ["bash", root.scripts + "/updates.sh"]
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
        onRunningChanged: root.checking = running
    }
    Process {
        id: upgrader
        // own scope: a shell restart must never kill a running paru
        command: ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--unit=sigil-upgrade-" + Date.now(), root.scripts + "/update-now.sh"]
        onRunningChanged: { root.upgrading = running; if (!running) root.check(); }
    }

    function check() { if (!checker.running) checker.running = true; }
    function upgrade() { if (!upgrader.running) upgrader.running = true; }

    Component.onCompleted: { cached.running = true; startup.start(); }
    Timer { id: startup; interval: 20000; onTriggered: root.check() }   // let the session settle first
    Timer { interval: 4 * 3600 * 1000; running: true; repeat: true; onTriggered: root.check() }

    IpcHandler {
        target: "updates"
        function check(): void { root.check(); }
        function upgrade(): void { root.upgrade(); }
        function count(): int { return root.count; }
        function list(): string { return root.packages.map(p => p.name + " " + p.from + " -> " + p.to).join("\n"); }
    }
}
