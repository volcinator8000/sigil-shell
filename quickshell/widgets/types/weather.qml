pragma ComponentBehavior: Bound

// Current weather, next hours, and the week when there is room:
//   wide (≥ 340 px)  → the 7 days as columns under the current conditions
//   tall (≥ 200 px)  → the 7 days as rows
import QtQuick
import qs.services
import qs.components

Column {
    id: root
    spacing: 8
    readonly property int w: Math.max(196, entry.w || 0)
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }
    readonly property bool wide: w >= 340
    readonly property bool tall: !wide && (entry.h || 0) >= 200
    readonly property bool week: (wide || tall) && Weather.days.length > 0

    Component.onCompleted: Weather.users++
    Component.onDestruction: Weather.users--

    WidgetHeader { width: root.w; title: "weather"; detail: Weather.error || Weather.city }

    Row {
        spacing: 12
        WLabel {
            text: Weather.ready ? Weather.glyph : String.fromCodePoint(0xF0590)
            font.pixelSize: 34
            color: Theme.a2
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            WLabel {
                text: Weather.ready ? Math.round(Weather.temp) + "°" : "--°"
                font.pixelSize: 28
                font.bold: true
            }
            WLabel {
                text: Weather.ready ? Weather.description + (root.o("showRange") ? " · H " + Math.round(Weather.high) + "° L " + Math.round(Weather.low) + "°" : "") : "loading…"
                color: Theme.widgetDim
                font.pixelSize: 11
            }
        }
    }

    Row {
        visible: Weather.hours.length > 0 && root.o("showForecast") !== false
        Repeater {
            model: Weather.hours
            delegate: Column {
                required property var modelData
                width: root.w / 4
                WLabel { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.label; color: Theme.widgetDim; font.pixelSize: 10 }
                WLabel { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.temp + "°"; font.pixelSize: 11 }
            }
        }
    }

    Rectangle { visible: root.week; width: root.w; height: 1; color: Theme.alpha(Theme.fg, 0.08) }

    // week, wide: one column per day
    Row {
        visible: root.week && root.wide
        Repeater {
            model: root.wide ? Weather.days : []
            delegate: Column {
                required property var modelData
                width: root.w / 7
                spacing: 3
                WLabel { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.label; color: Theme.widgetDim; font.pixelSize: 10 }
                WLabel { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.glyph; color: Theme.a2; font.pixelSize: 18 }
                WLabel { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.high + "°"; font.pixelSize: 11; font.bold: true }
                WLabel { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.low + "°"; color: Theme.widgetDim; font.pixelSize: 10 }
            }
        }
    }

    // week, tall: one row per day
    Column {
        visible: root.week && root.tall
        spacing: 4
        Repeater {
            model: root.tall ? Weather.days : []
            delegate: Item {
                required property var modelData
                width: root.w
                height: 18
                WLabel { anchors.verticalCenter: parent.verticalCenter; width: 46; text: parent.modelData.label; color: Theme.widgetDim; font.pixelSize: 11 }
                WLabel { anchors.verticalCenter: parent.verticalCenter; x: 46; text: parent.modelData.glyph; color: Theme.a2; font.pixelSize: 14 }
                WLabel { anchors.verticalCenter: parent.verticalCenter; x: 70; width: root.w - 70 - 70; elide: Text.ElideRight; text: parent.modelData.text; color: Theme.widgetDim; font.pixelSize: 10 }
                WLabel {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: parent.modelData.high + "° / " + parent.modelData.low + "°"
                    font.pixelSize: 11
                }
            }
        }
    }
}
