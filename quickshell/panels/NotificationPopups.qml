pragma ComponentBehavior: Bound

// Notification popups, top right, one card per app group. A ListModel mirrors
// Notifs.popupGroups (by group key) so the ListView can animate: new groups slide in,
// dismissed or timed-out ones slide out to the right, a group that gets a new message
// moves to the top, and the rest glide into place.

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
    margins { top: Theme.barH + Theme.gap; right: Theme.frame + Theme.gap }
    implicitWidth: 380
    property real heldHeight: 1
    implicitHeight: model.count > 0 ? Math.max(1, list.contentHeight + 4) : heldHeight
    Timer { id: linger; interval: Theme.dur(260) + 60; onTriggered: if (model.count === 0) win.alive = false }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sigil-panel"
    // keyboard only while typing an inline reply
    property int replying: 0
    WlrLayershell.keyboardFocus: replying > 0 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    ListModel {
        id: model
        onCountChanged: { if (count > 0) { linger.stop(); win.alive = true; } else linger.restart(); }
    }
    Connections { target: list; function onContentHeightChanged() { if (model.count > 0) win.heldHeight = list.contentHeight + 4; } }

    function sync() {
        const want = Notifs.popupGroups.map(g => g.key);
        for (let i = model.count - 1; i >= 0; i--)
            if (want.indexOf(model.get(i).gkey) < 0) model.remove(i);
        want.forEach((key, i) => {
            let j = -1;
            for (let k = 0; k < model.count; k++) if (model.get(k).gkey === key) { j = k; break; }
            if (j < 0) model.insert(Math.min(i, model.count), { gkey: key });
            else if (j !== i && i < model.count) model.move(j, i, 1);
        });
    }
    Connections { target: Notifs; function onPopupGroupsChanged() { win.sync(); } }
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

        delegate: NotificationGroup {
            id: card
            required property string gkey
            // keep the last items we had, so the card still has content while it animates out
            readonly property var live: (Notifs.popupGroups.find(g => g.key === gkey) || { items: [] }).items
            // bound at creation so the card has its real height before the list lays it out
            property var held: live
            onLiveChanged: if (live.length) held = live
            items: held
            popup: true
            width: list.width
            onDismissGroup: Notifs.dismissAll(held)
            onDismissOne: (n) => Notifs.dismiss(n)
            property bool typing: false
            onReplyFocus: (on) => { if (on !== typing) { typing = on; win.replying += on ? 1 : -1; } }
            Component.onDestruction: if (typing) win.replying--

            // a new message in the group restarts the countdown
            readonly property var head: held[0] || null
            onHeadChanged: if (timer.running) timer.restart()
            HoverHandler { id: hover }
            Timer {
                id: timer
                interval: card.head ? Notifs.timeoutFor(card.head) : 0
                running: interval > 0 && !hover.hovered && !card.expanded && !card.typing
                onTriggered: Notifs.dropPopups(card.held)   // stays in history
            }
        }
    }
}
