pragma ComponentBehavior: Bound

// Notifications: grouping, timing, and per-app rules (settings.json → notifications).
// Rules are checked top to bottom; the first that matches a notification decides.
// Right-clicking a notification card makes quick rules too.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false

    readonly property var cfg: Theme.notifications || {}
    readonly property var modes: ["normal", "silent", "mute"]
    readonly property var timeouts: [-1, 3000, 6000, 10000, 30000, 0]
    readonly property var timeoutLabels: ["app decides", "3 s", "6 s", "10 s", "30 s", "until closed"]
    readonly property var urgencies: ["", "low", "normal", "critical"]
    readonly property var urgencyLabels: ["as sent", "low", "normal", "critical"]
    readonly property var unruled: Notifs.knownApps.filter(a => !Notifs.rules.some(r => (r.app || "").toLowerCase() === a && !r.match))

    function patch(p) { Theme.patchSettings({ notifications: p }); }

    Section {
        title: "Behaviour"
        description: "Popups and the history in the control center group notifications by app. Right-click any notification for quick rules."
        SettingRow {
            title: "Group by app"; subtitle: "One card per app with a count; click the arrow to see each message"
            Toggle { checked: page.cfg.group !== false; onToggled: (c) => page.patch({ group: c }) }
        }
        SettingRow {
            title: "Popup time"; subtitle: "Seconds a popup stays when the app doesn't say (hovering pauses it)"
            SpinField { from: 2; to: 60; value: Math.round(Notifs.defaultTimeout / 1000); onValueModified: (v) => page.patch({ timeout: Math.round(v) * 1000 }) }
        }
        SettingRow {
            title: "Popups on screen"; subtitle: "Most app groups shown at once"
            SpinField { from: 1; to: 10; value: Notifs.maxPopups; onValueModified: (v) => page.patch({ maxPopups: Math.round(v) }) }
        }
        SettingRow {
            title: "Do not disturb"; subtitle: "Only critical notifications and apps set to ignore it pop up"
            Toggle { checked: Notifs.dnd; onToggled: (c) => Notifs.dnd = c }
        }
        SettingRow {
            title: "Test"; subtitle: Notifs.mutedCount > 0 ? Notifs.mutedCount + " notification(s) muted by rules since the shell started" : "Send a sample notification"
            ActionButton { text: "send test"; onClicked: Notifs.test("sigil-test", "Test notification") }
        }
    }

    Section {
        title: "Apps with their own sound"
        description: "These apps already play a sound when they notify, so the shell's notification sound is skipped for them (Discord, Slack, Signal…). Matched as part of the app name."
        Flow {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 6
            Repeater {
                model: Notifs.ownSound
                delegate: Rectangle {
                    id: chip
                    required property string modelData
                    width: chipRow.implicitWidth + 18
                    height: 26
                    radius: 13
                    color: Theme.alpha(Theme.fg, 0.05)
                    border.width: 1
                    border.color: Theme.line
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Label { text: chip.modelData; font.pixelSize: 11 }
                        Label {
                            text: "\u{F0156}"
                            color: rm.containsMouse ? Theme.crit : Theme.dim
                            font.pixelSize: 11
                            MouseArea { id: rm; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: Notifs.setOwnSound(Notifs.ownSound.filter(a => a !== chip.modelData)) }
                        }
                    }
                }
            }
            TextField {
                id: ownField
                implicitWidth: 150
                implicitHeight: 26
                placeholder: "+ add app"
                onAccepted: {
                    const a = text.trim().toLowerCase();
                    if (a && Notifs.ownSound.indexOf(a) < 0) Notifs.setOwnSound(Notifs.ownSound.concat([a]));
                    text = "";
                }
            }
        }
    }

    Section {
        title: "App rules"
        description: "Matched against the app name (case-insensitive). Add a pattern to only match some messages, e.g. a regex on the title or body. First match wins; use the arrows to reorder."
        actions: [
            Dropdown {
                id: appPick
                implicitWidth: 170
                visible: page.unruled.length > 0
                model: page.unruled
            },
            ActionButton {
                text: "+ rule for app"
                visible: page.unruled.length > 0
                onClicked: Notifs.addRule({ app: page.unruled[appPick.currentIndex] || "" })
            },
            ActionButton { text: "+ blank rule"; onClicked: Notifs.addRule({}) }
        ]

        Label {
            visible: Notifs.rules.length === 0
            Layout.fillWidth: true
            Layout.margins: 14
            text: "No rules yet. Every app gets popups, sound and the default timeout."
            color: Theme.dim
        }

        Repeater {
            model: Notifs.rules
            delegate: Rectangle {
                id: rc
                required property var modelData
                required property int index
                readonly property var r: modelData
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: index === 0 ? 8 : 0
                Layout.bottomMargin: 8
                implicitHeight: ruleCol.implicitHeight + 20
                radius: Theme.radius * 0.8
                color: Theme.s2
                border.width: 1
                border.color: r.mode === "mute" ? Theme.alpha(Theme.crit, 0.5) : r.mode === "silent" ? Theme.alpha(Theme.warn, 0.4) : Theme.line

                function set(p) { Notifs.setRule(index, p); }

                ColumnLayout {
                    id: ruleCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: "#" + (rc.index + 1); color: Theme.dim; font.pixelSize: 10 }
                        TextField {
                            id: appField
                            Layout.preferredWidth: 160
                            placeholder: "app name (any)"
                            Component.onCompleted: text = rc.r.app || ""
                            onAccepted: rc.set({ app: text.trim() })
                            Connections { target: appField.input; function onActiveFocusChanged() { if (!appField.input.activeFocus && appField.text.trim() !== (rc.r.app || "")) rc.set({ app: appField.text.trim() }); } }
                        }
                        TextField {
                            id: matchField
                            Layout.fillWidth: true
                            placeholder: "only if title/body matches (regex, optional)"
                            error: { try { new RegExp(text); return false; } catch (e) { return true; } }
                            Component.onCompleted: text = rc.r.match || ""
                            onAccepted: rc.set({ match: text })
                            Connections { target: matchField.input; function onActiveFocusChanged() { if (!matchField.input.activeFocus && matchField.text !== (rc.r.match || "")) rc.set({ match: matchField.text }); } }
                        }
                        IconButton { glyph: "\u{F005D}"; hint: "earlier (checked first)"; enabled: rc.index > 0; onClicked: Notifs.moveRule(rc.index, -1) }
                        IconButton { glyph: "\u{F0045}"; hint: "later"; enabled: rc.index < Notifs.rules.length - 1; onClicked: Notifs.moveRule(rc.index, 1) }
                        IconButton { glyph: "\u{F0A7A}"; hint: "delete rule"; tint: Theme.crit; onClicked: Notifs.removeRule(rc.index) }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        Segmented {
                            options: page.modes
                            current: rc.r.mode || "normal"
                            onActivated: (v) => rc.set({ mode: v })
                        }
                        Row {
                            spacing: 6
                            visible: (rc.r.mode || "normal") !== "mute"
                            Label { anchors.verticalCenter: parent.verticalCenter; text: "stays"; color: Theme.dim; font.pixelSize: 11 }
                            Dropdown {
                                implicitWidth: 120
                                model: page.timeoutLabels
                                currentIndex: Math.max(0, page.timeouts.indexOf(rc.r.timeout === undefined ? -1 : rc.r.timeout))
                                onActivated: (i) => rc.set({ timeout: page.timeouts[i] })
                            }
                        }
                        Row {
                            spacing: 6
                            visible: (rc.r.mode || "normal") !== "mute"
                            Label { anchors.verticalCenter: parent.verticalCenter; text: "urgency"; color: Theme.dim; font.pixelSize: 11 }
                            Dropdown {
                                implicitWidth: 100
                                model: page.urgencyLabels
                                currentIndex: Math.max(0, page.urgencies.indexOf(rc.r.urgency || ""))
                                onActivated: (i) => rc.set({ urgency: page.urgencies[i] })
                            }
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        visible: (rc.r.mode || "normal") !== "mute"
                        spacing: 14
                        CheckBox { text: "ignore do-not-disturb"; checked: !!rc.r.dnd; onToggled: (c) => rc.set({ dnd: c }) }
                        CheckBox { text: "sound"; checked: rc.r.sound !== false; onToggled: (c) => rc.set({ sound: c }) }
                        CheckBox { text: "group with its app"; checked: rc.r.group !== false; onToggled: (c) => rc.set({ group: c }) }
                    }
                }
            }
        }
    }
}
