-- Shared fake volumetric beam for script spotlights (cortex-polcam, gsd-arges, cortex-flashlight).
--
-- GTA gives DrawSpotLight no visible beam, and a faceted cone shell shows its faces, so each lit
-- lamp draws one camera-facing band instead. It spans the cone's full width as seen from the
-- camera, is brightest along the axis where the eye looks through the most lit haze, and softens
-- to nothing at the edges. It brightens when seen down its length, dims away from the lamp as the
-- light spreads, and fades out against the surface it lands on rather than cutting into it.
--
-- Cost is one DrawSpritePoly_2 per triangle, so each segment of the band is one quad, each
-- triangle is drawn once, facing the camera, and beams or segments outside the view are skipped.
-- The soft profile across the band comes from a texture (see Paint), which keeps it exact however
-- the quad is split.
--
-- Use through the loader (`lib.volumetric`) or include it directly as a client script
-- (`@cortex-lib/imports/volumetric/client.lua`, which also exposes the global `CortexVolumetric`).
-- It runs in the caller's runtime: each resource owns its beams, texture and ray cache.
--
--   local beam = CortexVolumetric.new({ alpha = 55, coneScale = 0.7, ... })
--   beam:draw(params) -- params is a table the caller refills each frame (see Beam:draw)
local math_sqrt, math_abs, math_floor = math.sqrt, math.abs, math.floor
local math_rad, math_tan, math_min, math_max = math.rad, math.tan, math.min, math.max
local math_sin, math_cos, math_atan = math.sin, math.cos, math.atan
local type, tonumber, pairs = type, tonumber, pairs

local volumetric = {}

local MAX_VIEW_BOOST = 2.5
local RAY_INTERVAL_MS = 90
local FORGET_AFTER_MS = 3000
local DARKNESS_REFRESH_MS = 250
-- Widest screen the view test allows for (21:9 and a little more).
local MAX_ASPECT = 2.4

-- Profile texture. Each segment of the band is a trapezoid: narrow ring at the lamp end, wide ring
-- at the far end. The soft profile depends on the offset from the axis divided by the local width,
-- which no triangle can interpolate, so the division lives in the texture instead. U is the offset
-- across the segment's wide end (0 and 1 are its edges), V runs along the segment (0 at the narrow
-- ring), and both are linear over the quad, so any split samples the right texel. One strip per
-- narrow-to-wide width ratio holds (1 - z^2)^softness with z = offset / local width.
local TEX_W, STRIP_H, STRIPS = 32, 8, 32
local TEX_H = STRIP_H * STRIPS
volumetric.texture = { width = TEX_W, stripHeight = STRIP_H, strips = STRIPS, height = TEX_H }

local function Smoothstep(x)
    if x <= 0.0 then return 0.0 end
    if x >= 1.0 then return 1.0 end
    return x * x * (3.0 - 2.0 * x)
end
volumetric.smoothstep = Smoothstep

-- Full strength 21:00-05:00 (and indoors when asked), ramping over two hours either side.
function volumetric.darkness(dayFactor, interiors)
    if interiors and GetInteriorFromEntity(PlayerPedId()) ~= 0 then return 1.0 end
    local h = GetClockHours() + GetClockMinutes() / 60.0
    local night
    if h >= 21.0 or h < 5.0 then night = 1.0
    elseif h >= 19.0 then night = (h - 19.0) / 2.0
    elseif h < 7.0 then night = (7.0 - h) / 2.0
    else night = 0.0 end
    local day = tonumber(dayFactor) or 0.0
    return day + (1.0 - day) * night
end

-- Player opt-in: Cortex settings → Graphics → Volumetric lights (cortex-lib setting
-- `volumetricLights`, off by default). Lamps that should honour it gate on playerEnabled(); a
-- resource that never asks (cortex-polcam) draws its beam regardless and registers no handlers.
local PLAYER_SETTING = 'volumetricLights'
local playerOn, playerWatched
local playerListeners = {}

local function ReadPlayerSetting()
    local ok, value = pcall(function() return exports['cortex-lib']:getSetting(PLAYER_SETTING) end)
    return ok and value == true
end

