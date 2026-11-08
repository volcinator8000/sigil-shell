pragma ComponentBehavior: Bound

// Wallpaper (replaces hyprpaper in sigil mode). Follows the path in
// ~/.config/hypr/hyprpaper.conf, which sigil-settings writes, and crossfades
// to a new image (instant on battery).

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

PanelWindow {
    id: win
    anchors { top: true; bottom: true; left: true; right: true }
    color: Theme.bg
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "sigil-wallpaper"

    readonly property string path: Theme.wallpaperPath
    property bool flip: false

    onPathChanged: {
        if (!path) return;
        const next = flip ? a : b;
        next.source = "file://" + path;
    }

    component Wall: Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: win.width
        sourceSize.height: win.height
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur(700); easing.type: Easing.InOutQuad } }
    }

    Wall {
        id: a
        onStatusChanged: if (status === Image.Ready) { opacity = 1; b.opacity = 0; win.flip = true; }
    }
    Wall {
        id: b
        onStatusChanged: if (status === Image.Ready) { opacity = 1; a.opacity = 0; win.flip = false; }
    }

    Component.onCompleted: if (path) a.source = "file://" + path
}
