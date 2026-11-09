pragma ComponentBehavior: Bound

// Popup panel window, sized to the panel itself (not full screen), so the compositor
// only redraws and blurs that area while it animates.
//  • placement: centred ("center"), near the top ("top", topFraction of the screen),
//    or a full-height side panel (fullHeight). Opened from a hot corner, it sits at
//    that corner instead.
//  • closes on Esc, on a click anywhere else (Hyprland focus grab), and in corner mode
//    when the pointer leaves: 300 ms after leaving the panel, or 450 ms after leaving
//    the corner without reaching it.
//  • fullHeight = side sheet: flush against the screen edge from the bar down to the
//    bottom, slides in from that edge; its inner corners curve into the bar and the
//    screen bottom (inverted radius), and Overlay draws its background.
//  • `openness` (0..1) animates both ways; the window stays mapped until it is 0.

import QtQuick
import QtQuick.Shapes
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
    readonly property bool sheet: fullHeight
    readonly property int fillet: Theme.radius + 2

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
    Timer { id: leaveTimer; interval: 300; onTriggered: if (root.shown && root.cornerMode && !root.panelHovered && !Actions.cornerInside[root.corner]) root.dismissed() }
    // only close if the pointer really is out of the corner (exit events can be spurious)
    Timer { id: cornerTimer; interval: 450; onTriggered: if (root.shown && root.cornerMode && !root.leaveArmed && !root.panelHovered && !Actions.cornerInside[root.corner]) root.dismissed() }
    Connections {
        target: Actions
        function onCornerExited(c) { if (root.shown && c === root.corner && !root.leaveArmed) cornerTimer.restart(); }
    }

    property real openness: shown ? 1 : 0
    Behavior on openness {
        NumberAnimation {
            duration: root.sheet ? (root.shown ? Theme.dur(320) : Theme.dur(220)) : (root.shown ? Theme.dur(200) : Theme.dur(140))
            easing.type: root.sheet ? (root.shown ? Easing.OutQuint : Easing.InCubic) : (root.shown ? Easing.OutCubic : Easing.InCubic)
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
        top: sheet ? Theme.bs(30) : (!cornerMode && placement === "top" && !fullHeight) ? Math.round((screen ? screen.height : 1080) * topFraction) : barGap
        bottom: sheet ? 0 : 10
        left: sheet ? 0 : 10
        right: sheet ? 0 : 10
    }
    implicitWidth: panelWidth + (sheet ? fillet : 0)
    // the fillet strip outside the sheet must not eat clicks
    mask: Region { item: panel }
    implicitHeight: panelHeight

    // click outside → close. Not in corner mode: there the panel closes when the pointer
    // leaves, and a grab would steal the pointer from the corner trigger and loop.
    HyprlandFocusGrab {
        active: root.shown && root.visible && !root.cornerMode
        windows: [root]
        onCleared: if (root.shown && root.closeOnOutsideClick) root.dismissed()
    }

    // side-sheet background: one path for the body and both inner fillets
    Item {
        id: sheetBg
        visible: root.sheet
        anchors.fill: parent
        transform: Translate { x: slide.x }
        readonly property bool lft: root.atLeft
        readonly property real ww: width
        readonly property real hh: height
        readonly property real r: root.fillet
        function px(v) { return lft ? ww - v : v; }
        readonly property int dir: lft ? PathArc.Clockwise : PathArc.Counterclockwise
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Theme.rich ? Theme.alpha(Theme.s1, 0.78) : Theme.s1   // same as the bar
                strokeColor: "transparent"
                startX: sheetBg.px(0); startY: 0
                PathLine { x: sheetBg.px(sheetBg.ww); y: 0 }
                PathLine { x: sheetBg.px(sheetBg.ww); y: sheetBg.hh }
                PathLine { x: sheetBg.px(0); y: sheetBg.hh }
                PathArc { x: sheetBg.px(sheetBg.r); y: sheetBg.hh - sheetBg.r; radiusX: sheetBg.r; radiusY: sheetBg.r; direction: sheetBg.dir }
                PathLine { x: sheetBg.px(sheetBg.r); y: sheetBg.r }
                PathArc { x: sheetBg.px(0); y: 0; radiusX: sheetBg.r; radiusY: sheetBg.r; direction: sheetBg.dir }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.line
                strokeWidth: 1
                startX: sheetBg.px(0); startY: sheetBg.hh
                PathArc { x: sheetBg.px(sheetBg.r + 0.5); y: sheetBg.hh - sheetBg.r; radiusX: sheetBg.r; radiusY: sheetBg.r; direction: sheetBg.dir }
                PathLine { x: sheetBg.px(sheetBg.r + 0.5); y: sheetBg.r }
                PathArc { x: sheetBg.px(0); y: 0; radiusX: sheetBg.r; radiusY: sheetBg.r; direction: sheetBg.dir }
            }
        }
    }
    // slides the whole sheet (background + content) out past the screen edge
    QtObject {
        id: slide
        readonly property real x: root.sheet ? (1 - root.openness) * root.width * (root.atLeft ? -1 : 1) : 0
    }

    Item {
        id: panel
        x: root.sheet && !root.atLeft ? root.fillet : 0
        y: 0
        width: root.sheet ? root.panelWidth : parent.width
        height: parent.height
        transform: Translate { x: slide.x }
        opacity: root.sheet ? 1 : root.openness
        scale: root.sheet ? 1 : (root.cornerMode ? 0.9 : 0.95) + (root.cornerMode ? 0.1 : 0.05) * root.openness
        transformOrigin: !root.cornerMode ? Item.Center
                       : root.atTop ? (root.atLeft ? Item.TopLeft : Item.TopRight)
                       : (root.atLeft ? Item.BottomLeft : Item.BottomRight)
        focus: true
        Keys.onEscapePressed: root.dismissed()
    }
}
