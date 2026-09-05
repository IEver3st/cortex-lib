local resourceName = GetCurrentResourceName()
local isCortexLib = resourceName == 'cortex-lib'

local pendingCallbacks = {}
local scheduledRequests = {}
local callbackId = 0
local registeredCallbacks = {}
local pendingCount = 0
local pendingOwnerCounts = {}
local scheduledCount = 0
local scheduledOwnerCounts = {}

local CALLBACK_TIMEOUT = 30000
local CALLBACK_SWEEP_INTERVAL = 5000
local MAX_CALLBACK_NAME_LENGTH = 96
local MAX_CALLBACK_ID_LENGTH = 128
local MAX_CALLBACK_TOKEN_LENGTH = 256
local MAX_CALLBACK_ARGS = 32
local MAX_CALLBACK_DELAY = 600000
local MAX_PENDING_CALLBACKS = 1024
local MAX_PENDING_CALLBACKS_PER_OWNER = 128
local MAX_SCHEDULED_REQUESTS = 256
local MAX_SCHEDULED_REQUESTS_PER_OWNER = 64
local MAX_PAYLOAD_DEPTH = 16
local MAX_PAYLOAD_NODES = 4096
local MAX_PAYLOAD_STRING_BYTES = 1024 * 1024
local requestEpoch = ('%s:%s:%s'):format(GetGameTimer(), math.random(0, 2147483647), tostring({}))

local function pack(...)
    return table.pack(...)
end

local function elapsedSince(now, startedAt)
    local elapsed = now - startedAt
    return elapsed < 0 and elapsed + 4294967296 or elapsed
end

local function isBoundedString(value, maxLength)
    return type(value) == 'string'
        and #value > 0
        and #value <= maxLength
        and not value:find('[%z\1-\31\127]')
end

local function getCallbackOwner()
    local owner = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil

    if type(owner) ~= 'string' or owner == '' then
        return resourceName
    end

    return owner
end

local function validatePayloadNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function validatePayloadValue(value, state, depth, activeTables)
    state.nodes = state.nodes + 1

    if state.nodes > MAX_PAYLOAD_NODES then
        return false
    end

    local valueType = type(value)

    if valueType == 'nil' or valueType == 'boolean' then
        return true
    end

    if valueType == 'number' then
        return validatePayloadNumber(value)
    end

    if valueType == 'string' then
        state.stringBytes = state.stringBytes + #value
        return state.stringBytes <= MAX_PAYLOAD_STRING_BYTES
    end

    if valueType == 'vector2' or valueType == 'vector3' or valueType == 'vector4' or valueType == 'quaternion' then
        local components = { value.x, value.y }
        local componentCount = 2

        if valueType ~= 'vector2' then
            components[3] = value.z
            componentCount = 3
        end

        if valueType == 'vector4' or valueType == 'quaternion' then
            components[4] = value.w
            componentCount = 4
        end

        for index = 1, componentCount do
            if not validatePayloadNumber(components[index]) then
                return false
            end
        end

        return true
    end

    if valueType ~= 'table' or depth > MAX_PAYLOAD_DEPTH or activeTables[value] then
        return false
    end

    activeTables[value] = true

    for key, item in next, value do
        local keyType = type(key)

        if keyType ~= 'string' and keyType ~= 'number' and keyType ~= 'boolean' then
            activeTables[value] = nil
            return false
        end

        if not validatePayloadValue(key, state, depth + 1, activeTables)
            or not validatePayloadValue(item, state, depth + 1, activeTables)
        then
            activeTables[value] = nil
            return false
        end
    end

    activeTables[value] = nil
    return true
end

local function validatePackedPayload(values)
    local state = {
        nodes = 0,
        stringBytes = 0,
    }
    local activeTables = {}

    for index = 1, values.n do
        if not validatePayloadValue(values[index], state, 0, activeTables) then
            return false
        end
    end

    return true
end

local function validateDelay(delay)
    if delay == nil or delay == false then
        return 0
    end

    if type(delay) ~= 'number' or delay ~= delay or delay == math.huge or delay == -math.huge then
        return nil
    end

    delay = math.floor(delay)

    if delay < 0 or delay > MAX_CALLBACK_DELAY then
        return nil
    end

    return delay
end

local function isResponder(value)
    return value == nil
        or type(value) == 'function'
        or (type(value) == 'table' and type(value.resolve) == 'function')
