pragma ComponentBehavior: Bound

// Four 3×3 px trigger zones on the overlay layer. Hovering one for 150 ms runs
// the action mapped to it in settings.json → corners. Disabled while the focused
// workspace has a fullscreen window (games, video).

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

Scope {
    id: root
    required property ShellScreen screen

    readonly property bool blocked: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.hasFullscreen

    component Corner: PanelWindow {
        id: corner
        required property string key
        required property bool atTop
        required property bool atLeft

        screen: root.screen
        visible: !root.blocked && (Theme.corners[key] || "none") !== "none"
        anchors { top: atTop; bottom: !atTop; left: atLeft; right: !atLeft }
        implicitWidth: 3
        implicitHeight: 3
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "sigil-corner"

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: dwell.restart()
            onExited: { dwell.stop(); Actions.cornerExited(corner.key); }
        }
        Timer {
            id: dwell
            interval: 150
            onTriggered: Actions.run(Theme.corners[corner.key], corner.key)
        }
    }

    Corner { key: "topLeft";     atTop: true;  atLeft: true }
    Corner { key: "topRight";    atTop: true;  atLeft: false }
    Corner { key: "bottomLeft";  atTop: false; atLeft: true }
    Corner { key: "bottomRight"; atTop: false; atLeft: false }
}
