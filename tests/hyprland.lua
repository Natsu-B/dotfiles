-- Execute the actual modules with a recorder; validate expansion and key ownership.
package.path = './home/desktop/hypr/?.lua;' .. package.path
local bindings, count = {}, 0
local commands = {}
for _, name in ipairs({'launcher','cheatsheet','keyboard','clipboard','clipboardPrivacy','clipboardClear','terminal','fileManager','lock','dms','logout','restartShell'}) do
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
    config = function(_) end, monitor = function(_) end,
    animation = function(_) end, window_rule = function(_) end,
    layer_rule = function(_) end,
    dsp = { exec_cmd = dispatcher('exec'), focus = dispatcher('focus'), window = {} },
    bind = function(chord, action, options)
        assert(not bindings[chord], 'Duplicate binding: ' .. chord)
        assert(options and options.description and #options.description > 0, 'Missing description: ' .. chord)
        bindings[chord] = { action = action, options = options }
        count = count + 1
    end,
}
for _, name in ipairs({'close','fullscreen','float','move','drag','resize'}) do
    hl.dsp.window[name] = dispatcher(name)
end
require('hyprland')
assert(count == 60, 'Expected 60 bindings, got ' .. count)
assert(bindings['SUPER + code:55'].action.argument == 'clipboard')
assert(bindings['SUPER + space'].action.argument == 'launcher')
assert(bindings['SUPER + F2'].options.release)
assert(bindings['SUPER + code:46'].action.argument == 'lock')
for i = 1, 10 do
    local code = tostring(i + 9)
    assert(bindings['SUPER + code:' .. code].action.argument.workspace == i)
    assert(bindings['SUPER + SHIFT + code:' .. code].action.argument.workspace == i)
end
print('Lua: 60 unique, described bindings; keyboard, clipboard and lock routing verified')
