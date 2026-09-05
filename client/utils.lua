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

local uiAppHandlers = {}
local uiAppCount = 0
local CURRENT_RESOURCE = GetCurrentResourceName()
local MAX_UI_APPS = 16
local MAX_UI_PAYLOAD_NODES = 128
local MAX_UI_PAYLOAD_DEPTH = 4
local MAX_CLIPBOARD_LENGTH = 16384
local SUPPORTED_UI_APPS = { weatherzonesEditor = true }
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

local function isSafePayloadString(value, maxLength, allowEmpty)
    return type(value) == 'string'
        and (allowEmpty or value ~= '')
        and #value <= maxLength
        and not value:find('%c')
end

local function isSafePayloadKey(value)
    return isSafePayloadString(value, 128, false)
        and value ~= '__proto__'
        and value ~= 'prototype'
        and value ~= 'constructor'
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

local function validatePayload(value, depth, budget, seen)
    local valueType = type(value)
    if valueType == 'nil' or valueType == 'boolean' then return true end
    if valueType == 'number' then return isFiniteNumber(value) end
    if valueType == 'string' then return isSafePayloadString(value, 2048, true) end
    if valueType ~= 'table' or depth > MAX_UI_PAYLOAD_DEPTH or seen[value] then return false end

    seen[value] = true
    for key, child in next, value do
        budget.count = budget.count + 1
        if budget.count > MAX_UI_PAYLOAD_NODES then
            seen[value] = nil
            return false
        end

        if (type(key) ~= 'string' and type(key) ~= 'number')
            or (type(key) == 'string' and not isSafePayloadKey(key))
            or (type(key) == 'number' and not isFiniteNumber(key))
            or not validatePayload(child, depth + 1, budget, seen)
        then
            seen[value] = nil
            return false
        end
    end

    seen[value] = nil
    return true
end

local function copyPayload(value, depth, budget, seen)
    local valueType = type(value)
    if valueType ~= 'table' then
        if valueType == 'nil' or valueType == 'boolean' then return value end
        if valueType == 'number' then return isFiniteNumber(value) and value or nil end
        if valueType == 'string' then return isSafePayloadString(value, 2048, true) and value or nil end
        return nil
    end
    if depth > MAX_UI_PAYLOAD_DEPTH or seen[value] then return nil end

    seen[value] = true
    local copy = {}
    for key, child in next, value do
        budget.count = budget.count + 1
        if budget.count > MAX_UI_PAYLOAD_NODES
            or (type(key) == 'string' and not isSafePayloadKey(key))
            or (type(key) == 'number' and not isFiniteNumber(key))
            or (type(key) ~= 'string' and type(key) ~= 'number')
        then
            seen[value] = nil
            return nil
        end

        local childCopy = copyPayload(child, depth + 1, budget, seen)
        if type(child) == 'table' and childCopy == nil then
            seen[value] = nil
            return nil
        end
        copy[key] = childCopy
    end
    seen[value] = nil
    return copy
end

local function normalizePayload(value)
    local validateOk, valid = pcall(validatePayload, value, 0, { count = 0 }, {})
    if not validateOk or not valid then return nil end

    if type(value) ~= 'table' then return value end
    local copyOk, copy = pcall(copyPayload, value, 0, { count = 0 }, {})
    if not copyOk then return nil end
    return copy
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

local function closeCurrentModal(reason)
    if not modalState.surface then return false end

    local previousSurface = modalState.surface
    local previousGeneration = modalState.generation
    modalState.surface = nil
    modalState.resource = nil
    modalState.focused = false
    releaseNativeFocus()

    local closer = modalClosers[previousSurface]
    if closer then
        local ok, err = pcall(closer, previousGeneration, reason or 'replaced')
        if not ok then
            print(('^1[cortex-lib]^7 modal closer "%s" failed: %s'):format(previousSurface, safeErrorText(err)))
        end
    end

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

function lib._focusModal(surface, generation, keepInput)
    if modalState.surface ~= surface or modalState.generation ~= generation then
        return false
    end

    SetNuiFocus(true, true)
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

    modalState.surface = nil
    modalState.resource = nil
    modalState.focused = false
    releaseNativeFocus()
    return true
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

function lib.registerUiApp(appId, handler)
    if not isBoundedString(appId, 64) or not appId:match('^[%w:_%-%.]+$') then
        error('cortex-lib.registerUiApp: appId must be a non-empty string')
    end

    if type(handler) ~= 'function' then
        error('cortex-lib.registerUiApp: handler must be a function')
    end
    if not SUPPORTED_UI_APPS[appId] then return false, 'unsupported_app' end

    local owner = getInvokingOwner()
    local existing = uiAppHandlers[appId]
    if existing and existing.owner ~= owner then
        return false, 'owned_by_other_resource'
    end

    if not existing and uiAppCount >= MAX_UI_APPS then
        return false, 'capacity_exceeded'
    end

    if existing and existing.session then
        local session = existing.session
        existing.session = nil
        lib._releaseModal('uiApp:' .. appId, session)
        SendNUIMessage({ action = 'uiAppClose', data = { id = appId, session = session, reason = 're_registered' } })
    end

    if not existing then uiAppCount = uiAppCount + 1 end
    uiAppHandlers[appId] = {
        owner = owner,
        handler = handler,
        session = nil,
    }
    return true
