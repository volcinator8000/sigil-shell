pragma Singleton
pragma ComponentBehavior: Bound

// Every user-facing action of the shell. Hot corners, the bar, keybinds (through
// `sigil-do`, which calls `qs -c sigil ipc call shell run <action>`) all end up here.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var available: ["launcher", "overview", "controlcenter", "dashboard", "power", "media", "none"]

    // which panel is open
    property string launcherMode: ""        // "" | apps | emoji | clipboard
    property bool controlCenterOpen: false
    property bool powerOpen: false
    property bool mediaOpen: false
    property string mediaCorner: "bottomLeft"
    // Hot corner that opened the current panel ("" when opened by key / click).
    // Panels opened from a corner sit at that corner and close once the pointer leaves both.
    property string openCorner: ""
    signal cornerExited(string corner)

    function sound(name) {
        Quickshell.execDetached(["sh", "-c", "[ -x ~/.config/keysound/keysound.sh ] && ~/.config/keysound/keysound.sh play " + (name || "open")]);
    }

    function closeAll() {
        launcherMode = "";
        controlCenterOpen = false;
        powerOpen = false;
        mediaOpen = false;
    }

    function openLauncher(mode) {
        const wasOpen = launcherMode === mode;
        closeAll();
        if (!wasOpen) { launcherMode = mode; sound("open"); }
    }

    function run(action, corner) {
        openCorner = corner || "";
        switch (action) {
        case "launcher":      openLauncher("apps"); break;
        case "emoji":         openLauncher("emoji"); break;
        case "clipboard":     openLauncher("clipboard"); break;
        case "overview":      Quickshell.execDetached(["pkill", "-SIGUSR1", "hyprexpose"]); break;
        case "controlcenter":
        case "notifications": { const o = !controlCenterOpen; closeAll(); controlCenterOpen = o; if (o) sound("open"); break; }
        case "power":         { const o = !powerOpen; closeAll(); powerOpen = o; if (o) sound("open"); break; }
        case "dashboard":     Widgets.peekCorner = corner || ""; Widgets.togglePeek(); break;
        case "media":         { const o = !mediaOpen; mediaCorner = corner || "bottomLeft"; closeAll(); mediaOpen = o; break; }
        case "lock":          closeAll(); Lock.lock(); break;
        case "settings":      closeAll(); Quickshell.execDetached(["qs", "-c", "sigil", "ipc", "call", "settings", "toggle"]); break;
        case "close":         closeAll(); break;
        default: console.warn("sigil: unknown action", action);
        }
    }

    IpcHandler {
        target: "shell"
        function run(action: string): void { root.run(action, ""); }
    }
}
