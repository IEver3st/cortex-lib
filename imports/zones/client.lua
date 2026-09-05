local GetEntityCoords = GetEntityCoords
local DoesEntityExist = DoesEntityExist
local PlayerPedId = PlayerPedId
local DrawLine = DrawLine
local DrawMarker = DrawMarker
local Wait = Wait

local sin = math.sin
local cos = math.cos
local rad = math.rad
local abs = math.abs
local min = math.min
local max = math.max

local zones = {}
local zoneId = 0
local checkInterval = 250
local maxPolygonPoints = 1024
local reservedFields = {
    id = true,
    type = true,
    points = true,
    thickness = true,
    minX = true,
    maxX = true,
    minY = true,
    maxY = true,
    minZ = true,
    maxZ = true,
    center = true,
    coords = true,
    size = true,
    rotation = true,
    rotRad = true,
    cosR = true,
    sinR = true,
    halfX = true,
    halfY = true,
    halfZ = true,
    radius = true,
    radiusSq = true,
    debug = true,
    onEnter = true,
    onExit = true,
    inside = true,
    isInside = true,
    contains = true,
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

local function validateCallbacks(data, apiName)
    for _, callbackName in ipairs({ 'onEnter', 'onExit', 'inside' }) do
        local callback = data[callbackName]
        if callback ~= nil and type(callback) ~= 'function' then
            error(('%s.%s must be a function'):format(apiName, callbackName), 3)
        end
    end
end

local function validateDebug(data, apiName)
    if data.debug ~= nil and type(data.debug) ~= 'boolean' then
        error(('%s.debug must be a boolean'):format(apiName), 3)
    end
end

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    return ok and text or '<unprintable error>'
end

local function invokeCallback(zone, callbackName)
    local callback = zone[callbackName]
    if type(callback) ~= 'function' then return end

    local ok, err = pcall(callback, zone)
    if not ok then
        print(('^1[cortex-lib] zone %s callback failed: %s^0'):format(callbackName, safeErrorText(err)))
    end
end

local function hasZones()
    return next(zones) ~= nil
end

local function copyMetadata(zone, data)
    for key, value in pairs(data) do
        if not reservedFields[key] then
            zone[key] = value
        end
    end
end

local function isUsablePed(ped)
    if type(ped) ~= 'number' or ped <= 0 then return false end
    if type(DoesEntityExist) ~= 'function' then return true end

    local ok, exists = pcall(DoesEntityExist, ped)
    return ok and exists == true
end

local function pointInPolygon(x, y, points)
    local inside = false
    local j = #points
    
    for i = 1, #points do
        local xi, yi = points[i].x, points[i].y
        local xj, yj = points[j].x, points[j].y
        
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        
        j = i
    end
    
    return inside
end

local ZoneMethods = {}
ZoneMethods.__index = ZoneMethods

function ZoneMethods:remove()
    zones[self.id] = nil
end

local function poly(data)
    if type(data) ~= 'table' then
        error('lib.zones.poly requires a data table', 2)
    end

    local points = data.points
    if type(points) ~= 'table' then
        error('lib.zones.poly requires a dense points array', 2)
    end

    local count = 0
    local highestIndex = 0
    for key in pairs(points) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 then
            error('lib.zones.poly requires a dense points array', 2)
        end
        count = count + 1
        highestIndex = max(highestIndex, key)
    end

    if count < 3 or count ~= highestIndex or count > maxPolygonPoints then
        error(('lib.zones.poly requires a dense array of 3 to %d points'):format(maxPolygonPoints), 2)
    end

    local validatedPoints = {}
    local sumX, sumY, sumZ = 0, 0, 0

    for i = 1, count do
        local p = points[i]
        local x, y, z = readFiniteCoords(p)
        if not x then
            error(('lib.zones.poly point %d must contain finite x, y and z values'):format(i), 2)
        end

        validatedPoints[i] = vector3(x, y, z)
        sumX = sumX + x
        sumY = sumY + y
        sumZ = sumZ + z

        if not isFiniteNumber(sumX) or not isFiniteNumber(sumY) or not isFiniteNumber(sumZ) then
            error('lib.zones.poly point aggregate exceeds the finite coordinate range', 2)
        end
    end

    local minX, maxX = validatedPoints[1].x, validatedPoints[1].x
    local minY, maxY = validatedPoints[1].y, validatedPoints[1].y
    local minZ, maxZ = validatedPoints[1].z, validatedPoints[1].z
    for i = 2, count do
        local p = validatedPoints[i]
        minX = min(minX, p.x)
        maxX = max(maxX, p.x)
        minY = min(minY, p.y)
        maxY = max(maxY, p.y)
        minZ = min(minZ, p.z)
        maxZ = max(maxZ, p.z)
    end

    local thickness = data.thickness or 4.0
    if not isFiniteNumber(thickness) or thickness <= 0 then
        error('lib.zones.poly thickness must be a positive finite number', 2)
    end

    if not isFiniteNumber(maxZ + thickness) then
        error('lib.zones.poly height exceeds the finite coordinate range', 2)
    end

    validateCallbacks(data, 'lib.zones.poly')
    validateDebug(data, 'lib.zones.poly')
    zoneId = zoneId + 1

    local zone = setmetatable({
        id = zoneId,
        type = 'poly',
        points = validatedPoints,
        thickness = thickness,
        minZ = minZ,
        maxZ = maxZ + thickness,
        minX = minX,
        maxX = maxX,
        minY = minY,
        maxY = maxY,
        center = vector3(sumX / count, sumY / count, sumZ / count),
        debug = data.debug == true,
        onEnter = data.onEnter,
        onExit = data.onExit,
        inside = data.inside,
        isInside = false
    }, ZoneMethods)
    
    copyMetadata(zone, data)
    
    function zone:contains(point)
        local pointX, pointY, pointZ = readFiniteCoords(point)
        if not pointX then return false end

        if pointX < self.minX or pointX > self.maxX or
           pointY < self.minY or pointY > self.maxY or
           pointZ < self.minZ or pointZ > self.maxZ then
            return false
        end

        return pointInPolygon(pointX, pointY, self.points)
    end
    
    zones[zoneId] = zone
    return zone
end

local function box(data)
    if type(data) ~= 'table' then
        error('lib.zones.box requires a data table', 2)
    end

    local coords = data.coords
    local x, y, z = readFiniteCoords(coords)
    if not x then
        error('lib.zones.box coords must contain finite x, y and z values', 2)
    end

    local size = data.size or vector3(2, 2, 2)
    local sizeX, sizeY, sizeZ = readFiniteCoords(size)
    if not sizeX or sizeX <= 0 or sizeY <= 0 or sizeZ <= 0 then
        error('lib.zones.box size must contain positive finite x, y and z values', 2)
    end

    local rotation = data.rotation or 0
    if not isFiniteNumber(rotation) then
        error('lib.zones.box rotation must be a finite number', 2)
    end

    validateCallbacks(data, 'lib.zones.box')
    validateDebug(data, 'lib.zones.box')
    zoneId = zoneId + 1

    local rotRad = rad(rotation % 360.0)
    local cosR = cos(rotRad)
    local sinR = sin(rotRad)
    
    local halfX = sizeX / 2
    local halfY = sizeY / 2
    local halfZ = sizeZ / 2
    
    local zone = setmetatable({
        id = zoneId,
        type = 'box',
        coords = vector3(x, y, z),
        size = vector3(sizeX, sizeY, sizeZ),
        rotation = rotation,
        rotRad = rotRad,
        cosR = cosR,
        sinR = sinR,
        halfX = halfX,
        halfY = halfY,
        halfZ = halfZ,
        debug = data.debug == true,
        onEnter = data.onEnter,
        onExit = data.onExit,
        inside = data.inside,
        isInside = false
    }, ZoneMethods)
    
    copyMetadata(zone, data)
    
    function zone:contains(point)
        local pointX, pointY, pointZ = readFiniteCoords(point)
        if not pointX then return false end

        local dx = pointX - self.coords.x
        local dy = pointY - self.coords.y
        local dz = pointZ - self.coords.z
        
        local localX = dx * self.cosR + dy * self.sinR
        local localY = -dx * self.sinR + dy * self.cosR
        
        return abs(localX) <= self.halfX and
               abs(localY) <= self.halfY and
               abs(dz) <= self.halfZ
    end
    
    zones[zoneId] = zone
    return zone
end

local function sphere(data)
    if type(data) ~= 'table' then
        error('lib.zones.sphere requires a data table', 2)
    end

    local coords = data.coords
    local x, y, z = readFiniteCoords(coords)
    if not x then
        error('lib.zones.sphere coords must contain finite x, y and z values', 2)
    end

    local radius = data.radius or 2.0
    if not isFiniteNumber(radius) or radius <= 0 then
        error('lib.zones.sphere radius must be a positive finite number', 2)
    end


    if not isFiniteNumber(radius * radius) then
        error('lib.zones.sphere radius exceeds the finite distance range', 2)
    end

    validateCallbacks(data, 'lib.zones.sphere')
    validateDebug(data, 'lib.zones.sphere')
    zoneId = zoneId + 1

    local radiusSq = radius * radius
    
    local zone = setmetatable({
        id = zoneId,
        type = 'sphere',
        coords = vector3(x, y, z),
        radius = radius,
        radiusSq = radiusSq,
        debug = data.debug == true,
        onEnter = data.onEnter,
        onExit = data.onExit,
        inside = data.inside,
        isInside = false
    }, ZoneMethods)
    
    copyMetadata(zone, data)
    
    function zone:contains(point)
        local pointX, pointY, pointZ = readFiniteCoords(point)
        if not pointX then return false end

        local dx = pointX - self.coords.x
        local dy = pointY - self.coords.y
        local dz = pointZ - self.coords.z
        return (dx * dx + dy * dy + dz * dz) <= self.radiusSq
    end
    
    zones[zoneId] = zone
    return zone
end

CreateThread(function()
    while true do
        if hasZones() then
            local ped = PlayerPedId()
            local coordsOk, playerCoords = false, nil

            if isUsablePed(ped) then
                coordsOk, playerCoords = pcall(GetEntityCoords, ped)
            end

            local playerX = coordsOk and readFiniteCoords(playerCoords) or nil

            if playerX then
                for _, zone in pairs(zones) do
                    local wasInside = zone.isInside
                    local isInside = zone:contains(playerCoords)
                    zone.isInside = isInside

                    if isInside and not wasInside then
                        invokeCallback(zone, 'onEnter')
                    elseif not isInside and wasInside then
                        invokeCallback(zone, 'onExit')
                    end

                    if isInside then
                        invokeCallback(zone, 'inside')
                    end
                end
            end
        end

        Wait(hasZones() and checkInterval or 500)
    end
end)

CreateThread(function()
    while true do
        local hasDebug = false
        
        for id, zone in pairs(zones) do
            if zone.debug then
                hasDebug = true
                local color = zone.isInside and {0, 255, 0, 100} or {255, 0, 0, 100}
                
                if zone.type == 'sphere' then
                    DrawMarker(28, zone.coords.x, zone.coords.y, zone.coords.z, 
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 
                        zone.radius * 2, zone.radius * 2, zone.radius * 2, 
                        color[1], color[2], color[3], color[4], false, false, 2, false, nil, nil, false)
                        
                elseif zone.type == 'box' then
                    DrawMarker(1, zone.coords.x, zone.coords.y, zone.coords.z, 
                        0.0, 0.0, 0.0, 0.0, 0.0, zone.rotation, 
                        zone.size.x, zone.size.y, zone.size.z, 
                        color[1], color[2], color[3], color[4], false, false, 2, false, nil, nil, false)
                        
                elseif zone.type == 'poly' then
                    local points = zone.points
                    for i = 1, #points do
                        local p1 = points[i]
                        local p2 = points[i % #points + 1]
                        DrawLine(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, color[1], color[2], color[3], 200)
                        DrawLine(p1.x, p1.y, p1.z + zone.thickness, p2.x, p2.y, p2.z + zone.thickness, color[1], color[2], color[3], 200)
                        DrawLine(p1.x, p1.y, p1.z, p1.x, p1.y, p1.z + zone.thickness, color[1], color[2], color[3], 200)
                    end
                end
            end
        end
        
        if hasDebug then
            Wait(0)
        else
            Wait(500)
        end
    end
end)

local zonesModule = {
    poly = poly,
    box = box,
    sphere = sphere
}

lib.zones = zonesModule

return zonesModule
