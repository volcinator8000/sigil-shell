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
    readonly property int barGap: Theme.barH + Theme.gap
    readonly property bool sheet: fullHeight
    // pocketable + opened from a hot corner = tucked into that corner, flush with both
    // edges (Pocket background), sliding out of the screen edge
    property bool pocketable: false
    readonly property bool pocket: pocketable && cornerMode && !sheet
    readonly property bool flush: sheet || pocket
    readonly property int fillet: Theme.frameRadius

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
    // the bar strip right above a side sheet counts as part of it
    readonly property bool overBar: sheet && Actions.barHoverX >= 0
        && (atLeft ? Actions.barHoverX <= width : Actions.barHoverX >= (screen ? screen.width : 1920) - width)
    readonly property bool pointerHome: panelHovered || overBar || !!Actions.cornerInside[corner]
    onOverBarChanged: {
        if (overBar || !shown || !cornerMode || panelHovered) return;
        if (leaveArmed) leaveTimer.restart(); else cornerTimer.restart();
    }
    Timer { id: leaveTimer; interval: 600; onTriggered: if (root.shown && root.cornerMode && !root.pointerHome) root.dismissed() }
    // only close if the pointer really is out of the corner (exit events can be spurious)
    Timer { id: cornerTimer; interval: 800; onTriggered: if (root.shown && root.cornerMode && !root.leaveArmed && !root.pointerHome) root.dismissed() }
    Connections {
        target: Actions
        function onCornerExited(c) { if (root.shown && c === root.corner && !root.leaveArmed) cornerTimer.restart(); }
    }

    property real openness: shown ? 1 : 0
    Behavior on openness {
        NumberAnimation {
            duration: root.flush ? (root.shown ? Theme.dur(340) : Theme.dur(300)) : (root.shown ? Theme.dur(200) : Theme.dur(140))
            easing.type: root.flush ? (root.shown ? Easing.OutQuint : Easing.InOutCubic) : (root.shown ? Easing.OutCubic : Easing.InCubic)
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
        top: sheet || (pocket && atTop) ? Theme.barH : pocket ? 0 : (!cornerMode && placement === "top" && !fullHeight) ? Math.round((screen ? screen.height : 1080) * topFraction) : barGap
        // flush panels join the screen frame; floating ones keep a gap from it
        bottom: Theme.frame + (flush ? 0 : Theme.gap)
        left: Theme.frame + (flush ? 0 : Theme.gap)
        right: Theme.frame + (flush ? 0 : Theme.gap)
    }
    implicitWidth: panelWidth + (flush ? fillet : 0)
    // the fillet strip outside the sheet must not eat clicks
    // (an untransformed twin of the panel: a Region does not follow the slide transform,
    //  so tracking `panel` left the input area where the sheet was before it slid in)
    mask: Region { item: hitArea }
    implicitHeight: panelHeight + (pocket ? fillet : 0)

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
                fillColor: Theme.surface   // same as the bar
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
    Pocket {
        visible: root.pocket
        anchors.fill: parent
        atTop: root.atTop
        atLeft: root.atLeft
        fillet: root.fillet
        transform: Translate { x: slide.x; y: slide.y }
    }

    // slides the whole sheet / pocket (background + content) out past the screen edge
    QtObject {
        id: slide
        readonly property real x: root.sheet ? (1 - root.openness) * root.width * (root.atLeft ? -1 : 1) : 0
        readonly property real y: root.pocket ? (1 - root.openness) * root.height * (root.atTop ? -1 : 1) : 0
    }

    Item {
        id: hitArea
        x: panel.x; y: panel.y; width: panel.width; height: panel.height
    }

    Item {
        id: panel
        x: root.flush && !root.atLeft ? root.fillet : 0
        y: root.pocket && !root.atTop ? root.fillet : 0
        width: root.flush ? root.panelWidth : parent.width
        height: root.pocket ? root.panelHeight : parent.height
        transform: Translate { x: slide.x; y: slide.y }
        opacity: root.flush ? 1 : root.openness
        scale: root.flush ? 1 : (root.cornerMode ? 0.9 : 0.95) + (root.cornerMode ? 0.1 : 0.05) * root.openness
        transformOrigin: !root.cornerMode ? Item.Center
                       : root.atTop ? (root.atLeft ? Item.TopLeft : Item.TopRight)
                       : (root.atLeft ? Item.BottomLeft : Item.BottomRight)
        focus: true
        Keys.onEscapePressed: root.dismissed()
    }
}
