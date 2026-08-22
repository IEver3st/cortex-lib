-- Presentation for the shared interaction registry. Gameplay resources own
-- their commands/actions; cortex-lib owns the one consistent NUI surface.

local math_abs = math.abs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_sqrt = math.sqrt

local DoesEntityExist = DoesEntityExist
local GetActiveScreenResolution = GetActiveScreenResolution
local GetEntityBoneIndexByName = GetEntityBoneIndexByName
local GetEntityBonePosition_2 = GetEntityBonePosition_2
local GetEntityCoords = GetEntityCoords
local GetEntityModel = GetEntityModel
local GetOffsetFromEntityInWorldCoords = GetOffsetFromEntityInWorldCoords
local GetSafeZoneSize = GetSafeZoneSize
local PlayerPedId = PlayerPedId
local SendNUIMessage = SendNUIMessage
local Wait = Wait
local World3dToScreen2d = World3dToScreen2d
local playerCache = lib.cache

local started = true
local nuiReady = false
local lastSafezone = -1.0
local lastWidth = -1
local lastHeight = -1
local lastScreenItems = nil
local worldInteractions = {}
local worldFrameItems = {}
local worldFrameMessage = { action = 'interaction:world', data = { items = worldFrameItems } }
local emptyWorldFrameMessage = { action = 'interaction:world', data = { items = {} } }
local visibleWorldInteractions = {}
local lastWorldInteractions = {}
local lastWorldCount = 0
local worldFrameVisible = false
local worldFrameDirty = true

local function send(message)
    if nuiReady then
        SendNUIMessage(message)
    end
end

local function setPresentationState(item, visible, distance)
    if type(lib._setInteractionPresentationState) ~= 'function' then return end
    lib._setInteractionPresentationState(item.owner, item.id, visible == true, distance)
end

-- Screen prompts communicate a single key press. Hold state is intentionally
-- forwarded only for anchored world prompts, where the ring is visible.
local function copyPresentationItem(item, includeHold)
    local panel = item.panel

    return {
        id = item.id,
        owner = item.owner,
        label = item.label,
        key = item.key,
        panel = type(panel) == 'table' and {
            id = panel.id,
            label = panel.label,
            variant = panel.variant,
        } or nil,
        holdDuration = includeHold and item.holdDuration or nil,
        holdActive = includeHold and item.holdActive == true or false,
        holdRevision = includeHold and (item.holdRevision or 0) or 0,
    }
end

local function presentationPanelsEqual(left, right)
    if left == nil or right == nil then return left == right end
    return left.id == right.id
        and left.label == right.label
        and left.variant == right.variant
end

local function presentationItemsEqual(left, right)
    if left == right then return true end
    if not left or not right or #left ~= #right then return false end

    for index = 1, #left do
        local leftItem = left[index]
        local rightItem = right[index]

        if leftItem.id ~= rightItem.id
            or leftItem.owner ~= rightItem.owner
            or leftItem.label ~= rightItem.label
            or leftItem.key ~= rightItem.key
            or not presentationPanelsEqual(leftItem.panel, rightItem.panel)
            or leftItem.holdDuration ~= rightItem.holdDuration
            or leftItem.holdActive ~= rightItem.holdActive
            or leftItem.holdRevision ~= rightItem.holdRevision
        then
            return false
        end
    end

    return true
end

local function clearArray(items, fromIndex)
    for index = #items, fromIndex or 1, -1 do
        items[index] = nil
    end
end

local function hideWorldFrame()
    if worldFrameVisible then
        send(emptyWorldFrameMessage)
    end

    clearArray(worldFrameItems)
    clearArray(visibleWorldInteractions)
    clearArray(lastWorldInteractions)
    lastWorldCount = 0
    worldFrameVisible = false
end

