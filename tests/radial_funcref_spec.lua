-- Radial items registered from another resource carry Cfx funcrefs (callable
-- tables that throw when indexed). They must validate and fire on click.
local function funcref(fn)
    return setmetatable({}, {
        __index = function() error('Cannot index a funcref') end,
        __call = function(_, ...) return fn(...) end,
    })
end

local callbacks, exported, sent = {}, {}, {}
local env = setmetatable({ lib = {} }, { __index = _G })
env.GetCurrentResourceName = function() return 'cortex-lib' end
env.GetInvokingResource = function() return 'cortex-emotemenu' end
env.RegisterNUICallback = function(name, fn) callbacks[name] = fn end
env.SendNUIMessage = function(message) sent[#sent + 1] = message end
env.exports = function(name, fn) exported[name] = fn end
env.AddEventHandler = function() end
env.CreateThread = function() end
env.Wait = function() end
env.IsPauseMenuActive = function() return false end
env.SetCursorLocation = function() end
env.SetNuiFocus = function() end
env.IsControlJustPressed = function() return false end
env.DisableControlAction = function() end
assert(loadfile('imports/radial/client.lua', 't', env))()

local fired = 0
local ok, err = exported.registerRadial({
    id = 'emote-wheel',
    items = {
        { id = 'wave', label = 'Wave', icon = 'W', onSelect = funcref(function() fired = fired + 1 end) },
        { id = 'plain', label = 'Plain', onSelect = function() fired = fired + 10 end },
    },
})
assert(ok ~= false, 'funcref item rejected: ' .. tostring(err))
assert(exported.showRadial('emote-wheel'), 'radial did not open')

local show = sent[#sent]
local session = show.data.session
local reply
callbacks.radialClick({ index = 0, itemId = 'wave', menuId = 'emote-wheel', session = session }, function(r) reply = r end)
assert(reply and reply.ok, 'click failed: ' .. tostring(reply and reply.error))
assert(fired == 1, 'funcref onSelect did not fire')

assert(exported.showRadial('emote-wheel'), 'radial did not reopen')
session = sent[#sent].data.session
callbacks.radialClick({ index = 1, itemId = 'plain', menuId = 'emote-wheel', session = session }, function(r) reply = r end)
assert(fired == 11, 'plain function onSelect did not fire')

local bad = exported.registerRadial({ id = 'bad', items = { { id = 'x', label = 'X', onSelect = {} } } })
assert(bad == false, 'a non-callable table was accepted')

print('radial funcref: ok')
