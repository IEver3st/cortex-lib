local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

local loadCounts = {}

IsDuplicityVersion = function() return false end
GetCurrentResourceName = function() return 'cortex-lib' end
PlayerId = function() return 2 end
GetPlayerServerId = function(playerId) return playerId + 10 end
PlayerPedId = function() return 0 end
GetVehiclePedIsIn = function() return 0 end
GetVehicleMaxNumberOfPassengers = function() return 0 end
GetPedInVehicleSeat = function() return 0 end
Wait = function() end
CreateThread = function() end
AddEventHandler = function() end
TriggerEvent = function() end
exports = function() end

LoadResourceFile = function(resource, path)
    loadCounts[path] = (loadCounts[path] or 0) + 1
    assertEqual(resource, 'cortex-lib', 'internal modules should load from cortex-lib')

    if path == 'imports/localutility/client.lua' then
        return "return { marker = 'internal-local' }"
    end

    return nil
end

local loaded = dofile('resource/init.lua')
local utility = loaded('localutility')

assertEqual(utility.marker, 'internal-local', 'internal module should load normally')
assertEqual(loaded('localutility'), utility, 'internal call syntax should return cached module')
assertEqual(loadCounts['imports/localutility/client.lua'], 1, 'internal call syntax should load a module once')

print('internal loader cache spec: PASS')
