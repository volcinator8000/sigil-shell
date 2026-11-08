pragma ComponentBehavior: Bound

// One wallpaper slot: still image, animated image or muted video. See Wallpaper.qml.
import QtQuick
import QtMultimedia
import qs.services

Item {
    id: slot
    required property var win
    property string path: ""
    readonly property string kind: Wallpapers.kindOf(path)
    // animate only the slot showing (or about to show) the current wallpaper; the outgoing
    // slot drops to its still frame while it fades out
    readonly property bool live: kind !== "image" && Wallpapers.shouldPlay && path === slot.win.path
    readonly property bool ready: loader.item !== null && loader.item.ready === true
    anchors.fill: parent
    opacity: 0
    Behavior on opacity { NumberAnimation { duration: Theme.dur(800); easing.type: Easing.InOutQuad } }
    // swap in once loaded. Checked on every load too: a new item can be ready immediately,
    // in which case `ready` never changes and onReadyChanged alone would miss it.
    function trySwap() { if (ready && path === slot.win.path) slot.win.swap(slot); }
    onReadyChanged: trySwap()
    readonly property string state_: (slot.win.front === slot && ready) ? kind + ":" + (live ? "live" : "still") + ":" + path.split("/").pop() : ""
    onState_Changed: if (state_) Wallpapers.rendered = state_

    Loader {
        id: loader
        anchors.fill: parent
        active: slot.path !== ""
        // the still frame whenever the file is not playing; the decoder is unloaded then
        sourceComponent: !slot.live ? stillComp : slot.kind === "video" ? videoComp : animComp
        onLoaded: Qt.callLater(slot.trySwap)
    }

    Component {
        id: stillComp
        Image {
            readonly property bool ready: status === Image.Ready
            source: slot.kind === "image" ? "file://" + slot.path
                  : (Wallpapers.still && slot.path === Wallpapers.current ? "file://" + Wallpapers.still : "file://" + Wallpapers.stillFor(slot.path))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: slot.win.width
            sourceSize.height: slot.win.height
        }
    }
    Component {
        id: animComp
        AnimatedImage {
            readonly property bool ready: status === AnimatedImage.Ready
            source: "file://" + slot.path
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            playing: true
        }
    }
    Component {
        id: videoComp
        Item {
            id: vid
            property bool ready: false
            MediaPlayer {
                id: player
                source: "file://" + slot.path
                loops: MediaPlayer.Infinite
                videoOutput: out
                // no audioOutput: wallpapers are silent
                onMediaStatusChanged: if (mediaStatus === MediaPlayer.BufferedMedia || mediaStatus === MediaPlayer.LoadedMedia) vid.ready = true
                Component.onCompleted: play()
            }
            VideoOutput {
                id: out
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }
        }
    }
}
