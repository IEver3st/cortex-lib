lib = lib or {}

local PlayerPedId = PlayerPedId
local PlayerId = PlayerId
local GetEntityCoords = GetEntityCoords
local GetEntityHeading = GetEntityHeading
local DoesEntityExist = DoesEntityExist
local DeleteEntity = DeleteEntity
local SetEntityAsMissionEntity = SetEntityAsMissionEntity
local GetGamePool = GetGamePool
local IsEntityDead = IsEntityDead
local GetEntityHealth = GetEntityHealth
local GetEntityModel = GetEntityModel
local GetVehiclePedIsIn = GetVehiclePedIsIn
local GetVehicleMaxNumberOfPassengers = GetVehicleMaxNumberOfPassengers
local GetPedInVehicleSeat = GetPedInVehicleSeat
local SendNUIMessage = SendNUIMessage
local SetNuiFocus = SetNuiFocus
local SetNuiFocusKeepInput = SetNuiFocusKeepInput
local IsPedAPlayer = IsPedAPlayer
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local NetworkHasControlOfEntity = NetworkHasControlOfEntity
local IsNuiFocused = IsNuiFocused

local sqrt = math.sqrt
local pcall = pcall
local huge = math.huge

local CURRENT_RESOURCE = GetCurrentResourceName()
local MAX_CLIPBOARD_LENGTH = 16384
local VALID_POOLS = {
    CPed = true,
    CObject = true,
    CVehicle = true,
    CPickup = true,
}

local modalState = {
    surface = nil,
    resource = nil,
    generation = 0,
    focused = false,
}
local modalClosers = {}

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value ~= huge and value ~= -huge
end

local function isBoundedString(value, maxLength)
    return type(value) == 'string' and value ~= '' and #value <= maxLength and not value:find('\0', 1, true)
end

local function isValidEntityHandle(entity)
    if type(entity) ~= 'number' or math.tointeger(entity) ~= entity or entity <= 0 then return false end
    local ok, exists = pcall(DoesEntityExist, entity)
    return ok and exists == true
end

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    return ok and type(text) == 'string' and text or '<unprintable error>'
end

local function getVectorComponents(value)
    local ok, x, y, z = pcall(function() return value.x, value.y, value.z end)
    if not ok or not isFiniteNumber(x) or not isFiniteNumber(y) or not isFiniteNumber(z) then
        return nil
    end
    return x, y, z
end

local function getInvokingOwner()
    local owner = GetInvokingResource and GetInvokingResource() or nil
    return owner or CURRENT_RESOURCE
end

local function isDenseArray(value, maxItems)
    if type(value) ~= 'table' then return false end

    local length = #value
    if length > maxItems then return false end

    local count = 0
    for key in next, value do
        if type(key) ~= 'number' or math.tointeger(key) ~= key or key < 1 or key > length then
            return false
        end
        count = count + 1
    end

    return count == length
end

local function vehicleHasPlayerOccupant(vehicle, localPlayerVehicle)
    if vehicle == localPlayerVehicle then return true end
    if type(GetVehicleMaxNumberOfPassengers) ~= 'function'
        or type(GetPedInVehicleSeat) ~= 'function'
        or type(IsPedAPlayer) ~= 'function'
    then
        return true
    end

    local maxPassengers = tonumber(GetVehicleMaxNumberOfPassengers(vehicle))
    if not isFiniteNumber(maxPassengers) then return true end
    maxPassengers = math.min(64, math.max(0, math.floor(maxPassengers)))

    for seat = -1, maxPassengers do
        local occupant = GetPedInVehicleSeat(vehicle, seat)
        if occupant and occupant ~= 0 and IsPedAPlayer(occupant) then return true end
    end
    return false
end

local function releaseNativeFocus()
    SetNuiFocus(false, false)
    if type(SetNuiFocusKeepInput) == 'function' then
        SetNuiFocusKeepInput(false)
    end
end

