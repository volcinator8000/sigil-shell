pragma Singleton
pragma ComponentBehavior: Bound

// Wallpaper engine: file types, still frames, when to animate, and rotation.
//
// The current wallpaper is the `path` in ~/.config/hypr/hyprpaper.conf (the settings
// page and the rotation both write it), so the lock screen, the wallpaper palette and
// the legacy setup all agree on it.
//
// settings.json → "wallpapers":
//   mode:            "fixed" | "interval" | "schedule"
//   folder:          folder to rotate through (interval mode)          default ~/Pictures/Wallpapers
//   interval:        minutes between changes (interval mode)           default 30
//   shuffle:         random order instead of alphabetical              default true
//   schedule:        [{ "at": "07:00", "path": "<file or folder>" }, …]  (schedule mode;
//                    the latest entry at or before now wins; a folder picks a random file)
//   animate:         "auto" (only on AC) | "always" | "never"           default auto
//   pauseFullscreen: freeze while a fullscreen window covers it         default true

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property var videoExt: ["mp4", "m4v", "mkv", "webm", "mov", "avi", "wmv", "flv", "ogv", "mpg", "mpeg", "ts", "3gp"]
    readonly property var animExt: ["gif", "apng", "mng"]
    // webp / avif / jxl can be either; Qt's AnimatedImage plays them if animated, shows them if not
    readonly property var maybeAnimExt: ["webp", "avif", "jxl"]
    readonly property var imageExt: ["jpg", "jpeg", "png", "bmp", "tif", "tiff", "tga", "svg", "heic", "heif", "jp2", "qoi", "exr", "hdr", "psd", "kra", "xcf", "pcx", "ico", "dds"]
    readonly property var allExt: imageExt.concat(animExt, maybeAnimExt, videoExt)

    function ext(p) { const m = String(p).toLowerCase().match(/\.([a-z0-9]+)$/); return m ? m[1] : ""; }
    function kindOf(p) {
        const e = ext(p);
        if (videoExt.indexOf(e) >= 0) return "video";
        if (animExt.indexOf(e) >= 0 || maybeAnimExt.indexOf(e) >= 0) return "animated";
        return "image";
    }
    function isSupported(p) { return allExt.indexOf(ext(p)) >= 0; }

    // ── config ───────────────────────────────────────────────────────
    readonly property var cfg: Theme.wallpapers || ({})
    readonly property string mode: cfg.mode || "fixed"
    readonly property string folder: expand(cfg.folder || "~/Pictures/Wallpapers")
    readonly property int interval: Math.max(1, cfg.interval || 30)
    readonly property bool shuffle: cfg.shuffle !== false
    readonly property var schedule: cfg.schedule || []
    readonly property string animate: cfg.animate || "auto"
    readonly property bool pauseFullscreen: cfg.pauseFullscreen !== false
    function expand(p) { return String(p).replace(/^~/, Theme.home); }

    // ── current wallpaper + still frame ──────────────────────────────
    readonly property string current: Theme.wallpaperPath
    readonly property string kind: kindOf(current)
    readonly property string stillDir: Theme.home + "/.cache/sigil/stills"
    function stillFor(p) { return kindOf(p) === "image" ? p : stillDir + "/" + Qt.md5(p) + ".jpg"; }
    readonly property string thumbDir: Theme.home + "/.cache/sigil/thumbs"
    function thumbFor(p) { return kindOf(p) === "image" ? p : thumbDir + "/" + Qt.md5(p) + ".jpg"; }
    // still image for anything that needs a picture (lock screen, palette, battery mode)
    property string still: ""
    onCurrentChanged: makeStill(current)

    Process {
        id: stillProc
        property string target: ""
        onExited: (code) => { if (code === 0) root.still = root.stillFor(target); }
    }
    function makeStill(p) {
        if (!p) { still = ""; return; }
        if (kindOf(p) === "image") { still = p; return; }
        stillProc.target = p;
        // frame at 1 s (0 s for short clips / GIFs); kept in ~/.cache/sigil/stills
        stillProc.command = ["sh", "-c",
            'o="$2"; [ -s "$o" ] && exit 0; mkdir -p "$(dirname "$o")"; ' +
            'ffmpeg -nostdin -loglevel error -y -ss 1 -i "$1" -frames:v 1 -q:v 3 "$o" 2>/dev/null || ' +
            'ffmpeg -nostdin -loglevel error -y -i "$1" -frames:v 1 -q:v 3 "$o"',
            "sh", p, stillFor(p)];
        stillProc.running = true;
    }
    // Generate small stills for many files (gallery thumbnails, ~/.cache/sigil/thumbs); calls back when done.
    function makeStills(paths, cb) {
        const todo = paths.filter(p => kindOf(p) !== "image");
        if (!todo.length) { if (cb) cb(); return; }
        const job = stillBatch.createObject(root, { cb: cb });
        job.command = ["sh", "-c",
            'd="$1"; shift; mkdir -p "$d"; for f; do o="$d/$(printf "%s" "$f" | md5sum | cut -c1-32).jpg"; [ -s "$o" ] && continue; ' +
            'ffmpeg -nostdin -loglevel error -y -ss 1 -i "$f" -frames:v 1 -vf scale=480:-2 -q:v 4 "$o" 2>/dev/null || ' +
            'ffmpeg -nostdin -loglevel error -y -i "$f" -frames:v 1 -vf scale=480:-2 -q:v 4 "$o"; done',
            "sh", thumbDir].concat(todo);
        job.running = true;
    }
    Component {
        id: stillBatch
        Process {
            property var cb: null
            onExited: { if (cb) cb(); destroy(); }
        }
    }

    // ── animate or freeze ────────────────────────────────────────────
    readonly property bool covered: pauseFullscreen && Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.hasFullscreen
    readonly property bool playing: kind !== "image" && animate !== "never"
                                    && (animate === "always" || !UPower.onBattery)
                                    && !covered && !Lock.locked
    property bool manualPause: false
    property string rendered: ""        // set by the front WallSlot: "<kind>:<live|still>:<file>"
    readonly property bool shouldPlay: playing && !manualPause

    // ── apply ────────────────────────────────────────────────────────
    FileView { id: hyprpaperFile; path: Theme.home + "/.config/hypr/hyprpaper.conf"; blockLoading: true; printErrors: false }
    function set(p) {
        if (!p || p === current) return;
        hyprpaperFile.setText("wallpaper {\n    monitor =\n    path = " + p + "\n    fit_mode = cover\n}\nsplash = false\n");
    }

    // ── rotation ─────────────────────────────────────────────────────
    property var folderFiles: []
    Process {
        id: lister
        property var after: null
        command: ["find", "-L", root.folder, "-maxdepth", "1", "-type", "f"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.folderFiles = text.split("\n").filter(f => f && root.isSupported(f) && !/_raw\.png$/.test(f)).sort();
                if (lister.after) { const a = lister.after; lister.after = null; a(); }
            }
        }
    }
    function listFolder(dir, cb) {
        lister.command = ["find", "-L", expand(dir), "-maxdepth", "1", "-type", "f"];
        lister.after = cb;
        lister.running = true;
    }

    function next(step) {
        listFolder(folder, () => {
            const files = folderFiles;
            if (!files.length) return;
            if (shuffle && files.length > 1) {
                let p;
                do { p = files[Math.floor(Math.random() * files.length)]; } while (p === current);
                set(p);
            } else {
                const i = files.indexOf(current);
                set(files[((i < 0 ? -1 : i) + (step || 1) + files.length) % files.length]);
            }
        });
    }

    Timer {
        interval: root.interval * 60 * 1000
        running: root.mode === "interval"
        repeat: true
        onTriggered: root.next(1)
    }

    // schedule: which entry applies now (latest "at" ≤ now, else the last one from yesterday)
    function scheduleEntry() {
        const s = schedule.filter(e => e && e.at && e.path).slice().sort((a, b) => a.at.localeCompare(b.at));
        if (!s.length) return null;
        const d = new Date(), now = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2);
        let pick = s[s.length - 1];
        for (const e of s) if (e.at <= now) pick = e;
        return pick;
    }
    property string lastSlot: ""
    function checkSchedule(force) {
        const e = scheduleEntry();
        if (!e) return;
        const slot = e.at + "|" + e.path;
        if (slot === lastSlot && !force) return;
        lastSlot = slot;
        const p = expand(e.path);
        if (isSupported(p)) set(p);
        else listFolder(p, () => {
            const f = folderFiles;
            if (f.length) set(f[Math.floor(Math.random() * f.length)]);
        });
    }
    Timer {
        interval: 30000
        running: root.mode === "schedule"
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkSchedule(false)
    }
    onModeChanged: lastSlot = ""
    onScheduleChanged: { lastSlot = ""; if (mode === "schedule") checkSchedule(true); }

    // ── settings write (merge into settings.json → "wallpapers") ─────
    FileView { id: settingsFile; path: Theme.dir + "/settings.json"; blockLoading: true; printErrors: false }
    function setConfig(patch) {
        settingsFile.reload();
        let s = {};
        try { s = JSON.parse(settingsFile.text() || "{}"); } catch (e) { console.warn("sigil: settings.json invalid, not writing"); return; }
        s.wallpapers = Object.assign({}, s.wallpapers || {}, patch);
        settingsFile.setText(JSON.stringify(s, null, 2) + "\n");
    }

    IpcHandler {
        target: "wallpaper"
        function next(): void { root.next(1); }
        function prev(): void { root.next(-1); }
        function set(path: string): void { root.set(path); }
        function pause(): void { root.manualPause = !root.manualPause; }
        function current(): string { return root.current; }
        function status(): string {
            return JSON.stringify({ current: root.current, kind: root.kind, mode: root.mode, shouldPlay: root.shouldPlay,
                                    onBattery: UPower.onBattery, covered: root.covered, still: root.still, rendered: root.rendered });
        }
    }
}
