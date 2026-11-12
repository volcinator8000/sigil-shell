pragma Singleton
pragma ComponentBehavior: Bound

// CPU / RAM / GPUs / temperatures / fans / battery power / network / root disk sampler.
// Only runs while something uses it (Sys.users > 0), every 1 s on AC and every 4 s on battery.
// Sensors are plain sysfs files found once at start (hwmon numbering moves between boots).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int users: 0
    // kept long enough for the widest performance widget (it shows the newest N samples)
    readonly property int historyLength: 300

    property real cpu: 0          // %
    property real ramUsed: 0      // GiB
    property real ramTotal: 1     // GiB
    property real gpu: 0          // %
    property real temp: 0         // °C
    property real diskPct: 0      // root filesystem, % used
    property string diskText: ""  // "212G / 476G"
    property var cpuHist: []
    property var ramHist: []
    property var gpuHist: []
    property var tempHist: []

    // every amdgpu card: [{ label: "igpu" | "dgpu" | "gpu", busy, vramUsed, vramTotal (GiB), temp }]
    property var gpus: []
    property var gpuHists: ({})   // label → busy % history
    property var fans: []         // rpm, one per laptop fan
    property real nvmeTemp: 0
    // battery (BAT0 sysfs): W is positive while charging, negative while draining
    property bool hasBattery: false
    property real batPct: 0
    property string batStatus: ""        // Charging / Discharging / Full / Not charging
    property real batWatts: 0
    property real batEnergy: 0           // Wh now
    property real batFull: 0             // Wh at full
    property real batDesign: 0           // Wh as designed
    property int batCycles: 0
    property bool acOnline: false
    property var powerHist: []           // |W|
    // network: the interface carrying the default route
    property string netIf: ""
    property string netIp: ""
    property real rxRate: 0              // bytes/s
    property real txRate: 0
    property var rxHist: []
    property var txHist: []
    property var prevNet: null

    property string tempPath: ""
    property string gpuPath: ""
    property var gpuDevs: []      // [{ label, dir, temp }]
    property var fanPaths: []
    property string nvmePath: ""
    property string batDir: ""
    property string acPath: ""
    property var prevStat: null

    // Find the sensors once; hwmon numbering is not stable across boots.
    Process {
        running: true
        command: ["sh", "-c", `
for h in /sys/class/hwmon/hwmon*; do
  n=$(cat $h/name 2>/dev/null)
  case "$n" in
    k10temp) echo "cpu $h/temp1_input" ;;
    nvme) echo "nvme $h/temp1_input" ;;
    hp|thinkpad|asus|dell_smm|applesmc) for f in $h/fan*_input; do [ -f "$f" ] && echo "fan $f"; done ;;
  esac
done
for c in /sys/class/drm/card[0-9]*; do
  case "$c" in *-*) continue ;; esac
  d=$c/device; [ -f $d/gpu_busy_percent ] || continue
  igpu=0; ls -d $c-eDP-* >/dev/null 2>&1 && igpu=1
  t=$(ls $d/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)
  echo "gpu $igpu $d $t"
done
for b in /sys/class/power_supply/*; do
  case "$(cat $b/type 2>/dev/null)" in
    Battery) [ -f $b/energy_now ] || [ -f $b/charge_now ] && echo "bat $b" ;;
    Mains) echo "ac $b/online" ;;
  esac
done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const g = [], f = [];
                for (const line of text.trim().split("\n")) {
                    const p = line.split(" ");
                    if (p[0] === "cpu") root.tempPath = p[1];
                    else if (p[0] === "nvme") root.nvmePath = p[1];
                    else if (p[0] === "fan") f.push(p[1]);
                    else if (p[0] === "gpu") g.push({ igpu: p[1] === "1", dir: p[2], temp: p[3] || "" });
                    else if (p[0] === "bat" && !root.batDir) root.batDir = p[1];
                    else if (p[0] === "ac") root.acPath = p[1];
                }
                // one GPU = "gpu"; two = "igpu" (drives the panel) and "dgpu"
                for (const x of g) x.label = g.length === 1 ? "gpu" : x.igpu ? "igpu" : "dgpu";
                g.sort((a, b) => (a.igpu ? 0 : 1) - (b.igpu ? 0 : 1));
                root.gpuDevs = g;
                const ig = g.find(x => x.igpu) || g[0];
                root.gpuPath = ig ? ig.dir + "/gpu_busy_percent" : "";
                root.fanPaths = f;
                root.hasBattery = root.batDir !== "";
            }
        }
    }
    // the slower-moving sensors: one cat for all of them per tick
    Process {
        id: sensors
        command: ["sh", "-c", 'for f in "$@"; do printf "%s\\n" "$(cat "$f" 2>/dev/null || echo -)"; done', "sh"].concat(root.sensorFiles)
        stdout: StdioCollector { onStreamFinished: root.parseSensors(text) }
    }
    readonly property var sensorFiles: {
        const l = [];
        for (const g of gpuDevs) l.push(g.dir + "/gpu_busy_percent", g.dir + "/mem_info_vram_used", g.dir + "/mem_info_vram_total", g.temp || "/nonexistent");
        for (const f of fanPaths) l.push(f);
        l.push(nvmePath || "/nonexistent");
        if (batDir) for (const k of ["status", "capacity", "power_now", "energy_now", "energy_full", "energy_full_design", "cycle_count", "current_now", "voltage_now", "charge_now", "charge_full", "charge_full_design"]) l.push(batDir + "/" + k);
        l.push(acPath || "/nonexistent");
        if (netIf) l.push("/sys/class/net/" + netIf + "/statistics/rx_bytes", "/sys/class/net/" + netIf + "/statistics/tx_bytes");
        return l;
    }
    function parseSensors(t) {
        const v = t.split("\n");
        let i = 0;
        const n = () => { const x = v[i++]; return x === undefined || x === "-" ? NaN : Number(x); };
        const s = () => { const x = v[i++]; return x === undefined || x === "-" ? "" : x; };
        const gl = [], gh = Object.assign({}, gpuHists);
        for (const g of gpuDevs) {
            const busy = n() || 0, vu = n(), vt = n(), tp = n();
            gl.push({ label: g.label, busy: busy, vramUsed: (vu || 0) / 1073741824, vramTotal: (vt || 0) / 1073741824, temp: isNaN(tp) ? 0 : tp / 1000 });
            gh[g.label] = push(gh[g.label] || [], busy);
        }
        gpus = gl; gpuHists = gh;
        const fl = [];
        for (let k = 0; k < fanPaths.length; k++) { const r = n(); if (!isNaN(r)) fl.push(r); }
        fans = fl;
        const nt = n(); nvmeTemp = isNaN(nt) ? 0 : nt / 1000;
        if (batDir) {
            batStatus = s(); batPct = n() || 0;
            let pw = n(), en = n(), ef = n(), ed = n();
            batCycles = n() || 0;
            const cur = n(), volt = n(), cn = n(), cf = n(), cd = n();
            // charge_* (µAh) batteries: convert with the voltage
            const vv = (volt || 0) / 1e6;
            if (isNaN(pw) && !isNaN(cur)) pw = cur * vv;
            if (isNaN(en) && !isNaN(cn)) { en = cn * vv; ef = cf * vv; ed = cd * vv; }
            const w = (pw || 0) / 1e6;
            batWatts = batStatus === "Discharging" ? -w : w;
            batEnergy = (en || 0) / 1e6; batFull = (ef || 0) / 1e6; batDesign = (ed || 0) / 1e6;
            powerHist = push(powerHist, w);
        }
        const ac = n(); acOnline = ac === 1;
        if (netIf) {
            const rx = n(), tx = n(), now = Date.now();
            if (prevNet && prevNet.ifc === netIf && !isNaN(rx)) {
                const dt = Math.max(0.2, (now - prevNet.t) / 1000);
                rxRate = Math.max(0, (rx - prevNet.rx) / dt);
                txRate = Math.max(0, (tx - prevNet.tx) / dt);
            }
            prevNet = { ifc: netIf, rx: rx, tx: tx, t: now };
            rxHist = push(rxHist, rxRate);
            txHist = push(txHist, txRate);
        }
    }
    // default-route interface and its address; re-checked every 30 s (Wi-Fi ↔ ethernet, VPNs)
    Process {
        id: route
        command: ["sh", "-c", 'i=$(ip -o route get 1.1.1.1 2>/dev/null | sed -n "s/.* dev \\([^ ]*\\).*/\\1/p"); echo "$i"; ip -o -4 addr show dev "$i" 2>/dev/null | awk "{print \\$4}" | head -1']
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                root.netIf = l[0] || "";
                root.netIp = (l[1] || "").split("/")[0];
            }
        }
    }
    Timer { interval: 30000; running: root.users > 0; repeat: true; triggeredOnStart: true; onTriggered: route.running = true }

    FileView { id: stat; path: "/proc/stat"; onLoaded: root.parseStat(text()) }
    FileView { id: mem; path: "/proc/meminfo"; onLoaded: root.parseMem(text()) }
    FileView { id: tempFile; path: root.tempPath; onLoaded: root.temp = parseInt(text()) / 1000 }
    FileView { id: gpuFile; path: root.gpuPath; onLoaded: root.gpu = parseInt(text()) || 0 }

    // root disk: df once a minute (it barely moves)
    Process {
        id: df
        command: ["df", "-B1", "--output=pcent,used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = (text.trim().split("\n")[1] || "").trim().split(/\s+/);
                if (f.length < 3) return;
                root.diskPct = parseInt(f[0]) || 0;
                const g = b => (Number(b) / 1073741824).toFixed(0) + "G";
                root.diskText = g(f[1]) + " / " + g(f[2]);
            }
        }
    }
    Timer { interval: 60000; running: root.users > 0; repeat: true; triggeredOnStart: true; onTriggered: df.running = true }

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
            if (!sensors.running) sensors.running = true;
            root.tempHist = root.push(root.tempHist, root.temp);
        }
    }
}
