pragma ComponentBehavior: Bound

// One row inside a Section: optional glyph, title + subtitle on the left,
// controls (children) on the right. Draws its own divider unless it is first.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

Item {
    id: row
    property string title: ""
    property string subtitle: ""
    property string glyph: ""
    property color titleColor: Theme.fg
    property color glyphColor: Theme.dim
    property bool divider: y > 0
    default property alias suffix: suffixRow.data

    Layout.fillWidth: true
    implicitWidth: 400
    implicitHeight: Math.max(46, texts.implicitHeight + 20, suffixRow.implicitHeight + 16)
    opacity: enabled ? 1 : 0.45

    Rectangle {
        visible: row.divider
        anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12 }
        height: 1
        color: Theme.line
    }
    Label {
        id: glyphLabel
        visible: row.glyph !== ""
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        width: visible ? 18 : 0
        text: row.glyph
        color: row.glyphColor
        font.pixelSize: 15
    }
    Column {
        id: texts
        anchors {
            left: glyphLabel.visible ? glyphLabel.right : parent.left
            leftMargin: glyphLabel.visible ? 10 : 14
            right: suffixRow.left
            rightMargin: 12
            verticalCenter: parent.verticalCenter
        }
        spacing: 2
        Label {
            width: parent.width
            visible: text !== ""
            text: row.title
            color: row.titleColor
            elide: Text.ElideRight
        }
        Label {
            width: parent.width
            visible: text !== ""
            text: row.subtitle
            color: Theme.dim
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
    RowLayout {
        id: suffixRow
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 6
    }
}
