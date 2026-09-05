if not _VERSION:find('5.4') then
    error('^1[cortex-lib] Lua 5.4 is required. Add `lua54 \'yes\'` to your fxmanifest.lua^0')
end

local libResourceName = 'cortex-lib'

if GetResourceState(libResourceName) ~= 'started' then
    error('^1[cortex-lib] cortex-lib must be started before this resource^0')
end

local context = IsDuplicityVersion() and 'server' or 'client'

local cache = {}

if context == 'client' then
    cache = setmetatable({
        ped = nil,
        playerId = nil,
        serverId = nil,
        vehicle = 0,
        seat = -1,
    }, {
        __index = function(self, key)
            return rawget(self, key)
        end,
        __newindex = function(self, key, value)
            rawset(self, key, value)
        end,
    })

    local GetPedInVehicleSeat = GetPedInVehicleSeat
    local GetVehicleMaxNumberOfPassengers = GetVehicleMaxNumberOfPassengers
    local GetVehiclePedIsIn = GetVehiclePedIsIn
    local PlayerId = PlayerId
    local PlayerPedId = PlayerPedId

    local function findPedSeat(vehicle, ped)
        local passengerCount = math.max(0, math.floor(tonumber(GetVehicleMaxNumberOfPassengers(vehicle)) or 0))

        for seat = -1, passengerCount - 1 do
            if GetPedInVehicleSeat(vehicle, seat) == ped then
                return seat
            end
        end

        return -1
    end

    cache.playerId = PlayerId()
    cache.serverId = GetPlayerServerId(cache.playerId)

    CreateThread(function()
        while true do
            local playerId = PlayerId()
            if playerId ~= cache.playerId then
                cache.playerId = playerId
                cache.serverId = GetPlayerServerId(playerId)
            end

            local ped = PlayerPedId()
            cache.ped = ped

            if ped ~= 0 then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle > 0 then
                    local vehicleChanged = vehicle ~= cache.vehicle
                    cache.vehicle = vehicle
                    local seat = cache.seat

                    if vehicleChanged or type(seat) ~= 'number' or GetPedInVehicleSeat(vehicle, seat) ~= ped then
                        cache.seat = findPedSeat(vehicle, ped)
                    end
                else
                    cache.vehicle = 0
                    cache.seat = -1
                end
            else
                cache.vehicle = 0
                cache.seat = -1
            end

            Wait(100)
        end
    end)
end

local memberModules = {
    safeJsonDecode = 'utils',
    safeJsonEncode = 'utils',
    kvpGet = 'utils',
    kvpSet = 'utils',
    kvpGetJson = 'utils',
    kvpSetJson = 'utils',
    kvpDelete = 'utils',
    distanceSquared = 'utils',
    distanceSquaredVec = 'utils',
    distance = 'utils',
    isWithinDistance = 'utils',
    isWithinDistanceVec = 'utils',
    shallowCopy = 'utils',
    mergeDefaults = 'utils',
    parseNumber = 'utils',
    clamp = 'utils',
    round = 'utils',
}

if context == 'client' then
    memberModules.getClosestPlayer = 'getters'
    memberModules.getClosestVehicle = 'getters'
    memberModules.getClosestPed = 'getters'
    memberModules.getClosestObject = 'getters'
    memberModules.getNearbyPlayers = 'getters'
    memberModules.getNearbyVehicles = 'getters'
    memberModules.getNearbyPeds = 'getters'
    memberModules.getNearbyObjects = 'getters'
    memberModules.disableControls = 'disablecontrols'
end

