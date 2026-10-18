-- Run from cortex-lib: lua tests/callouts_api_spec.lua
-- The callouts API (imports/callouts/client.lua) with the real renderer,
-- label atlas and layout: validation, owner scoping, replacement, updates in
-- place, select / wheel / cancel events, entity and focus loss, effects,
-- state, the atlas message and its paint handshake, prepare, the game text
-- fallback and cleanup. Natives are deterministic stubs, and the native
-- projection uses the layout's own camera. This proves no FiveM or CEF
-- behaviour.
local realPrint = print

local passed, failed = 0, 0
local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; realPrint(('FAIL %s\n     %s'):format(name, err)) end
end
local function eq(a, b, what) if a ~= b then error(('%s: expected %s, got %s'):format(what or 'value', tostring(b), tostring(a)), 2) end end
local function truthy(v, what) if not v then error((what or 'value') .. ': expected true', 2) end end

-- Deterministic JSON stand-in: sorted keys; the decoded value is kept so a
-- test reads back what was sent.
local function encode(value)
    local kind = type(value)
    if kind == 'string' then return string.format('%q', value) end
    if kind ~= 'table' then return tostring(value) end
    if #value > 0 or next(value) == nil then
        local parts = {}
        for i = 1, #value do parts[i] = encode(value[i]) end
        return '[' .. table.concat(parts, ',') .. ']'
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = {}
    for i, key in ipairs(keys) do parts[i] = key .. ':' .. encode(value[key]) end
    return '{' .. table.concat(parts, ',') .. '}'
end

local s, API

