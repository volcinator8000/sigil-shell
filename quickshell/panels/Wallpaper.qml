pragma ComponentBehavior: Bound

// Wallpaper layer (replaces hyprpaper in sigil mode).
//  • still images: jpg png webp avif heif jxl tiff svg psd …
//  • animated images: gif apng animated webp/avif/jxl
//  • video: mp4 mkv webm mov avi … (QtMultimedia + ffmpeg, hardware decoding when available, muted)
// When Wallpapers.shouldPlay is false (unplugged, effects "never", a fullscreen window
// on top, locked) animated files are replaced by their still frame and the decoder is
// unloaded, so a paused wallpaper costs nothing. Changes crossfade between two slots.

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

    readonly property string path: Wallpapers.current
    property Item front: slotA

    function show(p) {
        if (!p) return;
        const back = front === slotA ? slotB : slotA;
        if (back.path === p && back.ready) { swap(back); return; }
        back.path = p;
        Qt.callLater(back.trySwap);
    }
    function swap(s) {
        if (front === s) return;
        s.opacity = 1;
        front.opacity = 0;
        front = s;
    }
    onPathChanged: show(path)
    Component.onCompleted: { slotA.path = path; slotA.opacity = 1; }

    WallSlot { id: slotA; win: win }
    WallSlot { id: slotB; win: win }
}