local clientOwnedModules = {
    menu = function(self)
        return {
            registerMenu = self.registerMenu,
            showMenu = self.showMenu,
            hideMenu = self.hideMenu,
            getOpenMenu = self.getOpenMenu,
            setMenuOptions = self.setMenuOptions,
        }
    end,
    radial = function(self)
        return {
            addRadialItem = self.addRadialItem,
            removeRadialItem = self.removeRadialItem,
            clearRadialItems = self.clearRadialItems,
            registerRadial = self.registerRadial,
            showRadial = self.showRadial,
            hideRadial = self.hideRadial,
            disableRadial = self.disableRadial,
            isRadialOpen = self.isRadialOpen,
            isRadialDisabled = self.isRadialDisabled,
            getCurrentRadialId = self.getCurrentRadialId,
        }
    end,
    help = function(self)
        return {
            showHelp = self.showHelp,
            hideHelp = self.hideHelp,
        }
    end,
    settings = function(self)
        return {
            registerSettings = self.registerSettings,
            registerSettingsScript = self.registerSettingsScript,
            openSettings = self.openSettings,
            openSettingsMenu = self.openSettingsMenu,
            closeSettings = self.closeSettings,
            closeSettingsMenu = self.closeSettingsMenu,
            getSetting = self.getSetting,
            getAllSettings = self.getAllSettings,
            setSetting = self.setSetting,
            saveSetting = self.saveSetting,
            getTabSetting = self.getTabSetting,
            onSettingChange = self.onSettingChange,
            getNotifySoundCatalog = self.getNotifySoundCatalog,
        }
    end,
    interaction = function(self)
        return {
            show = self.showInteraction,
            hide = self.hideInteraction,
            set = self.setInteractions,
            clear = self.clearInteractions,
            get = self.getInteractions,
            getState = self.getInteractionState,
            isActive = self.isInteractionActive,
            isVisible = self.isInteractionVisible,
            startHold = self.startInteractionHold,
            cancelHold = self.cancelInteractionHold,
        }
    end,
}

local function callCortexExport(exportName, ...)
    local resourceExports = exports[libResourceName]
    local exportHandler = resourceExports[exportName]

    return exportHandler(resourceExports, ...)
end

local function loadModule(self, moduleName)
    if type(moduleName) ~= 'string' or moduleName == '' then
        error('module name must be a non-empty string', 2)
    end

    local cached = rawget(self, moduleName)
    if cached ~= nil then
        return cached
    end

    local memberModule = memberModules[moduleName]
    if memberModule then
        local loadedModule = loadModule(self, memberModule)
        local member = rawget(self, moduleName)

        if member == nil and type(loadedModule) == 'table' then
            member = loadedModule[moduleName]
        end

        if member ~= nil then
            rawset(self, moduleName, member)
        end

        return member
    end

    if context == 'client' then
        local createOwnedModule = clientOwnedModules[moduleName]

        if createOwnedModule then
            local result = createOwnedModule(self)
            rawset(self, moduleName, result)
            return result
        end
    end

    local dir = ('imports/%s'):format(moduleName)
    
    local chunk = LoadResourceFile(libResourceName, ('%s/%s.lua'):format(dir, context))
    
    local shared = LoadResourceFile(libResourceName, ('%s/shared.lua'):format(dir))
    
    if shared then
        chunk = chunk and ('%s\n%s'):format(shared, chunk) or shared
    end
    
    if not chunk then
        return nil
    end
    
    local fn, err = load(chunk, ('@@cortex-lib/imports/%s/%s.lua'):format(moduleName, context))
    
    if not fn then
        error(('^1[cortex-lib] Error loading module %s: %s^0'):format(moduleName, err))
    end
    
    local result = fn()
    
    if result ~= nil then
        rawset(self, moduleName, result)
    else
        rawset(self, moduleName, function() end)
    end
    
    return rawget(self, moduleName)
end

lib = setmetatable({
    name = libResourceName,
    context = context,
    cache = cache,
}, {
    __index = loadModule,
    __call = function(self, moduleName)
        return loadModule(self, moduleName)
    end,
})

_ENV.lib = lib
_ENV.cache = cache

function lib.load(moduleName)
    if rawget(lib, moduleName) then
        return rawget(lib, moduleName)
    end
    return loadModule(lib, moduleName)
end

function lib.isInternalResource()
    return GetCurrentResourceName() == libResourceName
end

lib._moduleCache = rawget(lib, '_moduleCache') or {}

function lib.require(modulePath)
    local resource = GetCurrentResourceName()
    local cacheKey = resource .. ':' .. modulePath

    if lib._moduleCache[cacheKey] ~= nil then
        return lib._moduleCache[cacheKey]
    end

    local filePath = modulePath:gsub('%.', '/') .. '.lua'
    local code = LoadResourceFile(resource, filePath)
    if not code then
        error(('lib.require: missing module "%s" (%s) in %s'):format(modulePath, filePath, resource))
    end

    local chunk, err = load(code, ('@%s/%s'):format(resource, filePath), 't', _ENV)
    if not chunk then
        error(('lib.require: compile error in "%s": %s'):format(filePath, err))
    end

    local result = chunk()
    if result == nil then
        result = true
    end

    lib._moduleCache[cacheKey] = result
    return result
