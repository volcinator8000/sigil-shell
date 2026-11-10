import QtQuick
import Quickshell
import qs.services
import qs.components

Column {
    id: root
    property var entry: ({})
    function o(k) { return Widgets.opt(entry, k); }
    spacing: 2

    SystemClock { id: clock; precision: root.o("seconds") ? SystemClock.Seconds : SystemClock.Minutes }
    WLabel {
        text: Qt.formatDateTime(clock.date, (root.o("h12") ? "h:mm" : "HH:mm") + (root.o("seconds") ? ":ss" : "") + (root.o("h12") ? " AP" : ""))
        font.pixelSize: root.o("size") || 44
        font.bold: true
    }
    WLabel { visible: root.o("showDate") !== false; text: Qt.formatDate(clock.date, "dddd d MMMM"); color: Theme.dim }
}