end

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    if not ok or type(text) ~= 'string' then return '<unprintable error>' end
    if #text > 512 then return text:sub(1, 512) .. '...' end
    return text
end

local function logError(message)
    pcall(print, message)
end

local function invokeProtected(handler, ...)
    local callResults = pack(pcall(handler, ...))

    if not callResults[1] then
        return false, safeErrorText(callResults[2])
    end

    local results = { n = callResults.n - 1 }

    for index = 2, callResults.n do
        results[index - 1] = callResults[index]
    end

    return true, results
end

local function settleResponder(responder, results)
    if type(responder) == 'function' then
        local ok, err = pcall(responder, table.unpack(results, 1, results.n))

        if not ok then
            logError(('^1[cortex-lib] callback responder failed: %s^0'):format(safeErrorText(err)))
        end

        return
    end

    if type(responder) == 'table' and type(responder.resolve) == 'function' then
        local ok, err = pcall(responder.resolve, responder, results)

        if not ok then
            logError(('^1[cortex-lib] callback promise resolver failed: %s^0'):format(safeErrorText(err)))
        end
    end
end

local function addPendingCallback(id, entry)
    local ownerCount = pendingOwnerCounts[entry.owner] or 0

    if pendingCount >= MAX_PENDING_CALLBACKS or ownerCount >= MAX_PENDING_CALLBACKS_PER_OWNER then
        return false
    end

    pendingCallbacks[id] = entry
    pendingCount = pendingCount + 1
    pendingOwnerCounts[entry.owner] = ownerCount + 1
    return true
end

local function takePendingCallback(id)
    local entry = pendingCallbacks[id]
    if not entry then return nil end

    pendingCallbacks[id] = nil
    pendingCount = pendingCount - 1

    local ownerCount = (pendingOwnerCounts[entry.owner] or 1) - 1
    pendingOwnerCounts[entry.owner] = ownerCount > 0 and ownerCount or nil
    return entry
end

local function addScheduledRequest(id, owner)
    local ownerCount = scheduledOwnerCounts[owner] or 0

    if scheduledCount >= MAX_SCHEDULED_REQUESTS or ownerCount >= MAX_SCHEDULED_REQUESTS_PER_OWNER then
        return false
    end

    scheduledRequests[id] = { owner = owner }
    scheduledCount = scheduledCount + 1
    scheduledOwnerCounts[owner] = ownerCount + 1
    return true
end

local function removeScheduledRequest(id)
    local entry = scheduledRequests[id]
    if not entry then return false end

    scheduledRequests[id] = nil
    scheduledCount = scheduledCount - 1

    local ownerCount = (scheduledOwnerCounts[entry.owner] or 1) - 1
    scheduledOwnerCounts[entry.owner] = ownerCount > 0 and ownerCount or nil
    return true
end

local function resolvePendingCallback(id, ...)
    local entry = takePendingCallback(id)

    if not entry then
        return false
    end

    settleResponder(entry.responder, pack(...))
    return true
end

local function rejectResponder(responder, reason)
    if responder ~= nil then
        settleResponder(responder, pack(nil, reason))
    end
end

local function validateRequest(name, delay, responder, args)
    if not isBoundedString(name, MAX_CALLBACK_NAME_LENGTH) then
        return nil, 'invalid_callback_name'
    end

    local normalizedDelay = validateDelay(delay)

    if normalizedDelay == nil then
        return nil, 'invalid_callback_delay'
    end

    if not isResponder(responder) then
        return nil, 'invalid_callback_responder'
    end

    if args.n > MAX_CALLBACK_ARGS then
        return nil, 'too_many_callback_arguments'
    end

    if not validatePackedPayload(args) then
        return nil, 'invalid_callback_payload'
    end

    return normalizedDelay
end

local function nextCallbackId()
    callbackId = callbackId + 1
    return ('%s:%s'):format(resourceName, callbackId)
end

local function createRequestToken()
    return ('%s:%s'):format(requestEpoch, callbackId)
end

