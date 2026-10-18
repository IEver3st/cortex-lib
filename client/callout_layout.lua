-- Callouts, the pure part: label metrics and text measurement, projection
-- helpers, the layout of labels round a vehicle (columns beside it, a row
-- above it), square leaders routed so none cross, pin merging, picking and
-- atlas packing. No natives: client/callout_renderer.lua feeds it each frame,
-- and the specs load it on their own.
--
-- Screen work is in pixels with y down. u is the Cortex unit: 1px at 1080p.
local C = {}

local floor, max, min, abs, sqrt = math.floor, math.max, math.min, math.abs, math.sqrt

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Type ------------------------------------------------------------------------

-- Advance widths of the display face (Barlow Condensed ExtraBold, 1/1000 em),
-- read from ui/cortex-display.woff2. The atlas page (ui/callouts.js) turns kerning
-- off, so a run is exactly its advances plus letter-spacing after each glyph.
local ADV = {
    [32] = 200, [33] = 289, [34] = 385, [35] = 626, [36] = 454, [37] = 761, [38] = 624, [39] = 188,
    [40] = 343, [41] = 343, [42] = 362, [43] = 437, [44] = 223, [45] = 337, [46] = 235, [47] = 444,
    [48] = 456, [49] = 294, [50] = 451, [51] = 446, [52] = 508, [53] = 450, [54] = 451, [55] = 422,
    [56] = 446, [57] = 446, [58] = 298, [59] = 246, [60] = 437, [61] = 437, [62] = 437, [63] = 462,
    [64] = 760, [65] = 508, [66] = 477, [67] = 470, [68] = 480, [69] = 441, [70] = 427, [71] = 473,
    [72] = 483, [73] = 235, [74] = 462, [75] = 505, [76] = 437, [77] = 558, [78] = 522, [79] = 479,
    [80] = 474, [81] = 467, [82] = 481, [83] = 454, [84] = 485, [85] = 480, [86] = 506, [87] = 707,
    [88] = 490, [89] = 492, [90] = 419, [91] = 360, [92] = 444, [93] = 360, [94] = 432, [95] = 437,
    [96] = 234, [123] = 370, [124] = 201, [125] = 370, [126] = 500,
    [192] = 508, [193] = 508, [194] = 508, [195] = 508, [196] = 508, [197] = 508, [198] = 775, [199] = 470,
    [200] = 441, [201] = 441, [202] = 441, [203] = 441, [204] = 235, [205] = 235, [206] = 235, [207] = 235,
    [208] = 506, [209] = 522, [210] = 479, [211] = 479, [212] = 479, [213] = 479, [214] = 479, [215] = 409,
    [216] = 517, [217] = 480, [218] = 480, [219] = 480, [220] = 480, [221] = 492, [222] = 473,
}
local AVG = 480

-- Labels are uppercase: a-z and the accented lower case map onto the capitals.
local function upper(cp)
    if (cp >= 97 and cp <= 122) or (cp >= 224 and cp <= 254 and cp ~= 247) then return cp - 32 end
    return cp
end

-- Width in pixels of text set in the display face at `size` px with
-- letter-spacing `spacing` em. Text the face lacks is measured at the average.
function C.textWidth(text, size, spacing)
    text = tostring(text or '')
    local total, n = 0, 0
    local ok = pcall(function()
        for _, cp in utf8.codes(text) do
            total = total + (ADV[upper(cp)] or AVG)
            n = n + 1
        end
    end)
    if not ok then total, n = #text * AVG, #text end
    return (total / 1000 + n * (spacing or 0)) * size
end

-- A label row: a name and an optional verb chip (CORTEX-DESIGN: slip tag).
-- Sizes in u; the atlas page (ui/callouts.js) is sent the same numbers.
C.ROW = {
    lg = { name = 25, chip = 16, padL = 11, padR = 10, chipPadL = 8, chipPadR = 7, gap = 10, h = 36 },
    sm = { name = 20, chip = 14, padL = 9, padR = 8, chipPadL = 7, chipPadR = 6, gap = 10, h = 27 },
}
C.NAME_SPACING, C.CHIP_SPACING = 0.02, 0.04
-- Every atlas cell has this margin round its box, so the text halo and the
-- paper flip's drop shadow are never cut off at the cell edge.
C.PAD = 10
C.SWITCH = { text = 16, padL = 10, padR = 9, h = 29 }
C.PIN = 36 -- pin cell edge; the hot pin with its rings is 32

-- Width of a row in u.
function C.rowWidth(size, name, chip)
    local s = C.ROW[size] or C.ROW.lg
    local w = s.padL + C.textWidth(name, s.name, C.NAME_SPACING) + s.padR
    if chip and chip ~= '' then
        w = w + s.gap + s.chipPadL + C.textWidth(chip, s.chip, C.CHIP_SPACING) + s.chipPadR
    end
    return math.ceil(w)
