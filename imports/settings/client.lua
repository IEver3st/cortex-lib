local GetNumResources = GetNumResources
local GetResourceByFindIndex = GetResourceByFindIndex
local GetResourceKvpString = GetResourceKvpString
local GetResourceState = GetResourceState
local SetResourceKvp = SetResourceKvp
local DeleteResourceKvp = DeleteResourceKvp

local CURRENT_RESOURCE = GetCurrentResourceName()
local SETTINGS_PREFIX = 'cortex:'
local CORTEX_TAB_ID = 'cortex'
local MAX_TABS = 32
local MAX_FIELDS = 64
local MAX_OPTIONS = 64
local MAX_SETTINGS_PER_TAB = 128

local registeredTabs = {}
local registeredOrder = {}
local settingIndex = {}
local settingListeners = {}
local discoveredResources = {}
local discoveryDirty = true

local settingsOpen = false
local previewSnapshot = nil
local settingsSession = nil
local settingsOwner = nil
local settingsReady = false
local fallbackGeneration = 0
local rollbackPreviewValues
local SETTINGS_READY_TIMEOUT = 10000

local function getInvokingOwner()
    local owner = GetInvokingResource and GetInvokingResource() or nil
    return owner or CURRENT_RESOURCE
end

local function getRegistrationOwner(fallback)
    local owner = GetInvokingResource and GetInvokingResource() or nil
    return owner or fallback
end

local function boundedString(value, maxLength, allowEmpty)
    return type(value) == 'string'
        and (allowEmpty or value ~= '')
        and #value <= maxLength
        and not value:find('\0', 1, true)
end

local function safeObjectKey(value, maxLength)
    return boundedString(value, maxLength, false)
        and not value:find('%c')
        and value ~= '__proto__'
        and value ~= 'prototype'
        and value ~= 'constructor'
end

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    if not ok or type(text) ~= 'string' then return '<unprintable error>' end
    if #text > 512 then return text:sub(1, 512) .. '...' end
    return text
end

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function isDenseArray(value, maxItems)
    if type(value) ~= 'table' then return false end
    local length = #value
    if length > maxItems then return false end

    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or math.tointeger(key) ~= key or key < 1 or key > length then return false end
        count = count + 1
    end
    return count == length
end

local function acquireSettingsModal(owner)
    if type(lib._acquireModal) == 'function' then return lib._acquireModal('settings', owner) end
    fallbackGeneration = fallbackGeneration + 1
    return fallbackGeneration
end

local function focusSettingsModal(session)
    if type(lib._focusModal) == 'function' then return lib._focusModal('settings', session, false) end
    SetNuiFocus(true, true)
    return true
end

local function matchesSettingsModal(data)
    if not settingsOpen or not settingsSession then return false end
    if type(lib._matchesModal) == 'function' then
        return type(data) == 'table' and lib._matchesModal('settings', settingsSession, data.session)
    end
    return type(data) == 'table' and (data.session == nil or data.session == settingsSession)
end

