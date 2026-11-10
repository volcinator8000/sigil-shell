pragma Singleton
pragma ComponentBehavior: Bound

// Desktop widget layout, persisted in ~/.config/sigil/widgets.json.
//
// Entry: { id, type, ax, x, ay, y, style, opacity, scale, w, h, opts: { … } }
//   ax/ay:   left|center|right / top|center|bottom; x/y = px from that edge (center: offset
//            of the widget's centre from the screen's), so the layout fits any screen size
//   style:   card | glass | bare
//   opts:    per-type options; the schema lives in ../widgets/types/registry.json
//
// Widget types = ../widgets/types/<type>.qml + an entry in registry.json.
// `sigil-new-widget <name>` scaffolds both. The registry is watched, so new types
// and options appear in the settings page and the edit bar without a restart.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property var types: []                       // from registry.json
    readonly property var styles: ["card", "glass", "bare"]
    readonly property var defaults: [
        { id: 1, type: "calendar", ax: "left",  x: 24,  ay: "top", y: 60,  style: "card" },
        { id: 2, type: "weather",  ax: "left",  x: 24,  ay: "top", y: 300, style: "glass" },
        { id: 3, type: "perf",     ax: "right", x: 24,  ay: "top", y: 60,  style: "bare" }
    ]

    property var items: []
    property bool editing: false      // drag / restyle / add / remove
    property bool peek: false         // widgets raised above windows (dashboard corner)
    property string peekCorner: ""    // corner that raised them ("" = key / clock click)
    property int selected: -1         // widget id highlighted from the settings page
    property bool pageOpen: false     // the settings Widgets page is on screen (it highlights `selected`)
    // leaving edit mode by any route (Esc, keybind, toolbar) drops the selection outline
    onEditingChanged: if (!editing && !pageOpen) selected = -1
    property bool ignoreNextChange: false

    // Can anyone see the widgets right now? Raised (edit / peek), or no windows on the
    // focused workspace. Widgets with live data only poll while this is true.
    readonly property var ws: Hyprland.focusedWorkspace
    readonly property bool desktopVisible: editing || peek || !ws || !ws.toplevels || ws.toplevels.values.length === 0

    // ── registry ─────────────────────────────────────────────────────
    FileView {
        path: Quickshell.shellDir + "/widgets/types/registry.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.types = JSON.parse(text()); }
            catch (e) { console.warn("sigil: widgets/types/registry.json is not valid JSON:", e); }
        }
    }
    function typeInfo(type) { return types.find(t => t.type === type) || { type: type, label: type, options: [] }; }
    function defaultOpts(type) {
        const o = {};
        for (const opt of typeInfo(type).options || []) o[opt.key] = opt.default;
        return o;
    }
    // Option value with the registry default filled in.
    function opt(entry, key) {
        if (entry && entry.opts && entry.opts[key] !== undefined) return entry.opts[key];
        const d = (typeInfo(entry ? entry.type : "").options || []).find(o => o.key === key);
        return d ? d.default : undefined;
    }

    // ── layout file ──────────────────────────────────────────────────
    FileView {
        id: file
        path: Theme.dir + "/widgets.json"
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: {
            if (root.ignoreNextChange) { root.ignoreNextChange = false; return; }
            reload();
        }
        onLoaded: {
            try { root.items = JSON.parse(text()); }
            catch (e) { console.warn("sigil: widgets.json is not valid JSON:", e); }
        }
        onLoadFailed: root.items = root.defaults
    }

    function save() {
        ignoreNextChange = true;
        file.setText(JSON.stringify(items, null, 2) + "\n");
    }
    function get(id) { return items.find(w => w.id === id) || null; }
    function update(id, patch) {
        items = items.map(w => w.id === id ? Object.assign({}, w, patch) : w);
        save();
    }
    function setOpt(id, key, value) {
        const w = get(id);
        if (!w) return;
        const o = Object.assign({}, w.opts || {});
        o[key] = value;
        update(id, { opts: o });
    }
    function resetOpts(id) { const w = get(id); if (w) update(id, { opts: defaultOpts(w.type) }); }
    function cycleStyle(id) {
        const w = get(id);
        if (w) update(id, { style: styles[(styles.indexOf(w.style) + 1) % styles.length] });
    }
    function remove(id) { items = items.filter(w => w.id !== id); if (selected === id) selected = -1; save(); }
    function nextId() { return items.reduce((m, w) => Math.max(m, w.id), 0) + 1; }
    function add(type, opts) {
        const id = nextId(), n = items.length;
        items = items.concat([{ id: id, type: type, ax: "center", x: (n % 4) * 40, ay: "center", y: (n % 4) * 40, style: "glass",
                                opacity: 1, scale: 1, opts: Object.assign(defaultOpts(type), opts || {}) }]);
        save();
        return id;
    }
    function duplicate(id) {
        const w = get(id);
        if (!w) return -1;
        const copy = JSON.parse(JSON.stringify(w));
        copy.id = nextId();
        copy.x = w.x + 40;
        copy.y = w.y + 40;
        items = items.concat([copy]);
        save();
        return copy.id;
    }
    // Move a widget earlier/later in the list (= drawing order; later is on top).
    function reorder(id, delta) {
        const i = items.findIndex(w => w.id === id), j = i + delta;
        if (i < 0 || j < 0 || j >= items.length) return;
        const a = items.slice();
        const t = a[i]; a[i] = a[j]; a[j] = t;
        items = a;
        save();
    }
    readonly property int grid: Theme.widgetGrid
    readonly property var gridSizes: [0, 10, 20, 40]
    function cycleGrid() { Theme.patchSettings({ widgets: { grid: gridSizes[(gridSizes.indexOf(grid) + 1) % gridSizes.length] } }); }
    function snap(v) { return grid > 0 ? Math.round(v / grid) * grid : Math.round(v); }
    // arrow keys: move on screen whatever the anchor (offsets from right / bottom grow inward)
    function nudge(id, dx, dy) {
        const w = get(id);
        if (!w) return;
        const x = (w.x || 0) + (w.ax === "right" ? -dx : dx), y = (w.y || 0) + (w.ay === "bottom" ? -dy : dy);
        update(id, { x: w.ax === "center" ? x : Math.max(Theme.frame, x),
                     y: w.ay === "center" ? y : Math.max(w.ay === "bottom" ? Theme.frame : Theme.barH + Theme.frame, y) });
    }
    function stepScale(id, d) { const w = get(id); if (w) update(id, { scale: Math.round(Math.max(0.5, Math.min(2.5, (w.scale || 1) + d)) * 100) / 100 }); }
    function stepOpacity(id, d) { const w = get(id); if (w) update(id, { opacity: Math.round(Math.max(0.2, Math.min(1, (w.opacity === undefined ? 1 : w.opacity) + d)) * 100) / 100 }); }
    function selectNext(d) {
        if (!items.length) { selected = -1; return; }
        const i = items.findIndex(w => w.id === selected);
        selected = items[(i < 0 ? 0 : i + d + items.length) % items.length].id;
    }
    function openOptions(id) {
        selected = id;
        editing = false;
        Quickshell.execDetached(["qs", "-c", "sigil", "ipc", "call", "settings", "open", "widgets"]);
    }
    function resetLayout() { items = JSON.parse(JSON.stringify(defaults)); save(); }

    function toggleEdit() { editing = !editing; if (editing) peek = false; else selected = -1; }
    function togglePeek() { peek = !peek; if (peek) editing = false; else peekCorner = ""; }

    IpcHandler {
        target: "widgets"
        function edit(): void { root.toggleEdit(); }
        function peek(): void { root.peekCorner = ""; root.togglePeek(); }
        function close(): void { root.editing = false; root.peek = false; }
        function add(type: string): int { return root.add(type, {}); }
        function list(): string { return JSON.stringify(root.items); }
        function select(id: int): void { root.selected = id; }
    }
}