local function prepareWorldInteraction(item, previous)
    local anchor = item.anchor
    if type(anchor) ~= 'table' then return nil end

    local offset = type(anchor.offset) == 'table' and anchor.offset or {}
    local offsetX = tonumber(offset.x) or 0.0
    local offsetY = tonumber(offset.y) or 0.0
    local offsetZ = tonumber(offset.z) or 0.0
    local maxDistance = tonumber(anchor.maxDistance) or 3.0
    local descriptor = {
        key = item.owner .. '\0' .. item.id,
        type = anchor.type,
        maxDistanceSquared = maxDistance * maxDistance,
        frameItem = copyPresentationItem(item, true),
    }

    if anchor.type == 'world' then
        local x = tonumber(anchor.x)
        local y = tonumber(anchor.y)
        local z = tonumber(anchor.z)
        if not x or not y or not z then return nil end

        descriptor.x = x + offsetX
        descriptor.y = y + offsetY
        descriptor.z = z + offsetZ
        return descriptor
    end

    if anchor.type ~= 'entity' and anchor.type ~= 'entity-bone' then return nil end

    local entity = tonumber(anchor.entity)
    if not entity or entity <= 0 then return nil end
    if anchor.type == 'entity-bone' and type(anchor.bone) ~= 'string' then return nil end

    descriptor.entity = entity
    descriptor.expectedModel = tonumber(anchor.model)
    descriptor.offsetX = offsetX
    descriptor.offsetY = offsetY
    descriptor.offsetZ = offsetZ
    descriptor.hasOffset = offsetX ~= 0.0 or offsetY ~= 0.0 or offsetZ ~= 0.0

    if anchor.type == 'entity' then return descriptor end

    descriptor.bone = anchor.bone
    if previous
        and previous.type == 'entity-bone'
        and previous.entity == entity
        and previous.bone == anchor.bone
    then
        descriptor.entityModel = previous.entityModel
        descriptor.boneIndex = previous.boneIndex
    end

    return descriptor
end

