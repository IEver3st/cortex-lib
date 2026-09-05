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

focusSucceeds = false
assert(api.showMenu('main') == false and activeSession == nil, 'focus failure must release the modal session')

print('menu lifecycle: PASS')
