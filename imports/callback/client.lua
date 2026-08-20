local resourceName = GetCurrentResourceName()
local isCortexLib = resourceName == 'cortex-lib'

local pendingCallbacks = {}
local callbackTimestamps = {}
local callbackId = 0
local registeredCallbacks = {}
local CALLBACK_TIMEOUT = 30000

local function resolvePendingCallback(id, ...)
    local cb = pendingCallbacks[id]
    if not cb then
        return false
    end

    pendingCallbacks[id] = nil
    callbackTimestamps[id] = nil

    if type(cb) == 'function' then
        cb(...)
    elseif type(cb) == 'table' and cb.resolve then
        cb:resolve({ ... })
    end

    return true
end

local function triggerCallback(name, delay, cb, ...)
    callbackId = callbackId + 1
    local id = ('%s:%s'):format(resourceName, callbackId)
    local args = { ... }

    if cb ~= nil then
        pendingCallbacks[id] = cb
        callbackTimestamps[id] = GetGameTimer()
    end

    if delay and delay > 0 then
        SetTimeout(delay, function()
            TriggerServerEvent('cortex-lib:callback', name, id, table.unpack(args))
        end)
    else
        TriggerServerEvent('cortex-lib:callback', name, id, table.unpack(args))
    end
end

local function awaitCallback(name, delay, ...)
    callbackId = callbackId + 1
    local id = ('%s:%s'):format(resourceName, callbackId)
    local args = { ... }
    
    local p = promise.new()
    pendingCallbacks[id] = p
    callbackTimestamps[id] = GetGameTimer()
    
    if delay and delay > 0 then
        SetTimeout(delay, function()
            TriggerServerEvent('cortex-lib:callback', name, id, table.unpack(args))
        end)
    else
        TriggerServerEvent('cortex-lib:callback', name, id, table.unpack(args))
    end
    
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
    __call = function(_, name, delay, cb, ...)
        return triggerCallback(name, delay, cb, ...)
    end
})

RegisterNetEvent('cortex-lib:callbackResponse', function(id, ...)
    resolvePendingCallback(id, ...)
end)

if isCortexLib then
    RegisterNetEvent('cortex-lib:clientCallback', function(name, id, token, ...)
        local cb = registeredCallbacks[name]

        if cb then
            local results = { cb(...) }
            TriggerServerEvent('cortex-lib:clientCallbackResponse', id, token, table.unpack(results))
        else
            TriggerServerEvent('cortex-lib:clientCallbackResponse', id, token, nil)
        end
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
