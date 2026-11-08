pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.components

Column {
    id: root
    spacing: 8
    readonly property int w: 196

    SystemClock { id: clock; precision: SystemClock.Hours }

    readonly property date today: clock.date
    readonly property int year: today.getFullYear()
    readonly property int month: today.getMonth()
    // ISO week number
    readonly property int week: {
        const d = new Date(Date.UTC(year, month, today.getDate()));
        const day = d.getUTCDay() || 7;
        d.setUTCDate(d.getUTCDate() + 4 - day);
        const y0 = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
        return Math.ceil(((d - y0) / 86400000 + 1) / 7);
    }
    readonly property var cells: {
        const first = new Date(year, month, 1);
        const lead = (first.getDay() + 6) % 7;                 // Monday first
        const daysIn = new Date(year, month + 1, 0).getDate();
        const prevDays = new Date(year, month, 0).getDate();
        const out = [];
        for (let i = lead; i > 0; i--) out.push({ d: prevDays - i + 1, out: true });
        for (let d = 1; d <= daysIn; d++) out.push({ d: d, out: false, today: d === today.getDate(), we: (lead + d - 1) % 7 >= 5 });
        let k = 1;
        while (out.length % 7) out.push({ d: k++, out: true });
        return out;
    }

    WidgetHeader { width: root.w; title: "calendar"; detail: "week " + root.week }

    Label {
        text: Qt.formatDate(root.today, "MMMM yyyy")
        font.bold: true
        font.pixelSize: 13
    }

    Grid {
        columns: 7
        columnSpacing: 2
        rowSpacing: 2

        Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            delegate: Label {
                required property string modelData
                width: 26
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Theme.dim
                font.pixelSize: 10
            }
        }
        Repeater {
            model: root.cells
            delegate: Rectangle {
                required property var modelData
                width: 26
                height: 20
                radius: Theme.radius * 0.5
                color: modelData.today ? Theme.a1 : "transparent"
                Label {
                    anchors.centerIn: parent
                    text: parent.modelData.d
                    font.pixelSize: 11
                    font.bold: parent.modelData.today === true
                    color: parent.modelData.today ? Theme.bg
                         : parent.modelData.out ? Theme.alpha(Theme.dim, 0.45)
                         : parent.modelData.we ? Theme.a2 : Theme.fg
                }
            }
        }
    }
}
