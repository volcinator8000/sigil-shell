pragma ComponentBehavior: Bound

// Wi-Fi via nmcli, plus Tailscale and KDE Connect status (same commands as the GTK app).

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false
    property string dev: "wlan0"
    property var nets: []              // [{ssid, sig, sec, active, known}]
    property string status: ""
    property bool scanning: false
    property string ts: "…"
    property var tsInfo: ({ st: "", ip: "", name: "", online: 0 })
    property string phone: "…"
    property string pwSsid: ""
    property string pwSec: ""

    Component.onCompleted: {
        Sh.run(["nmcli", "-t", "-f", "DEVICE,TYPE", "dev"], o => {
            const l = o.split("\n").find(x => x.endsWith(":wifi"));
            page.dev = l ? l.split(":")[0] : "wlan0";
            refresh();
        });
    }
    function refresh() {
        Sh.run(["nmcli", "radio", "wifi"], o => wifiSw.checked = o === "enabled");
        tsStatus();
        phoneStatus();
        scan(false);
    }

    function tsStatus() {
        Sh.run(["tailscale", "status", "--json"], o => {
            let d;
            try { d = JSON.parse(o); } catch (e) { d = null; }
            if (!d) {
                page.tsInfo = { st: "", ip: "", name: "", online: 0 };
                page.ts = "not installed or not running (sudo pacman -S tailscale; sudo systemctl enable --now tailscaled; sudo tailscale up --ssh)";
                return;
            }
            const me = d.Self || {};
            const ip = (me.TailscaleIPs || []).find(a => a.indexOf(".") >= 0) || "";
            const name = (me.DNSName || "").replace(/\.$/, "");
            const online = Object.values(d.Peer || {}).filter(p => p.Online).length;
            const st = d.BackendState || "";
            page.tsInfo = { st: st, ip: ip, name: name, online: online };
            page.ts = st !== "Running" ? st.toLowerCase() + " · run: sudo tailscale up --ssh"
                    : "connected · " + ip + (name ? " · " + name.split(".")[0] : "") + " · " + online + " other device(s) online";
        }, 4);
    }
    function copyTs() {
        const i = tsInfo, target = i.name ? i.name.split(".")[0] : i.ip;
        if (!target) { Sh.toast("Tailscale is not connected"); return; }
        Sh.sh('printf "%s" "$1" | wl-copy', () => Sh.toast("Copied: ssh " + Sh.user + "@" + target), 4, ["ssh " + Sh.user + "@" + target]);
    }
    function phoneStatus() {
        Sh.sh('command -v kdeconnect-cli >/dev/null || { echo "@missing"; exit; }; timeout 4 kdeconnect-cli -l', o => {
            if (o === "@missing") { page.phone = "kdeconnect not installed (sudo pacman -S kdeconnect; sudo ufw allow 1714:1764/tcp; sudo ufw allow 1714:1764/udp)"; return; }
            const r = o.split("\n").filter(l => l.indexOf("reachable") >= 0 && l.indexOf("paired") >= 0);
            page.phone = r.length ? r[0].trim().replace(/^[- ]+/, "") : "no phone reachable · pair from the KDE Connect app (add by Tailscale IP when not on the same Wi-Fi)";
        }, 6);
    }

    function scan(rescan) {
        scanning = true;
        if (rescan) status = "scanning…";
        Sh.runAll(["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,BSSID", "dev", "wifi", "list"].concat(rescan ? ["--rescan", "yes"] : []), out => {
            Sh.sh('nmcli -t -f NAME,DEVICE con show --active; echo @@; nmcli -t -f NAME,TYPE con show', cons => {
                const [a, k] = cons.split("@@");
                const active = (a || "").split("\n").filter(l => l.endsWith(":" + page.dev)).map(l => l.split(":")[0]);
                const known = (k || "").split("\n").filter(l => l.endsWith("802-11-wireless")).map(l => l.split(":")[0]);
                const seen = {}, list = [];
                for (const line of out.split("\n")) {
                    const parts = line.replace(/\\:/g, "\u0000").split(":").map(p => p.replace(/\u0000/g, ":"));
                    if (parts.length < 3) continue;
                    const ssid = parts[0];
                    if (!ssid || seen[ssid]) continue;
                    seen[ssid] = true;
                    list.push({ ssid: ssid, sig: parseInt(parts[1]) || 0, sec: parts[2], active: active.indexOf(ssid) >= 0, known: known.indexOf(ssid) >= 0 });
                }
                list.sort((x, y) => (x.active === y.active ? y.sig - x.sig : (x.active ? -1 : 1)));
                page.nets = list;
                page.status = list.length ? list.length + " network(s) · " + page.dev : (!wifiSw.checked ? "Wi-Fi is off" : "nothing found");
                page.scanning = false;
            });
        }, 25);
    }
    function cmd(c, ok) {
        Sh.toast("Working…");
        Sh.runAll(c, (o, rc) => { Sh.toast(rc === 0 ? ok : Sh.lastLine(o, "failed")); page.scan(false); }, 45);
    }
    function connect(n) {
        if (n.known || !n.sec) cmd(n.known ? ["nmcli", "con", "up", "id", n.ssid] : ["nmcli", "dev", "wifi", "connect", n.ssid], "Connected to " + n.ssid);
        else { pwSsid = n.ssid; pwSec = n.sec; pwField.text = ""; pwModal.open(); pwField.input.forceActiveFocus(); }
    }
    function sigGlyph(s) { return s > 75 ? "\u{F0928}" : s > 50 ? "\u{F0925}" : s > 25 ? "\u{F0922}" : "\u{F091F}"; }

    Section {
        title: "Wi-Fi"
        SettingRow {
            title: "Wi-Fi"; subtitle: page.dev
            Toggle {
                id: wifiSw
                onToggled: on => Sh.run(["nmcli", "radio", "wifi", on ? "on" : "off"], () => Sh.later(1500, () => page.scan(false)))
            }
        }
    }

    Section {
        title: "Remote access"
        description: "Tailscale: private network between your devices, works from anywhere; SSH goes over it."
        SettingRow {
            title: "Tailscale"; subtitle: page.ts
            ActionButton { text: "Copy ssh command"; onClicked: page.copyTs() }
        }
        SettingRow {
            title: "Phone (KDE Connect)"; subtitle: page.phone
            ActionButton { text: "Pair / manage"; onClicked: Sh.spawn(["kdeconnect-app"]) }
            ActionButton {
                text: "Find phone"
                onClicked: Sh.sh('id=$(timeout 4 kdeconnect-cli -a --id-only | head -1); kdeconnect-cli --ring -d "$id"', () => Sh.toast("Ringing the phone"), 8)
            }
        }
    }

    Section {
        title: "Networks"
        description: page.status
        actions: [
            ActionButton { text: page.scanning ? "Scanning…" : "Rescan"; small: false; onClicked: page.scan(true) }
        ]
        Repeater {
            model: page.nets
            delegate: SettingRow {
                id: net
                required property var modelData
                glyph: page.sigGlyph(modelData.sig)
                glyphColor: modelData.active ? Theme.a1 : Theme.dim
                title: modelData.ssid + (modelData.active ? "  \u{F012C}" : "")
                titleColor: modelData.active ? Theme.a1 : Theme.fg
                subtitle: modelData.sig + "%  ·  " + (modelData.sec || "open") + (modelData.known && !modelData.active ? "  ·  saved" : "")
                ActionButton {
                    visible: net.modelData.active
                    text: "Disconnect"
                    onClicked: page.cmd(["nmcli", "dev", "disconnect", page.dev], "Disconnected")
                }
                ActionButton {
                    visible: !net.modelData.active
                    text: "Connect"; accent: true
                    onClicked: page.connect(net.modelData)
                }
                IconButton {
                    visible: !net.modelData.active && net.modelData.known
                    glyph: "\u{F01B4}"; hint: "Forget network"
                    onClicked: page.cmd(["nmcli", "con", "delete", "id", net.modelData.ssid], "Forgot " + net.modelData.ssid)
                }
            }
        }
    }

    overlays: Modal {
        id: pwModal
        title: page.pwSsid
        body: page.pwSec + " network"
        TextField {
            id: pwField
            Layout.fillWidth: true
            password: true
            placeholder: "password"
            onAccepted: connectBtn.clicked()
        }
        buttons: [
            ActionButton { text: "Cancel"; onClicked: pwModal.close() },
            ActionButton {
                id: connectBtn
                text: "Connect"; accent: true
                onClicked: {
                    pwModal.close();
                    page.cmd(["nmcli", "dev", "wifi", "connect", page.pwSsid, "password", pwField.text], "Connected to " + page.pwSsid);
                    pwField.text = "";
                }
            }
        ]
    }
}
