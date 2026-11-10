pragma ComponentBehavior: Bound

// Now-playing card that pops out of whichever corner triggered it.
// Closes when the pointer leaves it, or after 4 s if it is never entered.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs.services
import qs.components

PanelWindow {
    id: panel
    readonly property string corner: Actions.mediaCorner
    readonly property bool atTop: corner.startsWith("top")
    readonly property bool atLeft: corner.endsWith("Left")

    readonly property var player: Players.active

    property real openness: Actions.mediaOpen ? 1 : 0
    Behavior on openness { NumberAnimation { duration: Actions.mediaOpen ? Theme.dur(340) : Theme.dur(300); easing.type: Actions.mediaOpen ? Easing.OutQuint : Easing.InOutCubic } }
    visible: Actions.mediaOpen || openness > 0.001
    anchors { top: atTop; bottom: !atTop; left: atLeft; right: !atLeft }
    // tucked into the corner, flush with both edges (under the bar at the top)
    readonly property int fillet: Theme.radius + 2
    margins { top: atTop ? Theme.bs(30) : 0 }
    implicitWidth: 320 + fillet
    implicitHeight: 110 + fillet
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

    Connections { target: Actions; function onMediaOpenChanged() { if (Actions.mediaOpen) { panel.entered = false; autoClose.restart(); } } }
    property bool entered: false
    Timer { id: autoClose; interval: 4000; onTriggered: if (!panel.entered) Actions.mediaOpen = false }
    Timer { id: leftCorner; interval: 450; onTriggered: if (!panel.entered && !Actions.cornerInside[panel.corner]) Actions.mediaOpen = false }
    Connections {
        target: Actions
        function onCornerExited(c) { if (Actions.mediaOpen && c === panel.corner) leftCorner.restart(); }
    }

    Item {
        id: card
        x: panel.atLeft ? 0 : panel.fillet
        y: panel.atTop ? 0 : panel.fillet
        width: 320
        height: 110
        transform: Translate { y: panel.slideY }

        HoverHandler {
            onHoveredChanged: {
                if (hovered) panel.entered = true;
                else if (panel.entered) Actions.mediaOpen = false;
            }
        }

        RowLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 12

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
