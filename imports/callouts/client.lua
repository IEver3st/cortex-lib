-- Callouts: hold a key and every part of an entity (a vehicle's doors,
-- windows, seats, engine) gets a pin, a square leader and a label beside it,
-- with a block of switches; the player points and clicks. This module owns
-- the public API: validation and owner scoping. client/callout_renderer.lua
-- alone projects, lays out, draws and reads the pointer.
--
-- Display only, like interaction prompts: the owner registers its own key
-- mapping, decides what every row and switch says, and acts on the events it
-- is sent. Nothing here authorizes anything; revalidate on the server.
--
-- showCallouts(data) opens the invoking resource's callouts, or updates them
-- in place when they are already up on the same entity (call it on state
-- changes, never every frame). One session is up at a time; another
-- resource's replaces it. See docs/api.md **Callouts** for the fields.

local CURRENT_RESOURCE = GetCurrentResourceName()
local MAX_CALLOUTS, MAX_ROWS, MAX_SWITCHES, MAX_CHIPS, MAX_TEXTS = 48, 4, 24, 64, 8
local TONES = { off = true, on = true, you = true, no = true }

local function getInvokingOwner()
    local owner = GetInvokingResource and GetInvokingResource() or nil
    return owner or CURRENT_RESOURCE
end

local function boundedString(value, maxLength, allowEmpty)
    return type(value) == 'string'
        and (allowEmpty or value ~= '')
        and #value <= maxLength
        and not value:find('\0', 1, true)
end

local function finite(value, limit)
    return type(value) == 'number' and value == value and math.abs(value) <= limit
end

-- Handlers from other resources arrive as Cfx funcrefs: callable tables whose
-- fields throw when indexed. Check the metatable, never the table itself.
local function isCallable(value)
    if type(value) == 'function' then return true end
    if type(value) ~= 'table' then return false end
    local mt = getmetatable(value)
    return type(mt) == 'table' and type(rawget(mt, '__call')) == 'function'
end

local function isDenseArray(value, maxItems)
    if type(value) ~= 'table' then return false end
    local length = #value
    if length > maxItems then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or math.tointeger(key) ~= key or key < 1 or key > length then return false end
        count = count + 1
    end
    return count == length
end

-- A vector3 or { x, y, z } within `limit` of zero on each axis.
local function readVector(value, limit)
    local kind = type(value)
    if kind ~= 'vector3' and kind ~= 'table' then return nil end
    local x, y, z = value.x, value.y, value.z
    if not (finite(x, limit) and finite(y, limit) and finite(z, limit)) then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

local function readRow(row, ids)
    if type(row) ~= 'table' or not boundedString(row.id, 64) or ids[row.id] then return nil, 'invalid_row_id' end
    if not boundedString(row.name, 48) then return nil, 'invalid_row_name' end
    if row.chip ~= nil and not boundedString(row.chip, 32, true) then return nil, 'invalid_row_chip' end
    if row.tone ~= nil and not TONES[row.tone] then return nil, 'invalid_row_tone' end
    ids[row.id] = true
    return { id = row.id, name = row.name, chip = row.chip or '', tone = row.tone or 'off',
        hidden = row.hidden == true or nil, pending = row.pending == true or nil }
end

local function readSwitch(item, ids)
    if type(item) ~= 'table' or not boundedString(item.id, 64) or ids[item.id] then return nil, 'invalid_switch_id' end
    if not boundedString(item.text, 48) then return nil, 'invalid_switch_text' end
    if item.tone ~= nil and not TONES[item.tone] then return nil, 'invalid_switch_tone' end
    local texts = {}
    if item.texts ~= nil then
        if not isDenseArray(item.texts, MAX_TEXTS) then return nil, 'invalid_switch_texts' end
        for i, text in ipairs(item.texts) do
            if not boundedString(text, 48) then return nil, 'invalid_switch_texts' end
            texts[i] = text
        end
    end
    ids[item.id] = true
    return { id = item.id, text = item.text, texts = texts, tone = item.tone or 'off',
        hidden = item.hidden == true or nil, pending = item.pending == true or nil }
end

