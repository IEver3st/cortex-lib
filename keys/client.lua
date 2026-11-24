local HOST = GetCurrentResourceName()
local INTERNAL = HOST == 'cortex-lib'
local EVENT_FIRE = HOST .. ':keys:fire'
local PREFIX = INTERNAL and 'cortex_' or (HOST:gsub('[^%w]', '_') .. '_')

local MAX_ID_BYTES = 48
local MAX_LABEL_BYTES = 32
local MAX_ACTIONS = 32
local MAX_ITEMS = 16
local MAX_PER_OWNER = 32
local HOLD_MS = 200
local ASK_TAIL_MS = 300
local ASK_DEFAULT_SECONDS = 20
local ASK_MAX_SECONDS = 120
local ASK_PRIORITY = 70
local LABEL_REFRESH_MS = 2000
local FOCUS_WAIT_MS = 500
local RESULT_WAIT_MS = 100
local DUCK_CONTROL = 73
local ROW_ANSWER = 'keys:answer'
local ROW_DECLINE = 'keys:decline'
local RADIAL_ID = 'cortex-actions'

local KEYS = {
    cancel = { command = PREFIX .. 'cancel', default = GetConvar('cortex_lib_cancel_key', 'X'), description = 'Cortex: cancel or put away' },
    answer = { command = PREFIX .. 'answer', default = GetConvar('cortex_lib_answer_key', 'Y'), description = 'Cortex: answer' },
    actions = { command = PREFIX .. 'actions', default = GetConvar('cortex_lib_actions_key', 'M'), description = 'Cortex: actions' },
    point = { command = PREFIX .. 'point', default = GetConvar('cortex_lib_point_key', 'B'), description = 'Cortex: point (tap) or hold' },
}

local serial = 0
local cancels = {}
local asks = {}
local actions = {}
local points = {}
local askEndedAt = -ASK_TAIL_MS
local rows = { answer = nil, decline = nil }
local watching = false
local ducking = false
local results = {}
local labels = {}
local press = nil
local internalCancels = {}

local function nextSerial()
    serial = serial + 1
    return serial
end

local function validId(value)
    return type(value) == 'string' and #value > 0 and #value <= MAX_ID_BYTES and not value:find('[%c]')
end

local function text(value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c]', ' '):match('^%s*(.-)%s*$')
    if value == '' then return nil end
    return value:sub(1, MAX_LABEL_BYTES)
end

local function validWhere(value)
    return value == nil or value == 'any' or value == 'foot' or value == 'vehicle'
end

local function caller()
    return GetInvokingResource() or HOST
end

local function owned(list, owner)
    local count = 0
    for _, entry in pairs(list) do
        if entry.owner == owner then count = count + 1 end
    end
    return count
end

local function place()
    return IsPedInAnyVehicle(PlayerPedId(), false) and 'vehicle' or 'foot'
end

local function matches(where, here)
    return where == nil or where == 'any' or where == here
end

local function radialOpen()
    local isOpen = rawget(lib, 'isRadialOpen')
    return isOpen and isOpen() == true
end

local function blocked()
    return IsNuiFocused() or IsPauseMenuActive() or radialOpen()
end

local function registry(fn, ...)
    local as = INTERNAL and rawget(lib, '_asInteractionOwner')
    if as then return as(HOST, fn, ...) end
    return fn(...)
end

local function fire(owner, kind, id, phase)
    TriggerEvent(EVENT_FIRE, owner, kind, id, phase)
end

local function label(kind)
    local key = KEYS[kind]
    if not key then return nil end
    local now = GetGameTimer()
    local cached = labels[kind]
    if cached and now - cached.at < LABEL_REFRESH_MS then return cached.text end
    local button = GetControlInstructionalButton(2, joaat('+' .. key.command) | 0x80000000, true)
    local found = type(button) == 'string' and button:match('^t_(.+)$') or nil
    local value = found and found:upper():sub(1, 12) or key.default
    labels[kind] = { text = value, at = now }
    return value
end

local function newest(list, accept)
    local best = nil
    for _, entry in pairs(list) do
        if (not accept or accept(entry)) and (not best or entry.seq > best.seq) then best = entry end
    end
    return best
