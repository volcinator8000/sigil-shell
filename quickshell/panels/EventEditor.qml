pragma ComponentBehavior: Bound

// New Google Calendar event (Actions.eventDate = the day; opened by the calendar widget's +).
// Title, day, all-day or start/end, location, and which calendar. Enter adds, Esc closes,
// Tab moves between fields. Writes through bin/sigil-gcal (Google Calendar API).

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

Overlay {
    id: ed
    shown: Actions.eventDate !== ""
    panelWidth: 470
    panelHeight: connected ? 418 : 330
    onDismissed: Actions.eventDate = ""

    readonly property string gcal: Theme.home + "/.local/bin/sigil-gcal"
    property bool connected: false
    property var calendars: []
    property string calendarId: ""
    property date day: new Date()
    property bool allDay: false
    property string status: ""
    property bool busy: false

    function pad(n) { return (n < 10 ? "0" : "") + n; }
    function hm(d) { return pad(d.getHours()) + ":" + pad(d.getMinutes()); }
    function validTime(t) { return /^([01]?\d|2[0-3]):[0-5]\d$/.test(t); }

    onShownChanged: {
        if (!shown) return;
        const d = new Date(Actions.eventDate + "T12:00:00");
        day = isNaN(d) ? new Date() : d;
        allDay = false;
        status = "";
        busy = false;
        title.text = ""; place.text = "";
        // default slot: the next full hour today, 09:00 on other days
        const now = new Date();
        const isToday = Qt.formatDate(day, "yyyy-MM-dd") === Qt.formatDate(now, "yyyy-MM-dd");
        const h = isToday ? Math.min(22, now.getHours() + 1) : 9;
        start.text = pad(h) + ":00";
        end.text = pad(h + 1) + ":00";
        state_.running = true;
        title.input.forceActiveFocus();
    }

    // connection + calendar list (the list is cached by sigil-gcal, so this is quick)
    Process {
        id: state_
        command: ["sh", "-c", "s=$('" + ed.gcal + "' status 2>&1); echo \"$s\"; [ \"$s\" = ok ] && '" + ed.gcal + "' calendars"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n");
                ed.connected = l[0] === "ok";
                if (!ed.connected) { ed.status = l[0].startsWith("error") ? l[0] : ""; return; }
                try {
                    ed.calendars = JSON.parse(l.slice(1).join("\n")).filter(c => c.writable);
                    if (!ed.calendars.find(c => c.id === ed.calendarId))
                        ed.calendarId = (ed.calendars.find(c => c.primary) || ed.calendars[0] || { id: "" }).id;
                } catch (e) { ed.status = "could not read the calendar list"; }
            }
        }
    }

    Process {
        id: adder
        stdout: StdioCollector { id: addOut }
        stderr: StdioCollector { id: addErr }
        onExited: (code) => {
            ed.busy = false;
            if (code === 0) {
                Actions.sound("click");
                Actions.calendarChanged();
                Actions.eventDate = "";
            } else ed.status = (addErr.text || "failed").trim().split("\n").pop().slice(0, 160);
        }
    }

    function save() {
        if (busy || !connected) return;
        if (!title.text.trim()) { status = "give it a title"; title.input.forceActiveFocus(); return; }
        if (!allDay && (!validTime(start.text) || !validTime(end.text))) { status = "times are HH:MM"; return; }
        busy = true;
        status = "adding…";
        adder.command = [gcal, "add", JSON.stringify({
            calendar: calendarId, title: title.text.trim(), date: Qt.formatDate(day, "yyyy-MM-dd"),
            allDay: allDay, start: start.text, end: end.text, location: place.text.trim() })];
        adder.running = true;
    }

    // ── look ─────────────────────────────────────────────────────────
    component Field: Rectangle {
        id: fr
        property alias input: ti
        property alias text: ti.text
        property string hint: ""
        property Item next: null          // Tab goes here
        signal accepted()
        implicitHeight: 34
        radius: Theme.radius * 0.8
        color: Theme.alpha(Theme.fg, 0.05)
        border.width: 1
        border.color: ti.activeFocus ? Theme.alpha(Theme.a1, 0.6) : Theme.alpha(Theme.fg, 0.08)
        TextInput {
            id: ti
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
            selectionColor: Theme.a1
            selectedTextColor: Theme.bg
            clip: true
            selectByMouse: true
            onAccepted: fr.accepted()
            KeyNavigation.tab: fr.next
            Label { anchors.verticalCenter: parent.verticalCenter; visible: !ti.text && !ti.activeFocus; text: fr.hint; color: Theme.dim; font.pixelSize: 13 }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius * 1.4
        color: Theme.surface
        border.width: 1
        border.color: Theme.line
        Keys.onEscapePressed: Actions.eventDate = ""

        Column {
            anchors { fill: parent; margins: 18 }
            spacing: 12

            Item {
                width: parent.width; height: 22
                Label { text: "NEW EVENT"; color: Theme.dim; font.pixelSize: 10; font.letterSpacing: 1.4; anchors.verticalCenter: parent.verticalCenter }
                Label { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Google Calendar"; color: Theme.a2; font.pixelSize: 10 }
            }

            // ── not connected: how to connect ──
            Column {
                visible: !ed.connected
                width: parent.width
                spacing: 8
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Adding events needs a one-time Google sign-in (the calendar's iCal link is read-only)."
                }
                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    color: Theme.dim
                    font.pixelSize: 11
                    textFormat: Text.PlainText
                    text: "1. console.cloud.google.com → new project → enable \"Google Calendar API\"\n"
                        + "2. OAuth consent screen → External, add yourself as a test user, then Publish app\n"
                        + "3. Credentials → OAuth client ID → Desktop app → download the JSON\n"
                        + "4. in a terminal:  sigil-gcal auth ~/Downloads/client_secret_….json"
                }
                Row {
                    spacing: 8
                    ChipButton { text: "copy step 4"; onClicked: Quickshell.execDetached(["wl-copy", "sigil-gcal auth ~/Downloads/client_secret_"]) }
                    ChipButton { text: "open Google Cloud"; onClicked: Quickshell.execDetached(["xdg-open", "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com"]) }
                    ChipButton { text: "check again"; onClicked: state_.running = true }
                }
            }

            // ── the form ──
            Field {
                id: title
                visible: ed.connected
                width: parent.width
                hint: "Title"
                input.font.pixelSize: 15
                onAccepted: ed.save()
                next: start.input
            }

            Row {
                visible: ed.connected
                spacing: 8
                ChipButton { text: "‹"; onClicked: ed.day = new Date(ed.day.getFullYear(), ed.day.getMonth(), ed.day.getDate() - 1) }
                Label {
                    width: 150
                    height: 30
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(ed.day, "ddd d MMMM yyyy")
                    font.bold: true
                }
                ChipButton { text: "›"; onClicked: ed.day = new Date(ed.day.getFullYear(), ed.day.getMonth(), ed.day.getDate() + 1) }
                Item { width: 12; height: 1 }
                ChipButton { text: "all day"; accent: ed.allDay; onClicked: ed.allDay = !ed.allDay }
            }

            Row {
                visible: ed.connected
                spacing: 8
                opacity: ed.allDay ? 0.35 : 1
                enabled: !ed.allDay
                Label { text: "from"; color: Theme.dim; height: 34 }
                Field {
                    id: start; width: 80; onAccepted: ed.save(); next: end.input
                    // moving the start keeps the event's length
                    property string last: ""
                    Connections {
                        target: start.input
                        function onActiveFocusChanged() { if (start.input.activeFocus) start.last = start.text; }
                        function onEditingFinished() {
                            if (ed.validTime(start.text) && ed.validTime(start.last) && ed.validTime(end.text)) {
                                const m = s => parseInt(s.split(":")[0]) * 60 + parseInt(s.split(":")[1]);
                                const len = (m(end.text) - m(start.last) + 1440) % 1440, e = (m(start.text) + len) % 1440;
                                end.text = ed.pad(Math.floor(e / 60)) + ":" + ed.pad(e % 60);
                            }
                            start.last = start.text;
                        }
                    }
                }
                Label { text: "to"; color: Theme.dim; height: 34 }
                Field { id: end; width: 80; onAccepted: ed.save(); next: place.input }
            }

            Field {
                id: place
                visible: ed.connected
                width: parent.width
                hint: "Location (optional)"
                onAccepted: ed.save()
                next: title.input
            }

            // calendar picker
            Flow {
                visible: ed.connected
                width: parent.width
                spacing: 6
                Repeater {
                    model: ed.calendars
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool on: modelData.id === ed.calendarId
                        width: row.implicitWidth + 20
                        height: 28
                        radius: 14
                        color: on ? Theme.alpha(modelData.color, 0.22) : Theme.alpha(Theme.fg, 0.05)
                        border.width: 1
                        border.color: on ? modelData.color : Theme.alpha(Theme.fg, 0.08)
                        Row {
                            id: row
                            anchors.centerIn: parent
                            spacing: 6
                            Rectangle { width: 8; height: 8; radius: 4; color: chip.modelData.color; anchors.verticalCenter: parent.verticalCenter }
                            Label { text: chip.modelData.name; font.pixelSize: 11; color: chip.on ? Theme.fg : Theme.dim; elide: Text.ElideRight; width: Math.min(implicitWidth, 160) }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ed.calendarId = chip.modelData.id }
                    }
                }
            }

            Item {
                width: parent.width; height: 30
                Label { anchors.verticalCenter: parent.verticalCenter; width: parent.width - 170; elide: Text.ElideRight; text: ed.status; color: ed.busy ? Theme.dim : Theme.warn; font.pixelSize: 11 }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    ChipButton { text: "cancel"; onClicked: Actions.eventDate = "" }
                    ChipButton { visible: ed.connected; text: ed.busy ? "adding…" : "add event"; accent: true; onClicked: ed.save() }
                }
            }
        }
    }
}
