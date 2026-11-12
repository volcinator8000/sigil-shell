pragma ComponentBehavior: Bound

// Network: connection (Wi-Fi name and signal, or ethernet), download / upload graphs, local IP.
// Rates are measured on the interface carrying the default route (services/Sys.qml).
import QtQuick
import Quickshell.Networking
import qs.services
import qs.components

Column {
    id: root
    spacing: 8
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }
    readonly property int w: Math.max(220, entry.w || 260)

    property bool counted: false
    function sync() {
        if (Widgets.desktopVisible && !counted) { Sys.users++; counted = true; }
        else if (!Widgets.desktopVisible && counted) { Sys.users--; counted = false; }
    }
    Connections { target: Widgets; function onDesktopVisibleChanged() { root.sync(); } }
    Component.onCompleted: sync()
    Component.onDestruction: if (counted) Sys.users--

    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wiredDev: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) || null
    readonly property var wifiNet: wifiDev ? (wifiDev.networks.values.find(n => n.connected) || null) : null
    readonly property bool vpn: Sys.netIf !== "" && !/^(wl|en|eth)/.test(Sys.netIf)

    function g(cp) { return String.fromCodePoint(cp); }
    function rate(b) {
        if (b < 1024) return Math.round(b) + " B/s";
        if (b < 1048576) return (b / 1024).toFixed(b < 10240 ? 1 : 0) + " K/s";
        return (b / 1048576).toFixed(b < 10485760 ? 1 : 0) + " M/s";
    }
    readonly property int samples: Math.max(10, Math.min(Sys.historyLength, Math.round(40 * (w - 60) / 200)))
    function tail(a) { return a.length > samples ? a.slice(-samples) : a; }
    // both graphs share one scale so up and down compare at a glance
    readonly property real peak: Math.max(65536, ...tail(Sys.rxHist), ...tail(Sys.txHist))

    WidgetHeader { title: "network"; detail: Sys.netIf }

    Row {
        spacing: 12
        WLabel {
            anchors.verticalCenter: parent.verticalCenter
            font.pixelSize: 28
            color: root.wiredDev || root.wifiNet ? Theme.a2 : Theme.widgetDim
            text: {
                if (root.wiredDev) return root.g(0xF0200);
                if (!root.wifiNet) return root.g(0xF092D);
                const s = root.wifiNet.signalStrength;
                return root.g(s > 0.75 ? 0xF0928 : s > 0.5 ? 0xF0925 : s > 0.25 ? 0xF0922 : 0xF091F);
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            WLabel {
                width: root.w - 52
                elide: Text.ElideRight
                text: root.wiredDev ? "Ethernet" : root.wifiNet ? root.wifiNet.name : "Offline"
                font.pixelSize: 16
                font.bold: true
            }
            WLabel {
                width: root.w - 52
                elide: Text.ElideRight
                visible: text !== ""
                text: [root.wifiNet && !root.wiredDev ? Math.round(root.wifiNet.signalStrength * 100) + "% signal" : "",
                       root.o("ip") !== false ? Sys.netIp : "", root.vpn ? "via " + Sys.netIf : ""].filter(x => x).join("  ·  ")
                color: Theme.widgetDim
                font.pixelSize: 12
            }
        }
    }

    component Rate: Row {
        id: r
        property string name
        property var values: []
        property real now: 0
        property color tint: Theme.a1
        spacing: 8
        WLabel { width: 34; text: r.name; color: Theme.widgetDim; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        Sparkline { width: root.w - 34 - 64 - 16; height: 20; values: root.tail(r.values); minValue: 0; maxValue: root.peak; lineColor: r.tint }
        WLabel { width: 64; horizontalAlignment: Text.AlignRight; text: root.rate(r.now); font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
    }
    Rate { visible: root.o("graphs") !== false; name: "down"; values: Sys.rxHist; now: Sys.rxRate }
    Rate { visible: root.o("graphs") !== false; name: "up"; values: Sys.txHist; now: Sys.txRate; tint: Theme.a2 }
}
