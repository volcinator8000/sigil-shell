pragma Singleton
pragma ComponentBehavior: Bound

// Lock state. The surfaces live in panels/LockScreen.qml (ext-session-lock).
// `sigil-do lock` calls lock() and checks isLocked(); if the lock did not engage
// it falls back to hyprlock, so a broken shell never leaves the machine open.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool locked: false
    property bool testMode: false
    property var lockedAt: new Date()
    property bool engaged: false          // set by LockScreen once the compositor confirms

    function lock() {
        if (locked) return;
        lockedAt = new Date();
        Actions.closeAll();
        locked = true;
        Actions.sound("lock");
        // same marker file the old lock wrapper used, for scripts that read it
        Quickshell.execDetached(["sh", "-c", "date +%s > \"${XDG_RUNTIME_DIR:-/tmp}/locked-at\""]);
    }
    function unlock() {
        if (!locked) return;
        locked = false;
        testMode = false;
        Actions.sound("unlock");
        Quickshell.execDetached(["sh", "-c", "rm -f \"${XDG_RUNTIME_DIR:-/tmp}/locked-at\""]);
    }

    Timer { id: testTimer; interval: 6000; onTriggered: root.unlock() }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        function isLocked(): bool { return root.locked && root.engaged; }
        // Locks for 6 s and unlocks by itself, without PAM. For checking the visuals.
        function test(): void { root.testMode = true; root.lock(); testTimer.restart(); }
    }
}
