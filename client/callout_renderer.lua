-- Callouts on a vehicle (or any entity): a pin on every part, a square leader
-- from each pin to a label beside it, and a block of switches. A consumer
-- describes them through imports/callouts/client.lua; this file alone turns
-- that into presentation and reads the pointer while they are up.
--
-- Everything is drawn by the game: leaders as rectangles, pins and labels
-- from the label atlas (client/callout_dui.lua), all relative to one draw
-- origin at the entity's middle. SetDrawOrigin resolves at render time with
-- the current camera, so the whole drawing stays on the entity while the
-- camera moves. Positions come from the game's projection of last frame's
-- camera; only the shape of the drawing (pins relative to the middle) is a
-- frame old, and it changes slowly. A moving entity is drawn where it will be
-- this frame (position plus velocity times frame time): scripts run before
-- physics.
--
-- While a session is up the mouse moves the game's cursor instead of the
-- camera; nothing takes NUI focus, so driving and walking stay with the
-- player. Clicks and wheel turns go to the owner's onEvent; actions,
-- permissions and server checks stay with the owner.

local L = lib._calloutLayout
local atlas = lib._calloutAtlas

local abs, floor, max, min, sin = math.abs, math.floor, math.max, math.min, math.sin

local OPEN_MS, POP_MS, SHAKE_MS = 200, 220, 320
local STATIC_ROW = 40      -- u reserved at the atlas top for the pins
local PAPER, HALO = { 240, 240, 233 }, { 11, 12, 14 }
local CANCEL_GUARD_MS = 350

local predict = GetConvarInt('cortex_lib_callouts_predict', 1) ~= 0

-- Held while the callouts are up: looking, weapons, the phone, the radio,
-- the pause menu and the arrows. Driving and walking stay with the player.
local HELD = {
    1, 2, 3, 4, 5, 6, 14, 15, 16, 17, 24, 25, 37, 68, 69, 70, 91, 92, 99, 100, 106, 114, 115, 116,
    140, 141, 142, 257, 263, 264, 81, 82, 83, 84, 85, 172, 173, 174, 175, 177, 199, 200, 237, 238,
    241, 242, 261, 262, 322, 330, 331,
}

local function resolve(...)
    for _, f in ipairs({ ... }) do if type(f) == 'function' then return f end end
end
local cursorThisFrame = resolve(SetMouseCursorThisFrame, SetMouseCursorActiveThisFrame, ShowCursorThisFrame)
local cursorStyle = resolve(SetMouseCursorStyle, SetMouseCursorSprite)
local cursorAt = resolve(SetCursorLocation)

local R = {}
local cur -- the open session
-- Set while an owner is told its session closed for another, and while
-- cortex-lib stops: a show from inside that event is refused, not lost.
local blocked = false

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    return ok and type(text) == 'string' and text or '<unprintable error>'
end

-- Screen ------------------------------------------------------------------------

-- The radar's corner, which the labels keep clear of. GTA sizes the radar
-- from the screen height and insets it by the safe zone; the room here is
-- generous (a 1080p capture with its bars measured 311 x 188 at 37, 814),
-- since HUDs restyle it.
local function radar(w, h, zone)
    if IsRadarHidden() then return nil end
    return { x0 = 0, y0 = h - zone * h - h * 0.26, x1 = zone * w + h * 0.34, y1 = h }
end

local function unitOf(w, h) return max(0.72, min(w, h) / 1080) end

