pragma ComponentBehavior: Bound

// Month calendar with events from iCal feeds (Google Calendar: Settings → your calendar →
// "Secret address in iCal format"; paste it in this widget's options). ‹ › change month,
// click a day for its events; the list below shows the selected day, then what's next.
// Wider = wider cells and room for locations, taller = more events.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

Column {
    id: root
    spacing: 8
    readonly property int w: Math.max(196, entry.w || 0)
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property date today: clock.date
    function key(d) { return Qt.formatDate(d, "yyyy-MM-dd"); }
    readonly property string todayKey: key(today)

    // shown month (offset from the current one) and selected day
    property int offset: 0
    property string selected: todayKey
    readonly property date shown: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    readonly property int year: shown.getFullYear()
    readonly property int month: shown.getMonth()

    // ISO week number of today
    readonly property int week: {
        const d = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));
        const day = d.getUTCDay() || 7;
        d.setUTCDate(d.getUTCDate() + 4 - day);
        const y0 = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
        return Math.ceil(((d - y0) / 86400000 + 1) / 7);
    }
    readonly property bool mondayFirst: o("weekStart") !== "sunday"
    readonly property var cells: {
        const first = new Date(year, month, 1);
        const lead = mondayFirst ? (first.getDay() + 6) % 7 : first.getDay();
        const out = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(year, month, 1 - lead + i);
            if (i >= 35 && d.getMonth() !== month) break;
            const k = key(d);
            out.push({ d: d.getDate(), k: k, out: d.getMonth() !== month, today: k === todayKey,
                       we: d.getDay() === 0 || d.getDay() === 6 });
        }
        return out;
    }

    // ── events ───────────────────────────────────────────────────────
    readonly property var urls: String(o("ics") || "").split(/\s+/).filter(u => /^(https?|webcal):\/\//.test(u))
    // Google Calendar connected through the API (sigil-gcal auth): read + create events
    FileView { id: gcalToken; path: Theme.home + "/.config/sigil/gcal/token.json"; watchChanges: true; printErrors: false; onFileChanged: reload() }
    readonly property bool gcal: gcalToken.loaded
    readonly property bool hasSource: urls.length > 0 || gcal
    Connections { target: Actions; function onCalendarChanged() { root.refresh(); } }
    property var events: []
    property string error: ""
    // fetched window: two months back to a year ahead; refetched when navigating outside it
    property date winFrom: new Date(today.getFullYear(), today.getMonth() - 2, 1)
    property date winTo: new Date(today.getFullYear(), today.getMonth() + 13, 1)
    readonly property var byDay: {
        const m = {};
        for (const e of events) {
            // an event covers each day from its start to just before its end
            const s = new Date(e.start), en = new Date(e.end);
            const d = new Date(s.getFullYear(), s.getMonth(), s.getDate());
            let guard = 0;
            do { (m[key(d)] = m[key(d)] || []).push(e); d.setDate(d.getDate() + 1); }
            while (d < en && ++guard < 60);
        }
        return m;
    }
    Process {
        id: fetch
        command: [Theme.home + "/.local/bin/sigil-calendar", root.key(root.winFrom), root.key(root.winTo)].concat(root.urls)
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.events = JSON.parse(text || "[]"); root.error = ""; }
                catch (e) { root.error = "feed error"; }
            }
        }
        onExited: (code) => { if (code !== 0) root.error = "feed error"; }
    }
    // deferred: when this runs from a urls / window change, `command` has not caught up yet
    function refresh() { Qt.callLater(() => { if (root.hasSource && !fetch.running) fetch.running = true; }); }
    onUrlsChanged: refresh()
    onGcalChanged: refresh()
    Timer { interval: 15 * 60 * 1000; running: root.hasSource; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    onShownChanged: {
        if (shown < winFrom || shown >= new Date(winTo.getFullYear(), winTo.getMonth() - 1, 1)) {
            winFrom = new Date(year, month - 2, 1);
            winTo = new Date(year, month + 13, 1);
            refresh();
        }
    }

    // view: "month" = grid + the selected day / what's next, "agenda" = the coming days as a list
    readonly property bool agenda: o("view") === "agenda"
    // the list: the selected day's events, then upcoming ones after it. A resized widget fits as
    // many as its height allows, never fewer than the "Events listed" option.
    readonly property int optEvents: o("events") === undefined ? 4 : o("events")
    readonly property int fitEvents: entry.h ? Math.floor((entry.h - (agenda ? 28 : monthBlock.height + 36) - 14) / 20) : 0
    readonly property int maxEvents: Math.max(optEvents, fitEvents)
    readonly property var listed: {
        const day = byDay[selected] || [];
        const out = day.map(e => ({ e: e, day: true }));
        const after = selected + "T23:59:59";
        for (const e of events) {
            if (out.length >= maxEvents) break;
            if (e.start > after) out.push({ e: e, day: false });
        }
        return out.slice(0, Math.max(maxEvents, day.length));
    }
    // agenda: [{ head: "Today · Thu 12" } | { e, day: true }], the next `agendaDays` days from the selected one
    readonly property var agendaRows: {
        if (!agenda) return [];
        const out = [];
        const start = new Date(selected + "T12:00:00");
        const nd = Math.max(1, o("agendaDays") || 7);
        let n = 0;
        for (let i = 0; i < nd && n < maxEvents; i++) {
            const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            const k = key(d), evs = byDay[k] || [];
            if (!evs.length) continue;
            const tm = key(new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1));
            out.push({ head: (k === todayKey ? "Today · " : k === tm ? "Tomorrow · " : "") + Qt.formatDate(d, "ddd d MMM") });
            for (const e of evs) { if (n++ >= maxEvents) break; out.push({ e: e, day: true }); }
        }
        return out;
    }
    function shiftDays(n) {
        const d = new Date(selected + "T12:00:00");
        d.setDate(d.getDate() + n);
        selected = key(d);
        offset = (d.getFullYear() - today.getFullYear()) * 12 + d.getMonth() - today.getMonth();
    }
    function when(e, dayItem) {
        const s = new Date(e.start);
        const t = e.allDay ? "all day" : Qt.formatTime(s, "HH:mm");
        if (dayItem) return t;
        const k = key(s);
        const label = k === todayKey ? "today" : k === key(new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1)) ? "tmrw" : Qt.formatDate(s, "ddd d");
        return label + (e.allDay ? "" : " " + t);
    }

    // ── layout ───────────────────────────────────────────────────────
    WidgetHeader {
        width: root.w; title: "calendar"
        detail: root.error ? root.error : root.o("showWeek") ? "week " + root.week : ""
    }

    Item {
        width: root.w
        height: 20
        WLabel {
            anchors.verticalCenter: parent.verticalCenter
            text: root.agenda ? (root.selected === root.todayKey ? "Coming up" : "From " + Qt.formatDate(new Date(root.selected + "T12:00:00"), "ddd d MMM")) : Qt.formatDate(root.shown, "MMMM yyyy")
            font.bold: true
            font.pixelSize: 14
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 2
            component Nav: WLabel {
                id: nb
                signal hit()
                width: 20; height: 20
                horizontalAlignment: Text.AlignHCenter
                color: nh.hovered ? Theme.a1 : Theme.widgetDim
                font.pixelSize: 14
                HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: !Widgets.editing; onTapped: nb.hit() }
            }
            Nav { visible: root.offset !== 0 || root.selected !== root.todayKey; width: 40; text: "today"; font.pixelSize: 12; onHit: { root.offset = 0; root.selected = root.todayKey; } }
            Nav { text: "+"; font.pixelSize: 15; onHit: Actions.newEvent(root.selected) }
            Nav { text: "‹"; onHit: root.agenda ? root.shiftDays(-7) : root.offset-- }
            Nav { text: "›"; onHit: root.agenda ? root.shiftDays(7) : root.offset++ }
        }
    }

    Grid {
        id: monthBlock
        visible: !root.agenda
        columns: 7
        columnSpacing: 2
        rowSpacing: 2
        readonly property real cw: (root.w - 12) / 7

        Repeater {
            model: root.mondayFirst ? ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] : ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
            delegate: WLabel {
                required property string modelData
                width: (root.w - 12) / 7
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Theme.widgetDim
                font.pixelSize: 12
            }
        }
        Repeater {
            model: root.cells
            delegate: Rectangle {
                id: cell
                required property var modelData
                readonly property bool sel: modelData.k === root.selected
                readonly property int count: (root.byDay[modelData.k] || []).length
                width: (root.w - 12) / 7
                height: 22
                radius: Theme.radius * 0.5
                color: modelData.today ? Theme.a1 : ch.hovered && !Widgets.editing ? Theme.alpha(Theme.fg, 0.07) : "transparent"
                border.width: sel && !modelData.today ? 1 : 0
                border.color: Theme.alpha(Theme.a1, 0.8)
                WLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 2
                    text: cell.modelData.d
                    font.pixelSize: 12
                    font.bold: cell.modelData.today === true
                    color: cell.modelData.today ? Theme.bg
                         : cell.modelData.out ? Theme.alpha(Theme.widgetDim, 0.45)
                         : cell.modelData.we ? Theme.a2 : Theme.fg
                }
                // one dot per event, up to three
                Row {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 2 }
                    spacing: 2
                    Repeater {
                        model: Math.min(3, cell.count)
                        delegate: Rectangle {
                            required property int index
                            width: 3; height: 3; radius: 1.5
                            readonly property var ev: (root.byDay[cell.modelData.k] || [])[index]
                            color: cell.modelData.today ? Theme.bg : (ev && ev.color) ? ev.color : Theme.a2
                            opacity: cell.modelData.out ? 0.5 : 1
                        }
                    }
                }
                HoverHandler { id: ch; enabled: !Widgets.editing; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    enabled: !Widgets.editing
                    onTapped: {
                        root.selected = cell.modelData.k;
                        if (cell.modelData.out) root.offset += cell.modelData.d > 15 ? -1 : 1;
                    }
                }
            }
        }
    }

    // events
    Column {
        visible: root.hasSource && root.maxEvents > 0
        width: root.w
        spacing: 2
        Rectangle { width: root.w; height: 1; color: Theme.alpha(Theme.fg, 0.08) }
        Item { width: 1; height: 4 }
        WLabel {
            visible: root.agenda ? root.agendaRows.length === 0 : (root.byDay[root.selected] || []).length === 0
            text: root.agenda ? "nothing in the next " + (root.o("agendaDays") || 7) + " days"
                : (root.selected === root.todayKey ? "nothing today" : "nothing on " + Qt.formatDate(new Date(root.selected + "T12:00:00"), "ddd d MMM")) + (root.listed.length ? " · next:" : "")
            color: Theme.widgetDim
            font.pixelSize: 12
            height: 18
        }
        Repeater {
            model: root.agenda ? root.agendaRows : root.listed
            delegate: Item {
                id: ev
                required property var modelData
                required property int index
                width: root.w
                height: modelData.head ? 22 : 18
                // agenda day heading
                WLabel {
                    visible: ev.modelData.head !== undefined
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    text: ev.modelData.head || ""
                    color: Theme.a2
                    font.pixelSize: 12
                    font.bold: true
                }
                Rectangle {
                    visible: ev.modelData.e !== undefined
                    width: 2; height: 12; radius: 1; anchors.verticalCenter: parent.verticalCenter
                    color: ev.modelData.e && ev.modelData.e.color ? ev.modelData.e.color : ev.modelData.day ? Theme.a1 : Theme.alpha(Theme.a2, 0.6)
                    opacity: ev.modelData.day ? 1 : 0.7
                }
                WLabel {
                    id: whenL
                    visible: ev.modelData.e !== undefined
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: ev.modelData.day ? 44 : 78
                    text: ev.modelData.e ? root.when(ev.modelData.e, ev.modelData.day) : ""
                    color: ev.modelData.day ? Theme.a1 : Theme.widgetDim
                    font.pixelSize: 12
                }
                WLabel {
                    x: whenL.x + whenL.width
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.w - x
                    elide: Text.ElideRight
                    visible: ev.modelData.e !== undefined
                    text: ev.modelData.e ? ev.modelData.e.title + (root.w >= 300 && ev.modelData.e.location ? "  ·  " + ev.modelData.e.location : "") : ""
                    font.pixelSize: 12
                }
            }
        }
    }
    WLabel {
        visible: !root.hasSource && root.o("hint") !== false
        width: root.w
        wrapMode: Text.Wrap
        text: "link Google Calendar: sigil-gcal (read + add events) or a feed URL in the options"
        color: Theme.alpha(Theme.widgetDim, 0.7)
        font.pixelSize: 11
    }
}
