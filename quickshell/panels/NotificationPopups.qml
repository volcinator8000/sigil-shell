pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor !== null && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    visible: Notifs.popups.length > 0 && !Actions.controlCenterOpen && !Lock.locked
    anchors { top: true; right: true }
    margins { top: 44; right: 10 }
    implicitWidth: 370
    implicitHeight: Math.max(1, col.implicitHeight)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sigil-panel"

    Column {
        id: col
        width: parent.width
        spacing: 8

        Repeater {
            model: Notifs.popups
            delegate: NotificationCard {
                id: card
                required property var modelData
                notif: modelData
                popup: true
                width: col.width
                onClosed: Notifs.dismiss(modelData)

                // slide in from the right
                x: 0
                NumberAnimation on x { from: 40; to: 0; duration: Theme.dur(220); easing.type: Easing.OutCubic }
                NumberAnimation on opacity { from: 0; to: 1; duration: Theme.dur(180) }

                HoverHandler { id: hover }
                Timer {
                    interval: Notifs.timeoutFor(card.modelData)
                    running: interval > 0 && !hover.hovered
                    onTriggered: Notifs.dropPopup(card.modelData)   // stays in history
                }
            }
        }
    }
}
