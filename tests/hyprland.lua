-- Execute the actual modules with a recorder; validate expansion and key ownership.
package.path = './home/desktop/hypr/?.lua;' .. package.path
local bindings, count, input, devices, notices = {}, 0, nil, {}, {}
local tick, startup, cursor, monitors, executions = nil, nil, { x = 0, y = 0 }, {{x=0,y=0,dpms_status=true}}, {}
local locked, realOpen, realGetenv = false, io.open, os.getenv
local activeWindow, activeWorkspace, moves, specialToggles = nil, {id=1}, {}, {}
local windows, fullscreenStates = {}, {}
os.getenv = function(name) return name == 'XDG_RUNTIME_DIR' and '/dotfiles-test' or realGetenv(name) end
io.open = function(path, mode)
    if path == '/dotfiles-test/dotfiles-screen-locked' then
        return locked and {close=function() end} or nil
    end
    return realOpen(path, mode)
end
local commands = {}
for _, name in ipairs({'launcher','windowSwitcher','snapAssist','cheatsheet','keyboard','clipboard','clipboardPrivacy','clipboardClear','terminal','fileManager','lock','dms','logout','restartShell'}) do
    commands[name] = name
end
package.preload.commands = function() return commands end
for _, name in ipairs({'outputs','layout','colors','cursor','windowrules'}) do
    package.preload['dms.' .. name] = function() return true end
end
local function dispatcher(name)
    return function(arg) return { dispatcher = name, argument = arg } end
