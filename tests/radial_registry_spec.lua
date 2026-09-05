local scriptPath = arg[1] or 'imports/radial/client.lua'

local invoking = nil
local callbacks, events, messages = {}, {}, {}
local generation, activeSession = 0, nil
local focusSucceeds = true

function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return invoking end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function AddEventHandler(name, callback) events[name] = callback end
function SendNUIMessage(message) messages[#messages + 1] = message end
function IsPauseMenuActive() return false end
function SetCursorLocation() end
function CreateThread() end
function DisablePlayerFiring() end
function DisableControlAction() end
function PlayerId() return 1 end
function Wait() end
function SetNuiFocus() end

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
local selected = 0
local hostileError = setmetatable({}, { __tostring = function() error('hostile tostring') end })

invoking = 'owner-a'
api.addRadialItem({
    id = 'leaf-a', label = 'A', iconColor = 'var(--state-focus)', keepOpen = true,
    onSelect = function() selected = selected + 1 end,
})
local invalidColor = pcall(api.addRadialItem, { id = 'bad-color', label = 'Bad', iconColor = 'red;position:fixed' })
assert(invalidColor == false, 'radial icon colors must reject arbitrary CSS')
local invalidAppearance, invalidAppearanceError = api.registerRadial({ id = 'bad-appearance', appearance = 'unknown', items = {} })
assert(invalidAppearance == false and invalidAppearanceError == 'invalid_appearance',
    'radial menus must reject unsupported nonnil appearances')
api.registerRadial({ id = 'sub', items = { { id = 'sub-leaf', label = 'Sub', keepOpen = true } } })
api.addRadialItem({ id = 'to-sub', label = 'Submenu', menu = 'sub' })
api.addRadialItem({ id = 'hostile', label = 'Hostile', keepOpen = true,
    onSelect = function() error(hostileError, 0) end })

invoking = 'owner-b'
api.addRadialItem({ id = 'leaf-b', label = 'B' })
local collision, collisionError = api.addRadialItem({ id = 'leaf-a', label = 'Collision' })
assert(collision == false and collisionError == 'owned_by_other_resource', 'root item IDs must be owner scoped')

invoking = 'owner-a'
assert(api.showRadial())
local session = messages[#messages].data.session
assert(messages[#messages].data.items[1].iconColor == 'var(--state-focus)',
    'safe radial icon colors must be forwarded to NUI')

invoking = 'owner-b'
assert(api.hideRadial() == false and api.isRadialOpen(), 'unrelated owners must not hide the active radial')
local disableOk, disableError = api.disableRadial('false')
assert(disableOk == false and disableError == 'invalid_state' and api.isRadialOpen(),
    'disableRadial must reject non-boolean state')
api.disableRadial(true)
assert(not api.isRadialOpen() and api.isRadialDisabled(), 'any owner inhibitor must close and globally disable the shared radial')

invoking = 'owner-a'
assert(api.showRadial() == false, 'a different owner must remain blocked by the global inhibitor')
events.onResourceStop('owner-b')
assert(not api.isRadialDisabled(), 'a stopped owner must release its radial inhibitor')

assert(api.showRadial())
session = messages[#messages].data.session
local response
callbacks.radialClick({ index = 0, itemId = 'wrong', menuId = nil, session = session }, function(value) response = value end)
assert(response and response.ok == false and selected == 0, 'shifted/stale radial item IDs must be rejected')
callbacks.radialClick({ index = 0, itemId = 'leaf-a', menuId = nil, session = session }, function(value) response = value end)
assert(response and response.ok == true and selected == 1, 'the exact rendered radial item must execute')
local hostileReplies = 0
callbacks.radialClick({ index = 2, itemId = 'hostile', menuId = nil, session = session }, function(value)
    response = value; hostileReplies = hostileReplies + 1
end)
assert(hostileReplies == 1 and response.ok == false and response.error == 'handler_error',
    'hostile error tostring handlers must still receive exactly one radial callback reply')

callbacks.radialClick({ index = 1, itemId = 'to-sub', menuId = nil, session = session }, function(value) response = value end)
assert(response and response.ok == true, 'root submenu transition must succeed')
callbacks.radialBack({ menuId = nil, session = session }, function(value) response = value end)
assert(response and response.ok == false and api.getCurrentRadialId() == 'sub',
    'queued same-session events from the prior radial menu must be rejected')
callbacks.radialBack({ menuId = 'sub', session = session }, function(value) response = value end)
assert(response and response.ok == true, 'submenu back must succeed')
local transition = messages[#messages]
assert(transition.action == 'radialTransitionIn' and transition.data.menuId == nil,
    'root sentinel must return to the shared root instead of a fake menu ID')

api.hideRadial(true)
focusSucceeds = false
assert(api.showRadial() == false and activeSession == nil, 'radial focus failure must release the modal session')

print('radial registry lifecycle: PASS')
