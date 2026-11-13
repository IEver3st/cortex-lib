local worldScreen = {}
local owner = GetCurrentResourceName()
local pages, swaps = {}, {}

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end

local function squareToQuad(p)
    local x0, y0, x1, y1, x2, y2, x3, y3 = p[1][1], p[1][2], p[2][1], p[2][2], p[3][1], p[3][2], p[4][1], p[4][2]
    local dx3, dy3 = x0 - x1 + x2 - x3, y0 - y1 + y2 - y3
    if math.abs(dx3) < 1e-9 and math.abs(dy3) < 1e-9 then
        return { x1 - x0, x3 - x0, x0, y1 - y0, y3 - y0, y0, 0.0, 0.0, 1.0 }
    end
    local dx1, dx2, dy1, dy2 = x1 - x2, x3 - x2, y1 - y2, y3 - y2
    local den = dx1 * dy2 - dx2 * dy1
    if math.abs(den) < 1e-12 then return nil end
    local g = (dx3 * dy2 - dx2 * dy3) / den
    local h = (dx1 * dy3 - dx3 * dy1) / den
    return { x1 - x0 + g * x1, x3 - x0 + h * x3, x0, y1 - y0 + g * y1, y3 - y0 + h * y3, y0, g, h, 1.0 }
end

local function invert(m)
    local a, b, c, d, e, f, g, h, i = m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]
    local A, B, Cc = e * i - f * h, -(d * i - f * g), d * h - e * g
    local det = a * A + b * B + c * Cc
    if math.abs(det) < 1e-12 then return nil end
    local inv = 1.0 / det
    return { A * inv, -(b * i - c * h) * inv, (b * f - c * e) * inv,
        B * inv, (a * i - c * g) * inv, -(a * f - c * d) * inv,
        Cc * inv, -(a * h - b * g) * inv, (a * e - b * d) * inv }
end

local function apply(m, x, y)
    local w = m[7] * x + m[8] * y + m[9]
    if math.abs(w) < 1e-12 then return nil end
    return (m[1] * x + m[2] * y + m[3]) / w, (m[4] * x + m[5] * y + m[6]) / w
end

worldScreen.squareToQuad, worldScreen.invert, worldScreen.apply = squareToQuad, invert, apply

function worldScreen.homography(poly)
    local forward = poly and squareToQuad(poly)
    return forward and invert(forward) or nil
end

function worldScreen.map(inverse, px, py)
    if not inverse then return nil end
    local u, v = apply(inverse, px, py)
    if not u or u < 0 or u > 1 or v < 0 or v > 1 then return nil end
    return u, v
end

