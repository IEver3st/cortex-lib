local scriptPath = arg[1] or 'imports/menu/client.lua'

local invoking = nil
local callbacks, events, messages = {}, {}, {}
local generation, activeSession = 0, nil
local focusSucceeds = true

function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return invoking end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function AddEventHandler(name, callback) events[name] = callback end
function SendNUIMessage(message) messages[#messages + 1] = message end
function CreateThread() end
function DisableControlAction() end
function DisablePlayerFiring() end
function PlayerId() return 1 end
function Wait() end
function SetNuiFocus() end
function SetNuiFocusKeepInput() end

exports = function() end
lib = {
    _acquireModal = function()
        generation = generation + 1
        activeSession = generation
        return generation
    end,
    _focusModal = function(_, session) return focusSucceeds and activeSession == session end,
    _matchesModal = function(_, session, supplied) return activeSession == session and supplied == session end,
    _releaseModal = function(_, session)
        if activeSession ~= session then return false end
        activeSession = nil
        return true
    end,
    _registerModalSurface = function() end,
}

local api = assert(dofile(scriptPath))
local callbackScroll
local closeReason = 'unset'
local hostileError = setmetatable({}, { __tostring = function() error('hostile tostring') end })
local value = { label = 'One', description = 'Safe', poison = function() end }
value.cycle = value
local sourceOptions = {
    { label = 'Values', values = { value }, defaultIndex = 1, close = false },
    { label = 'Plain', close = false },
}

invoking = 'owner-a'
local invalid, invalidError = api.registerMenu({
    id = 'invalid-callback', title = 'Invalid', options = {}, onClose = 'not-a-function',
})
assert(invalid == false and invalidError == 'invalid_callbacks',
    'menu callback declarations must be functions or nil')
invalid, invalidError = api.registerMenu({
    id = 'invalid-default', title = 'Invalid', options = { { label = 'Plain', defaultIndex = 1 } },
}, function() end)
assert(invalid == false and invalidError == 'invalid_options',
    'plain options must reject a defaultIndex without values')
invalid, invalidError = api.registerMenu({
    id = 'invalid-color', title = 'Invalid', options = { { label = 'Plain', iconColor = 'red;position:fixed' } },
}, function() end)
assert(invalid == false and invalidError == 'invalid_options',
    'menu icon colors must reject arbitrary CSS')
assert(api.registerMenu({
    id = 'main', title = 'Main', position = 'top-left', options = sourceOptions,
    onClose = function(reason) closeReason = reason end,
}, function(_, scrollIndex) callbackScroll = scrollIndex end))

sourceOptions[1].label = 'MUTATED'
value.label = 'MUTATED'
value.poison = value
assert(api.showMenu('main'))
local open = messages[#messages]
assert(open.action == 'menuOpen' and open.data.options[1].label == 'Values', 'registration must snapshot menu display state')
assert(open.data.options[1].values[1].label == 'One', 'registration must snapshot option values')
assert(open.data.options[1].values[1].poison == nil and open.data.options[1].values[1].cycle == nil,
    'NUI values must contain only supported serializable fields')
local session = open.data.session
local revision = open.data.revision

local response
assert(api.setMenuOptions('main', { label = 'Updated', close = false }, 1))
local updatedRevision = messages[#messages].data.revision
callbacks.cortex_menu_selected({ id = 'main', session = session, revision = revision, selected = 1 }, function(value) response = value end)
assert(response and response.ok == false, 'queued callbacks from an older option revision must be rejected')

callbacks.cortex_menu_check({ id = 'main', session = session, revision = updatedRevision, selected = 2, checked = true }, function(value) response = value end)
assert(response and response.ok == false, 'unchecked options must reject forged check callbacks')

callbacks.cortex_menu_submit({ id = 'main', session = session, revision = updatedRevision, selected = 2, scrollIndex = 999 }, function(value) response = value end)
assert(response and response.ok == true and callbackScroll == 1, 'plain options must not pass attacker-controlled scroll indexes')

invoking = 'owner-b'
assert(api.hideMenu() == false, 'an unrelated owner must not hide the active menu')
local collision, collisionError = api.registerMenu({ id = 'main', title = 'Other', options = {} }, function() end)
assert(collision == false and collisionError == 'owned_by_other_resource', 'cross-owner menu IDs must collide safely')

invoking = 'owner-a'
assert(api.registerMenu({ id = 'main', title = 'Replacement', canClose = false, options = { { label = 'New' } } }, function() end))
assert(activeSession == nil and closeReason == 'replaced', 're-registering an open menu must close the displayed session')

assert(api.showMenu('main'))
open = messages[#messages]
callbacks.cortex_menu_close({
    id = 'main', session = open.data.session, revision = open.data.revision, keyPressed = 'Escape',
}, function(value) response = value end)
assert(response and response.ok == false and response.error == 'close_not_allowed' and activeSession ~= nil,
    'a forged NUI close must not bypass canClose=false')
assert(api.hideMenu() == 'main' and activeSession == nil, 'programmatic owner close must remain available')

assert(api.registerMenu({
    id = 'errors', title = 'Errors',
    options = { { label = 'State', values = { 'one', 'two' }, defaultIndex = 1, checked = false, close = false } },
    onSelected = function() error(hostileError, 0) end,
    onSideScroll = function() error('side failed') end,
    onCheck = function() error('check failed') end,
}, function() end))
assert(api.showMenu('errors'))
open = messages[#messages]
local hostileReplies = 0
callbacks.cortex_menu_selected({
    id = 'errors', session = open.data.session, revision = open.data.revision, selected = 1,
}, function(value) response = value; hostileReplies = hostileReplies + 1 end)
assert(hostileReplies == 1 and response.ok == false and response.error == 'handler_error',
    'hostile error tostring handlers must still receive exactly one menu callback reply')
callbacks.cortex_menu_sideScroll({
    id = 'errors', session = open.data.session, revision = open.data.revision, selected = 1, scrollIndex = 2,
}, function(value) response = value end)
assert(response.ok == false, 'throwing side-scroll handlers must return a transactional failure')
callbacks.cortex_menu_check({
    id = 'errors', session = open.data.session, revision = open.data.revision, selected = 1, checked = true,
}, function(value) response = value end)
assert(response.ok == false, 'throwing check handlers must return a transactional failure')
assert(api.hideMenu() == 'errors')
assert(api.showMenu('errors'))
open = messages[#messages]
assert(open.data.options[1].defaultIndex == 1 and open.data.options[1].checked == false,
    'failed optimistic menu mutations must roll Lua state back')
assert(api.hideMenu() == 'errors')

assert(api.registerMenu({
    id = 'close-error', title = 'Close Error', options = {},
    onClose = function() error('close failed') end,
}))
assert(api.showMenu('close-error'))
open = messages[#messages]
callbacks.cortex_menu_close({
    id = 'close-error', session = open.data.session, revision = open.data.revision, keyPressed = 'Escape',
}, function(value) response = value end)
assert(response.ok == true and response.handlerError == true and activeSession == nil,
    'a throwing post-close hook must not report lifecycle failure after Lua/focus already closed')

-- FiveM export serialization turns functions into callable reference tables.
local function reference(callback)
    return setmetatable({ __cfx_functionReference = 'test:menu' }, {
        __call = function(_, ...) return callback(...) end,
    })
end
local referencedSubmit, referencedCheck, referencedClose = false, false, false
assert(api.registerMenu({
    id = 'exported', title = 'Classic', options = { { label = 'Toggle', checked = false, close = false } },
    onCheck = reference(function(index, checked) referencedCheck = index == 1 and checked end),
    onClose = reference(function(reason) referencedClose = reason == 'Backspace' end),
}, reference(function(index) referencedSubmit = index == 1 end)), 'cross-resource callbacks must register')
assert(api.showMenu('exported'))
open = messages[#messages]
local request = { id = 'exported', session = open.data.session, revision = open.data.revision, selected = 1, checked = true, keyPressed = 'Backspace' }
callbacks.cortex_menu_submit(request, function(value) response = value end)
assert(response.ok and referencedSubmit, 'exported submit callback must execute')
callbacks.cortex_menu_check(request, function(value) response = value end)
assert(response.ok and referencedCheck, 'exported toggle callback must execute')
callbacks.cortex_menu_close(request, function(value) response = value end)
assert(response.ok and referencedClose and activeSession == nil, 'exported back callback must execute after focus release')
assert(not api.registerMenu({ id = 'fake-ref', title = 'Invalid', options = {}, onCheck = { __cfx_functionReference = 'not-callable' } }))

-- Disabled rows are validated, reach NUI, and are refused by Lua whatever NUI sends.
invalid, invalidError = api.registerMenu({
    id = 'invalid-disabled', title = 'Invalid', options = { { label = 'Row', disabled = 'yes' } },
}, function() end)
assert(invalid == false and invalidError == 'invalid_options', 'disabled must be a boolean')
local disabledSubmit, disabledCheck, disabledScroll = false, false, false
assert(api.registerMenu({
    id = 'disabled', title = 'Disabled', options = {
        { label = 'Locked', disabled = true, close = false },
        { label = 'Locked check', checked = false, disabled = true },
        { label = 'Locked values', values = { 'a', 'b' }, disabled = true },
        { label = 'Open', disabled = false, close = false },
    },
    onCheck = function() disabledCheck = true end,
    onSideScroll = function() disabledScroll = true end,
}, function(index) disabledSubmit = index end))
assert(api.showMenu('disabled'))
open = messages[#messages]
assert(open.data.options[1].disabled == true and open.data.options[4].disabled == nil,
    'NUI must learn which rows are disabled')
local base = { id = 'disabled', session = open.data.session, revision = open.data.revision }
local function call(name, extra)
    local payload = {}
    for key, entry in pairs(base) do payload[key] = entry end
    for key, entry in pairs(extra) do payload[key] = entry end
    callbacks[name](payload, function(value) response = value end)
    return response
end
assert(call('cortex_menu_submit', { selected = 1 }).error == 'option_disabled' and disabledSubmit == false,
    'a forged submit on a disabled row must be refused')
assert(call('cortex_menu_check', { selected = 2, checked = true }).error == 'option_disabled' and disabledCheck == false,
    'a forged check on a disabled row must be refused')
assert(call('cortex_menu_sideScroll', { selected = 3, scrollIndex = 2 }).error == 'option_disabled' and disabledScroll == false,
    'a forged side scroll on a disabled row must be refused')
assert(call('cortex_menu_submit', { selected = 4 }).ok == true and disabledSubmit == 4, 'enabled rows still submit')
assert(api.hideMenu() == 'disabled')

focusSucceeds = false
assert(api.showMenu('main') == false and activeSession == nil, 'focus failure must release the modal session')

-- Game-control menus open without NUI focus and forward control input to NUI.
assert(select(2, api.registerMenu({ id = 'bad-start', title = 'Bad', startIndex = 3, options = { { label = 'A' } } }))
    == 'invalid_start_index', 'startIndex must address an existing option')
local thread
function CreateThread(fn) thread = fn end
function IsNuiFocused() return false end
function IsPauseMenuActive() return false end
function IsUsingKeyboard() return true end
local clock = 0
function GetGameTimer() clock = clock + 100; return clock end
function IsDisabledControlJustPressed(_, control) return control == 241 end
function IsDisabledControlPressed() return false end
assert(api.registerMenu({
    id = 'game', title = 'Game', gameControls = true, startIndex = 2,
    options = { { label = 'A' }, { label = 'B' } },
}))
assert(focusSucceeds == false)
assert(api.showMenu('game'), 'game-control menus must not depend on NUI focus')
open = messages[#messages]
assert(open.data.gameControls == true and open.data.startIndex == 2, 'NUI must learn the input mode and start row')
local waits = 0
function Wait() waits = waits + 1; if waits == 1 then api.hideMenu() end end
assert(type(thread) == 'function', 'game-control input must run on its own thread')
local before = #messages
thread()
local nav
for index = before + 1, #messages do
    if messages[index].action == 'menuNav' then nav = messages[index] end
end
assert(nav and nav.data.input == 'up' and nav.data.session == open.data.session, 'wheel up must navigate the open session')

print('menu lifecycle: PASS')