local function transmitRequest(name, id, token, args, expectsResponse)
    if expectsResponse then
        local entry = pendingCallbacks[id]

        if not entry then
            return
        end

        -- Start the timeout when the delayed request is actually transmitted.
        entry.sentAt = GetGameTimer()
    end

    local sent, sendError = pcall(
        TriggerServerEvent,
        'cortex-lib:callback',
        name,
        id,
        token,
        table.unpack(args, 1, args.n)
    )

    if not sent then
        logError(('^1[cortex-lib] failed to transmit server callback "%s": %s^0'):format(name, safeErrorText(sendError)))

        if expectsResponse then
            resolvePendingCallback(id, nil, 'callback_transmit_error')
        end

        return false, 'callback_transmit_error'
    end
end

local function triggerCallback(name, delay, cb, ...)
    local args = pack(...)
    local normalizedDelay, validationError = validateRequest(name, delay, cb, args)

    if normalizedDelay == nil then
        rejectResponder(cb, validationError)
        return false, validationError
    end

    local id = nextCallbackId()
    local token = createRequestToken()
    local expectsResponse = cb ~= nil
    local owner = getCallbackOwner()

    if expectsResponse then
        local added = addPendingCallback(id, {
            responder = cb,
            sentAt = nil,
            owner = owner,
            token = token,
        })

        if not added then
            rejectResponder(cb, 'callback_capacity_exceeded')
            return false, 'callback_capacity_exceeded'
        end
    end

    local transmit = function()
        return transmitRequest(name, id, token, args, expectsResponse)
    end

    if normalizedDelay > 0 then
        if not addScheduledRequest(id, owner) then
            if expectsResponse then
                resolvePendingCallback(id, nil, 'callback_capacity_exceeded')
            end
            return false, 'callback_capacity_exceeded'
        end

        local scheduled, scheduleError = pcall(SetTimeout, normalizedDelay, function()
            if not removeScheduledRequest(id) then
                return
            end

            return transmit()
        end)

        if not scheduled then
            removeScheduledRequest(id)
            logError(('^1[cortex-lib] failed to schedule server callback "%s": %s^0'):format(name, safeErrorText(scheduleError)))

            if expectsResponse then
                resolvePendingCallback(id, nil, 'callback_transmit_error')
            end

            return false, 'callback_transmit_error'
        end
    else
        return transmit()
    end
end

