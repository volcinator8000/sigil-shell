import QtQuick
import qs.services

// Icon + draggable bar + value. `value` is 0..1; emits moved(v) while dragging or scrolling.
Item {
    id: root
    property real value: 0
    property string glyph: ""
    property color tint: Theme.a1
    property bool dimmed: false
    signal moved(real v)
    signal iconClicked()

    implicitHeight: 26
    implicitWidth: 300

    Label {
        id: icon
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: 22
        text: root.glyph
        font.pixelSize: 15
        color: root.dimmed ? Theme.dim : Theme.fg
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.iconClicked() }
    }
    Rectangle {
        id: track
        anchors { left: icon.right; leftMargin: 8; right: pct.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        height: 10
        radius: Math.min(Theme.radius * 0.5, 5)
        color: Theme.s2
        Rectangle {
            height: parent.height
            radius: parent.radius
            width: Math.max(height, parent.width * Math.min(1, root.value))
            color: root.dimmed ? Theme.dim : root.tint
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            function at(x) { return Math.max(0, Math.min(1, (x - 6) / track.width)); }
            onPressed: (m) => root.moved(at(m.x))
            onPositionChanged: (m) => { if (pressed) root.moved(at(m.x)); }
            onWheel: (w) => root.moved(Math.max(0, Math.min(1, root.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
    }
    Label {
        id: pct
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 36
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.value * 100)
        color: root.dimmed ? Theme.dim : Theme.fg
    }
}
