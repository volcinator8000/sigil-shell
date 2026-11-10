pragma ComponentBehavior: Bound

// System: package updates, restarting pieces of the desktop, and the dotfiles repo.

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components
import qs.settings.controls
import qs.settings.lib

PageView {
    id: page
    property bool pageActive: false
    property string dots: "…"

    Component.onCompleted: refresh()
    function refresh() {
        Sh.run(["git", "-C", Sh.home + "/dotfiles-and-scripts", "status", "--porcelain"], o => {
            const n = o.split("\n").filter(x => x).length;
            page.dots = n ? n + " uncommitted change(s)" : "clean";
        });
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
                { t: "Shell", s: "sigil-shell (bar, panels, notifications, wallpaper, this window too)", k: "shell" },
                { t: "hypridle", s: "idle daemon", k: "hypridle" },
                { t: "hyprsunset", s: "night light daemon", k: "hyprsunset" },
                { t: "Key sounds", s: "typewriter daemon", k: "keys" },
                { t: "Audio stack", s: "pipewire + wireplumber (when sound dies or media will not start)", k: "audio" },
                { t: "Hyprland config", s: "hyprctl reload", k: "hypr" }
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
                        if (k === "shell") Sh.spawn(["systemctl", "--user", "restart", "sigil-shell"]);
                        else if (k === "hypridle") Sh.run(["systemctl", "--user", "restart", "hypridle"]);
                        else if (k === "hyprsunset") Sh.restart("hyprsunset");
                        else if (k === "keys") Sh.run([Sh.ksSh, "restart"]);
                        else if (k === "audio") Sh.run(["systemctl", "--user", "restart", "pipewire", "pipewire-pulse", "wireplumber"], null, 15);
                        else if (k === "hypr") Sh.run(["hyprctl", "reload"]);
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
