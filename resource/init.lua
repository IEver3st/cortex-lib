local libResourceName = 'cortex-lib'
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

function lib.hasLoaded()
    return true
end

exports('hasLoaded', lib.hasLoaded)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == libResourceName then
        TriggerEvent('cortex-lib:loaded')
    end
end)

local coreModules = {
    'settings',
    'notify',
    'menu',
    'radial',
    'callback',
    'help',
    'interaction',
    'getters',
}

for _, moduleName in ipairs(coreModules) do
    lib.load(moduleName)
end

return lib