end

function C.switchWidth(text)
    local s = C.SWITCH
    return math.ceil(s.padL + C.textWidth(text, s.text, C.CHIP_SPACING) + s.padR)
end

-- Projection ----------------------------------------------------------------------

-- A camera from position, rotation (degrees, GTA order 2), vertical field of
-- view (degrees) and aspect (width / height). Columns of R = Rz Rx Ry are its
-- right, forward and up.
function C.camera(pos, rot, fov, aspect)
    local a, b, c = math.rad(rot.x), math.rad(rot.y), math.rad(rot.z)
    local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    return {
        x = pos.x, y = pos.y, z = pos.z,
        rx = cc * cb - sc * sa * sb, ry = sc * cb + cc * sa * sb, rz = -ca * sb,
        fx = -sc * ca, fy = cc * ca, fz = sa,
        ux = cc * sb + sc * sa * cb, uy = sc * sb - cc * sa * cb, uz = ca * cb,
        tanV = math.tan(math.rad(fov) * 0.5), aspect = aspect,
    }
end

-- Screen position (0-1, y down) and depth of a world point. Depth <= 0 is
-- behind the camera.
function C.project(cam, x, y, z)
    local dx, dy, dz = x - cam.x, y - cam.y, z - cam.z
    local depth = dx * cam.fx + dy * cam.fy + dz * cam.fz
    if depth <= 0.05 then return nil, nil, depth end
    local sx = dx * cam.rx + dy * cam.ry + dz * cam.rz
    local sy = dx * cam.ux + dy * cam.uy + dz * cam.uz
    return 0.5 + sx / (depth * cam.tanV * cam.aspect) * 0.5, 0.5 - sy / (depth * cam.tanV) * 0.5, depth
end

-- A local point through an entity matrix (right, forward, up, position).
function C.toWorld(m, p)
    return m.px + m.rx * p.x + m.fx * p.y + m.ux * p.z,
        m.py + m.ry * p.x + m.fy * p.y + m.uy * p.z,
        m.pz + m.rz * p.x + m.fz * p.y + m.uz * p.z
end

-- The car's box on screen (pixels) from its eight model corners; nil when
-- any corner is behind the camera, which happens inside the car.
function C.screenBox(cam, m, dims, w, h)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i = 0, 7 do
        local p = {
            x = (i & 1) == 0 and dims.min.x or dims.max.x,
            y = (i & 2) == 0 and dims.min.y or dims.max.y,
            z = (i & 4) == 0 and dims.min.z or dims.max.z,
        }
        local sx, sy = C.project(cam, C.toWorld(m, p))
        if not sx then return nil end
        sx, sy = sx * w, sy * h
        if sx < x0 then x0 = sx end
        if sx > x1 then x1 = sx end
        if sy < y0 then y0 = sy end
        if sy > y1 then y1 = sy end
    end
    return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

-- Layout --------------------------------------------------------------------------

