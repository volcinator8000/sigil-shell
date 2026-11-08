pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.components

Column {
    id: root
    spacing: 8
    readonly property int w: 196
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }

    Component.onCompleted: Weather.users++
    Component.onDestruction: Weather.users--

    WidgetHeader { width: root.w; title: "weather"; detail: Weather.error || Weather.city }

    Row {
        spacing: 12
        Label {
            text: Weather.ready ? Weather.glyph : String.fromCodePoint(0xF0590)
            font.pixelSize: 34
            color: Theme.a2
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Label {
                text: Weather.ready ? Math.round(Weather.temp) + "°" : "--°"
                font.pixelSize: 28
                font.bold: true
            }
            Label {
                text: Weather.ready ? Weather.description + (root.o("showRange") ? " · H " + Math.round(Weather.high) + "° L " + Math.round(Weather.low) + "°" : "") : "loading…"
                color: Theme.dim
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
                Label { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.label; color: Theme.dim; font.pixelSize: 10 }
                Label { anchors.horizontalCenter: parent.horizontalCenter; text: parent.modelData.temp + "°"; font.pixelSize: 11 }
            }
        }
    }
}
