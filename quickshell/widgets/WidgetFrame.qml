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

    // ── edit mode ────────────────────────────────────────────────────
    readonly property bool isSelected: Widgets.selected === entry.id
    readonly property real curScale: entry.scale !== undefined ? entry.scale : 1
    readonly property real curOpacity: entry.opacity !== undefined ? entry.opacity : 1

    MouseArea {
        anchors.fill: parent
        enabled: frame.editing
        visible: frame.editing
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: frame
        drag.threshold: 2
        onPressed: Widgets.selected = frame.entry.id
        onReleased: if (drag.active || frame.x !== frame.entry.x || frame.y !== frame.entry.y)
                        Widgets.move(frame.entry.id, Math.max(0, Widgets.snap(frame.x)), Math.max(40, Widgets.snap(frame.y)))
    }

    // resize handle: drag to scale (snaps to 5 %)
    Rectangle {
        visible: frame.editing && frame.isSelected
        width: 12; height: 12
        radius: 3
        color: Theme.a1
        x: frame.width - 8
        y: frame.height - 8
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.SizeFDiagCursor
            property real startX: 0
            property real startScale: 1
            onPressed: (m) => { startX = mapToItem(null, m.x, m.y).x; startScale = frame.curScale; Widgets.selected = frame.entry.id; }
            onPositionChanged: (m) => {
                if (!pressed) return;
                const dx = mapToItem(null, m.x, m.y).x - startX;
                frame.scale = Math.max(0.5, Math.min(2.5, Math.round(startScale * (1 + dx / (frame.width * startScale)) * 20) / 20));
            }
            onReleased: Widgets.update(frame.entry.id, { scale: frame.scale })
        }
    }

    // toolbar of the selected widget (above it, or below when there is no room)
    Row {
        visible: frame.editing && frame.isSelected
        spacing: 3
        x: 0
        y: frame.y < 80 ? frame.height + 8 : -30
        // keep it readable whatever the widget's own scale / opacity
        scale: 1 / Math.max(0.01, frame.curScale)
        transformOrigin: frame.y < 80 ? Item.TopLeft : Item.BottomLeft
        opacity: 1 / Math.max(0.2, frame.curOpacity)

        ChipButton { text: frame.entry.style; small: true; onClicked: Widgets.cycleStyle(frame.entry.id) }
        ChipButton { text: "◐−"; small: true; onClicked: Widgets.stepOpacity(frame.entry.id, -0.1) }
        ChipButton { text: Math.round(frame.curOpacity * 100) + "%"; small: true; onClicked: Widgets.update(frame.entry.id, { opacity: 1 }) }
        ChipButton { text: "◐+"; small: true; onClicked: Widgets.stepOpacity(frame.entry.id, 0.1) }
        ChipButton { text: "−"; small: true; onClicked: Widgets.stepScale(frame.entry.id, -0.1) }
        ChipButton { text: frame.curScale.toFixed(1) + "×"; small: true; onClicked: Widgets.update(frame.entry.id, { scale: 1 }) }
        ChipButton { text: "+"; small: true; onClicked: Widgets.stepScale(frame.entry.id, 0.1) }
        ChipButton { text: "⧉"; small: true; onClicked: Widgets.selected = Widgets.duplicate(frame.entry.id) }
        ChipButton { text: "⇡"; small: true; onClicked: Widgets.reorder(frame.entry.id, 1) }
        ChipButton { text: "⇣"; small: true; onClicked: Widgets.reorder(frame.entry.id, -1) }
        ChipButton { text: "options"; small: true; onClicked: Widgets.openOptions(frame.entry.id) }
        ChipButton { text: "✕"; small: true; danger: true; onClicked: Widgets.remove(frame.entry.id) }
    }

    // unselected widgets in edit mode: just their type
    Label {
        visible: frame.editing && !frame.isSelected
        y: -16
        text: Widgets.typeInfo(frame.entry.type).label.toUpperCase()
        color: Theme.a2
        font.pixelSize: 9
        font.letterSpacing: 1.4
    }
}
