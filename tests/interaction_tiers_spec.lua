-- Run from cortex-lib: lua tests/interaction_tiers_spec.lua
-- Real registry + renderer: marker tier, merged lists, list preference
-- arbitration, wheel selection, hold freeze and preference cleanup.
-- No GTA/CEF runtime is involved; natives are deterministic stubs.
local exported, handlers, callbacks, threads, messages = {}, {}, {}, {}, {}
local invoking = 'fridge'
local player = { x = 0.0, y = 0.0, z = 0.0 }
local settings = {}
local pressed, disabled = {}, {}
local paused, aiming = false, false

lib = {
    isInternalResource = function() return true end,
    cache = { ped = 1 },
    getSetting = function(key) return settings[key] end,
}
function exports(name, callback) exported[name] = callback end
function GetInvokingResource() return invoking end
function GetCurrentResourceName() return 'cortex-lib' end
function AddEventHandler(name, callback)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], callback)
end
function TriggerEvent(name, ...)
    for _, callback in ipairs(handlers[name] or {}) do callback(...) end
end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function CreateThread(callback) threads[#threads + 1] = coroutine.create(callback) end
function Wait(ms) coroutine.yield(ms) end
function SendNUIMessage(message) messages[#messages + 1] = message end
function GetSafeZoneSize() return 1.0 end
function GetActiveScreenResolution() return 1920, 1080 end
function PlayerPedId() return 1 end
function PlayerId() return 0 end
function DoesEntityExist(entity) return entity == 1 end
function GetEntityCoords() return player end
function GetEntityModel() return 1 end
-- World y maps finely onto the screen (0.01 of the width per unit) so rows a
-- metre apart project close together; z separates anchors strongly.
function World3dToScreen2d(_, y, z) return true, 0.5 + y * 0.01 + z * 0.2, 0.5 end
function DisableControlAction(_, control) disabled[control] = true end
function IsDisabledControlJustPressed(_, control) return pressed[control] == true end
function IsPauseMenuActive() return paused end
function IsPlayerFreeAiming() return aiming end

dofile('imports/interaction/client.lua')
dofile('client/interaction_renderer.lua')
callbacks.interactionReady({}, function(data) assert(data.ok) end)

local function as(owner, fn, ...)
    local previous = invoking
    invoking = owner
    local a, b = fn(...)
    invoking = previous
    return a, b
end

local function worker() return threads[#threads] end
local function frame()
    disabled = {}
    local co = worker()
    assert(coroutine.status(co) ~= 'dead', 'projection worker must be running')
    local ok, waitMs = coroutine.resume(co)
    assert(ok, waitMs)
    pressed = {}
    return waitMs
end
local function lastWorld()
    for index = #messages, 1, -1 do
        if messages[index].action == 'interaction:world' then return messages[index].data.items end
    end
    return {}
end
local function world(id, key, priority, y, more, z)
    local item = {
        id = id, label = id:upper(), key = key, priority = priority,
        anchor = { type = 'world', x = 10.0, y = y or 0.0, z = z or 0.0, maxDistance = 2.0 },
    }
    for field, value in pairs(more or {}) do item[field] = value end
    return item
end
local function find(items, id)
    for index = 1, #items do if items[index].id == id then return items[index] end end
end

-- markerDistance: validated, defaulted, part of the definition identity.
local ok, err = as('fridge', exported.showInteraction,
    { id = 'bad', label = 'BAD', key = 'E', anchor = { type = 'world', x = 1, y = 1, z = 1, markerDistance = 30 } })
assert(ok == false and err:find('anchor.markerDistance', 1, true), 'markerDistance above 25 is rejected')
ok = as('fridge', exported.showInteraction,
    { id = 'bad', label = 'BAD', key = 'E', anchor = { type = 'world', x = 1, y = 1, z = 1, markerDistance = -1 } })
assert(ok == false, 'negative markerDistance is rejected')
assert(as('fridge', exported.showInteraction,
    { id = 'probe', label = 'PROBE', key = 'E', anchor = { type = 'world', x = 1, y = 1, z = 1, maxDistance = 2.0 } }))
assert(as('fridge', exported.getInteractionState, 'probe').anchor.markerDistance == 6.0,
    'default markerDistance = min(25, max(maxDistance + 4, maxDistance * 2.5))')
assert(as('fridge', exported.clearInteractions))

-- The GTA fridge: two same-key rows and one unique-key row at one spot.
local fridge = {
    world('beer', 'E', 10, 0.0),
    world('smoothie', 'E', 5, 0.8, { holdDuration = 800 }),
    world('inspect', 'G', 0, 1.6),
}
assert(as('fridge', exported.setInteractions, fridge))

player = { x = -20.0, y = 0.0, z = 0.0 }
local waitMs = frame()
assert(#lastWorld() == 0, 'nothing is drawn outside the marker range')
assert(waitMs == 250, 'far from every anchor the worker polls slowly')

player = { x = 5.0, y = 0.0, z = 0.0 }
waitMs = frame()
local items = lastWorld()
assert(#items == 1 and items[1].tier == 'marker', 'nearby anchors merge into one marker')
assert(items[1].id == 'beer', 'the merged marker sits at the highest-ranked anchor')
assert(items[1].label == nil and items[1].key == nil, 'markers carry no label or key')
assert(items[1].fade > 0 and items[1].fade < 1, 'markers fade with distance')
assert(waitMs == 33, 'marker-only frames run at the coarse cadence')
assert(not as('fridge', exported.isInteractionVisible, 'beer'), 'markers never make an entry visible')
assert(next(disabled) == nil, 'markers never take the wheel')

settings.promptMarkers = false
TriggerEvent('cortex-lib:settingChanged', 'promptMarkers', false)
frame()
assert(#lastWorld() == 0, 'the promptMarkers preference disables the marker tier')
settings.promptMarkers = nil
TriggerEvent('cortex-lib:settingChanged', 'promptMarkers', true)

player = { x = 9.0, y = 0.0, z = 0.0 }
waitMs = frame()
items = lastWorld()
assert(#items == 3, 'the losing same-key row is still projected as a list row')
assert(items[1].tier == 'prompt' and items[1].group == items[2].group and items[2].group == items[3].group,
    'prompt-tier anchors within 6% of screen height merge into one list')
assert(items[1].x == items[3].x and items[1].y == items[3].y, 'every row carries the list anchor')
assert(items[1].id == 'beer' and items[1].selected and items[1].active)
assert(items[2].id == 'smoothie' and not items[2].selected and not items[2].active)
assert(items[3].id == 'inspect' and not items[3].selected and items[3].active, 'a unique key stays active')
assert(items[1].focused, 'a list with a real choice is focused')
assert(waitMs == 0, 'visible prompts are tracked every frame')
for _, control in ipairs({ 14, 15, 16, 17, 99, 115, 261, 262 }) do
    assert(disabled[control], ('wheel control %d must be blocked while a list is focused'):format(control))
end
assert(as('fridge', exported.isInteractionActive, 'beer') and not as('fridge', exported.isInteractionActive, 'smoothie'))
assert(as('fridge', exported.isInteractionVisible, 'inspect'), 'unique-key rows remain usable')
assert(not as('fridge', exported.isInteractionVisible, 'smoothie'))

-- Scroll down: the selected row wins its key through the preference.
pressed[14] = true
frame()
items = lastWorld()
assert(find(items, 'smoothie').selected and find(items, 'smoothie').active)
assert(not find(items, 'beer').active)
assert(as('fridge', exported.isInteractionActive, 'smoothie'), 'isInteractionActive follows the list selection')
assert(not as('fridge', exported.isInteractionActive, 'beer'))
frame()
assert(as('fridge', exported.isInteractionVisible, 'smoothie'))
assert(not as('fridge', exported.isInteractionVisible, 'beer'))
local prefOwner, prefId = lib._getInteractionPreference()
assert(prefOwner == 'fridge' and prefId == 'smoothie')

-- A running hold freezes the selection.
assert(as('fridge', exported.startInteractionHold, 'smoothie'))
frame()
pressed[14] = true
frame()
assert(find(lastWorld(), 'smoothie').selected, 'the wheel cannot move a running hold to another row')
pressed[15] = true
frame()
assert(find(lastWorld(), 'smoothie').selected)
assert(as('fridge', exported.cancelInteractionHold, 'smoothie'))
frame()

-- Selection clamps and invertScroll flips direction.
pressed[14] = true
frame()
assert(find(lastWorld(), 'inspect').selected)
pressed[14] = true
frame()
assert(find(lastWorld(), 'inspect').selected, 'selection clamps at the last row')
assert(as('fridge', exported.isInteractionActive, 'beer'), 'a unique-key selection returns the E key to its natural owner')
settings.invertScroll = true
TriggerEvent('cortex-lib:settingChanged', 'invertScroll', true)
pressed[14] = true
frame()
assert(find(lastWorld(), 'smoothie').selected, 'invertScroll flips the wheel')
settings.invertScroll = nil
TriggerEvent('cortex-lib:settingChanged', 'invertScroll', false)

-- Free-aim or the pause menu never lose the wheel to a list.
aiming = true
frame()
assert(next(disabled) == nil and not lastWorld()[1].focused, 'free-aiming keeps weapon switching')
aiming = false
frame()

-- Leaving the list clears the preference; a hold on the preferred row is
-- cancelled exactly once by re-arbitration.
assert(as('fridge', exported.startInteractionHold, 'smoothie'))
local revision = as('fridge', exported.getInteractionState, 'smoothie').holdRevision
player = { x = -20.0, y = 0.0, z = 0.0 }
frame()
assert(lib._getInteractionPreference() == nil, 'the preference is cleared when the list disappears')
local state = as('fridge', exported.getInteractionState, 'smoothie')
assert(state.active == false and state.holdActive == false and state.holdRevision == revision + 1,
    'losing the key cancels the presentation hold')
assert(as('fridge', exported.isInteractionActive, 'beer'))

-- Owner stop clears a live preference.
player = { x = 9.0, y = 0.0, z = 0.0 }
frame()
pressed[14] = true
frame()
assert(select(2, lib._getInteractionPreference()) == 'smoothie')
TriggerEvent('onClientResourceStop', 'fridge')
assert(lib._getInteractionPreference() == nil, 'owner stop clears its preference')
frame()

-- Unique keys only: nothing to choose, so the wheel is never taken.
assert(as('bench', exported.setInteractions, { world('repair', 'E', 0, 0.0), world('paint', 'G', 0, 1.0) }))
frame()
items = lastWorld()
assert(#items == 2 and items[1].group == items[2].group, 'unique-key rows still merge')
assert(not items[1].focused and next(disabled) == nil, 'a list without a shared key never hijacks the wheel')
assert(items[1].active and items[2].active)
assert(as('bench', exported.clearInteractions))

-- A row whose key is owned elsewhere is not offered: it degrades to a marker.
assert(as('fridge', exported.setInteractions, { world('beer', 'E', 10, 0.0) }))
assert(as('car', exported.showInteraction, world('door', 'E', 100, 0.0, nil, 1.5)))
frame()
items = lastWorld()
assert(find(items, 'door').tier == 'prompt' and find(items, 'door').active)
assert(find(items, 'beer').tier == 'marker', 'a same-key loser outside the owner list is only a marker')
assert(not as('fridge', exported.isInteractionVisible, 'beer'))

-- A screen prompt owning the key keeps world rows out and rejects preference.
assert(as('hud', exported.showInteraction, { id = 'menu', label = 'MENU', key = 'E', priority = 500 }))
frame()
assert(find(lastWorld(), 'door').tier == 'marker', 'world rows cannot compete with a screen prompt owner')
assert(lib._setInteractionPreference('car', 'door') == false, 'preference never beats a screen prompt')
assert(as('hud', exported.isInteractionActive, 'menu'))
assert(lib._setInteractionPreference('hud', 'menu') == false, 'screen prompts cannot be preferred')

print('PASS: marker tier, merged lists, list preference arbitration, wheel selection, hold freeze and cleanup')