local function awaitCallback(name, delay, ...)
    local args = pack(...)
    local normalizedDelay, validationError = validateRequest(name, delay, nil, args)

    if normalizedDelay == nil then
        return nil, validationError
    end

    local id = nextCallbackId()
    local token = createRequestToken()
    local callbackPromise = promise.new()
    local owner = getCallbackOwner()

    local added = addPendingCallback(id, {
        responder = callbackPromise,
        sentAt = nil,
        owner = owner,
        token = token,
    })

    if not added then
        return nil, 'callback_capacity_exceeded'
    end

    local transmit = function()
        return transmitRequest(name, id, token, args, true)
    end

    if normalizedDelay > 0 then
        if not addScheduledRequest(id, owner) then
            resolvePendingCallback(id, nil, 'callback_capacity_exceeded')
        else
            local scheduled, scheduleError = pcall(SetTimeout, normalizedDelay, function()
                if not removeScheduledRequest(id) then
                    return
                end

                return transmit()
            end)

            if not scheduled then
                removeScheduledRequest(id)
                logError(('^1[cortex-lib] failed to schedule server callback "%s": %s^0'):format(name, safeErrorText(scheduleError)))
                resolvePendingCallback(id, nil, 'callback_transmit_error')
            end
        end
    else
        transmit()
    end

    local results = Citizen.Await(callbackPromise)

    if type(results) ~= 'table' then
        return results
    end

    return table.unpack(results, 1, results.n or #results)
end

local function sendClientCallbackResponse(id, token, results)
    local sent, sendError = pcall(
        TriggerServerEvent,
        'cortex-lib:clientCallbackResponse',
        id,
        token,
        table.unpack(results, 1, results.n)
    )

    if not sent then
        logError(('^1[cortex-lib] failed to send client callback response: %s^0'):format(safeErrorText(sendError)))
    end

    return sent
end

local function registerCallback(name, cb)
    if not isCortexLib then
        return exports['cortex-lib']:registerCallback(name, cb)
    end

    if not isBoundedString(name, MAX_CALLBACK_NAME_LENGTH) then
        return false, 'invalid_callback_name'
    end

    if type(cb) ~= 'function' then
        return false, 'invalid_callback_handler'
    end

    local owner = getCallbackOwner()
    local existing = registeredCallbacks[name]

    if existing and existing.owner ~= owner then
        return false, ('callback_name_in_use:%s'):format(existing.owner)
    end

    registeredCallbacks[name] = {
        owner = owner,
        handler = cb,
    }
end

local callback = setmetatable({
    await = awaitCallback,
    register = registerCallback,
}, {
    __call = function(_, name, delay, cb, ...)
        return triggerCallback(name, delay, cb, ...)
    end,
})

RegisterNetEvent('cortex-lib:callbackResponse', function(id, token, ...)
    if not isBoundedString(id, MAX_CALLBACK_ID_LENGTH)
        or not isBoundedString(token, MAX_CALLBACK_TOKEN_LENGTH)
    then
        return
    end

    local entry = pendingCallbacks[id]
    if not entry or entry.token ~= token then return end

    local results = pack(...)

    if results.n > MAX_CALLBACK_ARGS or not validatePackedPayload(results) then
        resolvePendingCallback(id, nil, 'invalid_callback_response')
        return
    end

    resolvePendingCallback(id, table.unpack(results, 1, results.n))
end)

if isCortexLib then
    RegisterNetEvent('cortex-lib:clientCallback', function(name, id, token, ...)
        local validId = isBoundedString(id, MAX_CALLBACK_ID_LENGTH)
        local validToken = isBoundedString(token, MAX_CALLBACK_TOKEN_LENGTH)

        if not validId or not validToken then
            return
        end

        local args = pack(...)

        if not isBoundedString(name, MAX_CALLBACK_NAME_LENGTH)
            or args.n > MAX_CALLBACK_ARGS
            or not validatePackedPayload(args)
        then
            sendClientCallbackResponse(id, token, pack(nil, 'invalid_callback_request'))
            return
        end

        local entry = registeredCallbacks[name]

        if not entry then
            sendClientCallbackResponse(id, token, pack(nil, 'callback_not_found'))
            return
        end

        local ok, resultsOrError = invokeProtected(entry.handler, table.unpack(args, 1, args.n))

        if not ok then
            logError(('^1[cortex-lib] client callback "%s" failed: %s^0'):format(name, resultsOrError))
            sendClientCallbackResponse(id, token, pack(nil, 'callback_handler_error'))
            return
        end

        if resultsOrError.n > MAX_CALLBACK_ARGS then
            sendClientCallbackResponse(id, token, pack(nil, 'too_many_callback_results'))
            return
        end

        if not validatePackedPayload(resultsOrError) then
            sendClientCallbackResponse(id, token, pack(nil, 'invalid_callback_result'))
            return
        end

        sendClientCallbackResponse(id, token, resultsOrError)
    end)

    exports('callback', function(name, delay, cb, ...)
        return triggerCallback(name, delay, cb, ...)
    end)

    exports('callbackAwait', function(name, delay, ...)
        return awaitCallback(name, delay, ...)
    end)

    exports('registerCallback', function(name, cb)
        return registerCallback(name, cb)
    end)
end

AddEventHandler('onClientResourceStop', function(stoppedResource)
    if isCortexLib then
        for name, entry in pairs(registeredCallbacks) do
            if entry.owner == stoppedResource then
                registeredCallbacks[name] = nil
            end
        end
    end

    local scheduledIds = {}

    for id, scheduled in pairs(scheduledRequests) do
        if stoppedResource == resourceName or scheduled.owner == stoppedResource then
            scheduledIds[#scheduledIds + 1] = id
        end
    end

    for index = 1, #scheduledIds do
        removeScheduledRequest(scheduledIds[index])
    end

    local pendingIds = {}

    for id, entry in pairs(pendingCallbacks) do
        if stoppedResource == resourceName or entry.owner == stoppedResource then
            pendingIds[#pendingIds + 1] = id
        end
    end

    for index = 1, #pendingIds do
        resolvePendingCallback(pendingIds[index], nil, 'resource_stopped')
    end
end)

CreateThread(function()
    while true do
        Wait(CALLBACK_SWEEP_INTERVAL)
        local now = GetGameTimer()
        local expired = {}

        for id, entry in pairs(pendingCallbacks) do
            if entry.sentAt and elapsedSince(now, entry.sentAt) > CALLBACK_TIMEOUT then
                expired[#expired + 1] = id
            end
        end

        for index = 1, #expired do
            resolvePendingCallback(expired[index], nil, 'timeout')
        end
    end
end)

lib.callback = callback

return callback