local function sendCurrentInteractions(force)
    local items = lib.getInteractions and select(1, lib.getInteractions()) or {}
    local screenItems = {}
    local nextWorldInteractions = {}
    local previousWorldByKey = {}

    for index = 1, #worldInteractions do
        local descriptor = worldInteractions[index]
        previousWorldByKey[descriptor.key] = descriptor
    end

    for index = 1, #items do
        local item = items[index]

        if item.active ~= false then
            if type(item.anchor) == 'table' then
                local descriptorKey = item.owner .. '\0' .. item.id
                local descriptor = prepareWorldInteraction(item, previousWorldByKey[descriptorKey])
                if descriptor then
                    nextWorldInteractions[#nextWorldInteractions + 1] = descriptor
                else
                    setPresentationState(item, false)
                end
            else
                screenItems[#screenItems + 1] = copyPresentationItem(item)
                setPresentationState(item, nuiReady)
            end
        else
            setPresentationState(item, false)
        end
    end

    worldInteractions = nextWorldInteractions
    worldFrameDirty = true

    if #worldInteractions == 0 and worldFrameVisible then
        hideWorldFrame()
    end

    if force or not presentationItemsEqual(screenItems, lastScreenItems) then
        lastScreenItems = screenItems
        send({ action = 'interaction:update', data = { items = screenItems } })
    end
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

local function resolveAnchor(descriptor)
    if descriptor.type == 'world' then
        return descriptor.x, descriptor.y, descriptor.z
    end

    local entity = descriptor.entity
    if not DoesEntityExist(entity) then
        descriptor.entityModel = nil
        descriptor.boneIndex = nil
        return nil
    end

    local entityModel = GetEntityModel(entity)
    if descriptor.expectedModel and descriptor.expectedModel ~= entityModel then return nil end

    if descriptor.type == 'entity' then
        local coords
        if descriptor.hasOffset then
            coords = GetOffsetFromEntityInWorldCoords(
                entity,
                descriptor.offsetX,
                descriptor.offsetY,
                descriptor.offsetZ
            )
        else
            coords = GetEntityCoords(entity)
        end

        if not coords then return nil end
        return coords.x, coords.y, coords.z
    end

    if descriptor.boneIndex == nil or descriptor.entityModel ~= entityModel then
        descriptor.entityModel = entityModel
        local boneIndex = GetEntityBoneIndexByName(entity, descriptor.bone)
        descriptor.boneIndex = boneIndex ~= -1 and boneIndex or nil
    end

    local boneIndex = descriptor.boneIndex
    if boneIndex == nil then return nil end

    local coords = GetEntityBonePosition_2(entity, boneIndex)
    if not coords then return nil end

    if not descriptor.hasOffset then
        return coords.x, coords.y, coords.z
    end

    local entityCoords = GetEntityCoords(entity)
    local offsetCoords = GetOffsetFromEntityInWorldCoords(
        entity,
        descriptor.offsetX,
        descriptor.offsetY,
        descriptor.offsetZ
    )
    if not entityCoords or not offsetCoords then return coords.x, coords.y, coords.z end

    return coords.x + offsetCoords.x - entityCoords.x,
        coords.y + offsetCoords.y - entityCoords.y,
        coords.z + offsetCoords.z - entityCoords.z
end

local function getPlayerPed()
    local ped = playerCache and playerCache.ped or nil
    if type(ped) ~= 'number' or ped <= 0 or not DoesEntityExist(ped) then
        ped = PlayerPedId()
    end
    return ped
end

local function buildWorldFrame()
    local ped = getPlayerPed()
    if ped == 0 or not DoesEntityExist(ped) then return 0, worldFrameVisible end

    local pedCoords = GetEntityCoords(ped)
    local frameCount = 0
    local frameChanged = worldFrameDirty

    for index = 1, #worldInteractions do
        local descriptor = worldInteractions[index]
        setPresentationState(descriptor.frameItem, false)
        local x, y, z = resolveAnchor(descriptor)

        if x then
            local dx = pedCoords.x - x
            local dy = pedCoords.y - y
            local dz = pedCoords.z - z
            local distanceSquared = (dx * dx) + (dy * dy) + (dz * dz)

            if distanceSquared <= descriptor.maxDistanceSquared then
                local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)

                if onScreen and screenX >= 0.0 and screenX <= 1.0 and screenY >= 0.0 and screenY <= 1.0 then
                    frameCount = frameCount + 1
                    local distance = math_sqrt(distanceSquared)
                    local frameItem = descriptor.frameItem

                    frameItem.x = screenX
                    frameItem.y = screenY
                    frameItem.distance = distance
                    worldFrameItems[frameCount] = frameItem
                    visibleWorldInteractions[frameCount] = descriptor
                    setPresentationState(frameItem, true, distance)

                    if lastWorldInteractions[frameCount] ~= descriptor
                        or descriptor.lastSentX ~= screenX
                        or descriptor.lastSentY ~= screenY
                        or descriptor.lastSentDistance ~= distance
                    then
                        frameChanged = true
                    end
                end
            end
        end
    end

    if frameCount ~= lastWorldCount then
        frameChanged = true
    end

    clearArray(worldFrameItems, frameCount + 1)
    clearArray(visibleWorldInteractions, frameCount + 1)
    return frameCount, frameChanged
end

local function commitWorldFrame(frameCount)
    for index = 1, frameCount do
        local descriptor = visibleWorldInteractions[index]
        local frameItem = worldFrameItems[index]
        descriptor.lastSentX = frameItem.x
        descriptor.lastSentY = frameItem.y
        descriptor.lastSentDistance = frameItem.distance
        lastWorldInteractions[index] = descriptor
    end

    clearArray(lastWorldInteractions, frameCount + 1)
    lastWorldCount = frameCount
    worldFrameDirty = false
end

local function updateWorldFrame()
    local frameCount, frameChanged = buildWorldFrame()

    if frameCount > 0 then
        if frameChanged or not worldFrameVisible then
            send(worldFrameMessage)
            commitWorldFrame(frameCount)
        end

        worldFrameVisible = true
    elseif worldFrameVisible then
        hideWorldFrame()
        worldFrameDirty = false
    else
        worldFrameDirty = false
    end

    return frameCount
end

RegisterNUICallback('interactionReady', function(_, cb)
    nuiReady = true
    sendCurrentInteractions(true)
    sendLayout(true)
    cb({ ok = true })
end)

AddEventHandler('cortex-lib:interaction:changed', function()
    sendCurrentInteractions(false)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    started = false
    nuiReady = false
    lastScreenItems = nil
    worldInteractions = {}
    hideWorldFrame()
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
            local frameCount = updateWorldFrame()
            Wait(frameCount > 0 and 0 or 50)
        end
    end
end)
