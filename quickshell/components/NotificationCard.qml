pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.services

Rectangle {
    id: card
    required property var notif
    property bool popup: false
    signal closed()

    readonly property bool critical: notif && notif.urgency === NotificationUrgency.Critical
    readonly property var defaultAction: notif ? notif.actions.find(a => a.identifier === "default") || null : null
    readonly property var buttons: notif ? notif.actions.filter(a => a.identifier !== "default") : []

    implicitWidth: 360
    implicitHeight: col.implicitHeight + 24
    radius: Theme.radius
    color: popup ? (Theme.rich ? Theme.alpha(Theme.s1, 0.92) : Theme.s1) : Theme.s2
    border.width: 1
    border.color: critical ? Theme.crit : popup ? Theme.line : "transparent"

    // accent edge
    Rectangle {
        width: 2
        radius: 1
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 10; bottomMargin: 10 }
        color: card.critical ? Theme.crit : Theme.a2
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: card.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: (m) => {
            if (m.button === Qt.MiddleButton) { card.closed(); return; }
            if (card.defaultAction) { card.defaultAction.invoke(); card.closed(); }
        }
    }

    Row {
        anchors { fill: parent; margins: 12; leftMargin: 14 }
        spacing: 10

        // image (album art, avatar) or app icon
        Item {
            width: 36; height: 36
            visible: !!(card.notif && (card.notif.image || card.notif.appIcon))
            ClippingRectangle {
                anchors.fill: parent
                radius: Theme.radius * 0.5
                color: "transparent"
                visible: !!(card.notif && card.notif.image)
                Image { anchors.fill: parent; source: card.notif ? card.notif.image : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true }
            }
            IconImage {
                anchors.fill: parent
                visible: !!(card.notif && !card.notif.image && card.notif.appIcon)
                source: card.notif && card.notif.appIcon ? Quickshell.iconPath(card.notif.appIcon, true) : ""
                asynchronous: true
            }
        }

        Column {
            id: col
            width: parent.width - (parent.children[0].visible ? 46 : 0) - 20
            spacing: 3

            Row {
                width: parent.width
                Label {
                    width: parent.width - 16
                    elide: Text.ElideRight
                    text: (card.notif ? card.notif.appName || "notification" : "").toUpperCase()
                    color: Theme.dim
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }
                Label {
                    width: 16
                    text: "✕"
                    color: Theme.dim
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: 11
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: card.closed() }
                }
            }
            Label {
                width: parent.width
                text: card.notif ? card.notif.summary : ""
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Label {
                width: parent.width
                visible: text.length > 0
                text: card.notif ? card.notif.body : ""
                textFormat: Text.StyledText
                color: Theme.alpha(Theme.fg, 0.8)
                font.pixelSize: 11
                wrapMode: Text.Wrap
                maximumLineCount: card.popup ? 4 : 6
                elide: Text.ElideRight
                linkColor: Theme.a2
                onLinkActivated: (l) => Qt.openUrlExternally(l)
            }
            Row {
                visible: card.buttons.length > 0
                topPadding: 4
                spacing: 6
                Repeater {
                    model: card.buttons
                    delegate: ChipButton {
                        required property var modelData
                        text: modelData.text
                        onClicked: { modelData.invoke(); card.closed(); }
                    }
                }
            }
        }
    }
}
