pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

PanelWindow {
    id: bar

    anchors { top: true; left: true; right: true }
    // flush with the screen top; the window reaches `fillet` px lower so the bar's bottom
    // corners can curve out into the screen edges (inverted radius). Only the bar itself
    // reserves space and takes input.
    readonly property int barH: Theme.bs(30)
    readonly property int fillet: Theme.radius + 2
    implicitHeight: barH + fillet
    exclusiveZone: barH
    mask: Region { item: frame }
    color: "transparent"
    WlrLayershell.namespace: "sigil-bar"
    WlrLayershell.layer: WlrLayer.Top

    property color fill: Theme.rich ? Theme.alpha(Theme.s1, 0.78) : Theme.s1
    Behavior on fill { ColorAnimation { duration: Theme.dur(300) } }

    // one path for bar + both fillets, so the translucent fill has no seams
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: bar.fill
            strokeColor: "transparent"
            startX: 0; startY: 0
            PathLine { x: bar.width; y: 0 }
            PathLine { x: bar.width; y: bar.barH + bar.fillet }
            PathArc { x: bar.width - bar.fillet; y: bar.barH; radiusX: bar.fillet; radiusY: bar.fillet; direction: PathArc.Counterclockwise }
            PathLine { x: bar.fillet; y: bar.barH }
            PathArc { x: 0; y: bar.barH + bar.fillet; radiusX: bar.fillet; radiusY: bar.fillet; direction: PathArc.Counterclockwise }
            PathLine { x: 0; y: 0 }
        }
        // hairline along the lower contour only
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.line
            strokeWidth: 1
            startX: bar.width - 0.5; startY: bar.barH + bar.fillet
            PathArc { x: bar.width - bar.fillet; y: bar.barH - 0.5; radiusX: bar.fillet - 0.5; radiusY: bar.fillet - 0.5; direction: PathArc.Counterclockwise }
            PathLine { x: bar.fillet; y: bar.barH - 0.5 }
            PathArc { x: 0.5; y: bar.barH + bar.fillet; radiusX: bar.fillet - 0.5; radiusY: bar.fillet - 0.5; direction: PathArc.Counterclockwise }
        }
    }

    Item {
        id: frame
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: bar.barH

        RowLayout {
            anchors { fill: parent; leftMargin: Theme.bs(10); rightMargin: Theme.bs(12) }
            spacing: Theme.bs(14)

            Label {
                text: "◆"
                color: Theme.a1
                font.bold: true
                font.pixelSize: Theme.bs(13)
            }

            Workspaces { monitorName: bar.screen ? bar.screen.name : "" }

            Label {
                id: title
                // window title gives way to the lyrics when something is playing
                Layout.fillWidth: !lyrics.visible
                Layout.maximumWidth: lyrics.visible ? 260 : -1
                elide: Text.ElideRight
                color: Theme.dim
                font.pixelSize: Theme.bs(12)
                // Some apps animate their title (terminal spinners, page loads): ~10 changes a
                // second, each one a bar redraw. Show the newest title at most every 350 ms.
                readonly property string live: Hyprland.activeToplevel ? (Hyprland.activeToplevel.title || "") : ""
                text: live
                onLiveChanged: {
                    if (titleGate.running) return;
                    text = live;
                    titleGate.start();
                }
                Timer { id: titleGate; interval: 350; onTriggered: title.text = title.live }
            }

            Lyrics {
                id: lyrics
                maxWidth: frame.width * 0.45
                Layout.preferredWidth: implicitWidth
            }

            Item { Layout.fillWidth: true; visible: lyrics.visible }

            TrayItems { window: bar }

            UpdatesButton { window: bar }

            // ultra power saver is on: click to leave it
            Label {
                visible: Theme.ultra
                text: String.fromCodePoint(0xF032A) + " ULTRA"
                color: Theme.warn
                font.bold: true
                font.letterSpacing: 1
                font.pixelSize: Theme.bs(11)
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached([Theme.home + "/.local/bin/ultra", "off"])
                }
            }

            StatusIcons {}

            Label {
                // notifications: count, or a slashed bell in do-not-disturb
                font.pixelSize: Theme.bs(14)
                color: Notifs.dnd ? Theme.dim : Notifs.count > 0 ? Theme.a1 : Theme.fg
                text: String.fromCodePoint(Notifs.dnd ? 0xF009B : Notifs.count > 0 ? 0xF116B : 0xF009A) + (Notifs.count > 0 && !Notifs.dnd ? " " + Notifs.count : "")
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => m.button === Qt.RightButton ? (Notifs.dnd = !Notifs.dnd) : Actions.run("controlcenter")
                }
            }

            Rectangle { implicitWidth: 1; implicitHeight: Theme.bs(14); color: Theme.line }

            Label {
                id: clock
                font.bold: true
                font.pixelSize: Theme.bs(12)
                text: Qt.formatDateTime(sysClock.date, "HH:mm")
                SystemClock { id: sysClock; precision: SystemClock.Minutes }
                MouseArea {
                    anchors.fill: parent
                    onClicked: Widgets.togglePeek()
                }
            }
        }
    }
}
