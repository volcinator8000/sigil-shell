-- sigil-shell additions to Hyprland. Loaded from hyprland.lua with
--   pcall(dofile, os.getenv("HOME") .. "/sigil-shell/hypr/sigil.lua")
-- Harmless in legacy mode: the rules only match sigil-shell surfaces.

-- Blur behind the bar, panels and glass widgets. Fully transparent pixels are skipped.
hl.layer_rule({ name = "blur-sigil", match = { namespace = "^sigil-(bar|panel|desktop|desktop-raised)$" }, blur = true, ignore_alpha = 0.3 })

local sw = os.getenv("HOME") .. "/.local/bin/sigil-switch"

-- Emergency switch between the old setup and sigil-shell
hl.bind("SUPER + CTRL + SHIFT + B", hl.dsp.exec_cmd(sw .. " toggle"))
-- Desktop widgets: edit mode / raise above windows
hl.bind("SUPER + W", hl.dsp.exec_cmd("qs -c sigil ipc call widgets edit"))
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("qs -c sigil ipc call widgets peek"))
