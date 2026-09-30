local CURRENT_RESOURCE = GetCurrentResourceName()
local MAX_MENUS = 32
local MAX_OPTIONS = 64
local MAX_VALUES = 64
local VALID_MENU_POSITIONS = {
    ['top-left'] = true,
    ['top-right'] = true,
    ['bottom-left'] = true,
    ['bottom-right'] = true,
}

local Menus = {}
local MenuCount = 0
local OpenMenuId = nil
local OpenMenuOwner = nil
local OpenMenuSession = nil
local OpenMenuRevision = nil
local MenuRevision = 0

local controlsLocked = false
local controlThreadActive = false
local fallbackGeneration = 0

local LookControls = { 1, 2, 3, 4 }
local CombatControls = { 24, 25, 68, 69, 70, 91, 92 }

-- Game-control menus keep gameplay input (walk, drive, mouse look) and read
-- navigation from controls instead of NUI focus, like vMenu. The wheel, both
-- mouse buttons, arrows, Enter/Backspace/Esc and the pad's D-pad/A/B are
-- claimed; weapon firing, aiming and weapon-wheel scrolling are suppressed.
local GameMenuBlocked = {
    14, 15, 16, 17, 37, 24, 25, 257, 140, 141, 142, 263, 264,
    68, 69, 70, 91, 92, 99, 100, 114, 115, 116, 81, 82,
    27, 172, 173, 174, 175, 176, 177, 191, 194, 200, 201, 202, 241, 242,
}
local GameMenuInputs = {
    { 'back', 'Escape', { 200 } },
    { 'back', 'Backspace', { 177, 194, 202, 25, 68, 91 } },
    { 'select', nil, { 176, 191, 201, 24, 69, 92 } },
    { 'up', nil, { 172, 241, 15, 17 } },
    { 'down', nil, { 173, 242, 14, 16 } },
    { 'left', nil, { 174 } },
    { 'right', nil, { 175 } },
}
local GameMenuRepeat = { up = { 172 }, down = { 173 }, left = { 174 }, right = { 175 } }
local GAME_MENU_REPEAT_DELAY = 350
local GAME_MENU_REPEAT_RATE = 90
local GAME_MENU_RELEASE_GRACE = 300
local gameInputSession = nil

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
    if not boundedString(value, 64, false) then return false end
    local hex = value:match('^#([%x]+)$')
    if hex and (#hex == 3 or #hex == 4 or #hex == 6 or #hex == 8) then return true end
    return value:match('^var%(%-%-[%w%-]+%)$') ~= nil
end

local function isCallback(value)
    if type(value) == 'function' then return true end
    -- Export arguments are deserialized as callable Cfx function references.
    if type(value) ~= 'table' or type(rawget(value, '__cfx_functionReference')) ~= 'string' then return false end
    local mt = getmetatable(value)
    return type(mt) == 'table' and type(mt.__call) == 'function'
end

local function isOptionalCallback(value)
    return value == nil or isCallback(value)
end

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    return ok and type(text) == 'string' and text or '<unprintable error>'
end

local function isDenseArray(value, maxItems)
    if type(value) ~= 'table' then return false end

    local length = #value
    if length > maxItems then return false end

    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or math.tointeger(key) ~= key or key < 1 or key > length then
            return false
        end
        count = count + 1
    end

    return count == length
end

local function acquireModal(owner)
    if type(lib._acquireModal) == 'function' then return lib._acquireModal('menu', owner) end
    fallbackGeneration = fallbackGeneration + 1
    return fallbackGeneration
end

local function focusModal(session, keepInput)
    if type(lib._focusModal) == 'function' then return lib._focusModal('menu', session, keepInput) end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(keepInput == true)
    return true
end

local function matchesModal(session, suppliedSession)
    if type(lib._matchesModal) == 'function' then
        return lib._matchesModal('menu', session, suppliedSession)
    end
    return OpenMenuId ~= nil and (suppliedSession == nil or suppliedSession == session)
end

local function releaseModal(session)
    if type(lib._releaseModal) == 'function' then return lib._releaseModal('menu', session) end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    return true
end

local function protectedCall(label, callback, ...)
    if callback == nil then return true end
    if not isCallback(callback) then return false end

    local ok, err = pcall(callback, ...)
    if not ok then print(('^1[cortex-lib]^7 menu %s callback failed: %s'):format(label, safeErrorText(err))) end
    return ok
end

local function nextMenuRevision()
    MenuRevision = MenuRevision + 1
    return MenuRevision
end

local function startControlLock()
    if controlThreadActive then return end

    controlThreadActive = true
    CreateThread(function()
        while controlsLocked do
            for index = 1, #LookControls do DisableControlAction(0, LookControls[index], true) end
            DisablePlayerFiring(PlayerId(), true)
            for index = 1, #CombatControls do DisableControlAction(0, CombatControls[index], true) end
            Wait(0)
        end
        controlThreadActive = false
    end)
end

local function stopControlLock()
    controlsLocked = false
end

local function anyControl(list, check)
    for index = 1, #list do
        if check(0, list[index]) then return true end
    end
    return false
end

local function blockGameMenuControls()
    for index = 1, #GameMenuBlocked do DisableControlAction(0, GameMenuBlocked[index], true) end
    DisablePlayerFiring(PlayerId(), true)
end

local function readGameMenuInput(allowPad)
    if not allowPad and not IsUsingKeyboard(2) then return nil end
    for index = 1, #GameMenuInputs do
        local input = GameMenuInputs[index]
        if anyControl(input[3], IsDisabledControlJustPressed) then return input[1], input[2] end
    end
    return nil
end

local function startGameMenuInput(session, allowPad)
    gameInputSession = session
    CreateThread(function()
        local held, heldSince, lastRepeat = nil, 0, 0
        while gameInputSession == session do
            blockGameMenuControls()
            -- Chat, another focused UI or the pause menu own input for now.
            if not IsNuiFocused() and not IsPauseMenuActive() then
                local now = GetGameTimer()
                local input, key = readGameMenuInput(allowPad)
                if input then
                    held, heldSince, lastRepeat = GameMenuRepeat[input] and input or nil, now, now
                    SendNUIMessage({ action = 'menuNav', data = { session = session, input = input, key = key } })
                elseif held then
                    if not anyControl(GameMenuRepeat[held], IsDisabledControlPressed) then
                        held = nil
                    elseif now - heldSince >= GAME_MENU_REPEAT_DELAY and now - lastRepeat >= GAME_MENU_REPEAT_RATE then
                        lastRepeat = now
                        SendNUIMessage({ action = 'menuNav', data = { session = session, input = held } })
                    end
                end
            end
            Wait(0)
        end
        -- The click that closed the menu must not fire a weapon on release.
        local releaseUntil = GetGameTimer() + GAME_MENU_RELEASE_GRACE
        while GetGameTimer() < releaseUntil and gameInputSession == nil do
            blockGameMenuControls()
            Wait(0)
        end
    end)
end

local function validateValue(value)
    if type(value) == 'string' then return boundedString(value, 256, true) end
    if type(value) == 'number' then return isFiniteNumber(value) end
    if type(value) == 'boolean' then return true end
    if type(value) ~= 'table' then return false end

    return boundedString(value.label or '', 256, true)
        and (value.description == nil or boundedString(value.description, 512, true))
end

local function validateOption(option)
    if type(option) ~= 'table' or not boundedString(option.label, 128, false) then return false end
    if option.description ~= nil and not boundedString(option.description, 512, true) then return false end
    if option.icon ~= nil and not boundedString(option.icon, 128, true) then return false end
    if option.iconColor ~= nil and not safeColor(option.iconColor) then return false end
    if option.progress ~= nil and (not isFiniteNumber(option.progress) or option.progress < 0 or option.progress > 100) then return false end
    if option.checked ~= nil and type(option.checked) ~= 'boolean' then return false end
    if option.defaultIndex ~= nil and (not isFiniteNumber(option.defaultIndex) or not math.tointeger(option.defaultIndex)) then return false end
    if option.close ~= nil and type(option.close) ~= 'boolean' then return false end
    if option.disabled ~= nil and type(option.disabled) ~= 'boolean' then return false end

    if option.values ~= nil then
        if not isDenseArray(option.values, MAX_VALUES) then return false end
        for index = 1, #option.values do
            if not validateValue(option.values[index]) then return false end
        end
        if option.defaultIndex and (option.defaultIndex < 1 or option.defaultIndex > #option.values) then return false end
    elseif option.defaultIndex ~= nil then
        return false
    end
    return true
end

local function validateOptions(options)
    if not isDenseArray(options, MAX_OPTIONS) then return false end
    for index = 1, #options do
        if not validateOption(options[index]) then return false end
    end
    return true
end

local function sanitizeValue(value)
    if type(value) ~= 'table' then return value end
    return {
        label = value.label or '',
        description = value.description,
    }
end

local function sanitizeOption(option)
    local values = nil
    if option.values then
        values = {}
        for index = 1, #option.values do values[index] = sanitizeValue(option.values[index]) end
    end

    return {
        label = option.label,
        description = option.description,
        icon = option.icon,
        iconColor = option.iconColor,
        progress = option.progress,
        values = values,
        checked = option.checked,
        defaultIndex = option.defaultIndex,
        close = option.close,
        disabled = option.disabled == true or nil,
    }
end

local function copyStoredOption(option)
    local stored = sanitizeOption(option)
    stored.args = option.args
    return stored
end

local function getMenuOption(menu, selected)
    if type(selected) ~= 'number' then return nil, nil end
    selected = math.tointeger(selected)
    if not selected or selected < 1 or selected > #menu.options then return nil, nil end
    return menu.options[selected], selected
end

local function getOptionArgs(option)
    return type(option and option.args) == 'table' and option.args or {}
end

local function buildNuiMenu(menu, session, revision)
    local options = {}
    for index = 1, #menu.options do options[index] = sanitizeOption(menu.options[index]) end
    return {
        id = menu.id,
        title = menu.title,
        subtitle = menu.subtitle,
        position = menu.position or 'top-left',
        disableInput = menu.disableInput == true,
        gameControls = menu.gameControls == true,
        startIndex = menu.startIndex,
        canClose = menu.canClose ~= false,
        options = options,
        session = session,
        revision = revision,
    }
end

local function getMenu(id)
    return Menus[id]
end

local function clearOpenMenu(sendMessage, reason, runOnClose)
    if not OpenMenuId then return false end

    local id = OpenMenuId
    local menu = Menus[id]
    local session = OpenMenuSession
    OpenMenuId = nil
    OpenMenuOwner = nil
    OpenMenuSession = nil
    OpenMenuRevision = nil
    stopControlLock()
    gameInputSession = nil

    if sendMessage then SendNUIMessage({ action = 'menuClose', data = { id = id, session = session } }) end
    if runOnClose and menu then protectedCall('close', menu.onClose, reason) end
    return id, session
end

local function registerMenu(menu, cb)
    if type(menu) ~= 'table' then error('cortex-lib.registerMenu: menu must be a table') end
    if not boundedString(menu.id, 64, false) then error('cortex-lib.registerMenu: invalid menu.id') end
    if not boundedString(menu.title, 128, false) then error('cortex-lib.registerMenu: invalid menu.title') end
    if menu.subtitle ~= nil and not boundedString(menu.subtitle, 256, true) then return false, 'invalid_subtitle' end
    if menu.position ~= nil and not VALID_MENU_POSITIONS[menu.position] then return false, 'invalid_position' end
    if menu.disableInput ~= nil and type(menu.disableInput) ~= 'boolean' then return false, 'invalid_disable_input' end
    if menu.canClose ~= nil and type(menu.canClose) ~= 'boolean' then return false, 'invalid_can_close' end
    if menu.gameControls ~= nil and type(menu.gameControls) ~= 'boolean' then return false, 'invalid_game_controls' end
    if menu.gamepad ~= nil and type(menu.gamepad) ~= 'boolean' then return false, 'invalid_gamepad' end
    local startIndex = nil
    if menu.startIndex ~= nil then
        startIndex = type(menu.startIndex) == 'number' and math.tointeger(menu.startIndex) or nil
        if not startIndex or startIndex < 1 or type(menu.options) ~= 'table' or startIndex > #menu.options then
            return false, 'invalid_start_index'
        end
    end
    if not isOptionalCallback(cb)
        or not isOptionalCallback(menu.onClose)
        or not isOptionalCallback(menu.onSelected)
        or not isOptionalCallback(menu.onSideScroll)
        or not isOptionalCallback(menu.onCheck)
    then
        return false, 'invalid_callbacks'
    end
    if not validateOptions(menu.options) then return false, 'invalid_options' end

    local owner = getInvokingOwner()
    local existing = Menus[menu.id]
    if existing and existing.owner ~= owner then return false, 'owned_by_other_resource' end
    if not existing and MenuCount >= MAX_MENUS then return false, 'capacity_exceeded' end

    if existing and OpenMenuId == menu.id then
        local _, session = clearOpenMenu(true, 'replaced', true)
        if session then releaseModal(session) end
    end

    local storedOptions = {}
    for index = 1, #menu.options do storedOptions[index] = copyStoredOption(menu.options[index]) end

    if not existing then MenuCount = MenuCount + 1 end
    Menus[menu.id] = {
        id = menu.id,
        owner = owner,
        title = menu.title,
        subtitle = menu.subtitle,
        position = menu.position,
        disableInput = menu.disableInput == true,
        gameControls = menu.gameControls == true,
        gamepad = menu.gamepad ~= false,
        startIndex = startIndex,
        canClose = menu.canClose,
        options = storedOptions,
        onClose = menu.onClose,
        onSelected = menu.onSelected,
        onSideScroll = menu.onSideScroll,
        onCheck = menu.onCheck,
        cb = cb,
        revision = existing and existing.revision or 0,
    }
    return true
end

local function showMenu(id)
    local menu = getMenu(id)
    local owner = getInvokingOwner()
    if not menu or menu.owner ~= owner then return false end

    local session = acquireModal(owner)
    if not session then return false end

    OpenMenuId = id
    OpenMenuOwner = owner
    OpenMenuSession = session
    menu.revision = nextMenuRevision()
    OpenMenuRevision = menu.revision
    SendNUIMessage({ action = 'menuOpen', data = buildNuiMenu(menu, session, OpenMenuRevision) })

    if menu.gameControls then
        -- No NUI focus: gameplay keeps the keyboard, mouse look and movement.
        controlsLocked = false
        stopControlLock()
        startGameMenuInput(session, menu.gamepad)
        return true
    end

    local lockInput = menu.disableInput == true
    if not focusModal(session, lockInput) then
        clearOpenMenu(true, 'focus_failed', false)
        releaseModal(session)
        return false
    end

    controlsLocked = lockInput
    if lockInput then startControlLock() else stopControlLock() end
    return true
end

local function hideMenu(runOnClose)
    if not OpenMenuId or OpenMenuOwner ~= getInvokingOwner() then return false end
    local id, session = clearOpenMenu(true, 'programmatic', runOnClose)
    releaseModal(session)
    return id
end

local function getOpenMenu()
    return OpenMenuId
end

local function setMenuOptions(id, options, index)
    local menu = getMenu(id)
    if not menu or menu.owner ~= getInvokingOwner() then return false end

    if index ~= nil then
        index = type(index) == 'number' and math.tointeger(index) or nil
        if not index or index < 1 or index > #menu.options or not validateOption(options) then return false end
        menu.options[index] = copyStoredOption(options)
        menu.revision = nextMenuRevision()
        if OpenMenuId == id then
            OpenMenuRevision = menu.revision
            SendNUIMessage({ action = 'menuSetOption', data = {
                id = id, index = index, option = sanitizeOption(menu.options[index]),
                session = OpenMenuSession, revision = OpenMenuRevision,
            } })
        end
        return true
    end

    if not validateOptions(options) then return false end
    local storedOptions = {}
    for optionIndex = 1, #options do storedOptions[optionIndex] = copyStoredOption(options[optionIndex]) end
    menu.options = storedOptions
    menu.revision = nextMenuRevision()
    if OpenMenuId == id then
        OpenMenuRevision = menu.revision
        local packed = {}
        for optionIndex = 1, #storedOptions do packed[optionIndex] = sanitizeOption(storedOptions[optionIndex]) end
        SendNUIMessage({ action = 'menuSetOptions', data = {
            id = id, options = packed, session = OpenMenuSession, revision = OpenMenuRevision,
        } })
    end
    return true
end

local function validCallback(data)
    return type(data) == 'table'
        and OpenMenuId ~= nil
        and data.id == OpenMenuId
        and type(data.revision) == 'number'
        and math.tointeger(data.revision) == OpenMenuRevision
        and matchesModal(OpenMenuSession, data.session)
end

RegisterNUICallback('cortex_menu_close', function(data, cb)
    if not validCallback(data) then cb({ ok = false, error = 'stale_session' }); return end

    local menu = getMenu(OpenMenuId)
    if not menu or menu.canClose == false then cb({ ok = false, error = 'close_not_allowed' }); return end
    local keyPressed = type(data.keyPressed) == 'string' and boundedString(data.keyPressed, 64, true)
        and data.keyPressed or nil
    local _, session = clearOpenMenu(false, data.keyPressed, false)
    releaseModal(session)
    local ok = protectedCall('close', menu and menu.onClose, keyPressed)
    cb({ ok = true, handlerError = not ok })
end)

RegisterNUICallback('cortex_menu_selected', function(data, cb)
    if not validCallback(data) then cb({ ok = false, error = 'stale_session' }); return end
    local menu = getMenu(OpenMenuId)
    local option, selected = getMenuOption(menu, data.selected)
    if not option then cb({ ok = false, error = 'invalid_option' }); return end
    local ok = protectedCall('selected', menu.onSelected, selected, data.secondary == true, getOptionArgs(option))
    cb({ ok = ok, error = ok and nil or 'handler_error' })
end)

RegisterNUICallback('cortex_menu_sideScroll', function(data, cb)
    if not validCallback(data) then cb({ ok = false, error = 'stale_session' }); return end
    local menu = getMenu(OpenMenuId)
    local option, selected = getMenuOption(menu, data.selected)
    local scrollIndex = type(data.scrollIndex) == 'number' and math.tointeger(data.scrollIndex) or nil
    if not option or not option.values or not scrollIndex or scrollIndex < 1 or scrollIndex > #option.values then
        cb({ ok = false, error = 'invalid_option' }); return
    end
    if option.disabled then cb({ ok = false, error = 'option_disabled' }); return end
    local previousIndex = option.defaultIndex
    option.defaultIndex = scrollIndex
    local ok = protectedCall('sideScroll', menu.onSideScroll, selected, scrollIndex, getOptionArgs(option))
    if not ok then option.defaultIndex = previousIndex end
    cb({ ok = ok, error = ok and nil or 'handler_error' })
end)

RegisterNUICallback('cortex_menu_check', function(data, cb)
    if not validCallback(data) then cb({ ok = false, error = 'stale_session' }); return end
    local menu = getMenu(OpenMenuId)
    local option, selected = getMenuOption(menu, data.selected)
    if not option or type(option.checked) ~= 'boolean' or type(data.checked) ~= 'boolean' then
        cb({ ok = false, error = 'invalid_option' }); return
    end
    if option.disabled then cb({ ok = false, error = 'option_disabled' }); return end
    local previousChecked = option.checked
    option.checked = data.checked
    local ok = protectedCall('check', menu.onCheck, selected, data.checked, getOptionArgs(option))
    if not ok then option.checked = previousChecked end
    cb({ ok = ok, error = ok and nil or 'handler_error' })
end)

RegisterNUICallback('cortex_menu_submit', function(data, cb)
    if not validCallback(data) then cb({ ok = false, error = 'stale_session' }); return end
    local menu = getMenu(OpenMenuId)
    local option, selected = getMenuOption(menu, data.selected)
    if not option then cb({ ok = false, error = 'invalid_option' }); return end
    -- Disabled rows are presentation in NUI; Lua is the authority that refuses them.
    if option.disabled then cb({ ok = false, error = 'option_disabled' }); return end

    local scrollIndex = 1
    if option.values then
        scrollIndex = type(data.scrollIndex) == 'number' and math.tointeger(data.scrollIndex) or option.defaultIndex or 1
        if scrollIndex < 1 or scrollIndex > #option.values then
            cb({ ok = false, error = 'invalid_option' }); return
        end
    end

    local shouldClose = option.close ~= false
    if shouldClose then
        local _, session = clearOpenMenu(true, 'submit', false)
        releaseModal(session)
    end
    local ok = protectedCall('submit', menu.cb, selected, scrollIndex, getOptionArgs(option))
    cb({ ok = ok, close = shouldClose, error = ok and nil or 'handler_error' })
end)

local function closeMenuForModal(generation, reason)
    if OpenMenuSession == generation then clearOpenMenu(true, reason, true) end
end
local pendingModalSurfaces = rawget(lib, '_pendingModalSurfaces') or {}
pendingModalSurfaces.menu = closeMenuForModal
rawset(lib, '_pendingModalSurfaces', pendingModalSurfaces)
if type(lib._registerModalSurface) == 'function' then lib._registerModalSurface('menu', closeMenuForModal) end

AddEventHandler('onResourceStop', function(resourceName)
    if OpenMenuOwner == resourceName or resourceName == CURRENT_RESOURCE then
        local _, session = clearOpenMenu(true, 'resource_stop', true)
        if session then releaseModal(session) end
    end

    local removed = 0
    for id, menu in pairs(Menus) do
        if menu.owner == resourceName then Menus[id] = nil; removed = removed + 1 end
    end
    MenuCount = math.max(0, MenuCount - removed)
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
    setMenuOptions = setMenuOptions,
}
