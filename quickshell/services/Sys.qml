pragma Singleton
pragma ComponentBehavior: Bound

// CPU / RAM / GPU / temperature sampler. Only runs while something uses it
// (Sys.users > 0), every 1 s on AC and every 4 s on battery.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int users: 0
    readonly property int historyLength: 30

    property real cpu: 0          // %
    property real ramUsed: 0      // GiB
    property real ramTotal: 1     // GiB
    property real gpu: 0          // %
    property real temp: 0         // °C
    property var cpuHist: []
    property var ramHist: []
    property var gpuHist: []
    property var tempHist: []

    property string tempPath: ""
    property string gpuPath: ""
    property var prevStat: null

    // Find the k10temp sensor and the GPU that drives the internal panel once;
    // hwmon numbering is not stable across boots.
    Process {
        running: true
        command: ["sh", "-c",
            "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat $h/name)\" = k10temp ] && echo $h/temp1_input && break; done; " +
            "for c in /sys/class/drm/card*-eDP-*; do d=${c%%-eDP-*}; echo $d/device/gpu_busy_percent; break; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.tempPath = l[0] || "";
                root.gpuPath = l[1] || "";
            }
        }
    }

    FileView { id: stat; path: "/proc/stat"; onLoaded: root.parseStat(text()) }
    FileView { id: mem; path: "/proc/meminfo"; onLoaded: root.parseMem(text()) }
    FileView { id: tempFile; path: root.tempPath; onLoaded: root.temp = parseInt(text()) / 1000 }
    FileView { id: gpuFile; path: root.gpuPath; onLoaded: root.gpu = parseInt(text()) || 0 }

    function push(arr, v) { const a = arr.slice(-(historyLength - 1)); a.push(v); return a; }

    function parseStat(t) {
        const f = t.split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        const idle = f[3] + f[4], total = f.reduce((a, b) => a + b, 0);
        if (prevStat) {
            const dt = total - prevStat.total, di = idle - prevStat.idle;
            cpu = dt > 0 ? Math.max(0, Math.min(100, 100 * (1 - di / dt))) : 0;
        }
        prevStat = { total: total, idle: idle };
    }
    function parseMem(t) {
        const get = k => { const m = t.match(new RegExp("^" + k + ":\\s+(\\d+)", "m")); return m ? parseInt(m[1]) / 1048576 : 0; };
        ramTotal = get("MemTotal") || 1;
        ramUsed = ramTotal - get("MemAvailable");
    }

    Timer {
        interval: Theme.rich ? 1000 : 4000
        running: root.users > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload(); mem.reload();
            if (root.tempPath) tempFile.reload();
            if (root.gpuPath) gpuFile.reload();
            root.cpuHist = root.push(root.cpuHist, root.cpu);
            root.ramHist = root.push(root.ramHist, root.ramUsed);
            root.gpuHist = root.push(root.gpuHist, root.gpu);
            root.tempHist = root.push(root.tempHist, root.temp);
        }
    }
}
