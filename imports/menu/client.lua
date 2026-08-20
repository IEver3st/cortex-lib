local Menus = {}
local OpenMenuId = nil

local controlsLocked = false
local controlThreadActive = false

local LookControls = { 1, 2, 3, 4 }
local CombatControls = { 24, 25, 68, 69, 70, 91, 92 }

local function startControlLock()
    if controlThreadActive then return end

    controlThreadActive = true

    CreateThread(function()
        while controlsLocked do
            for i = 1, #LookControls do
                DisableControlAction(0, LookControls[i], true)
            end

            DisablePlayerFiring(PlayerId(), true)
            for i = 1, #CombatControls do
                DisableControlAction(0, CombatControls[i], true)
            end

            Wait(0)
        end

        controlThreadActive = false
    end)
end

local function stopControlLock()
    controlsLocked = false
end

local function shallowCopyOption(option)
    return {
        label = option.label,
        description = option.description,
        icon = option.icon,
        iconColor = option.iconColor,
        progress = option.progress,
        values = option.values,
        checked = option.checked,
        defaultIndex = option.defaultIndex,
        close = option.close,
    }
end

local function getMenuOption(menu, selected)
    if type(selected) ~= 'number' then
        return nil, nil
    end

    selected = math.tointeger(selected)
    if not selected or selected < 1 or selected > #menu.options then
        return nil, nil
    end

    return menu.options[selected], selected
end

local function getOptionArgs(option)
    return type(option and option.args) == 'table' and option.args or {}
end

local function buildNuiMenu(menu)
    local options = {}
    for i = 1, #menu.options do
        options[i] = shallowCopyOption(menu.options[i])
    end

    return {
        id = menu.id,
        title = menu.title,
        subtitle = menu.subtitle,
        position = menu.position or 'top-left',
        disableInput = menu.disableInput or false,
        canClose = menu.canClose ~= false,
        options = options,
    }
end

local function getMenu(id)
    return Menus[id]
end

local function registerMenu(menu, cb)
    if type(menu) ~= 'table' then
        error('cortex-lib.registerMenu: menu must be a table')
    end

    if type(menu.id) ~= 'string' or menu.id == '' then
        error('cortex-lib.registerMenu: menu.id must be a string')
    end

    if type(menu.title) ~= 'string' then
        error('cortex-lib.registerMenu: menu.title must be a string')
    end

    if type(menu.options) ~= 'table' then
        error('cortex-lib.registerMenu: menu.options must be a table')
    end

    Menus[menu.id] = {
        id = menu.id,
        title = menu.title,
        subtitle = menu.subtitle,
        position = menu.position,
        disableInput = menu.disableInput,
        canClose = menu.canClose,
        options = menu.options,
        onClose = menu.onClose,
        onSelected = menu.onSelected,
        onSideScroll = menu.onSideScroll,
        onCheck = menu.onCheck,
        cb = cb,
    }

    return true
end

local function showMenu(id)
    local menu = getMenu(id)
    if not menu then
        print(('^1[cortex-lib]^7 showMenu failed: unknown id %s'):format(tostring(id)))
        return false
    end

    OpenMenuId = id

    local payload = buildNuiMenu(menu)

    SendNUIMessage({
        action = 'menuOpen',
        data = payload
    })

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)

    controlsLocked = true
    startControlLock()

    return true
end

local function hideMenu(runOnClose)
    if not OpenMenuId then
        return false
    end

    local menu = getMenu(OpenMenuId)

    SendNUIMessage({ action = 'menuClose' })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    stopControlLock()

    local prevId = OpenMenuId
    OpenMenuId = nil

    if runOnClose and menu and menu.onClose then
        menu.onClose()
    end

    return prevId
end

local function getOpenMenu()
    return OpenMenuId
end

local function setMenuOptions(id, options, index)
    local menu = getMenu(id)
    if not menu then
        return false
    end

    if index then
        if type(index) ~= 'number' or index < 1 then
            return false
        end

        menu.options[index] = options

        if OpenMenuId == id then
            SendNUIMessage({
                action = 'menuSetOption',
                data = { id = id, index = index, option = shallowCopyOption(options) }
            })
        end

        return true
    end

    menu.options = options

    if OpenMenuId == id then
        local packed = {}
        for i = 1, #options do
            packed[i] = shallowCopyOption(options[i])
        end

        SendNUIMessage({
            action = 'menuSetOptions',
            data = { id = id, options = packed }
        })
    end

    return true
