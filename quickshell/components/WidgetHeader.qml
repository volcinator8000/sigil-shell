import QtQuick
import qs.services

// Widgets go without titles now: the header takes no space (kept so types and
// scaffolds that place one still load).
Item {
    id: root
    visible: false
    property string title: ""
    property string detail: ""
    implicitHeight: 0
    implicitWidth: 120

    WLabel {
        anchors.left: parent.left
        text: root.title.toUpperCase()
        color: Theme.widgetDim
        font.pixelSize: 10
        font.letterSpacing: 1.4
    }
    WLabel {
        anchors.right: parent.right
        text: root.detail.toUpperCase()
        color: Theme.a2
        font.pixelSize: 10
        font.letterSpacing: 1.4
    }
}