local function normalize(data)
    if type(data) ~= 'table' then return nil, 'invalid_data' end
    local entity = math.tointeger(data.entity)
    if not entity or entity <= 0 then return nil, 'invalid_entity' end
    local model
    if data.model ~= nil then
        model = math.tointeger(data.model)
        if not model then return nil, 'invalid_model' end
    end
    local bounds
    if data.bounds ~= nil then
        if type(data.bounds) ~= 'table' then return nil, 'invalid_bounds' end
        local lo, hi = readVector(data.bounds.min, 100), readVector(data.bounds.max, 100)
        if not lo or not hi or lo.x > hi.x or lo.y > hi.y or lo.z > hi.z then return nil, 'invalid_bounds' end
        bounds = { min = lo, max = hi }
    end

    -- Row and switch ids share one namespace: events and effects name them.
    local ids, calloutIds = {}, {}
    local callouts = {}
    if data.callouts ~= nil and not isDenseArray(data.callouts, MAX_CALLOUTS) then return nil, 'invalid_callouts' end
    for i, c in ipairs(data.callouts or {}) do
        if type(c) ~= 'table' or not boundedString(c.id, 64) or calloutIds[c.id] then return nil, 'invalid_callout_id' end
        local offset = readVector(c.offset, 50)
        if not offset then return nil, 'invalid_callout_offset' end
        local order = c.order == nil and i or c.order
        if not finite(order, 1e6) then return nil, 'invalid_callout_order' end
        if not isDenseArray(c.rows, MAX_ROWS) or #c.rows == 0 then return nil, 'invalid_callout_rows' end
        local rows = {}
        for j, r in ipairs(c.rows) do
            local row, err = readRow(r, ids)
            if not row then return nil, err end
            rows[j] = row
        end
        calloutIds[c.id] = true
        callouts[i] = { id = c.id, offset = offset, order = order, minor = c.minor == true or nil, rows = rows }
    end

    local switches = {}
    if data.switches ~= nil and not isDenseArray(data.switches, MAX_SWITCHES) then return nil, 'invalid_switches' end
    for i, item in ipairs(data.switches or {}) do
        local sw, err = readSwitch(item, ids)
        if not sw then return nil, err end
        switches[i] = sw
    end

    local title
    if data.title ~= nil then
        local t = data.title
        if type(t) ~= 'table' or not boundedString(t.name, 48) or (t.chip ~= nil and not boundedString(t.chip, 32, true)) then
            return nil, 'invalid_title'
        end
        title = { name = t.name, chip = t.chip or '' }
    end

    local chips = {}
    if data.chips ~= nil then
        if not isDenseArray(data.chips, MAX_CHIPS) then return nil, 'invalid_chips' end
        for i, text in ipairs(data.chips) do
            if not boundedString(text, 32) then return nil, 'invalid_chips' end
            chips[i] = text
        end
    end

    if data.onEvent ~= nil and not isCallable(data.onEvent) then return nil, 'invalid_onEvent' end
    if #callouts == 0 and #switches == 0 and not title then return nil, 'empty' end

    return { entity = entity, model = model, bounds = bounds, callouts = callouts, switches = switches,
        title = title, chips = chips, onEvent = data.onEvent }
end

local function renderer()
    return lib._calloutRenderer
end

local function showCallouts(data)
    -- A function where a table belongs arrives as a funcref, which throws
    -- when indexed: refused like any other malformed field.
    local ok, normalized, err = pcall(normalize, data)
    if not ok then return false, 'invalid_data' end
    if not normalized then return false, err end
    local R = renderer()
    if not R then return false, 'unavailable' end
    return R.show(getInvokingOwner(), normalized)
end

local function hideCallouts()
    local R = renderer()
    return R ~= nil and R.hide(getInvokingOwner())
end

local function calloutEffect(id, kind)
    if not boundedString(id, 64) or (kind ~= 'pop' and kind ~= 'shake') then return false end
    local R = renderer()
    return R ~= nil and R.effect(getInvokingOwner(), id, kind)
end

local function isCalloutsOpen()
    local R = renderer()
    return R ~= nil and R.isOpen(getInvokingOwner())
end

local function getCalloutState()
    local R = renderer()
    if not R then return { open = false } end
    return R.state(getInvokingOwner())
end

local function prepareCallouts()
    local R = renderer()
    return R ~= nil and R.prepare()
end

exports('showCallouts', showCallouts)
exports('hideCallouts', hideCallouts)
exports('calloutEffect', calloutEffect)
exports('isCalloutsOpen', isCalloutsOpen)
exports('getCalloutState', getCalloutState)
exports('prepareCallouts', prepareCallouts)

lib.showCallouts = showCallouts
lib.hideCallouts = hideCallouts
lib.calloutEffect = calloutEffect
lib.isCalloutsOpen = isCalloutsOpen
lib.getCalloutState = getCalloutState
lib.prepareCallouts = prepareCallouts

return {
    showCallouts = showCallouts,
    hideCallouts = hideCallouts,
    calloutEffect = calloutEffect,
    isCalloutsOpen = isCalloutsOpen,
    getCalloutState = getCalloutState,
    prepareCallouts = prepareCallouts,
}
