pragma ComponentBehavior: Bound

// Scrollable page body: a centred column of Sections. Pages put their
// Sections in the default slot and modals in `overlays`.

import QtQuick
import QtQuick.Layouts
import qs.services

Item {
    id: root
    default property alias content: column.data
    property alias overlays: overlayLayer.data
    property alias flick: flick
    property int maxWidth: 760

    // Scroll `item` (a Section or SettingRow on this page) into view and flash it.
    function reveal(item) {
        if (!item) return;
        let target = item;
        // a row hidden by its section's current mode: show the section instead
        while (target && target !== column && !target.visible) target = target.parent;
        if (!target || target === column) return;
        const y = target.mapToItem(column, 0, 0).y + column.y;
        scrollAnim.to = Math.max(0, Math.min(flick.contentHeight - flick.height, y - 70));
        scrollAnim.restart();
        if (typeof target.flash === "function") target.flash();
    }
    NumberAnimation { id: scrollAnim; target: flick; property: "contentY"; duration: Theme.dur(260); easing.type: Easing.OutCubic }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + 48
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        flickDeceleration: 4000
        maximumFlickVelocity: 3000

        ColumnLayout {
            id: column
            x: Math.max(24, (flick.width - width) / 2)
            y: 20
            width: Math.min(root.maxWidth, flick.width - 48)
            spacing: 22
        }
    }
    // scroll indicator
    Rectangle {
        visible: flick.contentHeight > flick.height
        anchors.right: parent.right
        anchors.rightMargin: 3
        width: 3
        radius: 1.5
        color: Theme.alpha(Theme.a2, 0.5)
        y: flick.visibleArea.yPosition * flick.height
        height: Math.max(20, flick.visibleArea.heightRatio * flick.height)
    }
    Item { id: overlayLayer; anchors.fill: parent }
}
