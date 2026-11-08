import QtQuick
import qs.services
import qs.components

// Square check box with optional label. Emits toggled(checked) on clicks only.
Item {
    id: root
    property bool checked: false
    property string text: ""
    signal toggled(bool checked)

    implicitWidth: row.implicitWidth
    implicitHeight: 18

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Rectangle {
            width: 16
            height: 16
            radius: Math.min(4, Theme.radius / 2)
            color: root.checked ? Theme.a1 : Theme.s2
            border.width: 1
            border.color: root.checked ? Theme.a1 : mouse.containsMouse ? Theme.a2 : Theme.line
            Label {
                anchors.centerIn: parent
                visible: root.checked
                text: "\u{F012C}"
                color: Theme.bg
                font.pixelSize: 12
            }
        }
        Label {
            visible: root.text !== ""
            text: root.text
            height: 16
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.checked = !root.checked; root.toggled(root.checked); }
    }
}
