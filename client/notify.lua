local SoundPresets = {
    success = { name = 'MEDAL_UP', set = 'HUD_MINI_GAME_SOUNDSET' },
    error = { name = 'ERROR', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    warning = { name = 'WARNING', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    info = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
}

local function isSoundEnabled()
    local setting = lib.getSetting and lib.getSetting('notifySound')
    if setting == nil then
        return true
    end
    return setting
end

local function getDefaultPosition()
    local setting = lib.getSetting and lib.getSetting('notifyPosition')
    return setting or 'top-right'
end

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
    
    local soundId = GetSoundId()
    PlaySoundFrontend(soundId, soundData.name, soundData.set, true)
    ReleaseSoundId(soundId)
end

function lib.notify(data)
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
    
    if data.sound ~= false then
        local s = data.sound
        if s == nil then
            s = true
        end
        playSound(s, data.type)
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

function lib.hideNotify(id)
    SendNUIMessage({
        action = 'hideNotify',
        data = { id = id }
    })
end

function lib.clearNotifications()
    SendNUIMessage({
        action = 'clearNotifications'
    })
end

function lib.notifySuccess(msg, title, sound)
    lib.notify({ type = 'success', description = msg, title = title, sound = sound })
end

function lib.notifyError(msg, title, sound)
    lib.notify({ type = 'error', description = msg, title = title, sound = sound })
end

function lib.notifyWarning(msg, title, sound)
    lib.notify({ type = 'warning', description = msg, title = title, sound = sound })
end

function lib.notifyInfo(msg, title, sound)
    lib.notify({ type = 'info', description = msg, title = title, sound = sound })
end

local activeProgress = nil
local progressPromise = nil

function lib.progress(data)
    if activeProgress then
        return false
    end
    
    activeProgress = data
    local completed = true
    local startTime = GetGameTimer()
    local duration = data.duration
    local ped = (lib.cache and lib.cache.ped) or PlayerPedId()
    
    if data.anim then
        if data.anim.dict then
            lib.requestAnimDict(data.anim.dict)
            TaskPlayAnim(ped, data.anim.dict, data.anim.clip, 
                data.anim.blendIn or 3.0, data.anim.blendOut or 1.0, 
                -1, data.anim.flag or 49, 0, false, false, false)
        elseif data.anim.scenario then
            TaskStartScenarioInPlace(ped, data.anim.scenario, 0, true)
        end
    end
    
    local propEntity = nil
    if data.prop then
        lib.requestModel(data.prop.model)
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

function lib.cancelProgress()
    if activeProgress then
        activeProgress = nil
    end
end

function lib.isProgressActive()
    return activeProgress ~= nil
end

function lib.requestAnimDict(dict, timeout)
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

function lib.requestModel(model, timeout)
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

local alertPromise = nil

function lib.alertDialog(data)
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

function lib.showTextUI(text, opts)
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

function lib.hideTextUI()
    SendNUIMessage({ action = 'textUIHide' })
end

local contextMenuPromise = nil

function lib.contextMenu(data)
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

function lib.hideContextMenu()
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

exports('notify', lib.notify)
exports('hideNotify', lib.hideNotify)
exports('clearNotifications', lib.clearNotifications)
exports('progress', lib.progress)
exports('cancelProgress', lib.cancelProgress)
exports('isProgressActive', lib.isProgressActive)
exports('alertDialog', lib.alertDialog)
exports('contextMenu', lib.contextMenu)
exports('hideContextMenu', lib.hideContextMenu)
exports('showTextUI', lib.showTextUI)
exports('hideTextUI', lib.hideTextUI)

exports('Notify', function(notifyType, message, duration)
    lib.notify({
        type = notifyType or 'info',
        description = message or '',
        duration = duration or 3000
    })
end)

exports('notifySuccess', lib.notifySuccess)
exports('notifyError', lib.notifyError)
exports('notifyWarning', lib.notifyWarning)
exports('notifyInfo', lib.notifyInfo)
exports('requestAnimDict', lib.requestAnimDict)
exports('requestModel', lib.requestModel)

RegisterNetEvent('es_lib:notify', function(data)
    lib.notify(data)
end)

return lib
