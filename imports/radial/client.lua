local SetNuiFocus = SetNuiFocus
local SetCursorLocation = SetCursorLocation
local SendNUIMessage = SendNUIMessage
local DisablePlayerFiring = DisablePlayerFiring
local DisableControlAction = DisableControlAction
local Wait = Wait
local CreateThread = CreateThread
local PlayerId = PlayerId
local IsPauseMenuActive = IsPauseMenuActive
local IsNuiFocused = IsNuiFocused

local isOpen = false
local isDisabled = false
local menus = {}
local menuItems = {}
local menuHistory = {}
local currentRadial = nil

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

local function buildNuiItems()
    local items
    
    if currentRadial then
        local menu = menus[currentRadial]
        items = menu and menu.items or {}
    else
        items = menuItems
    end
    
    local sanitized = {}
    for i = 1, #items do
        sanitized[i] = sanitizeItem(items[i])
    end
    
    return sanitized
end

local function currentAppearance()
    if not currentRadial then return nil end
    local menu = menus[currentRadial]
    return menu and menu.appearance or nil
end

local function getItemByIndex(index)
    local items
    
    if currentRadial then
        local menu = menus[currentRadial]
        items = menu and menu.items or {}
    else
        items = menuItems
    end
    
    return items[index]
end

local function refreshRadial()
    if not isOpen then return end
    
    SendNUIMessage({
        action = 'radialRefresh',
        data = {
            items = buildNuiItems(),
            menuId = currentRadial,
            appearance = currentAppearance(),
            canGoBack = #menuHistory > 0
        }
    })
end

local controlThread = nil

local function startControlThread()
    if controlThread then return end
    
    controlThread = CreateThread(function()
        while isOpen do
            DisablePlayerFiring(PlayerId(), true)
            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 142, true)
            DisableControlAction(2, 199, true)
            DisableControlAction(2, 200, true)
            Wait(0)
        end
        controlThread = nil
    end)
end

local function addRadialItem(items)
    if items.id then
        items = { items }
    end
    
    for i = 1, #items do
        local item = items[i]
        if not item.id then
            error('lib.addRadialItem: item requires an id')
        end
        
        local found = false
        for j = 1, #menuItems do
            if menuItems[j].id == item.id then
                menuItems[j] = item
                found = true
                break
            end
        end
        
        if not found then
            menuItems[#menuItems + 1] = item
        end
    end
    
    refreshRadial()
end

local function removeRadialItem(id)
    for i = #menuItems, 1, -1 do
        if menuItems[i].id == id then
            table.remove(menuItems, i)
            refreshRadial()
            return true
        end
    end
    return false
end

local function clearRadialItems()
    table.wipe(menuItems)
    refreshRadial()
end

local function registerRadial(data)
    if not data.id then
        error('lib.registerRadial: menu requires an id')
    end
    
    menus[data.id] = {
        id = data.id,
        items = data.items or {},
        appearance = data.appearance == 'compact-control' and 'compact-control' or nil
    }
end

local function showRadial(menuId)
    if isDisabled then return false end
    if isOpen then return false end
    if IsPauseMenuActive() then return false end
    if IsNuiFocused() then return false end
    
    local items
    
    if menuId then
        local menu = menus[menuId]
        if not menu then
            print(('^1[cortex-lib]^7 showRadial: unknown menu id "%s"'):format(menuId))
            return false
        end
        currentRadial = menuId
        items = menu.items
    else
        currentRadial = nil
        items = menuItems
    end
    
    if #items == 0 then
        return false
    end
    
    isOpen = true
    menuHistory = {}
    
    SendNUIMessage({
        action = 'radialShow',
        data = {
            items = buildNuiItems(),
            menuId = currentRadial,
            appearance = currentAppearance(),
            canGoBack = false
        }
    })
    
    SetCursorLocation(0.5, 0.5)
    SetNuiFocus(true, true)
    startControlThread()
    
    return true
end

local function hideRadial(skipTransition)
    if not isOpen then return end
    
    isOpen = false
    currentRadial = nil
    menuHistory = {}
    
    SendNUIMessage({
        action = 'radialHide',
        data = { instant = skipTransition }
    })
    
    SetNuiFocus(false, false)
end

local function navigateToMenu(menuId)
    local menu = menus[menuId]
    if not menu then return end
    
    menuHistory[#menuHistory + 1] = currentRadial
    currentRadial = menuId
    
    SendNUIMessage({ action = 'radialTransitionOut' })
    Wait(100)
    
    if isOpen then
        SendNUIMessage({
            action = 'radialTransitionIn',
            data = {
                items = buildNuiItems(),
                menuId = currentRadial,
                appearance = currentAppearance(),
                canGoBack = #menuHistory > 0
            }
        })
    end
end

local function radialBack()
    if #menuHistory == 0 then
        hideRadial()
        return
    end
    
    currentRadial = table.remove(menuHistory)
    
    SendNUIMessage({ action = 'radialTransitionOut' })
    Wait(100)
    
    if isOpen then
        SendNUIMessage({
            action = 'radialTransitionIn',
            data = {
                items = buildNuiItems(),
                menuId = currentRadial,
                appearance = currentAppearance(),
                canGoBack = #menuHistory > 0
            }
        })
    end
end

local function disableRadial(state)
    isDisabled = state
    if state and isOpen then
        hideRadial(true)
    end
end

local function isRadialOpen()
    return isOpen
end

local function isRadialDisabled()
    return isDisabled
end

local function getCurrentRadialId()
    return currentRadial
end

RegisterNUICallback('radialClick', function(data, cb)
    cb('ok')
    
    local index = (data.index or 0) + 1
    local item = getItemByIndex(index)
    
    if not item then return end
    
    if item.menu then
        navigateToMenu(item.menu)
        return
    end
    
    if not item.keepOpen then
        hideRadial()
    end
    
    if item.onSelect then
        item.onSelect(currentRadial, index)
    end
end)

RegisterNUICallback('radialBack', function(_, cb)
    cb('ok')
    radialBack()
end)

RegisterNUICallback('radialClose', function(_, cb)
    cb('ok')
    hideRadial()
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if isOpen then
            hideRadial(true)
        end
    end
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