local function SetPlayerOn(value)
    if value == playerOn then return end
    playerOn = value
    for i = 1, #playerListeners do pcall(playerListeners[i], value) end
end

local function WatchPlayerSetting()
    if playerWatched then return end
    playerWatched = true
    playerOn = ReadPlayerSetting()
    if type(AddEventHandler) ~= 'function' then return end
    -- Fires on preview, Discard and Save, so the beam follows the toggle while the menu is open.
    AddEventHandler('cortex-lib:settingChanged', function(key, value)
        if key == PLAYER_SETTING then SetPlayerOn(value == true) end
    end)
    AddEventHandler('onClientResourceStart', function(resource)
        if resource == 'cortex-lib' then SetPlayerOn(ReadPlayerSetting()) end
    end)
    AddEventHandler('onClientResourceStop', function(resource)
        if resource == 'cortex-lib' then SetPlayerOn(false) end
    end)
end

function volumetric.playerEnabled()
    if not playerWatched then WatchPlayerSetting() end
    return playerOn == true
end

-- fn(enabled) runs whenever the player's setting changes.
function volumetric.onPlayerSetting(fn)
    WatchPlayerSetting()
    playerListeners[#playerListeners + 1] = fn
end

-- Rings along the beam, packed towards the lamp where brightness changes fastest.
local function BuildRings(count)
    local t = {}
    for i = 1, count do
        local s = (i - 1) / (count - 1)
        t[i] = s * s
    end
    return t
end

local Beam = {}
Beam.__index = Beam

local function option(value, default)
    value = tonumber(value)
    if value == nil then return default end
    return value
end

-- Options (all optional; defaults are cortex-polcam's spotlight):
--   txd, tex           runtime texture names (default '<resource>_volumetric', 'profile')
--   alpha              peak alpha at full strength (55)
--   coneScale          visible band width as a fraction of the DrawSpotLight cone (0.7)
--   sourceRadius       band half-width at the lamp, metres (0.08)
--   maxEndRadius       cap on the band half-width, metres (45; math.huge for none)
--   maxDrawDistance    skip beams farther from the camera than this (800; false for no limit)
--   drawDistanceFrom   'middle' of the beam (default) or 'origin'
--   edgeSoftness       profile exponent across the band (1.3)
--   falloff            dimming as the light spreads (0.4)
--   openFade           fraction of the beam that fades out when it lands on nothing (0.2); rings are
--                      packed towards the lamp, so 0.2 is one segment and reads as a cut seen down the beam
--   rings              rings along the beam, at least 4 (10)
--   traceFlags         surface ray flags (19)
--   rayStart           metres past the lamp where the surface ray starts (1.0)
--   minLength          beams shorter than this are not drawn, metres (1.0)
--   contactSoftness    soft contact depth at the lamp end, metres; grows with the band (0.3)
--   inside             camera-in-cone fade { behind = 2.0, margin = 1.0, soften = 1.0 }
--   doubleSided        draw both windings (debug aid; false)
--   cull               skip beams and segments outside the view (true)
--   maxBeams           beams drawn per frame (unlimited)
--   paintEarly         paint the texture one strip per frame from creation (true)
--   profile            { enabled, enter, leave } profiler scopes; labels profileBuild/profilePolys
function volumetric.new(options)
    options = options or {}
    local inside = type(options.inside) == 'table' and options.inside or {}
    local rings = math_max(4, math_floor(option(options.rings, 10)))
    local resource = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'cortex'
    local self = setmetatable({
        txd = options.txd or (resource .. '_volumetric'),
        tex = options.tex or 'profile',
        alpha = option(options.alpha, 55),
        coneScale = option(options.coneScale, 0.7),
        sourceRadius = option(options.sourceRadius, 0.08),
        maxEndRadius = option(options.maxEndRadius, 45.0),
        maxDrawDistance = options.maxDrawDistance ~= false and option(options.maxDrawDistance, 800.0) or nil,
        fromOrigin = options.drawDistanceFrom == 'origin',
        softness = option(options.edgeSoftness, 1.3),
        falloff = option(options.falloff, 0.4),
        openFade = math_min(1.0, math_max(0.05, option(options.openFade, 0.2))),
        ringT = BuildRings(rings),
        ringCount = rings,
        traceFlags = option(options.traceFlags, 19),
        rayStart = option(options.rayStart, 1.0),
        minLength = option(options.minLength, 1.0),
        contactSoftness = option(options.contactSoftness, 0.3),
        insideBehind = option(inside.behind, 2.0),
        insideMargin = option(inside.margin, 1.0),
        insideSoften = option(inside.soften, 1.0),
        doubleSided = options.doubleSided == true,
        cull = options.cull ~= false,
        maxBeams = tonumber(options.maxBeams),
        profile = type(options.profile) == 'table' and options.profile or nil,
        profileBuild = options.profileBuild or 'volumetric:build',
        profilePolys = options.profilePolys or 'volumetric:polys',
        -- texture
        texture = nil, paintedSoftness = nil, paintSoftness = nil, paintStrip = 0,
        -- per-lamp surface rays
        rays = {}, swept = 0,
        -- per-frame
        frame = { id = nil, drawn = 0, darkAt = nil, dark = 0.0 },
        -- vertex scratch: two vertices per ring (2i - 1 left edge, 2i right); ring centres for culling
        vx = {}, vy = {}, vz = {}, va = {}, rr = {}, rcx = {}, rcy = {}, rcz = {}, rd = {},
        cr = 255.0, cg = 255.0, cb = 255.0,
    }, Beam)
    if options.paintEarly ~= false and type(CreateThread) == 'function' and type(Wait) == 'function' then
        CreateThread(function()
            while self.paintedSoftness ~= self.softness do
                if not self:paint(self.softness, 1) and not self.texture then return end
                Wait(0)
            end
        end)
    end
    return self
end

-- White; alpha is the profile. Painting it is 8192 pixel natives (about a millisecond), so it is
-- spread one strip per frame from creation; a draw that needs it sooner finishes the rest at once.
-- Repainted only if the softness changes. True once the whole texture is committed.
function Beam:paint(softness, strips)
    if self.paintedSoftness == softness then return true end
    if not self.texture then
        local tex = CreateRuntimeTexture(CreateRuntimeTxd(self.txd), self.tex, TEX_W, TEX_H)
        if not tex or tex == 0 then return false end
        self.texture = tex
    end
    if self.paintSoftness ~= softness then self.paintSoftness, self.paintStrip = softness, 0 end
    local texture = self.texture
    local last = math_min(STRIPS, self.paintStrip + strips) - 1
    for k = self.paintStrip, last do
        local ratio = k / (STRIPS - 1)
        for j = 0, STRIP_H - 1 do
            local width = ratio + (1.0 - ratio) * j / (STRIP_H - 1)
            for x = 0, TEX_W - 1 do
                local z = width > 0.0001 and ((x + 0.5) / TEX_W * 2.0 - 1.0) / width or 2.0
                local a = z * z < 1.0 and math_floor(255.0 * (1.0 - z * z) ^ softness + 0.5) or 0
                SetRuntimeTexturePixel(texture, x, k * STRIP_H + j, 255, 255, 255, a)
            end
        end
    end
    self.paintStrip = last + 1
    if self.paintStrip < STRIPS then return false end
    CommitRuntimeTexture(texture)
    self.paintedSoftness = softness
    return true
end

-- Changes the ring count (live config edits).
function Beam:setRings(count)
    count = math_max(4, math_floor(tonumber(count) or 10))
    if count ~= self.ringCount then self.ringT, self.ringCount = BuildRings(count), count end
end

function Beam:ensureTexture()
    return self:paint(self.softness, STRIPS)
end

-- Darkness for this beam's day factor, re-read a few times a second.
function Beam:darkness(dayFactor, interiors, now)
    local f = self.frame
    now = now or GetGameTimer()
    if f.darkAt == nil or now - f.darkAt >= DARKNESS_REFRESH_MS or now < f.darkAt then
        f.darkAt = now
        f.dark = volumetric.darkness(dayFactor, interiors)
    end
    return f.dark
end

-- One budget per frame: the camera and view are read once whatever the number of beams.
-- id/cam/now let a caller that already has them skip the natives.
function Beam:beginFrame(id, cam, now)
    local f = self.frame
    if id == nil then id = type(GetFrameCount) == 'function' and GetFrameCount() or GetGameTimer() end
    if f.id == id then return f end
    f.id, f.drawn = id, 0
    f.now = now or GetGameTimer()
    f.cam = cam or GetFinalRenderedCamCoord()
    f.view = nil
    if self.cull and type(GetFinalRenderedCamRot) == 'function' and type(GetFinalRenderedCamFov) == 'function' then
        local rot, fov = GetFinalRenderedCamRot(2), tonumber(GetFinalRenderedCamFov())
        if rot and fov and fov > 0.0 then
            local pitch, yaw = math_rad(rot.x), math_rad(rot.z)
            local cp = math_cos(pitch)
            f.fx, f.fy, f.fz = -math_sin(yaw) * cp, math_cos(yaw) * cp, math_sin(pitch)
            -- Half the screen diagonal as an angle from the view axis.
            f.view = math_atan(math_tan(math_rad(fov) * 0.5) * math_sqrt(1.0 + MAX_ASPECT * MAX_ASPECT))
            f.viewCos, f.viewSin = math_cos(f.view), math_sin(f.view)
        end
    end
    if f.now - self.swept > 1000 then
        self.swept = f.now
        self:sweep(f.now)
    end
    return f
end

-- False when a sphere around a beam (or segment) lies outside the camera's view.
local function InView(f, x, y, z, radius)
    if not f.view then return true end
    local cam = f.cam
    local vx, vy, vz = x - cam.x, y - cam.y, z - cam.z
    local distSq = vx * vx + vy * vy + vz * vz
    if distSq <= radius * radius then return true end
    -- cos(view + asin(radius / dist)) * dist, without per-sphere trig.
    local cv, sv = f.viewCos or math_cos(f.view), f.viewSin or math_sin(f.view)
    return vx * f.fx + vy * f.fy + vz * f.fz >= cv * math_sqrt(distSq - radius * radius) - sv * radius
end
volumetric.inView = InView

-- Surface ahead of a lamp: async ray per key, re-cast every RAY_INTERVAL_MS. Returns the hit
-- distance from the origin (nil until a ray has hit / when nothing is within reach) and the
-- surface plane. The ray is up to RAY_INTERVAL_MS old and was cast from where the lamp was then,
-- so while the lamp moves (a torch swinging as its holder walks) the distance is re-solved every
-- frame against the hit plane; the old ray distance stepped the beam's end ten times a second.
function Beam:surface(key, ox, oy, oz, dx, dy, dz, reach, ignore, now)
    local c = self.rays[key]
    if not c then c = { at = 0 }; self.rays[key] = c end
    c.seen = now
    if c.handle then
        local status, hit, at, normal = GetShapeTestResult(c.handle)
        if status == 2 then
            c.dist, c.plane = nil, nil
            if (hit == 1 or hit == true) and at then
                local x, y, z = at.x - c.fx, at.y - c.fy, at.z - c.fz
                c.dist = math_sqrt(x * x + y * y + z * z)
                local nl = normal and math_sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z) or 0.0
                if nl > 0.001 then
                    c.plane = { x = at.x, y = at.y, z = at.z, nx = normal.x / nl, ny = normal.y / nl, nz = normal.z / nl }
                end
            end
            c.handle = nil
        elseif status == 0 then
            c.handle = nil
        end
    end
    if not c.handle and now - c.at > RAY_INTERVAL_MS then
        c.at = now
        c.fx, c.fy, c.fz = ox, oy, oz
        local s = self.rayStart
        c.handle = StartShapeTestLosProbe(ox + dx * s, oy + dy * s, oz + dz * s,
            ox + dx * reach, oy + dy * reach, oz + dz * reach, self.traceFlags, ignore or 0, 7)
    end
    local dist, plane = c.dist, c.plane
    if dist and plane then
        local facing = dx * plane.nx + dy * plane.ny + dz * plane.nz
        if facing < -0.05 then
            local t = ((plane.x - ox) * plane.nx + (plane.y - oy) * plane.ny + (plane.z - oz) * plane.nz) / facing
            -- Off the surface the ray found (a small prop, an edge), keep the ray until the next one.
            if t > 0.0 and t <= reach and t < dist * 2.0 and t > dist * 0.5 then dist = t end
        end
    end
    return dist, plane
end

-- Forget rays for lamps not drawn for a while (streamed out, switched off).
function Beam:sweep(now)
    now = now or GetGameTimer()
    for key, c in pairs(self.rays) do
        if now - (c.seen or 0) > FORGET_AFTER_MS then self.rays[key] = nil end
    end
end

function Beam:forget(key)
    if key ~= nil then self.rays[key] = nil end
end

function Beam:clear()
    for key in pairs(self.rays) do self.rays[key] = nil end
end

-- Triangle emitter over the beam being drawn (module-level so no closure is made per beam).
-- The draw native is read once per beam rather than once per triangle.
local t_vx, t_vy, t_vz, t_va, t_cr, t_cg, t_cb, t_txd, t_tex, t_poly
local function Tri(i1, u1, v1, i2, u2, v2, i3, u3, v3)
    local a1, a2, a3 = t_va[i1], t_va[i2], t_va[i3]
    if a1 + a2 + a3 == 0 then return end
    t_poly(t_vx[i1], t_vy[i1], t_vz[i1], t_vx[i2], t_vy[i2], t_vz[i2], t_vx[i3], t_vy[i3], t_vz[i3],
        t_cr, t_cg, t_cb, a1, t_cr, t_cg, t_cb, a2, t_cr, t_cg, t_cb, a3,
        t_txd, t_tex, u1, v1, 1.0, u2, v2, 1.0, u3, v3, 1.0)
end

-- A camera inside the cone (an operator at its apex) would see the band as a veil over the whole
-- view. Fade it out from just outside the edge.
local function OutsideFactor(self, cam, ox, oy, oz, dx, dy, dz, length, spread)
    local rx, ry, rz = cam.x - ox, cam.y - oy, cam.z - oz
    local along = rx * dx + ry * dy + rz * dz
    if along < -self.insideBehind or along > length then return 1.0 end
    local perpSq = rx * rx + ry * ry + rz * rz - along * along
    local perp = perpSq > 0.0 and math_sqrt(perpSq) or 0.0
    local edge = self.sourceRadius + (along > 0.0 and along or 0.0) * spread
    local fade = (perp - edge - self.insideMargin) / (edge * 0.5 + self.insideSoften)
    if fade <= 0.0 then return 0.0 end
    return fade < 1.0 and fade or 1.0
end

-- Draws one beam. p (a table the caller reuses):
--   key        identifies the lamp across frames (ray cache)
--   ox, oy, oz origin and dx, dy, dz normalised direction (the values given to DrawSpotLight)
--   radius     DrawSpotLight radius (cone angle, degrees)
--   length     metres to the lit point when the caller knows it; the ray then only finds the
--              surface plane. Without it the ray measures the length, up to range.
--   range      reach when length is not given (100)
--   r, g, b    colour 0-255; strength 0-1 (darkness x output, etc.)
--   ignore     entity the surface ray skips
--   frame, cam, now  optional per-frame values the caller already has (see Beam:beginFrame)
-- Returns true when drawn.
function Beam:draw(p)
    local ox, oy, oz, dx, dy, dz = p.ox, p.oy, p.oz, p.dx, p.dy, p.dz
    local strength = p.strength or 1.0
    if strength <= 0.0 or not ox or not dx then return false end

    local f = self:beginFrame(p.frame, p.cam, p.now)
    if self.maxBeams and f.drawn >= self.maxBeams then return false end
    local cam, now = p.cam or f.cam, p.now or f.now
    local maxDraw = self.maxDrawDistance
    if maxDraw and self.fromOrigin then
        -- Before any ray: lamps out of range cost nothing.
        local cdx, cdy, cdz = ox - cam.x, oy - cam.y, oz - cam.z
        if cdx * cdx + cdy * cdy + cdz * cdz > maxDraw * maxDraw then return false end
    end

    -- Length and the surface the beam lands on.
    local length, plane = p.length, nil
    if length then
        if length < self.minLength then return false end
    else
        local range = p.range or 100.0
        local hit
        if p.key ~= nil then hit, plane = self:surface(p.key, ox, oy, oz, dx, dy, dz, range, p.ignore, now) end
        length = hit and math_min(hit, range) or range
        if not (hit and hit < range) then plane = nil end
        if length < self.minLength then return false end
    end

    local half = length * 0.5
    if maxDraw and not self.fromOrigin then
        local cdx, cdy, cdz = ox + dx * half - cam.x, oy + dy * half - cam.y, oz + dz * half - cam.z
        if cdx * cdx + cdy * cdy + cdz * cdz > maxDraw * maxDraw then return false end
    end

    local source, maxEnd = self.sourceRadius, self.maxEndRadius
    local spread = math_tan(math_rad(p.radius or 10.0)) * self.coneScale
    if f.view and not InView(f, ox + dx * half, oy + dy * half, oz + dz * half,
        half + math_min(maxEnd, source + length * spread)) then
        return false
    end
    strength = strength * OutsideFactor(self, cam, ox, oy, oz, dx, dy, dz, length, spread)
    if strength <= 0.01 or not self:ensureTexture() then return false end

    -- With a known length the ray only supplies the contact plane.
    if p.length and p.key ~= nil then
        local _
        _, plane = self:surface(p.key, ox, oy, oz, dx, dy, dz, length + 3.0, p.ignore, now)
    end

    local profile = self.profile
    local profiling = profile and profile.enabled
    if profiling then profile.enter(self.profileBuild) end

    local vx, vy, vz, va, rr = self.vx, self.vy, self.vz, self.va, self.rr
    local rcx, rcy, rcz, rd = self.rcx, self.rcy, self.rcz, self.rd
    local ringT, ringCount = self.ringT, self.ringCount
    local peak = self.alpha * strength
    local falloff, contact, openFade = self.falloff, self.contactSoftness, self.openFade
    local refRadius = source + spread -- one metre out
    local camX, camY, camZ = cam.x, cam.y, cam.z
    local px, py, pz = 0.0, 0.0, 1.0 -- last good side vector

    -- Side vector: across the axis and across the line of sight, so the band always shows the
    -- cone's full width. dir x (ring centre - camera) is the same for every ring (the along-axis
    -- part drops out), so it is computed once; only the sight length, and with it the sine of the
    -- view angle, changes along the beam. Looking down the beam passes through more haze, so a
    -- small sine brightens it.
    local wox, woy, woz = ox - camX, oy - camY, oz - camZ
    local ax, ay, az = dy * woz - dz * woy, dz * wox - dx * woz, dx * woy - dy * wox
    local al = math_sqrt(ax * ax + ay * ay + az * az)
    local nsx, nsy, nsz = 0.0, 0.0, 0.0
    if al > 0.0 then nsx, nsy, nsz = ax / al, ay / al, az / al end

    local n = 0
    for i = 1, ringCount do
        local t = ringT[i]
        local d = t * length
        local ringRadius = math_min(maxEnd, source + d * spread)
        local cx, cy, cz = ox + dx * d, oy + dy * d, oz + dz * d

        local wx, wy, wz = cx - camX, cy - camY, cz - camZ
        local wl = math_sqrt(wx * wx + wy * wy + wz * wz)
        local sx, sy, sz, sine = px, py, pz, 0.0
        if wl > 0.001 then
            sine = al / wl
            if sine > 0.02 then sx, sy, sz = nsx, nsy, nsz end
        end
        if sine <= 0.02 and i == 1 then
            -- Dead on the axis from the first ring: any perpendicular will do.
            local hx, hz = 0.0, 1.0
            if math_abs(dz) > 0.99 then hx, hz = 1.0, 0.0 end
            local ux, uy, uz = dy * hz, dz * hx - dx * hz, -dy * hx
            local ul = math_sqrt(ux * ux + uy * uy + uz * uz)
            sx, sy, sz = ux / ul, uy / ul, uz / ul
        end
        px, py, pz = sx, sy, sz
        local boost = math_min(MAX_VIEW_BOOST, 1.0 / math_max(sine, 1.0 / MAX_VIEW_BOOST))

        -- The light spreads over a wider disc further out, so the haze dims.
        local spreadDim = math_min(1.0, (refRadius / ringRadius) ^ falloff)
        -- No surface known: trail off over the last openFade of the beam.
        local tail = plane and 1.0 or Smoothstep((1.0 - t) / openFade)
        local ringAlpha = peak * boost * spreadDim * tail
        local soft = contact + 0.35 * ringRadius
        rr[i] = ringRadius
        rcx[i], rcy[i], rcz[i], rd[i] = cx, cy, cz, d

        for side = -1, 1, 2 do
            local w = side * ringRadius
            local x, y, z = cx + sx * w, cy + sy * w, cz + sz * w
            local a = ringAlpha
            if plane and a > 0.0 then
                -- Soft contact: fade out approaching the surface instead of cutting through it.
                local h = (x - plane.x) * plane.nx + (y - plane.y) * plane.ny + (z - plane.z) * plane.nz
                a = a * Smoothstep(h / soft)
            end
            n = n + 1
            vx[n], vy[n], vz[n] = x, y, z
            va[n] = math_min(255, math_floor(a + 0.5))
        end
    end
    if profiling then profile.leave(); profile.enter(self.profilePolys) end

    -- Floats: the native reads RGB as float and int-casts internally; alpha is an integer.
    t_vx, t_vy, t_vz, t_va = vx, vy, vz, va
    t_cr, t_cg, t_cb = (p.r or 255) * 1.0, (p.g or 255) * 1.0, (p.b or 255) * 1.0
    t_txd, t_tex, t_poly = self.txd, self.tex, DrawSpritePoly_2
    local both = self.doubleSided
    local cullSegments = f.view ~= nil
    for i = 1, ringCount - 1 do
        local l0, r0, l1, r1 = 2 * i - 1, 2 * i, 2 * i + 1, 2 * i + 2
        -- A beam that leaves the screen draws only the segments still in view.
        local visible = va[l0] + va[r0] + va[l1] + va[r1] > 0
        if visible and cullSegments then
            local segHalf = (rd[i + 1] - rd[i]) * 0.5
            visible = InView(f, (rcx[i] + rcx[i + 1]) * 0.5, (rcy[i] + rcy[i + 1]) * 0.5,
                (rcz[i] + rcz[i + 1]) * 0.5, segHalf + rr[i + 1])
        end
        if visible then
            -- Only the side (b - a) x (c - a) points to is drawn, so wind each segment towards the
            -- camera instead of drawing both sides.
            local ex, ey, ez = vx[r0] - vx[l0], vy[r0] - vy[l0], vz[r0] - vz[l0]
            local gx, gy, gz = vx[l1] - vx[l0], vy[l1] - vy[l0], vz[l1] - vz[l0]
            local facing = (ey * gz - ez * gy) * (camX - vx[l0]) + (ez * gx - ex * gz) * (camY - vy[l0])
                + (ex * gy - ey * gx) * (camZ - vz[l0])
            -- The strip for this segment's narrow-to-wide ratio; V spans its rows.
            local ratio = rr[i + 1] > 0.0 and math_min(1.0, rr[i] / rr[i + 1]) or 1.0
            local strip = math_floor(ratio * (STRIPS - 1) + 0.5) * STRIP_H
            local vn, vw = (strip + 0.5) / TEX_H, (strip + STRIP_H - 0.5) / TEX_H
            local ul, ur = 0.5 - 0.5 * ratio, 0.5 + 0.5 * ratio
            if facing > 0.0 or both then
                Tri(l0, ul, vn, r0, ur, vn, r1, 1.0, vw)
                Tri(l0, ul, vn, r1, 1.0, vw, l1, 0.0, vw)
            end
            if facing <= 0.0 or both then
                Tri(r1, 1.0, vw, r0, ur, vn, l0, ul, vn)
                Tri(l1, 0.0, vw, r1, 1.0, vw, l0, ul, vn)
            end
        end
    end
    if profiling then profile.leave() end
    f.drawn = f.drawn + 1
    return true
end

CortexVolumetric = volumetric
if type(lib) == 'table' then rawset(lib, 'volumetric', volumetric) end

return volumetric
