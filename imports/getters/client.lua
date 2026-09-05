local GetGamePool = GetGamePool
local GetEntityCoords = GetEntityCoords
local GetActivePlayers = GetActivePlayers
local GetPlayerPed = GetPlayerPed
local DoesEntityExist = DoesEntityExist
local PlayerId = PlayerId
local PlayerPedId = PlayerPedId
local GetVehiclePedIsIn = GetVehiclePedIsIn
local IsPedAPlayer = IsPedAPlayer
local MAX_QUERY_DISTANCE = 100000.0

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function readFiniteCoords(value)
    if value == nil then return nil end

    local ok, x, y, z = pcall(function()
        return value.x, value.y, value.z
    end)

    if not ok or not isFiniteNumber(x) or not isFiniteNumber(y) or not isFiniteNumber(z) then
        return nil
    end

    return x, y, z
end

local function readQuery(coords, maxDistance)
    local x, y, z = readFiniteCoords(coords)
    if not x then return nil end

    maxDistance = maxDistance or 2.0
    if not isFiniteNumber(maxDistance) or maxDistance < 0 or maxDistance > MAX_QUERY_DISTANCE then return nil end

    local maxDistanceSquared = maxDistance * maxDistance
    if not isFiniteNumber(maxDistanceSquared) then return nil end

    return x, y, z, maxDistanceSquared
end

local function isOptionalBoolean(value)
    return value == nil or type(value) == 'boolean'
end

local function getDenseArray(value)
    if type(value) ~= 'table' then return nil end

    local count = 0
    local highestIndex = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 then
            return nil
        end

        count = count + 1
        if key > highestIndex then highestIndex = key end
    end

    if count ~= highestIndex then return nil end
    return value, count
end

local function getDistanceSquared(coords, x, y, z)
    local entityX, entityY, entityZ = readFiniteCoords(coords)
    if not entityX then return nil end

    local dx = entityX - x
    local dy = entityY - y
    local dz = entityZ - z
    return dx * dx + dy * dy + dz * dz
end

local function getClosestPlayer(coords, maxDistance, includePlayer)
    if not isOptionalBoolean(includePlayer) then return nil, nil, nil end

    local cx, cy, cz, maxDistSq = readQuery(coords, maxDistance)
    if not cx then return nil, nil, nil end

    local players = getDenseArray(GetActivePlayers())
    if not players then return nil, nil, nil end

    local closestId = nil
    local closestPed = nil
    local closestCoords = nil
    local closestDistSq = maxDistSq
    local myId = PlayerId()

    for i = 1, #players do
        local playerId = players[i]
        if includePlayer or playerId ~= myId then
            local ped = GetPlayerPed(playerId)
            if DoesEntityExist(ped) then
                local pedCoords = GetEntityCoords(ped)
                local distSq = getDistanceSquared(pedCoords, cx, cy, cz)

                if distSq and distSq < closestDistSq then
                    closestDistSq = distSq
                    closestId = playerId
                    closestPed = ped
                    closestCoords = pedCoords
                end
            end
        end
    end

    return closestId, closestPed, closestCoords
end

