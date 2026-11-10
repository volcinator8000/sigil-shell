pragma ComponentBehavior: Bound

// Power menu (replaces wlogout). Arrow keys / Tab to move, Enter to run,
// or the letter shown on each card.

import QtQuick
import Quickshell
import qs.services
import qs.components

Overlay {
    id: menu
    shown: Actions.powerOpen
    panelWidth: row.implicitWidth + 36
    panelHeight: 150 + 36
    onDismissed: Actions.powerOpen = false
    requestedCorner: Actions.openCorner
    pocketable: true
    panelHovered: rowHover.hovered

    readonly property var items: [
        { key: "L", label: "lock",      glyph: 0xF033E, cmd: [] },
        { key: "E", label: "logout",    glyph: 0xF0343, cmd: ["loginctl", "terminate-user", Quickshell.env("USER")] },
        { key: "S", label: "suspend",   glyph: 0xF04B2, cmd: ["systemctl", "suspend"] },
        { key: "H", label: "hibernate", glyph: 0xF0717, cmd: ["systemctl", "hibernate"] },
        { key: "R", label: "reboot",    glyph: 0xF0709, cmd: ["systemctl", "reboot"] },
        { key: "P", label: "shutdown",  glyph: 0xF0425, cmd: ["systemctl", "poweroff"] }
    ]
    property int current: 0
    onShownChanged: if (shown) { current = 0; row.forceActiveFocus(); }

    function activate(i) {
        const it = items[i];
        Actions.powerOpen = false;
        Actions.sound("click");
        if (it.label === "lock") Lock.lock();
        else Quickshell.execDetached(it.cmd);
    }

    // own container when opened by key / click (in a corner the Pocket is the container)
    Rectangle {
        visible: !menu.pocket
        anchors.fill: parent
        radius: Theme.radius * 1.4
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12
        focus: true

        HoverHandler { id: rowHover }

        Keys.onLeftPressed: menu.current = (menu.current + menu.items.length - 1) % menu.items.length
        Keys.onRightPressed: menu.current = (menu.current + 1) % menu.items.length
        Keys.onTabPressed: menu.current = (menu.current + 1) % menu.items.length
        Keys.onReturnPressed: menu.activate(menu.current)
        Keys.onEnterPressed: menu.activate(menu.current)
        Keys.onEscapePressed: Actions.powerOpen = false
        Keys.onPressed: (e) => {
            const i = menu.items.findIndex(it => it.key === e.text.toUpperCase());
            if (i >= 0) { menu.activate(i); e.accepted = true; }
        }

        Repeater {
            model: menu.items
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index
                readonly property bool active: menu.current === index
                readonly property bool danger: modelData.label === "shutdown" || modelData.label === "reboot"

                width: 132
                height: 150
                radius: Theme.radius * 1.2
                // solid: tinted towards the accent, never see-through
                color: active ? Qt.tint(Theme.s2, Theme.alpha(danger ? Theme.crit : Theme.a1, 0.16)) : Theme.s2
                border.width: 1
                border.color: active ? (danger ? Theme.crit : Theme.a1) : Theme.line
                scale: active ? 1.04 : 1
                Behavior on scale { NumberAnimation { duration: Theme.dur(160); easing.type: Easing.OutBack } }
                Behavior on color { ColorAnimation { duration: Theme.dur(140) } }

                // glow under the active card
                Rectangle {
                    z: -1
                    anchors.fill: parent
                    anchors.margins: -6
                    radius: parent.radius + 6
                    color: Theme.alpha(card.danger ? Theme.crit : Theme.a1, 0.12)
                    visible: false
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String.fromCodePoint(card.modelData.glyph)
                        font.pixelSize: 38
                        color: card.active ? (card.danger ? Theme.crit : Theme.a1) : Theme.fg
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: card.modelData.label.toUpperCase()
                        font.letterSpacing: 2
                        font.pixelSize: 11
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: card.modelData.key
                        color: Theme.dim
                        font.pixelSize: 10
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: menu.current = card.index
                    onClicked: menu.activate(card.index)
                }
            }
        }
    }
}
