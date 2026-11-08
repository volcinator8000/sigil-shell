// Horizontal slider with a value readout. `moved(value)` fires live while
// dragging; `committed(value)` fires 150 ms after the last move (debounced,
// like scale_row in the GTK app). Setting `value` from code emits nothing.

import QtQuick
import qs.services
import qs.components

Item {
    id: root
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property real value: 0
    property var format: v => Math.round(v) + "%"
    property int trackWidth: 200
    property int debounce: 150
    signal moved(real value)
    signal committed(real value)

    implicitWidth: trackWidth + 12 + readout.width
    implicitHeight: 22
    opacity: enabled ? 1 : 0.4

    readonly property real frac: to > from ? Math.max(0, Math.min(1, (value - from) / (to - from))) : 0

    Item {
        id: track
        width: root.trackWidth
        height: parent.height
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: Theme.line
            Rectangle {
                width: parent.width * root.frac
                height: parent.height
                radius: 2
                color: Theme.a1
            }
        }
        Rectangle {
            x: root.frac * (track.width - width)
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            radius: Math.min(6, Theme.radius / 2)
            color: mouse.pressed || mouse.containsMouse ? Theme.fg : Theme.a1
            border.width: 2
            border.color: Theme.bg
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            anchors.topMargin: -4
            anchors.bottomMargin: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            function setFrom(mx) {
                const f = Math.max(0, Math.min(1, mx / track.width));
                let v = root.from + f * (root.to - root.from);
                if (root.stepSize > 0) v = root.from + Math.round((v - root.from) / root.stepSize) * root.stepSize;
                v = Math.max(root.from, Math.min(root.to, +v.toFixed(6)));
                if (v !== root.value) {
                    root.value = v;
                    root.moved(v);
                    commit.restart();
                }
            }
            onPressed: e => setFrom(e.x)
            onPositionChanged: e => { if (pressed) setFrom(e.x); }
            onWheel: e => {
                const s = root.stepSize > 0 ? root.stepSize : (root.to - root.from) / 100;
                const v = Math.max(root.from, Math.min(root.to, +(root.value + (e.angleDelta.y > 0 ? s : -s)).toFixed(6)));
                if (v !== root.value) { root.value = v; root.moved(v); commit.restart(); }
            }
        }
    }
    Label {
        id: readout
        anchors { left: track.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
        width: 56
        horizontalAlignment: Text.AlignRight
        text: root.format(root.value)
        font.pixelSize: 11
    }
    Timer {
        id: commit
        interval: root.debounce
        onTriggered: root.committed(root.value)
    }
}
