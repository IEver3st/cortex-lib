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

    local GetPedInVehicleSeat = GetPedInVehicleSeat
    local GetVehicleMaxNumberOfPassengers = GetVehicleMaxNumberOfPassengers
    local GetVehiclePedIsIn = GetVehiclePedIsIn
    local PlayerId = PlayerId
    local PlayerPedId = PlayerPedId

    local function findPedSeat(vehicle, ped)
        local passengerCount = math.max(0, math.floor(tonumber(GetVehicleMaxNumberOfPassengers(vehicle)) or 0))

        for seat = -1, passengerCount - 1 do
            if GetPedInVehicleSeat(vehicle, seat) == ped then
                return seat
            end
        end

        return -1
    end

    cache.playerId = PlayerId()
    cache.serverId = GetPlayerServerId(cache.playerId)

    CreateThread(function()
        while true do
            local playerId = PlayerId()
            if playerId ~= cache.playerId then
                cache.playerId = playerId
                cache.serverId = GetPlayerServerId(playerId)
            end

            local ped = PlayerPedId()
            cache.ped = ped

            if ped ~= 0 then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle > 0 then
                    local vehicleChanged = vehicle ~= cache.vehicle
                    cache.vehicle = vehicle
                    local seat = cache.seat

                    if vehicleChanged or type(seat) ~= 'number' or GetPedInVehicleSeat(vehicle, seat) ~= ped then
                        cache.seat = findPedSeat(vehicle, ped)
                    end
                else
                    cache.vehicle = 0
                    cache.seat = -1
                end
            else
                cache.vehicle = 0
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

    function lib.getInteractionState(id)
        return exports[libResourceName]:getInteractionState(id)
    end

    function lib.isInteractionActive(id)
        return exports[libResourceName]:isInteractionActive(id)
    end

    function lib.isInteractionVisible(id)
        return exports[libResourceName]:isInteractionVisible(id)
    end

    function lib.startInteractionHold(id)
        return exports[libResourceName]:startInteractionHold(id)
    end

    function lib.cancelInteractionHold(id)
        return exports[libResourceName]:cancelInteractionHold(id)
    end
end

return lib
