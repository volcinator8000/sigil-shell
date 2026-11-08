pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components

Column {
    id: root
    spacing: 7
    readonly property int w: 276

    Component.onCompleted: Sys.users++
    Component.onDestruction: Sys.users--

    WidgetHeader { width: root.w; title: "performance"; detail: Theme.rich ? "1s" : "4s · battery" }

    component Metric: Row {
        id: m
        property string name
        property string value
        property var values: []
        property real lo: 0
        property real hi: 100
        property color tint: Theme.a1
        spacing: 8
        Label { width: 34; text: m.name; color: Theme.dim; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
        Sparkline { width: root.w - 34 - 46 - 16; height: 20; values: m.values; minValue: m.lo; maxValue: m.hi; lineColor: m.tint }
        Label { width: 46; horizontalAlignment: Text.AlignRight; text: m.value; color: m.tint === Theme.warn ? Theme.warn : Theme.fg; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
    }

    Metric { name: "cpu"; values: Sys.cpuHist; value: Math.round(Sys.cpu) + "%" }
    Metric { name: "ram"; values: Sys.ramHist; hi: Sys.ramTotal; tint: Theme.a2; value: Sys.ramUsed.toFixed(1) + "G" }
    Metric { name: "gpu"; values: Sys.gpuHist; value: Math.round(Sys.gpu) + "%" }
    Metric { name: "temp"; values: Sys.tempHist; lo: 30; hi: 100; tint: Sys.temp > 80 ? Theme.warn : Theme.a2; value: Math.round(Sys.temp) + "°" }
}
