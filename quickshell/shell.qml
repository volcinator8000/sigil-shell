//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
pragma ComponentBehavior: Bound

// sigil-shell entry point. Per screen: wallpaper, widget layer, bar, hot corners.
// Shared: launcher, control center, notifications, power menu, OSD, lock, polkit, settings.

import QtQuick
import Quickshell
import qs.services
import "bar"
import "corners"
import "widgets"
import "panels"
import "settings"

ShellRoot {
    // singletons start when first used; these run in the background and have no UI of their own
    readonly property var services: [PowerAuto.enabled, Players.active]
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: perScreen
            required property ShellScreen modelData

            Bar { screen: perScreen.modelData }
            HotCorners { screen: perScreen.modelData }
            Desktop { screen: perScreen.modelData }
            Wallpaper { screen: perScreen.modelData }
        }
    }

    MediaPanel {}
    Launcher {}
    ControlCenter {}
    NotificationPopups {}
    PowerMenu {}
    Osd {}
    LockScreen {}
    PolkitDialog {}
    Settings {}
}
