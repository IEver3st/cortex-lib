-- Custom pause entry and extension registry. Settings remains the single modal,
-- preview and focus owner; native frontend handoffs explicitly release it.
local RESOURCE = GetCurrentResourceName()
local pages, locations = {}, {}
local visible = false
local nativeHandoff = nil
local generation = 0
local nextOpenAt = 0
local bypassUntil = 0
local nativeError = nil
local alive = true
local blurOwned = false
local blurModifierIndex = nil
local pauseBlurName = RESOURCE .. '_pause_blur'
local pauseBlurCreated = false
-- Settings and the quick menu ask for a heavy background blur. The NUI adds an
-- ink scrim on top; CEF never filters the backdrop (backdrop-filter renders black).
local PAUSE_BLUR_SCALE = 8.0
local SCREENBLUR_FADE_MS = 160.0
-- Graphics packs often neuter hud_def_blur or the screen blur. The menu
-- selection postfx is a separate engine effect, so the three layers together
-- keep the background blurred whichever one a pack disables.
local PAUSE_POSTFX = 'MenuMGSelectionIn'
local postfxOwned = false
local hudHidden = false
local function getPauseBlur()
    if pauseBlurCreated then return pauseBlurName end
    -- Clone the installed preset so graphics packs keep their own definitions.
    -- Increase actual blur values, not the timecycle blend (which tops out at 1).
    if CloneTimecycleModifier('hud_def_blur', pauseBlurName) == -1 then return 'hud_def_blur' end
    pauseBlurCreated = true
    local changed = false
    for index = 0, GetTimecycleModifierVarCount('hud_def_blur') - 1 do
        local name = GetTimecycleModifierVarNameByIndex('hud_def_blur', index)
        if name:find('blur', 1, true) and not name:find('vignet', 1, true)
            and not name:find('motion', 1, true) then
            local ok, value, blend = GetTimecycleModifierVar('hud_def_blur', name)
            if ok and value > 0 then
                SetTimecycleModifierVar(pauseBlurName, name, value * PAUSE_BLUR_SCALE, blend)
                changed = true
            end
        end
    end
    if not changed then
        print('[cortex-lib] Pause blur: installed hud_def_blur has no adjustable blur values; using stock blur.')
    end
    return pauseBlurName
end
local function releaseBlur()
    if blurModifierIndex ~= nil then
        -- A different resource may have replaced the secondary effect meanwhile.
        if GetExtraTimecycleModifierIndex() == blurModifierIndex then ClearExtraTimecycleModifier() end
        blurModifierIndex = nil
    end
    if blurOwned then TriggerScreenblurFadeOut(SCREENBLUR_FADE_MS); blurOwned = false end
    if postfxOwned then
        if AnimpostfxIsRunning(PAUSE_POSTFX) then AnimpostfxStop(PAUSE_POSTFX) end
        postfxOwned = false
    end
end

