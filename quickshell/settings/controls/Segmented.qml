pragma ComponentBehavior: Bound

// Row of exclusive options. `activated(value)` on user clicks.

import QtQuick
import qs.services
import qs.components
import qs.settings.lib

Row {
    id: root
    property var options: []          // strings
    property string current: ""
    signal activated(string value)
    spacing: 0

    Repeater {
        model: root.options
        delegate: Rectangle {
            id: seg
            required property string modelData
            required property int index
            readonly property bool on: root.current === modelData
            width: segLabel.implicitWidth + 22
            height: 26
            color: on ? Theme.alpha(Theme.a1, 0.16) : sm.containsMouse ? Theme.s2 : Theme.bg
            border.width: 1
            border.color: on ? Theme.a1 : Theme.line
            radius: Math.min(Theme.radius * 0.6, 8)
            Behavior on color { ColorAnimation { duration: Theme.dur(120) } }
            Label {
                id: segLabel
                anchors.centerIn: parent
                text: seg.modelData
                color: seg.on ? Theme.a1 : Theme.fg
                font.pixelSize: 11
            }
            MouseArea {
                id: sm
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (seg.on) return;
                    Sh.snd("click");
                    root.current = seg.modelData;
                    root.activated(seg.modelData);
                }
            }
        }
    }
}
