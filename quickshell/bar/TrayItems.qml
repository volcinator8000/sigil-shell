pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.services

Row {
    id: root
    required property var window
    spacing: Theme.bs(8)

    Repeater {
        model: SystemTray.items

        delegate: MouseArea {
            id: item
            required property SystemTrayItem modelData
            implicitWidth: Theme.bs(15)
            implicitHeight: Theme.bs(15)
            anchors.verticalCenter: parent.verticalCenter
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor

            IconImage {
                anchors.fill: parent
                source: item.modelData.icon
                asynchronous: true
            }

            onClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton && !item.modelData.onlyMenu) item.modelData.activate();
                else if (mouse.button === Qt.MiddleButton) item.modelData.secondaryActivate();
                else if (item.modelData.hasMenu) menu.open();
            }

            QsMenuAnchor {
                id: menu
                menu: item.modelData.menu
                anchor.item: item
                anchor.edges: Edges.Bottom
                anchor.gravity: Edges.Bottom
            }
        }
    }
}
