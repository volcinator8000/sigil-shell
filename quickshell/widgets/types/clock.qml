import QtQuick
import Quickshell
import qs.services
import qs.components

Column {
    spacing: 2
    SystemClock { id: clock; precision: SystemClock.Minutes }
    Label { text: Qt.formatDateTime(clock.date, "HH:mm"); font.pixelSize: 44; font.bold: true }
    Label { text: Qt.formatDate(clock.date, "dddd d MMMM"); color: Theme.dim }
}
