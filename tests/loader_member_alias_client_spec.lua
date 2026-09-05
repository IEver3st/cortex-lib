local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

_VERSION = 'Lua 5.4'

local expectedMembers = {
    getClosestPlayer = { module = 'getters', path = 'imports/getters/client.lua' },
    getClosestVehicle = { module = 'getters', path = 'imports/getters/client.lua' },
    getClosestPed = { module = 'getters', path = 'imports/getters/client.lua' },
    getClosestObject = { module = 'getters', path = 'imports/getters/client.lua' },
    getNearbyPlayers = { module = 'getters', path = 'imports/getters/client.lua' },
    getNearbyVehicles = { module = 'getters', path = 'imports/getters/client.lua' },
    getNearbyPeds = { module = 'getters', path = 'imports/getters/client.lua' },
    getNearbyObjects = { module = 'getters', path = 'imports/getters/client.lua' },
    disableControls = { module = 'disablecontrols', path = 'imports/disablecontrols/client.lua' },
    safeJsonDecode = { module = 'utils', path = 'imports/utils/shared.lua' },
    safeJsonEncode = { module = 'utils', path = 'imports/utils/shared.lua' },
    kvpGet = { module = 'utils', path = 'imports/utils/shared.lua' },
    kvpSet = { module = 'utils', path = 'imports/utils/shared.lua' },
    kvpGetJson = { module = 'utils', path = 'imports/utils/shared.lua' },
    kvpSetJson = { module = 'utils', path = 'imports/utils/shared.lua' },
    kvpDelete = { module = 'utils', path = 'imports/utils/shared.lua' },
    distanceSquared = { module = 'utils', path = 'imports/utils/shared.lua' },
    distanceSquaredVec = { module = 'utils', path = 'imports/utils/shared.lua' },
    distance = { module = 'utils', path = 'imports/utils/shared.lua' },
    isWithinDistance = { module = 'utils', path = 'imports/utils/shared.lua' },
    isWithinDistanceVec = { module = 'utils', path = 'imports/utils/shared.lua' },
    shallowCopy = { module = 'utils', path = 'imports/utils/shared.lua' },
    mergeDefaults = { module = 'utils', path = 'imports/utils/shared.lua' },
    parseNumber = { module = 'utils', path = 'imports/utils/shared.lua' },
    clamp = { module = 'utils', path = 'imports/utils/shared.lua' },
    round = { module = 'utils', path = 'imports/utils/shared.lua' },
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

for memberName, expected in pairs(expectedMembers) do
    local loadCounts = {}
    local centralProxyCalls = 0

    GetResourceState = function() return 'started' end
    IsDuplicityVersion = function() return false end
    GetCurrentResourceName = function() return 'consumer-client' end
    PlayerId = function() return 1 end
    GetPlayerServerId = function(playerId) return playerId + 10 end
    PlayerPedId = function() return 0 end
    GetVehiclePedIsIn = function() return 0 end
    GetVehicleMaxNumberOfPassengers = function() return 0 end
    GetPedInVehicleSeat = function() return 0 end
    CreateThread = function() end
    Wait = function() end

    LoadResourceFile = function(resource, path)
        assertEqual(resource, 'cortex-lib', 'member aliases should load from cortex-lib')
        loadCounts[path] = (loadCounts[path] or 0) + 1
        return moduleSources[path]
    end

    exports = setmetatable({}, {
        __call = function() end,
        __index = function()
            local resourceExports = {}
            return setmetatable(resourceExports, {
                __index = function()
                    return function()
                        centralProxyCalls = centralProxyCalls + 1
                    end
                end,
            })
        end,
    })

    local loaded = dofile('init.lua')
    assertEqual(rawget(loaded, memberName), nil, memberName .. ' should begin cold in a consumer')

    local handler = loaded[memberName]
    assertEqual(type(handler), 'function', memberName .. ' should resolve to its consumer-local function')
    assertEqual(loadCounts[expected.path], 1, memberName .. ' should load its actual module once')
    assertEqual(rawget(loaded, expected.module) ~= nil, true, memberName .. ' should cache its owning module')
    assertEqual(loaded[memberName], handler, memberName .. ' should cache its resolved member')
    assertEqual(loadCounts[expected.path], 1, memberName .. ' should not reload after member caching')
    assertEqual(centralProxyCalls, 0, memberName .. ' must not proxy consumer-local execution to cortex-lib')
end

print('client cold member alias spec: PASS')
