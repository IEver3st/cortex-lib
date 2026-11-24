local HOST = GetCurrentResourceName()
local INTERNAL = HOST == 'cortex-lib'
local ASK = HOST .. ':thing:ask'
local LOCKS = HOST .. ':thing:locks'
local EVENT_LOCK = HOST .. ':thing:lock'
local EVENT_CANCEL = HOST .. ':thing:cancel'
local EVENT_NEAR = HOST .. ':thing:near'
local EVENT_STAND = HOST .. ':thing:stand'
local EVENT_GO = HOST .. ':thing:go'
local EVENT_STOP = HOST .. ':thing:stop'
local USE_COMMAND = INTERNAL and 'cortex_use' or (HOST:gsub('[^%w]', '_') .. '_use')
local USE_HASH = joaat('+' .. USE_COMMAND) | 0x80000000
local DEFAULT_KEY = GetConvar('cortex_lib_use_key', 'E')

local MAX_ID_BYTES = 48
local MAX_LABEL_BYTES = 24
local MAX_NOTE_BYTES = 40
local MAX_VERBS = 8
local MAX_INSTANCES_PER_OWNER = 1024
local MAX_NEAR = 8
local MAX_ROWS = 8
local MAX_NEAREST_VERBS = 4
local MAX_KEYS_PER_QUERY = 64
local LOCK_RANGE_SQUARED = 100.0 * 100.0
local SCAN_MS = 200
local SCAN_STILL_MS = 500
local VALIDATE_PER_SCAN = 16
local FEED_PRIORITY = 20
local REFUSAL_MS = 2500
local ASK_TIMEOUT_MS = 3000
local STAND_REPLY_MS = 500
local WALK_DEADLINE_MS = 2600
local WALK_START_MS = 400
local TASK_GO_STRAIGHT = 0x7D8F4411
local KEY_REFRESH_MS = 2000

local things = {}
local instances = {}
local busy = {}
local nearList = {}
local nearSignature = ''
local shown = {}
local serial = 0
local cursor = 0
local scanning = false
local feedQueued = false
local use = nil
local token = 0
local pressed = false
local holding = false
local lookEntity = nil
local quotaLogged = false
local keyLabel = DEFAULT_KEY
local keyLabelAt = -KEY_REFRESH_MS
local customKeys = {}
local lastX, lastY, lastZ = 0.0, 0.0, 0.0
local standReplies = {}
local rich = nil

local function validId(value)
    return type(value) == 'string' and #value > 0 and #value <= MAX_ID_BYTES and not value:find('[%c]')
end

local function normalizeCustomKey(value)
    if type(value) ~= 'string' then return nil end
    local cleaned = value:match('^%s*(.-)%s*$'):upper()
    if cleaned == '' or #cleaned > 12 or not cleaned:match('^[%w_]+$') then return nil end
    if cleaned == DEFAULT_KEY:upper() then return nil end
    return cleaned
end

local function keyText(key)
    local whole = type(key) == 'number' and math.tointeger(key)
    if whole then return 'n:' .. whole end
    if validId(key) then return 's:' .. key end
    return nil
end

local function text(value, limit)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c]', ' '):match('^%s*(.-)%s*$')
    if value == '' then return nil end
    return value:sub(1, limit or MAX_NOTE_BYTES)
end

local function supportsRichRows()
    if rich == nil then
        if INTERNAL then
            rich = rawget(lib, '_interactionRowFields') == true
        else
            local ok, value = pcall(function() return exports['cortex-lib']:interactionSupports('blocked') end)
            rich = ok and value == true
        end
    end
    return rich
end

local function registry(fn, ...)
    local as = INTERNAL and rawget(lib, '_asInteractionOwner')
    if as then return as(HOST, fn, ...) end
    return fn(...)
end

local function serverId()
    return GetPlayerServerId(PlayerId())
end

local function downed(ped)
    local state = LocalPlayer.state
    return IsEntityDead(ped) or IsPedFatallyInjured(ped) or state.isDead == true or state.inLaststand == true
