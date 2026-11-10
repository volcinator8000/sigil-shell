pragma ComponentBehavior: Bound

// Titled group of rows: uppercase accent heading, optional description and
// header actions, then a rounded card that stacks its children.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

ColumnLayout {
    id: root
    property string title: ""
    property string description: ""
    default property alias rows: body.data
    property alias actions: actionRow.data
    property bool card: true
    readonly property string searchKind: "section"  // found by the settings search
    function flash() { flashAnim.restart(); }

    Layout.fillWidth: true
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        visible: root.title !== "" || actionRow.children.length > 0
        Label {
            id: heading
            Layout.fillWidth: true
            text: root.title.toUpperCase()
            color: Theme.a1
            font.pixelSize: 10
            font.letterSpacing: 1.4
        }
        RowLayout { id: actionRow; spacing: 6 }
    }
    Label {
        Layout.fillWidth: true
        visible: root.description !== ""
        text: root.description
        color: Theme.dim
        font.pixelSize: 11
        wrapMode: Text.Wrap
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        implicitHeight: body.implicitHeight
        visible: body.children.length > 0
        radius: Theme.radius
        color: root.card ? Theme.s1 : "transparent"
        border.width: root.card ? 1 : 0
        border.color: Theme.line
        ColumnLayout {
            id: body
            width: parent.width
            spacing: 0
        }
    }
    SequentialAnimation {
        id: flashAnim
        ColorAnimation { target: heading; property: "color"; to: Theme.fg; duration: Theme.dur(160) }
        PauseAnimation { duration: 700 }
        ColorAnimation { target: heading; property: "color"; to: Theme.a1; duration: Theme.dur(500) }
    }
}
