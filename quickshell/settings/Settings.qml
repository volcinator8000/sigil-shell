pragma ComponentBehavior: Bound

// SIGIL // SETTINGS — the Quickshell port of ~/.config/sigil-settings/sigil-settings.py.
// One FloatingWindow, created once and shown/hidden (closing only hides it).
// Pages load lazily on first visit and stay alive, like the GTK app.
//   qs -c sigil ipc call settings toggle
//   qs -c sigil ipc call settings open <page>

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

    readonly property var pages: [
        { name: "shell",     title: "Shell",       glyph: "\u{F03D8}" },
        { name: "widgets",   title: "Widgets",     glyph: "\u{F072C}" },
        { name: "dashboard", title: "Dashboard",   glyph: "\u{F056E}" },
        { name: "wifi",      title: "Wi-Fi",       glyph: "\u{F05A9}" },
        { name: "bluetooth", title: "Bluetooth",   glyph: "\u{F00AF}" },
        { name: "audio",     title: "Audio",       glyph: "\u{F057E}" },
        { name: "sounds",    title: "Sound theme", glyph: "\u{F0387}" },
        { name: "power",     title: "Power",       glyph: "\u{F0079}" },
        { name: "desktop",   title: "Desktop",     glyph: "\u{F02E9}" },
        { name: "snapshots", title: "Snapshots",   glyph: "\u{F02DA}" },
        { name: "input",     title: "Input",       glyph: "\u{F030C}" },
        { name: "tablet",    title: "Tablet",      glyph: "\u{F03FA}" },
        { name: "about",     title: "About",       glyph: "\u{F02FC}" }
    ]
    property string current: "shell"
    property bool shown: false

    function indexOf(name) { return pages.findIndex(p => p.name === name); }

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
        if (indexOf(name) < 0) return false;
        const fresh = current !== name;
        current = name;
        if (!fresh || win.visible) refreshCurrent();
        return true;
    }
    function refreshCurrent() {
        const l = loaders.itemAt(indexOf(current));
        if (l && l.item && typeof l.item.refresh === "function") l.item.refresh();
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
    }

    FloatingWindow {
        id: win
        title: "sigil-settings"
        visible: false
        implicitWidth: 980
        implicitHeight: 640
        minimumSize: Qt.size(720, 460)
        color: Theme.bg
        // the compositor closing the window only hides it
        onVisibleChanged: if (!visible && root.shown) { root.shown = false; Sh.snd("close"); }

        Item {
            id: content
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.hide()

            // ── sidebar ──────────────────────────────────────────────
            Rectangle {
                id: sidebar
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: 200
                color: Theme.s1
                Rectangle { anchors { top: parent.top; bottom: parent.bottom; right: parent.right } width: 1; color: Theme.line }

                Label {
                    id: brand
                    anchors { top: parent.top; left: parent.left; topMargin: 18; leftMargin: 20 }
                    text: "SIGIL // SETTINGS"
                    color: Theme.a1
                    font.pixelSize: 11
                    font.letterSpacing: 2.4
                }

                Column {
                    anchors { top: brand.bottom; topMargin: 14; left: parent.left; right: parent.right }
                    spacing: 2
                    Repeater {
                        model: root.pages
                        delegate: Item {
                            id: navRow
                            required property var modelData
                            readonly property bool active: root.current === modelData.name
                            width: parent.width
                            height: 34

                            Rectangle {
                                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                radius: Math.min(Theme.radius * 0.6, 8)
                                color: navRow.active ? Theme.alpha(Theme.a1, 0.08) : navMouse.containsMouse ? Theme.alpha(Theme.fg, 0.04) : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.dur(120) } }
                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 6; bottomMargin: 6 }
                                    width: 2
                                    color: Theme.a1
                                    opacity: navRow.active ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Theme.dur(160) } }
                                }
                                Row {
                                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
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
                                        font.letterSpacing: 0.6
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

            // ── header ───────────────────────────────────────────────
            Item {
                id: header
                anchors { top: parent.top; left: sidebar.right; right: parent.right }
                height: 48
                Label {
                    anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                    text: (root.pages[root.indexOf(root.current)] || { title: "" }).title.toUpperCase()
                    font.pixelSize: 13
                    font.letterSpacing: 1.6
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
                        active: visited
                        visible: isCurrent
                        opacity: isCurrent ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.dur(140) } }
                        asynchronous: false
                        source: "pages/" + modelData.name.charAt(0).toUpperCase() + modelData.name.slice(1) + "Page.qml"
                        // pages read `pageActive` to pause timers while hidden
                        onLoaded: item.pageActive = Qt.binding(() => pageLoader.isCurrent && root.shown)
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
