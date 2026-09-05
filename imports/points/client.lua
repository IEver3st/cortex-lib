local GetEntityCoords = GetEntityCoords
local DoesEntityExist = DoesEntityExist
local PlayerPedId = PlayerPedId
local Wait = Wait

local sqrt = math.sqrt

local points = {}
local pointId = 0
local nearbyPoints = {}
local closestPoint = nil
local nearbyThreadActive = false
local MAX_POINT_DISTANCE = 100000.0
local reservedFields = {
    id = true,
    coords = true,
    distance = true,
    currentDistance = true,
    isClosest = true,
    _wasNearby = true,
    remove = true,
}

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

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    return ok and text or '<unprintable error>'
end

local function invokeCallback(point, callbackName)
    local callback = point[callbackName]
    if type(callback) ~= 'function' then return end

    local ok, err = pcall(callback, point)
    if not ok then
        print(('^1[cortex-lib] point %s callback failed: %s^0'):format(callbackName, safeErrorText(err)))
    end
end

local function hasPoints()
    return next(points) ~= nil
end

local function isUsablePed(ped)
    if type(ped) ~= 'number' or ped <= 0 then return false end
    if type(DoesEntityExist) ~= 'function' then return true end

    local ok, exists = pcall(DoesEntityExist, ped)
    return ok and exists == true
end

local CPoint = {}
CPoint.__index = CPoint

function CPoint:remove()
    points[self.id] = nil
    
    for i = #nearbyPoints, 1, -1 do
        if nearbyPoints[i].id == self.id then
            table.remove(nearbyPoints, i)
            break
        end
    end
    
    if closestPoint and closestPoint.id == self.id then
        closestPoint = nil
    end
end

local function new(data)
    if type(data) ~= 'table' then
        error('lib.points.new requires a data table', 2)
    end

    local coords = data.coords
    local x, y, z = readFiniteCoords(coords)
    if not x then
        error('lib.points.new coords must contain finite x, y and z values', 2)
    end

    local distance = data.distance or 5.0
    if not isFiniteNumber(distance) or distance <= 0 or distance > MAX_POINT_DISTANCE then
        error('lib.points.new distance must be a positive finite number', 2)
    end

    for _, callbackName in ipairs({ 'onEnter', 'onExit', 'nearby' }) do
        local callback = data[callbackName]
        if callback ~= nil and type(callback) ~= 'function' then
            error(('lib.points.new %s must be a function'):format(callbackName), 2)
        end
    end

    pointId = pointId + 1

    local point = setmetatable({
        id = pointId,
        coords = coords,
        distance = distance,
        currentDistance = math.huge,
        isClosest = false,
        _wasNearby = false
    }, CPoint)
    
    for k, v in pairs(data) do
        if not reservedFields[k] then
            point[k] = v
        end
    end
    
    points[pointId] = point
    return point
end

local function getAllPoints()
    local result = {}
    local count = 0
    
    for _, point in pairs(points) do
        count = count + 1
        result[count] = point
    end
    
    return result
end

local function getNearbyPoints()
    local snapshot = {}
    for index = 1, #nearbyPoints do
        snapshot[index] = nearbyPoints[index]
    end
    return snapshot
end

local function getClosestPoint()
    return closestPoint
end

local function startNearbyThread()
    if nearbyThreadActive or #nearbyPoints == 0 then return end

    nearbyThreadActive = true
    CreateThread(function()
        while #nearbyPoints > 0 do
            for i = 1, #nearbyPoints do
                local point = nearbyPoints[i]
                if point then
                    invokeCallback(point, 'nearby')
                end
            end

            Wait(0)
        end

        nearbyThreadActive = false
    end)
end

CreateThread(function()
    while true do
        if hasPoints() then
            local ped = PlayerPedId()
            local coordsOk, playerCoords = false, nil

            if isUsablePed(ped) then
                coordsOk, playerCoords = pcall(GetEntityCoords, ped)
            end

            local px, py, pz
            if coordsOk then
                px, py, pz = readFiniteCoords(playerCoords)
            end

            nearbyPoints = {}
            closestPoint = nil

            if px then
                local nearbyCount = 0
                local closestDistSq = math.huge

                for _, point in pairs(points) do
                    local x, y, z = readFiniteCoords(point.coords)
                    local distance = point.distance
                    local wasNearby = point._wasNearby
                    local isNearby = false

                    point.isClosest = false

                    if x and isFiniteNumber(distance) and distance > 0 and distance <= MAX_POINT_DISTANCE then
                        local dx = x - px
                        local dy = y - py
                        local dz = z - pz
                        local distSq = dx * dx + dy * dy + dz * dz

                        if isFiniteNumber(distSq) then
                            local dist = sqrt(distSq)

                            point.currentDistance = dist
                            isNearby = dist <= distance

                            if distSq < closestDistSq then
                                closestDistSq = distSq
                                closestPoint = point
                            end
                        else
                            point.currentDistance = math.huge
                        end
                    else
                        point.currentDistance = math.huge
                    end

                    if isNearby and not wasNearby then
                        invokeCallback(point, 'onEnter')
                    elseif not isNearby and wasNearby then
                        invokeCallback(point, 'onExit')
                    end

                    point._wasNearby = isNearby

                    if isNearby then
                        nearbyCount = nearbyCount + 1
                        nearbyPoints[nearbyCount] = point
                    end
                end

                if closestPoint then
                    closestPoint.isClosest = true
                end

                startNearbyThread()
            else
                for _, point in pairs(points) do
                    local wasNearby = point._wasNearby
                    point._wasNearby = false
                    point.isClosest = false
                    point.currentDistance = math.huge

                    if wasNearby then
                        invokeCallback(point, 'onExit')
                    end
                end
            end
        end

        Wait(hasPoints() and 100 or 500)
    end
end)

local pointsModule = {
    new = new,
    getAllPoints = getAllPoints,
    getNearbyPoints = getNearbyPoints,
    getClosestPoint = getClosestPoint
}

lib.points = pointsModule

return pointsModule
