--[[
    Everest Lib - Server Callback Module
    ox_lib compatible callback system for server-client communication

    Usage:
    - lib.callback(name, source, cb, ...) - Async callback to client with function
    - lib.callback.await(name, source, ...) - Synchronous callback to client
    - lib.callback.register(name, cb) - Register a server callback for client to call

    IMPORTANT:
    Net handlers for `es_lib:callback` must live ONLY in the es_lib resource.
    External resources that lazy-load this module must NOT register a second
    handler (that race answers first with nil and breaks client awaits).
    See Dynamic_weather hud_callback.lua for the historical failure mode.
]]

local resourceName = GetCurrentResourceName()
local isEsLib = resourceName == 'es_lib'

-- ============================================================================
-- CALLBACK STORAGE (es_lib resource only)
-- ============================================================================

local pendingCallbacks = {}
local callbackId = 0
local registeredCallbacks = {}

-- ============================================================================
-- TRIGGER CLIENT CALLBACK (Async)
-- ============================================================================

---Trigger a client callback asynchronously
---@param name string The callback name registered on the client
---@param source number The player server id
---@param cb function The function to call with the result
---@vararg any Arguments to pass to the client
local function triggerCallback(name, source, cb, ...)
    if not isEsLib then
        return exports.es_lib:callback(name, source, cb, ...)
    end

    callbackId = callbackId + 1
    local id = ('%s:%s'):format(resourceName, callbackId)

    pendingCallbacks[id] = cb

    TriggerClientEvent('es_lib:clientCallback', source, name, id, ...)
end

-- ============================================================================
-- TRIGGER CLIENT CALLBACK (Sync/Await)
-- ============================================================================

---Trigger a client callback and wait for the result
---@param name string The callback name registered on the client
---@param source number The player server id
---@vararg any Arguments to pass to the client
---@return any ... The values returned by the client callback
local function awaitCallback(name, source, ...)
    if not isEsLib then
        return exports.es_lib:callbackAwait(name, source, ...)
    end

    callbackId = callbackId + 1
    local id = ('%s:%s'):format(resourceName, callbackId)

    local p = promise.new()
    pendingCallbacks[id] = p

    TriggerClientEvent('es_lib:clientCallback', source, name, id, ...)

    return table.unpack(Citizen.Await(p))
end

-- ============================================================================
-- REGISTER SERVER CALLBACK (For client to call)
-- ============================================================================

---Register a callback on the server that can be triggered by the client
---@param name string The callback name
---@param cb function The callback function (receives source as first arg)
local function registerCallback(name, cb)
    if not isEsLib then
        -- Proxy into the single es_lib registry so only one net handler responds.
        return exports.es_lib:registerCallback(name, cb)
    end

    registeredCallbacks[name] = cb
end

-- ============================================================================
-- CREATE CALLABLE TABLE
-- ============================================================================

local callback = setmetatable({
    await = awaitCallback,
    register = registerCallback
}, {
    __call = function(_, name, source, cb, ...)
        return triggerCallback(name, source, cb, ...)
    end
})

-- ============================================================================
-- EVENT HANDLERS (es_lib resource only)
-- ============================================================================

if isEsLib then
    -- Handle client calling a server callback
    RegisterNetEvent('es_lib:callback', function(name, id, ...)
        local src = source
        local cb = registeredCallbacks[name]

        if cb then
            local results = { cb(src, ...) }
            TriggerClientEvent('es_lib:callbackResponse', src, id, table.unpack(results))
        else
            TriggerClientEvent('es_lib:callbackResponse', src, id, nil)
        end
    end)

    -- Handle response from client callback
    RegisterNetEvent('es_lib:clientCallbackResponse', function(id, ...)
        local cb = pendingCallbacks[id]

        if cb then
            pendingCallbacks[id] = nil

            if type(cb) == 'function' then
                cb(...)
            elseif type(cb) == 'table' and cb.resolve then
                cb:resolve({ ... })
            end
        end
    end)

    -- ============================================================================
    -- EXPORTS (used by external resources + Dynamic_weather-style direct calls)
    -- ============================================================================

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

-- ============================================================================
-- ATTACH TO LIB
-- ============================================================================

lib.callback = callback

return callback