end

local function suppressed()
    if next(busy) then return true end
    local skillCheck = INTERNAL and rawget(lib, '_skillCheckRunning')
    if skillCheck and skillCheck() then return true end
    local ped = PlayerPedId()
    return downed(ped) or IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, true)
        or IsPedSwimming(ped) or IsNuiFocused() or IsPauseMenuActive()
end

local function refreshKeyLabel(now)
    if now - keyLabelAt >= KEY_REFRESH_MS then
        keyLabelAt = now
        local button = GetControlInstructionalButton(2, USE_HASH, true)
        local label = type(button) == 'string' and button:match('^t_(.+)$') or nil
        keyLabel = label and label:upper():sub(1, 12) or DEFAULT_KEY
    end
    for key, entry in pairs(customKeys) do
        if now - entry.labelAt >= KEY_REFRESH_MS then
            entry.labelAt = now
            local button = GetControlInstructionalButton(2, entry.hash, true)
            local label = type(button) == 'string' and button:match('^t_(.+)$') or nil
            entry.label = label and label:upper():sub(1, 12) or key
        end
    end
end

local function keyLabelFor(bindKey)
    if not bindKey then return keyLabel end
    local entry = customKeys[bindKey]
    return entry and entry.label or bindKey
end

local rebuildFeed

local function requestFeed()
    if feedQueued then return end
    feedQueued = true
    SetTimeout(0, function()
        feedQueued = false
        rebuildFeed()
    end)
end

