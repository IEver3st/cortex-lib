local timerPath = arg[1] or 'imports/timer/shared.lua'
local waitForPath = arg[2] or 'imports/waitFor/shared.lua'
local raycastPath = arg[3] or 'imports/raycast/client.lua'

local now = 0
local threads = {}
local waitNext = nil
local lastFlags = nil
local malformedCamera = false

function GetGameTimer() return now end
function Wait()
    if waitNext ~= nil then now = waitNext; waitNext = nil else now = now + 1 end
end
function CreateThread(callback) threads[#threads + 1] = callback end
function GetCurrentResourceName() return 'cortex-lib' end
function PlayerPedId() return 1 end
function GetVehiclePedIsIn() return 0 end
function StartShapeTestLosProbe(_, _, _, _, _, _, flags)
    lastFlags = flags
    return 10
end
function GetShapeTestResultIncludingMaterial() return 1, 0, nil, nil, nil, nil end
function GetGameplayCamCoord() return malformedCamera and { x = 0 / 0, y = 0, z = 0 } or { x = 0, y = 0, z = 0 } end
function GetGameplayCamRot() return { x = 0, y = 0, z = 0 } end
function vector3(x, y, z) return { x = x, y = y, z = z } end

exports = function() end
lib = {}

local timer = assert(dofile(timerPath))
now = 4294967280
local wrapped = timer(100, nil, true)
now = 20
assert(wrapped:getTimeLeft() == 64, 'timer time-left must survive the 32-bit clock wrap')
wrapped:pause()
assert(wrapped:isPaused() and wrapped:getTimeLeft() == 64, 'pause must preserve wrap-safe remaining time')
now = 50
wrapped:play()
now = 60
assert(wrapped:getTimeLeft() == 54, 'resume must rebuild its deadline from remaining time')

local ended = 0
now = 100
local overdue = timer(10, function() ended = ended + 1 end, true)
now = 111
overdue:pause()
assert(overdue:hasEnded() and overdue:getTimeLeft() == 0 and ended == 1,
    'pausing an elapsed timer must clamp/end/callback exactly once')
overdue:pause()
assert(ended == 1, 'an elapsed timer must not callback twice')

local hostileTimerError = setmetatable({}, {
    __tostring = function() error('secondary tostring failure') end,
})
local hostileTimerOk = pcall(timer, 0, function() error(hostileTimerError) end, false)
assert(hostileTimerOk, 'an unprintable timer callback error must remain contained')

local waitFor = assert(dofile(waitForPath))
now = 4294967290
waitNext = 5
local attempts = 0
local result = waitFor(function() attempts = attempts + 1; return nil end, nil, 10)
assert(result == nil and attempts == 2, 'waitFor must expire across timer wrap')

local raycast = assert(dofile(raycastPath))
now = 4294967290
waitNext = 2
local hit, _, _, _, _, err = raycast.fromCoords(
    { x = 0, y = 0, z = 0 }, { x = 1, y = 1, z = 1 }, -1, 1, 10
)
assert(hit == false and err == 'timeout' and lastFlags == -1,
    'raycast must accept the documented -1 mask and expire across timer wrap')
local _, _, _, _, _, invalid = raycast.fromCoords(
    { x = 0, y = 0, z = 0 }, { x = 1, y = 1, z = 1 }, -2, 1, 10
)
assert(invalid == 'invalid_options', 'raycast must reject undocumented negative masks')
malformedCamera = true
local _, _, _, _, _, cameraError = raycast.fromCamera(511, 1, 10, 10)
assert(cameraError == 'invalid_coordinates', 'raycast camera mode must reject malformed native vectors without arithmetic errors')

print('wait and deadline safety: PASS')
