pragma ComponentBehavior: Bound

// Power: profile, keep-awake, automatic profile + eco (power-auto.conf), ultra
// power saver, brightness, night light (hyprsunset.conf) and idle timers
// (hypridle.conf). File formats are byte-for-byte those of the GTK app.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false
    property var profiles: []
    property string profile: ""
    property var pa: ({})
    property bool paReady: false
    property bool helper: false
    property var sunset: ({ start: "21:00", end: "07:30", temp: 4200, gamma: 100, day: 6500, enabled: true })
    property var idle: ({ dim: 120, dim_level: 15, lock: 300, off: 600, sleep: 630 })
    property real brightness: 100
    property int tempVal: 4200
    property int gammaVal: 100
    property int dayVal: 6500

    Component.onCompleted: {
        Sh.run(["powerprofilesctl", "list"], o => {
            page.profiles = o.split("\n").filter(l => l.trim().endsWith(":") && !l.startsWith("    "))
                             .map(l => l.trim().replace(/^[* ]+/, "").replace(/:$/, ""));
            refresh();
        });
        Sh.run([Sh.keepAwake, "state"], o => awake.checked = o === "true");
        readPowerAuto(d => { page.pa = d; page.paReady = true; });
        Sh.run(["sudo", "-n", "/usr/local/bin/sigil-powerctl", "status"], o => page.helper = o !== "");
        Sh.run(["brightnessctl", "-m"], o => {
            const b = o.split(",");
            page.brightness = b.length > 3 ? parseFloat(b[3]) : 100;
        });
        Sh.readFile(Sh.hyprsunset, t => {
            const s = page.parseSunset(t);
            page.sunset = s; page.tempVal = s.temp; page.gammaVal = s.gamma; page.dayVal = s.day;
            sched.checked = s.enabled; startField.text = s.start; endField.text = s.end;
        });
        Sh.readFile(Sh.hypridle, t => page.idle = page.parseIdle(t));
    }
    function refresh() {
        Sh.run(["powerprofilesctl", "get"], o => page.profile = o);
        Sh.run([Sh.nightLight, "state"], o => nightNow.checked = o === "true");
        Sh.run([Sh.ultra, "state"], o => ultraSw.checked = o === "true");
    }

    // ── power-auto.conf ──────────────────────────────────────────────
    function readPowerAuto(cb) {
        Sh.readFile(Sh.powerAuto, t => {
            const d = { enabled: "true", on_battery: "power-saver", on_ac: "balanced", eco_effects: "true", eco_brightness: "60" };
            Object.assign(d, Sh.kv(t));
            cb(d);
        });
    }
    function writePowerAuto() {
        if (!paReady || !profiles.length) return;
        paTimer.restart();
    }
    Timer {
        id: paTimer
        interval: 250
        onTriggered: page.readPowerAuto(d => {           // keep keys this page does not know about
            const upd = {
                enabled: paEnabled.checked ? "true" : "false",
                on_battery: page.profiles[paBat.currentIndex], on_ac: page.profiles[paAc.currentIndex],
                eco_effects: paEco.checked ? "true" : "false", eco_brightness: String(Math.round(paBright.value)),
                ultra_exit_on_ac: uExitAc.checked ? "true" : "false", ultra_at_pct: String(Math.round(uAt.value)),
                ultra_brightness: String(Math.round(uBright.value)), ultra_refresh: uRefresh.checked ? "true" : "false",
                ultra_max_mhz: String(Math.round(uMhz.value)), ultra_abm: String(Math.round(uAbm.value)),
                ultra_bluetooth_off: uBt.checked ? "true" : "false",
                ultra_quit_apps: uApps.text.split(/\s+/).filter(x => x).join(" ")
            };
            Object.assign(d, upd);
            const eco = ["enabled", "on_battery", "on_ac", "eco_effects", "eco_brightness"];
            let s = "# automatic power profile + eco mode on charger events (read by waybar/scripts/battery.sh every 10 s; edit in the settings app)\n"
                  + "# eco_effects=true: blur/shadows off on battery (iGPU work); eco_brightness=N: cap the backlight at N% when unplugging (0 = off)\n";
            for (const k of eco) s += k + "=" + d[k] + "\n";
            s += "# ultra power saver mode (~/.local/bin/ultra; settings app > Power > Ultra power saver)\n";
            for (const k in d) if (eco.indexOf(k) < 0) s += k + "=" + d[k] + "\n";
            page.pa = d;
            Sh.writeFile(Sh.powerAuto, s);
        })
    }

    // ── hyprsunset ───────────────────────────────────────────────────
    function parseSunset(text) {
        const d = { start: "21:00", end: "07:30", temp: 4200, gamma: 100, day: 6500, enabled: true };
        if (!text) return d;
        d.enabled = !/^#\s*schedule\s*=\s*off/m.test(text);
        const blocks = [];
        const re = /profile\s*\{([\s\S]*?)\}/g;
        let m;
        while ((m = re.exec(text)) !== null) blocks.push(m[1]);
        const tempOf = b => { const x = b.match(/temperature\s*=\s*(\d+)/); return x ? parseInt(x[1]) : 6500; };
        let night = null;
        for (const b of blocks) if (night === null || tempOf(b) < tempOf(night)) night = b;
        for (const b of blocks) {
            const t = b.match(/time\s*=\s*(\d+):(\d+)/);
            if (!t) continue;
            const hhmm = String(parseInt(t[1])).padStart(2, "0") + ":" + String(parseInt(t[2])).padStart(2, "0");
            if (b === night) {
                d.start = hhmm; d.temp = tempOf(b);
                const g = b.match(/gamma\s*=\s*(\d+)/);
                d.gamma = g ? parseInt(g[1]) : 100;
            } else {
                d.end = hhmm; d.day = tempOf(b);
            }
        }
        return d;
    }
    function applySunset() {
        const times = [];
        for (const f of [startField, endField]) {
            const m = f.text.match(/^\s*(\d{1,2}):(\d{2})\s*$/);
            if (!m || parseInt(m[1]) > 23 || parseInt(m[2]) > 59) { f.error = true; Sh.toast("Time must be HH:MM"); return; }
            f.error = false;
            times.push(parseInt(m[1]) + ":" + String(parseInt(m[2])).padStart(2, "0"));
        }
        const enabled = sched.checked;
        const day = dayVal >= 6500 ? "    identity = true\n" : "    temperature = " + dayVal + "\n";
        const ng = gammaVal < 100 ? "    gamma = " + gammaVal + "\n" : "";
        const text = "# hyprsunset schedule (generated by sigil-settings) - warm evenings, neutral by day\n"
                   + "# manual override: ~/.config/swaync/nightlight.sh on|off|toggle\n"
                   + "# schedule = " + (enabled ? "on" : "off") + "\nmax-gamma = 150\n\n"
                   + "profile {\n    time = " + times[1] + "\n" + day + "}\n\n"
                   + "profile {\n    time = " + times[0] + "\n    temperature = " + tempVal + "\n" + ng + "}\n";
        Sh.writeFile(Sh.hyprsunset, text, () => {
            Sh.run([Sh.nightLight, "reset"], () => {
                if (enabled) Sh.restart("hyprsunset");
                else Sh.sh('hyprctl hyprsunset identity; hyprctl hyprsunset gamma 100; pkill -x hyprsunset');
                Sh.later(900, () => Sh.run([Sh.nightLight, "state"], o => nightNow.checked = o === "true"));
            });
        });
        Sh.toast(enabled ? "Night light schedule applied" : "Night light schedule disabled");
    }

    // ── hypridle ─────────────────────────────────────────────────────
    function parseIdle(text) {
        const t = { dim: 120, dim_level: 15, lock: 300, off: 600, sleep: 630 };
        const re = /listener\s*\{([\s\S]*?)\}/g;
        let b;
        while ((b = re.exec(text || "")) !== null) {
            const m = b[1].match(/timeout\s*=\s*(\d+)/), cmd = b[1].match(/on-timeout\s*=\s*(.*)/);
            if (!(m && cmd)) continue;
            const secs = parseInt(m[1]), c = cmd[1];
            if (c.indexOf("brightnessctl") >= 0) {
                t.dim = secs;
                const l = c.match(/set\s+(\d+)%/);
                if (l) t.dim_level = parseInt(l[1]);
            } else if (c.indexOf("lock-session") >= 0) t.lock = secs;
            else if (c.indexOf("dpms") >= 0) t.off = secs;
            else if (c.indexOf("suspend") >= 0 || c.indexOf("hibernate") >= 0) t.sleep = secs;
        }
        return t;
    }
    function applyIdle() {
        const [dim, lock, off, sleep] = [idDim, idLock, idOff, idSleep].map(r => Math.round(r.value * 60));
        const level = Math.round(idLevel.value);
        let p = ["general {", "    # plain hyprlock: a stale/hung hyprlock must not block re-locking", "    lock_cmd = " + Sh.lockSh,
                 "    before_sleep_cmd = loginctl lock-session", "    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms(\"on\")'",
                 "    inhibit_sleep = 3   # delay suspend until the lock screen is drawn", "}", "",
                 "# generated by sigil-settings; edit there or by hand (timeouts in seconds)"];
        if (dim) p = p.concat(["", "listener {", "    timeout = " + dim, "    on-timeout = brightnessctl -s set " + level + "%", "    on-resume = brightnessctl -r", "}"]);
        if (lock) p = p.concat(["", "listener {", "    timeout = " + lock, "    on-timeout = loginctl lock-session", "}"]);
        if (off) p = p.concat(["", "listener {", "    timeout = " + off, "    on-timeout = hyprctl dispatch 'hl.dsp.dpms(\"off\")'", "    on-resume = hyprctl dispatch 'hl.dsp.dpms(\"on\")'", "}"]);
        if (sleep) p = p.concat(["", "listener {", "    timeout = " + sleep, "    on-timeout = systemctl suspend", "}"]);
        Sh.writeFile(Sh.hypridle, p.join("\n") + "\n", () => { Sh.restart("hypridle"); Sh.toast("hypridle restarted with new timers"); });
    }

    // ── UI ───────────────────────────────────────────────────────────
    Section {
        title: "Power profile"
        SettingRow {
            title: "Profile"; subtitle: "power-profiles-daemon / amd-pstate-epp"
            Dropdown {
                model: page.profiles.length ? page.profiles : ["unavailable"]
                currentIndex: Math.max(0, page.profiles.indexOf(page.profile))
                onActivated: i => {
                    const p = page.profiles[i];
                    if (!p) return;
                    Sh.run(["powerprofilesctl", "set", p], () => { page.profile = p; Sh.toast("Profile: " + p); });
                }
            }
        }
        SettingRow {
            title: "Keep awake"; subtitle: "Inhibit idle dimming, lock and sleep"
            Toggle { id: awake; onToggled: on => Sh.run([Sh.keepAwake, on ? "on" : "off"], () => Sh.toast("Keep awake " + (on ? "on" : "off"))) }
        }
    }

    Section {
        title: "Automatic profile"
        description: "Switch on charger events (checked every 10 s by the battery widget)."
        enabled: page.paReady
        SettingRow {
            title: "Switch automatically"
            Toggle { id: paEnabled; checked: page.pa.enabled === "true"; onToggled: page.writePowerAuto() }
        }
        SettingRow {
            title: "On battery"
            Dropdown {
                id: paBat
                model: page.profiles.length ? page.profiles : ["power-saver"]
                currentIndex: Math.max(0, page.profiles.indexOf(page.pa.on_battery))
                onActivated: page.writePowerAuto()
            }
        }
        SettingRow {
            title: "On charger"
            Dropdown {
                id: paAc
                model: page.profiles.length ? page.profiles : ["balanced"]
                currentIndex: Math.max(0, page.profiles.indexOf(page.pa.on_ac))
                onActivated: page.writePowerAuto()
            }
        }
        SettingRow {
            title: "Eco effects on battery"; subtitle: "Blur and shadows off while unplugged (less GPU work), restored on charger"
            Toggle { id: paEco; checked: (page.pa.eco_effects || "true") === "true"; onToggled: page.writePowerAuto() }
        }
        SettingRow {
            title: "Brightness cap on unplug"; subtitle: "percent, 0 = leave it"
            SpinField { id: paBright; from: 0; to: 100; stepSize: 5; value: parseInt(page.pa.eco_brightness || "60") || 0; onValueModified: page.writePowerAuto() }
        }
    }

    Section {
        title: "Ultra power saver"
        description: "Focus mode: no effects, lowest refresh rate, minimal bar, short idle timers, chat apps closed, bluetooth off. SUPER+SHIFT+U or `ultra` in a terminal; everything comes back on exit."
        SettingRow {
            title: "Ultra mode now"; subtitle: "takes a second or two either way"
            Toggle {
                id: ultraSw
                onToggled: on => {
                    Sh.toast(on ? "Entering ultra power saver…" : "Leaving ultra power saver…");
                    Sh.runAll([Sh.ultra, on ? "on" : "off"], (o, rc) => Sh.toast(o ? Sh.lastLine(o, "") : (rc === 0 ? "done" : "ultra failed")), 30);
                }
            }
        }
        SettingRow {
            title: "Leave when the charger is plugged in"; enabled: page.paReady
            Toggle { id: uExitAc; checked: page.pa.ultra_exit_on_ac !== "false"; onToggled: page.writePowerAuto() }
        }
        SettingRow {
            title: "Enter automatically below"; subtitle: "battery percent, 0 = never"; enabled: page.paReady
            SpinField { id: uAt; from: 0; to: 60; stepSize: 5; value: parseInt(page.pa.ultra_at_pct || "0") || 0; onValueModified: page.writePowerAuto() }
        }
        SettingRow {
            title: "Backlight cap"; subtitle: "percent on entering"; enabled: page.paReady
            SpinField { id: uBright; from: 5; to: 100; stepSize: 5; value: parseInt(page.pa.ultra_brightness || "30") || 30; onValueModified: page.writePowerAuto() }
        }
        SettingRow {
            title: "Lowest refresh rate"; subtitle: "switch the panel to its slowest mode (40 Hz here); back to hyprland.lua on exit"; enabled: page.paReady
            Toggle { id: uRefresh; checked: page.pa.ultra_refresh !== "false"; onToggled: page.writePowerAuto() }
        }
        SettingRow {
            title: "Bluetooth off"; subtitle: "powered back on when leaving if it was on"; enabled: page.paReady
            Toggle { id: uBt; checked: page.pa.ultra_bluetooth_off !== "false"; onToggled: page.writePowerAuto() }
        }
        SettingRow {
            title: "Apps to close"; subtitle: "space separated, relaunched on exit"; enabled: page.paReady
            TextField {
                id: uApps
                implicitWidth: 240
                text: page.pa.ultra_quit_apps !== undefined ? page.pa.ultra_quit_apps : "vesktop slack spotify"
                onEdited: page.writePowerAuto()
            }
        }
        SettingRow {
            title: "CPU clock cap"; subtitle: "MHz, root helper" + (page.helper ? "" : " (not installed)"); enabled: page.paReady
            SpinField { id: uMhz; from: 800; to: 5000; stepSize: 100; value: parseInt(page.pa.ultra_max_mhz || "2400") || 2400; onValueModified: page.writePowerAuto() }
        }
        SettingRow {
            title: "Panel power saving (ABM)"; subtitle: "amdgpu adaptive backlight 0-4, root helper" + (page.helper ? "" : " (not installed)"); enabled: page.paReady
            SpinField { id: uAbm; from: 0; to: 4; stepSize: 1; value: parseInt(page.pa.ultra_abm || "3"); onValueModified: page.writePowerAuto() }
        }
        SettingRow {
            visible: !page.helper
            title: "Root helper not installed"
            subtitle: "the clock cap and ABM need system/usr/local/bin/sigil-powerctl + system/etc/sudoers.d (install.sh does both)"
            glyph: "\u{F0026}"
            glyphColor: Theme.warn
        }
    }

    Section {
        title: "Display"
        SettingRow {
            title: "Brightness"; subtitle: "Panel backlight"
            Slider { from: 1; to: 100; value: page.brightness; onCommitted: v => Sh.run(["brightnessctl", "-q", "set", Math.round(v) + "%"]) }
        }
    }

    Section {
        title: "Night light"
        description: "hyprsunset warms the screen on a schedule; the override switch lasts until the next scheduled change."
        SettingRow {
            title: "Schedule"; subtitle: "Run hyprsunset at login and follow the times below"
            Toggle { id: sched }
        }
        SettingRow {
            title: "Night light now"; subtitle: "Manual override"
            Toggle { id: nightNow; onToggled: on => Sh.run([Sh.nightLight, on ? "on" : "off"], () => Sh.toast("Night light " + (on ? "on" : "off"))) }
        }
        SettingRow {
            title: "Night warmth"; subtitle: "Colour temperature at night (lower = warmer); previews live"
            Slider {
                from: 2500; to: 6000; stepSize: 100; value: page.sunset.temp; format: v => Math.round(v) + " K"
                onCommitted: v => { page.tempVal = Math.round(v); if (nightNow.checked) Sh.run(["hyprctl", "hyprsunset", "temperature", String(page.tempVal)]); }
            }
        }
        SettingRow {
            title: "Night brightness"; subtitle: "Gamma applied with the warm tint; previews live"
            Slider {
                from: 40; to: 100; stepSize: 5; value: page.sunset.gamma
                onCommitted: v => { page.gammaVal = Math.round(v); if (nightNow.checked) Sh.run(["hyprctl", "hyprsunset", "gamma", String(page.gammaVal)]); }
            }
        }
        SettingRow {
            title: "Day warmth"; subtitle: "Daytime colour temperature; 6500 K = untouched"
            Slider {
                from: 4000; to: 6500; stepSize: 100; value: page.sunset.day; format: v => Math.round(v) + " K"
                onCommitted: v => {
                    page.dayVal = Math.round(v);
                    if (!nightNow.checked)
                        Sh.run(page.dayVal >= 6500 ? ["hyprctl", "hyprsunset", "identity"] : ["hyprctl", "hyprsunset", "temperature", String(page.dayVal)]);
                }
            }
        }
        SettingRow {
            title: "Evening start"; subtitle: "HH:MM"
            TextField { id: startField; implicitWidth: 90 }
        }
        SettingRow {
            title: "Morning end"; subtitle: "HH:MM"
            TextField { id: endField; implicitWidth: 90 }
        }
        SettingRow {
            title: "Apply schedule"; subtitle: "Write hyprsunset.conf and restart hyprsunset"
            ActionButton { text: "Apply"; accent: true; onClicked: page.applySunset() }
        }
    }

    Section {
        title: "Idle timers"
        description: "Rewrites hypridle.conf and restarts hypridle. 0 disables a step."
        SettingRow { title: "Dim after"; subtitle: "minutes"
            SpinField { id: idDim; from: 0; to: 120; stepSize: 0.5; decimals: 1; value: page.idle.dim / 60 } }
        SettingRow { title: "Dim level"; subtitle: "percent of full brightness"
            SpinField { id: idLevel; from: 1; to: 100; stepSize: 5; value: page.idle.dim_level } }
        SettingRow { title: "Lock after"; subtitle: "minutes"
            SpinField { id: idLock; from: 0; to: 240; stepSize: 0.5; decimals: 1; value: page.idle.lock / 60 } }
        SettingRow { title: "Screen off after"; subtitle: "minutes"
            SpinField { id: idOff; from: 0; to: 240; stepSize: 0.5; decimals: 1; value: page.idle.off / 60 } }
        SettingRow { title: "Sleep after"; subtitle: "minutes, suspend"
            SpinField { id: idSleep; from: 0; to: 480; stepSize: 0.5; decimals: 1; value: page.idle.sleep / 60 } }
        SettingRow {
            title: "Apply"; subtitle: "Write the config and restart the idle daemon"
            ActionButton { text: "Apply"; accent: true; onClicked: page.applyIdle() }
        }
    }
}
