--[[
    cortex-lib interaction prompt registry

    This module owns presentation state only. The calling resource remains
    responsible for registering and handling the actual keybind/action.
]]

local MAX_INTERACTIONS_PER_RESOURCE = 8
local MAX_INTERACTIONS_TOTAL = 16
local MAX_ID_BYTES = 64
local MAX_LABEL_BYTES = 96
local MAX_KEY_BYTES = 16
local MAX_BONE_BYTES = 64
local MAX_PANEL_ID_BYTES = 64
local MAX_PANEL_LABEL_BYTES = 96
local MAX_ENTITY_HANDLE = 2147483647
local MIN_ENTITY_MODEL = -2147483648
local MAX_ENTITY_MODEL = 4294967295
local MAX_WORLD_COORD = 100000.0
local MAX_ANCHOR_OFFSET = 10.0
local MIN_HOLD_DURATION_MS = 100
local MAX_HOLD_DURATION_MS = 600000

if not lib.isInternalResource() then
    return {
        show = lib.showInteraction,
        hide = lib.hideInteraction,
        set = lib.setInteractions,
        clear = lib.clearInteractions,
        get = function()
            return exports['cortex-lib']:getInteractions()
        end,
        getState = lib.getInteractionState,
        isActive = lib.isInteractionActive,
        isVisible = lib.isInteractionVisible,
        startHold = lib.startInteractionHold,
        cancelHold = lib.cancelInteractionHold,
    }
end

local interactions = {}
local ownerEntries = {}
local ownerCounts = {}
local sortedEntries = {}
local totalCount = 0
local sequence = 0
local revision = 0

local function trim(value)
    return value:match('^%s*(.-)%s*$')
end

local function validateText(value, field, maxBytes)
    if type(value) ~= 'string' then
        return nil, ('%s must be a string'):format(field)
    end

    value = trim(value)

    if value == '' then
        return nil, ('%s cannot be empty'):format(field)
    end

    if #value > maxBytes then
        return nil, ('%s is too long (maximum %d bytes)'):format(field, maxBytes)
    end

    if value:find('[%z\1-\31\127]') then
        return nil, ('%s contains control characters'):format(field)
    end

    return value
end

local function validateId(value)
    local id, err = validateText(value or 'default', 'id', MAX_ID_BYTES)
    if not id then
        return nil, err
    end

    if not id:match('^[%w_.:%-]+$') then
        return nil, 'id may only contain letters, numbers, underscore, dash, dot, and colon'
    end

    return id
end

local function normalizePanel(value)
    if value == nil then return nil end

    if type(value) ~= 'table' then
        return nil, 'panel must be a table'
    end

    local id, idError = validateText(value.id, 'panel.id', MAX_PANEL_ID_BYTES)
    if not id then return nil, idError end
    if not id:match('^[%w_.:%-]+$') then
        return nil, 'panel.id contains unsupported characters'
    end

    local label, labelError = validateText(value.label, 'panel.label', MAX_PANEL_LABEL_BYTES)
    if not label then return nil, labelError end

    local variant = value.variant or 'target'
    if variant ~= 'target' then
        return nil, 'panel.variant must be target'
    end

    return {
        id = id,
        label = label,
        variant = variant,
    }
end

local function panelsEqual(left, right)
    if left == nil or right == nil then return left == right end
    return left.id == right.id
        and left.label == right.label
        and left.variant == right.variant
end

local function copyPanel(panel)
    if not panel then return nil end
    return {
        id = panel.id,
        label = panel.label,
        variant = panel.variant,
    }
end

local function validateFiniteNumber(value, field, minimum, maximum)
    value = tonumber(value)

    if not value or value ~= value or value == math.huge or value == -math.huge then
        return nil, ('%s must be a finite number'):format(field)
    end

    if value < minimum or value > maximum then
        return nil, ('%s must be between %s and %s'):format(field, minimum, maximum)
    end

    return value
end

local function normalizeOffset(value)
    if value == nil then
        return { x = 0.0, y = 0.0, z = 0.0 }
    end

    if type(value) ~= 'table' then
        return nil, 'anchor.offset must be a table'
    end

    local x, xError = validateFiniteNumber(value.x or 0.0, 'anchor.offset.x', -MAX_ANCHOR_OFFSET, MAX_ANCHOR_OFFSET)
    if not x then return nil, xError end

    local y, yError = validateFiniteNumber(value.y or 0.0, 'anchor.offset.y', -MAX_ANCHOR_OFFSET, MAX_ANCHOR_OFFSET)
    if not y then return nil, yError end

    local z, zError = validateFiniteNumber(value.z or 0.0, 'anchor.offset.z', -MAX_ANCHOR_OFFSET, MAX_ANCHOR_OFFSET)
    if not z then return nil, zError end

    return { x = x, y = y, z = z }
