-- The callout label atlas: one transparent DUI page (ui/callouts.html) the
-- game draws pieces of. Labels, chips, switches and pins are painted into
-- cells of it; client/callout_renderer.lua draws each cell where it belongs
-- with SetDrawOrigin, which the game resolves at render time with the current
-- camera, so nothing trails the vehicle the way a NUI element placed from
-- last frame's projection does.
--
-- Lua owns the cell positions (client/callout_layout.lua packs them) and
-- sends the whole content, numbered by revision, only when it changes. The
-- page reports each revision once painted; content in new places is drawn
-- only after that (at most REVEAL_MS from a page that never reports).
--
-- Renderer-private: client/callout_renderer.lua drives it.

local Atlas = {}

local W_U, H_U = 1280, 1280         -- atlas size in u
local MAX_EDGE = 3072               -- texture edge cap in pixels
local AVAILABLE_TIMEOUT_MS = 8000
local REVEAL_MS = 300
local RESEND_MS = 250               -- first resend; each later one waits twice as long
local RESEND_MAX_MS = 4000
local TXD_NAME = 'cortex_lib_callouts'

local resourceName = GetCurrentResourceName()
local URL = 'nui://' .. resourceName .. '/ui/callouts.html?resource=' .. resourceName .. '&dui=%d'

Atlas.W_U, Atlas.H_U = W_U, H_U

local txd
local serial = 0
local dui -- { serial, object, texture, r, w, h, createdAt, availableAt, painted, sent, sentAt, encoded, failed, resends }
local revision, lastContent = 0, nil
local revealRevision, revealAt = 0, 0
local profile = { accent = '#8fcbbf', motion = 'system' }
local layout = lib._calloutLayout

-- Read once: natives do not appear later.
local SUPPORTED = type(CreateDui) == 'function' and type(CreateRuntimeTxd) == 'function'
    and type(CreateRuntimeTextureFromDuiHandle) == 'function' and type(DrawSpriteUv) == 'function'

-- Pixels per u for a screen unit, within the edge cap.
local function renderScale(u)
    return math.min(u, MAX_EDGE / W_U, MAX_EDGE / H_U)
end

local function destroy()
    if dui and dui.object then DestroyDui(dui.object) end
    dui = nil
end

-- Starts the page for screen unit u; a new size replaces the old page.
function Atlas.ensure(u)
    if not SUPPORTED then return false end
    local r = renderScale(u)
    if dui and math.abs(dui.r - r) < 0.001 then return not dui.failed end
    destroy()
    serial = serial + 1
    local w, h = math.floor(W_U * r + 0.5), math.floor(H_U * r + 0.5)
    local object = CreateDui(URL:format(serial), w, h)
    if not object then
        print('[cortex-lib] callouts: the label atlas could not start (CreateDui failed); labels use game text')
        -- Kept as failed at this size, so it is not retried every session.
        dui = { serial = serial, r = r, failed = true }
        return false
    end
    dui = { serial = serial, object = object, texture = 'atlas' .. serial, r = r, w = w, h = h,
        createdAt = GetGameTimer(), painted = 0, sent = 0, sentAt = 0 }
    lastContent = nil
    return true
end

-- True once the texture exists. Called every frame the callouts are up.
function Atlas.ready(now)
    local d = dui
    if not d or d.failed then return false end
    if d.availableAt then return true end
    if not IsDuiAvailable(d.object) then
        if now - d.createdAt > AVAILABLE_TIMEOUT_MS then
            d.failed = true
            print('[cortex-lib] callouts: the label atlas did not load; labels use game text')
        end
        return false
    end
    txd = txd or CreateRuntimeTxd(TXD_NAME)
    -- The native returns a pointer: nil or 0 when it failed.
    local texture = CreateRuntimeTextureFromDuiHandle(txd, d.texture, GetDuiHandle(d.object))
    if not texture or texture == 0 then
        d.failed = true
        print('[cortex-lib] callouts: the label atlas texture failed; labels use game text')
        return false
    end
    d.availableAt = now
    d.sentAt = 0
    return true
end

-- Labels fall back to game text: the natives are missing or the page failed.
function Atlas.failed() return not SUPPORTED or (dui ~= nil and dui.failed == true) end

-- The sizes the page paints with, from the same table the layout measures with.
local metricsCache
local function metrics()
    if metricsCache then return metricsCache end
    local C = layout
    metricsCache = { row = C.ROW, switch = C.SWITCH, pad = C.PAD, pin = C.PIN,
        nameSpacing = C.NAME_SPACING, chipSpacing = C.CHIP_SPACING }
    return metricsCache
end

local function deliver(now)
    local d = dui
    if not d or not d.availableAt or not d.encoded then return end
    d.sentAt = now
    SendDuiMessage(d.object, d.encoded)
end

-- Sends the cells if they differ from the last ones sent. `moved`: cells sit
-- in new places, so nothing is drawn from them until this revision is painted.
function Atlas.publish(cells, now, moved)
    local d = dui
    if not d or not d.availableAt then return false end
    local content = json.encode({ cells, profile.accent, profile.motion, d.r })
    if content == lastContent then return true end
    lastContent = content
    revision = revision + 1
    d.encoded = json.encode({
        action = 'callouts:atlas',
        data = { revision = revision, r = d.r, accent = profile.accent, motion = profile.motion, cells = cells, metrics = metrics() },
    })
    d.sent = revision
    d.resends = 0
    d.firstAt = d.firstAt or now
    if moved then revealRevision, revealAt = revision, now + REVEAL_MS end
    deliver(now)
    return true
