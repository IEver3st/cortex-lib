local floor = math.floor
local sqrt = math.sqrt
local type = type
local next = next
local tonumber = tonumber
local tostring = tostring
local pcall = pcall

local MAX_JSON_DEPTH = 32
local MAX_JSON_NODES = 8192
local MAX_JSON_STRING_BYTES = 1024 * 1024
local MAX_JSON_ENCODED_BYTES = 1024 * 1024
local MAX_KVP_KEY_BYTES = 256
local MAX_KVP_VALUE_BYTES = 1024 * 1024

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function readFiniteCoords(value)
    if value == nil then return nil end

    local ok, x, y, z = pcall(function()
        return value.x, value.y, value.z
    end)

    if not ok or not isFiniteNumber(x) or not isFiniteNumber(y) or not isFiniteNumber(z) then
        return nil
    end

    return x, y, z
end

local function validateJsonValue(value, state, depth)
    if depth > MAX_JSON_DEPTH then return false end

    state.nodes = state.nodes + 1
    if state.nodes > MAX_JSON_NODES then return false end

    if state.hasJsonNull and value == state.jsonNull then return true end

    local valueType = type(value)
    if valueType == 'nil' or valueType == 'boolean' then return true end

    if valueType == 'number' then
        return isFiniteNumber(value)
    end

    if valueType == 'string' then
        state.stringBytes = state.stringBytes + #value
        return state.stringBytes <= MAX_JSON_STRING_BYTES
    end

    if valueType ~= 'table' or state.seen[value] then return false end

    state.seen[value] = true
    for key, child in next, value do
        state.nodes = state.nodes + 1
        if state.nodes > MAX_JSON_NODES then
            state.seen[value] = nil
            return false
        end

        local keyType = type(key)
        if keyType == 'string' then
            state.stringBytes = state.stringBytes + #key
            if state.stringBytes > MAX_JSON_STRING_BYTES or key:find('%c') then
                state.seen[value] = nil
                return false
            end
        elseif keyType ~= 'number' or not isFiniteNumber(key) or key % 1 ~= 0 then
            state.seen[value] = nil
            return false
        end

        if not validateJsonValue(child, state, depth + 1) then
            state.seen[value] = nil
            return false
        end
    end
    state.seen[value] = nil

    return true
end

local function isJsonSerializable(value)
    local nullOk, nullValue = pcall(function()
        return json and json.null
    end)
    local ok, valid = pcall(validateJsonValue, value, {
        seen = {},
        nodes = 0,
        stringBytes = 0,
        hasJsonNull = nullOk and nullValue ~= nil,
        jsonNull = nullValue,
    }, 0)

    return ok and valid == true
end

local function getJsonFunction(name)
    local ok, handler = pcall(function()
        return json and json[name]
    end)

    return ok and type(handler) == 'function' and handler or nil
end

local function tryJsonEncode(data)
    if type(data) ~= 'table' or not isJsonSerializable(data) then return nil end

    local encoder = getJsonFunction('encode')
    if not encoder then return nil end

    local ok, encoded = pcall(encoder, data)
    if not ok or type(encoded) ~= 'string' or encoded == '' or #encoded > MAX_JSON_ENCODED_BYTES then return nil end
    return encoded
end

local function safeJsonDecode(value)
    if type(value) ~= 'string' or value == '' or #value > MAX_JSON_ENCODED_BYTES then return nil end

    local decoder = getJsonFunction('decode')
    if not decoder then return nil end

    local ok, decoded = pcall(decoder, value)
    if ok and type(decoded) == 'table' and isJsonSerializable(decoded) then
        return decoded
    end

    return nil
end

local function safeJsonEncode(data)
    return tryJsonEncode(data) or '{}'
end

local function isValidKvpKey(key)
    return type(key) == 'string' and key ~= '' and #key <= MAX_KVP_KEY_BYTES and not key:find('%c')
end

local function readKvp(key)
    if not isValidKvpKey(key) or type(GetResourceKvpString) ~= 'function' then return nil end

    local ok, value = pcall(GetResourceKvpString, key)
    if not ok or type(value) ~= 'string' or value == '' or #value > MAX_KVP_VALUE_BYTES then return nil end
    return value
end

local function kvpGet(key, fallback)
    return readKvp(key) or fallback
end

local function kvpSet(key, value)
    if not isValidKvpKey(key) or type(SetResourceKvp) ~= 'function' then return false end

    local valueType = type(value)
    if valueType == 'number' and not isFiniteNumber(value) then return false end
    if valueType ~= 'string' and valueType ~= 'number' and valueType ~= 'boolean' then return false end

    local okString, encoded = pcall(tostring, value)
    if not okString or type(encoded) ~= 'string' or #encoded > MAX_KVP_VALUE_BYTES or encoded:find('\0', 1, true) then
        return false
    end

    local ok = pcall(SetResourceKvp, key, encoded)
    if not ok then return false end
end

local function kvpGetJson(key, fallback)
    local decoded = safeJsonDecode(readKvp(key))
    return decoded == nil and fallback or decoded
end

local function kvpSetJson(key, data)
    if not isValidKvpKey(key) or type(SetResourceKvp) ~= 'function' then return false end

    local encoded = tryJsonEncode(data)
    if not encoded or #encoded > MAX_KVP_VALUE_BYTES then return false end

    local ok = pcall(SetResourceKvp, key, encoded)
    if not ok then return false end