-- While settings or the quick menu own the screen, the native HUD and radar
-- stay hidden (they otherwise draw through the page's open left column).
local function hideHudWhileVisible()
    if hudHidden then return end
    hudHidden = true
    CreateThread(function()
        while alive and visible do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
        hudHidden = false
    end)
end
-- Replicated by the server; there is no player KVP or settings toggle.
local function quickMenuEnabled()
    return GetConvarInt('cortex_pause_replace_native', 0) == 1
end
local title = GetConvar('cortex_pause_title', 'CORTEX'):sub(1, 48)
local MAX_PAGES, MAX_LOCATIONS = 24, 256
local pauseControls = { { 0, 199 }, { 0, 200 }, { 2, 199 }, { 2, 200 } }
local controllerInputs = { { 188, 'up' }, { 187, 'down' }, { 189, 'left' }, { 190, 'right' },
    { 201, 'accept' }, { 202, 'back' }, { 199, 'back' } }

local function clearPausePresses()
    for _, binding in ipairs(pauseControls) do binding.armed = false end
end

local function pauseInputBusy()
    -- Native/Scaleform menus and GTA text boxes need not take NUI focus.
    if lib._hasModalSurface() or IsPauseMenuActive() or IsNuiFocused()
        or UpdateOnscreenKeyboard() == 0 or IsWarningMessageActive()
        or IsScreenFadedOut() or IsPlayerSwitchInProgress() then return true end
    -- Respect either pause control being reserved, including vMenu's Escape
    -- lock while P remains enabled. Never read through another menu's lock.
    for _, binding in ipairs(pauseControls) do
        if not IsControlEnabled(binding[1], binding[2]) then return true end
    end
    return false
end

local function owner()
    return GetInvokingResource() or RESOURCE
end

local function text(value, limit, empty)
    return type(value) == 'string' and #value <= limit
        and (empty or #value > 0) and not value:find('%z')
end

local function id(value)
    return text(value, 64) and value:match('^[%w_-]+$') ~= nil
        and value ~= '__proto__' and value ~= 'constructor' and value ~= 'prototype'
end

local function finite(value, low, high)
    return type(value) == 'number' and value == value and value >= low and value <= high
end

local function array(value, maximum)
    if type(value) ~= 'table' or #value > maximum then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key % 1 ~= 0 or key < 1 or key > #value then return false end
        count = count + 1
    end
    return count == #value
end

local function count(registry)
    local total = 0
    for _ in pairs(registry) do total = total + 1 end
    return total
end

local function callable(value)
    if type(value) == 'function' then return true end
    -- Cross-resource Lua function arguments are decoded by Cfx scheduler.lua
    -- as callable tables, not plain functions. Keep the function reference alive.
    if type(value) ~= 'table' or type(rawget(value, '__cfx_functionReference')) ~= 'string' then return false end
    local mt = getmetatable(value)
    return type(mt) == 'table' and type(rawget(mt, '__call')) == 'function'
end

local function registryKey(resource, entryId)
    return resource .. ':' .. entryId
end

local function publishState()
    -- Local-only observation. Never use this flag as server authorization.
    local active = visible or nativeHandoff ~= nil
    if LocalPlayer and LocalPlayer.state then LocalPlayer.state:set('cortexPauseOpen', active, false) end
    TriggerEvent('cortex-lib:pauseChanged', active, nativeHandoff and 'native' or (visible and 'custom' or 'closed'))
end

-- Every settings session (quick menu, /cortexsettings, openSettingsMenu) opens
-- and closes through here: Save, Discard, Escape, readiness timeout, a modal
-- takeover, a native handoff and resource stop all end with open == false.
function lib._settingsVisibilityChanged(open)
    clearPausePresses()
    visible = open == true
    if visible then
        -- Layer the menu blur without replacing weather/camera timecycles or
        -- an extra effect already owned by another resource.
        if blurModifierIndex == nil and GetExtraTimecycleModifierIndex() == -1 then
            SetExtraTimecycleModifier(getPauseBlur())
            local index = GetExtraTimecycleModifierIndex()
            if index ~= -1 then blurModifierIndex = index end
        end
        if not blurOwned then TriggerScreenblurFadeIn(SCREENBLUR_FADE_MS) end
        blurOwned = true
        -- Never restart or later stop an effect another resource is running.
        if not postfxOwned and not AnimpostfxIsRunning(PAUSE_POSTFX) then
            AnimpostfxPlay(PAUSE_POSTFX, 0, true)
            postfxOwned = true
        end
        hideHudWhileVisible()
    else releaseBlur() end
    if lib._presentationSettingsOpen then lib._presentationSettingsOpen(visible) end
    if not visible then
        if lib._stopGameSettings then lib._stopGameSettings(true) end
        nextOpenAt = GetGameTimer() + 250; nativeError = nil
    end
    publishState()
end

function lib._pauseReadinessFailed()
    -- If CEF cannot acknowledge the shell, temporarily restore native Escape.
    bypassUntil = GetGameTimer() + 30000
end

function lib._getPausePayload()
    local pageList, locationList = {}, {}
    for key, entry in pairs(pages) do
        local sections = {}
        for index, section in ipairs(entry.sections) do
            local actions = {}
            for actionIndex, action in ipairs(section.actions) do
                actions[actionIndex] = { id = action.id, label = action.label }
            end
            sections[index] = { title = section.title, body = section.body, actions = actions }
        end
        pageList[#pageList + 1] = { id = key, label = entry.label, description = entry.description,
            order = entry.order, sections = sections }
    end
    table.sort(pageList, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    for key, entry in pairs(locations) do
        locationList[#locationList + 1] = { id = key, label = entry.label, category = entry.category }
    end
    table.sort(locationList, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    local player = PlayerId()
    local coords = GetEntityCoords(PlayerPedId())
    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    return { version = 1, title = title, player = GetPlayerName(player), notice = nativeError,
        serverId = GetPlayerServerId(player), zone = zone ~= 'NULL' and zone or 'Los Santos',
        safezone = GetSafeZoneSize(), pages = pageList, locations = locationList,
        quickMenu = quickMenuEnabled() }
end

local function refresh()
    if not visible then return end
    local modal = lib._getModalState()
    SendNUIMessage({ action = 'pauseUpdate', data = { session = modal.generation, pause = lib._getPausePayload() } })
end

local function registerPage(definition)
    if type(definition) ~= 'table' or not id(definition.id)
        or not text(definition.label, 48) or not text(definition.description or '', 256, true)
        or not finite(definition.order or 100, -1000, 1000)
        or not array(definition.sections or {}, 16)
        or (definition.onAction ~= nil and not callable(definition.onAction)) then
        return false, 'invalid_page'
    end
    local resource = owner()
    local key = registryKey(resource, definition.id)
    if not pages[key] and count(pages) >= MAX_PAGES then return false, 'page_limit' end
    local sections, actionIds = {}, {}
    for index, section in ipairs(definition.sections or {}) do
        if type(section) ~= 'table' or not text(section.title or '', 96, true)
            or not text(section.body or '', 2048, true) or not array(section.actions or {}, 8) then
            return false, 'invalid_section'
        end
        local actions = {}
        for actionIndex, action in ipairs(section.actions or {}) do
            if type(action) ~= 'table' or not id(action.id) or not text(action.label, 64)
                or actionIds[action.id] or not callable(definition.onAction) then
                return false, 'invalid_action'
            end
            actionIds[action.id] = true
            actions[actionIndex] = { id = action.id, label = action.label }
        end
        sections[index] = { title = section.title or '', body = section.body or '', actions = actions }
    end
    pages[key] = { owner = resource, label = definition.label, description = definition.description or '',
        order = definition.order or 100, sections = sections, actions = actionIds, onAction = definition.onAction }
    refresh()
    return true, key
end

local function registerLocation(definition)
    if type(definition) ~= 'table' or not id(definition.id) or not text(definition.label, 96)
        or not text(definition.category or 'Locations', 64)
        or not finite(definition.x, -20000, 20000) or not finite(definition.y, -20000, 20000) then
        return false, 'invalid_location'
    end
    local resource = owner()
    local key = registryKey(resource, definition.id)
    if not locations[key] and count(locations) >= MAX_LOCATIONS then return false, 'location_limit' end
    locations[key] = { owner = resource, label = definition.label, category = definition.category or 'Locations',
        x = definition.x, y = definition.y }
    refresh()
    return true, key
end

local function remove(registry, entryId)
    if not id(entryId) then return false, 'invalid_id' end
    registry[registryKey(owner(), entryId)] = nil
    refresh()
    return true
end

local function openPause(page)
    if not alive or visible or nativeHandoff or pauseInputBusy()
        or GetGameTimer() < nextOpenAt then return false, 'ui_busy' end
    if (page == nil or page == 'home') and not quickMenuEnabled() then page = 'settings' end
    return lib._openSettingsSurface(page or 'home')
end

local function matches(data)
    if not visible or type(data) ~= 'table' then return false end
    local modal = lib._getModalState()
    return modal.surface == 'settings' and modal.focused
        and lib._matchesModal('settings', modal.generation, data.session)
end

local function nativeMenu(kind, returnTo)
    -- Dedicated menu versions in Cfx's shipped pausemenu.xml avoid depending
    -- on a visible tab index or a build-specific component number.
    local menu = kind == 'settings' and 'FE_MENU_VERSION_LANDING_MENU'
        or kind == 'keybindings' and 'FE_MENU_VERSION_LANDING_KEYMAPPING_MENU'
        or 'FE_MENU_VERSION_MP_PAUSE'
    nativeError = nil
    generation = generation + 1
    local token = generation
    nativeHandoff = { token = token, seen = false, started = GetGameTimer(),
        kind = kind, hash = GetHashKey(menu), expanded = false, returnTo = returnTo }
    publishState()
    ActivateFrontendMenu(GetHashKey(menu), false, -1)
end

RegisterNUICallback('pauseNative', function(data, cb)
    if not matches(data) then cb({ ok = false, error = 'stale_session' }); return end
    if data.target ~= 'map' and data.target ~= 'settings' and data.target ~= 'keybindings' then
        cb({ ok = false, error = 'invalid_target' }); return
    end
    -- Only Cortex pages that can host the handoff are valid return targets.
    local returnTo = (data.returnTo == 'home' or data.returnTo == 'settings') and data.returnTo or nil
    if not lib._closeSettingsForPause(data.session) then cb({ ok = false, error = 'close_failed' }); return end
    nativeMenu(data.target, returnTo)
    cb({ ok = true })
end)

RegisterNUICallback('pauseDisconnect', function(data, cb)
    if not matches(data) then cb({ ok = false, error = 'stale_session' }); return end
    if data.confirmed ~= true then cb({ ok = false, error = 'confirmation_required' }); return end
    if not lib._closeSettingsForPause(data.session) then cb({ ok = false, error = 'close_failed' }); return end
    cb({ ok = true })
    -- Fixed local command. Never execute browser-supplied commands or events.
    ExecuteCommand('disconnect')
end)

RegisterNUICallback('pauseWaypoint', function(data, cb)
    if not matches(data) then cb({ ok = false, error = 'stale_session' }); return end
    local entry = type(data.id) == 'string' and locations[data.id] or nil
    if not entry or GetResourceState(entry.owner) ~= 'started' then
        cb({ ok = false, error = 'location_unavailable' }); return
    end
    SetNewWaypoint(entry.x, entry.y)
    cb({ ok = true })
end)

RegisterNUICallback('pauseAction', function(data, cb)
    if not matches(data) then cb({ ok = false, error = 'stale_session' }); return end
    local entry = type(data.page) == 'string' and pages[data.page] or nil
    if not entry or not id(data.id) or not entry.actions[data.id]
        or GetResourceState(entry.owner) ~= 'started' then
        cb({ ok = false, error = 'action_unavailable' }); return
    end
    -- Close before dispatch so an extension can open its own focus-owning UI.
    -- A repeated or late callback is now stale, even if the handler yields.
    if not lib._closeSettingsForPause(data.session) then cb({ ok = false, error = 'close_failed' }); return end
    -- Acknowledge the dispatch before running extension code: even a yielding
    -- callback cannot leave a browser request hanging. Completion belongs to
    -- the resource and failures are surfaced through a notification.
    cb({ ok = true })
    if pages[data.page] ~= entry or GetResourceState(entry.owner) ~= 'started' then return end
    local ok, accepted = pcall(entry.onAction, data.id)
    if not ok then
        print(('[cortex-lib] Pause action failed for %s: %s'):format(entry.owner, tostring(accepted):sub(1, 256)))
    end
    if not ok or accepted == false then
        lib.notify({ type = 'error', title = entry.label, description = 'That action could not be completed.' })
    end
end)

exports('registerPausePage', registerPage)
exports('unregisterPausePage', function(entryId) return remove(pages, entryId) end)
exports('registerPauseLocation', registerLocation)
exports('unregisterPauseLocation', function(entryId) return remove(locations, entryId) end)
exports('openPauseMenu', openPause)
exports('isPauseMenuOpen', function() return visible or nativeHandoff ~= nil end)
exports('closePauseMenu', function()
    local modal = lib._getModalState()
    if visible and modal.resource == owner() then return lib._closeSettingsForPause(modal.generation) end
    return false
end)

RegisterCommand('cortexpause', openPause, false)
RegisterKeyMapping('cortexpause', 'Cortex: open pause menu', 'keyboard', '')

-- Diagnostic for servers whose graphics pack changes blur: open settings,
-- run /cortexblur in F8 and report which layers are live.
RegisterCommand('cortexblur', function()
    local values = {}
    for index = 0, GetTimecycleModifierVarCount('hud_def_blur') - 1 do
        local name = GetTimecycleModifierVarNameByIndex('hud_def_blur', index)
        if name:find('blur', 1, true) then
            local ok, value = GetTimecycleModifierVar('hud_def_blur', name)
            values[#values + 1] = ('%s=%s'):format(name, ok and tostring(value) or '?')
        end
    end
    print(('[cortex-lib] blur: settingsOpen=%s extraModifier=%d owned=%s screenblur=%s postfx(%s)=%s'):format(
        tostring(visible), GetExtraTimecycleModifierIndex(), tostring(blurModifierIndex ~= nil),
        tostring(blurOwned), PAUSE_POSTFX, tostring(AnimpostfxIsRunning(PAUSE_POSTFX))))
    print('[cortex-lib] hud_def_blur values: ' .. (#values > 0 and table.concat(values, ', ') or 'none'))
end, false)
RegisterCommand('cortexnative', function()
    if nativeHandoff or IsPauseMenuActive() then return end
    if visible then
        local modal = lib._getModalState()
        lib._closeSettingsForPause(modal.generation)
    elseif pauseInputBusy() then
        return
    end
    nativeMenu('map')
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE then
        alive = false
        releaseBlur()
        if pauseBlurCreated then RemoveTimecycleModifier(pauseBlurName); pauseBlurCreated = false end
        generation = generation + 1
        if nativeHandoff and GetCurrentFrontendMenuVersion() == nativeHandoff.hash then
            SetFrontendActive(false)
        end
        nativeHandoff = nil
        visible = false
        publishState()
        return
    end
    for key, entry in pairs(pages) do if entry.owner == resource then pages[key] = nil end end
    for key, entry in pairs(locations) do if entry.owner == resource then locations[key] = nil end end
    refresh()
end)

CreateThread(function()
    local lastQuickMenu = quickMenuEnabled()
    while alive do
        -- Backstop: blur never outlives the surface that asked for it.
        if blurOwned and not visible then releaseBlur() end
        local quickMenu = quickMenuEnabled()
        if quickMenu ~= lastQuickMenu then
            lastQuickMenu = quickMenu
            clearPausePresses()
            refresh()
        end
        if nativeHandoff then
            local handoff = nativeHandoff
            local active = IsPauseMenuActive()
            local ownsFrontend = active and GetCurrentFrontendMenuVersion() == handoff.hash
            if active and not ownsFrontend then
                -- Another resource replaced the frontend. Do not close it or
                -- reopen our NUI over it, including from a delayed return.
                generation = generation + 1
                nativeHandoff = nil
                publishState()
            elseif ownsFrontend and not (handoff.kind == 'map' and not handoff.expanded
                and GetGameTimer() - handoff.started > 3000) then
                handoff.seen = true
                if handoff.kind == 'map' then
                    if not handoff.expanded and not IsPauseMenuRestarting() and IsFrontendReadyForControl() then
                        -- Cfx's documented page table: MAP = 1000, page IDs
                        -- passed to this native subtract 1000. Keep the engine
                        -- renderer, legend, blip metadata and routes intact.
                        PauseMenuceptionGoDeeper(0)
                        handoff.expanded = true
                    elseif handoff.expanded and (IsControlJustReleased(2, 202)
                        or IsControlJustReleased(2, 200) or IsControlJustReleased(2, 199)) then
                        SetFrontendActive(false)
                    end
                end
            elseif handoff.seen or GetGameTimer() - handoff.started > 3000 then
                local failed = not handoff.seen or (handoff.kind == 'map' and not handoff.expanded)
                if ownsFrontend then SetFrontendActive(false) end
                nativeHandoff = nil
                publishState()
                nextOpenAt = GetGameTimer() + 250
                -- Leaving GTA's settings or key mapping returns to the Cortex page
                -- that opened it, so the handoff reads as one Settings surface.
                local returnPage = handoff.returnTo
                    or (handoff.kind == 'settings' or handoff.kind == 'keybindings') and 'settings' or nil
                SetTimeout(275, function()
                    if alive and generation == handoff.token then openPause(returnPage) end
                end)
                if failed then
                    nativeError = 'Game menu did not open. Use /cortexnative to retry.'
                    lib.notify({ type = 'error', title = 'Game menu unavailable', description = nativeError })
                end
            end
            Wait(handoff.kind == 'map' and 0 or 100)
        elseif visible then
            -- The settings modal owns focus and blocks world/native actions.
            DisableFrontendThisFrame()
            DisableAllControlActions(0)
            DisableAllControlActions(2)
            DisablePlayerFiring(PlayerId(), true)
            if not IsUsingKeyboard(2) then
                for _, binding in ipairs(controllerInputs) do
                    if IsDisabledControlJustPressed(2, binding[1]) then
                        local modal = lib._getModalState()
                        if modal.focused then
                            SendNUIMessage({ action = 'pauseInput', data = { session = modal.generation, input = binding[2] } })
                        end
                        break
                    end
                end
            end
            if IsPauseMenuActive() then
                -- A different script opened native frontend while we had focus.
                lib._closeSettingsForPause(lib._getModalState().generation)
            end
            Wait(0)
        elseif quickMenu then
            -- Sample input every frame, but ownership checks and frontend
            -- suppression only have work to do during a pause gesture. Keep
            -- watching armed gestures between edges to catch foreign takeover.
            local gesture = false
            for index = 1, #pauseControls do
                local binding = pauseControls[index]
                binding.pressed = IsControlJustPressed(binding[1], binding[2])
                binding.released = IsControlJustReleased(binding[1], binding[2])
                if binding.pressed or binding.released or binding.armed then gesture = true end
            end
            if gesture then
                if (bypassUntil == 0 or GetGameTimer() >= bypassUntil) and not pauseInputBusy() then
                    -- Suppress even an unarmed release (e.g. held on startup),
                    -- but never treat it as permission to open Cortex.
                    DisableFrontendThisFrame()
                    local requested = false
                    for index = 1, #pauseControls do
                        local binding = pauseControls[index]
                        if binding.pressed then binding.armed = true end
                        if binding.armed and binding.released then
                            requested = true
                            binding.armed = false
                        end
                    end
                    if requested then clearPausePresses(); openPause() end
                else
                    -- A menu closing before Escape releases must not open us.
                    clearPausePresses()
                end
            end
            Wait(0)
        else
            clearPausePresses()
            Wait(250)
        end
    end
end)
