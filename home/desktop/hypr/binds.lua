local c = require("commands")
local toggle_touchpad = require("input")

local restore_frames = {}
local function apply_frame(window, frame)
    local selector = "address:" .. window.address
    hl.dispatch(hl.dsp.window.float({ window = selector, action = "on" }))
    hl.dispatch(hl.dsp.window.resize({ window = selector,
        x = frame.size.x, y = frame.size.y, relative = false }))
    hl.dispatch(hl.dsp.window.move({ window = selector,
        x = frame.at.x, y = frame.at.y, relative = false }))
end

local function restore_display(window, frame)
    -- Ignore geometry belonging to a reused address or another monitor.
    local monitor = window.monitor
    if frame and (frame.pid ~= window.pid or frame.monitor ~= (monitor and monitor.id)) then frame = nil end
    if frame and frame.floating then
        apply_frame(window, frame)
        return
    end
    if window.floating or not window.workspace then return end
    for _, other in ipairs(hl.get_windows()) do
        if other.address ~= window.address and not other.hidden and not other.floating
            and other.workspace and other.workspace.name == window.workspace.name then return end
    end
    -- An only tiled window still fills the workspace after unmaximizing.
    -- Restore its previous smaller rectangle, or use 80% of the working area.
    local at, size = window.at, window.size
    if not frame or (frame.size.x >= size.x * 0.95 and frame.size.y >= size.y * 0.95) then
        local width, height = math.max(1, math.floor(size.x * 0.8)), math.max(1, math.floor(size.y * 0.8))
        frame = { size = { x = width, y = height },
            at = { x = at.x + math.floor((size.x - width) / 2), y = at.y + math.floor((size.y - height) / 2) } }
    end
    apply_frame(window, frame)
end

-- Read both states at keypress time. Hyprland's maximized toggle can leave a
-- combined fullscreen/maximized window maximized, or retain a client-only flag.
local function display_toggle(mode)
    return function()
        local window = hl.get_active_window()
        if not window then return end
        local current = window.fullscreen | window.fullscreen_client
        local state = mode
        -- Win+F restores from every expanded state; Win+Shift+F can still
        -- promote a maximized window to fullscreen before restoring it.
        if (mode == 1 and current ~= 0) or (current & mode) ~= 0 then state = 0 end
        if state ~= 0 and current == 0 then
            local at, size, monitor = window.at, window.size, window.monitor
            restore_frames[window.address] = { pid = window.pid, monitor = monitor and monitor.id,
                floating = window.floating, at = { x = at.x, y = at.y }, size = { x = size.x, y = size.y } }
        end
        hl.dispatch(hl.dsp.window.fullscreen_state({ window = "address:" .. window.address,
            internal = state, client = state, action = "set" }))
        if state == 0 then
            restore_display(window, restore_frames[window.address])
            restore_frames[window.address] = nil
        end
    end
end

-- A shared minimized workspace brings every hidden window back together.
-- Give each window its own workspace, and always address the active window.
local function minimize()
    local window = hl.get_active_window()
    if not window or not window.workspace then return end
    local base = "minimized-" .. window.address:gsub("^0x", "")
    local name, occupied, suffix = base, {}, 0
    -- New windows can join a revealed special workspace. Never hide those too.
    for _, other in ipairs(hl.get_windows()) do
        if other.address ~= window.address and other.workspace then
            occupied[other.workspace.name] = true
        end
    end
    while occupied["special:" .. name] do
        suffix = suffix + 1
        name = base .. "-" .. suffix
    end
    local target = "special:" .. name
    local monitor = window.monitor or hl.get_active_monitor()
    local special = monitor and monitor.active_special_workspace
    if window.workspace.name ~= target then
        hl.dispatch(hl.dsp.window.move({ window = "address:" .. window.address,
            workspace = target, follow = false }))
    end
    if special and special.name == target then
        hl.dispatch(hl.dsp.workspace.toggle_special(name))
    end
end

