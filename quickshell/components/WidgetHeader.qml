import QtQuick
import qs.services

Item {
    id: root
    property string title: ""
    property string detail: ""
    implicitHeight: 14
    implicitWidth: 120

    Label {
        anchors.left: parent.left
        text: root.title.toUpperCase()
        color: Theme.dim
        font.pixelSize: 10
        font.letterSpacing: 1.4
    }
    Label {
        anchors.right: parent.right
        text: root.detail.toUpperCase()
        color: Theme.a2
        font.pixelSize: 10
        font.letterSpacing: 1.4
    }
}
