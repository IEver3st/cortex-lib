-- A stale or edited stored value in a registered tab (an option the tab no longer offers, a slider
-- value outside its range) loads as the default, so it is not sent back with every Save and does not
-- get the whole batch rejected.
local kvp, nui, sent = {
    ['cortex-test:mode'] = 'retired',
    ['cortex-test:level'] = '150',
    ['cortex-test:enabled'] = 'false',
}, {}, {}
function GetNumResources() return 0 end
function GetResourceByFindIndex() return nil end
function GetResourceState() return 'missing' end
function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return nil end
function GetResourceKvpString(key) return kvp[key] end
function SetResourceKvp(key, value) kvp[key] = value end
function DeleteResourceKvp(key) kvp[key] = nil end
function SetTimeout() end
function SetNuiFocus() end
function SendNUIMessage(message) sent[#sent + 1] = message end
function RegisterNUICallback(name, callback) nui[name] = callback end
function AddEventHandler() end
function RegisterCommand() end
function GetSoundId() return 1 end
function PlaySoundFrontend() end
function ReleaseSoundId() end
function TriggerEvent() end
exports = setmetatable({}, { __call = function() end })
lib = {}

local api = assert(dofile(arg[1] or 'imports/settings/client.lua'))
assert(api.registerSettings('test', 'Test', 'cortex-test:', {
    { key = 'mode', type = 'select', label = 'Mode', options = { { value = 'a', label = 'A' }, { value = 'b', label = 'B' } } },
    { key = 'level', type = 'slider', label = 'Level', min = 0, max = 100 },
    { key = 'enabled', type = 'toggle', label = 'Enabled' },
}, { mode = 'a', level = 80, enabled = true }))

assert(api.getSetting('mode') == 'a', 'a retired option loads as the default')
assert(api.getSetting('level') == 80, 'an out-of-range slider value loads as the default')
assert(api.getSetting('enabled') == false, 'a valid stored value is kept')

local function call(name, data)
    local reply
    nui[name](data or {}, function(payload) reply = payload end)
    return reply
end

api.openSettings()
local open = sent[#sent]
assert(open.action == 'settingsOpen')
local values = {}
for _, tab in ipairs(open.data.tabs) do
    values[tab.id] = {}
    for _, field in ipairs(tab.fields or {}) do
        if tab.values and tab.values[field.key] ~= nil then values[tab.id][field.key] = tab.values[field.key] end
    end
end
values.test.enabled = true
local reply = call('settingsSave', { tabs = values, session = open.data.session, keepOpen = true })
assert(reply.ok == true, 'Save of every tab as the NUI sends it succeeds: ' .. tostring(reply.error))
assert(kvp['cortex-test:enabled'] == 'true', 'the change is persisted')
values.test.mode = 'forged'
reply = call('settingsSave', { tabs = values, session = open.data.session, keepOpen = true })
assert(reply.ok == false and reply.error == 'invalid_settings', 'a changed invalid value is still rejected')

print('settings stale stored values: PASS')
