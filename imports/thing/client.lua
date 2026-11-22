local HOST = rawget(_G, 'CortexThingHost') or 'cortex-lib'
local RESOURCE = GetCurrentResourceName()
local EVALUATE_MS = 250

local defs = {}
local near = {}
local evaluating = false

local function fail(where, err)
    print(('^1[%s] thing %s failed: %s^7'):format(RESOURCE, where, tostring(err)))
end

local function context(def, entity, record, verbId)
    local coords = GetEntityCoords(entity)
    local ctx = {
        entity = entity, key = record.key, data = record.data, coords = coords,
        distance = #(coords - GetEntityCoords(PlayerPedId())), verb = verbId,
    }
    return setmetatable(ctx, {
        __index = function(_, field)
            if field == 'locked' then return exports[HOST]:thingLocked(def.id, entity) == true end
            return nil
        end,
    })
end

local function evaluate(entry)
    local def, entity, record = entry.def, entry.entity, entry.record
    if not DoesEntityExist(entity) then return end

    local ctx = context(def, entity, record)
    local status = nil
    if def.status then
        local ok, value = pcall(def.status, ctx)
        if ok then status = value else fail(def.id .. ' status', value) end
    end

    local states = {}
    local parts = { tostring(status) }
    for index = 1, #def.verbs do
        local verb = def.verbs[index]
        ctx.verb = verb.id
        local usable, reason = true, nil
        if verb.can then
            local ok, allowed, why = pcall(verb.can, ctx)
            if ok then
                usable, reason = allowed == true, type(why) == 'string' and why or nil
            else
                usable = false
                fail(def.id .. ':' .. verb.id .. ' can', allowed)
            end
        end
        local label = nil
        if type(verb.label) == 'function' then
            local ok, value = pcall(verb.label, ctx)
            if ok then label = value else fail(def.id .. ':' .. verb.id .. ' label', value) end
        end
        states[index] = { usable = usable, reason = reason, label = label }
        parts[#parts + 1] = (usable and '1' or '0') .. tostring(reason) .. tostring(label)
    end

    local signature = table.concat(parts, '|')
    if signature ~= entry.sent and exports[HOST]:thingReport(def.id, entity, status, states) then
        entry.sent = signature
    end
end

local function evaluateAll()
    for index = 1, #near do
        local entry = near[index]
        if entry then evaluate(entry) end
    end
end

local function ensureEvaluating()
    if evaluating then return end
    evaluating = true
    CreateThread(function()
        while #near > 0 do
            local ok, err = pcall(evaluateAll)
            if not ok then
                near = {}
                fail('report', err)
            end
            Wait(EVALUATE_MS)
        end
        evaluating = false
    end)
end

AddEventHandler(HOST .. ':thing:near', function(owner, list)
    if owner ~= RESOURCE or type(list) ~= 'table' then return end

    local previous = {}
    for index = 1, #near do
        local entry = near[index]
        previous[entry.def.id .. '|' .. entry.entity] = entry
    end

    local updated = {}
    for index = 1, #list do
        local item = list[index]
        local def = defs[item.thing]
        local record = def and def.records[item.entity]
        if record then
            updated[#updated + 1] = previous[def.id .. '|' .. item.entity]
                or { def = def, entity = item.entity, record = record }
        end
    end
    near = updated
    ensureEvaluating()
end)

local function resolve(owner, thingId, entity, verbId)
    if owner ~= RESOURCE then return nil end
    local def = defs[thingId]
    local record = def and def.records[entity]
    local verb = def and def.byId[verbId]
    if not record or not verb then return nil end
    return def, record, verb
end

AddEventHandler(HOST .. ':thing:stand', function(owner, token, thingId, entity, verbId)
    local def, record, verb = resolve(owner, thingId, entity, verbId)
    if not def then return end

    local coords, heading = nil, nil
    if verb.stand then
        local ok, where, facing = pcall(verb.stand, context(def, entity, record, verbId))
        if ok then coords, heading = where, facing else fail(thingId .. ':' .. verbId .. ' stand', where) end
    end
    if coords then
        exports[HOST]:thingStandAt(token, coords.x, coords.y, coords.z, heading)
    else
        exports[HOST]:thingStandAt(token)
    end
end)

AddEventHandler(HOST .. ':thing:go', function(owner, _, thingId, entity, verbId, reply)
    local def, record, verb = resolve(owner, thingId, entity, verbId)
    if not def then
        if owner == RESOURCE then exports[HOST]:thingDone(thingId, entity) end
        return
    end

    local ctx = context(def, entity, record, verbId)
    local held, returned = false, false
    ctx.hold = function()
        held = true
        if returned then exports[HOST]:thingHold(thingId, entity) end
    end
    ctx.done = function()
        held = false
        exports[HOST]:thingDone(thingId, entity)
    end

    if verb.run then
        local ok, err = pcall(verb.run, ctx, reply)
        if not ok then fail(thingId .. ':' .. verbId .. ' run', err) end
    end
    returned = true
    if not held then exports[HOST]:thingDone(thingId, entity) end
end)

AddEventHandler(HOST .. ':thing:stop', function(owner, _, thingId, entity, verbId, why)
    local def, record, verb = resolve(owner, thingId, entity, verbId)
    if not def or not verb.cancel then return end
    local ok, err = pcall(verb.cancel, context(def, entity, record, verbId), why)
    if not ok then fail(thingId .. ':' .. verbId .. ' cancel', err) end
end)

local Thing = {}
Thing.__index = Thing

function Thing:add(entity, options)
    options = options or {}
    local key = options.key
    if key == nil then key = entity end
    local offset = type(options.anchor) == 'table' and options.anchor.offset or nil
    local plain = offset and { x = offset.x, y = offset.y, z = offset.z } or nil
    local ok, err = exports[HOST]:thingAdd(self.id, entity, key, plain)
    if not ok then return false, err end
    self.records[entity] = { key = key, data = options.data }
    return true
end

function Thing:remove(entity)
    self.records[entity] = nil
    return exports[HOST]:thingRemove(self.id, entity) == true
end

function Thing:destroy()
    defs[self.id] = nil
    self.records = {}
    return exports[HOST]:thingDestroy(self.id) == true
end

local function define(spec)
    if type(spec) ~= 'table' or type(spec.id) ~= 'string' or type(spec.verbs) ~= 'table' then
        error('lib.thing needs an id and verbs', 3)
    end

    local plain = {}
    local byId = {}
    for index = 1, #spec.verbs do
        local verb = spec.verbs[index]
        byId[verb.id] = verb
        plain[index] = {
            id = verb.id,
            label = type(verb.label) == 'string' and verb.label or nil,
            hold = verb.hold,
            server = verb.server == true,
            stand = verb.stand ~= nil,
        }
    end

    local ok, err = exports[HOST]:thingDefine(spec.id, {
        range = spec.range, markerRange = spec.markerRange, verbs = plain,
    })
    if not ok then error(('lib.thing(%s): %s'):format(spec.id, tostring(err)), 3) end

    local def = setmetatable({
        id = spec.id, status = spec.status, verbs = spec.verbs, byId = byId, records = {},
    }, Thing)
    defs[spec.id] = def
    return def
end

return setmetatable({
    busy = function(state)
        return exports[HOST]:thingBusy(state == true)
    end,
}, {
    __call = function(_, spec)
        return define(spec)
    end,
})
