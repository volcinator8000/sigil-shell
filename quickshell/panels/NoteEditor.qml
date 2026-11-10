pragma ComponentBehavior: Bound

// Small editor for the notes widget's file (Actions.notePath). Saves as you type
// (0.6 s after the last key) and on close. Esc or a click outside closes it.
//   Ctrl+Enter  toggle the current line's checkbox ("- [ ]" ⇄ "- [x]", adds one if missing)
//   Ctrl+S      save now

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

Overlay {
    id: ed
    shown: Actions.notePath !== ""
    panelWidth: 580
    panelHeight: 540
    onDismissed: close()

    property string path: ""
    property bool dirty: false
    property bool loaded: false
    property string status: ""

    onShownChanged: {
        if (shown) {
            path = Actions.notePath;
            loaded = false;
            dirty = false;
            status = "";
            file.reload();
            area.forceActiveFocus();
        }
    }
    function close() { save(); Actions.notePath = ""; }
    function save() {
        if (!dirty || !path) return;
        file.setText(area.text);
        dirty = false;
        status = "saved " + Qt.formatTime(new Date(), "HH:mm:ss");
    }

    FileView {
        id: file
        path: ed.path
        printErrors: false
        atomicWrites: true
        onLoaded: if (!ed.dirty) { area.text = text(); ed.loaded = true; area.cursorPosition = area.length; }
        onLoadFailed: if (!ed.dirty) { area.text = ""; ed.loaded = true; ed.status = "new file"; }
    }
    Timer { id: autosave; interval: 600; onTriggered: ed.save() }

    function toggleCheck() {
        const t = area.text, pos = area.cursorPosition;
        const a = t.lastIndexOf("\n", pos - 1) + 1;
        let b = t.indexOf("\n", pos); if (b < 0) b = t.length;
        const line = t.slice(a, b);
        let out;
        if (/^(\s*[-*] )\[ \]/.test(line)) out = line.replace(/^(\s*[-*] )\[ \]/, "$1[x]");
        else if (/^(\s*[-*] )\[[xX]\]/.test(line)) out = line.replace(/^(\s*[-*] )\[[xX]\]/, "$1[ ]");
        else if (/^(\s*)[-*] /.test(line)) out = line.replace(/^(\s*[-*] )/, "$1[ ] ");
        else out = "- [ ] " + line;
        area.remove(a, b);
        area.insert(a, out);
        area.cursorPosition = Math.min(a + out.length, pos + (out.length - line.length));
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius * 1.4
        color: Theme.surface
        border.width: 1
        border.color: Theme.line

        Item {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            height: 30
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Label { text: ed.path.split("/").pop(); font.bold: true; font.pixelSize: 14 }
                Label { text: ed.path.replace(Theme.home, "~"); color: Theme.dim; font.pixelSize: 10 }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ed.dirty ? "editing…" : ed.status
                    color: Theme.dim
                    font.pixelSize: 10
                }
                ChipButton { text: "☑ ctrl+enter"; small: true; onClicked: { ed.toggleCheck(); area.forceActiveFocus(); } }
                ChipButton { text: "done"; small: true; accent: true; onClicked: ed.close() }
            }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; margins: 16; topMargin: 12 }
            radius: Theme.radius
            color: Theme.alpha(Theme.fg, 0.035)
            border.width: 1
            border.color: area.activeFocus ? Theme.alpha(Theme.a1, 0.5) : Theme.alpha(Theme.fg, 0.07)

            Flickable {
                id: flick
                anchors { fill: parent; margins: 12 }
                clip: true
                contentWidth: width
                contentHeight: area.contentHeight
                boundsBehavior: Flickable.StopAtBounds
                function ensureVisible(r) {
                    if (contentY >= r.y) contentY = r.y;
                    else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height;
                }

                TextEdit {
                    id: area
                    width: flick.width
                    height: Math.max(flick.height, contentHeight)
                    wrapMode: TextEdit.Wrap
                    color: Theme.fg
                    selectionColor: Theme.alpha(Theme.a1, 0.35)
                    selectedTextColor: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 13
                    selectByMouse: true
                    persistentSelection: true
                    focus: true
                    onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
                    onTextChanged: if (ed.loaded) { ed.dirty = true; autosave.restart(); }
                    Keys.onPressed: (e) => {
                        if ((e.modifiers & Qt.ControlModifier) && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { ed.toggleCheck(); e.accepted = true; }
                        else if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_S) { ed.save(); e.accepted = true; }
                    }
                    Keys.onEscapePressed: ed.close()

                    Label {
                        visible: area.length === 0 && ed.loaded
                        text: "write here · \"- [ ] task\" lines become checkboxes"
                        color: Theme.dim
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