-- The screen in pixels, u, the safe area and what the labels keep clear of:
-- the radar and other Cortex overlays, but the owner's own.
local function screen(owner)
    local w, h = GetActiveScreenResolution()
    local u = unitOf(w, h)
    -- The game's safe zone or Cortex's 56u, whichever is wider.
    local zone = (1.0 - GetSafeZoneSize()) * 0.5
    local mx, my = max(56 * u, zone * w), max(56 * u, zone * h)
    local reserve = atlas.reserved(w, h, owner)
    reserve[#reserve + 1] = radar(w, h, zone)
    return { w = w, h = h, u = u, safe = { l = mx, r = mx, t = my, b = my }, reserve = reserve }
end

local function rgb(hex)
    local r, g, b = tostring(hex):match('^#(%x%x)(%x%x)(%x%x)$')
    if not r then return { 143, 203, 191 } end
    return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

-- Atlas cells --------------------------------------------------------------------

local PINS = { 'idle', 'on', 'hot' }

local function staticCells()
    local cells = {}
    for i, v in ipairs(PINS) do
        cells[#cells + 1] = { key = 'pin:' .. v, k = 'pin', v = v, x = (i - 1) * (L.PIN + 2), y = 0, w = L.PIN, h = L.PIN }
    end
    return cells
end

-- The room every row of `size` keeps for its chip (u): the widest chip the
-- owner says a row can show, or any it shows now.
local function chipRoom(s, size)
    local room = s.chipRoom[size]
    if room then return room end
    local m = L.ROW[size]
    local widest = 0
    for _, text in ipairs(s.chips) do widest = max(widest, L.textWidth(text, m.chip, L.CHIP_SPACING)) end
    for _, c in ipairs(s.callouts) do
        for _, r in ipairs(c.rows) do
            if r.chip ~= '' then widest = max(widest, L.textWidth(r.chip, m.chip, L.CHIP_SPACING)) end
        end
    end
    room = math.ceil(m.gap + m.chipPadL + widest + m.chipPadR)
    s.chipRoom[size] = room
    return room
end

-- Places every cell the session can need. A row's slot fits its name and the
-- widest chip, so state changes repaint in place and nothing moves. Cells
-- include L.PAD round the box for the halo and shadow.
local function packCells(s)
    s.chipRoom = {}
    local packed = {}
    for _, c in ipairs(s.callouts) do
        for i, r in ipairs(c.rows) do
            local size = i == 1 and 'lg' or 'sm'
            local w = L.rowWidth(size, r.name) + chipRoom(s, size) + 2 * L.PAD
            local h = L.ROW[size].h + 2 * L.PAD
            packed[#packed + 1] = { key = 'row:' .. r.id .. ':n', row = r.id, size = size, w = w, h = h, minor = c.minor }
            packed[#packed + 1] = { key = 'row:' .. r.id .. ':h', row = r.id, size = size, hot = true, w = w, h = h, minor = c.minor }
        end
    end
    for _, sw in ipairs(s.switches) do
        local w = L.switchWidth(sw.text)
        for _, text in ipairs(sw.texts) do w = max(w, L.switchWidth(text)) end
        -- A refusal can flash in the switch.
        w = max(w, chipRoom(s, 'lg') - L.ROW.lg.gap) + 2 * L.PAD
        local h = L.SWITCH.h + 2 * L.PAD
        packed[#packed + 1] = { key = 'sw:' .. sw.id .. ':n', switch = sw.id, w = w, h = h }
        packed[#packed + 1] = { key = 'sw:' .. sw.id .. ':h', switch = sw.id, hot = true, w = w, h = h }
    end
    if s.title then
        local t = s.title
        local w = max(L.rowWidth('lg', t.name, t.chip), L.rowWidth('lg', t.name) + chipRoom(s, 'lg')) + 2 * L.PAD
        packed[#packed + 1] = { key = 'title', title = true, w = w, h = L.ROW.lg.h + 2 * L.PAD }
    end
    -- Rows of hover-only callouts drop out first when the atlas is full;
    -- whatever drops out is drawn as game text.
    local used = L.packAtlas(packed, atlas.W_U, atlas.H_U - STATIC_ROW)
    if not used then print(('[cortex-lib] callouts: the label atlas is full for %s; some labels use game text'):format(s.owner)) end
    while not used and #packed > 0 do
        local drop
        for i = #packed, 1, -1 do if packed[i].minor then drop = i; break end end
        table.remove(packed, drop or #packed)
        used = L.packAtlas(packed, atlas.W_U, atlas.H_U - STATIC_ROW)
    end
    local cells, byKey = staticCells(), {}
    for _, p in ipairs(packed) do
        p.y = p.y + STATIC_ROW
        cells[#cells + 1] = p
    end
    for _, c in ipairs(cells) do byKey[c.key] = c end
    s.cells, s.byKey = cells, byKey
end

-- What the session shows now: each callout's shown rows, the shown switches,
-- the title, and the page's message (each filled cell's place in the atlas,
-- padding included, and its box width rw in u). Returns false when something
-- outgrew its cell; it is drawn as game text until the cells are packed again.
local function compose(s)
    local entries, rows = {}, {}
    for _, c in ipairs(s.callouts) do
        local shown, w, h = L.shownRows(c)
        entries[#entries + 1] = { id = c.id, offset = c.offset, order = c.order, minor = c.minor, rows = shown, w = w, h = h }
        for _, r in ipairs(shown) do rows[r.id] = r end
    end
    local switches, switchById = {}, {}
    for _, sw in ipairs(s.switches) do
        if not sw.hidden then
            local e = { id = sw.id, text = sw.text, tone = sw.tone, pending = sw.pending, w = L.switchWidth(sw.text) }
            switches[#switches + 1] = e
            switchById[sw.id] = e
        end
    end
    local title
    if s.title then title = { name = s.title.name, chip = s.title.chip, w = L.rowWidth('lg', s.title.name, s.title.chip) } end

    local fits, list, filled = true, {}, {}
    local room = 2 * L.PAD
    for _, c in ipairs(s.cells) do
        local e
        if c.k == 'pin' then
            e = { k = 'pin', v = c.v }
        elseif c.row then
            local r = rows[c.row]
            if r then
                -- Its own size, not the row's place among the shown rows.
                if r.w + room > c.w then fits = false
                else e = { k = 'row', size = c.size, name = r.name, chip = r.chip, tone = r.tone, rw = r.w, hot = c.hot or nil } end
            end
        elseif c.switch then
            local sw = switchById[c.switch]
            if sw then
                if sw.w + room > c.w then fits = false
                else e = { k = 'switch', text = sw.text, tone = sw.tone, rw = sw.w, hot = c.hot or nil } end
            end
        elseif c.title and title then
            if title.w + room > c.w then fits = false
            else e = { k = 'row', size = 'lg', name = title.name, chip = title.chip, tone = 'off', rw = title.w } end
        end
        if e then
            e.x, e.y, e.w, e.h = c.x, c.y, c.w, c.h
            list[#list + 1] = e
            filled[c.key] = true
        end
    end
    s.entries, s.rows, s.shownSwitches, s.switchById, s.titleShown = entries, rows, switches, switchById, title
    s.message, s.filled = list, filled
    return fits
end

-- The structure the cells are packed for: ids, names, the texts a switch can
-- show, the chips and the title. Anything else repaints in place.
local function shapeOf(s)
    local parts = {}
    for _, c in ipairs(s.callouts) do
        parts[#parts + 1] = c.id
        for _, r in ipairs(c.rows) do parts[#parts + 1] = r.id .. '=' .. r.name end
    end
    parts[#parts + 1] = '|'
    for _, sw in ipairs(s.switches) do parts[#parts + 1] = sw.id .. '=' .. table.concat(sw.texts, '/') end
    parts[#parts + 1] = '|' .. table.concat(s.chips, '/')
    if s.title then parts[#parts + 1] = '|' .. s.title.name .. '=' .. s.title.chip end
    return table.concat(parts, '\n')
end

-- Drawing helpers ----------------------------------------------------------------

local function ease(k) return 1 - (1 - k) ^ 3 end

-- GetEntityMatrix answers forward, right, up, position.
local function matrixOf(entity)
    local f, r, up, p = GetEntityMatrix(entity)
    return { rx = r.x, ry = r.y, rz = r.z, fx = f.x, fy = f.y, fz = f.z, ux = up.x, uy = up.y, uz = up.z, px = p.x, py = p.y, pz = p.z }
end

local function projectNative(sc, x, y, z)
    local on, sx, sy = GetScreenCoordFromWorldCoord(x, y, z)
    if not on then return nil end
    return sx * sc.w, sy * sc.h
end

-- One leader: axis-aligned segments, a dark halo under a paper (or accent)
-- line at least 3u wide (CORTEX-DESIGN law 4). A corner belongs to the
-- segment arriving at it, so the halo never doubles up. `grow` draws the first
-- part of it, from the pin outward.
local function leader(path, grow, hot, alpha, d)
    local u = d.u
    local total = 0
    for i = 1, #path - 2, 2 do total = total + abs(path[i + 2] - path[i]) + abs(path[i + 3] - path[i + 1]) end
    local core = hot and 4 * u or 3 * u
    local color = hot and d.accent or PAPER
    local n = #path / 2 - 1
    for pass = 1, 2 do
        local wide = pass == 1 and 9 * u or core
        local col = pass == 1 and HALO or color
        local a = floor((pass == 1 and 128 or (hot and 255 or 235)) * alpha + 0.5)
        local left = total * grow
        for i = 1, n do
            if left <= 0 then break end
            local x1, y1, x2, y2 = path[2 * i - 1], path[2 * i], path[2 * i + 1], path[2 * i + 2]
            local len = abs(x2 - x1) + abs(y2 - y1)
            local part = len > 0 and min(1, left / len) or 1
            left = left - len
            x2, y2 = x1 + (x2 - x1) * part, y1 + (y2 - y1) * part
            local half = wide / 2
            local sx = x2 > x1 and 1 or (x2 < x1 and -1 or 0)
            local sy = y2 > y1 and 1 or (y2 < y1 and -1 or 0)
            local a0 = i > 1 and half or 0
            local a1 = (i < n and part >= 1) and half or 0
            local ax, ay = x1 + sx * a0, y1 + sy * a0
            local bx, by = x2 + sx * a1, y2 + sy * a1
            local w = sx ~= 0 and abs(bx - ax) or wide
            local h = sy ~= 0 and abs(by - ay) or wide
            if w > 0 and h > 0 then
                DrawRect(((ax + bx) / 2 - d.ox) / d.sw, ((ay + by) / 2 - d.oy) / d.sh, w / d.sw, h / d.sh, col[1], col[2], col[3], a)
            end
        end
    end
end

-- Game text when a label has no atlas cell: plain, but every part still works.
local function fallbackText(text, x, y, size, hot, alpha, d)
    SetTextFont(4)
    SetTextScale(0.0, (L.ROW[size].name * d.u / d.sh) * 1.6)
    local col = hot and d.accent or PAPER
    SetTextColour(col[1], col[2], col[3], floor(255 * alpha))
    SetTextDropShadow()
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text:upper())
    EndTextCommandDisplayText((x - d.ox) / d.sw, (y - d.oy) / d.sh)
end

-- An effect ('pop' or 'shake') still running on any of the ids.
local function effectOn(s, rows, kind, ms, now)
    for _, r in ipairs(rows) do
        local fx = s.fx[r.id]
        if fx and fx.kind == kind and now - fx.at < ms then return fx end
    end
end

-- Frame ------------------------------------------------------------------------------

-- Lays out and draws one frame. input: { mx, my } pixels for the mouse,
-- { stick = { x, y } } for a controller, { step = { dx, dy } } for an arrow
-- key, or {} to keep the current pick. Returns what is picked: { id, row,
-- target } for a callout row, { switch, target } for a switch, or nil; and
-- the entity's middle on screen.
local function draw(s, now, input)
    local sc = screen(s.owner)
    local u = sc.u
    s.u = u
    local reduced = atlas.reducedMotion()
    local k = reduced and 1 or min(1, (now - s.openedAt) / OPEN_MS)
    local grow = ease(k)
    local labelK = reduced and 1 or ease(max(0, (k - 0.35) / 0.65))

    local ready = atlas.ready(now)
    if ready and s.dirty then
        if atlas.publish(s.message, now, s.moved) then s.moved, s.dirty = false, false end
    end
    atlas.tick(now)
    local labelsOk = ready and not s.moved and atlas.revealed(now)
    local pinsOk = ready and atlas.painted(now)
    local fallback = atlas.failed()

    -- Where things are, from last frame's camera.
    local entity = s.entity
    local m = matrixOf(entity)
    local dims = s.dims
    local mid = { x = (dims.min.x + dims.max.x) / 2, y = (dims.min.y + dims.max.y) / 2, z = (dims.min.z + dims.max.z) / 2 }
    local wx, wy, wz = L.toWorld(m, mid)
    local ox, oy = projectNative(sc, wx, wy, wz)
    local cam = L.camera(GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2), GetFinalRenderedCamFov(), GetAspectRatio(false))
    local box = L.screenBox(cam, m, dims, sc.w, sc.h)

    local items, pins, bounds, byId = L.items(s.entries, function(p) return projectNative(sc, L.toWorld(m, p)) end, u)
    box = box or bounds
    local blockList, block = L.block(s.titleShown, s.shownSwitches, u)

    -- With no pin on screen the switches sit at the bottom of the screen.
    -- Without the entity's middle (first person) the drawing is placed from
    -- last frame's projection instead of pinned at render time.
    local layout
    if box and #items > 0 then
        layout = L.layout(sc, box, items, block, s.prev, now)
    else
        layout = { items = {}, hover = {} }
    end
    if block and not layout.block then
        layout.block = { x = (sc.w - block.w) / 2, y = sc.h - sc.safe.b - block.h - 90 * u, w = block.w, h = block.h }
        -- Screen-fixed: drawn without the origin.
        if #items == 0 then ox, oy = nil, nil end
    end
    -- A hover-only label under the pointer stays up beside its pin.
    if s.hot and s.hot.id and layout.hover[s.hot.id] and byId[s.hot.id] then
        layout.items[s.hot.id] = L.hoverPlace(sc, byId[s.hot.id])
    end
    s.prev, s.layout = layout, layout

    -- What is picked.
    local switches = {}
    if layout.block then
        for _, b in ipairs(blockList) do
            if b.switch then
                switches[#switches + 1] = { id = b.switch.id, x = layout.block.x + b.x, y = layout.block.y + b.y, w = b.w, h = b.h }
            end
        end
    end
    s.switchRects = switches
    local function targets(skip)
        local list = {}
        for id, p in pairs(layout.items) do
            if id ~= skip then list[#list + 1] = { id = id, x = p.x + p.w / 2, y = p.y + p.h / 2 } end
        end
        -- Pins whose label shows on hover are picked at the pin.
        for id in pairs(layout.hover) do
            local it = byId[id]
            if it and id ~= skip and not layout.items[id] then list[#list + 1] = { id = id, x = it.px, y = it.py } end
        end
        for _, sw in ipairs(switches) do
            if 'sw:' .. sw.id ~= skip then list[#list + 1] = { id = 'sw:' .. sw.id, x = sw.x + sw.w / 2, y = sw.y + sw.h / 2 } end
        end
        return list
    end
    local function picked(id)
        if not id then return nil end
        local swId = id:match('^sw:(.+)$')
        return swId and { switch = swId } or { id = id, row = 1 }
    end
    local hit = s.hot
    if input.mx then
        local heights = {}
        for _, it in ipairs(items) do
            local list = {}
            for _, r in ipairs(it.rows) do list[#list + 1] = L.ROW[r.size].h * u end
            heights[it.id] = list
        end
        hit = L.hit(layout, heights, pins, switches, input.mx, input.my, u)
    elseif input.stick then
        hit = picked(L.aim(ox or sc.w / 2, oy or sc.h / 2, input.stick.x, input.stick.y, targets())) or s.hot
    elseif input.step then
        local fx, fy, skip
        if s.hot and s.hot.id and layout.items[s.hot.id] then
            local p = layout.items[s.hot.id]
            fx, fy, skip = p.x + p.w / 2, p.y + p.h / 2, s.hot.id
        elseif s.hot and s.hot.switch then
            for _, sw in ipairs(switches) do
                if sw.id == s.hot.switch then fx, fy, skip = sw.x + sw.w / 2, sw.y + sw.h / 2, 'sw:' .. sw.id end
            end
        end
        fx, fy = fx or ox or sc.w / 2, fy or oy or sc.h / 2
        hit = picked(L.aim(fx, fy, input.step[1], input.step[2], targets(skip))) or s.hot
    end
    -- A pick that went away with the layout is dropped; a kept one names
    -- what it works this frame: the row or the switch.
    if hit and hit.id and not (byId[hit.id] and (layout.items[hit.id] or layout.hover[hit.id])) then hit = nil end
    if hit and hit.switch and not s.switchById[hit.switch] then hit = nil end
    if hit and hit.id then
        local rows = byId[hit.id].rows
        hit.target = (rows[hit.row or 1] or rows[1]).id
        hit.rows = rows
    elseif hit then
        hit.target = hit.switch
    end
    s.hot = hit

    -- Drawing ------------------------------------------------------------------------
    local d = { u = u, sw = sc.w, sh = sc.h, ox = ox or 0, oy = oy or 0, accent = rgb(atlas.accent()) }
    if ox then
        local px, py, pz = wx, wy, wz
        if predict then
            local v = GetEntityVelocity(entity)
            local dt = GetFrameTime()
            px, py, pz = px + v.x * dt, py + v.y * dt, pz + v.z * dt
        end
        SetDrawOrigin(px, py, pz, 0)
    end
    local hotId = hit and hit.id

    local function shakeOf(rows)
        local fx = not reduced and effectOn(s, rows, 'shake', SHAKE_MS, now)
        if not fx then return 0 end
        return 6 * u * sin((now - fx.at) / 22) * (1 - (now - fx.at) / SHAKE_MS)
    end
    local function pulse(pending)
        if reduced or not pending then return 1 end
        return 0.65 + 0.35 * abs(sin(now / 110))
    end

    -- Leaders under pins and labels.
    for id, p in pairs(layout.items) do
        local it = byId[id]
        if p.path and it then
            local dim = #it.rows == 1 and it.rows[1].tone == 'no'
            leader(p.path, grow, hotId == id, dim and 0.5 or 1.0, d)
        end
    end

    -- Pins.
    for _, it in ipairs(items) do
        local scale = 0.6 + 0.4 * grow
        local alpha = min(1, k * 2)
        local pending = false
        for _, r in ipairs(it.rows) do if r.pending then pending = true end end
        if pending and not reduced then scale = scale * (1.0 + 0.18 * abs(sin(now / 110))) end
        local fx = not reduced and effectOn(s, it.rows, 'pop', POP_MS, now)
        if fx then scale = scale * (1.0 + 0.4 * (1 - (now - fx.at) / POP_MS)) end
        local first = it.rows[1]
        if layout.hover[it.id] and hotId ~= it.id then alpha = alpha * 0.8 end
        if #it.rows == 1 and first.tone == 'no' then alpha = alpha * 0.55 end
        if pinsOk then
            local variant = hotId == it.id and 'hot' or ((first.tone == 'on' or first.tone == 'you') and 'on' or 'idle')
            local size = L.PIN * u * scale
            atlas.draw(s.byKey['pin:' .. variant], it.px - d.ox - size / 2, it.py - d.oy - size / 2, scale, u, sc.w, sc.h, alpha)
        else
            local dot = 9 * u * scale
            local col = hotId == it.id and d.accent or PAPER
            DrawRect((it.px - d.ox) / sc.w, (it.py - d.oy) / sc.h, dot / sc.w, dot / sc.h, col[1], col[2], col[3], floor(255 * alpha))
        end
    end

    -- Labels, the hover label last so it sits over the rest. A cell's box
    -- sits `pad` inside it; a row without a filled cell is game text.
    local pad = L.PAD * u
    for pass = 1, 2 do
        for id, p in pairs(layout.items) do
            local it = byId[id]
            if it and (p.side == 'pin') == (pass == 2) then
                local slide = (1 - labelK) * 10 * u
                local sx = (p.side == 'left' and slide or (p.side == 'right' and -slide or 0)) + shakeOf(it.rows)
                local sy = p.side == 'top' and slide or 0
                local y = p.y
                for i, r in ipairs(it.rows) do
                    local rw = r.w * u
                    local x = p.side == 'left' and (p.x + p.w - rw) or p.x
                    local isHot = hotId == id and (hit.row == i or (i == 1 and (hit.row or 1) > #it.rows))
                    local alpha = labelK * pulse(r.pending)
                    local key = 'row:' .. r.id .. (isHot and ':h' or ':n')
                    local cell = s.filled[key] and s.byKey[key]
                    if labelsOk and cell then
                        atlas.draw(cell, x + sx - pad - d.ox, y + sy - pad - d.oy, 1.0, u, sc.w, sc.h, alpha)
                    elseif fallback or labelsOk then
                        local text = r.chip ~= '' and (r.name .. '  ' .. r.chip) or r.name
                        fallbackText(text, x + sx + L.ROW[r.size].padL * u, y + sy, r.size, isHot, alpha, d)
                    end
                    y = y + (L.ROW[r.size].h + L.ROW_GAP) * u
                end
            end
        end
    end

    -- Switches.
    if layout.block then
        local bx, by = layout.block.x, layout.block.y
        for _, b in ipairs(blockList) do
            local sw = b.switch
            local isHot = sw and hit and hit.switch == sw.id
            local key = b.title and 'title' or ('sw:' .. sw.id .. (isHot and ':h' or ':n'))
            local cell = s.filled[key] and s.byKey[key]
            local shake = sw and shakeOf({ sw }) or 0
            local alpha = labelK * (sw and pulse(sw.pending) or 1)
            if labelsOk and cell then
                atlas.draw(cell, bx + b.x + shake - pad - d.ox, by + b.y - pad - d.oy, 1.0, u, sc.w, sc.h, alpha)
            elseif fallback or labelsOk then
                local text = b.title and s.titleShown.name or sw.text
                fallbackText(text, bx + b.x + shake, by + b.y, 'sm', isHot, alpha, d)
            end
        end
    end

    if ox then ClearDrawOrigin() end

    -- The pointer is the game's own cursor: a hand over anything that acts.
    if input.mx and cursorThisFrame then
        cursorThisFrame()
        if cursorStyle then cursorStyle(hit and 3 or 1) end
    end
    return hit, ox, oy
end

-- Session ---------------------------------------------------------------------------

local function emit(s, event)
    if not s.onEvent then return end
    local ok, err = pcall(s.onEvent, event)
    if not ok then print(('^1[cortex-lib]^7 callouts: onEvent of %s failed: %s'):format(s.owner, safeErrorText(err))) end
end

-- Closes the session; `reason` tells the owner it was closed for it.
local function finish(s, reason)
    if cur ~= s then return end
    cur = nil
    if reason then emit(s, { type = 'closed', reason = reason }) end
end

-- Esc and Backspace close the callouts, not the pause menu behind them.
local function guardPause()
    local untilAt = GetGameTimer() + CANCEL_GUARD_MS
    CreateThread(function()
        while GetGameTimer() < untilAt do
            DisableControlAction(0, 199, true); DisableControlAction(0, 200, true); DisableControlAction(0, 322, true)
            Wait(0)
        end
    end)
end

local function pressed(...)
    for _, c in ipairs({ ... }) do if IsDisabledControlJustPressed(0, c) then return true end end
    return false
end

-- The pointer this frame, as draw() takes it.
local function readInput(s)
    if not IsUsingKeyboard(0) then
        local x, y = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
        return (x * x + y * y > 0.2) and { stick = { x = x, y = y } } or {}
    end
    local step
    if pressed(172) then step = { 0, -1 } elseif pressed(173) then step = { 0, 1 }
    elseif pressed(174) then step = { -1, 0 } elseif pressed(175) then step = { 1, 0 } end
    if step then
        s.arrows = true
        return { keyboard = true, step = step }
    end
    local mx, my = GetDisabledControlNormal(0, 239), GetDisabledControlNormal(0, 240)
    local input
    -- The arrows keep their pick until the mouse moves.
    if s.arrows and s.lastMouse and abs(mx - s.lastMouse[1]) + abs(my - s.lastMouse[2]) < 0.002 then
        input = { keyboard = true }
    else
        s.arrows = false
        local w, h = GetActiveScreenResolution()
        input = { keyboard = true, mx = mx * w, my = my * h }
    end
    s.lastMouse = { mx, my }
    return input
end

-- Puts the pointer at (x, y) pixels.
local function placeCursor(x, y)
    if not (cursorAt and x and y) then return end
    local w, h = GetActiveScreenResolution()
    cursorAt(x / w, y / h)
end

local function rowIds(rows)
    local list = {}
    for i, r in ipairs(rows) do list[i] = r.id end
    return list
end

-- One frame of the session.
local function frame(s)
    for i = 1, #HELD do DisableControlAction(0, HELD[i], true) end
    if not DoesEntityExist(s.entity) or (s.model and GetEntityModel(s.entity) ~= s.model) then return finish(s, 'entity') end
    if IsPauseMenuActive() or IsNuiFocused() then return finish(s, 'focus') end
    local now = GetGameTimer()

    local input = readInput(s)
    local hit, ox, oy = draw(s, now, input)
    if not s.cursorPlaced and input.keyboard and ox then
        s.cursorPlaced = true
        placeCursor(ox, oy)
    end

    if pressed(24, 237, 201) and hit and hit.target then
        emit(s, { type = 'select', id = hit.target, callout = hit.id, switch = hit.switch ~= nil })
        if cur ~= s then return end
    end
    if hit and hit.id then
        local delta = pressed(241) and -1 or (pressed(242) and 1 or nil)
        if delta then
            emit(s, { type = 'wheel', id = hit.target, callout = hit.id, rows = rowIds(hit.rows), delta = delta })
            if cur ~= s then return end
        end
    end
    if pressed(25, 238, 177, 200, 322) then
        guardPause()
        finish(s, 'cancel')
    end
end

local function loop(s)
    CreateThread(function()
        while cur == s do
            -- An error on some odd entity closes the session instead of leaving pins on screen.
            local ok, err = pcall(frame, s)
            if not ok then
                print(('^1[cortex-lib]^7 callouts: closed after an error: %s'):format(safeErrorText(err)))
                finish(s, 'error')
                break
            end
            Wait(0)
        end
    end)
end

local function modelBounds(entity)
    local mn, mx = GetModelDimensions(GetEntityModel(entity))
    return { min = { x = mn.x, y = mn.y, z = mn.z }, max = { x = mx.x, y = mx.y, z = mx.z } }
end

-- Opens or updates `owner`'s callouts from validated data
-- (imports/callouts/client.lua). The same owner on the same entity updates
-- in place: nothing animates in again. Another owner's session closes.
function R.show(owner, data)
    if blocked then return false, 'busy' end
    local now = GetGameTimer()
    local s = cur
    local fresh = not (s and s.owner == owner and s.entity == data.entity)
    -- Checked first: a refused show leaves the open session alone.
    if fresh and not DoesEntityExist(data.entity) then return false, 'invalid_entity' end
    if s and s.owner ~= owner then
        blocked = true
        finish(s, 'replaced')
        blocked = false
    elseif s and fresh then
        cur = nil
    end
    if fresh then s = { owner = owner, entity = data.entity, openedAt = now, fx = {} } end
    s.model = data.model
    s.onEvent = data.onEvent or s.onEvent
    s.callouts, s.switches, s.title, s.chips = data.callouts, data.switches, data.title, data.chips
    s.dims = data.bounds or s.dims or modelBounds(data.entity)
    local shape = shapeOf(s)
    if fresh then
        local w, h = GetActiveScreenResolution()
        atlas.ensure(unitOf(w, h))
    end
    if fresh or shape ~= s.shape then
        s.shape = shape
        packCells(s)
        s.moved = true
    end
    if not compose(s) then
        packCells(s)
        s.moved = true
        compose(s)
    end
    s.dirty = true
    if fresh then
        cur = s
        loop(s)
    end
    return true
end

function R.hide(owner)
    local s = cur
    if not s or s.owner ~= owner then return false end
    cur = nil
    return true
end

function R.isOpen(owner)
    return cur ~= nil and cur.owner == owner
end

-- Feedback on a row or switch id: 'pop' when done, 'shake' when refused.
function R.effect(owner, id, kind)
    local s = cur
    if not s or s.owner ~= owner then return false end
    s.fx[id] = { kind = kind, at = GetGameTimer() }
    return true
end

-- What is up for `owner`: the pick, and where labels and switches sit on
-- screen (pixel centres), for tooling and tests.
function R.state(owner)
    local s = cur
    if not s or s.owner ~= owner then return { open = false } end
    local labels, switches, hover = {}, {}, {}
    local u = s.u or 1
    if s.layout then
        for id, p in pairs(s.layout.items) do labels[id] = { x = p.x + p.w / 2, y = p.y + L.ROW.lg.h * u / 2, side = p.side } end
        for id in pairs(s.layout.hover) do hover[#hover + 1] = id end
        table.sort(hover)
    end
    for _, r in ipairs(s.switchRects or {}) do switches[r.id] = { x = r.x + r.w / 2, y = r.y + r.h / 2 } end
    local hot = s.hot and { id = s.hot.target, callout = s.hot.id, switch = s.hot.switch ~= nil } or nil
    local w, h = GetActiveScreenResolution()
    return { open = true, hot = hot, labels = labels, switches = switches, hover = hover, screen = { width = w, height = h } }
end

-- Starts the label atlas and paints the pins ahead of the first session, so
-- the first one shows everything at once. Owners call it once at start.
local preparing = false
function R.prepare()
    if preparing then return true end
    preparing = true
    CreateThread(function()
        local w, h = GetActiveScreenResolution()
        if not atlas.ensure(unitOf(w, h)) then return end
        local deadline = GetGameTimer() + 10000
        while GetGameTimer() < deadline and not atlas.ready(GetGameTimer()) and not atlas.failed() do Wait(200) end
        if cur or not atlas.ready(GetGameTimer()) then return end
        local cells = {}
        for _, c in ipairs(staticCells()) do cells[#cells + 1] = { k = 'pin', v = c.v, x = c.x, y = c.y, w = c.w, h = c.h } end
        atlas.publish(cells, GetGameTimer(), false)
    end)
    return true
end

-- A new accent or motion preference repaints the open session.
atlas.onProfile = function()
    if cur then cur.dirty = true end
end

AddEventHandler('onClientResourceStop', function(resource)
    local s = cur
    if not s then return end
    if resource == GetCurrentResourceName() then
        -- The owner keeps running: tell it, so a restart leaves nothing stale.
        blocked = true
        finish(s, 'stopped')
    elseif s.owner == resource then
        cur = nil
    end
end)

lib._calloutRenderer = R