end

local function normalizeAnchor(value)
    if value == nil then return nil end

    if type(value) ~= 'table' then
        return nil, 'anchor must be a table'
    end

    local anchorType = value.type
    if anchorType ~= 'world' and anchorType ~= 'entity' and anchorType ~= 'entity-bone' then
        return nil, 'anchor.type must be world, entity, or entity-bone'
    end

    local maxDistance, distanceError = validateFiniteNumber(
        value.maxDistance or 3.0,
        'anchor.maxDistance',
        0.5,
        25.0
    )
    if not maxDistance then return nil, distanceError end

    local offset, offsetError = normalizeOffset(value.offset)
    if not offset then return nil, offsetError end

    if anchorType == 'world' then
        local x, xError = validateFiniteNumber(value.x, 'anchor.x', -MAX_WORLD_COORD, MAX_WORLD_COORD)
        if not x then return nil, xError end

        local y, yError = validateFiniteNumber(value.y, 'anchor.y', -MAX_WORLD_COORD, MAX_WORLD_COORD)
        if not y then return nil, yError end

        local z, zError = validateFiniteNumber(value.z, 'anchor.z', -MAX_WORLD_COORD, MAX_WORLD_COORD)
        if not z then return nil, zError end

        return {
            type = anchorType,
            x = x,
            y = y,
            z = z,
            offset = offset,
            maxDistance = maxDistance,
        }
    end

    local entity, entityError = validateFiniteNumber(value.entity, 'anchor.entity', 1, MAX_ENTITY_HANDLE)
    if not entity then return nil, entityError end
    if entity % 1 ~= 0 then return nil, 'anchor.entity must be an integer handle' end

    local model = nil
    if value.model ~= nil then
        local modelError
        model, modelError = validateFiniteNumber(
            value.model,
            'anchor.model',
            MIN_ENTITY_MODEL,
            MAX_ENTITY_MODEL
        )
        if not model then return nil, modelError end
        if model % 1 ~= 0 then return nil, 'anchor.model must be an integer hash' end
        model = math.floor(model)
    end

    if anchorType == 'entity' then
        return {
            type = anchorType,
            entity = math.floor(entity),
            model = model,
            offset = offset,
            maxDistance = maxDistance,
        }
    end

    local bone, boneError = validateText(value.bone, 'anchor.bone', MAX_BONE_BYTES)
    if not bone then return nil, boneError end
    if not bone:match('^[%w_:%-]+$') then
        return nil, 'anchor.bone contains unsupported characters'
    end

    return {
        type = anchorType,
        entity = math.floor(entity),
        model = model,
        bone = bone,
        offset = offset,
        maxDistance = maxDistance,
    }
end

local function anchorsEqual(left, right)
    if left == nil or right == nil then return left == right end
    if left.type ~= right.type or left.maxDistance ~= right.maxDistance then return false end
    if left.offset.x ~= right.offset.x or left.offset.y ~= right.offset.y or left.offset.z ~= right.offset.z then
        return false
    end

    if left.type == 'world' then
        return left.x == right.x and left.y == right.y and left.z == right.z
    end

    if left.entity ~= right.entity or left.model ~= right.model then return false end
    if left.type == 'entity' then return true end
    return left.bone == right.bone
end

local function copyAnchor(anchor)
    if not anchor then return nil end

    local copy = {
        type = anchor.type,
        maxDistance = anchor.maxDistance,
        offset = {
            x = anchor.offset.x,
            y = anchor.offset.y,
            z = anchor.offset.z,
        },
    }

    if anchor.type == 'world' then
        copy.x = anchor.x
        copy.y = anchor.y
        copy.z = anchor.z
    else
        copy.entity = anchor.entity
        copy.model = anchor.model
        if anchor.type == 'entity-bone' then copy.bone = anchor.bone end
    end

    return copy
end

local function resolveOwner()
    local invokingResource = GetInvokingResource()
    if type(invokingResource) == 'string' and invokingResource ~= '' then
        return invokingResource
    end

    return GetCurrentResourceName()
end