local function dropInstance(inst)
    if inst.gone then return end
    inst.gone = true
    local def = inst.def
    def.byEntity[inst.entity] = nil
    if def.byKey[inst.keyText] == inst then def.byKey[inst.keyText] = nil end
    def.count = def.count - 1
    for index = #instances, 1, -1 do
        if instances[index] == inst then
            instances[index] = instances[#instances]
            instances[#instances] = nil
            break
        end
    end
end

local function dropThing(def)
    local list = {}
    for _, inst in pairs(def.byEntity) do list[#list + 1] = inst end
    for index = 1, #list do dropInstance(list[index]) end
    local owned = things[def.owner]
    if owned and owned[def.id] == def then
        owned[def.id] = nil
        if not next(owned) then things[def.owner] = nil end
    end
end

local function thingOf(owner, thingId)
    local owned = things[owner]
    return owned and owned[thingId] or nil
end

local function instanceOf(owner, thingId, entity)
    local def = thingOf(owner, thingId)
    return def and def.byEntity[entity] or nil
end

local function rowAnchor(inst)
    local def = inst.def
    return {
        type = 'entity',
        entity = inst.entity,
        model = inst.model,
        offset = inst.offset,
        maxDistance = def.range,
        markerDistance = def.markerRange,
    }
end

local function blockedRow(inst, reason)
    if not supportsRichRows() then return nil end
    return {
        id = ('t%d:0'):format(inst.serial), inst = inst, blocked = true,
        label = reason, key = keyLabel,
    }
end

local function rowsFor(inst, nearest, now, out)
    local report = inst.report
    if inst.hidden or not report then return end

    local refusal = inst.refusal and now < inst.refusalUntil and inst.refusal or nil
    if inst.lockHolder ~= 0 and inst.lockHolder ~= serverId() then
        out[#out + 1] = blockedRow(inst, 'In use')
        return
    end

    local verbs = inst.def.verbs
    local usable = {}
    local reason = nil
    for index = 1, #verbs do
        local state = report.verbs[index]
        if state and state.usable then
            usable[#usable + 1] = index
        elseif state and state.reason and not reason then
            reason = state.reason
        end
    end

    local note = refusal or report.status
    if #usable == 0 then
        local why = note or reason
        if why then out[#out + 1] = blockedRow(inst, why) end
        return
    end

    local count = nearest and math.min(#usable, MAX_NEAREST_VERBS) or 1
    for position = 1, count do
        local index = usable[position]
        local verb = verbs[index]
        out[#out + 1] = {
            id = ('t%d:%d'):format(inst.serial, index), inst = inst, verb = verb,
            label = report.verbs[index].label or verb.label,
            key = keyLabelFor(verb.key), bindKey = verb.key,
            holdDuration = verb.hold, note = note,
            more = position == 1 and count > 1 and count - 1 or nil,
        }
    end
end

local function rowSignature(row)
    local inst = row.inst
    local offset = inst.offset
    local richRows = supportsRichRows()
    return table.concat({
        row.label, row.key, row.holdDuration or 0,
        richRows and row.note or '', richRows and row.more or 0, row.blocked and 1 or 0,
        inst.entity, offset.x, offset.y, offset.z,
    }, '|')
end

rebuildFeed = function()
    local now = GetGameTimer()
    local desired = {}
    if not (use and use.accepted) and not suppressed() then
        refreshKeyLabel(now)
        for index = 1, #nearList do
            if #desired >= MAX_ROWS then break end
            local inst = nearList[index]
            if not inst.gone then rowsFor(inst, index == 1, now, desired) end
        end
    end
    while #desired > MAX_ROWS do desired[#desired] = nil end

    local keep = {}
    for index = 1, #desired do keep[desired[index].id] = true end
    for id in pairs(shown) do
        if not keep[id] then
            registry(lib.hideInteraction, id)
            shown[id] = nil
        end
    end

    local richRows = supportsRichRows()
    for index = 1, #desired do
        local row = desired[index]
        local signature = rowSignature(row)
        local current = shown[row.id]
        if not current or current.signature ~= signature then
            local ok, err = registry(lib.showInteraction, {
                id = row.id, label = row.label, key = row.key, priority = FEED_PRIORITY,
                holdDuration = row.holdDuration, anchor = rowAnchor(row.inst),
                note = richRows and row.note or nil,
                more = richRows and row.more or nil,
                blocked = richRows and row.blocked or nil,
            })
            if ok then
                row.signature = signature
                shown[row.id] = row
            else
                shown[row.id] = nil
                if not quotaLogged then
                    quotaLogged = true
                    print(('^3[%s] a thing could not show its prompt: %s^7'):format(HOST, tostring(err)))
                end
            end
        else
            current.inst, current.verb = row.inst, row.verb
        end
    end
end

local function refuse(inst, reason)
    reason = text(reason) or 'Not available'
    inst.refusal = reason
    inst.refusalUntil = GetGameTimer() + REFUSAL_MS
    requestFeed()
    SetTimeout(REFUSAL_MS + 50, requestFeed)

    if rawget(lib, '_logNotice') then
        lib._logNotice({
            key = ('thing:%s:%s:%s'):format(inst.def.owner, inst.def.id, reason),
            owner = inst.def.owner, type = 'error', title = reason, shown = false,
        })
    end
    if not supportsRichRows() then
        lib.notify({ description = reason, type = 'error' })
    end
end

local function publishNear(owners)
    for owner in pairs(owners) do
        local list = {}
        for index = 1, #nearList do
            local inst = nearList[index]
            if inst.def.owner == owner then
                list[#list + 1] = { thing = inst.def.id, entity = inst.entity }
            end
        end
        TriggerEvent(EVENT_NEAR, owner, list)
    end
end

local function applyLock(inst, holder, counter)
    if counter < inst.lockCounter then return end
    local me = serverId()
    local previous = inst.lockHolder
    inst.lockHolder = holder
    inst.lockCounter = counter
    if previous == me and holder ~= me then inst.hidden = false end
    if previous ~= holder then requestFeed() end
end

local function queryLocks(def, batch)
    local keys = {}
    for index = 1, #batch do keys[index] = batch[index].key end
    lib.callback(LOCKS, false, function(list, serverCounter)
        if type(list) ~= 'table' or type(serverCounter) ~= 'number' then return end
        local held = {}
        for index = 1, #list do
            local entry = list[index]
            local id = type(entry) == 'table' and keyText(entry.key)
            if id then held[id] = entry end
        end
        for index = 1, #batch do
            local inst = batch[index]
            if not inst.gone then
                local entry = held[inst.keyText]
                if entry then
                    applyLock(inst, tonumber(entry.holder) or 0, tonumber(entry.counter) or serverCounter)
                else
                    applyLock(inst, 0, serverCounter)
                end
            end
        end
    end, def.owner, def.id, keys)
end

local function updateLook(ped)
    local target = nil
    local first = nearList[1]
    local walking = use ~= nil and use.accepted == true
    for id, row in pairs(shown) do
        row.visible = registry(lib.isInteractionVisible, id) == true
        if row.visible and row.inst == first and not walking then target = first.entity end
    end
    if target == lookEntity then return end
    if lookEntity then TaskClearLookAt(ped) end
    if target then TaskLookAtEntity(ped, target, -1, 2048, 3) end
    lookEntity = target
end

local function scan()
    local ped = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local px, py, pz = origin.x, origin.y, origin.z

    for _ = 1, math.min(VALIDATE_PER_SCAN, #instances) do
        if #instances == 0 then break end
        cursor = cursor % #instances + 1
        local inst = instances[cursor]
        if not DoesEntityExist(inst.entity) or GetEntityModel(inst.entity) ~= inst.model then
            dropInstance(inst)
        else
            local coords = GetEntityCoords(inst.entity)
            inst.x, inst.y, inst.z = coords.x, coords.y, coords.z
        end
    end

    local candidates = {}
    local queries = nil
    local quiet = suppressed()
    for index = 1, #instances do
        local inst = instances[index]
        local dx, dy, dz = inst.x - px, inst.y - py, inst.z - pz
        local distance = dx * dx + dy * dy + dz * dz
        inst.distance = distance

        if distance > LOCK_RANGE_SQUARED then
            if inst.lockFresh then
                inst.lockFresh = false
                if inst.lockHolder == serverId() then inst.hidden = false end
                inst.lockHolder = 0
            end
        elseif not inst.lockFresh and inst.def.server then
            inst.lockFresh = true
            queries = queries or {}
            local batch = queries[inst.def]
            if not batch then
                batch = {}
                queries[inst.def] = batch
            end
            if #batch < MAX_KEYS_PER_QUERY then batch[#batch + 1] = inst else inst.lockFresh = false end
        end

        if not quiet and distance <= inst.def.markerRangeSquared then
            local slot = #candidates + 1
            while slot > 1 and candidates[slot - 1].distance > distance do
                candidates[slot] = candidates[slot - 1]
                slot = slot - 1
            end
            if slot <= MAX_NEAR then
                candidates[slot] = inst
                candidates[MAX_NEAR + 1] = nil
            end
        end
    end

    local kept = {}
    for index = 1, #candidates do
        local inst = candidates[index]
        if DoesEntityExist(inst.entity) and GetEntityModel(inst.entity) == inst.model then
            local coords = GetEntityCoords(inst.entity)
            inst.x, inst.y, inst.z = coords.x, coords.y, coords.z
            kept[#kept + 1] = inst
        else
            dropInstance(inst)
        end
    end

    local parts = {}
    for index = 1, #kept do parts[index] = kept[index].serial end
    local signature = table.concat(parts, ',')
    if signature ~= nearSignature then
        local owners = {}
        local inside = {}
        for index = 1, #kept do
            inside[kept[index]] = true
            owners[kept[index].def.owner] = true
        end
        for index = 1, #nearList do
            local inst = nearList[index]
            owners[inst.def.owner] = true
            if not inside[inst] then
                inst.near = false
                inst.report = nil
            end
        end
        for index = 1, #kept do kept[index].near = true end
        nearList = kept
        nearSignature = signature
        publishNear(owners)
        requestFeed()
    elseif quiet and next(shown) then
        requestFeed()
    end

    if queries then
        for def, batch in pairs(queries) do queryLocks(def, batch) end
    end

    updateLook(ped)

    local dx, dy, dz = px - lastX, py - lastY, pz - lastZ
    local moved = dx * dx + dy * dy + dz * dz > 1.0
    if moved then lastX, lastY, lastZ = px, py, pz end
    return (moved or #nearList > 0) and SCAN_MS or SCAN_STILL_MS
end

local function ensureScan()
    if scanning then return end
    scanning = true
    CreateThread(function()
        while #instances > 0 do
            Wait(scan())
        end
        if #nearList > 0 then
            local owners = {}
            for index = 1, #nearList do owners[nearList[index].def.owner] = true end
            nearList = {}
            nearSignature = ''
            publishNear(owners)
        end
        rebuildFeed()
        updateLook(PlayerPedId())
        scanning = false
    end)
end

local function reducedMotion()
    local atlas = rawget(_G, 'Atlas')
    return type(atlas) == 'table' and type(atlas.reducedMotion) == 'function' and atlas.reducedMotion() == true
end

local function stopUse(why, tellServer)
    local current = use
    if not current then return end
    use = nil
    local inst, verb = current.inst, current.verb
    local def = inst.def
    if current.walking then ClearPedTasks(PlayerPedId()) end
    if tellServer and verb.server then TriggerServerEvent(EVENT_CANCEL, def.owner, def.id, inst.key) end
    if current.accepted then
        TriggerEvent(EVENT_STOP, def.owner, current.token, def.id, inst.entity, verb.id, why)
    end
    requestFeed()
end

local function moving()
    return IsControlPressed(0, 32) or IsControlPressed(0, 33) or IsControlPressed(0, 34) or IsControlPressed(0, 35)
end

local function unfit(ped, inst)
    if inst.gone or not DoesEntityExist(inst.entity) then return 'gone' end
    if downed(ped) then return 'dead' end
    if IsPedRagdoll(ped) then return 'ragdoll' end
    if IsPedInAnyVehicle(ped, true) then return 'vehicle' end
    return nil
end

local function walk(current, stand)
    local inst = current.inst
    local ped = PlayerPedId()
    local entity = GetEntityCoords(inst.entity)
    local reach = inst.def.range + 1.0
    local dx, dy, dz = stand.x - entity.x, stand.y - entity.y, stand.z - entity.z
    if dx * dx + dy * dy + dz * dz > reach * reach then return true end

    current.walking = true
    local started = GetGameTimer()
    local deadline = started + WALK_DEADLINE_MS
    local underway = false
    TaskGoStraightToCoord(ped, stand.x, stand.y, stand.z, 1.0, WALK_DEADLINE_MS, stand.heading or GetEntityHeading(ped), 0.3)
    while GetGameTimer() < deadline do
        Wait(50)
        if use ~= current then return false end
        local why = unfit(ped, inst) or (moving() and 'moved')
        if why then return false, why end
        local status = GetScriptTaskStatus(ped, TASK_GO_STRAIGHT)
        if status == 0 or status == 1 then
            underway = true
        elseif underway or GetGameTimer() - started > WALK_START_MS then
            break
        end
    end
    if GetScriptTaskStatus(ped, TASK_GO_STRAIGHT) ~= 7 then ClearPedTasks(ped) end
    current.walking = false

    local at = GetEntityCoords(ped)
    entity = GetEntityCoords(inst.entity)
    dx, dy, dz = at.x - entity.x, at.y - entity.y, at.z - entity.z
    if dx * dx + dy * dy + dz * dz > inst.def.range * inst.def.range then return false, 'too_far' end
    return true
end

local function begin(inst, verb, rowId)
    token = token + 1
    local current = { token = token, inst = inst, verb = verb, rowId = rowId }
    use = current
    local def = inst.def
    local reply = nil

    if verb.server then
        local answer = nil
        lib.callback(ASK, false, function(ok, detail)
            if answer == false then
                if ok == true then TriggerServerEvent(EVENT_CANCEL, def.owner, def.id, inst.key) end
                return
            end
            answer = { ok == true, detail }
        end, def.owner, def.id, inst.key, verb.id)

        local deadline = GetGameTimer() + ASK_TIMEOUT_MS
        while not answer and GetGameTimer() < deadline do Wait(0) end
        if use ~= current then
            if answer and answer[1] then TriggerServerEvent(EVENT_CANCEL, def.owner, def.id, inst.key) end
            answer = answer or false
            return
        end
        if not answer then
            answer = false
            use = nil
            refuse(inst, 'No answer')
            return
        end
        if not answer[1] then
            use = nil
            refuse(inst, answer[2])
            return
        end
        reply = answer[2]
    end

    current.accepted = true
    requestFeed()
    local why = unfit(PlayerPedId(), inst)
    if why then return stopUse(why, true) end

    if verb.stand and not reducedMotion() then
        standReplies[current.token] = nil
        TriggerEvent(EVENT_STAND, def.owner, current.token, def.id, inst.entity, verb.id)
        local deadline = GetGameTimer() + STAND_REPLY_MS
        while standReplies[current.token] == nil and GetGameTimer() < deadline do Wait(0) end
        local stand = standReplies[current.token]
        standReplies[current.token] = nil
        if use ~= current then return end
        if stand then
            local ok, walkWhy = walk(current, stand)
            if use ~= current then return end
            if not ok then return stopUse(walkWhy or 'cancelled', true) end
        end
    end

    use = nil
    inst.hidden = true
    rebuildFeed()
    TriggerEvent(EVENT_GO, def.owner, current.token, def.id, inst.entity, verb.id, reply)
end

local function start(inst, verb, rowId)
    local ok, err = pcall(begin, inst, verb, rowId)
    if ok then return end
    print(('^1[%s] thing %s:%s use failed: %s^7'):format(HOST, inst.def.owner, inst.def.id, tostring(err)))
    if use and use.walking then ClearPedTasks(PlayerPedId()) end
    use = nil
    inst.hidden = false
    requestFeed()
end

local function activeRow(bindKey)
    for id, row in pairs(shown) do
        if not row.blocked and row.bindKey == bindKey and registry(lib.isInteractionVisible, id) then return id, row end
    end
    return nil
end

local function isPressed(bindKey)
    if not bindKey then return pressed end
    local entry = customKeys[bindKey]
    return entry ~= nil and entry.pressed == true
end

local function setHolding(bindKey, state)
    if not bindKey then
        holding = state
    else
        local entry = customKeys[bindKey]
        if entry then entry.holding = state end
    end
end

local function press(bindKey)
    if use or suppressed() then return end
    local id, row = activeRow(bindKey)
    if not row then return end
    local inst, verb = row.inst, row.verb
    if inst.gone then return end

    if not verb.hold then return start(inst, verb, id) end

    if not registry(lib.startInteractionHold, id) then return end
    setHolding(bindKey, true)
    local finish = GetGameTimer() + verb.hold
    while GetGameTimer() < finish do
        Wait(50)
        if not isPressed(bindKey) or inst.gone or use or suppressed() or not registry(lib.isInteractionVisible, id) then
            registry(lib.cancelInteractionHold, id)
            setHolding(bindKey, false)
            return
        end
    end
    registry(lib.cancelInteractionHold, id)
    setHolding(bindKey, false)
    start(inst, verb, id)
end

local function ensureCustomKey(key)
    if not key or customKeys[key] then return end
    local cmd = USE_COMMAND .. '_' .. key:lower()
    local entry = {
        cmd = cmd,
        hash = joaat('+' .. cmd) | 0x80000000,
        label = key,
        labelAt = -KEY_REFRESH_MS,
        pressed = false,
        holding = false,
    }
    customKeys[key] = entry
    RegisterCommand('+' .. cmd, function()
        entry.pressed = true
        if entry.holding then return end
        CreateThread(function() press(key) end)
    end, false)
    RegisterCommand('-' .. cmd, function()
        entry.pressed = false
    end, false)
    RegisterKeyMapping('+' .. cmd, ('Use (%s)'):format(key), 'keyboard', key)
end

RegisterCommand('+' .. USE_COMMAND, function()
    pressed = true
    if holding then return end
    CreateThread(function() press(nil) end)
end, false)

RegisterCommand('-' .. USE_COMMAND, function()
    pressed = false
end, false)

RegisterKeyMapping('+' .. USE_COMMAND, 'Use the thing in front of you', 'keyboard', DEFAULT_KEY)

RegisterNetEvent(EVENT_LOCK, function(owner, thingId, key, holder, counter)
    local def = type(owner) == 'string' and type(thingId) == 'string' and thingOf(owner, thingId) or nil
    local id = def and keyText(key)
    local inst = id and def.byKey[id]
    if not inst or type(holder) ~= 'number' or type(counter) ~= 'number' then return end
    if not inst.lockFresh then return end
    applyLock(inst, holder, counter)
end)

AddEventHandler('onClientResourceStop', function(resource)
    busy[resource] = nil
    busy[resource .. '|placement'] = nil
    local owned = things[resource]
    if owned then
        if use and use.inst.def.owner == resource then stopUse('stopped', true) end
        local list = {}
        for _, def in pairs(owned) do list[#list + 1] = def end
        for index = 1, #list do dropThing(list[index]) end
    end
    requestFeed()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= HOST then return end
    local ped = PlayerPedId()
    if lookEntity then TaskClearLookAt(ped) end
    if use and use.walking then ClearPedTasks(ped) end
end)

local function caller()
    return GetInvokingResource() or HOST
end

exports('thingDefine', function(thingId, spec)
    local resource = caller()
    if not validId(thingId) or type(spec) ~= 'table' or type(spec.verbs) ~= 'table' then
        return false, 'a thing needs an id and verbs'
    end
    if #spec.verbs == 0 or #spec.verbs > MAX_VERBS then return false, 'a thing takes 1 to 8 verbs' end

    local verbs = {}
    local server = false
    for index = 1, #spec.verbs do
        local verb = spec.verbs[index]
        if type(verb) ~= 'table' or not validId(verb.id) then return false, 'verb ids must be short strings' end
        local hold = tonumber(verb.hold)
        local bindKey = normalizeCustomKey(verb.key)
        if bindKey then ensureCustomKey(bindKey) end
        verbs[index] = {
            id = verb.id,
            label = text(verb.label, MAX_LABEL_BYTES) or verb.id:sub(1, MAX_LABEL_BYTES),
            key = bindKey,
            hold = hold and math.floor(math.max(100, math.min(600000, hold))) or nil,
            server = verb.server == true,
            stand = verb.stand == true,
        }
        server = server or verb.server == true
    end

    local existing = thingOf(resource, thingId)
    if existing then dropThing(existing) end

    local range = math.max(0.5, math.min(25.0, tonumber(spec.range) or 2.0))
    local markerRange = math.max(range, math.min(25.0, tonumber(spec.markerRange) or range + 4.0))
    things[resource] = things[resource] or {}
    things[resource][thingId] = {
        owner = resource, id = thingId, verbs = verbs, server = server,
        range = range, markerRange = markerRange, markerRangeSquared = markerRange * markerRange,
        byEntity = {}, byKey = {}, count = 0,
    }
    requestFeed()
    return true
end)

exports('thingAdd', function(thingId, entity, key, offset)
    local def = thingOf(caller(), thingId)
    if not def then return false, 'thing is not defined' end
    local id = keyText(key)
    if not id then return false, 'key must be an integer or a short string' end
    if math.type(entity) ~= 'integer' or not DoesEntityExist(entity) then return false, 'entity does not exist' end

    local existing = def.byEntity[entity]
    if existing then dropInstance(existing) end
    local duplicate = def.byKey[id]
    if duplicate then dropInstance(duplicate) end
    if def.count >= MAX_INSTANCES_PER_OWNER then return false, 'too many instances' end

    local coords = GetEntityCoords(entity)
    serial = serial + 1
    local inst = {
        def = def, entity = entity, model = GetEntityModel(entity), key = key, keyText = id, serial = serial,
        offset = {
            x = type(offset) == 'table' and tonumber(offset.x) or 0.0,
            y = type(offset) == 'table' and tonumber(offset.y) or 0.0,
            z = type(offset) == 'table' and tonumber(offset.z) or 0.0,
        },
        x = coords.x, y = coords.y, z = coords.z, distance = math.huge,
        near = false, hidden = false, report = nil,
        lockHolder = 0, lockCounter = 0, lockFresh = false,
        refusal = nil, refusalUntil = 0,
    }
    def.byEntity[entity] = inst
    def.byKey[id] = inst
    def.count = def.count + 1
    instances[#instances + 1] = inst
    ensureScan()
    return true
end)

exports('thingRemove', function(thingId, entity)
    local inst = instanceOf(caller(), thingId, entity)
    if not inst then return false end
    if use and use.inst == inst then stopUse('gone', true) end
    dropInstance(inst)
    requestFeed()
    return true
end)

exports('thingDestroy', function(thingId)
    local def = thingOf(caller(), thingId)
    if not def then return false end
    if use and use.inst.def == def then stopUse('gone', true) end
    dropThing(def)
    requestFeed()
    return true
end)

exports('thingReport', function(thingId, entity, status, verbs)
    local inst = instanceOf(caller(), thingId, entity)
    if not inst or not inst.near or type(verbs) ~= 'table' then return false end

    local states = {}
    for index = 1, #inst.def.verbs do
        local state = verbs[index]
        if type(state) == 'table' then
            states[index] = {
                usable = state.usable == true,
                label = text(state.label, MAX_LABEL_BYTES),
                reason = text(state.reason),
            }
        end
    end
    inst.report = { status = text(status), verbs = states }
    requestFeed()
    return true
end)

exports('thingStandAt', function(replyToken, x, y, z, heading)
    if not use or use.token ~= replyToken or use.inst.def.owner ~= caller() then return false end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    standReplies[replyToken] = x and y and z and x == x and y == y and z == z and { x = x, y = y, z = z, heading = tonumber(heading) } or false
    return true
end)

exports('thingDone', function(thingId, entity)
    local inst = instanceOf(caller(), thingId, entity)
    if not inst then return false end
    if inst.hidden then
        inst.hidden = false
        if inst.def.server then TriggerServerEvent(EVENT_CANCEL, inst.def.owner, inst.def.id, inst.key) end
        requestFeed()
    end
    return true
end)

exports('thingHold', function(thingId, entity)
    local inst = instanceOf(caller(), thingId, entity)
    if not inst then return false end
    if not inst.hidden then
        inst.hidden = true
        requestFeed()
    end
    return true
end)

exports('thingLocked', function(thingId, entity)
    local inst = instanceOf(caller(), thingId, entity)
    return inst ~= nil and inst.lockHolder ~= 0 and inst.lockHolder ~= serverId()
end)

exports('thingBusy', function(state, reason)
    local key = reason == 'placement' and (caller() .. '|placement') or caller()
    busy[key] = state == true or nil
    requestFeed()
    return true
end)

exports('thingState', function()
    local rows = {}
    for id, row in pairs(shown) do
        rows[#rows + 1] = {
            id = id, label = row.label, key = row.key, note = row.note, more = row.more,
            blocked = row.blocked == true, thing = row.inst.def.id, entityKey = row.inst.key,
            verb = row.verb and row.verb.id or nil, visible = row.visible == true,
        }
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return {
        instances = #instances, near = #nearList, rows = rows, using = use ~= nil,
        look = lookEntity ~= nil, key = keyLabel, rich = supportsRichRows(), suppressed = suppressed(),
    }
end)