end

RegisterNUICallback('es_menu_close', function(data, cb)
    local id = data and data.id
    local keyPressed = data and data.keyPressed

    if OpenMenuId and id and OpenMenuId ~= id then
        cb({ ok = true })
        return
    end

    local menu = OpenMenuId and getMenu(OpenMenuId)

    OpenMenuId = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    stopControlLock()

    if menu and menu.onClose then
        menu.onClose(keyPressed)
    end

    cb({ ok = true })
end)

RegisterNUICallback('es_menu_selected', function(data, cb)
    local id = data and data.id
    if not id or OpenMenuId ~= id then
        cb({ ok = true })
        return
    end

    local menu = getMenu(id)
    if menu and menu.onSelected then
        local option, selected = getMenuOption(menu, data.selected)
        if option then
            menu.onSelected(selected, data.secondary == true, getOptionArgs(option))
        end
    end

    cb({ ok = true })
end)

RegisterNUICallback('es_menu_sideScroll', function(data, cb)
    local id = data and data.id
    if not id or OpenMenuId ~= id then
        cb({ ok = true })
        return
    end

    local menu = getMenu(id)
    if menu and menu.onSideScroll then
        local option, selected = getMenuOption(menu, data.selected)
        local scrollIndex = type(data.scrollIndex) == 'number' and math.tointeger(data.scrollIndex) or nil

        if option and option.values and scrollIndex and scrollIndex >= 1 and scrollIndex <= #option.values then
            option.defaultIndex = scrollIndex
            menu.onSideScroll(selected, scrollIndex, getOptionArgs(option))
        end
    end

    cb({ ok = true })
end)

RegisterNUICallback('es_menu_check', function(data, cb)
    local id = data and data.id
    if not id or OpenMenuId ~= id then
        cb({ ok = true })
        return
    end

    local menu = getMenu(id)
    if menu and menu.onCheck then
        local option, selected = getMenuOption(menu, data.selected)
        if option and type(data.checked) == 'boolean' then
            option.checked = data.checked
            menu.onCheck(selected, data.checked, getOptionArgs(option))
        end
    end

    cb({ ok = true })
end)

RegisterNUICallback('es_menu_submit', function(data, cb)
    local id = data and data.id
    if not id or OpenMenuId ~= id then
        cb({ ok = true })
        return
    end

    local menu = getMenu(id)
    if not menu then
        cb({ ok = true })
        return
    end

    local selected = type(data.selected) == 'number' and math.tointeger(data.selected) or nil
    local option = selected and menu.options[selected] or nil
    if not option then
        cb({ ok = true })
        return
    end

    local scrollIndex = type(data.scrollIndex) == 'number' and math.tointeger(data.scrollIndex) or option.defaultIndex or 1
    if option.values and (scrollIndex < 1 or scrollIndex > #option.values) then
        cb({ ok = true })
        return
    end

    local args = getOptionArgs(option)

    if menu.cb then
        menu.cb(selected, scrollIndex, args)
    end

    local shouldClose = option and option.close ~= false

    if shouldClose and OpenMenuId == id then
        OpenMenuId = nil
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        stopControlLock()
        SendNUIMessage({ action = 'menuClose' })
    else
        shouldClose = false
    end

    cb({ ok = true, close = shouldClose })
end)

exports('registerMenu', registerMenu)
exports('showMenu', showMenu)
exports('hideMenu', hideMenu)
exports('getOpenMenu', getOpenMenu)
exports('setMenuOptions', setMenuOptions)

lib.registerMenu = registerMenu
lib.showMenu = showMenu
lib.hideMenu = hideMenu
lib.getOpenMenu = getOpenMenu
lib.setMenuOptions = setMenuOptions

return {
    registerMenu = registerMenu,
    showMenu = showMenu,
    hideMenu = hideMenu,
    getOpenMenu = getOpenMenu,
    setMenuOptions = setMenuOptions
}
