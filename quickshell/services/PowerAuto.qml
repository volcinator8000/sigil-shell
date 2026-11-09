pragma Singleton
pragma ComponentBehavior: Bound

// Charger automation (was waybar's battery.sh, run every 10 s). Event-driven here:
// UPower tells us about plug/unplug and percentage, PipeWire about new streams.
// Settings: ~/.config/hypr/power-auto.conf (edited on the settings app's Power page)
//
//   plug     sound · leave ultra mode (ultra_exit_on_ac) · profile on_ac · eco off
//   unplug   sound · profile on_battery · eco on (blur/shadows off, brightness cap)
//   ≤ ultra_at_pct while discharging → ultra mode, once per discharge
//   ≤ 15 % while discharging → warning + sound, once
//   call boost: on battery, hold `balanced` while an app records from a real microphone
//               (power-saver makes WebRTC calls sound robotic), drop back afterwards

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire

Singleton {
    id: root

    property var cfg: ({})
    function pa(k, d) { return cfg[k] !== undefined ? cfg[k] : d; }
    readonly property bool enabled: pa("enabled", "true") === "true"

    FileView {
        path: Theme.home + "/.config/hypr/power-auto.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const o = {};
            for (const l of text().split("\n")) {
                const m = l.match(/^\s*([A-Za-z_]+)\s*=\s*(.*?)\s*$/);
                if (m) o[m[1]] = m[2];
            }
            root.cfg = o;
        }
    }

    readonly property var dev: UPower.displayDevice
    readonly property real pct: dev && dev.ready ? (dev.percentage > 1 ? dev.percentage : dev.percentage * 100) : 100
    readonly property bool onBattery: UPower.onBattery
    readonly property string rt: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string ultraCmd: Theme.home + "/.local/bin/ultra"

    function sh(script) { Quickshell.execDetached(["sh", "-c", script]); }
    function notify(title, body, icon) { Quickshell.execDetached(["notify-send", "-a", "power", "-i", icon || "battery", title, body]); }
    function setProfile(p, title) {
        if (!p) return;
        sh("powerprofilesctl set '" + p + "' 2>/dev/null && notify-send -a power -i battery '" + title + "' 'profile: " + p + "'");
    }
    function eco(on) {
        if (pa("eco_effects", "false") === "true") {
            if (on) sh("hyprctl eval 'hl.config({ decoration = { blur = { enabled = false }, shadow = { enabled = false } } })' >/dev/null 2>&1");
            else sh("hyprctl reload >/dev/null 2>&1");     // hyprland.lua is the source of truth
        }
        const lvl = parseInt(pa("eco_brightness", "0")) || 0;
        if (on && lvl > 0)
            sh("cur=$(brightnessctl -m | cut -d, -f4 | tr -d %); [ \"$cur\" -gt " + lvl + " ] && brightnessctl -q set " + lvl + "%");
    }

    // ── plug / unplug ────────────────────────────────────────────────
    property bool started: false
    Timer { interval: 3000; running: true; onTriggered: root.started = true }   // no events for the start-up state
    onOnBatteryChanged: {
        if (!started) return;
        if (!onBattery) {
            Actions.sound("plug", true);
            if (Theme.ultra && pa("ultra_exit_on_ac", "true") !== "false") {
                Quickshell.execDetached([ultraCmd, "off", "--keep-profile"]);
                afterUltra.start();
            } else afterUltra.triggered();
        } else {
            Actions.sound("unplug", true);
            if (enabled) setProfile(pa("on_battery", ""), "On battery");
            eco(true);
            boostCheck.restart();
        }
    }
    // leaving ultra reloads Hyprland and restores the old profile; apply the charger profile after it
    Timer {
        id: afterUltra
        interval: 2500
        onTriggered: {
            if (root.enabled) root.setProfile(root.pa("on_ac", ""), "Charger connected");
            if (!Theme.ultra) root.eco(false);
            Quickshell.execDetached(["rm", "-f", root.rt + "/call-boost", root.rt + "/ultra-auto-entered"]);
            root.ultraEntered = false;
        }
    }

    // ── levels ───────────────────────────────────────────────────────
    property bool lowWarned: false
    property bool ultraEntered: false
    onPctChanged: levels()
    function levels() {
        if (!onBattery) { lowWarned = false; return; }
        const at = parseInt(pa("ultra_at_pct", "0")) || 0;
        if (at > 0 && pct <= at && !Theme.ultra && !ultraEntered) {
            ultraEntered = true;
            Quickshell.execDetached([ultraCmd, "on"]);
        }
        if (pct <= 15 && !lowWarned) {
            lowWarned = true;
            Actions.sound("batt-low", true);
            Quickshell.execDetached(["sh", "-c", "notify-send -u critical -a battery -i battery-caution \"Battery " + Math.round(pct) + "%\" \"$(" + Theme.home + "/.local/bin/sigil-battery)\""]);
        } else if (pct > 17) lowWarned = false;
    }

    // ── call boost ───────────────────────────────────────────────────
    // re-checked when streams come and go (debounced); the check itself is the old shell logic
    readonly property int streams: Pipewire.nodes.values.filter(n => n.isStream).length
    onStreamsChanged: if (onBattery) boostCheck.restart()
    Timer {
        id: boostCheck
        interval: 1500
        onTriggered: {
            if (!root.enabled || root.pa("call_boost", "true") === "false") return;
            const onb = root.pa("on_battery", "");
            root.sh('CB="' + root.rt + '/call-boost"; state=' + (root.onBattery ? "discharging" : "ac") + '; onb="' + onb + '"\n'
                + 'mons=" $(pactl list short sources 2>/dev/null | awk \'$2 ~ /\\.monitor$/ {printf "%s ", $1}\')"\n'
                + 'mic=$(pactl list short source-outputs 2>/dev/null | awk -v m="$mons" \'index(m, " " $2 " ") == 0\' | head -1)\n'
                + 'ultra() { [ -f "' + root.rt + '/ultra/active" ]; }\n'
                + 'if [ "$state" = discharging ] && [ -n "$mic" ] && ! ultra; then\n'
                + '  if [ ! -f "$CB" ] && [ "$(powerprofilesctl get)" = "$onb" ] && [ "$onb" != balanced ] && [ "$onb" != performance ]; then\n'
                + '    powerprofilesctl set balanced 2>/dev/null && touch "$CB" && notify-send -a power -i audio-input-microphone "Mic in use" "profile: balanced until the call ends"\n'
                + '  fi\n'
                + 'elif [ -f "$CB" ]; then\n'
                + '  rm -f "$CB"\n'
                + '  [ "$state" = discharging ] && [ "$(powerprofilesctl get)" = balanced ] && powerprofilesctl set "$onb" 2>/dev/null\n'
                + 'fi');
        }
    }
}
