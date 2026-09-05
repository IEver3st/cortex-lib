local scriptPath = arg[1] or 'imports/settings/client.lua'

local kvp = {}
local nuiCallbacks = {}
local eventHandlers = {}
local sentMessages = {}
local emittedChanges = {}
local registeredExports = {}
local focusState = false
local timeouts = {}
local failWriteAt = nil
local writeAttempts = 0

function GetNumResources() return 0 end
function GetResourceByFindIndex() return nil end
function GetResourceState() return 'missing' end
function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return nil end
function GetResourceKvpString(key) return kvp[key] end
function SetResourceKvp(key, value)
    writeAttempts = writeAttempts + 1
    if failWriteAt and writeAttempts == failWriteAt then
        failWriteAt = nil
        error('simulated KVP write failure')
    end
    kvp[key] = value
end
function DeleteResourceKvp(key) kvp[key] = nil end
function SetTimeout(delay, callback) timeouts[#timeouts + 1] = { delay = delay, callback = callback } end
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
assert(callNui('settingsReady').ok == true and focusState, 'settingsReady must focus the exact active session')

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
assert(callNui('settingsReady').ok == true)
callNui('settingsPreview', { tabId = 'hud', key = 'hud_enabled', value = false })
local batchReply = callNui('settingsPreview', {
    tabId = 'hud',
    values = { hud_strength = 75 },
})
assert(batchReply.ok == true and api.getSetting('hud_strength') == 75, 'Reset-style preview batches must apply live')
local invalidReply = callNui('settingsPreview', { tabId = 'hud', key = 'hud_strength', value = 101 })
assert(invalidReply.ok == false, 'out-of-range slider previews must be rejected')
assert(api.getSetting('hud_strength') == 75, 'invalid previews must not mutate runtime state')

local invalidSaveReply = callNui('settingsSave', {
    tabs = { hud = { hud_enabled = 'forged' }, unknown = { value = true } },
})
assert(invalidSaveReply.ok == false and invalidSaveReply.error == 'invalid_settings',
    'Save must reject an invalid batch atomically')
assert(api.getSetting('hud_enabled') == false and kvp['cortex:hud:hud_enabled'] == nil,
    'invalid Save must retain preview state without partially persisting')

kvp['cortex:hud:hud_enabled'] = 'true'
kvp['cortex:hud:hud_strength'] = '50'
writeAttempts = 0
failWriteAt = 2
local messagesBeforeFailedSave = #sentMessages
local failedSaveReply = callNui('settingsSave', {
    tabs = { hud = { hud_enabled = false, hud_strength = 25 } },
})
assert(failedSaveReply.ok == false and failedSaveReply.error == 'commit_failed'
    and failedSaveReply.persistedRestored == true,
    'a mid-commit KVP failure must report failure only after restoring persisted originals')
assert(kvp['cortex:hud:hud_enabled'] == 'true' and kvp['cortex:hud:hud_strength'] == '50',
    'a partial KVP commit must restore every original persisted value')
assert(api.getSetting('hud_enabled') == true and api.getSetting('hud_strength') == 50,
    'a failed commit must roll runtime preview values back to the opening snapshot')
assert(focusState == true and #sentMessages == messagesBeforeFailedSave,
    'a failed commit must keep focus and must not force-close the active settings session')
local retryPreviewReply = callNui('settingsPreview', {
    tabId = 'hud',
    key = 'hud_enabled',
    value = false,
})
assert(retryPreviewReply.ok == true and api.getSetting('hud_enabled') == false,
    'a failed commit must leave a fresh preview snapshot so the active panel can retry')
assert(callNui('settingsCancel').ok == true and focusState == false,
    'the retained settings session must still cancel and release focus cleanly')

api.openSettings()
assert(callNui('settingsReady').ok == true)
callNui('settingsPreview', { tabId = 'hud', key = 'hud_enabled', value = false })
callNui('settingsPreview', { tabId = 'hud', key = 'hud_strength', value = 75 })

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
assert(kvp['cortex:hud:hud_enabled'] == 'false', 'Save must persist boolean values in the tab namespace')
assert(kvp['cortex:hud:hud_strength'] == '25', 'Save must persist numeric values in the tab namespace')
assert(kvp['cortex:hud_enabled'] == nil, 'Save must not mirror consumer values into the legacy global namespace')
assert(focusState == false, 'Save must release NUI focus')

assert(type(eventHandlers.onResourceStop) == 'function', 'resource-stop cleanup must be registered')
eventHandlers.onResourceStop('hud')
api.openSettings()
assert(#sentMessages[#sentMessages].data.tabs == 1, 'stopped resources must be removed from the settings tabs')
callNui('settingsCancel')

api.openSettings()
local watchdog = timeouts[#timeouts]
assert(watchdog and watchdog.delay == 10000, 'settings open must arm a bounded settingsReady watchdog')
watchdog.callback()
assert(sentMessages[#sentMessages].action == 'settingsClose'
    and sentMessages[#sentMessages].data.reason == 'settings_ready_timeout',
    'a missing settingsReady acknowledgement must close and release the modal session')

print('settings live preview runtime: PASS')
