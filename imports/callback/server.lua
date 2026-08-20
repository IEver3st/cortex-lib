local resourceName = GetCurrentResourceName()
local isCortexLib = resourceName == 'cortex-lib'

local pendingCallbacks = {}
local callbackTimestamps = {}
local callbackId = 0
local registeredCallbacks = {}
local CALLBACK_TIMEOUT = 30000

local function createCallbackToken(id, source)
    return ('%s:%s:%s'):format(id, source or 0, GetGameTimer())
end

local function resolvePendingCallback(id, ...)
    local entry = pendingCallbacks[id]
    if not entry then
        return false
    end

    pendingCallbacks[id] = nil
    callbackTimestamps[id] = nil

    local cb = entry.cb

    if type(cb) == 'function' then
        cb(...)
    elseif type(cb) == 'table' and cb.resolve then
        cb:resolve({ ... })
    end

    return true
end

local function triggerCallback(name, source, cb, ...)
    if not isCortexLib then
        return exports['cortex-lib']:callback(name, source, cb, ...)
    end

    callbackId = callbackId + 1
    local id = ('%s:%s'):format(resourceName, callbackId)
    local token = createCallbackToken(id, source)

    if cb ~= nil then
        pendingCallbacks[id] = {
            cb = cb,
            source = source,
            token = token,
        }
        callbackTimestamps[id] = GetGameTimer()
    end

    TriggerClientEvent('cortex-lib:clientCallback', source, name, id, token, ...)
end

local function awaitCallback(name, source, ...)
    if not isCortexLib then
        return exports['cortex-lib']:callbackAwait(name, source, ...)
    end

    callbackId = callbackId + 1
    local id = ('%s:%s'):format(resourceName, callbackId)
    local token = createCallbackToken(id, source)
    local p = promise.new()
    pendingCallbacks[id] = {
        cb = p,
        source = source,
        token = token,
    }
    callbackTimestamps[id] = GetGameTimer()

    TriggerClientEvent('cortex-lib:clientCallback', source, name, id, token, ...)

    return table.unpack(Citizen.Await(p))
end

local function registerCallback(name, cb)
    if not isCortexLib then
        return exports['cortex-lib']:registerCallback(name, cb)
    end

    registeredCallbacks[name] = cb
end

local callback = setmetatable({
    await = awaitCallback,
    register = registerCallback
}, {
    __call = function(_, name, source, cb, ...)
        return triggerCallback(name, source, cb, ...)
    end
})

if isCortexLib then
    RegisterNetEvent('cortex-lib:callback', function(name, id, ...)
        local src = source
        local cb = registeredCallbacks[name]

        if cb then
            local results = { cb(src, ...) }
            TriggerClientEvent('cortex-lib:callbackResponse', src, id, table.unpack(results))
        else
            TriggerClientEvent('cortex-lib:callbackResponse', src, id, nil)
        end
    end)

    RegisterNetEvent('cortex-lib:clientCallbackResponse', function(id, token, ...)
        local src = source
        local entry = pendingCallbacks[id]

        if entry and entry.source == src and entry.token == token then
            resolvePendingCallback(id, ...)
        end
    end)

    exports('callback', function(name, source, cb, ...)
        return triggerCallback(name, source, cb, ...)
    end)

    exports('callbackAwait', function(name, source, ...)
        return awaitCallback(name, source, ...)
    end)

    exports('registerCallback', function(name, cb)
        return registerCallback(name, cb)
    end)
end

CreateThread(function()
    while true do
        Wait(10000)
        local now = GetGameTimer()
        for id, ts in pairs(callbackTimestamps) do
            if now - ts > CALLBACK_TIMEOUT then
                resolvePendingCallback(id, nil, 'timeout')
            end
        end
    end
end)

lib.callback = callback

return callback