local function boot(options)
    options = options or {}
    s = {
        exported = {}, handlers = {}, callbacks = {}, threads = {}, prints = {}, decoded = {}, messages = {},
        created = {}, destroyed = {}, sprites = 0, rects = 0, texts = {}, cursorAt = nil,
        clock = 1000, entities = { [42] = 111, [43] = 222 }, invoking = 'cortex-pinpoint',
        pressed = {}, mouse = { 0.5, 0.5 }, pause = false, focus = false, available = true,
        noDui = options.noDui,
    }
    lib = {}
    exports = setmetatable({}, {
        __call = function(_, name, fn) s.exported[name] = fn end,
        __index = function() return { getPresentation = function()
            return { profile = { accent = '#D8BA82', motion = 'system' }, viewport = { width = 1920, height = 1080 },
                surfaces = { { x = 1500, y = 40, width = 380, height = 120, owner = 'cortex-hud' } } }
        end } end,
    })
    json = { encode = function(value) local text = encode(value); s.decoded[text] = value; return text end }
    print = function(...) s.prints[#s.prints + 1] = table.concat({ ... }, ' ') end
    function GetCurrentResourceName() return 'cortex-lib' end
    function GetInvokingResource() return s.invoking end
    function GetConvarInt(_, default) return default end
    function AddEventHandler(name, fn) s.handlers[name] = s.handlers[name] or {}; table.insert(s.handlers[name], fn) end
    function TriggerEvent(name, ...) for _, fn in ipairs(s.handlers[name] or {}) do fn(...) end end
    function RegisterNUICallback(name, fn) s.callbacks[name] = fn end
    function CreateThread(fn) s.threads[#s.threads + 1] = coroutine.create(fn) end
    function Wait(ms) coroutine.yield(ms) end
    function GetGameTimer() return s.clock end
    function GetActiveScreenResolution() return 1920, 1080 end
    function GetSafeZoneSize() return 1.0 end
    function IsRadarHidden() return false end
    -- DUI
    function CreateDui(url, w, h)
        if s.noDui then return nil end
        s.created[#s.created + 1] = { url = url, w = w, h = h }
        return 'dui' .. #s.created
    end
    function DestroyDui(object) s.destroyed[#s.destroyed + 1] = object end
    function IsDuiAvailable() return s.available end
    function GetDuiHandle(object) return 'handle:' .. object end
    function CreateRuntimeTxd(name) return name end
    function CreateRuntimeTextureFromDuiHandle() return 1 end
    function SendDuiMessage(_, text) s.messages[#s.messages + 1] = s.decoded[text] end
    function DrawSpriteUv() s.sprites = s.sprites + 1 end
    -- Entity and camera: a car at the origin facing +y, seen from behind.
    function DoesEntityExist(entity) return s.entities[entity] ~= nil end
    function GetEntityModel(entity) return s.entities[entity] or 0 end
    function GetModelDimensions() return { x = -1.0, y = -2.4, z = -0.6 }, { x = 1.0, y = 2.4, z = 0.9 } end
    function GetEntityMatrix() return { x = 0, y = 1, z = 0 }, { x = 1, y = 0, z = 0 }, { x = 0, y = 0, z = 1 }, { x = 0, y = 0, z = 0 } end
    function GetEntityVelocity() return { x = 0, y = 0, z = 0 } end
    function GetFrameTime() return 0.016 end
    function GetFinalRenderedCamCoord() return { x = 0.0, y = -7.0, z = 2.2 } end
    function GetFinalRenderedCamRot() return { x = -10.0, y = 0.0, z = 0.0 } end
    function GetFinalRenderedCamFov() return 50.0 end
    function GetAspectRatio() return 16 / 9 end
    function GetScreenCoordFromWorldCoord(x, y, z)
        local L = lib._calloutLayout
        local cam = L.camera(GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(), 50.0, 16 / 9)
        local sx, sy = L.project(cam, x, y, z)
        if not sx then return false, -1.0, -1.0 end
        return true, sx, sy
    end
    function SetDrawOrigin() end
    function ClearDrawOrigin() end
    function DrawRect() s.rects = s.rects + 1 end
    function SetTextFont() end
    function SetTextScale() end
    function SetTextColour() end
    function SetTextDropShadow() end
    function SetTextOutline() end
    function BeginTextCommandDisplayText() end
    function AddTextComponentSubstringPlayerName(text) s.texts[#s.texts + 1] = text end
    function EndTextCommandDisplayText() end
    -- Input
    function IsPauseMenuActive() return s.pause end
    function IsNuiFocused() return s.focus end
    function DisableControlAction(_, control) s.disabled[control] = true end
    function IsDisabledControlJustPressed(_, control) return s.pressed[control] == true end
    function IsUsingKeyboard() return true end
    function GetDisabledControlNormal(_, control)
        if control == 239 then return s.mouse[1] end
        if control == 240 then return s.mouse[2] end
        return 0.0
    end
    function SetMouseCursorThisFrame() end
    function SetMouseCursorStyle() end
    function SetCursorLocation(x, y) s.cursorAt = { x, y } end
    s.disabled = {}

    dofile('client/callout_layout.lua')
    dofile('client/callout_dui.lua')
    dofile('client/callout_renderer.lua')
    API = dofile('imports/callouts/client.lua')
end

-- Runs every live thread once and moves the clock a frame; presses last a frame.
local function step(n)
    for _ = 1, n or 1 do
        s.disabled = {}
        local list = s.threads
        s.threads = {}
        for _, co in ipairs(list) do
            if coroutine.status(co) == 'suspended' then
                local ok, err = coroutine.resume(co)
                if not ok then error(err, 0) end
                if coroutine.status(co) == 'suspended' then s.threads[#s.threads + 1] = co end
            end
        end
        s.pressed = {}
        s.clock = s.clock + 16
    end
end

local function as(owner, name, ...)
    s.invoking = owner
    return API[name](...)
end

local function data(extra)
    local d = {
        entity = 42, model = 111,
        bounds = { min = { x = -1.0, y = -2.4, z = -0.6 }, max = { x = 1.0, y = 2.4, z = 0.9 } },
        callouts = {
            { id = 'door:0', offset = { x = -0.9, y = 0.4, z = 0.3 }, rows = {
                { id = 'door:0', name = 'Left door', chip = 'Open' },
                { id = 'window:0', name = 'Window', chip = 'Down' } } },
            { id = 'door:1', offset = { x = 0.9, y = 0.4, z = 0.3 }, rows = { { id = 'door:1', name = 'Right door', chip = 'Open' } } },
            { id = 'door:5', offset = { x = 0.0, y = -2.2, z = 0.4 }, rows = { { id = 'door:5', name = 'Trunk', chip = 'Open' } } },
        },
        switches = {
            { id = 'lock', text = 'Unlocked', texts = { 'Locked', 'Unlocked' } },
            { id = 'hazards', text = 'Hazards', tone = 'on' },
        },
        chips = { 'Open', 'Close', 'Down', 'Up', 'Not yours' },
    }
    for k, v in pairs(extra or {}) do d[k] = v end
    return d
end

local function recorder()
    local events = {}
    return events, function(event) events[#events + 1] = event end
end

local function lastAtlas()
    for i = #s.messages, 1, -1 do
        local m = s.messages[i]
        if m and m.action == 'callouts:atlas' then return m end
    end
end

-- Puts the mouse on a pixel.
local function point(x, y) s.mouse = { x / 1920, y / 1080 } end

-- Validation ----------------------------------------------------------------------------

check('malformed data is refused with a reason, and nothing opens', function()
    boot()
    local cases = {
        { nil, 'invalid_data' },
        { data({ entity = 0 }), 'invalid_entity' },
        { data({ entity = 1.5 }), 'invalid_entity' },
        { data({ model = 'adder' }), 'invalid_model' },
        { data({ bounds = { min = { x = 1, y = 0, z = 0 }, max = { x = 0, y = 1, z = 1 } } }), 'invalid_bounds' },
        { data({ callouts = { { id = 'a', offset = { x = 0, y = 0, z = 0 }, rows = {} } } }), 'invalid_callout_rows' },
        { data({ callouts = { { id = 'a', offset = { x = 0, y = 0, z = 99 }, rows = { { id = 'r', name = 'R' } } } } }), 'invalid_callout_offset' },
        { data({ callouts = { { id = 'a', offset = { x = 0, y = 0, z = 0 }, rows = { { id = 'r', name = 'R', tone = 'red' } } } } }), 'invalid_row_tone' },
        { data({ callouts = { { id = 'a', offset = { x = 0, y = 0, z = 0 }, rows = { { id = 'r', name = ('x'):rep(49) } } } } }), 'invalid_row_name' },
        { data({ switches = { { id = 'door:0', text = 'Clash' } } }), 'invalid_switch_id' },
        { data({ switches = { { id = 's', text = 'S', texts = { 'a', 3 } } } }), 'invalid_switch_texts' },
        { data({ chips = { 'ok', '' } }), 'invalid_chips' },
        { data({ onEvent = 'callback' }), 'invalid_onEvent' },
        { { entity = 42 }, 'empty' },
    }
    for i, c in ipairs(cases) do
        local ok, err = as('cortex-pinpoint', 'showCallouts', c[1])
        eq(ok, false, 'case ' .. i); eq(err, c[2], 'case ' .. i)
    end
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), false)
end)
check('a funcref handler (a callable table that throws when indexed) is accepted', function()
    boot()
    local events = {}
    local ref = setmetatable({}, {
        __call = function(_, event) events[#events + 1] = event end,
        __index = function() error('funcref fields throw') end,
    })
    truthy(as('cortex-pinpoint', 'showCallouts', data({ onEvent = ref })), 'shown')
    s.pressed[25] = true
    step()
    eq(events[1] and events[1].reason, 'cancel', 'the funcref is called')
end)
check('a funcref where a table belongs is refused, not thrown', function()
    boot()
    local function funcref() return setmetatable({}, { __call = function() end, __index = function() error('funcref fields throw') end }) end
    local cases = {
        data({ bounds = { min = funcref(), max = { x = 1, y = 1, z = 1 } } }),
        data({ callouts = { { id = 'a', offset = funcref(), rows = { { id = 'r', name = 'R' } } } } }),
        data({ title = funcref() }),
    }
    for i, d in ipairs(cases) do
        local okCall, ok, err = pcall(API.showCallouts, d)
        truthy(okCall, 'case ' .. i .. ' did not throw')
        eq(ok, false, 'case ' .. i); eq(err, 'invalid_data', 'case ' .. i)
    end
end)
check('an entity that does not exist is refused', function()
    boot()
    local ok, err = as('cortex-pinpoint', 'showCallouts', data({ entity = 99 }))
    eq(ok, false); eq(err, 'invalid_entity')
end)

-- Owners ------------------------------------------------------------------------------------

check('a session belongs to the resource that opened it', function()
    boot()
    truthy(as('cortex-pinpoint', 'showCallouts', data()), 'shown')
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), true)
    eq(as('cortex-other', 'isCalloutsOpen'), false, 'not another resource\'s')
    eq(as('cortex-other', 'hideCallouts'), false, 'another resource cannot hide it')
    eq(as('cortex-other', 'calloutEffect', 'door:0', 'pop'), false, 'nor work its effects')
    eq(as('cortex-other', 'getCalloutState').open, false)
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), true, 'still open')
    eq(as('cortex-pinpoint', 'hideCallouts'), true)
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), false)
end)
check('another resource\'s callouts replace the open ones, and the first owner is told', function()
    boot()
    local events, handler = recorder()
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
    truthy(as('cortex-other', 'showCallouts', data({ entity = 43, model = 222 })), 'replaced')
    eq(events[1] and events[1].type, 'closed'); eq(events[1].reason, 'replaced')
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), false)
    eq(as('cortex-other', 'isCalloutsOpen'), true)
