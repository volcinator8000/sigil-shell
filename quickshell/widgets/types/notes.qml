pragma ComponentBehavior: Bound

// Shows the first lines of ~/notes.md. "- [x]" items render struck through.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

Column {
    id: root
    spacing: 6
    readonly property int w: 196
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }

    FileView {
        id: file
        path: String(root.o("path") || "~/notes.md").replace(/^~/, Theme.home)
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property var lines: (file.text() || "create ~/notes.md").split("\n").filter(l => l.trim()).slice(0, root.o("lines") || 8)

    WidgetHeader { width: root.w; title: "notes"; detail: String(root.o("path") || "").split("/").pop() }

    Repeater {
        model: root.lines
        delegate: Label {
            required property string modelData
            readonly property bool done: /^\s*[-*] \[x\]/i.test(modelData)
            width: root.w
            elide: Text.ElideRight
            text: modelData.replace(/^\s*[-*] \[[ x]\]\s*/i, "").replace(/^\s*[-*]\s*/, "· ").replace(/^#+\s*/, "")
            color: done ? Theme.dim : Theme.fg
            font.strikeout: done
            font.pixelSize: 11
        }
    }
}
