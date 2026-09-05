local scriptPath = arg[1] or 'imports/help/client.lua'
local invoking = nil
local messages, events = {}, {}
function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return invoking end
function SendNUIMessage(message) messages[#messages + 1] = message end
function AddEventHandler(name, callback) events[name] = callback end
exports = function() end
lib = {}

local api = assert(dofile(scriptPath))
invoking = 'owner-a'
assert(api.showHelp({ { label = 'E', value = 'Interact' } }))
assert(messages[#messages].data.items[1].label == 'E' and messages[#messages].data.items[1].value == 'Interact',
    'help payload must preserve the label/value NUI contract')

invoking = 'owner-b'
local ok, err = api.showHelp({ { key = 'G', description = 'Replace' } })
assert(ok == false and err == 'not_owner', 'an unrelated owner must not replace active help')
assert(api.hideHelp() == false, 'an unrelated owner must not hide active help')

events.onResourceStop('owner-a')
assert(messages[#messages].action == 'helpHide', 'owner stop must hide active help')
assert(api.showHelp({ { key = 'G', description = 'Alias' } }))
assert(messages[#messages].data.items[1].label == 'G', 'legacy key/description aliases must normalize to label/value')

print('help lifecycle: PASS')
