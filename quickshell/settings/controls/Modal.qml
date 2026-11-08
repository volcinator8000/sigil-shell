pragma ComponentBehavior: Bound

// In-window dialog: dims its parent and centres a card. Put content in the
// default slot; `buttons` go bottom-right. close() / open().

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

Item {
    id: root
    property string title: ""
    property string body: ""
    property int cardWidth: 420
    property int cardHeight: 0         // 0 = fit content
    property bool shown: false
    default property alias content: slot.data
    property alias buttons: buttonRow.data
    signal dismissed()

    function open() { shown = true; }
    function close() { shown = false; }

    anchors.fill: parent
    z: 100
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.dur(140) } }

    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.bg, 0.72)
        MouseArea {
            anchors.fill: parent
            onClicked: { root.close(); root.dismissed(); }
            onWheel: e => e.accepted = true
        }
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.cardWidth, root.width - 40)
        height: root.cardHeight > 0 ? Math.min(root.cardHeight, root.height - 40) : col.implicitHeight + 32
        radius: Theme.radius
        color: Theme.s1
        border.width: 1
        border.color: Theme.a2
        scale: root.shown ? 1 : 0.97
        Behavior on scale { NumberAnimation { duration: Theme.dur(180); easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }       // swallow clicks

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 16 }
            spacing: 10
            Label {
                Layout.fillWidth: true
                visible: root.title !== ""
                text: root.title
                font.pixelSize: 14
                font.bold: true
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                visible: root.body !== ""
                text: root.body
                color: Theme.dim
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
            ColumnLayout {
                id: slot
                Layout.fillWidth: true
                Layout.fillHeight: root.cardHeight > 0
                spacing: 8
            }
            RowLayout {
                id: buttonRow
                Layout.alignment: Qt.AlignRight
                spacing: 8
            }
        }
    }
}
