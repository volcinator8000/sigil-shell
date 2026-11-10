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
    // Size: the content's own size, or the width / height set by dragging an edge in edit
    // mode (entry.w / entry.h, content px before scaling). Types read entry.w / entry.h and
    // lay themselves out for it (notes: more lines, weather: the week, …).
    property real liveW: -1
    property real liveH: -1
    readonly property var liveEntry: (liveW < 0 && liveH < 0) ? entry
        : Object.assign({}, entry, liveW >= 0 ? { w: liveW } : {}, liveH >= 0 ? { h: liveH } : {})
    readonly property real setH: liveEntry.h || 0
    width: content.item ? content.item.implicitWidth + 24 : 120
    height: content.item ? Math.max(content.item.implicitHeight, setH) + 24 : 60

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: frame.entry.style === "card" ? Theme.s1
             : frame.entry.style === "glass" ? Theme.alpha(Theme.s1, 0.55) : "transparent"
        // bare: no outline at all outside edit mode
        border.width: frame.entry.style === "bare" && !frame.editing ? 0 : 1
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
        // only while arranging or while the settings Widgets page is open
        visible: Widgets.selected === frame.entry.id && (frame.editing || Widgets.pageOpen)
        opacity: 0.9
    }

    Loader {
        id: content
        x: 12
        y: 12
        source: Qt.resolvedUrl("types/" + frame.entry.type + ".qml")
        // every type gets its entry (opts live in entry.opts; read them with Widgets.opt(entry, key))
        onLoaded: item.entry = Qt.binding(() => frame.liveEntry)
        // Text on bare widgets gets a soft shadow so it stays readable on any wallpaper.
        layer.enabled: frame.entry.style === "bare" && Theme.rich
        // render the layer at the scaled size, or it is a small texture stretched (blurry)
        layer.textureSize: Qt.size(Math.ceil(width * frame.scale), Math.ceil(height * frame.scale))
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

    // edge handles: drag to set just the width or just the height; double-click resets
    component EdgeHandle: Rectangle {
        id: eh
        property bool vertical: false     // false = right edge (width), true = bottom edge (height)
        visible: frame.editing && frame.isSelected
        width: vertical ? 34 : 6
        height: vertical ? 6 : 34
        radius: 3
        color: ma.containsMouse || ma.pressed ? Theme.a1 : Theme.alpha(Theme.a1, 0.6)
        x: vertical ? (frame.width - width) / 2 : frame.width - width / 2
        y: vertical ? frame.height - height / 2 : (frame.height - height) / 2
        MouseArea {
            id: ma
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: eh.vertical ? Qt.SizeVerCursor : Qt.SizeHorCursor
            property real start: 0
            property real startSize: 0
            onPressed: (m) => {
                Widgets.selected = frame.entry.id;
                const p = mapToItem(null, m.x, m.y);
                start = eh.vertical ? p.y : p.x;
                // current content size (unscaled)
                startSize = eh.vertical ? frame.height - 24 : frame.width - 24;
            }
            onPositionChanged: (m) => {
                if (!pressed) return;
                const p = mapToItem(null, m.x, m.y);
                const d = ((eh.vertical ? p.y : p.x) - start) / Math.max(0.1, frame.curScale);
                const v = Math.max(40, Widgets.snap(startSize + d));
                if (eh.vertical) frame.liveH = v; else frame.liveW = v;
            }
            onReleased: {
                if (eh.vertical && frame.liveH >= 0) Widgets.update(frame.entry.id, { h: frame.liveH });
                else if (!eh.vertical && frame.liveW >= 0) Widgets.update(frame.entry.id, { w: frame.liveW });
                frame.liveW = -1; frame.liveH = -1;
            }
            onDoubleClicked: Widgets.update(frame.entry.id, eh.vertical ? { h: undefined } : { w: undefined })
        }
    }
    EdgeHandle {}
    EdgeHandle { vertical: true }

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
