--[[
    Everest Lib - Client Notification System
    Lazy-loaded module that returns notify functions
    
    Usage: lib.notify({ type = 'success', description = 'Hello!' })
]]

---@alias NotifyPosition 'top' | 'top-right' | 'top-left' | 'bottom' | 'bottom-right' | 'bottom-left'
---@alias NotifyType 'info' | 'inform' | 'success' | 'warning' | 'error'

---@class SoundData
---@field name string Sound name
---@field set string Sound set/bank name

---@class NotifyData
---@field id? string Unique ID (for updating/removing)
---@field title? string Notification title
---@field description? string Notification message
---@field duration? number Duration in ms (default 3000, 0 = persistent)
---@field position? NotifyPosition Position on screen
---@field type? NotifyType Notification type/style
---@field showDuration? boolean Show duration progress bar
---@field sound? boolean|SoundData|false Omit = default click; true = settings/preset; table = custom; false = mute
---@field persistent? boolean If true, notification stays until manually closed
---@field plain? boolean Transparent panel (no black card)
---@field hideIcon? boolean Hide leading type icon
---@field icon? boolean Set `false` to hide icon (same as hideIcon)

-- Min ms between notification UI sounds (burst spam guard)
local NOTIFY_SOUND_MIN_INTERVAL_MS = 280
local lastNotifySoundGameMs = 0

