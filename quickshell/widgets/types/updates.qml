pragma ComponentBehavior: Bound

// Pending pacman + AUR updates (services/Updates.qml), with upgrade / check buttons.

import QtQuick
import qs.services
import qs.components

Column {
    id: root
    spacing: 7
    readonly property int w: Math.max(230, entry.w || 0)
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }
    readonly property int rows: o("rows")
    opacity: o("hideWhenCurrent") && Updates.count === 0 && !Updates.checking && !Updates.upgrading && !Widgets.editing ? 0.25 : 1
    Behavior on opacity { NumberAnimation { duration: Theme.dur(300) } }

    WidgetHeader {
        width: root.w
        title: "updates"
        detail: Updates.checking ? "checking…" : Updates.checkedAt ? Qt.formatTime(new Date(Updates.checkedAt), "HH:mm") : ""
    }

    Row {
        spacing: 10
        WLabel {
            text: Updates.upgrading ? "…" : Updates.state === "unknown" ? "—" : String(Updates.count)
            font.pixelSize: 34
            font.bold: true
            color: Updates.count >= 20 ? Theme.warn : Updates.count > 0 ? Theme.a1 : Theme.ok
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            WLabel { text: Updates.upgrading ? "upgrading" : Updates.count ? "pending" : Updates.state === "unknown" ? "not checked" : "up to date"; font.pixelSize: 11 }
            WLabel { text: "repo " + Updates.repo + "  ·  aur " + Updates.aur; color: Theme.widgetDim; font.pixelSize: 10 }
        }
    }

    Repeater {
        model: Updates.packages.slice(0, root.rows)
        delegate: Row {
            required property var modelData
            width: root.w
            WLabel { width: root.w * 0.55; elide: Text.ElideRight; text: parent.modelData.name; font.pixelSize: 10 }
            WLabel { width: root.w * 0.45; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight; text: parent.modelData.to; color: Theme.widgetDim; font.pixelSize: 10 }
        }
    }
    WLabel {
        visible: Updates.packages.length > root.rows && root.rows > 0
        text: "+ " + (Updates.packages.length - root.rows) + " more"
        color: Theme.widgetDim
        font.pixelSize: 10
    }

    Row {
        spacing: 6
        topPadding: 2
        ChipButton { text: "upgrade"; accent: Updates.count > 0; visible: Updates.count > 0 && !Updates.upgrading; onClicked: Updates.upgrade() }
        ChipButton { text: Updates.checking ? "checking…" : "check"; onClicked: Updates.check() }
    }
}
