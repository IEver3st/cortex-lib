local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

local exported = {}
local activePlayerReads = 0
local poolReads = 0
local activePlayers = { 1, 2 }
local pools = {
    CVehicle = { 20 },
    CPed = { 10, 30 },
    CObject = { 40 },
}
local entityCoords = {
    [10] = { x = 0, y = 0, z = 0 },
    [20] = { x = 1, y = 0, z = 0 },
    [30] = { x = 2, y = 0, z = 0 },
    [40] = { x = 3, y = 0, z = 0 },
}

lib = {}
exports = function(name, handler) exported[name] = handler end
GetActivePlayers = function()
    activePlayerReads = activePlayerReads + 1
    return activePlayers
end
GetGamePool = function(name)
    poolReads = poolReads + 1
    return pools[name]
end
PlayerId = function() return 1 end
PlayerPedId = function() return 10 end
GetPlayerPed = function(playerId) return playerId == 1 and 10 or 30 end
GetVehiclePedIsIn = function() return 0 end
DoesEntityExist = function(entity) return entityCoords[entity] ~= nil end
GetEntityCoords = function(entity) return entityCoords[entity] end
IsPedAPlayer = function() return false end

local getters = dofile('imports/getters/client.lua')
local invalid = { x = 0 / 0, y = 0, z = 0 }
local first, second, third = getters.getClosestPlayer(invalid, 10)
assertEqual(first, nil, 'invalid closest-player coords should preserve the nil first return')
assertEqual(second, nil, 'invalid closest-player coords should preserve the nil second return')
assertEqual(third, nil, 'invalid closest-player coords should preserve the nil third return')
assertEqual(activePlayerReads, 0, 'invalid public coords must be rejected before player natives')

first, second = getters.getClosestVehicle({ x = 0, y = 0, z = 0 }, math.huge)
assertEqual(first, nil, 'invalid max distance should preserve closest-vehicle shape')
assertEqual(second, nil, 'invalid max distance should preserve closest-vehicle coords shape')
assertEqual(poolReads, 0, 'invalid public distance must be rejected before pool natives')

local nearby = getters.getNearbyObjects({ x = 0, y = 0, z = 0 }, -1)
assertEqual(type(nearby), 'table', 'invalid nearby-object queries should return an array')
assertEqual(#nearby, 0, 'invalid nearby-object queries should return an empty array')
assertEqual(poolReads, 0, 'negative distance must be rejected before pool natives')

first, second, third = getters.getClosestPlayer({ x = 0, y = 0, z = 0 }, 10, 'include')
assertEqual(first, nil, 'malformed includePlayer should preserve the nil result shape')
assertEqual(second, nil, 'malformed includePlayer should preserve the nil ped shape')
assertEqual(third, nil, 'malformed includePlayer should preserve the nil coords shape')
assertEqual(activePlayerReads, 0, 'malformed includePlayer must be rejected before player natives')

nearby = getters.getNearbyVehicles({ x = 0, y = 0, z = 0 }, 10, 1)
assertEqual(#nearby, 0, 'malformed includePlayerVehicle should return an empty array')
assertEqual(poolReads, 0, 'malformed includePlayerVehicle must be rejected before pool natives')

first, second = getters.getClosestObject({ x = 0, y = 0, z = 0 }, 100001)
assertEqual(first, nil, 'excessive max distance should preserve nil entity shape')
assertEqual(second, nil, 'excessive max distance should preserve nil coords shape')
assertEqual(poolReads, 0, 'excessive max distance must be rejected before pool natives')

activePlayers = { [1] = 1, [3] = 2 }
nearby = getters.getNearbyPlayers({ x = 0, y = 0, z = 0 }, 10, true)
assertEqual(#nearby, 0, 'sparse native player arrays should be rejected safely')

pools.CVehicle = { [2] = 20 }
first, second = getters.getClosestVehicle({ x = 0, y = 0, z = 0 }, 10, true)
assertEqual(first, nil, 'sparse vehicle pools should preserve nil result shape')
assertEqual(second, nil, 'sparse vehicle pools should preserve nil coords shape')

activePlayers = { 1, 2 }
pools.CVehicle = { 20 }
first, second, third = getters.getClosestPlayer({ x = 0, y = 0, z = 0 }, 10, false)
assertEqual(first, 2, 'ordinary player queries should retain their player id result')
assertEqual(second, 30, 'ordinary player queries should retain their ped result')
assertEqual(third, entityCoords[30], 'ordinary player queries should retain coords identity')

nearby = getters.getNearbyVehicles({ x = 0, y = 0, z = 0 }, 10, true)
assertEqual(#nearby, 1, 'ordinary nearby-vehicle queries should still return dense results')
assertEqual(nearby[1].vehicle, 20, 'ordinary nearby-vehicle result fields should be preserved')

local threads = {}
local disabledControls = {}
local waitValues = {}
local disableAllCalls = 0

CreateThread = function(handler) threads[#threads + 1] = handler end
Wait = function(delay)
    waitValues[#waitValues + 1] = delay
    error('__disable_tick_complete__')
end
DisableControlAction = function(_, control)
    disabledControls[#disabledControls + 1] = control
end
DisablePlayerFiring = function() end
DisableAllControlActions = function() disableAllCalls = disableAllCalls + 1 end

local disableControls = dofile('imports/disablecontrols/client.lua')
local empty = disableControls({})
assertEqual(#threads, 0, 'an empty control lock must not retain an idle Wait(0) thread')

local ok = pcall(function() disableControls('movement') end)
assertEqual(ok, false, 'disableControls should reject non-table options')
ok = pcall(function() disableControls({ combat = 'yes' }) end)
assertEqual(ok, false, 'disableControls should reject non-boolean options')

empty:Add(-1):Add(1.5):Add(0 / 0):Add(math.huge):Add(361):Add('INPUT_UNKNOWN')
assertEqual(#threads, 0, 'invalid controls must not start a frame thread')

empty:Add('INPUT_ATTACK')
assertEqual(#threads, 1, 'adding the first valid control should start the frame thread')
local okTick, tickError = pcall(threads[1])
assert(not okTick and tostring(tickError):find('__disable_tick_complete__', 1, true), tostring(tickError))
assertEqual(disabledControls[1], 24, 'known named controls should resolve to valid integer ids')
assertEqual(waitValues[#waitValues], 0, 'active control suppression should remain frame-bound')

empty:Destroy()
local all = disableControls({ disableAll = true })
assertEqual(#threads, 2, 'a configured control lock should start immediately')
okTick, tickError = pcall(threads[2])
assert(not okTick and tostring(tickError):find('__disable_tick_complete__', 1, true), tostring(tickError))
assertEqual(disableAllCalls, 1, 'disableAll should preserve its native behavior')
all:Destroy()

print('utility getters and disable-controls spec: PASS')