local modalReleaseObservers = {}
local function notifyModalReleased(generation, reason)
    local observer = modalReleaseObservers[generation]
    modalReleaseObservers[generation] = nil
    if observer then
        SetTimeout(0, function()
            if GetResourceState(observer.owner) == 'started' then
                pcall(observer.callback, generation, reason)
            end
        end)
    end
end

local function closeCurrentModal(reason)
    if not modalState.surface then return false end

    local previousSurface = modalState.surface
    local previousGeneration = modalState.generation
    local external = modalState.external
    modalState.external = nil
    modalState.surface = nil
    modalState.resource = nil
    modalState.focused = false
    if not external then releaseNativeFocus() end

    local closer = modalClosers[previousSurface]
    if external then modalClosers[previousSurface] = nil end
    if closer then
        local ok, err = pcall(closer, previousGeneration, reason or 'replaced')
        if not ok then
            print(('^1[cortex-lib]^7 modal closer "%s" failed: %s'):format(previousSurface, safeErrorText(err)))
        end
    end

    notifyModalReleased(previousGeneration, reason or 'replaced')
    return true
end


function lib._registerModalSurface(surface, closer)
    if not isBoundedString(surface, 64) or type(closer) ~= 'function' then
        return false
    end

    modalClosers[surface] = closer
    return true
end

function lib._acquireModal(surface, resourceName)
    if not isBoundedString(surface, 64) then return nil end
    if not modalState.surface and type(IsNuiFocused) == 'function' and IsNuiFocused() then return nil end

    closeCurrentModal('replaced')
    modalState.generation = modalState.generation + 1
    modalState.surface = surface
    modalState.resource = resourceName or getInvokingOwner()
    modalState.focused = false
    return modalState.generation
end

function lib._focusModal(surface, generation, keepInput, cursor)
    if modalState.surface ~= surface or modalState.generation ~= generation then
        return false
    end

    SetNuiFocus(true, cursor ~= false)
    if type(SetNuiFocusKeepInput) == 'function' then
        SetNuiFocusKeepInput(keepInput == true)
    end
    modalState.focused = true
    return true
end

function lib._matchesModal(surface, generation, suppliedGeneration)
    return modalState.surface == surface
        and modalState.generation == generation
        and type(suppliedGeneration) == 'number'
        and math.tointeger(suppliedGeneration) == generation
end

function lib._releaseModal(surface, generation)
    if modalState.surface ~= surface or modalState.generation ~= generation then
        return false
    end

    if modalState.external then return closeCurrentModal('released') end
    modalState.surface = nil
    modalState.resource = nil
    modalState.focused = false
    releaseNativeFocus()
    notifyModalReleased(generation, 'released')
    return true
end

-- Frame-bound guards only need occupancy, not an allocated snapshot.
function lib._hasModalSurface()
    return modalState.surface ~= nil
end

function lib._getModalState()
    return {
        surface = modalState.surface,
        resource = modalState.resource,
        generation = modalState.generation,
        focused = modalState.focused,
    }
end

for surface, closer in pairs(rawget(lib, '_pendingModalSurfaces') or {}) do
    lib._registerModalSurface(surface, closer)
end
rawset(lib, '_pendingModalSurfaces', nil)

