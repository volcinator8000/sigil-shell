pragma ComponentBehavior: Bound

// Appearance: palette, roundness, effects, font and hot corners, stored in ~/.config/sigil/settings.json.
// Writes are merges (unknown keys survive); Theme watches the file and applies live.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false

    readonly property string settingsPath: Sh.home + "/.config/sigil/settings.json"
    readonly property var cornerActions: ["launcher", "overview", "controlcenter", "dashboard", "power", "media", "none"]
    property var palettes: []          // [{ id, name, colors }]
    property var fonts: []
    property string fontFilter: ""

    function refresh() { loadPalettes(); }
    Component.onCompleted: { loadPalettes(); loadFonts(); }

    // ── merge-write queue ────────────────────────────────────────────
    property var pending: ({})
    property bool writing: false
    function merge(a, b) {
        const out = Object.assign({}, a);
        for (const k in b) {
            const v = b[k];
            out[k] = (v && typeof v === "object" && !Array.isArray(v) && out[k] && typeof out[k] === "object")
                     ? merge(out[k], v) : v;
        }
        return out;
    }
    function save(patch) {
        pending = merge(pending, patch);
        if (!writing) flush();
    }
    function flush() {
        writing = true;
        Sh.readFile(settingsPath, (txt, ok) => {
            let cur = {};
            if (ok && txt.trim() !== "") {
                try { cur = JSON.parse(txt); }
                catch (e) {
                    Sh.toast("settings.json is not valid JSON, not overwriting it");
                    pending = {};
                    writing = false;
                    return;
                }
            }
            const next = merge(cur, pending);
            pending = {};
            Sh.sh('mkdir -p "$(dirname "$2")" && printf "%s" "$1" > "$2"', (out, rc) => {
                if (rc !== 0) Sh.toast("Could not write settings.json");
                writing = false;
                if (Object.keys(pending).length) flush();
            }, 8, [JSON.stringify(next, null, 2) + "\n", settingsPath]);
        });
    }

    // ── data ─────────────────────────────────────────────────────────
    function loadPalettes() {
        Sh.sh('for f in "$1"/*.json; do printf "%s\\t" "$(basename "$f" .json)"; tr -d "\\n" < "$f"; echo; done',
              out => {
                  const list = [];
                  for (const line of out.split("\n")) {
                      const i = line.indexOf("\t");
                      if (i < 0) continue;
                      try {
                          const p = JSON.parse(line.slice(i + 1));
                          list.push({ id: line.slice(0, i), name: p.name || line.slice(0, i), colors: p });
                      } catch (e) {}
                  }
                  page.palettes = list;
              }, 5, [Quickshell.shellDir + "/palettes"]);
    }
    function loadFonts() {
        Sh.run(["fc-list", ":", "family"], out => {
            const seen = {};
            for (const l of out.split("\n")) {
                const f = l.split(",")[0].trim();
                if (f) seen[f] = true;
            }
            page.fonts = Object.keys(seen).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
        }, 15);
    }
    readonly property var filteredFonts: {
        const q = fontFilter.trim().toLowerCase();
        return q ? fonts.filter(f => f.toLowerCase().indexOf(q) >= 0) : fonts;
    }

    // ── palette ──────────────────────────────────────────────────────
    component Swatch: Rectangle {
        width: 14
        height: 14
        radius: Math.min(3, Theme.radius / 3)
        border.width: 1
        border.color: Theme.alpha(Theme.fg, 0.12)
    }
    component PaletteCard: Rectangle {
        id: pc
        property string pid
        property string name
        property var colors: ({})
        property bool wallpaper: false
        readonly property bool selected: Theme.paletteName === pid
        width: 168
        height: 74
        radius: Theme.radius
        color: pcm.containsMouse ? Theme.s2 : Theme.s1
        border.width: selected ? 2 : 1
        border.color: selected ? Theme.a1 : pcm.containsMouse ? Theme.a2 : Theme.line
        Behavior on border.color { ColorAnimation { duration: Theme.dur(140) } }
        Column {
            anchors { fill: parent; margins: 11 }
            spacing: 8
            Label {
                width: parent.width
                text: pc.name
                color: pc.selected ? Theme.a1 : Theme.fg
                elide: Text.ElideRight
            }
            Row {
                spacing: 4
                visible: !pc.wallpaper || pc.selected
                Repeater {
                    model: ["bg", "s2", "fg", "a1", "a2", "ok", "warn", "crit"]
                    delegate: Swatch {
                        required property string modelData
                        color: pc.wallpaper ? Theme[modelData] : (pc.colors[modelData] || "transparent")
                    }
                }
            }
            Label {
                visible: pc.wallpaper && !pc.selected
                text: "\u{F02E9}  derived from the wallpaper"
                color: Theme.dim
                font.pixelSize: 10
            }
        }
        MouseArea {
            id: pcm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (pc.selected) return;
                Sh.snd("click");
                page.save({ palette: pc.pid });
            }
        }
    }

    Section {
        title: "Palette"
        description: "Colours for the bar, panels, widgets and (through sigil-apply) kitty & co."
        card: false
        Flow {
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                model: page.palettes
                delegate: PaletteCard {
                    required property var modelData
                    pid: modelData.id
                    name: modelData.name
                    colors: modelData.colors
                }
            }
            PaletteCard { pid: "wallpaper"; name: "From wallpaper"; wallpaper: true }
        }
    }

    Section {
        title: "Look"
        SettingRow {
            title: "Roundness"
            subtitle: "corner radius of every surface, 0 = square"
            Slider {
                from: 0; to: 24; stepSize: 1
                value: Theme.radius
                format: v => Math.round(v) + " px"
                onCommitted: v => page.save({ radius: Math.round(v) })
            }
        }
        SettingRow {
            title: "Effects"
            subtitle: "auto = full on charger, light on battery"
            Segmented {
                options: ["auto", "full", "low"]
                current: Theme.effects
                onActivated: v => page.save({ effects: v })
            }
        }
        SettingRow {
            title: "Font"
            subtitle: "current: " + Theme.font + " · type to filter, Enter to use the typed name"
            TextField {
                id: fontField
                implicitWidth: 240
                placeholder: "filter " + page.fonts.length + " families"
                onEdited: t => page.fontFilter = t
                onAccepted: if (text.trim()) { page.save({ font: text.trim() }); Sh.toast("Font: " + text.trim()); }
            }
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: 168
            Rectangle {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12; bottomMargin: 12 }
                radius: Math.min(Theme.radius * 0.7, 10)
                color: Theme.bg
                border.width: 1
                border.color: Theme.line
                ListView {
                    id: fontList
                    anchors { fill: parent; margins: 4 }
                    clip: true
                    model: page.filteredFonts
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: fontItem
                        required property string modelData
                        readonly property bool on: modelData === Theme.font
                        width: ListView.view.width
                        height: 24
                        radius: 4
                        color: fm.containsMouse ? Theme.s2 : on ? Theme.alpha(Theme.a1, 0.1) : "transparent"
                        Label {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            text: fontItem.modelData
                            color: fontItem.on ? Theme.a1 : Theme.fg
                        }
                        Label {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: "Aa 0123 \u{F03D8}"
                            font.family: fontItem.modelData
                            color: Theme.dim
                        }
                        MouseArea {
                            id: fm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Sh.snd("click");
                                fontField.text = fontItem.modelData;
                                page.save({ font: fontItem.modelData });
                            }
                        }
                    }
                }
                Label {
                    anchors.centerIn: parent
                    visible: fontList.count === 0
                    text: page.fonts.length ? "no match" : "reading fc-list…"
                    color: Theme.dim
                }
            }
        }
    }

    Section {
        title: "Hot corners"
        description: "What touching each screen corner does."
        Repeater {
            model: [["topLeft", "Top left"], ["topRight", "Top right"], ["bottomLeft", "Bottom left"], ["bottomRight", "Bottom right"]]
            delegate: SettingRow {
                id: cornerRow
                required property var modelData
                title: modelData[1]
                Dropdown {
                    model: page.cornerActions
                    currentIndex: Math.max(0, page.cornerActions.indexOf(Theme.corners[cornerRow.modelData[0]] || "none"))
                    onActivated: i => {
                        const c = {};
                        c[cornerRow.modelData[0]] = page.cornerActions[i];
                        page.save({ corners: c });
                    }
                }
            }
        }
    }
}
