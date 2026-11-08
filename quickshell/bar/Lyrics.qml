pragma ComponentBehavior: Bound

// Current lyric line in the bar, visible whenever the playing track has synced lyrics.
// Data comes from the same script waybar used (~/.config/waybar/scripts/lyrics.py:
// LRCLIB lookup, cache in ~/.cache/waybar-lyrics, one JSON line per second).
// The script only runs while an MPRIS player exists.
// Click: play/pause · scroll: next/previous · hidden with settings.json → bar.lyrics = false

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.services
import qs.components

Item {
    id: root

    readonly property bool enabled_: Theme.barLyrics
    readonly property bool hasPlayer: Mpris.players.values.length > 0
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null

    property string line: ""        // current lyric (StyledText: escaped, <i> when paused)
    property string kind: "none"     // synced | paused | plain | none
    property string lastLine: ""

    readonly property bool hasLyric: line.length > 0 && kind !== "none" && kind !== "plain"

    // only the lyric line; what is playing lives in the media corner
    visible: enabled_ && hasPlayer && hasLyric
    implicitHeight: 20
    implicitWidth: visible ? Math.min(row.implicitWidth, maxWidth) : 0
    property real maxWidth: 560
    clip: true

    Process {
        id: proc
        running: root.enabled_ && root.hasPlayer
        command: ["python3", "-u", Theme.home + "/.config/waybar/scripts/lyrics.py"]
        stdout: SplitParser {
            onRead: (data) => {
                try {
                    const j = JSON.parse(data);
                    root.kind = j.class || "none";
                    if (j.text !== root.line) { root.lastLine = root.line; root.line = j.text || ""; }
                } catch (e) {}
            }
        }
        onRunningChanged: if (!running) { root.line = ""; root.kind = "none"; }
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Label {
            id: note
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0387)        // music note
            color: root.player && root.player.isPlaying ? Theme.a2 : Theme.dim
            font.pixelSize: 13
        }
        // the lyric line, fades in when it changes
        Label {
            id: lyric
            anchors.verticalCenter: parent.verticalCenter
            visible: root.hasLyric
            width: Math.min(implicitWidth, root.maxWidth - 24)
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: root.line
            color: root.kind === "paused" ? Theme.dim : Theme.a1
            onTextChanged: if (Theme.rich) fadeIn.restart()
            NumberAnimation { id: fadeIn; target: lyric; property: "opacity"; from: 0.15; to: 1; duration: Theme.dur(320); easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.player && root.player.canTogglePlaying) root.player.togglePlaying()
        onWheel: (w) => {
            const p = root.player;
            if (!p) return;
            if (w.angleDelta.y > 0 && p.canGoNext) p.next();
            else if (w.angleDelta.y < 0 && p.canGoPrevious) p.previous();
        }
    }
}
