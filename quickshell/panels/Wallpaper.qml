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
import Quickshell.Hyprland
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
        kick();
    }
    onPathChanged: show(path)
    Component.onCompleted: { slotA.path = path; slotA.opacity = 1; kick(); }

    // Redraw nudge. Under windows this surface gets no frame callbacks from Hyprland, and Qt
    // can drop the redraw that should follow an image load, leaving the first (empty) frame on
    // screen until something else changes. A 1 px change after loads/swaps and whenever the
    // workspace or its windows change (when the desktop may come into view) forces a fresh
    // frame. Event-driven only: nothing runs while idle.
    property bool pokeTick: false
    Rectangle { width: 1; height: 1; z: 100; color: win.pokeTick ? "#01000000" : "#00000000" }
    Timer {
        id: settle
        property int n: 0
        interval: 350; repeat: true
        onTriggered: { win.pokeTick = !win.pokeTick; if (++n >= 6) stop(); }
    }
    function kick() { settle.n = 0; settle.restart(); }
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (/^(workspace|focusedmon|activespecial|openwindow|closewindow|movewindow|changefloatingmode|fullscreen|monitoradded)/.test(e.name)) win.kick();
        }
    }

    WallSlot { id: slotA; win: win }
    WallSlot { id: slotB; win: win }
}
