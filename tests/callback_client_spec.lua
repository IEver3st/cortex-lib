local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

local function assertTruthy(value, message)
    if not value then
        error(message)
    end
end

local eventHandlers = {}
local exported = {}
local emitted = {}
local timeouts = {}
local threads = {}
local invokingResource = nil
local now = 0
local waitCount = 0
local runningThread = false

lib = {}
GetCurrentResourceName = function() return 'cortex-lib' end
GetInvokingResource = function() return invokingResource end
GetGameTimer = function() return now end
RegisterNetEvent = function(name, handler) eventHandlers[name] = handler end
AddEventHandler = function(name, handler) eventHandlers[name] = handler end
TriggerServerEvent = function(...) emitted[#emitted + 1] = table.pack(...) end
SetTimeout = function(delay, handler) timeouts[#timeouts + 1] = { delay = delay, handler = handler } end
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

local callback = dofile('imports/callback/client.lua')
local hostileError = setmetatable({}, {
    __tostring = function() error('secondary tostring failure') end,
})

invokingResource = 'owner-a'
local ok = exported.registerCallback('shared:name', function() return 'a' end)
assertEqual(ok, nil, 'successful registration should preserve its nil return shape')

invokingResource = 'owner-b'
local collisionOk, collisionError = exported.registerCallback('shared:name', function() return 'b' end)
assertEqual(collisionOk, false, 'cross-owner collision should be rejected')
assertTruthy(collisionError:find('owner%-a') ~= nil, 'collision should identify the existing owner')

eventHandlers.onClientResourceStop('owner-a')
ok = exported.registerCallback('shared:name', function()
    return nil, 'middle', nil
end)
assertEqual(ok, nil, 'stopped owner registrations should be released')

eventHandlers['cortex-lib:clientCallback']('shared:name', 'request:1', 'token:1', 'payload')
local response = emitted[#emitted]
assertEqual(response[1], 'cortex-lib:clientCallbackResponse', 'client handler should respond')
assertEqual(response.n, 6, 'trailing nil callback results should be transmitted')
assertEqual(response[4], nil, 'first nil callback result should be preserved')
assertEqual(response[5], 'middle', 'middle callback result should be preserved')
assertEqual(response[6], nil, 'trailing nil callback result should be preserved')

ok = exported.registerCallback('throwing:name', function()
    error('handler exploded')
end)
assertEqual(ok, nil, 'throwing handler should still register')

local handlerOk = pcall(eventHandlers['cortex-lib:clientCallback'], 'throwing:name', 'request:2', 'token:2')
assertEqual(handlerOk, true, 'handler exceptions should not escape the network event')
response = emitted[#emitted]
assertEqual(response[4], nil, 'handler error response should begin with nil')
assertEqual(response[5], 'callback_handler_error', 'handler error should be explicit')

ok = exported.registerCallback('throwing:hostile-error', function()
    error(hostileError)
end)
assertEqual(ok, nil, 'hostile-error handler should register')
handlerOk = pcall(eventHandlers['cortex-lib:clientCallback'], 'throwing:hostile-error', 'request:hostile', 'token:hostile')
assertEqual(handlerOk, true, 'an unprintable handler error must not escape the network event')
response = emitted[#emitted]
assertEqual(response[5], 'callback_handler_error', 'an unprintable handler error must still receive an explicit response')

local invalidResult
local invalidOk, invalidError = callback('', false, function(...)
    invalidResult = table.pack(...)
end)
assertEqual(invalidOk, false, 'invalid name should be rejected before transmit')
assertEqual(invalidError, 'invalid_callback_name', 'invalid name should have a stable error')
assertEqual(invalidResult[1], nil, 'invalid request callback should receive nil')
assertEqual(invalidResult[2], 'invalid_callback_name', 'invalid request callback should receive the error')

invalidResult = nil
callback('response:nil', false, function(...)
    invalidResult = table.pack(...)
end)
local request = emitted[#emitted]
local requestId = request[3]
local requestToken = request[4]
eventHandlers['cortex-lib:callbackResponse'](requestId, 'stale-restart-token', 'stale')
assertEqual(invalidResult, nil, 'a stale response token must not settle a reused callback id')
eventHandlers['cortex-lib:callbackResponse'](requestId, requestToken, nil, 'middle', nil)
assertEqual(invalidResult.n, 3, 'response should preserve trailing nil results')
assertEqual(invalidResult[2], 'middle', 'response should preserve middle values')

callback('response:throws', false, function()
    error('responder exploded')
end)
request = emitted[#emitted]
handlerOk = pcall(eventHandlers['cortex-lib:callbackResponse'], request[3], request[4], 'ok')
assertEqual(handlerOk, true, 'responder exceptions should not escape response handling')

callback('response:hostile-responder', false, function()
    error(hostileError)
end)
request = emitted[#emitted]
handlerOk = pcall(eventHandlers['cortex-lib:callbackResponse'], request[3], request[4], 'ok')
assertEqual(handlerOk, true, 'an unprintable responder error must not escape response handling')

local hostilePromiseResponder = {
    resolve = function() error(hostileError) end,
}
callback('response:hostile-promise', false, hostilePromiseResponder)
request = emitted[#emitted]
handlerOk = pcall(eventHandlers['cortex-lib:callbackResponse'], request[3], request[4], 'ok')
assertEqual(handlerOk, true, 'an unprintable promise-resolver error must not escape response handling')

local delayedResult
callback('delayed:name', 60000, function(...)
    delayedResult = table.pack(...)
end)
assertEqual(timeouts[#timeouts].delay, 60000, 'requested callback delay should be retained')

now = 40000
runThreadOnce(threads[1])
assertEqual(delayedResult, nil, 'unsent delayed request must not time out')

timeouts[#timeouts].handler()
now = 70001
runThreadOnce(threads[1])
assertEqual(delayedResult[1], nil, 'timed out request should resolve with nil')
assertEqual(delayedResult[2], 'timeout', 'timeout should start from actual transmit')

local wrappedTimerResult
now = 4294967200
callback('wrapped:timer', false, function(...)
    wrappedTimerResult = table.pack(...)
end)
now = 50
runThreadOnce(threads[1])
assertEqual(wrappedTimerResult, nil, 'timer wrap must not immediately expire a recent client callback')
now = 30100
runThreadOnce(threads[1])
assertEqual(wrappedTimerResult[2], 'timeout', 'client timeout should remain accurate across GetGameTimer wrap')

local stoppedDelayedResult
invokingResource = 'scheduled-owner'
callback('delayed:owned', 1000, function(...)
    stoppedDelayedResult = table.pack(...)
end)
local ownedResponderTimer = timeouts[#timeouts]
callback('delayed:fire-and-forget', 1000, nil, 'payload')
local ownedFireAndForgetTimer = timeouts[#timeouts]
local emittedBeforeStop = #emitted

eventHandlers.onClientResourceStop('scheduled-owner')
assertEqual(stoppedDelayedResult[1], nil, 'owner stop should settle delayed responder')
assertEqual(stoppedDelayedResult[2], 'resource_stopped', 'owner stop should identify delayed cancellation')
ownedResponderTimer.handler()
ownedFireAndForgetTimer.handler()
assertEqual(#emitted, emittedBeforeStop, 'cancelled delayed calls must not transmit after owner stop')
invokingResource = 'owner-b'

local tooMany = {}
for index = 1, 33 do tooMany[index] = index end
invalidOk, invalidError = callback('too:many', false, function() end, table.unpack(tooMany, 1, 33))
assertEqual(invalidOk, false, 'oversized vararg request should be rejected')
assertEqual(invalidError, 'too_many_callback_arguments', 'oversized varargs should have a stable error')

local circularPayload = {}
circularPayload.self = circularPayload
local deepPayload = {}
local deepCursor = deepPayload
for _ = 1, 18 do
    deepCursor.child = {}
    deepCursor = deepCursor.child
end

for _, payload in ipairs({ circularPayload, deepPayload, string.rep('x', 1024 * 1024 + 1), 0 / 0 }) do
    invalidResult = nil
    invalidOk, invalidError = callback('payload:invalid', false, function(...)
        invalidResult = table.pack(...)
    end, payload)
    assertEqual(invalidOk, false, 'malformed payload should be rejected before transmit')
    assertEqual(invalidError, 'invalid_callback_payload', 'malformed payload should have a stable error')
    assertEqual(invalidResult[2], 'invalid_callback_payload', 'malformed payload should settle responder')
end

local ordinaryPayload = { nested = { value = 'ok' }, list = { 1, 2, 3 } }
local emittedBeforeOrdinary = #emitted
callback('payload:ordinary', false, nil, ordinaryPayload)
assertEqual(#emitted, emittedBeforeOrdinary + 1, 'ordinary nested payload should pass validation')

ok = exported.registerCallback('result:invalid', function() return 0 / 0 end)
assertEqual(ok, nil, 'invalid result handler should register')
eventHandlers['cortex-lib:clientCallback']('result:invalid', 'request:invalid-result', 'token:invalid-result')
response = emitted[#emitted]
assertEqual(response[5], 'invalid_callback_result', 'invalid client callback result should be rejected')

local invalidRequestHandlerCalled = false
ok = exported.registerCallback('payload:inbound-invalid', function()
    invalidRequestHandlerCalled = true
end)
assertEqual(ok, nil, 'invalid inbound payload handler should register')
eventHandlers['cortex-lib:clientCallback'](
    'payload:inbound-invalid',
    'request:invalid-payload',
    'token:invalid-payload',
    deepPayload
)
response = emitted[#emitted]
assertEqual(invalidRequestHandlerCalled, false, 'invalid inbound payload must not reach client handler')
assertEqual(response[5], 'invalid_callback_request', 'invalid inbound client payload should be rejected')

local invalidResponseResult
callback('response:invalid-payload', false, function(...)
    invalidResponseResult = table.pack(...)
end)
request = emitted[#emitted]
eventHandlers['cortex-lib:callbackResponse'](request[3], request[4], circularPayload)
assertEqual(invalidResponseResult[2], 'invalid_callback_response', 'malformed response should settle caller explicitly')

invokingResource = 'pending-cap-owner'
local capacityResult
for index = 1, 128 do
    local capacityOk = callback('capacity:pending', false, function() end, index)
    assertEqual(capacityOk, nil, 'callbacks within the per-owner pending cap should be accepted')
end
invalidOk, invalidError = callback('capacity:pending', false, function(...)
    capacityResult = table.pack(...)
end)
assertEqual(invalidOk, false, 'pending callbacks beyond the owner cap should be rejected')
assertEqual(invalidError, 'callback_capacity_exceeded', 'pending callback cap should have a stable error')
assertEqual(capacityResult[2], 'callback_capacity_exceeded', 'pending cap rejection should settle responder')
eventHandlers.onClientResourceStop('pending-cap-owner')
local capacityOkAfterCleanup = callback('capacity:pending-reused', false, function() end)
assertEqual(capacityOkAfterCleanup, nil, 'owner-stop cleanup should release pending capacity')
eventHandlers.onClientResourceStop('pending-cap-owner')

invokingResource = 'scheduled-cap-owner'
for index = 1, 64 do
    local capacityOk = callback('capacity:scheduled', 1000, nil, index)
    assertEqual(capacityOk, nil, 'scheduled calls within the owner cap should be accepted')
end
invalidOk, invalidError = callback('capacity:scheduled', 1000, nil)
assertEqual(invalidOk, false, 'scheduled calls beyond the owner cap should be rejected')
assertEqual(invalidError, 'callback_capacity_exceeded', 'scheduled callback cap should have a stable error')
eventHandlers.onClientResourceStop('scheduled-cap-owner')
capacityOkAfterCleanup = callback('capacity:scheduled-reused', 1000, nil)
assertEqual(capacityOkAfterCleanup, nil, 'owner-stop cleanup should release scheduled capacity')
eventHandlers.onClientResourceStop('scheduled-cap-owner')
invokingResource = 'owner-b'

local originalTriggerServerEvent = TriggerServerEvent
TriggerServerEvent = function() error(hostileError) end
local transmitResult
invalidOk, invalidError = callback('transmit:error', false, function(...)
    transmitResult = table.pack(...)
end)
assertEqual(invalidOk, false, 'client transmit exceptions should return failure')
assertEqual(invalidError, 'callback_transmit_error', 'client transmit failure should be explicit')
assertEqual(transmitResult[2], 'callback_transmit_error', 'client transmit failure should settle responder')

ok = exported.registerCallback('response:transport-error', function() return 'ok' end)
assertEqual(ok, nil, 'transport error handler should register')
handlerOk = pcall(eventHandlers['cortex-lib:clientCallback'], 'response:transport-error', 'request:3', 'token:3')
assertEqual(handlerOk, true, 'response transport exceptions should not escape the event handler')
TriggerServerEvent = originalTriggerServerEvent

print('callback client spec: PASS')