local function copySnapshotEntry(entry)
    return {
            id = entry.id,
            owner = entry.owner,
            label = entry.label,
            key = entry.key,
            priority = entry.priority,
            sequence = entry.sequence,
            anchor = copyAnchor(entry.anchor),
            panel = copyPanel(entry.panel),
            holdDuration = entry.holdDuration,
            holdActive = entry.holdActive == true,
            holdRevision = entry.holdRevision or 0,
            active = entry.active == true,
            visible = entry.visible == true,
            distance = entry.visible == true and entry.distance or nil,
        }
end

local function rebuildSortedEntries()
    local nextSortedEntries = {}

    for _, entry in pairs(interactions) do
        nextSortedEntries[#nextSortedEntries + 1] = entry
    end

    table.sort(nextSortedEntries, function(left, right)
        if left.priority ~= right.priority then
            return left.priority > right.priority
        end

        if left.sequence ~= right.sequence then
            return left.sequence < right.sequence
        end

        if left.owner ~= right.owner then
            return left.owner < right.owner
        end

        return left.id < right.id
    end)

    local claimedKeys = {}
    for index = 1, #nextSortedEntries do
        local entry = nextSortedEntries[index]
        local key = entry.key:upper()
        entry.active = claimedKeys[key] == nil
        if not entry.active then
            entry.visible = false
            entry.distance = nil
        end
        claimedKeys[key] = true
    end

    sortedEntries = nextSortedEntries
end

local function buildSnapshot()
    local snapshot = {}

    for index = 1, #sortedEntries do
        snapshot[index] = copySnapshotEntry(sortedEntries[index])
    end

    return snapshot
end

local function publish(registryChanged)
    if registryChanged then
        rebuildSortedEntries()
    end

    revision = revision + 1
    TriggerEvent('cortex-lib:interaction:changed', revision)
end

local function addEntry(owner, entry)
    local entries = ownerEntries[owner]
    if not entries then
        entries = {}
        ownerEntries[owner] = entries
    end

    entry.owner = owner
    entry.registryKey = owner .. ':' .. entry.id
    entries[entry.id] = entry
    interactions[entry.registryKey] = entry
    ownerCounts[owner] = (ownerCounts[owner] or 0) + 1
    totalCount = totalCount + 1
end

local function replaceEntry(current, entry)
    entry.owner = current.owner
    entry.sequence = current.sequence
    entry.registryKey = current.registryKey
    ownerEntries[current.owner][current.id] = entry
    interactions[current.registryKey] = entry
end

local function removeEntry(entry)
    local entries = ownerEntries[entry.owner]
    if not entries or entries[entry.id] ~= entry then return false end

    entries[entry.id] = nil
    interactions[entry.registryKey] = nil
    totalCount = totalCount - 1

    local nextOwnerCount = (ownerCounts[entry.owner] or 1) - 1
    if nextOwnerCount > 0 then
        ownerCounts[entry.owner] = nextOwnerCount
    else
        ownerCounts[entry.owner] = nil
        ownerEntries[entry.owner] = nil
    end

    return true
end

local function normalize(data)
    if type(data) ~= 'table' then
        return nil, 'interaction must be a table'
    end

    local id, idError = validateId(data.id)
    if not id then
        return nil, idError
    end

    local label, labelError = validateText(data.label, 'label', MAX_LABEL_BYTES)
    if not label then
        return nil, labelError
    end

    local key, keyError = validateText(data.key, 'key', MAX_KEY_BYTES)
    if not key then
        return nil, keyError
    end

    local priority = tonumber(data.priority) or 0
    if priority ~= priority or priority == math.huge or priority == -math.huge then
        return nil, 'priority must be a finite number'
    end

    priority = math.max(-1000, math.min(1000, math.floor(priority)))

    local holdDuration = nil
    if data.holdDuration ~= nil then
        local holdError
        holdDuration, holdError = validateFiniteNumber(
            data.holdDuration,
            'holdDuration',
            MIN_HOLD_DURATION_MS,
            MAX_HOLD_DURATION_MS
        )
        if not holdDuration then
            return nil, holdError
        end

        holdDuration = math.floor(holdDuration)
    end

    local anchor, anchorError = normalizeAnchor(data.anchor)
    if anchorError then
        return nil, anchorError
    end

    if holdDuration and not anchor then
        return nil, 'holdDuration is only supported for world interactions'
    end

    local panel, panelError = normalizePanel(data.panel)
    if panelError then
        return nil, panelError
    end
    if panel and anchor then
        return nil, 'panel is only supported for screen interactions'
    end

    return {
        id = id,
        label = label,
        key = key,
        priority = priority,
        anchor = anchor,
        panel = panel,
        holdDuration = holdDuration,
        holdActive = false,
        holdRevision = 0,
        visible = false,
        distance = nil,
    }
end

local function definitionsEqual(left, right)
    return left.label == right.label
        and left.key == right.key
        and left.priority == right.priority
        and left.holdDuration == right.holdDuration
        and panelsEqual(left.panel, right.panel)
        and anchorsEqual(left.anchor, right.anchor)
end

local function finiteNumber(value)
    local valueType = type(value)
    if valueType ~= 'number' and valueType ~= 'string' then return nil end

    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function defaultNumber(value, fallback)
    if value == nil or value == false then return fallback end
    return finiteNumber(value)
end

local function rawOffsetMatches(current, value)
    if value == nil then
        return current.x == 0.0 and current.y == 0.0 and current.z == 0.0
    end

    if type(value) ~= 'table' then return false end

    return defaultNumber(value.x, 0.0) == current.x
        and defaultNumber(value.y, 0.0) == current.y
        and defaultNumber(value.z, 0.0) == current.z
end

local function rawAnchorMatches(current, value)
    if current == nil or value == nil then return current == nil and value == nil end
    if type(value) ~= 'table' or value.type ~= current.type then return false end
    if defaultNumber(value.maxDistance, 3.0) ~= current.maxDistance then return false end
    if not rawOffsetMatches(current.offset, value.offset) then return false end

    if current.type == 'world' then
        return finiteNumber(value.x) == current.x
            and finiteNumber(value.y) == current.y
            and finiteNumber(value.z) == current.z
    end

    local entity = finiteNumber(value.entity)
    if entity == nil or entity % 1 ~= 0 or entity ~= current.entity then
        return false
    end

    local model = nil
    if value.model ~= nil then
        model = finiteNumber(value.model)
        if not model
            or model % 1 ~= 0
            or model < MIN_ENTITY_MODEL
            or model > MAX_ENTITY_MODEL
        then
            return false
        end
        model = math.floor(model)
    end
    if model ~= current.model then return false end
    if current.type == 'entity' then return true end
    return value.bone == current.bone
end

local function rawPanelMatches(current, value)
    if current == nil or value == nil then return current == nil and value == nil end
    if type(value) ~= 'table' then return false end

    return value.id == current.id
        and value.label == current.label
        and (value.variant or 'target') == current.variant
end


-- Calling show/set from a frame loop is discouraged, but common in gameplay
-- resources. This allocation-free check makes identical canonical updates a
-- no-op while the full normalizer remains the authority for changed input.
local function rawDefinitionMatches(current, data)
    if type(data) ~= 'table' then return false end

    local id = data.id or 'default'
    if id ~= current.id or data.label ~= current.label or data.key ~= current.key then return false end

    local priority = data.priority == nil and 0 or finiteNumber(data.priority)
    if not priority then return false end
    priority = math.max(-1000, math.min(1000, math.floor(priority)))
    if priority ~= current.priority then return false end

    local holdDuration = nil
    if data.holdDuration ~= nil then
        holdDuration = finiteNumber(data.holdDuration)
        if not holdDuration
            or holdDuration < MIN_HOLD_DURATION_MS
            or holdDuration > MAX_HOLD_DURATION_MS
        then
            return false
        end
        holdDuration = math.floor(holdDuration)
    end

    return holdDuration == current.holdDuration
        and rawAnchorMatches(current.anchor, data.anchor)
        and rawPanelMatches(current.panel, data.panel)
end

local function getOwnedEntry(owner, id)
    local entries = ownerEntries[owner]
    local directId = id or 'default'

    if entries and type(directId) == 'string' then
        local directEntry = entries[directId]
        if directEntry then return directEntry end
    end

    local normalizedId, err = validateId(id)
    if not normalizedId then return nil, err end

    return entries and entries[normalizedId] or nil, nil, normalizedId
end

local function showInteraction(data)
    local owner = resolveOwner()
    local entries = ownerEntries[owner]
    local directId = type(data) == 'table' and (data.id or 'default') or nil
    local current = entries and type(directId) == 'string' and entries[directId] or nil

    if current and rawDefinitionMatches(current, data) then
        return true, current.id
    end

    local normalized, err = normalize(data)
    if not normalized then
        return false, err
    end

    current = entries and entries[normalized.id] or nil

    if not current and (ownerCounts[owner] or 0) >= MAX_INTERACTIONS_PER_RESOURCE then
        return false, ('resource interaction limit reached (%d)'):format(MAX_INTERACTIONS_PER_RESOURCE)
    end

    if not current and totalCount >= MAX_INTERACTIONS_TOTAL then
        return false, ('global interaction limit reached (%d)'):format(MAX_INTERACTIONS_TOTAL)
    end

    if current and definitionsEqual(current, normalized) then
        return true, normalized.id
    end

    if current then
        replaceEntry(current, normalized)
    else
        sequence = sequence + 1
        normalized.sequence = sequence
        addEntry(owner, normalized)
    end

    publish(true)

    return true, normalized.id
end

local function hideInteraction(id)
    local owner = resolveOwner()
    local normalizedId, err = validateId(id)
    if not normalizedId then
        return false, err
    end

    local entries = ownerEntries[owner]
    local entry = entries and entries[normalizedId] or nil
    if not entry then
        return false, 'interaction not found'
    end

    removeEntry(entry)
    publish(true)

    return true
end

local function clearOwner(owner, shouldPublish)
    local entries = ownerEntries[owner]
    if not entries then return false end

    local removedCount = ownerCounts[owner] or 0
    for _, entry in pairs(entries) do
        interactions[entry.registryKey] = nil
    end

    ownerEntries[owner] = nil
    ownerCounts[owner] = nil
    totalCount = totalCount - removedCount

    if shouldPublish ~= false then
        publish(true)
    end

    return true
end

local function clearInteractions()
    return clearOwner(resolveOwner())
end

local function getArrayLength(items)
    local length = #items
    local count = 0

    for key in pairs(items) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 or key > length then
            return nil
        end

        count = count + 1
    end

    if count ~= length then
        return nil
    end

    return length
end

local function setInteractions(items)
    if type(items) ~= 'table' then
        return false, 'interactions must be an array'
    end

    local itemCount = getArrayLength(items)
    if not itemCount then
        return false, 'interactions must be a dense array'
    end

    if itemCount > MAX_INTERACTIONS_PER_RESOURCE then
        return false, ('resource interaction limit exceeded (%d)'):format(MAX_INTERACTIONS_PER_RESOURCE)
    end

    local owner = resolveOwner()
    local currentOwnerCount = ownerCounts[owner] or 0
    local totalAfterReplace = totalCount - currentOwnerCount + itemCount
    if totalAfterReplace > MAX_INTERACTIONS_TOTAL then
        return false, ('global interaction limit exceeded (%d)'):format(MAX_INTERACTIONS_TOTAL)
    end

    local entries = ownerEntries[owner]
    if currentOwnerCount == itemCount then
        local fastUnchanged = true
        local fastSeenIds = {}

        for index = 1, itemCount do
            local data = items[index]
            local id = type(data) == 'table' and (data.id or 'default') or nil
            local current = entries and type(id) == 'string' and entries[id] or nil

            if not current or fastSeenIds[id] or not rawDefinitionMatches(current, data) then
                fastUnchanged = false
                break
            end

            fastSeenIds[id] = true
        end

        if fastUnchanged then return true end
    end

    local normalizedItems = {}
    local seenIds = {}

    for index = 1, itemCount do
        local normalized, err = normalize(items[index])
        if not normalized then
            return false, ('interaction %d: %s'):format(index, err)
        end

        if seenIds[normalized.id] then
            return false, ('duplicate interaction id: %s'):format(normalized.id)
        end

        seenIds[normalized.id] = true
        normalizedItems[#normalizedItems + 1] = normalized
    end

    local unchanged = currentOwnerCount == #normalizedItems
    if unchanged then
        for index = 1, #normalizedItems do
            local entry = normalizedItems[index]
            local current = entries and entries[entry.id] or nil

            if not current or not definitionsEqual(current, entry) then
                unchanged = false
                break
            end
        end
    end

    if unchanged then
        return true
    end

    local previousStates = {}

    if entries then
        for _, entry in pairs(entries) do
            previousStates[entry.id] = {
                sequence = entry.sequence,
                definition = entry,
                holdActive = entry.holdActive == true,
                holdRevision = entry.holdRevision or 0,
                visible = entry.visible == true,
                distance = entry.distance,
            }
        end
    end

    clearOwner(owner, false)

    for index = 1, #normalizedItems do
        local entry = normalizedItems[index]
        local previous = previousStates[entry.id]
        entry.sequence = previous and previous.sequence or nil

        if previous and definitionsEqual(previous.definition, entry) then
            entry.holdActive = previous.holdActive
            entry.holdRevision = previous.holdRevision
            entry.visible = previous.visible
            entry.distance = previous.distance
        end

        if not entry.sequence then
            sequence = sequence + 1
            entry.sequence = sequence
        end

        addEntry(owner, entry)
    end

    publish(true)
    return true
end

local function getInteractions()
    return buildSnapshot(), revision
end

local function getInteractionState(id)
    local owner = resolveOwner()
    local entry, err = getOwnedEntry(owner, id)
    if err then return nil, err end
    if not entry then return nil, 'interaction not found' end

    return copySnapshotEntry(entry)
end

local function isInteractionActive(id)
    local owner = resolveOwner()
    local entry, err = getOwnedEntry(owner, id)
    if err then return false, err end
    if entry then return entry.active == true end

    return false, 'interaction not found'
end

local function isInteractionVisible(id)
    local owner = resolveOwner()
    local entry, err = getOwnedEntry(owner, id)
    if err then return false, err end
    if entry then return entry.active == true and entry.visible == true end

    return false, 'interaction not found'
end

-- The renderer is the sole source of frame-derived presentation state. This is
-- deliberately internal: callers can query their own state through exports but
-- cannot mark an off-screen or out-of-range prompt visible themselves.
local function setInteractionPresentationState(owner, id, visible, distance)
    if type(owner) ~= 'string' or owner == '' or type(id) ~= 'string' then return false end

    local entries = ownerEntries[owner]
    local entry = entries and entries[id] or nil
    if not entry then return false end

    visible = visible == true and entry.active == true
    if visible and entry.anchor then
        distance = validateFiniteNumber(distance, 'distance', 0.0, MAX_WORLD_COORD * 2.0)
        if not distance then visible = false end
    else
        distance = nil
    end

    entry.visible = visible
    entry.distance = visible and distance or nil
    return true
end

local function setInteractionHold(id, active)
    if type(active) ~= 'boolean' then
        return false, 'hold state must be a boolean'
    end

    local owner = resolveOwner()
    local entry, err = getOwnedEntry(owner, id)
    if err then return false, err end
    if not entry then
        return false, 'interaction not found'
    end

    if not entry.anchor then
        return false, 'screen interactions are press-only'
    end

    if not entry.holdDuration then
        return false, 'interaction does not define holdDuration'
    end

    if active then
        if not entry.active then
            return false, 'interaction is not active'
        end
    end

    if entry.holdActive == active then
        return true
    end

    entry.holdActive = active
    entry.holdRevision = (entry.holdRevision or 0) + 1
    publish(false)
    return true
end

local function startInteractionHold(id)
    return setInteractionHold(id, true)
end

local function cancelInteractionHold(id)
    return setInteractionHold(id, false)
end

AddEventHandler('onClientResourceStop', function(resourceName)
    if type(resourceName) == 'string' and resourceName ~= GetCurrentResourceName() then
        clearOwner(resourceName)
    end
end)

exports('showInteraction', showInteraction)
exports('hideInteraction', hideInteraction)
exports('setInteractions', setInteractions)
exports('clearInteractions', clearInteractions)
exports('getInteractions', getInteractions)
exports('getInteractionState', getInteractionState)
exports('isInteractionActive', isInteractionActive)
exports('isInteractionVisible', isInteractionVisible)
exports('startInteractionHold', startInteractionHold)
exports('cancelInteractionHold', cancelInteractionHold)

lib.showInteraction = showInteraction
lib.hideInteraction = hideInteraction
lib.setInteractions = setInteractions
lib.clearInteractions = clearInteractions
lib.getInteractions = getInteractions
lib.getInteractionState = getInteractionState
lib.isInteractionActive = isInteractionActive
lib.isInteractionVisible = isInteractionVisible
lib.startInteractionHold = startInteractionHold
lib.cancelInteractionHold = cancelInteractionHold
lib._setInteractionPresentationState = setInteractionPresentationState

return {
    show = showInteraction,
    hide = hideInteraction,
    set = setInteractions,
    clear = clearInteractions,
    get = getInteractions,
    getState = getInteractionState,
    isActive = isInteractionActive,
    isVisible = isInteractionVisible,
    startHold = startInteractionHold,
    cancelHold = cancelInteractionHold,
}