end
hl = {
    on = function(name, callback) assert(name == 'hyprland.start'); startup = callback end,
    get_active_monitor = function() return monitors[1] end,
    get_active_window = function() return activeWindow end,
    get_windows = function() return windows end,
    get_active_workspace = function() return activeWorkspace end,
    timer = function(callback, options)
        assert(not tick and options.timeout == 100 and options.type == 'repeat')
        tick = callback
    end,
    get_cursor_pos = function() return cursor end,
    get_monitors = function() return monitors end,
    dispatch = function(action)
        if action.dispatcher == 'move' then
            moves[#moves+1] = action.argument
            if action.argument.x then activeWindow.at = {x=action.argument.x, y=action.argument.y} end
            return
        end
        if action.dispatcher == 'float' then activeWindow.floating = action.argument.action == 'on'; return end
        if action.dispatcher == 'resize' then activeWindow.size = {x=action.argument.x, y=action.argument.y}; return end
        if action.dispatcher == 'toggle_special' then specialToggles[#specialToggles+1] = action.argument; return end
        if action.dispatcher == 'fullscreen_state' then
            fullscreenStates[#fullscreenStates+1] = action.argument
            activeWindow.fullscreen = action.argument.internal
            activeWindow.fullscreen_client = action.argument.client
            return
        end
        assert(action.dispatcher == 'exec')
        executions[#executions+1] = action.argument
    end,
    config = function(options) input = options.input or input end, monitor = function(_) end,
    device = function(options) devices[options.name] = options end,
    notification = { create = function(options) notices[#notices+1] = options.text end },
    animation = function(_) end, window_rule = function(_) end,
    layer_rule = function(_) end,
    dsp = { exec_cmd = dispatcher('exec'), focus = dispatcher('focus'), window = {},
        workspace = { toggle_special = dispatcher('toggle_special') } },
    bind = function(chord, action, options)
        assert(not bindings[chord], 'Duplicate binding: ' .. chord)
        assert(options and options.description and #options.description > 0, 'Missing description: ' .. chord)
        bindings[chord] = { action = action, options = options }
        count = count + 1
    end,
}
for _, name in ipairs({'close','fullscreen','fullscreen_state','float','move','drag','resize'}) do
    hl.dsp.window[name] = dispatcher(name)
end
require('hyprland')
startup() -- timer is not duplicated if startup follows an already-live monitor
assert(count == 81, 'Expected 81 bindings, got ' .. count)
local minimize = bindings['SUPER + code:58'].action
minimize(); assert(#moves == 0) -- empty desktop
activeWindow = {address='0x123', workspace={name='1'}}
minimize(); assert(moves[1].workspace == 'special:minimized-123' and moves[1].follow == false)
assert(moves[1].window == 'address:0x123')
-- A legacy/shared view must keep its other windows visible.
activeWindow.workspace.name = 'special:minimized'
monitors[1].active_special_workspace = {name='special:minimized'}
minimize(); assert(moves[2].workspace == 'special:minimized-123' and #specialToggles == 0)
-- Calling back a single minimized window and minimizing again closes only it.
activeWindow.workspace.name = 'special:minimized-123'
monitors[1].active_special_workspace = {name='special:minimized-123'}
minimize(); assert(#moves == 2 and specialToggles[1] == 'minimized-123')
activeWindow = {address='0x456', workspace={name='1'}}
monitors[1].active_special_workspace = {name='special:other'}
minimize(); assert(moves[3].workspace == 'special:minimized-456' and #specialToggles == 1)
monitors[1].active_special_workspace = nil
windows = {
    {address='0x123', workspace={name='special:minimized-123'}},
    {address='0x456', workspace={name='special:minimized-456'}},
    {address='0x789', workspace={name='1'}},
    {address='0xabc', workspace={name='special:other'}},
    {address='0xdef', workspace={name='special:minimized'}},
}
local showMinimized = bindings['SUPER + CTRL + code:58'].action
showMinimized()
assert(#moves == 5 and moves[4].window == 'address:0x123' and moves[5].window == 'address:0x456')
assert(moves[4].workspace == 'special:minimized' and not moves[4].follow)
assert(specialToggles[2] == 'minimized')
monitors[1].active_special_workspace = {name='special:minimized'}
showMinimized(); assert(#moves == 5 and specialToggles[3] == 'minimized')
-- A newly opened window can join an individual revealed workspace. Keep it.
activeWindow = {address='0x123', workspace={name='special:minimized-123'}}
windows = {activeWindow, {address='0x456', workspace={name='special:minimized-123'}},
    {address='0x789', workspace={name='special:minimized-123-1'}}}
monitors[1].active_special_workspace = {name='special:minimized-123'}
minimize()
assert(#moves == 6 and moves[6].workspace == 'special:minimized-123-2')
assert(moves[6].window == 'address:0x123' and #specialToggles == 3)
monitors[1].active_special_workspace = nil
local touchpad = 'syna8022:00-06cb:ce67-touchpad'
assert(input.touchpad.disable_while_typing)
assert(devices[touchpad].enabled == false)
local toggle = bindings['SUPER + F3']
assert(toggle.options.locked and toggle.options.release)
toggle.action(); assert(devices[touchpad].enabled == true and notices[#notices] == 'Touchpad: ON')
toggle.action(); assert(devices[touchpad].enabled == false and notices[#notices] == 'Touchpad: OFF')
local trackpoint = devices['tpps/2-elan-trackpoint']
assert(trackpoint.scroll_method == 'on_button_down' and trackpoint.scroll_button == 274)
assert(trackpoint.accel_profile == 'adaptive' and trackpoint.sensitivity < 0)
assert(not trackpoint.scroll_button_lock and not trackpoint.middle_button_emulation)
assert(not bindings['mouse:274']) -- libinput distinguishes a click from button scrolling
assert(bindings['SUPER + Tab'].action.argument == 'windowSwitcher')
assert(bindings['SUPER + code:55'].action.argument == 'clipboard')
assert(bindings['SUPER + space'].action.argument == 'launcher')
assert(bindings['SUPER + F2'].options.release)
-- Electron can leave the compositor/client flags different, or combine
-- maximized and fullscreen bits. Every restore must clear both states.
for _, chord in ipairs({'SUPER + code:41', 'SUPER + CTRL + code:41', 'SUPER + SHIFT + code:41'}) do
    local toggle = bindings[chord].action
    local mode = chord == 'SUPER + SHIFT + code:41' and 2 or 1
    activeWindow = nil
    local countBefore = #fullscreenStates
    toggle(); assert(#fullscreenStates == countBefore) -- empty desktop
    for internal = 0, 3 do
        for client = 0, 3 do
            activeWindow = { address='0x123', pid=12, monitor={id=0}, workspace={name='1'},
                at={x=100,y=100}, size={x=800,y=500}, floating=false,
                fullscreen=internal, fullscreen_client=client }
            windows = {activeWindow, {address='0x456', workspace={name='1'}, floating=false}}
            local current = internal | client
            local restore = mode == 1 and current ~= 0 or (current & mode) ~= 0
            local expected = restore and 0 or mode
            toggle()
            local action = fullscreenStates[#fullscreenStates]
            assert(action.window == 'address:0x123' and action.action == 'set')
            assert(action.internal == expected and action.client == expected)
            if expected ~= 0 then
                toggle()
                assert(activeWindow.fullscreen == 0 and activeWindow.fullscreen_client == 0)
            end
        end
    end
end
-- A single tiled window needs a visible normal size, even on a recalled
-- minimized workspace; subsequent toggles must preserve that exact rectangle.
local maximize = bindings['SUPER + code:41'].action
activeWindow = {address='0x100', pid=100, monitor={id=0}, workspace={name='special:minimized-100'},
    at={x=2,y=40}, size={x=1800,y=1000}, floating=false, fullscreen=0, fullscreen_client=0}
windows = {activeWindow}
maximize(); assert(activeWindow.fullscreen == 1 and not activeWindow.floating)
maximize(); assert(activeWindow.fullscreen == 0 and activeWindow.floating)
assert(activeWindow.size.x == 1440 and activeWindow.size.y == 800)
assert(activeWindow.at.x == 182 and activeWindow.at.y == 140)
maximize()
activeWindow.at, activeWindow.size = {x=0,y=0}, {x=1800,y=1100}
maximize()
assert(activeWindow.size.x == 1440 and activeWindow.size.y == 800)
assert(activeWindow.at.x == 182 and activeWindow.at.y == 140)
-- Keep normal tiling when another tiled app remains in the same workspace.
activeWindow = {address='0x200', pid=200, monitor={id=0}, workspace={name='1'},
    at={x=2,y=40}, size={x=800,y=1000}, floating=false, fullscreen=0, fullscreen_client=0}
local neighbour = {address='0x201', workspace={name='1'}, floating=false}
windows = {activeWindow, neighbour}
maximize(); maximize(); assert(not activeWindow.floating)
-- If the neighbour was minimized while maximized, restore the smaller original
-- rectangle instead of expanding the remaining app to fill the whole workspace.
maximize()
activeWindow.size = {x=1600,y=1000}
neighbour.workspace.name = 'special:minimized-201'
maximize()
assert(activeWindow.floating and activeWindow.size.x == 800 and activeWindow.at.x == 2)
-- Config reloads or an already-maximized app may have no saved rectangle.
activeWindow = {address='0x300', pid=300, monitor={id=0}, workspace={name='1'},
    at={x=0,y=40}, size={x=1800,y=1000}, floating=false, fullscreen=1, fullscreen_client=1}
windows = {activeWindow}
maximize(); assert(activeWindow.floating and activeWindow.size.x == 1440)
for _, direction in ipairs({'left','right','up','down'}) do
    assert(bindings['SUPER + SHIFT + ' .. direction].action.argument == 'snapAssist ' .. direction)
end
assert(bindings['SUPER + code:46'].action.argument == 'lock')
for i = 1, 10 do
    local code = tostring(i + 9)
    assert(bindings['SUPER + code:' .. code].action.argument == 'dms ipc call dotfiles-apps activate ' .. i)
    assert(not bindings['SUPER + code:' .. code].options.locked)
    assert(bindings['SUPER + CTRL + code:' .. code].action.argument.workspace == i)
    assert(bindings['SUPER + SHIFT + code:' .. code].action.argument.workspace == i)
end
local function move(x, y, expected)
    cursor = {x=x,y=y}; tick()
    assert(#executions == expected, 'Hot corner unexpectedly fired or failed to fire')
end
move(0,0,0) -- starting in the corner is not an entry
move(100,100,0); move(0,0,1); move(0,0,1)
move(10,10,1); move(0,0,1) -- still inside the rearm zone
move(32,0,1); move(1,1,2)
monitors = {{x=-1920,y=100,dpms_status=true}}
move(-1800,200,2); move(-1920,100,3)
monitors[1].dpms_status = false
move(-1800,200,3); move(-1920,100,3)
monitors[1].dpms_status = true
locked = true
move(-1800,200,3); move(-1920,100,3)
locked = false
move(-1920,100,3) -- unlocking in the corner must not open the switcher
move(-1800,200,3); move(-1920,100,4)
for _, command in ipairs(executions) do assert(command == 'windowSwitcher') end
io.open, os.getenv = realOpen, realGetenv
print('Lua: 81 bindings, maximize/fullscreen, snap assist, numbered apps, workspace shortcuts, input and hot corner verified')
