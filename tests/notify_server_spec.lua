local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end


local function assertTruthy(value, message)
    if not value then error(message) end
end

local emitted = {}
local exported = {}

lib = {}
exports = function(name, handler) exported[name] = handler end
TriggerClientEvent = function(...) emitted[#emitted + 1] = table.pack(...) end

local notify = dofile('imports/notify/server.lua')

assertEqual(exported.notify, notify, 'notify export should retain callable module identity')
assertEqual(lib.notify, notify, 'lib.notify should retain callable module identity')
assertEqual(type(exported.notifyAll), 'function', 'notifyAll export should remain available')
assertEqual(lib.notifyAll, exported.notifyAll, 'lib.notifyAll should retain export identity')

local original = {
    id = 'job:complete',
    title = 'Completed',
    description = 'The operation completed.',
    type = 'success',
    position = 'bottom-right',
    duration = 1234.9,
    showDuration = true,
    persistent = false,
    plain = true,
    hideIcon = false,
    dedupe = false,
    icon = false,
    sound = { name = 'MEDAL_UP', set = 'HUD_MINI_GAME_SOUNDSET', ignored = true },
    ignored = { untrusted = true },
}

local successResult = notify(42, original)
assertEqual(successResult, nil, 'successful notify should preserve its nil return shape')
assertEqual(#emitted, 1, 'valid notification should transmit once')

local delivery = emitted[1]
local normalized = delivery[3]
assertEqual(delivery[1], 'cortex-lib:notify', 'notify should use the established event')
assertEqual(delivery[2], 42, 'notify should target the validated player')
assertEqual(normalized.id, original.id, 'notification id should be preserved')
assertEqual(normalized.title, original.title, 'notification title should be preserved')
assertEqual(normalized.description, original.description, 'notification description should be preserved')
assertEqual(normalized.type, original.type, 'notification type should be preserved')
assertEqual(normalized.position, original.position, 'notification position should be preserved')
assertEqual(normalized.duration, 1234, 'notification duration should be normalized to an integer')
assertEqual(normalized.showDuration, true, 'showDuration should be normalized')
assertEqual(normalized.persistent, false, 'persistent should be normalized')
assertEqual(normalized.plain, true, 'plain should be normalized')
assertEqual(normalized.hideIcon, true, 'legacy icon=false should normalize to hideIcon')
assertEqual(normalized.dedupe, false, 'dedupe should be normalized')
assertEqual(normalized.sound.name, 'MEDAL_UP', 'sound name should be copied')
assertEqual(normalized.sound.set, 'HUD_MINI_GAME_SOUNDSET', 'sound set should be copied')
assertEqual(normalized.sound.ignored, nil, 'unsupported sound fields should be removed')
assertEqual(normalized.ignored, nil, 'unsupported notification fields should be removed')
assertTruthy(normalized ~= original, 'normalization must not transmit the caller table directly')
assertTruthy(normalized.sound ~= original.sound, 'normalization must copy the sound table')

successResult = notify(7, 'string notification')
assertEqual(successResult, nil, 'string shorthand should preserve success return shape')
normalized = emitted[#emitted][3]
assertEqual(normalized.description, 'string notification', 'string shorthand should normalize description')
assertEqual(normalized.title, '', 'string shorthand should normalize title')
assertEqual(normalized.type, 'info', 'string shorthand should normalize type')
assertEqual(normalized.duration, 3000, 'string shorthand should normalize duration')
assertEqual(normalized.showDuration, true, 'omitted showDuration should retain the client default')
assertEqual(normalized.dedupe, true, 'string shorthand should normalize dedupe')

successResult = notify(7, { description = 'hidden timer', showDuration = false })
assertEqual(successResult, nil, 'explicit showDuration=false should remain valid')
assertEqual(emitted[#emitted][3].showDuration, false, 'explicit showDuration=false should be preserved')

exported.notifyAll({ description = 'broadcast', persistent = true })
delivery = emitted[#emitted]
assertEqual(delivery[2], -1, 'notifyAll should remain the only explicit broadcast path')
assertEqual(delivery[3].duration, 0, 'persistent broadcast should normalize duration')
assertEqual(delivery[3].persistent, true, 'persistent broadcast should normalize persistent state')

local invalidSources = { 0, -1, -10, 1.5, math.huge, -math.huge, 0 / 0, '4', {}, false }

for index = 1, #invalidSources do
    local before = #emitted
    local ok, err = notify(invalidSources[index], 'invalid source')
    assertEqual(ok, false, 'invalid player source should be rejected')
    assertEqual(err, 'invalid_notification_source', 'invalid player source should have a stable error')
    assertEqual(#emitted, before, 'invalid player source must not transmit')
end

local beforeNilPayload = #emitted
local nilPayloadOk, nilPayloadError = notify(9, nil)
assertEqual(nilPayloadOk, false, 'nil notification payload should be rejected')
assertEqual(nilPayloadError, 'invalid_notification_data', 'nil payload should have a stable error')
assertEqual(#emitted, beforeNilPayload, 'nil notification payload must not transmit')

local invalidPayloads = {
    false,
    { type = 'unknown', description = 'bad' },
    { type = 0 / 0, description = 'bad' },
    { position = 'center', description = 'bad' },
    { position = 0 / 0, description = 'bad' },
    { description = string.rep('x', 2049) },
    { title = string.rep('x', 129), description = 'bad' },
    { description = 'bad', duration = math.huge },
    { description = 'bad', duration = -1 },
    { description = 'bad', duration = 600001 },
    { description = 'bad', id = '' },
    { description = 'bad', showDuration = 'yes' },
    { description = 'bad', persistent = 'yes' },
    { description = 'bad', plain = 'yes' },
    { description = 'bad', hideIcon = 'yes' },
    { description = 'bad', dedupe = 'yes' },
    { description = 'bad', sound = { name = '../bad', set = 'SET' } },
    { description = {}, title = 'bad' },
}

for index = 1, #invalidPayloads do
    local before = #emitted
    local ok, err = notify(9, invalidPayloads[index])
    assertEqual(ok, false, 'invalid notification payload should be rejected at case ' .. index)
    assertEqual(err, 'invalid_notification_data', 'invalid payload should have a stable error')
    assertEqual(#emitted, before, 'invalid notification payload must not transmit')
end

local legacyResult = exported.Notify(11, 'warning', 'legacy message', 2500)
assertEqual(legacyResult, nil, 'legacy Notify should preserve success return shape')
normalized = emitted[#emitted][3]
assertEqual(normalized.type, 'warning', 'legacy Notify should preserve type')
assertEqual(normalized.description, 'legacy message', 'legacy Notify should preserve message')
assertEqual(normalized.duration, 2500, 'legacy Notify should preserve duration')

local legacyOk, legacyError = exported.Notify(-1, 'info', 'must not broadcast', 1000)
assertEqual(legacyOk, false, 'legacy Notify must reject broadcast source')
assertEqual(legacyError, 'invalid_notification_source', 'legacy Notify should preserve multiple failure returns')

local originalTriggerClientEvent = TriggerClientEvent
local hostileTransportError = setmetatable({}, {
    __tostring = function() error('secondary tostring failure') end,
})
TriggerClientEvent = function() error(hostileTransportError) end
local transmitOk, transmitError = notify(12, 'transmit failure')
assertEqual(transmitOk, false, 'transmit exception should be contained')
assertEqual(transmitError, 'notification_transmit_error', 'transmit exception should have a stable error')
transmitOk, transmitError = exported.notifyAll('broadcast transmit failure')
assertEqual(transmitOk, false, 'broadcast transmit exception should be contained')
assertEqual(transmitError, 'notification_transmit_error', 'broadcast transmit error should be preserved')
TriggerClientEvent = originalTriggerClientEvent

print('notify server spec: PASS')
