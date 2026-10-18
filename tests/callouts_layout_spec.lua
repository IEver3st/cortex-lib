-- Run from cortex-lib: lua tests/callouts_layout_spec.lua
-- The pure part of the callouts (client/callout_layout.lua): text measurement,
-- the virtual camera, packing, sides, columns, the top row, merging, the
-- frame helpers the renderer feeds, picking and atlas packing. No natives.
-- cortex-pinpoint runs the same layout over 21 measured vehicles.
local C = dofile('client/callout_layout.lua')

local passed, failed = 0, 0
local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; print(('FAIL %s\n     %s'):format(name, err)) end
end
local function eq(a, b, what) if a ~= b then error(('%s: expected %s, got %s'):format(what or 'value', tostring(b), tostring(a)), 2) end end
local function truthy(v, what) if not v then error((what or 'value') .. ': expected true', 2) end end

local function viewOf(w, h)
    local u = math.max(0.72, math.min(w, h) / 1080)
    local mx = 56 * u
    return { w = w, h = h, u = u, safe = { l = mx, r = mx, t = mx, b = mx } }
end
local VIEW = viewOf(1920, 1080)

local function overlaps(a, b, slack)
    slack = slack or 0
    return a.x < b.x + b.w - slack and b.x < a.x + a.w - slack and a.y < b.y + b.h - slack and b.y < a.y + a.h - slack
end

-- Type and camera --------------------------------------------------------------------

