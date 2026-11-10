pragma Singleton
pragma ComponentBehavior: Bound

// Notification daemon (replaces swaync while sigil-shell runs).
//
//  popups        notifications on screen now (newest first)
//  history       everything still tracked (newest first)
//  popupGroups / historyGroups   the same, grouped by app: [{ key, app, items: [newest…] }]
//
// Per-app rules live in settings.json → notifications.rules, first match wins:
//   { app: "discord",          // matched (case-insensitive) against app name and desktop entry; "" = any app
//     match: "",                // optional regex on summary + body
//     mode: "normal",           // normal | silent (history only) | mute (dropped)
//     timeout: -1,              // ms the popup stays; -1 = app/default, 0 = until dismissed
//     dnd: false,               // true = still pops up during do-not-disturb
//     urgency: "",              // "" | low | normal | critical (override)
//     group: true,              // false = one card per message
//     sound: true }
// Other settings: notifications.group (true), .timeout (6000), .maxPopups (5),
//   .ownSound: apps that play their own notification sound, so the shell stays quiet for
//   them (substring of the app name / desktop entry; default: common chat apps). Apps that
//   send the sound-file / sound-name / suppress-sound hints are covered too.

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

    readonly property var cfg: Theme.notifications || {}
    readonly property var rules: cfg.rules || []
    readonly property bool grouping: cfg.group !== false
    readonly property int defaultTimeout: cfg.timeout > 0 ? cfg.timeout : 6000
    readonly property int maxPopups: cfg.maxPopups > 0 ? cfg.maxPopups : 5
    readonly property var defaultOwnSound: ["vesktop", "discord", "equibop", "legcord", "webcord", "slack", "signal", "telegram", "element", "whatsapp", "teams"]
    readonly property var ownSound: Array.isArray(cfg.ownSound) ? cfg.ownSound : defaultOwnSound
    function playsOwnSound(n) {
        const h = n.hints || {};
        if (h["suppress-sound"] || h["sound-file"] || h["sound-name"]) return true;
        const names = ((n.appName || "") + " " + (n.desktopEntry || "")).toLowerCase();
        return ownSound.some(a => a && names.indexOf(String(a).toLowerCase()) >= 0);
    }
    function setOwnSound(list) { Theme.patchSettings({ notifications: { ownSound: list } }); }

    readonly property var popupGroups: groupsOf(popups).slice(0, maxPopups)
    readonly property var historyGroups: groupsOf(history)

    // id → { rule, at }   (bookkeeping the notification object itself can't hold)
    property var meta: ({})
    property int mutedCount: 0           // dropped by a mute rule since start
    property bool settled: false
    Timer { interval: 1500; running: true; onTriggered: root.settled = true }

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
        inlineReplySupported: true

        onNotification: (n) => {
            const rule = root.ruleFor(n);
            if (rule && rule.mode === "mute") { root.mutedCount++; return; }   // not tracked → discarded
            n.tracked = true;
            const m = Object.assign({}, root.meta);
            m[n.id] = { rule: rule, at: Date.now() };
            root.meta = m;
            n.closed.connect(() => root.forget(n));

            // keepOnReload re-sends every kept notification when the shell reloads: history only
            if (rule && rule.mode === "silent" || !root.settled) return;
            const urgent = root.urgencyOf(n) === NotificationUrgency.Critical;
            if (root.dnd && !urgent && !(rule && rule.dnd)) return;
            if (n.transient && root.dnd) return;
            if (root.popups.indexOf(n) < 0) root.popups = [n].concat(root.popups).slice(0, 30);
            if ((!rule || rule.sound !== false) && !root.playsOwnSound(n)) Actions.sound(urgent ? "notify-urgent" : "notify", urgent || !!(rule && rule.dnd));
        }
    }

    // ── rules ────────────────────────────────────────────────────────
    function appKey(n) { return ((n.desktopEntry || n.appName || "unknown") + "").toLowerCase(); }
    function ruleMatches(r, n) {
        const app = (r.app || "").toLowerCase().trim();
        if (app && app !== (n.appName || "").toLowerCase() && app !== (n.desktopEntry || "").toLowerCase()) return false;
        if (r.match) {
            try { if (!new RegExp(r.match, "i").test((n.summary || "") + "\n" + (n.body || ""))) return false; }
            catch (e) { return false; }
        }
        return !!(app || r.match);
    }
    function ruleFor(n) { return rules.find(r => ruleMatches(r, n)) || null; }
    function ruleOf(n) { return n && meta[n.id] ? meta[n.id].rule : null; }
    function receivedAt(n) { return n && meta[n.id] ? meta[n.id].at : 0; }
    function urgencyOf(n) {
        const r = ruleOf(n) || (n ? ruleFor(n) : null);
        if (r && r.urgency) return ({ low: NotificationUrgency.Low, normal: NotificationUrgency.Normal, critical: NotificationUrgency.Critical })[r.urgency];
        return n ? n.urgency : NotificationUrgency.Normal;
    }

    function saveRules(list) { Theme.patchSettings({ notifications: { rules: list } }); }
    function addRule(rule) { saveRules(rules.concat([Object.assign({ app: "", match: "", mode: "normal", timeout: -1, dnd: false, urgency: "", group: true, sound: true }, rule)])); }
    function setRule(i, patch) { saveRules(rules.map((r, j) => j === i ? Object.assign({}, r, patch) : r)); }
    function removeRule(i) { saveRules(rules.filter((r, j) => j !== i)); }
    function moveRule(i, d) {
        const j = i + d;
        if (j < 0 || j >= rules.length) return;
        const a = rules.slice(); const t = a[i]; a[i] = a[j]; a[j] = t;
        saveRules(a);
    }
    // Quick rule from a card: update this app's plain rule (no regex), or add one.
    function quickRule(n, patch) {
        const app = (n.appName || n.desktopEntry || "").toLowerCase();
        if (!app) return;
        const i = rules.findIndex(r => (r.app || "").toLowerCase() === app && !r.match);
        if (i >= 0) setRule(i, patch); else addRule(Object.assign({ app: app }, patch));
    }
    function appRule(n) {
        const app = (n.appName || n.desktopEntry || "").toLowerCase();
        return rules.find(r => (r.app || "").toLowerCase() === app && !r.match) || null;
    }
    readonly property var knownApps: {
        const seen = {};
        for (const n of server.trackedNotifications.values) if (n.appName) seen[n.appName.toLowerCase()] = true;
        return Object.keys(seen).sort();
    }

    // ── grouping ─────────────────────────────────────────────────────
    function groupKey(n) {
        const r = ruleOf(n);
        if (!grouping || (r && r.group === false)) return "id:" + n.id;
        return appKey(n);
    }
    function groupsOf(list) {
        const out = [], at = {};
        for (const n of list) {
            if (!n) continue;
            const k = groupKey(n);
            if (at[k] === undefined) { at[k] = out.length; out.push({ key: k, app: n.appName || "notification", items: [] }); }
            out[at[k]].items.push(n);
        }
        return out;
    }

    // ── closing ──────────────────────────────────────────────────────
    function forget(n) {
        dropPopup(n);
        if (meta[n.id]) { const m = Object.assign({}, meta); delete m[n.id]; meta = m; }
    }
    function dropPopup(n) { popups = popups.filter(p => p !== n); }
    function dropPopups(list) { popups = popups.filter(p => list.indexOf(p) < 0); }
    // Take cards off screen first and dismiss once their slide-out has played,
    // so they keep their content while they animate.
    function dismiss(n) { dismissAll([n]); }
    function dismissAll(list) {
        list = list.filter(n => !!n);
        dropPopups(list);
        const t = Qt.createQmlObject('import QtQuick; Timer { interval: 260 }', root);
        t.triggered.connect(() => { for (const n of list) if (n && typeof n.dismiss === "function") n.dismiss(); t.destroy(); });
        t.start();
    }
    function clearAll() {
        popups = [];
        for (const n of server.trackedNotifications.values.slice()) n.dismiss();
    }
    function timeoutFor(n) {
        if (!n) return 0;
        const r = ruleOf(n);
        if (r && r.timeout >= 0) return r.timeout;                  // 0 = until dismissed
        if (urgencyOf(n) === NotificationUrgency.Critical) return 0;
        // expireTimeout is in milliseconds (from the sender); clamp silly values
        return n.expireTimeout > 0 ? Math.max(1500, Math.min(n.expireTimeout, 60000)) : defaultTimeout;
    }

    function ago(n) {
        const t = receivedAt(n);
        if (!t) return "";
        const s = Math.max(0, (clock.now - t) / 1000);
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + "m" : s < 86400 ? Math.floor(s / 3600) + "h" : Math.floor(s / 86400) + "d";
    }
    QtObject { id: clock; property real now: Date.now() }
    Timer { interval: 30000; running: root.count > 0; repeat: true; onTriggered: clock.now = Date.now() }

    IpcHandler {
        target: "notifs"
        function dnd(): void { root.dnd = !root.dnd; }
        function isDnd(): bool { return root.dnd; }
        function clear(): void { root.clearAll(); }
        function count(): int { return root.count; }
        function rules(): string { return JSON.stringify(root.rules); }
        function clearApp(app: string): int {
            const list = root.history.filter(n => (n.appName || "").toLowerCase() === app.toLowerCase());
            root.dismissAll(list);
            return list.length;
        }
        function test(app: string, summary: string): void {
            Quickshell.execDetached(["notify-send", "-a", app || "sigil-test", summary || "test notification", "body text for " + (app || "test")]);
        }
    }
}
