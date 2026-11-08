pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool ready: sink !== null && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : false
    readonly property bool micMuted: source !== null && source.audio !== null ? source.audio.muted : false

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }

    function setVolume(v) { if (ready) sink.audio.volume = Math.max(0, Math.min(1, v)); }
    function toggleMute() { if (ready) sink.audio.muted = !sink.audio.muted; }
    function toggleMic() { if (source && source.audio) source.audio.muted = !source.audio.muted; }

    function icon(vol, mute) {
        const g = cp => String.fromCodePoint(cp);
        if (mute) return g(0xF075F);
        return g(vol > 0.6 ? 0xF057E : vol > 0.25 ? 0xF0580 : 0xF057F);
    }
}
