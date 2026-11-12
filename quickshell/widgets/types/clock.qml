pragma ComponentBehavior: Bound

// Large time, optional date line and a second time zone.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

Column {
    id: root
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }
    spacing: 2

    readonly property bool sec: o("seconds") === true
    readonly property bool smallSec: sec && o("smallSeconds") !== false
    readonly property bool h12: o("h12") === true
    readonly property int size: o("size") || 44

    SystemClock { id: clock; precision: root.sec ? SystemClock.Seconds : SystemClock.Minutes }

    Row {
        spacing: 0
        WLabel {
            id: main
            text: Qt.formatDateTime(clock.date, (root.h12 ? "h:mm" : "HH:mm") + (root.sec && !root.smallSec ? ":ss" : ""))
            font.pixelSize: root.size
            font.bold: true
        }
        // seconds (and AM/PM) set smaller, on the baseline of the big digits
        WLabel {
            visible: root.smallSec || root.h12
            anchors.baseline: main.baseline
            leftPadding: root.size * 0.08
            text: (root.smallSec ? Qt.formatDateTime(clock.date, "ss") : "") + (root.h12 ? (root.smallSec ? " " : "") + Qt.formatDateTime(clock.date, "AP") : "")
            font.pixelSize: Math.round(root.size * 0.42)
            font.bold: true
            color: Theme.widgetDim
        }
    }

    readonly property var dateFormats: ({ long: "dddd d MMMM", short: "ddd d MMM", numeric: "dd/MM/yyyy", iso: "yyyy-MM-dd", week: "dddd d MMMM" })
    WLabel {
        visible: root.o("showDate") !== false
        text: {
            const f = root.o("dateFormat") || "long";
            let t = Qt.formatDate(clock.date, root.dateFormats[f] || root.dateFormats.long);
            if (f === "week") {
                const d = new Date(Date.UTC(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate()));
                const day = d.getUTCDay() || 7;
                d.setUTCDate(d.getUTCDate() + 4 - day);
                t += "  ·  week " + Math.ceil(((d - new Date(Date.UTC(d.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7);
            }
            return t;
        }
        color: Theme.widgetDim
        font.pixelSize: Math.max(12, Math.round(root.size * 0.3))
    }

    // second time zone: its UTC offset is asked from `date` (QML has no tz database), hourly
    readonly property string zone: String(o("zone") || "").trim()
    property int zoneOffset: 0      // minutes east of UTC
    property bool zoneOk: false
    Process {
        id: tz
        command: ["sh", "-c", 'TZ="$1" date +%z', "sh", root.zone]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^([+-])(\d\d)(\d\d)$/);
                root.zoneOk = m !== null;
                if (m) root.zoneOffset = (m[1] === "-" ? -1 : 1) * (parseInt(m[2]) * 60 + parseInt(m[3]));
            }
        }
    }
    onZoneChanged: if (zone) tz.running = true
    Timer { interval: 3600000; running: root.zone !== ""; repeat: true; triggeredOnStart: true; onTriggered: tz.running = true }
    readonly property date zoneTime: new Date(clock.date.getTime() + (zoneOffset + clock.date.getTimezoneOffset()) * 60000)
    WLabel {
        visible: root.zone !== "" && root.zoneOk
        topPadding: 2
        text: (root.o("zoneLabel") || root.zone.split("/").pop().replace(/_/g, " ")) + "  "
              + Qt.formatDateTime(root.zoneTime, root.h12 ? "h:mm AP" : "HH:mm")
              + (root.zoneTime.getDate() !== clock.date.getDate() ? (root.zoneTime > clock.date ? "  +1d" : "  −1d") : "")
        color: Theme.widgetDim
        font.pixelSize: Math.max(12, Math.round(root.size * 0.3))
    }
}