-- Sound presets for quick access
local SoundPresets = {
    success = { name = 'MEDAL_UP', set = 'HUD_MINI_GAME_SOUNDSET' },
    error = { name = 'ERROR', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    warning = { name = 'WARNING', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    info = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
}

local function isSoundEnabled()
    local getSetting = lib.getSetting
    if type(getSetting) ~= 'function' then
        return true
    end

    local setting = getSetting('notifySound')
    if setting == nil then
        return true
    end

    return setting
end

---Resolve { name, set } from Settings → Sound preset (used when `sound == true`).
local function resolveUserDefaultSound()
    local getCatalog = lib.getNotifySoundCatalog
    local getSetting = lib.getSetting

    if type(getCatalog) ~= 'function' or type(getSetting) ~= 'function' then
        return nil
    end

    local presetId = getSetting('notifySoundPreset')
    if type(presetId) ~= 'string' or presetId == '' then
        return nil
    end

    for _, entry in ipairs(getCatalog()) do
        if entry.value == presetId then
            return { name = entry.name, set = entry.set }
        end
    end

    return nil
end

local function getDefaultPosition()
    local getSetting = lib.getSetting
    if type(getSetting) ~= 'function' then
        return 'top-right'
    end

    return getSetting('notifyPosition') or 'top-right'
end

---Play a native GTA sound
---@param sound SoundData|boolean
---@param notifyType? string
local function playSound(sound, notifyType)
    if not isSoundEnabled() then
        return
    end

    local soundData
    
    if sound == true then
        soundData = resolveUserDefaultSound() or SoundPresets[notifyType] or SoundPresets.info
    elseif type(sound) == 'table' then
        soundData = sound
    else
        return
    end

    local now = GetGameTimer()
    if now - lastNotifySoundGameMs < NOTIFY_SOUND_MIN_INTERVAL_MS then
        return
    end
    lastNotifySoundGameMs = now

    local soundId = GetSoundId()
    PlaySoundFrontend(soundId, soundData.name, soundData.set, true)
    ReleaseSoundId(soundId)
end

-- ============================================================================
-- NOTIFY FUNCTION
-- ============================================================================

---Send a notification to the player
---@param data NotifyData|string
---@return string|nil id The notification ID if provided
local function notify(data)
    -- Support simple string notifications
    if type(data) == 'string' then
        data = { description = data }
    end

    -- Defaults
    data.type = data.type or 'info'
    data.position = data.position or getDefaultPosition()
    
    -- Handle persistent notifications
    if data.persistent then
        data.duration = 0
    else
        data.duration = data.duration or 3000
    end
    
    -- Native sound every notify unless explicitly muted (exports / net / lib paths)
    if data.sound ~= false then
        local s = data.sound
        if s == nil then
            s = true
        end
        playSound(s, data.type)
    end

    -- Don't send sound data to NUI
    local nuiData = {}
    for k, v in pairs(data) do
        if k ~= 'sound' then
            nuiData[k] = v
        end
    end

    SendNUIMessage({
        action = 'notify',
        data = nuiData
    })
    
    return data.id
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Hide a notification by ID
---@param id string
local function hideNotify(id)
    SendNUIMessage({
        action = 'hideNotify',
        data = { id = id }
    })
end

---Clear all active notifications
local function clearNotifications()
    SendNUIMessage({
        action = 'clearNotifications'
    })
end

---@param msg string
---@param title? string
---@param sound? boolean|SoundData
local function notifySuccess(msg, title, sound)
    notify({ type = 'success', description = msg, title = title, sound = sound })
end

---@param msg string
---@param title? string
---@param sound? boolean|SoundData
local function notifyError(msg, title, sound)
    notify({ type = 'error', description = msg, title = title, sound = sound })
end

---@param msg string
---@param title? string
---@param sound? boolean|SoundData
local function notifyWarning(msg, title, sound)
    notify({ type = 'warning', description = msg, title = title, sound = sound })
end

---@param msg string
---@param title? string
---@param sound? boolean|SoundData
local function notifyInfo(msg, title, sound)
    notify({ type = 'info', description = msg, title = title, sound = sound })
end

-- ============================================================================
-- PROGRESS BAR SYSTEM
-- ============================================================================

---@class ProgressData
---@field duration number Duration in ms
---@field label? string Progress label text
---@field position? 'bottom' | 'middle' Position on screen
---@field style? 'bar' | 'circle' Progress UI style
---@field useWhileDead? boolean Allow while dead
---@field canCancel? boolean Allow cancellation with right-click
---@field disable? table { move?: boolean, car?: boolean, combat?: boolean, mouse?: boolean }
---@field anim? table { dict?: string, clip: string, flag?: number, blendIn?: number, blendOut?: number, scenario?: string }
---@field prop? table { model: string, bone?: number, pos?: vector3, rot?: vector3 }

local activeProgress = nil

---Request an animation dictionary with timeout
---@param dict string
---@param timeout? number Timeout in ms (default 5000)
---@return boolean
local function requestAnimDict(dict, timeout)
    if HasAnimDictLoaded(dict) then return true end
    
    RequestAnimDict(dict)
    local start = GetGameTimer()
    timeout = timeout or 5000
    
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() - start > timeout then
            return false
        end
        Wait(0)
    end
    
    return true
end

---Request a model with timeout
---@param model string|number
---@param timeout? number Timeout in ms (default 5000)
---@return boolean
local function requestModel(model, timeout)
    if type(model) == 'string' then
        model = joaat(model)
    end
    
    if HasModelLoaded(model) then return true end
    
    RequestModel(model)
    local start = GetGameTimer()
    timeout = timeout or 5000
    
    while not HasModelLoaded(model) do
        if GetGameTimer() - start > timeout then
            return false
        end
        Wait(0)
    end
    
    return true
end

---Start a progress bar
---@param data ProgressData
---@return boolean completed True if completed, false if cancelled
local function progress(data)
    if activeProgress then
        return false
    end
    
    activeProgress = data
    local completed = true
    local startTime = GetGameTimer()
    local duration = data.duration
    local ped = cache.ped or PlayerPedId()
    
    -- Load animation dict if needed
    if data.anim then
        if data.anim.dict then
            requestAnimDict(data.anim.dict)
            TaskPlayAnim(ped, data.anim.dict, data.anim.clip, 
                data.anim.blendIn or 3.0, data.anim.blendOut or 1.0, 
                -1, data.anim.flag or 49, 0, false, false, false)
        elseif data.anim.scenario then
            TaskStartScenarioInPlace(ped, data.anim.scenario, 0, true)
        end
    end
    
    -- Create prop if needed
    local propEntity = nil
    if data.prop then
        requestModel(data.prop.model)
        local coords = GetEntityCoords(ped)
        propEntity = CreateObject(joaat(data.prop.model), coords.x, coords.y, coords.z, true, true, true)
        local bone = data.prop.bone or 60309 -- Right hand
        local pos = data.prop.pos or vector3(0.0, 0.0, 0.0)
        local rot = data.prop.rot or vector3(0.0, 0.0, 0.0)
        AttachEntityToEntity(propEntity, ped, GetPedBoneIndex(ped, bone), 
            pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 0, true)
        SetModelAsNoLongerNeeded(joaat(data.prop.model))
    end

    -- Show progress UI
    SendNUIMessage({
        action = 'progressStart',
        data = {
            duration = duration,
            label = data.label or '',
            position = data.position or 'bottom',
            style = data.style or 'bar',
            canCancel = data.canCancel or false
        }
    })
    
    -- Progress loop
    while activeProgress do
        local elapsed = GetGameTimer() - startTime
        
        if elapsed >= duration then
            break
        end
        
        -- Check for cancellation
        if data.canCancel and IsControlJustPressed(0, 177) then
            completed = false
            break
        end
        
        -- Check if dead
        if not data.useWhileDead and IsEntityDead(ped) then
            completed = false
            break
        end
        
        -- Apply disables
        if data.disable then
            if data.disable.move then
                DisableControlAction(0, 30, true)
                DisableControlAction(0, 31, true)
                DisableControlAction(0, 21, true)
                DisableControlAction(0, 22, true)
            end
            if data.disable.car then
                DisableControlAction(0, 63, true)
                DisableControlAction(0, 64, true)
                DisableControlAction(0, 71, true)
                DisableControlAction(0, 72, true)
            end
            if data.disable.combat then
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
            end
            if data.disable.mouse then
                DisableControlAction(0, 1, true)
                DisableControlAction(0, 2, true)
            end
        end
        
        Wait(0)
    end
    
    -- Cleanup
    activeProgress = nil
    
    -- Hide progress UI
    SendNUIMessage({ action = 'progressEnd' })
    
    -- Clear animation
    if data.anim then
        if data.anim.dict then
            StopAnimTask(ped, data.anim.dict, data.anim.clip, 1.0)
            RemoveAnimDict(data.anim.dict)
        elseif data.anim.scenario then
            ClearPedTasks(ped)
        end
    end
    
    -- Delete prop
    if propEntity and DoesEntityExist(propEntity) then
        DeleteEntity(propEntity)
    end
    
    return completed
end

---Cancel the active progress bar
local function cancelProgress()
    if activeProgress then
        activeProgress = nil
    end
end

---Check if a progress bar is active
---@return boolean
local function isProgressActive()
    return activeProgress ~= nil
end

-- ============================================================================
-- ALERT DIALOG
-- ============================================================================

---@class AlertDialogData
---@field header? string
---@field content? string|string[]
---@field centered? boolean
---@field cancel? boolean
---@field labels? { confirm?: string, cancel?: string }
---@field style? table<string, any>

---@alias AlertDialogResult 'confirm' | 'cancel'

local alertPromise = nil

---Show an alert dialog and await the result
---@param data AlertDialogData
---@return AlertDialogResult
local function alertDialog(data)
    if alertPromise then
        return 'cancel'
    end

    data = data or {}

    alertPromise = promise.new()

    SendNUIMessage({
        action = 'alertDialog',
        data = {
            header = data.header,
            content = data.content,
            centered = data.centered or false,
            cancel = data.cancel ~= false,
            labels = data.labels or {},
            style = data.style
        }
    })

    local result = Citizen.Await(alertPromise)
    alertPromise = nil
    return result
end

RegisterNUICallback('alertDialogResult', function(data, cb)
    if alertPromise then
        alertPromise:resolve(data and data.result or 'cancel')
    end

    cb({ ok = true })
end)

-- ============================================================================
-- TEXT UI
-- ============================================================================

---@class TextUIData
---@field text string
---@field position? 'top-center' | 'top-left' | 'top-right' | 'bottom-center' | 'bottom-left' | 'bottom-right'
---@field icon? 'hand' | string
---@field style? table<string, any>
---@field backdrop? boolean When true, allow solid background/border from `style` (default: false = text-only plate)

---Show a single top-level text UI prompt
---@param text string
---@param opts? TextUIData
local function showTextUI(text, opts)
    opts = opts or {}

    SendNUIMessage({
        action = 'textUIShow',
        data = {
            text = text,
            position = opts.position or 'bottom-center',
            icon = opts.icon,
            style = opts.style,
            backdrop = opts.backdrop == true
        }
    })
end

---Hide the text UI prompt
local function hideTextUI()
    SendNUIMessage({ action = 'textUIHide' })
end

local contextMenuPromise = nil

local function contextMenu(data)
    if contextMenuPromise then
        return nil
    end

    data = data or {}

    contextMenuPromise = promise.new()

    SendNUIMessage({
        action = 'contextMenu',
        data = {
            title = data.title,
            fields = data.fields or {},
            values = data.values or {},
            labels = data.labels or {}
        }
    })

    SetNuiFocus(true, true)

    local result = Citizen.Await(contextMenuPromise)
    contextMenuPromise = nil

    SetNuiFocus(false, false)

    return result
end

local function hideContextMenu()
    if contextMenuPromise then
        contextMenuPromise:resolve(nil)
    end

    SendNUIMessage({ action = 'contextMenuClose' })
    SetNuiFocus(false, false)
end

RegisterNUICallback('contextMenuResult', function(data, cb)
    if contextMenuPromise then
        if data and data.result == 'confirm' then
            contextMenuPromise:resolve(data.values)
        else
            contextMenuPromise:resolve(nil)
        end
    end

    SetNuiFocus(false, false)
    cb({ ok = true })
end)

-- ============================================================================
-- NET EVENTS
-- ============================================================================

RegisterNetEvent('es_lib:notify', function(data)
    notify(data)
end)

-- ============================================================================
-- EXPORTS (for compatibility)
-- ============================================================================

exports('notify', notify)
exports('hideNotify', hideNotify)
exports('clearNotifications', clearNotifications)
exports('progress', progress)
exports('cancelProgress', cancelProgress)
exports('isProgressActive', isProgressActive)
exports('alertDialog', alertDialog)
exports('contextMenu', contextMenu)
exports('hideContextMenu', hideContextMenu)
exports('showTextUI', showTextUI)
exports('hideTextUI', hideTextUI)
exports('notifySuccess', notifySuccess)
exports('notifyError', notifyError)
exports('notifyWarning', notifyWarning)
exports('notifyInfo', notifyInfo)
exports('requestAnimDict', requestAnimDict)
exports('requestModel', requestModel)

-- Compatibility export with capital N and (type, message, duration) signature
exports('Notify', function(notifyType, message, duration)
    notify({
        type = notifyType or 'info',
        description = message or '',
        duration = duration or 3000
    })
end)

-- ============================================================================
-- RETURN MODULE API
-- ============================================================================

-- Attach functions to lib table for lib.notify(), lib.progress(), etc.
lib.notify = notify
lib.hideNotify = hideNotify
lib.clearNotifications = clearNotifications
lib.notifySuccess = notifySuccess
lib.notifyError = notifyError
lib.notifyWarning = notifyWarning
lib.notifyInfo = notifyInfo
lib.progress = progress
lib.cancelProgress = cancelProgress
lib.isProgressActive = isProgressActive
lib.alertDialog = alertDialog
lib.contextMenu = contextMenu
lib.hideContextMenu = hideContextMenu
lib.showTextUI = showTextUI
lib.hideTextUI = hideTextUI
lib.requestAnimDict = requestAnimDict
lib.requestModel = requestModel

return notify
