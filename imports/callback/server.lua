local resourceName = GetCurrentResourceName()
local isCortexLib = resourceName == 'cortex-lib'

local pendingCallbacks = {}
local callbackId = 0
local registeredCallbacks = {}
local rateBuckets = {}
local pendingCount = 0
local pendingOwnerCounts = {}

local CALLBACK_TIMEOUT = 30000
local CALLBACK_SWEEP_INTERVAL = 5000
local MAX_CALLBACK_NAME_LENGTH = 96
local MAX_CALLBACK_ID_LENGTH = 128
local MAX_CALLBACK_TOKEN_LENGTH = 256
local MAX_CALLBACK_ARGS = 32
local MAX_PENDING_CALLBACKS = 1024
local MAX_PENDING_CALLBACKS_PER_OWNER = 128
local MAX_PAYLOAD_DEPTH = 16
local MAX_PAYLOAD_NODES = 4096
local MAX_PAYLOAD_STRING_BYTES = 1024 * 1024

-- This limit absorbs normal UI/data bursts while bounding a malicious client
-- independently for each callback name. Server handlers still own permission,
-- state, target and payload validation.
local RATE_CAPACITY = 24
local RATE_REFILL_PER_SECOND = 12
local RATE_BUCKET_TTL = 120000
local MAX_RATE_NAMES_PER_SOURCE = 128
local GLOBAL_RATE_CAPACITY = 120
local GLOBAL_RATE_REFILL_PER_SECOND = 60

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

