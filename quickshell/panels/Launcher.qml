pragma ComponentBehavior: Bound

// Launcher with three modes (replaces rofi): apps, emoji, clipboard.
// Tab / Shift+Tab switches mode, ↑↓ moves, Enter runs, Esc closes.
// Apps are ranked by match quality plus how often you launch them.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.components

Overlay {
    id: launcher
    shown: Actions.launcherMode !== ""
    dim: 0.35
    onDismissed: Actions.launcherMode = ""

    readonly property string mode: Actions.launcherMode || "apps"
    readonly property var modes: ["apps", "emoji", "clipboard"]
    property string query: ""
    property int current: 0

    onShownChanged: {
        if (!shown) return;
        search.text = "";
        current = 0;
        search.forceActiveFocus();
        if (mode === "clipboard") clipList.running = true;
    }
    onModeChanged: { current = 0; if (mode === "clipboard" && shown) clipList.running = true; }

    // ── usage counts (apps) ──────────────────────────────────────────
    property var usage: ({})
    FileView {
        id: usageFile
        path: Theme.dir + "/launcher-usage.json"
        printErrors: false
        onLoaded: { try { launcher.usage = JSON.parse(text()); } catch (e) {} }
    }
    function bump(id) {
        const u = Object.assign({}, usage);
        u[id] = (u[id] || 0) + 1;
        usage = u;
        usageFile.setText(JSON.stringify(u));
    }

    // ── emoji data (loaded on first use) ─────────────────────────────
    property var emojis: []
    FileView {
        id: emojiFile
        path: launcher.mode === "emoji" || launcher.emojis.length ? "/usr/share/rofi-emoji/all_emojis.txt" : ""
        printErrors: false
        onLoaded: {
            launcher.emojis = text().split("\n").filter(l => l).map(l => {
                const f = l.split("\t");
                return { e: f[0], name: f[3] || "", kw: (f[4] || "") };
            });
        }
    }

    // ── clipboard history ────────────────────────────────────────────
    property var clips: []
    Process {
        id: clipList
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: launcher.clips = text.split("\n").filter(l => l).slice(0, 300).map(l => {
                const i = l.indexOf("\t");
                return { line: l, text: l.slice(i + 1) };
            })
        }
    }

    // ── results ──────────────────────────────────────────────────────
    function score(hay, q) {
        hay = (hay || "").toLowerCase();
        if (!q) return 1;
        if (hay.startsWith(q)) return 100;
        if (hay.indexOf(" " + q) >= 0 || hay.indexOf("-" + q) >= 0) return 60;
        if (hay.indexOf(q) >= 0) return 40;
        // subsequence match ("ffx" → firefox)
        let j = 0;
        for (let i = 0; i < hay.length && j < q.length; i++) if (hay[i] === q[j]) j++;
        return j === q.length ? 10 : 0;
    }

    readonly property var results: {
        const q = query.trim().toLowerCase();
        if (mode === "apps") {
            const out = [];
            for (const a of DesktopEntries.applications.values) {
                if (a.noDisplay) continue;
                const s = Math.max(score(a.name, q), 0.6 * score(a.genericName, q), 0.5 * score((a.keywords || []).join(" "), q), 0.3 * score(a.comment, q));
                if (s > 0) out.push({ entry: a, s: s + Math.min(30, (usage[a.id] || 0) * 2), title: a.name, sub: a.genericName || a.comment || "", icon: a.icon });
            }
            out.sort((x, y) => y.s - x.s || x.title.localeCompare(y.title));
            return out.slice(0, 60);
        }
        if (mode === "emoji") {
            const out = [];
            for (const e of emojis) {
                const s = q ? Math.max(score(e.name, q), 0.6 * score(e.kw, q)) : 1;
                if (s > 0) out.push({ emoji: e.e, s: s, title: e.name, sub: e.kw.replace(/ \| /g, " · ") });
                if (!q && out.length >= 120) break;
            }
            out.sort((x, y) => y.s - x.s);
            return out.slice(0, 120);
        }
        return clips.filter(c => !q || c.text.toLowerCase().indexOf(q) >= 0).slice(0, 120)
                    .map(c => ({ clip: c.line, title: c.text, sub: "" }));
    }

    function run(i) {
        const r = results[i];
        if (!r) return;
        Actions.launcherMode = "";
        if (r.entry) { bump(r.entry.id); r.entry.execute(); }
        else if (r.emoji) Quickshell.execDetached(["wl-copy", r.emoji]);
        else if (r.clip) Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "_", r.clip]);
    }
    function cycle(d) {
        const i = modes.indexOf(mode);
        Actions.launcherMode = modes[(i + d + modes.length) % modes.length];
    }

    Rectangle {
        id: box
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.18
        width: 600
        height: 470
        radius: Theme.radius * 1.2
        color: Theme.rich ? Theme.alpha(Theme.s1, 0.92) : Theme.s1
        border.width: 1
        border.color: Theme.line
        MouseArea { anchors.fill: parent }   // swallow clicks so the backdrop doesn't close us

        Column {
            anchors { fill: parent; margins: 14 }
            spacing: 10

            // mode tabs
            Row {
                spacing: 6
                Repeater {
                    model: launcher.modes
                    delegate: ChipButton {
                        required property string modelData
                        text: modelData
                        accent: launcher.mode === modelData
                        onClicked: Actions.launcherMode = modelData
                    }
                }
                Label { text: "  tab ↹ to switch"; color: Theme.dim; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
            }

            // search field
            Rectangle {
                width: parent.width
                height: 42
                radius: Theme.radius
                color: Theme.s2
                border.width: 1
                border.color: search.activeFocus ? Theme.a1 : Theme.line
                Label {
                    id: prompt
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "❯"
                    color: Theme.a1
                    font.bold: true
                }
                TextInput {
                    id: search
                    anchors { left: prompt.right; leftMargin: 10; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 14
                    selectionColor: Theme.a1
                    selectedTextColor: Theme.bg
                    clip: true
                    onTextChanged: { launcher.query = text; launcher.current = 0; }
                    Keys.onDownPressed: launcher.current = Math.min(launcher.results.length - 1, launcher.current + 1)
                    Keys.onUpPressed: launcher.current = Math.max(0, launcher.current - 1)
                    Keys.onTabPressed: launcher.cycle(1)
                    Keys.onBacktabPressed: launcher.cycle(-1)
                    Keys.onReturnPressed: launcher.run(launcher.current)
                    Keys.onEnterPressed: launcher.run(launcher.current)
                    Keys.onEscapePressed: Actions.launcherMode = ""
                    Label {
                        visible: search.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: launcher.mode === "apps" ? "search apps" : launcher.mode === "emoji" ? "search emoji (copies to clipboard)" : "search clipboard history"
                        color: Theme.dim
                        font.pixelSize: 14
                    }
                }
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - 42 - 24 - 20
                clip: true
                model: launcher.results
                currentIndex: launcher.current
                highlightMoveDuration: Theme.dur(120)
                boundsBehavior: Flickable.StopAtBounds
                highlight: Rectangle {
                    radius: Theme.radius * 0.8
                    color: Theme.alpha(Theme.a1, 0.12)
                    border.width: 1
                    border.color: Theme.alpha(Theme.a1, 0.5)
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width
                    height: 44

                    Row {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 12

                        Item {
                            width: 26; height: 26
                            anchors.verticalCenter: parent.verticalCenter
                            IconImage {
                                anchors.fill: parent
                                visible: !!row.modelData.entry
                                source: row.modelData.entry ? Quickshell.iconPath(row.modelData.icon, "application-x-executable") : ""
                                asynchronous: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !!row.modelData.emoji
                                text: row.modelData.emoji || ""
                                font.pixelSize: 22
                                font.family: "Noto Color Emoji"
                            }
                            Label {
                                anchors.centerIn: parent
                                visible: !!row.modelData.clip
                                text: String.fromCodePoint(0xF0147)
                                color: Theme.dim
                                font.pixelSize: 16
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 26 - 12
                            Label {
                                width: parent.width
                                elide: Text.ElideRight
                                text: row.modelData.title
                                color: row.index === launcher.current ? Theme.a1 : Theme.fg
                                font.pixelSize: 13
                                maximumLineCount: 1
                            }
                            Label {
                                width: parent.width
                                visible: text.length > 0
                                elide: Text.ElideRight
                                text: row.modelData.sub
                                color: Theme.dim
                                font.pixelSize: 10
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: launcher.current = row.index
                        onClicked: launcher.run(row.index)
                    }
                }

                Label {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: launcher.mode === "clipboard" && launcher.clips.length === 0 ? "clipboard history is empty" : "no matches"
                    color: Theme.dim
                }
            }
        }
    }
}
