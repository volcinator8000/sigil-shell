pragma ComponentBehavior: Bound

// Volume / mic / brightness OSD. Reacts to the actual state (Pipewire, udev
// backlight events), so it shows whatever changed it: keys, apps, scripts.

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

PanelWindow {
    id: osd

    property string kind: "volume"     // volume | mic | brightness
    property bool shown: false
    property bool armed: false          // ignore the initial values at startup

    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor !== null && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    visible: shown || fade.running
    anchors.bottom: true
    margins.bottom: 64
    implicitWidth: 260
    implicitHeight: 44
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "sigil-panel"
    mask: Region {}                     // never takes input

    function show(k) {
        if (!armed || Lock.locked) return;
        kind = k;
        shown = true;
        hideTimer.restart();
    }
    Timer { interval: 1500; running: true; onTriggered: osd.armed = true }
    Timer { id: hideTimer; interval: 1400; onTriggered: osd.shown = false }

    Connections {
        target: Audio
        function onVolumeChanged() { osd.show("volume"); }
        function onMutedChanged() { osd.show("volume"); }
        function onMicMutedChanged() { osd.show("mic"); }
    }
    Connections {
        target: Brightness
        function onChangedExternally() { osd.show("brightness"); }
    }

    readonly property real level: kind === "volume" ? Audio.volume : kind === "brightness" ? Brightness.value : (Audio.micMuted ? 0 : 1)
    readonly property bool off: kind === "volume" ? Audio.muted : kind === "mic" ? Audio.micMuted : false

    Rectangle {
        anchors.fill: parent
        radius: Math.min(Theme.radius * 1.4, height / 2)
        color: Theme.rich ? Theme.alpha(Theme.s1, 0.85) : Theme.s1
        border.width: 1
        border.color: Theme.line
        opacity: osd.shown ? 1 : 0
        scale: osd.shown ? 1 : 0.92
        Behavior on opacity { NumberAnimation { id: fade; duration: Theme.dur(160) } }
        Behavior on scale { NumberAnimation { duration: Theme.dur(220); easing.type: Easing.OutBack } }

        Row {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
            spacing: 12

            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                font.pixelSize: 17
                color: osd.off ? Theme.dim : Theme.a1
                text: osd.kind === "volume" ? Audio.icon(Audio.volume, Audio.muted)
                    : osd.kind === "mic" ? String.fromCodePoint(Audio.micMuted ? 0xF036D : 0xF036C)
                    : String.fromCodePoint(0xF00E0)
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 20 - 40 - 24
                height: 6
                radius: 3
                color: Theme.s2
                Rectangle {
                    height: parent.height
                    radius: 3
                    width: parent.width * Math.min(1, osd.level)
                    color: osd.off ? Theme.dim : Theme.a1
                    Behavior on width { NumberAnimation { duration: Theme.dur(120) } }
                }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                horizontalAlignment: Text.AlignRight
                text: osd.kind === "mic" ? (Audio.micMuted ? "off" : "on") : Math.round(osd.level * 100) + "%"
                color: osd.off ? Theme.dim : Theme.fg
            }
        }
    }
}
