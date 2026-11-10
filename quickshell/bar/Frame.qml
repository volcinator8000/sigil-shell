pragma ComponentBehavior: Bound

// Screen frame: a Theme.frame-px border on the left, right and bottom edges, in the bar's
// colour, with rounded inner corners (the top two curve into the bar). Windows sit inside
// it: invisible strips reserve the space (the bar's too), the drawing itself takes no input.
// A side sheet or corner pocket slides in on top and joins the same edges.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.services

Scope {
    id: root
    required property ShellScreen screen
    readonly property int t: Theme.frame

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

    PanelWindow {
        id: win
        screen: root.screen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "sigil-frame"
        WlrLayershell.layer: WlrLayer.Bottom

        readonly property real b: Theme.barH
        readonly property real r: Theme.frameRadius

        // strips + four corner pieces (a single contour with a hole is mis-filled by both
        // Shape renderers: nothing at all, or the hole too, which hid the wallpaper)
        Rectangle { color: Theme.surface; x: 0; y: win.b; width: root.t; height: win.height - win.b }
        Rectangle { color: Theme.surface; x: win.width - root.t; y: win.b; width: root.t; height: win.height - win.b }
        Rectangle { color: Theme.surface; x: root.t; y: win.height - root.t; width: win.width - 2 * root.t; height: root.t }
        component Fillet: Shape {
            id: fil
            property bool onRight: false
            property bool onBottom: false
            width: win.r; height: win.r
            x: onRight ? win.width - root.t - win.r : root.t
            y: onBottom ? win.height - root.t - win.r : win.b
            preferredRendererType: Shape.CurveRenderer
            // drawn for the top-left corner, mirrored for the others
            transform: Scale { origin.x: win.r / 2; origin.y: win.r / 2; xScale: fil.onRight ? -1 : 1; yScale: fil.onBottom ? -1 : 1 }
            ShapePath {
                fillColor: Theme.surface
                strokeColor: "transparent"
                startX: 0; startY: 0
                PathLine { x: win.r; y: 0 }
                PathArc { x: 0; y: win.r; radiusX: win.r; radiusY: win.r; direction: PathArc.Counterclockwise }
                PathLine { x: 0; y: 0 }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.line
                strokeWidth: 1
                startX: win.r; startY: 0.5
                PathArc { x: 0.5; y: win.r; radiusX: win.r - 0.5; radiusY: win.r - 0.5; direction: PathArc.Counterclockwise }
            }
        }
        Fillet {}
        Fillet { onRight: true }
        Fillet { onBottom: true }
        Fillet { onRight: true; onBottom: true }

        // hairline just inside the inner edge (its top run is the line under the bar);
        // straight runs here, the curved bits are in the Fillets
        Rectangle { color: Theme.line; x: root.t + win.r; y: win.b; width: win.width - 2 * (root.t + win.r); height: 1 }
        Rectangle { color: Theme.line; x: root.t + win.r; y: win.height - root.t - 1; width: win.width - 2 * (root.t + win.r); height: 1 }
        Rectangle { color: Theme.line; x: root.t; y: win.b + win.r; width: 1; height: win.height - win.b - root.t - 2 * win.r }
        Rectangle { color: Theme.line; x: win.width - root.t - 1; y: win.b + win.r; width: 1; height: win.height - win.b - root.t - 2 * win.r }
    }
}
