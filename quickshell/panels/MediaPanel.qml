pragma ComponentBehavior: Bound

// Now-playing card that pops out of whichever corner triggered it.
// Closes when the pointer leaves it, or after 4 s if it is never entered.
// It also peeks out of the corner mapped to "media" when the track changes
// (Theme.trackPopup: spotify | all | off), then tucks back after a few seconds;
// hovering it during a peek keeps it out until the pointer leaves.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.services
import qs.components

PanelWindow {
    id: panel
    readonly property string corner: Actions.mediaOpen ? Actions.mediaCorner : peekCorner
    readonly property bool atTop: corner.startsWith("top")
    readonly property bool atLeft: corner.endsWith("Left")

    readonly property var player: Players.active

    // ── track-change peek ─────────────────────────────────────────────
    property bool peeking: false
    property string peekCorner: "bottomLeft"
    readonly property bool shown: Actions.mediaOpen || peeking
    readonly property bool peekOnly: peeking && !Actions.mediaOpen

    readonly property string trackKey: player ? (player.trackTitle || "") + "\u0001" + (player.trackArtist || "") : ""
    property string lastKey: ""
    property bool primed: false     // players announce their current track at start-up: not a change
    Timer { running: true; interval: 3000; onTriggered: panel.primed = true }
    // metadata arrives in pieces (title, then artist, then art): let it settle first
    onTrackKeyChanged: { settle.restart(); if (openness > 0.99) swapIn.restart(); }
    Timer { id: settle; interval: 350; onTriggered: panel.maybePeek() }
    Timer { id: peekTimer; interval: 4500; onTriggered: if (!panel.entered) panel.peeking = false }

    function maybePeek() {
        const k = trackKey, prev = lastKey;
        lastKey = k;
        const p = player;
        if (!primed || !p || !p.trackTitle || k === prev) return;
        if (Theme.trackPopup === "off") return;
        if (Theme.trackPopup === "spotify" && !Players.matches(p, "org.mpris.MediaPlayer2.spotify")) return;
        if (!p.isPlaying || Lock.locked || Actions.mediaOpen) return;      // open: the card updates in place
        if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen) return;
        if (Actions.launcherMode || Actions.controlCenterOpen || Actions.powerOpen || Actions.notePath || Actions.eventDate) return;
        if (!peeking) {
            const c = Object.keys(Theme.corners).find(k => Theme.corners[k] === "media");
            peekCorner = c || "bottomLeft";
            entered = false;
        }
        peeking = true;
        peekTimer.restart();
        drainAnim.restart();
    }
    Connections { target: Lock; function onLockedChanged() { if (Lock.locked) panel.peeking = false; } }

    property real openness: shown ? 1 : 0
    Behavior on openness {
        NumberAnimation {
            duration: panel.shown ? Theme.dur(panel.peekOnly ? 520 : 340) : Theme.dur(panel.peekOnly ? 460 : 300)
            easing.type: panel.shown ? Easing.OutQuint : Easing.InOutCubic
        }
    }
    visible: shown || openness > 0.001
    anchors { top: atTop; bottom: !atTop; left: atLeft; right: !atLeft }
    // tucked into the corner, flush with both edges (under the bar at the top)
    readonly property int fillet: Theme.frameRadius
    // reaches the screen edges and covers the frame strip there (Pocket insets its curves)
    readonly property int ix: Theme.frame
    readonly property int iy: atTop ? 0 : Theme.frame
    margins { top: atTop ? Theme.barH : 0 }
    implicitWidth: 320 + fillet + ix
    implicitHeight: 110 + fillet + iy
    mask: Region { item: hitArea }
    readonly property real slideY: (1 - openness) * height * (atTop ? -1 : 1)

    Pocket {
        anchors.fill: parent
        atTop: panel.atTop
        atLeft: panel.atLeft
        fillet: panel.fillet
        transform: Translate { y: panel.slideY }
    }
    Item { id: hitArea; x: card.x; y: card.y; width: card.width; height: card.height }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sigil-panel"

    Connections {
        target: Actions
        function onMediaOpenChanged() {
            if (!Actions.mediaOpen) { panel.peeking = false; return; }
            panel.peekCorner = Actions.mediaCorner;     // stays put while it slides away
            // opened from its corner mid-peek: the pointer is already on the card
            panel.entered = panel.peeking && cardHover.hovered;
            panel.peeking = false;
            autoClose.restart();
        }
    }
    property bool entered: false
    Timer { id: autoClose; interval: 4000; onTriggered: if (!panel.entered) Actions.mediaOpen = false }
    Timer { id: leftCorner; interval: 450; onTriggered: if (!panel.entered && !Actions.cornerInside[panel.corner]) Actions.mediaOpen = false }
    Connections {
        target: Actions
        function onCornerExited(c) { if (Actions.mediaOpen && c === panel.corner) leftCorner.restart(); }
    }

    Item {
        id: card
        x: panel.atLeft ? panel.ix : panel.fillet
        y: panel.atTop ? 0 : panel.fillet
        width: 320
        height: 110
        transform: Translate { y: panel.slideY }

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (hovered) panel.entered = true;
                else if (panel.entered) { Actions.mediaOpen = false; panel.peeking = false; }
            }
        }

        // how long the peek stays out, drained along the card's inner edge
        Rectangle {
            anchors { left: parent.left; leftMargin: 12; top: panel.atTop ? undefined : parent.top; bottom: panel.atTop ? parent.bottom : undefined }
            height: 2
            radius: 1
            color: Theme.a1
            opacity: panel.peekOnly && !panel.entered ? 0.7 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur(200) } }
            width: (parent.width - 24) * drain.value
            QtObject { id: drain; property real value: 1 }
            NumberAnimation {
                id: drainAnim
                target: drain; property: "value"; from: 1; to: 0
                duration: peekTimer.interval
            }
        }

        RowLayout {
            id: content
            anchors { fill: parent; margins: 12 }
            spacing: 12
            // a new track while the card is out slides its details in
            property real shift: 0
            transform: Translate { x: content.shift }
            ParallelAnimation {
                id: swapIn
                NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: Theme.dur(320); easing.type: Easing.OutCubic }
                NumberAnimation { target: content; property: "shift"; from: 14; to: 0; duration: Theme.dur(380); easing.type: Easing.OutQuint }
            }

            Rectangle {
                Layout.preferredWidth: 84
                Layout.preferredHeight: 84
                radius: Theme.radius * 0.8
                color: Theme.s2
                clip: true
                Image {
                    anchors.fill: parent
                    source: panel.player ? (panel.player.trackArtUrl || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 168
                    sourceSize.height: 168
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.bold: true
                    text: panel.player ? (panel.player.trackTitle || "Unknown track") : "Nothing playing"
                }
                Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Theme.dim
                    font.pixelSize: 11
                    text: panel.player ? (panel.player.trackArtist || panel.player.identity) : ""
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    implicitHeight: 4
                    radius: 2
                    color: Theme.s2
                    Rectangle {
                        height: parent.height
                        radius: 2
                        color: Theme.a1
                        width: panel.player && panel.player.lengthSupported && panel.player.length > 0
                               ? parent.width * Math.min(1, panel.player.position / panel.player.length) : 0
                    }
                    // position is not pushed by MPRIS; poll it while visible
                    Timer {
                        running: panel.visible && panel.player !== null && panel.player.isPlaying
                        interval: Theme.rich ? 1000 : 3000
                        repeat: true
                        onTriggered: panel.player.positionChanged()
                    }
                }
                Row {
                    Layout.topMargin: 2
                    spacing: 18
                    Repeater {
                        model: [
                            { g: 0xF04AE, act: "prev" },
                            { g: -1, act: "toggle" },
                            { g: 0xF04AD, act: "next" }
                        ]
                        delegate: Label {
                            required property var modelData
                            font.pixelSize: 16
                            color: modelData.act === "toggle" ? Theme.a1 : Theme.fg
                            text: modelData.g >= 0 ? String.fromCodePoint(modelData.g)
                                 : String.fromCodePoint(panel.player && panel.player.isPlaying ? 0xF03E4 : 0xF040A)
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const p = panel.player;
                                    if (!p) return;
                                    if (parent.modelData.act === "prev" && p.canGoPrevious) p.previous();
                                    else if (parent.modelData.act === "next" && p.canGoNext) p.next();
                                    else if (parent.modelData.act === "toggle" && p.canTogglePlaying) p.togglePlaying();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
