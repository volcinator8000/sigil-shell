// Single-line text input in the shell's look. `accepted()` on Enter,
// `edited(text)` on user typing only.

import QtQuick
import qs.services
import qs.components

Rectangle {
    id: root
    property alias text: input.text
    property string placeholder: ""
    property bool password: false
    property bool error: false
    property alias input: input
    signal accepted()
    signal edited(string text)

    implicitWidth: 220
    implicitHeight: 28
    radius: Math.min(Theme.radius * 0.7, height / 2)
    color: Theme.bg
    border.width: 1
    border.color: error ? Theme.crit : input.activeFocus ? Theme.a1 : mouse.containsMouse ? Theme.a2 : Theme.line
    opacity: enabled ? 1 : 0.45
    Behavior on border.color { ColorAnimation { duration: Theme.dur(120) } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }
    TextInput {
        id: input
        anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.fg
        selectionColor: Theme.alpha(Theme.a1, 0.4)
        selectedTextColor: Theme.fg
        font.family: Theme.font
        font.pixelSize: 12
        clip: true
        selectByMouse: true
        echoMode: root.password ? TextInput.Password : TextInput.Normal
        onAccepted: root.accepted()
        onTextEdited: root.edited(text)
    }
    Label {
        anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
        visible: input.text === "" && !input.activeFocus
        text: root.placeholder
        color: Theme.alpha(Theme.dim, 0.8)
    }
}
