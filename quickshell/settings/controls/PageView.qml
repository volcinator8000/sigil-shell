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
