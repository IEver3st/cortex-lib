local scriptPath = arg[1] or 'client/utils.lua'

local invoking = nil
local callbacks, events, messages = {}, {}, {}
local focusState = false
local exists = { [1] = true, [2] = true, [10] = true, [11] = true, [12] = true }
local deleted = {}

function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return invoking end
function PlayerPedId() return 1 end
function PlayerId() return 1 end
function GetEntityCoords() return { x = 0, y = 0, z = 0 } end
function GetEntityHeading() return 0 end
function DoesEntityExist(entity) return exists[entity] == true end
function DeleteEntity(entity) deleted[entity] = true; exists[entity] = false end
function SetEntityAsMissionEntity() end
function GetGamePool(name) return name == 'CVehicle' and { 10, 11, 12 } or {} end
function IsEntityDead() return false end
function GetEntityHealth() return 200 end
function GetEntityModel() return 1 end
function GetVehiclePedIsIn(ped) return ped == 1 and 10 or 0 end
function GetVehicleMaxNumberOfPassengers() return 1 end
function GetPedInVehicleSeat(vehicle, seat) return vehicle == 11 and seat == 0 and 2 or 0 end
function IsPedAPlayer(ped) return ped == 1 or ped == 2 end
function NetworkGetEntityIsNetworked() return false end
function NetworkHasControlOfEntity() return true end
function SendNUIMessage(message) messages[#messages + 1] = message end
function SetNuiFocus(focus) focusState = focus == true end
function SetNuiFocusKeepInput() end
function IsNuiFocused() return false end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function AddEventHandler(name, callback) events[name] = callback end
function GetGameplayCamRot() return { x = 0, y = 0, z = 0 } end
function vector3(x, y, z) return { x = x, y = y, z = z } end

exports = function() end
lib = {}
local api = assert(dofile(scriptPath))
local hostileError = setmetatable({}, { __tostring = function() error('hostile tostring') end })

api.cache = { ped = 99 }
assert(api.getPed() == 1, 'getPed must reject a stale cached entity and refresh from PlayerPedId')
assert(api.isInVehicle('yes') == false and api.getCurrentVehicle(1) == nil,
    'vehicle helpers must reject non-boolean includeLastVehicle values')
exists[1] = false
assert(api.getPed() == nil and api.getCoords() == nil and api.getHeading() == nil
    and api.isInVehicle() == false and api.getCurrentVehicle() == nil,
    'ped-dependent helpers must fail safely when no current ped exists')
exists[1] = true

local removed = api.clearPool('CVehicle', { x = 0, y = 0, z = 0 }, 10)
assert(removed == 1 and deleted[12] and not deleted[10] and not deleted[11],
    'clearPool must exclude the local and every player-occupied vehicle')

local before = #messages
local ok, err = api.copyToClipboard({ unsafe = true })
assert(ok == false and err == 'invalid_text' and #messages == before, 'clipboard must reject unsupported values')
ok = api.copyToClipboard(string.rep('x', 16385))
assert(ok == false and #messages == before, 'clipboard must reject oversized values')
assert(api.copyToClipboard(42) == true and messages[#messages].data.text == '42', 'clipboard must accept bounded numbers')

invoking = 'owner-a'
ok, err = api.registerUiApp('unknownRenderer', function() end)
assert(ok == false and err == 'unsupported_app', 'UI apps must be restricted to bundled renderers')

local circular = {}
circular.self = circular
assert(api.registerUiApp('weatherzonesEditor', function() return circular end))
assert(api.openUiApp('weatherzonesEditor', { zone = 'safe' }) == true and focusState,
    'successful UI-app open must focus the modal and return true')
local session = messages[#messages].data.session
assert(api.updateUiApp('weatherzonesEditor', { zone = 'updated' }) == true,
    'successful UI-app update must return true')
local response, replies = nil, 0
callbacks['cortex:uiEvent']({
    appId = 'weatherzonesEditor', type = 'save', payload = {}, session = session,
}, function(value) response = value; replies = replies + 1 end)
assert(replies == 1 and response.ok == false and response.error == 'invalid_handler_result',
    'circular handler results must receive one structured serialization error')

assert(api.registerUiApp('weatherzonesEditor', function() return { constructor = 'unsafe' } end))
assert(messages[#messages].action == 'uiAppClose' and messages[#messages].data.reason == 're_registered',
    're-registering an open UI app must close the prior session before replacing its handler')
local outboundBefore = #messages
ok, err = api.openUiApp('weatherzonesEditor', { constructor = 'unsafe' })
assert(ok == false and err == 'invalid_payload' and #messages == outboundBefore,
    'UI-app payloads must reject reserved JavaScript object keys')
ok, err = api.openUiApp('weatherzonesEditor', { zone = 'line\nbreak' })
assert(ok == false and err == 'invalid_payload', 'UI-app payloads must reject control characters')

local originalFocus = api._focusModal
api._focusModal = function() return false end
ok, err = api.openUiApp('weatherzonesEditor', { zone = 'safe' })
assert(ok == false and err == 'focus_failed' and messages[#messages].action == 'uiAppClose'
    and messages[#messages].data.reason == 'focus_failed',
    'UI-app focus failure must close the emitted session and release its modal state')
api._focusModal = originalFocus

assert(api.openUiApp('weatherzonesEditor', { zone = 'safe' }) == true)
session = messages[#messages].data.session
callbacks['cortex:uiEvent']({
    appId = 'weatherzonesEditor', type = 'save', payload = {}, session = session,
}, function(value) response = value end)
assert(response.ok == false and response.error == 'invalid_handler_result',
    'handler results must reject reserved JavaScript object keys')
assert(api.registerUiApp('weatherzonesEditor', function() error(hostileError, 0) end))
assert(api.openUiApp('weatherzonesEditor', { zone = 'safe' }) == true)
session = messages[#messages].data.session
replies = 0
callbacks['cortex:uiEvent']({
    appId = 'weatherzonesEditor', type = 'save', payload = {}, session = session,
}, function(value) response = value; replies = replies + 1 end)
assert(replies == 1 and response.ok == false and response.error == 'handler_error',
    'hostile UI-app error tostring handlers must still receive exactly one callback reply')
assert(api.closeUiApp('weatherzonesEditor') == true, 'successful UI-app close must return true')
assert(api.unregisterUiApp('weatherzonesEditor'))
events.onResourceStop('owner-a')

print('shared lifecycle utilities: PASS')