end

-- Resends the last cells while the page has not reported painting them
-- (messages sent before it listens are lost), backing off so a page whose
-- reports never arrive costs one message every few seconds.
function Atlas.tick(now)
    local d = dui
    if not (d and d.encoded and d.painted < d.sent) then return end
    local wait = math.min(RESEND_MS * 2 ^ (d.resends or 0), RESEND_MAX_MS)
    if now - d.sentAt >= wait then
        d.resends = (d.resends or 0) + 1
        deliver(now)
    end
end

-- Whether cells moved by the last `moved` publish are on the texture yet.
function Atlas.revealed(now)
    local d = dui
    if not d or not d.availableAt then return false end
    return d.painted >= revealRevision or now >= revealAt
end

-- Whether anything has been painted: the pins never move, so any revision has them.
function Atlas.painted(now)
    local d = dui
    if not d or not d.availableAt or not d.firstAt then return false end
    return d.painted > 0 or now - d.firstAt >= REVEAL_MS
end

-- Draws cell { x, y, w, h } (u) with its top-left at (left, top) pixels from
-- the draw origin, `scale` times its size. Screen size sw, sh.
function Atlas.draw(cell, left, top, scale, u, sw, sh, alpha)
    local d = dui
    if not d or not d.availableAt then return end
    local r = d.r
    local pw, ph = cell.w * u * scale, cell.h * u * scale
    local u1, v1 = cell.x * r / d.w, cell.y * r / d.h
    local u2, v2 = (cell.x + cell.w) * r / d.w, (cell.y + cell.h) * r / d.h
    DrawSpriteUv(TXD_NAME, d.texture, (left + pw * 0.5) / sw, (top + ph * 0.5) / sh, pw / sw, ph / sh,
        u1, v1, u2, v2, 0.0, 255, 255, 255, math.floor(255 * (alpha or 1.0) + 0.5))
end

-- The shared accent and motion preference.
function Atlas.accent() return profile.accent end
function Atlas.reducedMotion() return profile.motion == 'reduced' end

-- Where other Cortex overlays sit (presentation surfaces, NUI pixels of
-- `viewport`), so the labels can keep clear of them.
local surfaces, viewport = {}, nil
local function finite(n) return type(n) == 'number' and n == n and math.abs(n) < 100000 end

-- The surfaces as { x0, y0, x1, y1 } pixel rects of a sw x sh screen, but
-- those of `skipOwner` (the resource showing the callouts). Anything over a
-- quarter of the screen is a page, not a corner to avoid.
function Atlas.reserved(sw, sh, skipOwner)
    local list = {}
    local kx = viewport and sw / viewport.width or 1
    local ky = viewport and sh / viewport.height or 1
    for _, r in ipairs(surfaces) do
        if r.owner ~= skipOwner then
            local w, h = r.w * kx, r.h * ky
            if w * h < sw * sh * 0.25 then list[#list + 1] = { x0 = r.x * kx, y0 = r.y * ky, x1 = r.x * kx + w, y1 = r.y * ky + h } end
        end
    end
    return list
end

local function readSurfaces(data)
    local v = data.viewport
    if type(v) == 'table' and finite(v.width) and finite(v.height) and v.width > 0 and v.height > 0 then viewport = v end
    if type(data.surfaces) ~= 'table' then return end
    local list = {}
    for _, r in ipairs(data.surfaces) do
        if type(r) == 'table' and finite(r.x) and finite(r.y) and finite(r.width) and finite(r.height)
            and r.width > 0 and r.height > 0 and #list < 64 then
            list[#list + 1] = { x = r.x, y = r.y, w = r.width, h = r.height, owner = r.owner }
        end
    end
    surfaces = list
end

local function readProfile(data)
    if type(data) ~= 'table' then return end
    readSurfaces(data)
    local p = data.profile
    if type(p) ~= 'table' then return end
    local accent, motion = profile.accent, profile.motion
    if type(p.accent) == 'string' and p.accent:match('^#%x%x%x%x%x%x$') then accent = p.accent:lower() end
    if p.motion == 'reduced' or p.motion == 'full' or p.motion == 'system' then motion = p.motion end
    if accent ~= profile.accent or motion ~= profile.motion then
        profile.accent, profile.motion = accent, motion
        -- The next publish resends.
        lastContent = nil
        if Atlas.onProfile then Atlas.onProfile() end
    end
end
AddEventHandler('cortex-lib:presentation', readProfile)
CreateThread(function()
    local ok, data = pcall(function() return exports[resourceName]:getPresentation() end)
    if ok then readProfile(data) end
end)

-- From ui/callouts.js: { dui, revision } when it starts listening (0) and
-- after each revision reaches a frame.
RegisterNUICallback('calloutsPainted', function(data, cb)
    local d = dui
    local id = type(data) == 'table' and tonumber(data.dui) or nil
    local painted = type(data) == 'table' and tonumber(data.revision) or nil
    if d and id == d.serial and painted and painted % 1 == 0 then
        if painted == 0 then d.sentAt, d.resends = 0, 0 end
        if painted > d.painted and painted <= d.sent then d.painted = painted end
    end
    cb({ ok = true })
end)

AddEventHandler('onClientResourceStop', function(name)
    if name == resourceName then destroy() end
end)

lib._calloutAtlas = Atlas
