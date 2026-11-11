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
    // Long lines wrap. Without a set height: the first `lines` lines. With one (bottom edge
    // handle): as many whole lines as fit, then "+N" in the header.
    readonly property var all: (file.text() || "empty · click to write").split("\n").filter(l => l.trim())
    readonly property var lines: entry.h ? all.slice(0, 200) : all.slice(0, o("lines") || 8)
    readonly property real boxH: entry.h ? Math.max(15, entry.h - 20) : list.implicitHeight

    WidgetHeader {
        width: root.w; title: "notes"
        detail: String(root.o("path") || "").split("/").pop() + (root.hidden > 0 ? " · +" + root.hidden : "")
    }

    property int hidden: 0
    Item {
        width: root.w
        height: root.boxH
        clip: true
        Column {
            id: list
            width: parent.width
            spacing: 4
            Repeater {
                id: rep
                model: root.lines
                delegate: WLabel {
                    required property string modelData
                    readonly property bool done: /^\s*[-*] \[x\]/i.test(modelData)
                    width: root.w
                    wrapMode: Text.Wrap
                    verticalAlignment: Text.AlignTop
                    text: modelData.replace(/^\s*[-*] \[[ x]\]\s*/i, "").replace(/^\s*[-*]\s*/, "· ").replace(/^#+\s*/, "")
                    color: done ? Theme.widgetDim : Theme.fg
                    font.strikeout: done
                    font.pixelSize: 12
                    // only whole lines: one that would be cut at the bottom is hidden
                    opacity: y + height <= root.boxH + 0.5 ? 1 : 0
                }
            }
        }
        Timer {
            id: recount
            interval: 0
            onTriggered: {
                let n = root.all.length - root.lines.length;
                for (let k = 0; k < rep.count; k++) { const it = rep.itemAt(k); if (it && it.opacity === 0) n++; }
                root.hidden = Math.max(0, n);
            }
        }
        Connections {
            target: root
            function onBoxHChanged() { recount.restart(); }
            function onLinesChanged() { recount.restart(); }
            function onWChanged() { recount.restart(); }
        }
        Component.onCompleted: recount.restart()
    }

    // click → editor (not while arranging widgets)
    TapHandler {
        enabled: !Widgets.editing
        onTapped: Actions.openNote(root.path)
    }
    HoverHandler { enabled: !Widgets.editing; cursorShape: Qt.PointingHandCursor }
}
