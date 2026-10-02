-- Cortex tab: built-in player preferences, the retired Dynamic UI migration and
-- the cortex:prefs push. Stubbed natives only; no FiveM or CEF is executed.
local kvp = {
    -- A player who used the retired Dynamic UI tab.
    ['cortex:cortex-dynamic:dynamic_accent'] = '#bea9de',
    ['cortex:cortex-dynamic:dynamic_opacity'] = '80',
    ['cortex:cortex-dynamic:dynamic_layout'] = 'false',
    ['cortex:cortex-dynamic:dynamic_independent_cortex-chat'] = 'true',
    ['cortex:cortex-dynamic:dynamic_independent_opticom'] = 'false',
    -- Already in the new namespace: the new value wins over the legacy copy.
    ['cortex:dynamic_motion'] = 'full',
    ['cortex:cortex-dynamic:dynamic_motion'] = 'reduced',
    -- Tampered or stale values fall back to their defaults.
    ['cortex:textSize'] = 'enormous',
    ['cortex:uiScale'] = '400',
    ['cortex:notifyLimit'] = '5',
}
local callbacks, events, messages, changes = {}, {}, {}, {}
local invoking = nil
local focused = false

function GetNumResources() return 0 end
function GetResourceByFindIndex() return nil end
function GetResourceState() return 'started' end
function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return invoking end
function GetResourceKvpString(key) return kvp[key] end
function SetResourceKvp(key, value) kvp[key] = value end
function DeleteResourceKvp(key) kvp[key] = nil end
function SetTimeout() end
function SetNuiFocus(value) focused = value end
function SendNUIMessage(message) messages[#messages + 1] = message end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function AddEventHandler(name, callback) events[name] = callback end
function RegisterCommand() end
function GetSoundId() return 1 end
function PlaySoundFrontend() end
function ReleaseSoundId() end
function TriggerEvent(name, key, value, tabId)
    if name == 'cortex-lib:settingChanged' then changes[#changes + 1] = { key = key, value = value, tabId = tabId } end
end
exports = setmetatable({}, { __call = function() end })
lib = {}

local api = assert(dofile('imports/settings/client.lua'))

local function call(name, data)
    local reply, count = nil, 0
    callbacks[name](data or {}, function(payload) count = count + 1; reply = payload end)
    assert(count == 1, name .. ' must reply exactly once')
    return reply
end
local function lastPrefs()
    for index = #messages, 1, -1 do
        if messages[index].action == 'cortex:prefs' then return messages[index].data.prefs, index end
    end
end

-- Migration: four kept keys move once; independent switches are deleted.
assert(api.getSetting('dynamic_accent') == '#bea9de' and kvp['cortex:dynamic_accent'] == '#bea9de')
assert(api.getSetting('dynamic_opacity') == 80 and api.getSetting('dynamic_layout') == false)
assert(api.getSetting('dynamic_motion') == 'full', 'an existing Cortex value is not overwritten by the legacy copy')
for key in pairs(kvp) do
    assert(not key:find('cortex-dynamic:', 1, true), 'legacy Dynamic UI keys are removed after migration: ' .. key)
end
assert(api.getSetting('textSize') == 'standard' and api.getSetting('uiScale') == 100,
    'stored values outside their field fall back to defaults')
assert(api.getSetting('notifyLimit') == 5 and math.type(api.getSetting('notifyLimit')) == 'integer')

-- Every built-in key is readable, with its documented default.
local expected = {
    uiScale = 100, textSize = 'standard', controlHints = true, notifyPosition = 'top-right',
    notifyDuration = 'standard', notifyLimit = 5, notifySound = true, notifySoundPreset = 'mp_idle_kick',
    promptMarkers = true, promptScale = 'standard', invertScroll = false, showPercent = true,
}
for key, value in pairs(expected) do
    assert(api.getSetting(key) == value, key .. ' default')
end

-- Ready handshake pushes the current prefs (and notification position).
assert(call('cortexPrefsReady').ok == true)
local prefs = lastPrefs()
assert(prefs.scale == 1 and prefs.textSize == 'standard' and prefs.notifyDuration == 1 and prefs.notifyLimit == 5)
assert(prefs.showPercent == true and prefs.promptMarkers == true and prefs.promptScale == 'standard')
assert(prefs.controlHints == true and prefs.invertScroll == false)
assert(messages[#messages].action == 'notifySetPosition' and messages[#messages].data.position == 'top-right')

-- One Cortex tab, sectioned, and no Dynamic UI tab.
api.openSettings()
local open = messages[#messages]
assert(open.action == 'settingsOpen' and #open.data.tabs == 1 and open.data.tabs[1].id == 'cortex')
local sections, keys = {}, {}
for _, field in ipairs(open.data.tabs[1].fields) do
    sections[field.section] = true
    keys[#keys + 1] = field.key
    assert(open.data.tabs[1].defaults[field.key] ~= nil, field.key .. ' has a default for per-row reset')
end
assert(sections.Interface and sections.Notifications and sections.Prompts and sections.Progress)
assert(#keys == 16, 'the Cortex tab lists exactly the built-in preferences')
assert(call('settingsReady', { session = open.data.session }).ok)

-- Preview pushes prefs live and emits settingChanged; Cancel rolls both back.
local before = #messages
assert(call('settingsPreview', { tabId = 'cortex', key = 'uiScale', value = 120 }).ok)
prefs = lastPrefs()
assert(#messages > before and prefs.scale == 1.2, 'preview pushes the new scale')
assert(changes[#changes].key == 'uiScale' and changes[#changes].value == 120 and changes[#changes].tabId == 'cortex')
assert(call('settingsPreview', { tabId = 'cortex', key = 'notifyDuration', value = 'long' }).ok)
assert(lastPrefs().notifyDuration == 1.5)
assert(call('settingsPreview', { tabId = 'cortex', key = 'invertScroll', value = true }).ok)
assert(changes[#changes].key == 'invertScroll' and changes[#changes].value == true, 'renderer-facing keys emit settingChanged')
assert(not call('settingsPreview', { tabId = 'cortex', key = 'uiScale', value = 200 }).ok, 'out-of-range scale rejected')
assert(not call('settingsPreview', { tabId = 'cortex', key = 'notifyLimit', value = 4 }).ok, 'unlisted limit rejected')
assert(not call('settingsPreview', { tabId = 'cortex', key = 'promptScale', value = 'huge' }).ok)
for _, bad in ipairs({ 'red', '#ff00', '#ff00000', '#gg0000', 'ff0000', 16711680 }) do
    assert(not call('settingsPreview', { tabId = 'cortex', key = 'dynamic_accent', value = bad }).ok,
        'accent is an offered colour or a six-digit hex')
end
assert(kvp['cortex:uiScale'] == '400', 'preview never persists')
local messagesBeforeAccent = #messages
assert(call('settingsPreview', { tabId = 'cortex', key = 'dynamic_accent', value = '#9bbcd3' }).ok)
assert(call('settingsPreview', { tabId = 'cortex', key = 'dynamic_accent', value = '#FF5A36' }).ok, 'a custom hex accent is accepted')
assert(api.getSetting('dynamic_accent') == '#ff5a36', 'and stored lowercase')
assert(#messages == messagesBeforeAccent, 'appearance keys travel through the presentation profile, not prefs')
assert(call('settingsCancel', { session = open.data.session }).ok)
prefs = lastPrefs()
assert(prefs.scale == 1 and prefs.notifyDuration == 1 and prefs.invertScroll == false, 'Cancel pushes the rolled-back prefs')
assert(api.getSetting('uiScale') == 100 and api.getSetting('dynamic_accent') == '#bea9de')
assert(not focused)

-- Save persists under cortex:<key>; the NUI already shows the previewed value.
api.openSettings()
local session = messages[#messages].data.session
assert(call('settingsReady', { session = session }).ok)
assert(call('settingsPreview', { tabId = 'cortex', key = 'textSize', value = 'large' }).ok)
assert(lastPrefs().textSize == 'large')
assert(call('settingsSave', { session = session, tabs = { cortex = { textSize = 'large', notifyLimit = 8, showPercent = false } } }).ok)
assert(kvp['cortex:textSize'] == 'large' and kvp['cortex:notifyLimit'] == '8' and kvp['cortex:showPercent'] == 'false')
prefs = lastPrefs()
assert(prefs.textSize == 'large' and prefs.notifyLimit == 8 and prefs.showPercent == false)

-- Code-driven changes (lib.setSetting) push too.
assert(api.setSetting('promptScale', 'large'))
assert(lastPrefs().promptScale == 'large' and kvp['cortex:promptScale'] == 'large')

-- A consumer that declares its own key with a built-in name keeps its value.
invoking = 'hud'
assert(api.registerSettings('hud', 'HUD', nil, { { key = 'showPercent', type = 'toggle', label = 'Percent' } },
    { showPercent = true }))
assert(api.getSetting('showPercent') == true, 'owner tab value shadows the built-in for its owner')
invoking = 'other'
assert(api.getSetting('showPercent') == false, 'other resources read the Cortex preference')
invoking = nil
assert(api.getSetting('showPercent') == false)

print('settings prefs, sections and Dynamic UI migration: PASS')