end

local function hasCancelable()
    return next(cancels) ~= nil
end

local function showRow(slot, id, key, value)
    local current = rows[slot]
    local signature = key .. '|' .. value
    if current == signature then return end
    local ok = registry(lib.showInteraction, { id = id, label = value, key = key, priority = ASK_PRIORITY })
    rows[slot] = ok and signature or nil
end

local function hideRow(slot, id)
    if not rows[slot] then return end
    registry(lib.hideInteraction, id)
    rows[slot] = nil
end

local function declineShown(ask)
    return ask and ask.decline and place() == 'foot' and not hasCancelable()
end

local function refreshRows()
    local ask = newest(asks)
    if not ask then
        hideRow('answer', ROW_ANSWER)
        hideRow('decline', ROW_DECLINE)
        return
    end
    if ask.prompt then
        showRow('answer', ROW_ANSWER, label('answer'), ask.label)
    else
        hideRow('answer', ROW_ANSWER)
    end
    if declineShown(ask) then
        showRow('decline', ROW_DECLINE, label('cancel'), ask.decline)
    else
        hideRow('decline', ROW_DECLINE)
    end
end

local function endAsk(key, accepted, notify)
    local ask = asks[key]
    if not ask then return end
    asks[key] = nil
    askEndedAt = GetGameTimer()
    if notify then fire(ask.owner, 'ask', ask.id, accepted) end
    refreshRows()
end

local watch

local function ensureWatching()
    if watching then return end
    watching = true
    CreateThread(watch)
end

watch = function()
    while next(asks) do
        local now = GetGameTimer()
        for key, ask in pairs(asks) do
            if now >= ask.expires then
                local outcome = 'timeout'
                if ask.decline then outcome = false end
                endAsk(key, outcome, true)
            end
        end
        refreshRows()
        Wait(250)
    end
    watching = false
end

local function ensureDucking()
    if ducking then return end
    ducking = true
    CreateThread(function()
        while hasCancelable() do
            if IsPedInAnyVehicle(PlayerPedId(), false) then
                DisableControlAction(0, DUCK_CONTROL, true)
                Wait(0)
            else
                Wait(100)
            end
        end
        ducking = false
    end)
end

local function setCancelable(owner, id, on, fn)
    local key = owner .. '|' .. id
    if not on then
        cancels[key] = nil
        internalCancels[key] = nil
        refreshRows()
        return true
    end
    if not cancels[key] and owned(cancels, owner) >= MAX_PER_OWNER then return false, 'capacity' end
    cancels[key] = { owner = owner, id = id, seq = nextSerial() }
    internalCancels[key] = fn
    ensureDucking()
    refreshRows()
    return true
end

local function runCancel()
    while true do
        local entry = newest(cancels)
        if not entry then break end
        local key = entry.owner .. '|' .. entry.id
        cancels[key] = nil
        local fn = internalCancels[key]
        internalCancels[key] = nil
        local handled = true
        if fn then
            local ok, value = pcall(fn)
            handled = not (ok and value == false)
        else
            local token = nextSerial()
            results[token] = 'pending'
            fire(entry.owner, 'cancel', entry.id, token)
            local deadline = GetGameTimer() + RESULT_WAIT_MS
            while results[token] == 'pending' and GetGameTimer() < deadline do Wait(0) end
            handled = results[token] ~= false
            results[token] = nil
        end
        if handled then
            refreshRows()
            return
        end
    end
    local ask = newest(asks)
    if declineShown(ask) then endAsk(ask.owner .. '|' .. ask.id, false, true) end
end

local function answer()
    local ask = newest(asks)
    if ask then endAsk(ask.owner .. '|' .. ask.id, true, true) end
end

local function sortedActions(here)
    local list = {}
    for _, action in pairs(actions) do
        if matches(action.where, here) then list[#list + 1] = action end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.seq < b.seq
    end)
    while #list > MAX_ACTIONS do list[#list] = nil end
    return list
end

