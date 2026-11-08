pragma ComponentBehavior: Bound

// Full-screen overlay on the focused monitor: dimmed (and, via the Hyprland layer
// rule, blurred) backdrop, keyboard grab while shown, Esc / backdrop click → dismissed().
// Children go into `content` and fade/scale in with the backdrop.

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

PanelWindow {
    id: root

    property bool shown: false
    property real dim: 0.45
    property string ns: "sigil-panel"
    property bool grabKeyboard: true
    signal dismissed()
    default property alias content: holder.data

    // Corner mode: opened from a hot corner. Stays open while the pointer is in the
    // corner zone or over the panel (panels report that via panelHovered), closes
    // 300 ms after it leaves both.
    // requestedCorner is latched into `corner` when the overlay opens and kept until it has
    // fully faded out, so a closing panel never jumps back to the centre for a frame.
    property string requestedCorner: ""
    property string corner: ""
    property bool panelHovered: false
    readonly property bool cornerMode: corner !== ""
    readonly property bool atTop: corner.startsWith("top")
    readonly property bool atLeft: corner.endsWith("Left")
    readonly property bool pointerInside: panelHovered || cornerZone.containsMouse
    property bool leaveArmed: false
    onPointerInsideChanged: {
        if (!cornerMode || !shown) return;
        if (pointerInside) { leaveTimer.stop(); leaveArmed = true; }
        else if (leaveArmed) leaveTimer.restart();
    }
    onShownChanged: { leaveArmed = false; leaveTimer.stop(); if (shown) corner = requestedCorner; }
    onVisibleChanged: if (!visible) corner = ""
    Timer { id: leaveTimer; interval: 300; onTriggered: if (root.shown && root.cornerMode && !root.pointerInside) root.dismissed() }
    // If the pointer never reports being inside (no motion yet), give up after a while
    Timer { interval: 2500; running: root.shown && root.cornerMode && !root.leaveArmed; onTriggered: if (!root.pointerInside) root.dismissed() }
    readonly property Item contentItem: holder

    // 0 = closed, 1 = open. Animated both ways; the surface stays mapped until it reaches 0,
    // so closing plays out fully. Opening eases out, closing is quicker and eases in.
    property real openness: shown ? 1 : 0
    Behavior on openness {
        NumberAnimation {
            duration: root.shown ? Theme.dur(210) : Theme.dur(150)
            easing.type: root.shown ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: shown || openness > 0.001
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor !== null && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: ns
    WlrLayershell.keyboardFocus: (shown && grabKeyboard) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.alpha(Theme.bg, root.dim)
        opacity: root.openness
        MouseArea { anchors.fill: parent; onClicked: root.dismissed() }
    }

    MouseArea {
        id: cornerZone
        visible: root.cornerMode
        width: 90
        height: 90
        x: root.atLeft ? 0 : parent.width - width
        y: root.atTop ? 0 : parent.height - height
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    Item {
        id: holder
        anchors.fill: parent
        opacity: root.openness
        scale: (root.cornerMode ? 0.9 : 0.96) + (root.cornerMode ? 0.1 : 0.04) * root.openness
        // grow out of the corner that opened it, or from the centre
        transformOrigin: !root.cornerMode ? Item.Center
                       : root.atTop ? (root.atLeft ? Item.TopLeft : Item.TopRight)
                       : (root.atLeft ? Item.BottomLeft : Item.BottomRight)
        focus: true
        Keys.onEscapePressed: root.dismissed()
    }
}
