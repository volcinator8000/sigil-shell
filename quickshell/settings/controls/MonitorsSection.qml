pragma ComponentBehavior: Bound

// Display page → monitors (lives in controls/ so the page can import it): arrangement, mode, scale, rotation, VRR, 10-bit, mirror, on/off.
//
// Only what is changed here is written: ~/.config/sigil/monitors.json keeps the per-monitor
// overrides (keyed by EDID description, so they follow a monitor to any port) and
// ~/.config/hypr/monitors.lua is generated from it; hyprland.lua merges that into its own
// monitor rules. `sigil-monitors apply` re-issues the rules live. After every apply a 15 s
// "keep these settings?" bar reverts on its own, so a mode the screen can't show undoes itself.

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 18

    readonly property string jsonPath: Sh.home + "/.config/sigil/monitors.json"
    readonly property string luaPath: Sh.cfg + "/hypr/monitors.lua"
    readonly property string helper: Sh.home + "/.local/bin/sigil-monitors"

    property var live: []         // hyprctl monitors all -j
    property var saved: ({})      // desc → override object (what monitors.json holds)
    property var draft: []        // one entry per live monitor, see makeDraft()
    property int sel: 0
    property bool busy: false
    // confirm-or-revert after an apply
    property var previous: null   // overrides before the apply
    property int countdown: 0

    readonly property var cur: draft.length ? draft[Math.min(sel, draft.length - 1)] : null
    readonly property var curLive: cur ? live.find(m => m.name === cur.name) : null

    Component.onCompleted: reload()
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name === "monitoradded" || e.name === "monitoraddedv2" || e.name === "monitorremoved" || e.name === "monitorremovedv2")
                Sh.later(400, () => root.reload());
        }
    }

    function reload() {
        Sh.readFile(jsonPath, t => {
            try { root.saved = t ? JSON.parse(t) : {}; } catch (e) { root.saved = {}; }
            Sh.run(["hyprctl", "monitors", "all", "-j"], out => {
                let ms = [];
                try { ms = JSON.parse(out || "[]"); } catch (e) {}
                ms.sort((a, b) => a.x - b.x || a.y - b.y);
                root.live = ms;
                root.draft = ms.map(m => root.makeDraft(m));
                if (root.sel >= root.draft.length) root.sel = 0;
            });
        });
    }

    // ── model ────────────────────────────────────────────────────────
    function modeOf(m) { return m.width + "x" + m.height + "@" + (+m.refreshRate.toFixed(2)); }
    function makeDraft(m) {
        const o = saved[m.description] || {};
        const vrrLive = m.vrr ? 1 : 0;
        return {
            name: m.name, desc: m.description, make: m.make, model: m.model,
            mode: o.mode !== undefined ? o.mode : modeOf(m),
            x: m.x, y: m.y,
            scale: o.scale !== undefined ? o.scale : m.scale,
            transform: o.transform !== undefined ? o.transform : m.transform,
            vrr: o.vrr !== undefined ? o.vrr : vrrLive,
            bit10: o.bitdepth !== undefined ? o.bitdepth === 10 : String(m.currentFormat).indexOf("2101010") >= 0,
            enabled: o.disabled !== undefined ? !o.disabled : !m.disabled,
            mirror: o.mirror !== undefined ? o.mirror : (m.mirrorOf && m.mirrorOf !== "none" ? nameOfId(m.mirrorOf) : ""),
            overridden: Object.keys(o).length > 0
        };
    }
    function nameOfId(id) { const m = live.find(x => String(x.id) === String(id)); return m ? m.name : ""; }
    function setField(k, v) {
        const d = draft.slice();
        const e = Object.assign({}, d[sel]);
        e[k] = v;
        d[sel] = e;
        draft = d;
    }
    // mode string → size in px (explicit modes only; highrr / preferred use the live size)
    function sizeOf(d) {
        const m = String(d.mode).match(/^(\d+)x(\d+)/);
        const lm = live.find(x => x.name === d.name) || { width: 1920, height: 1080 };
        return m ? { w: +m[1], h: +m[2] } : { w: lm.width, h: lm.height };
    }
    function logical(d) {
        const s = sizeOf(d), k = d.scale || 1;
        const rot = d.transform % 2 === 1;
        return { w: Math.round((rot ? s.h : s.w) / k), h: Math.round((rot ? s.w : s.h) / k) };
    }
    readonly property bool dirty: {
        for (const d of draft) {
            const m = live.find(x => x.name === d.name);
            if (!m) continue;
            const b = makeDraft(m);
            for (const k of ["mode", "x", "y", "scale", "transform", "vrr", "bit10", "enabled", "mirror"])
                if (String(b[k]) !== String(d[k])) return true;
        }
        return false;
    }

    // overrides = what differs from the live state, plus whatever was already overridden
    function buildOverrides() {
        const out = {};
        for (const d of draft) {
            const m = live.find(x => x.name === d.name);
            if (!m) continue;
            const prev = saved[d.desc] || {};
            const o = Object.assign({}, prev);
            const vrrLive = m.vrr ? 1 : 0;
            const bitLive = String(m.currentFormat).indexOf("2101010") >= 0;
            if (d.mode !== modeOf(m) || prev.mode !== undefined) o.mode = d.mode;
            if (d.x !== m.x || d.y !== m.y || prev.position !== undefined) o.position = d.x + "x" + d.y;
            if (d.scale !== m.scale || prev.scale !== undefined) o.scale = d.scale;
            if (d.transform !== m.transform || prev.transform !== undefined) o.transform = d.transform;
            if (d.vrr !== vrrLive || prev.vrr !== undefined) o.vrr = d.vrr;
            if (d.bit10 !== bitLive || prev.bitdepth !== undefined) o.bitdepth = d.bit10 ? 10 : 8;
            if (d.enabled === m.disabled || prev.disabled !== undefined) o.disabled = !d.enabled;
            if (d.mirror || prev.mirror !== undefined) { if (d.mirror) o.mirror = d.mirror; else delete o.mirror; }
            o.name = d.name;
            if (Object.keys(o).length > 1) out[d.desc] = o;
        }
        return out;
    }
    function luaStr(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'; }
    function toLua(ov) {
        let t = "-- generated by sigil-settings (Display page) from ~/.config/sigil/monitors.json; loaded by\n"
              + "-- hyprland.lua, merged into its monitor rules. Delete both files to undo every change.\nreturn {\n";
        for (const desc in ov) {
            const o = ov[desc], r = [];
            for (const k of ["mode", "position", "scale", "transform", "vrr", "bitdepth", "disabled", "mirror"]) {
                if (o[k] === undefined) continue;
                r.push(k + " = " + (typeof o[k] === "string" ? luaStr(o[k]) : String(o[k])));
            }
            t += "    { desc = " + luaStr(desc) + ", name = " + luaStr(o.name) + ", rule = { " + r.join(", ") + " } },\n";
        }
        return t + "}\n";
    }
    function write(ov, nudge, after) {
        busy = true;
        Sh.writeFile(jsonPath, JSON.stringify(ov, null, 2) + "\n", () => {
            Sh.writeFile(luaPath, toLua(ov), () => {
                Sh.run([helper, "apply"].concat(nudge), (out, rc) => {
                    busy = false;
                    if (rc !== 0) Sh.toast("Hyprland refused the monitor rules: " + out);
                    Sh.later(700, () => { root.reload(); if (after) after(); });
                }, 20);
            });
        });
    }
    // vrr / bitdepth only re-commit on a mode change, so those monitors get nudged
    function nudgeFor(ov, before) {
        const n = [];
        for (const d of draft) {
            const a = ov[d.desc] || {}, b = before[d.desc] || {};
            const m = live.find(x => x.name === d.name);
            if (!m) continue;
            const vrrNow = m.vrr ? 1 : 0, bitNow = String(m.currentFormat).indexOf("2101010") >= 0 ? 10 : 8;
            const modeChanged = (a.mode || modeOf(m)) !== modeOf(m);
            if (!modeChanged && ((a.vrr !== undefined && a.vrr !== vrrNow) || (a.bitdepth !== undefined && a.bitdepth !== bitNow)
                                 || (a.vrr === undefined && b.vrr !== undefined) || (a.bitdepth === undefined && b.bitdepth !== undefined)))
                n.push(d.name);
        }
        return n;
    }
    function apply() {
        if (!draft.some(d => d.enabled && !d.mirror)) { Sh.toast("Keep at least one monitor on"); return; }
        const before = saved;
        const ov = buildOverrides();
        previous = before;
        write(ov, nudgeFor(ov, before), () => { root.countdown = 15; });
    }
    function keep() { countdown = 0; previous = null; Sh.toast("Monitor settings kept"); }
    function revert() {
        countdown = 0;
        const p = previous || {};
        previous = null;
        write(p, nudgeFor(p, saved), () => Sh.toast("Monitor settings reverted"));
    }
    function resetAll() {
        busy = true;
        Sh.sh('rm -f "$1" && "$2" reset', (out, rc) => { busy = false; Sh.later(700, () => root.reload()); Sh.toast("Back to the rules in hyprland.lua"); },
              20, [jsonPath, helper]);
    }
    Timer {
        interval: 1000; repeat: true; running: root.countdown > 0
        onTriggered: { root.countdown--; if (root.countdown === 0) root.revert(); }
    }

    // ── arrangement ──────────────────────────────────────────────────
    // drop a monitor so it touches the nearest edge of another one, aligned when close
    function snap(i, x, y) {
        const me = logical(draft[i]);
        let best = null, bestD = 1e12;
        const al = (v, opts) => { for (const o of opts) if (Math.abs(v - o) < 60) return o; return v; };
        for (let j = 0; j < draft.length; j++) {
            const o = draft[j];
            if (j === i || !o.enabled || o.mirror) continue;
            const ol = logical(o);
            const cy = Math.max(o.y - me.h + 1, Math.min(o.y + ol.h - 1, y));
            const cx = Math.max(o.x - me.w + 1, Math.min(o.x + ol.w - 1, x));
            const ys = al(cy, [o.y, o.y + ol.h - me.h, o.y + (ol.h - me.h) / 2]);
            const xs = al(cx, [o.x, o.x + ol.w - me.w, o.x + (ol.w - me.w) / 2]);
            for (const c of [{ x: o.x + ol.w, y: ys }, { x: o.x - me.w, y: ys }, { x: xs, y: o.y - me.h }, { x: xs, y: o.y + ol.h }]) {
                const dd = (c.x - x) * (c.x - x) + (c.y - y) * (c.y - y);
                if (dd < bestD) { bestD = dd; best = c; }
            }
        }
        return best ? { x: Math.round(best.x), y: Math.round(best.y) } : { x: 0, y: 0 };
    }
    function normalize() {
        const on = draft.filter(d => d.enabled && !d.mirror);
        if (!on.length) return;
        const mx = Math.min(...on.map(d => d.x)), my = Math.min(...on.map(d => d.y));
        if (mx === 0 && my === 0) return;
        draft = draft.map(d => Object.assign({}, d, { x: d.x - mx, y: d.y - my }));
    }

    Section {
        title: "Monitors"
        description: "Drag to arrange, click one to change it. Applying asks you to confirm and reverts after 15 s, so a mode your screen can't show undoes itself."
        actions: [
            ActionButton { text: "Reset"; visible: Object.keys(root.saved).length > 0; onClicked: root.resetAll() },
            ActionButton { text: root.busy ? "Applying…" : "Apply"; accent: true; enabled: root.dirty && !root.busy && root.countdown === 0; onClicked: root.apply() }
        ]

        // confirm bar
        Rectangle {
            Layout.fillWidth: true
            visible: root.countdown > 0
            implicitHeight: 46
            color: Theme.alpha(Theme.a1, 0.12)
            radius: Theme.radius
            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
                Label { Layout.fillWidth: true; text: "Keep these display settings? Reverting in " + root.countdown + " s" }
                ActionButton { text: "Revert"; onClicked: root.revert() }
                ActionButton { text: "Keep"; accent: true; onClicked: root.keep() }
            }
        }

        // arrangement canvas
        Item {
            id: canvas
            Layout.fillWidth: true
            implicitHeight: 210
            readonly property var placed: root.draft.filter(d => d.enabled && !d.mirror)
            readonly property var box: {
                let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
                for (const d of placed) {
                    const l = root.logical(d);
                    x0 = Math.min(x0, d.x); y0 = Math.min(y0, d.y); x1 = Math.max(x1, d.x + l.w); y1 = Math.max(y1, d.y + l.h);
                }
                return placed.length ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : { x: 0, y: 0, w: 1, h: 1 };
            }
            // a third of the space around the layout so a monitor can be dragged to any side
            readonly property real k: Math.min((width - 40) / (box.w * 1.6), (height - 30) / (box.h * 1.6))
            readonly property real ox: (width - box.w * k) / 2 - box.x * k
            readonly property real oy: (height - box.h * k) / 2 - box.y * k

            Repeater {
                model: root.draft.length
                delegate: Rectangle {
                    id: tile
                    required property int index
                    readonly property var d: root.draft[index]
                    readonly property var l: root.logical(d)
                    readonly property bool active: index === root.sel
                    visible: d.enabled && !d.mirror
                    x: canvas.ox + d.x * canvas.k
                    y: canvas.oy + d.y * canvas.k
                    width: l.w * canvas.k
                    height: l.h * canvas.k
                    radius: 6
                    color: active ? Theme.alpha(Theme.a1, 0.2) : Theme.s2
                    border.width: active ? 2 : 1
                    border.color: active ? Theme.a1 : Theme.line
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 12
                        Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: tile.d.make || tile.d.name; font.bold: true }
                        Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: tile.d.name; color: Theme.dim; font.pixelSize: 11 }
                    }
                    DragHandler {
                        id: drag
                        target: tile
                        enabled: canvas.placed.length > 1
                        onActiveChanged: if (!active) {
                            const p = root.snap(tile.index, Math.round((tile.x - canvas.ox) / canvas.k), Math.round((tile.y - canvas.oy) / canvas.k));
                            const dd = root.draft.slice();
                            dd[tile.index] = Object.assign({}, dd[tile.index], { x: p.x, y: p.y });
                            root.draft = dd;
                            root.normalize();
                            root.sel = tile.index;
                            // the drag replaced the position bindings
                            tile.x = Qt.binding(() => canvas.ox + tile.d.x * canvas.k);
                            tile.y = Qt.binding(() => canvas.oy + tile.d.y * canvas.k);
                        }
                    }
                    TapHandler { onTapped: root.sel = tile.index }
                    HoverHandler { cursorShape: canvas.placed.length > 1 ? Qt.OpenHandCursor : Qt.PointingHandCursor }
                }
            }
            // monitors that are off or mirrored, listed so they can still be selected
            Row {
                anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
                spacing: 6
                Repeater {
                    model: root.draft.filter(d => !d.enabled || d.mirror)
                    delegate: ChipButton {
                        required property var modelData
                        text: modelData.name + (modelData.mirror ? " · mirrors " + modelData.mirror : " · off")
                        onClicked: root.sel = root.draft.findIndex(d => d.name === modelData.name)
                    }
                }
            }
        }
    }

    // ── selected monitor ─────────────────────────────────────────────
    Section {
        visible: root.cur !== null
        title: root.cur ? (root.cur.make ? root.cur.make + " " + root.cur.model : root.cur.name) + " · " + root.cur.name : ""
        description: root.cur && root.cur.overridden ? "Changed from hyprland.lua here; Reset puts every monitor back." : ""

        SettingRow {
            title: "On"; subtitle: "Turn this output off without unplugging it"
            Toggle {
                checked: root.cur ? root.cur.enabled : true
                onToggled: on => {
                    if (!on && root.draft.filter(d => d.enabled && !d.mirror).length <= 1 && !root.cur.mirror) { checked = true; Sh.toast("Keep at least one monitor on"); return; }
                    root.setField("enabled", on);
                }
            }
        }
        SettingRow {
            title: "Resolution & refresh"
            subtitle: "“Fastest refresh” follows the cable: e.g. 100 Hz over HDMI, 144 Hz over DisplayPort"
            enabled: root.cur ? root.cur.enabled : false
            Dropdown {
                id: modeBox
                implicitWidth: 260
                readonly property var specials: [["highrr", "Fastest refresh (auto)"], ["highres", "Highest resolution (auto)"], ["preferred", "Monitor's preferred"]]
                readonly property var modes: {
                    const lm = root.curLive;
                    if (!lm) return [];
                    const seen = {}, out = [];
                    for (const s of lm.availableModes || []) {
                        const m = s.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
                        if (!m) continue;
                        const v = m[1] + "x" + m[2] + "@" + (+(+m[3]).toFixed(2));
                        if (seen[v]) continue;
                        seen[v] = true;
                        out.push([v, m[1] + " × " + m[2] + "  ·  " + (+(+m[3]).toFixed(2)) + " Hz"]);
                    }
                    return out;
                }
                readonly property var all: specials.concat(modes)
                model: all.map(x => x[1])
                currentIndex: root.cur ? Math.max(0, all.findIndex(x => x[0] === root.cur.mode)) : 0
                onActivated: i => root.setField("mode", all[i][0])
            }
        }
        SettingRow {
            title: "Scale"; subtitle: "Bigger UI on dense screens; Hyprland rounds to the nearest clean value"
            enabled: root.cur ? root.cur.enabled : false
            Segmented {
                readonly property var values: [1, 1.25, 1.333333, 1.5, 1.6, 2]
                options: ["1×", "1.25", "1.33", "1.5", "1.6", "2×"]
                current: root.cur ? (options[values.findIndex(v => Math.abs(v - root.cur.scale) < 0.01)] || "") : ""
                onActivated: v => root.setField("scale", values[options.indexOf(v)])
            }
        }
        SettingRow {
            title: "Rotation"
            enabled: root.cur ? root.cur.enabled : false
            Segmented {
                options: ["normal", "90°", "180°", "270°"]
                current: root.cur ? options[root.cur.transform % 4] : ""
                onActivated: v => root.setField("transform", options.indexOf(v))
            }
        }
        SettingRow {
            title: "Adaptive sync (VRR)"
            subtitle: root.curLive && root.curLive.hardwareDetails && !root.curLive.hardwareDetails.vrrCapable
                      ? "This monitor doesn't report FreeSync / VRR support"
                      : "Refresh follows the frame rate: no tearing, less stutter in games"
            enabled: root.cur ? root.cur.enabled : false
            Segmented {
                options: ["off", "always", "fullscreen"]
                current: root.cur ? options[root.cur.vrr] || "off" : ""
                onActivated: v => root.setField("vrr", options.indexOf(v))
            }
        }
        SettingRow {
            title: "10-bit colour"; subtitle: "Smoother gradients; needed for wide gamut and HDR"
            enabled: root.cur ? root.cur.enabled : false
            Toggle { checked: root.cur ? root.cur.bit10 : false; onToggled: on => root.setField("bit10", on) }
        }
        SettingRow {
            title: "Mirror"; subtitle: "Show another monitor's picture on this one"
            visible: root.draft.length > 1
            Dropdown {
                readonly property var names: [""].concat(root.draft.filter(d => root.cur && d.name !== root.cur.name).map(d => d.name))
                model: names.map(n => n || "none")
                currentIndex: root.cur ? Math.max(0, names.indexOf(root.cur.mirror)) : 0
                onActivated: i => root.setField("mirror", names[i])
            }
        }
        SettingRow {
            title: "Position"; subtitle: "Top-left corner in the layout, logical pixels"
            enabled: root.cur ? root.cur.enabled && !root.cur.mirror : false
            Label { text: root.cur ? root.cur.x + ", " + root.cur.y + "   ·   " + root.logical(root.cur).w + " × " + root.logical(root.cur).h : ""; color: Theme.dim }
        }
    }
}
