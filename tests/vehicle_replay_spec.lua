-- Real shared module, deterministic native stubs. No live FiveM claim.
local present, owned, networked, count = true, true, true, 6
local writes, reads, forbidden = {}, {}, 0
function DoesEntityExist(entity) return present and entity == 2 end
function GetVehicleNumberOfWheels() return count end
function NetworkGetEntityIsNetworked() return networked end
function NetworkHasControlOfEntity() return owned end
function GetVehicleWheelRotationSpeed(_, index)
    reads[#reads + 1] = index
    return 20 + index * 3
end
function GetVehicleWheelSuspensionCompression(_, index) return index / 5 end
function SetVehicleWheelRotationSpeed(_, index, speed) writes[#writes + 1] = { index, speed } end
function SetVehicleWheelXrot() forbidden = forbidden + 1; error('camber is not wheel spin') end
function SetVehicleWheelYRotation() forbidden = forbidden + 1; error('geometry is not telemetry') end
function SetVehicleSuspensionHeight() forbidden = forbidden + 1; error('ride height is not per-wheel compression') end
function SetVehicleWheelFlags() forbidden = forbidden + 1; error('capture must not alter wheel physics') end
local dentRadius
function SetVehicleDamage(_, _, _, _, _, radius) dentRadius = radius end
local Replay = dofile('imports/vehicleReplay/client.lua')
assert(#writes == 0 and #reads == 0, 'loading must be passive')

local frame, recordedCount = Replay.capture(2)
assert(recordedCount == 6 and frame.count == 6 and #reads == 6 and #writes == 0,
    'recording must read every axle without touching the vehicle')
for index = 1, 6 do
    assert(frame[index] == 20 + (index - 1) * 3 and frame[10 + index] == (index - 1) / 5)
end
for index = 7, 10 do assert(frame[index] == 0 and frame[10 + index] == -1) end
assert(Replay.valid(frame))
local nextFrame = Replay.copy(frame)
nextFrame[1], nextFrame[11], nextFrame[17] = 40, 0.8, 0.5
local half = Replay.interpolate(frame, nextFrame, 0.5)
assert(half[1] == 30 and half[11] == 0.4 and half[17] == -1 and half.count == 6)
local reversed = Replay.copy(half, nil, nil, -2)
assert(reversed[1] == -60 and reversed[11] == half[11], 'time direction changes spin, never compression')
assert(Replay.apply(2, half, -2) and #writes == 6)
assert(writes[1][1] == 0 and writes[1][2] == -60 and writes[6][2] == -70)
writes = {}
assert(Replay.apply(2, half, 0) and #writes == 6)
for _, write in ipairs(writes) do assert(write[2] == 0) end
assert(half[11] == 0.4 and forbidden == 0, 'pause must not rewrite suspension or wheel geometry')

-- The Director stores wheel fields inside a larger flat numeric track.
local flat = { 123 }
Replay.copy(frame, flat, 16)
local blended = { 456 }
Replay.interpolate(flat, flat, 0.5, blended, 16, 16, 16)
assert(blended[1] == 456 and Replay.valid(blended, 16) and blended[22] == 35 and blended[32] == 1)
writes, count = {}, 4
assert(Replay.apply(2, blended, 1, 6, 16) and #writes == 4, 'bound writes by the current model wheel count')
owned, writes = false, {}
assert(not Replay.apply(2, frame, 1) and #writes == 0, 'a non-owner cannot replay wheels')
networked = false
assert(Replay.apply(2, frame, 1) and #writes == 4, 'local stand-ins do not require network ownership')
present, writes = false, {}
assert(not Replay.apply(2, frame, 1) and #writes == 0, 'deleted vehicles cannot be written')
present, owned, networked = true, true, true
local bad = Replay.copy(frame); bad[1] = 0 / 0
assert(not Replay.valid(bad) and not Replay.apply(2, bad, 1))
bad = Replay.copy(frame); bad[11] = -0.2
assert(not Replay.valid(bad) and not Replay.apply(2, bad, 1))
assert(not Replay.apply(2, frame, math.huge) and not Replay.apply(2, frame, 1, 1.5))
assert(not Replay.apply(2, frame, 1, -1) and not Replay.apply(2, frame, 1, '6'))

GetVehicleWheelSuspensionCompression = nil
local missing = Replay.capture(2)
for index = 11, 20 do assert(missing[index] == -1, 'unavailable telemetry must stay unknown') end
Replay.dent(2, { x = 1, y = 0, z = 0, size = 0.4 }, 5)
assert(dentRadius == 100, 'both callers use the bounded shared dent impact')

-- Exercise the consumer loader rather than supplying a fake lib module. This
-- is the boundary both resources use after @cortex-lib/init.lua runs.
local moduleLoads, loaderThreads = 0, 0
function GetResourceState() return 'started' end
function IsDuplicityVersion() return false end
function GetCurrentResourceName() return 'wheel-fixture' end
function PlayerId() return 4 end
function GetPlayerServerId() return 104 end
function PlayerPedId() return 0 end
function GetVehiclePedIsIn() return 0 end
function GetVehicleMaxNumberOfPassengers() return 0 end
function GetPedInVehicleSeat() return 0 end
function CreateThread() loaderThreads = loaderThreads + 1 end
function Wait() end
function LoadResourceFile(resource, file)
    assert(resource == 'cortex-lib')
    if file == 'imports/vehicleReplay/client.lua' then moduleLoads = moduleLoads + 1 end
    local handle = io.open(file, 'r')
    if not handle then return nil end
    local source = handle:read('*a'); handle:close()
    return source
end
exports = {}
local consumer = dofile('init.lua')
local wheelWrites = #writes
local loaded = consumer.vehicleReplay
assert(type(loaded) == 'table' and loaded == consumer('vehicleReplay') and moduleLoads == 1,
    'the real lazy loader must resolve and cache the wheel module')
assert(loaderThreads == 1 and #writes == wheelWrites, 'module loading adds no worker or vehicle writes')
assert(loaded.capture(2).count == 4)
print('vehicle_replay_spec: passive capture, all axles, compression, interpolation, pause, reverse, ownership and bounded dents passed')
