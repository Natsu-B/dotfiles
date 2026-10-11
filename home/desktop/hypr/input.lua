-- Keep XKB stable. xremap alone switches normal typing between QWERTY/Dvorak.
hl.config({
    input = {
        kb_layout = "jp",
        kb_variant = "",
        kb_options = "",
        resolve_binds_by_sym = false,
        follow_mouse = 1,
        touchpad = {
            natural_scroll = false,
            disable_while_typing = true,
        },
    },
})

-- Match the GNOME default without disabling the separate TrackPoint buttons.
local touchpad = "syna8022:00-06cb:ce67-touchpad"
local enabled = false
hl.device({ name = touchpad, enabled = enabled })
hl.device({
    name = "tpps/2-elan-trackpoint",
    accel_profile = "adaptive",
    sensitivity = -0.35,
    scroll_method = "on_button_down",
    scroll_button = 274, -- Linux BTN_MIDDLE, not the X11 button number 2.
    scroll_button_lock = false,
    middle_button_emulation = false,
})

-- ponytail: session-only toggle; reload/login restores the declared off default.
return function()
    enabled = not enabled
    hl.device({ name = touchpad, enabled = enabled })
    hl.notification.create({ text = "Touchpad: " .. (enabled and "ON" or "OFF"), timeout = 1500 })
end
