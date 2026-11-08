// Dashboard tile: label / big value / sub line / optional thin bar.
// state: "" | "alert" | "bad" tints the border.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

Rectangle {
    id: root
    property string label: ""
    property string value: "—"
    property string sub: ""
    property real frac: -1             // < 0 hides the bar
    property string state_: ""
    property bool showBar: true

    Layout.fillWidth: true
    implicitHeight: 92
    implicitWidth: 150
    radius: Theme.radius
    color: Theme.s1
    border.width: 1
    border.color: state_ === "bad" ? Theme.crit : state_ === "alert" ? Theme.warn : Theme.line
    Behavior on border.color { ColorAnimation { duration: Theme.dur(200) } }

    Column {
        anchors { fill: parent; margins: 12; leftMargin: 14; rightMargin: 14 }
        spacing: 3
        Label { text: root.label; color: Theme.dim; font.pixelSize: 10; font.letterSpacing: 1.5 }
        Label {
            width: parent.width
            text: root.value
            color: root.state_ === "bad" ? Theme.crit : root.state_ === "alert" ? Theme.warn : Theme.a1
            font.pixelSize: 22
            elide: Text.ElideRight
        }
        Label { width: parent.width; text: root.sub; color: Theme.dim; font.pixelSize: 10; elide: Text.ElideRight }
    }
    Rectangle {
        visible: root.showBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14; bottomMargin: 10 }
        height: 3
        radius: 1.5
        color: Theme.line
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.frac))
            height: parent.height
            radius: 1.5
            color: root.state_ === "bad" ? Theme.crit : root.state_ === "alert" ? Theme.warn : Theme.a1
            Behavior on width { NumberAnimation { duration: Theme.dur(400); easing.type: Easing.OutCubic } }
        }
    }
}
