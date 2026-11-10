// Background for a panel tucked into a screen corner, flush with both edges.
// Fills its parent: the body is the parent minus a `fillet` strip on the two inner
// sides; the exposed corner is rounded (`radius`), and where the body meets each screen
// edge the outline curves into it (inverted radius), like the bar and the side sheet.
//
//   atTop / atLeft   which corner (the drawing below is for bottom-right, then mirrored)
//   insetX / insetY  the screen frame's width on the side / bottom edge: the pocket covers it
//                    and its curves meet the frame's inner edge (no inset under the bar)

import QtQuick
import QtQuick.Shapes
import qs.services

Item {
    id: root
    property bool atTop: false
    property bool atLeft: false
    property real fillet: Theme.radius + 2
    property real insetX: Theme.frame
    property real insetY: atTop ? 0 : Theme.frame
    property real radius: Theme.radius * 1.4
    property color fill: Theme.surface
    property color line: Theme.line

    readonly property real ww: width
    readonly property real hh: height
    readonly property real f: fillet
    readonly property real rr: radius
    readonly property real ix: insetX
    readonly property real iy: insetY
    function px(v) { return atLeft ? ww - v : v; }
    function py(v) { return atTop ? hh - v : v; }
    // one mirror flips the turning direction, two cancel out
    readonly property bool flip: atLeft !== atTop
    readonly property int ccw: flip ? PathArc.Clockwise : PathArc.Counterclockwise
    readonly property int cw: flip ? PathArc.Counterclockwise : PathArc.Clockwise

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        // body + both fillets, one path
        ShapePath {
            fillColor: root.fill
            strokeColor: "transparent"
            startX: root.px(root.ww); startY: root.py(0)
            PathLine { x: root.px(root.ww); y: root.py(root.hh) }
            PathLine { x: root.px(0); y: root.py(root.hh) }
            PathLine { x: root.px(0); y: root.py(root.hh - root.iy) }
            PathArc { x: root.px(root.f); y: root.py(root.hh - root.iy - root.f); radiusX: root.f; radiusY: root.f; direction: root.ccw }
            PathLine { x: root.px(root.f); y: root.py(root.f + root.rr) }
            PathArc { x: root.px(root.f + root.rr); y: root.py(root.f); radiusX: root.rr; radiusY: root.rr; direction: root.cw }
            PathLine { x: root.px(root.ww - root.ix - root.f); y: root.py(root.f) }
            PathArc { x: root.px(root.ww - root.ix); y: root.py(0); radiusX: root.f; radiusY: root.f; direction: root.ccw }
            PathLine { x: root.px(root.ww); y: root.py(0) }
        }
        // hairline along the exposed outline
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.line
            strokeWidth: 1
            startX: root.px(0); startY: root.py(root.hh - root.iy)
            PathArc { x: root.px(root.f + 0.5); y: root.py(root.hh - root.iy - root.f); radiusX: root.f; radiusY: root.f; direction: root.ccw }
            PathLine { x: root.px(root.f + 0.5); y: root.py(root.f + root.rr) }
            PathArc { x: root.px(root.f + root.rr); y: root.py(root.f + 0.5); radiusX: root.rr - 0.5; radiusY: root.rr - 0.5; direction: root.cw }
            PathLine { x: root.px(root.ww - root.ix - root.f); y: root.py(root.f + 0.5) }
            PathArc { x: root.px(root.ww - root.ix); y: root.py(0); radiusX: root.f; radiusY: root.f; direction: root.ccw }
        }
    }
}
