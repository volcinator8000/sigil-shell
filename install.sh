#!/usr/bin/env bash
# Link sigil-shell into place. Safe to re-run; touches nothing outside these paths:
#   ~/.config/quickshell/sigil  -> <repo>/quickshell
#   ~/.local/bin/sigil*        -> <repo>/bin/*
#   ~/.local/share/applications/sigil-*.desktop -> <repo>/applications/*
#   ~/.config/systemd/user/sigil-{shell,health}.* -> <repo>/systemd/*
#   ~/.config/sigil/settings.json (created with defaults if missing)
set -euo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

mkdir -p "$HOME/.config/quickshell" "$HOME/.local/bin" "$HOME/.config/sigil"
ln -sfn "$REPO/quickshell" "$HOME/.config/quickshell/sigil"
for f in "$REPO"/bin/*; do
    chmod +x "$f"
    ln -sfn "$f" "$HOME/.local/bin/$(basename "$f")"
done
"$REPO/bin/sigil-units" link
mkdir -p "$HOME/.local/share/applications"
for f in "$REPO"/applications/*.desktop; do ln -sfn "$f" "$HOME/.local/share/applications/$(basename "$f")"; done

if [ ! -f "$HOME/.config/sigil/settings.json" ]; then
    cat > "$HOME/.config/sigil/settings.json" <<'EOF'
{
  "palette": "cybersigil",
  "radius": 10,
  "font": "JetBrainsMono Nerd Font",
  "effects": "auto",
  "corners": {
    "topLeft": "launcher",
    "topRight": "controlcenter",
    "bottomLeft": "media",
    "bottomRight": "power"
  },
  "weather": { "city": "Paris", "lat": 48.8566, "lon": 2.3522 },
  "wallpaper": ""
}
EOF
fi

cat <<EOF
sigil-shell linked.

One-time Hyprland hookup (hyprland.lua):
  1. autostart  hl.exec_cmd("~/.local/bin/sigil-session")   (instead of your bar / notification daemon)
  2. append     pcall(dofile, os.getenv("HOME") .. "/sigil-shell/hypr/sigil.lua")
kitty.conf: append   globinclude sigil-colors.conf

Then log in again, or run:  sigil-session
EOF