end

if context == 'client' then
    -- cortex-lib owns the shared NUI and its stateful UI registries. Resolve
    -- these exports at call time so consumers do not execute the UI imports in
    -- their own resource environment.
    function lib.notify(data)
        return callCortexExport('notify', data)
    end

    function lib.hideNotify(id)
        return callCortexExport('hideNotify', id)
    end

    function lib.clearNotifications()
        return callCortexExport('clearNotifications')
    end

    function lib.progress(data)
        return callCortexExport('progress', data)
    end

    function lib.cancelProgress()
        return callCortexExport('cancelProgress')
    end

    function lib.isProgressActive()
        return callCortexExport('isProgressActive')
    end

    function lib.alertDialog(data)
        return callCortexExport('alertDialog', data)
    end

    function lib.contextMenu(data)
        return callCortexExport('contextMenu', data)
    end

    function lib.hideContextMenu()
        return callCortexExport('hideContextMenu')
    end

    function lib.showTextUI(text, options)
        return callCortexExport('showTextUI', text, options)
    end

    function lib.hideTextUI()
        return callCortexExport('hideTextUI')
    end

    function lib.notifySuccess(message, title, sound)
        return callCortexExport('notifySuccess', message, title, sound)
    end

    function lib.notifyError(message, title, sound)
        return callCortexExport('notifyError', message, title, sound)
    end

    function lib.notifyWarning(message, title, sound)
        return callCortexExport('notifyWarning', message, title, sound)
    end

    function lib.notifyInfo(message, title, sound)
        return callCortexExport('notifyInfo', message, title, sound)
    end

    function lib.requestAnimDict(dict, timeout)
        return callCortexExport('requestAnimDict', dict, timeout)
    end

    function lib.requestModel(model, timeout)
        return callCortexExport('requestModel', model, timeout)
    end

    function lib.Notify(notifyType, message, duration)
        return callCortexExport('Notify', notifyType, message, duration)
    end

    function lib.registerMenu(data, cb)
        return callCortexExport('registerMenu', data, cb)
    end

    function lib.showMenu(id)
        return callCortexExport('showMenu', id)
    end

    function lib.hideMenu(runOnClose)
        return callCortexExport('hideMenu', runOnClose)
    end

    function lib.getOpenMenu()
        return callCortexExport('getOpenMenu')
    end

    function lib.setMenuOptions(id, options, index)
        return callCortexExport('setMenuOptions', id, options, index)
    end

    function lib.addRadialItem(items)
        return callCortexExport('addRadialItem', items)
    end

    function lib.removeRadialItem(id)
        return callCortexExport('removeRadialItem', id)
    end

    function lib.clearRadialItems()
        return callCortexExport('clearRadialItems')
    end

    function lib.registerRadial(data)
        return callCortexExport('registerRadial', data)
    end

    function lib.showRadial(id)
        return callCortexExport('showRadial', id)
    end

    function lib.hideRadial(skipTransition)
        return callCortexExport('hideRadial', skipTransition)
    end

    function lib.disableRadial(disabled)
        return callCortexExport('disableRadial', disabled)
    end

    function lib.isRadialOpen()
        return callCortexExport('isRadialOpen')
    end

    function lib.isRadialDisabled()
        return callCortexExport('isRadialDisabled')
    end

    function lib.getCurrentRadialId()
        return callCortexExport('getCurrentRadialId')
    end

    function lib.showHelp(data)
        return callCortexExport('showHelp', data)
    end

    function lib.hideHelp()
        return callCortexExport('hideHelp')
    end

    function lib.registerSettings(tabId, tabLabel, kvpPrefix, fields, defaults)
        return callCortexExport('registerSettings', tabId, tabLabel, kvpPrefix, fields, defaults)
    end

    function lib.registerSettingsScript(scriptId, definition)
        return callCortexExport('registerSettingsScript', scriptId, definition)
    end

    function lib.openSettings()
        return callCortexExport('openSettings')
    end

    function lib.openSettingsMenu()
        return callCortexExport('openSettingsMenu')
    end

    function lib.closeSettings()
        return callCortexExport('closeSettings')
    end

    function lib.closeSettingsMenu()
        return callCortexExport('closeSettingsMenu')
    end

    function lib.getSetting(key)
        return callCortexExport('getSetting', key)
    end

    function lib.getAllSettings()
        return callCortexExport('getAllSettings')
    end

    function lib.setSetting(key, value)
        return callCortexExport('setSetting', key, value)
    end

    function lib.saveSetting(key, value)
        return callCortexExport('saveSetting', key, value)
    end

    function lib.getTabSetting(tabId, fieldId)
        return callCortexExport('getTabSetting', tabId, fieldId)
    end

    function lib.onSettingChange(key, callback)
        return callCortexExport('onSettingChange', key, callback)
    end

    function lib.getNotifySoundCatalog()
        return callCortexExport('getNotifySoundCatalog')
    end

    function lib.clearPool(poolName, centerCoords, radius, excludeEntity)
        return callCortexExport('clearPool', poolName, centerCoords, radius, excludeEntity)
    end

    function lib.clearPools(poolNames, centerCoords, radius, excludeEntity)
        return callCortexExport('clearPools', poolNames, centerCoords, radius, excludeEntity)
    end

    function lib.findNearestInPool(poolName, centerCoords, maxRadius, excludeEntity)
        return callCortexExport('findNearestInPool', poolName, centerCoords, maxRadius, excludeEntity)
    end

    function lib.getPed()
        return callCortexExport('getPed')
    end

    function lib.getPlayerId()
        return callCortexExport('getPlayerId')
    end

    function lib.isInVehicle(includeLastVehicle)
        return callCortexExport('isInVehicle', includeLastVehicle)
    end

    function lib.getCurrentVehicle(includeLastVehicle)
        return callCortexExport('getCurrentVehicle', includeLastVehicle)
    end

    function lib.getCoords()
        return callCortexExport('getCoords')
    end

    function lib.getHeading()
        return callCortexExport('getHeading')
    end

    function lib.ensureVehicle(showNotify)
        return callCortexExport('ensureVehicle', showNotify)
    end

    function lib.getCamDirection()
        return callCortexExport('getCamDirection')
    end

    function lib.copyToClipboard(text)
        return callCortexExport('copyToClipboard', text)
    end

    function lib.registerUiApp(appId, handler)
        return callCortexExport('registerUiApp', appId, handler)
    end

    function lib.unregisterUiApp(appId)
        return callCortexExport('unregisterUiApp', appId)
    end

    function lib.openUiApp(appId, payload)
        return callCortexExport('openUiApp', appId, payload)
    end

    function lib.updateUiApp(appId, payload)
        return callCortexExport('updateUiApp', appId, payload)
    end

    function lib.closeUiApp(appId)
        return callCortexExport('closeUiApp', appId)
    end

    function lib.showDebugPanel(data)
        return callCortexExport('showDebugPanel', data)
    end

    function lib.updateDebugPanel(data)
        return callCortexExport('updateDebugPanel', data)
    end

    function lib.hideDebugPanel()
        return callCortexExport('hideDebugPanel')
    end

    function lib.isDebugPanelOpen()
        return callCortexExport('isDebugPanelOpen')
    end

    function lib.showInteraction(data)
        return callCortexExport('showInteraction', data)
    end

    function lib.hideInteraction(id)
        return callCortexExport('hideInteraction', id)
    end

    function lib.setInteractions(items)
        return callCortexExport('setInteractions', items)
    end

    function lib.clearInteractions()
        return callCortexExport('clearInteractions')
    end

    function lib.getInteractions()
        return callCortexExport('getInteractions')
    end

    function lib.getInteractionState(id)
        return callCortexExport('getInteractionState', id)
    end

    function lib.isInteractionActive(id)
        return callCortexExport('isInteractionActive', id)
    end

    function lib.isInteractionVisible(id)
        return callCortexExport('isInteractionVisible', id)
    end

    function lib.startInteractionHold(id)
        return callCortexExport('startInteractionHold', id)
    end

    function lib.cancelInteractionHold(id)
        return callCortexExport('cancelInteractionHold', id)
    end
else
    function lib.notify(target, data)
        return callCortexExport('notify', target, data)
    end

    function lib.notifyAll(data)
        return callCortexExport('notifyAll', data)
    end

    function lib.Notify(target, notifyType, message, duration)
        return callCortexExport('Notify', target, notifyType, message, duration)
    end
end

return lib