local function isPlayerSource(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
        and value > 0
        and value == math.floor(value)
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

local function getCallbackOwner()
    local owner = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil

    if type(owner) ~= 'string' or owner == '' then
        return resourceName
    end

    return owner
end

local function createCallbackToken(id, target)
    return ('%s:%s:%s:%s'):format(id, target, GetGameTimer(), callbackId)
end

local function validateOutboundRequest(name, target, responder, args)
    if not isBoundedString(name, MAX_CALLBACK_NAME_LENGTH) then
        return false, 'invalid_callback_name'
    end

    if not isPlayerSource(target) then
        return false, 'invalid_callback_source'
    end

    if not isResponder(responder) then
        return false, 'invalid_callback_responder'
    end

    if args.n > MAX_CALLBACK_ARGS then
        return false, 'too_many_callback_arguments'
    end

    if not validatePackedPayload(args) then
        return false, 'invalid_callback_payload'
    end

    return true
end

local function triggerCallback(name, target, cb, ...)
    if not isCortexLib then
        return exports['cortex-lib']:callback(name, target, cb, ...)
    end

    local args = pack(...)
    local valid, validationError = validateOutboundRequest(name, target, cb, args)

    if not valid then
        rejectResponder(cb, validationError)
        return false, validationError
    end

    callbackId = callbackId + 1
    local id = ('%s:%s'):format(resourceName, callbackId)
    local token = createCallbackToken(id, target)

    if cb ~= nil then
        local added = addPendingCallback(id, {
            responder = cb,
            target = target,
            token = token,
            owner = getCallbackOwner(),
            sentAt = GetGameTimer(),
        })

        if not added then
            rejectResponder(cb, 'callback_capacity_exceeded')
            return false, 'callback_capacity_exceeded'
        end
    end

    local sent, sendError = pcall(
        TriggerClientEvent,
        'cortex-lib:clientCallback',
        target,
        name,
        id,
        token,
        table.unpack(args, 1, args.n)
    )

    if not sent then
        logError(('^1[cortex-lib] failed to transmit client callback "%s": %s^0'):format(name, safeErrorText(sendError)))

        if cb ~= nil then
            resolvePendingCallback(id, nil, 'callback_transmit_error')
        end

        return false, 'callback_transmit_error'
    end
end

local function awaitCallback(name, target, ...)
    if not isCortexLib then
        return exports['cortex-lib']:callbackAwait(name, target, ...)
    end

    local args = pack(...)
    local valid, validationError = validateOutboundRequest(name, target, nil, args)

    if not valid then
        return nil, validationError
    end

    callbackId = callbackId + 1
    local id = ('%s:%s'):format(resourceName, callbackId)
    local token = createCallbackToken(id, target)
    local callbackPromise = promise.new()
    local owner = getCallbackOwner()

    local added = addPendingCallback(id, {
        responder = callbackPromise,
        target = target,
        token = token,
        owner = owner,
        sentAt = GetGameTimer(),
    })

    if not added then
        return nil, 'callback_capacity_exceeded'
    end

    local sent, sendError = pcall(
        TriggerClientEvent,
        'cortex-lib:clientCallback',
        target,
        name,
        id,
        token,
        table.unpack(args, 1, args.n)
    )

    if not sent then
        logError(('^1[cortex-lib] failed to transmit client callback "%s": %s^0'):format(name, safeErrorText(sendError)))
        resolvePendingCallback(id, nil, 'callback_transmit_error')
    end

    local results = Citizen.Await(callbackPromise)

    if type(results) ~= 'table' then
        return results
    end

    return table.unpack(results, 1, results.n or #results)
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

local function consumeBucket(bucket, now, capacity, refillPerSecond)
    local elapsed = elapsedSince(now, bucket.updatedAt)

    bucket.tokens = math.min(capacity, bucket.tokens + elapsed * refillPerSecond / 1000)
    bucket.updatedAt = now
    bucket.lastSeen = now

    if bucket.tokens < 1 then return false end

    bucket.tokens = bucket.tokens - 1
    return true
end

local function consumeRateLimit(playerSource, name)
    local now = GetGameTimer()
    local sourceBuckets = rateBuckets[playerSource]

    if not sourceBuckets then
        sourceBuckets = {
            count = 0,
            entries = {},
            global = {
                tokens = GLOBAL_RATE_CAPACITY,
                updatedAt = now,
                lastSeen = now,
            },
        }
        rateBuckets[playerSource] = sourceBuckets
    end

    if not consumeBucket(
        sourceBuckets.global,
        now,
        GLOBAL_RATE_CAPACITY,
        GLOBAL_RATE_REFILL_PER_SECOND
    ) then
        return false
    end

    local bucket = sourceBuckets.entries[name]

    if not bucket then
        if sourceBuckets.count >= MAX_RATE_NAMES_PER_SOURCE then
            return false
        end

        bucket = {
            tokens = RATE_CAPACITY,
            updatedAt = now,
            lastSeen = now,
        }
        sourceBuckets.entries[name] = bucket
        sourceBuckets.count = sourceBuckets.count + 1
    end

    return consumeBucket(bucket, now, RATE_CAPACITY, RATE_REFILL_PER_SECOND)
end

local function sendCallbackResponse(playerSource, id, token, results)
    local sent, sendError = pcall(
        TriggerClientEvent,
        'cortex-lib:callbackResponse',
        playerSource,
        id,
        token,
        table.unpack(results, 1, results.n)
    )

    if not sent then
        logError(('^1[cortex-lib] failed to send callback response: %s^0'):format(safeErrorText(sendError)))
    end

    return sent
end

local callback = setmetatable({
    await = awaitCallback,
    register = registerCallback,
}, {
    __call = function(_, name, target, cb, ...)
        return triggerCallback(name, target, cb, ...)
    end,
})

if isCortexLib then
    RegisterNetEvent('cortex-lib:callback', function(name, id, token, ...)
        local playerSource = tonumber(source)
        local validId = isBoundedString(id, MAX_CALLBACK_ID_LENGTH)
        local validToken = isBoundedString(token, MAX_CALLBACK_TOKEN_LENGTH)

        if not isPlayerSource(playerSource) or not validId or not validToken then
            return
        end

        local args = pack(...)

        if not isBoundedString(name, MAX_CALLBACK_NAME_LENGTH) or args.n > MAX_CALLBACK_ARGS then
            sendCallbackResponse(playerSource, id, token, pack(nil, 'invalid_callback_request'))
            return
        end

        if not consumeRateLimit(playerSource, name) then
            sendCallbackResponse(playerSource, id, token, pack(nil, 'callback_rate_limited'))
            return
        end

        if not validatePackedPayload(args) then
            sendCallbackResponse(playerSource, id, token, pack(nil, 'invalid_callback_request'))
            return
        end

        local entry = registeredCallbacks[name]

        if not entry then
            sendCallbackResponse(playerSource, id, token, pack(nil, 'callback_not_found'))
            return
        end

        local ok, resultsOrError = invokeProtected(entry.handler, playerSource, table.unpack(args, 1, args.n))

        if not ok then
            logError(('^1[cortex-lib] server callback "%s" failed: %s^0'):format(name, resultsOrError))
            sendCallbackResponse(playerSource, id, token, pack(nil, 'callback_handler_error'))
            return
        end

        if resultsOrError.n > MAX_CALLBACK_ARGS then
            sendCallbackResponse(playerSource, id, token, pack(nil, 'too_many_callback_results'))
            return
        end

        if not validatePackedPayload(resultsOrError) then
            sendCallbackResponse(playerSource, id, token, pack(nil, 'invalid_callback_result'))
            return
        end

        sendCallbackResponse(playerSource, id, token, resultsOrError)
    end)

    RegisterNetEvent('cortex-lib:clientCallbackResponse', function(id, token, ...)
        local playerSource = tonumber(source)

        if not isPlayerSource(playerSource)
            or not isBoundedString(id, MAX_CALLBACK_ID_LENGTH)
            or not isBoundedString(token, MAX_CALLBACK_TOKEN_LENGTH)
        then
            return
        end

        local entry = pendingCallbacks[id]

        if not entry or entry.target ~= playerSource or entry.token ~= token then
            return
        end

        local results = pack(...)

        if results.n > MAX_CALLBACK_ARGS or not validatePackedPayload(results) then
            resolvePendingCallback(id, nil, 'invalid_callback_response')
            return
        end

        resolvePendingCallback(id, table.unpack(results, 1, results.n))
    end)

    exports('callback', function(name, target, cb, ...)
        return triggerCallback(name, target, cb, ...)
    end)

    exports('callbackAwait', function(name, target, ...)
        return awaitCallback(name, target, ...)
    end)

    exports('registerCallback', function(name, cb)
        return registerCallback(name, cb)
    end)
end

if isCortexLib then
    AddEventHandler('playerDropped', function()
        local playerSource = tonumber(source)

        if not isPlayerSource(playerSource) then
            return
        end

        rateBuckets[playerSource] = nil
        local pendingIds = {}

        for id, entry in pairs(pendingCallbacks) do
            if entry.target == playerSource then
                pendingIds[#pendingIds + 1] = id
            end
        end

        for index = 1, #pendingIds do
            resolvePendingCallback(pendingIds[index], nil, 'player_dropped')
        end
    end)

    AddEventHandler('onResourceStop', function(stoppedResource)
        for name, entry in pairs(registeredCallbacks) do
            if stoppedResource == resourceName or entry.owner == stoppedResource then
                registeredCallbacks[name] = nil
            end
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
                if elapsedSince(now, entry.sentAt) > CALLBACK_TIMEOUT then
                    expired[#expired + 1] = id
                end
            end

            for index = 1, #expired do
                resolvePendingCallback(expired[index], nil, 'timeout')
            end

            for playerSource, sourceBuckets in pairs(rateBuckets) do
                for name, bucket in pairs(sourceBuckets.entries) do
                    if elapsedSince(now, bucket.lastSeen) > RATE_BUCKET_TTL then
                        sourceBuckets.entries[name] = nil
                        sourceBuckets.count = sourceBuckets.count - 1
                    end
                end

                if sourceBuckets.count == 0
                    and elapsedSince(now, sourceBuckets.global.lastSeen) > RATE_BUCKET_TTL
                then
                    rateBuckets[playerSource] = nil
                end
            end
        end
    end)
end

lib.callback = callback

return callback
