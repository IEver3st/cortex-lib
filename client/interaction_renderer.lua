-- Presentation for the shared interaction registry. Gameplay resources own
-- their commands/actions; cortex-lib owns the one consistent NUI surface.
--
-- World prompts have two tiers:
--   prompt  inside anchor.maxDistance: key disc + label, may become visible
--   marker  between maxDistance and anchor.markerDistance: a small dot, never
--           visible, never authorization
-- Prompt-tier anchors that project close together merge into one list. The
-- focused list (nearest screen centre, with a key shared by two or more rows)
-- takes the mouse wheel to move its selection; the selected row wins its key
-- through the registry-private preference.

local math_abs = math.abs
local math_floor = math.floor
local math_huge = math.huge
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

-- Prompts within this fraction of screen height of a list head merge into it.
local LIST_MERGE_RATIO = 0.06
-- Markers closer than this merge into one marker (and hide under a prompt).
local MARKER_MERGE_RATIO = 0.035
local MAX_WORLD_ITEMS = 16

-- Adaptive cadence. A visible prompt, hold or focused list is tracked every
-- frame. Markers are small and faded, so they move at ~30 Hz (the NUI eases
-- the steps). Nothing in range at all polls slowly by distance.
local MARKER_WAIT_MS = 33
local IDLE_NEAR_WAIT_MS = 50
local IDLE_FAR_WAIT_MS = 250
local IDLE_FAR_GAP = 8.0

-- Control indices from docs.fivem.net/docs/game-references/controls:
-- 14 INPUT_WEAPON_WHEEL_NEXT, 15 INPUT_WEAPON_WHEEL_PREV,
-- 16 INPUT_SELECT_NEXT_WEAPON, 17 INPUT_SELECT_PREV_WEAPON,
-- 99 INPUT_VEH_SELECT_NEXT_WEAPON, 115 INPUT_VEH_FLY_SELECT_NEXT_WEAPON,
-- 261 INPUT_PREV_WEAPON, 262 INPUT_NEXT_WEAPON (all mouse wheel),
-- 241 INPUT_CURSOR_SCROLL_UP, 242 INPUT_CURSOR_SCROLL_DOWN.
local WHEEL_BLOCKED_CONTROLS = { 14, 15, 16, 17, 99, 115, 261, 262 }
local WHEEL_UP_CONTROLS = { 15, 17, 241 }
local WHEEL_DOWN_CONTROLS = { 14, 16, 242 }

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
local frameDescriptors = {}
local lastFrameDescriptors = {}
local lastWorldCount = 0
local worldFrameVisible = false
local worldFrameDirty = true
local worldWorkerRunning = false
local startWorldWorker

-- Player preferences (Cortex settings tab). nil means default.
local markersEnabled = true
local invertScroll = false

-- List selection and registry preference, by descriptor key (never handles).
local selectedKey = nil
local preferenceKey = nil

-- Registry events raised while the renderer is mid-frame are deferred so the
-- descriptor list is never replaced under the frame that is using it.
local processing = false
local refreshPending = false
local frameStamp = 0

-- Reused per-frame scratch space (allocation-free steady state).
local promptCandidates = {}
local markerCandidates = {}
local clusters = {}
local clusterCount = 0
local markerHeads = {}

local function send(message)
    if nuiReady then
        SendNUIMessage(message)
    end
end

local function readPreferences()
    local getter = rawget(lib, 'getSetting')
    local nextMarkers, nextInvert = true, false

    if type(getter) == 'function' then
        local ok, value = pcall(getter, 'promptMarkers')
        if ok and value == false then nextMarkers = false end
        ok, value = pcall(getter, 'invertScroll')
        if ok and value == true then nextInvert = true end
    end

    if nextMarkers ~= markersEnabled then worldFrameDirty = true end
    markersEnabled = nextMarkers
    invertScroll = nextInvert
end

