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
local MAX_ENTITY_HANDLE = 2147483647
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
        isActive = lib.isInteractionActive,
        startHold = lib.startInteractionHold,
        cancelHold = lib.cancelInteractionHold,
    }
end

local interactions = {}
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
    if anchorType ~= 'world' and anchorType ~= 'entity-bone' then
        return nil, 'anchor.type must be world or entity-bone'
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

    local bone, boneError = validateText(value.bone, 'anchor.bone', MAX_BONE_BYTES)
    if not bone then return nil, boneError end
    if not bone:match('^[%w_:%-]+$') then
        return nil, 'anchor.bone contains unsupported characters'
    end

    return {
        type = anchorType,
        entity = math.floor(entity),
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

    return left.entity == right.entity and left.bone == right.bone
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
        copy.bone = anchor.bone
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

local function countOwner(owner)
    local count = 0

    for _, entry in pairs(interactions) do
        if entry.owner == owner then
            count = count + 1
        end
    end

    return count
end

local function buildSnapshot()
    local snapshot = {}

    for _, entry in pairs(interactions) do
        snapshot[#snapshot + 1] = {
            id = entry.id,
            owner = entry.owner,
            label = entry.label,
            key = entry.key,
            priority = entry.priority,
            sequence = entry.sequence,
            anchor = copyAnchor(entry.anchor),
            holdDuration = entry.holdDuration,
            holdActive = entry.holdActive == true,
            holdRevision = entry.holdRevision or 0,
        }
    end

    table.sort(snapshot, function(left, right)
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
    for index = 1, #snapshot do
        local entry = snapshot[index]
        local key = entry.key:upper()
        entry.active = claimedKeys[key] == nil
        claimedKeys[key] = true
    end

    return snapshot
end

local function publish()
    revision = revision + 1
    TriggerEvent('cortex-lib:interaction:changed', revision)
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

    return {
        id = id,
        label = label,
        key = key,
        priority = priority,
        anchor = anchor,
        holdDuration = holdDuration,
        holdActive = false,
        holdRevision = 0,
    }
end

local function showInteraction(data)
    local owner = resolveOwner()
    local normalized, err = normalize(data)
    if not normalized then
        return false, err
    end

    local registryKey = owner .. ':' .. normalized.id
    local current = interactions[registryKey]

    if not current and countOwner(owner) >= MAX_INTERACTIONS_PER_RESOURCE then
        return false, ('resource interaction limit reached (%d)'):format(MAX_INTERACTIONS_PER_RESOURCE)
    end

    if not current and #buildSnapshot() >= MAX_INTERACTIONS_TOTAL then
        return false, ('global interaction limit reached (%d)'):format(MAX_INTERACTIONS_TOTAL)
    end

    if current
        and current.label == normalized.label
        and current.key == normalized.key
        and current.priority == normalized.priority
        and current.holdDuration == normalized.holdDuration
        and anchorsEqual(current.anchor, normalized.anchor)
    then
        return true, normalized.id
    end

    if current then
        normalized.sequence = current.sequence
        if current.holdDuration == normalized.holdDuration then
            normalized.holdActive = current.holdActive == true
            normalized.holdRevision = current.holdRevision or 0
        end
    else
        sequence = sequence + 1
        normalized.sequence = sequence
    end

    normalized.owner = owner
    interactions[registryKey] = normalized
    publish()

    return true, normalized.id
end

local function hideInteraction(id)
    local owner = resolveOwner()
    local normalizedId, err = validateId(id)
    if not normalizedId then
        return false, err
    end

    local registryKey = owner .. ':' .. normalizedId
    if not interactions[registryKey] then
        return false, 'interaction not found'
    end

    interactions[registryKey] = nil
    publish()

    return true
end

local function clearOwner(owner, shouldPublish)
    local changed = false

    for registryKey, entry in pairs(interactions) do
        if entry.owner == owner then
            interactions[registryKey] = nil
            changed = true
        end
    end

    if changed and shouldPublish ~= false then
        publish()
    end

    return changed
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

    local owner = resolveOwner()
    local totalAfterReplace = #buildSnapshot() - countOwner(owner) + #normalizedItems
    if totalAfterReplace > MAX_INTERACTIONS_TOTAL then
        return false, ('global interaction limit exceeded (%d)'):format(MAX_INTERACTIONS_TOTAL)
    end

    local unchanged = countOwner(owner) == #normalizedItems
    if unchanged then
        for index = 1, #normalizedItems do
            local entry = normalizedItems[index]
            local current = interactions[owner .. ':' .. entry.id]

            if not current
                or current.label ~= entry.label
                or current.key ~= entry.key
                or current.priority ~= entry.priority
                or current.holdDuration ~= entry.holdDuration
                or not anchorsEqual(current.anchor, entry.anchor)
            then
                unchanged = false
                break
            end
        end
    end

    if unchanged then
        return true
    end

    local previousStates = {}

    for _, entry in pairs(interactions) do
        if entry.owner == owner then
            previousStates[entry.id] = {
                sequence = entry.sequence,
                holdDuration = entry.holdDuration,
                holdActive = entry.holdActive == true,
                holdRevision = entry.holdRevision or 0,
            }
        end
    end

    clearOwner(owner, false)

    for index = 1, #normalizedItems do
        local entry = normalizedItems[index]
        entry.owner = owner
        local previous = previousStates[entry.id]
        entry.sequence = previous and previous.sequence or nil

        if previous and previous.holdDuration == entry.holdDuration then
            entry.holdActive = previous.holdActive
            entry.holdRevision = previous.holdRevision
        end

        if not entry.sequence then
            sequence = sequence + 1
            entry.sequence = sequence
        end

        interactions[owner .. ':' .. entry.id] = entry
    end

    publish()
    return true
end

local function getInteractions()
    return buildSnapshot(), revision
end

local function isInteractionActive(id)
    local owner = resolveOwner()
    local normalizedId, err = validateId(id)
    if not normalizedId then return false, err end

    local registryKey = owner .. ':' .. normalizedId
    local snapshot = buildSnapshot()

    for index = 1, #snapshot do
        local entry = snapshot[index]
        if entry.owner .. ':' .. entry.id == registryKey then
            return entry.active == true
        end
    end

    return false, 'interaction not found'
end

local function setInteractionHold(id, active)
    if type(active) ~= 'boolean' then
        return false, 'hold state must be a boolean'
    end

    local owner = resolveOwner()
    local normalizedId, err = validateId(id)
    if not normalizedId then return false, err end

    local entry = interactions[owner .. ':' .. normalizedId]
    if not entry then
        return false, 'interaction not found'
    end

    if not entry.holdDuration then
        return false, 'interaction does not define holdDuration'
    end

    if entry.holdActive == active then
        return true
    end

    entry.holdActive = active
    entry.holdRevision = (entry.holdRevision or 0) + 1
    publish()
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
exports('isInteractionActive', isInteractionActive)
exports('startInteractionHold', startInteractionHold)
exports('cancelInteractionHold', cancelInteractionHold)

lib.showInteraction = showInteraction
lib.hideInteraction = hideInteraction
lib.setInteractions = setInteractions
lib.clearInteractions = clearInteractions
lib.getInteractions = getInteractions
lib.isInteractionActive = isInteractionActive
lib.startInteractionHold = startInteractionHold
lib.cancelInteractionHold = cancelInteractionHold

return {
    show = showInteraction,
    hide = hideInteraction,
    set = setInteractions,
    clear = clearInteractions,
    get = getInteractions,
    isActive = isInteractionActive,
    startHold = startInteractionHold,
    cancelHold = cancelInteractionHold,
}
