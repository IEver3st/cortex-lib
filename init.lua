if not _VERSION:find('5.4') then
    error('^1[cortex-lib] Lua 5.4 is required. Add `lua54 \'yes\'` to your fxmanifest.lua^0')
end

local libResourceName = 'cortex-lib'

if GetResourceState(libResourceName) ~= 'started' then
    error('^1[cortex-lib] cortex-lib must be started before this resource^0')
end

local context = IsDuplicityVersion() and 'server' or 'client'

local cache = {}

if context == 'client' then
    cache = setmetatable({
        ped = nil,
        playerId = nil,
        serverId = nil,
        vehicle = 0,
        seat = -1,
    }, {
        __index = function(self, key)
            return rawget(self, key)
        end,
        __newindex = function(self, key, value)
            rawset(self, key, value)
        end,
    })
    
    CreateThread(function()
        while true do
            cache.playerId = PlayerId()
            cache.ped = PlayerPedId()
            cache.serverId = GetPlayerServerId(cache.playerId)
            
            local vehicle = GetVehiclePedIsIn(cache.ped, false)
            if vehicle ~= cache.vehicle then
                cache.vehicle = vehicle
            end
            
            if vehicle > 0 then
                for i = -1, 16 do
                    if GetPedInVehicleSeat(vehicle, i) == cache.ped then
                        cache.seat = i
                        break
                    end
                end
            else
                cache.seat = -1
            end
            
            Wait(100)
        end
    end)
end

local function loadModule(self, moduleName)
    local dir = ('imports/%s'):format(moduleName)
    
    local chunk = LoadResourceFile(libResourceName, ('%s/%s.lua'):format(dir, context))
    
    local shared = LoadResourceFile(libResourceName, ('%s/shared.lua'):format(dir))
    
    if shared then
        chunk = chunk and ('%s\n%s'):format(shared, chunk) or shared
    end
    
    if not chunk then
        return nil
    end
    
    local fn, err = load(chunk, ('@@cortex-lib/imports/%s/%s.lua'):format(moduleName, context))
    
    if not fn then
        error(('^1[cortex-lib] Error loading module %s: %s^0'):format(moduleName, err))
    end
    
    local result = fn()
    
    if result ~= nil then
        rawset(self, moduleName, result)
    else
        rawset(self, moduleName, function() end)
    end
    
    return rawget(self, moduleName)
end

lib = setmetatable({
    name = libResourceName,
    context = context,
    cache = cache,
}, {
    __index = loadModule,
    __call = function(self, moduleName)
        return loadModule(self, moduleName)
    end,
})

_ENV.lib = lib
_ENV.cache = cache

function lib.load(moduleName)
    if rawget(lib, moduleName) then
        return rawget(lib, moduleName)
    end
    return loadModule(lib, moduleName)
end

function lib.isInternalResource()
    return GetCurrentResourceName() == libResourceName
end

lib._moduleCache = lib._moduleCache or {}

function lib.require(modulePath)
    local resource = GetCurrentResourceName()
    local cacheKey = resource .. ':' .. modulePath

    if lib._moduleCache[cacheKey] ~= nil then
        return lib._moduleCache[cacheKey]
    end

    local filePath = modulePath:gsub('%.', '/') .. '.lua'
    local code = LoadResourceFile(resource, filePath)
    if not code then
        error(('lib.require: missing module "%s" (%s) in %s'):format(modulePath, filePath, resource))
    end

    local chunk, err = load(code, ('@%s/%s'):format(resource, filePath), 't', _ENV)
    if not chunk then
        error(('lib.require: compile error in "%s": %s'):format(filePath, err))
    end

    local result = chunk()
    if result == nil then
        result = true
    end

    lib._moduleCache[cacheKey] = result
    return result
end

if context == 'client' then
    function lib.showInteraction(data)
        return exports[libResourceName]:showInteraction(data)
    end

    function lib.hideInteraction(id)
        return exports[libResourceName]:hideInteraction(id)
    end

    function lib.setInteractions(items)
        return exports[libResourceName]:setInteractions(items)
    end

    function lib.clearInteractions()
        return exports[libResourceName]:clearInteractions()
    end

    function lib.isInteractionActive(id)
        return exports[libResourceName]:isInteractionActive(id)
    end
end

return lib
