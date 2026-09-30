-- Deterministic Lua/native-boundary harness. Does not execute GTA or CEF.
local callbacks, commands, public, events, threads, timeouts, messages = {}, {}, {}, {}, {}, {}, {}
local convars, requested, released = {}, {}, {}
local blur = false
local extraModifier = -1
local blurClones, blurRemoved, blurWrites = 0, false, {}
function CloneTimecycleModifier(source, target)
    assert(source == 'hud_def_blur' and target == 'cortex-lib_pause_blur')
    blurClones = blurClones + 1
    return 42
end
-- Synthetic preset fields test value scaling and blend preservation only.
local blurVars = { 'test_blur_amount', 'test_blur_vignetting', 'test_motion_blur', 'test_color' }
function GetTimecycleModifierVarCount(name) assert(name == 'hud_def_blur'); return #blurVars end
function GetTimecycleModifierVarNameByIndex(name, index) assert(name == 'hud_def_blur'); return blurVars[index + 1] end
function GetTimecycleModifierVar(name, var) assert(name == 'hud_def_blur'); return true, 2.0, 0.75 end
function SetTimecycleModifierVar(name, var, value, blend)
    assert(name == 'cortex-lib_pause_blur')
    blurWrites[var] = { value, blend }
end
function RemoveTimecycleModifier(name) assert(name == 'cortex-lib_pause_blur'); blurRemoved = true end
function GetExtraTimecycleModifierIndex() return extraModifier end
function SetExtraTimecycleModifier(name) assert(name == 'cortex-lib_pause_blur'); extraModifier = 42 end
function ClearExtraTimecycleModifier() extraModifier = -1 end
local kvp, stopped, inputReleased, inputPressed, executed = {}, {}, {}, {}, {}
local currentOwner, nativeActive, keyboard, now = nil, false, true, 0
local focused, nativeMenu, waypoint, state = false, nil, nil, nil
local onscreenKeyboard, warningActive, inputGroup = -1, false, 0
local foreignDisabled = { [0] = {}, [2] = {} }
local suppressed, allControls, disabled = 0, 0, {}
local modal = { generation = 0 }
local frontendReady, frontendRestarting, expanded = true, false, 0
function GetCurrentFrontendMenuVersion() return nativeMenu and nativeMenu[1] end
function IsFrontendReadyForControl() return frontendReady end
function IsPauseMenuRestarting() return frontendRestarting end
function PauseMenuceptionGoDeeper(page)
    assert(page == 0)
    if page == 0 then expanded = expanded + 1 end
end
function IsControlEnabled(group, key) return not foreignDisabled[group][key] end
function IsControlJustPressed(group, key)
    return group == inputGroup and not foreignDisabled[group][key] and inputPressed[key] == true
end
function IsControlJustReleased(group, key)
    return group == inputGroup and not foreignDisabled[group][key] and inputReleased[key] == true
end

