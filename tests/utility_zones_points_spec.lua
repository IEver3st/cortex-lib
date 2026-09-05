local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

local function assertFails(handler, message)
    local ok = pcall(handler)
    if ok then error(message) end
end

local threads = {}
local waits = {}
local nativeReads = 0
local playerCoords = { x = 0.0, y = 0.0, z = 0.0 }
local playerPed = 1

lib = {}
vector3 = function(x, y, z) return { x = x, y = y, z = z } end
PlayerPedId = function()
    nativeReads = nativeReads + 1
    return playerPed
end
GetEntityCoords = function(entity)
    nativeReads = nativeReads + 1
    assertEqual(entity, 1, 'scheduler should read the local player ped')
    return playerCoords
end
DoesEntityExist = function(entity) return entity == 1 end
DrawLine = function() end
DrawMarker = function() end
CreateThread = function(handler) threads[#threads + 1] = handler end
Wait = function(delay)
    waits[#waits + 1] = delay
    error('__utility_tick_complete__')
end

local function runTick(handler)
    local ok, err = pcall(handler)
    assert(not ok and tostring(err):find('__utility_tick_complete__', 1, true), tostring(err))
end

local zones = dofile('imports/zones/client.lua')
assertEqual(#threads, 2, 'zones should install detector and debug schedulers')

runTick(threads[1])
assertEqual(nativeReads, 0, 'idle zone detection must not call player natives')
assertEqual(waits[#waits], 500, 'idle zone detection should use an adaptive wait')
runTick(threads[2])
assertEqual(waits[#waits], 500, 'idle zone debug rendering should not use Wait(0)')

assertFails(function() zones.sphere(nil) end, 'sphere should reject missing data')
assertFails(function()
    zones.sphere({ coords = { x = 0, y = 0 / 0, z = 0 } })
end, 'sphere should reject NaN coords')
assertFails(function()
    zones.sphere({ coords = { x = 0, y = 0, z = 0 }, radius = math.huge })
end, 'sphere should reject infinite radius')
assertFails(function()
    zones.box({ coords = { x = 0, y = 0, z = 0 }, size = { x = 1, y = 0, z = 1 } })
end, 'box should reject non-positive size components')
assertFails(function()
    zones.poly({
        points = {
            [1] = { x = 0, y = 0, z = 0 },
            [3] = { x = 1, y = 0, z = 0 },
            [4] = { x = 0, y = 1, z = 0 },
        }
    })
end, 'poly should reject sparse point arrays')
assertFails(function()
    zones.sphere({ coords = { x = 0, y = 0, z = 0 }, onEnter = true })
end, 'zones should reject non-function callbacks')

local entered = 0
local exited = 0
local inside = 0
local failingZone = zones.sphere({
    id = 999,
    isInside = true,
    radiusSq = 0,
    remove = 'poisoned',
    coords = { x = 0, y = 0, z = 0 },
    onEnter = function() error('zone enter failure') end,
    onExit = function() error('zone exit failure') end,
    inside = function() error('zone inside failure') end,
})
assertEqual(failingZone.id, 1, 'zone metadata must not overwrite the scheduler id')
assertEqual(failingZone.isInside, false, 'zone metadata must not poison internal entry state')
assertEqual(failingZone.radiusSq, 4, 'zone metadata must not overwrite derived geometry')
assertEqual(type(failingZone.remove), 'function', 'zone metadata must not shadow lifecycle removal')
local healthyZone = zones.sphere({
    coords = { x = 0, y = 0, z = 0 },
    onEnter = function() entered = entered + 1 end,
    onExit = function() exited = exited + 1 end,
    inside = function() inside = inside + 1 end,
})

runTick(threads[1])
assertEqual(entered, 1, 'one failing zone onEnter must not terminate the shared detector')
assertEqual(inside, 1, 'one failing zone inside callback must not stop healthy callbacks')
assertEqual(waits[#waits], 250, 'active zone detection should retain its low-frequency cadence')

playerCoords = { x = 20.0, y = 0.0, z = 0.0 }
playerPed = 0
runTick(threads[1])
assertEqual(exited, 0, 'an unavailable player ped must not generate a false zone exit')
playerPed = 1
runTick(threads[1])
assertEqual(exited, 1, 'one failing zone onExit must not terminate the shared detector')

failingZone:remove()
healthyZone:remove()

local pointThreadsStart = #threads
local points = dofile('imports/points/client.lua')
local detector = threads[pointThreadsStart + 1]
assert(detector, 'points should install one low-frequency detector')

local readsBeforeIdlePoint = nativeReads
runTick(detector)
assertEqual(nativeReads, readsBeforeIdlePoint, 'idle point detection must not call player natives')
assertEqual(waits[#waits], 500, 'idle point detection should use an adaptive wait')

assertFails(function() points.new(nil) end, 'points should reject missing data')
assertFails(function()
    points.new({ coords = { x = 0, y = math.huge, z = 0 } })
end, 'points should reject infinite coords')
assertFails(function()
    points.new({ coords = { x = 0, y = 0, z = 0 }, distance = 0 })
end, 'points should reject non-positive distance')
assertFails(function()
    points.new({ coords = { x = 0, y = 0, z = 0 }, distance = 100001 })
end, 'points should reject distances outside the sane world range')
assertFails(function()
    points.new({ coords = { x = 0, y = 0, z = 0 }, nearby = 'bad' })
end, 'points should reject non-function callbacks')

playerCoords = { x = 0.0, y = 0.0, z = 0.0 }
local pointEntered = 0
local pointExited = 0
local nearby = 0
local failingPoint = points.new({
    id = 999,
    _wasNearby = true,
    currentDistance = 0,
    isClosest = true,
    remove = 'poisoned',
    coords = { x = 0, y = 0, z = 0 },
    distance = 2,
    onEnter = function() error('point enter failure') end,
    onExit = function() error('point exit failure') end,
    nearby = function() error('point nearby failure') end,
})
assertEqual(failingPoint.id, 1, 'point metadata must not overwrite the scheduler id')
assertEqual(failingPoint._wasNearby, false, 'point metadata must not poison nearby state')
assertEqual(failingPoint.currentDistance, math.huge, 'point metadata must not poison measured distance')
assertEqual(failingPoint.isClosest, false, 'point metadata must not poison closest state')
assertEqual(type(failingPoint.remove), 'function', 'point metadata must not shadow lifecycle removal')
local healthyPoint = points.new({
    coords = { x = 0, y = 0, z = 0 },
    distance = 2,
    onEnter = function() pointEntered = pointEntered + 1 end,
    onExit = function() pointExited = pointExited + 1 end,
    nearby = function() nearby = nearby + 1 end,
})

runTick(detector)
assertEqual(pointEntered, 1, 'one failing point onEnter must not terminate the shared detector')
assertEqual(waits[#waits], 100, 'active point detection should retain its low-frequency cadence')

local nearbySnapshot = points.getNearbyPoints()
assertEqual(#nearbySnapshot, 2, 'nearby snapshot should include both registered points')
nearbySnapshot[1] = nil
assertEqual(#points.getNearbyPoints(), 2, 'mutating a nearby snapshot must not corrupt scheduler state')

local nearbyThread = threads[#threads]
assert(nearbyThread ~= detector, 'nearby callbacks should start a frame-bound thread only while needed')
runTick(nearbyThread)
assertEqual(nearby, 1, 'one failing nearby callback must not stop healthy nearby callbacks')
assertEqual(waits[#waits], 0, 'active nearby callbacks are the only point path that should use Wait(0)')

playerCoords = { x = 20.0, y = 0.0, z = 0.0 }
playerPed = 0
runTick(detector)
assertEqual(pointExited, 1, 'an unavailable player ped should issue one point exit for stale nearby state')
assertEqual(failingPoint._wasNearby, false, 'invalid ped frames should clear internal nearby state')
assertEqual(failingPoint.isClosest, false, 'invalid ped frames should clear closest state')
assertEqual(failingPoint.currentDistance, math.huge, 'invalid ped frames should reset measured distance')
playerPed = 1
runTick(detector)
assertEqual(pointExited, 1, 'restoring the ped should not duplicate the prior point exit')

failingPoint:remove()
healthyPoint:remove()

print('utility zones and points safety spec: PASS')