end)
check('a replaced owner showing again from its closed event is refused, not silently lost', function()
    boot()
    local again
    local function handler(event)
        if event.type == 'closed' and event.reason == 'replaced' then
            again = table.pack(as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler })))
        end
    end
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
    truthy(as('cortex-other', 'showCallouts', data({ entity = 43, model = 222 })), 'replaced')
    truthy(again, 'the first owner tried again')
    eq(again[1], false); eq(again[2], 'busy')
    eq(as('cortex-other', 'isCalloutsOpen'), true)
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), false)
    step()
    eq(as('cortex-other', 'isCalloutsOpen'), true, 'the new owner keeps its session')
end)
check('a refused show leaves another resource\'s callouts open', function()
    boot()
    local events, handler = recorder()
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
    local ok = as('cortex-other', 'showCallouts', data({ entity = 99 }))
    eq(ok, false)
    eq(#events, 0, 'no closed event')
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), true, 'still open')
end)
check('the same owner on the same entity updates in place', function()
    boot()
    local events, handler = recorder()
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
    step(30)
    local first = lastAtlas()
    truthy(first, 'the atlas was sent')
    s.callbacks.calloutsPainted({ dui = 1, revision = first.data.revision }, function() end)
    local before = {}
    for _, c in ipairs(first.data.cells) do if c.k == 'row' then before[c.name .. (c.hot and 'h' or 'n')] = c.x .. ',' .. c.y end end
    local d = data({ onEvent = handler })
    d.callouts[1].rows[1].chip, d.callouts[1].rows[1].tone = 'Close', 'on'
    truthy(as('cortex-pinpoint', 'showCallouts', d), 'updated')
    step()
    local second = lastAtlas()
    truthy(second.data.revision > first.data.revision, 'a new revision')
    local repainted = false
    for _, c in ipairs(second.data.cells) do
        if c.k == 'row' then
            eq(c.x .. ',' .. c.y, before[c.name .. (c.hot and 'h' or 'n')], c.name .. ' stays in its cell')
            if c.name == 'Left door' and c.chip == 'Close' and c.tone == 'on' then repainted = true end
        end
    end
    truthy(repainted, 'the new chip and tone are painted')
    eq(#events, 0, 'no closed event')
    eq(#s.created, 1, 'one page')
end)
check('a new entity for the same owner starts over without a closed event', function()
    boot()
    local events, handler = recorder()
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
    truthy(as('cortex-pinpoint', 'showCallouts', data({ entity = 43, model = 222, onEvent = handler })), 'shown')
    step()
    eq(#events, 0)
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), true)
end)

-- Events ------------------------------------------------------------------------------------

check('a click on a label selects its row; on a switch, the switch', function()
    boot()
    local events, handler = recorder()
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
    step(20)
    local st = as('cortex-pinpoint', 'getCalloutState')
    truthy(st.open and st.labels['door:1'], 'the right door is labelled')
    point(st.labels['door:1'].x, st.labels['door:1'].y)
    step()
    eq(as('cortex-pinpoint', 'getCalloutState').hot.id, 'door:1', 'hovered')
    s.pressed[24] = true
    step()
    eq(events[1].type, 'select'); eq(events[1].id, 'door:1'); eq(events[1].callout, 'door:1'); eq(events[1].switch, false)
    local sw = as('cortex-pinpoint', 'getCalloutState').switches.hazards
    truthy(sw, 'the hazards switch is placed')
    point(sw.x, sw.y)
    step()
    s.pressed[24] = true
    step()
    eq(events[2].type, 'select'); eq(events[2].id, 'hazards'); eq(events[2].switch, true)
end)
check('the wheel over a label names its rows and the direction', function()
    boot()
    local events, handler = recorder()
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
    step(20)
    local label = as('cortex-pinpoint', 'getCalloutState').labels['door:0']
    point(label.x, label.y)
    step()
    s.pressed[242] = true
    step()
    eq(events[1].type, 'wheel'); eq(events[1].delta, 1); eq(events[1].callout, 'door:0')
    eq(table.concat(events[1].rows, ','), 'door:0,window:0')
    s.pressed[241] = true
    step()
    eq(events[2].delta, -1)
end)
check('right click closes with cancel and holds the pause menu off briefly', function()
    boot()
    local events, handler = recorder()
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
    step(2)
    s.pressed[25] = true
    step()
    eq(events[1].reason, 'cancel')
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), false)
    step()
    truthy(s.disabled[200], 'Esc held after closing')
    step(30)
    eq(s.disabled[200], nil, 'released after the guard')
