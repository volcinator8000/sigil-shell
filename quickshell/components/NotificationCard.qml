pragma ComponentBehavior: Bound

// One notification. Used alone or as the head of a NotificationGroup.
//  • left click: default action · middle click / ✕: close · right click: per-app quick rules
//  • `count` > 1 shows "APP · N" and an expand chevron (group head)
//  • inline reply for apps that support it (chat apps)

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.services

Rectangle {
    id: card
    required property var notif
    property bool popup: false
    property int count: 1
    property bool expanded: false
    property bool nested: false          // a non-head card inside an expanded group
    signal closed()
    signal expandToggled()
    signal replyFocus(bool on)           // popups need keyboard focus while typing a reply

    readonly property bool critical: notif && Notifs.urgencyOf(notif) === NotificationUrgency.Critical
    readonly property var defaultAction: notif ? notif.actions.find(a => a.identifier === "default") || null : null
    readonly property var buttons: notif ? notif.actions.filter(a => a.identifier !== "default") : []
    readonly property bool canReply: !!(notif && notif.hasInlineReply)
    property bool menuOpen: false
    property bool replying: false
    onReplyingChanged: replyFocus(replying)

    implicitWidth: 360
    implicitHeight: col.implicitHeight + (nested ? 16 : 24)
    radius: Theme.radius
    color: popup ? (Theme.rich ? Theme.alpha(Theme.s1, 0.92) : Theme.s1) : nested ? Theme.alpha(Theme.s2, 0.6) : Theme.s2
    border.width: 1
    border.color: critical ? Theme.crit : menuOpen ? Theme.a2 : popup ? Theme.line : "transparent"
    // not in popups: the list there positions cards itself and a resizing card would land on its neighbour
    Behavior on implicitHeight { enabled: Theme.rich && !card.popup; NumberAnimation { duration: Theme.dur(150); easing.type: Easing.OutCubic } }

    // accent edge
    Rectangle {
        width: 2
        radius: 1
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 10; bottomMargin: 10 }
        color: card.critical ? Theme.crit : card.nested ? Theme.line : Theme.a2
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: card.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: (m) => {
            if (m.button === Qt.RightButton) { card.menuOpen = !card.menuOpen; return; }
            if (m.button === Qt.MiddleButton) { card.closed(); return; }
            if (card.menuOpen) { card.menuOpen = false; return; }
            if (card.defaultAction) { card.defaultAction.invoke(); card.closed(); }
            else if (card.count > 1) card.expandToggled();
        }
    }

    Row {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: card.nested ? 8 : 12; leftMargin: 14 }
        spacing: 10

        // image (album art, avatar) or app icon
        Item {
            id: pic
            width: card.nested ? 28 : 36; height: width
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
            width: parent.width - (pic.visible ? pic.width + 10 : 0)
            spacing: 3

            Item {
                width: parent.width
                height: 14
                visible: !card.nested
                Label {
                    anchors { left: parent.left; right: tail.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    text: (card.notif ? card.notif.appName || "notification" : "").toUpperCase()
                          + (card.count > 1 ? "  ·  " + card.count : "")
                    color: card.count > 1 ? Theme.a1 : Theme.dim
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }
                Row {
                    id: tail
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 10
                    Label { text: Notifs.ago(card.notif); color: Theme.dim; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        visible: card.count > 1
                        text: "\u{F0140}"
                        rotation: card.expanded ? 180 : 0
                        color: card.expanded ? Theme.a1 : Theme.dim
                        font.pixelSize: 13
                        Behavior on rotation { NumberAnimation { duration: Theme.dur(150) } }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: card.expandToggled() }
                    }
                    Label {
                        text: card.count > 1 && !card.expanded ? "✕ all" : "✕"
                        color: Theme.dim
                        font.pixelSize: 11
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: card.closed() }
                    }
                }
            }
            Item {
                width: parent.width
                height: summary.implicitHeight
                Label {
                    id: summary
                    anchors { left: parent.left; right: nestedTail.left; rightMargin: 6 }
                    text: card.notif ? card.notif.summary : ""
                    font.bold: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                Row {
                    id: nestedTail
                    visible: card.nested
                    width: visible ? implicitWidth : 0
                    anchors { right: parent.right; top: parent.top }
                    spacing: 8
                    Label { text: Notifs.ago(card.notif); color: Theme.dim; font.pixelSize: 10 }
                    Label {
                        text: "✕"; color: Theme.dim; font.pixelSize: 11
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: card.closed() }
                    }
                }
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
            Flow {
                width: parent.width
                visible: card.buttons.length > 0 || (card.canReply && !card.replying)
                topPadding: 4
                spacing: 6
                Repeater {
                    model: card.buttons
                    delegate: ChipButton {
                        required property var modelData
                        anchors.verticalCenter: undefined
                        text: modelData.text
                        onClicked: { modelData.invoke(); card.closed(); }
                    }
                }
                ChipButton {
                    visible: card.canReply && !card.replying
                    anchors.verticalCenter: undefined
                    text: "\u{F0167}  reply"
                    onClicked: { card.replying = true; Qt.callLater(() => reply.forceActiveFocus()); }
                }
            }

            // inline reply
            Rectangle {
                visible: card.replying
                width: parent.width
                height: visible ? 30 : 0
                radius: Theme.radius * 0.7
                color: Theme.bg
                border.width: 1
                border.color: reply.activeFocus ? Theme.a1 : Theme.line
                TextInput {
                    id: reply
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 12
                    clip: true
                    onAccepted: {
                        if (text.length && card.notif) { card.notif.sendInlineReply(text); text = ""; card.replying = false; card.closed(); }
                    }
                    Keys.onEscapePressed: { text = ""; card.replying = false; }
                }
                Label {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    visible: reply.text.length === 0
                    text: (card.notif && card.notif.inlineReplyPlaceholder) || "reply…  (enter sends, esc cancels)"
                    color: Theme.dim
                    font.pixelSize: 11
                }
            }

            // per-app quick rules (right click)
            Flow {
                id: rulesStrip
                visible: card.menuOpen && !!card.notif
                width: parent.width
                topPadding: 6
                spacing: 6
                readonly property var r: card.notif ? Notifs.appRule(card.notif) : null
                readonly property string mode: r ? (r.mode || "normal") : "normal"
                Label { text: "RULES FOR " + (card.notif ? (card.notif.appName || "?").toUpperCase() : ""); color: Theme.dim; font.pixelSize: 9; font.letterSpacing: 1.2; height: 20; verticalAlignment: Text.AlignVCenter; width: parent.width }
                ChipButton {
                    small: true; anchors.verticalCenter: undefined
                    text: "mute"; danger: rulesStrip.mode !== "mute"; accent: rulesStrip.mode === "mute"
                    onClicked: { Notifs.quickRule(card.notif, { mode: rulesStrip.mode === "mute" ? "normal" : "mute" }); card.menuOpen = false; }
                }
                ChipButton {
                    small: true; anchors.verticalCenter: undefined
                    text: "silent"; accent: rulesStrip.mode === "silent"
                    onClicked: Notifs.quickRule(card.notif, { mode: rulesStrip.mode === "silent" ? "normal" : "silent" })
                }
                ChipButton {
                    small: true; anchors.verticalCenter: undefined
                    text: "keep until closed"; accent: !!(rulesStrip.r && rulesStrip.r.timeout === 0)
                    onClicked: Notifs.quickRule(card.notif, { timeout: rulesStrip.r && rulesStrip.r.timeout === 0 ? -1 : 0 })
                }
                ChipButton {
                    small: true; anchors.verticalCenter: undefined
                    text: "ignore dnd"; accent: !!(rulesStrip.r && rulesStrip.r.dnd)
                    onClicked: Notifs.quickRule(card.notif, { dnd: !(rulesStrip.r && rulesStrip.r.dnd) })
                }
                ChipButton {
                    small: true; anchors.verticalCenter: undefined
                    text: "no sound"; accent: !!(rulesStrip.r && rulesStrip.r.sound === false)
                    onClicked: Notifs.quickRule(card.notif, { sound: !!(rulesStrip.r && rulesStrip.r.sound === false) })
                }
                ChipButton {
                    small: true; anchors.verticalCenter: undefined
                    text: "all rules…"
                    onClicked: { card.menuOpen = false; Quickshell.execDetached(["qs", "-c", "sigil", "ipc", "call", "settings", "open", "notifications"]); }
                }
            }
        }
    }
}
