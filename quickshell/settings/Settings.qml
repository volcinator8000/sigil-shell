pragma ComponentBehavior: Bound

// SIGIL // SETTINGS — the settings window.
// One FloatingWindow, created once and shown/hidden (closing only hides it).
// Pages load lazily on first visit and stay alive.
//   qs -c sigil ipc call settings toggle
//   qs -c sigil ipc call settings open <page>
//
// Getting around: the sidebar groups pages; the search box (Ctrl+F, or just start typing)
// finds any setting by its name, description, section or page and jumps to it.
// Ctrl+Tab / Ctrl+PgDn and Ctrl+Shift+Tab / Ctrl+PgUp step through pages, Esc clears the
// search or closes the window.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.components
import qs.settings.lib
import qs.settings.controls

Scope {
    id: root

    // Sidebar order. `keys` are extra search words; `preload: false` keeps a page out of the
    // search's background load (Snapshots may ask for a password when it loads).
    readonly property var pages: [
        { name: "overview",      group: "",                      title: "Overview",          glyph: "\u{F056E}", desc: "Live system stats and quick actions", keys: "dashboard stats cpu memory battery uptime lock" },

        { name: "appearance",    group: "Personalise",           title: "Appearance",        glyph: "\u{F03D8}", desc: "Colour palette, roundness, effects, font and hot corners", keys: "theme colours colors palette font radius blur shadows corners" },
        { name: "wallpaper",     group: "Personalise",           title: "Wallpaper",         glyph: "\u{F02E9}", desc: "Pick a wallpaper, rotate them, play animated ones", keys: "background image video gif rotation schedule" },
        { name: "widgets",       group: "Personalise",           title: "Widgets",           glyph: "\u{F072C}", desc: "Desktop widgets: arrange, style, options, weather location", keys: "desktop clock calendar notes weather city location" },

        { name: "notifications", group: "Notifications & sound", title: "Notifications",     glyph: "\u{F009A}", desc: "Popups, do not disturb and per-app rules", keys: "dnd popup alerts rules mute silent sound discord" },
        { name: "audio",         group: "Notifications & sound", title: "Audio",             glyph: "\u{F057E}", desc: "Output and input devices, volume, mixer", keys: "speakers headphones microphone volume" },
        { name: "sounds",        group: "Notifications & sound", title: "Sound effects",     glyph: "\u{F0387}", desc: "The shell's sound pack, system sounds and key sounds", keys: "sound theme pack keystrokes typewriter clicks" },

        { name: "wifi",          group: "Connections",           title: "Wi-Fi",             glyph: "\u{F05A9}", desc: "Networks, Tailscale and KDE Connect", keys: "network internet wireless tailscale vpn phone kde connect" },
        { name: "bluetooth",     group: "Connections",           title: "Bluetooth",         glyph: "\u{F00AF}", desc: "Adapter and devices", keys: "headphones pair devices" },

        { name: "display",       group: "Devices",               title: "Display",           glyph: "\u{F0379}", desc: "Brightness and night light", keys: "screen backlight brightness night light warm hyprsunset" },
        { name: "power",         group: "Devices",               title: "Power",             glyph: "\u{F0079}", desc: "Power profile, battery saving, ultra power saver, idle timers", keys: "battery profile performance eco ultra idle sleep lock suspend dim" },
        { name: "input",         group: "Devices",               title: "Keyboard & mouse",  glyph: "\u{F030C}", desc: "Key repeat, mouse sensitivity and touchpad", keys: "input keyboard mouse touchpad trackpad tap scroll repeat" },
        { name: "tablet",        group: "Devices",               title: "Tablet",            glyph: "\u{F03FA}", desc: "Drawing tablet mapping and buttons", keys: "pen wacom stylus drawing" },

        { name: "system",        group: "System",                title: "Updates & services", glyph: "\u{F06B0}", desc: "Package updates, restart parts of the desktop, dotfiles", keys: "updates packages pacman aur restart services daemons dotfiles git" },
        { name: "snapshots",     group: "System",                title: "Snapshots",         glyph: "\u{F02DA}", desc: "Btrfs snapshots with snapper", keys: "backup restore btrfs snapper", preload: false },
        { name: "about",         group: "System",                title: "About",             glyph: "\u{F02FC}", desc: "Keybinds, palette and where everything lives", keys: "keys keybinds shortcuts help version repos" }
    ]
    // old page names (IPC callers, muscle memory)
    readonly property var aliases: ({ shell: "appearance", desktop: "wallpaper", dashboard: "overview", keyboard: "input", mouse: "input", updates: "system", sound: "sounds", nightlight: "display" })

    property string current: "overview"
    property bool shown: false
    property bool searchedOnce: false        // loads every page once, so search can see their rows

    function indexOf(name) { return pages.findIndex(p => p.name === name); }
    function pageOf(name) { return pages[indexOf(name)] || { title: "", desc: "", group: "" }; }

    function show() {
        if (!shown) Sh.snd("open");
        shown = true;
        win.visible = true;
        refreshCurrent();
    }
    function hide() {
        if (shown) Sh.snd("close");
        shown = false;
        win.visible = false;
    }
    function select(name) {
        name = aliases[name] || name;
        if (indexOf(name) < 0) return false;
        const fresh = current !== name;
        current = name;
        if (!fresh || win.visible) refreshCurrent();
        return true;
    }
    function step(d) {
        const i = indexOf(current);
        select(pages[(i + d + pages.length) % pages.length].name);
        Sh.snd("click");
    }
    function refreshCurrent() {
        const l = loaders.itemAt(indexOf(current));
        if (l && l.item && typeof l.item.refresh === "function") l.item.refresh();
    }

    // ── search ───────────────────────────────────────────────────────
    property string query: ""
    property int hit: 0                       // highlighted result
    onQueryChanged: { hit = 0; if (query.trim()) searchedOnce = true; }

    // every Section / SettingRow of the loaded pages (walks their item trees)
    function collect(item, page, section, out) {
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i];
            if (c.searchKind === "section") {
                if (c.title) out.push({ page: page, title: c.title, sub: c.description || "", section: "", item: c, kind: "section" });
                collect(c, page, c.title || section, out);
            } else if (c.searchKind === "row") {
                if (c.title) out.push({ page: page, title: c.title, sub: c.subtitle || "", section: section, item: c, kind: "row" });
                collect(c, page, section, out);
            } else {
                collect(c, page, section, out);
            }
        }
    }
    readonly property var results: {
        const q = query.trim().toLowerCase();
        if (!q) return [];
        const words = q.split(/\s+/);
        const all = [];
        for (let i = 0; i < pages.length; i++) {
            const p = pages[i];
            all.push({ page: p, title: p.title, sub: p.desc, section: "", item: null, kind: "page" });
            const l = loaders.itemAt(i);
            if (l && l.item) collect(l.item, p, "", all);
        }
        void loadedCount;                     // re-run as pages finish loading
        const out = [];
        const seen = {};
        for (const r of all) {
            const t = r.title.toLowerCase();
            const hay = (t + " " + r.sub + " " + r.section + " " + r.page.title + " " + (r.kind === "page" ? r.page.keys : "")).toLowerCase();
            if (!words.every(w => hay.indexOf(w) >= 0)) continue;
            const key = r.page.name + "|" + r.section + "|" + r.title;
            if (seen[key]) continue;
            seen[key] = true;
            const score = (t.startsWith(q) ? 0 : t.indexOf(q) >= 0 ? 1 : words.every(w => t.indexOf(w) >= 0) ? 2 : 4)
                        + (r.kind === "page" ? -0.5 : r.kind === "section" ? 0 : 0.3);
            out.push(Object.assign({ score: score }, r));
        }
        out.sort((a, b) => a.score - b.score || a.title.length - b.title.length);
        return out.slice(0, 40);
    }
    property int loadedCount: 0

    function open(r) {
        if (!r) return;
        Sh.snd("click");
        select(r.page.name);
        query = "";
        searchInput.text = "";
        content.forceActiveFocus();
        if (r.item) {
            const l = loaders.itemAt(indexOf(r.page.name));
            Qt.callLater(() => { if (l && l.item && typeof l.item.reveal === "function") l.item.reveal(r.item); });
        }
    }

    Connections {
        target: Actions
        function onToggleSettings() { if (root.shown) root.hide(); else root.show(); }
    }
    IpcHandler {
        target: "settings"
        function toggle(): void {
            if (root.shown) root.hide(); else root.show();
        }
        function open(page: string): void {
            root.select(page.toLowerCase());
            root.show();
        }
        // what the search box would list for `q` (loads the pages; the window stays hidden)
        function search(q: string): string {
            root.searchedOnce = true;
            root.query = q;
            const out = root.results.map(r => r.title + "  [" + r.page.title + (r.section ? " › " + r.section : "") + "]").join("\n");
            root.query = "";
            return out;
        }
    }

    FloatingWindow {
        id: win
        title: "sigil-settings"
        visible: false
        implicitWidth: 1000
        implicitHeight: 680
        minimumSize: Qt.size(760, 480)
        color: Theme.bg
        // the compositor closing the window only hides it
        onVisibleChanged: if (!visible && root.shown) { root.shown = false; Sh.snd("close"); }

        Item {
            id: content
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.hide()
            // typing anywhere outside a text field starts a search
            Keys.onPressed: (e) => {
                if (e.text && /\S/.test(e.text) && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                    searchInput.text += e.text;
                    root.query = searchInput.text;
                    searchInput.forceActiveFocus();
                    e.accepted = true;
                }
            }

            Shortcut { sequences: ["Ctrl+F", "Ctrl+K"]; onActivated: { searchInput.forceActiveFocus(); searchInput.selectAll(); } }
            Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; onActivated: root.step(1) }
            Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab", "Ctrl+PgUp"]; onActivated: root.step(-1) }
            Shortcut { sequence: "Ctrl+W"; onActivated: root.hide() }

            // ── sidebar ──────────────────────────────────────────────
            Rectangle {
                id: sidebar
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: 220
                color: Theme.s1
                Rectangle { anchors { top: parent.top; bottom: parent.bottom; right: parent.right } width: 1; color: Theme.line }

                Label {
                    id: brand
                    anchors { top: parent.top; left: parent.left; topMargin: 16; leftMargin: 18 }
                    text: "SIGIL // SETTINGS"
                    color: Theme.a1
                    font.pixelSize: 11
                    font.letterSpacing: 2.4
                }

                // search box
                Rectangle {
                    id: searchBox
                    anchors { top: brand.bottom; topMargin: 12; left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10 }
                    height: 32
                    radius: Math.min(Theme.radius * 0.7, 16)
                    color: Theme.bg
                    border.width: 1
                    border.color: searchInput.activeFocus ? Theme.a1 : Theme.line
                    Behavior on border.color { ColorAnimation { duration: Theme.dur(120) } }
                    Label {
                        id: searchGlyph
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "\u{F0349}"
                        color: searchInput.activeFocus ? Theme.a1 : Theme.dim
                        font.pixelSize: 13
                    }
                    TextInput {
                        id: searchInput
                        anchors { left: searchGlyph.right; leftMargin: 8; right: clearBtn.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 12
                        selectionColor: Theme.alpha(Theme.a1, 0.4)
                        selectByMouse: true
                        clip: true
                        onTextEdited: root.query = text
                        onAccepted: root.open(root.results[root.hit])
                        Keys.onDownPressed: root.hit = Math.min(root.results.length - 1, root.hit + 1)
                        Keys.onUpPressed: root.hit = Math.max(0, root.hit - 1)
                        Keys.onEscapePressed: {
                            if (text) { text = ""; root.query = ""; }
                            else content.forceActiveFocus();
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !searchInput.text
                            text: searchInput.activeFocus ? "setting, page or word" : "Search   Ctrl+F"
                            color: Theme.alpha(Theme.dim, 0.8)
                        }
                    }
                    Label {
                        id: clearBtn
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        visible: searchInput.text !== ""
                        text: "\u{F0156}"
                        color: Theme.dim
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { searchInput.text = ""; root.query = ""; } }
                    }
                }

                // page list, grouped
                Flickable {
                    id: navFlick
                    visible: root.query.trim() === ""
                    anchors { top: searchBox.bottom; topMargin: 8; bottom: parent.bottom; left: parent.left; right: parent.right }
                    contentHeight: navCol.implicitHeight + 12
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    Column {
                        id: navCol
                        width: parent.width
                        Repeater {
                            model: root.pages
                            delegate: Column {
                                id: navRow
                                required property var modelData
                                required property int index
                                readonly property bool active: root.current === modelData.name
                                readonly property bool firstOfGroup: index === 0 || root.pages[index - 1].group !== modelData.group
                                width: parent.width
                                Item {
                                    visible: navRow.firstOfGroup && navRow.modelData.group !== ""
                                    width: parent.width
                                    height: visible ? 30 : 0
                                    Label {
                                        anchors { left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 6 }
                                        text: navRow.modelData.group.toUpperCase()
                                        color: Theme.alpha(Theme.dim, 0.85)
                                        font.pixelSize: 9
                                        font.letterSpacing: 1.6
                                    }
                                }
                                Item {
                                    width: parent.width
                                    height: 32
                                    Rectangle {
                                        anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1; bottomMargin: 1 }
                                        radius: Math.min(Theme.radius * 0.6, 8)
                                        color: navRow.active ? Theme.alpha(Theme.a1, 0.10) : navMouse.containsMouse ? Theme.alpha(Theme.fg, 0.05) : "transparent"
                                        Behavior on color { ColorAnimation { duration: Theme.dur(120) } }
                                        Rectangle {
                                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 7; bottomMargin: 7 }
                                            width: 2
                                            radius: 1
                                            color: Theme.a1
                                            opacity: navRow.active ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: Theme.dur(160) } }
                                        }
                                        Row {
                                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                            spacing: 10
                                            Label {
                                                width: 18
                                                text: navRow.modelData.glyph
                                                color: navRow.active ? Theme.a1 : Theme.dim
                                                font.pixelSize: 14
                                            }
                                            Label {
                                                text: navRow.modelData.title
                                                color: navRow.active ? Theme.a1 : Theme.fg
                                            }
                                        }
                                    }
                                    MouseArea {
                                        id: navMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (navRow.active) return;
                                            Sh.snd("click");
                                            root.select(navRow.modelData.name);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // search results
                ListView {
                    id: resultList
                    visible: root.query.trim() !== ""
                    anchors { top: searchBox.bottom; topMargin: 8; bottom: parent.bottom; left: parent.left; right: parent.right }
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.results
                    currentIndex: root.hit
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: Item {
                        id: res
                        required property var modelData
                        required property int index
                        readonly property bool on: index === root.hit
                        width: ListView.view.width
                        height: 46
                        Rectangle {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1; bottomMargin: 1 }
                            radius: Math.min(Theme.radius * 0.6, 8)
                            color: res.on ? Theme.alpha(Theme.a1, 0.10) : resMouse.containsMouse ? Theme.alpha(Theme.fg, 0.05) : "transparent"
                            Column {
                                anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Label {
                                    width: parent.width
                                    text: res.modelData.title
                                    color: res.on ? Theme.a1 : Theme.fg
                                    elide: Text.ElideRight
                                }
                                Label {
                                    width: parent.width
                                    text: res.modelData.kind === "page" ? "page · " + (res.modelData.page.group || "start")
                                        : res.modelData.page.title + (res.modelData.section ? "  ›  " + res.modelData.section : "")
                                    color: Theme.dim
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        MouseArea {
                            id: resMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.hit = res.index
                            onClicked: root.open(res.modelData)
                        }
                    }
                    Label {
                        anchors { top: parent.top; topMargin: 16; horizontalCenter: parent.horizontalCenter }
                        visible: resultList.count === 0
                        text: "nothing matches"
                        color: Theme.dim
                    }
                }
            }

            // ── header ───────────────────────────────────────────────
            Item {
                id: header
                anchors { top: parent.top; left: sidebar.right; right: parent.right }
                height: 64
                Column {
                    anchors { left: parent.left; leftMargin: 28; right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                    spacing: 3
                    Label {
                        text: root.pageOf(root.current).title
                        font.pixelSize: 17
                        font.bold: true
                    }
                    Label {
                        width: parent.width
                        text: root.pageOf(root.current).desc
                        color: Theme.dim
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right } height: 1; color: Theme.line }
            }

            // ── pages ────────────────────────────────────────────────
            Item {
                id: stack
                anchors { top: header.bottom; bottom: parent.bottom; left: sidebar.right; right: parent.right }
                Repeater {
                    id: loaders
                    model: root.pages
                    delegate: Loader {
                        id: pageLoader
                        required property var modelData
                        required property int index
                        readonly property bool isCurrent: root.current === modelData.name
                        property bool visited: false
                        onIsCurrentChanged: if (isCurrent) visited = true
                        Component.onCompleted: if (isCurrent) visited = true
                        anchors.fill: parent
                        active: visited || (root.searchedOnce && modelData.preload !== false)
                        visible: isCurrent
                        opacity: isCurrent ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.dur(140) } }
                        // search loads the other pages in the background
                        asynchronous: !isCurrent
                        source: "pages/" + modelData.name.charAt(0).toUpperCase() + modelData.name.slice(1) + "Page.qml"
                        // pages read `pageActive` to pause timers while hidden
                        onLoaded: {
                            item.pageActive = Qt.binding(() => pageLoader.isCurrent && root.shown);
                            root.loadedCount++;
                        }
                    }
                }
            }

            // ── toast ────────────────────────────────────────────────
            Rectangle {
                id: toast
                property string message: ""
                anchors { horizontalCenter: stack.horizontalCenter; bottom: parent.bottom; bottomMargin: 18 }
                width: Math.min(toastLabel.implicitWidth + 32, stack.width - 40)
                height: 34
                radius: Math.min(Theme.radius, 17)
                color: Theme.s2
                border.width: 1
                border.color: Theme.a2
                z: 200
                opacity: 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Theme.dur(160) } }
                Label {
                    id: toastLabel
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, toast.width - 24)
                    text: toast.message
                    elide: Text.ElideRight
                }
                Timer { id: toastTimer; interval: 2400; onTriggered: toast.opacity = 0 }
                Connections {
                    target: Sh
                    function onHideRequested(): void { root.hide(); }
                    function onToastRequested(message: string): void {
                        toast.message = message;
                        toast.opacity = 1;
                        toastTimer.restart();
                    }
                }
            }
        }
    }
}
