local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

_VERSION = 'Lua 5.4'

local utilityMembers = {
    'safeJsonDecode',
    'safeJsonEncode',
    'kvpGet',
    'kvpSet',
    'kvpGetJson',
    'kvpSetJson',
    'kvpDelete',
    'distanceSquared',
    'distanceSquaredVec',
    'distance',
    'isWithinDistance',
    'isWithinDistanceVec',
    'shallowCopy',
    'mergeDefaults',
    'parseNumber',
    'clamp',
    'round',
}

local utilitySource = [[
local module = {}
for _, memberName in ipairs({
    'safeJsonDecode', 'safeJsonEncode', 'kvpGet', 'kvpSet', 'kvpGetJson', 'kvpSetJson',
    'kvpDelete', 'distanceSquared', 'distanceSquaredVec', 'distance', 'isWithinDistance',
    'isWithinDistanceVec', 'shallowCopy', 'mergeDefaults', 'parseNumber', 'clamp', 'round'
}) do
    local handler = function() end
    lib[memberName] = handler
    exports(memberName, handler)
    module[memberName] = handler
end
return module
]]

for index = 1, #utilityMembers do
    local memberName = utilityMembers[index]
    local loadCounts = {}
    local centralProxyCalls = 0

    GetResourceState = function() return 'started' end
    IsDuplicityVersion = function() return true end
    GetCurrentResourceName = function() return 'consumer-server' end
    LoadResourceFile = function(resource, path)
        assertEqual(resource, 'cortex-lib', 'server member aliases should load from cortex-lib')
        loadCounts[path] = (loadCounts[path] or 0) + 1
        return path == 'imports/utils/shared.lua' and utilitySource or nil
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
    assertEqual(rawget(loaded, memberName), nil, memberName .. ' should begin cold on a consumer server')

    local handler = loaded[memberName]
    assertEqual(type(handler), 'function', memberName .. ' should resolve from shared utils on the server')
    assertEqual(loadCounts['imports/utils/shared.lua'], 1, memberName .. ' should load shared utils once')
    assertEqual(rawget(loaded, 'utils') ~= nil, true, memberName .. ' should cache the shared utils module')
    assertEqual(loaded[memberName], handler, memberName .. ' should cache its resolved server member')
    assertEqual(loadCounts['imports/utils/shared.lua'], 1, memberName .. ' should not reload shared utils')
    assertEqual(centralProxyCalls, 0, memberName .. ' must remain server-consumer-local')
end

GetResourceState = function() return 'started' end
IsDuplicityVersion = function() return true end
GetCurrentResourceName = function() return 'consumer-server' end
LoadResourceFile = function() return nil end
exports = setmetatable({}, {
    __index = function()
        return setmetatable({}, { __index = function() return function() end end })
    end,
})
local serverLib = dofile('init.lua')
assertEqual(serverLib.getClosestPlayer, nil, 'client-only getter aliases must not appear on the server')
assertEqual(serverLib.disableControls, nil, 'client-only control aliases must not appear on the server')

print('server cold member alias spec: PASS')
