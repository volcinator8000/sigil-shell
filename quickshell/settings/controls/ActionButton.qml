import QtQuick
import qs.components
import qs.settings.lib

// ChipButton that plays the pack's click sound and can be disabled.
ChipButton {
    id: root
    property bool sounds: true
    anchors.verticalCenter: undefined
    opacity: enabled ? 1 : 0.4
    onClicked: if (root.sounds) Sh.snd("click")
}