function lib.clearPool(poolName, centerCoords, radius, excludeEntity)
    local cx, cy, cz = getVectorComponents(centerCoords)
    if not VALID_POOLS[poolName]
        or cx == nil
        or not isFiniteNumber(radius)
        or radius < 0.0
        or radius > 500.0
    then
        return 0
    end

    local pool = GetGamePool(poolName)
    if type(pool) ~= 'table' then return 0 end

    local radiusSq = radius * radius
    local count = 0
    local playerPed = PlayerPedId()
    local localPlayerVehicle = type(GetVehiclePedIsIn) == 'function'
        and GetVehiclePedIsIn(playerPed, false)
        or 0
    
    for i = 1, #pool do
        local entity = pool[i]
        local entityExists = DoesEntityExist(entity)
        local isPlayerPed = entityExists and poolName == 'CPed'
            and (entity == playerPed or (type(IsPedAPlayer) == 'function' and IsPedAPlayer(entity)))
        local isPlayerVehicle = entityExists and poolName == 'CVehicle'
            and vehicleHasPlayerOccupant(entity, localPlayerVehicle)
        local hasControl = entityExists and (type(NetworkGetEntityIsNetworked) ~= 'function'
            or not NetworkGetEntityIsNetworked(entity)
            or (type(NetworkHasControlOfEntity) == 'function' and NetworkHasControlOfEntity(entity)))

        if entity ~= excludeEntity and not isPlayerPed and not isPlayerVehicle and hasControl then
            local eCoords = GetEntityCoords(entity)
            local dx = eCoords.x - cx
            local dy = eCoords.y - cy
            local dz = eCoords.z - cz
            local distSq = dx * dx + dy * dy + dz * dz
            
            if distSq <= radiusSq then
                SetEntityAsMissionEntity(entity, true, true)
                DeleteEntity(entity)
                if not DoesEntityExist(entity) then
                    count = count + 1
                end
            end
        end
    end
    
    return count
end

function lib.clearPools(poolNames, centerCoords, radius, excludeEntity)
    if not isDenseArray(poolNames, 4) then return 0 end

    local total = 0
    for i = 1, #poolNames do
        total = total + lib.clearPool(poolNames[i], centerCoords, radius, excludeEntity)
    end
    return total
end

function lib.findNearestInPool(poolName, centerCoords, maxRadius, excludeEntity)
    local cx, cy, cz = getVectorComponents(centerCoords)
    if not VALID_POOLS[poolName]
        or cx == nil
    then
        return nil, huge
    end

    local pool = GetGamePool(poolName)
    maxRadius = maxRadius or 50.0
    if type(pool) ~= 'table' or not isFiniteNumber(maxRadius) or maxRadius < 0.0 or maxRadius > 5000.0 then
        return nil, huge
    end
    local maxRadiusSq = maxRadius * maxRadius
    local nearestEntity = nil
    local nearestDistSq = maxRadiusSq
    
    for i = 1, #pool do
        local entity = pool[i]
        if entity ~= excludeEntity and DoesEntityExist(entity) then
            local eCoords = GetEntityCoords(entity)
            local dx = eCoords.x - cx
            local dy = eCoords.y - cy
            local dz = eCoords.z - cz
            local distSq = dx * dx + dy * dy + dz * dz
            
            if distSq < nearestDistSq then
                nearestDistSq = distSq
                nearestEntity = entity
            end
        end
    end
    
    if nearestEntity then
        return nearestEntity, sqrt(nearestDistSq)
    end
    
    return nil, math.huge
end

function lib.getPed()
    if lib.cache and isValidEntityHandle(lib.cache.ped) then
        return lib.cache.ped
    end

    local ok, ped = pcall(PlayerPedId)
    if ok and isValidEntityHandle(ped) then return ped end
    return nil
end

function lib.getPlayerId()
    if lib.cache and type(lib.cache.playerId) == 'number' and lib.cache.playerId >= 0 then
        return lib.cache.playerId
    end
    return PlayerId()
end

function lib.isInVehicle(includeLastVehicle)
    if includeLastVehicle ~= nil and type(includeLastVehicle) ~= 'boolean' then return false end
    local ped = lib.getPed()
    if not ped then return false end

    local ok, vehicle = pcall(GetVehiclePedIsIn, ped, includeLastVehicle == true)
    return ok and isValidEntityHandle(vehicle)
end

function lib.getCurrentVehicle(includeLastVehicle)
    if includeLastVehicle ~= nil and type(includeLastVehicle) ~= 'boolean' then return nil end
    local ped = lib.getPed()
    if not ped then return nil end

    local ok, vehicle = pcall(GetVehiclePedIsIn, ped, includeLastVehicle == true)
    if ok and isValidEntityHandle(vehicle) then return vehicle end
    return nil