local function releaseSettingsFocus()
    local session = settingsSession
    settingsOpen = false
    settingsSession = nil
    settingsOwner = nil
    settingsReady = false
    if type(lib._releaseModal) == 'function' then
        if session then lib._releaseModal('settings', session) end
    else
        SetNuiFocus(false, false)
    end
    if rawget(lib, '_settingsVisibilityChanged') then lib._settingsVisibilityChanged(false) end
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

    if not isDenseArray(options or {}, MAX_OPTIONS) then return nil end

    for _, option in ipairs(options or {}) do
        if type(option) == 'table' then
            local value = option.value
            local name = option.name
            local set = option.set

            if value ~= nil
                and (type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean')
                and (type(value) ~= 'number' or isFiniteNumber(value))
                and boundedString(option.label or tostring(value), 128, false)
                and boundedString(name, 128, false)
                and boundedString(set, 128, false)
            then
                normalized[#normalized + 1] = {
                    value = value,
                    label = option.label or tostring(value),
                    name = name,
                    set = set,
                }
            else
                return nil
            end
        else
            return nil
        end
    end

    return normalized
end

-- Built-in player preferences. Every key is per-client KVP under `cortex:<key>`,
-- readable through lib.getSetting and announced through cortex-lib:settingChanged.
-- The four dynamic_* keys keep their historical names so shared appearance
-- (client/presentation.lua) and existing player values carry over unchanged.
local cortexDefaults = {
    uiScale = 100,
    textSize = 'standard',
    dynamic_accent = '#8fcbbf',
    dynamic_opacity = 92,
    dynamic_motion = 'system',
    dynamic_layout = true,
    controlHints = true,
    notifyPosition = 'top-right',
    notifyDuration = 'standard',
    notifyLimit = 5,
    notifySound = true,
    notifySoundPreset = DEFAULT_NOTIFY_SOUND_PRESET,
    promptMarkers = true,
    promptScale = 'standard',
    invertScroll = false,
    showPercent = true,
}

local SECTION_INTERFACE = 'Interface'
local SECTION_NOTIFICATIONS = 'Notifications'
local SECTION_PROMPTS = 'Prompts'
local SECTION_PROGRESS = 'Progress'

local cortexFields = {
    {
        key = 'uiScale', section = SECTION_INTERFACE, type = 'slider',
        label = 'Interface size', min = 80, max = 130, step = 5, suffix = '%',
        description = 'Makes every Cortex prompt, menu and notification larger or smaller.',
    },
    {
        key = 'textSize', section = SECTION_INTERFACE, type = 'select', label = 'Text size',
        description = 'Larger body text in menus, dialogs and notifications.',
        options = { { value = 'standard', label = 'Standard' }, { value = 'large', label = 'Large' } },
    },
    {
        key = 'dynamic_accent', section = SECTION_INTERFACE, type = 'color', label = 'Shared accent', custom = true,
        description = 'The highlight colour for selected and active items in every Cortex interface. Pick one, or type a hex colour.',
        options = {
            { value = '#8fcbbf', label = 'Mint' }, { value = '#9bbcd3', label = 'Blue' },
            { value = '#bea9de', label = 'Lavender' }, { value = '#d8ba82', label = 'Amber' },
            { value = '#ebe9e6', label = 'Paper' },
        },
    },
    {
        key = 'dynamic_opacity', section = SECTION_INTERFACE, type = 'slider', label = 'Surface opacity',
        min = 65, max = 100, step = 1, suffix = '%',
        description = 'How solid menus and panels look over the game.',
    },
    {
        key = 'dynamic_motion', section = SECTION_INTERFACE, type = 'select', label = 'Motion',
        description = 'Follow your system setting, keep animation to a minimum, or always animate.',
        options = {
            { value = 'system', label = 'System' }, { value = 'reduced', label = 'Reduced' },
            { value = 'full', label = 'Full' },
        },
    },
    {
        key = 'dynamic_layout', section = SECTION_INTERFACE, type = 'toggle', label = 'Avoid overlapping overlays',
        description = 'Moves notifications and prompts aside so they do not cover chat, the HUD or each other.',
    },
    {
        key = 'controlHints', section = SECTION_INTERFACE, type = 'toggle', label = 'Control hints',
        description = 'Show key hints under menus and prompts. A hint that is the only instruction always stays.',
    },
    {
        key = 'notifyPosition', section = SECTION_NOTIFICATIONS, type = 'select', label = 'Position',
        description = 'Where notifications appear on screen.',
        options = {
            { value = 'top-right', label = 'Top right' },
            { value = 'top-left', label = 'Top left' },
            { value = 'top', label = 'Top centre' },
            { value = 'bottom-right', label = 'Bottom right' },
            { value = 'bottom-left', label = 'Bottom left' },
            { value = 'bottom', label = 'Bottom centre' },
        },
    },
    {
        key = 'notifyDuration', section = SECTION_NOTIFICATIONS, type = 'select', label = 'Display time',
        description = 'How long notifications stay on screen before they leave.',
        options = {
            { value = 'short', label = 'Short' }, { value = 'standard', label = 'Standard' },
            { value = 'long', label = 'Long' },
        },
    },
    {
        key = 'notifyLimit', section = SECTION_NOTIFICATIONS, type = 'select', label = 'Visible at once',
        description = 'The most notifications shown at the same time.',
        options = { { value = 3, label = '3' }, { value = 5, label = '5' }, { value = 8, label = '8' } },
    },
    {
        key = 'notifySound', section = SECTION_NOTIFICATIONS, type = 'toggle', label = 'Sound',
        description = 'Play a sound when a notification arrives.',
    },
    {
        key = 'notifySoundPreset', section = SECTION_NOTIFICATIONS, type = 'soundList', label = 'Sound preset',
        description = 'The sound notifications use. Choosing one plays it.',
        options = catalogToFieldOptions(),
        showWhen = { notifySound = true },
    },
    {
        key = 'promptMarkers', section = SECTION_PROMPTS, type = 'toggle', label = 'Distant interaction markers',
        description = 'Show a small marker where you can interact before you are close enough to use it.',
    },
    {
        key = 'promptScale', section = SECTION_PROMPTS, type = 'select', label = 'Prompt size',
        description = 'Size of interaction prompts in the world and on screen.',
        options = {
            { value = 'small', label = 'Small' }, { value = 'standard', label = 'Standard' },
            { value = 'large', label = 'Large' },
        },
    },
    {
        key = 'invertScroll', section = SECTION_PROMPTS, type = 'toggle', label = 'Invert list scroll',
        description = 'Flip the mouse wheel direction when choosing between stacked prompts.',
    },
    {
        key = 'showPercent', section = SECTION_PROGRESS, type = 'toggle', label = 'Show percentage',
        description = 'Show how far along an action is next to progress bars and circles.',
    },
}

-- Enum values stay readable through lib.getSetting; the NUI receives multipliers.
local NOTIFY_DURATION_SCALE = { short = 0.75, standard = 1.0, long = 1.5 }
local PREF_KEYS = {
    uiScale = true, textSize = true, notifyDuration = true, notifyLimit = true, showPercent = true,
    promptMarkers = true, promptScale = true, controlHints = true, invertScroll = true,
}

-- The retired "Dynamic UI" tab stored under its own registry prefix. Its four
-- kept settings move to the Cortex namespace once; its per-resource
-- "independent appearance" switches no longer exist and are removed.
local LEGACY_DYNAMIC_PREFIX = SETTINGS_PREFIX .. 'cortex-dynamic:'
local MIGRATED_DYNAMIC_KEYS = { 'dynamic_accent', 'dynamic_opacity', 'dynamic_motion', 'dynamic_layout' }
local RETIRED_DYNAMIC_KEYS = {
    'cortex-lib', 'cortex-chat', 'cortex-hud', 'cortex-polcam', 'cortex-rewind', 'cortex-admin',
    'cortex-emotemenu', 'cortex_mdtsv', 'cortex_soundtool', 'cortex-death', 'gsd-arges', 'opticom',
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

local function normalizeStoragePrefix(tabId, candidate)
    if candidate == nil then return SETTINGS_PREFIX .. tabId .. ':' end
    if not boundedString(candidate, 96, false)
        or not candidate:match('^[%w_:%-%.]+:$')
    then
        return nil
    end
    return candidate
end

local function decodeStoredValue(stored, defaultValue)
    if stored == nil then return defaultValue end

    if type(defaultValue) == 'boolean' then
        if stored == 'true' then return true end
        if stored == 'false' then return false end
        return defaultValue
    end
    if type(defaultValue) == 'number' then
        local decoded = tonumber(stored)
        return isFiniteNumber(decoded) and decoded or defaultValue
    end
    if type(defaultValue) == 'string' and not boundedString(stored, 4096, true) then return defaultValue end
    return stored
end

local function readStoredValue(key)
    local ok, value = pcall(GetResourceKvpString, key)
    if not ok then return false, nil end
    return true, value
end

local function serializeStoredValue(value)
    if type(value) == 'boolean' then return value and 'true' or 'false' end
    return tostring(value)
end

local function writeStoredValue(prefix, key, value)
    local ok, err = pcall(SetResourceKvp, prefix .. key, serializeStoredValue(value))
    return ok, err
end

local function loadStoredValue(prefix, key, defaultValue, migrateLegacy)
    local readOk, stored = readStoredValue(prefix .. key)
    if not readOk then return defaultValue end

    if stored == nil and migrateLegacy and prefix ~= SETTINGS_PREFIX then
        local legacyOk
        legacyOk, stored = readStoredValue(SETTINGS_PREFIX .. key)
        if legacyOk and stored ~= nil then
            writeStoredValue(prefix, key, decodeStoredValue(stored, defaultValue))
        end
    end

    return decodeStoredValue(stored, defaultValue)
end

local function saveStoredValue(prefix, key, value)
    return writeStoredValue(prefix, key, value)
end

local function saveTabStoredValue(tab, key, value)
    return saveStoredValue(tab.kvpPrefix, key, value)
end

local function migrateRetiredDynamicTab()
    for index = 1, #MIGRATED_DYNAMIC_KEYS do
        local key = MIGRATED_DYNAMIC_KEYS[index]
        local legacyOk, legacy = readStoredValue(LEGACY_DYNAMIC_PREFIX .. key)
        if legacyOk and legacy ~= nil then
            local currentOk, current = readStoredValue(SETTINGS_PREFIX .. key)
            local moved = currentOk and current ~= nil
            if currentOk and current == nil then
                -- Copy the raw string; reloadCortexSettings validates it against the field.
                moved = pcall(SetResourceKvp, SETTINGS_PREFIX .. key, legacy)
            end
            if moved and type(DeleteResourceKvp) == 'function' then
                pcall(DeleteResourceKvp, LEGACY_DYNAMIC_PREFIX .. key)
            end
        end
    end
    if type(DeleteResourceKvp) ~= 'function' then return end
    for index = 1, #RETIRED_DYNAMIC_KEYS do
        local storageKey = LEGACY_DYNAMIC_PREFIX .. 'dynamic_independent_' .. RETIRED_DYNAMIC_KEYS[index]
        local ok, value = readStoredValue(storageKey)
        if ok and value ~= nil then pcall(DeleteResourceKvp, storageKey) end
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

local function rebuildSettingIndex()
    settingIndex = {}

    for index = 1, #registeredOrder do
        local tabId = registeredOrder[index]
        local tab = registeredTabs[tabId]
        if tab then
            for key in pairs(tab.defaults or {}) do
                if settingIndex[key] == nil then
                    settingIndex[key] = tabId
                elseif settingIndex[key] ~= tabId then
                    settingIndex[key] = false
                end
            end
        end
    end
end

local function unregisterTab(tabId)
    local tab = registeredTabs[tabId]

    if not tab then
        return
    end

    registeredTabs[tabId] = nil

    for index = #registeredOrder, 1, -1 do
        if registeredOrder[index] == tabId then
            table.remove(registeredOrder, index)
            break
        end
    end
    rebuildSettingIndex()
end

local function resourceHasRegisteredTab(resourceName)
    for _, tab in pairs(registeredTabs) do
        if tab and tab.resource == resourceName then
            return true
        end
    end

    return false
end

-- A colour field marked `custom` also takes any #rrggbb value, stored lowercase.
local function customColor(field, value)
    if not field or field.type ~= 'color' or field.custom ~= true or type(value) ~= 'string' then return nil end
    return value:match('^#%x%x%x%x%x%x$') and value:lower() or nil
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

    if not isDenseArray(options or {}, MAX_OPTIONS) then return nil end

    for _, option in ipairs(options or {}) do
        if type(option) == 'table' then
            local value = option.value
            local label = option.label

            if value ~= nil
                and (type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean')
                and (type(value) ~= 'number' or isFiniteNumber(value))
                and boundedString(label or tostring(value), 128, true)
            then
                normalized[#normalized + 1] = {
                    value = value,
                    label = label or tostring(value)
                }
            else
                return nil
            end
        else
            return nil
        end
    end

    return normalized
end

local function normalizeButtons(setting)
    local buttons = {}
    local source = setting.buttons or setting.actions or {}

    if not isDenseArray(source, MAX_OPTIONS) then return nil end

    for _, button in ipairs(source) do
        if type(button) == 'table' then
            local value = button.value
            if value == nil then value = button.action end
            if value == nil then value = button.key end

            if value ~= nil
                and (type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean')
                and (type(value) ~= 'number' or isFiniteNumber(value))
                and boundedString(tostring(value), 128, false)
                and boundedString(button.label or tostring(value), 128, false)
            then
                buttons[#buttons + 1] = {
                    value = value,
                    label = button.label or tostring(value)
                }
            else
                return nil
            end
        else
            return nil
        end
    end

    return buttons
end

local VALID_INPUT_TYPES = {
    text = true,
    number = true,
    email = true,
    password = true,
    search = true,
    url = true,
}

local function sanitizeModernField(field)
    local fieldType = normalizeFieldType(field.type)
    local label = field.label or field.key
    if not safeObjectKey(field.key, 128)
        or not boundedString(label, 128, false)
        or not boundedString(fieldType, 32, false)
        or (field.description ~= nil and not boundedString(field.description, 512, true))
        or (field.section ~= nil and not boundedString(field.section, 128, true))
        or (field.advanced ~= nil and type(field.advanced) ~= 'boolean')
        or (field.custom ~= nil and type(field.custom) ~= 'boolean')
    then
        return nil
    end

    local normalized = {
        key = field.key,
        label = label,
        description = field.description,
        type = fieldType,
        section = field.section,
        advanced = field.advanced == true,
        custom = fieldType == 'color' and field.custom == true or nil,
    }

    if field.showWhen ~= nil then
        if type(field.showWhen) ~= 'table' then return nil end
        normalized.showWhen = {}
        local count = 0
        for key, value in pairs(field.showWhen) do
            count = count + 1
            if count > 8 or not safeObjectKey(key, 128)
                or not (type(value) == 'boolean'
                    or (type(value) == 'string' and boundedString(value, 128, true))
                    or (type(value) == 'number' and isFiniteNumber(value)))
            then return nil end
            normalized.showWhen[key] = value
        end
        if count == 0 then return nil end
    end

    if fieldType == 'select' or fieldType == 'color' then
        normalized.options = normalizeOptions(field.options)
        if not normalized.options then return nil end
    elseif fieldType == 'soundList' then
        normalized.options = normalizeSoundOptions(field.options)
        if not normalized.options then return nil end
    elseif fieldType == 'slider' then
        local minValue = tonumber(field.min)
        local maxValue = tonumber(field.max)
        local step = field.step == nil and 1 or tonumber(field.step)
        if not isFiniteNumber(minValue) or not isFiniteNumber(maxValue) or not isFiniteNumber(step)
            or minValue > maxValue or step <= 0
            or (field.suffix ~= nil and not boundedString(field.suffix, 24, true))
        then
            return nil
        end
        normalized.min = minValue
        normalized.max = maxValue
        normalized.step = step
        normalized.suffix = field.suffix
    elseif fieldType == 'buttons' then
        normalized.buttons = normalizeButtons(field)
        if not normalized.buttons then return nil end
    elseif fieldType == 'text' or fieldType == 'input' then
        if (field.placeholder ~= nil and not boundedString(field.placeholder, 256, true))
            or (field.maxLength ~= nil and (type(field.maxLength) ~= 'number'
                or math.tointeger(field.maxLength) == nil or field.maxLength < 1 or field.maxLength > 4096))
            or (field.inputType ~= nil and not VALID_INPUT_TYPES[field.inputType])
        then
            return nil
        end
        normalized.placeholder = field.placeholder
        normalized.maxLength = field.maxLength
        normalized.inputType = field.inputType
    end

    return normalized
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
        advanced = setting.advanced,
        showWhen = setting.showWhen,
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

    return sanitizeModernField(field)
end

local function buildLegacyTab(scriptId, definition, kvpPrefix)
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
                    local normalized = normalizeLegacyField(setting, section.label)
                    if not normalized then return nil end
                    fields[#fields + 1] = normalized
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
                local normalized = normalizeLegacyField(setting, setting.section)
                if not normalized then return nil end
                fields[#fields + 1] = normalized
            end
            used[key] = true
        end
    end

    return {
        id = scriptId,
        label = definition.label or scriptId,
        icon = definition.icon,
        kvpPrefix = kvpPrefix,
        fields = fields,
        defaults = defaults,
        values = {},
    }
end

local function buildModernTab(tabId, label, icon, kvpPrefix, fields, defaults)
    local normalizedFields = {}
    local normalizedDefaults = shallowCopy(defaults)

    for _, field in ipairs(fields or {}) do
        if not safeObjectKey(field.key, 128) then return nil end

        if field.hidden == true then
            if normalizedDefaults[field.key] == nil and field.default ~= nil then
                normalizedDefaults[field.key] = field.default
            end
            goto continue
        end

        local normalized = sanitizeModernField(field)
        if not normalized then return nil end

        normalizedFields[#normalizedFields + 1] = normalized

        if normalizedDefaults[field.key] == nil and field.default ~= nil then
            normalizedDefaults[field.key] = field.default
        end

        ::continue::
    end

    return {
        id = tabId,
        label = label or tabId,
        icon = icon,
        kvpPrefix = kvpPrefix,
        fields = normalizedFields,
        defaults = normalizedDefaults,
        values = {},
    }
end

local function validateLegacyDefinition(definition)
    if type(definition) ~= 'table'
        or not isDenseArray(definition.settings or {}, MAX_SETTINGS_PER_TAB)
        or not isDenseArray(definition.sections or {}, MAX_FIELDS)
    then
        return false
    end

    local seen = {}
    for index = 1, #(definition.settings or {}) do
        local setting = definition.settings[index]
        if type(setting) ~= 'table' or not safeObjectKey(setting.key, 128) or seen[setting.key] then return false end
        seen[setting.key] = true
    end

    for index = 1, #(definition.sections or {}) do
        local section = definition.sections[index]
        if type(section) ~= 'table'
            or (section.label ~= nil and not boundedString(section.label, 128, true))
            or not isDenseArray(section.keys or {}, MAX_SETTINGS_PER_TAB)
        then
            return false
        end
        for keyIndex = 1, #(section.keys or {}) do
            if not safeObjectKey(section.keys[keyIndex], 128) then return false end
        end
    end
    return true
end

local VALID_FIELD_TYPES = {
    toggle = true,
    select = true,
    color = true,
    soundList = true,
    slider = true,
    buttons = true,
    text = true,
    input = true,
}

local function fieldAcceptsValue(field, value)
    if field.type == 'toggle' then return type(value) == 'boolean' end
    if field.type == 'slider' then
        return isFiniteNumber(value) and value >= field.min and value <= field.max
    end
    if field.type == 'select' or field.type == 'color' or field.type == 'soundList' then
        if customColor(field, value) then return true end
        for index = 1, #(field.options or {}) do
            local optionValue = field.options[index].value
            if type(optionValue) == type(value) and optionValue == value then return true end
        end
        return false
    end
    if field.type == 'text' or field.type == 'input' then
        local maxLength = field.maxLength or 256
        return boundedString(value, maxLength, true)
    end
    return field.type == 'buttons' and value == nil
end

local function findCortexField(key)
    for index = 1, #cortexFields do
        if cortexFields[index].key == key then return cortexFields[index] end
    end
    return nil
end

-- Stored values are untrusted: an edited or stale KVP falls back to the default.
local function reloadCortexSettings()
    for key, defaultValue in pairs(cortexDefaults) do
        local value = loadStoredValue(SETTINGS_PREFIX, key, defaultValue, false)
        local field = findCortexField(key)
        if field and not fieldAcceptsValue(field, value) then value = defaultValue end
        cortexSettings[key] = value
    end
end

local function validateTab(tab)
    if type(tab) ~= 'table'
        or not safeObjectKey(tab.id, 64)
        or tab.id == CORTEX_TAB_ID
        or not boundedString(tab.label, 128, false)
        or (tab.icon ~= nil and not boundedString(tab.icon, 64, true))
        or not boundedString(tab.kvpPrefix, 96, false)
        or not isDenseArray(tab.fields, MAX_FIELDS)
        or type(tab.defaults) ~= 'table'
    then
        return false, 'invalid_tab'
    end

    local defaultCount = 0
    for key, value in pairs(tab.defaults) do
        defaultCount = defaultCount + 1
        if defaultCount > MAX_SETTINGS_PER_TAB
            or not safeObjectKey(key, 128)
            or (type(value) == 'number' and not isFiniteNumber(value))
            or (type(value) == 'string' and not boundedString(value, 4096, true))
            or (type(value) ~= 'nil' and type(value) ~= 'boolean' and type(value) ~= 'number' and type(value) ~= 'string')
        then
            return false, 'invalid_defaults'
        end
    end

    local keys = {}
    for index = 1, #tab.fields do
        local field = tab.fields[index]
        if type(field) ~= 'table'
            or not safeObjectKey(field.key, 128)
            or keys[field.key]
            or not boundedString(field.label or field.key, 128, false)
            or not VALID_FIELD_TYPES[field.type]
            or (field.description ~= nil and not boundedString(field.description, 512, true))
        then
            return false, 'invalid_fields'
        end

        keys[field.key] = true
        if (field.type == 'select' or field.type == 'color' or field.type == 'soundList')
            and not isDenseArray(field.options or {}, MAX_OPTIONS)
        then
            return false, 'invalid_options'
        end
        if field.type == 'buttons' and not isDenseArray(field.buttons or {}, MAX_OPTIONS) then
            return false, 'invalid_buttons'
        end
        if field.type == 'select' or field.type == 'color' or field.type == 'soundList' then
            for optionIndex = 1, #field.options do
                local option = field.options[optionIndex]
                if type(option) ~= 'table' or option.value == nil
                    or (type(option.value) ~= 'string' and type(option.value) ~= 'number' and type(option.value) ~= 'boolean')
                    or (type(option.value) == 'number' and not isFiniteNumber(option.value))
                    or not boundedString(option.label or tostring(option.value), 128, true)
                then
                    return false, 'invalid_options'
                end
            end
        end
        if field.type == 'buttons' then
            for buttonIndex = 1, #field.buttons do
                local button = field.buttons[buttonIndex]
                if type(button) ~= 'table' or button.value == nil
                    or not boundedString(tostring(button.value), 128, false)
                    or not boundedString(button.label or tostring(button.value), 128, false)
                then
                    return false, 'invalid_buttons'
                end
            end
        end
        if field.type == 'slider' then
            local minValue = tonumber(field.min)
            local maxValue = tonumber(field.max)
            local step = field.step == nil and 1 or tonumber(field.step)
            if not isFiniteNumber(minValue) or not isFiniteNumber(maxValue) or not isFiniteNumber(step)
                or minValue > maxValue or step <= 0
            then
                return false, 'invalid_slider'
            end
            field.min, field.max, field.step = minValue, maxValue, step
        end
        if field.type ~= 'buttons' then
            local defaultValue = tab.defaults[field.key]
            if defaultValue == nil then return false, 'missing_default' end
            if not fieldAcceptsValue(field, defaultValue) then return false, 'invalid_default' end
        end
    end

    return true
end

local function validateTabStorageKeys(tab)
    for key in pairs(tab.defaults) do
        local storageKey = tab.kvpPrefix .. key

        for cortexKey in pairs(cortexDefaults) do
            if storageKey == SETTINGS_PREFIX .. cortexKey then
                return false, 'reserved_storage_key'
            end
        end

        for existingId, existing in pairs(registeredTabs) do
            if existingId ~= tab.id and existing then
                for existingKey in pairs(existing.defaults or {}) do
                    if storageKey == existing.kvpPrefix .. existingKey then
                        return false, 'storage_key_collision'
                    end
                end
            end
        end
    end

    return true
end

local function canMigrateLegacyValue(tab, key)
    if cortexDefaults[key] ~= nil then return false end

    for existingId, existing in pairs(registeredTabs) do
        if existingId ~= tab.id and existing and existing.defaults and existing.defaults[key] ~= nil then
            return false
        end
    end
    return true
end

local function reloadTabValues(tab)
    tab.values = {}

    for key, defaultValue in pairs(tab.defaults or {}) do
        tab.values[key] = loadStoredValue(
            tab.kvpPrefix,
            key,
            defaultValue,
            canMigrateLegacyValue(tab, key)
        )
    end
end

local function registerTab(tab, resourceName)
    local valid, err = validateTab(tab)
    if not valid then return false, err end

    valid, err = validateTabStorageKeys(tab)
    if not valid then return false, err end

    local owner = resourceName or tab.resource or tab.id
    local existing = registeredTabs[tab.id]
    if existing and existing.resource ~= owner then return false, 'owned_by_other_resource' end
    if not existing and #registeredOrder >= MAX_TABS then return false, 'capacity_exceeded' end
    if settingsOpen then
        local session = settingsSession
        rollbackPreviewValues()
        releaseSettingsFocus()
        SendNUIMessage({ action = 'settingsClose', data = { session = session, reason = 'registry_changed' } })
    end
    if existing then unregisterTab(tab.id) end

    ensureRegisteredOrder(tab.id)
    tab.resource = owner
    reloadTabValues(tab)
    registeredTabs[tab.id] = tab
    rebuildSettingIndex()
    return true
end

local function emitSettingChanged(key, value, tabId)
    TriggerEvent('cortex-lib:settingChanged', key, value, tabId)

    local listeners = settingListeners[key]
    local changedTab = registeredTabs[tabId]
    local changedOwner = tabId == CORTEX_TAB_ID and CURRENT_RESOURCE
        or (changedTab and changedTab.resource)

    -- Built-in Cortex settings are globally readable, but direct callback registrations stay
    -- owner-scoped just like consumer tabs. The public settingChanged event remains observable.
    if listeners and changedOwner then
        for index = 1, #listeners do
            local listener = listeners[index]
            if listener.owner == changedOwner then
                pcall(listener.callback, value, key, tabId)
            end
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

    local okDefinition, definition = pcall(function()
        return exports[resourceName]:getSettingsDefinition()
    end)

    if not okDefinition then
        local message = safeErrorText(definition):lower()
        if message:find('no such export', 1, true) or message:find('does not have export', 1, true) then
            discoveredResources[resourceName] = true
        end
        return
    end
    if definition == nil then discoveredResources[resourceName] = true; return end
    if not validateLegacyDefinition(definition) then return end

    local prefix = normalizeStoragePrefix(resourceName, definition.kvpPrefix)
    local tab = prefix and buildLegacyTab(resourceName, definition, prefix) or nil
    local registered = tab and registerTab(tab, resourceName) or false
    if registered then discoveredResources[resourceName] = true end
end

local function refreshDiscoveredSettingsTabs(force)
    if not force and not discoveryDirty then return end
    discoveryDirty = false
    local resourceCount = GetNumResources()

    for index = 0, resourceCount - 1 do
        local resourceName = GetResourceByFindIndex(index)
        tryRegisterResourceDefinition(resourceName)
    end
end

local function buildTabsPayload()
    refreshDiscoveredSettingsTabs(true)
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
                icon = tab.icon,
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
    if not safeObjectKey(tabId, 64) then
        return false, nil
    end

    if not safeObjectKey(key, 128) then
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
            if option.value ~= nil and type(option.value) == type(value) and option.value == value then
                return true, option.value
            end
        end

        local custom = customColor(field, value)
        if custom then return true, custom end
        return false, nil
    end

    if fieldType == 'text' or fieldType == 'input' then
        if type(value) ~= 'string' or value:find('\0', 1, true) then
            return false, nil
        end

        local maxLength = math.min(4096, math.max(1, tonumber(field.maxLength) or 256))
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

    if type(value) == 'string' and (#value > 4096 or value:find('\0', 1, true)) then
        return false, nil
    end

    if type(value) ~= 'boolean' and type(value) ~= 'number' and type(value) ~= 'string' then
        return false, nil
    end

    return true, value
end

local function buildUiPrefs()
    local scale = tonumber(cortexSettings.uiScale) or cortexDefaults.uiScale
    local limit = math.tointeger(tonumber(cortexSettings.notifyLimit)) or cortexDefaults.notifyLimit
    return {
        scale = math.floor(math.max(80, math.min(130, scale)) + 0.5) / 100,
        textSize = cortexSettings.textSize == 'large' and 'large' or 'standard',
        notifyDuration = NOTIFY_DURATION_SCALE[cortexSettings.notifyDuration] or 1.0,
        notifyLimit = limit,
        showPercent = cortexSettings.showPercent ~= false,
        promptMarkers = cortexSettings.promptMarkers ~= false,
        promptScale = (cortexSettings.promptScale == 'small' or cortexSettings.promptScale == 'large')
            and cortexSettings.promptScale or 'standard',
        controlHints = cortexSettings.controlHints ~= false,
        invertScroll = cortexSettings.invertScroll == true,
    }
end

-- The runtime (preview-inclusive) values drive the shared NUI. Rollback and
-- Save both flow through here, so the NUI always matches lib.getSetting.
local function pushUiPrefs()
    SendNUIMessage({ action = 'cortex:prefs', data = { prefs = buildUiPrefs() } })
end
lib._getUiPrefs = buildUiPrefs

local function notifyCortexRuntimeChanges(changes)
    if changes.notifyPosition then
        SendNUIMessage({
            action = 'notifySetPosition',
            data = { position = changes.notifyPosition }
        })
    end
    for key in pairs(changes) do
        if PREF_KEYS[key] then pushUiPrefs(); break end
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

rollbackPreviewValues = function()
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

local function resolveTabForKey(key)
    local owner = getInvokingOwner()
    local tabId = settingIndex[key]
    if owner == CURRENT_RESOURCE then
        if type(tabId) == 'string' then return tabId, registeredTabs[tabId] end
        if tabId ~= false then return nil, nil end
    end

    for index = 1, #registeredOrder do
        local candidateId = registeredOrder[index]
        local candidate = registeredTabs[candidateId]
        if candidate and candidate.resource == owner and candidate.defaults[key] ~= nil then
            return candidateId, candidate
        end
    end
    return nil, nil
end

-- A consumer tab that declares a key with the same name as a built-in Cortex
-- preference keeps its own value; built-ins answer everyone else.
local function ownsTabKey(key)
    if getInvokingOwner() == CURRENT_RESOURCE then return false end
    local _, tab = resolveTabForKey(key)
    return tab ~= nil
end

local function setTrackedSetting(key, value)
    if not safeObjectKey(key, 128) then return false end

    if cortexDefaults[key] ~= nil and not ownsTabKey(key) then
        local valid, normalized = normalizeNuiSettingValue(CORTEX_TAB_ID, key, value)
        if not valid then return false end

        local stored = saveStoredValue(SETTINGS_PREFIX, key, normalized)
        if not stored then return false end
        cortexSettings[key] = normalized
        notifyCortexRuntimeChanges({ [key] = normalized })
        emitSettingChanged(key, normalized, CORTEX_TAB_ID)
        return true
    end

    local tabId, tab = resolveTabForKey(key)

    if not tab then
        return false
    end

    local valid, normalized = normalizeNuiSettingValue(tabId, key, value)
    if not valid then return false end
    local stored = saveTabStoredValue(tab, key, normalized)
    if not stored then return false end
    tab.values[key] = normalized
    emitTabChanged(tabId, { [key] = normalized })
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
                local stored, writeError = saveStoredValue(SETTINGS_PREFIX, key, normalized)
                if not stored then error(('kvp_write_failed:%s'):format(safeErrorText(writeError))) end
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
            local stored, writeError = saveTabStoredValue(tab, key, normalized)
            if not stored then error(('kvp_write_failed:%s'):format(safeErrorText(writeError))) end
            tab.values[key] = normalized
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

    return committed
end

local function capturePersistedValues(tabs)
    local originals = {}
    for tabId, values in next, tabs do
        local prefix
        if tabId == CORTEX_TAB_ID then
            prefix = SETTINGS_PREFIX
        else
            local tab = registeredTabs[tabId]
            prefix = tab and tab.kvpPrefix or nil
        end
        if not prefix then return nil, 'missing_tab' end

        for key in next, values do
            local storageKey = prefix .. key
            if originals[storageKey] == nil then
                local ok, value = readStoredValue(storageKey)
                if not ok then return nil, 'kvp_read_failed' end
                originals[storageKey] = { present = value ~= nil, value = value }
            end
        end
    end
    return originals
end

local function restorePersistedValues(originals)
    local restored = true
    for storageKey, original in next, originals or {} do
        local ok
        if original.present then
            ok = pcall(SetResourceKvp, storageKey, original.value)
        elseif type(DeleteResourceKvp) == 'function' then
            ok = pcall(DeleteResourceKvp, storageKey)
        else
            ok = false
        end
        if not ok then restored = false end
    end
    return restored
end

local function validatePreviewSubmission(tabs)
    if type(tabs) ~= 'table' then return nil end
    local normalizedTabs = {}
    local tabCount = 0

    for tabId, values in next, tabs do
        tabCount = tabCount + 1
        if type(tabId) ~= 'string' or not boundedString(tabId, 64, false)
            or tabCount > MAX_TABS + 1 or type(values) ~= 'table'
        then
            return nil
        end
        local fields, tabDefaults = getTabState(tabId)
        if not fields or not tabDefaults then return nil end

        local normalizedValues = {}
        local valueCount = 0
        for key, value in next, values do
            valueCount = valueCount + 1
            local valid, normalized = normalizeNuiSettingValue(tabId, key, value)
            if valueCount > MAX_SETTINGS_PER_TAB or not valid then return nil end
            normalizedValues[key] = normalized
        end
        normalizedTabs[tabId] = normalizedValues
    end
    return normalizedTabs
end

function lib.getSetting(key)
    if cortexDefaults[key] ~= nil and not ownsTabKey(key) then
        return cortexSettings[key]
    end

    local _, tab = resolveTabForKey(key)

    if tab then
        return tab.values[key]
    end

    return nil
end

function lib.getAllSettings()
    local out = shallowCopy(cortexSettings)

    local owner = getInvokingOwner()
    for key, indexedTabId in pairs(settingIndex) do
        local tabId, tab
        if owner == CURRENT_RESOURCE and type(indexedTabId) == 'string' then
            tabId, tab = indexedTabId, registeredTabs[indexedTabId]
        else
            tabId, tab = resolveTabForKey(key)
        end
        if tabId and tab then out[key] = tab.values[key] end
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
    local tab = registeredTabs[tabId]
    if not tab or (getInvokingOwner() ~= CURRENT_RESOURCE and tab.resource ~= getInvokingOwner()) then
        return nil
    end

    return tab.values[key]
end

function lib.getNotifySoundCatalog()
    local catalog = {}
    for index = 1, #NOTIFY_SOUND_CATALOG do catalog[index] = shallowCopy(NOTIFY_SOUND_CATALOG[index]) end
    return catalog
end

function lib.onSettingChange(key, callback)
    local mt = type(callback) == 'table' and getmetatable(callback)
    local callable = type(callback) == 'function'
        or type(mt) == 'table' and type(rawget(mt,'__call')) == 'function'
    if not safeObjectKey(key, 128) or not callable then
        return false
    end

    local listeners = settingListeners[key]

    if not listeners then
        listeners = {}
        settingListeners[key] = listeners
    end

    listeners[#listeners + 1] = {
        owner = getInvokingOwner(),
        callback = callback,
    }
    return true
end

function lib.registerSettingsScript(scriptId, definition)
    if not safeObjectKey(scriptId, 64)
        or scriptId == CORTEX_TAB_ID
        or not validateLegacyDefinition(definition)
    then
        return false
    end

    local prefix = normalizeStoragePrefix(scriptId, definition.kvpPrefix)
    if not prefix then return false, 'invalid_kvp_prefix' end
    local tab = buildLegacyTab(scriptId, definition, prefix)
    if not tab then return false, 'invalid_fields' end
    return registerTab(tab, getRegistrationOwner(scriptId))
end

function lib.registerSettings(tabId, tabLabel, kvpPrefix, fields, defaults)
    if type(tabLabel) == 'table' and kvpPrefix == nil then
        return lib.registerSettingsScript(tabId, tabLabel)
    end

    local resolvedFields = fields
    local resolvedDefaults = defaults
    local resolvedIcon = nil
    local resolvedPrefix = nil

    if type(kvpPrefix) == 'table' then
        resolvedFields = kvpPrefix
        resolvedDefaults = fields
    elseif type(kvpPrefix) == 'string' then
        if kvpPrefix:sub(-1) == ':' then
            resolvedPrefix = kvpPrefix
        else
            resolvedIcon = kvpPrefix
        end
    end

    if not safeObjectKey(tabId, 64)
        or tabId == CORTEX_TAB_ID
        or not boundedString(tabLabel or tabId, 128, false)
        or (resolvedIcon ~= nil and not boundedString(resolvedIcon, 64, true))
    then
        return false
    end

    if not isDenseArray(resolvedFields or {}, MAX_FIELDS) or type(resolvedDefaults or {}) ~= 'table' then
        return false
    end
    for index = 1, #(resolvedFields or {}) do
        if type(resolvedFields[index]) ~= 'table' then return false end
    end

    resolvedPrefix = normalizeStoragePrefix(tabId, resolvedPrefix)
    if not resolvedPrefix then return false, 'invalid_kvp_prefix' end
    local tab = buildModernTab(tabId, tabLabel, resolvedIcon, resolvedPrefix, resolvedFields or {}, resolvedDefaults or {})
    if not tab then return false, 'invalid_fields' end
    return registerTab(tab, getRegistrationOwner(tabId))
end

local function openSettingsSurface(page)
    if settingsOpen then
        return false
    end

    if type(IsPauseMenuActive) == 'function' and IsPauseMenuActive() then return false end

    local tabs = buildTabsPayload()
    local owner = getInvokingOwner()
    local session = acquireSettingsModal(owner)
    if not session then return false end

    beginPreviewSession()
    settingsOpen = true
    settingsSession = session
    settingsOwner = owner
    settingsReady = false
    if rawget(lib, '_settingsVisibilityChanged') then lib._settingsVisibilityChanged(true) end

    SendNUIMessage({
        action = 'settingsOpen',
        data = { tabs = tabs, session = session, page = page or 'settings',
            pause = rawget(lib, '_getPausePayload') and lib._getPausePayload() or nil }
    })
    if type(SetTimeout) == 'function' then
        SetTimeout(SETTINGS_READY_TIMEOUT, function()
            if settingsOpen and settingsSession == session and not settingsReady then
                rollbackPreviewValues()
                releaseSettingsFocus()
                if rawget(lib, '_pauseReadinessFailed') then lib._pauseReadinessFailed() end
                SendNUIMessage({ action = 'settingsClose', data = {
                    session = session, reason = 'settings_ready_timeout',
                } })
            end
        end)
    end
    return true
end

-- Private entry points share the existing preview and modal lifecycle. A native
-- handoff must discard previews before another UI can take focus.
lib._openSettingsSurface = openSettingsSurface
lib._closeSettingsForPause = function(session)
    if not matchesSettingsModal({ session = session }) then return false end
    rollbackPreviewValues()
    releaseSettingsFocus()
    SendNUIMessage({ action = 'settingsClose', data = { session = session } })
    return true
end

function lib.openSettings()
    return openSettingsSurface('settings')
end

function lib.openSettingsMenu()
    return lib.openSettings()
end

function lib.closeSettings()
    local wasOpen = settingsOpen
    local session = settingsSession
    if wasOpen and settingsOwner ~= getInvokingOwner() then return false end

    if wasOpen then
        rollbackPreviewValues()
        releaseSettingsFocus()
        SendNUIMessage({ action = 'settingsClose', data = { session = session } })
    end
end

function lib.closeSettingsMenu()
    return lib.closeSettings()
end

migrateRetiredDynamicTab()
reloadCortexSettings()

-- The shared NUI asks for preferences once it has mounted (and again after a
-- cortex-lib restart reloads the page). No session: prefs are not modal state.
RegisterNUICallback('cortexPrefsReady', function(_, cb)
    pushUiPrefs()
    SendNUIMessage({ action = 'notifySetPosition', data = { position = cortexSettings.notifyPosition } })
    cb({ ok = true })
end)

RegisterNUICallback('settingsReady', function(data, cb)
    if not matchesSettingsModal(data) then cb({ ok = false, error = 'stale_session' }); return end
    local ok = focusSettingsModal(settingsSession)
    if ok then
        settingsReady = true
    else
        local session = settingsSession
        rollbackPreviewValues()
        releaseSettingsFocus()
        SendNUIMessage({ action = 'settingsClose', data = { session = session, reason = 'focus_failed' } })
    end
    cb({ ok = ok, error = ok and nil or 'focus_failed' })
end)

RegisterNUICallback('settingsSave', function(data, cb)
    if not matchesSettingsModal(data) or not previewSnapshot or type(data.tabs) ~= 'table' then
        cb({ ok = false, error = 'stale_session' })
        return
    end

    if data.keepOpen ~= nil and type(data.keepOpen) ~= 'boolean' then
        cb({ ok = false, error = 'invalid_settings' })
        return
    end

    local tabs = validatePreviewSubmission(data.tabs)
    if not tabs then
        cb({ ok = false, error = 'invalid_settings' })
        return
    end

    local persistedOriginals, captureError = capturePersistedValues(tabs)
    if not persistedOriginals then
        cb({ ok = false, error = captureError or 'commit_failed' })
        return
    end

    local ok, committed = pcall(function()
        return commitPreviewValues(tabs)
    end)
    if not ok then
        local persistedRestored = restorePersistedValues(persistedOriginals)
        rollbackPreviewValues()
        beginPreviewSession()
        pcall(print, ('^1[cortex-lib]^7 settings save failed: %s'):format(safeErrorText(committed)))
        cb({ ok = false, error = 'commit_failed', persistedRestored = persistedRestored })
        return
    end

    if data.keepOpen == true then
        -- Apply commits a new rollback baseline without releasing this session.
        beginPreviewSession()
        cb({ ok = true, committed = committed, applied = true })
        return
    end

    local session = settingsSession
    previewSnapshot = nil
    releaseSettingsFocus()
    SendNUIMessage({ action = 'settingsClose', data = { session = session } })
    cb({ ok = true, committed = committed })
end)

RegisterNUICallback('settingsCancel', function(data, cb)
    if not matchesSettingsModal(data) then cb({ ok = false, error = 'stale_session' }); return end

    local session = settingsSession
    local restored = rollbackPreviewValues()
    releaseSettingsFocus()
    SendNUIMessage({ action = 'settingsClose', data = { session = session } })
    cb({ ok = true, restored = restored })
end)

RegisterNUICallback('settingsPreview', function(data, cb)
    local tabId = data and data.tabId or nil
    local key = data and data.key or nil
    local value = data and data.value
    local applied = 0
    local ok = false

    if matchesSettingsModal(data) and type(tabId) == 'string' then
        if type(data.values) == 'table' then
            local inspected = 0
            local normalizedValues = {}
            ok = getTabState(tabId) ~= nil
            for candidateKey, candidateValue in pairs(data.values) do
                inspected = inspected + 1
                local valid, normalized = normalizeNuiSettingValue(tabId, candidateKey, candidateValue)
                if inspected > MAX_SETTINGS_PER_TAB or not valid then ok = false; break end
                normalizedValues[candidateKey] = normalized
            end
            if ok then applied = applyRuntimeTabValues(tabId, normalizedValues) end
        else
            ok = previewTabValue(tabId, key, value)
            applied = ok and 1 or 0
        end
    end

    cb({ ok = ok, applied = applied })
end)

RegisterNUICallback('settingsPreviewSound', function(data, cb)
    if not matchesSettingsModal(data) then cb({ ok = false, error = 'stale_session' }); return end

    local allowed = false
    for index = 1, #NOTIFY_SOUND_CATALOG do
        local entry = NOTIFY_SOUND_CATALOG[index]
        if entry.name == data.name and entry.set == data.set then allowed = true; break end
    end
    if not allowed then cb({ ok = false, error = 'invalid_sound' }); return end

    local soundId = GetSoundId()
    PlaySoundFrontend(soundId, data.name, data.set, true)
    ReleaseSoundId(soundId)
    cb({ ok = true })
end)

RegisterNUICallback('settingsAction', function(data, cb)
    if not matchesSettingsModal(data) then cb({ ok = false, error = 'stale_session' }); return end

    local tabId = data.tabId
    local fieldKey = data.key
    local fields = getTabState(tabId)
    local field = fields and findTabField(fields, fieldKey) or nil
    local action = data.value
    if action == nil then action = data.key end
    local actionType = type(action)
    local validAction = actionType == 'string' or actionType == 'boolean'
        or (actionType == 'number' and isFiniteNumber(action))
    local allowed = field and field.type == 'buttons' and validAction
        and boundedString(tostring(action), 128, false)
    if allowed then
        allowed = false
        for index = 1, #(field.buttons or {}) do
            local buttonValue = field.buttons[index].value
            if type(buttonValue) == actionType and buttonValue == action then allowed = true; break end
        end
    end

    if not allowed then cb({ ok = false, error = 'invalid_action' }); return end

    TriggerEvent('cortex-lib:settingsAction', tabId, action, fieldKey, data.value)
    cb({ ok = true })
end)

local function closeSettingsForModal(generation, reason)
    if settingsSession ~= generation then return end

    rollbackPreviewValues()
    settingsOpen = false
    settingsSession = nil
    settingsOwner = nil
    settingsReady = false
    if rawget(lib, '_settingsVisibilityChanged') then lib._settingsVisibilityChanged(false) end
    SendNUIMessage({ action = 'settingsClose', data = { session = generation, reason = reason } })
end
local pendingModalSurfaces = rawget(lib, '_pendingModalSurfaces') or {}
pendingModalSurfaces.settings = closeSettingsForModal
rawset(lib, '_pendingModalSurfaces', pendingModalSurfaces)
if type(lib._registerModalSurface) == 'function' then lib._registerModalSurface('settings', closeSettingsForModal) end

AddEventHandler('onResourceStart', function(resourceName)
    discoveryDirty = true
    if resourceName == CURRENT_RESOURCE then
        refreshDiscoveredSettingsTabs(true)
        return
    end

    discoveredResources[resourceName] = nil
    tryRegisterResourceDefinition(resourceName)
end)

AddEventHandler('onResourceStop', function(resourceName)
    discoveryDirty = true
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

    local removedListener = false
    for key, listeners in pairs(settingListeners) do
        for index = #listeners, 1, -1 do
            if listeners[index].owner == resourceName then table.remove(listeners, index); removedListener = true end
        end
        if #listeners == 0 then settingListeners[key] = nil end
    end

    if settingsOpen and (resourceName == CURRENT_RESOURCE or settingsOwner == resourceName or #stoppedTabs > 0) then
        local session = settingsSession
        rollbackPreviewValues()
        releaseSettingsFocus()
        SendNUIMessage({ action = 'settingsClose', data = { session = session, reason = 'resource_stop' } })
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
