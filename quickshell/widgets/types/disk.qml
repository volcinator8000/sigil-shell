pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

Column {
    id: root
    spacing: 7
    readonly property int w: Math.max(196, entry.w || 0)
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }
    property var mounts: []

    Process {
        id: df
        command: ["df", "--output=target,pcent"].concat(String(root.o("mounts") || "/").split(/\s+/).filter(m => m))
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                root.mounts = text.trim().split("\n").slice(1).map(l => l.trim().split(/\s+/))
                    .filter(p => !seen[p[0]] && (seen[p[0]] = true))
                    .map(p => ({ name: p[0], pct: parseInt(p[1]) }));
            }
        }
    }
    Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: df.running = true }
    onEntryChanged: df.running = true

    WidgetHeader { width: root.w; title: "disks"; detail: "btrfs" }

    Repeater {
        model: root.mounts
        delegate: Row {
            required property var modelData
            spacing: 8
            WLabel { width: 44; text: parent.modelData.name; font.pixelSize: 12 }
            Rectangle {
                width: root.w - 44 - 34 - 16
                height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.s2
                Rectangle {
                    height: parent.height
                    radius: 3
                    width: parent.width * parent.parent.modelData.pct / 100
                    color: parent.parent.modelData.pct > 90 ? Theme.crit : parent.parent.modelData.pct > 75 ? Theme.warn : Theme.a2
                }
            }
            WLabel { width: 34; horizontalAlignment: Text.AlignRight; text: parent.modelData.pct + "%"; font.pixelSize: 12 }
        }
    }
}
