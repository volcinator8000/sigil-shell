pragma ComponentBehavior: Bound

// Notifications from one app: the newest as a full card, the rest stacked behind it.
// Expanded, the older ones are listed underneath (each closable on its own).

import QtQuick
import qs.services

Item {
    id: grp
    property var items: []               // newest first
    property bool popup: false
    property bool expanded: false
    signal dismissGroup()
    signal dismissOne(var notif)
    signal replyFocus(bool on)

    readonly property int n: items.length
    readonly property int ghosts: expanded ? 0 : Math.min(2, n - 1)
    onNChanged: if (n <= 1) expanded = false

    implicitWidth: 360
    implicitHeight: col.implicitHeight + ghosts * 5

    // stacked edges peeking out under the head card
    Repeater {
        model: grp.ghosts
        delegate: Rectangle {
            required property int index
            x: (index + 1) * 7
            width: grp.width - 2 * x
            y: head.height - head.radius + (index + 1) * 5
            height: head.radius + 0.5
            z: -1 - index
            radius: head.radius
            color: Theme.alpha(Theme.s2, 0.95 - index * 0.3)
            border.width: 1
            border.color: Theme.alpha(Theme.a2, 0.35 - index * 0.15)
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 6

        NotificationCard {
            id: head
            width: col.width
            notif: grp.items[0] || null
            popup: grp.popup
            count: grp.n
            expanded: grp.expanded
            onExpandToggled: grp.expanded = !grp.expanded
            onClosed: (grp.n > 1 && !grp.expanded) ? grp.dismissGroup() : grp.dismissOne(notif)
            onReplyFocus: (on) => grp.replyFocus(on)
        }
        Repeater {
            model: grp.expanded ? grp.items.slice(1) : []
            delegate: NotificationCard {
                required property var modelData
                x: 12
                width: col.width - 12
                notif: modelData
                popup: grp.popup
                nested: true
                onClosed: grp.dismissOne(modelData)
                onReplyFocus: (on) => grp.replyFocus(on)
            }
        }
        Item {
            visible: grp.expanded
            width: col.width
            height: 20
            ChipButton {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                small: true
                text: "clear all " + grp.n
                onClicked: grp.dismissGroup()
            }
        }
    }
}
