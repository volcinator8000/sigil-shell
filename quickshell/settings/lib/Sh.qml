pragma Singleton
pragma ComponentBehavior: Bound

// Process plumbing for the settings window (the QML twin of run / run_async /
// spawn / snd in sigil-settings.py). Every call is async; callbacks get
// (output, exitCode). Also carries the window-wide toast channel.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string user: Quickshell.env("USER") || "kali"
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string cfg: home + "/.config"
    readonly property string ks: cfg + "/keysound"
    readonly property string ksSh: ks + "/keysound.sh"
    readonly property string keepAwake: cfg + "/swaync/keepawake.sh"
    readonly property string nightLight: cfg + "/swaync/nightlight.sh"
    readonly property string hypridle: cfg + "/hypr/hypridle.conf"
    readonly property string lockSh: cfg + "/hypr/scripts/lock.sh"
    readonly property string ultra: home + "/.local/bin/ultra"
    readonly property string hyprpaper: cfg + "/hypr/hyprpaper.conf"
    readonly property string hyprlock: cfg + "/hypr/hyprlock.conf"
    readonly property string hyprsunset: cfg + "/hypr/hyprsunset.conf"
    readonly property string localLua: cfg + "/hypr/local.lua"
    readonly property string tabletLua: cfg + "/hypr/tablet.lua"
    readonly property string powerAuto: cfg + "/hypr/power-auto.conf"
    readonly property string walls: home + "/Pictures/Wallpapers"
    readonly property string updateNow: cfg + "/waybar/scripts/update-now.sh"
    readonly property string pyApp: cfg + "/sigil-settings/sigil-settings.py"

    signal toastRequested(string message)
    function toast(msg: string): void { toastRequested(msg); }
    // pages ask the window to hide itself (e.g. Widgets → "Arrange on desktop")
    signal hideRequested()
    function hideWindow(): void { hideRequested(); }

    // ── processes ────────────────────────────────────────────────────
    // The command runs as `timeout T cmd…`; the wrapper appends the exit code
    // after a marker so only the stdout stream has to finish (no race with exited()).
    Component {
        id: procComp
        Process {
            id: proc
            property var cb: null
            stdout: StdioCollector {
                onStreamFinished: {
                    const t = text;
                    const i = t.lastIndexOf("\n\u001fRC=");
                    const out = i >= 0 ? t.slice(0, i) : t;
                    const rc = i >= 0 ? parseInt(t.slice(i + 5)) : 1;
                    const f = proc.cb;
                    proc.cb = null;
                    if (f) {
                        try { f(out.trim(), isNaN(rc) ? 1 : rc); }
                        catch (e) { console.warn("sigil-settings: callback failed:", e); }
                    }
                    proc.destroy();
                }
            }
        }
    }

    function exec(cmd, cb, timeout, merge) {
        const script = 'timeout "$0" "$@" ' + (merge ? "2>&1" : "2>/dev/null") + '; printf "\\n\\037RC=%s" "$?"';
        const p = procComp.createObject(root, {
            command: ["sh", "-c", script, String(timeout || 8)].concat(cmd),
            cb: cb || null
        });
        p.running = true;
    }
    // stdout only (like run() in the Python app)
    function run(cmd, cb, timeout): void { exec(cmd, cb, timeout, false); }
    // stdout + stderr (like run_async())
    function runAll(cmd, cb, timeout): void { exec(cmd, cb, timeout, true); }
    // shell snippet; extra args become $1…
    function sh(script, cb, timeout, args): void { exec(["sh", "-c", script, "sh"].concat(args || []), cb, timeout, false); }

    function spawn(cmd): void { Quickshell.execDetached(cmd); }
    function hyprExec(command): void { spawn(["hyprctl", "dispatch", 'hl.dsp.exec_cmd("' + command + '")']); }
    // Kill a daemon by exact name and relaunch it through Hyprland.
    function restart(proc, command): void {
        run(["pkill", "-x", proc], () => later(300, () => hyprExec(command || proc)));
    }

    function readFile(path, cb): void { run(["cat", path], (out, rc) => cb(rc === 0 ? out : "", rc === 0)); }
    function writeFile(path, text, cb): void {
        sh('printf "%s" "$1" > "$2"', (out, rc) => { if (cb) cb(rc === 0); }, 8, [text, path]);
    }

    // UI sound from the active keysound pack (no-op when system sounds are off)
    function snd(ev): void { spawn([ksSh, "play", ev]); }

    // ── timers ───────────────────────────────────────────────────────
    Component {
        id: timerComp
        Timer {
            id: tm
            property var fn: null
            onTriggered: { const f = tm.fn; tm.fn = null; tm.destroy(); if (f) f(); }
        }
    }
    function later(ms, fn): void {
        const t = timerComp.createObject(root, { interval: ms, fn: fn });
        t.start();
    }

    // ── tiny parsers shared by pages ─────────────────────────────────
    function kv(text) {           // key=value files, '#' comments
        const out = {};
        for (const line of (text || "").split("\n")) {
            if (line.indexOf("=") < 0 || line.startsWith("#")) continue;
            const i = line.indexOf("=");
            out[line.slice(0, i).trim()] = line.slice(i + 1).trim();
        }
        return out;
    }
    function lastLine(out, fallback) {
        const ls = (out || "").split("\n").filter(l => l.trim());
        return ls.length ? ls[ls.length - 1].slice(0, 90) : fallback;
    }
}
