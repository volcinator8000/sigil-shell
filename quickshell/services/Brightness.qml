pragma Singleton
pragma ComponentBehavior: Bound

// Backlight level via brightnessctl. Changes made by anything (keys, other apps)
// are picked up from udev backlight events, so there is no polling.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real value: 0          // 0..1
    property bool available: false
    signal changedExternally()

    Process {
        id: read
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",");
                if (f.length >= 5) {
                    const v = parseInt(f[2]) / parseInt(f[4]);
                    const changed = root.available && Math.abs(v - root.value) > 0.001;
                    root.value = v;
                    root.available = true;
                    if (changed) root.changedExternally();
                }
            }
        }
    }
    Component.onCompleted: read.running = true

    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=backlight"]
        stdout: SplitParser {
            onRead: (line) => { if (line.indexOf("change") >= 0 && !read.running) read.running = true; }
        }
    }

    function set(v) {
        v = Math.max(0.01, Math.min(1, v));
        value = v;
        Quickshell.execDetached(["brightnessctl", "-q", "set", Math.round(v * 100) + "%"]);
    }
}
