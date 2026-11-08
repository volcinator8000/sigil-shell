// Pill switch. `checked` flips on click and `toggled(checked)` fires;
// setting `checked` from code never emits.

import QtQuick
import qs.services
import qs.settings.lib

Rectangle {
    id: root
    property bool checked: false
    property bool sounds: true
    signal toggled(bool checked)

    implicitWidth: 38
    implicitHeight: 20
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: checked ? Theme.alpha(Theme.a1, 0.85) : Theme.s2
    border.width: 1
    border.color: checked ? Theme.a1 : mouse.containsMouse ? Theme.a2 : Theme.line
    Behavior on color { ColorAnimation { duration: Theme.dur(140) } }

    Rectangle {
        width: 14
        height: 14
        radius: 7
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - width - 3 : 3
        color: root.checked ? Theme.bg : Theme.dim
        Behavior on x { NumberAnimation { duration: Theme.dur(140); easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.checked = !root.checked;
            if (root.sounds) Sh.snd(root.checked ? "toggle-on" : "toggle-off");
            root.toggled(root.checked);
        }
    }
}
