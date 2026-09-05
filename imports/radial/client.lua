local CURRENT_RESOURCE = GetCurrentResourceName()
local MAX_ROOT_ITEMS = 32
local MAX_MENUS = 32
local MAX_MENU_ITEMS = 32
local ROOT_SENTINEL = {}

local isOpen = false
local disabledOwners = {}
local menus = {}
local menuCount = 0
local menuItems = {}
local menuHistory = {}
local currentRadial = nil
local currentOwner = nil
local currentSession = nil
local transitionRevision = 0
local fallbackGeneration = 0
local controlThreadActive = false
local clearOpenRadial

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

local function safeColor(value)
    if not boundedString(value, 64, false) then return false end
    local hex = value:match('^#([%x]+)$')
    if hex and (#hex == 3 or #hex == 4 or #hex == 6 or #hex == 8) then return true end
    return value:match('^var%(%-%-[%w%-]+%)$') ~= nil
end

local function isDenseArray(value, maxItems)
    if type(value) ~= 'table' then return false end
    local length = #value
    if length > maxItems then return false end

    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or math.tointeger(key) ~= key or key < 1 or key > length then return false end
        count = count + 1
    end
    return count == length
end

local function validateItems(items, maxItems)
    if not isDenseArray(items, maxItems) then return false, 'invalid_items' end

    local seen = {}
    for index = 1, #items do
        local item = items[index]
        if type(item) ~= 'table'
            or not boundedString(item.id, 64, false)
            or seen[item.id]
            or not boundedString(item.label, 128, false)
            or (item.icon ~= nil and not boundedString(item.icon, 128, true))
            or (item.iconColor ~= nil and not safeColor(item.iconColor))
            or (item.menu ~= nil and not boundedString(item.menu, 64, false))
            or (item.keepOpen ~= nil and type(item.keepOpen) ~= 'boolean')
            or (item.onSelect ~= nil and type(item.onSelect) ~= 'function')
        then
            return false, 'invalid_item'
        end
        seen[item.id] = true
    end

    return true
end

local function acquireModal(owner)
    if type(lib._acquireModal) == 'function' then return lib._acquireModal('radial', owner) end
    fallbackGeneration = fallbackGeneration + 1
    return fallbackGeneration
end

local function focusModal(session)
    if type(lib._focusModal) == 'function' then return lib._focusModal('radial', session, false) end
    SetNuiFocus(true, true)
    return true
end

local function matchesModal(session, suppliedSession)
    if type(lib._matchesModal) == 'function' then
        return lib._matchesModal('radial', session, suppliedSession)
    end
    return isOpen and (suppliedSession == nil or suppliedSession == session)
end

local function releaseModal(session)
    if type(lib._releaseModal) == 'function' then return lib._releaseModal('radial', session) end
    SetNuiFocus(false, false)
    return true
end

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    return ok and type(text) == 'string' and text or '<unprintable error>'
end

local function protectedSelect(callback, menuId, index)
    if type(callback) ~= 'function' then return true end
    local ok, err = pcall(callback, menuId, index)
    if not ok then print(('^1[cortex-lib]^7 radial callback failed: %s'):format(safeErrorText(err))) end
    return ok
end

local function sanitizeItem(item)
    return {
        id = item.id,
        label = item.label,
        icon = item.icon,
        iconColor = item.iconColor,
        menu = item.menu,
        keepOpen = item.keepOpen,
    }
end

local function copyStoredItem(item, owner)
    return {
        id = item.id,
        label = item.label,
        icon = item.icon,
        iconColor = item.iconColor,
        menu = item.menu,
        keepOpen = item.keepOpen,
        onSelect = item.onSelect,
        _owner = owner,
    }
end

local function currentItems()
    if currentRadial then
        local menu = menus[currentRadial]
        return menu and menu.items or {}
    end
    return menuItems
end

local function buildNuiItems()
    local items = currentItems()
    local sanitized = {}
    for index = 1, #items do sanitized[index] = sanitizeItem(items[index]) end
    return sanitized
end

local function currentAppearance()
    if not currentRadial then return nil end
    local menu = menus[currentRadial]
    return menu and menu.appearance or nil
end

local function getItemByIndex(index)
    return currentItems()[index]
end

local function refreshRadial()
    if not isOpen then return end
    SendNUIMessage({
        action = 'radialRefresh',
        data = {
            items = buildNuiItems(),
            menuId = currentRadial,
            appearance = currentAppearance(),
            canGoBack = #menuHistory > 0,
            session = currentSession,
        }
    })
end

local function startControlThread()
    if controlThreadActive then return end
    controlThreadActive = true
    CreateThread(function()
        while isOpen do
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(2, 199, true)
            DisableControlAction(2, 200, true)
            Wait(0)
        end
        controlThreadActive = false
    end)
end

local function addRadialItem(items)
    if type(items) == 'table' and items.id ~= nil then items = { items } end

    local valid, err = validateItems(items, MAX_ROOT_ITEMS)
    if not valid then
        if err == 'invalid_item' then error('lib.addRadialItem: invalid or duplicate item') end
        return false, err
    end

    local owner = getInvokingOwner()
    local indexes = {}
    for index = 1, #menuItems do indexes[menuItems[index].id] = index end

    local additions = 0
    for index = 1, #items do
        local existingIndex = indexes[items[index].id]
        local existing = existingIndex and menuItems[existingIndex] or nil
        if existing and existing._owner ~= owner then return false, 'owned_by_other_resource' end
        if not existing then additions = additions + 1 end
    end
    if #menuItems + additions > MAX_ROOT_ITEMS then return false, 'capacity_exceeded' end

    for index = 1, #items do
        local item = items[index]
        local stored = copyStoredItem(item, owner)
        local existingIndex = indexes[item.id]
        if existingIndex then
            menuItems[existingIndex] = stored
        else
            menuItems[#menuItems + 1] = stored
            indexes[item.id] = #menuItems
        end
    end

    refreshRadial()
end

local function removeRadialItem(id)
    local owner = getInvokingOwner()
    for index = #menuItems, 1, -1 do
        if menuItems[index].id == id then
            if menuItems[index]._owner ~= owner then return false end
            table.remove(menuItems, index)
            refreshRadial()
            return true
        end
    end
    return false
end

local function clearRadialItems()
    local owner = getInvokingOwner()
    for index = #menuItems, 1, -1 do
        if menuItems[index]._owner == owner then table.remove(menuItems, index) end
    end
    refreshRadial()
end

local function registerRadial(data)
    if type(data) ~= 'table' or not boundedString(data.id, 64, false) then
        error('lib.registerRadial: menu requires a valid id')
    end
    if data.appearance ~= nil and data.appearance ~= 'compact-control' then
        return false, 'invalid_appearance'
    end

    local valid, err = validateItems(data.items or {}, MAX_MENU_ITEMS)
    if not valid then return false, err end

    local owner = getInvokingOwner()
    local existing = menus[data.id]
    if existing and existing.owner ~= owner then return false, 'owned_by_other_resource' end
    if not existing and menuCount >= MAX_MENUS then return false, 'capacity_exceeded' end

    local items = {}
    for index = 1, #(data.items or {}) do items[index] = copyStoredItem(data.items[index], owner) end
    if not existing then menuCount = menuCount + 1 end
    menus[data.id] = {
        id = data.id,
        owner = owner,
        items = items,
        appearance = data.appearance,
    }
    if isOpen and currentRadial == data.id then
        local session = clearOpenRadial(true, true)
        if session then releaseModal(session) end
    end
end

clearOpenRadial = function(sendMessage, instant)
    if not isOpen then return nil end

    local session = currentSession
    isOpen = false
    currentRadial = nil
    currentOwner = nil
    currentSession = nil
    menuHistory = {}
    transitionRevision = transitionRevision + 1
    if sendMessage then
        SendNUIMessage({ action = 'radialHide', data = { instant = instant, session = session } })
    end
    return session
end

local function showRadial(menuId)
    local owner = getInvokingOwner()
    if next(disabledOwners) ~= nil or isOpen or IsPauseMenuActive() then return false end

    local items
    if menuId then
        local menu = menus[menuId]
        if not menu or menu.owner ~= owner then return false end
        currentRadial = menuId
        items = menu.items
    else
        currentRadial = nil
        items = menuItems
    end
    if #items == 0 then return false end

    local session = acquireModal(owner)
    if not session then currentRadial = nil; return false end

    isOpen = true
    currentOwner = owner
    currentSession = session
    menuHistory = {}
    transitionRevision = transitionRevision + 1
    SendNUIMessage({
        action = 'radialShow',
        data = {
            items = buildNuiItems(),
            menuId = currentRadial,
            appearance = currentAppearance(),
            canGoBack = false,
            session = session,
        }
    })

    SetCursorLocation(0.5, 0.5)
    if not focusModal(session) then
        clearOpenRadial(true, true)
        releaseModal(session)
        return false
    end
    startControlThread()
    return true
end

local function closeActiveRadial(skipTransition)
    if not isOpen then return end
    local session = clearOpenRadial(true, skipTransition)
    releaseModal(session)
end

local function hideRadial(skipTransition)
    if not isOpen then return end
    if currentOwner ~= getInvokingOwner() then return false end
    closeActiveRadial(skipTransition)
end

local function transitionTo(menuId, historyEntry)
    local menu = menus[menuId]
    if not menu then return false end

    menuHistory[#menuHistory + 1] = historyEntry
    currentRadial = menuId
    transitionRevision = transitionRevision + 1
    local revision = transitionRevision
    local session = currentSession
    SendNUIMessage({ action = 'radialTransitionOut', data = { session = session } })
    Wait(100)

    if not isOpen or currentSession ~= session or transitionRevision ~= revision then return false end
    SendNUIMessage({
        action = 'radialTransitionIn',
        data = {
            items = buildNuiItems(),
            menuId = currentRadial,
            appearance = currentAppearance(),
            canGoBack = #menuHistory > 0,
            session = session,
        }
    })
    return true
end

local function navigateToMenu(menuId, itemOwner)
    local menu = menus[menuId]
    if not menu or menu.owner ~= itemOwner then return false end
    return transitionTo(menuId, currentRadial or ROOT_SENTINEL)
end

local function radialBack()
    if #menuHistory == 0 then closeActiveRadial(); return end

    local previous = table.remove(menuHistory)
    transitionRevision = transitionRevision + 1
    local revision = transitionRevision
    local session = currentSession
    if previous == ROOT_SENTINEL then
        currentRadial = nil
    else
        currentRadial = previous
    end
    SendNUIMessage({ action = 'radialTransitionOut', data = { session = session } })
    Wait(100)

    if not isOpen or currentSession ~= session or transitionRevision ~= revision then return end
    SendNUIMessage({
        action = 'radialTransitionIn',
        data = {
            items = buildNuiItems(),
            menuId = currentRadial,
            appearance = currentAppearance(),
            canGoBack = #menuHistory > 0,
            session = session,
        }
    })
end

local function disableRadial(state)
    if type(state) ~= 'boolean' then return false, 'invalid_state' end
    local owner = getInvokingOwner()
    if state == true then disabledOwners[owner] = true else disabledOwners[owner] = nil end
    if state == true and isOpen then closeActiveRadial(true) end
end

local function isRadialOpen() return isOpen end
local function isRadialDisabled() return next(disabledOwners) ~= nil end
local function getCurrentRadialId() return currentRadial end

local function validCallback(data)
    return type(data) == 'table'
        and isOpen
        and (data.menuId == nil or boundedString(data.menuId, 64, false))
        and data.menuId == currentRadial
        and matchesModal(currentSession, data.session)
end

RegisterNUICallback('radialClick', function(data, cb)
    if not validCallback(data) then cb({ ok = false, error = 'stale_session' }); return end

    local rawIndex = data.index
    local zeroIndex = type(rawIndex) == 'number' and math.tointeger(rawIndex) or nil
    if not zeroIndex or zeroIndex < 0 or zeroIndex >= #currentItems() then
        cb({ ok = false, error = 'invalid_index' }); return
    end

    local index = zeroIndex + 1
    local item = getItemByIndex(index)
    if not item or data.itemId ~= item.id or data.menuId ~= currentRadial then
        cb({ ok = false, error = 'stale_item' }); return
    end

    if item.menu then
        local ok = navigateToMenu(item.menu, item._owner)
        cb({ ok = ok, error = ok and nil or 'invalid_menu' })
        return
    end

    local selectedMenu = currentRadial
    local callback = item.onSelect
    if not item.keepOpen then closeActiveRadial() end
    local ok = protectedSelect(callback, selectedMenu, index)
    cb({ ok = ok, error = ok and nil or 'handler_error' })
end)

RegisterNUICallback('radialBack', function(data, cb)
    if not validCallback(data) then cb({ ok = false, error = 'stale_session' }); return end
    radialBack()
    cb({ ok = true })
end)

RegisterNUICallback('radialClose', function(data, cb)
    if not validCallback(data) then cb({ ok = false, error = 'stale_session' }); return end
    closeActiveRadial()
    cb({ ok = true })
end)

local function closeRadialForModal(generation)
    if currentSession == generation then clearOpenRadial(true, true) end
end
local pendingModalSurfaces = rawget(lib, '_pendingModalSurfaces') or {}
pendingModalSurfaces.radial = closeRadialForModal
rawset(lib, '_pendingModalSurfaces', pendingModalSurfaces)
if type(lib._registerModalSurface) == 'function' then lib._registerModalSurface('radial', closeRadialForModal) end

AddEventHandler('onResourceStop', function(resourceName)
    disabledOwners[resourceName] = nil
    if currentOwner == resourceName or resourceName == CURRENT_RESOURCE
        or (currentRadial and menus[currentRadial] and menus[currentRadial].owner == resourceName)
    then
        local session = clearOpenRadial(true, true)
        if session then releaseModal(session) end
    end

    for index = #menuItems, 1, -1 do
        if menuItems[index]._owner == resourceName then table.remove(menuItems, index) end
    end

    local removed = 0
    for id, menu in pairs(menus) do
        if menu.owner == resourceName then menus[id] = nil; removed = removed + 1 end
    end
    menuCount = math.max(0, menuCount - removed)
    refreshRadial()
end)

exports('addRadialItem', addRadialItem)
exports('removeRadialItem', removeRadialItem)
exports('clearRadialItems', clearRadialItems)
exports('registerRadial', registerRadial)
exports('showRadial', showRadial)
exports('hideRadial', hideRadial)
exports('disableRadial', disableRadial)
exports('isRadialOpen', isRadialOpen)
exports('isRadialDisabled', isRadialDisabled)
exports('getCurrentRadialId', getCurrentRadialId)

lib.addRadialItem = addRadialItem
lib.removeRadialItem = removeRadialItem
lib.clearRadialItems = clearRadialItems
lib.registerRadial = registerRadial
lib.showRadial = showRadial
lib.hideRadial = hideRadial
lib.disableRadial = disableRadial
lib.isRadialOpen = isRadialOpen
lib.isRadialDisabled = isRadialDisabled
lib.getCurrentRadialId = getCurrentRadialId

return {
    addRadialItem = addRadialItem,
    removeRadialItem = removeRadialItem,
    clearRadialItems = clearRadialItems,
    registerRadial = registerRadial,
    showRadial = showRadial,
    hideRadial = hideRadial,
    disableRadial = disableRadial,
    isRadialOpen = isRadialOpen,
    isRadialDisabled = isRadialDisabled,
    getCurrentRadialId = getCurrentRadialId,
}
