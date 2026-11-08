import QtQuick
import qs.services

Rectangle {
    id: root
    property string text: ""
    property bool accent: false
    property bool danger: false
    property bool small: false
    signal clicked()

    implicitWidth: label.implicitWidth + (small ? 12 : 18)
    implicitHeight: small ? 18 : 24
    radius: Math.min(Theme.radius * 0.7, height / 2)
    color: accent ? Theme.a1 : mouse.containsMouse ? Theme.s2 : Theme.alpha(Theme.s2, small ? 1 : 0)
    border.width: 1
    border.color: accent ? Theme.a1 : mouse.containsMouse ? Theme.a2 : Theme.line
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

    Label {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: root.small ? 9.5 : 11
        font.bold: root.small || root.accent
        color: root.accent ? Theme.bg : root.danger ? Theme.crit : Theme.fg
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
