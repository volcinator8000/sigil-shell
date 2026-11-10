pragma ComponentBehavior: Bound

// Screen frame: a Theme.frame-px border on the left, right and bottom edges, in the bar's
// colour, with rounded inner corners (the top two curve into the bar). Windows sit inside
// it: three invisible strips reserve the space, the drawing itself takes no input.
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

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            // border = (screen below the bar) minus (rounded inner area)
            ShapePath {
                fillColor: Theme.surface
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill
                PathRectangle { x: 0; y: win.b; width: win.width; height: win.height - win.b }
                PathRectangle { x: root.t; y: win.b; width: win.width - 2 * root.t; height: win.height - win.b - root.t; radius: win.r }
            }
            // hairline just inside the inner edge (its top run is the line under the bar)
            ShapePath {
                fillColor: "transparent"
                strokeColor: Theme.line
                strokeWidth: 1
                PathRectangle { x: root.t + 0.5; y: win.b + 0.5; width: win.width - 2 * root.t - 1; height: win.height - win.b - root.t - 1; radius: win.r - 0.5 }
            }
        }
    }
}
