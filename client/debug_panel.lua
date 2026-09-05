lib = lib or {}

local CURRENT_RESOURCE = GetCurrentResourceName()
local MAX_PAYLOAD_NODES = 128
local MAX_PAYLOAD_DEPTH = 4
local VALID_POSITIONS = {
    ['top-left'] = true,
    ['top-right'] = true,
    ['bottom-left'] = true,
    ['bottom-right'] = true,
}

local panelState = { open = false, owner = nil, id = nil, lastPayload = nil }

local function getInvokingOwner()
    local owner = GetInvokingResource and GetInvokingResource() or nil
    return owner or CURRENT_RESOURCE
end

local function boundedString(value, maxLength, allowEmpty)
    return type(value) == 'string'
        and (allowEmpty or value ~= '')
        and #value <= maxLength
        and not value:find('\0', 1, true)
end

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeColor(value)
    if not boundedString(value, 96, false) then return false end
    local hex = value:match('^#([%x]+)$')
    if hex and (#hex == 3 or #hex == 4 or #hex == 6 or #hex == 8) then return true end
    return value:match('^var%(%-%-[%w%-]+%)$') ~= nil
end

local function sanitizeValue(value, depth, budget, seen)
    local valueType = type(value)
    if valueType == 'nil' or valueType == 'boolean' then return value, true end
    if valueType == 'number' then return value, isFiniteNumber(value) end
    if valueType == 'string' then return value, boundedString(value, 1024, true) end
    if valueType ~= 'table' or depth > MAX_PAYLOAD_DEPTH or seen[value] then return nil, false end

    seen[value] = true
    local out = {}
    for key, child in next, value do
        budget.count = budget.count + 1
        if budget.count > MAX_PAYLOAD_NODES
            or (type(key) ~= 'string' and type(key) ~= 'number')
            or (type(key) == 'string' and not boundedString(key, 128, false))
            or (type(key) == 'number' and (not isFiniteNumber(key) or math.tointeger(key) == nil))
        then
            seen[value] = nil
            return nil, false
        end
        local copied, ok = sanitizeValue(child, depth + 1, budget, seen)
        if not ok then seen[value] = nil; return nil, false end
        out[key] = copied
    end
    seen[value] = nil
    return out, true
end

local function sanitizeLines(lines, budget)
    if lines == nil then return nil, true end
    if type(lines) ~= 'table' or #lines > 128 then return nil, false end

    local out = {}
    local count = 0
    for key in next, lines do
        count = count + 1
        if type(key) ~= 'number' or math.tointeger(key) ~= key or key < 1 or key > #lines then return nil, false end
    end
    if count ~= #lines then return nil, false end

    for index = 1, #lines do
        budget.count = budget.count + 1
        if budget.count > MAX_PAYLOAD_NODES then return nil, false end
        local line = rawget(lines, index)
        if type(line) == 'string' then
            if not boundedString(line, 1024, true) then return nil, false end
            out[index] = line
        elseif type(line) == 'table'
            and boundedString(rawget(line, 'label') or '', 160, true)
            and (rawget(line, 'color') == nil or safeColor(rawget(line, 'color')))
        then
            local value, ok = sanitizeValue(rawget(line, 'value'), 0, budget, {})
            if not ok then return nil, false end
            out[index] = {
                label = rawget(line, 'label') or '',
                value = value,
                color = rawget(line, 'color'),
            }
        else
            return nil, false
        end
    end
    return out, true
end

local function normalizePayload(payload, isUpdate)
    if type(payload) ~= 'table' then return nil end
    local id = rawget(payload, 'id')
    local title = rawget(payload, 'title')
    local subtitle = rawget(payload, 'subtitle')
    local position = rawget(payload, 'position')
    local accentColor = rawget(payload, 'accentColor')
    if id ~= nil and not boundedString(id, 64, false) then return nil end
    if title ~= nil and not boundedString(title, 160, true) then return nil end
    if subtitle ~= nil and not boundedString(subtitle, 256, true) then return nil end
    if position ~= nil and not VALID_POSITIONS[position] then return nil end
    if accentColor ~= nil and not safeColor(accentColor) then return nil end

    local budget = { count = 0 }
    local lines, linesOk = sanitizeLines(rawget(payload, 'lines'), budget)
    if not linesOk then return nil end
    local data, dataOk = sanitizeValue(rawget(payload, 'data'), 0, budget, {})
    if not dataOk then return nil end

    return {
        id = id,
        title = title,
        subtitle = subtitle,
        position = position or (isUpdate and nil or 'top-right'),
        accentColor = accentColor,
        lines = lines,
        data = data,
    }
end

local function hidePanel(force)
    if not panelState.open then return false end
    local owner = getInvokingOwner()
    if not force and owner ~= CURRENT_RESOURCE and panelState.owner ~= owner then return false, 'not_owner' end

    panelState.open = false
    panelState.owner = nil
    panelState.id = nil
    panelState.lastPayload = nil
    SendNUIMessage({ action = 'debugPanelHide' })
    return true
end

function lib.showDebugPanel(payload)
    local owner = getInvokingOwner()
    if panelState.open and panelState.owner ~= owner and owner ~= CURRENT_RESOURCE then return false, 'not_owner' end
    local data = normalizePayload(payload or {}, false)
    if not data then return false, 'invalid_payload' end

    panelState.open = true
    panelState.owner = owner
    panelState.id = data.id or panelState.id
    panelState.lastPayload = data
    SendNUIMessage({ action = 'debugPanelShow', data = data })
    return true
end

function lib.updateDebugPanel(payload)
    local owner = getInvokingOwner()
    if not panelState.open or (panelState.owner ~= owner and owner ~= CURRENT_RESOURCE) then return false, 'not_owner' end
    local data = normalizePayload(payload or {}, true)
    if not data then return false, 'invalid_payload' end
    panelState.lastPayload = data
    SendNUIMessage({ action = 'debugPanelUpdate', data = data })
    return true
end

function lib.hideDebugPanel()
    return hidePanel(false)
end

function lib.isDebugPanelOpen()
    return panelState.open
end

AddEventHandler('onResourceStop', function(resourceName)
    if panelState.open and (resourceName == panelState.owner or resourceName == CURRENT_RESOURCE) then hidePanel(true) end
end)

exports('showDebugPanel', lib.showDebugPanel)
exports('updateDebugPanel', lib.updateDebugPanel)
exports('hideDebugPanel', lib.hideDebugPanel)
exports('isDebugPanelOpen', lib.isDebugPanelOpen)

return lib
