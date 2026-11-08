pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.services
import qs.components

Row {
    id: root
    spacing: Theme.bs(12)

    function g(cp) { return String.fromCodePoint(cp); }

    // ── network ──────────────────────────────────────────────────────
    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wiredDev: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) || null
    readonly property var wifiNet: wifiDev ? (wifiDev.networks.values.find(n => n.connected) || null) : null

    Label {
        id: net
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: Theme.bs(14)
        color: (root.wiredDev || root.wifiNet) ? Theme.fg : Theme.dim
        text: {
            if (root.wiredDev) return root.g(0xF0200);                  // ethernet
            if (!root.wifiNet) return root.g(0xF092D);                  // wifi off
            const s = root.wifiNet.signalStrength;                       // 0..1
            return root.g(s > 0.75 ? 0xF0928 : s > 0.5 ? 0xF0925 : s > 0.25 ? 0xF0922 : 0xF091F);
        }
        MouseArea {
            id: netHover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: Quickshell.execDetached(["nm-connection-editor"])
        }
    }

    // ── volume ───────────────────────────────────────────────────────
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    Label {
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: Theme.bs(14)
        color: root.muted ? Theme.dim : Theme.fg
        text: root.muted ? root.g(0xF075F) : root.g(root.volume > 0.6 ? 0xF057E : root.volume > 0.25 ? 0xF0580 : 0xF057F)
        MouseArea {
            anchors.fill: parent
            onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
            onWheel: (w) => {
                if (!root.sink || !root.sink.audio) return;
                root.sink.audio.volume = Math.max(0, Math.min(1.5, root.sink.audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05)));
            }
        }
    }

    // ── battery ──────────────────────────────────────────────────────
    readonly property var batt: UPower.displayDevice
    readonly property real pct: batt && batt.ready ? (batt.percentage > 1 ? batt.percentage / 100 : batt.percentage) : 0
    readonly property bool charging: batt && batt.state === UPowerDeviceState.Charging

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.bs(5)
        visible: root.batt && root.batt.isLaptopBattery

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.bs(20); height: Theme.bs(10)
            radius: 2
            color: "transparent"
            border.width: 1
            border.color: Theme.dim
            Rectangle {
                x: 2; y: 2
                height: parent.height - 4
                width: Math.max(1, (parent.width - 4) * root.pct)
                radius: 1
                color: root.charging ? Theme.a2 : root.pct < 0.15 ? Theme.crit : root.pct < 0.3 ? Theme.warn : Theme.ok
                Behavior on width { NumberAnimation { duration: Theme.dur(400) } }
            }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.pct * 100) + "%" + (root.charging ? "+" : "")
            font.pixelSize: Theme.bs(12)
        }
    }
}
