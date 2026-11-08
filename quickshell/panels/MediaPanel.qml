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

    readonly property var player: {
        const ps = Mpris.players.values;
        return ps.find(p => p.isPlaying) || ps.find(p => p.identity === "Spotify") || ps[0] || null;
    }

    property real openness: Actions.mediaOpen ? 1 : 0
    Behavior on openness { NumberAnimation { duration: Actions.mediaOpen ? Theme.dur(220) : Theme.dur(150); easing.type: Actions.mediaOpen ? Easing.OutCubic : Easing.InCubic } }
    visible: Actions.mediaOpen || openness > 0.001
    anchors { top: atTop; bottom: !atTop; left: atLeft; right: !atLeft }
    margins { top: atTop ? Theme.bs(30) + 14 : 0; bottom: atTop ? 0 : 10; left: atLeft ? 10 : 0; right: atLeft ? 0 : 10 }
    implicitWidth: 320
    implicitHeight: 110
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

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.rich ? Theme.alpha(Theme.s1, 0.86) : Theme.s1
        border.width: 1
        border.color: Theme.line

        opacity: panel.openness
        scale: 0.9 + 0.1 * panel.openness
        transformOrigin: panel.atTop ? (panel.atLeft ? Item.TopLeft : Item.TopRight) : (panel.atLeft ? Item.BottomLeft : Item.BottomRight)

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
