local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

local clientMembers = {
    getClosestPlayer = 'imports/getters/client.lua',
    getClosestVehicle = 'imports/getters/client.lua',
    getClosestPed = 'imports/getters/client.lua',
    getClosestObject = 'imports/getters/client.lua',
    getNearbyPlayers = 'imports/getters/client.lua',
    getNearbyVehicles = 'imports/getters/client.lua',
    getNearbyPeds = 'imports/getters/client.lua',
    getNearbyObjects = 'imports/getters/client.lua',
    disableControls = 'imports/disablecontrols/client.lua',
}

local utilityMembers = {
    safeJsonDecode = 'imports/utils/shared.lua',
    safeJsonEncode = 'imports/utils/shared.lua',
    kvpGet = 'imports/utils/shared.lua',
    kvpSet = 'imports/utils/shared.lua',
    kvpGetJson = 'imports/utils/shared.lua',
    kvpSetJson = 'imports/utils/shared.lua',
    kvpDelete = 'imports/utils/shared.lua',
    distanceSquared = 'imports/utils/shared.lua',
    distanceSquaredVec = 'imports/utils/shared.lua',
    distance = 'imports/utils/shared.lua',
    isWithinDistance = 'imports/utils/shared.lua',
    isWithinDistanceVec = 'imports/utils/shared.lua',
    shallowCopy = 'imports/utils/shared.lua',
    mergeDefaults = 'imports/utils/shared.lua',
    parseNumber = 'imports/utils/shared.lua',
    clamp = 'imports/utils/shared.lua',
    round = 'imports/utils/shared.lua',
}

local function fixtureSource(memberNames, returnMember)
    local quoted = {}
    for index = 1, #memberNames do
        quoted[index] = ("'%s'"):format(memberNames[index])
    end

    return ([[
local module = {}
for _, memberName in ipairs({ %s }) do
    local handler = function() end
    lib[memberName] = handler
    exports(memberName, handler)
    module[memberName] = handler
end
return %s
]]):format(table.concat(quoted, ', '), returnMember and ('module.' .. returnMember) or 'module')
end

local moduleSources = {
    ['imports/getters/client.lua'] = fixtureSource({
        'getClosestPlayer', 'getClosestVehicle', 'getClosestPed', 'getClosestObject',
        'getNearbyPlayers', 'getNearbyVehicles', 'getNearbyPeds', 'getNearbyObjects',
    }),
    ['imports/disablecontrols/client.lua'] = fixtureSource({ 'disableControls' }, 'disableControls'),
    ['imports/utils/shared.lua'] = fixtureSource({
        'safeJsonDecode', 'safeJsonEncode', 'kvpGet', 'kvpSet', 'kvpGetJson', 'kvpSetJson',
        'kvpDelete', 'distanceSquared', 'distanceSquaredVec', 'distance', 'isWithinDistance',
        'isWithinDistanceVec', 'shallowCopy', 'mergeDefaults', 'parseNumber', 'clamp', 'round',
    }),
}

local function verifyMember(memberName, expectedPath, server)
    local allowFiles = false
    local successfulLoads = {}

    IsDuplicityVersion = function() return server end
    GetCurrentResourceName = function() return 'cortex-lib' end
    PlayerId = function() return 1 end
    GetPlayerServerId = function(playerId) return playerId + 10 end
    PlayerPedId = function() return 0 end
    GetVehiclePedIsIn = function() return 0 end
    GetVehicleMaxNumberOfPassengers = function() return 0 end
    GetPedInVehicleSeat = function() return 0 end
    CreateThread = function() end
    Wait = function() end
    AddEventHandler = function() end
    TriggerEvent = function() end
    exports = function() end

    LoadResourceFile = function(resource, path)
        assertEqual(resource, 'cortex-lib', 'internal member aliases should load from cortex-lib')
        if not allowFiles then return nil end

        local content = moduleSources[path]
        if content then
            successfulLoads[path] = (successfulLoads[path] or 0) + 1
        end
        return content
    end

    local loaded = dofile('resource/init.lua')
    assertEqual(rawget(loaded, memberName), nil, memberName .. ' should remain cold when bootstrap source is unavailable')

    allowFiles = true
    local handler = loaded[memberName]
    assertEqual(type(handler), 'function', memberName .. ' should resolve through the internal alias map')
    assertEqual(successfulLoads[expectedPath], 1, memberName .. ' should load its owning internal module once')
    assertEqual(loaded[memberName], handler, memberName .. ' should cache its internal member')
    assertEqual(successfulLoads[expectedPath], 1, memberName .. ' should not reload internally')
end

for memberName, path in pairs(clientMembers) do
    verifyMember(memberName, path, false)
end

for memberName, path in pairs(utilityMembers) do
    verifyMember(memberName, path, false)
    verifyMember(memberName, path, true)
end

print('internal cold member alias spec: PASS')
