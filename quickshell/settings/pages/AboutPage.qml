pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false
    property string hyprVer: ""

    readonly property var keys: [
        ["SUPER + T", "terminal"], ["SUPER + R", "launcher"], ["SUPER + E", "files"], ["SUPER + B", "browser"],
        ["SUPER + N", "control center"], ["SUPER + I", "this app"], ["SUPER + L", "lock"], ["SUPER + Q", "close window"],
        ["SUPER + V", "float"], ["SUPER + SHIFT + V", "clipboard history"], ["SUPER + O", "emoji"], ["SUPER + P", "pop-out (pin)"],
        ["SUPER + F", "fullscreen"], ["SUPER + 1..9", "workspaces"], ["SUPER + S / D / M", "scratch · discord · spotify"],
        ["Print", "screenshot → satty"], ["SUPER + Print", "region → clipboard"]
    ]

    Component.onCompleted: Sh.run(["hyprctl", "version"], out => {
        const v = out.split(/\s+/);
        page.hyprVer = v.length > 1 ? v[1] : "";
    })

    Section {
        title: "Keys"
        Repeater {
            model: page.keys
            delegate: SettingRow {
                id: keyRow
                required property var modelData
                title: modelData[1]
                Rectangle {
                    implicitWidth: cap.implicitWidth + 16
                    implicitHeight: 22
                    radius: Math.min(Theme.radius * 0.5, 6)
                    color: Theme.bg
                    border.width: 1
                    border.color: Theme.line
                    Label { id: cap; anchors.centerIn: parent; text: keyRow.modelData[0]; color: Theme.a1; font.pixelSize: 11 }
                }
            }
        }
    }

    Section {
        title: "Sigil"
        SettingRow { title: "Palette"; subtitle: "cherenkov blue · plasmatic purple · snooze pink · communication red · wavelength green · infrared · phosphorus amber" }
        SettingRow { title: "Stack"; subtitle: "hyprland " + page.hyprVer + " · sigil-shell (quickshell) · waybar · swaync · hyprlock · kitty · rofi · zsh + starship" }
        SettingRow { title: "Repo"; subtitle: "github.com/volcinator8000/dotfiles-and-scripts" }
    }
}