end)
check('the entity going, changing model, the pause menu or NUI focus close the session', function()
    for _, case in ipairs({
        { function() s.entities[42] = nil end, 'entity' },
        { function() s.entities[42] = 999 end, 'entity' },
        { function() s.pause = true end, 'focus' },
        { function() s.focus = true end, 'focus' },
    }) do
        boot()
        local events, handler = recorder()
        as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
        step(2)
        case[1]()
        step()
        eq(events[1] and events[1].reason, case[2])
        eq(as('cortex-pinpoint', 'isCalloutsOpen'), false)
    end
end)
check('a handler may update the callouts from inside an event', function()
    boot()
    local events = {}
    local d
    local function handler(event)
        events[#events + 1] = event
        if event.type == 'select' then
            d.callouts[2].rows[1].chip = 'Close'
            assert(API.showCallouts(d))
        end
    end
    d = data({ onEvent = handler })
    as('cortex-pinpoint', 'showCallouts', d)
    step(20)
    local label = as('cortex-pinpoint', 'getCalloutState').labels['door:1']
    point(label.x, label.y)
    step()
    s.pressed[24] = true
    step(2)
    eq(#events, 1)
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), true, 'still open')
end)
check('a handler that throws is reported and the session stays up', function()
    boot()
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = function() error('boom') end }))
    step(20)
    local label = as('cortex-pinpoint', 'getCalloutState').labels['door:1']
    point(label.x, label.y)
    step()
    s.pressed[24] = true
    step()
    local found = false
    for _, line in ipairs(s.prints) do if line:find('onEvent of cortex-pinpoint failed', 1, true) then found = true end end
    truthy(found, 'printed')
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), true)
end)

