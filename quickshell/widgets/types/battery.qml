pragma ComponentBehavior: Bound

// Battery & power: charge, time left / to full, live wattage with a graph, battery health.
// Numbers come straight from sysfs through services/Sys.qml. Wider = longer timeline.
import QtQuick
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

    readonly property bool charging: Sys.batStatus === "Charging"
    readonly property bool draining: Sys.batStatus === "Discharging"
    readonly property real watts: Math.abs(Sys.batWatts)
    readonly property real health: Sys.batDesign > 0 ? 100 * Sys.batFull / Sys.batDesign : 0
    readonly property color tint: Sys.batPct <= 15 && !charging ? Theme.crit : Sys.batPct <= 30 && !charging ? Theme.warn : charging ? Theme.ok : Theme.a1
    function hm(h) {
        if (!isFinite(h) || h <= 0 || h > 48) return "";
        const m = Math.round(h * 60);
        return Math.floor(m / 60) + "h " + String(m % 60).padStart(2, "0");
    }
    readonly property string eta: charging && watts > 0.5 ? hm((Sys.batFull - Sys.batEnergy) / watts) + " to full"
                                : draining && watts > 0.5 ? hm(Sys.batEnergy / watts) + " left" : ""
    readonly property string stateText: !Sys.hasBattery ? "no battery"
                                      : charging ? "charging" : draining ? "on battery"
                                      : Sys.batStatus === "Full" ? "full" : Sys.acOnline ? "plugged in, not charging" : Sys.batStatus.toLowerCase()

    readonly property int samples: Math.max(10, Math.min(Sys.historyLength, Math.round(40 * (w - 60) / 200)))
    readonly property int step: Theme.rich ? 1 : 4

    WidgetHeader {
        title: "battery"
        detail: root.samples * root.step < 120 ? root.samples * root.step + "s" : Math.round(root.samples * root.step / 60) + "m"
    }

    Row {
        spacing: 12
        // battery glyph with the fill drawn in
        Item {
            width: 26; height: 44
            anchors.verticalCenter: parent.verticalCenter
            Rectangle { x: 8; width: 10; height: 4; radius: 1; color: Theme.alpha(Theme.fg, 0.5) }
            Rectangle {
                y: 4; width: 26; height: 40; radius: 5
                color: "transparent"
                border.width: 2; border.color: Theme.alpha(Theme.fg, 0.5)
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 4 }
                    height: (parent.height - 8) * Math.min(1, Sys.batPct / 100)
                    radius: 2
                    color: root.tint
                }
                WLabel {
                    anchors.centerIn: parent
                    visible: root.charging
                    text: String.fromCodePoint(0xF140B)
                    font.pixelSize: 16
                    color: Theme.bg
                }
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            WLabel { text: Math.round(Sys.batPct) + "%"; font.pixelSize: 28; font.bold: true }
            WLabel {
                text: root.stateText + (root.eta ? "  ·  " + root.eta : "")
                color: Theme.widgetDim
                font.pixelSize: 12
            }
        }
    }

    // power draw / charge rate
    Row {
        visible: root.o("graph") !== false && Sys.hasBattery
        spacing: 8
        WLabel { width: 34; text: root.charging ? "in" : "draw"; color: Theme.widgetDim; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        Sparkline {
            width: root.w - 34 - 52 - 16
            height: 22
            values: Sys.powerHist.length > root.samples ? Sys.powerHist.slice(-root.samples) : Sys.powerHist
            minValue: 0
            maxValue: Math.max(20, ...Sys.powerHist.slice(-root.samples))
            lineColor: root.charging ? Theme.ok : root.watts > 25 ? Theme.warn : Theme.a2
        }
        WLabel {
            width: 52; horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            text: root.watts.toFixed(1) + " W"
            font.pixelSize: 12
        }
    }

    Row {
        visible: root.o("health") !== false && root.health > 0
        spacing: 8
        WLabel { width: 34; text: "health"; color: Theme.widgetDim; font.pixelSize: 12 }
        WLabel {
            text: Math.round(root.health) + "%  ·  " + Sys.batFull.toFixed(1) + " of " + Sys.batDesign.toFixed(1) + " Wh" + (Sys.batCycles > 0 ? "  ·  " + Sys.batCycles + " cycles" : "")
            color: root.health < 70 ? Theme.warn : Theme.fg
            font.pixelSize: 12
        }
    }
}
