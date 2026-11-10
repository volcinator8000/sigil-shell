pragma ComponentBehavior: Bound

// Shows the first lines of ~/notes.md. "- [x]" items render struck through.
// Resizable: wider = longer lines, taller = more lines. Click it to edit the file.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

Column {
    id: root
    spacing: 6
    readonly property int w: Math.max(196, entry.w || 0)
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }
    readonly property string path: String(o("path") || "~/notes.md").replace(/^~/, Theme.home)

    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    // a set height decides how many lines fit (header 14 + 6, then 15 + 6 per line)
    readonly property int maxLines: entry.h ? Math.max(1, Math.floor((entry.h - 20 + 6) / 21)) : (o("lines") || 8)
    readonly property var lines: (file.text() || "empty · click to write").split("\n").filter(l => l.trim()).slice(0, maxLines)

    WidgetHeader { width: root.w; title: "notes"; detail: String(root.o("path") || "").split("/").pop() }

    Repeater {
        model: root.lines
        delegate: WLabel {
            required property string modelData
            readonly property bool done: /^\s*[-*] \[x\]/i.test(modelData)
            width: root.w
            height: 15
            elide: Text.ElideRight
            text: modelData.replace(/^\s*[-*] \[[ x]\]\s*/i, "").replace(/^\s*[-*]\s*/, "· ").replace(/^#+\s*/, "")
            color: done ? Theme.dim : Theme.fg
            font.strikeout: done
            font.pixelSize: 11
        }
    }

    // click → editor (not while arranging widgets)
    TapHandler {
        enabled: !Widgets.editing
        onTapped: Actions.openNote(root.path)
    }
    HoverHandler { enabled: !Widgets.editing; cursorShape: Qt.PointingHandCursor }
}
