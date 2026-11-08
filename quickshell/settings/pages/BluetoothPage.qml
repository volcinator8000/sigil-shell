pragma ComponentBehavior: Bound

// Bluetooth via bluetoothctl (power, scan, pair/trust/connect, forget).

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false
    property var devs: []
    property string status: ""
    property bool scanning: false

    Component.onCompleted: refresh()
    function refresh() {
        Sh.run(["bluetoothctl", "show"], o => { btSw.checked = o.indexOf("Powered: yes") >= 0; page.list(); });
    }
    function list() {
        if (!btSw.checked) { devs = []; status = "Bluetooth is off"; return; }
        Sh.sh('bluetoothctl devices | while read -r _ mac name; do case "$mac" in ??:??:??:??:??:??) ;; *) continue;; esac; '
            + 'i=$(bluetoothctl info "$mac"); c=0; p=0; t=0; '
            + 'case "$i" in *"Connected: yes"*) c=1;; esac; case "$i" in *"Paired: yes"*) p=1;; esac; case "$i" in *"Trusted: yes"*) t=1;; esac; '
            + 'printf "%s\\t%s\\t%s\\t%s\\t%s\\n" "$mac" "$c" "$p" "$t" "$name"; done', o => {
            const d = o.split("\n").filter(x => x).map(l => {
                const f = l.split("\t");
                return { mac: f[0], conn: f[1] === "1", paired: f[2] === "1", trusted: f[3] === "1", name: f.slice(4).join("\t") };
            });
            d.sort((a, b) => (a.conn !== b.conn ? (a.conn ? -1 : 1) : a.paired !== b.paired ? (a.paired ? -1 : 1) : a.name.toLowerCase().localeCompare(b.name.toLowerCase())));
            page.devs = d;
            page.status = d.length ? d.length + " device(s)" : "no devices known; scan to find some";
        }, 20);
    }
    function scan() {
        scanning = true;
        status = "scanning for 8 s…";
        Sh.runAll(["bluetoothctl", "--timeout", "8", "scan", "on"], () => { page.scanning = false; page.list(); }, 20);
    }
    function cmd(c, ok, timeout) {
        Sh.toast("Working…");
        Sh.runAll(c, (o, rc) => { Sh.toast(rc === 0 ? ok : Sh.lastLine(o, "failed")); page.list(); }, timeout || 20);
    }

    Section {
        title: "Bluetooth"
        SettingRow {
            title: "Bluetooth"; subtitle: "adapter power"
            Toggle {
                id: btSw
                onToggled: on => Sh.run(["bluetoothctl", "power", on ? "on" : "off"], () => Sh.later(800, () => page.list()))
            }
        }
    }

    Section {
        title: "Devices"
        description: page.status
        actions: [
            ActionButton { text: page.scanning ? "Scanning…" : "Scan 8 s"; enabled: !page.scanning && btSw.checked; onClicked: page.scan() }
        ]
        Repeater {
            model: page.devs
            delegate: SettingRow {
                id: d
                required property var modelData
                glyph: d.modelData.conn ? "\u{F00B1}" : "\u{F00AF}"
                glyphColor: d.modelData.conn ? Theme.a1 : Theme.dim
                title: d.modelData.name + (d.modelData.conn ? "  \u{F012C}" : "")
                titleColor: d.modelData.conn ? Theme.a1 : Theme.fg
                subtitle: d.modelData.mac + "  ·  " + (d.modelData.conn ? "connected" : d.modelData.paired ? "paired" : "seen, not paired")
                ActionButton {
                    visible: d.modelData.conn
                    text: "Disconnect"
                    onClicked: page.cmd(["bluetoothctl", "disconnect", d.modelData.mac], "Disconnected")
                }
                ActionButton {
                    visible: !d.modelData.conn && d.modelData.paired
                    text: "Connect"; accent: true
                    onClicked: page.cmd(["bluetoothctl", "connect", d.modelData.mac], "Connected " + d.modelData.name)
                }
                ActionButton {
                    visible: !d.modelData.conn && !d.modelData.paired
                    text: "Pair"; accent: true
                    onClicked: page.cmd(["sh", "-c", 'bluetoothctl pair "$1" && bluetoothctl trust "$1" && bluetoothctl connect "$1"', "sh", d.modelData.mac], "Paired " + d.modelData.name, 40)
                }
                IconButton {
                    glyph: "\u{F01B4}"; hint: "Forget device"
                    onClicked: page.cmd(["bluetoothctl", "remove", d.modelData.mac], "Forgot " + d.modelData.name)
                }
            }
        }
    }
}
