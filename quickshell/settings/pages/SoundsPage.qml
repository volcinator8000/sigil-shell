pragma ComponentBehavior: Bound

// Keysound packs: one pack drives keystrokes, notifications and system events.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false
    property var packs: []
    property var cfg: ({})
    property bool keysOn: false
    property bool regenerating: false

    readonly property var events: [["keys", "Keystrokes"], ["notify", "Notification"], ["notify-urgent", "Urgent"], ["lock", "Lock"], ["unlock", "Unlock"],
        ["shutter", "Shutter"], ["plug", "Plug"], ["unplug", "Unplug"], ["batt-low", "Battery low"],
        ["click", "Click"], ["toggle-on", "Toggle on"], ["toggle-off", "Toggle off"], ["open", "Open"], ["close", "Close"]]

    function pretty(n) {
        return ({ cybersigil: "Cybersigil (typewriter)", animalese: "Animalese (Animal Crossing)", frog: "Frog (croaks and pond plops)" })[n]
               || n.replace(/-/g, " ").replace(/\b\w/g, c => c.toUpperCase());
    }
    function readCfg(cb) { Sh.readFile(Sh.ks + "/config", t => { page.cfg = Sh.kv(t); if (cb) cb(); }); }
    function refresh() {
        Sh.sh('for d in "$1"/packs/*/; do basename "$d"; done', o => page.packs = o.split("\n").filter(x => x).sort(), 5, [Sh.ks]);
        readCfg();
        Sh.run([Sh.ksSh, "state"], o => keysToggle.checked = o === "true");
    }
    Component.onCompleted: refresh()
    readonly property string currentPack: packs[packDrop.currentIndex] || "cybersigil"

    function preview(ev) {
        const pack = currentPack;
        if (ev === "keys") { Sh.spawn(["python3", Sh.ks + "/keysoundd.py", "--demo", "--pack", pack]); return; }
        readCfg(() => Sh.spawn(["pw-play", "--volume", page.cfg.system_volume || "0.6", Sh.ks + "/packs/" + pack + "/" + ev + ".wav"]));
    }
    function regen() {
        regenerating = true;
        Sh.toast("Regenerating packs…");
        const ks = Sh.ks, pack = currentPack;
        Sh.sh('for p in cybersigil animalese frog; do python3 "$1/gen-sounds.py" --pack "$p"; done; "$1/keysound.sh" pack "$2"',
              () => { page.regenerating = false; Sh.toast("Packs regenerated"); }, 400, [ks, pack]);
    }

    Section {
        title: "Theme"
        description: "One pack drives keystrokes, notifications and system events. Packs live in ~/.config/keysound/packs/NAME/ as 23 WAV files."
        SettingRow {
            title: "Active pack"; subtitle: "Switches live, no restart needed"
            Dropdown {
                id: packDrop
                implicitWidth: 260
                model: page.packs.map(p => page.pretty(p))
                currentIndex: Math.max(0, page.packs.indexOf(page.cfg.pack || "cybersigil"))
                onActivated: i => {
                    const name = page.packs[i];
                    Sh.run([Sh.ksSh, "pack", name], () => Sh.toast("Pack: " + page.pretty(name)));
                }
            }
        }
        SettingRow {
            title: "Preview"; subtitle: "Play each event from the selected pack"
        }
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.bottomMargin: 12
            spacing: 6
            Repeater {
                model: page.events
                delegate: ChipButton {
                    required property var modelData
                    anchors.verticalCenter: undefined
                    text: modelData[1]
                    onClicked: page.preview(modelData[0])
                }
            }
        }
        SettingRow {
            title: "Pack files"; subtitle: "Open the folder or re-synthesise the built-in packs (a few seconds)"
            ActionButton { text: "Open folder"; onClicked: Sh.spawn(["xdg-open", Sh.ks + "/packs"]) }
            ActionButton { text: page.regenerating ? "Working…" : "Regenerate"; enabled: !page.regenerating; onClicked: page.regen() }
        }
    }

    Section {
        title: "Keystrokes"
        description: "Typewriter clicks from a small daemon reading the keyboard."
        SettingRow {
            title: "Key sounds"; subtitle: "Start or stop the daemon"
            Toggle {
                id: keysToggle
                onToggled: on => Sh.run([Sh.ksSh, on ? "start" : "stop"], () => Sh.toast("Key sounds " + (on ? "started" : "stopped")))
            }
        }
        SettingRow {
            title: "Volume"; subtitle: "Mixer level for keystrokes"
            Slider {
                value: parseFloat(page.cfg.volume || "0.45") * 100
                onCommitted: v => Sh.run([Sh.ksSh, "volume", (v / 100).toFixed(2)])
            }
        }
    }

    Section {
        title: "System sounds"
        description: "Notifications, lock/unlock, screenshots, charger, low battery, and the clicks/toggles in this app, the bar and the control center. Silenced by do-not-disturb (except lock/unlock)."
        SettingRow {
            title: "System sounds"
            Toggle {
                checked: (page.cfg.system || "true") !== "false"
                onToggled: on => Sh.run([Sh.ksSh, "system", on ? "on" : "off"], () => Sh.toast("System sounds " + (on ? "on" : "off")))
            }
        }
        SettingRow {
            title: "Volume"; subtitle: "Level for system sounds"
            Slider {
                value: parseFloat(page.cfg.system_volume || "0.6") * 100
                onCommitted: v => Sh.run([Sh.ksSh, "system-volume", (v / 100).toFixed(2)])
            }
        }
    }
}
