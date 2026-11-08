# sigil-shell

A lightweight [Quickshell](https://quickshell.org) desktop shell for Hyprland, built to
be re-themed and rearranged endlessly. Every visual value lives in one settings file
and changes apply live.

- **Thin top bar**: workspaces, focused window, tray, network, volume, battery, clock
- **Hot corners**: each screen corner runs an action you choose (launcher, overview,
  control center, dashboard, power menu, media)
- **Desktop widgets**: calendar, weather, performance, clock, notes, disks, and a
  *command* widget that shows the output of any shell command. Drag them around (20 px
  grid), and set style, opacity, scale and per-type options on the Widgets page of the
  settings window. `sigil-new-widget <name>` scaffolds a new type: one QML file plus its
  options in `widgets/types/registry.json`. It shows up live, settings form included.
- **Seven palettes**: Cybersigil, one generated from your wallpaper, Ashfall, Cold Iron,
  Bruise, Static and Patina. Templates push the active palette to other apps (kitty for now).
- **Power-aware effects**: full blur, glow and animation on AC. On battery, animations
  get shorter and sensors refresh less often.
- **Replaces the whole stack**, with the old tools kept for switching back:

  | sigil-shell | replaces |
  |---|---|
  | launcher (apps · emoji · clipboard) | rofi |
  | notifications + control center | swaync |
  | power menu | wlogout |
  | lock screen (PAM service `hyprlock`) | hyprlock |
  | volume / mic / brightness OSD | none |
  | wallpaper layer: images, GIF/APNG/animated WebP, video; rotation | hyprpaper |
  | polkit dialog | hyprpolkitagent |
  | settings window | sigil-settings (GTK) |

- **Safe to try**: one command switches between this and your previous setup.

## Install

```sh
pacman -S quickshell            # 0.3.x
git clone https://github.com/volcinator8000/sigil-shell ~/sigil-shell
~/sigil-shell/install.sh        # links ~/.config/quickshell/sigil and ~/.local/bin/sigil-*
```

The installer prints the lines to add to your Hyprland config and to `kitty.conf`:

```lua
-- hyprland.lua: start this instead of waybar
hl.exec_cmd("~/.local/bin/sigil-session")
-- and at the end
pcall(dofile, os.getenv("HOME") .. "/sigil-shell/hypr/sigil.lua")
```

```conf
# kitty.conf
globinclude sigil-colors.conf
```

## Switching

| command | what it does |
|---|---|
| `sigil-switch sigil` | takes a snapper snapshot of /home (if configured), stops waybar, starts sigil-shell |
| `sigil-switch legacy` | stops sigil-shell, deletes generated colour files, starts waybar |
| `sigil-switch toggle` | flips between the two. Also bound to **SUPER+CTRL+SHIFT+B** |
| `sigil-switch status` | current mode and what is running |
| `sigil-switch palette patina` | change palette |
| `sigil-switch test-lock` | show the lock screen for 6 s; it unlocks by itself |

Keybinds and autostart lines call `sigil-do <action>` (launcher, emoji, clipboard,
controlcenter, power, lock, settings, overview, notifd, polkitd, wallpaperd). It runs the
sigil-shell version in sigil mode and the original tool otherwise. If the shell is not
running, it falls back to the original. `sigil-do lock` uses hyprlock if the sigil lock
has not engaged within 2 s, and `hypr/sigil.lua` enables `misc:allow_session_lock_restore`.

The choice is remembered in `~/.config/sigil/mode` and used at the next login.

## Staying up

- `sigil-shell.service` (systemd user unit) runs the shell. Quickshell relaunches its own shell
  process after a crash; systemd restarts the whole thing if that fails too. Apps opened from the
  launcher and the upgrade window get their own scope, so a shell restart never closes them.
- In sigil mode swaync is masked until reboot (`--runtime`), so D-Bus can't hand it the
  notification name while the shell restarts. `sigil-switch legacy` unmasks it.
- `sigil-health` (timer, every minute, ~0.1 s CPU) restarts the shell if it is down, frozen, lost
  the notification name or its PipeWire connection; restarts WirePlumber/PipeWire when only
  "Dummy Output" is left; and notifies you if the session bus or PipeWire get close to their
  1024 open-file limit (naming the programs holding the most connections).
  Log: `journalctl --user -u sigil-health`, or run `sigil-health -v`.
- `sigil-units env|link|sigil|legacy` does the plumbing (copy Hyprland's environment into
  systemd, link the units, hand the session over).

## Wallpapers

Any image Qt + kimageformats can read (jpg png webp avif heif jxl tiff svg psd …),
animated images (gif, apng, animated webp/avif/jxl) and video (mp4 mkv webm mov avi …,
muted, via QtMultimedia + ffmpeg). Needs `qt6-multimedia-ffmpeg` and `kimageformats`.

- **Battery**: with `animate: "auto"` moving wallpapers play only on AC. On battery,
  behind a fullscreen window or while locked, they show a still frame and the decoder
  is unloaded. Stills are cached in `~/.cache/sigil/stills`.
- **Rotation** (`settings.json` → `wallpapers`, or the Desktop page): `fixed`; `interval`
  (every N minutes from a folder, shuffled or in order); `schedule`
  (`[{"at": "07:00", "path": "file or folder"}, …]`, where the latest slot at or before now wins).
- IPC: `qs -c sigil ipc call wallpaper next|prev|set <path>|pause|status`.
- `sigil-switch legacy` hands hyprpaper the still frame and restores the moving
  wallpaper on the way back.

## Keys

| key | action |
|---|---|
| SUPER+W | widget edit mode (drag, restyle, add, remove; Esc or *Done* to leave) |
| SUPER+SHIFT+W | raise widgets above windows |
| click the clock | same as SUPER+SHIFT+W |

## Settings: `~/.config/sigil/settings.json`

```json
{
  "palette": "cybersigil",
  "radius": 10,
  "font": "JetBrainsMono Nerd Font",
  "effects": "auto",
  "corners": { "topLeft": "launcher", "topRight": "controlcenter", "bottomLeft": "media", "bottomRight": "power" },
  "weather": { "city": "Paris", "lat": 48.8566, "lon": 2.3522 },
  "wallpaper": ""
}
```

- `palette`: a file name in `quickshell/palettes/`, or `wallpaper`
- `effects`: `auto` (full on AC, reduced on battery), `full`, or `low`
- corner actions: `launcher` `overview` `controlcenter` `dashboard` `power` `media` `none`
- `wallpaper`: empty means the path from `~/.config/hypr/hyprpaper.conf`

The widget layout is saved to `~/.config/sigil/widgets.json`.

## Layout

```
quickshell/
  shell.qml              entry point
  services/              Theme (settings + palettes), Widgets, Sys, Weather, Actions
  bar/ corners/ panels/  bar, hot corners, media popup
  widgets/               widget layer + types/<name>.qml (one file per widget)
  palettes/*.json        palette definitions
templates/*.tmpl         app colour templates (header says target file + reload command)
bin/                     sigil-switch, sigil-session, sigil-apply, sigil-units, sigil-health
systemd/                 sigil-shell.service, sigil-health.{service,timer}
hypr/sigil.lua           layer blur rules and keybinds
```

## Roadmap

Still uses hyprexpose for the window overview. Next: palette templates for starship,
GTK/Qt, Hyprland borders and hyprlock.

## License

MIT
