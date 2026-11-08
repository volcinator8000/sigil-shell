pragma ComponentBehavior: Bound

// Desktop widget layer for one screen.
//  • normal: a full-screen surface on the Bottom layer (behind windows, above the wallpaper)
//  • peek / edit: the same widgets on the Overlay layer, above windows, with a dim
//    backdrop. Edit mode adds a grid, drag + snap, per-widget controls and an add bar.
//    Esc or a click on empty space leaves either mode.

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

Scope {
    id: root
    required property ShellScreen screen
    readonly property bool raised: Widgets.editing || Widgets.peek

    // Behind windows
    PanelWindow {
        screen: root.screen
        visible: !root.raised
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "sigil-desktop"
        WidgetCanvas { anchors.fill: parent; editing: false }
    }

    // Above windows (dashboard peek / edit mode)
    PanelWindow {
        id: raisedWin
        screen: root.screen
        visible: root.raised
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "sigil-desktop-raised"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: Theme.alpha(Theme.bg, Widgets.editing ? 0.72 : 0.55)
            focus: true
            Keys.onEscapePressed: { Widgets.editing = false; Widgets.peek = false; }
            MouseArea {
                anchors.fill: parent
                onClicked: { Widgets.editing = false; Widgets.peek = false; }
            }
        }

        // 20 px snap grid
        Canvas {
            anchors.fill: parent
            visible: Widgets.editing
            opacity: 0.5
            onVisibleChanged: if (visible) requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = Theme.alpha(Theme.a2, 0.18);
                ctx.lineWidth = 1;
                ctx.beginPath();
                for (let x = 0.5; x < width; x += 20) { ctx.moveTo(x, 0); ctx.lineTo(x, height); }
                for (let y = 0.5; y < height; y += 20) { ctx.moveTo(0, y); ctx.lineTo(width, y); }
                ctx.stroke();
            }
        }

        WidgetCanvas { anchors.fill: parent; editing: Widgets.editing }

        // Edit toolbar
        Rectangle {
            visible: Widgets.editing
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 48 }
            implicitWidth: bar.implicitWidth + 20
            implicitHeight: 36
            radius: Theme.radius
            color: Theme.s1
            border.width: 1
            border.color: Theme.a1

            Row {
                id: bar
                anchors.centerIn: parent
                spacing: 6
                Label { text: "ADD"; color: Theme.dim; font.pixelSize: 10; font.letterSpacing: 1.4; anchors.verticalCenter: parent.verticalCenter; rightPadding: 4 }
                Repeater {
                    model: Widgets.types
                    delegate: ChipButton {
                        required property var modelData
                        text: "+ " + modelData.label
                        onClicked: Widgets.add(modelData.type)
                    }
                }
                Rectangle { width: 1; height: 18; color: Theme.line; anchors.verticalCenter: parent.verticalCenter }
                ChipButton { text: "Done"; accent: true; onClicked: Widgets.editing = false }
            }
        }
    }
}
