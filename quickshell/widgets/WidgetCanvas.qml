pragma ComponentBehavior: Bound

import QtQuick
import qs.services

Item {
    id: root
    property bool editing: false
    property bool migrate: false      // convert old absolute positions (one canvas only)
    readonly property bool anyHovered: {
        for (let i = 0; i < rep.count; i++) { const it = rep.itemAt(i); if (it && it.hovered) return true; }
        return false;
    }
    Repeater {
        id: rep
        model: Widgets.items
        delegate: WidgetFrame {
            required property var modelData
            entry: modelData
            editing: root.editing
            migrate: root.migrate
        }
    }
}
