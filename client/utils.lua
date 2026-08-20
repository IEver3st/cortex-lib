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
local SendNUIMessage = SendNUIMessage

local sqrt = math.sqrt
local pcall = pcall

local uiAppHandlers = {}

function lib.clearPool(poolName, centerCoords, radius, excludeEntity)
    local pool = GetGamePool(poolName)
    local radiusSq = radius * radius
    local cx, cy, cz = centerCoords.x, centerCoords.y, centerCoords.z
    local count = 0
    
    for i = 1, #pool do
        local entity = pool[i]
        if entity ~= excludeEntity and DoesEntityExist(entity) then
            local eCoords = GetEntityCoords(entity)
            local dx = eCoords.x - cx
            local dy = eCoords.y - cy
            local dz = eCoords.z - cz
            local distSq = dx * dx + dy * dy + dz * dz
            
            if distSq <= radiusSq then
                SetEntityAsMissionEntity(entity, true, true)
                DeleteEntity(entity)
                count = count + 1
            end
        end
    end
    
    return count
end

function lib.clearPools(poolNames, centerCoords, radius, excludeEntity)
    local total = 0
    for i = 1, #poolNames do
        total = total + lib.clearPool(poolNames[i], centerCoords, radius, excludeEntity)
    end
    return total
end

function lib.findNearestInPool(poolName, centerCoords, maxRadius, excludeEntity)
    local pool = GetGamePool(poolName)
    maxRadius = maxRadius or 50.0
    local maxRadiusSq = maxRadius * maxRadius
    local cx, cy, cz = centerCoords.x, centerCoords.y, centerCoords.z
    
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
    if lib.cache and type(lib.cache.ped) == 'number' and lib.cache.ped > 0 then
        return lib.cache.ped
    end
    return PlayerPedId()
end

function lib.getPlayerId()
    if lib.cache and type(lib.cache.playerId) == 'number' and lib.cache.playerId >= 0 then
        return lib.cache.playerId
    end
    return PlayerId()
end

function lib.isInVehicle(includeLastVehicle)
    local ped = lib.getPed()
    return GetVehiclePedIsIn(ped, includeLastVehicle or false) ~= 0
end

function lib.getCurrentVehicle(includeLastVehicle)
    local ped = lib.getPed()
    local vehicle = GetVehiclePedIsIn(ped, includeLastVehicle or false)
    if vehicle ~= 0 then
        return vehicle
    end
    return nil
end

function lib.getCoords()
    return GetEntityCoords(lib.getPed())
end

function lib.getHeading()
    return GetEntityHeading(lib.getPed())
end

function lib.ensureVehicle(showNotify)
    local ped = lib.getPed()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
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
    SendNUIMessage({
        action = 'copyToClipboard',
        data = { text = tostring(text) }
    })
end

function lib.registerUiApp(appId, handler)
    if type(appId) ~= 'string' or appId == '' then
        error('cortex-lib.registerUiApp: appId must be a non-empty string')
    end

    if type(handler) ~= 'function' then
        error('cortex-lib.registerUiApp: handler must be a function')
    end

    uiAppHandlers[appId] = handler
    return true
end

function lib.unregisterUiApp(appId)
    uiAppHandlers[appId] = nil
    return true
end

function lib.openUiApp(appId, payload)
    SendNUIMessage({
        action = 'uiAppOpen',
        data = {
            id = appId,
            payload = payload or {}
        }
    })
end

function lib.updateUiApp(appId, payload)
    SendNUIMessage({
        action = 'uiAppData',
        data = {
            id = appId,
            payload = payload or {}
        }
    })
end

function lib.closeUiApp(appId)
    SendNUIMessage({
        action = 'uiAppClose',
        data = {
            id = appId
        }
    })
end

RegisterNUICallback('cortex:uiEvent', function(data, cb)
    local appId = data and data.appId
    local eventType = data and data.type
    local payload = data and data.payload or {}
    local handler = appId and uiAppHandlers[appId]

    if type(handler) ~= 'function' then
        cb({
            ok = false,
            error = 'unregistered_app'
        })
        return
    end

    local ok, result = pcall(handler, eventType, payload)
    if not ok then
        print(('^1[cortex-lib]^7 ui app handler "%s" failed: %s'):format(appId, result))
        cb({
            ok = false,
            error = 'handler_error'
        })
        return
    end

    if type(result) == 'table' then
        if result.ok == nil then
            result.ok = true
        end

        cb(result)
        return
    end

    cb({
        ok = true,
        result = result
    })
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
exports('registerUiApp', lib.registerUiApp)
exports('unregisterUiApp', lib.unregisterUiApp)
exports('openUiApp', lib.openUiApp)
exports('updateUiApp', lib.updateUiApp)
exports('closeUiApp', lib.closeUiApp)

return lib
