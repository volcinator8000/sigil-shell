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
        // the note editor opened from a raised notes widget needs the keyboard
        WlrLayershell.keyboardFocus: Actions.notePath ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        Rectangle {
            anchors.fill: parent
            color: Theme.alpha(Theme.bg, Widgets.editing ? 0.72 : 0.55)
            opacity: raisedWin.openness
            focus: true
            Keys.onEscapePressed: { if (Widgets.editing && Widgets.selected >= 0) Widgets.selected = -1; else { Widgets.editing = false; Widgets.peek = false; } }
            // edit-mode keys for the selected widget
            Keys.onPressed: (e) => {
                if (!Widgets.editing) return;
                if (e.key === Qt.Key_Tab) { Widgets.selectNext(1); e.accepted = true; return; }
                if (e.key === Qt.Key_Backtab) { Widgets.selectNext(-1); e.accepted = true; return; }
                const id = Widgets.selected;
                if (id < 0) return;
                const step = (e.modifiers & Qt.ShiftModifier) ? Math.max(10, Widgets.grid) : 1;
                switch (e.key) {
                case Qt.Key_Left:  Widgets.nudge(id, -step, 0); break;
                case Qt.Key_Right: Widgets.nudge(id, step, 0); break;
                case Qt.Key_Up:    Widgets.nudge(id, 0, -step); break;
                case Qt.Key_Down:  Widgets.nudge(id, 0, step); break;
                case Qt.Key_Plus: case Qt.Key_Equal: Widgets.stepScale(id, 0.05); break;
                case Qt.Key_Minus: Widgets.stepScale(id, -0.05); break;
                case Qt.Key_BracketRight: Widgets.reorder(id, 1); break;
                case Qt.Key_BracketLeft:  Widgets.reorder(id, -1); break;
                case Qt.Key_Delete: case Qt.Key_Backspace: Widgets.remove(id); break;
                case Qt.Key_D: if (e.modifiers & Qt.ControlModifier) Widgets.selected = Widgets.duplicate(id); else return; break;
                case Qt.Key_S: Widgets.cycleStyle(id); break;
                default: return;
                }
                e.accepted = true;
            }
            MouseArea {
                anchors.fill: parent
                // edit mode: empty space deselects. Peek stays up until Esc, so the widgets
                // can be used (clicks on empty space do nothing).
                onClicked: if (Widgets.editing) Widgets.selected = -1
            }
        }

        // snap grid (settings.json → widgets.grid; hidden when free placement)
        Canvas {
            id: gridCanvas
            anchors.fill: parent
            visible: Widgets.editing && Widgets.grid > 0
            opacity: 0.5 * raisedWin.openness
            onVisibleChanged: if (visible) requestPaint()
            Connections { target: Widgets; function onGridChanged() { gridCanvas.requestPaint(); } }
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = Theme.alpha(Theme.a2, 0.18);
                ctx.lineWidth = 1;
                ctx.beginPath();
                const g = Math.max(4, Widgets.grid);
                for (let x = 0.5; x < width; x += g) { ctx.moveTo(x, 0); ctx.lineTo(x, height); }
                for (let y = 0.5; y < height; y += g) { ctx.moveTo(0, y); ctx.lineTo(width, y); }
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

        // Edit toolbar
        Rectangle {
            visible: Widgets.editing
            opacity: raisedWin.openness
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 48 }
            implicitWidth: Math.max(bar.implicitWidth, hint.implicitWidth) + 24
            implicitHeight: 58
            radius: Theme.radius
            color: Theme.s1
            border.width: 1
            border.color: Theme.a1

            Label {
                id: hint
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 5 }
                text: Widgets.selected >= 0
                      ? "arrows move · shift+arrows by grid · + − size · [ ] order · ctrl+D duplicate · S style · Del remove · Esc deselect"
                      : "click a widget to select it · Tab cycles · drag to move · Esc or Done to finish"
                color: Theme.dim
                font.pixelSize: 10
            }
            Row {
                id: bar
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 7 }
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
                ChipButton { text: Widgets.grid > 0 ? "grid " + Widgets.grid : "grid off"; onClicked: Widgets.cycleGrid() }
                ChipButton { text: "settings"; onClicked: Widgets.openOptions(Widgets.selected) }
                ChipButton { text: "Done"; accent: true; onClicked: Widgets.editing = false }
            }
        }
    }
}
