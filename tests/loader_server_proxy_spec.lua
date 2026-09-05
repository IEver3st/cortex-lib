local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

_VERSION = 'Lua 5.4'

local loadCounts = {}

GetResourceState = function() return 'started' end
IsDuplicityVersion = function() return true end
GetCurrentResourceName = function() return 'consumer-server' end

LoadResourceFile = function(resource, path)
    loadCounts[path] = (loadCounts[path] or 0) + 1
    assertEqual(resource, 'cortex-lib', 'external server modules should load from cortex-lib')

    if path == 'imports/localutility/server.lua' then
        return "return { marker = 'server-local' }"
    end

    return nil
end


exports = setmetatable({}, {
    __index = function(_, resource)
        local resourceExports = { resource = resource }

        return setmetatable(resourceExports, {
            __index = function(self, exportName)
                return function(exportSelf, ...)
                    assertEqual(exportSelf, self, 'server proxy should preserve method invocation')
                    return 'export:' .. exportName, select('#', ...)
                end
            end,
        })
    end,
})

local loaded = dofile('init.lua')

local result, forwarded = loaded.notify(42, { description = 'hello' })
assertEqual(result, 'export:notify', 'server notify should proxy')
assertEqual(forwarded, 2, 'server notify should forward both arguments')
result, forwarded = loaded.notifyAll({ description = 'hello all' })
assertEqual(result, 'export:notifyAll', 'server notifyAll should proxy')
assertEqual(forwarded, 1, 'server notifyAll should forward its argument')
result, forwarded = loaded.Notify(42, 'success', 'done', 1000)
assertEqual(result, 'export:Notify', 'legacy server Notify should proxy')
assertEqual(forwarded, 4, 'legacy server Notify should forward all arguments')
assertEqual(loaded('notify'), loaded.notify, 'server notify module should preserve callable return shape')
assertEqual(loadCounts['imports/notify/server.lua'], nil, 'server notify code must not execute in a consumer')

local utility = loaded('localutility')
assertEqual(utility.marker, 'server-local', 'ordinary server utility should stay lazy-local')
assertEqual(loaded('localutility'), utility, 'server utility should be cached')
assertEqual(loadCounts['imports/localutility/server.lua'], 1, 'server utility should load once')

print('server loader proxy spec: PASS')
