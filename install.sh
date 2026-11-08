#!/usr/bin/env bash
# Link sigil-shell into place. Safe to re-run; touches nothing outside these paths:
#   ~/.config/quickshell/sigil  -> <repo>/quickshell
#   ~/.local/bin/sigil-{switch,session,apply} -> <repo>/bin/*
#   ~/.config/sigil/settings.json (created with defaults if missing)
set -euo pipefail
REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

mkdir -p "$HOME/.config/quickshell" "$HOME/.local/bin" "$HOME/.config/sigil"
ln -sfn "$REPO/quickshell" "$HOME/.config/quickshell/sigil"
for f in sigil-switch sigil-session sigil-apply; do
    chmod +x "$REPO/bin/$f"
    ln -sfn "$REPO/bin/$f" "$HOME/.local/bin/$f"
done

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
[ -f "$HOME/.config/sigil/mode" ] || echo legacy > "$HOME/.config/sigil/mode"

cat <<EOF
sigil-shell linked.

One-time Hyprland hookup (hyprland.lua):
  1. replace   hl.exec_cmd("waybar")
     with      hl.exec_cmd("~/.local/bin/sigil-session")
  2. append    pcall(dofile, os.getenv("HOME") .. "/sigil-shell/hypr/sigil.lua")
kitty.conf: append   globinclude sigil-colors.conf

Then:  sigil-switch sigil   (and sigil-switch legacy to go back)
EOF
