local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

_VERSION = 'Lua 5.4'

local threads = {}
local loadCounts = {}
local exportCalls = {}

GetResourceState = function(resource)
    assertEqual(resource, 'cortex-lib', 'loader should check cortex-lib state')
    return 'started'
end
IsDuplicityVersion = function() return false end
GetCurrentResourceName = function() return 'consumer-resource' end
PlayerId = function() return 4 end
GetPlayerServerId = function(playerId) return playerId + 100 end
PlayerPedId = function() return 0 end
GetVehiclePedIsIn = function() return 0 end
GetVehicleMaxNumberOfPassengers = function() return 0 end
GetPedInVehicleSeat = function() return 0 end
Wait = function() end
CreateThread = function(handler) threads[#threads + 1] = handler end

LoadResourceFile = function(resource, path)
    loadCounts[path] = (loadCounts[path] or 0) + 1
    assertEqual(resource, 'cortex-lib', 'external modules should load from cortex-lib')

    if path == 'imports/localutility/client.lua' then
        return "return { marker = 'consumer-local' }"
    end

    return nil
end

exports = setmetatable({}, {
    __index = function(_, resource)
        local resourceExports = { resource = resource }

        return setmetatable(resourceExports, {
            __index = function(self, exportName)
                return function(exportSelf, ...)
                    assertEqual(exportSelf, self, 'proxy should preserve export method invocation')
                    local args = table.pack(...)
                    exportCalls[#exportCalls + 1] = {
                        resource = resource,
                        name = exportName,
                        args = args,
                    }
                    return 'export:' .. exportName, args.n
                end
            end,
        })
    end,
})

local loaded = dofile('init.lua')

local notifyResult = loaded.notify({ description = 'hello' })
assertEqual(notifyResult, 'export:notify', 'cold notify should proxy')
assertEqual(loaded.progress({ duration = 10 }), 'export:progress', 'cold progress should proxy')
assertEqual(loaded.cancelProgress(), 'export:cancelProgress', 'cold cancelProgress should proxy')
assertEqual(loaded.alertDialog({ header = 'confirm' }), 'export:alertDialog', 'cold alertDialog should proxy')
assertEqual(loaded.contextMenu({ title = 'actions' }), 'export:contextMenu', 'cold contextMenu should proxy')
assertEqual(loaded.registerSettings({ id = 'consumer' }), 'export:registerSettings', 'cold settings API should proxy')
assertEqual(loaded.getSetting('notifyPosition'), 'export:getSetting', 'cold setting read should proxy')
assertEqual(loaded.clearPool('objects', {}, 10), 'export:clearPool', 'client utility exports should proxy')
assertEqual(loaded.getPed(), 'export:getPed', 'client getter exports should proxy')
assertEqual(loaded.registerUiApp('consumer-app', function() end), 'export:registerUiApp', 'UI app ownership should stay in cortex-lib')
assertEqual(loaded.copyToClipboard('copy me'), 'export:copyToClipboard', 'clipboard should stay in cortex-lib')
assertEqual(loaded.showDebugPanel({ title = 'debug' }), 'export:showDebugPanel', 'debug panel should stay in cortex-lib')

local utilityProxyCalls = {
    { 'clearPools', { { 'objects', 'peds' }, {}, 10, 0 } },
    { 'findNearestInPool', { 'vehicles', {}, 50, 0 } },
    { 'getPlayerId', {} },
    { 'isInVehicle', { true } },
    { 'getCurrentVehicle', { true } },
    { 'getCoords', {} },
    { 'getHeading', {} },
    { 'ensureVehicle', { false } },
    { 'getCamDirection', {} },
    { 'unregisterUiApp', { 'consumer-app' } },
    { 'openUiApp', { 'consumer-app', { open = true } } },
    { 'updateUiApp', { 'consumer-app', { value = 1 } } },
    { 'closeUiApp', { 'consumer-app' } },
    { 'updateDebugPanel', { { value = 2 } } },
    { 'hideDebugPanel', {} },
    { 'isDebugPanelOpen', {} },
}

for index = 1, #utilityProxyCalls do
    local entry = utilityProxyCalls[index]
    local exportName = entry[1]
    local args = entry[2]
    assertEqual(loaded[exportName](table.unpack(args)), 'export:' .. exportName, exportName .. ' should proxy')
end

local sentinelA = { sentinel = 'a' }
local sentinelB = { sentinel = 'b' }
local callbackSentinel = function() end
local facadeCases = {
    { 'notify', table.pack(sentinelA) },
    { 'hideNotify', table.pack('notify-id') },
    { 'clearNotifications', table.pack() },
    { 'progress', table.pack(sentinelA) },
    { 'cancelProgress', table.pack() },
    { 'isProgressActive', table.pack() },
    { 'alertDialog', table.pack(sentinelA) },
    { 'contextMenu', table.pack(sentinelA) },
    { 'hideContextMenu', table.pack() },
    { 'showTextUI', table.pack('text', sentinelA) },
    { 'hideTextUI', table.pack() },
    { 'notifySuccess', table.pack('message', 'title', sentinelA) },
    { 'notifyError', table.pack('message', 'title', sentinelA) },
    { 'notifyWarning', table.pack('message', 'title', sentinelA) },
    { 'notifyInfo', table.pack('message', 'title', sentinelA) },
    { 'requestAnimDict', table.pack('anim-dict', 1234) },
    { 'requestModel', table.pack(123, 5678) },
    { 'Notify', table.pack('success', 'message', 1000) },
    { 'registerMenu', table.pack(sentinelA, callbackSentinel) },
    { 'showMenu', table.pack('menu-id') },
    { 'hideMenu', table.pack(true) },
    { 'getOpenMenu', table.pack() },
    { 'setMenuOptions', table.pack('menu-id', sentinelA, 2) },
    { 'addRadialItem', table.pack(sentinelA) },
    { 'removeRadialItem', table.pack('radial-id') },
    { 'clearRadialItems', table.pack() },
    { 'registerRadial', table.pack(sentinelA) },
    { 'showRadial', table.pack('radial-id') },
    { 'hideRadial', table.pack(true) },
    { 'disableRadial', table.pack(true) },
    { 'isRadialOpen', table.pack() },
    { 'isRadialDisabled', table.pack() },
    { 'getCurrentRadialId', table.pack() },
    { 'showHelp', table.pack(sentinelA) },
    { 'hideHelp', table.pack() },
    { 'registerSettings', table.pack('tab', 'Tab', 'prefix', sentinelA, sentinelB) },
    { 'registerSettingsScript', table.pack('script', sentinelA) },
    { 'openSettings', table.pack() },
    { 'openSettingsMenu', table.pack() },
    { 'closeSettings', table.pack() },
    { 'closeSettingsMenu', table.pack() },
    { 'getSetting', table.pack('setting') },
    { 'getAllSettings', table.pack() },
    { 'setSetting', table.pack('setting', sentinelA) },
    { 'saveSetting', table.pack('setting', sentinelA) },
    { 'getTabSetting', table.pack('tab', 'setting') },
    { 'onSettingChange', table.pack('setting', callbackSentinel) },
    { 'getNotifySoundCatalog', table.pack() },
    { 'clearPool', table.pack('objects', sentinelA, 10, 22) },
    { 'clearPools', table.pack(sentinelA, sentinelB, 10, 22) },
    { 'findNearestInPool', table.pack('vehicles', sentinelA, 50, 22) },
    { 'getPed', table.pack() },
    { 'getPlayerId', table.pack() },
    { 'isInVehicle', table.pack(true) },
    { 'getCurrentVehicle', table.pack(true) },
    { 'getCoords', table.pack() },
    { 'getHeading', table.pack() },
    { 'ensureVehicle', table.pack(true) },
    { 'getCamDirection', table.pack() },
    { 'copyToClipboard', table.pack('clipboard') },
    { 'registerUiApp', table.pack('app-id', callbackSentinel) },
    { 'unregisterUiApp', table.pack('app-id') },
    { 'openUiApp', table.pack('app-id', sentinelA) },
    { 'updateUiApp', table.pack('app-id', sentinelA) },
    { 'closeUiApp', table.pack('app-id') },
    { 'showDebugPanel', table.pack(sentinelA) },
    { 'updateDebugPanel', table.pack(sentinelA) },
    { 'hideDebugPanel', table.pack() },
    { 'isDebugPanelOpen', table.pack() },
    { 'showInteraction', table.pack(sentinelA) },
    { 'hideInteraction', table.pack('interaction-id') },
    { 'setInteractions', table.pack(sentinelA) },
    { 'clearInteractions', table.pack() },
    { 'getInteractions', table.pack() },
    { 'getInteractionState', table.pack('interaction-id') },
    { 'isInteractionActive', table.pack('interaction-id') },
    { 'isInteractionVisible', table.pack('interaction-id') },
    { 'startInteractionHold', table.pack('interaction-id') },
    { 'cancelInteractionHold', table.pack('interaction-id') },
}

for index = 1, #facadeCases do
    local facadeCase = facadeCases[index]
    local exportName = facadeCase[1]
    local expectedArgs = facadeCase[2]
    local callIndex = #exportCalls + 1
    local result, forwardedCount = loaded[exportName](table.unpack(expectedArgs, 1, expectedArgs.n))
    local call = exportCalls[callIndex]

    assertEqual(result, 'export:' .. exportName, exportName .. ' should preserve its return value')
    assertEqual(forwardedCount, expectedArgs.n, exportName .. ' should preserve argument count')
    assertEqual(call.args.n, expectedArgs.n, exportName .. ' should forward the exact argument count')

    for argumentIndex = 1, expectedArgs.n do
        assertEqual(call.args[argumentIndex], expectedArgs[argumentIndex], exportName .. ' should preserve argument identity')
    end
end

local notifyModule = loaded('notify')
assertEqual(notifyModule, loaded.notify, 'notify module should retain its callable return shape')
assertEqual(loadCounts['imports/notify/client.lua'], nil, 'notify code must not execute in a consumer')

local menu = loaded('menu')
assertEqual(menu, loaded('menu'), 'menu module should be cached')
assertEqual(menu.showMenu('main'), 'export:showMenu', 'menu module method should proxy')

local radial = loaded('radial')
assertEqual(radial.showRadial('vehicle'), 'export:showRadial', 'radial module method should proxy')

local help = loaded('help')
assertEqual(help.showHelp({ key = 'E' }), 'export:showHelp', 'help module method should proxy')

local settings = loaded('settings')
assertEqual(settings.onSettingChange('key', function() end), 'export:onSettingChange', 'settings module method should proxy')

local interaction = loaded('interaction')
assertEqual(interaction.show({ id = 'inspect' }), 'export:showInteraction', 'interaction module method should proxy')
assertEqual(interaction.get(), 'export:getInteractions', 'interaction module should preserve its get method')

for _, moduleName in ipairs({ 'menu', 'radial', 'help', 'settings', 'interaction' }) do
    assertEqual(loadCounts[('imports/%s/client.lua'):format(moduleName)], nil, moduleName .. ' code must not execute in a consumer')
end

local utility = loaded('localutility')
assertEqual(utility.marker, 'consumer-local', 'ordinary utility module should remain consumer-local')
assertEqual(loaded('localutility'), utility, 'call syntax should return cached local module')
assertEqual(loadCounts['imports/localutility/client.lua'], 1, 'cached call syntax should load local code once')

assertEqual(exportCalls[1].resource, 'cortex-lib', 'UI proxies should target cortex-lib')

print('external loader proxy spec: PASS')