local function setPresentationState(item, visible, distance)
    if type(lib._setInteractionPresentationState) ~= 'function' then return end
    lib._setInteractionPresentationState(item.owner, item.id, visible == true, distance)
end

local function setWorldPresentationState(descriptor, visible, distance)
    local nextVisible = visible == true
    local nextDistance = nextVisible and distance or nil
    if descriptor.presentationVisible == nextVisible
        and descriptor.presentationDistance == nextDistance
    then
        return
    end

    descriptor.presentationVisible = nextVisible
    descriptor.presentationDistance = nextDistance
    setPresentationState(descriptor.frameItem, nextVisible, nextDistance)
end

-- Ask the registry to let this row win its key (nil clears). Idempotent.
local function applyPreference(descriptor)
    local key = descriptor and descriptor.key or nil
    if key == preferenceKey then return end
    preferenceKey = key

    local setter = lib._setInteractionPreference
    if type(setter) ~= 'function' then return end
    if descriptor then
        setter(descriptor.owner, descriptor.id)
    else
        setter(nil)
    end
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
            marker = panel.marker,
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
        and left.marker == right.marker
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

local function hideWorldPresentations()
    for index = 1, #worldInteractions do
        setWorldPresentationState(worldInteractions[index], false)
    end

    for index = 1, #lastFrameDescriptors do
        setWorldPresentationState(lastFrameDescriptors[index], false)
    end
end

local function hideWorldFrame()
    hideWorldPresentations()
    selectedKey = nil
    applyPreference(nil)

    if worldFrameVisible then
        send(emptyWorldFrameMessage)
    end

    clearArray(worldFrameItems)
    clearArray(frameDescriptors)
    clearArray(lastFrameDescriptors)
    lastWorldCount = 0
    worldFrameVisible = false
end

local function defaultMarkerDistance(maxDistance)
    return math_min(25.0, math_max(maxDistance + 4.0, maxDistance * 2.5))
end