function worldScreen.inside(poly, px, py)
    local sign = 0
    for i = 1, #poly do
        local a, b = poly[i], poly[i % #poly + 1]
        local cross = (b[1] - a[1]) * (py - a[2]) - (b[2] - a[2]) * (px - a[1])
        if cross ~= 0 then
            local s = cross > 0 and 1 or -1
            if sign == 0 then sign = s elseif s ~= sign then return false end
        end
    end
    return sign ~= 0
end

function worldScreen.projectPoint(v, rw, rh)
    local ok, x, y = GetScreenCoordFromWorldCoord(v.x, v.y, v.z)
    if not ok then return nil end
    return x * rw, y * rh
end

function worldScreen.projectQuad(corners, rw, rh)
    if not rw then rw, rh = GetActiveScreenResolution() end
    local out = {}
    for i = 1, 4 do
        local x, y = worldScreen.projectPoint(corners[i], rw, rh)
        if not x then return false end
        out[i] = { x, y }
    end
    return out
end

local function vec(t, fallback)
    if type(t) == 'vector3' then return t end
    if type(t) == 'table' and finite(t.x) and finite(t.y) and finite(t.z) then return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end
    return fallback
end

local function cross(a, b) return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end

function worldScreen.quad(entity, face, lift, grow)
    local centre = vec(face.centre, vector3(0.0, 0.0, 0.0))
    local right = vec(face.right, vector3(1.0, 0.0, 0.0))
    local up = vec(face.up, vector3(0.0, 0.0, 1.0))
    local out = cross(right, up)
    lift, grow = (lift or 0.0) + 0.0, grow or 0.0
    local hw, hh = face.w / 2 + grow, face.h / 2 + grow
    local function at(du, dv)
        local p = centre + right * du + up * dv + out * lift
        return GetOffsetFromEntityInWorldCoords(entity, p.x, p.y, p.z)
    end
    local c = GetOffsetFromEntityInWorldCoords(entity, centre.x, centre.y, centre.z)
    local n = GetOffsetFromEntityInWorldCoords(entity, centre.x + out.x, centre.y + out.y, centre.z + out.z) - c
    return { corners = { at(-hw, hh), at(hw, hh), at(hw, -hh), at(-hw, -hh) }, centre = c, normal = n }
end

function worldScreen.facing(geo, from)
    local d = from - geo.centre
    return d.x * geo.normal.x + d.y * geo.normal.y + d.z * geo.normal.z > 0.0
end

function worldScreen.drawQuad(q, dict, name, u0, v0, u1, v1, alpha)
    local a = alpha or 255
    DrawSpritePoly(q[1].x, q[1].y, q[1].z, q[2].x, q[2].y, q[2].z, q[3].x, q[3].y, q[3].z, 255, 255, 255, a, dict, name,
        u0, v0, 1.0, u1, v0, 1.0, u1, v1, 1.0)
    DrawSpritePoly(q[3].x, q[3].y, q[3].z, q[4].x, q[4].y, q[4].z, q[1].x, q[1].y, q[1].z, 255, 255, 255, a, dict, name,
        u1, v1, 1.0, u0, v1, 1.0, u0, v0, 1.0)
    DrawSpritePoly(q[1].x, q[1].y, q[1].z, q[3].x, q[3].y, q[3].z, q[2].x, q[2].y, q[2].z, 255, 255, 255, a, dict, name,
        u0, v0, 1.0, u1, v1, 1.0, u1, v0, 1.0)
    DrawSpritePoly(q[3].x, q[3].y, q[3].z, q[1].x, q[1].y, q[1].z, q[4].x, q[4].y, q[4].z, 255, 255, 255, a, dict, name,
        u1, v1, 1.0, u0, v0, 1.0, u0, v1, 1.0)
end

function worldScreen.cell(index, cols, rows, pageW, pageH)
    local cw, ch = 1.0 / cols, 1.0 / rows
    local c, r = index % cols, index // cols
    local ix, iy = 0.5 / (pageW or 2048), 0.5 / (pageH or 2048)
    return c * cw + ix, r * ch + iy, (c + 1) * cw - ix, (r + 1) * ch - iy
end

function worldScreen.cursor()
    local state = LocalPlayer.state
    local pilot = state.cortexPilotCursor
    if state.cortexPilot == true and type(pilot) == 'table' and finite(pilot.x) and finite(pilot.y) then
        local w, h = GetActiveScreenResolution()
        return pilot.x * w, pilot.y * h
    end
    return GetNuiCursorPosition()
end

local Pointer = {}
Pointer.__index = Pointer

function worldScreen.pointer(spec)
    return setmetatable({ spec = spec, inverse = nil, keys = {} }, Pointer)
end

function Pointer:project()
    local rw, rh = GetActiveScreenResolution()
    local spec = self.spec
    local corners = type(spec.screen) == 'function' and spec.screen() or spec.screen
    local poly = corners and worldScreen.projectQuad(corners, rw, rh)
    self.poly = poly or nil
    self.inverse = poly and worldScreen.homography(poly) or nil
    self.keys = {}
    for _, key in ipairs(spec.keys or {}) do
        local kp = worldScreen.projectQuad(key.quad, rw, rh)
        if kp then self.keys[#self.keys + 1] = { id = key.id, poly = kp, quad = key.quad } end
    end
end

function Pointer:hit(px, py)
    local u, v = worldScreen.map(self.inverse, px, py)
    if u then
        local r = self.spec.rect or { x = 0.0, y = 0.0, w = 1.0, h = 1.0 }
        local pw, ph = self.spec.width or 1, self.spec.height or 1
        return { kind = 'screen', u = u, v = v, x = math.floor((r.x + u * r.w) * pw + 0.5), y = math.floor((r.y + v * r.h) * ph + 0.5) }
    end
    for _, k in ipairs(self.keys) do
        if worldScreen.inside(k.poly, px, py) then return { kind = 'key', id = k.id, quad = k.quad } end
    end
    return nil
end

local Page = {}
Page.__index = Page
local pageSeq = 0

function worldScreen.page(spec)
    if type(spec) ~= 'table' or type(spec.url) ~= 'string' or not finite(spec.width) or not finite(spec.height) then
        return nil, 'invalid_page'
    end
    local width, height = math.floor(spec.width), math.floor(spec.height)
    if width < 1 or height < 1 then return nil, 'invalid_page' end
    pageSeq = pageSeq + 1
    local txdName = ('%s_%s'):format(spec.txd or (owner .. '_ws'), pageSeq)
    local texName = spec.tex or 'page'
    local dui = CreateDui(spec.url, width, height)
    if not dui then return nil, 'dui_failed' end
    local handle = GetDuiHandle(dui)
    if type(handle) ~= 'string' or handle == '' then
        DestroyDui(dui)
        return nil, 'dui_failed'
    end
    CreateRuntimeTextureFromDuiHandle(CreateRuntimeTxd(txdName), texName, handle)
    local p = setmetatable({ dui = dui, txd = txdName, tex = texName, width = width, height = height, ready = false, born = GetGameTimer() }, Page)
    pages[p] = true
    return p
end

function Page:send(msg)
    if not self.dui then return false end
    SendDuiMessage(self.dui, type(msg) == 'string' and msg or json.encode(msg))
    return true
end

function Page:mouse(x, y, button, down)
    if not self.dui then return end
    SendDuiMouseMove(self.dui, math.floor(x), math.floor(y))
    if button then
        if down == nil or down then SendDuiMouseDown(self.dui, button) end
        if down == nil or not down then SendDuiMouseUp(self.dui, button) end
    end
end

function Page:destroy()
    pages[self] = nil
    if self.dui then pcall(DestroyDui, self.dui) end
    self.dui, self.ready = nil, false
end

local Swap = {}
Swap.__index = Swap

function worldScreen.replace(spec)
    if type(spec) ~= 'table' or type(spec.dict) ~= 'string' or type(spec.name) ~= 'string' or type(spec.page) ~= 'table' then
        return nil, 'invalid_swap'
    end
    local hash = type(spec.model) == 'number' and spec.model or (type(spec.model) == 'string' and joaat(spec.model)) or nil
    if hash and not IsModelInCdimage(hash) then return nil, 'unknown_model' end
    local s = setmetatable({ hash = hash, dict = spec.dict, name = spec.name, hd = spec.hd, page = spec.page, applied = false, alive = true }, Swap)
    swaps[s] = true
    if hash then RequestModel(hash) end
    if s.hd then RequestStreamedTextureDict(s.hd, false) end
    CreateThread(function()
        local deadline = GetGameTimer() + (spec.timeoutMs or 120000)
        while s.alive and hash and not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(100) end
        if not s.alive then return end
        if hash and not HasModelLoaded(hash) then
            s.failed = 'model_timeout'
            return
        end
        AddReplaceTexture(s.dict, s.name, s.page.txd, s.page.tex)
        s.applied = true
        local hdDeadline = GetGameTimer() + 10000
        while s.alive and s.hd and not HasStreamedTextureDictLoaded(s.hd) and GetGameTimer() < hdDeadline do Wait(100) end
        if s.alive and s.hd and HasStreamedTextureDictLoaded(s.hd) then
            AddReplaceTexture(s.hd, s.name, s.page.txd, s.page.tex)
            s.hdApplied = true
        end
    end)
    return s
end

function Swap:release()
    if not self.alive then return end
    self.alive = false
    swaps[self] = nil
    if self.applied then pcall(RemoveReplaceTexture, self.dict, self.name) end
    if self.hdApplied then pcall(RemoveReplaceTexture, self.hd, self.name) end
    if self.hash then pcall(SetModelAsNoLongerNeeded, self.hash) end
    if self.hd then pcall(SetStreamedTextureDictAsNoLongerNeeded, self.hd) end
end

local Pool = {}
Pool.__index = Pool

function worldScreen.pool(size)
    return setmetatable({ size = math.max(1, math.floor(size or 8)), holders = {} }, Pool)
end

function Pool:slotOf(key)
    for s = 0, self.size - 1 do if self.holders[s] == key then return s end end
    return nil
end

function Pool:take(key)
    local held = self:slotOf(key)
    if held then return held end
    for s = 0, self.size - 1 do
        if self.holders[s] == nil then
            self.holders[s] = key
            return s
        end
    end
    return nil
end

function Pool:release(key)
    local s = self:slotOf(key)
    if s then self.holders[s] = nil end
    return s
end

function Pool:holder(slot) return self.holders[slot] end

function Pool:free()
    local n = 0
    for s = 0, self.size - 1 do if self.holders[s] == nil then n = n + 1 end end
    return n
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= owner and resource ~= 'cortex-lib' then return end
    for s in pairs(swaps) do pcall(Swap.release, s) end
    for p in pairs(pages) do pcall(Page.destroy, p) end
end)

return worldScreen
