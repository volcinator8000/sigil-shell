// Numeric field with − / + steppers (Adw.SpinRow equivalent).
// `valueModified(value)` fires on user changes only.

import QtQuick
import qs.services
import qs.components
import qs.settings.lib

Row {
    id: root
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property int decimals: 0
    property real value: 0
    signal valueModified(real value)
    spacing: 4
    opacity: enabled ? 1 : 0.4

    function clamp(v) {
        v = Math.max(from, Math.min(to, v));
        return +v.toFixed(decimals);
    }
    function set(v) {
        v = clamp(v);
        if (v !== value) { value = v; valueModified(v); }
        field.text = value.toFixed(decimals);
    }
    onValueChanged: if (!field.input.activeFocus) field.text = value.toFixed(decimals)
    Component.onCompleted: field.text = value.toFixed(decimals)

    component Step: Rectangle {
        id: st
        property string glyph
        signal hit()
        width: 24
        height: 26
        radius: Math.min(Theme.radius * 0.6, 8)
        color: sm.containsMouse ? Theme.s2 : "transparent"
        border.width: 1
        border.color: sm.containsMouse ? Theme.a2 : Theme.line
        Label { anchors.centerIn: parent; text: st.glyph; color: Theme.fg }
        MouseArea {
            id: sm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { Sh.snd("click"); st.hit(); }
            onPressAndHold: rep.start()
            onReleased: rep.stop()
        }
        Timer { id: rep; interval: 70; repeat: true; onTriggered: st.hit() }
    }

    Step { glyph: "−"; onHit: root.set(root.value - root.stepSize) }
    TextField {
        id: field
        width: 64
        height: 26
        input.horizontalAlignment: TextInput.AlignHCenter
        onAccepted: root.set(parseFloat(text.replace(",", ".")) || 0)
        input.onActiveFocusChanged: if (!input.activeFocus) root.set(parseFloat(text.replace(",", ".")) || 0)
    }
    Step { glyph: "+"; onHit: root.set(root.value + root.stepSize) }
}
