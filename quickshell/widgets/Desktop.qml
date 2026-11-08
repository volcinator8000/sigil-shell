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
        visible: !root.raised && raisedWin.openness < 0.001
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
        property real openness: root.raised ? 1 : 0
        Behavior on openness { NumberAnimation { duration: root.raised ? Theme.dur(220) : Theme.dur(160); easing.type: root.raised ? Easing.OutCubic : Easing.InCubic } }
        visible: root.raised || openness > 0.001
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "sigil-desktop-raised"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: Theme.alpha(Theme.bg, Widgets.editing ? 0.72 : 0.55)
            opacity: raisedWin.openness
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
            opacity: 0.5 * raisedWin.openness
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

        WidgetCanvas {
            id: raisedCanvas
            anchors.fill: parent
            editing: Widgets.editing
            opacity: raisedWin.openness
            scale: 0.97 + 0.03 * raisedWin.openness
        }

        // Raised from a hot corner: close once the pointer leaves the corner and the widgets.
        readonly property bool fromCorner: Widgets.peek && Widgets.peekCorner !== ""
        readonly property bool inside: raisedCanvas.anyHovered || peekZone.containsMouse
        property bool armed: false
        onFromCornerChanged: armed = false
        onInsideChanged: { if (!fromCorner) return; if (inside) { peekLeave.stop(); armed = true; } else if (armed) peekLeave.restart(); }
        Timer { id: peekLeave; interval: 300; onTriggered: if (!raisedWin.inside) Widgets.peek = false }
        MouseArea {
            id: peekZone
            visible: raisedWin.fromCorner
            width: 90; height: 90
            x: Widgets.peekCorner.endsWith("Left") ? 0 : parent.width - width
            y: Widgets.peekCorner.startsWith("top") ? 0 : parent.height - height
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

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