local function getClosestVehicle(coords, maxDistance, includePlayerVehicle)
    if not isOptionalBoolean(includePlayerVehicle) then return nil, nil end

    local cx, cy, cz, maxDistSq = readQuery(coords, maxDistance)
    if not cx then return nil, nil end

    local vehicles = getDenseArray(GetGamePool('CVehicle'))
    if not vehicles then return nil, nil end

    local playerVehicle = not includePlayerVehicle and GetVehiclePedIsIn(PlayerPedId(), false) or 0
    local closestVehicle = nil
    local closestCoords = nil
    local closestDistSq = maxDistSq

    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if vehicle ~= playerVehicle and DoesEntityExist(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            local distSq = getDistanceSquared(vehicleCoords, cx, cy, cz)

            if distSq and distSq < closestDistSq then
                closestDistSq = distSq
                closestVehicle = vehicle
                closestCoords = vehicleCoords
            end
        end
    end

    return closestVehicle, closestCoords
end

local function getClosestPed(coords, maxDistance)
    local cx, cy, cz, maxDistSq = readQuery(coords, maxDistance)
    if not cx then return nil, nil end

    local peds = getDenseArray(GetGamePool('CPed'))
    if not peds then return nil, nil end

    local playerPed = PlayerPedId()
    local closestPed = nil
    local closestCoords = nil
    local closestDistSq = maxDistSq

    for i = 1, #peds do
        local ped = peds[i]
        if ped ~= playerPed and not IsPedAPlayer(ped) and DoesEntityExist(ped) then
            local pedCoords = GetEntityCoords(ped)
            local distSq = getDistanceSquared(pedCoords, cx, cy, cz)

            if distSq and distSq < closestDistSq then
                closestDistSq = distSq
                closestPed = ped
                closestCoords = pedCoords
            end
        end
    end

    return closestPed, closestCoords
end

local function getClosestObject(coords, maxDistance)
    local cx, cy, cz, maxDistSq = readQuery(coords, maxDistance)
    if not cx then return nil, nil end

    local objects = getDenseArray(GetGamePool('CObject'))
    if not objects then return nil, nil end

    local closestObject = nil
    local closestCoords = nil
    local closestDistSq = maxDistSq

    for i = 1, #objects do
        local object = objects[i]
        if DoesEntityExist(object) then
            local objectCoords = GetEntityCoords(object)
            local distSq = getDistanceSquared(objectCoords, cx, cy, cz)

            if distSq and distSq < closestDistSq then
                closestDistSq = distSq
                closestObject = object
                closestCoords = objectCoords
            end
        end
    end

    return closestObject, closestCoords
end

local function getNearbyPlayers(coords, maxDistance, includePlayer)
    if not isOptionalBoolean(includePlayer) then return {} end

    local cx, cy, cz, maxDistSq = readQuery(coords, maxDistance)
    if not cx then return {} end

    local players = getDenseArray(GetActivePlayers())
    if not players then return {} end

    local myId = PlayerId()
    local nearby = {}

    for i = 1, #players do
        local playerId = players[i]
        if includePlayer or playerId ~= myId then
            local ped = GetPlayerPed(playerId)
            if DoesEntityExist(ped) then
                local pedCoords = GetEntityCoords(ped)
                local distSq = getDistanceSquared(pedCoords, cx, cy, cz)

                if distSq and distSq <= maxDistSq then
                    nearby[#nearby + 1] = { id = playerId, ped = ped, coords = pedCoords }
                end
            end
        end
    end

    return nearby
end

local function getNearbyVehicles(coords, maxDistance, includePlayerVehicle)
    if not isOptionalBoolean(includePlayerVehicle) then return {} end

    local cx, cy, cz, maxDistSq = readQuery(coords, maxDistance)
    if not cx then return {} end

    local vehicles = getDenseArray(GetGamePool('CVehicle'))
    if not vehicles then return {} end

    local playerVehicle = not includePlayerVehicle and GetVehiclePedIsIn(PlayerPedId(), false) or 0
    local nearby = {}

    for i = 1, #vehicles do
        local vehicle = vehicles[i]
        if vehicle ~= playerVehicle and DoesEntityExist(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            local distSq = getDistanceSquared(vehicleCoords, cx, cy, cz)

            if distSq and distSq <= maxDistSq then
                nearby[#nearby + 1] = { vehicle = vehicle, coords = vehicleCoords }
            end
        end
    end

    return nearby
end

local function getNearbyPeds(coords, maxDistance)
    local cx, cy, cz, maxDistSq = readQuery(coords, maxDistance)
    if not cx then return {} end

    local peds = getDenseArray(GetGamePool('CPed'))
    if not peds then return {} end

    local playerPed = PlayerPedId()
    local nearby = {}

    for i = 1, #peds do
        local ped = peds[i]
        if ped ~= playerPed and not IsPedAPlayer(ped) and DoesEntityExist(ped) then
            local pedCoords = GetEntityCoords(ped)
            local distSq = getDistanceSquared(pedCoords, cx, cy, cz)

            if distSq and distSq <= maxDistSq then
                nearby[#nearby + 1] = { ped = ped, coords = pedCoords }
            end
        end
    end

    return nearby
end

local function getNearbyObjects(coords, maxDistance)
    local cx, cy, cz, maxDistSq = readQuery(coords, maxDistance)
    if not cx then return {} end

    local objects = getDenseArray(GetGamePool('CObject'))
    if not objects then return {} end

    local nearby = {}

    for i = 1, #objects do
        local object = objects[i]
        if DoesEntityExist(object) then
            local objectCoords = GetEntityCoords(object)
            local distSq = getDistanceSquared(objectCoords, cx, cy, cz)

            if distSq and distSq <= maxDistSq then
                nearby[#nearby + 1] = { object = object, coords = objectCoords }
            end
        end
    end

    return nearby
end

exports('getClosestPlayer', getClosestPlayer)
exports('getClosestVehicle', getClosestVehicle)
exports('getClosestPed', getClosestPed)
exports('getClosestObject', getClosestObject)
exports('getNearbyPlayers', getNearbyPlayers)
exports('getNearbyVehicles', getNearbyVehicles)
exports('getNearbyPeds', getNearbyPeds)
exports('getNearbyObjects', getNearbyObjects)

lib.getClosestPlayer = getClosestPlayer
lib.getClosestVehicle = getClosestVehicle
lib.getClosestPed = getClosestPed
lib.getClosestObject = getClosestObject
lib.getNearbyPlayers = getNearbyPlayers
lib.getNearbyVehicles = getNearbyVehicles
lib.getNearbyPeds = getNearbyPeds
lib.getNearbyObjects = getNearbyObjects

return {
    getClosestPlayer = getClosestPlayer,
    getClosestVehicle = getClosestVehicle,
    getClosestPed = getClosestPed,
    getClosestObject = getClosestObject,
    getNearbyPlayers = getNearbyPlayers,
    getNearbyVehicles = getNearbyVehicles,
    getNearbyPeds = getNearbyPeds,
    getNearbyObjects = getNearbyObjects
}
