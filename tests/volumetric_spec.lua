-- Shared volumetric beam: native doubles only. Proves argument types, winding, gating, the texture
-- painter and the ray cache; not how the beam looks in game.
local h = { draws = {}, rays = 0, now = 1000, frame = 1, hour = 23, interior = 0, pixels = 0, commits = 0 }
local painter

function GetCurrentResourceName() return 'spec' end
function GetGameTimer() return h.now end
function GetFrameCount() return h.frame end
function GetClockHours() return h.hour end
function GetClockMinutes() return 0 end
function PlayerPedId() return 7 end
function GetInteriorFromEntity() return h.interior end
function GetFinalRenderedCamCoord() return h.cam end
function GetFinalRenderedCamRot() return h.rot end
function GetFinalRenderedCamFov() return 50.0 end
function CreateRuntimeTxd() return 1 end
function CreateRuntimeTexture() return 2 end
function SetRuntimeTexturePixel() h.pixels = h.pixels + 1 end
function CommitRuntimeTexture() h.commits = h.commits + 1 end
function CreateThread(fn) painter = coroutine.create(fn) end
function Wait() coroutine.yield() end
function DrawSpritePoly_2(...) h.draws[#h.draws + 1] = table.pack(...) end
function StartShapeTestLosProbe(...) h.rays = h.rays + 1; h.lastRay = table.pack(...); return h.rays end
function GetShapeTestResult()
    if h.hit then return 2, true, h.hit, { x = 0.0, y = 0.0, z = 1.0 }, 0 end
    return 2, false, nil, nil, 0
end

lib = {}
local V = dofile('imports/volumetric/client.lua')
assert(CortexVolumetric == V and lib.volumetric == V, 'global and loader alias')

local function expect(value, message) if not value then error(message, 2) end end

-- A lamp 100 m up pointing straight down, seen from the side.
h.cam, h.rot = { x = 60.0, y = 0.0, z = 50.0 }, { x = 0.0, y = 0.0, z = 90.0 }
local beam = V.new({ txd = 'spec_beam' })
expect(painter and h.pixels == 0, 'creation starts the painter without painting')
assert(coroutine.resume(painter))
expect(h.pixels == 32 * 8 and h.commits == 0, 'one strip per frame')

local p = { key = 9, ignore = 9, ox = 0.0, oy = 0.0, oz = 100.0, dx = 0.0, dy = 0.0, dz = -1.0,
    radius = 10.0, length = 100.0, r = 255, g = 200, b = 120, strength = 1.0 }

local function facesCamera(d, cam)
    local ex, ey, ez = d[4] - d[1], d[5] - d[2], d[6] - d[3]
    local fx, fy, fz = d[7] - d[1], d[8] - d[2], d[9] - d[3]
    local nx, ny, nz = ey * fz - ez * fy, ez * fx - ex * fz, ex * fy - ey * fx
    return nx * (cam.x - d[1]) + ny * (cam.y - d[2]) + nz * (cam.z - d[3]) > 0.0
end

expect(beam:draw(p) == true, 'night beam draws')
expect(h.commits == 1 and h.pixels == 32 * 256, 'a draw before the painter finishes paints the rest once')
expect(#h.draws > 0 and #h.draws <= (10 - 1) * 2, 'one quad per segment, one side each')
for _, d in ipairs(h.draws) do
    expect(d.n == 32 and d[22] == 'spec_beam' and d[23] == 'profile', 'texture and argument count')
    for i = 1, 12 do if i ~= 13 then expect(math.type(d[i]) == 'float', 'float coords and rgb') end end
    for _, i in ipairs({ 13, 17, 21 }) do expect(math.type(d[i]) == 'integer' and d[i] <= 255, 'integer alpha') end
    expect(facesCamera(d, h.cam), 'triangle wound towards the camera')
end
expect(h.lastRay[7] == 19 and h.lastRay[8] == 9, 'surface ray uses the flags and skips the lamp entity')
assert(coroutine.resume(painter))
expect(coroutine.status(painter) == 'dead' and h.commits == 1, 'painter stops without repainting')

-- Known length: the ray only looks for the contact plane, from rayStart to just past the lit point.
local ray = h.lastRay
expect(math.abs(ray[3] - 99.0) < 1e-6 and math.abs(ray[6] - (100.0 - 103.0)) < 1e-6, 'ray span')

-- Unknown length: the ray measures it, up to range.
h.frame, h.now = 2, 1200
local q = { key = 'm', ox = 0.0, oy = 0.0, oz = 100.0, dx = 0.0, dy = 0.0, dz = -1.0, radius = 10.0,
    range = 80.0, strength = 1.0 }
beam:draw(q)
h.hit = { x = 0.0, y = 0.0, z = 40.0 }
h.frame, h.now = 3, 1400
beam:draw(q)
expect(beam.rays.m.dist and math.abs(beam.rays.m.dist - 60.0) < 1e-6, 'measured length from the origin')
-- Between rays the lamp moves and tilts: the length is re-solved against the hit plane, not the
-- stale ray distance (a level 45 degree tilt from z = 90 lands 50 * sqrt(2) along the axis).
local s2 = math.sqrt(0.5)
local dist = beam:surface('m', 0.0, 0.0, 90.0, s2, 0.0, -s2, 80.0, nil, 1450)
expect(math.abs(dist - 50.0 / s2) < 1e-6, 'length follows the moving lamp between rays')
dist = beam:surface('m', 0.0, 0.0, 90.0, 0.0, 1.0, 0.0, 80.0, nil, 1460)
expect(math.abs(dist - 60.0) < 1e-6, 'level with the plane: the ray distance stands')
h.hit = nil

-- Gating.
h.draws = {}
h.frame = 4
expect(beam:draw({ key = 1, ox = 0.0, oy = 0.0, oz = 100.0, dx = 0.0, dy = 0.0, dz = -1.0, length = 0.5, strength = 1.0 }) == false,
    'too short')
p.strength = 0.0
expect(beam:draw(p) == false and #h.draws == 0, 'zero strength')
p.strength = 1.0
h.cam = { x = 0.0, y = 0.0, z = 60.0 } -- inside the cone
h.frame = 5
expect(beam:draw(p) == false and #h.draws == 0, 'camera inside the cone')
h.cam, h.rot = { x = 200.0, y = 0.0, z = 50.0 }, { x = 0.0, y = 0.0, z = -90.0 } -- far, looking away
h.frame = 6
expect(beam:draw(p) == false and #h.draws == 0, 'beam behind the camera is culled')
h.cam, h.rot = { x = 60.0, y = 0.0, z = 50.0 }, { x = 0.0, y = 0.0, z = 90.0 }
h.frame = 7
local capped = V.new({ txd = 'spec_cap', maxBeams = 1, paintEarly = false })
expect(capped:draw(p) == true and capped:draw(p) == false, 'maxBeams per frame')
local far = V.new({ txd = 'spec_far', maxDrawDistance = 20.0, drawDistanceFrom = 'origin', paintEarly = false })
local before = h.rays
expect(far:draw({ key = 'far', ox = 0.0, oy = 0.0, oz = 100.0, dx = 0.0, dy = 0.0, dz = -1.0, range = 50.0, strength = 1.0 }) == false
    and h.rays == before, 'origin distance limit skips before casting a ray')

-- Darkness: night, day, indoors.
h.hour = 13
expect(V.darkness(0.0, false) == 0.0 and V.darkness(0.5, false) == 0.5, 'day factor')
h.interior = 3
expect(V.darkness(0.0, true) == 1.0 and V.darkness(0.0, false) == 0.0, 'interiors only when asked')

-- Ray cache housekeeping.
beam:sweep(h.now + 5000)
expect(next(beam.rays) == nil, 'sweep forgets lamps no longer drawn')

-- Player setting: off by default, read from cortex-lib, followed live; only callers who ask see it.
local handlers, setting, reads = {}, nil, 0
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
local function fire(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
exports = setmetatable({}, { __index = function(_, resource)
    expect(resource == 'cortex-lib', 'reads the cortex-lib setting')
    return { getSetting = function(_, key) reads = reads + 1; expect(key == 'volumetricLights', 'setting key'); return setting end }
end })
expect(next(handlers) == nil, 'nothing is watched until a lamp asks (cortex-polcam never does)')
expect(V.playerEnabled() == false, 'off by default')
local heard = {}
V.onPlayerSetting(function(on) heard[#heard + 1] = on end)
expect(#handlers['cortex-lib:settingChanged'] == 1, 'one handler however often it is asked')
fire('cortex-lib:settingChanged', 'promptMarkers', true)
expect(V.playerEnabled() == false and #heard == 0, 'other settings are ignored')
fire('cortex-lib:settingChanged', 'volumetricLights', true)
expect(V.playerEnabled() == true and heard[1] == true, 'preview and save turn it on')
local before = reads
for _ = 1, 10 do V.playerEnabled() end
expect(reads == before, 'cached; no export call per frame')
fire('onClientResourceStop', 'cortex-lib')
expect(V.playerEnabled() == false and heard[2] == false, 'off while cortex-lib is stopped')
setting = true
fire('onClientResourceStart', 'cortex-lib')
expect(V.playerEnabled() == true and heard[3] == true, 're-read when cortex-lib starts')
fire('cortex-lib:settingChanged', 'volumetricLights', false)
expect(V.playerEnabled() == false and heard[4] == false, 'Discard turns it back off')

print('volumetric: winding, texture painter, ray modes, gating, culling, darkness and player setting passed')
