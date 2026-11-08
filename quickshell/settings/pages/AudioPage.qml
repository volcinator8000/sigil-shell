pragma ComponentBehavior: Bound

// Default devices and levels from wireplumber (wpctl), like the GTK Audio page.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false

    function refresh() { out.load(); inp.load(); }

    // [{id, name, def}] for "Sinks" / "Sources" from `wpctl status` (same parser as wp_nodes)
    function wpNodes(text, kind) {
        const nodes = [];
        let grab = false;
        const re = new RegExp("\\b" + kind + ":");
        for (const line of text.split("\n")) {
            if (re.test(line)) { grab = true; continue; }
            if (!grab) continue;
            const m = line.match(/^\s*[│|]?\s*(\*?)\s*(\d+)\.\s+(.*?)\s+\[vol:/);
            if (m) nodes.push({ id: parseInt(m[2]), name: m[3].trim(), def: m[1] === "*" });
            else if (["│", ""].indexOf(line.trim()) >= 0 || line.indexOf("├─") >= 0) { if (nodes.length) break; }
        }
        return nodes;
    }

    component Device: QtObject {
        id: dev
        required property string kind
        required property string target
        required property string title
        property var nodes: []
        property real volume: 0
        property bool muted: false
        function load() {
            Sh.run(["wpctl", "status"], o => dev.nodes = page.wpNodes(o, dev.kind));
            Sh.run(["wpctl", "get-volume", dev.target], o => {
                const m = o.match(/Volume:\s*([\d.]+)(.*)/);
                dev.volume = m ? parseFloat(m[1]) * 100 : 0;
                dev.muted = !!(m && m[2].indexOf("MUTED") >= 0);
            });
        }
    }
    property Device out: Device { kind: "Sinks"; target: "@DEFAULT_AUDIO_SINK@"; title: "Output" }
    property Device inp: Device { kind: "Sources"; target: "@DEFAULT_AUDIO_SOURCE@"; title: "Input" }
    Component.onCompleted: refresh()

    Section {
        title: "Devices and levels"
        description: "Defaults from wireplumber; per-app control in the mixer."
        Repeater {
            model: [page.out, page.inp]
            delegate: ColumnLayout {
                id: grp
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 0
                SettingRow {
                    divider: grp.index > 0
                    title: grp.modelData.title
                    subtitle: "default device"
                    Dropdown {
                        implicitWidth: 300
                        model: grp.modelData.nodes.length ? grp.modelData.nodes.map(n => n.name) : ["none"]
                        currentIndex: Math.max(0, grp.modelData.nodes.findIndex(n => n.def))
                        onActivated: i => {
                            const n = grp.modelData.nodes[i];
                            if (!n) return;
                            Sh.run(["wpctl", "set-default", String(n.id)], () => { Sh.toast("Default: " + n.name); grp.modelData.load(); });
                        }
                    }
                }
                SettingRow {
                    title: grp.modelData.title + " volume"
                    subtitle: grp.modelData.muted ? "muted" : ""
                    Slider {
                        from: 0; to: 150
                        value: Math.min(grp.modelData.volume, 150)
                        onCommitted: v => Sh.run(["wpctl", "set-volume", grp.modelData.target, Math.round(v) + "%"])
                    }
                    IconButton {
                        glyph: grp.modelData.title === "Output" ? "\u{F075F}" : "\u{F036D}"
                        hint: "Mute"
                        tint: grp.modelData.muted ? Theme.crit : Theme.dim
                        onClicked: {
                            const m = !grp.modelData.muted;
                            Sh.run(["wpctl", "set-mute", grp.modelData.target, m ? "1" : "0"], () => grp.modelData.muted = m);
                        }
                    }
                }
            }
        }
        SettingRow {
            title: "Mixer"; subtitle: "per-app volumes, ports, profiles"
            ActionButton { text: "Open pavucontrol"; onClicked: Sh.spawn(["pavucontrol"]) }
        }
    }
}
