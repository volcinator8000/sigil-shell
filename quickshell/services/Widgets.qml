pragma Singleton
pragma ComponentBehavior: Bound

// Desktop widget layout, persisted in ~/.config/sigil/widgets.json.
// Each entry: { id, type, x, y, style }  (style: card | glass | bare)
// Widget types are the files in ../widgets/types/<type>.qml; adding a new file
// and listing it in `types` below is all it takes to add a widget.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var types: [
        { type: "calendar", label: "Calendar" },
        { type: "weather",  label: "Weather" },
        { type: "perf",     label: "Performance" },
        { type: "clock",    label: "Clock" },
        { type: "notes",    label: "Notes" },
        { type: "disk",     label: "Disks" }
    ]
    readonly property var styles: ["card", "glass", "bare"]
    readonly property var defaults: [
        { id: 1, type: "calendar", x: 24,  y: 60,  style: "card" },
        { id: 2, type: "weather",  x: 24,  y: 300, style: "glass" },
        { id: 3, type: "perf",     x: 260, y: 60,  style: "bare" }
    ]

    property var items: []
    property bool editing: false      // drag / restyle / add / remove
    property bool peek: false         // widgets raised above windows (dashboard corner)
    property string peekCorner: ""    // corner that raised them ("" = key / clock click)
    property bool ignoreNextChange: false

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
    function update(id, patch) {
        items = items.map(w => w.id === id ? Object.assign({}, w, patch) : w);
        save();
    }
    function move(id, x, y) { update(id, { x: x, y: y }); }
    function cycleStyle(id) {
        const w = items.find(i => i.id === id);
        if (w) update(id, { style: styles[(styles.indexOf(w.style) + 1) % styles.length] });
    }
    function remove(id) { items = items.filter(w => w.id !== id); save(); }
    function add(type) {
        const id = items.reduce((m, w) => Math.max(m, w.id), 0) + 1;
        const n = items.length;
        items = items.concat([{ id: id, type: type, x: 600 + (n % 4) * 40, y: 200 + (n % 4) * 40, style: "glass" }]);
        save();
    }
    function toggleEdit() { editing = !editing; if (editing) peek = false; }
    function togglePeek() { peek = !peek; if (peek) editing = false; else peekCorner = ""; }

    IpcHandler {
        target: "widgets"
        function edit(): void { root.toggleEdit(); }
        function peek(): void { root.peekCorner = ""; root.togglePeek(); }
        function close(): void { root.editing = false; root.peek = false; }
    }
}
