pragma Singleton
pragma ComponentBehavior: Bound

// Notification daemon (replaces swaync while sigil-shell runs).
// `popups` = what is on screen now; `history` = everything still tracked.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    property bool dnd: false
    property var popups: []
    readonly property var history: server.trackedNotifications.values.slice().reverse()
    readonly property int count: server.trackedNotifications.values.length

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        actionIconsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: (n) => {
            n.tracked = true;
            if (n.transient && root.dnd) return;
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) return;
            root.popups = [n].concat(root.popups).slice(0, 5);
            Actions.sound("notify");
            n.closed.connect(() => root.dropPopup(n));
        }
    }

    function dropPopup(n) { popups = popups.filter(p => p !== n); }
    // Take the card off screen first and dismiss once its slide-out has played,
    // so the card keeps its content while it animates.
    function dismiss(n) {
        dropPopup(n);
        const t = Qt.createQmlObject('import QtQuick; Timer { interval: 260 }', root);
        t.triggered.connect(() => { if (n) n.dismiss(); t.destroy(); });
        t.start();
    }
    function clearAll() {
        popups = [];
        for (const n of server.trackedNotifications.values.slice()) n.dismiss();
    }
    function timeoutFor(n) {
        if (n.urgency === NotificationUrgency.Critical) return 0;
        // expireTimeout is in milliseconds (from the sender); clamp silly values
        return n.expireTimeout > 0 ? Math.max(1500, Math.min(n.expireTimeout, 60000)) : 6000;
    }

    IpcHandler {
        target: "notifs"
        function dnd(): void { root.dnd = !root.dnd; }
        function clear(): void { root.clearAll(); }
        function count(): int { return root.count; }
    }
}
