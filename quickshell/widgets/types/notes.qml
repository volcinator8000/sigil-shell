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

    FileView {
        id: file
        path: Theme.home + "/notes.md"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property var lines: (file.text() || "create ~/notes.md").split("\n").filter(l => l.trim()).slice(0, 8)

    WidgetHeader { width: root.w; title: "notes"; detail: "~/notes.md" }

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
