local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

local proxyCalls = {}
local registeredEvents = 0
local registeredHandlers = 0
local threads = 0

lib = {}
GetCurrentResourceName = function() return 'consumer-server' end
RegisterNetEvent = function() registeredEvents = registeredEvents + 1 end
AddEventHandler = function() registeredHandlers = registeredHandlers + 1 end
CreateThread = function() threads = threads + 1 end
exports = setmetatable({}, {
    __index = function()
        local resourceExports = {}
        return setmetatable(resourceExports, {
            __index = function(self, exportName)
                return function(exportSelf, ...)
                    assertEqual(exportSelf, self, 'external server callback export should use method shape')
                    proxyCalls[#proxyCalls + 1] = { name = exportName, args = table.pack(...) }
                    return 'central:' .. exportName, 'second-result'
                end
            end,
        })
    end,
})

local callback = dofile('imports/callback/server.lua')
local responder = function() end
local first, second = callback('client:name', 22, responder, 'payload')
assertEqual(first, 'central:callback', 'external server callback should preserve first return')
assertEqual(second, 'second-result', 'external server callback should preserve second return')

first, second = callback.await('client:await', 23, 'payload')
assertEqual(first, 'central:callbackAwait', 'external await should proxy centrally')
assertEqual(second, 'second-result', 'external await should preserve multiple returns')

first, second = callback.register('server:name', responder)
assertEqual(first, 'central:registerCallback', 'external register should proxy centrally')
assertEqual(second, 'second-result', 'external register should preserve multiple returns')
assertEqual(proxyCalls[3].args[2], responder, 'external register should preserve handler identity')

assertEqual(registeredEvents, 0, 'external server module should not install central network handlers')
assertEqual(registeredHandlers, 0, 'external server module should not install empty cleanup handlers')
assertEqual(threads, 0, 'external server module should not install an empty sweeper')

print('external callback server spec: PASS')
