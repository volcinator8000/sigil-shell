pragma ComponentBehavior: Bound

// Session lock (replaces hyprlock in sigil mode). PAM service: /etc/pam.d/hyprlock,
// the same one hyprlock uses, so password rules don't change.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.services
import qs.components

Scope {
    id: root

    property string buffer: ""
    property string message: ""
    property bool error: false
    property bool busy: false
    signal failed()

    function submit(pw) {
        if (Lock.testMode) { Lock.unlock(); return; }
        if (pam.active || pw.length === 0) return;
        buffer = pw;
        busy = true;
        message = "";
        error = false;
        pam.start();
    }

    PamContext {
        id: pam
        config: "hyprlock"
        onPamMessage: {
            if (responseRequired) respond(root.buffer);
            else if (message) { root.message = message; root.error = messageIsError; }
        }
        onCompleted: (result) => {
            root.busy = false;
            root.buffer = "";
            if (result === PamResult.Success) { root.message = ""; Lock.unlock(); }
            else { root.message = result === PamResult.MaxTries ? "too many attempts" : "wrong password"; root.error = true; root.failed(); }
        }
        onError: (err) => { root.busy = false; root.buffer = ""; root.message = "authentication error"; root.error = true; root.failed(); }
    }

    FileView { id: hostFile; path: "/etc/hostname" }
    readonly property string host: (hostFile.text() || "").trim()
    readonly property string user: Quickshell.env("USER") || ""

    WlSessionLock {
        id: sessionLock
        locked: Lock.locked
        onLockedChanged: Lock.engaged = locked && secure
        onSecureChanged: Lock.engaged = locked && secure

        WlSessionLockSurface {
            id: surface
            color: Theme.bg

            SystemClock { id: clock; precision: SystemClock.Seconds }

            // wallpaper, blurred and darkened
            Image {
                id: wall
                anchors.fill: parent
                source: Theme.wallpaperPath ? "file://" + Theme.wallpaperPath : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: wall
                blurEnabled: Theme.rich
                blur: 1.0
                blurMax: 48
                brightness: -0.35
                saturation: -0.2
            }
            Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.bg, 0.35) }

            Column {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -60
                spacing: 6

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    font.pixelSize: 112
                    font.weight: Font.ExtraLight
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(clock.date, "ddd dd MMM").toUpperCase()
                    color: Theme.a1
                    font.pixelSize: 16
                    font.letterSpacing: 4
                }
                Item { width: 1; height: 36 }

                // password field
                Rectangle {
                    id: field
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 320
                    height: 46
                    radius: Theme.radius
                    color: Theme.alpha(Theme.s1, 0.85)
                    border.width: 1
                    border.color: root.error ? Theme.crit : input.activeFocus ? Theme.a1 : Theme.line
                    Behavior on border.color { ColorAnimation { duration: Theme.dur(150) } }

                    SequentialAnimation {
                        id: shake
                        NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 12; duration: 50 }
                        NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: -12; duration: 50 }
                        NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 8; duration: 50 }
                        NumberAnimation { target: field; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
                    }
                    Connections { target: root; function onFailed() { shake.restart(); input.text = ""; } }

                    // one dot per typed character
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: input.text.length > 0
                        Repeater {
                            model: Math.min(input.text.length, 24)
                            delegate: Rectangle { width: 8; height: 8; radius: 4; color: root.busy ? Theme.dim : Theme.a1 }
                        }
                    }
                    Label {
                        anchors.centerIn: parent
                        visible: input.text.length === 0
                        text: Lock.testMode ? "test lock · press Enter or wait 6 s" : root.busy ? "checking…" : "password"
                        color: Theme.dim
                    }
                    TextInput {
                        id: input
                        anchors.fill: parent
                        opacity: 0
                        focus: true
                        echoMode: TextInput.Password
                        enabled: !root.busy
                        onAccepted: root.submit(text)
                        onTextChanged: if (text.length > 0) root.error = false
                        Component.onCompleted: forceActiveFocus()
                    }
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.message
                    color: root.error ? Theme.crit : Theme.dim
                    font.pixelSize: 11
                    height: 16
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (root.host + " // " + root.user).toUpperCase()
                    color: Theme.dim
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }
            }

            // bottom-left: now playing
            Row {
                readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
                visible: player !== null && !!player.trackTitle
                anchors { left: parent.left; bottom: parent.bottom; margins: 36 }
                spacing: 12
                Rectangle {
                    width: 52; height: 52
                    radius: Theme.radius * 0.6
                    color: Theme.s2
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: parent.parent.player ? (parent.parent.player.trackArtUrl || "") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Label { text: parent.parent.player ? parent.parent.player.trackTitle : ""; font.bold: true }
                    Label { text: parent.parent.player ? (parent.parent.player.trackArtist || "") : ""; color: Theme.dim; font.pixelSize: 11 }
                }
            }

            // bottom-right: battery + away time
            Column {
                anchors { right: parent.right; bottom: parent.bottom; margins: 36 }
                spacing: 2
                Label {
                    anchors.right: parent.right
                    readonly property var b: UPower.displayDevice
                    visible: b && b.isLaptopBattery
                    text: b ? "BAT " + Math.round(b.percentage > 1 ? b.percentage : b.percentage * 100) + "%" + (UPower.onBattery ? "" : " · AC") : ""
                    color: Theme.dim
                    font.letterSpacing: 2
                    font.pixelSize: 11
                }
                Label {
                    anchors.right: parent.right
                    readonly property int mins: Math.floor((clock.date - Lock.lockedAt) / 60000)
                    text: "AWAY " + (mins < 60 ? mins + " MIN" : Math.floor(mins / 60) + " H " + (mins % 60) + " MIN")
                    color: Theme.dim
                    font.letterSpacing: 2
                    font.pixelSize: 11
                }
            }
        }
    }
}