-- Presentation -------------------------------------------------------------------------------

check('effects take the owner\'s row ids and the two kinds only', function()
    boot()
    as('cortex-pinpoint', 'showCallouts', data())
    eq(as('cortex-pinpoint', 'calloutEffect', 'door:0', 'pop'), true)
    eq(as('cortex-pinpoint', 'calloutEffect', 'door:0', 'spin'), false)
    eq(as('cortex-pinpoint', 'calloutEffect', 42, 'pop'), false)
    step()
end)
check('state names the labels, switches and screen while open, and nothing after', function()
    boot()
    as('cortex-pinpoint', 'showCallouts', data())
    step(20)
    local st = as('cortex-pinpoint', 'getCalloutState')
    eq(st.open, true); eq(st.screen.width, 1920)
    for _, id in ipairs({ 'door:0', 'door:1', 'door:5' }) do
        local p = st.labels[id]
        truthy(p and p.x > 0 and p.x < 1920 and p.y > 0 and p.y < 1080, id .. ' on screen')
    end
    truthy(st.switches.lock and st.switches.hazards, 'switches')
    as('cortex-pinpoint', 'hideCallouts')
    eq(as('cortex-pinpoint', 'getCalloutState').open, false)
end)
check('labels keep clear of other owners\' surfaces', function()
    boot()
    step() -- reads the presentation snapshot
    as('cortex-pinpoint', 'showCallouts', data())
    step(20)
    local st = as('cortex-pinpoint', 'getCalloutState')
    for id, p in pairs(st.labels) do
        truthy(not (p.x > 1500 and p.x < 1880 and p.y > 40 and p.y < 160), id .. ' clear of the HUD surface')
    end
end)
check('the atlas message carries every cell, the metrics and the accent, sent only on change', function()
    boot()
    step() -- reads the presentation snapshot
    as('cortex-pinpoint', 'showCallouts', data())
    step(3)
    local m = lastAtlas()
    truthy(m, 'sent')
    eq(m.data.revision, 1); eq(m.data.accent, '#d8ba82', 'the shared accent, lower case')
    truthy(m.data.metrics and m.data.metrics.row.lg.h == 36 and m.data.metrics.pad == 10, 'metrics')
    local kinds = {}
    for _, c in ipairs(m.data.cells) do kinds[c.k] = (kinds[c.k] or 0) + 1 end
    eq(kinds.pin, 3, 'idle, on and hot pins'); eq(kinds.row, 8, 'four rows, normal and hot'); eq(kinds.switch, 4)
    truthy(s.created[1].url:find('nui://cortex-lib/ui/callouts.html?resource=cortex-lib&dui=1', 1, true), 'the page URL')
    -- Unpainted: resent with backoff, not every frame.
    local count = #s.messages
    step(10)
    truthy(#s.messages - count <= 1, 'one resend in 160 ms at most')
    s.callbacks.calloutsPainted({ dui = 1, revision = 1 }, function() end)
    count = #s.messages
    step(400)
    eq(#s.messages, count, 'painted: nothing more is sent')
end)
check('paint reports from another page or an unsent revision are ignored', function()
    boot()
    as('cortex-pinpoint', 'showCallouts', data())
    step(3)
    local replies = 0
    s.callbacks.calloutsPainted({ dui = 7, revision = 1 }, function() replies = replies + 1 end)
    s.callbacks.calloutsPainted({ dui = 1, revision = 9 }, function() replies = replies + 1 end)
    s.callbacks.calloutsPainted('junk', function() replies = replies + 1 end)
    eq(replies, 3, 'every callback answered')
    local count = #s.messages
    step(40)
    truthy(#s.messages > count, 'still resending: nothing was painted')
end)
check('labels draw from the atlas once painted', function()
    boot()
    as('cortex-pinpoint', 'showCallouts', data())
    step(3)
    s.callbacks.calloutsPainted({ dui = 1, revision = lastAtlas().data.revision }, function() end)
    s.sprites, s.texts = 0, {}
    step(20)
    truthy(s.sprites > 0, 'sprites drawn')
    eq(#s.texts, 0, 'no game text')
end)
check('without a DUI the labels are game text and every part still works', function()
    boot({ noDui = true })
    local events, handler = recorder()
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
    step(20)
    local seen = {}
    for _, text in ipairs(s.texts) do seen[text] = true end
    truthy(seen['RIGHT DOOR  OPEN'] and seen['HAZARDS'], 'labels and switches as text')
    local found = 0
    for _, line in ipairs(s.prints) do if line:find('could not start', 1, true) then found = found + 1 end end
    eq(found, 1, 'said once')
    local label = as('cortex-pinpoint', 'getCalloutState').labels['door:1']
    point(label.x, label.y)
    step()
    s.pressed[24] = true
    step()
    eq(events[1] and events[1].id, 'door:1', 'still clickable')
end)
check('prepare starts the page and paints the pins before any session', function()
    boot()
    eq(as('cortex-pinpoint', 'prepareCallouts'), true)
    step(3)
    eq(#s.created, 1)
    local m = lastAtlas()
    truthy(m, 'pins sent')
    eq(#m.data.cells, 3)
    as('cortex-pinpoint', 'showCallouts', data())
    eq(#s.created, 1, 'the session uses the same page')
end)
check('the owner stopping closes its callouts; cortex-lib stopping destroys the page', function()
    boot()
    as('cortex-pinpoint', 'showCallouts', data())
    step(2)
    TriggerEvent('onClientResourceStop', 'cortex-pinpoint')
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), false)
    TriggerEvent('onClientResourceStop', 'cortex-lib')
    eq(s.destroyed[1], 'dui1')
end)
check('cortex-lib stopping tells the owner, and refuses a show from inside that event', function()
    boot()
    local events, again = {}, nil
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = function(event)
        events[#events + 1] = event
        again = table.pack(API.showCallouts(data()))
    end }))
    step(2)
    TriggerEvent('onClientResourceStop', 'cortex-lib')
    eq(events[1] and events[1].reason, 'stopped')
    eq(again[1], false, 'not reopened while stopping')
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), false)
end)
check('the owner stopping closes its callouts without an event', function()
    boot()
    local events, handler = recorder()
    as('cortex-pinpoint', 'showCallouts', data({ onEvent = handler }))
    step(2)
    TriggerEvent('onClientResourceStop', 'cortex-pinpoint')
    eq(#events, 0)
    eq(as('cortex-pinpoint', 'isCalloutsOpen'), false)
end)
check('the cursor starts on the entity and controls are held while open', function()
    boot()
    as('cortex-pinpoint', 'showCallouts', data())
    step(2)
    truthy(s.cursorAt, 'the cursor was placed')
    truthy(s.cursorAt[1] > 0.3 and s.cursorAt[1] < 0.7, 'near the middle of the car')
    step()
    truthy(s.disabled[1] and s.disabled[24] and s.disabled[200], 'look, attack and pause held')
    eq(s.disabled[71], nil, 'driving stays with the player')
end)

print = realPrint
print(('callouts api: %d passed, %d failed'):format(passed, failed))
if failed > 0 then os.exit(1) end