end

function lib.getCoords()
    local ped = lib.getPed()
    if not ped then return nil end

    local ok, coords = pcall(GetEntityCoords, ped)
    if not ok or not getVectorComponents(coords) then return nil end
    return coords
end

function lib.getHeading()
    local ped = lib.getPed()
    if not ped then return nil end

    local ok, heading = pcall(GetEntityHeading, ped)
    return ok and isFiniteNumber(heading) and heading or nil
end

function lib.ensureVehicle(showNotify)
    local ped = lib.getPed()
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    
    if vehicle == 0 then
        if showNotify and lib.notify then
            lib.notify({ type = 'error', description = 'You are not in a vehicle.' })
        end
        return nil
    end
    
    return vehicle
end

function lib.getCamDirection()
    local rot = GetGameplayCamRot(2)
    local rotZ = math.rad(rot.z)
    local rotX = math.rad(rot.x)
    local cosX = math.cos(rotX)
    
    return vector3(
        -math.sin(rotZ) * cosX,
        math.cos(rotZ) * cosX,
        math.sin(rotX)
    )
end

function lib.copyToClipboard(text)
    local textType = type(text)
    if textType ~= 'string' and textType ~= 'number' then return false, 'invalid_text' end
    if textType == 'number' and not isFiniteNumber(text) then return false, 'invalid_text' end

    text = tostring(text)
    if #text > MAX_CLIPBOARD_LENGTH or text:find('\0', 1, true) then return false, 'invalid_text' end

    SendNUIMessage({
        action = 'copyToClipboard',
        data = { text = text }
    })
    return true
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == CURRENT_RESOURCE or modalState.resource == resourceName then
        closeCurrentModal('resource_stop')
    end
end)

exports('clearPool', lib.clearPool)
exports('clearPools', lib.clearPools)
exports('findNearestInPool', lib.findNearestInPool)

exports('getPed', lib.getPed)
exports('getPlayerId', lib.getPlayerId)
exports('isInVehicle', lib.isInVehicle)
exports('getCurrentVehicle', lib.getCurrentVehicle)
exports('getCoords', lib.getCoords)
exports('getHeading', lib.getHeading)
exports('ensureVehicle', lib.ensureVehicle)

exports('getCamDirection', lib.getCamDirection)

exports('copyToClipboard', lib.copyToClipboard)

-- External renderers retain their own iframe; this library arbitrates ownership.
local function isExternalCallback(value)
    if type(value) == 'function' then return true end
    if type(value) ~= 'table' then return false end
    local mt = getmetatable(value)
    return type(mt) == 'table' and type(rawget(mt,'__call')) == 'function'
end
exports('getExternalFocusVersion', function() return 1 end)
exports('ownsExternalFocus', function(token)
    return modalState.external == true and modalState.resource == getInvokingOwner()
        and modalState.generation == token
end)
exports('acquireExternalFocus', function(onRevoke)
    local owner = getInvokingOwner()
    if owner == CURRENT_RESOURCE or not isExternalCallback(onRevoke) or modalState.surface
        or IsNuiFocused() then return false end
    modalState.generation = modalState.generation + 1
    modalState.surface, modalState.resource, modalState.external = 'external', owner, true
    modalState.focused = true
    modalClosers.external = onRevoke
    return modalState.generation
end)
exports('releaseExternalFocus', function(token)
    if not modalState.external or modalState.resource ~= getInvokingOwner()
        or modalState.generation ~= token then return false end
    return closeCurrentModal('released')
end)
exports('openSettingsHandoff', function(onClose)
    local owner = getInvokingOwner()
    if owner == CURRENT_RESOURCE or not isExternalCallback(onClose) or modalState.surface
        or IsNuiFocused() then return false end
    if not lib.openSettingsMenu() or modalState.surface ~= 'settings'
        or modalState.resource ~= owner then return false end
    local token = modalState.generation
    modalReleaseObservers[token] = { owner=owner, callback=onClose }
    return token
end)

return lib