local function prepareWorldInteraction(item, previous)
    local anchor = item.anchor
    if type(anchor) ~= 'table' then return nil end

    local offset = type(anchor.offset) == 'table' and anchor.offset or {}
    local offsetX = tonumber(offset.x) or 0.0
    local offsetY = tonumber(offset.y) or 0.0
    local offsetZ = tonumber(offset.z) or 0.0
    local maxDistance = tonumber(anchor.maxDistance) or 3.0
    local markerDistance = tonumber(anchor.markerDistance) or defaultMarkerDistance(maxDistance)
    local hasMarkerTier = markerDistance > maxDistance
    local key = item.owner .. '\0' .. item.id
    local descriptor = {
        key = key,
        owner = item.owner,
        id = item.id,
        groupId = item.owner .. ':' .. item.id,
        keyUpper = type(item.key) == 'string' and item.key:upper() or '',
        type = anchor.type,
        maxDistance = maxDistance,
        maxDistanceSquared = maxDistance * maxDistance,
        markerDistance = hasMarkerTier and markerDistance or maxDistance,
        markerDistanceSquared = hasMarkerTier and markerDistance * markerDistance or 0.0,
        frameItem = copyPresentationItem(item, true),
        markerItem = { tier = 'marker', id = item.id, owner = item.owner },
        -- A definition replacement (including a label-only change) resets
        -- registry visibility. Seed the write cache from that current state,
        -- not the old descriptor, so the next projection restores visibility
        -- even when the player and anchor have not moved at all.
        presentationVisible = item.visible == true,
        presentationDistance = item.visible == true and item.distance or nil,
    }
    descriptor.frameItem.tier = 'prompt'

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
    local nextWorldByKey = {}
    -- The natural (priority) owner of each key, ignoring the list preference.
    -- A world row is only offered while its key's natural owner is in the
    -- same list; a screen prompt (false) owning the key excludes world rows.
    local naturalWinners = {}

    for index = 1, #worldInteractions do
        local descriptor = worldInteractions[index]
        previousWorldByKey[descriptor.key] = descriptor
    end

    for index = 1, #items do
        local item = items[index]
        local keyUpper = type(item.key) == 'string' and item.key:upper() or ''
        if naturalWinners[keyUpper] == nil then
            naturalWinners[keyUpper] = type(item.anchor) == 'table' and (item.owner .. '\0' .. item.id) or false
        end

        if type(item.anchor) == 'table' then
            -- Anchored entries are projected even when they lose arbitration:
            -- they can appear as list rows or markers, never as a pressable
            -- prompt of their own.
            local descriptorKey = item.owner .. '\0' .. item.id
            local descriptor = prepareWorldInteraction(item, previousWorldByKey[descriptorKey])
            if descriptor then
                descriptor.winnerKey = naturalWinners[keyUpper]
                descriptor.natural = descriptor.winnerKey == descriptorKey
                nextWorldInteractions[#nextWorldInteractions + 1] = descriptor
                nextWorldByKey[descriptorKey] = true
            elseif not previousWorldByKey[descriptorKey] then
                setPresentationState(item, false)
            end
        elseif item.active ~= false then
            screenItems[#screenItems + 1] = copyPresentationItem(item)
            setPresentationState(item, nuiReady)
        else
            setPresentationState(item, false)
        end
    end

    for index = 1, #worldInteractions do
        local descriptor = worldInteractions[index]
        if not nextWorldByKey[descriptor.key] then setWorldPresentationState(descriptor, false) end
    end

    worldInteractions = nextWorldInteractions
    worldFrameDirty = true
    clearArray(lastFrameDescriptors)
    lastWorldCount = -1

    -- The registry drops a preference whose entry disappeared.
    local getPreference = lib._getInteractionPreference
    if type(getPreference) == 'function' then
        local owner, id = getPreference()
        preferenceKey = owner and (owner .. '\0' .. id) or nil
    end

    if #worldInteractions == 0 and worldFrameVisible then
        hideWorldFrame()
    end

    if force or not presentationItemsEqual(screenItems, lastScreenItems) then
        lastScreenItems = screenItems
        send({ action = 'interaction:update', data = { items = screenItems } })
    end
    startWorldWorker()
end

local function refresh(force)
    if processing then
        refreshPending = true
        return
    end

    processing = true
    sendCurrentInteractions(force)
    processing = false

    while refreshPending do
        refreshPending = false
        processing = true
        sendCurrentInteractions(false)
        processing = false
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

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math_huge
        and value ~= -math_huge
end

local function finiteCoords(coords)
    if coords == nil then return nil end
    local ok, x, y, z = pcall(function()
        return coords.x, coords.y, coords.z
    end)
    if not ok or not isFiniteNumber(x) or not isFiniteNumber(y) or not isFiniteNumber(z) then
        return nil
    end
    return x, y, z
end

local function acquireCluster(index)
    local cluster = clusters[index]
    if not cluster then
        cluster = { rows = {} }
        clusters[index] = cluster
    end
    cluster.count = 0
    cluster.selectedIndex = 1
    cluster.choosable = false
    return cluster
end

local function anyControlJustPressed(controls)
    for index = 1, #controls do
        if IsDisabledControlJustPressed(0, controls[index]) then return true end
    end
    return false
end

-- True while the wheel may be taken: never over the pause menu or while the
-- player is free-aiming (weapon switching stays theirs).
local function canTakeWheel()
    if type(IsPauseMenuActive) == 'function' and IsPauseMenuActive() then return false end
    if type(IsPlayerFreeAiming) == 'function' and type(PlayerId) == 'function'
        and IsPlayerFreeAiming(PlayerId())
    then
        return false
    end
    return type(DisableControlAction) == 'function' and type(IsDisabledControlJustPressed) == 'function'
end

-- Returns -1 (up), 1 (down) or 0 after blocking the native wheel inputs.
local function readWheel()
    for index = 1, #WHEEL_BLOCKED_CONTROLS do
        DisableControlAction(0, WHEEL_BLOCKED_CONTROLS[index], true)
    end

    local delta = 0
    if anyControlJustPressed(WHEEL_UP_CONTROLS) then delta = delta - 1 end
    if anyControlJustPressed(WHEEL_DOWN_CONTROLS) then delta = delta + 1 end
    if invertScroll then delta = -delta end
    return delta
end

local function rowsShareKey(cluster)
    local rows = cluster.rows
    for left = 1, cluster.count - 1 do
        local keyUpper = rows[left].keyUpper
        for right = left + 1, cluster.count do
            if rows[right].keyUpper == keyUpper then return true end
        end
    end
    return false
end

-- Row display activity mirrors the registry once the preference is applied:
-- the preferred row owns its key, otherwise the natural (priority) owner does.
local function rowIsActive(descriptor, preferred)
    if preferred and preferred.keyUpper == descriptor.keyUpper then
        return preferred == descriptor
    end
    return descriptor.natural == true
end

local function stageItem(frameCount, descriptor, item, pixelX, pixelY, centimetres, flags, group)
    frameCount = frameCount + 1
    worldFrameItems[frameCount] = item
    frameDescriptors[frameCount] = descriptor
    descriptor.framePixelX = pixelX
    descriptor.framePixelY = pixelY
    descriptor.frameCentimetres = centimetres
    descriptor.frameFlags = flags
    descriptor.frameGroup = group
    return frameCount
end

-- Returns frameCount, frameChanged, waitMs.
local function buildWorldFrame()
    local ped = getPlayerPed()
    if type(ped) ~= 'number' or ped <= 0 or not DoesEntityExist(ped) then
        hideWorldFrame()
        return 0, false, IDLE_NEAR_WAIT_MS
    end

    local pedX, pedY, pedZ = finiteCoords(GetEntityCoords(ped))
    if not pedX then
        hideWorldFrame()
        return 0, false, IDLE_NEAR_WAIT_MS
    end

    frameStamp = frameStamp + 1
    local stamp = frameStamp
    local screenWidth = lastWidth > 0 and lastWidth or 1920
    local screenHeight = lastHeight > 0 and lastHeight or 1080
    local promptCount, markerCount = 0, 0
    local anyInRange = false
    local nearestGap = math_huge

    -- 1. Project every anchor inside its outer range.
    for index = 1, #worldInteractions do
        local descriptor = worldInteractions[index]
        descriptor.tier = nil
        local x, y, z = resolveAnchor(descriptor)

        if isFiniteNumber(x) and isFiniteNumber(y) and isFiniteNumber(z) then
            local dx = pedX - x
            local dy = pedY - y
            local dz = pedZ - z
            local distanceSquared = (dx * dx) + (dy * dy) + (dz * dz)
            local outerSquared = descriptor.maxDistanceSquared
            local outer = descriptor.maxDistance
            if markersEnabled and descriptor.markerDistanceSquared > outerSquared then
                outerSquared = descriptor.markerDistanceSquared
                outer = descriptor.markerDistance
            end

            if distanceSquared <= outerSquared then
                anyInRange = true
                local onScreen, screenX, screenY = World3dToScreen2d(x, y, z)

                if onScreen
                    and isFiniteNumber(screenX) and isFiniteNumber(screenY)
                    and screenX >= 0.0 and screenX <= 1.0 and screenY >= 0.0 and screenY <= 1.0
                then
                    descriptor.screenX = screenX
                    descriptor.screenY = screenY
                    descriptor.pixelX = screenX * screenWidth
                    descriptor.pixelY = screenY * screenHeight
                    descriptor.distance = math_sqrt(distanceSquared)

                    if distanceSquared <= descriptor.maxDistanceSquared then
                        descriptor.tier = 'prompt'
                        promptCount = promptCount + 1
                        promptCandidates[promptCount] = descriptor
                    else
                        descriptor.tier = 'marker'
                        markerCount = markerCount + 1
                        markerCandidates[markerCount] = descriptor
                    end
                end
            else
                local gap = math_sqrt(distanceSquared) - outer
                if gap < nearestGap then nearestGap = gap end
            end
        end
    end
    clearArray(promptCandidates, promptCount + 1)

    -- 2. Merge prompt-tier anchors into lists at the highest-ranked head.
    local mergeRadius = LIST_MERGE_RATIO * screenHeight
    local mergeSquared = mergeRadius * mergeRadius
    clusterCount = 0

    for index = 1, promptCount do
        local descriptor = promptCandidates[index]
        local target = nil

        for clusterIndex = 1, clusterCount do
            local cluster = clusters[clusterIndex]
            local dx = descriptor.pixelX - cluster.head.pixelX
            local dy = descriptor.pixelY - cluster.head.pixelY
            if (dx * dx) + (dy * dy) <= mergeSquared then
                target = cluster
                break
            end
        end

        if not target then
            clusterCount = clusterCount + 1
            target = acquireCluster(clusterCount)
            target.head = descriptor
        end

        target.count = target.count + 1
        target.rows[target.count] = descriptor
    end

    -- 3. A row is offered only while its key's natural owner is in the same
    --    list; otherwise pressing the key would run something else. Such rows
    --    fall back to the marker tier.
    local keptClusters = 0
    for clusterIndex = 1, clusterCount do
        local cluster = clusters[clusterIndex]
        local rows = cluster.rows
        local kept = 0

        for rowIndex = 1, cluster.count do
            local descriptor = rows[rowIndex]
            local eligible = descriptor.natural == true
            if not eligible and descriptor.winnerKey then
                for other = 1, cluster.count do
                    if rows[other].key == descriptor.winnerKey then
                        eligible = true
                        break
                    end
                end
            end

            if eligible then
                kept = kept + 1
                rows[kept] = descriptor
            else
                descriptor.tier = 'marker'
                markerCount = markerCount + 1
                markerCandidates[markerCount] = descriptor
            end
        end

        clearArray(rows, kept + 1)
        cluster.count = kept
        if kept > 0 then
            cluster.head = rows[1]
            keptClusters = keptClusters + 1
            if keptClusters ~= clusterIndex then
                clusters[clusterIndex], clusters[keptClusters] = clusters[keptClusters], cluster
            end
        end
    end
    clusterCount = keptClusters
    clearArray(markerCandidates, markerCount + 1)

    -- 4. Focus: the list nearest the screen centre that has a real choice.
    local focused = nil
    local focusDistance = math_huge
    for clusterIndex = 1, clusterCount do
        local cluster = clusters[clusterIndex]
        cluster.choosable = cluster.count > 1 and rowsShareKey(cluster)
        if cluster.choosable then
            local dx = cluster.head.pixelX - (screenWidth * 0.5)
            local dy = cluster.head.pixelY - (screenHeight * 0.5)
            local distance = (dx * dx) + (dy * dy)
            if distance < focusDistance then
                focused = cluster
                focusDistance = distance
            end
        end
    end

    local takesWheel = false
    local preferred = nil
    if focused then
        local rows = focused.rows
        local selected = 1
        local holding = false
        for rowIndex = 1, focused.count do
            local descriptor = rows[rowIndex]
            if descriptor.key == selectedKey then selected = rowIndex end
            if descriptor.frameItem.holdActive then holding = true end
        end

        takesWheel = canTakeWheel()
        if takesWheel then
            local delta = readWheel()
            -- A hold in progress freezes the selection: scrolling cannot move
            -- a consumer's running hold onto a different row.
            if delta ~= 0 and not holding then
                selected = math_max(1, math_min(focused.count, selected + delta))
            end
        end

        focused.selectedIndex = selected
        selectedKey = rows[selected].key
        if selected ~= 1 then preferred = rows[selected] end
    else
        selectedKey = nil
    end

    -- Apply before presentation writes so the registry agrees this frame.
    applyPreference(preferred)

    -- 5. Stage prompt rows (list heads carry the anchor for the whole list).
    local frameCount = 0
    local needsEveryFrame = false

    for clusterIndex = 1, clusterCount do
        local cluster = clusters[clusterIndex]
        local head = cluster.head
        local pixelX = math_floor(head.pixelX + 0.5)
        local pixelY = math_floor(head.pixelY + 0.5)
        local centimetres = math_floor(head.distance * 100 + 0.5)
        local isFocused = cluster == focused and takesWheel
        needsEveryFrame = true

        for rowIndex = 1, cluster.count do
            if frameCount >= MAX_WORLD_ITEMS then break end
            local descriptor = cluster.rows[rowIndex]
            local item = descriptor.frameItem
            local active = rowIsActive(descriptor, preferred)
            local selected = rowIndex == cluster.selectedIndex

            item.tier = 'prompt'
            item.group = head.groupId
            item.x = head.screenX
            item.y = head.screenY
            item.distance = head.distance
            item.selected = selected
            item.active = active
            item.focused = isFocused
            item.fade = nil

            local flags = (selected and 2 or 0) + (active and 4 or 0) + (isFocused and 8 or 0)
            frameCount = stageItem(frameCount, descriptor, item, pixelX, pixelY, centimetres, flags, head.groupId)
            descriptor.frameStamp = stamp
            -- Only the row that owns its key is visible (actionable).
            setWorldPresentationState(descriptor, active, descriptor.distance)
        end
    end

    -- 6. Markers: merged, hidden under prompts, faded with distance.
    local markerHeadCount = 0
    if markersEnabled then
        local markerRadius = MARKER_MERGE_RATIO * screenHeight
        local markerSquared = markerRadius * markerRadius

        for index = 1, markerCount do
            if frameCount >= MAX_WORLD_ITEMS then break end
            local descriptor = markerCandidates[index]
            local hidden = false

            for clusterIndex = 1, clusterCount do
                local head = clusters[clusterIndex].head
                local dx = descriptor.pixelX - head.pixelX
                local dy = descriptor.pixelY - head.pixelY
                if (dx * dx) + (dy * dy) <= mergeSquared then
                    hidden = true
                    break
                end
            end

            if not hidden then
                for headIndex = 1, markerHeadCount do
                    local head = markerHeads[headIndex]
                    local dx = descriptor.pixelX - head.pixelX
                    local dy = descriptor.pixelY - head.pixelY
                    if (dx * dx) + (dy * dy) <= markerSquared then
                        hidden = true
                        break
                    end
                end
            end

            if not hidden then
                markerHeadCount = markerHeadCount + 1
                markerHeads[markerHeadCount] = descriptor

                local span = descriptor.markerDistance - descriptor.maxDistance
                local near = 1.0
                if span > 0.0 and descriptor.distance > descriptor.maxDistance then
                    near = math_max(0.0, math_min(1.0, (descriptor.markerDistance - descriptor.distance) / span))
                end
                local fadeStep = math_floor(near * 20 + 0.5)
                local item = descriptor.markerItem
                item.x = descriptor.screenX
                item.y = descriptor.screenY
                item.distance = descriptor.distance
                item.fade = fadeStep / 20

                frameCount = stageItem(
                    frameCount,
                    descriptor,
                    item,
                    math_floor(descriptor.pixelX + 0.5),
                    math_floor(descriptor.pixelY + 0.5),
                    0,
                    1 + (fadeStep * 16),
                    descriptor.groupId
                )
            end
        end
    end
    clearArray(markerHeads, markerHeadCount + 1)

    -- Everything not presented as an actionable row is not visible.
    for index = 1, #worldInteractions do
        local descriptor = worldInteractions[index]
        if descriptor.frameStamp ~= stamp then setWorldPresentationState(descriptor, false) end
    end

    clearArray(worldFrameItems, frameCount + 1)
    clearArray(frameDescriptors, frameCount + 1)

    local frameChanged = worldFrameDirty or frameCount ~= lastWorldCount
    if not frameChanged then
        -- Compare at whole-pixel / centimetre resolution so idle bone sway
        -- and float noise do not re-send an identical frame to CEF; the sent
        -- values themselves stay exact.
        for index = 1, frameCount do
            local descriptor = frameDescriptors[index]
            if lastFrameDescriptors[index] ~= descriptor
                or descriptor.lastSentPixelX ~= descriptor.framePixelX
                or descriptor.lastSentPixelY ~= descriptor.framePixelY
                or descriptor.lastSentCentimetres ~= descriptor.frameCentimetres
                or descriptor.lastSentFlags ~= descriptor.frameFlags
                or descriptor.lastSentGroup ~= descriptor.frameGroup
            then
                frameChanged = true
                break
            end
        end
    end

    local waitMs
    if needsEveryFrame then
        waitMs = 0
    elseif frameCount > 0 or anyInRange then
        waitMs = MARKER_WAIT_MS
    elseif nearestGap > IDLE_FAR_GAP then
        waitMs = IDLE_FAR_WAIT_MS
    else
        waitMs = IDLE_NEAR_WAIT_MS
    end

    return frameCount, frameChanged, waitMs
end

local function commitWorldFrame(frameCount)
    for index = 1, frameCount do
        local descriptor = frameDescriptors[index]
        descriptor.lastSentPixelX = descriptor.framePixelX
        descriptor.lastSentPixelY = descriptor.framePixelY
        descriptor.lastSentCentimetres = descriptor.frameCentimetres
        descriptor.lastSentFlags = descriptor.frameFlags
        descriptor.lastSentGroup = descriptor.frameGroup
        lastFrameDescriptors[index] = descriptor
    end

    clearArray(lastFrameDescriptors, frameCount + 1)
    lastWorldCount = frameCount
    worldFrameDirty = false
end

local function updateWorldFrame()
    processing = true
    local frameCount, frameChanged, waitMs = buildWorldFrame()

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
    processing = false

    -- Registry changes raised by this frame (the list preference) rebuild the
    -- descriptors only now, outside the frame that was using them.
    if refreshPending then refresh(false) end

    return waitMs
end

RegisterNUICallback('interactionReady', function(_, cb)
    nuiReady = true
    readPreferences()
    refresh(true)
    sendLayout(true)
    cb({ ok = true })
end)

AddEventHandler('cortex-lib:interaction:changed', function()
    refresh(false)
end)

AddEventHandler('cortex-lib:settingChanged', function(key, value)
    if key == 'promptMarkers' then
        local nextMarkers = value ~= false
        if nextMarkers ~= markersEnabled then worldFrameDirty = true end
        markersEnabled = nextMarkers
    elseif key == 'invertScroll' then
        invertScroll = value == true
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    started = false
    nuiReady = false
    lastScreenItems = nil
    hideWorldFrame()
    worldInteractions = {}
end)

CreateThread(function()
    while started do
        sendLayout(false)
        -- Settings preview/rollback may not raise settingChanged; a 1 s
        -- re-read keeps the renderer honest without a per-frame lookup.
        readPreferences()
        Wait(1000)
    end
end)

startWorldWorker = function()
    if worldWorkerRunning or not started or not nuiReady or #worldInteractions == 0 then return end
    worldWorkerRunning = true
    CreateThread(function()
        while started and nuiReady and #worldInteractions > 0 do
            Wait(updateWorldFrame())
        end
        worldWorkerRunning = false
    end)
end
