import QtQuick
import qs.services

// Widgets go without titles: the header takes no space. Its `detail` (city, week, time
// span, file name, error…) is shown by WidgetFrame in the widget's bottom-right corner.
Item {
    id: root
    visible: false
    readonly property bool isWidgetHeader: true
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
