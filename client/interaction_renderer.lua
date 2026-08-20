-- Presentation for the shared interaction registry. Gameplay resources own
-- their commands/actions; cortex-lib owns the one consistent NUI surface.

local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sqrt = math.sqrt

local started = true
local nuiReady = false
local lastSafezone = -1.0
local lastWidth = -1
local lastHeight = -1
local worldInteractions = {}
local worldFrameVisible = false

local function send(message)
    if nuiReady then
        SendNUIMessage(message)
    end
end

local function copyPresentationItem(item)
    return {
        id = item.id,
        owner = item.owner,
        label = item.label,
        key = item.key,
    }
end

local function clearWorldFrame()
    worldInteractions = {}

    if worldFrameVisible then
        send({ action = 'interaction:world', data = { items = {} } })
    end

    worldFrameVisible = false
end

local function sendCurrentInteractions()
    local items = lib.getInteractions and select(1, lib.getInteractions()) or {}
    local screenItems = {}
    local nextWorldInteractions = {}

    for index = 1, #items do
        local item = items[index]

        if item.active ~= false then
            if type(item.anchor) == 'table' then
                nextWorldInteractions[#nextWorldInteractions + 1] = item
            else
                screenItems[#screenItems + 1] = copyPresentationItem(item)
            end
        end
    end

    worldInteractions = nextWorldInteractions

    if #worldInteractions == 0 and worldFrameVisible then
        clearWorldFrame()
    end

    send({ action = 'interaction:update', data = { items = screenItems } })
end

local function sendLayout(force)
    local safezone = tonumber(GetSafeZoneSize()) or 1.0
    local width, height = GetActiveScreenResolution()

    width = math_max(1, tonumber(width) or 1920)
    height = math_max(1, tonumber(height) or 1080)
    safezone = math_max(0.0, math_min(1.0, safezone))

    if not force
        and math_abs(safezone - lastSafezone) < 0.0005
        and width == lastWidth
        and height == lastHeight
    then
        return
    end

    lastSafezone = safezone
    lastWidth = width
    lastHeight = height

    local normalizedInset = (1.0 - safezone) * 0.5

    send({
        action = 'interaction:layout',
        data = {
            safezone = safezone,
            insetRight = math_floor((width * normalizedInset) + 0.5),
            insetBottom = math_floor((height * normalizedInset) + 0.5),
            screenWidth = width,
            screenHeight = height,
        },
    })
end

local function resolveAnchor(anchor)
    if type(anchor) ~= 'table' then return nil end

    local offset = type(anchor.offset) == 'table' and anchor.offset or {}
    local offsetX = tonumber(offset.x) or 0.0
    local offsetY = tonumber(offset.y) or 0.0
    local offsetZ = tonumber(offset.z) or 0.0

    if anchor.type == 'world' then
        local x = tonumber(anchor.x)
        local y = tonumber(anchor.y)
        local z = tonumber(anchor.z)
        if not x or not y or not z then return nil end
        return x + offsetX, y + offsetY, z + offsetZ
    end

    if anchor.type ~= 'entity-bone' then return nil end

    local entity = tonumber(anchor.entity)
    if not entity or entity <= 0 or not DoesEntityExist(entity) then return nil end

    local boneIndex = GetEntityBoneIndexByName(entity, anchor.bone)
    if boneIndex == -1 then return nil end

    local coords = GetEntityBonePosition_2(entity, boneIndex)
    if not coords then return nil end

    if offsetX == 0.0 and offsetY == 0.0 and offsetZ == 0.0 then
        return coords.x, coords.y, coords.z
    end

    local entityCoords = GetEntityCoords(entity)
    local offsetCoords = GetOffsetFromEntityInWorldCoords(entity, offsetX, offsetY, offsetZ)
    if not entityCoords or not offsetCoords then return coords.x, coords.y, coords.z end

    return coords.x + offsetCoords.x - entityCoords.x,
        coords.y + offsetCoords.y - entityCoords.y,
        coords.z + offsetCoords.z - entityCoords.z
end

local function buildWorldFrame()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then return {} end

    local pedCoords = GetEntityCoords(ped)
    local frame = {}

    for index = 1, #worldInteractions do
        local item = worldInteractions[index]
        local x, y, z = resolveAnchor(item.anchor)

        if x then
            local dx = pedCoords.x - x
            local dy = pedCoords.y - y
            local dz = pedCoords.z - z
            local distanceSquared = (dx * dx) + (dy * dy) + (dz * dz)
            local maxDistance = tonumber(item.anchor.maxDistance) or 3.0

            if distanceSquared <= (maxDistance * maxDistance) then
                local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)

                if onScreen and screenX >= 0.0 and screenX <= 1.0 and screenY >= 0.0 and screenY <= 1.0 then
                    local entry = copyPresentationItem(item)
                    entry.x = screenX
                    entry.y = screenY
                    entry.distance = math_sqrt(distanceSquared)
                    frame[#frame + 1] = entry
                end
            end
        end
    end

    return frame
end

RegisterNUICallback('interactionReady', function(_, cb)
    nuiReady = true
    sendCurrentInteractions()
    sendLayout(true)
    cb({ ok = true })
end)

AddEventHandler('cortex-lib:interaction:changed', sendCurrentInteractions)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    started = false
    nuiReady = false
    worldInteractions = {}
end)

CreateThread(function()
    while started do
        sendLayout(false)
        Wait(1000)
    end
end)

CreateThread(function()
    while started do
        if not nuiReady or #worldInteractions == 0 then
            Wait(200)
        else
            local frame = buildWorldFrame()

            if #frame > 0 or worldFrameVisible then
                send({ action = 'interaction:world', data = { items = frame } })
            end

            worldFrameVisible = #frame > 0
            Wait(#frame > 0 and 0 or 50)
        end
    end
end)
