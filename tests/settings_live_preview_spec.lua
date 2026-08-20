local scriptPath = arg[1]
assert(type(scriptPath) == 'string' and scriptPath ~= '', 'settings client path is required')

local kvp = {}
local nuiCallbacks = {}
local eventHandlers = {}
local sentMessages = {}
local emittedChanges = {}
local registeredExports = {}
local focusState = false

function GetNumResources() return 0 end
function GetResourceByFindIndex() return nil end
function GetResourceState() return 'missing' end
function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return nil end
function GetResourceKvpString(key) return kvp[key] end
function SetResourceKvp(key, value) kvp[key] = value end
function SetNuiFocus(hasFocus) focusState = hasFocus == true end
function SendNUIMessage(message) sentMessages[#sentMessages + 1] = message end
function RegisterNUICallback(name, callback) nuiCallbacks[name] = callback end
function AddEventHandler(name, callback) eventHandlers[name] = callback end
function RegisterCommand() end
function GetSoundId() return 1 end
function PlaySoundFrontend() end
function ReleaseSoundId() end
function TriggerEvent(name, key, value, tabId)
    if name == 'cortex-lib:settingChanged' then
        emittedChanges[#emittedChanges + 1] = { key = key, value = value, tabId = tabId }
    end
end

exports = setmetatable({}, {
    __call = function(_, name, callback)
        registeredExports[name] = callback
    end,
})

lib = {}

local api = assert(dofile(scriptPath))
assert(type(api) == 'table', 'settings client must return its public API')

assert(api.registerSettings('hud', 'HUD', nil, {
    { key = 'hud_enabled', label = 'Enabled', type = 'toggle' },
    { key = 'hud_strength', label = 'Strength', type = 'slider', min = 0, max = 100 },
}, {
    hud_enabled = true,
    hud_strength = 50,
}))

local function callNui(name, data)
    local response = nil
    assert(type(nuiCallbacks[name]) == 'function', name .. ' callback must be registered')
    nuiCallbacks[name](data or {}, function(payload)
        assert(response == nil, name .. ' callback must reply exactly once')
        response = payload
    end)
    assert(response ~= nil, name .. ' callback must reply')
    return response
end

api.openSettings()
assert(sentMessages[#sentMessages].action == 'settingsOpen', 'open must send settingsOpen')
assert(#sentMessages[#sentMessages].data.tabs == 2, 'open must include library and HUD tabs')

local previewReply = callNui('settingsPreview', {
    tabId = 'hud',
    key = 'hud_enabled',
    value = false,
})
assert(previewReply.ok == true, 'false toggle previews must be accepted')
assert(api.getSetting('hud_enabled') == false, 'preview must update runtime reads immediately')
assert(kvp['cortex:hud_enabled'] == nil, 'preview must not persist before Save')
assert(emittedChanges[#emittedChanges].value == false, 'preview must notify resource listeners')
local emittedAfterFirstPreview = #emittedChanges
local repeatedReply = callNui('settingsPreview', {
    tabId = 'hud',
    key = 'hud_enabled',
    value = false,
})
assert(repeatedReply.ok == true, 'repeated valid previews must remain idempotent')
assert(#emittedChanges == emittedAfterFirstPreview, 'repeated previews must not emit duplicate changes')
local unknownReply = callNui('settingsPreview', {
    tabId = 'hud',
    key = 'unknown_setting',
    value = true,
})
assert(unknownReply.ok == false, 'unknown settings must be rejected')

local cancelReply = callNui('settingsCancel')
assert(cancelReply.ok == true, 'Cancel must succeed')
assert(api.getSetting('hud_enabled') == true, 'Cancel must restore the pre-open runtime value')
assert(kvp['cortex:hud_enabled'] == nil, 'Cancel must not write preview values')
assert(focusState == false, 'Cancel must release NUI focus')

api.openSettings()
callNui('settingsPreview', { tabId = 'hud', key = 'hud_enabled', value = false })
local batchReply = callNui('settingsPreview', {
    tabId = 'hud',
    values = { hud_strength = 75 },
})
assert(batchReply.ok == true and api.getSetting('hud_strength') == 75, 'Reset-style preview batches must apply live')
local invalidReply = callNui('settingsPreview', { tabId = 'hud', key = 'hud_strength', value = 101 })
assert(invalidReply.ok == false, 'out-of-range slider previews must be rejected')
assert(api.getSetting('hud_strength') == 75, 'invalid previews must not mutate runtime state')

local saveReply = callNui('settingsSave', {
    tabs = {
        hud = {
            hud_enabled = false,
            hud_strength = 25,
        },
    },
})
assert(saveReply.ok == true, 'Save must succeed')
assert(saveReply.committed == 2, 'Save must report committed values')
assert(api.getSetting('hud_enabled') == false, 'Save must keep the previewed runtime value')
assert(api.getSetting('hud_strength') == 25, 'Save must apply the final submitted slider value')
assert(kvp['cortex:hud_enabled'] == 'false', 'Save must persist boolean values')
assert(kvp['cortex:hud_strength'] == '25', 'Save must persist numeric values')
assert(focusState == false, 'Save must release NUI focus')

assert(type(eventHandlers.onResourceStop) == 'function', 'resource-stop cleanup must be registered')
eventHandlers.onResourceStop('hud')
api.openSettings()
assert(#sentMessages[#sentMessages].data.tabs == 1, 'stopped resources must be removed from the settings tabs')
callNui('settingsCancel')

print('settings live preview runtime: PASS')
