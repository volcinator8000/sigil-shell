import QtQuick
import qs.services

// Area sparkline with an emphasised last point.
Canvas {
    id: root
    property var values: []
    property real minValue: 0
    property real maxValue: 100
    property color lineColor: Theme.a1

    implicitHeight: 20
    implicitWidth: 120
    renderStrategy: Canvas.Cooperative

    onValuesChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onWidthChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const v = values, n = v.length;
        if (n < 2) return;
        const w = width, h = height, span = Math.max(1e-6, maxValue - minValue);
        const px = i => i / (n - 1) * (w - 3);
        const py = x => h - 1 - Math.max(0, Math.min(1, (x - minValue) / span)) * (h - 3);

        ctx.beginPath();
        ctx.moveTo(0, h);
        for (let i = 0; i < n; i++) ctx.lineTo(px(i), py(v[i]));
        ctx.lineTo(px(n - 1), h);
        ctx.closePath();
        ctx.fillStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.14);
        ctx.fill();

        ctx.beginPath();
        for (let i = 0; i < n; i++) i === 0 ? ctx.moveTo(px(i), py(v[i])) : ctx.lineTo(px(i), py(v[i]));
        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 1.4;
        ctx.stroke();

        ctx.beginPath();
        ctx.arc(px(n - 1), py(v[n - 1]), 2, 0, Math.PI * 2);
        ctx.fillStyle = lineColor;
        ctx.fill();
    }
}
