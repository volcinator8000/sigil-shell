pragma ComponentBehavior: Bound

// Current lyric line in the bar, whenever the playing track has synced lyrics.
// No helper process: track info and position come from MPRIS, lyrics from LRCLIB
// (fetched once per track, cached in ~/.cache/sigil/lyrics/<md5(artist|title|album)>.json),
// and instead of polling, a single-shot timer fires when the next line starts. Seeking,
// pausing or a track change re-syncs it.
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
    readonly property var player: Players.active
    readonly property bool playing: !!(player && player.isPlaying)

    readonly property string artist: player ? (player.trackArtist || "") : ""
    readonly property string title: player ? (player.trackTitle || "") : ""
    readonly property string album: player ? (player.trackAlbum || "") : ""
    readonly property string key: title ? Qt.md5(artist + "|" + title + "|" + album) : ""
    readonly property string cacheDir: Theme.home + "/.cache/sigil/lyrics"

    property var lines: []           // [{ t: seconds, s: text }] for the current track
    property int idx: -1
    readonly property string line: idx >= 0 && idx < lines.length ? (lines[idx].s || "♪") : ""
    readonly property bool hasLyric: lines.length > 0 && idx >= 0

    visible: enabled_ && !!player && hasLyric
    implicitHeight: Theme.bs(20)
    implicitWidth: visible ? Math.min(row.implicitWidth, maxWidth) : 0
    property real maxWidth: 560
    clip: true

    // ── loading ──────────────────────────────────────────────────────
    onKeyChanged: load()
    onEnabled_Changed: load()
    Component.onCompleted: load()

    function parse(synced) {
        const out = [];
        const re = /\[(\d+):(\d+(?:\.\d+)?)\](.*)/g;
        let m;
        while ((m = re.exec(synced || "")) !== null) out.push({ t: parseInt(m[1]) * 60 + parseFloat(m[2]), s: m[3].trim() });
        out.sort((a, b) => a.t - b.t);
        return out;
    }
    function load() {
        lines = []; idx = -1; tick.stop();
        if (!enabled_ || !key) return;
        cache.path = "";
        cache.path = cacheDir + "/" + key + ".json";
    }
    FileView {
        id: cache
        printErrors: false
        blockLoading: false
        onLoaded: {
            try { root.lines = root.parse(JSON.parse(text()).synced); root.resync(); }
            catch (e) { root.fetch(); }
        }
        onLoadFailed: root.fetch()
    }
    FileView { id: writer; printErrors: false }

    function get(url, cb) {
        const x = new XMLHttpRequest();
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            let j = null;
            if (x.status === 200) { try { j = JSON.parse(x.responseText); } catch (e) {} }
            cb(j);
        };
        x.open("GET", url);
        x.setRequestHeader("User-Agent", "sigil-shell (https://github.com/volcinator8000/sigil-shell)");
        x.send();
    }
    function fetch() {
        const k = key, a = artist, t = title, al = album;
        const dur = player && player.lengthSupported ? Math.round(player.length) : 0;
        const q = s => encodeURIComponent(s);
        const save = (d) => {
            if (k !== root.key) return;                       // track changed meanwhile
            const data = { synced: (d && d.syncedLyrics) || "", plain: (d && d.plainLyrics) || "" };
            Quickshell.execDetached(["mkdir", "-p", root.cacheDir]);
            writer.path = root.cacheDir + "/" + k + ".json";
            Qt.callLater(() => writer.setText(JSON.stringify(data)));
            root.lines = root.parse(data.synced);
            root.resync();
        };
        get("https://lrclib.net/api/get?artist_name=" + q(a) + "&track_name=" + q(t) + "&album_name=" + q(al) + "&duration=" + dur, d => {
            if (d && (d.syncedLyrics || d.plainLyrics)) { save(d); return; }
            get("https://lrclib.net/api/search?artist_name=" + q(a) + "&track_name=" + q(t), res => {
                const list = Array.isArray(res) ? res : [];
                save(list.find(x => x.syncedLyrics) || list[0] || null);
            });
        });
    }

    // ── timing ───────────────────────────────────────────────────────
    property bool reading: false
    function position() {
        if (!player) return 0;
        reading = true;
        player.positionChanged();                             // refresh the estimate from MPRIS
        reading = false;
        return player.position;
    }
    // pick the line for the current position, then sleep until the next one starts
    function resync() {
        tick.stop();
        if (!lines.length || !player) { idx = -1; return; }
        const pos = position() + 0.3;
        let lo = 0, hi = lines.length - 1, found = -1;
        while (lo <= hi) { const mid = (lo + hi) >> 1; if (lines[mid].t <= pos) { found = mid; lo = mid + 1; } else hi = mid - 1; }
        idx = found;
        if (!playing || found + 1 >= lines.length) return;
        const wait = (lines[found + 1].t - pos) / Math.max(0.1, player.rate || 1);
        tick.interval = Math.max(80, Math.min(15000, Math.round(wait * 1000) + 20));
        tick.start();
    }
    Timer { id: tick; onTriggered: root.resync() }
    Connections {
        target: root.player
        // MPRIS seeks arrive as a position change (our own refreshes are ignored)
        function onPositionChanged() { if (!root.reading) root.resync(); }
        function onIsPlayingChanged() { root.resync(); }
        function onRateChanged() { root.resync(); }
    }
    onPlayerChanged: resync()

    // ── view ─────────────────────────────────────────────────────────
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.bs(8)

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF0387)        // music note
            color: root.playing ? Theme.a2 : Theme.dim
            font.pixelSize: Theme.bs(13)
        }
        // the lyric line, fades in when it changes
        Label {
            id: lyric
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.maxWidth - 24)
            elide: Text.ElideRight
            font.pixelSize: Theme.bs(12)
            font.italic: !root.playing
            text: root.line
            color: root.playing ? Theme.a1 : Theme.dim
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
