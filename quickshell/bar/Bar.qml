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
    // flush with the screen top; corners and the hairline under it come from Frame
    readonly property int barH: Theme.barH
    implicitHeight: barH
    exclusiveZone: barH
    mask: Region { item: frame }
    color: "transparent"
    WlrLayershell.namespace: "sigil-bar"
    WlrLayershell.layer: WlrLayer.Top

    property color fill: Theme.surface
    Behavior on fill { ColorAnimation { duration: Theme.dur(300) } }

    Rectangle { anchors.fill: parent; color: bar.fill }

    Item {
        id: frame
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: bar.barH
        // where the pointer is on the bar (a corner-opened sheet stays open while it is over the sheet's span)
        HoverHandler {
            onHoveredChanged: if (!hovered) Actions.barHoverX = -1
            onPointChanged: if (hovered) Actions.barHoverX = point.position.x
        }

        RowLayout {
            anchors { fill: parent; leftMargin: Theme.bs(10); rightMargin: Theme.bs(12) }
            spacing: Theme.bs(14)

            Workspaces { monitorName: bar.screen ? bar.screen.name : "" }

            Label {
                id: title
                // window title gives way to the lyrics when something is playing
                Layout.fillWidth: !lyrics.visible
                Layout.maximumWidth: lyrics.visible ? 260 : -1
                elide: Text.ElideRight
                color: Theme.dim
                font.pixelSize: Theme.bs(12)
                // Some apps animate their title (terminal spinners, page loads): ~10 changes a
                // second, each one a bar redraw. Show the newest title at most every 350 ms.
                readonly property string live: Hyprland.activeToplevel ? (Hyprland.activeToplevel.title || "") : ""
                text: live
                onLiveChanged: {
                    if (titleGate.running) return;
                    text = live;
                    titleGate.start();
                }
                Timer { id: titleGate; interval: 350; onTriggered: title.text = title.live }
            }

            Lyrics {
                id: lyrics
                maxWidth: frame.width * 0.45
                Layout.preferredWidth: implicitWidth
            }

            Item { Layout.fillWidth: true; visible: lyrics.visible }

            TrayItems { window: bar }

            UpdatesButton { window: bar }

            // ultra power saver is on: click to leave it
            Label {
                visible: Theme.ultra
                text: String.fromCodePoint(0xF032A) + " ULTRA"
                color: Theme.warn
                font.bold: true
                font.letterSpacing: 1
                font.pixelSize: Theme.bs(11)
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([Theme.home + "/.local/bin/ultra", "off"])
                }
            }

            StatusIcons {}

            Label {
                // notifications: count, or a slashed bell in do-not-disturb
                font.pixelSize: Theme.bs(14)
                color: Notifs.dnd ? Theme.dim : Notifs.count > 0 ? Theme.a1 : Theme.fg
                text: String.fromCodePoint(Notifs.dnd ? 0xF009B : Notifs.count > 0 ? 0xF116B : 0xF009A) + (Notifs.count > 0 && !Notifs.dnd ? " " + Notifs.count : "")
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => m.button === Qt.RightButton ? (Notifs.dnd = !Notifs.dnd) : Actions.run("controlcenter")
                }
            }

            Rectangle { implicitWidth: 1; implicitHeight: Theme.bs(14); color: Theme.line }

            Label {
                id: clock
                font.bold: true
                font.pixelSize: Theme.bs(12)
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
