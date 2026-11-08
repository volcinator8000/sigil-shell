pragma Singleton
pragma ComponentBehavior: Bound

// What a hot corner (or IPC call) can trigger. Parts of the shell that are not
// rebuilt yet hand off to the existing tools (rofi, swaync, wlogout, hyprexpose).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var available: ["launcher", "overview", "controlcenter", "dashboard", "power", "media", "none"]

    property bool mediaOpen: false
    property string mediaCorner: "bottomLeft"

    function sound() {
        Quickshell.execDetached(["sh", "-c", "[ -x ~/.config/keysound/keysound.sh ] && ~/.config/keysound/keysound.sh play open"]);
    }

    function run(action, corner) {
        switch (action) {
        case "launcher":      sound(); Quickshell.execDetached(["rofi", "-show", "drun"]); break;
        case "overview":      Quickshell.execDetached(["pkill", "-SIGUSR1", "hyprexpose"]); break;
        case "controlcenter": sound(); Quickshell.execDetached(["swaync-client", "-t", "-sw"]); break;
        case "power":         sound(); Quickshell.execDetached(["wlogout"]); break;
        case "dashboard":     Widgets.togglePeek(); break;
        case "media":         mediaCorner = corner || "bottomLeft"; mediaOpen = !mediaOpen; break;
        default: break;
        }
    }

    IpcHandler {
        target: "shell"
        function run(action: string): void { root.run(action, "bottomLeft"); }
    }
}
