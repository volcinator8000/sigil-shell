pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

PanelWindow {
    id: bar

    anchors { top: true; left: true; right: true }
    implicitHeight: 36
    color: "transparent"
    WlrLayershell.namespace: "sigil-bar"
    WlrLayershell.layer: WlrLayer.Top

    Rectangle {
        id: frame
        anchors { fill: parent; topMargin: 6; leftMargin: 6; rightMargin: 6 }
        radius: Theme.radius
        color: Theme.rich ? Theme.alpha(Theme.s1, 0.78) : Theme.s1
        border.width: 1
        border.color: Theme.line
        Behavior on color { ColorAnimation { duration: Theme.dur(300) } }

        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 12 }
            spacing: 14

            Label {
                text: "◆"
                color: Theme.a1
                font.bold: true
                font.pixelSize: 13
            }

            Workspaces { monitorName: bar.screen ? bar.screen.name : "" }

            Label {
                // window title gives way to the lyrics when something is playing
                Layout.fillWidth: !lyrics.visible
                Layout.maximumWidth: lyrics.visible ? 260 : -1
                elide: Text.ElideRight
                color: Theme.dim
                text: Hyprland.activeToplevel ? (Hyprland.activeToplevel.title || "") : ""
            }

            Lyrics {
                id: lyrics
                maxWidth: frame.width * 0.45
                Layout.preferredWidth: implicitWidth
            }

            Item { Layout.fillWidth: true; visible: lyrics.visible }

            TrayItems { window: bar }

            StatusIcons {}

            Label {
                // notifications: count, or a slashed bell in do-not-disturb
                font.pixelSize: 14
                color: Notifs.dnd ? Theme.dim : Notifs.count > 0 ? Theme.a1 : Theme.fg
                text: String.fromCodePoint(Notifs.dnd ? 0xF009B : Notifs.count > 0 ? 0xF116B : 0xF009A) + (Notifs.count > 0 && !Notifs.dnd ? " " + Notifs.count : "")
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => m.button === Qt.RightButton ? (Notifs.dnd = !Notifs.dnd) : Actions.run("controlcenter")
                }
            }

            Rectangle { implicitWidth: 1; implicitHeight: 14; color: Theme.line }

            Label {
                id: clock
                font.bold: true
                text: Qt.formatDateTime(sysClock.date, "HH:mm")
                SystemClock { id: sysClock; precision: SystemClock.Minutes }
                MouseArea {
                    anchors.fill: parent
                    onClicked: Widgets.togglePeek()
                }
            }
        }
    }
}
