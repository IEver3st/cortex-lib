local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

local eventHandlers = {}
local emitted = {}
local proxyCalls = {}

lib = {}
GetCurrentResourceName = function() return 'consumer-client' end
GetGameTimer = function() return 100 end
RegisterNetEvent = function(name, handler) eventHandlers[name] = handler end
AddEventHandler = function(name, handler) eventHandlers[name] = handler end
TriggerServerEvent = function(...) emitted[#emitted + 1] = table.pack(...) end
SetTimeout = function(_, handler) handler() end
CreateThread = function() end
exports = setmetatable({}, {
    __index = function()
        local resourceExports = {}
        return setmetatable(resourceExports, {
            __index = function(self, exportName)
                return function(exportSelf, ...)
                    assertEqual(exportSelf, self, 'external callback export should use method shape')
                    proxyCalls[#proxyCalls + 1] = { name = exportName, args = table.pack(...) }
                    return false, 'central-result'
                end
            end,
        })
    end,
})

local callback = dofile('imports/callback/client.lua')
local marker = function() end
local registered, registerError = callback.register('consumer:name', marker)

assertEqual(registered, false, 'external client register should preserve central first return')
assertEqual(registerError, 'central-result', 'external client register should preserve central second return')
assertEqual(proxyCalls[1].name, 'registerCallback', 'external client register should proxy centrally')
assertEqual(proxyCalls[1].args[1], 'consumer:name', 'external client register should preserve name')
assertEqual(proxyCalls[1].args[2], marker, 'external client register should preserve handler identity')

callback('server:name', false, nil, 'payload')
assertEqual(emitted[#emitted][1], 'cortex-lib:callback', 'external client request should keep local response ownership')
assertEqual(type(emitted[#emitted][4]), 'string', 'external client request should include a correlation token')
assertEqual(eventHandlers['cortex-lib:callbackResponse'] ~= nil, true, 'external client should retain its response handler')
assertEqual(eventHandlers['cortex-lib:clientCallback'], nil, 'external client must not install central client handlers')

print('external callback client spec: PASS')
