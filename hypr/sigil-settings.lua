-- Window rules for the Quickshell settings window (quickshell/settings/Settings.qml).
-- Loaded from sigil.lua. The window is a Quickshell FloatingWindow: class "org.quickshell",
-- title "sigil-settings" (the GTK app keeps its own io.sigil.Settings rule in hyprland.lua).
hl.window_rule({
    name = "float-sigil-shell-settings",
    match = { class = "^org\\.quickshell$", title = "^sigil-settings$" },
    float = true,
    center = true,
    size = "980 640",
})
