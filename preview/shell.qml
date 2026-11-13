//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
pragma ComponentBehavior: Bound

// Widget preview: one desktop widget in its own window, drawn by the real WidgetFrame
// (same styles, glass over the wallpaper, corner label). Used by bin/sigil-widgets.
// Run: qs -p ~/sigil-shell/preview   (this dir links the shell's services, components, widgets)
// What to show is read from ~/.cache/sigil/preview.json, or the file in $SIGIL_PREVIEW, and
// follows its changes: type, source (a draft .qml to load instead of the type's own),
// style, opts, w, h, scale. With snapshot set to a .png path it renders once, saves, quits.
// (Keep this header free of braces and angle brackets: the qs import scanner trips on them.)

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "widgets"

ShellRoot {
    id: shell
    readonly property string specPath: Quickshell.env("SIGIL_PREVIEW") || (Theme.home + "/.cache/sigil/preview.json")
    property var spec: ({ type: "clock", style: "frost" })

    FileView {
        path: shell.specPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { shell.spec = JSON.parse(text()); } catch (e) {} }
    }

    // sensors normally run only while the desktop is in view; here they always do
    Component.onCompleted: { Sys.users++; }

    readonly property var entry: ({
        id: -1, type: spec.type || "clock", style: spec.style || "frost",
        ax: "center", x: 0, ay: "center", y: 0,
        opacity: 1, scale: spec.scale || 1,
        w: spec.w || undefined, h: spec.h || undefined,
        opts: Object.assign(Widgets.defaultOpts(spec.type || "clock"), spec.opts || {})
    })

    FloatingWindow {
        id: win
        title: Quickshell.env("SIGIL_PREVIEW_TITLE") || "sigil widget preview"
        color: Theme.bg
        // fixed size (Hyprland keeps the first size anyway); the widget sits in the middle
        implicitWidth: 1000
        implicitHeight: 760
        readonly property int pad: 36
        visible: true

        Item {
        id: stage
        anchors.fill: parent
        clip: true
        // a virtual screen at the layout's reference height, so the widget is drawn 1:1
        Item {
            id: screenArea
            width: 2400
            height: Theme.widgetRefHeight
            x: Math.round((stage.width - frame.vw) / 2 - frame.x)
            y: Math.round((stage.height - frame.vh) / 2 - frame.y)

            // the wallpaper behind, as on the desktop (the frost style shows a softened copy of it)
            Image {
                anchors.fill: parent
                source: Wallpapers.still ? "file://" + Wallpapers.still : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: 0.9
            }

            WidgetFrame {
                id: frame
                entry: shell.entry
                editing: false
                sourceOverride: shell.spec.source || ""
            }
        }

        }

        // snapshot mode: render, save, quit
        Timer {
            running: !!shell.spec.snapshot
            interval: shell.spec.snapshotDelay || 3500
            onTriggered: {
                // the widget's rectangle in the image, for the caller to crop: SNAP x y w h
                console.log("SNAP", Math.round(screenArea.x + frame.x), Math.round(screenArea.y + frame.y), Math.ceil(frame.vw), Math.ceil(frame.vh));
                stage.grabToImage(r => { r.saveToFile(shell.spec.snapshot); Qt.quit(); });
            }
        }
    }
}
