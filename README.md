# sigil-shell

A lightweight [Quickshell](https://quickshell.org) desktop shell for Hyprland, built to
be re-themed and rearranged endlessly. Every visual value lives in one settings file
and changes apply live.

- **Thin top bar**: workspaces, focused window, tray, network, volume, battery, clock
- **Hot corners**: each screen corner runs an action you choose (launcher, overview,
  control center, dashboard, power menu, media)
- **Desktop widgets**: calendar, weather, performance, clock, notes, disks. Drag them
  around (20 px grid), switch each between *card*, *glass* and *bare*, add or remove
  them. Adding a new widget type means adding one QML file.
- **Seven palettes**: Cybersigil, one generated from your wallpaper, Ashfall, Cold Iron,
  Bruise, Static and Patina. Templates push the active palette to other apps (kitty for now).
- **Power-aware effects**: full blur, glow and animation on AC. On battery, animations
  get shorter and sensors refresh less often.
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

The choice is remembered in `~/.config/sigil/mode` and used at the next login.

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
bin/                     sigil-switch, sigil-session, sigil-apply
hypr/sigil.lua           layer blur rules and keybinds
```

## Roadmap

Still handed off to existing tools (rofi, swaync, wlogout, hyprlock) until rebuilt here:
launcher, notifications and control center, power menu, OSD, lock screen. Next up:
a sigil-settings page for palettes, roundness, font and corner mapping, plus templates
for starship, GTK/Qt, Hyprland borders and hyprlock.

## License

MIT
