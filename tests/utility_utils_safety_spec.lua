local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

local exported = {}
local kvp = {}

lib = {}
exports = function(name, handler) exported[name] = handler end
json = {
    encode = function(value)
        if value.marker == 'ordinary' then return '{"marker":"ordinary"}' end
        if value.marker == 'oversized' then return string.rep('x', 1024 * 1024 + 1) end
        return '{}'
    end,
    decode = function(value)
        if value == '{"marker":"ordinary"}' then return { marker = 'ordinary' } end
        error('invalid json')
    end,
}
GetResourceKvpString = function(key) return kvp[key] end
SetResourceKvp = function(key, value) kvp[key] = value end
DeleteResourceKvp = function(key) kvp[key] = nil end

local utils = dofile('imports/utils/shared.lua')
local decoded = utils.safeJsonDecode('{"marker":"ordinary"}')
assertEqual(decoded.marker, 'ordinary', 'ordinary JSON tables should decode')
assertEqual(utils.safeJsonEncode({ marker = 'ordinary' }), '{"marker":"ordinary"}', 'ordinary JSON tables should encode')
assertEqual(utils.safeJsonEncode({ marker = 'oversized' }), '{}', 'oversized encoded JSON output should be rejected')

local decodeCalls = 0
local savedDecoder = json.decode
json.decode = function()
    decodeCalls = decodeCalls + 1
    return {}
end
assertEqual(utils.safeJsonDecode(string.rep('x', 1024 * 1024 + 1)), nil, 'oversized JSON input should be rejected')
assertEqual(decodeCalls, 0, 'oversized JSON input must be rejected before decoder invocation')
json.decode = savedDecoder

local originalJson = json
local originalDecoder = json.decode
json = nil
assertEqual(utils.safeJsonDecode('{}'), nil, 'missing JSON runtime should be contained')
assertEqual(utils.safeJsonEncode({}), '{}', 'missing JSON runtime should retain safe fallback shape')
json = originalJson

json.decode = function() error('decoder failure') end
assertEqual(utils.safeJsonDecode('{}'), nil, 'decoder exceptions should be contained')
json.decode = originalDecoder

local circular = {}
circular.self = circular
assertEqual(utils.safeJsonEncode(circular), '{}', 'circular JSON input should be rejected safely')
assertEqual(utils.safeJsonEncode({ value = 0 / 0 }), '{}', 'NaN JSON input should be rejected safely')
assertEqual(utils.safeJsonEncode({ value = math.huge }), '{}', 'infinite JSON input should be rejected safely')
assertEqual(utils.safeJsonEncode({ callback = function() end }), '{}', 'unsupported JSON values should be rejected safely')
assertEqual(utils.safeJsonEncode({ ['bad\nkey'] = true }), '{}', 'control characters in JSON keys should be rejected')

local oversizedFlat = {}
for index = 1, 5000 do oversizedFlat[index] = index end
assertEqual(utils.safeJsonEncode(oversizedFlat), '{}', 'flat JSON input must respect the aggregate node budget')

local deeplyNested = {}
local cursor = deeplyNested
for _ = 1, 34 do
    cursor.child = {}
    cursor = cursor.child
end
assertEqual(utils.safeJsonEncode(deeplyNested), '{}', 'overly deep JSON input should be rejected safely')

assertEqual(utils.kvpSet('utility:key', 'value'), nil, 'successful KVP writes should preserve their nil return')
assertEqual(utils.kvpGet('utility:key', 'fallback'), 'value', 'ordinary KVP values should round-trip')
assertEqual(utils.kvpSet('utility:empty', ''), nil, 'empty-string KVP writes should remain valid')
assertEqual(utils.kvpGet('utility:empty', 'fallback'), 'fallback', 'legacy KVP reads must treat an empty string as missing')
assertEqual(utils.kvpSet('utility:number', 42), nil, 'finite numeric KVP values should remain supported')
assertEqual(kvp['utility:number'], '42', 'numeric KVP values should remain string encoded')
assertEqual(utils.kvpSet('utility:bad', {}), false, 'non-scalar KVP values should be rejected')
assertEqual(utils.kvpSet('utility:bad', 0 / 0), false, 'NaN KVP values should be rejected')
assertEqual(utils.kvpSet('utility:large', string.rep('x', 1024 * 1024 + 1)), false, 'oversized scalar KVP values should be rejected')
assertEqual(utils.kvpSet('', 'value'), false, 'empty KVP keys should be rejected')
assertEqual(utils.kvpSet('bad\0key', 'value'), false, 'NUL-containing KVP keys should be rejected')
assertEqual(utils.kvpSet('bad\nkey', 'value'), false, 'control characters in KVP keys should be rejected')

