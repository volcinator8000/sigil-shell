pragma Singleton
pragma ComponentBehavior: Bound

// The media player the shell talks about: the one playing, else the one that played most
// recently (like playerctld). At start-up the recency comes from playerctld itself, asked
// once; after that every play is tracked here, so nothing polls.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    readonly property var list: Mpris.players.values
    property var lastActive: null
    property string hint: ""            // player bus name suffix playerctld reported at start

    readonly property var active: {
        const ps = list;
        return ps.find(p => p.isPlaying)
            || (lastActive && ps.indexOf(lastActive) >= 0 ? lastActive : null)
            || (hint ? ps.find(p => root.matches(p, hint)) : null)
            || ps.find(p => p.trackTitle)
            || ps[0] || null;
    }

    // hint = "org.mpris.MediaPlayer2.spotify" / "...firefox.instance_1_506"
    function matches(p, name) {
        if (p.dbusName && p.dbusName === name) return true;
        const app = name.replace("org.mpris.MediaPlayer2.", "").split(".")[0].toLowerCase();
        return (p.identity || "").toLowerCase().includes(app) || (p.desktopEntry || "").toLowerCase().includes(app);
    }

    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onIsPlayingChanged() { if (modelData.isPlaying) root.lastActive = modelData; }
        }
    }

    Process {
        running: true
        // playerctld keeps players most-recent first
        command: ["timeout", "2", "busctl", "--user", "get-property", "org.mpris.MediaPlayer2.playerctld",
                  "/org/mpris/MediaPlayer2", "com.github.altdesktop.playerctld", "PlayerNames"]
        stdout: StdioCollector { onStreamFinished: { const m = text.match(/"([^"]+)"/); root.hint = m ? m[1] : ""; } }
    }
}
