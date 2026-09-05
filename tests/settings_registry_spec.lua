local scriptPath = arg[1] or 'imports/settings/client.lua'

local invokingResource = nil
local resourceScans = 0
local kvp = {
    ['cortex:shared'] = 'true',
    ['cortex:notifyPosition'] = 'top-left',
}
local callbacks = {}
local events = {}
local messages = {}
local emitted = {}
local settingsActions = {}
local discoveryAttempts = 0
local hostileDiscoveryAttempts = 0
local discoveredNames = { 'hostile-resource', 'healthy-resource', 'retry-resource' }
local hostileDiscoveryError = setmetatable({}, {
    __tostring = function() error('secondary tostring failure') end,
})

function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return invokingResource end
function GetNumResources() resourceScans = resourceScans + 1; return #discoveredNames end
function GetResourceByFindIndex(index) return discoveredNames[index + 1] end
function GetResourceState(name)
    return (name == 'hostile-resource' or name == 'healthy-resource' or name == 'retry-resource') and 'started' or 'missing'
end
function GetResourceKvpString(key) return kvp[key] end
function SetResourceKvp(key, value) kvp[key] = value end
function DeleteResourceKvp(key) kvp[key] = nil end
function SetNuiFocus() end
function SendNUIMessage(message) messages[#messages + 1] = message end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function AddEventHandler(name, callback) events[name] = callback end
function RegisterCommand() end
function GetSoundId() return 1 end
function PlaySoundFrontend() end
function ReleaseSoundId() end
function TriggerEvent(name, key, value, tabId)
    if name == 'cortex-lib:settingChanged' then
        emitted[#emitted + 1] = { key = key, value = value, tabId = tabId }
    elseif name == 'cortex-lib:settingsAction' then
        settingsActions[#settingsActions + 1] = { tabId = key, action = value, fieldKey = tabId }
    end
end

exports = setmetatable({}, {
    __call = function() end,
    __index = function(_, resourceName)
        if resourceName == 'hostile-resource' then
            return {
                getSettingsDefinition = function()
                    hostileDiscoveryAttempts = hostileDiscoveryAttempts + 1
                    error(hostileDiscoveryError)
                end,
            }
        end
        if resourceName == 'healthy-resource' then
            return {
                getSettingsDefinition = function()
                    return {
                        label = 'Healthy',
                        settings = { { key = 'healthy_enabled', label = 'Healthy', type = 'toggle', default = true } },
                        sections = {},
                    }
                end,
            }
        end
        if resourceName ~= 'retry-resource' then return nil end
        return {
            getSettingsDefinition = function()
                discoveryAttempts = discoveryAttempts + 1
                if discoveryAttempts == 1 then error('temporary export failure') end
                return {
                    label = 'Retry',
                    settings = { { key = 'retry_enabled', label = 'Retry', type = 'toggle', default = true } },
                    sections = {},
                }
            end,
        }
    end,
})
lib = {}

local api = assert(dofile(scriptPath))
local poison = function() end
local field = { key = 'shared', label = 'Shared', type = 'toggle', poison = poison }
field.cycle = field
local fieldsA = { field, { key = 'unique_a', label = 'Unique A', type = 'toggle' } }
local fieldsB = { field }

invokingResource = 'owner-a'
local invalid, invalidError = api.registerSettings('__proto__', 'Unsafe', nil, {}, {})
assert(invalid == false, 'reserved tab IDs must be rejected')
invalid, invalidError = api.registerSettings('missing-default', 'Missing', nil, {
    { key = 'enabled', label = 'Enabled', type = 'toggle' },
}, {})
assert(invalid == false and invalidError == 'missing_default',
    'visible non-action fields must declare a validated default')
invalid, invalidError = api.registerSettings('bad-default', 'Bad', nil, {
    { key = 'level', label = 'Level', type = 'slider', min = 0, max = 10 },
}, { level = 99 })
assert(invalid == false and invalidError == 'invalid_default', 'out-of-range field defaults must be rejected')
invalid, invalidError = api.registerSettings('bad-options', 'Bad', nil, {
    { key = 'choice', label = 'Choice', type = 'select', options = { [1] = { value = 'a', label = 'A' }, [3] = { value = 'b', label = 'B' } } },
}, { choice = 'a' })
assert(invalid == false, 'sparse field options must reject registration instead of normalizing to empty')
invalid, invalidError = api.registerSettings('bad-key', 'Bad', nil, {
    { key = 'line\nbreak', label = 'Bad', type = 'toggle' },
}, { ['line\nbreak'] = true })
assert(invalid == false, 'control characters in field keys must be rejected')
local longDefault = string.rep('x', 2048)
assert(api.registerSettings('long-text', 'Long Text', nil, {
    { key = 'content', label = 'Content', type = 'text', maxLength = 4096 },
}, { content = longDefault }))
assert(api.getTabSetting('long-text', 'content') == longDefault,
    'text defaults must honor the same 4096-byte schema bound used by runtime validation')
assert(api.registerSettings('tab-a', 'Tab A', nil, fieldsA, { shared = false, unique_a = true }))
assert(kvp['cortex:tab-a:shared'] == 'true', 'the first unclaimed tab must migrate its legacy value')

invokingResource = 'owner-b'
assert(api.registerSettings('tab-b', 'Tab B', nil, fieldsB, { shared = false }))
assert(kvp['cortex:tab-b:shared'] == nil, 'a second owner must not migrate another tab\'s legacy value')
assert(api.getTabSetting('tab-b', 'shared') == false, 'the second owner must retain its own default')
assert(api.getSetting('unique_a') == nil and api.setSetting('unique_a', false) == false,
    'an external resource must not read or write another owner\'s unique setting')

local ownerACalls, ownerBCalls = 0, 0
invokingResource = 'owner-a'
assert(api.onSettingChange('shared', function(value, _, tabId)
    ownerACalls = ownerACalls + 1
    assert(value == false and tabId == 'tab-a')
end))
invokingResource = 'owner-b'
assert(api.onSettingChange('shared', function() ownerBCalls = ownerBCalls + 1 end))

invokingResource = 'owner-a'
assert(api.setSetting('shared', false))
assert(kvp['cortex:tab-a:shared'] == 'false', 'writes must use the owning tab namespace')
assert(kvp['cortex:shared'] == 'true', 'consumer writes must not mirror into the legacy global namespace')
assert(ownerACalls == 1 and ownerBCalls == 0, 'same-key listeners must be routed only to the changed tab owner')
assert(emitted[#emitted].tabId == 'tab-a', 'the public settingChanged event must include tabId')

local collisionOk, collisionError = api.registerSettings('builtin-collision', 'Collision', 'cortex:', {
    { key = 'notifyPosition', label = 'Position', type = 'text' },
}, { notifyPosition = 'overwrite' })
assert(collisionOk == false and collisionError == 'reserved_storage_key',
    'consumer settings must not claim a concrete built-in Cortex KVP key')

assert(api.registerSettings('builtin-name-custom-prefix', 'Independent Position', 'consumer:layout:', {
    { key = 'notifyPosition', label = 'Position', type = 'text' },
}, { notifyPosition = 'bottom-right' }))
assert(api.getTabSetting('builtin-name-custom-prefix', 'notifyPosition') == 'bottom-right'
    and kvp['consumer:layout:notifyPosition'] == nil,
    'a custom-prefix consumer field must not migrate a same-named built-in Cortex value')

assert(api.registerSettings('typed-actions', 'Typed Actions', 'consumer:actions:', {
    { key = 'choice', label = 'Choice', type = 'buttons', buttons = {
        { value = false, label = 'False' },
        { value = 1, label = 'One' },
    } },
}, {}), 'false and numeric settings button values must survive normalization')

collisionOk, collisionError = api.registerSettings('owner-collision', 'Collision', 'cortex:tab-a:', {
    { key = 'shared', label = 'Shared', type = 'toggle' },
}, { shared = true })
assert(collisionOk == false and collisionError == 'storage_key_collision',
    'a different tab must not claim an already registered concrete storage key')
assert(api.registerSettings('shared-prefix-ok', 'Shared Prefix', 'cortex:tab-a:', {
    { key = 'unique_b', label = 'Unique B', type = 'toggle' },
}, { unique_b = true }), 'noncolliding keys may intentionally share a custom prefix')

invokingResource = 'temporary-owner'
assert(api.registerSettings('temporary-tab', 'Temporary', 'custom:shared:', {
    { key = 'enabled', label = 'Enabled', type = 'toggle' },
}, { enabled = true }))
invokingResource = 'replacement-owner'
collisionOk, collisionError = api.registerSettings('replacement-tab', 'Replacement', 'custom:shared:', {
    { key = 'enabled', label = 'Enabled', type = 'toggle' },
}, { enabled = false })
assert(collisionOk == false and collisionError == 'storage_key_collision',
    'a concrete custom KVP key must remain reserved to its registered tab')
events.onResourceStop('temporary-owner')
assert(api.registerSettings('replacement-tab', 'Replacement', 'custom:shared:', {
    { key = 'enabled', label = 'Enabled', type = 'toggle' },
}, { enabled = false }), 'resource-stop cleanup must release concrete storage-key ownership')
invokingResource = 'owner-a'

local scansBeforeReads = resourceScans
for _ = 1, 20 do
    assert(api.getSetting('shared') == false)
    assert(api.getTabSetting('tab-a', 'shared') == false)
    assert(type(api.getAllSettings()) == 'table')
end
assert(resourceScans == scansBeforeReads, 'ordinary settings reads must not enumerate resources')

api.openSettings()
assert(resourceScans == scansBeforeReads + 1, 'opening settings must refresh dirty discovery once')
assert(discoveryAttempts == 1, 'a transient discovery export failure must be attempted once')
assert(hostileDiscoveryAttempts == 1, 'an unprintable discovery error must remain contained')
local openMessage = messages[#messages]
local foundHealthy = false
for _, tab in ipairs(openMessage.data.tabs) do if tab.id == 'healthy-resource' then foundHealthy = true end end
assert(foundHealthy, 'a hostile discovery error must not prevent subsequent resources from registering')
local externalField = openMessage.data.tabs[2].fields[1]
assert(externalField.poison == nil and externalField.cycle == nil, 'settings fields must use a strict serializable allowlist')
local actionSession = openMessage.data.session
local actionReply
callbacks.settingsAction({ session = actionSession, tabId = 'typed-actions', key = 'choice', value = false }, function(value)
    actionReply = value
end)
assert(actionReply.ok == true and #settingsActions == 1 and settingsActions[1].action == false,
    'a false-valued settings action must execute without being treated as missing')
callbacks.settingsAction({ session = actionSession, tabId = 'typed-actions', key = 'choice', value = '1' }, function(value)
    actionReply = value
end)
assert(actionReply.ok == false and actionReply.error == 'invalid_action' and #settingsActions == 1,
    'settings action authorization must not conflate numeric and string values')
local response
callbacks.settingsCancel({}, function(value) response = value end)
assert(response and response.ok == true, 'test must close the settings session')
for _ = 1, 20 do api.getSetting('shared') end
assert(resourceScans == scansBeforeReads + 1, 'cached discovery must keep later reads O(1)')

local catalog = api.getNotifySoundCatalog()
catalog[1].label = 'MUTATED'
assert(api.getNotifySoundCatalog()[1].label ~= 'MUTATED', 'sound catalog callers must receive defensive copies')

kvp['cortex:corrupt:bad_bool'] = 'not-a-boolean'
kvp['cortex:corrupt:bad_number'] = '1e9999'
invokingResource = 'owner-c'
assert(api.registerSettings('corrupt', 'Corrupt', nil, {
    { key = 'bad_bool', label = 'Bool', type = 'toggle' },
    { key = 'bad_number', label = 'Number', type = 'slider', min = 0, max = 10 },
}, { bad_bool = true, bad_number = 5 }))
assert(api.getTabSetting('corrupt', 'bad_bool') == true and api.getTabSetting('corrupt', 'bad_number') == 5,
    'corrupt KVP primitives must fall back to validated defaults')

api.openSettings()
assert(discoveryAttempts == 2, 'a transient discovery failure must remain retryable on the next refresh')
local foundRetry = false
for _, tab in ipairs(messages[#messages].data.tabs) do if tab.id == 'retry-resource' then foundRetry = true end end
assert(foundRetry, 'a successful discovery retry must register the recovered settings tab')
assert(api.registerSettings('added-live', 'Added Live', nil, {}, {}))
assert(messages[#messages].action == 'settingsClose' and messages[#messages].data.reason == 'registry_changed',
    'registry mutation must close and roll back an active settings definition')

print('settings registry lifecycle: PASS')
