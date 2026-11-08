pragma ComponentBehavior: Bound

// Full-screen overlay on the focused monitor: dimmed (and, via the Hyprland layer
// rule, blurred) backdrop, keyboard grab while shown, Esc / backdrop click → dismissed().
// Children go into `content` and fade/scale in with the backdrop.

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

PanelWindow {
    id: root

    property bool shown: false
    property real dim: 0.45
    property string ns: "sigil-panel"
    property bool grabKeyboard: true
    signal dismissed()
    default property alias content: holder.data
    readonly property Item contentItem: holder

    visible: shown || fade.running
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor !== null && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: ns
    WlrLayershell.keyboardFocus: (shown && grabKeyboard) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: Theme.alpha(Theme.bg, root.dim)
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { id: fade; duration: Theme.dur(170); easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent; onClicked: root.dismissed() }
    }

    Item {
        id: holder
        anchors.fill: parent
        opacity: backdrop.opacity
        scale: 0.97 + 0.03 * backdrop.opacity
        focus: true
        Keys.onEscapePressed: root.dismissed()
    }
}
