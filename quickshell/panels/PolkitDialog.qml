pragma ComponentBehavior: Bound

// Polkit authentication agent (replaces hyprpolkitagent in sigil mode), so
// pkexec and GUI admin prompts ask for the password in a sigil-styled dialog.

import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import qs.services
import qs.components

Scope {
    id: root

    PolkitAgent { id: agent }
    readonly property var flow: agent.flow

    Overlay {
        id: dlg
        shown: agent.isActive && root.flow !== null && !root.flow.isCompleted
        dim: 0.55
        onDismissed: if (root.flow) root.flow.cancelAuthenticationRequest()
        onShownChanged: if (shown) { pw.text = ""; pw.forceActiveFocus(); }

        Rectangle {
            id: box
            anchors.centerIn: parent
            width: 440
            height: col.implicitHeight + 36
            radius: Theme.radius * 1.2
            color: Theme.s1
            border.width: 1
            border.color: root.flow && root.flow.failed ? Theme.crit : Theme.a1
            MouseArea { anchors.fill: parent }

            Column {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
                spacing: 12

                Row {
                    spacing: 10
                    Label { text: String.fromCodePoint(0xF0483); font.pixelSize: 22; color: Theme.a1 }
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "AUTHENTICATION REQUIRED"; font.letterSpacing: 2; font.pixelSize: 11; color: Theme.dim }
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: root.flow ? root.flow.message : ""
                    font.pixelSize: 13
                }
                Label {
                    width: parent.width
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                    text: root.flow ? (root.flow.supplementaryMessage || "") : ""
                    color: root.flow && root.flow.supplementaryIsError ? Theme.crit : Theme.dim
                    font.pixelSize: 11
                }
                Label {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: root.flow ? root.flow.actionId : ""
                    color: Theme.dim
                    font.pixelSize: 10
                }
                Rectangle {
                    width: parent.width
                    height: 40
                    radius: Theme.radius
                    color: Theme.s2
                    border.width: 1
                    border.color: pw.activeFocus ? Theme.a1 : Theme.line
                    TextInput {
                        id: pw
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: (root.flow && root.flow.responseVisible) ? TextInput.Normal : TextInput.Password
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 14
                        focus: true
                        enabled: root.flow !== null && root.flow.isResponseRequired
                        onAccepted: if (root.flow && text.length > 0) { root.flow.submit(text); text = ""; }
                        Keys.onEscapePressed: if (root.flow) root.flow.cancelAuthenticationRequest()
                    }
                    Label {
                        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                        visible: pw.text.length === 0
                        text: root.flow && root.flow.failed ? "wrong password, try again" : (root.flow ? (root.flow.inputPrompt || "password") : "")
                        color: root.flow && root.flow.failed ? Theme.crit : Theme.dim
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    ChipButton { text: "cancel"; onClicked: if (root.flow) root.flow.cancelAuthenticationRequest() }
                    ChipButton { text: "authenticate"; accent: true; onClicked: pw.accepted() }
                }
            }
        }
    }
}
