pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.services

Row {
    id: root
    property string monitorName: ""
    spacing: Theme.bs(5)

    readonly property int count: {
        let m = 5;
        for (const w of Hyprland.workspaces.values) if (w.id > m) m = w.id;
        return m;
    }

    Repeater {
        model: root.count

        delegate: Item {
            id: dot
            required property int index
            readonly property int wsId: index + 1
            readonly property var ws: Hyprland.workspaces.values.find(w => w.id === wsId) || null
            readonly property bool active: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === wsId
            readonly property bool occupied: ws !== null && ws.toplevels.values.length > 0
            readonly property bool urgent: ws !== null && ws.urgent

            implicitWidth: pill.width
            implicitHeight: Theme.bs(14)
            anchors.verticalCenter: parent.verticalCenter

            // soft glow behind the active pill (AC only)
            Rectangle {
                anchors.centerIn: pill
                width: pill.width + 8
                height: pill.height + 8
                radius: height / 2
                color: Theme.alpha(Theme.a1, 0.22)
                visible: dot.active && Theme.rich
            }

            Rectangle {
                id: pill
                anchors.verticalCenter: parent.verticalCenter
                width: dot.active ? Theme.bs(22) : Theme.bs(7)
                height: Theme.bs(7)
                radius: Math.min(Theme.radius * 0.4, height / 2)
                color: dot.urgent ? Theme.crit : dot.active ? Theme.a1 : dot.occupied ? Theme.dim : Theme.line
                Behavior on width { NumberAnimation { duration: Theme.dur(260); easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: Theme.dur(200) } }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -3
                cursorShape: Qt.PointingHandCursor
                onClicked: dot.ws ? dot.ws.activate() : Hyprland.dispatch("workspace " + dot.wsId)
            }
        }
    }
}
