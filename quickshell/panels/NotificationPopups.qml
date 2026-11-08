pragma ComponentBehavior: Bound

// Notification popups, top right. A ListModel mirrors Notifs.popups (by notification id)
// so the ListView can animate: new cards slide in, dismissed or timed-out cards slide out
// to the right, and the rest glide into place.

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor !== null && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    // stay mapped (at the last size) until the last card has finished sliding out
    property bool alive: false        // set on the first card, cleared only after the last one has slid out
    visible: alive && !Actions.controlCenterOpen && !Lock.locked
    anchors { top: true; right: true }
    margins { top: Theme.bs(30) + 14; right: 10 }
    implicitWidth: 380
    property real heldHeight: 1
    implicitHeight: model.count > 0 ? Math.max(1, list.contentHeight + 4) : heldHeight
    Timer { id: linger; interval: Theme.dur(260) + 60; onTriggered: if (model.count === 0) win.alive = false }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sigil-panel"

    ListModel {
        id: model
        onCountChanged: { if (count > 0) { linger.stop(); win.alive = true; } else linger.restart(); }
    }
    Connections { target: list; function onContentHeightChanged() { if (model.count > 0) win.heldHeight = list.contentHeight + 4; } }

    function sync() {
        const want = Notifs.popups.map(n => n.id);
        for (let i = model.count - 1; i >= 0; i--)
            if (want.indexOf(model.get(i).nid) < 0) model.remove(i);
        want.forEach((id, i) => {
            let j = -1;
            for (let k = 0; k < model.count; k++) if (model.get(k).nid === id) { j = k; break; }
            if (j < 0) model.insert(Math.min(i, model.count), { nid: id });
        });
    }
    Connections { target: Notifs; function onPopupsChanged() { win.sync(); } }
    Component.onCompleted: sync()

    ListView {
        id: list
        // fills the window (whose height is held during the last slide-out); a list sized to
        // its content would collapse to 0 and skip the remove transition
        anchors { fill: parent; leftMargin: 10 }
        spacing: 8
        interactive: false
        model: model

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.dur(200); easing.type: Easing.OutCubic }
                NumberAnimation { property: "x"; from: 48; to: 0; duration: Theme.dur(240); easing.type: Easing.OutCubic }
            }
        }
        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: Theme.dur(170); easing.type: Easing.InCubic }
                NumberAnimation { property: "x"; to: 60; duration: Theme.dur(190); easing.type: Easing.InCubic }
            }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: Theme.dur(220); easing.type: Easing.OutCubic }
        }

        delegate: NotificationCard {
            id: card
            required property int nid
            // keep the object we were created with, so the card still has content while it animates out
            property var held: null
            Component.onCompleted: held = Notifs.popups.find(n => n.id === nid) || null
            notif: held
            popup: true
            width: list.width
            onClosed: if (held) Notifs.dismiss(held)

            HoverHandler { id: hover }
            Timer {
                interval: card.held ? Notifs.timeoutFor(card.held) : 0
                running: interval > 0 && !hover.hovered
                onTriggered: Notifs.dropPopup(card.held)   // stays in history
            }
        }
    }
}
