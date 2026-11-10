pragma Singleton
pragma ComponentBehavior: Bound

// Every user-facing action of the shell. Hot corners, the bar, keybinds (through
// `sigil-do`, which calls `qs -c sigil ipc call shell run <action>`) all end up here.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property var available: ["launcher", "overview", "controlcenter", "dashboard", "power", "media", "none"]

    // which panel is open
    property string launcherMode: ""        // "" | apps | emoji | clipboard
    property bool controlCenterOpen: false
    property bool powerOpen: false
    property bool mediaOpen: false
    // file open in the note editor ("" = closed); the notes widget opens it on click
    property string notePath: ""
    function openNote(p) { closeAll(); notePath = p; sound("open"); }
    // new calendar event for this day ("" = editor closed); calendarChanged tells widgets to refetch
    property string eventDate: ""
    signal calendarChanged()
    function newEvent(d) { closeAll(); eventDate = d || Qt.formatDate(new Date(), "yyyy-MM-dd"); sound("open"); }
    property string mediaCorner: "bottomLeft"
    // Hot corner that opened the current panel ("" when opened by key / click).
    // Panels opened from a corner sit at that corner and close once the pointer leaves both.
    property string openCorner: ""
    signal cornerExited(string corner)
    // which hot corners the pointer is in right now (set by HotCorners)
    property var cornerInside: ({})
    // the pointer's x on the bar (-1 = not on the bar)
    property real barHoverX: -1
    function setCornerInside(c, v) { const o = Object.assign({}, cornerInside); o[c] = v; cornerInside = o; if (!v) cornerExited(c); }

    // The shell knows its own do-not-disturb, so the helper is told to skip its check (--force).
    // `force` = play even during do-not-disturb (lock/unlock, rules that bypass DND).
    function sound(name, force) {
        name = name || "open";
        if (Notifs.dnd && !force && name !== "lock" && name !== "unlock") return;
        Quickshell.execDetached(["sh", "-c", "[ -x ~/.config/keysound/keysound.sh ] && exec ~/.config/keysound/keysound.sh play \"$1\" --force", "sh", name]);
    }

    function isOpen(action) {
        switch (action) {
        case "launcher": return launcherMode === "apps";
        case "controlcenter": case "notifications": return controlCenterOpen;
        case "power": return powerOpen;
        case "media": return mediaOpen;
        case "dashboard": return Widgets.peek;
        default: return false;
        }
    }

    function closeAll() {
        launcherMode = "";
        controlCenterOpen = false;
        powerOpen = false;
        mediaOpen = false;
        notePath = "";
        eventDate = "";
    }

    function openLauncher(mode) {
        const wasOpen = launcherMode === mode;
        closeAll();
        if (!wasOpen) { launcherMode = mode; sound("open"); }
    }

    function run(action, corner) {
        // A hot corner only ever opens: a repeated trigger (pointer wobbling in the
        // corner) must not close the panel it just opened.
        if (corner && isOpen(action)) return;
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
        case "settings":      closeAll(); toggleSettings(); break;
        case "close":         closeAll(); break;
        default: console.warn("sigil: unknown action", action);
        }
    }

    signal toggleSettings()     // Settings.qml listens (no `qs ipc` round trip)

    // Keybinds land here directly as Hyprland global shortcuts:
    //   hl.bind("SUPER + N", hl.dsp.global("sigil:controlcenter"))
    // No process per key press (`sigil-do` / `qs ipc` start Qt, ~0.25 s each).
    Variants {
        model: ["launcher", "emoji", "clipboard", "controlcenter", "power", "settings", "media", "dashboard", "overview", "widgets-edit", "widgets-peek"]
        GlobalShortcut {
            required property string modelData
            appid: "sigil"
            name: modelData
            description: "sigil-shell: " + modelData
            onPressed: {
                if (modelData === "widgets-edit") Widgets.toggleEdit();
                else if (modelData === "widgets-peek") { Widgets.peekCorner = ""; Widgets.togglePeek(); }
                else root.run(modelData, "");
            }
        }
    }

    IpcHandler {
        target: "shell"
        function run(action: string): void { root.run(action, ""); }
        // as if from a hot corner (topLeft, topRight, bottomLeft, bottomRight)
        function runAt(action: string, corner: string): void { root.run(action, corner); }
        function note(path: string): void { root.openNote(path.replace(/^~/, Theme.home)); }
        function newEvent(day: string): void { root.newEvent(day); }
    }
}
