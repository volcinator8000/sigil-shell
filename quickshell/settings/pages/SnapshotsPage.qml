pragma ComponentBehavior: Bound

// Snapper manager: list / create / delete, inspect and undo changes, retention.
// Runs snapper as the user (needs ALLOW_USERS + SYNC_ACL, granted once through
// pkexec); anything still refused is retried once through pkexec.
// No rollback button: rootflags=subvol=@ is pinned in the rEFInd stanza.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false
    readonly property var limits: [["TIMELINE_LIMIT_HOURLY", "Hourly"], ["TIMELINE_LIMIT_DAILY", "Daily"], ["TIMELINE_LIMIT_WEEKLY", "Weekly"],
                                   ["TIMELINE_LIMIT_MONTHLY", "Monthly"], ["TIMELINE_LIMIT_YEARLY", "Yearly"], ["NUMBER_LIMIT", "Number (pre/post)"]]
    property var configs: ["root"]
    property string cfg: "root"
    property var cfgVals: ({})
    property bool cfgReady: false
    property var entries: []           // [{pre, post}]
    property var checked: []
    property string status: "loading…"
    property bool noAccess: false
    // changes dialog
    property var chg: ({ a: 0, b: 0, title: "" })
    property string chgText: ""
    property string chgSummary: ""
    property bool chgCanUndo: false
    // confirm dialog
    property var confirmFn: null

    Component.onCompleted: {
        Sh.run(["snapper", "list-configs"], o => {
            const c = o.split("\n").slice(2).filter(l => l.indexOf("│") >= 0).map(l => l.split("│")[0].trim()).filter(x => x);
            c.sort((a, b) => (a === "root" ? -1 : b === "root" ? 1 : 0));
            page.configs = c.length ? c : ["root"];
            page.cfg = page.configs[0];
            page.load();
        });
    }
    function refresh() { if (configs.length) load(); }

    // snapper -c CFG ARGS as the user; on a permission error retry once through pkexec
    function snap(args, done, timeout) {
        const c = ["snapper", "-c", cfg].concat(args), t = timeout || 60;
        Sh.runAll(c, (o, rc) => {
            if (rc !== 0 && (o.indexOf("No permissions") >= 0 || o.toLowerCase().indexOf("permission") >= 0))
                Sh.runAll(["pkexec"].concat(c), done, t + 60);
            else done(o, rc);
        }, t);
    }
    function subvol() { return cfgVals.SUBVOLUME || (cfg === "root" ? "/" : "/" + cfg); }

    function load() {
        status = "loading…";
        cfgVals = {}; cfgReady = false;          // never Apply zeros from a config we couldn't read
        const c = cfg;                           // drop replies after a config switch
        Sh.run(["snapper", "--jsonout", "-c", c, "get-config"], o => { if (c === page.cfg) page.gotConfig(o); }, 10);
        Sh.runAll(["snapper", "--jsonout", "-c", c, "list", "--disable-used-space"], o => { if (c === page.cfg) page.gotList(o); }, 20);
    }
    function gotConfig(o) {
        let v;
        try { v = JSON.parse(o); } catch (e) { return; }
        if (!v || typeof v !== "object" || !("SUBVOLUME" in v)) return;
        cfgVals = v; cfgReady = true;
        tlCreate.checked = v.TIMELINE_CREATE === "yes";
        tlCleanup.checked = v.TIMELINE_CLEANUP === "yes";
        for (let i = 0; i < limitRows.count; i++) {
            const r = limitRows.itemAt(i);
            const n = parseInt(String(v[r.key] || "0").split("-").pop());   // ranges like "2-10" keep the upper bound
            if (!isNaN(n)) r.spin.value = n;
        }
    }
    function gotList(o) {
        checked = [];
        if (o.indexOf("No permissions") >= 0) { noAccess = true; entries = []; status = "no permission to read snapshots"; return; }
        noAccess = false;
        let snaps;
        try {
            const data = JSON.parse(o);
            snaps = (data[cfg] || Object.values(data)[0] || []).filter(s => (s.number || 0) !== 0);
        } catch (e) { entries = []; status = o ? Sh.lastLine(o, "").slice(0, 120) : "snapper failed"; return; }
        const nums = {};
        for (const s of snaps) nums[s.number] = true;
        const posts = {};
        for (const s of snaps) if (s.type === "post" && s["pre-number"]) posts[s["pre-number"]] = s;
        const e = [];
        for (const s of snaps) {
            if (s.type === "post" && nums[s["pre-number"]]) continue;     // folded into its pre
            e.push({ pre: s, post: s.type === "pre" ? (posts[s.number] || null) : null });
        }
        e.sort((a, b) => b.pre.number - a.pre.number);
        const nTl = snaps.filter(s => s.cleanup === "timeline").length, nNum = snaps.filter(s => s.cleanup === "number").length;
        status = snaps.length ? snaps.length + " snapshot(s) · " + nNum + " pacman · " + nTl + " timeline · " + (snaps.length - nTl - nNum) + " manual" : "no snapshots yet";
        entries = e;
    }

    function ask(title, body, label, fn) {
        confirmModal.title = title; confirmModal.body = body; confirmOk.text = label;
        confirmFn = fn;
        confirmModal.open();
    }
    function grant() {
        const script = configs.map(c => "snapper -c " + c + " set-config ALLOW_USERS=" + Sh.user + " SYNC_ACL=yes").join(" && ");
        Sh.toast("Waiting for authentication…");
        Sh.runAll(["pkexec", "sh", "-c", script], (o, rc) => { Sh.toast(rc === 0 ? "Access granted" : Sh.lastLine(o, "cancelled")); page.load(); }, 120);
    }
    function create(desc, important) {
        const args = ["create", "--print-number", "--description", desc || "manual (sigil settings)"].concat(important ? ["--userdata", "important=yes"] : []);
        Sh.toast("Creating snapshot…");
        snap(args, (o, rc) => { Sh.toast(rc === 0 && o ? "Snapshot #" + Sh.lastLine(o, "") + " created" : Sh.lastLine(o, "failed")); page.load(); });
    }
    function del(ids) {
        if (!ids.length) return;
        const label = ids.length === 1 ? "#" + ids[0] : ids.length + " snapshots";
        ask("Delete " + label + "?", "From config " + cfg + ". This cannot be undone; --sync waits until btrfs has freed the space.", "Delete", () => {
            Sh.toast("Deleting " + label + "…");
            page.snap(["delete", "--sync"].concat(ids.map(String)), (o, rc) => { Sh.toast(rc === 0 ? "Deleted " + label : Sh.lastLine(o, "failed")); page.load(); }, 300);
        });
    }
    function cleanup() {
        Sh.toast("Cleaning up…");
        const step = algos => {
            if (!algos.length) { Sh.toast("Cleanup done"); page.load(); return; }
            page.snap(["cleanup", algos[0]], (o, rc) => { if (rc === 0) step(algos.slice(1)); else { Sh.toast(Sh.lastLine(o, "cleanup failed")); page.load(); } }, 300);
        };
        step(["number", "timeline", "empty-pre-post"]);
    }
    function applyLimits() {
        const vals = {};
        for (let i = 0; i < limitRows.count; i++) { const r = limitRows.itemAt(i); vals[r.key] = String(Math.round(r.spin.value)); }
        vals.TIMELINE_CREATE = tlCreate.checked ? "yes" : "no";
        vals.TIMELINE_CLEANUP = tlCleanup.checked ? "yes" : "no";
        const changed = Object.keys(vals).filter(k => cfgVals[k] !== vals[k]).map(k => k + "=" + vals[k]);
        if (!changed.length) { Sh.toast("Nothing changed"); return; }
        snap(["set-config"].concat(changed), (o, rc) => { Sh.toast(rc === 0 ? page.cfg + ": " + changed.length + " setting(s) saved" : Sh.lastLine(o, "failed")); page.load(); });
    }
    function browse(num) {
        const path = subvol().replace(/\/$/, "") + "/.snapshots/" + num + "/snapshot";
        Sh.sh('[ -r "$1" ] && [ -x "$1" ]', (o, rc) => {
            if (rc !== 0) Sh.toast("Can't read the snapshot dir (grant access sets SYNC_ACL)");
            else Sh.spawn(["xdg-open", path]);
        }, 4, [path]);
    }
    function changes(a, b, title) {
        chg = { a: a, b: b, title: title };
        chgText = "comparing… (big ranges can take a while)";
        chgSummary = title.slice(0, 70);
        chgCanUndo = false;
        changesModal.open();
        snap(["status", a + ".." + b], (o, rc) => {
            if (rc !== 0) { page.chgText = o || "snapper status failed"; return; }
            const lines = o.split("\n").filter(l => /^[+\-c.tpugxa]{5,}\s/.test(l));
            const cnt = k => lines.filter(l => l[0] === k).length;
            page.chgSummary = lines.length + " path(s) · +" + cnt("+") + " new · -" + cnt("-") + " deleted · " + cnt("c") + " modified";
            const shown = lines.slice(0, 5000);
            page.chgText = lines.length ? shown.join("\n") + (lines.length > shown.length ? "\n… " + (lines.length - shown.length) + " more" : "") : "no changes";
            page.chgCanUndo = lines.length > 0;
        }, 600);
    }
    function undo() {
        const a = chg.a, b = chg.b;
        ask("Undo these changes?", "Files changed between #" + a + " and " + (b ? "#" + b : "the current system") + " are put back to their state in #" + a
            + " (config " + cfg + "). For root this rewrites live system files; take a fresh snapshot first if unsure.", "Undo changes", () => {
            changesModal.close();
            Sh.toast("Undoing changes…");
            page.snap(["undochange", a + ".." + b], (o, rc) => Sh.toast(rc === 0 ? "Changes undone" : Sh.lastLine(o, "undo failed")), 900);
        });
    }
    function toggleCheck(ids, on) {
        let c = checked.filter(x => ids.indexOf(x) < 0);
        if (on) c = c.concat(ids);
        checked = c.sort((x, y) => x - y);
    }

    Section {
        title: "Snapper"
        SettingRow {
            title: "Config"
            Dropdown {
                model: page.configs
                onActivated: i => { page.cfg = page.configs[i]; page.load(); }
            }
        }
        SettingRow {
            visible: page.noAccess
            glyph: "\u{F0026}"; glyphColor: Theme.warn
            title: "No access"
            subtitle: "snapperd refuses your user; grant once with your password (ALLOW_USERS + SYNC_ACL for every config)"
            ActionButton { text: "Grant access"; accent: true; onClicked: page.grant() }
        }
        SettingRow {
            title: "New snapshot"; subtitle: "single snapshot of the selected config, kept until deleted"
            ActionButton {
                text: "Create…"; accent: true
                onClicked: { descField.text = ""; impBox.checked = false; createModal.open(); descField.input.forceActiveFocus(); }
            }
        }
    }

    Section {
        title: "Snapshots"
        description: page.status
        actions: [
            ActionButton {
                text: page.checked.length ? "Delete " + page.checked.length : "Delete selected"
                danger: true
                enabled: page.checked.length > 0
                onClicked: page.del(page.checked.slice())
            },
            IconButton { glyph: "\u{F0450}"; hint: "Reload"; onClicked: page.load() }
        ]
        Repeater {
            model: page.entries
            delegate: SettingRow {
                id: sr
                required property var modelData
                readonly property var s: modelData.pre
                readonly property var post: modelData.post
                readonly property var ids: post ? [s.number, post.number] : [s.number]
                readonly property string desc: s.description || (s.cleanup === "timeline" ? "timeline" : "(no description)")
                readonly property var tags: [s.cleanup, (s.userdata || {}).important === "yes" ? "important" : ""].filter(t => t)
                title: desc.slice(0, 90)
                subtitle: (post ? "#" + s.number + " → #" + post.number : "#" + s.number + (s.type === "pre" ? " · pre, no post" : ""))
                          + "  ·  " + String(s.date || "").slice(0, 16) + (tags.length ? "  ·  " + tags.join(", ") : "")
                glyph: post ? "\u{F03D3}" : s.cleanup === "timeline" ? "\u{F0020}" : "\u{F0100}"
                CheckBox {
                    checked: sr.ids.every(i => page.checked.indexOf(i) >= 0)
                    onToggled: on => page.toggleCheck(sr.ids, on)
                }
                IconButton {
                    glyph: "\u{F0219}"
                    hint: "Changes" + (sr.post ? " in this transaction" : " since this snapshot")
                    onClicked: page.changes(sr.s.number, sr.post ? sr.post.number : 0, sr.desc)
                }
                IconButton { glyph: "\u{F0770}"; hint: "Browse files"; onClicked: page.browse(sr.post ? sr.post.number : sr.s.number) }
                IconButton { glyph: "\u{F01B4}"; hint: "Delete"; tint: Theme.crit; onClicked: page.del(sr.ids) }
            }
        }
    }

    Section {
        title: "Retention"
        description: "cleanup runs from snapper-cleanup.timer; snap-pac adds a pre/post pair per pacman transaction"
        enabled: page.cfgReady
        SettingRow { title: "Timeline snapshots"; subtitle: "hourly snapshots from snapper-timeline.timer"; Toggle { id: tlCreate } }
        SettingRow { title: "Timeline cleanup"; subtitle: "prune timeline snapshots down to the limits below"; Toggle { id: tlCleanup } }
        Repeater {
            id: limitRows
            model: page.limits
            delegate: SettingRow {
                id: lr
                required property var modelData
                readonly property string key: modelData[0]
                property alias spin: sp
                title: modelData[1]
                subtitle: modelData[0]
                SpinField { id: sp; from: 0; to: 500; stepSize: 1 }
            }
        }
        SettingRow {
            title: "Apply"; subtitle: "write the limits to the snapper config"
            ActionButton { text: "Clean up now"; onClicked: page.cleanup() }
            ActionButton { text: "Apply"; accent: true; onClicked: page.applyLimits() }
        }
    }

    overlays: [
        Modal {
            id: createModal
            title: "New snapshot"
            body: "config " + page.cfg + " (" + page.subvol() + ")"
            TextField {
                id: descField
                Layout.fillWidth: true
                placeholder: "description, e.g. before kernel tinkering"
                onAccepted: createOk.clicked()
            }
            CheckBox { id: impBox; text: "Important (survives number cleanup)" }
            buttons: [
                ActionButton { text: "Cancel"; onClicked: createModal.close() },
                ActionButton {
                    id: createOk
                    text: "Create"; accent: true
                    onClicked: { createModal.close(); page.create(descField.text.trim(), impBox.checked); }
                }
            ]
        },
        Modal {
            id: changesModal
            title: "#" + page.chg.a + " → " + (page.chg.b ? "#" + page.chg.b : "now")
            cardWidth: 820
            cardHeight: 560
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.bg
                radius: Math.min(Theme.radius * 0.7, 10)
                border.width: 1
                border.color: Theme.line
                Flickable {
                    id: chgFlick
                    anchors { fill: parent; margins: 8 }
                    clip: true
                    contentWidth: chgEdit.paintedWidth
                    contentHeight: chgEdit.paintedHeight
                    boundsBehavior: Flickable.StopAtBounds
                    TextEdit {
                        id: chgEdit
                        text: page.chgText
                        readOnly: true
                        selectByMouse: true
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 11
                        selectionColor: Theme.alpha(Theme.a1, 0.4)
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                text: page.chgSummary
                color: Theme.dim
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            buttons: [
                ActionButton { text: "Close"; onClicked: changesModal.close() },
                ActionButton { text: "Undo these changes"; danger: true; enabled: page.chgCanUndo; onClicked: page.undo() }
            ]
        },
        Modal {
            id: confirmModal
            z: 110
            buttons: [
                ActionButton { text: "Cancel"; onClicked: confirmModal.close() },
                ActionButton {
                    id: confirmOk
                    danger: true
                    onClicked: { confirmModal.close(); const f = page.confirmFn; page.confirmFn = null; if (f) f(); }
                }
            ]
        }
    ]
}