end

local function kvpDelete(key)
    if not isValidKvpKey(key) or type(DeleteResourceKvp) ~= 'function' then return false end

    local ok = pcall(DeleteResourceKvp, key)
    if not ok then return false end
end

local function distanceSquared(x1, y1, z1, x2, y2, z2)
    if not isFiniteNumber(x1) or not isFiniteNumber(y1) or not isFiniteNumber(z1) or
       not isFiniteNumber(x2) or not isFiniteNumber(y2) or not isFiniteNumber(z2) then
        return nil
    end

    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    local result = dx * dx + dy * dy + dz * dz
    return isFiniteNumber(result) and result or nil
end

local function distanceSquaredVec(v1, v2)
    local x1, y1, z1 = readFiniteCoords(v1)
    local x2, y2, z2 = readFiniteCoords(v2)
    if not x1 or not x2 then return nil end
    return distanceSquared(x1, y1, z1, x2, y2, z2)
end

local function distance(x1, y1, z1, x2, y2, z2)
    local squared = distanceSquared(x1, y1, z1, x2, y2, z2)
    return squared and sqrt(squared) or nil
end

local function isWithinDistance(x1, y1, z1, x2, y2, z2, radius)
    if not isFiniteNumber(radius) or radius < 0 then return false end

    local squared = distanceSquared(x1, y1, z1, x2, y2, z2)
    local radiusSquared = radius * radius
    return squared ~= nil and isFiniteNumber(radiusSquared) and squared <= radiusSquared
end

local function isWithinDistanceVec(v1, v2, radius)
    if not isFiniteNumber(radius) or radius < 0 then return false end

    local squared = distanceSquaredVec(v1, v2)
    local radiusSquared = radius * radius
    return squared ~= nil and isFiniteNumber(radiusSquared) and squared <= radiusSquared
end

local function shallowCopy(t)
    if type(t) ~= 'table' then return {} end

    local copy = {}
    for key, value in next, t do
        copy[key] = value
    end
    return copy
end

local function mergeDefaults(defaults, overrides)
    local merged = {}
    if type(defaults) == 'table' then
        for key, value in next, defaults do
            merged[key] = value
        end
    end
    if type(overrides) == 'table' then
        for key, value in next, overrides do
            merged[key] = value
        end
    end
    return merged
end

local function parseNumber(value, fallback)
    local num = tonumber(value)
    return isFiniteNumber(num) and num or fallback
end

local function clamp(value, minimum, maximum)
    if not isFiniteNumber(value) or not isFiniteNumber(minimum) or not isFiniteNumber(maximum) or minimum > maximum then
        return nil
    end

    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function round(value, decimals)
    decimals = decimals or 0
    if not isFiniteNumber(value) or not isFiniteNumber(decimals) or decimals % 1 ~= 0 then
        return nil
    end

    local multiplier = 10 ^ decimals
    if not isFiniteNumber(multiplier) or multiplier == 0 then return nil end

    local result = floor(value * multiplier + 0.5) / multiplier
    return isFiniteNumber(result) and result or nil
end

exports('safeJsonDecode', safeJsonDecode)
exports('safeJsonEncode', safeJsonEncode)
exports('kvpGet', kvpGet)
exports('kvpSet', kvpSet)
exports('kvpGetJson', kvpGetJson)
exports('kvpSetJson', kvpSetJson)
exports('kvpDelete', kvpDelete)
exports('distanceSquared', distanceSquared)
exports('distanceSquaredVec', distanceSquaredVec)
exports('distance', distance)
exports('isWithinDistance', isWithinDistance)
exports('isWithinDistanceVec', isWithinDistanceVec)
exports('shallowCopy', shallowCopy)
exports('mergeDefaults', mergeDefaults)
exports('parseNumber', parseNumber)
exports('clamp', clamp)
exports('round', round)

lib.safeJsonDecode = safeJsonDecode
lib.safeJsonEncode = safeJsonEncode
lib.kvpGet = kvpGet
lib.kvpSet = kvpSet
lib.kvpGetJson = kvpGetJson
lib.kvpSetJson = kvpSetJson
lib.kvpDelete = kvpDelete
lib.distanceSquared = distanceSquared
lib.distanceSquaredVec = distanceSquaredVec
lib.distance = distance
lib.isWithinDistance = isWithinDistance
lib.isWithinDistanceVec = isWithinDistanceVec
lib.shallowCopy = shallowCopy
lib.mergeDefaults = mergeDefaults
lib.parseNumber = parseNumber
lib.clamp = clamp
lib.round = round

return {
    safeJsonDecode = safeJsonDecode,
    safeJsonEncode = safeJsonEncode,
    kvpGet = kvpGet,
    kvpSet = kvpSet,
    kvpGetJson = kvpGetJson,
    kvpSetJson = kvpSetJson,
    kvpDelete = kvpDelete,
    distanceSquared = distanceSquared,
    distanceSquaredVec = distanceSquaredVec,
    distance = distance,
    isWithinDistance = isWithinDistance,
    isWithinDistanceVec = isWithinDistanceVec,
    shallowCopy = shallowCopy,
    mergeDefaults = mergeDefaults,
    parseNumber = parseNumber,
    clamp = clamp,
    round = round
}
