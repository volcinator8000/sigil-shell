pragma ComponentBehavior: Bound

// Popup panel window, sized to the panel itself (not full screen), so the compositor
// only redraws and blurs that area while it animates.
//  • placement: centred ("center"), near the top ("top", topFraction of the screen),
//    or a full-height side panel (fullHeight). Opened from a hot corner, it sits at
//    that corner instead.
//  • closes on Esc, on a click anywhere else (Hyprland focus grab), and in corner mode
//    when the pointer leaves: 300 ms after leaving the panel, or 450 ms after leaving
//    the corner without reaching it.
//  • `openness` (0..1) animates both ways; the window stays mapped until it is 0.

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

PanelWindow {
    id: root

    property bool shown: false
    property string ns: "sigil-panel"
    property bool grabKeyboard: true
    property bool closeOnOutsideClick: true
    property real dim: 0                 // kept for compatibility; no full-screen backdrop any more
    signal dismissed()
    default property alias content: panel.data
    readonly property Item contentItem: panel

    // size + placement
    property real panelWidth: 400
    property real panelHeight: 300
    property string placement: "center"   // center | top
    property real topFraction: 0.18
    property bool fullHeight: false
    property bool preferLeft: false
    readonly property int barGap: Theme.bs(30) + 14

    // corner mode (latched while open so a closing panel never jumps)
    property string requestedCorner: ""
    property string corner: ""
    property bool panelHovered: false
    readonly property bool cornerMode: corner !== ""
    readonly property bool atTop: corner.startsWith("top")
    readonly property bool atLeft: cornerMode ? corner.endsWith("Left") : preferLeft

    property bool leaveArmed: false
    onPanelHoveredChanged: {
        if (!cornerMode || !shown) return;
        if (panelHovered) { leaveTimer.stop(); cornerTimer.stop(); leaveArmed = true; }
        else if (leaveArmed) leaveTimer.restart();
    }
    onShownChanged: {
        leaveArmed = false;
        leaveTimer.stop();
        cornerTimer.stop();
        if (shown) corner = requestedCorner;
    }
    onVisibleChanged: if (!visible) corner = ""
    Timer { id: leaveTimer; interval: 300; onTriggered: if (root.shown && root.cornerMode && !root.panelHovered) root.dismissed() }
    Timer { id: cornerTimer; interval: 450; onTriggered: if (root.shown && root.cornerMode && !root.leaveArmed && !root.panelHovered) root.dismissed() }
    Connections {
        target: Actions
        function onCornerExited(c) { if (root.shown && c === root.corner && !root.leaveArmed) cornerTimer.restart(); }
    }

    property real openness: shown ? 1 : 0
    Behavior on openness {
        NumberAnimation {
            duration: root.shown ? Theme.dur(200) : Theme.dur(140)
            easing.type: root.shown ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: shown || openness > 0.001

    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor !== null && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: ns
    WlrLayershell.keyboardFocus: (shown && grabKeyboard) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // no anchors on an axis = centred on that axis by the compositor
    anchors {
        top: cornerMode ? (atTop || fullHeight) : (fullHeight || placement === "top")
        bottom: cornerMode ? (!atTop || fullHeight) : fullHeight
        left: cornerMode || fullHeight ? atLeft : false
        right: cornerMode || fullHeight ? !atLeft : false
    }
    margins {
        top: (!cornerMode && placement === "top" && !fullHeight) ? Math.round((screen ? screen.height : 1080) * topFraction) : barGap
        bottom: 10
        left: 10
        right: 10
    }
    implicitWidth: panelWidth
    implicitHeight: panelHeight

    // click outside → close
    HyprlandFocusGrab {
        active: root.shown && root.visible
        windows: [root]
        onCleared: if (root.shown && root.closeOnOutsideClick) root.dismissed()
    }

    Item {
        id: panel
        anchors.fill: parent
        opacity: root.openness
        scale: (root.cornerMode ? 0.9 : 0.95) + (root.cornerMode ? 0.1 : 0.05) * root.openness
        transformOrigin: !root.cornerMode ? Item.Center
                       : root.atTop ? (root.atLeft ? Item.TopLeft : Item.TopRight)
                       : (root.atLeft ? Item.BottomLeft : Item.BottomRight)
        focus: true
        Keys.onEscapePressed: root.dismissed()
    }
}
