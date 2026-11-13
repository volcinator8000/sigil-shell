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
-- Desktop widgets: raise above windows / edit mode
hl.bind("SUPER + W", hl.dsp.global("sigil:widgets-peek"))          -- widgets over the windows (Esc / empty click closes)
hl.bind("SUPER + SHIFT + W", hl.dsp.global("sigil:widgets-edit"))  -- arrange widgets

-- Settings window rules (owned by quickshell/settings)
pcall(dofile, os.getenv("HOME") .. "/sigil-shell/hypr/sigil-settings.lua")

-- Widget maker (sigil-widgets): its live preview floats next to it instead of tiling
hl.window_rule({ name = "sigil-widget-preview", match = { title = "^sigil widget preview$" }, float = true, size = "720 540" })
hl.window_rule({ name = "sigil-widget-snapshot", match = { title = "^sigil widget snapshot$" }, float = true, move = "-3000 -3000", no_initial_focus = true })
