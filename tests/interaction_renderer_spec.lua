local callbacks = {}
local handlers = {}
local messages = {}
local threads = {}
local boneLookups = 0
local resolvedBoneIndex = 2
local entityModel = 1001
local projectedX = 0.55
local walletModel = 2001
local presentationStates = {}
local presentationTransitions = {}
local playerPed = 1
local playerPedExists = true
local panelMarker = '?'
local playerCoords = { x = 0.0, y = 0.0, z = 0.0 }

lib = {
    cache = { ped = 1 },
    getInteractions = function()
        return {
            {
                id = 'social-greet',
                owner = 'cortex-subtleadditions',
                label = 'GREET',
                key = 'G',
                active = true,
                holdDuration = 1200,
                holdActive = true,
                holdRevision = 7,
                panel = {
                    id = 'social-target',
                    label = 'STRANGER',
                    variant = 'target',
                    marker = panelMarker,
                },
            },
            {
                id = 'social-taunt',
                owner = 'cortex-subtleadditions',
                label = 'TAUNT',
                key = 'H',
                active = true,
                panel = {
                    id = 'social-target',
                    label = 'STRANGER',
                    variant = 'target',
                },
            },
            {
                id = 'vehicle-door',
                owner = 'cortex-hud',
                label = 'OPEN',
                key = 'E',
                active = true,
                holdDuration = 1200,
                holdActive = true,
                holdRevision = 3,
                anchor = {
                    type = 'entity-bone',
                    entity = 501,
                    bone = 'bonnet',
                    offset = { x = 0.2, y = 0.7, z = 0.1 },
                    maxDistance = 5.0,
                },
            },
            {
                id = 'wallet',
                owner = 'cortex-subtleadditions',
                label = 'PICK UP WALLET',
                key = 'F',
                active = true,
                holdDuration = 350,
                holdActive = false,
                holdRevision = 0,
                anchor = {
                    type = 'entity',
                    entity = 777,
                    model = 2001,
                    offset = { x = 0.0, y = 0.0, z = 0.15 },
                    maxDistance = 5.0,
                },
            },
        }
    end,
    _setInteractionPresentationState = function(owner, id, visible, distance)
        presentationStates[owner .. ':' .. id] = { visible = visible, distance = distance }
        presentationTransitions[#presentationTransitions + 1] = {
            key = owner .. ':' .. id,
            visible = visible,
            distance = distance,
        }
    end,
}

function RegisterNUICallback(name, callback)
    callbacks[name] = callback
end

