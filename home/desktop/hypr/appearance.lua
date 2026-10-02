hl.config({
    general = {
        gaps_in = 6,
        gaps_out = 12,
        border_size = 2,
        resize_on_border = true,
        layout = "dwindle",
        col = {
            active_border = { colors = { "rgba(cba6f7ff)", "rgba(89b4faff)" }, angle = 45 },
            inactive_border = "rgba(45475aaa)",
        },
    },
    decoration = {
        rounding = 14,
        blur = { enabled = true, size = 8, passes = 2 },
        shadow = { enabled = true, range = 12, render_power = 3, color = "rgba(00000055)" },
    },
    dwindle = { preserve_split = true },
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
})
hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "default", style = "slide" })
hl.layer_rule({ match = { namespace = "^dms:.*" }, no_anim = true, blur = true })
-- Dialogs used during conferencing/settings should not consume a tiled column.
hl.window_rule({ match = { class = "^(zoom)$" }, float = true })
