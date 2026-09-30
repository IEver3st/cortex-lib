-- Run from cortex-lib: lua tests/interaction_visibility_refresh_spec.lua
-- Uses the real registry and renderer together. No GTA/CEF runtime is involved.
local exported, handlers, callbacks, threads = {}, {}, {}, {}
local onScreen, presentationWrites = true, 0
local playerPosition = { x = 0, y = 0, z = 0 }
lib = { isInternalResource = function() return true end, cache = { ped = 1 } }
function exports(name, callback) exported[name] = callback end
function GetInvokingResource() return 'gsd-gt' end
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
function Wait() coroutine.yield() end
function SendNUIMessage() end
function GetSafeZoneSize() return 1.0 end
function GetActiveScreenResolution() return 1920, 1080 end
function PlayerPedId() return 1 end
function DoesEntityExist(entity) return entity == 1 or entity == 2 end
function GetEntityCoords(entity)
    return entity == 1 and playerPosition or { x = 1, y = 0, z = 0 }
end
function GetEntityModel() return 101 end
function World3dToScreen2d() return onScreen, 0.5, 0.5 end
dofile('imports/interaction/client.lua')
local setPresentation = lib._setInteractionPresentationState
lib._setInteractionPresentationState = function(...)
    presentationWrites = presentationWrites + 1
    return setPresentation(...)
end
dofile('client/interaction_renderer.lua')
assert(#threads == 1, 'empty world registry starts no projection worker')
local function setLabel(label)
    assert(exported.setInteractions({ {
        id = 'lock', label = label, key = 'K', holdDuration = 750,
        anchor = { type = 'entity', entity = 2, model = 101, maxDistance = 3 },
    } }))
end
local function frame()
    local ok, err = coroutine.resume(threads[2])
    assert(ok, err)
end
setLabel('RELEASE GATOR')
callbacks.interactionReady({}, function(data) assert(data.ok) end)
frame()
assert(exported.isInteractionVisible('lock'), 'Initial stationary prompt must be actionable')
setLabel('SECURE GATOR')
assert(not exported.isInteractionVisible('lock'), 'Changed definition awaits renderer validation')
frame()
assert(exported.isInteractionVisible('lock'), 'Label-only replacement must regain visibility without any entity, camera, or player movement')
assert(exported.startInteractionHold('lock'), 'Consumer can begin the next hold at the same position')
local before = presentationWrites
for _ = 1, 10 do frame() end
assert(presentationWrites == before, 'Stable hold/frame updates must not repeatedly republish presentation state')
assert(exported.cancelInteractionHold('lock'))
frame()
assert(exported.isInteractionVisible('lock'), 'Canceling hold must preserve stationary prompt visibility')
setLabel('RELEASE GATOR'); frame()
assert(exported.isInteractionVisible('lock'), 'Reverse label transition also works at the same position')

onScreen = false
setLabel('SECURE GATOR'); frame()
assert(not exported.isInteractionVisible('lock'), 'An off-screen replacement must stay unavailable')
onScreen = true; frame()
assert(exported.isInteractionVisible('lock'), 'Re-entering view restores the prompt')
playerPosition = { x = 10, y = 0, z = 0 }
setLabel('RELEASE GATOR'); frame()
assert(not exported.isInteractionVisible('lock'), 'An out-of-range replacement must stay unavailable')
assert(exported.clearInteractions())
frame()
assert(coroutine.status(threads[2]) == 'dead', 'projection worker exits after last anchor is removed')
setLabel('RELEASE GATOR')
assert(#threads == 3, 'new anchor starts a replacement worker without an idle polling delay')
setLabel('SECURE GATOR')
assert(#threads == 3, 'rapid updates do not create duplicate workers')
playerPosition = { x = 0, y = 0, z = 0 }
assert(coroutine.resume(threads[3]))
assert(exported.isInteractionVisible('lock'), 'replacement worker restores presentation')
print('PASS: real registry/renderer stationary label transitions, hold availability, visibility gates, and bounded writes')