-- Packs boxes along one axis: each wants its centre at `want`, keeps `gap`
-- from its neighbours and stays within [lo, hi]. Clusters that touch share the
-- displacement (least squares), so labels stay as close to their pins as room
-- allows. list: { want, size } sorted by want; sets .at (the box's start).
local function pack(list, gap, lo, hi)
    local clusters = {}
    for i, it in ipairs(list) do
        local c = { first = i, last = i, total = it.size, sum = it.want - it.size / 2, n = 1 }
        c.start = c.sum
        clusters[#clusters + 1] = c
        while #clusters > 1 do
            local cur, prev = clusters[#clusters], clusters[#clusters - 1]
            if prev.start + prev.total + gap <= cur.start then break end
            -- Merge: each member's offset from the cluster start is fixed, so
            -- the best start is the mean of (want - size/2 - offset).
            local off = prev.total + gap
            prev.sum = prev.sum + cur.sum - off * cur.n
            prev.n = prev.n + cur.n
            prev.total = prev.total + gap + cur.total
            prev.last = cur.last
            prev.start = prev.sum / prev.n
            clusters[#clusters] = nil
        end
    end
    for _, c in ipairs(clusters) do
        local at = c.start
        for i = c.first, c.last do
            list[i].at = at
            at = at + list[i].size + gap
        end
    end
    -- Bounds, then the gaps again from both ends.
    local n = #list
    if n == 0 then return end
    for i = 1, n do
        local it = list[i]
        it.at = clamp(it.at, lo, max(lo, hi - it.size))
        if i > 1 then it.at = max(it.at, list[i - 1].at + list[i - 1].size + gap) end
    end
    if list[n].at + list[n].size > hi then
        list[n].at = max(lo, hi - list[n].size)
        for i = n - 1, 1, -1 do
            list[i].at = min(list[i].at, list[i + 1].at - gap - list[i].size)
        end
        for i = 1, n do
            if list[i].at < lo then list[i].at = lo end
            if i > 1 then list[i].at = max(list[i].at, list[i - 1].at + list[i - 1].size + gap) end
        end
    end
end
C.pack = pack

local SIDE_BAND, SIDE_KEEP = 0.3, 0.22

-- Which side of the car a pin's label goes: the columns left and right of the
-- car, or the row above it for pins in the middle of the upper car.
local function sideOf(item, box, prev)
    local cx = (box.x0 + box.x1) / 2
    local half = max((box.x1 - box.x0) / 2, 1)
    local rel = (item.px - cx) / half
    local v = (item.py - box.y0) / max(box.y1 - box.y0, 1)
    local side
    if rel < -SIDE_BAND then side = 'left'
    elseif rel > SIDE_BAND then side = 'right'
    elseif v < 0.62 then side = 'top'
    else side = rel < 0 and 'left' or 'right' end
    -- A pin near a boundary keeps the side it had, so labels do not hop.
    if prev and prev ~= side then
        if (prev == 'left' and rel < -SIDE_KEEP) or (prev == 'right' and rel > SIDE_KEEP)
            or (prev == 'top' and abs(rel) < SIDE_BAND + 0.08 and v < 0.7) then
            side = prev
        end
    end
    return side, rel
end

-- Leaders ---------------------------------------------------------------------------

-- Leaders are square, runs along and across the screen drawn as rectangles.
-- Each label tries a few routes and takes the first that crosses no other
-- leader and passes over no other pin or label. Last frame's route is tried
-- first, so labels do not flick between routes that are equally good, and
-- between full passes (every ROUTE_MS) each label keeps its route.

local LINE = 4      -- u: half a leader with its halo, the room a line takes
local PIN_R = 10    -- u: an idle pin with its ring
local LANES = 5
local NEST = 0.5    -- how far a pin's depth moves its label outward
C.ROUTE_MS = 100

-- Of the leaders whose label lies before its pin along the column (`key`:
-- where the leader meets the label), the one furthest along turns furthest
-- from the labels, and the same for those after: nested, they never cross.
-- Sets .lane, 0 nearest the labels.
local function laneOrder(before, after, key)
    table.sort(before, function(a, b) return a[key] < b[key] end)
    for i, e in ipairs(before) do e.lane = (#before - i) % LANES end
    table.sort(after, function(a, b) return a[key] > b[key] end)
    for i, e in ipairs(after) do e.lane = (#after - i) % LANES end
end

-- A route's runs as boxes reaching `r` either side of the line.
local function boxesOf(path, r)
    local list = {}
    for i = 1, #path - 2, 2 do
        local x1, y1, x2, y2 = path[i], path[i + 1], path[i + 2], path[i + 3]
        list[#list + 1] = { min(x1, x2) - r, min(y1, y2) - r, max(x1, x2) + r, max(y1, y2) + r }
    end
    return list
end

local function meets(a, b)
    return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end

-- The routes a label can take, best first. r: { side, px, py, edge, ly } for
-- a column label (edge, ly: where the leader meets it), { side = 'top', px,
-- py, ax, yb } above the car; r.rect: the label; r.lane: its nested lane.
local function routesOf(r, u, jog, lane)
    local list = {}
    local px, py, rect = r.px, r.py, r.rect
    local function add(key, ...) list[#list + 1] = { key = key, path = { ... } } end
    local function lanes(make)
        for k = 0, LANES - 1 do
            local n = ((r.lane or 0) + k) % LANES
            make(n, jog + n * lane)
        end
    end
    if r.side == 'top' then
        local ax, yb = r.ax, r.yb
        if py - yb < 6 * u then return list end
        if ax == px then add('v', px, py, px, yb); return list end
        lanes(function(n, d)
            local gy = yb + d
            if py - gy >= 6 * u then add('l' .. n, px, py, px, gy, ax, gy, ax, yb) end
        end)
        add('hv', px, py, ax, py, ax, yb)
        return list
    end
    local s = r.side == 'left' and 1 or -1 -- from the labels toward the car
    local edge, ly = r.edge, r.ly
    local outer = s == 1 and rect.x or rect.x + rect.w
    if s * (px - edge) < 6 * u then
        if s * (px - outer) > 0 then
            -- The pin is level with its label: up or down into it.
            local x = clamp(px, rect.x + 6 * u, rect.x + rect.w - 6 * u)
            local y = py > rect.y + rect.h and rect.y + rect.h or (py < rect.y and rect.y or nil)
            if y and x == px then add('u', px, py, px, y)
            elseif y then add('u', px, py, x, py, x, y) end
        else
            add('u', px, py, px, ly, outer, ly)
        end
        return list
    end
    if ly == py then add('h', px, py, edge, ly); return list end
    lanes(function(n, d)
        local gx = edge + s * d
        if s * (px - gx) >= 6 * u then add('l' .. n, px, py, gx, py, gx, ly, edge, ly) end
    end)
    add('vh', px, py, px, ly, edge, ly)
    return list
end

-- Chooses every label's route. list: route records (above) with id, order
-- and .first (route before the rest); obstacles: { id, box } pins and labels
-- a route keeps clear of, but its own. Returns how many things the routes
-- meet, and which labels met them.
local function route(list, obstacles, prevItems, u, jog, lane)
    local placed, line = {}, LINE * u
    local total, met = 0, {}
    table.sort(list, function(a, b)
        if a.first ~= b.first then return a.first end
        if a.straight ~= b.straight then return a.straight end
        return a.order < b.order
    end)
    for _, r in ipairs(list) do
        local options = routesOf(r, u, jog, lane)
        local p = prevItems[r.id]
        if p and p.route then
            for i, o in ipairs(options) do
                if o.key == p.route then table.remove(options, i); table.insert(options, 1, o); break end
            end
        end
        local best, bestCost, bestBoxes
        for _, o in ipairs(options) do
            local boxes = boxesOf(o.path, line)
            local cost = 0
            for _, b in ipairs(boxes) do
                for _, q in ipairs(placed) do if meets(b, q) then cost = cost + 1 end end
                for _, ob in ipairs(obstacles) do
                    if ob.id ~= r.id and meets(b, ob.box) then cost = cost + 1 end
                end
            end
            if not bestCost or cost < bestCost then best, bestCost, bestBoxes = o, cost, boxes end
            if cost == 0 then break end
        end
        if best then
            r.path, r.route = best.path, best.key
            if bestCost > 0 then
                total, met[r.id] = total + bestCost, true
                -- Whoever it met can make room too, by its label or its leader.
                for _, b in ipairs(bestBoxes) do
                    for _, q in ipairs(placed) do if meets(b, q) then met[q.id] = true end end
                    for _, ob in ipairs(obstacles) do
                        if ob.label and ob.id ~= r.id and meets(b, ob.box) then met[ob.id] = true end
                    end
                end
            end
            for _, b in ipairs(bestBoxes) do b.id = r.id; placed[#placed + 1] = b end
        end
    end
    return total, met
end

-- Between full passes: each label's route from last time, if it still exists.
local function keepRoutes(list, prevItems, u, jog, lane)
    for _, r in ipairs(list) do
        local p = prevItems[r.id]
        if not p then return false end
        local options = routesOf(r, u, jog, lane)
        if #options == 0 or not p.route then
            -- A pin under its own label has no leader; keep it that way.
            if #options > 0 or p.route then return false end
            r.path, r.route = nil, nil
        else
            local found
            for _, o in ipairs(options) do
                if o.key == p.route then found = o; break end
            end
            if not found then return false end
            r.path, r.route = found.path, found.key
        end
    end
    return true
end

-- view = { w, h, u, safe = { l, t, r, b }, reserve = { { x0, y0, x1, y1 } }? }
-- in pixels; columns and the top row keep clear of reserved rects (the radar).
-- box: the car on screen. items: { id, px, py, w, h, row1, minor, order } in
-- pixels, one per on-screen pin with its label size; row1 is the first row's
-- height (a column leader meets its middle). block: the switch block { w, h }
-- or nil. prev: the last layout (sides and routes are sticky). now: ms, for
-- the route passes; without it every call routes afresh.
-- Returns { items = { [id] = placed }, block = { x, y, w, h }?, hover = { [id] = true }, routedAt }.
-- placed = { side, x, y, w, h, path = { x1, y1, x2, y2, ... }?, route }; hover
-- marks pins whose label only shows under the pointer.
function C.layout(view, box, items, block, prev, now)
    local u, W, H, safe = view.u, view.w, view.h, view.safe
    local gapX, gapY, spacing, jog, lane = 48 * u, 40 * u, 10 * u, 20 * u, 10 * u
    local prevItems = prev and prev.items or {}
    local out = { items = {}, hover = {} }
    local cols = { left = {}, right = {}, top = {} }

    for _, it in ipairs(items) do
        if it.minor then
            out.hover[it.id] = true
        else
            local p = prevItems[it.id]
            local side, rel = sideOf(it, box, p and p.side)
            it.rel = rel
            local list = cols[side]
            list[#list + 1] = it
            it.side = side
        end
    end

    -- The top row: its height above the car, and its run across, short of
    -- anything reserved level with it.
    local function rowTop(list)
        local maxH = 0
        for _, it in ipairs(list) do if it.h > maxH then maxH = it.h end end
        return max(safe.t, box.y0 - gapY - maxH), maxH
    end
    local function rowReach(y0, y1)
        local lo, hi = safe.l, W - safe.r
        for _, r in ipairs(view.reserve or {}) do
            if y0 < r.y1 and r.y0 < y1 then
                if r.x0 + r.x1 < W then lo = max(lo, r.x1 + spacing) else hi = min(hi, r.x0 - spacing) end
            end
        end
        return lo, max(lo, hi)
    end

    -- The top row holds what fits across; the outermost go to the columns.
    local rowY, rowH = rowTop(cols.top)
    local rowLo, rowHi = rowReach(rowY, rowY + rowH)
    local avail = rowHi - rowLo
    local function rowWidth()
        local total = 0
        for _, it in ipairs(cols.top) do total = total + it.w + spacing end
        return total
    end
    while #cols.top > 0 and rowWidth() > avail * 0.9 do
        local worst, wi
        for i, it in ipairs(cols.top) do
            if not worst or abs(it.rel) > abs(worst.rel) then worst, wi = it, i end
        end
        table.remove(cols.top, wi)
        worst.side = worst.rel < 0 and 'left' or 'right'
        local list = cols[worst.side]
        list[#list + 1] = worst
    end

    -- A column's run: the safe area, short of anything reserved beside it.
    local reach = {}
    for _, side in ipairs({ 'left', 'right' }) do
        local mw = 0
        for _, it in ipairs(cols[side]) do if it.w > mw then mw = it.w end end
        if block then mw = max(mw, block.w) end
        local x0 = side == 'left' and box.x0 - gapX - mw or box.x1 + gapX
        local x1 = x0 + mw
        local t, b = safe.t, H - safe.b
        for _, r in ipairs(view.reserve or {}) do
            if x0 < r.x1 and r.x0 < x1 then
                if r.y0 + r.y1 > H then b = min(b, r.y0 - spacing) else t = max(t, r.y1 + spacing) end
            end
        end
        reach[side] = { t = t, b = max(t, b) }
    end

    -- A column that cannot hold its labels keeps the ones that rank first;
    -- the rest show on hover.
    local function fit(list, extra, top, bottom)
        table.sort(list, function(a, b) return a.order < b.order end)
        local total = extra
        local keep = {}
        for _, it in ipairs(list) do
            if total + it.h + spacing <= bottom - top then
                total = total + it.h + spacing
                keep[#keep + 1] = it
            else
                out.hover[it.id] = true
            end
        end
        return keep
    end
    -- The switch block joins the column with more room.
    local blockSide
    if block then
        local hl, hr = 0, 0
        for _, it in ipairs(cols.left) do hl = hl + it.h + spacing end
        for _, it in ipairs(cols.right) do hr = hr + it.h + spacing end
        blockSide = hr <= hl and 'right' or 'left'
    end
    for _, side in ipairs({ 'left', 'right' }) do
        cols[side] = fit(cols[side], blockSide == side and (block.h + spacing) or 0, reach[side].t, reach[side].b)
    end

    local function maxWidth(list, extra)
        local m = extra or 0
        for _, it in ipairs(list) do if it.w > m then m = it.w end end
        return m
    end

    -- Places the labels: in pin order, or nested (of leaders running the same
    -- way, the one from deeper in the car takes the outer label). Which of the
    -- two crosses less depends on the view, so a routing pass tries both.
    local function place(nested, drop)
        local placedItems, placedBlock, leaders = {}, nil, {}

        -- Columns: right-aligned to the left of the car, left-aligned to its right.
        for _, side in ipairs({ 'left', 'right' }) do
            local list = cols[side]
            local withBlock = blockSide == side
            if #list > 0 or withBlock then
                local mw = maxWidth(list, withBlock and block.w or 0)
                local edge
                if side == 'left' then
                    edge = max(box.x0 - gapX, safe.l + mw)
                    edge = min(edge, W - safe.r)
                else
                    edge = min(box.x1 + gapX, W - safe.r - mw)
                    edge = max(edge, safe.l)
                end
                local packed = {}
                for _, it in ipairs(list) do
                    -- The leader meets the middle of the first row.
                    if not drop[it.id] then packed[#packed + 1] = { item = it, want = it.py - it.row1 / 2 + it.h / 2, size = it.h } end
                end
                if withBlock then
                    -- Under the car's middle, or as low as the column allows.
                    packed[#packed + 1] = { block = true, want = box.y1 - block.h / 2, size = block.h }
                end
                table.sort(packed, function(a, b) return a.want < b.want end)
                pack(packed, spacing, reach[side].t, reach[side].b)
                if nested then
                    for _, e in ipairs(packed) do
                        e.key = e.want
                        if not e.block then
                            local it = e.item
                            local d = e.at + it.row1 / 2 - it.py
                            if abs(d) > 2 * u then e.key = e.want + (d < 0 and -1 or 1) * abs(it.px - edge) * NEST end
                        end
                    end
                    table.sort(packed, function(a, b) return a.key < b.key end)
                    pack(packed, spacing, reach[side].t, reach[side].b)
                end
                local up, down = {}, {}
                for _, e in ipairs(packed) do
                    if e.block then
                        placedBlock = { x = side == 'left' and edge - block.w or edge, y = e.at, w = block.w, h = block.h, side = side }
                    else
                        local it = e.item
                        e.ly = e.at + it.row1 / 2
                        -- Within a hair of the pin's height: snap level, no jog.
                        if abs(e.ly - it.py) < 2 * u then
                            e.at = e.at + (it.py - e.ly)
                            e.ly = it.py
                        end
                        if e.ly < it.py then up[#up + 1] = e elseif e.ly > it.py then down[#down + 1] = e end
                        local x = side == 'left' and edge - it.w or edge
                        local placed = { side = side, x = x, y = e.at, w = it.w, h = it.h }
                        placedItems[it.id] = placed
                        leaders[#leaders + 1] = { id = it.id, side = side, px = it.px, py = it.py, edge = edge, ly = e.ly,
                            rect = placed, order = it.order, straight = e.ly == it.py, e = e }
                    end
                end
                laneOrder(up, down, 'ly')
            end
        end

        -- The top row, above the car. Leaders meet the label's foot.
        if #cols.top > 0 then
            local y, maxH = rowTop(cols.top)
            local lo, hi = rowReach(y, y + maxH)
            local packed = {}
            for _, it in ipairs(cols.top) do
                if not drop[it.id] then packed[#packed + 1] = { item = it, want = it.px, size = it.w } end
            end
            table.sort(packed, function(a, b) return a.want < b.want end)
            pack(packed, spacing, lo, hi)
            if nested then
                for _, e in ipairs(packed) do
                    local it = e.item
                    local d = e.at + it.w / 2 - it.px
                    e.key = e.want
                    if abs(d) > 2 * u then e.key = e.want + (d < 0 and -1 or 1) * max(0, it.py - (y + maxH)) * NEST end
                end
                table.sort(packed, function(a, b) return a.key < b.key end)
                pack(packed, spacing, lo, hi)
            end
            local before, after = {}, {}
            for _, e in ipairs(packed) do
                local it = e.item
                e.ax = clamp(it.px, e.at + 14 * u, e.at + it.w - 14 * u)
                if abs(e.ax - it.px) < 2 * u then e.ax = it.px
                elseif e.ax < it.px then before[#before + 1] = e
                else after[#after + 1] = e end
                local ly = y + maxH - it.h -- bottoms align
                local placed = { side = 'top', x = e.at, y = ly, w = it.w, h = it.h }
                placedItems[it.id] = placed
                leaders[#leaders + 1] = { id = it.id, side = 'top', px = it.px, py = it.py, ax = e.ax, yb = ly + it.h,
                    rect = placed, order = it.order, straight = e.ax == it.px, e = e }
            end
            laneOrder(before, after, 'ax')
        end

        for _, r in ipairs(leaders) do r.lane = r.e.lane end
        return placedItems, placedBlock, leaders
    end

    -- A full routing pass over one placement.
    local function solve(nested, drop)
        local placedItems, placedBlock, leaders = place(nested, drop)
        local obstacles, pr, gap = {}, PIN_R * u, 2 * u
        for _, it in ipairs(items) do
            obstacles[#obstacles + 1] = { id = it.id, box = { it.px - pr, it.py - pr, it.px + pr, it.py + pr } }
        end
        for id, p in pairs(placedItems) do
            obstacles[#obstacles + 1] = { id = id, label = true, box = { p.x - gap, p.y - gap, p.x + p.w + gap, p.y + p.h + gap } }
        end
        if placedBlock then
            local b = placedBlock
            obstacles[#obstacles + 1] = { id = false, box = { b.x - gap, b.y - gap, b.x + b.w + gap, b.y + b.h + gap } }
        end
        for _, r in ipairs(leaders) do r.first = false end
        local cost, met = route(leaders, obstacles, prevItems, u, jog, lane)
        -- Leaders that met something choose first, once or twice, if that helps.
        for _ = 1, 2 do
            if cost == 0 then break end
            local saved = {}
            for _, r in ipairs(leaders) do saved[r] = { r.path, r.route }; r.first = met[r.id] or false end
            local again, metAgain = route(leaders, obstacles, prevItems, u, jog, lane)
            if again >= cost then
                for _, r in ipairs(leaders) do r.path, r.route = saved[r][1], saved[r][2] end
                break
            end
            cost, met = again, metAgain
        end
        return { items = placedItems, block = placedBlock, leaders = leaders, cost = cost, met = met, nested = nested, drop = drop }
    end

    -- Between passes the last placement and routes hold; a pass tries the
    -- last placement first and the other only when the first meets something.
    local pick
    local mode = prev and prev.nested or false
    if now and prev and prev.routedAt and now - prev.routedAt < C.ROUTE_MS then
        local drop = prev.dropped or {}
        local placedItems, placedBlock, leaders = place(mode, drop)
        if keepRoutes(leaders, prevItems, u, jog, lane) then
            pick = { items = placedItems, block = placedBlock, leaders = leaders, nested = mode, drop = drop }
            out.routedAt = prev.routedAt
        end
    end
    if not pick then
        pick = solve(mode, {})
        if pick.cost > 0 then
            local other = solve(not mode, {})
            if other.cost < pick.cost then pick = other end
        end
        -- A leader that still cannot run clear: the lowest ranked label
        -- involved shows on hover instead, so no two ever cross.
        local drop = {}
        for _ = 1, 4 do
            if pick.cost == 0 then break end
            local worst
            for _, l in ipairs(pick.leaders) do
                if pick.met[l.id] and (not worst or l.order > worst.order) then worst = l end
            end
            if not worst then break end
            drop[worst.id] = true
            pick = solve(pick.nested, drop)
        end
        out.routedAt = now
    end
    for id in pairs(pick.drop) do out.hover[id] = true end
    out.items, out.block, out.nested, out.dropped = pick.items, pick.block, pick.nested, pick.drop
    for _, r in ipairs(pick.leaders) do
        local p = out.items[r.id]
        p.path, p.route = r.path, r.route
    end
    return out
end

-- Pins that land on each other (a far door behind a seat, seen from the side)
-- become one callout: the first ranked pin with all their rows in rank order.
-- items as C.layout takes them, plus rows; gap: pixels between rows. Merged
-- items are changed in place; returns the list to lay out.
C.MERGE = 14 -- u
function C.merge(items, u, gap)
    local reach = C.MERGE * u
    table.sort(items, function(a, b) return a.order < b.order end)
    local out = {}
    for _, it in ipairs(items) do
        local into
        for _, o in ipairs(out) do
            if (o.px - it.px) ^ 2 + (o.py - it.py) ^ 2 < reach * reach then into = o; break end
        end
        if into then
            for _, r in ipairs(it.rows) do into.rows[#into.rows + 1] = r end
            into.w = max(into.w, it.w)
            into.h = into.h + gap + it.h
            into.minor = (into.minor and it.minor) or nil
            into.members = into.members or { into.id }
            into.members[#into.members + 1] = it.id
        else
            out[#out + 1] = it
        end
    end
    return out
end

-- Frame content ----------------------------------------------------------------------

C.ROW_GAP = 4     -- u between the rows of one label
C.BLOCK_W = 380   -- u; the switch block wraps past this
C.BLOCK_GAP = 8   -- u between switches

-- The rows a callout shows: { id, size, name, chip, tone, pending, w } with
-- w in u, and the label's width and height in u. The first row is large and
-- the rest small by their place in the callout, not among the shown rows, so
-- a hidden first row does not promote the second.
function C.shownRows(c)
    local rows, w, h = {}, 0, 0
    for i, r in ipairs(c.rows) do
        if not r.hidden then
            local size = i == 1 and 'lg' or 'sm'
            local chip = r.chip or ''
            local rw = C.rowWidth(size, r.name, chip)
            rows[#rows + 1] = { id = r.id, size = size, name = r.name, chip = chip, tone = r.tone or 'off', pending = r.pending, w = rw }
            if rw > w then w = rw end
            h = h + (#rows > 1 and C.ROW_GAP or 0) + C.ROW[size].h
        end
    end
    return rows, w, h
end

-- The frame's pins. entries: { id, offset, order, minor, rows, w, h } (rows,
-- w, h from C.shownRows); project(offset) gives the pin's pixels or nil.
-- Pins that land together are merged (C.merge). Returns the items C.layout
-- takes (with rows), the pins C.hit takes, the pins' bounds and items by id.
function C.items(entries, project, u)
    local items = {}
    for _, e in ipairs(entries) do
        if #e.rows > 0 then
            local px, py = project(e.offset)
            if px then
                items[#items + 1] = { id = e.id, px = px, py = py, w = e.w * u, h = e.h * u, row1 = C.ROW[e.rows[1].size].h * u,
                    minor = e.minor or nil, order = e.order, rows = e.rows }
            end
        end
    end
    items = C.merge(items, u, C.ROW_GAP * u)
    local pins, bounds, byId = {}, nil, {}
    for _, it in ipairs(items) do
        byId[it.id] = it
        pins[#pins + 1] = { id = it.id, px = it.px, py = it.py }
        if not bounds then bounds = { x0 = it.px, y0 = it.py, x1 = it.px, y1 = it.py }
        else
            bounds.x0, bounds.x1 = min(bounds.x0, it.px), max(bounds.x1, it.px)
            bounds.y0, bounds.y1 = min(bounds.y0, it.py), max(bounds.y1, it.py)
        end
    end
    return items, pins, bounds, byId
end

-- The switch block: the title, then the switches wrapped at BLOCK_W. title:
-- { w } or nil; switches: the shown ones, { w } in u. Returns its pieces
-- { title = true | switch, x, y, w, h } in pixels and its size { w, h }, or
-- nil when it is empty.
function C.block(title, switches, u)
    local list = {}
    local x, y, rowH, bw = 0, 0, 0, 0
    if title then
        list[#list + 1] = { title = true, x = 0, y = 0, w = title.w * u, h = C.ROW.lg.h * u }
        y = (C.ROW.lg.h + C.BLOCK_GAP) * u
        bw = title.w * u
    end
    for _, s in ipairs(switches) do
        local w, h = s.w * u, C.SWITCH.h * u
        if x > 0 and x + w > C.BLOCK_W * u then x, y, rowH = 0, y + rowH + C.BLOCK_GAP * u, 0 end
        list[#list + 1] = { switch = s, x = x, y = y, w = w, h = h }
        x = x + w + C.BLOCK_GAP * u
        if h > rowH then rowH = h end
        bw = max(bw, x - C.BLOCK_GAP * u)
    end
    if #list == 0 then return list, nil end
    return list, { w = bw, h = y + rowH }
end

-- Where a hover-only label sits: beside its pin, flipped at the right edge.
function C.hoverPlace(view, it)
    local u = view.u
    local x = it.px + 18 * u
    if x + it.w > view.w - view.safe.r then x = it.px - 18 * u - it.w end
    return { side = 'pin', x = x, y = it.py - it.row1 / 2, w = it.w, h = it.h }
end

-- Hit testing ---------------------------------------------------------------------

-- What is under the pointer: { id, row } for a callout row, { switch = id }
-- for a switch, or nil. rows: [id] = list of row heights; switches: list of
-- { id, x, y, w, h }; pins: list of { id, px, py }. Labels win over pins,
-- a hover label (drawn over the rest) over other labels, and a pin within
-- reach wins when nothing is under the pointer.
function C.hit(layout, rows, pins, switches, mx, my, u)
    for _, s in ipairs(switches or {}) do
        if mx >= s.x and mx <= s.x + s.w and my >= s.y and my <= s.y + s.h then return { switch = s.id } end
    end
    local pad = 4 * u
    local found
    for id, p in pairs(layout.items) do
        if mx >= p.x - pad and mx <= p.x + p.w + pad and my >= p.y - pad and my <= p.y + p.h + pad then
            local heights = rows[id] or { p.h }
            local y = p.y
            for i, rh in ipairs(heights) do
                if my <= y + rh + 2 * u or i == #heights then
                    if p.side == 'pin' then return { id = id, row = i } end
                    found = found or { id = id, row = i }
                    break
                end
                y = y + rh + 4 * u
            end
        end
    end
    if found then return found end
    local best, bestD = nil, 28 * u
    for _, p in ipairs(pins) do
        local d = sqrt((p.px - mx) ^ 2 + (p.py - my) ^ 2)
        if d < bestD then best, bestD = p, d end
    end
    if best then return { id = best.id, row = 1 } end
    return nil
end

-- A controller's stick picks the callout lying most in its direction from
-- the car's middle. dx, dy: the stick, y down. targets: { id, x, y }.
function C.aim(cx, cy, dx, dy, targets)
    local len = sqrt(dx * dx + dy * dy)
    if len < 0.3 then return nil end
    dx, dy = dx / len, dy / len
    local best, bestScore
    for _, t in ipairs(targets) do
        local vx, vy = t.x - cx, t.y - cy
        local d = sqrt(vx * vx + vy * vy)
        if d > 1 then
            local cos = (vx * dx + vy * dy) / d
            if cos > 0.5 and (not bestScore or cos > bestScore) then best, bestScore = t, cos end
        end
    end
    return best and best.id or nil
end

-- Atlas ---------------------------------------------------------------------------

-- Shelf packing: cells { key, w, h } in u go left to right in rows of equal
-- height, tallest first, within `width`. Sets .x and .y; returns the height
-- used, or nil when they do not fit in `height`.
function C.packAtlas(cells, width, height, gap)
    gap = gap or 2
    local order = {}
    for i, c in ipairs(cells) do order[i] = c end
    table.sort(order, function(a, b)
        if a.h ~= b.h then return a.h > b.h end
        return a.key < b.key
    end)
    local x, y, rowH = 0, 0, 0
    for _, c in ipairs(order) do
        if c.w > width then return nil end
        if x + c.w > width then
            x, y, rowH = 0, y + rowH + gap, 0
        end
        c.x, c.y = x, y
        x = x + c.w + gap
        if c.h > rowH then rowH = c.h end
    end
    local used = y + rowH
    if height and used > height then return nil end
    return used
end

-- Renderer-private (client/callout_renderer.lua); the specs load the file
-- directly and use what it returns.
if type(lib) == 'table' then lib._calloutLayout = C end

return C
