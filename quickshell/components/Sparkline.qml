import QtQuick
import QtQuick.Shapes
import qs.services

// Area sparkline with an emphasised last point. Vector (Shape), so it stays sharp when
// the widget around it is scaled.
Item {
    id: root
    property var values: []
    property real minValue: 0
    property real maxValue: 100
    property color lineColor: Theme.a1

    implicitHeight: 20
    implicitWidth: 120

    readonly property var pts: {
        const v = values, n = v ? v.length : 0;
        if (n < 2) return [];
        const w = width, h = height, span = Math.max(1e-6, maxValue - minValue);
        const out = [];
        for (let i = 0; i < n; i++)
            out.push(Qt.point(i / (n - 1) * (w - 3), h - 1 - Math.max(0, Math.min(1, (v[i] - minValue) / span)) * (h - 3)));
        return out;
    }

    Shape {
        anchors.fill: parent
        visible: root.pts.length > 1
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Theme.alpha(root.lineColor, 0.14)
            strokeColor: "transparent"
            PathPolyline {
                path: root.pts.length > 1 ? [Qt.point(0, root.height)].concat(root.pts, [Qt.point(root.pts[root.pts.length - 1].x, root.height)]) : []
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.lineColor
            strokeWidth: 1.4
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: root.pts }
        }
    }
    Rectangle {
        visible: root.pts.length > 1
        width: 4; height: 4; radius: 2
        color: root.lineColor
        x: root.pts.length ? root.pts[root.pts.length - 1].x - 2 : 0
        y: root.pts.length ? root.pts[root.pts.length - 1].y - 2 : 0
    }
}
