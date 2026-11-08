pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services
import qs.components

Item {
    id: frame
    property var entry: ({})
    property bool editing: false
    readonly property bool hovered: hoverH.hovered

    HoverHandler { id: hoverH }

    x: entry.x
    y: entry.y
    opacity: entry.opacity !== undefined ? entry.opacity : 1
    scale: entry.scale !== undefined ? entry.scale : 1
    transformOrigin: Item.TopLeft
    width: content.item ? content.item.implicitWidth + 24 : 120
    height: content.item ? content.item.implicitHeight + 24 : 60

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: frame.entry.style === "card" ? Theme.s1
             : frame.entry.style === "glass" ? Theme.alpha(Theme.s1, 0.55) : "transparent"
        border.width: 1
        border.color: frame.editing ? Theme.alpha(Theme.a1, 0.7)
                    : frame.entry.style === "card" ? Theme.line
                    : frame.entry.style === "glass" ? Theme.alpha(Theme.fg, 0.10) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.dur(200) } }
    }

    // highlighted while selected on the settings page
    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: Theme.radius + 4
        color: "transparent"
        border.width: 2
        border.color: Theme.a1
        visible: Widgets.selected === frame.entry.id
        opacity: 0.9
    }

    Loader {
        id: content
        x: 12
        y: 12
        source: Qt.resolvedUrl("types/" + frame.entry.type + ".qml")
        // every type gets its entry (opts live in entry.opts; read them with Widgets.opt(entry, key))
        onLoaded: item.entry = Qt.binding(() => frame.entry)
        // Text on bare widgets gets a soft shadow so it stays readable on any wallpaper.
        layer.enabled: frame.entry.style === "bare" && Theme.rich
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.5
            shadowOpacity: 0.8
            shadowColor: "black"
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: frame.editing
        visible: frame.editing
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: frame
        drag.threshold: 2
        onReleased: {
            const nx = Math.max(0, Math.round(frame.x / 20) * 20);
            const ny = Math.max(40, Math.round(frame.y / 20) * 20);
            Widgets.move(frame.entry.id, nx, ny);
        }
    }

    Row {
        visible: frame.editing
        spacing: 4
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.top }
        ChipButton { text: frame.entry.style; small: true; onClicked: Widgets.cycleStyle(frame.entry.id) }
        ChipButton { text: "✕"; small: true; danger: true; onClicked: Widgets.remove(frame.entry.id) }
    }
}
