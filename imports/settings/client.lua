local GetNumResources = GetNumResources
local GetResourceByFindIndex = GetResourceByFindIndex
local GetResourceKvpString = GetResourceKvpString
local GetResourceState = GetResourceState
local SetResourceKvp = SetResourceKvp

local CURRENT_RESOURCE = GetCurrentResourceName()
local SETTINGS_PREFIX = 'cortex:'
local CORTEX_TAB_ID = 'cortex'

local registeredTabs = {}
local registeredOrder = {}
local settingIndex = {}
local settingListeners = {}
local discoveredResources = {}

local settingsOpen = false
local previewSnapshot = nil

local function releaseSettingsFocus()
    settingsOpen = false
    SetNuiFocus(false, false)
end

---@type { value: string, label: string, name: string, set: string }[]
local NOTIFY_SOUND_CATALOG = {
    { value = 'mp_idle_kick', label = 'MP Idle Kick', name = 'MP_IDLE_KICK', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    { value = 'mp_award', label = 'MP Award', name = 'MP_AWARD', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    { value = 'highlight_nav', label = 'Highlight Nav', name = 'HIGHLIGHT_NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    { value = 'error_fe', label = 'Error', name = 'ERROR', set = 'HUD_FRONTEND_MP_SOUNDSET' },
    { value = 'timer', label = 'Timer', name = 'TIMER', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    { value = 'atm_window', label = 'ATM Window', name = 'ATM_WINDOW', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    { value = 'dropped', label = 'Dropped', name = 'Dropped', set = 'HUD_FRONTEND_MP_COLLECTABLE_SOUNDS' },
    { value = 'radio_off_high', label = 'Radio Off High', name = 'Off_High', set = 'MP_RADIO_SFX' },
    { value = 'radio_retune_high', label = 'Radio Retune High', name = 'Retune_High', set = 'MP_RADIO_SFX' },
    { value = 'lose_1st_biker', label = 'Lose 1st (Biker)', name = 'Lose_1st', set = 'GTAO_Biker_Modes_Soundset' },
    { value = 'lose_1st_fm', label = 'Lose 1st (FM Events)', name = 'Lose_1st', set = 'GTAO_FM_Events_Soundset' },
    { value = 'object_collect_remote', label = 'Object Collect Remote', name = 'Object_Collect_Remote', set = 'GTAO_FM_Events_Soundset' },
    { value = 'popup_confirm_success', label = 'Popup Confirm Success', name = 'Popup_Confirm_Success', set = 'GTAO_Exec_SecuroServ_Computer_Sounds' },
}

local DEFAULT_NOTIFY_SOUND_PRESET = NOTIFY_SOUND_CATALOG[1] and NOTIFY_SOUND_CATALOG[1].value or 'mp_idle_kick'

local function catalogToFieldOptions()
    local opts = {}

    for index = 1, #NOTIFY_SOUND_CATALOG do
        local entry = NOTIFY_SOUND_CATALOG[index]
        opts[#opts + 1] = {
            value = entry.value,
            label = entry.label,
            name = entry.name,
            set = entry.set,
        }
    end

    return opts
end

local function normalizeSoundOptions(options)
    local normalized = {}

    for _, option in ipairs(options or {}) do
        local value = option.value
        local name = option.name
        local set = option.set

        if value ~= nil and name ~= nil and set ~= nil then
            normalized[#normalized + 1] = {
                value = value,
                label = option.label or tostring(value),
                name = name,
                set = set,
            }
        end
    end

    return normalized
end

local cortexDefaults = {
    notifySound = true,
    notifySoundPreset = DEFAULT_NOTIFY_SOUND_PRESET,
    notifyPosition = 'top-right'
}

local cortexFields = {
    {
        key = 'notifySound',
        label = 'Notification sounds',
        description = 'Master toggle for default notification audio',
        type = 'toggle',
    },
    {
        key = 'notifySoundPreset',
        label = 'Sound preset',
        description = 'Default audio when a notification uses built-in sound; Preview plays immediately',
        type = 'soundList',
        options = catalogToFieldOptions(),
    },
    {
        key = 'notifyPosition',
        label = 'Notification Position',
        description = 'Where notifications appear on screen',
        type = 'select',
        options = {
            { value = 'top-right', label = 'Top Right' },
            { value = 'top-left', label = 'Top Left' },
            { value = 'top', label = 'Top Center' },
            { value = 'bottom-right', label = 'Bottom Right' },
            { value = 'bottom-left', label = 'Bottom Left' },
            { value = 'bottom', label = 'Bottom Center' },
        },
    },
}

local cortexSettings = {}

local function shallowCopy(tbl)
    local out = {}

    for key, value in pairs(tbl or {}) do
        out[key] = value
    end

    return out
end

local function hasArrayEntries(tbl)
    return type(tbl) == 'table' and next(tbl) ~= nil
end

local function loadStoredValue(key, defaultValue)
    local stored = GetResourceKvpString(SETTINGS_PREFIX .. key)

    if stored == nil then
        return defaultValue
    end

    if type(defaultValue) == 'boolean' then
        return stored == 'true'
    end

    if type(defaultValue) == 'number' then
        return tonumber(stored) or defaultValue
    end

    return stored
end

local function saveStoredValue(key, value)
    if type(value) == 'boolean' then
        SetResourceKvp(SETTINGS_PREFIX .. key, value and 'true' or 'false')
        return
    end

    SetResourceKvp(SETTINGS_PREFIX .. key, tostring(value))
end

local function reloadCortexSettings()
    for key, defaultValue in pairs(cortexDefaults) do
        cortexSettings[key] = loadStoredValue(key, defaultValue)
    end
end

local function ensureRegisteredOrder(tabId)
    for index = 1, #registeredOrder do
        if registeredOrder[index] == tabId then
            return
        end
    end

    registeredOrder[#registeredOrder + 1] = tabId
end

local function unregisterTab(tabId)
    local tab = registeredTabs[tabId]

    if not tab then
        return
    end

    for key in pairs(tab.defaults or {}) do
        if settingIndex[key] == tabId then
            settingIndex[key] = nil
        end
    end

    registeredTabs[tabId] = nil

    for index = #registeredOrder, 1, -1 do
        if registeredOrder[index] == tabId then
            table.remove(registeredOrder, index)
            break
        end
    end
end

local function resourceHasRegisteredTab(resourceName)
    for _, tab in pairs(registeredTabs) do
        if tab and tab.resource == resourceName then
            return true
        end
    end

    return false
end

local function normalizeFieldType(fieldType)
    if fieldType == 'checkbox' then
        return 'toggle'
    end

    if fieldType == 'action' then
        return 'buttons'
    end

    return fieldType
end

local function normalizeOptions(options)
    local normalized = {}

    for _, option in ipairs(options or {}) do
        local value = option.value
        local label = option.label

        if value ~= nil then
            normalized[#normalized + 1] = {
                value = value,
                label = label or tostring(value)
            }
        end
    end

    return normalized
end

local function normalizeButtons(setting)
    local buttons = {}
    local source = setting.buttons or setting.actions or {}

    for _, button in ipairs(source) do
        local value = button.value or button.action or button.key

        if value ~= nil then
            buttons[#buttons + 1] = {
                value = value,
                label = button.label or tostring(value)
            }
        end
    end

    return buttons
end

local function normalizeLegacyField(setting, section)
    local fieldType = normalizeFieldType(setting.type)
    local field = {
        key = setting.key,
        label = setting.label or setting.key,
        description = setting.description,
        type = fieldType,
        section = section,
        hidden = setting.hidden == true,
    }

    if fieldType == 'select' or fieldType == 'color' then
        field.options = normalizeOptions(setting.options)
    elseif fieldType == 'soundList' then
        field.options = normalizeSoundOptions(setting.options)
    elseif fieldType == 'slider' then
        field.min = setting.min
        field.max = setting.max
        field.step = setting.step
        field.suffix = setting.suffix
    elseif fieldType == 'buttons' then
        field.buttons = normalizeButtons(setting)
    elseif fieldType == 'text' or fieldType == 'input' then
        if setting.placeholder ~= nil then field.placeholder = setting.placeholder end
        if setting.maxLength ~= nil then field.maxLength = setting.maxLength end
        if setting.inputType ~= nil then field.inputType = setting.inputType end
    end

    return field
end

local function buildLegacyTab(scriptId, definition)
    local fields = {}
    local defaults = {}
    local used = {}
    local settingsByKey = {}

    for _, setting in ipairs(definition.settings or {}) do
        if setting.key then
            settingsByKey[setting.key] = setting
        end
    end

    for _, section in ipairs(definition.sections or {}) do
        for _, key in ipairs(section.keys or {}) do
            local setting = settingsByKey[key]

            if setting and not used[key] then
                defaults[key] = setting.default
                if setting.hidden ~= true then
                    fields[#fields + 1] = normalizeLegacyField(setting, section.label)
                end
                used[key] = true
            end
        end
    end

    for _, setting in ipairs(definition.settings or {}) do
        local key = setting.key

        if key and not used[key] then
            defaults[key] = setting.default
            if setting.hidden ~= true then
                fields[#fields + 1] = normalizeLegacyField(setting, setting.section)
            end
            used[key] = true
        end
    end

    return {
        id = scriptId,
        label = definition.label or scriptId,
        fields = fields,
        defaults = defaults,
        values = {},
    }
end

local function buildModernTab(tabId, label, fields, defaults)
    local normalizedFields = {}
    local normalizedDefaults = shallowCopy(defaults)

    for _, field in ipairs(fields or {}) do
        local normalized = shallowCopy(field)
        normalized.type = normalizeFieldType(normalized.type)

        if type(normalized.key) ~= 'string' or normalized.key == '' then
            goto continue
        end

        if normalized.hidden == true then
            if normalized.key and normalizedDefaults[normalized.key] == nil and field.default ~= nil then
                normalizedDefaults[normalized.key] = field.default
            end
            goto continue
        end

        if normalized.type == 'buttons' and not hasArrayEntries(normalized.buttons) then
            normalized.buttons = normalizeButtons(normalized)
        end

        if normalized.type == 'select' or normalized.type == 'color' then
            normalized.options = normalizeOptions(normalized.options)
        elseif normalized.type == 'soundList' then
            normalized.options = normalizeSoundOptions(normalized.options)
        end

        normalizedFields[#normalizedFields + 1] = normalized

        if normalized.key and normalizedDefaults[normalized.key] == nil and field.default ~= nil then
            normalizedDefaults[normalized.key] = field.default
        end

        ::continue::
    end

    return {
        id = tabId,
        label = label or tabId,
        fields = normalizedFields,
        defaults = normalizedDefaults,
        values = {},
    }
end

local function reloadTabValues(tab)
    tab.values = {}

    for key, defaultValue in pairs(tab.defaults or {}) do
        tab.values[key] = loadStoredValue(key, defaultValue)
        settingIndex[key] = tab.id
    end
end

local function registerTab(tab, resourceName)
    ensureRegisteredOrder(tab.id)
    tab.resource = resourceName or tab.resource or tab.id
    reloadTabValues(tab)
    registeredTabs[tab.id] = tab
end

local function emitSettingChanged(key, value, tabId)
    TriggerEvent('cortex-lib:settingChanged', key, value)

    local listeners = settingListeners[key]

    if listeners then
        for index = 1, #listeners do
            pcall(listeners[index], value, key, tabId)
        end
    end
end

local function emitTabChanged(tabId, changes)
    if next(changes) == nil then
        return
    end

    TriggerEvent('cortex-lib:settingsChanged', tabId, changes)

    for key, value in pairs(changes) do
        emitSettingChanged(key, value, tabId)
    end
end

local function tryRegisterResourceDefinition(resourceName)
    if not resourceName or resourceName == CURRENT_RESOURCE then
        return
    end

    if GetResourceState(resourceName) ~= 'started' then
        return
    end

    if discoveredResources[resourceName] then
        return
    end

    if resourceHasRegisteredTab(resourceName) then
        discoveredResources[resourceName] = true
        return
    end

    discoveredResources[resourceName] = true

    local okDefinition, definition = pcall(function()
        return exports[resourceName]:getSettingsDefinition()
    end)

    if okDefinition and type(definition) == 'table' then
        registerTab(buildLegacyTab(resourceName, definition), resourceName)
    end
end

local function refreshDiscoveredSettingsTabs()
    local resourceCount = GetNumResources()

    for index = 0, resourceCount - 1 do
        local resourceName = GetResourceByFindIndex(index)
        tryRegisterResourceDefinition(resourceName)
    end
end

local function buildTabsPayload()
    refreshDiscoveredSettingsTabs()
    reloadCortexSettings()

    local tabs = {
        {
            id = CORTEX_TAB_ID,
            label = 'CORTEX',
            fields = cortexFields,
            values = shallowCopy(cortexSettings),
            defaults = shallowCopy(cortexDefaults),
        }
    }

    for index = 1, #registeredOrder do
        local tabId = registeredOrder[index]
        local tab = registeredTabs[tabId]

        if tab then
            reloadTabValues(tab)
            tabs[#tabs + 1] = {
                id = tab.id,
                label = tab.label,
                fields = tab.fields,
                values = shallowCopy(tab.values),
                defaults = shallowCopy(tab.defaults),
            }
        end
    end

    return tabs
end

local function getTabState(tabId)
    if tabId == CORTEX_TAB_ID then
        return cortexFields, cortexDefaults, cortexSettings
    end

    local tab = registeredTabs[tabId]
    if not tab then
        return nil, nil, nil
    end

    return tab.fields, tab.defaults, tab.values
end

local function findTabField(fields, key)
    for index = 1, #(fields or {}) do
        local field = fields[index]
        if field and field.key == key then
            return field
        end
    end

    return nil
end

local function normalizeNuiSettingValue(tabId, key, value)
    if type(tabId) ~= 'string' or tabId == '' or #tabId > 64 then
        return false, nil
    end

    if type(key) ~= 'string' or key == '' or #key > 128 then
        return false, nil
    end

    local fields, defaults, values = getTabState(tabId)
    if not defaults or not values then
        return false, nil
    end

    local field = findTabField(fields, key)
    local defaultValue = defaults[key]
    local currentValue = values[key]

    if not field and defaultValue == nil and currentValue == nil then
        return false, nil
    end

    local fieldType = field and field.type or nil

    if fieldType == 'toggle' then
        if type(value) ~= 'boolean' then
            return false, nil
        end

        return true, value
    end

    if fieldType == 'slider' then
        if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
            return false, nil
        end

        local minValue = tonumber(field.min)
        local maxValue = tonumber(field.max)
        if (minValue and value < minValue) or (maxValue and value > maxValue) then
            return false, nil
        end

        return true, value
    end

    if fieldType == 'select' or fieldType == 'color' or fieldType == 'soundList' then
        if type(value) ~= 'string' and type(value) ~= 'number' and type(value) ~= 'boolean' then
            return false, nil
        end

        for _, option in ipairs(field.options or {}) do
            if option.value ~= nil and tostring(option.value) == tostring(value) then
                return true, option.value
            end
        end

        return false, nil
    end

    if fieldType == 'text' or fieldType == 'input' then
        if type(value) ~= 'string' or value:find('\0', 1, true) then
            return false, nil
        end

        local maxLength = math.min(512, math.max(1, tonumber(field.maxLength) or 256))
        if #value > maxLength then
            return false, nil
        end

        return true, value
    end

    local expectedValue = defaultValue
    if expectedValue == nil then
        expectedValue = currentValue
    end

    if expectedValue == nil or type(value) ~= type(expectedValue) then
        return false, nil
    end

    if type(value) == 'number' and (value ~= value or value == math.huge or value == -math.huge) then
        return false, nil
    end

    if type(value) == 'string' and (#value > 512 or value:find('\0', 1, true)) then
        return false, nil
    end

    if type(value) ~= 'boolean' and type(value) ~= 'number' and type(value) ~= 'string' then
        return false, nil
    end

    return true, value
end

local function notifyCortexRuntimeChanges(changes)
    if changes.notifyPosition then
        SendNUIMessage({
            action = 'notifySetPosition',
            data = { position = changes.notifyPosition }
        })
    end
end

local function applyRuntimeTabValues(tabId, values)
    if type(values) ~= 'table' then
        return 0
    end

    local _, _, runtimeValues = getTabState(tabId)
    if not runtimeValues then
        return 0
    end

    local changes = {}
    local applied = 0
    local inspected = 0

    for key, value in pairs(values) do
        inspected = inspected + 1
        if inspected > 128 then
            break
        end

        local valid, normalized = normalizeNuiSettingValue(tabId, key, value)
        if valid and runtimeValues[key] ~= normalized then
            runtimeValues[key] = normalized
            if tabId ~= CORTEX_TAB_ID then
                settingIndex[key] = tabId
            end
            changes[key] = normalized
            applied = applied + 1
        end
    end

    if tabId == CORTEX_TAB_ID then
        notifyCortexRuntimeChanges(changes)
    end

    emitTabChanged(tabId, changes)
    return applied
end

local function beginPreviewSession()
    previewSnapshot = {
        [CORTEX_TAB_ID] = shallowCopy(cortexSettings)
    }

    for index = 1, #registeredOrder do
        local tabId = registeredOrder[index]
        local tab = registeredTabs[tabId]
        if tab then
            previewSnapshot[tabId] = shallowCopy(tab.values)
        end
    end
end

local function previewTabValue(tabId, key, value)
    if not settingsOpen or not previewSnapshot then
        return false
    end

    local valid, normalized = normalizeNuiSettingValue(tabId, key, value)
    if not valid then
        return false
    end

    applyRuntimeTabValues(tabId, { [key] = normalized })
    return true
end

local function rollbackPreviewValues()
    local snapshot = previewSnapshot
    previewSnapshot = nil

    if not snapshot then
        return 0
    end

    local restored = 0
    for tabId, values in pairs(snapshot) do
        restored = restored + applyRuntimeTabValues(tabId, values)
    end

    return restored
end

local function setTrackedSetting(key, value)
    if cortexDefaults[key] ~= nil then
        saveStoredValue(key, value)
        cortexSettings[key] = value
        emitSettingChanged(key, value, CORTEX_TAB_ID)

        if key == 'notifyPosition' then
            SendNUIMessage({
                action = 'notifySetPosition',
                data = { position = value }
            })
        end

        return true
    end

    refreshDiscoveredSettingsTabs()

    local tabId = settingIndex[key]
    local tab = tabId and registeredTabs[tabId] or nil

    if not tab then
        saveStoredValue(key, value)
        emitSettingChanged(key, value, nil)
        return true
    end

    saveStoredValue(key, value)
    tab.values[key] = value
    emitTabChanged(tabId, { [key] = value })
    return true
end

local function applyTabValues(tabId, values)
    if type(values) ~= 'table' then
        return 0
    end

    local changes = {}
    local applied = 0
    local inspected = 0

    if tabId == CORTEX_TAB_ID then
        for key, value in pairs(values or {}) do
            inspected = inspected + 1
            if inspected > 128 then
                break
            end

            local valid, normalized = normalizeNuiSettingValue(tabId, key, value)
            if valid then
                local changed = cortexSettings[key] ~= normalized
                saveStoredValue(key, normalized)
                cortexSettings[key] = normalized
                if changed then
                    changes[key] = normalized
                end
                applied = applied + 1
            end
        end

        notifyCortexRuntimeChanges(changes)

        emitTabChanged(tabId, changes)
        return applied
    end

    local tab = registeredTabs[tabId]

    if not tab then
        return 0
    end

    for key, value in pairs(values or {}) do
        inspected = inspected + 1
        if inspected > 128 then
            break
        end

        local valid, normalized = normalizeNuiSettingValue(tabId, key, value)
        if valid then
            local changed = tab.values[key] ~= normalized
            saveStoredValue(key, normalized)
            tab.values[key] = normalized
            settingIndex[key] = tabId
            if changed then
                changes[key] = normalized
            end
            applied = applied + 1
        end
    end

    emitTabChanged(tabId, changes)
    return applied
end

local function commitPreviewValues(tabs)
    local committed = 0
    local inspected = 0

    if type(tabs) == 'table' then
        for tabId, values in pairs(tabs) do
            inspected = inspected + 1
            if inspected > 64 then
                break
            end

            if type(tabId) == 'string' and type(values) == 'table' then
                committed = committed + applyTabValues(tabId, values)
            end
        end
    end

    previewSnapshot = nil
    return committed
end

function lib.getSetting(key)
    if cortexDefaults[key] ~= nil then
        return cortexSettings[key]
    end

    refreshDiscoveredSettingsTabs()

    local tabId = settingIndex[key]
    local tab = tabId and registeredTabs[tabId] or nil

    if tab then
        return tab.values[key]
    end

    return GetResourceKvpString(SETTINGS_PREFIX .. key)
end

function lib.getAllSettings()
    refreshDiscoveredSettingsTabs()

    local out = shallowCopy(cortexSettings)

    for _, tabId in ipairs(registeredOrder) do
        local tab = registeredTabs[tabId]

        if tab then
            for key, value in pairs(tab.values) do
                out[key] = value
            end
        end
    end

    return out
end

function lib.setSetting(key, value)
    return setTrackedSetting(key, value)
end

function lib.saveSetting(key, value)
    return setTrackedSetting(key, value)
end

function lib.getTabSetting(tabId, key)
    refreshDiscoveredSettingsTabs()

    local tab = registeredTabs[tabId]
    if not tab then
        return nil
    end

    return tab.values[key]
end

function lib.getNotifySoundCatalog()
    return NOTIFY_SOUND_CATALOG
end

function lib.onSettingChange(key, callback)
    if type(key) ~= 'string' or type(callback) ~= 'function' then
        return false
    end

    local listeners = settingListeners[key]

    if not listeners then
        listeners = {}
        settingListeners[key] = listeners
    end

    listeners[#listeners + 1] = callback
    return true
end

function lib.registerSettingsScript(scriptId, definition)
    if type(scriptId) ~= 'string' or scriptId == '' or type(definition) ~= 'table' then
        return false
    end

    registerTab(buildLegacyTab(scriptId, definition), GetInvokingResource() or scriptId)
    return true
end

function lib.registerSettings(tabId, tabLabel, kvpPrefix, fields, defaults)
    if type(tabLabel) == 'table' and kvpPrefix == nil then
        return lib.registerSettingsScript(tabId, tabLabel)
    end

    local resolvedFields = fields
    local resolvedDefaults = defaults

    if type(kvpPrefix) == 'table' then
        resolvedFields = kvpPrefix
        resolvedDefaults = fields
    end

    if type(tabId) ~= 'string' or tabId == '' then
        return false
    end

    if type(resolvedFields) ~= 'table' then
        resolvedFields = {}
    end

    if type(resolvedDefaults) ~= 'table' then
        resolvedDefaults = {}
    end

    registerTab(buildModernTab(tabId, tabLabel, resolvedFields, resolvedDefaults), GetInvokingResource() or tabId)
    return true
end

function lib.openSettings()
    if settingsOpen then
        return
    end

    local tabs = buildTabsPayload()
    beginPreviewSession()

    SendNUIMessage({
        action = 'settingsOpen',
        data = { tabs = tabs }
    })
    settingsOpen = true
end

function lib.openSettingsMenu()
    lib.openSettings()
end

function lib.closeSettings()
    local wasOpen = settingsOpen

    releaseSettingsFocus()

    if wasOpen then
        rollbackPreviewValues()
        SendNUIMessage({ action = 'settingsClose' })
    end
end

function lib.closeSettingsMenu()
    lib.closeSettings()
end

reloadCortexSettings()

RegisterNUICallback('settingsReady', function(_, cb)
    cb('ok')

    if settingsOpen then
        SetNuiFocus(true, true)
    end
end)

RegisterNUICallback('settingsSave', function(data, cb)
    releaseSettingsFocus()
    local committed = commitPreviewValues(data and data.tabs or nil)
    cb({ ok = true, committed = committed })
end)

RegisterNUICallback('settingsCancel', function(_, cb)
    releaseSettingsFocus()
    local restored = rollbackPreviewValues()
    cb({ ok = true, restored = restored })
end)

RegisterNUICallback('settingsPreview', function(data, cb)
    local tabId = data and data.tabId or nil
    local key = data and data.key or nil
    local value = data and data.value
    local applied = 0
    local ok = false

    if settingsOpen and type(data) == 'table' and type(tabId) == 'string' then
        if type(data.values) == 'table' then
            applied = applyRuntimeTabValues(tabId, data.values)
            ok = true
        else
            ok = previewTabValue(tabId, key, value)
            applied = ok and 1 or 0
        end
    end

    cb({ ok = ok, applied = applied })
end)

RegisterNUICallback('settingsPreviewSound', function(data, cb)
    cb('ok')

    local name = data and data.name
    local set = data and data.set

    if type(name) ~= 'string' or type(set) ~= 'string' or name == '' or set == '' then
        return
    end

    local soundId = GetSoundId()
    PlaySoundFrontend(soundId, name, set, true)
    ReleaseSoundId(soundId)
end)

RegisterNUICallback('settingsAction', function(data, cb)
    cb('ok')

    local tabId = data and data.tabId or nil
    local fieldKey = data and data.key or nil
    local action = data and (data.value or data.key) or nil

    TriggerEvent('cortex-lib:settingsAction', tabId, action, fieldKey, data and data.value or nil)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == CURRENT_RESOURCE then
        refreshDiscoveredSettingsTabs()
        return
    end

    discoveredResources[resourceName] = nil
    tryRegisterResourceDefinition(resourceName)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == CURRENT_RESOURCE then
        releaseSettingsFocus()
        previewSnapshot = nil
    end

    discoveredResources[resourceName] = nil

    local stoppedTabs = {}
    for tabId, tab in pairs(registeredTabs) do
        if tab and tab.resource == resourceName then
            stoppedTabs[#stoppedTabs + 1] = tabId
        end
    end

    for index = 1, #stoppedTabs do
        unregisterTab(stoppedTabs[index])
    end
end)

exports('registerSettings', lib.registerSettings)
exports('registerSettingsScript', lib.registerSettingsScript)
exports('openSettings', lib.openSettings)
exports('openSettingsMenu', lib.openSettingsMenu)
exports('closeSettings', lib.closeSettings)
exports('closeSettingsMenu', lib.closeSettingsMenu)
exports('getSetting', lib.getSetting)
exports('getAllSettings', lib.getAllSettings)
exports('setSetting', lib.setSetting)
exports('saveSetting', lib.saveSetting)
exports('getTabSetting', lib.getTabSetting)
exports('onSettingChange', lib.onSettingChange)
exports('getNotifySoundCatalog', lib.getNotifySoundCatalog)

RegisterCommand('cortexsettings', function()
    lib.openSettings()
end, false)

return {
    registerSettings = lib.registerSettings,
    registerSettingsScript = lib.registerSettingsScript,
    openSettings = lib.openSettings,
    openSettingsMenu = lib.openSettingsMenu,
    closeSettings = lib.closeSettings,
    closeSettingsMenu = lib.closeSettingsMenu,
    getSetting = lib.getSetting,
    getAllSettings = lib.getAllSettings,
    setSetting = lib.setSetting,
    saveSetting = lib.saveSetting,
    getTabSetting = lib.getTabSetting,
    onSettingChange = lib.onSettingChange,
    getNotifySoundCatalog = lib.getNotifySoundCatalog,
}
