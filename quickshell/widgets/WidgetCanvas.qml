pragma ComponentBehavior: Bound

import QtQuick
import qs.services

Item {
    id: root
    property bool editing: false
    Repeater {
        model: Widgets.items
        delegate: WidgetFrame {
            required property var modelData
            entry: modelData
            editing: root.editing
        }
    }
}
