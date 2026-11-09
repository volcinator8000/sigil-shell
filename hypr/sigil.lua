-- sigil-shell additions to Hyprland. Loaded from hyprland.lua with
--   pcall(dofile, os.getenv("HOME") .. "/sigil-shell/hypr/sigil.lua")

-- sigil-shell animates its own surfaces; Hyprland's layer fade on top of that doubled
-- every open/close and made them feel laggy.
hl.layer_rule({ name = "noanim-sigil", match = { namespace = "^sigil-.*$" }, no_anim = true })
-- Blur only on panel-sized surfaces (bar, popups, OSD, launcher, control center).
-- Full-screen layers (wallpaper, desktop widgets, raised dashboard) are never blurred:
-- Qt redraws the whole surface on any change, which would re-blur the entire screen.
hl.layer_rule({ name = "blur-sigil", match = { namespace = "^sigil-(bar|panel)$" }, blur = true, ignore_alpha = 0.3 })

-- If a lock screen ever crashes, let a new locker (sigil-do lock / hyprlock) take over
-- instead of leaving the session stuck on the "lockscreen died" screen.
hl.config({ misc = { allow_session_lock_restore = true } })

-- Emergency: restart the shell (bar gone, panels stuck, …)
hl.bind("SUPER + CTRL + SHIFT + B", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/sigil restart"))
-- Desktop widgets: edit mode / raise above windows
hl.bind("SUPER + W", hl.dsp.exec_cmd("qs -c sigil ipc call widgets edit"))
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("qs -c sigil ipc call widgets peek"))

-- Settings window rules (owned by quickshell/settings)
pcall(dofile, os.getenv("HOME") .. "/sigil-shell/hypr/sigil-settings.lua")
