pragma ComponentBehavior: Bound

// Control center (replaces swaync's panel): toggles, sliders, media, notifications.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.services
import qs.components

Overlay {
    id: cc
    shown: Actions.controlCenterOpen
    fullHeight: true
    panelWidth: 390
    onDismissed: Actions.controlCenterOpen = false
    requestedCorner: Actions.openCorner
    panelHovered: panelHover.hovered

    readonly property string home: Theme.home
    readonly property var toggles: [
        { label: "Wi-Fi",       glyph: 0xF05A9, state: "[ \"$(nmcli radio wifi)\" = enabled ]",            on: "nmcli radio wifi on",                 off: "nmcli radio wifi off" },
        { label: "Bluetooth",   glyph: 0xF00AF, state: "bluetoothctl show | grep -q 'Powered: yes'",        on: "bluetoothctl power on",               off: "bluetoothctl power off" },
        { label: "Mic muted",   glyph: 0xF036D, state: "wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED", on: "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1", off: "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0" },
        { label: "Keep awake",  glyph: 0xF0176, state: "[ \"$(~/.local/bin/sigil-keepawake state)\" = true ]", on: "~/.local/bin/sigil-keepawake on", off: "~/.local/bin/sigil-keepawake off" },
        { label: "Night light", glyph: 0xF0594, state: "[ \"$(~/.local/bin/sigil-nightlight state)\" = true ]", on: "~/.local/bin/sigil-nightlight on", off: "~/.local/bin/sigil-nightlight off" },
        { label: "Performance", glyph: 0xF140B, state: "[ \"$(powerprofilesctl get)\" = performance ]",     on: "powerprofilesctl set performance",    off: "powerprofilesctl set power-saver" },
        { label: "Key sounds",  glyph: 0xF030C, state: "[ \"$(~/.config/keysound/keysound.sh state)\" = true ]", on: "~/.config/keysound/keysound.sh start", off: "~/.config/keysound/keysound.sh stop" },
        { label: "Ultra saver", glyph: 0xF032A, state: "[ \"$(~/.local/bin/ultra state)\" = true ]",        on: "setsid -f ~/.local/bin/ultra on",      off: "setsid -f ~/.local/bin/ultra off" }
    ]

    SystemClock { id: clock; precision: SystemClock.Minutes }
    FileView { id: uptimeFile; path: "/proc/uptime" }
    FileView { id: hostFile; path: "/etc/hostname" }
    readonly property string uptime: {
        clock.date;   // re-evaluate every minute
        const s = parseFloat((uptimeFile.text() || "0").split(" ")[0]);
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        return "up " + (h > 0 ? h + "h " : "") + m + "m";
    }
    onShownChanged: if (shown) { uptimeFile.reload(); panel.forceActiveFocus(); }

    Rectangle {
        id: panel
        anchors.fill: parent
        color: "transparent"      // Overlay draws the side-sheet background
        focus: true
        Keys.onEscapePressed: Actions.controlCenterOpen = false
        MouseArea { anchors.fill: parent }
        HoverHandler { id: panelHover }

        Column {
            id: top
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 12

            // header
            Item {
                width: parent.width
                height: 34
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Label { text: (Quickshell.env("USER") || "") + "@" + (hostFile.text() || "").trim(); font.bold: true }
                    Label { text: Qt.formatDate(clock.date, "ddd d MMM") + " · " + cc.uptime; color: Theme.dim; font.pixelSize: 10 }
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Repeater {
                        model: [
                            { g: 0xF0147, act: "clipboard", tip: "clipboard" },
                            { g: 0xF0493, act: "settings",  tip: "settings" },
                            { g: 0xF033E, act: "lock",      tip: "lock" },
                            { g: 0x23FB,  act: "power",     tip: "power" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 30; height: 30
                            radius: Theme.radius * 0.7
                            color: hov.hovered ? Theme.alpha(Theme.a1, 0.15) : Theme.s2
                            Label {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(parent.modelData.g)
                                font.pixelSize: 14
                                color: parent.modelData.act === "power" ? Theme.crit : Theme.fg
                            }
                            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { Actions.sound("click"); Actions.run(parent.modelData.act); } }
                        }
                    }
                }
            }

            // toggle grid
            Grid {
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                Repeater {
                    model: cc.toggles
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        property bool on: false
                        property bool busy: false
                        width: (top.width - 8) / 2
                        height: 44
                        radius: Theme.radius * 0.8
                        color: on ? Theme.alpha(Theme.a1, 0.16) : Theme.s2
                        border.width: 1
                        border.color: on ? Theme.alpha(Theme.a1, 0.5) : "transparent"
                        opacity: busy ? 0.6 : 1
                        Behavior on color { ColorAnimation { duration: Theme.dur(160) } }

                        Process {
                            id: probe
                            command: ["sh", "-c", tile.modelData.state]
                            onExited: (code) => { tile.on = code === 0; tile.busy = false; }
                        }
                        Process {
                            id: setter
                            onExited: probe.running = true
                        }
                        Connections {
                            target: cc
                            function onShownChanged() { if (cc.shown) probe.running = true; }
                        }
                        Component.onCompleted: probe.running = true

                        Row {
                            anchors { fill: parent; leftMargin: 12 }
                            spacing: 10
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCodePoint(tile.modelData.glyph)
                                font.pixelSize: 16
                                color: tile.on ? Theme.a1 : Theme.dim
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tile.modelData.label
                                color: tile.on ? Theme.fg : Theme.dim
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (tile.busy) return;
                                tile.busy = true;
                                tile.on = !tile.on;
                                Actions.sound(tile.on ? "toggle-on" : "toggle-off");
                                setter.command = ["sh", "-c", tile.on ? tile.modelData.on : tile.modelData.off];
                                setter.running = true;
                            }
                        }
                    }
                }
            }

            // sliders
            SliderRow {
                width: parent.width
                glyph: Audio.icon(Audio.volume, Audio.muted)
                value: Audio.volume
                dimmed: Audio.muted
                onMoved: (v) => Audio.setVolume(v)
                onIconClicked: Audio.toggleMute()
            }
            SliderRow {
                width: parent.width
                visible: Brightness.available
                glyph: String.fromCodePoint(0xF00E0)
                tint: Theme.a2
                value: Brightness.value
                onMoved: (v) => Brightness.set(v)
            }

            // media
            Rectangle {
                id: media
                readonly property var player: Players.active
                visible: player !== null
                width: parent.width
                height: 64
                radius: Theme.radius * 0.8
                color: Theme.s2
                Row {
                    anchors { fill: parent; margins: 8 }
                    spacing: 10
                    Rectangle {
                        width: 48; height: 48
                        radius: Theme.radius * 0.5
                        color: Theme.s1
                        clip: true
                        Image { anchors.fill: parent; source: media.player ? (media.player.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 48 - 10 - 90
                        Label { width: parent.width; elide: Text.ElideRight; text: media.player ? (media.player.trackTitle || media.player.identity) : ""; font.bold: true }
                        Label { width: parent.width; elide: Text.ElideRight; text: media.player ? (media.player.trackArtist || "") : ""; color: Theme.dim; font.pixelSize: 11 }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Label { text: String.fromCodePoint(0xF04AE); font.pixelSize: 16; MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: if (media.player && media.player.canGoPrevious) media.player.previous() } }
                        Label { text: String.fromCodePoint(media.player && media.player.isPlaying ? 0xF03E4 : 0xF040A); color: Theme.a1; font.pixelSize: 18; MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: if (media.player && media.player.canTogglePlaying) media.player.togglePlaying() } }
                        Label { text: String.fromCodePoint(0xF04AD); font.pixelSize: 16; MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: if (media.player && media.player.canGoNext) media.player.next() } }
                    }
                }
            }

            // notifications header
            Item {
                width: parent.width
                height: 24
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "NOTIFICATIONS" + (Notifs.count ? " · " + Notifs.count : "") + (Notifs.historyGroups.length > 1 ? "  /  " + Notifs.historyGroups.length + " APPS" : "")
                    color: Theme.dim
                    font.pixelSize: 10
                    font.letterSpacing: 1.4
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    ChipButton { text: Notifs.dnd ? "do not disturb: on" : "do not disturb"; accent: Notifs.dnd; onClicked: Notifs.dnd = !Notifs.dnd }
                    ChipButton { text: "clear"; visible: Notifs.count > 0; onClicked: Notifs.clearAll() }
                }
            }
        }

        ListView {
            id: hist
            anchors { left: parent.left; right: parent.right; top: top.bottom; bottom: parent.bottom; margins: 14; topMargin: 8 }
            clip: true
            spacing: 8
            model: Notifs.historyGroups
            boundsBehavior: Flickable.StopAtBounds
            // expanded groups survive the model being rebuilt
            property var open: ({})
            delegate: NotificationGroup {
                required property var modelData
                items: modelData.items
                width: ListView.view.width
                expanded: !!hist.open[modelData.key] && modelData.items.length > 1
                onExpandedChanged: {
                    const o = Object.assign({}, hist.open);
                    if (expanded) o[modelData.key] = true; else delete o[modelData.key];
                    hist.open = o;
                }
                onDismissGroup: Notifs.dismissAll(modelData.items)
                onDismissOne: (n) => Notifs.dismiss(n)
            }
            Label {
                anchors.centerIn: parent
                visible: Notifs.count === 0
                text: "all clear"
                color: Theme.dim
            }
        }
    }
}
