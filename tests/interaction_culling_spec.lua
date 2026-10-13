-- Run from cortex-lib: lua tests/interaction_culling_spec.lua
-- Real registry + renderer: an anchor far outside its range is not resolved
-- again until it could have closed the gap at 100 m/s (capped at 500ms).
local exported, handlers, callbacks, threads, messages = {}, {}, {}, {}, {}
local clock, farChecks = 0, 0
local farCoords = { x = 50.0, y = 0.0, z = 0.0 }

lib = { isInternalResource = function() return true end, cache = { ped = 1 }, getSetting = function() return nil end }
function exports(name, callback) exported[name] = callback end
function GetInvokingResource() return 'owner' end
function GetCurrentResourceName() return 'cortex-lib' end
function AddEventHandler(name, callback)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], callback)
end
function TriggerEvent(name, ...) for _, callback in ipairs(handlers[name] or {}) do callback(...) end end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function CreateThread(callback) threads[#threads + 1] = coroutine.create(callback) end
function Wait(ms) coroutine.yield(ms) end
function SendNUIMessage(message) messages[#messages + 1] = message end
function GetSafeZoneSize() return 1.0 end
function GetActiveScreenResolution() return 1920, 1080 end
function GetGameTimer() return clock end
function PlayerPedId() return 1 end
function PlayerId() return 0 end
function DoesEntityExist(entity)
    if entity == 5 then farChecks = farChecks + 1 end
    return entity == 1 or entity == 5
end
function GetEntityCoords(entity)
    if entity == 5 then return farCoords end
    return { x = 0.0, y = 0.0, z = 0.0 }
end
function GetEntityModel() return 1 end
local screenX = 0.5
function World3dToScreen2d() return true, screenX, 0.5 end
function DisableControlAction() end
function IsDisabledControlJustPressed() return false end
function IsPauseMenuActive() return false end
function IsPlayerFreeAiming() return false end

dofile('imports/interaction/client.lua')
dofile('client/interaction_renderer.lua')
callbacks.interactionReady({}, function(data) assert(data.ok) end)

assert(exported.setInteractions({
    { id = 'near', label = 'NEAR', key = 'E', anchor = { type = 'world', x = 1.0, y = 0.0, z = 0.0, maxDistance = 2.0 } },
    { id = 'far', label = 'FAR', key = 'G', anchor = { type = 'entity', entity = 5, maxDistance = 2.0 } },
}))

local function frame(at)
    clock = at
    local ok, waitMs = coroutine.resume(threads[#threads])
    assert(ok, waitMs)
    return waitMs
end

assert(frame(0) == 0, 'a visible prompt keeps the worker on every frame')
assert(farChecks == 1, 'the far anchor is resolved once')
-- 50m away, marker range 6m: a 44m gap is 440ms at 100 m/s.
for at = 16, 432, 16 do frame(at) end
assert(farChecks == 1, 'a far anchor costs no natives while it cannot be in range')
farCoords = { x = 1.5, y = 0.0, z = 0.0 }
frame(448)
assert(farChecks == 2, 'the skip ends once the gap could have closed')
local items
for index = #messages, 1, -1 do
    if messages[index].action == 'interaction:world' then items = messages[index].data.items; break end
end
local found = false
for _, item in ipairs(items or {}) do if item.id == 'far' then found = true end end
assert(found, 'an anchor that came into range is shown on its next check')
clock = 0
farCoords = { x = 50.0, y = 0.0, z = 0.0 }
frame(500)
local checks = farChecks
frame(100)
assert(farChecks == checks + 1, 'a clock rollback ends the skip')

-- Position-only updates are capped near 60 Hz; the resting position still lands.
local function moves()
    local count = 0
    for _, message in ipairs(messages) do
        if message.action == 'interaction:worldMove' then count = count + 1 end
    end
    return count
end
farCoords = { x = 50.0, y = 0.0, z = 0.0 }
frame(2000)
frame(2009)
local before = moves()
local at = 2009
for step = 1, 20 do
    at = at + 9 -- ~110 FPS
    screenX = 0.5 + step * 0.01
    frame(at)
end
local sent = moves() - before
assert(sent >= 9 and sent <= 11, 'a moving prompt at 110 FPS sends about every other frame: ' .. sent)
local finalX = screenX
frame(at + 9)
frame(at + 18)
local last
for index = #messages, 1, -1 do
    if messages[index].action == 'interaction:worldMove' then last = messages[index]; break end
end
assert(last and last.data.p[1] == finalX, 'the resting position is sent once the interval allows')
local settled = moves()
frame(at + 27)
frame(at + 36)
assert(moves() == settled, 'a still prompt sends nothing')
print('interaction culling: far anchor resolved 1x across 28 frames; expiry, arrival, clock rollback and the ~60 Hz move cap passed')
