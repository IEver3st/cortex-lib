local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

local function assertTruthy(value, message)
    if not value then error(message) end
end

local eventHandlers = {}
local exported = {}
local emitted = {}
local threads = {}
local invokingResource = nil
local now = 0
local waitCount = 0
local runningThread = false

lib = {}
source = nil
GetCurrentResourceName = function() return 'cortex-lib' end
GetInvokingResource = function() return invokingResource end
GetGameTimer = function() return now end
RegisterNetEvent = function(name, handler) eventHandlers[name] = handler end
AddEventHandler = function(name, handler) eventHandlers[name] = handler end
TriggerClientEvent = function(...) emitted[#emitted + 1] = table.pack(...) end
exports = function(name, handler) exported[name] = handler end
CreateThread = function(handler) threads[#threads + 1] = handler end
Wait = function()
    if not runningThread then return end
    waitCount = waitCount + 1
    if waitCount > 1 then error('stop_test_thread') end
end
promise = {
    new = function()
        return { resolve = function(self, value) self.value = value end }
    end,
}
Citizen = { Await = function(value) return value.value end }

local function runThreadOnce(handler)
    waitCount = 0
    runningThread = true
    local ok, err = pcall(handler)
    runningThread = false
    assertEqual(ok, false, 'test thread should stop after one sweep')
    assertTruthy(tostring(err):find('stop_test_thread', 1, true), 'unexpected test thread error')
end

local callback = dofile('imports/callback/server.lua')
local hostileError = setmetatable({}, {
    __tostring = function() error('secondary tostring failure') end,
})

local function invokeInbound(name, id, ...)
    local token = 'request-token:' .. id
    eventHandlers['cortex-lib:callback'](name, id, token, ...)
    return token
end

invokingResource = 'owner-a'
local ok = exported.registerCallback('shared:name', function()
    return nil, 'middle', nil
end)
assertEqual(ok, nil, 'successful registration should preserve its nil return shape')

invokingResource = 'owner-b'
local collisionOk, collisionError = exported.registerCallback('shared:name', function() return 'b' end)
assertEqual(collisionOk, false, 'cross-owner server collision should be rejected')
assertTruthy(collisionError:find('owner%-a') ~= nil, 'server collision should identify existing owner')

source = 41
local inboundToken = invokeInbound('shared:name', 'consumer:1', 'payload')
local response = emitted[#emitted]
assertEqual(response[1], 'cortex-lib:callbackResponse', 'server handler should respond')
assertEqual(response[2], 41, 'server response should target invoking player')
assertEqual(response[4], inboundToken, 'server response should echo the request correlation token')
assertEqual(response.n, 7, 'server response should preserve trailing nil results')
assertEqual(response[5], nil, 'first nil server result should be preserved')
assertEqual(response[6], 'middle', 'middle server result should be preserved')
assertEqual(response[7], nil, 'trailing nil server result should be preserved')

ok = exported.registerCallback('throwing:name', function()
    error('handler exploded')
end)
assertEqual(ok, nil, 'throwing server handler should register')
local handlerOk = pcall(invokeInbound, 'throwing:name', 'consumer:2')
assertEqual(handlerOk, true, 'server handler exception should not escape event')
response = emitted[#emitted]
assertEqual(response[5], nil, 'server handler error should begin with nil')
assertEqual(response[6], 'callback_handler_error', 'server handler error should be explicit')

ok = exported.registerCallback('throwing:hostile-error', function()
    error(hostileError)
end)
assertEqual(ok, nil, 'hostile-error server handler should register')
handlerOk = pcall(invokeInbound, 'throwing:hostile-error', 'consumer:hostile')
assertEqual(handlerOk, true, 'an unprintable server handler error must not escape the network event')
response = emitted[#emitted]
assertEqual(response[6], 'callback_handler_error', 'an unprintable server handler error must still receive an explicit response')

ok = exported.registerCallback('burst:name', function() return 'ok' end)
assertEqual(ok, nil, 'burst callback should register')
source = 51
for index = 1, 25 do
    invokeInbound('burst:name', 'burst:' .. index)
end
response = emitted[#emitted]
assertEqual(response[6], 'callback_rate_limited', '25th same-name request should hit burst limit')

ok = exported.registerCallback('burst:other', function() return 'other-ok' end)
assertEqual(ok, nil, 'second burst name should register')
invokeInbound('burst:other', 'burst:other:1')
response = emitted[#emitted]
assertEqual(response[5], 'other-ok', 'rate limit should be per source and callback name')

ok = exported.registerCallback('count', function() return 'count-ok' end)
assertEqual(ok, nil, 'metadata-like callback name should register')
local countHandlerOk = pcall(invokeInbound, 'count', 'count:1')
assertEqual(countHandlerOk, true, 'callback named count must not collide with rate metadata')
response = emitted[#emitted]
assertEqual(response[5], 'count-ok', 'callback named count should execute normally')

invokeInbound('', 'bad:1')
response = emitted[#emitted]
assertEqual(response[6], 'invalid_callback_request', 'invalid inbound name should be rejected')

local tooMany = {}
for index = 1, 33 do tooMany[index] = index end
invokeInbound('burst:other', 'bad:2', table.unpack(tooMany, 1, 33))
response = emitted[#emitted]
assertEqual(response[6], 'invalid_callback_request', 'oversized inbound varargs should be rejected')

local circularPayload = {}
circularPayload.self = circularPayload
local deepPayload = {}
local deepCursor = deepPayload
for _ = 1, 18 do
    deepCursor.child = {}
    deepCursor = deepCursor.child
end

source = 61
for index, payload in ipairs({ circularPayload, deepPayload, string.rep('x', 1024 * 1024 + 1), 0 / 0 }) do
    local payloadHandlerOk = pcall(invokeInbound, 'burst:other', 'bad:payload:' .. index, payload)
    assertEqual(payloadHandlerOk, true, 'malformed inbound payload must not escape server event')
    response = emitted[#emitted]
    assertEqual(response[6], 'invalid_callback_request', 'malformed inbound payload should be rejected')
end

ok = exported.registerCallback('payload:ordinary', function(_, payload)
    return { nested = payload.nested, accepted = true }
end)
assertEqual(ok, nil, 'ordinary payload handler should register')
invokeInbound('payload:ordinary', 'payload:ordinary:1', { nested = { value = 'ok' } })
response = emitted[#emitted]
assertEqual(response[5].nested.value, 'ok', 'ordinary nested payload should pass server validation')
assertEqual(response[5].accepted, true, 'ordinary nested result should pass server validation')

ok = exported.registerCallback('result:invalid', function() return circularPayload end)
assertEqual(ok, nil, 'invalid result handler should register')
invokeInbound('result:invalid', 'result:invalid:1')
response = emitted[#emitted]
assertEqual(response[6], 'invalid_callback_result', 'invalid server callback result should be rejected')

source = 52
for index = 1, 121 do
    invokeInbound('spread:' .. index, 'spread:' .. index)
end
response = emitted[#emitted]
assertEqual(response[6], 'callback_rate_limited', 'global source bucket should stop callback-name spread bursts')

local outgoingResult
invokingResource = 'consumer-rpc'
callback('client:request', 77, function(...)
    outgoingResult = table.pack(...)
end, 'payload')
local outbound = emitted[#emitted]
assertEqual(outbound[1], 'cortex-lib:clientCallback', 'server callback should transmit to client')
local outboundId = outbound[4]
local outboundToken = outbound[5]

source = 77
eventHandlers['cortex-lib:clientCallbackResponse'](outboundId, 'wrong-token', 'spoofed')
assertEqual(outgoingResult, nil, 'wrong response token should not settle callback')
eventHandlers['cortex-lib:clientCallbackResponse'](outboundId, outboundToken, nil, 'middle', nil)
assertEqual(outgoingResult.n, 3, 'server pending response should preserve trailing nil')
assertEqual(outgoingResult[2], 'middle', 'server pending response should preserve middle value')

local invalidResponseResult
callback('client:invalid-response', 77, function(...)
    invalidResponseResult = table.pack(...)
end)
outbound = emitted[#emitted]
eventHandlers['cortex-lib:clientCallbackResponse'](outbound[4], outbound[5], circularPayload)
assertEqual(invalidResponseResult[2], 'invalid_callback_response', 'invalid client response payload should settle caller')

callback('client:throws', 78, function()
    error('responder exploded')
end)
outbound = emitted[#emitted]
source = 78
handlerOk = pcall(eventHandlers['cortex-lib:clientCallbackResponse'], outbound[4], outbound[5], 'ok')
assertEqual(handlerOk, true, 'server responder exceptions should not escape response event')

callback('client:hostile-responder', 78, function()
    error(hostileError)
end)
outbound = emitted[#emitted]
source = 78
handlerOk = pcall(eventHandlers['cortex-lib:clientCallbackResponse'], outbound[4], outbound[5], 'ok')
assertEqual(handlerOk, true, 'an unprintable server responder error must not escape response handling')

local hostilePromiseResponder = {
    resolve = function() error(hostileError) end,
}
callback('client:hostile-promise', 78, hostilePromiseResponder)
outbound = emitted[#emitted]
source = 78
handlerOk = pcall(eventHandlers['cortex-lib:clientCallbackResponse'], outbound[4], outbound[5], 'ok')
assertEqual(handlerOk, true, 'an unprintable server promise error must not escape response handling')

local droppedResult
callback('client:drop', 79, function(...)
    droppedResult = table.pack(...)
end)
source = 79
eventHandlers.playerDropped()
assertEqual(droppedResult[1], nil, 'dropped player should settle pending callback with nil')
assertEqual(droppedResult[2], 'player_dropped', 'dropped player should settle pending callback explicitly')

eventHandlers.onResourceStop('owner-a')
ok = exported.registerCallback('shared:name', function() return 'owner-b' end)
assertEqual(ok, nil, 'stopped server owner registration should be released')

local stoppedResult
invokingResource = 'owner-to-stop'
callback('client:stop', 80, function(...)
    stoppedResult = table.pack(...)
end)
eventHandlers.onResourceStop('owner-to-stop')
assertEqual(stoppedResult[2], 'resource_stopped', 'owner stop should settle its pending server callbacks')

local timeoutResult
invokingResource = 'timeout-owner'
now = 0
callback('client:timeout', 81, function(...)
    timeoutResult = table.pack(...)
end)
now = 30001
runThreadOnce(threads[1])
assertEqual(timeoutResult[1], nil, 'server timeout should settle with nil')
assertEqual(timeoutResult[2], 'timeout', 'server timeout should be explicit')

local wrappedTimerResult
invokingResource = 'wrapped-timer-owner'
now = 4294967200
callback('client:wrapped-timer', 81, function(...)
    wrappedTimerResult = table.pack(...)
end)
now = 50
runThreadOnce(threads[1])
assertEqual(wrappedTimerResult, nil, 'timer wrap must not immediately expire a recent server callback')
now = 30100
runThreadOnce(threads[1])
assertEqual(wrappedTimerResult[2], 'timeout', 'server timeout should remain accurate across GetGameTimer wrap')

invokingResource = 'server-cap-owner'
for index = 1, 128 do
    local capacityOk = callback('client:capacity', 82, function() end, index)
    assertEqual(capacityOk, nil, 'server callbacks within the pending owner cap should be accepted')
end
local capacityResult
local capacityOk, capacityError = callback('client:capacity', 82, function(...)
    capacityResult = table.pack(...)
end)
assertEqual(capacityOk, false, 'server callbacks beyond the pending owner cap should be rejected')
assertEqual(capacityError, 'callback_capacity_exceeded', 'server pending cap should have a stable error')
assertEqual(capacityResult[2], 'callback_capacity_exceeded', 'server pending cap should settle responder')
eventHandlers.onResourceStop('server-cap-owner')
local capacityOkAfterCleanup = callback('client:capacity-reused', 82, function() end)
assertEqual(capacityOkAfterCleanup, nil, 'server owner-stop cleanup should release pending capacity')
eventHandlers.onResourceStop('server-cap-owner')

local invalidResult
local invalidOk, invalidError = callback('', 81, function(...)
    invalidResult = table.pack(...)
end)
assertEqual(invalidOk, false, 'invalid outbound name should be rejected')
assertEqual(invalidError, 'invalid_callback_name', 'invalid outbound name should have stable error')
assertEqual(invalidResult[2], 'invalid_callback_name', 'invalid outbound callback should receive the error')

invalidResult = nil
invalidOk, invalidError = callback('payload:invalid-outbound', 81, function(...)
    invalidResult = table.pack(...)
end, 0 / 0)
assertEqual(invalidOk, false, 'invalid outbound payload should be rejected')
assertEqual(invalidError, 'invalid_callback_payload', 'invalid outbound payload should have stable error')
assertEqual(invalidResult[2], 'invalid_callback_payload', 'invalid outbound payload should settle responder')

print('callback server spec: PASS')