end

function lib.unregisterUiApp(appId)
    local entry = uiAppHandlers[appId]
    if not entry then return false end
    if entry.owner ~= getInvokingOwner() then return false, 'not_owner' end

    if entry.session then
        lib._releaseModal('uiApp:' .. appId, entry.session)
        SendNUIMessage({ action = 'uiAppClose', data = { id = appId, session = entry.session } })
    end
    uiAppHandlers[appId] = nil
    modalClosers['uiApp:' .. appId] = nil
    uiAppCount = math.max(0, uiAppCount - 1)
    return true
end

function lib.openUiApp(appId, payload)
    local entry = uiAppHandlers[appId]
    if not entry or entry.owner ~= getInvokingOwner() then return false, 'not_owner' end
    local normalizedPayload = normalizePayload(payload or {})
    if not normalizedPayload then return false, 'invalid_payload' end

    local session = lib._acquireModal('uiApp:' .. appId, entry.owner)
    if not session then return false, 'modal_unavailable' end
    entry.session = session
    lib._registerModalSurface('uiApp:' .. appId, function(generation, reason)
        local current = uiAppHandlers[appId]
        if current and current.session == generation then
            current.session = nil
            SendNUIMessage({ action = 'uiAppClose', data = { id = appId, session = generation, reason = reason } })
        end
    end)
    SendNUIMessage({
        action = 'uiAppOpen',
        data = {
            id = appId,
            payload = normalizedPayload,
            session = session,
        }
    })
    if not lib._focusModal('uiApp:' .. appId, session, false) then
        entry.session = nil
        lib._releaseModal('uiApp:' .. appId, session)
        SendNUIMessage({ action = 'uiAppClose', data = { id = appId, session = session, reason = 'focus_failed' } })
        return false, 'focus_failed'
    end
    return true
end

function lib.updateUiApp(appId, payload)
    local entry = uiAppHandlers[appId]
    if not entry or entry.owner ~= getInvokingOwner() then return false, 'not_owner' end
    local normalizedPayload = normalizePayload(payload or {})
    if not entry.session
        or not lib._matchesModal('uiApp:' .. appId, entry.session, entry.session)
        or not normalizedPayload
    then
        return false, 'invalid_state'
    end

    SendNUIMessage({
        action = 'uiAppData',
        data = {
            id = appId,
            payload = normalizedPayload,
            session = entry.session,
        }
    })
    return true
end

function lib.closeUiApp(appId)
    local entry = uiAppHandlers[appId]
    if not entry or entry.owner ~= getInvokingOwner() then return false, 'not_owner' end

    local session = entry.session
    entry.session = nil
    if session then lib._releaseModal('uiApp:' .. appId, session) end
    SendNUIMessage({
        action = 'uiAppClose',
        data = {
            id = appId,
            session = session,
        }
    })
    return true
end

RegisterNUICallback('cortex:uiEvent', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false, error = 'invalid_payload' })
        return
    end

    local appId = data.appId
    local eventType = data.type
    local payload = normalizePayload(data.payload or {})
    local entry = appId and uiAppHandlers[appId]

    if not isBoundedString(appId, 64)
        or not isBoundedString(eventType, 64)
        or not isSafePayloadString(eventType, 64, false)
        or type(payload) ~= 'table'
    then
        cb({ ok = false, error = 'invalid_payload' })
        return
    end

    if not entry or type(entry.handler) ~= 'function' then
        cb({
            ok = false,
            error = 'unregistered_app'
        })
        return
    end

    if not lib._matchesModal('uiApp:' .. appId, entry.session, data.session) then
        cb({ ok = false, error = 'stale_session' })
        return
    end

    local ok, result = pcall(entry.handler, eventType, payload)
    if not ok then
        print(('^1[cortex-lib]^7 ui app handler "%s" failed: %s'):format(appId, safeErrorText(result)))
        cb({
            ok = false,
            error = 'handler_error'
        })
        return
    end

    local resultBudget = { count = 0 }
    local validateOk, resultValid = pcall(validatePayload, result, 0, resultBudget, {})
    if not validateOk or not resultValid then
        cb({ ok = false, error = 'invalid_handler_result' })
        return
    end

    if type(result) == 'table' then
        local copyBudget = { count = 0 }
        local copyOk, response = pcall(copyPayload, result, 0, copyBudget, {})
        if not copyOk or not response or (response.ok == nil and copyBudget.count >= MAX_UI_PAYLOAD_NODES) then
            cb({ ok = false, error = 'invalid_handler_result' })
            return
        end
        if response.ok == nil then response.ok = true end
        cb(response)
        return
    end

    cb({
        ok = true,
        result = result
    })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == CURRENT_RESOURCE or modalState.resource == resourceName then
        closeCurrentModal('resource_stop')
    end

    local removed = 0
    for appId, entry in pairs(uiAppHandlers) do
        if entry.owner == resourceName then
            uiAppHandlers[appId] = nil
            modalClosers['uiApp:' .. appId] = nil
            removed = removed + 1
        end
    end
    uiAppCount = math.max(0, uiAppCount - removed)
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
