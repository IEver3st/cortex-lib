local HOST = rawget(_G, 'CortexKeysHost') or 'cortex-lib'
local RESOURCE = GetCurrentResourceName()
local EVENT_FIRE = HOST .. ':keys:fire'
local FALLBACK = { cancel = 'X', answer = 'Y', actions = 'M', point = 'B' }

local READY_WAIT_MS = 5000

local function hostReady()
    if GetResourceMetadata(HOST, 'cortex_keys', 0) ~= '1' then return false end
    local state = GetResourceState(HOST)
    if state == 'starting' and coroutine.isyieldable() then
        local deadline = GetGameTimer() + READY_WAIT_MS
        while state == 'starting' and GetGameTimer() < deadline do
            Wait(50)
            state = GetResourceState(HOST)
        end
    end
    return state == 'started'
end

local keys = { available = hostReady() }
local cancels = {}
local asks = {}
local actions = {}
local points = {}

local function fail(where, err)
    print(('^1[%s] keys %s failed: %s^7'):format(RESOURCE, where, tostring(err)))
end

local function call(name, ...)
    if not keys.available or GetResourceState(HOST) ~= 'started' then return false end
    local args = table.pack(...)
    local ok, result = pcall(function()
        local host = exports[HOST]
        return host[name](host, table.unpack(args, 1, args.n))
    end)
    if not ok then
        fail(name, result)
        return false
    end
    return result
end

local function plainAsk(spec)
    return { label = spec.label, decline = spec.decline, seconds = spec.seconds, prompt = spec.prompt }
end

local function plainAction(spec)
    local items = nil
    if type(spec.items) == 'table' then
        items = {}
        for index = 1, #spec.items do
            local child = spec.items[index]
            items[index] = { id = child.id, label = child.label, icon = child.icon }
        end
    end
    return { label = spec.label, icon = spec.icon, where = spec.where, order = spec.order, items = items }
end

local function plainPoint(spec)
    return { tap = spec.tap, hold = spec.hold, where = spec.where, priority = spec.priority }
end

function keys.cancelable(id, fn)
    if not fn then
        cancels[id] = nil
        return call('keysCancelable', id, false)
    end
    cancels[id] = fn
    return call('keysCancelable', id, true)
end

function keys.ask(id, spec, fn)
    asks[id] = { spec = spec, fn = fn }
    return call('keysAsk', id, plainAsk(spec))
end

function keys.endAsk(id)
    asks[id] = nil
    return call('keysEndAsk', id)
end

function keys.askActive(id)
    return call('keysAskActive', id) == true
end

function keys.isAsking()
    return call('keysIsAsking') == true
end

function keys.label(kind)
    local value = call('keysLabel', kind)
    return type(value) == 'string' and value or FALLBACK[kind]
end

function keys.addAction(id, spec, fn)
    actions[id] = { spec = spec, fn = fn }
    return call('keysAddAction', id, plainAction(spec))
end

function keys.removeAction(id)
    actions[id] = nil
    return call('keysRemoveAction', id)
end

function keys.onPoint(id, spec, fn)
    if not spec then
        local result = call('keysPoint', id, false)
        points[id] = nil
        return result
    end
    points[id] = { spec = spec, fn = fn }
    return call('keysPoint', id, plainPoint(spec))
end

AddEventHandler(EVENT_FIRE, function(owner, kind, id, phase)
    if owner ~= RESOURCE then return end
    if kind == 'cancel' then
        local fn = cancels[id]
        cancels[id] = nil
        local handled = false
        if fn then
            local ok, value = pcall(fn)
            if not ok then fail('cancel ' .. tostring(id), value) end
            handled = not (ok and value == false)
        end
        call('keysResult', phase, handled)
    elseif kind == 'ask' then
        local entry = asks[id]
        asks[id] = nil
        if entry and entry.fn and type(phase) == 'boolean' then
            local ok, err = pcall(entry.fn, phase)
            if not ok then fail('ask ' .. tostring(id), err) end
        end
    elseif kind == 'action' then
        local entry = actions[id]
        if entry and entry.fn then
            local ok, err = pcall(entry.fn, phase)
            if not ok then fail('action ' .. tostring(id), err) end
        end
    elseif kind == 'point' then
        local entry = points[id]
        if entry and entry.fn then
            local ok, err = pcall(entry.fn, phase)
            if not ok then fail('point ' .. tostring(id), err) end
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= HOST then return end
    keys.available = GetResourceMetadata(HOST, 'cortex_keys', 0) == '1'
    for id in pairs(cancels) do call('keysCancelable', id, true) end
    for id, entry in pairs(asks) do call('keysAsk', id, plainAsk(entry.spec)) end
    for id, entry in pairs(actions) do call('keysAddAction', id, plainAction(entry.spec)) end
    for id, entry in pairs(points) do call('keysPoint', id, plainPoint(entry.spec)) end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == HOST then keys.available = false end
end)

CortexKeys = keys

return keys