function SendNUIMessage(message)
    messages[#messages + 1] = message
end

function AddEventHandler(name, callback)
    handlers[name] = callback
end
function CreateThread(callback)
    threads[#threads + 1] = callback
end
function GetSafeZoneSize()
    return 1.0
end
function GetActiveScreenResolution()
    return 1920, 1080
end
function PlayerPedId()
    return playerPed
end
function DoesEntityExist(entity)
    return (entity == 1 and playerPedExists) or entity == 501 or entity == 777
end
function GetEntityCoords(entity)
    assert(entity == 1 or entity == 501 or entity == 777)
    if entity == 777 then return { x = 0.8, y = 0.0, z = 0.1 } end
    if entity == 1 then return playerCoords end
    return { x = 0.0, y = 0.0, z = 0.0 }
end
function GetEntityBoneIndexByName(entity, bone)
    assert(entity == 501 and bone == 'bonnet')
    boneLookups = boneLookups + 1
    return resolvedBoneIndex
end
function GetEntityModel(entity)
    assert(entity == 501 or entity == 777)
    return entity == 501 and entityModel or walletModel
end
function GetEntityBonePosition_2(entity, boneIndex)
    assert(entity == 501 and boneIndex == 2)
    return { x = 1.0, y = 2.0, z = 0.0 }
end
function GetOffsetFromEntityInWorldCoords(entity, x, y, z)
    assert(entity == 501 or entity == 777)
    if entity == 777 then return { x = 0.8 + x, y = y, z = 0.1 + z } end
    return { x = y, y = -x, z = z }
end
function GetEntityMatrix()
    error('GetEntityMatrix must not be used by the OAL-safe projection path')
end
function World3dToScreen2d(x, y, z)
    if math.abs(x - 0.8) < 0.0001 then
        assert(math.abs(y) < 0.0001 and math.abs(z - 0.25) < 0.0001)
        return true, 0.65, 0.50
    end
    assert(math.abs(x - 1.7) < 0.0001, ('unexpected local-forward X: %.4f'):format(x))
    assert(math.abs(y - 1.8) < 0.0001, ('unexpected local-side Y: %.4f'):format(y))
    assert(math.abs(z - 0.1) < 0.0001, ('unexpected local-up Z: %.4f'):format(z))
    return true, projectedX, 0.50
end
function GetCurrentResourceName()
    return 'cortex-lib'
end
function Wait()
    error('__frame_complete__')
end

dofile('client/interaction_renderer.lua')

local readyResponse = nil
callbacks.interactionReady({}, function(response)
    readyResponse = response
end)
assert(readyResponse and readyResponse.ok == true, 'interaction renderer did not become ready')
assert(type(threads[2]) == 'function', 'the world projection thread was not created')

local screenFrame = nil
for index = #messages, 1, -1 do
    if messages[index].action == 'interaction:update' then
        screenFrame = messages[index].data
        break
    end
end
assert(screenFrame and #screenFrame.items == 2, 'target-panel actions did not reach the screen renderer')
assert(screenFrame.items[1].panel.label == 'STRANGER')
assert(screenFrame.items[1].panel.variant == 'target')
assert(screenFrame.items[1].holdDuration == nil, 'screen prompts must never forward hold timing')
assert(screenFrame.items[1].holdActive == false)
assert(screenFrame.items[1].holdRevision == 0)
assert(presentationStates['cortex-subtleadditions:social-greet'].visible == true)
screenFrame.items[1].panel.label = 'MUTATED'

handlers['cortex-lib:interaction:changed']()
local refreshedScreenFrame = messages[#messages]
assert(refreshedScreenFrame.action == 'interaction:update')
assert(refreshedScreenFrame.data.items[1].panel.label == 'STRANGER', 'renderer reused mutable panel payloads')
panelMarker = 'A'
handlers['cortex-lib:interaction:changed']()
assert(messages[#messages].action == 'interaction:update'
    and messages[#messages].data.items[1].panel.marker == 'A', 'badge-only changes must reach NUI')

local ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))

local frame = nil
for index = #messages, 1, -1 do
    local message = messages[index]
    if message.action == 'interaction:world'
        and message.data
        and #message.data.items > 0
    then
        frame = message.data
        break
    end
end

assert(frame, 'the entity-local anchor did not produce a world frame')
assert(frame.items[1].x == 0.55 and frame.items[1].y == 0.50)
assert(frame.items[1].key == 'E' and frame.items[1].label == 'OPEN')
assert(frame.items[1].holdDuration == 1200)
assert(frame.items[1].holdActive == true)
assert(frame.items[1].holdRevision == 3)
assert(frame.items[2].id == 'wallet' and frame.items[2].x == 0.65)
assert(frame.items[2].label == 'PICK UP WALLET' and frame.items[2].holdDuration == 350)
assert(presentationStates['cortex-hud:vehicle-door'].visible == true)
assert(presentationStates['cortex-subtleadditions:wallet'].visible == true)
assert(boneLookups == 1, 'the entity bone should be resolved once for a stable entity model')

local function countWorldMessages()
    local count = 0
    for index = 1, #messages do
        if messages[index].action == 'interaction:world' then
            count = count + 1
        end
    end
    return count
end

local worldMessages = countWorldMessages()

playerPedExists = false
lib.cache.ped = 0
playerPed = 0
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(countWorldMessages() == worldMessages + 1, 'an invalid player ped must hide the visible world frame')
assert(messages[#messages].action == 'interaction:world' and #messages[#messages].data.items == 0)
assert(presentationStates['cortex-hud:vehicle-door'].visible == false)
assert(presentationStates['cortex-subtleadditions:wallet'].visible == false)

local transitionsAfterInvalidPed = #presentationTransitions
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(countWorldMessages() == worldMessages + 1, 'a repeated invalid player frame must not resend the NUI hide')
assert(#presentationTransitions == transitionsAfterInvalidPed, 'a repeated invalid player frame must not republish false state')

playerPed = 1
playerPedExists = true
lib.cache.ped = 1
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(presentationStates['cortex-hud:vehicle-door'].visible == true)
assert(presentationStates['cortex-subtleadditions:wallet'].visible == true)
worldMessages = countWorldMessages()

playerCoords = nil
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(countWorldMessages() == worldMessages + 1, 'invalid player coordinates must hide the visible world frame')
assert(messages[#messages].action == 'interaction:world' and #messages[#messages].data.items == 0)
assert(presentationStates['cortex-hud:vehicle-door'].visible == false)
assert(presentationStates['cortex-subtleadditions:wallet'].visible == false)

playerCoords = { x = 0.0, y = 0.0, z = 0.0 }
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(presentationStates['cortex-hud:vehicle-door'].visible == true)
assert(presentationStates['cortex-subtleadditions:wallet'].visible == true)
worldMessages = countWorldMessages()

ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(countWorldMessages() == worldMessages, 'an unchanged projected frame should not be resent to NUI')
assert(boneLookups == 1, 'a stable entity model should reuse its cached bone index')

projectedX = 0.56
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(countWorldMessages() == worldMessages + 1, 'a moved projected frame must be sent to NUI')

assert(type(handlers['cortex-lib:interaction:changed']) == 'function')
handlers['cortex-lib:interaction:changed']()
assert(
    presentationStates['cortex-subtleadditions:wallet'].visible == true,
    'hold-state publishing must not briefly invalidate a renderer-validated world prompt'
)
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(boneLookups == 1, 'presentation updates should preserve the bone cache for the same entity and bone')

entityModel = 1002
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(boneLookups == 2, 'entity model changes must invalidate and rebuild the bone cache')

resolvedBoneIndex = -1
entityModel = 1003
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(boneLookups == 3, 'a missing bone must be revalidated after a model change')

resolvedBoneIndex = 2
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(boneLookups == 4, 'a transient missing bone must be retried without another model change')

walletModel = 2002
ok, err = pcall(threads[2])
assert(not ok and tostring(err):find('__frame_complete__', 1, true), tostring(err))
assert(presentationStates['cortex-subtleadditions:wallet'].visible == false, 'entity model reuse must hide the prompt')

print('interaction renderer projection tests passed')
