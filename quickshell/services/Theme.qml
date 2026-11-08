pragma Singleton
pragma ComponentBehavior: Bound

// Single source of truth for every visual value in the shell.
// Reads ~/.config/sigil/settings.json (live), resolves the active palette
// (a file in ../palettes or one derived from the wallpaper), then writes the
// resolved colours to ~/.config/sigil/palette.json and runs sigil-apply so
// kitty & co. follow along.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: home + "/.config/sigil"

    // ── settings (defaults; overridden by settings.json) ─────────────
    property string paletteName: "cybersigil"
    property int radius: 10
    property string font: "JetBrainsMono Nerd Font"
    property string effects: "auto"            // auto | full | low
    property var corners: ({ topLeft: "launcher", topRight: "controlcenter", bottomLeft: "media", bottomRight: "power" })
    property var weather: ({ city: "Paris", lat: 48.8566, lon: 2.3522 })
    property string wallpaperOverride: ""
    property bool barLyrics: true
    property real barScale: 1.1          // settings.json → bar.scale
    function bs(n) { return Math.round(n * barScale); }
    property var wallpapers: ({})        // see services/Wallpapers.qml
    property bool settingsLoaded: false

    // ── power-aware effects ──────────────────────────────────────────
    readonly property bool onBattery: UPower.onBattery
    readonly property bool rich: effects === "full" || (effects === "auto" && !onBattery)
    function dur(ms) { return rich ? ms : Math.round(ms * 0.4); }

    // ── colours ──────────────────────────────────────────────────────
    property color bg: "#050507"
    property color s1: "#0d0d12"
    property color s2: "#14141b"
    property color line: "#1b1b24"
    property color fg: "#dcdce3"
    property color dim: "#6b6b78"
    property color a1: "#3ae0ff"
    property color a2: "#a64dff"
    property color ok: "#39ff14"
    property color warn: "#ffb000"
    property color crit: "#ff2d3a"
    property var ansi: []
    property string paletteLabel: "Cybersigil"

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1); }
    function hex(c) {
        const h = v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0");
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    // ── settings file ────────────────────────────────────────────────
    FileView {
        id: settingsFile
        path: root.dir + "/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applySettings(text())
        onLoadFailed: root.settingsLoaded = true
    }

    function applySettings(txt) {
        let s;
        try { s = JSON.parse(txt); } catch (e) { console.warn("sigil: settings.json is not valid JSON:", e); return; }
        if (s.palette) paletteName = s.palette;
        if (s.radius !== undefined) radius = s.radius;
        if (s.font) font = s.font;
        if (s.effects) effects = s.effects;
        if (s.corners) corners = Object.assign({}, corners, s.corners);
        if (s.weather) weather = Object.assign({}, weather, s.weather);
        wallpaperOverride = s.wallpaper || "";
        barLyrics = !(s.bar && s.bar.lyrics === false);
        barScale = (s.bar && s.bar.scale) ? Math.max(0.8, Math.min(1.6, s.bar.scale)) : 1.1;
        wallpapers = s.wallpapers || {};
        settingsLoaded = true;
    }

    // ── palette files ────────────────────────────────────────────────
    FileView {
        id: paletteFile
        path: (root.settingsLoaded && root.paletteName !== "wallpaper") ? Quickshell.shellDir + "/palettes/" + root.paletteName + ".json" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.setPalette(JSON.parse(text())); }
            catch (e) { console.warn("sigil: bad palette file", path, e); }
        }
    }

    // ── wallpaper-derived palette ────────────────────────────────────
    FileView {
        id: hyprpaperConf
        path: root.home + "/.config/hypr/hyprpaper.conf"
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property string wallpaperPath: {
        if (wallpaperOverride) return wallpaperOverride;
        const m = (hyprpaperConf.text() || "").match(/^\s*path\s*=\s*(.+?)\s*$/m);
        return m ? m[1].replace(/^~/, home) : "";
    }

    ColorQuantizer {
        id: quantizer
        source: (root.paletteName === "wallpaper" && Wallpapers.still) ? "file://" + Wallpapers.still : ""
        depth: 4
        rescaleSize: 96
        onColorsChanged: if (root.paletteName === "wallpaper" && colors.length > 0) root.setPalette(root.fromColors(colors))
    }

    // Weighted hue histogram → two dominant hues → muted palette around them.
    function fromColors(colors) {
        const bins = [];
        for (let i = 0; i < 12; i++) bins.push({ w: 0, x: 0, y: 0 });
        for (const c of colors) {
            const h = c.hslHue, s = c.hslSaturation, l = c.hslLightness;
            if (h < 0) continue;
            const w = s * Math.max(0, 1 - Math.abs(l - 0.5) * 1.6);
            if (w < 0.04) continue;
            const b = bins[Math.floor(h * 12) % 12], rad = h * Math.PI * 2;
            b.w += w; b.x += Math.cos(rad) * w; b.y += Math.sin(rad) * w;
        }
        const hueOf = b => ((Math.atan2(b.y, b.x) / (Math.PI * 2)) + 1) % 1;
        const ranked = bins.filter(b => b.w > 0).sort((a, b) => b.w - a.w);
        const h1 = ranked.length ? hueOf(ranked[0]) : 0.6;
        const far = ranked.find(b => { const d = Math.abs(hueOf(b) - h1); return Math.min(d, 1 - d) >= 1 / 6; });
        const h2 = far ? hueOf(far) : (h1 + 0.42) % 1;
        const H = (h, s, l) => Qt.hsla(h, s, l, 1);
        return {
            name: "From wallpaper",
            bg: H(h1, .14, .05), s1: H(h1, .11, .08), s2: H(h1, .10, .115), line: H(h1, .09, .17),
            fg: H(h1, .12, .88), dim: H(h1, .07, .55), a1: H(h1, .45, .68), a2: H(h2, .38, .66),
            ok: H(130 / 360, .30, .62), warn: H(40 / 360, .55, .65), crit: H(3 / 360, .62, .60)
        };
    }

    function setPalette(p) {
        for (const k of ["bg", "s1", "s2", "line", "fg", "dim", "a1", "a2", "ok", "warn", "crit"])
            if (p[k] !== undefined) root[k] = p[k];
        paletteLabel = p.name || paletteName;
        ansi = p.ansi ? p.ansi : deriveAnsi();
        exportTimer.restart();
    }

    function deriveAnsi() {
        const W = Qt.rgba(1, 1, 1, 1), cyan = mix(a2, fg, .35);
        const base = [s2, crit, ok, warn, a2, a1, cyan, dim];
        const bright = [mix(line, fg, .25), mix(crit, W, .18), mix(ok, W, .18), mix(warn, W, .18), mix(a2, W, .18), mix(a1, W, .18), mix(cyan, W, .18), fg];
        return base.concat(bright).map(c => hex(c));
    }

    // ── export resolved palette for templates (debounced) ────────────
    Timer {
        id: exportTimer
        interval: 400
        onTriggered: {
            const out = { name: root.paletteName, label: root.paletteLabel, radius: root.radius, font: root.font, ansi: root.ansi };
            for (const k of ["bg", "s1", "s2", "line", "fg", "dim", "a1", "a2", "ok", "warn", "crit"]) out[k] = root.hex(root[k]);
            exportFile.setText(JSON.stringify(out, null, 2) + "\n");
            Quickshell.execDetached([root.home + "/.local/bin/sigil-apply"]);
        }
    }
    FileView { id: exportFile; path: root.dir + "/palette.json"; blockLoading: true; printErrors: false }
}
