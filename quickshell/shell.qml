//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
pragma ComponentBehavior: Bound

// sigil-shell entry point. One bar, one set of hot corners and one widget layer
// per screen, plus the shared media panel.

import QtQuick
import Quickshell
import "bar"
import "corners"
import "widgets"
import "panels"

ShellRoot {
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: perScreen
            required property ShellScreen modelData

            Bar { screen: perScreen.modelData }
            HotCorners { screen: perScreen.modelData }
            Desktop { screen: perScreen.modelData }
        }
    }

    MediaPanel {}
}
