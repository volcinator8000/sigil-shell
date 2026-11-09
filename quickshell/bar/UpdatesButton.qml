pragma ComponentBehavior: Bound

// Pending updates in the bar (hidden when up to date).
// Hover: list of packages · click: open the upgrade window · right click: check again.

import QtQuick
import Quickshell
import qs.services
import qs.components

Item {
    id: root
    property var window
    visible: Updates.count > 0 || Updates.upgrading
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Label {
        id: label
        font.pixelSize: Theme.bs(13)
        color: Updates.upgrading ? Theme.a1 : Updates.count >= 20 ? Theme.warn : Theme.a2
        text: String.fromCodePoint(Updates.upgrading ? 0xF06B0 : 0xF03D4) + " " + (Updates.upgrading ? "…" : Updates.count)
        opacity: Updates.checking ? 0.55 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.dur(200) } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (m) => {
            Actions.sound("click");
            if (m.button === Qt.RightButton) Updates.check(); else Updates.upgrade();
        }
    }

    PopupWindow {
        id: tip
        anchor.window: root.window
        anchor.rect.x: root.mapToItem(null, 0, 0).x + root.width - width
        anchor.rect.y: (root.window ? root.window.height : 30) + 4
        visible: mouse.containsMouse && !Updates.upgrading
        color: "transparent"
        implicitWidth: 380
        implicitHeight: box.height

        Rectangle {
            id: box
            width: parent.width
            height: col.implicitHeight + 24
            radius: Theme.radius
            color: Theme.rich ? Theme.alpha(Theme.s1, 0.96) : Theme.s1
            border.width: 1
            border.color: Theme.line

            Column {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 4
                Label {
                    text: Updates.count + " UPDATE" + (Updates.count === 1 ? "" : "S") + "   ·   repo " + Updates.repo + "  ·  aur " + Updates.aur
                    color: Theme.dim; font.pixelSize: 10; font.letterSpacing: 1.2
                }
                Item { width: 1; height: 4 }
                Repeater {
                    model: Updates.packages.slice(0, 18)
                    delegate: Row {
                        required property var modelData
                        width: col.width
                        Label { width: parent.width * 0.42; elide: Text.ElideRight; text: parent.modelData.name; font.pixelSize: 11 }
                        Label { width: parent.width * 0.29; elide: Text.ElideLeft; text: parent.modelData.from; color: Theme.dim; font.pixelSize: 10; horizontalAlignment: Text.AlignRight }
                        Label { width: parent.width * 0.29; elide: Text.ElideRight; text: "  → " + parent.modelData.to; color: Theme.a1; font.pixelSize: 10 }
                    }
                }
                Label { visible: Updates.packages.length > 18; text: "… and " + (Updates.packages.length - 18) + " more"; color: Theme.dim; font.pixelSize: 10 }
                Item { width: 1; height: 4 }
                Label { text: "click: upgrade   ·   right click: check again"; color: Theme.dim; font.pixelSize: 9 }
            }
        }
    }
}
