pragma ComponentBehavior: Bound

// Live stats, refreshed every 2 s while the page is visible (paused when hidden).
// The dGPU is probed only through power/runtime_status, every 5th tick, so the
// check itself never wakes the card (same rule as the GTK app).

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false
    property string hero: ""
    property var prev: null
    property int gpuTicks: 0
    property bool gpuSeen: false
    property string gpuCard: "?"       // "?" = not detected yet, "" = none
    property string profileCache: ""
    property bool nightCache: false

    onPageActiveChanged: if (pageActive) { prev = null; tick(); }
    function refresh() {
        Sh.run(["powerprofilesctl", "get"], out => page.profileCache = out);
        Sh.run([Sh.nightLight, "state"], out => page.nightCache = out === "true");
    }
    Component.onCompleted: {
        refresh();
        Sh.sh('printf "%s  //  %s  //  linux %s  //  hyprland" "$(uname -n)" "$USER" "$(uname -r)"', out => page.hero = out);
        Sh.sh('for c in card1 card0 card2; do d=/sys/class/drm/$c/device; '
            + 'case "$(readlink -f $d/driver)" in *amdgpu*) [ "$(cat $d/boot_vga 2>/dev/null)" != 1 ] && { echo $c; exit; };; esac; done',
              out => page.gpuCard = out.trim());
    }

    Timer {
        interval: 2000
        repeat: true
        running: page.pageActive
        onTriggered: page.tick()
    }

    function tick() {
        gpuTicks++;
        const gpu = ((gpuTicks % 5 === 1 || !gpuSeen) && gpuCard && gpuCard !== "?") ? "/sys/class/drm/" + gpuCard + "/device" : "";
        Sh.sh('head -1 /proc/stat; echo @@; cat /proc/loadavg; echo @@; cat /proc/meminfo; echo @@; '
            + 'b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | sort | head -1); '
            + 'if [ -n "$b" ]; then cat "$b/capacity"; cat "$b/status"; cat "$b/power_now" 2>/dev/null || echo 0; fi; echo @@; '
            + 'cat /proc/uptime; echo @@; cat "$XDG_RUNTIME_DIR/waybar-updates.json" 2>/dev/null; echo @@; '
            + 'p=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null); [ -n "$p" ] || p=$(cat "$XDG_RUNTIME_DIR/ppd-profile" 2>/dev/null); echo "$p"; echo @@; '
            + 'if [ -n "$1" ]; then cat "$1/power/runtime_status" 2>/dev/null; echo; cat "$1/power/control" 2>/dev/null; fi',
              out => page.parse(out.split(/^@@$/m).map(x => x.replace(/^\n/, "")), gpu !== ""), 5, [gpu]);
    }

    function parse(s, gpuRead) {
        // CPU
        const f = (s[0] || "").trim().split(/\s+/);
        if (f.length > 5) {
            const vals = f.slice(1, 9).map(Number);
            const idle = vals[3] + vals[4], total = vals.reduce((a, b) => a + b, 0);
            if (prev) {
                const dt = total - prev[0], di = idle - prev[1];
                const pct = dt ? 100 * (dt - di) / dt : 0;
                cpu.value = Math.round(pct) + "%";
                cpu.sub = "load " + (s[1] || "").trim().split(/\s+/).slice(0, 3).join(" ");
                cpu.frac = pct / 100;
                cpu.state_ = pct > 85 ? "alert" : "";
            }
            prev = [total, idle];
        }
        // memory
        const mi = {};
        for (const l of (s[2] || "").split("\n")) {
            const i = l.indexOf(":");
            if (i > 0) mi[l.slice(0, i)] = parseInt(l.slice(i + 1)) || 0;
        }
        if (mi.MemTotal) {
            const used = mi.MemTotal - (mi.MemAvailable || 0);
            mem.value = (used / 1048576).toFixed(1) + " G";
            mem.sub = "of " + (mi.MemTotal / 1048576).toFixed(1) + " G · swap " + (((mi.SwapTotal || 0) - (mi.SwapFree || 0)) / 1048576).toFixed(1) + " G";
            mem.frac = used / mi.MemTotal;
            mem.state_ = used / mi.MemTotal > 0.9 ? "alert" : "";
        }
        // battery
        const b = (s[3] || "").trim().split("\n");
        if (b.length >= 2 && b[0] !== "") {
            const cap = parseInt(b[0]) || 0, st = (b[1] || "").trim(), pw = parseInt(b[2]) || 0;
            bat.value = cap + "%";
            bat.sub = (pw ? (pw / 1e6).toFixed(1) + " W · " : "") + st.toLowerCase();
            bat.frac = cap / 100;
            bat.state_ = cap <= 15 && st === "Discharging" ? "bad" : cap <= 30 && st === "Discharging" ? "alert" : "";
        }
        // dGPU (runtime PM state only)
        if (gpuRead) {
            gpuSeen = true;
            const g = (s[7] || "").split("\n");
            const gs = (g[0] || "").trim(), pinned = (g[1] || "").trim() === "on";
            gpuCardTile.value = gs || "n/a";
            gpuCardTile.sub = pinned ? "held awake · performance profile" : "runtime power state · every 10 s";
            gpuCardTile.state_ = (gs !== "active" || pinned) ? "" : "alert";
        } else if (gpuCard === "") {
            gpuCardTile.value = "n/a";
        }
        // uptime
        const secs = parseFloat((s[4] || "0").split(/\s+/)[0]);
        if (!isNaN(secs)) {
            up.value = Math.floor(secs / 3600) + "h " + String(Math.floor(secs % 3600 / 60)).padStart(2, "0") + "m";
            up.sub = "since " + Qt.formatDateTime(new Date(Date.now() - secs * 1000), "ddd HH:mm");
        }
        // updates cache (written by the bar's updates module)
        try {
            const d = JSON.parse((s[5] || "").trim() || "{}");
            const n = String(d.text || "").replace(/\D/g, "") || "0";
            upd.value = n;
            upd.sub = String(d.tooltip || "").replace(/\n/g, " · ") || "not checked";
            upd.state_ = n !== "0" ? "alert" : "";
        } catch (e) {
            upd.value = "?";
            upd.sub = "cache unreadable";
        }
        prof.value = (s[6] || "").trim() || profileCache || "—";
        night.value = nightCache ? "on" : "off";
    }

    Label {
        Layout.fillWidth: true
        text: page.hero
        color: Theme.dim
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }

    Section {
        title: "Live"
        card: false
        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 10
            rowSpacing: 10
            uniformCellWidths: true
            StatCard { id: cpu; label: "CPU" }
            StatCard { id: mem; label: "MEMORY" }
            StatCard { id: bat; label: "BATTERY" }
            StatCard { id: gpuCardTile; label: "dGPU"; showBar: false }
            StatCard { id: up; label: "UPTIME"; showBar: false }
            StatCard { id: upd; label: "UPDATES"; showBar: false }
            StatCard { id: prof; label: "PROFILE"; showBar: false; sub: "power-profiles-daemon" }
            StatCard { id: night; label: "NIGHT LIGHT"; showBar: false; sub: "hyprsunset" }
        }
    }

    Section {
        title: "Quick actions"
        SettingRow {
            title: "Lock"; subtitle: "loginctl lock-session"
            ActionButton { text: "Lock now"; onClicked: Sh.spawn(["loginctl", "lock-session"]) }
        }
        SettingRow {
            title: "Session"; subtitle: "power menu / log out (sigil-do power: the shell's menu, or wlogout in legacy mode)"
            ActionButton { text: "Power menu"; onClicked: Sh.sh('d="$HOME/.local/bin/sigil-do"; if [ -x "$d" ]; then exec "$d" power; else exec bash "$HOME/sigil-shell/bin/sigil-do" power; fi') }
        }
        SettingRow {
            title: "Control center"; subtitle: "notifications and toggles (sigil-do controlcenter)"
            ActionButton { text: "Open"; onClicked: Sh.sh('d="$HOME/.local/bin/sigil-do"; if [ -x "$d" ]; then exec "$d" controlcenter; else exec bash "$HOME/sigil-shell/bin/sigil-do" controlcenter; fi') }
        }
    }
}