check('text is measured from the face\'s own advances', function()
    eq(C.textWidth('A', 1000, 0), 508)
    eq(C.textWidth('a', 1000, 0), 508, 'lower case is set as capitals')
    truthy(math.abs(C.textWidth('AA', 100, 0.1) - 121.6) < 1e-9, 'letter-spacing after each glyph')
    eq(C.textWidth('\u{20AC}', 1000, 0), 480, 'a glyph the face lacks counts as the average')
    truthy(C.rowWidth('lg', 'Trunk', 'Open') > C.rowWidth('lg', 'Trunk'), 'a chip widens the row')
    eq(C.rowWidth('lg', 'Trunk') % 1, 0, 'whole units')
end)
check('the virtual camera projects as GTA\'s does', function()
    local cam = C.camera({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, 50, 16 / 9)
    local x, y = C.project(cam, 0, 10, 0)
    truthy(math.abs(x - 0.5) < 1e-9 and math.abs(y - 0.5) < 1e-9, 'ahead is the middle')
    truthy(C.project(cam, 1, 10, 0) > 0.5, 'right is right')
    truthy(select(2, C.project(cam, 0, 10, 1)) < 0.5, 'up is up')
    eq(C.project(cam, 0, -10, 0), nil, 'behind')
    local west = C.camera({ x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 90 }, 50, 16 / 9)
    truthy(math.abs(C.project(west, -10, 0, 0) - 0.5) < 1e-9, 'heading 90 looks west')
    local down = C.camera({ x = 0, y = 0, z = 0 }, { x = -30, y = 0, z = 0 }, 50, 16 / 9)
    truthy(math.abs(select(2, C.project(down, 0, 10, -10 * math.tan(math.rad(30)))) - 0.5) < 1e-9, 'pitch down looks down')
end)

-- Layout ---------------------------------------------------------------------------------

check('packing keeps the gap, stays in bounds and sits round what each wants', function()
    local list = { { want = 500, size = 40 }, { want = 500, size = 40 }, { want = 500, size = 40 } }
    C.pack(list, 10, 0, 1000)
    for i = 2, 3 do eq(list[i].at - (list[i - 1].at + 40), 10, 'gap ' .. i) end
    eq((list[1].at + list[3].at + 40) / 2, 500, 'centred on the shared want')
    local edge = { { want = 5, size = 40 }, { want = 10, size = 40 } }
    C.pack(edge, 10, 0, 1000)
    eq(edge[1].at, 0, 'pushed in from the edge'); eq(edge[2].at, 50)
    local tight = { { want = 990, size = 40 }, { want = 995, size = 40 } }
    C.pack(tight, 10, 0, 1000)
    eq(tight[2].at + 40, 1000, 'held at the far edge'); eq(tight[1].at, 910)
end)

local BOX = { x0 = 800, y0 = 400, x1 = 1120, y1 = 600 }
local function one(px, py, prev)
    local item = { id = 'x', px = px, py = py, w = 200, h = 36, row1 = 36, order = 1 }
    return C.layout(VIEW, BOX, { item }, nil, prev).items.x
end

check('a pin picks its side by where it sits on the entity', function()
    eq(one(820, 500).side, 'left'); eq(one(1100, 500).side, 'right')
    eq(one(960, 440).side, 'top', 'middle of the upper half')
    eq(one(950, 580).side, 'left', 'middle of the lower half goes to a column')
end)
check('a pin near a boundary keeps the side it had', function()
    local rel = -0.25 -- inside the top band, outside the keep band of left
    local px = 960 + rel * 160
    eq(one(px, 480).side, 'top', 'fresh')
    eq(one(px, 480, { items = { x = { side = 'left' } } }).side, 'left', 'sticky')
end)
check('a full column sends its last-ranked labels to hover', function()
    local items = {}
    for i = 1, 40 do items[i] = { id = 'p' .. i, px = 810, py = 400 + i * 5, w = 150, h = 36, row1 = 36, order = i } end
    local layout = C.layout(VIEW, BOX, items, nil, nil)
    truthy(layout.items.p1 and not layout.items.p40, 'first kept, last dropped')
    truthy(layout.hover.p40, 'dropped one shows on hover')
end)
check('the top row keeps clear of an overlay level with it', function()
    local view = viewOf(1920, 1080)
    local item = { id = 'x', px = 960, py = 440, w = 200, h = 36, row1 = 36, order = 1 }
    local free = C.layout(view, BOX, { item }, nil, nil).items.x
    eq(free.side, 'top', 'fresh pin goes above the entity')
    local overlay = { x0 = 760, y0 = 250, x1 = 1160, y1 = 380 }
    local rect = { x = overlay.x0, y = overlay.y0, w = overlay.x1 - overlay.x0, h = overlay.y1 - overlay.y0 }
    truthy(overlaps(free, rect), 'the overlay is where the label would go')
    view.reserve = { overlay }
    local p = C.layout(view, BOX, { item }, nil, nil).items.x
    truthy(p, 'still labelled')
    truthy(not overlaps(p, rect), 'clear of the overlay')
end)
check('a ring of pins: labels on screen, clear of each other and the switches, leaders square', function()
    local items = {}
    for i = 1, 10 do
        local a = (i - 1) / 10 * 2 * math.pi
        items[i] = { id = 'p' .. i, px = 960 + math.cos(a) * 150, py = 500 + math.sin(a) * 90, w = 180, h = 36, row1 = 36, order = i }
    end
    local layout = C.layout(VIEW, BOX, items, { w = 300, h = 29 }, nil)
    local rects, byId = {}, {}
    for _, it in ipairs(items) do byId[it.id] = it end
    local s = VIEW.safe
    for id, p in pairs(layout.items) do
        truthy(p.x >= s.l - 0.5 and p.x + p.w <= VIEW.w - s.r + 0.5 and p.y >= s.t - 0.5 and p.y + p.h <= VIEW.h - s.b + 0.5, id .. ' inside the safe area')
        rects[#rects + 1] = { x = p.x, y = p.y, w = p.w, h = p.h, id = id }
        local path = p.path
        if path then
            eq(path[1], byId[id].px, id .. ' starts at its pin x'); eq(path[2], byId[id].py, id .. ' starts at its pin y')
            for i = 1, #path - 2, 2 do truthy(path[i] == path[i + 2] or path[i + 1] == path[i + 3], id .. ' segment square') end
        end
    end
    truthy(layout.block, 'the switches are placed')
    rects[#rects + 1] = { x = layout.block.x, y = layout.block.y, w = layout.block.w, h = layout.block.h, id = 'switches' }
    for i = 1, #rects do
        for j = i + 1, #rects do truthy(not overlaps(rects[i], rects[j], 0.5), rects[i].id .. ' clear of ' .. rects[j].id) end
    end
    truthy(#rects >= 9, 'most of the ring is labelled')
end)
check('pins that land on each other become one callout with all their rows', function()
    local items = {
        { id = 'a', px = 100, py = 100, w = 120, h = 36, row1 = 36, order = 2, rows = { 'a1' } },
        { id = 'b', px = 105, py = 104, w = 160, h = 63, row1 = 36, order = 1, rows = { 'b1', 'b2' }, minor = true },
        { id = 'c', px = 300, py = 100, w = 100, h = 36, row1 = 36, order = 3, rows = { 'c1' } },
    }
    local out = C.merge(items, 1, 4)
    eq(#out, 2); eq(out[1].id, 'b', 'the first ranked pin leads')
    eq(table.concat(out[1].rows, ','), 'b1,b2,a1'); eq(out[1].w, 160); eq(out[1].h, 103)
    eq(out[1].minor, nil, 'labelled if any member is')
end)

-- Frame helpers ------------------------------------------------------------------------

check('shown rows skip hidden ones, keep their declared size, and measure the label', function()
    local rows, w, h = C.shownRows({ rows = {
        { id = 'door', name = 'Hood', chip = 'Open', tone = 'on' },
        { id = 'engine', name = 'Engine', chip = 'Start' },
        { id = 'gone', name = 'Gone', hidden = true },
    } })
    eq(#rows, 2); eq(rows[1].size, 'lg'); eq(rows[2].size, 'sm')
    eq(rows[2].tone, 'off', 'tone defaults to off')
    eq(rows[1].w, C.rowWidth('lg', 'Hood', 'Open'))
    eq(w, math.max(rows[1].w, rows[2].w))
    eq(h, C.ROW.lg.h + C.ROW_GAP + C.ROW.sm.h)
    local second = C.shownRows({ rows = { { id = 'a', name = 'A', hidden = true }, { id = 'b', name = 'B' } } })
    eq(second[1].size, 'sm', 'a hidden first row does not promote the second')
    local none, nw, nh = C.shownRows({ rows = { { id = 'a', name = 'A', hidden = true } } })
    eq(#none, 0); eq(nw, 0); eq(nh, 0)
end)
check('items project each pin, skip empty and off-screen ones, merge and bound them', function()
    local function entry(id, x, rows)
        local shown, w, h = C.shownRows({ rows = rows })
        return { id = id, offset = { x = x, y = 0, z = 0 }, order = #id, rows = shown, w = w, h = h }
    end
    local entries = {
        entry('a', 100, { { id = 'a1', name = 'Left' } }),
        entry('b', 103, { { id = 'b1', name = 'Near' } }),
        entry('c', 400, { { id = 'c1', name = 'Right' } }),
        entry('d', 600, { { id = 'd1', name = 'Hidden', hidden = true } }),
        entry('e', -1, { { id = 'e1', name = 'Behind' } }),
    }
    local items, pins, bounds, byId = C.items(entries, function(p) if p.x >= 0 then return p.x, 200 end end, 1.5)
    eq(#items, 2, 'a and b merged, d empty, e off screen')
    eq(#pins, 2); truthy(byId.a and byId.c and not byId.b, 'by id')
    eq(bounds.x0, 100); eq(bounds.x1, 400); eq(bounds.y0, 200)
    eq(byId.c.w, entries[3].w * 1.5, 'sizes in pixels')
    eq(byId.c.row1, C.ROW.lg.h * 1.5)
    eq(#byId.a.rows, 2, 'merged rows')
end)
check('the switch block puts the title first and wraps switches at its width', function()
    local u = 1
    local list, size = C.block({ w = 200 }, { { id = 's1', w = 150 }, { id = 's2', w = 150 }, { id = 's3', w = 150 } }, u)
    truthy(list[1].title, 'title first'); eq(list[1].y, 0)
    local top = C.ROW.lg.h + C.BLOCK_GAP
    eq(list[2].y, top); eq(list[3].y, top, 'two fit one line'); eq(list[3].x, 150 + C.BLOCK_GAP)
    eq(list[4].x, 0, 'the third wraps'); eq(list[4].y, top + C.SWITCH.h + C.BLOCK_GAP)
    eq(size.w, 300 + C.BLOCK_GAP); eq(size.h, list[4].y + C.SWITCH.h)
    eq(list[2].switch.id, 's1', 'switch pieces carry their switch')
    local empty, none = C.block(nil, {}, u)
    eq(#empty, 0); eq(none, nil)
end)

-- Picking and the atlas -----------------------------------------------------------------

check('the pointer picks labels over pins, the right row, and nothing far off', function()
    local layout = { items = { a = { side = 'left', x = 100, y = 100, w = 200, h = 67, path = nil } }, hover = {} }
    local rows = { a = { 36, 27 } }
    local pins = { { id = 'b', px = 150, py = 110 }, { id = 'c', px = 600, py = 600 } }
    eq(C.hit(layout, rows, pins, {}, 150, 110, 1).id, 'a', 'label over pin')
    eq(C.hit(layout, rows, pins, {}, 150, 110, 1).row, 1)
    eq(C.hit(layout, rows, pins, {}, 150, 155, 1).row, 2, 'second row')
    eq(C.hit(layout, rows, pins, {}, 620, 600, 1).id, 'c', 'pin within reach')
    eq(C.hit(layout, rows, pins, {}, 900, 900, 1), nil, 'nothing')
    eq(C.hit(layout, rows, pins, { { id = 'hazards', x = 880, y = 890, w = 60, h = 29 } }, 900, 900, 1).switch, 'hazards')
end)
check('a hover label over other labels is the one picked', function()
    for _, hid in ipairs({ 'a', 'h', 'm', 'z', 'seat:1', 'door:0' }) do
        local items = {}
        for i = 1, 8 do items['l' .. i] = { side = 'left', x = 100, y = 100, w = 200, h = 36 } end
        items[hid] = { side = 'pin', x = 120, y = 90, w = 200, h = 36 }
        eq(C.hit({ items = items, hover = {} }, {}, {}, {}, 200, 110, 1).id, hid, 'hover label ' .. hid)
    end
end)
check('the stick picks what lies in its direction', function()
    local targets = { { id = 'l', x = 100, y = 500 }, { id = 'r', x = 900, y = 500 }, { id = 'u', x = 500, y = 100 } }
    eq(C.aim(500, 500, 1, 0, targets), 'r'); eq(C.aim(500, 500, -1, 0.1, targets), 'l'); eq(C.aim(500, 500, 0, -1, targets), 'u')
    eq(C.aim(500, 500, 0.1, 0.1, targets), nil, 'dead zone')
    eq(C.aim(500, 500, 0, 1, targets), nil, 'nothing below')
end)
check('atlas cells pack without overlap inside the texture', function()
    local cells = {}
    for i = 1, 30 do cells[i] = { key = ('c%02d'):format(i), w = 100 + (i * 37) % 200, h = i % 3 == 0 and 56 or 47 } end
    local used = C.packAtlas(cells, 1280, 1240)
    truthy(used and used <= 1240, 'fits')
    for i = 1, #cells do
        local a = cells[i]
        truthy(a.x >= 0 and a.x + a.w <= 1280 and a.y >= 0 and a.y + a.h <= used, a.key .. ' inside')
        for j = i + 1, #cells do truthy(not overlaps(a, cells[j]), a.key .. ' clear of ' .. cells[j].key) end
    end
    eq(C.packAtlas({ { key = 'wide', w = 1300, h = 10 } }, 1280, 1240), nil, 'too wide')
    eq(C.packAtlas(cells, 1280, 100), nil, 'too tall')
end)

print(('callouts layout: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
