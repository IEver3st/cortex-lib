local StartShapeTestLosProbe = StartShapeTestLosProbe
local GetShapeTestResultIncludingMaterial = GetShapeTestResultIncludingMaterial
local GetGameplayCamCoord = GetGameplayCamCoord
local GetGameplayCamRot = GetGameplayCamRot
local PlayerPedId = PlayerPedId
local GetVehiclePedIsIn = GetVehiclePedIsIn
local GetGameTimer = GetGameTimer
local Wait = Wait

local cos = math.cos
local sin = math.sin
local rad = math.rad
local DEFAULT_TIMEOUT = 1000
local MAX_TIMEOUT = 10000

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function validVector(value)
    local ok, x, y, z = pcall(function() return value.x, value.y, value.z end)
    return ok and isFiniteNumber(x) and isFiniteNumber(y) and isFiniteNumber(z)
end

local function normalizeTimeout(timeout)
    timeout = timeout == nil and DEFAULT_TIMEOUT or timeout
    if not isFiniteNumber(timeout) or timeout < 1 or timeout > MAX_TIMEOUT then return nil end
    return math.floor(timeout)
end

local function elapsedSince(now, startedAt)
    local elapsed = now - startedAt
    return elapsed < 0 and elapsed + 4294967296 or elapsed
end

local function getDefaultIgnoreEntity()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 then
        return vehicle
    end

    return ped
end

local function fromCoords(coords, destination, flags, ignore, timeout)
    if not validVector(coords) or not validVector(destination) then
        return false, nil, nil, nil, nil, 'invalid_coordinates'
    end

    flags = flags or 511
    ignore = ignore or getDefaultIgnoreEntity()
    timeout = normalizeTimeout(timeout)
    if type(flags) ~= 'number' or not math.tointeger(flags)
        or (flags ~= -1 and (flags < 0 or flags > 511))
        or type(ignore) ~= 'number' or not math.tointeger(ignore) or not timeout
    then
        return false, nil, nil, nil, nil, 'invalid_options'
    end
    
    local shapeTest = StartShapeTestLosProbe(
        coords.x, coords.y, coords.z,
        destination.x, destination.y, destination.z,
        flags, ignore, 0
    )
    if type(shapeTest) ~= 'number' or shapeTest == 0 then
        return false, nil, nil, nil, nil, 'probe_failed'
    end
    
    local status, hit, endCoords, surfaceNormal, materialHash, entityHit
    
    local startedAt = GetGameTimer()
    repeat
        Wait(0)
        status, hit, endCoords, surfaceNormal, materialHash, entityHit = GetShapeTestResultIncludingMaterial(shapeTest)
        if status == 1 and elapsedSince(GetGameTimer(), startedAt) >= timeout then
            return false, nil, nil, nil, nil, 'timeout'
        end
    until status ~= 1
    
    return hit == 1, entityHit, endCoords, surfaceNormal, materialHash
end

local function fromCamera(flags, ignore, distance, timeout)
    flags = flags or 511
    ignore = ignore or getDefaultIgnoreEntity()
    distance = distance or 10.0
    if not isFiniteNumber(distance) or distance <= 0 or distance > 1000 then
        return false, nil, nil, nil, nil, 'invalid_distance'
    end
    
    local camCoords = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    if not validVector(camCoords) or not validVector(camRot) then
        return false, nil, nil, nil, nil, 'invalid_coordinates'
    end
    
    local rotZ = rad(camRot.z)
    local rotX = rad(camRot.x)
    local cosX = cos(rotX)
    
    local direction = vector3(
        -sin(rotZ) * cosX,
        cos(rotZ) * cosX,
        sin(rotX)
    )
    
    local destination = vector3(
        camCoords.x + direction.x * distance,
        camCoords.y + direction.y * distance,
        camCoords.z + direction.z * distance
    )
    
    return fromCoords(camCoords, destination, flags, ignore, timeout)
end

local raycastModule = {
    fromCoords = fromCoords,
    fromCamera = fromCamera,
    cam = fromCamera
}

lib.raycast = raycastModule

return raycastModule
