local scriptPath = arg[1] or 'client/debug_panel.lua'

local invoking = nil
local messages, events = {}, {}
function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return invoking end
function SendNUIMessage(message) messages[#messages + 1] = message end
function AddEventHandler(name, callback) events[name] = callback end
exports = function() end
lib = {}

local api = assert(dofile(scriptPath))
local source = {
    title = 'Debug', position = 'top-right', ignored = function() end,
    lines = { { label = 'State', value = { ok = true }, ignored = function() end } },
    data = { count = 1 },
}

invoking = 'owner-a'
assert(api.showDebugPanel(source))
local shown = messages[#messages]
assert(shown.data.ignored == nil and shown.data.lines[1].ignored == nil,
    'debug panel must emit only its supported serializable shape')
source.lines[1].value.ok = false
assert(shown.data.lines[1].value.ok == true, 'debug panel must snapshot nested payload data')

local cycle = {}
cycle.self = cycle
local before = #messages
local ok, err = api.updateDebugPanel({ data = cycle })
assert(ok == false and err == 'invalid_payload' and #messages == before,
    'debug panel must reject cyclic update data without sending it')
ok, err = api.updateDebugPanel({ accentColor = 'red; position: fixed' })
assert(ok == false and err == 'invalid_payload' and #messages == before,
    'debug panel must reject arbitrary CSS in color fields')
assert(api.updateDebugPanel({ accentColor = 'var(--state-focus)', lines = { { label = 'OK', color = '#0f08' } } }),
    'debug panel must allow bounded CSS variables and hex colors')

invoking = 'owner-b'
ok, err = api.updateDebugPanel({ title = 'Hijack' })
assert(ok == false and err == 'not_owner', 'an unrelated owner must not update the active debug panel')
assert(api.hideDebugPanel() == false, 'an unrelated owner must not hide the active debug panel')

events.onResourceStop('owner-a')
assert(not api.isDebugPanelOpen() and messages[#messages].action == 'debugPanelHide',
    'consumer stop must hide and release its debug panel')

print('debug panel lifecycle: PASS')