assertEqual(utils.kvpSetJson('utility:json', { marker = 'ordinary' }), nil, 'serializable JSON KVP writes should preserve nil success')
assertEqual(kvp['utility:json'], '{"marker":"ordinary"}', 'JSON KVP writes should use the safe encoder')
json.decode = function(value)
    if value == '{"marker":"ordinary"}' then return { marker = 'ordinary' } end
    error('invalid json')
end
decoded = utils.kvpGetJson('utility:json', {})
assertEqual(decoded.marker, 'ordinary', 'JSON KVP values should round-trip')
assertEqual(utils.kvpSetJson('utility:cycle', circular), false, 'invalid JSON KVP values should be rejected')
assertEqual(utils.kvpSetJson('utility:large-json', { marker = 'oversized' }), false, 'oversized JSON KVP values should be rejected')

kvp['utility:large-read'] = string.rep('x', 1024 * 1024 + 1)
assertEqual(utils.kvpGet('utility:large-read', 'fallback'), 'fallback', 'oversized KVP reads should return the fallback')

GetResourceKvpString = function() error('KVP read failure') end
SetResourceKvp = function() error('KVP write failure') end
DeleteResourceKvp = function() error('KVP delete failure') end
assertEqual(utils.kvpGet('utility:key', 'fallback'), 'fallback', 'KVP read exceptions should return the fallback')
assertEqual(utils.kvpSet('utility:key', 'value'), false, 'KVP write exceptions should be contained')
assertEqual(utils.kvpSetJson('utility:key', { marker = 'ordinary' }), false, 'JSON KVP write exceptions should be contained')
assertEqual(utils.kvpDelete('utility:key'), false, 'KVP delete exceptions should be contained')

assertEqual(utils.distanceSquared(0, 0, 0, 1, 2, 2), 9, 'ordinary scalar distance should be preserved')
assertEqual(utils.distance(0, 0, 0, 0, 3, 4), 5, 'ordinary distance should be preserved')
assertEqual(utils.distanceSquared(0 / 0, 0, 0, 1, 1, 1), nil, 'NaN coordinates should be rejected')
assertEqual(utils.distanceSquaredVec({ x = 0, y = 0, z = 0 }, { x = math.huge, y = 0, z = 0 }), nil, 'infinite vector coords should be rejected')
assertEqual(utils.isWithinDistance(0, 0, 0, 1, 1, 1, math.huge), false, 'infinite radii should be rejected')
assertEqual(utils.isWithinDistanceVec({ x = 0, y = 0, z = 0 }, nil, 5), false, 'invalid vector inputs should return false')

assertEqual(utils.parseNumber(0 / 0, 7), 7, 'parseNumber should reject NaN')
assertEqual(utils.parseNumber('12.5', 7), 12.5, 'parseNumber should retain finite conversion')
assertEqual(utils.clamp(5, 0, 4), 4, 'ordinary clamping should be preserved')
assertEqual(utils.clamp(5, 10, 0), nil, 'reversed clamp bounds should be rejected')
assertEqual(utils.round(1.25, 1), 1.3, 'ordinary rounding should be preserved')
assertEqual(utils.round(math.huge, 1), nil, 'round should reject infinite values')
assertEqual(type(utils.shallowCopy(nil)), 'table', 'invalid shallow-copy input should preserve a table return')
assertEqual(type(utils.mergeDefaults(nil, nil)), 'table', 'invalid merge input should preserve a table return')

print('utility shared safety spec: PASS')
