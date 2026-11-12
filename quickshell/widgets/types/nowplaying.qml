pragma ComponentBehavior: Bound

// Now playing (MPRIS, the same player the bar and media panel follow: services/Players.qml).
// Art, title / artist, progress, prev · play/pause · next. Taller = bigger art on top.
import QtQuick
import qs.services
import qs.components

Item {
    id: root
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }
    readonly property int w: Math.max(240, entry.w || 300)
    readonly property var p: Players.active
    readonly property bool has: p !== null && (p.trackTitle || "") !== ""
    // a tall widget puts the art above the text, full width
    readonly property bool stacked: (entry.h || 0) >= w * 0.9
    readonly property int art: o("art") === false ? 0 : stacked ? w : 76
    opacity: !has && o("hideIdle") && !Widgets.editing ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: Theme.dur(300) } }

    implicitWidth: w
    implicitHeight: stacked ? art + 10 + info.implicitHeight : Math.max(art, info.implicitHeight)

    WidgetHeader { title: "now playing"; detail: root.p ? (root.p.identity || "").toLowerCase() : "" }

    function fmt(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
    // position is not pushed by MPRIS; poll it while playing and in view
    Timer {
        running: root.p !== null && root.p.isPlaying && Widgets.desktopVisible
        interval: Theme.rich ? 1000 : 3000
        repeat: true
        onTriggered: root.p.positionChanged()
    }

    Rectangle {
        id: artBox
        visible: root.art > 0
        width: root.art
        height: root.art
        radius: Theme.radius * 0.7
        color: Theme.alpha(Theme.fg, 0.06)
        clip: true
        WLabel {
            anchors.centerIn: parent
            text: String.fromCodePoint(0xF075A)
            font.pixelSize: root.art * 0.4
            color: Theme.widgetDim
            visible: cover.status !== Image.Ready
        }
        Image {
            id: cover
            anchors.fill: parent
            source: root.p ? (root.p.trackArtUrl || "") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: root.art * 2
            sourceSize.height: root.art * 2
        }
    }

    Column {
        id: info
        x: root.stacked || root.art === 0 ? 0 : root.art + 14
        y: root.stacked ? root.art + 10 : Math.max(0, (root.art - implicitHeight) / 2)
        width: root.w - x
        spacing: 3

        WLabel {
            width: parent.width
            elide: Text.ElideRight
            text: root.has ? root.p.trackTitle : "Nothing playing"
            font.pixelSize: 15
            font.bold: true
            color: root.has ? Theme.fg : Theme.widgetDim
        }
        WLabel {
            width: parent.width
            visible: root.has
            elide: Text.ElideRight
            text: root.has ? [root.p.trackArtist, root.o("album") !== false ? root.p.trackAlbum : ""].filter(x => x).join("  ·  ") : ""
            color: Theme.widgetDim
            font.pixelSize: 12
        }
        Item { width: 1; height: 4 }
        // progress
        Item {
            width: parent.width
            height: 14
            visible: root.has && root.p.lengthSupported && root.p.length > 0
            Rectangle {
                id: bar
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                height: 4; radius: 2
                color: Theme.alpha(Theme.fg, 0.12)
                Rectangle {
                    height: parent.height; radius: 2
                    color: Theme.a1
                    width: root.has && root.p.length > 0 ? parent.width * Math.min(1, root.p.position / root.p.length) : 0
                }
            }
            TapHandler {
                enabled: !Widgets.editing && root.has && root.p.canSeek
                onTapped: ev => root.p.position = root.p.length * Math.max(0, Math.min(1, ev.position.x / bar.width))
            }
        }
        Item {
            width: parent.width
            height: 26
            visible: root.has || root.p !== null
            WLabel {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.has && root.p.lengthSupported && root.p.length > 0
                text: root.has ? root.fmt(root.p.position) + " / " + root.fmt(root.p.length) : ""
                color: Theme.widgetDim
                font.pixelSize: 11
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 14
                Repeater {
                    model: ["prev", "toggle", "next"]
                    delegate: WLabel {
                        id: btn
                        required property string modelData
                        font.pixelSize: modelData === "toggle" ? 22 : 17
                        color: bh.hovered ? Theme.a1 : modelData === "toggle" ? Theme.fg : Theme.widgetDim
                        text: String.fromCodePoint(modelData === "prev" ? 0xF04AE : modelData === "next" ? 0xF04AD
                                                  : root.p && root.p.isPlaying ? 0xF03E4 : 0xF040A)
                        HoverHandler { id: bh; enabled: !Widgets.editing; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            enabled: !Widgets.editing
                            onTapped: {
                                const p = root.p;
                                if (!p) return;
                                if (btn.modelData === "prev" && p.canGoPrevious) p.previous();
                                else if (btn.modelData === "next" && p.canGoNext) p.next();
                                else if (btn.modelData === "toggle" && p.canTogglePlaying) p.togglePlaying();
                            }
                        }
                    }
                }
            }
        }
    }
}
