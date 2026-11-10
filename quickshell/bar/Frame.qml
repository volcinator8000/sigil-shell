pragma ComponentBehavior: Bound

// Screen frame: a Theme.frame-px border on the left, right and bottom edges, in the bar's
// colour, with rounded inner corners (the top two curve into the bar). Windows sit inside
// it: invisible strips reserve the space (the bar's too); the drawing takes no input.
//
// Drawn by three thin edge windows, never one full-screen surface: a full-screen
// transparent layer under windows could keep a stale first buffer (the bar colour over
// the whole screen), which hid the wallpaper.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.services

Scope {
    id: root
    required property ShellScreen screen
    readonly property int t: Theme.frame
    readonly property int r: Theme.frameRadius

    // ── space reservation ────────────────────────────────────────────
    component Reserve: PanelWindow {
        screen: root.screen
        color: "transparent"
        mask: Region {}
        exclusiveZone: root.t
        implicitWidth: root.t
        implicitHeight: root.t
        WlrLayershell.namespace: "sigil-frame-reserve"
        WlrLayershell.layer: WlrLayer.Bottom
    }
    // the bar's space too (the bar itself ignores zones, so it spans the full width)
    Reserve { anchors { top: true; left: true; right: true } exclusiveZone: Theme.barH; implicitHeight: Theme.barH }
    Reserve { visible: root.t > 0; anchors { left: true; top: true; bottom: true } }
    Reserve { visible: root.t > 0; anchors { right: true; top: true; bottom: true } }
    Reserve { visible: root.t > 0; anchors { bottom: true; left: true; right: true } }

    // ── drawing ──────────────────────────────────────────────────────
    // concave corner piece, drawn for the top-left inner corner and mirrored for the others
    component Fillet: Shape {
        id: fil
        property bool flipX: false
        property bool flipY: false
        width: root.r; height: root.r
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { origin.x: root.r / 2; origin.y: root.r / 2; xScale: fil.flipX ? -1 : 1; yScale: fil.flipY ? -1 : 1 }
        ShapePath {
            fillColor: Theme.surface
            strokeColor: "transparent"
            startX: 0; startY: 0
            PathLine { x: root.r; y: 0 }
            PathArc { x: 0; y: root.r; radiusX: root.r; radiusY: root.r; direction: PathArc.Counterclockwise }
            PathLine { x: 0; y: 0 }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.line
            strokeWidth: 1
            startX: root.r; startY: 0.5
            PathArc { x: 0.5; y: root.r; radiusX: root.r - 0.5; radiusY: root.r - 0.5; direction: PathArc.Counterclockwise }
        }
    }

    // left / right edge: the strip plus its two inner corners (window is t + r wide; the
    // corner area outside the strip is transparent and takes no input)
    component Side: PanelWindow {
        id: side
        property bool isLeft: true
        screen: root.screen
        visible: root.t > 0
        anchors { top: true; bottom: true; left: side.isLeft; right: !side.isLeft }
        margins.top: Theme.barH
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: root.t + root.r
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "sigil-frame"
        WlrLayershell.layer: WlrLayer.Bottom

        Rectangle { color: Theme.surface; x: side.isLeft ? 0 : side.width - root.t; width: root.t; height: side.height }
        // hairline on the inner edge, between the corners
        Rectangle { color: Theme.line; x: side.isLeft ? root.t : side.width - root.t - 1; y: root.r; width: 1; height: side.height - root.t - 2 * root.r }
        Fillet { x: side.isLeft ? root.t : 0; y: 0; flipX: !side.isLeft }
        Fillet { x: side.isLeft ? root.t : 0; y: side.height - root.t - root.r; flipX: !side.isLeft; flipY: true }
    }
    Side { isLeft: true }
    Side { isLeft: false }

    // bottom edge between the corners (+1 px above it for the hairline)
    PanelWindow {
        id: bottom
        screen: root.screen
        visible: root.t > 0
        anchors { bottom: true; left: true; right: true }
        margins { left: root.t + root.r; right: root.t + root.r }
        exclusionMode: ExclusionMode.Ignore
        implicitHeight: root.t + 1
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "sigil-frame"
        WlrLayershell.layer: WlrLayer.Bottom

        Rectangle { color: Theme.line; width: bottom.width; height: 1 }
        Rectangle { color: Theme.surface; y: 1; width: bottom.width; height: root.t }
    }
}