local function afterFocus(fn)
    CreateThread(function()
        local deadline = GetGameTimer() + FOCUS_WAIT_MS
        while IsNuiFocused() and GetGameTimer() < deadline do Wait(0) end
        Wait(0)
        if IsNuiFocused() or IsPauseMenuActive() then return end
        fn()
    end)
end

local function chooser(action, itemId)
    return function()
        afterFocus(function()
            if actions[action.owner .. '|' .. action.id] == action then fire(action.owner, 'action', action.id, itemId) end
        end)
    end
end

local function openActions()
    if blocked() then return end
    local list = sortedActions(place())
    if #list == 0 then return end
    local root = {}
    for index = 1, #list do
        local action = list[index]
        local item = { id = 'a' .. index, label = action.label, icon = action.icon }
        if action.items and #action.items > 0 then
            local menuId = RADIAL_ID .. ':' .. index
            local sub = {}
            for n = 1, #action.items do
                local child = action.items[n]
                sub[n] = { id = 'i' .. n, label = child.label, icon = child.icon, onSelect = chooser(action, child.id) }
            end
            if lib.registerRadial({ id = menuId, items = sub }) == false then
                item = nil
            else
                item.menu = menuId
            end
        else
            item.onSelect = chooser(action, nil)
        end
        if item then root[#root + 1] = item end
    end
    if #root == 0 or lib.registerRadial({ id = RADIAL_ID, items = root }) == false then return end
    lib.showRadial(RADIAL_ID)
end

local function bestPoint(kind, here)
    local best = nil
    for _, entry in pairs(points) do
        if entry[kind] and matches(entry.where, here)
            and (not best or entry.priority > best.priority or (entry.priority == best.priority and entry.seq > best.seq))
        then
            best = entry
        end
    end
    return best
end

local function endHold(notify)
    local current = press
    press = nil
    if current and current.holding and notify then
        local entry = points[current.holding]
        if entry then fire(entry.owner, 'point', entry.id, 'holdEnd') end
    end
end

local function startHold(current, entry)
    current.holding = entry.owner .. '|' .. entry.id
    fire(entry.owner, 'point', entry.id, 'holdStart')
    CreateThread(function()
        while press == current and current.holding do
            if IsNuiFocused() or IsPauseMenuActive() then
                endHold(true)
                return
            end
            Wait(50)
        end
    end)
end

local function pointDown()
    endHold(true)
    if blocked() then return end
    local here = place()
    local tap = bestPoint('tap', here)
    local hold = bestPoint('hold', here)
    if not tap and not hold then return end
    if tap and not hold then
        fire(tap.owner, 'point', tap.id, 'tap')
        return
    end
    local current = { token = nextSerial(), tap = tap and (tap.owner .. '|' .. tap.id) or nil }
    press = current
    if not tap then
        startHold(current, hold)
        return
    end
    SetTimeout(HOLD_MS, function()
        if press ~= current or current.holding then return end
        local entry = bestPoint('hold', place())
        if entry then startHold(current, entry) end
    end)
end

local function pointUp()
    local current = press
    if not current then return end
    if current.holding then
        endHold(true)
        return
    end
    press = nil
    local entry = current.tap and points[current.tap]
    if entry then fire(entry.owner, 'point', entry.id, 'tap') end
end

local function mapping(kind, down, up)
    local key = KEYS[kind]
    RegisterCommand('+' .. key.command, down, false)
    RegisterCommand('-' .. key.command, up or function() end, false)
    RegisterKeyMapping('+' .. key.command, key.description, 'keyboard', key.default)
end

mapping('cancel', function()
    if blocked() then return end
    runCancel()
end)

mapping('answer', function()
    if blocked() then return end
    answer()
end)

mapping('actions', openActions)

mapping('point', pointDown, pointUp)

AddEventHandler('onClientResourceStop', function(resource)
    for key, entry in pairs(cancels) do
        if entry.owner == resource then cancels[key] = nil; internalCancels[key] = nil end
    end
    for key, ask in pairs(asks) do
        if ask.owner == resource then asks[key] = nil end
    end
    for key, action in pairs(actions) do
        if action.owner == resource then actions[key] = nil end
    end
    if press and press.holding and points[press.holding] and points[press.holding].owner == resource then press = nil end
    for key, entry in pairs(points) do
        if entry.owner == resource then points[key] = nil end
    end
    refreshRows()
end)

exports('keysCancelable', function(id, on)
    if not validId(id) then return false, 'invalid_id' end
    return setCancelable(caller(), id, on == true)
end)

exports('keysResult', function(token, handled)
    if type(token) ~= 'number' then return end
    if results[token] == nil then
        print(('^3[%s] keys: late cancel result from %s; cancel callbacks must not yield^7'):format(HOST, tostring(caller())))
        return
    end
    results[token] = handled ~= false
end)

exports('keysAsk', function(id, spec)
    local owner = caller()
    if not validId(id) or type(spec) ~= 'table' then return false, 'invalid' end
    local value = text(spec.label)
    if not value then return false, 'invalid_label' end
    local key = owner .. '|' .. id
    if not asks[key] and owned(asks, owner) >= MAX_PER_OWNER then return false, 'capacity' end
    local seconds = tonumber(spec.seconds) or ASK_DEFAULT_SECONDS
    seconds = math.max(1, math.min(ASK_MAX_SECONDS, seconds))
    asks[key] = {
        owner = owner, id = id, label = value, decline = text(spec.decline), prompt = spec.prompt ~= false,
        expires = GetGameTimer() + math.floor(seconds * 1000), seq = nextSerial(),
    }
    refreshRows()
    ensureWatching()
    return true
end)

exports('keysEndAsk', function(id)
    if not validId(id) then return false end
    endAsk(caller() .. '|' .. id, false, false)
    return true
end)

exports('keysAskActive', function(id)
    if not validId(id) then return false end
    local ask = newest(asks)
    return ask ~= nil and ask.owner == caller() and ask.id == id
end)

exports('keysIsAsking', function()
    return next(asks) ~= nil or GetGameTimer() - askEndedAt < ASK_TAIL_MS
end)

exports('keysAddAction', function(id, spec)
    local owner = caller()
    if not validId(id) or type(spec) ~= 'table' or not validWhere(spec.where) then return false, 'invalid' end
    local value = text(spec.label)
    if not value then return false, 'invalid_label' end
    local items = nil
    if type(spec.items) == 'table' then
        items = {}
        for index = 1, math.min(#spec.items, MAX_ITEMS) do
            local child = spec.items[index]
            local childLabel = type(child) == 'table' and text(child.label)
            if not childLabel or not validId(child.id) then return false, 'invalid_item' end
            items[index] = { id = child.id, label = childLabel, icon = type(child.icon) == 'string' and child.icon or nil }
        end
    end
    local key = owner .. '|' .. id
    if not actions[key] and owned(actions, owner) >= MAX_PER_OWNER then return false, 'capacity' end
    actions[key] = {
        owner = owner, id = id, label = value, icon = type(spec.icon) == 'string' and spec.icon or nil,
        where = spec.where or 'any', order = tonumber(spec.order) or 50, items = items,
        seq = actions[key] and actions[key].seq or nextSerial(),
    }
    return true
end)

exports('keysRemoveAction', function(id)
    if not validId(id) then return false end
    actions[caller() .. '|' .. id] = nil
    return true
end)

exports('keysPoint', function(id, spec)
    local owner = caller()
    if not validId(id) then return false, 'invalid_id' end
    local key = owner .. '|' .. id
    if spec == false or spec == nil then
        if press and press.holding == key then endHold(true) end
        points[key] = nil
        return true
    end
    if type(spec) ~= 'table' or not validWhere(spec.where) then return false, 'invalid' end
    if not points[key] and owned(points, owner) >= MAX_PER_OWNER then return false, 'capacity' end
    points[key] = {
        owner = owner, id = id, tap = spec.tap == true, hold = spec.hold == true,
        where = spec.where or 'any', priority = tonumber(spec.priority) or 0,
        seq = points[key] and points[key].seq or nextSerial(),
    }
    return true
end)

exports('keysLabel', function(kind)
    return label(kind)
end)

lib._keysCancelable = function(id, fn)
    return setCancelable(HOST, id, fn ~= false and fn ~= nil, fn)
end