function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return currentOwner end
function GetNumResources() return 0 end
function GetResourceByFindIndex() return nil end
function GetResourceState(resource) return stopped[resource] and 'stopped' or 'started' end
function GetResourceKvpString(key) return kvp[key] end
function SetResourceKvp(key, value) kvp[key] = value end
function DeleteResourceKvp(key) kvp[key] = nil end
function GetConvar(name, fallback) return convars[name] or fallback end
function TriggerScreenblurFadeIn() blur = true end
function TriggerScreenblurFadeOut() blur = false end
local postfx = {}
function AnimpostfxIsRunning(name) return postfx[name] == true end
function AnimpostfxPlay(name) postfx[name] = true end
function AnimpostfxStop(name) postfx[name] = nil end
local hudHiddenFrames = 0
function HideHudAndRadarThisFrame() hudHiddenFrames = hudHiddenFrames + 1 end
function RequestStreamedTextureDict(name) requested[name] = true end
function HasStreamedTextureDictLoaded(name) return requested[name] == true end
function SetStreamedTextureDictAsNoLongerNeeded(name) released[name] = true end
function IsWaypointActive() return false end
function SetWaypointOff() waypoint = nil end
function GetEntityHeading() return 0 end
function GetFirstBlipInfoId() return 0 end
function GetNextBlipInfoId() return 0 end
function DoesBlipExist() return false end
function GetConvarInt(name, fallback) return convars[name] or fallback end
function SetConvarReplicated(name, value) convars[name] = tonumber(value) or value end
function GetGameTimer() return now end
function PlayerId() return 0 end
function PlayerPedId() return 1 end
function GetPlayerName() return 'Test player' end
function GetPlayerServerId() return 7 end
function GetEntityCoords() return { x = 1, y = 2, z = 3 } end
function GetNameOfZone() return 'PBOX' end
function GetLabelText() return 'Pillbox Hill' end
function GetSafeZoneSize() return 0.95 end
function GetHashKey(value) return value end
function GetSoundId() return 1 end
function PlaySoundFrontend() end
function ReleaseSoundId() end
function SetNuiFocus(value) focused = value end
function IsNuiFocused() return focused end
function UpdateOnscreenKeyboard() return onscreenKeyboard end
function IsWarningMessageActive() return warningActive end
function IsPauseMenuActive() return nativeActive end
function IsUsingKeyboard() return keyboard end
function IsScreenFadedOut() return false end
function IsPlayerSwitchInProgress() return false end
function ActivateFrontendMenu(hash, pause, component) nativeMenu = { hash, pause, component } end
function SetFrontendActive(value) nativeActive = value end
function SetNewWaypoint(x, y) waypoint = { x, y } end
function ExecuteCommand(value) executed[#executed + 1] = value end
function DisableFrontendThisFrame() suppressed = suppressed + 1 end
function DisableAllControlActions() allControls = allControls + 1 end
function DisablePlayerFiring() end
function DisableControlAction(_, key) disabled[key] = true end
function IsDisabledControlJustReleased(_, key) return inputReleased[key] == true end
function IsDisabledControlJustPressed(_, key) return inputPressed[key] == true end
function SendNUIMessage(message) messages[#messages + 1] = message end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function RegisterCommand(name, callback) commands[name] = callback end
function RegisterKeyMapping() end
function SetTimeout(delay, callback) timeouts[#timeouts + 1] = { delay = delay, callback = callback } end
function CreateThread(callback) threads[#threads + 1] = coroutine.create(callback) end
function Wait(delay) coroutine.yield(delay) end
function AddEventHandler(name, callback)
    events[name] = events[name] or {}
    table.insert(events[name], callback)
end
function TriggerEvent() end
LocalPlayer = { state = { set = function(_, key, value, replicated)
    assert(key == 'cortexPauseOpen' and replicated == false)
    state = value
end } }
exports = setmetatable({}, { __call = function(_, name, callback) public[name] = callback end })
lib = { notify = function() end }
local modalSnapshots = 0
function lib._getModalState() modalSnapshots = modalSnapshots + 1; return modal end
function lib._hasModalSurface() return modal.surface ~= nil end
function lib._acquireModal(surface, resource)
    if focused and not modal.surface then return nil end
    modal = { surface = surface, resource = resource, generation = modal.generation + 1, focused = false }
    return modal.generation
end
function lib._focusModal(surface, generation)
    if modal.surface ~= surface or modal.generation ~= generation then return false end
    focused = true; modal.focused = true
    return true
end
function lib._matchesModal(surface, generation, supplied)
    return modal.surface == surface and modal.generation == generation and supplied == generation
end
function lib._releaseModal(surface, generation)
    if modal.surface ~= surface or modal.generation ~= generation then return false end
    focused = false; modal.focused = false; modal.surface = nil
    return true
end

dofile('imports/settings/client.lua')
local idleNativeCalls = 0
for _, name in ipairs({ 'GetGameTimer', 'IsNuiFocused', 'UpdateOnscreenKeyboard',
    'IsWarningMessageActive', 'IsPauseMenuActive', 'IsScreenFadedOut', 'IsPlayerSwitchInProgress',
    'IsControlEnabled', 'IsControlJustPressed', 'IsControlJustReleased', 'DisableFrontendThisFrame' }) do
    local native = _G[name]
    _G[name] = function(...)
        idleNativeCalls = idleNativeCalls + 1
        return native(...)
    end
end
dofile('client/pause.lua')
dofile('server/config.lua')
assert(convars.cortex_pause_replace_native == 0, 'server must replicate an off default')
assert(#threads == 1, 'pause has one input/lifecycle loop')

local function tick()
    local ok, result = coroutine.resume(threads[1])
    assert(ok, result)
    inputPressed, inputReleased = {}, {}
    return result
end
local function call(name, data)
    local reply, calls = nil, 0
    callbacks[name](data, function(result) calls = calls + 1; reply = result end)
    assert(calls == 1 and type(reply) == 'table', name .. ' must reply exactly once')
    return reply
end
local function timeout(delay)
    for index = #timeouts, 1, -1 do
        if timeouts[index].delay == delay then
            local item = table.remove(timeouts, index)
            item.callback()
            return
        end
    end
    error('missing timeout ' .. delay)
end
local function stop(resource)
    stopped[resource] = true
    for _, handler in ipairs(events.onResourceStop or {}) do handler(resource) end
end
local function open()
    currentOwner = nil; now = now + 300
    assert(public.openPauseMenu())
    assert(state and not focused, 'opening must wait for CEF acknowledgement')
    local session = modal.generation
    assert(call('settingsReady', { session = session }).ok)
    assert(focused)
    return session
end

currentOwner = 'hud'
assert(public.registerSettings('hud', 'HUD', nil, { { key = 'enabled', type = 'toggle', label = 'Enabled' } }, { enabled = true }))
local actions = {}
local onActionReference = setmetatable({ __cfx_functionReference = 'test-reference' }, {
    __call = function(_, action) actions[#actions + 1] = action end,
})
local definition = { id = 'help', label = 'Help', sections = { { title = 'Guide', body = 'Original',
    actions = { { id = 'open', label = 'Open guide' } } } }, onAction = onActionReference }
assert(public.registerPausePage(definition))
definition.sections[1].body = 'Mutation'
assert(lib._getPausePayload().pages[1].sections[1].body == 'Original', 'registry must copy caller data')
local snapshot = lib._getPausePayload()
snapshot.pages[1].sections[1].body = 'Snapshot mutation'
assert(lib._getPausePayload().pages[1].sections[1].body == 'Original')
assert(not public.registerPausePage({ id = '__proto__', label = 'Bad' }))
assert(not public.registerPausePage({ id = 'bad', label = 'Bad', sections = { [2] = {} } }))
assert(not public.registerPausePage({ id = 'bad', label = 'Bad', sections = { { actions = { { id = 'a', label = 'A' } } } } }))
assert(not public.registerPausePage({ id = 'bad', label = 'Bad', onAction = { __cfx_functionReference = 'not-callable' } }))
assert(not public.registerPauseLocation({ id = 'bad', label = 'Bad', x = 0 / 0, y = 1 }))
assert(public.registerPauseLocation({ id = 'hospital', label = 'Hospital', x = 20, y = 30 }))
currentOwner = 'other'
assert(public.unregisterPausePage('help'))
assert(#lib._getPausePayload().pages == 1, 'unregister is owner scoped')
currentOwner = nil

-- Only the server convar enables the quick menu. Old per-player preferences
-- cannot restore it, and the default command opens standalone settings.
assert(not lib.setSetting('pauseMenu', true))
assert(lib.getSetting('pauseMenu') == nil)
assert(tick() == 250)
commands.cortexpause()
assert(messages[#messages].data.page == 'settings')
assert(messages[#messages].data.pause.quickMenu == false)
assert(blur and postfx.MenuMGSelectionIn, 'standalone settings owns native game blur, including the postfx layer')
assert(call('settingsReady', { session = modal.generation }).ok)
assert(public.closePauseMenu())
assert(not blur and not postfx.MenuMGSelectionIn, 'closing standalone settings releases every blur layer')
convars.cortex_pause_replace_native = 1
now = now + 300

-- Idle samples edges only. Native activation is suppressed during gestures,
-- without disabling the controls or inspecting unrelated menu state at rest.
assert(tick() == 0)
assert(suppressed == 0 and next(disabled) == nil and allControls == 0)
local beforeSnapshots = modalSnapshots
local beforeNativeCalls = idleNativeCalls
for _ = 1, 600 do tick() end
assert(modalSnapshots == beforeSnapshots, 'closed idle frames do not allocate modal snapshots')
assert(idleNativeCalls - beforeNativeCalls == 600 * 8, 'idle only samples both edges in both groups')
assert(suppressed == 0, 'idle does not issue frontend suppression natives')
print('Pause closed-idle fixture: 4800 native calls / 600 frames; zero modal snapshots')
local before = suppressed
focused = true; tick(); focused = false
assert(suppressed == before, 'other NUI must not be intercepted')
nativeActive = true; tick(); nativeActive = false
assert(suppressed == before, 'already open native frontend retains input')

-- Native menus can own input without NUI focus. Neither their typing nor
-- their closing release may open Cortex; both input groups must respect this.
local blockers = {
    { 'native text entry', function(active) onscreenKeyboard = active and 0 or 2 end },
    { 'foreign NUI', function(active) focused = active end },
    { 'native warning', function(active) warningActive = active end },
    { 'native frontend', function(active) nativeActive = active end },
    { 'menu disabling Escape', function(active) foreignDisabled[0][200] = active end },
    { 'menu disabling frontend P', function(active) foreignDisabled[2][199] = active end },
}
for _, blocker in ipairs(blockers) do
    for _, group in ipairs({ 0, 2 }) do
        inputGroup = group
        for _, key in ipairs({ 199, 200 }) do
            local count = #messages
            local suppression = suppressed
            blocker[2](true)
            inputPressed[key] = true; tick()
            inputReleased[key] = true; tick()
            assert(not public.isPauseMenuOpen(), blocker[1] .. ' must retain typing/back input')
            assert(suppressed == suppression and #messages == count, blocker[1] .. ' must retain frontend ownership')
            assert(not public.openPauseMenu(), blocker[1] .. ' must block direct pause entry')
            commands.cortexpause()
            commands.cortexnative()
            assert(not public.isPauseMenuOpen(), blocker[1] .. ' must block mapped commands too')

            inputPressed[key] = true; tick()
            blocker[2](false)
            inputReleased[key] = true; tick()
            assert(not public.isPauseMenuOpen(), blocker[1] .. ' closing release must not leak into Cortex')

            inputPressed[key] = true; tick()
            blocker[2](true); tick()
            blocker[2](false)
            inputReleased[key] = true; tick()
            assert(not public.isPauseMenuOpen(), blocker[1] .. ' takeover must cancel an earlier gameplay press')
        end
    end
end
onscreenKeyboard = -1
for _, group in ipairs({ 0, 2 }) do
    inputGroup = group
    for _, key in ipairs({ 199, 200 }) do
        now = now + 300
        local suppression = suppressed
        inputPressed[key] = true; tick()
        assert(suppressed == suppression + 1, 'press suppresses native frontend on the same frame')
        inputReleased[key] = true; tick()
        assert(suppressed == suppression + 2, 'release suppresses native frontend on the same frame')
        assert(public.isPauseMenuOpen(), 'a fresh gameplay press/release must still open Cortex')
        assert(call('settingsReady', { session = modal.generation }).ok)
        assert(public.closePauseMenu())
    end
end
-- A server owner can disable the quick menu live; players cannot override it.
inputGroup = 0
now = now + 300
assert(public.openPauseMenu())
assert(call('settingsReady', { session = modal.generation }).ok)
convars.cortex_pause_replace_native = 0
tick()
assert(messages[#messages].action == 'pauseUpdate' and messages[#messages].data.pause.quickMenu == false,
    'an open menu receives the server opt-out immediately')
assert(public.closePauseMenu())
assert(not lib.setSetting('pauseMenu', true))
now = now + 300
local suppression = suppressed
inputPressed[200] = true; tick()
inputReleased[200] = true; tick()
assert(not public.isPauseMenuOpen(), 'Escape stays with GTA when the quick menu is off')
assert(suppressed == suppression, 'the native pause menu is not suppressed when the quick menu is off')
commands.cortexpause()
assert(messages[#messages].action == 'settingsOpen' and messages[#messages].data.page == 'settings',
    'without the quick menu Cortex opens on Settings')
assert(messages[#messages].data.pause.quickMenu == false)
assert(call('settingsReady', { session = modal.generation }).ok)
assert(public.closePauseMenu())
convars.cortex_pause_replace_native = 1
dofile('server/config.lua')
assert(convars.cortex_pause_replace_native == 1, 'server startup preserves an explicit owner opt-in')
inputGroup = 0
now = now + 300
-- A release without a gameplay press is never an opening gesture.
local orphanSuppression = suppressed
inputReleased[200] = true; tick()
assert(not public.isPauseMenuOpen())
assert(suppressed == orphanSuppression + 1, 'unarmed release must not open GTA frontend either')
inputPressed[200] = true; tick()
inputReleased[200] = true; tick()
assert(messages[#messages].action == 'settingsOpen' and messages[#messages].data.page == 'home')
local session = modal.generation
assert(not call('pauseNative', { session = session, target = 'audio' }).ok, 'unfocused shell cannot open Audio')
assert(not call('pauseNative', { session = session, target = 'map' }).ok, 'unfocused shell cannot dispatch')
assert(call('settingsReady', { session = session }).ok)
assert(callbacks.pauseSfxTest == nil, 'experimental SFX mutation callbacks are removed')
beforeSnapshots = modalSnapshots
for _ = 1, 600 do tick() end
assert(modalSnapshots == beforeSnapshots, 'open keyboard idle frames do not allocate modal snapshots')
keyboard = false
for _ = 1, 600 do tick() end
assert(modalSnapshots == beforeSnapshots, 'idle controller frames do not allocate modal snapshots')
keyboard = true
assert(blur and extraModifier == 42, 'custom menu owns both background blur layers')
assert(blurWrites.test_blur_amount[1] == 16 and blurWrites.test_blur_amount[2] == 0.75, 'heavy blur scales the stock preset')
assert(not blurWrites.test_blur_vignetting and not blurWrites.test_motion_blur and not blurWrites.test_color)
assert(callbacks.pauseMap == nil and callbacks.pauseMapWaypoint == nil, 'no lossy custom map bridge remains')
assert(callbacks.pauseGameSettings == nil and callbacks.pauseGameApply == nil, 'GTA preferences have no custom read/write bridge')
assert(not call('pauseNative', { session = session, target = 'audio' }).ok, 'removed Audio styling route is rejected')
assert(not call('pauseNative', { session = session, target = 'arbitrary' }).ok)
assert(not call('pauseWaypoint', { session = session, id = {} }).ok)
assert(call('pauseWaypoint', { session = session, id = 'hud:hospital' }).ok)
assert(waypoint[1] == 20 and waypoint[2] == 30)
assert(call('settingsPreview', { session = session, tabId = 'hud', key = 'enabled', value = false }).ok)
assert(public.getTabSetting('hud', 'enabled') == false)
assert(call('pauseNative', { session = session, target = 'map' }).ok)
assert(not blur and extraModifier == -1 and next(requested) == nil, 'native map owns its textures; custom blur is released')
assert(not focused and state and modal.surface == nil, 'handoff releases focus but remains observed as pause')
assert(public.getTabSetting('hud', 'enabled') == true and kvp['cortex:hud:enabled'] == nil, 'native handoff rolls back previews')
assert(nativeMenu[1] == 'FE_MENU_VERSION_MP_PAUSE' and nativeMenu[2] == false and nativeMenu[3] == -1)
assert(not call('pauseNative', { session = session, target = 'map' }).ok, 'handoff is not replayable')
nativeActive = true; frontendReady = false; tick()
assert(expanded == 0, 'wait for frontend readiness')
frontendReady = true; frontendRestarting = true; tick()
assert(expanded == 0, 'do not enter map during frontend restart')
frontendRestarting = false; tick(); tick()
assert(expanded == 1, 'expand exactly once after readiness')
assert(not focused, 'native map retains input ownership')
inputGroup = 2; inputReleased[202] = true; tick(); inputGroup = 0
assert(not nativeActive, 'Back closes fullscreen map in one action')
tick()
now = now + 300; timeout(275)
assert(messages[#messages].action == 'settingsOpen' and messages[#messages].data.page == 'home', 'native exit returns to custom menu')
assert(call('settingsReady', { session = modal.generation }).ok)
session = modal.generation

-- Controller sends edge events only; no browser frame-rate message stream.
keyboard = false
inputPressed[188] = true; tick()
assert(messages[#messages].action == 'pauseInput' and messages[#messages].data.input == 'up')
local total = #messages
tick(); assert(#messages == total)
keyboard = true
currentOwner = 'other'
assert(public.closePauseMenu() == false, 'a foreign resource cannot close a consumer-owned session')
currentOwner = nil
assert(not call('pauseAction', { session = session, page = 'hud:help', id = 'unregistered' }).ok)
assert(call('pauseAction', { session = session, page = 'hud:help', id = 'open' }).ok)
assert(#actions == 1 and not focused)
assert(not call('pauseAction', { session = session, page = 'hud:help', id = 'open' }).ok)
assert(#actions == 1)

session = open()
assert(call('pauseNative', { session = session, target = 'settings' }).ok)
assert(nativeMenu[1] == 'FE_MENU_VERSION_LANDING_MENU' and nativeMenu[3] == -1)
assert(not focused and modal.surface == nil and not blur, 'vanilla Settings owns input; custom surface has released focus and blur')
local controlsBeforeSettings, expansionsBeforeSettings = allControls, expanded
nativeActive = true; tick()
assert(allControls == controlsBeforeSettings and expanded == expansionsBeforeSettings, 'Settings gets no synthetic input or map expansion')
nativeActive = false; tick()
focused = true; now = now + 300; timeout(275)
assert(not public.isPauseMenuOpen() and focused, 'native return must not steal new external focus')
focused = false
session = open()
assert(call('pauseNative', { session = session, target = 'map' }).ok)
nativeActive = true; frontendReady = false; tick()
local beforeExpansion = expanded
now = now + 3100; tick()
assert(not nativeActive and expanded == beforeExpansion, 'ready timeout closes only the owned frontend')
now = now + 300; timeout(275)
assert(call('settingsReady', { session = modal.generation }).ok)
session = modal.generation
assert(call('pauseNative', { session = session, target = 'map' }).ok)
frontendReady = true; nativeActive = true
nativeMenu = { 'FOREIGN_FRONTEND', false, -1 }; tick()
assert(nativeActive and not public.isPauseMenuOpen() and not focused, 'foreign frontend takeover is left intact')
nativeActive = false
session = open()
assert(call('pauseNative', { session = session, target = 'keybindings' }).ok)
assert(nativeMenu[1] == 'FE_MENU_VERSION_LANDING_KEYMAPPING_MENU')
now = now + 3100; tick(); now = now + 300; timeout(275)
assert(public.isPauseMenuOpen(), 'activation timeout offers the custom menu again')
assert(call('settingsReady', { session = modal.generation }).ok)
session = modal.generation
assert(not call('pauseDisconnect', { session = session, confirmed = 'true' }).ok)
assert(call('pauseDisconnect', { session = session, confirmed = true }).ok)
assert(executed[1] == 'disconnect' and #executed == 1 and not focused)
assert(not call('pauseDisconnect', { session = session, confirmed = true }).ok)

session = open()
stop('hud')
assert(#lib._getPausePayload().pages == 0 and #lib._getPausePayload().locations == 0)
assert(not focused and not state, 'stopped settings owner closes and rolls back the shell')
assert(not call('pauseAction', { session = session, page = 'hud:help', id = 'open' }).ok)

-- Script settings opened directly (not through the quick menu) get the same
-- blur, and every close path releases it: another modal taking focus, a
-- readiness timeout, and the settings owner stopping.
currentOwner = 'hud'; now = now + 300
assert(public.openSettingsMenu())
assert(blur and extraModifier == 42, 'openSettingsMenu blurs the game natively')
assert(call('settingsReady', { session = modal.generation }).ok)
local takeover = lib._pendingModalSurfaces and lib._pendingModalSurfaces.settings
assert(type(takeover) == 'function', 'settings registers a modal takeover closer')
takeover(modal.generation, 'replaced')
assert(not blur and extraModifier == -1 and not postfx.MenuMGSelectionIn, 'a modal takeover releases the blur')
assert(messages[#messages].action == 'settingsClose' and messages[#messages].data.reason == 'replaced')
modal.surface = nil; focused = false
now = now + 300
assert(public.openSettingsMenu())
assert(blur)
timeout(10000)
assert(not blur and extraModifier == -1, 'a readiness timeout releases the blur')
now = now + 300
assert(public.openSettingsMenu())
assert(call('settingsReady', { session = modal.generation }).ok)
stop('hud')
assert(not blur and extraModifier == -1, 'the owning resource stopping releases the blur')
stopped.hud = nil
currentOwner = 'hud'
assert(public.registerSettings('hud', 'HUD', nil, { { key = 'enabled', type = 'toggle', label = 'Enabled' } }, { enabled = true }))
currentOwner = nil

-- Extra blur respects occupied slots and later resource takeovers.
extraModifier = 77
session = open()
assert(extraModifier == 77, 'opening preserves an existing secondary effect')
assert(public.closePauseMenu())
assert(extraModifier == 77, 'closing preserves an existing secondary effect')
extraModifier = -1
session = open()
assert(extraModifier == 42)
extraModifier = 88
assert(public.closePauseMenu())
assert(extraModifier == 88, 'closing does not clear a replacement effect')
extraModifier = -1

-- CEF failure gives native Escape a temporary recovery window.
-- Exercise the actual bridge + pause owner together with asynchronous GTA close.
function RequestScaleformMovie(name) return name end
function HasScaleformMovieLoaded() return true end
function SetScaleformMovieAsNoLongerNeeded() end
function BeginScaleformMovieMethodOnFrontend() return true end
function BeginScaleformMovieMethodOnFrontendHeader() return true end
function BeginScaleformMovieMethod() return true end
function EndScaleformMovieMethod() end
function EndScaleformMovieMethodReturnValue() return 1 end
function ScaleformMovieMethodAddParamBool() end
function IsScaleformMovieMethodReturnValueReady() return true end
function GetScaleformMovieMethodReturnValueInt() return 0 end -- startup failure

now = now + 300; assert(public.openPauseMenu())
timeout(10000)
assert(not focused and not public.isPauseMenuOpen() and not blur)
before = suppressed; tick(); assert(suppressed == before)
inputPressed[200] = true; tick()
inputReleased[200] = true; tick()
assert(suppressed == before and not public.isPauseMenuOpen(), 'CEF recovery window leaves real pause gestures to GTA')

now = now + 31000
session = open()
assert(call('pauseNative', { session = session, target = 'settings' }).ok)
nativeActive = true
stop('cortex-lib')
assert(not nativeActive and not state and not public.isPauseMenuOpen(), 'stop cleans native and observation state')
assert(not public.openPauseMenu())
assert(blurRemoved and blurClones == 1, 'private blur is reused and removed on stop')
print('pause registry, native handoff, input and lifecycle: PASS (stubbed natives)')
