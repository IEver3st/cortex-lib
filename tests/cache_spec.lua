local threads = {}
local playerId = 7
local ped = 11
local vehicle = 22
local currentSeat = 1
local serverIdCalls = 0
local seatCalls = 0
local vehicleCalls = 0

function IsDuplicityVersion() return false end
function PlayerId() return playerId end
function PlayerPedId() return ped end
function GetPlayerServerId(id)
    serverIdCalls = serverIdCalls + 1
    return id + 100
end
function GetVehiclePedIsIn(entity)
    vehicleCalls = vehicleCalls + 1
    assert(entity == ped)
    return vehicle
end
function GetVehicleMaxNumberOfPassengers(entity)
    assert(entity == vehicle)
    return 3
end
function GetPedInVehicleSeat(entity, seat)
    assert(entity == vehicle)
    seatCalls = seatCalls + 1
    return seat == currentSeat and ped or 0
end
function CreateThread(callback)
    threads[#threads + 1] = callback
end
function Wait()
    error('__cache_tick_complete__')
end
function LoadResourceFile() return nil end
function GetCurrentResourceName() return 'cortex-lib' end
function AddEventHandler() end
function exports() end

dofile('resource/init.lua')

assert(serverIdCalls == 1, 'server id should be initialized once')
assert(cache.playerId == 7 and cache.serverId == 107)
assert(type(threads[1]) == 'function', 'cache updater thread was not created')

local function runTick()
    local ok, err = pcall(threads[1])
    assert(not ok and tostring(err):find('__cache_tick_complete__', 1, true), tostring(err))
end

runTick()
assert(cache.ped == ped and cache.vehicle == vehicle and cache.seat == 1)
assert(seatCalls == 3, 'initial seat resolution should inspect only valid vehicle seats')

local callsBeforeStableTick = seatCalls
runTick()
assert(seatCalls - callsBeforeStableTick == 1, 'a stable seat should require one occupant check')
assert(serverIdCalls == 1, 'stable player id should not repeat server-id lookup')

currentSeat = 2
local callsBeforeSeatMove = seatCalls
runTick()
assert(cache.seat == 2)
assert(seatCalls - callsBeforeSeatMove == 5, 'seat changes should validate once then perform one bounded scan')

playerId = 8
runTick()
assert(cache.playerId == 8 and cache.serverId == 108)
assert(serverIdCalls == 2, 'server id should refresh when the local player id changes')

vehicle = 0
runTick()
assert(cache.vehicle == 0 and cache.seat == -1)

local vehicleCallsBeforeTransition = vehicleCalls
ped = 0
runTick()
assert(vehicleCalls == vehicleCallsBeforeTransition, 'ped transitions should skip vehicle natives')
assert(cache.ped == 0 and cache.vehicle == 0 and cache.seat == -1,
    'ped transitions should clear stale public cache values')

print('client cache tests passed')
