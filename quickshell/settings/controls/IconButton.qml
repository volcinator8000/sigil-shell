import QtQuick
import qs.services
import qs.components
import qs.settings.lib

// Flat glyph button with a hover plate and a small tooltip-ish hint.
Rectangle {
    id: root
    property string glyph: ""
    property string hint: ""
    property color tint: Theme.fg
    signal clicked()

    implicitWidth: 26
    implicitHeight: 26
    radius: Math.min(Theme.radius * 0.7, height / 2)
    color: mouse.containsMouse ? Theme.s2 : "transparent"
    border.width: mouse.containsMouse ? 1 : 0
    border.color: Theme.line
    opacity: enabled ? 1 : 0.4

    Label {
        anchors.centerIn: parent
        text: root.glyph
        color: mouse.containsMouse ? Theme.a1 : root.tint
        font.pixelSize: 14
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { Sh.snd("click"); root.clicked(); }
    }
    Rectangle {
        visible: mouse.containsMouse && root.hint !== ""
        z: 10
        anchors { bottom: parent.top; bottomMargin: 4; right: parent.right }
        width: hintLabel.implicitWidth + 12
        height: 20
        radius: 4
        color: Theme.s2
        border.width: 1
        border.color: Theme.line
        Label { id: hintLabel; anchors.centerIn: parent; text: root.hint; font.pixelSize: 10 }
    }
}