-- Explicitly viewing all minimized windows retains the existing Ctrl+M action.
-- Win+M still removes just the selected window from this shared view.
local function toggle_minimized()
    local monitor = hl.get_active_monitor()
    local special = monitor and monitor.active_special_workspace
    if not special or special.name ~= "special:minimized" then
        for _, window in ipairs(hl.get_windows()) do
            local name = window.workspace and window.workspace.name
            if name and name:match("^special:minimized%-") then
                hl.dispatch(hl.dsp.window.move({ window = "address:" .. window.address,
                    workspace = "special:minimized", follow = false }))
            end
        end
    end
    hl.dispatch(hl.dsp.workspace.toggle_special("minimized"))
end

-- Keys are XKB physical codes (evdev + 8), unaffected by typing profile.
hl.bind("SUPER + space", hl.dsp.exec_cmd(c.launcher), { description = "Apps and actions" })
hl.bind("SUPER + code:40", hl.dsp.exec_cmd(c.launcher), { description = "Apps and actions (Win+D)" })
hl.bind("SUPER + F1", hl.dsp.exec_cmd(c.cheatsheet), { description = "Shortcut cheat sheet" })
hl.bind("SUPER + Tab", hl.dsp.exec_cmd(c.windowSwitcher), { description = "Running apps across all workspaces" })
hl.bind("SUPER + F2", hl.dsp.exec_cmd(c.keyboard), { release = true, description = "QWERTY / custom Dvorak" })
hl.bind("SUPER + F3", toggle_touchpad, { locked = true, release = true, description = "Touchpad on / off" })
hl.bind("SUPER + code:55", hl.dsp.exec_cmd(c.clipboard), { description = "Private clipboard history (Win+V)" })
hl.bind("SUPER + SHIFT + code:55", hl.dsp.exec_cmd(c.clipboardPrivacy), { description = "Pause / resume clipboard history" })
hl.bind("SUPER + CTRL + code:55", hl.dsp.exec_cmd(c.clipboardClear), { description = "Clear clipboard history" })
hl.bind("SUPER + Return", hl.dsp.exec_cmd(c.terminal), { description = "Terminal" })
hl.bind("CTRL + ALT + T", hl.dsp.exec_cmd(c.terminal), { description = "Emergency terminal (Ctrl+Alt+T)" })
hl.bind("SUPER + code:26", hl.dsp.exec_cmd(c.fileManager), { description = "Files (Win+E)" })
hl.bind("SUPER + code:46", hl.dsp.exec_cmd(c.lock), { description = "Lock and clear clipboard (Win+L)" })
hl.bind("SUPER + code:33", hl.dsp.exec_cmd(c.dms .. " ipc call settings focusOrToggleWith displays"), { description = "Displays / mirroring (Win+P)" })
hl.bind("SUPER + code:31", hl.dsp.exec_cmd(c.dms .. " ipc call settings focusOrToggle"), { description = "Desktop settings (Win+I)" })
hl.bind("SUPER + code:38", hl.dsp.exec_cmd(c.dms .. " ipc call control-center toggle"), { description = "Quick settings (Win+A)" })
hl.bind("SUPER + code:57", hl.dsp.exec_cmd(c.dms .. " ipc call notifications toggle"), { description = "Notifications (Win+N)" })
hl.bind("SUPER + code:53", hl.dsp.exec_cmd(c.dms .. " ipc call powermenu toggle"), { description = "Power menu (Win+X)" })
hl.bind("SUPER + CTRL + F5", hl.dsp.exec_cmd(c.restartShell), { description = "Restart DMS" })

