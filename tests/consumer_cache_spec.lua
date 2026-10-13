-- Consumer loader (root init.lua): the ped/vehicle/seat worker starts only
-- when a consumer first reads one of those fields.
local threads, ped, vehicle, pedReads = {}, 11, 0, 0

function IsDuplicityVersion() return false end
function GetResourceState() return 'started' end
function GetCurrentResourceName() return 'consumer' end
function PlayerId() return 7 end
function GetPlayerServerId(id) return id + 100 end
function PlayerPedId() pedReads = pedReads + 1; return ped end
function GetVehiclePedIsIn() return vehicle end
function GetVehicleMaxNumberOfPassengers() return 1 end
function GetPedInVehicleSeat(_, seat) return seat == -1 and ped or 0 end
function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function Wait(delay) coroutine.yield(delay) end
function LoadResourceFile() return nil end
function AddEventHandler() end
function RegisterNetEvent() end
function exports() end

dofile('init.lua')

assert(#threads == 0 and pedReads == 0, 'loading the library must not start the cache worker')
assert(cache.playerId == 7 and cache.serverId == 107)
assert(#threads == 0, 'player ids are static and must not start the worker')

assert(cache.ped == 11 and cache.vehicle == 0 and cache.seat == -1, 'first read must return live values')
assert(#threads == 1 and pedReads == 1, 'first live read starts exactly one worker')
assert(cache.vehicle == 0 and #threads == 1, 'later reads must not start more workers')

vehicle = 22
local ok, delay = coroutine.resume(threads[1])
assert(ok and delay == 100)
ok = coroutine.resume(threads[1])
assert(ok and cache.vehicle == 22 and cache.seat == -1, 'worker must keep refreshing at 100ms')
print('consumer cache: no worker until first ped/vehicle/seat read; live first read and 100ms refresh passed')
