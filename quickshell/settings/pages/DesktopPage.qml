pragma ComponentBehavior: Bound

// Desktop: wallpaper gallery (hyprpaper.conf + hyprlock.conf), updates,
// daemon restarts and the dotfiles repo.
// In sigil mode the shell draws the wallpaper itself (it watches hyprpaper.conf),
// so hyprpaper is only restarted in legacy mode; daemons replaced by the shell go
// through sigil-do, which starts the legacy daemon only in legacy mode.

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false
    property string wall: ""
    property var files: []
    property string updates: "not checked yet"
    property string dots: "…"
    property string mode: "legacy"

    // sigil-do from ~/.local/bin, or straight from the repo if it is not linked there yet
    readonly property string sigilDo: 'd="$HOME/.local/bin/sigil-do"; if [ -x "$d" ]; then exec "$d" "$@"; else exec bash "$HOME/sigil-shell/bin/sigil-do" "$@"; fi'
    function sdo(action, cb) { Sh.sh(sigilDo, cb || null, 15, [action]); }
    function isSigil() { return mode === "sigil"; }

    Component.onCompleted: refresh()
    function refresh() {
        Sh.readFile(Sh.home + "/.config/sigil/mode", t => page.mode = t.trim() || "legacy");
        readWallpaper();
        Sh.sh('cd "$1" 2>/dev/null && for f in *; do [ -f "$f" ] && echo "$f"; done', o => {
            const names = o.split("\n").filter(x => x && Wallpapers.isSupported(x) && !/_raw\.png$/.test(x)).sort();
            // video / animated thumbnails are rendered first (cached in ~/.cache/sigil/thumbs)
            Wallpapers.makeStills(names.map(n => Sh.walls + "/" + n), () => page.files = names);
        }, 5, [Sh.walls]);
        updateText();
        Sh.run(["git", "-C", Sh.home + "/dotfiles-and-scripts", "status", "--porcelain"], o => {
            const n = o.split("\n").filter(x => x).length;
            page.dots = n ? n + " uncommitted change(s)" : "clean";
        });
    }
    function readWallpaper() {
        Sh.readFile(Sh.hyprpaper, t => {
            const m = t.match(/^\s*path\s*=\s*(.+)$/m);
            page.wall = m ? m[1].trim() : "";
        });
    }
    function updateText() {
        Sh.readFile(Sh.runtime + "/waybar-updates.json", (t, ok) => {
            if (!ok) { page.updates = "up to date"; return; }
            try {
                const n = String(JSON.parse(t || "{}").text || "").trim();
                page.updates = n ? n + " pending" : "up to date";
            } catch (e) { page.updates = "not checked yet"; }
        });
    }

    function applyWallpaper(path) {
        const old = wall;
        Sh.writeFile(Sh.hyprpaper, "wallpaper {\n    monitor =\n    path = " + path + "\n    fit_mode = cover\n}\nsplash = false\n", () => {
            // byte-exact replace (the shell readers trim output)
            if (old) Sh.run(["python3", "-c",
                             "import sys\np, o, n = sys.argv[1:]\ntry:\n    t = open(p).read()\nexcept OSError:\n    sys.exit()\nif o in t:\n    open(p, 'w').write(t.replace(o, n))",
                             Sh.hyprlock, old, path]);
            Sh.readFile(Sh.home + "/.config/sigil/mode", m => {
                page.mode = m.trim() || "legacy";
                if (!page.isSigil()) Sh.restart("hyprpaper");
            });
        });
        wall = path;
        Sh.toast("Wallpaper applied");
    }
    function pickWallpaper() {
        Sh.run(["zenity", "--file-selection", "--title=Choose wallpaper", "--file-filter=Wallpapers | " + Wallpapers.allExt.map(e => "*." + e + " *." + e.toUpperCase()).join(" "), "--file-filter=All files | *"], (o, rc) => {
            const path = o.trim();
            if (rc !== 0 || !path) return;
            Sh.sh('mkdir -p "$2"; d="$2/$(basename "$1")"; [ "$(realpath "$1")" = "$(realpath "$d" 2>/dev/null)" ] || cp -p "$1" "$d"; printf "%s" "$d"',
                  dest => { page.applyWallpaper(dest); page.refresh(); }, 30, [path, Sh.walls]);
        }, 600);
    }

    Section {
        title: "Wallpaper"
        description: "Images, GIFs and videos in ~/Pictures/Wallpapers. Click a tile to apply; hyprlock's background follows."
            + (page.isSigil() ? " sigil-shell draws it (crossfade); hyprpaper is left alone." : "")
        card: false
        Flow {
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                model: page.files
                delegate: Rectangle {
                    id: tile
                    required property string modelData
                    readonly property string path: Sh.walls + "/" + modelData
                    readonly property bool current: page.wall === path
                    width: 200
                    height: 112 + 24
                    radius: Theme.radius
                    color: Theme.s1
                    border.width: current ? 2 : 1
                    border.color: current ? Theme.a1 : tm.containsMouse ? Theme.a2 : Theme.line
                    clip: true
                    Image {
                        x: 1; y: 1
                        width: parent.width - 2
                        height: 112
                        source: "file://" + Wallpapers.thumbFor(tile.path)
                        sourceSize.width: 400
                        sourceSize.height: 224
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }
                    // type badge for moving wallpapers
                    Rectangle {
                        readonly property string k: Wallpapers.kindOf(tile.path)
                        visible: k !== "image"
                        anchors { top: parent.top; right: parent.right; margins: 6 }
                        width: badge.implicitWidth + 10
                        height: 16
                        radius: 4
                        color: Theme.alpha(Theme.bg, 0.8)
                        Label {
                            id: badge
                            anchors.centerIn: parent
                            text: (parent.k === "video" ? "▶ " + Wallpapers.ext(tile.path) : Wallpapers.ext(tile.path)).toUpperCase()
                            color: Theme.a2
                            font.pixelSize: 9
                            font.bold: true
                        }
                    }
                    Label {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 7; bottomMargin: 5 }
                        text: tile.modelData.replace(/\.[^.]+$/, "")
                        color: tile.current ? Theme.a1 : Theme.dim
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: tm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Sh.snd("click"); page.applyWallpaper(tile.path); }
                    }
                }
            }
        }
    }
    Section {
        SettingRow {
            title: "Other image"; subtitle: "Pick any file; it is copied into the wallpaper folder"
            ActionButton { text: "Choose…"; onClicked: page.pickWallpaper() }
        }
    }

    // ── rotation & animation (settings.json → wallpapers; see services/Wallpapers.qml) ──
    readonly property var wcfg: Theme.wallpapers || ({})
    readonly property string wmode: wcfg.mode || "fixed"
    readonly property var wsched: (wcfg.schedule || []).slice().sort((a, b) => String(a.at).localeCompare(String(b.at)))
    function setSched(list) { Wallpapers.setConfig({ schedule: list }); }

    Section {
        title: "Rotation"
        description: page.wmode === "interval" ? "A new wallpaper from the folder every few minutes."
                   : page.wmode === "schedule" ? "Each time slot shows its wallpaper until the next slot starts. A folder picks a random file from it."
                   : "The wallpaper stays as picked above."
        SettingRow {
            title: "Change wallpaper"
            Segmented {
                options: ["fixed", "interval", "schedule"]
                current: page.wmode
                onActivated: (v) => Wallpapers.setConfig({ mode: v })
            }
        }
        SettingRow {
            visible: page.wmode === "interval"
            title: "Every"; subtitle: "minutes"
            SpinField { from: 1; to: 1440; value: page.wcfg.interval || 30; onValueModified: (v) => Wallpapers.setConfig({ interval: Math.round(v) }) }
        }
        SettingRow {
            visible: page.wmode === "interval"
            title: "Shuffle"; subtitle: "random order instead of alphabetical"
            Toggle { checked: page.wcfg.shuffle !== false; onToggled: (c) => Wallpapers.setConfig({ shuffle: c }) }
        }
        SettingRow {
            visible: page.wmode === "interval"
            title: "Folder"; subtitle: "Enter to save"
            TextField {
                Layout.preferredWidth: 300
                text: page.wcfg.folder || "~/Pictures/Wallpapers"
                onAccepted: Wallpapers.setConfig({ folder: text })
            }
        }
        // schedule editor
        Repeater {
            model: page.wmode === "schedule" ? page.wsched : []
            delegate: SettingRow {
                id: srow
                required property var modelData
                required property int index
                title: "From"
                TextField {
                    Layout.preferredWidth: 70
                    text: srow.modelData.at
                    placeholder: "07:00"
                    error: !/^([01]\d|2[0-3]):[0-5]\d$/.test(text)
                    onAccepted: if (!error) { const l = page.wsched.slice(); l[srow.index] = { at: text, path: srow.modelData.path }; page.setSched(l); }
                }
                TextField {
                    Layout.preferredWidth: 340
                    text: srow.modelData.path
                    placeholder: "file or folder"
                    onAccepted: { const l = page.wsched.slice(); l[srow.index] = { at: srow.modelData.at, path: text }; page.setSched(l); }
                }
                IconButton {
                    glyph: String.fromCodePoint(0xF0A7A); hint: "remove"; tint: Theme.crit
                    onClicked: page.setSched(page.wsched.filter((_, i) => i !== srow.index))
                }
            }
        }
        SettingRow {
            visible: page.wmode === "schedule"
            title: "Add a time slot"; subtitle: "starts with the current wallpaper; edit the time and path, Enter saves"
            ActionButton {
                text: "Add"
                onClicked: {
                    const used = page.wsched.map(e => e.at);
                    let h = 7; while (used.indexOf(("0" + h).slice(-2) + ":00") >= 0 && h < 23) h++;
                    page.setSched(page.wsched.concat([{ at: ("0" + h).slice(-2) + ":00", path: Wallpapers.current }]));
                }
            }
        }
        SettingRow {
            visible: page.wmode !== "fixed"
            title: "Skip ahead"; subtitle: "next wallpaper now (also: qs -c sigil ipc call wallpaper next)"
            ActionButton { text: "Next"; onClicked: Wallpapers.next(1) }
        }
    }

    Section {
        title: "Animated wallpapers"
        description: "GIF, animated WebP/AVIF/JXL and video (mp4, mkv, webm, mov…) play muted. When they don't play, a still frame is shown and the decoder is unloaded."
        SettingRow {
            title: "Play animations"
            subtitle: page.wcfg.animate === "always" ? "always, also on battery"
                    : page.wcfg.animate === "never" ? "never; always the still frame"
                    : "only when plugged in; still frame on battery"
            Segmented {
                options: ["auto", "always", "never"]
                current: page.wcfg.animate || "auto"
                onActivated: (v) => Wallpapers.setConfig({ animate: v })
            }
        }
        SettingRow {
            title: "Pause behind fullscreen windows"; subtitle: "games and videos cover it anyway"
            Toggle { checked: page.wcfg.pauseFullscreen !== false; onToggled: (c) => Wallpapers.setConfig({ pauseFullscreen: c }) }
        }
        SettingRow {
            title: "Now"
            subtitle: Wallpapers.kind === "image" ? "still image" : (Wallpapers.shouldPlay ? "playing" : "paused (still frame)")
                      + (Wallpapers.kind !== "image" && UPower.onBattery ? " · on battery" : "")
        }
    }

    Section {
        title: "Updates"
        SettingRow {
            title: "Pending packages"
            subtitle: Updates.checking ? "checking…" : Updates.upgrading ? "upgrading…"
                    : Updates.state === "unknown" ? "not checked yet"
                    : Updates.count ? Updates.count + " pending (repo " + Updates.repo + ", aur " + Updates.aur + ")" : "up to date"
            ActionButton {
                text: "Check now"
                enabled: !Updates.checking
                onClicked: { Updates.check(); Sh.toast("Checking for updates…"); }
            }
            ActionButton { text: "Update"; accent: true; enabled: !Updates.upgrading; onClicked: Updates.upgrade() }
        }
    }

    Section {
        title: "Services"
        description: "Restart a piece of the desktop without logging out."
        Repeater {
            model: [
                { t: "Status bar", s: "sigil-switch restart (sigil-shell, or waybar in legacy mode)", k: "bar" },
                { t: "Notifications", s: "sigil-do notifd; in legacy mode SwayNC also reloads config and style", k: "notifd" },
                { t: "Polkit agent", s: "sigil-do polkitd (hyprpolkitagent in legacy mode, the shell otherwise)", k: "polkitd" },
                { t: "hypridle", s: "idle daemon", k: "hypridle" },
                { t: "Wallpaper", s: "sigil-do wallpaperd (hyprpaper in legacy mode; the shell draws it otherwise)", k: "wallpaperd" },
                { t: "hyprsunset", s: "night light daemon", k: "hyprsunset" },
                { t: "Key sounds", s: "typewriter daemon", k: "keys" },
                { t: "Audio stack", s: "pipewire + wireplumber (when sound dies or media will not start)", k: "audio" },
                { t: "Hyprland config", s: "hyprctl reload", k: "hypr" },
                { t: "GTK settings app", s: "the resident python sigil-settings (reloads its code)", k: "gtk" }
            ]
            delegate: SettingRow {
                id: svc
                required property var modelData
                title: modelData.t
                subtitle: modelData.s
                ActionButton {
                    text: "Restart"
                    onClicked: {
                        const k = svc.modelData.k;
                        if (k === "bar") Sh.spawn([Sh.home + "/.local/bin/sigil-switch", "restart"]);
                        else if (k === "notifd") page.sdo("notifd", () => { if (!page.isSigil()) Sh.sh("swaync-client -R; swaync-client -rs"); });
                        else if (k === "polkitd") page.sdo("polkitd");
                        else if (k === "wallpaperd") {
                            if (page.isSigil()) page.sdo("wallpaperd");
                            else Sh.run(["pkill", "-x", "hyprpaper"], () => Sh.later(300, () => page.sdo("wallpaperd")));
                        }
                        else if (k === "hypridle") Sh.restart("hypridle");
                        else if (k === "hyprsunset") Sh.restart("hyprsunset");
                        else if (k === "keys") Sh.run([Sh.ksSh, "restart"]);
                        else if (k === "audio") Sh.run(["systemctl", "--user", "restart", "pipewire", "pipewire-pulse", "wireplumber"], null, 15);
                        else if (k === "hypr") Sh.run(["hyprctl", "reload"]);
                        else if (k === "gtk") Sh.spawn(["sh", "-c", "python3 ~/.config/sigil-settings/sigil-settings.py --quit; sleep 1; python3 ~/.config/sigil-settings/sigil-settings.py --hidden"]);
                        Sh.toast(svc.modelData.t + " restarted");
                    }
                }
            }
        }
    }

    Section {
        title: "Dotfiles"
        description: "~/dotfiles-and-scripts — configs are symlinks into it; a weekly timer commits and pushes."
        SettingRow {
            title: "Repository"; subtitle: page.dots
            ActionButton {
                text: "Sync now"; accent: true
                onClicked: Sh.run([Sh.home + "/.local/bin/dots-sync"], o => { page.dots = o.replace(/\n/g, " · ") || "nothing to do"; Sh.toast("Dotfiles synced"); }, 60)
            }
            ActionButton { text: "Open"; onClicked: Sh.spawn(["xdg-open", Sh.home + "/dotfiles-and-scripts"]) }
        }
    }
}
