pragma ComponentBehavior: Bound

// Shows the output of a shell command, refreshed every `interval` seconds
// (slower on battery). Configure it on the Widgets page of the settings window.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

Column {
    id: root
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }
    readonly property int w: Math.max(220, entry.w || 0)
    spacing: 6
    property string output: ""
    property bool failed: false

    Process {
        id: proc
        command: ["sh", "-c", String(root.o("command") || "true")]
        stdout: StdioCollector { onStreamFinished: root.output = text.replace(/\s+$/, "") }
        onExited: (code) => root.failed = code !== 0
    }
    Timer {
        interval: Math.max(1, root.o("interval") || 60) * 1000 * (Theme.rich ? 1 : 2)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }
    onEntryChanged: if (!proc.running) proc.running = true

    WidgetHeader { width: root.w; title: String(root.o("title") || "command"); detail: root.failed ? "error" : "" }
    WLabel {
        width: root.w
        text: root.output.split("\n").slice(0, root.o("lines") || 6).join("\n") || "…"
        wrapMode: Text.Wrap
        font.pixelSize: root.o("size") || 12
        color: root.failed ? Theme.warn : Theme.fg
    }
}
