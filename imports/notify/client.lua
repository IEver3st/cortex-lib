--[[
    Cortex Lib - Client Notification System
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

local notifyDedupeSoundKeyLast = nil
local notifyDedupeSoundAt = 0
local NOTIFY_DEDUPE_SOUND_MS = 400

local function notifyDedupeSoundKey(data)
    local t = data.type or 'info'
    local title = data.title
    local desc = data.description
    if title == nil then title = '' else title = tostring(title) end
    if desc == nil then desc = '' else desc = tostring(desc) end
    return t .. '\0' .. title .. '\0' .. desc
end

local function notify(data)
    if type(data) == 'string' then
        data = { description = data }
    end

    data.type = data.type or 'info'
    data.position = data.position or getDefaultPosition()
    
    if data.persistent then
        data.duration = 0
    else
        data.duration = data.duration or 3000
    end
    
    -- Native sound every notify unless explicitly muted (exports / net / lib paths).
    -- Repeated identical messages share a single sound during short bursts.
    if data.sound ~= false then
        local s = data.sound
        if s == nil then
            s = true
        end

        local now = GetGameTimer()
        local soundKey = notifyDedupeSoundKey(data)
        local skipSound = data.dedupe ~= false
            and soundKey == notifyDedupeSoundKeyLast
            and (now - notifyDedupeSoundAt) < NOTIFY_DEDUPE_SOUND_MS

        if not skipSound then
            playSound(s, data.type)
            notifyDedupeSoundKeyLast = soundKey
            notifyDedupeSoundAt = now
        end
    end

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

local function hideNotify(id)
    SendNUIMessage({
        action = 'hideNotify',
        data = { id = id }
    })
end

local function clearNotifications()
    SendNUIMessage({
        action = 'clearNotifications'
    })
end

local function notifySuccess(msg, title, sound)
    notify({ type = 'success', description = msg, title = title, sound = sound })
end

local function notifyError(msg, title, sound)
    notify({ type = 'error', description = msg, title = title, sound = sound })
end

local function notifyWarning(msg, title, sound)
    notify({ type = 'warning', description = msg, title = title, sound = sound })
end

local function notifyInfo(msg, title, sound)
    notify({ type = 'info', description = msg, title = title, sound = sound })
end

local activeProgress = nil

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

local function progress(data)
    if activeProgress then
        return false
    end
    
    activeProgress = data
    local completed = true
    local startTime = GetGameTimer()
    local duration = data.duration
    local ped = cache and cache.ped or nil
    if type(ped) ~= 'number' or ped <= 0 then
        ped = PlayerPedId()
    end
    
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
    
    local propEntity = nil
    if data.prop then
        requestModel(data.prop.model)
        local coords = GetEntityCoords(ped)
        propEntity = CreateObject(joaat(data.prop.model), coords.x, coords.y, coords.z, true, true, true)
        local bone = data.prop.bone or 60309
        local pos = data.prop.pos or vector3(0.0, 0.0, 0.0)
        local rot = data.prop.rot or vector3(0.0, 0.0, 0.0)
        AttachEntityToEntity(propEntity, ped, GetPedBoneIndex(ped, bone), 
            pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 0, true)
        SetModelAsNoLongerNeeded(joaat(data.prop.model))
    end

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
    
    while activeProgress do
        local elapsed = GetGameTimer() - startTime
        
        if elapsed >= duration then
            break
        end
        
        if data.canCancel and IsControlJustPressed(0, 177) then
            completed = false
            break
        end
        
        if not data.useWhileDead and IsEntityDead(ped) then
            completed = false
            break
        end
        
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
    
    activeProgress = nil
    
    SendNUIMessage({ action = 'progressEnd' })
    
    if data.anim then
        if data.anim.dict then
            StopAnimTask(ped, data.anim.dict, data.anim.clip, 1.0)
            RemoveAnimDict(data.anim.dict)
        elseif data.anim.scenario then
            ClearPedTasks(ped)
        end
    end
    
    if propEntity and DoesEntityExist(propEntity) then
        DeleteEntity(propEntity)
    end
    
    return completed
end

local function cancelProgress()
    if activeProgress then
        activeProgress = nil
    end
end

local function isProgressActive()
    return activeProgress ~= nil
end

local alertPromise = nil

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

    SetNuiFocus(true, true)
    local result = Citizen.Await(alertPromise)
    SetNuiFocus(false, false)
    alertPromise = nil
    return result
end

RegisterNUICallback('alertDialogResult', function(data, cb)
    SetNuiFocus(false, false)

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

RegisterNetEvent('cortex-lib:notify', function(data)
    notify(data)
end)

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

exports('Notify', function(notifyType, message, duration)
    notify({
        type = notifyType or 'info',
        description = message or '',
        duration = duration or 3000
    })
end)

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
