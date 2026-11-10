pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components

Column {
    id: root
    spacing: 7
    readonly property int w: Math.max(200, entry.w || o("width") || 276)
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }

    // sensors poll only while the desktop is in view (see Widgets.desktopVisible)
    property bool counted: false
    function sync() {
        if (Widgets.desktopVisible && !counted) { Sys.users++; counted = true; }
        else if (!Widgets.desktopVisible && counted) { Sys.users--; counted = false; }
    }
    Connections { target: Widgets; function onDesktopVisibleChanged() { root.sync(); } }
    Component.onCompleted: sync()
    Component.onDestruction: if (counted) Sys.users--

    // wider widget = longer timeline: 30 samples at the default width, more in proportion
    readonly property int sparkW: root.w - 34 - 46 - 16
    readonly property int samples: Math.max(10, Math.min(Sys.historyLength, Math.round(30 * sparkW / 180)))
    readonly property int step: Theme.rich ? 1 : 4
    function span(sec) { return sec < 120 ? sec + "s" : Math.round(sec / 60) + "m"; }
    function tail(a) { return a.length > samples ? a.slice(-samples) : a; }

    WidgetHeader { width: root.w; title: "performance"; detail: root.span(root.samples * root.step) + (Theme.rich ? "" : " · battery") }

    component Metric: Row {
        id: m
        property string name
        property string value
        property var values: []
        property real lo: 0
        property real hi: 100
        property color tint: Theme.a1
        spacing: 8
        WLabel { width: 34; text: m.name; color: Theme.dim; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
        Sparkline { width: root.sparkW; height: 20; values: root.tail(m.values); minValue: m.lo; maxValue: m.hi; lineColor: m.tint }
        WLabel { width: 46; horizontalAlignment: Text.AlignRight; text: m.value; color: m.tint === Theme.warn ? Theme.warn : Theme.fg; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
    }

    Metric { visible: root.o("cpu") !== false; name: "cpu"; values: Sys.cpuHist; value: Math.round(Sys.cpu) + "%" }
    Metric { visible: root.o("ram") !== false; name: "ram"; values: Sys.ramHist; hi: Sys.ramTotal; tint: Theme.a2; value: Sys.ramUsed.toFixed(1) + "G" }
    Metric { visible: root.o("gpu") !== false; name: "gpu"; values: Sys.gpuHist; value: Math.round(Sys.gpu) + "%" }
    Metric { visible: root.o("temp") !== false; name: "temp"; values: Sys.tempHist; lo: 30; hi: 100; tint: Sys.temp > 80 ? Theme.warn : Theme.a2; value: Math.round(Sys.temp) + "°" }

    // root disk: a bar, not a graph (it changes over days, not seconds)
    Row {
        visible: root.o("disk") !== false
        spacing: 8
        WLabel { width: 34; text: "disk"; color: Theme.dim; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
        Item {
            width: root.sparkW; height: 20
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 6; radius: 3
                color: Theme.alpha(Theme.fg, 0.08)
                Rectangle {
                    width: parent.width * Math.min(1, Sys.diskPct / 100); height: parent.height; radius: 3
                    color: Sys.diskPct >= 90 ? Theme.crit : Sys.diskPct >= 80 ? Theme.warn : Theme.a1
                }
            }
        }
        WLabel { width: 46; horizontalAlignment: Text.AlignRight; text: Math.round(Sys.diskPct) + "%"; color: Sys.diskPct >= 90 ? Theme.crit : Sys.diskPct >= 80 ? Theme.warn : Theme.fg; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
    }
}