hl.bind("SUPER + SHIFT + code:24", hl.dsp.window.close(), { description = "Close window (Win+Shift+Q)" })
hl.bind("SUPER + code:58", minimize, { description = "Minimize selected window (Win+M)" })
hl.bind("SUPER + CTRL + code:58", toggle_minimized, { description = "Show / hide minimized windows (Win+Ctrl+M)" })
hl.bind("SUPER + code:41", display_toggle(1), { description = "Maximize with bar (Win+F)" })
hl.bind("SUPER + SHIFT + code:41", display_toggle(2), { description = "Fullscreen (Win+Shift+F)" })
hl.bind("SUPER + CTRL + code:41", display_toggle(1), { description = "Maximize with bar (Win+Ctrl+F)" })
hl.bind("SUPER + SHIFT + space", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind("SUPER + SHIFT + code:58", hl.dsp.exec_cmd(c.logout), { description = "End UWSM session (Win+Shift+M)" })
hl.bind("SUPER + left", hl.dsp.focus({ direction = "l" }), { description = "Focus left" })
hl.bind("SUPER + right", hl.dsp.focus({ direction = "r" }), { description = "Focus right" })
hl.bind("SUPER + up", hl.dsp.focus({ direction = "u" }), { description = "Focus above" })
hl.bind("SUPER + down", hl.dsp.focus({ direction = "d" }), { description = "Focus below" })
hl.bind("SUPER + SHIFT + left", hl.dsp.exec_cmd(c.snapAssist .. " left"), { description = "Move left / snap and choose right app" })
hl.bind("SUPER + SHIFT + right", hl.dsp.exec_cmd(c.snapAssist .. " right"), { description = "Move right / snap and choose left app" })
hl.bind("SUPER + SHIFT + up", hl.dsp.exec_cmd(c.snapAssist .. " up"), { description = "Move above / snap and choose lower app" })
hl.bind("SUPER + SHIFT + down", hl.dsp.exec_cmd(c.snapAssist .. " down"), { description = "Move below / snap and choose upper app" })
hl.bind("SUPER + CTRL + left", hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true, description = "Resize window left" })
hl.bind("SUPER + CTRL + right", hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true, description = "Resize window right" })
hl.bind("SUPER + CTRL + up", hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true, description = "Resize window up" })
hl.bind("SUPER + CTRL + down", hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true, description = "Resize window down" })
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Drag window" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

for workspace = 1, 10 do
    local code = tostring(workspace + 9)
    hl.bind("SUPER + code:" .. code, hl.dsp.exec_cmd(c.dms .. " ipc call dotfiles-apps activate " .. workspace), { description = "Activate app " .. workspace .. (workspace <= 6 and " (fixed)" or " (bar)") })
    hl.bind("SUPER + CTRL + code:" .. code, hl.dsp.focus({ workspace = workspace }), { description = "Workspace " .. workspace })
    hl.bind("SUPER + SHIFT + code:" .. code, hl.dsp.window.move({ workspace = workspace, follow = false }), { description = "Send to workspace " .. workspace })
end

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(c.dms .. " ipc call audio increment 5"), { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(c.dms .. " ipc call audio decrement 5"), { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(c.dms .. " ipc call audio mute"), { locked = true, description = "Mute audio" })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(c.dms .. " ipc call audio micmute"), { locked = true, description = "Mute microphone" })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(c.dms .. ' ipc call brightness increment 5 ""'), { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(c.dms .. ' ipc call brightness decrement 5 ""'), { locked = true, repeating = true, description = "Brightness down" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(c.dms .. " ipc call mpris playPause"), { locked = true, description = "Play / pause" })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(c.dms .. " ipc call mpris next"), { locked = true, description = "Next track" })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(c.dms .. " ipc call mpris previous"), { locked = true, description = "Previous track" })
hl.bind("Print", hl.dsp.exec_cmd(c.dms .. " screenshot"), { description = "Screenshot region" })

-- Native polling avoids a daemon and subprocesses on every pointer check.
-- Reloading the config replaces this timer; entering once requires leaving 32px first.
local armed = false
local runtime = os.getenv("XDG_RUNTIME_DIR")
local started = false
local function start_corner()
    if started then return end
    started = true
    hl.timer(function()
        local cursor = hl.get_cursor_pos()
        if not cursor then return end
        local near, hit = false, false
        for _, monitor in ipairs(hl.get_monitors()) do
            if monitor.dpms_status then
                local dx, dy = cursor.x - monitor.x, cursor.y - monitor.y
                near = near or (dx >= 0 and dx < 32 and dy >= 0 and dy < 32)
                hit = hit or (dx >= 0 and dx < 2 and dy >= 0 and dy < 2)
            end
        end
        if hit and armed then
            armed = false
            local locked = runtime and io.open(runtime .. "/dotfiles-screen-locked", "r")
            if locked then locked:close()
            else hl.dispatch(hl.dsp.exec_cmd(c.windowSwitcher)) end
        elseif not near then
            armed = true
        end
    end, { timeout = 100, type = "repeat" })
end
-- Wait for the event loop on first login; a reload already has a live monitor.
hl.on("hyprland.start", start_corner)
if hl.get_active_monitor() then start_corner() end
