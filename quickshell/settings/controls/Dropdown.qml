pragma ComponentBehavior: Bound

// Combo box: a button showing the current entry and a popup list.
// `activated(index)` fires on user selection only.

import QtQuick
import QtQuick.Controls as QQC
import qs.services
import qs.components
import qs.settings.lib

Rectangle {
    id: root
    property var model: []            // strings
    property int currentIndex: 0
    property int maxPopupHeight: 300
    readonly property string currentText: currentIndex >= 0 && currentIndex < model.length ? String(model[currentIndex]) : ""
    signal activated(int index)
    function open() { popup.open(); }
    function close() { popup.close(); }

    implicitWidth: 200
    implicitHeight: 28
    radius: Math.min(Theme.radius * 0.7, height / 2)
    color: mouse.containsMouse || popup.opened ? Theme.s2 : Theme.bg
    border.width: 1
    border.color: popup.opened ? Theme.a1 : mouse.containsMouse ? Theme.a2 : Theme.line
    opacity: enabled ? 1 : 0.4

    Label {
        anchors { left: parent.left; leftMargin: 10; right: chevron.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
        text: root.currentText || "—"
        elide: Text.ElideRight
    }
    Label {
        id: chevron
        anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
        text: "\u{F0140}"
        color: popup.opened ? Theme.a1 : Theme.dim
        rotation: popup.opened ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.dur(140) } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.opened ? popup.close() : popup.open()
    }

    QQC.Popup {
        id: popup
        y: root.height + 4
        width: Math.max(root.width, 160)
        height: Math.min(list.contentHeight + 10, root.maxPopupHeight)
        padding: 5
        modal: false
        focus: true
        closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside
        onOpened: list.positionViewAtIndex(Math.max(0, root.currentIndex), ListView.Contain)
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.dur(120) } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.dur(90) } }
        background: Rectangle {
            radius: Theme.radius
            color: Theme.s1
            border.width: 1
            border.color: Theme.a2
        }
        contentItem: ListView {
            id: list
            clip: true
            model: root.model
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: item
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 26
                radius: Math.min(Theme.radius * 0.6, 8)
                color: im.containsMouse ? Theme.s2 : item.index === root.currentIndex ? Theme.alpha(Theme.a1, 0.1) : "transparent"
                Rectangle {
                    visible: item.index === root.currentIndex
                    width: 2
                    height: parent.height - 8
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.a1
                }
                Label {
                    anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: String(item.modelData)
                    color: item.index === root.currentIndex ? Theme.a1 : Theme.fg
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: im
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        popup.close();
                        if (item.index !== root.currentIndex) {
                            Sh.snd("click");
                            root.currentIndex = item.index;
                            root.activated(item.index);
                        }
                    }
                }
            }
        }
    }
}
