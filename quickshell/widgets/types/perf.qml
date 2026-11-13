pragma ComponentBehavior: Bound

// Performance: a grid of tiles (CPU, RAM, each GPU, CPU temperature), each a big value over a
// graph, then one line for GPU / SSD heat, VRAM and fans, and the root disk as a bar.
// Wider = more columns and a longer timeline.
import QtQuick
import qs.services
import qs.components

Column {
    id: root
    spacing: 10
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

    readonly property int gap: 8
    readonly property int cols: w >= 620 ? 3 : w >= 380 ? 2 : 1
    readonly property real tileW: (w - (cols - 1) * gap) / cols
    // one sample per ~4 px of graph, capped by the history kept
    readonly property int samples: Math.max(12, Math.min(Sys.historyLength, Math.round((tileW - 20) / 4)))
    readonly property int step: Theme.rich ? 1 : 4
    function span(sec) { return sec < 120 ? sec + "s" : Math.round(sec / 60) + "m"; }
    function tail(a) { return a.length > samples ? a.slice(-samples) : a; }
    function level(v, warn, crit) { return v >= crit ? Theme.crit : v >= warn ? Theme.warn : Theme.fg; }

    WidgetHeader { width: root.w; title: "performance"; detail: root.span(root.samples * root.step) + (Theme.rich ? "" : " · battery") }

    // the tiles, as data so the grid can flow them
    readonly property var tiles: {
        const t = [];
        if (o("cpu") !== false)
            t.push({ name: "CPU", value: Math.round(Sys.cpu), unit: "%", hist: Sys.cpuHist, lo: 0, hi: 100, tint: Theme.a1,
                     sub: "", warn: 85, crit: 95 });
        if (o("ram") !== false)
            t.push({ name: "RAM", value: Sys.ramUsed.toFixed(1), unit: "G", hist: Sys.ramHist, lo: 0, hi: Sys.ramTotal, tint: Theme.a2,
                     sub: "of " + Math.round(Sys.ramTotal) + " G", warn: Sys.ramTotal * 0.85, crit: Sys.ramTotal * 0.95, raw: Sys.ramUsed });
        if (o("gpu") !== false)
            for (const g of Sys.gpus)
                t.push({ name: g.label.toUpperCase(), value: Math.round(g.busy), unit: "%", hist: Sys.gpuHists[g.label] || [], lo: 0, hi: 100,
                         tint: g.label === "igpu" ? Theme.a1 : Theme.a2,
                         sub: g.temp > 0 ? Math.round(g.temp) + "°" : "", warn: 90, crit: 101 });
        if (o("temp") !== false)
            t.push({ name: "CPU TEMP", value: Math.round(Sys.temp), unit: "°", hist: Sys.tempHist, lo: 30, hi: 100,
                     tint: Sys.temp >= 85 ? Theme.warn : Theme.a2, sub: "", warn: 85, crit: 95 });
        return t;
    }

    Flow {
        width: root.w
        spacing: root.gap
        Repeater {
            model: root.tiles
            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index
                // an odd tile out at the end takes the whole row
                readonly property bool last: index === root.tiles.length - 1 && root.tiles.length % root.cols !== 0
                readonly property real num: modelData.raw !== undefined ? modelData.raw : Number(modelData.value)
                width: last ? root.w - (root.tiles.length % root.cols - 1) * (root.tileW + root.gap) : root.tileW
                height: 70
                radius: Theme.radius * 0.6
                color: Theme.alpha(Theme.fg, 0.045)
                border.width: 1
                border.color: Theme.alpha(Theme.fg, 0.06)

                WLabel {
                    x: 10; y: 8
                    text: tile.modelData.name
                    color: Theme.widgetDim
                    font.pixelSize: 11
                    font.letterSpacing: 1
                }
                WLabel {
                    anchors { right: parent.right; rightMargin: 10 }
                    y: 8
                    visible: text !== ""
                    text: tile.modelData.sub
                    color: Theme.widgetDim
                    font.pixelSize: 11
                }
                Row {
                    x: 10; y: 22
                    WLabel {
                        id: valueL
                        text: tile.modelData.value
                        font.pixelSize: 20
                        font.bold: true
                        color: root.level(tile.num, tile.modelData.warn, tile.modelData.crit)
                    }
                    WLabel {
                        anchors.baseline: valueL.baseline
                        text: tile.modelData.unit
                        leftPadding: 1
                        font.pixelSize: 12
                        color: Theme.widgetDim
                    }
                }
                Sparkline {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 1; rightMargin: 1; bottomMargin: 1 }
                    height: 26
                    values: root.tail(tile.modelData.hist)
                    minValue: tile.modelData.lo
                    maxValue: tile.modelData.hi
                    lineColor: tile.modelData.tint
                }
            }
        }
    }

    // heat, VRAM and fans as one line of small readouts
    readonly property var dgpu: Sys.gpus.find(g => g.label !== "igpu" && g.vramTotal > 1) || null
    readonly property var facts: {
        if (o("details") === false) return [];
        const f = [];
        if (Sys.nvmeTemp > 0) f.push({ k: "ssd", v: Math.round(Sys.nvmeTemp) + "°", hot: Sys.nvmeTemp >= 70 });
        if (dgpu) f.push({ k: "vram", v: dgpu.vramUsed.toFixed(1) + " / " + dgpu.vramTotal.toFixed(0) + " G", hot: dgpu.vramUsed / dgpu.vramTotal > 0.9 });
        if (Sys.fans.length) f.push({ k: "fans", v: Sys.fans.every(r => r === 0) ? "off" : Sys.fans.filter(r => r > 0).map(r => Math.round(r / 100) / 10 + "k").join(" · ") + " rpm", hot: false });
        return f;
    }
    Row {
        visible: root.facts.length > 0
        spacing: 16
        Repeater {
            model: root.facts
            delegate: Row {
                required property var modelData
                spacing: 5
                WLabel { text: parent.modelData.k; color: Theme.widgetDim; font.pixelSize: 12 }
                WLabel { text: parent.modelData.v; color: parent.modelData.hot ? Theme.warn : Theme.fg; font.pixelSize: 12 }
            }
        }
    }

    // root disk: a bar, not a graph (it changes over days, not seconds)
    Item {
        visible: root.o("disk") !== false
        width: root.w
        height: 16
        WLabel { id: diskL; anchors.verticalCenter: parent.verticalCenter; text: "disk"; color: Theme.widgetDim; font.pixelSize: 12 }
        Rectangle {
            anchors { left: diskL.right; leftMargin: 10; right: diskV.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            height: 6; radius: 3
            color: Theme.alpha(Theme.fg, 0.08)
            Rectangle {
                width: parent.width * Math.min(1, Sys.diskPct / 100); height: parent.height; radius: 3
                color: Sys.diskPct >= 90 ? Theme.crit : Sys.diskPct >= 80 ? Theme.warn : Theme.a1
            }
        }
        WLabel {
            id: diskV
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: (Sys.diskText ? Sys.diskText + "  " : "") + Math.round(Sys.diskPct) + "%"
            color: Sys.diskPct >= 90 ? Theme.crit : Sys.diskPct >= 80 ? Theme.warn : Theme.fg
            font.pixelSize: 12
        }
    }
}
