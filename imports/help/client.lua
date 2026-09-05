local CURRENT_RESOURCE = GetCurrentResourceName()
local MAX_HELP_ITEMS = 16
local helpState = { open = false, owner = nil }

local function getInvokingOwner()
    local owner = GetInvokingResource and GetInvokingResource() or nil
    return owner or CURRENT_RESOURCE
end

local function boundedString(value, maxLength)
    return type(value) == 'string' and value ~= '' and #value <= maxLength and not value:find('\0', 1, true)
end

local function normalizeItems(items)
    if type(items) ~= 'table' or #items == 0 or #items > MAX_HELP_ITEMS then return nil end

    local count = 0
    local normalized = {}
    for key in next, items do
        if type(key) ~= 'number' or math.tointeger(key) ~= key or key < 1 or key > #items then return nil end
        count = count + 1
    end
    if count ~= #items then return nil end

    for index = 1, #items do
        local item = items[index]
        if type(item) ~= 'table'
            or not boundedString(item.key or item.label, 64)
            or not boundedString(item.value or item.description, 256)
        then
            return nil
        end
        normalized[index] = {
            label = item.label or item.key,
            value = item.value or item.description,
        }
    end
    return normalized
end

local function showHelp(items)
    local normalized = normalizeItems(items)
    if not normalized then return false end
    local owner = getInvokingOwner()
    if helpState.open and helpState.owner ~= owner and owner ~= CURRENT_RESOURCE then return false, 'not_owner' end

    helpState.open = true
    helpState.owner = owner
    SendNUIMessage({ action = 'helpShow', data = { items = normalized } })
    return true
end

local function hideHelp()
    if not helpState.open then return false end
    local owner = getInvokingOwner()
    if owner ~= CURRENT_RESOURCE and helpState.owner ~= owner then return false end

    helpState.open = false
    helpState.owner = nil
    SendNUIMessage({ action = 'helpHide' })
    return true
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == CURRENT_RESOURCE or helpState.owner == resourceName then
        helpState.open = false
        helpState.owner = nil
        SendNUIMessage({ action = 'helpHide' })
    end
end)

exports('showHelp', showHelp)
exports('hideHelp', hideHelp)

lib.showHelp = showHelp
lib.hideHelp = hideHelp

return { showHelp = showHelp, hideHelp = hideHelp }
