---@alias NotifyPosition 'top' | 'top-right' | 'top-left' | 'bottom' | 'bottom-right' | 'bottom-left'
---@alias NotifyType 'info' | 'inform' | 'success' | 'warning' | 'error'

local CURRENT_RESOURCE = GetCurrentResourceName()
local MAX_PROGRESS_DURATION = 600000
local MAX_DIALOG_TIMEOUT = 600000
local DEFAULT_DIALOG_TIMEOUT = 120000
local MAX_CONTEXT_FIELDS = 32
local MAX_TRACKED_NOTIFICATIONS = 128
local NOTIFY_SOUND_MIN_INTERVAL_MS = 280
local NOTIFY_DEDUPE_SOUND_MS = 400

local VALID_NOTIFY_TYPES = { info = true, inform = true, success = true, warning = true, error = true }
local VALID_POSITIONS = {
    top = true, ['top-right'] = true, ['top-left'] = true,
    bottom = true, ['bottom-right'] = true, ['bottom-left'] = true,
}
local VALID_PROGRESS_POSITIONS = { bottom = true, top = true, center = true, middle = true }
local VALID_PROGRESS_STYLES = { bar = true, circle = true }
local VALID_TEXT_POSITIONS = {
    ['top-center'] = true, ['top-left'] = true, ['top-right'] = true,
    ['bottom-center'] = true, ['bottom-left'] = true, ['bottom-right'] = true,
}

local SoundPresets = {
    success = { name = 'MEDAL_UP', set = 'HUD_MINI_GAME_SOUNDSET' },
    error = { name = 'ERROR', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    warning = { name = 'WARNING', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    info = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    inform = { name = 'NAV_UP_DOWN', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
}

local lastNotifySoundGameMs = nil
local notifyDedupeSoundKeyLast = nil
local notifyDedupeSoundAt = nil
local activeProgress = nil
local alertSession = nil
local contextSession = nil
local textUiOwner = nil
local notificationOwners = {}
local notificationSequence = 0
local fallbackGeneration = 0

local function getInvokingOwner()
    local owner = GetInvokingResource and GetInvokingResource() or nil
    return owner or CURRENT_RESOURCE
end

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function boundedString(value, maxLength, allowEmpty)
    return type(value) == 'string'
        and (allowEmpty or value ~= '')
        and #value <= maxLength
        and not value:find('\0', 1, true)
end

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    return ok and type(text) == 'string' and text or '<unprintable error>'
end

local function normalizeScalarText(value, maxLength, allowEmpty)
    local valueType = type(value)
    if valueType ~= 'string' and valueType ~= 'number' and valueType ~= 'boolean' then return nil end
    if valueType == 'number' and not isFiniteNumber(value) then return nil end
    local ok, text = pcall(tostring, value)
    if not ok or not boundedString(text, maxLength, allowEmpty) then return nil end
    return text
end

local function safeObjectKey(value, maxLength)
    return boundedString(value, maxLength, false)
        and not value:find('%c')
        and value ~= '__proto__'
        and value ~= 'prototype'
        and value ~= 'constructor'
end

local function safeColor(value)
    if not boundedString(value, 96, false) then return false end
    local hex = value:match('^#([%x]+)$')
    if hex and (#hex == 3 or #hex == 4 or #hex == 6 or #hex == 8) then return true end
    return value:match('^var%(%-%-[%w%-]+%)$') ~= nil
end

local function safeBorder(value)
    if not boundedString(value, 128, false) then return false end
    local width, borderStyle, color = value:match('^(%d+%.?%d*)px%s+(%a+)%s+(.+)$')
    local validWidth = width and (width:match('^[0-3]$') or width:match('^[0-3]%.%d+$')
        or width == '4' or width:match('^4%.0+$'))
    borderStyle = borderStyle and borderStyle:lower() or nil
    return validWidth ~= nil
        and (borderStyle == 'solid' or borderStyle == 'dashed')
        and safeColor(color)
end

local function normalizeStyle(style)
    if style == nil then return nil end
    if type(style) ~= 'table' then return false end
    local normalized = {}
    for _, key in ipairs({ 'backgroundColor', 'borderColor', 'color' }) do
        local value = style[key]
        if value ~= nil then
            if not safeColor(value) then return false end
            normalized[key] = value
        end
    end
    if style.border ~= nil then
        if not safeBorder(style.border) then return false end
        normalized.border = style.border
    end
    return normalized
end

local function elapsedSince(now, startedAt)
    if not isFiniteNumber(now) or not isFiniteNumber(startedAt) then return math.huge end
    local elapsed = now - startedAt
    return elapsed < 0 and elapsed + 4294967296 or elapsed
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

local function getSettingValue(key)
    local getter = rawget(lib, 'getSetting')
    if type(getter) ~= 'function' then return nil end
    return getter(key)
end

local function isSoundEnabled()
    local setting = getSettingValue('notifySound')
    return setting == nil or setting == true
end

local function resolveUserDefaultSound()
    local getCatalog = rawget(lib, 'getNotifySoundCatalog')
    if type(getCatalog) ~= 'function' then return nil end

    local presetId = getSettingValue('notifySoundPreset')
    if not boundedString(presetId, 128, false) then return nil end

    for _, entry in ipairs(getCatalog()) do
        if entry.value == presetId then return { name = entry.name, set = entry.set } end
    end
    return nil
end

local function getDefaultPosition()
    local position = getSettingValue('notifyPosition')
    return VALID_POSITIONS[position] and position or 'top-right'
end

local function validSound(sound)
    return type(sound) == 'table'
        and boundedString(sound.name, 128, false)
        and boundedString(sound.set, 128, false)
        and sound.name:match('^[%w_%-]+$')
        and sound.set:match('^[%w_%-]+$')
end

local function playSound(sound, notifyType)
    if not isSoundEnabled() then return end

    local soundData
    if sound == true then
        soundData = resolveUserDefaultSound() or SoundPresets[notifyType] or SoundPresets.info
    elseif validSound(sound) then
        soundData = sound
    else
        return
    end

    local now = GetGameTimer()
    if lastNotifySoundGameMs and elapsedSince(now, lastNotifySoundGameMs) < NOTIFY_SOUND_MIN_INTERVAL_MS then return end
    lastNotifySoundGameMs = now

    local soundId = GetSoundId()
    PlaySoundFrontend(soundId, soundData.name, soundData.set, true)
    ReleaseSoundId(soundId)
end

local function notifyDedupeSoundKey(data)
    return (data.owner or '') .. '\0' .. data.type .. '\0' .. data.title .. '\0' .. data.description
end

local function normalizeNotify(data)
    if type(data) == 'string' then data = { description = data } end
    if type(data) ~= 'table' then return nil end

    local notifyType = data.type or 'info'
    local position = data.position or getDefaultPosition()
    local title = data.title == nil and '' or normalizeScalarText(data.title, 128, true)
    local description = data.description == nil and '' or normalizeScalarText(data.description, 2048, true)
    local duration = data.persistent == true and 0 or (data.duration == nil and 3000 or data.duration)

    if not VALID_NOTIFY_TYPES[notifyType]
        or not VALID_POSITIONS[position]
        or title == nil
        or description == nil
        or not isFiniteNumber(duration)
        or duration < 0 or duration > MAX_PROGRESS_DURATION
        or (data.id ~= nil and not boundedString(data.id, 128, false))
        or (data.showDuration ~= nil and type(data.showDuration) ~= 'boolean')
        or (data.persistent ~= nil and type(data.persistent) ~= 'boolean')
    then
        return nil
    end

    return {
        id = data.id,
        explicitId = data.id ~= nil,
        title = title,
        description = description,
        duration = math.floor(duration),
        position = position,
        type = notifyType,
        showDuration = data.showDuration ~= false,
        persistent = data.persistent == true or duration == 0,
        plain = data.plain == true,
        hideIcon = data.hideIcon == true or data.icon == false,
        dedupe = data.dedupe ~= false,
        sound = data.sound,
    }
end

local function nextNotificationId()
    notificationSequence = notificationSequence + 1
    return ('cortex-notify-%d'):format(notificationSequence)
end

local function getOwnerNotifications(owner)
    local entries = notificationOwners[owner]
    if not entries then entries = {}; notificationOwners[owner] = entries end
    return entries
end

local function removeOwnerNotifications(owner, sendHide)
    local entries = notificationOwners[owner]
    if not entries then return 0 end
    local removed = 0
    for _ in next, entries do removed = removed + 1 end
    if sendHide then SendNUIMessage({ action = 'clearNotifications', data = { owner = owner } }) end
    notificationOwners[owner] = nil
    return removed
end

local function notify(data)
    local normalized = normalizeNotify(data)
    if not normalized then return nil end

    local owner = getInvokingOwner()
    if not boundedString(owner, 96, false) then owner = CURRENT_RESOURCE end
    local entries = getOwnerNotifications(owner)
    normalized.owner = owner
    local publicId = normalized.id
    local entryKey = publicId and ('id:' .. publicId)
        or (normalized.dedupe and ('dedupe:' .. notifyDedupeSoundKey(normalized)) or nil)
    local entry = entryKey and entries[entryKey] or nil
    if not entry then
        local count = 0
        for _ in next, entries do count = count + 1 end
        if count >= MAX_TRACKED_NOTIFICATIONS then return false, 'capacity_exceeded' end
        local internalId = nextNotificationId()
        entryKey = entryKey or ('anon:' .. internalId)
        entry = { internalId = internalId, version = 0 }
        entries[entryKey] = entry
    end
    entry.version = entry.version + 1
    local version = entry.version
    normalized.id = entry.internalId

    if normalized.sound ~= false then
        local sound = normalized.sound == nil and true or normalized.sound
        local now = GetGameTimer()
        local key = notifyDedupeSoundKey(normalized)
        local skip = normalized.dedupe and key == notifyDedupeSoundKeyLast
            and notifyDedupeSoundAt ~= nil
            and elapsedSince(now, notifyDedupeSoundAt) < NOTIFY_DEDUPE_SOUND_MS
        if not skip then
            playSound(sound, normalized.type)
            notifyDedupeSoundKeyLast = key
            notifyDedupeSoundAt = now
        end
    end

    normalized.sound = nil
    SendNUIMessage({ action = 'notify', data = normalized })
    if normalized.duration > 0 then
        SetTimeout(normalized.duration + 500, function()
            if notificationOwners[owner] == entries and entries[entryKey] == entry and entry.version == version then
                entries[entryKey] = nil
                if next(entries) == nil then notificationOwners[owner] = nil end
            end
        end)
    end
    return publicId
end

local function hideNotify(id)
    if not boundedString(id, 128, false) then return false end
    local owner = getInvokingOwner()
    local entries = notificationOwners[owner]
    local key = 'id:' .. id
    local entry = entries and entries[key] or nil
    if not entry then return false end
    entries[key] = nil
    if next(entries) == nil then notificationOwners[owner] = nil end
    SendNUIMessage({ action = 'hideNotify', data = { id = entry.internalId } })
    return true
end

local function clearNotifications()
    local owner = getInvokingOwner()
    if owner == CURRENT_RESOURCE then
        notificationOwners = {}
        SendNUIMessage({ action = 'clearNotifications', data = { all = true } })
        return true
    end
    removeOwnerNotifications(owner, true)
    return true
end

local function notifySuccess(msg, title, sound) notify({ type = 'success', description = msg, title = title, sound = sound }) end
local function notifyError(msg, title, sound) notify({ type = 'error', description = msg, title = title, sound = sound }) end
local function notifyWarning(msg, title, sound) notify({ type = 'warning', description = msg, title = title, sound = sound }) end
local function notifyInfo(msg, title, sound) notify({ type = 'info', description = msg, title = title, sound = sound }) end

local function normalizeTimeout(timeout, defaultValue, maxValue)
    timeout = timeout == nil and defaultValue or timeout
    if not isFiniteNumber(timeout) or timeout < 0 or timeout > maxValue then return nil end
    return math.floor(timeout)
end

local function requestAnimDict(dict, timeout)
    if not boundedString(dict, 128, false) then return false end
    timeout = normalizeTimeout(timeout, 5000, 30000)
    if not timeout then return false end
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    local start = GetGameTimer()
    while not HasAnimDictLoaded(dict) do
        if elapsedSince(GetGameTimer(), start) >= timeout then return false end
        Wait(0)
    end
    return true
end

local function normalizeModel(model)
    if type(model) == 'string' then
        if not boundedString(model, 128, false) then return nil end
        return joaat(model)
    end
    if not isFiniteNumber(model) then return nil end
    return math.tointeger(model)
end

local function requestModel(model, timeout)
    model = normalizeModel(model)
    timeout = normalizeTimeout(timeout, 5000, 30000)
    if not model or not timeout then return false end
    if HasModelLoaded(model) then return true end

    RequestModel(model)
    local start = GetGameTimer()
    while not HasModelLoaded(model) do
        if elapsedSince(GetGameTimer(), start) >= timeout then return false end
        Wait(0)
    end
    return true
end

local function normalizeVector(value)
    value = value or { x = 0.0, y = 0.0, z = 0.0 }
    local ok, x, y, z = pcall(function() return value.x, value.y, value.z end)
    if not ok or not isFiniteNumber(x) or not isFiniteNumber(y) or not isFiniteNumber(z)
        or math.abs(x) > 10 or math.abs(y) > 10 or math.abs(z) > 10
    then
        return nil
    end
    return { x = x, y = y, z = z }
end

local function normalizeProgress(data)
    if type(data) ~= 'table' then return nil end
    local duration = normalizeTimeout(data.duration, nil, MAX_PROGRESS_DURATION)
    if not duration or duration < 1 then return nil end

    local label = data.label == nil and '' or normalizeScalarText(data.label, 256, true)
    local position = data.position or 'bottom'
    local style = data.style or 'bar'
    if label == nil
        or not VALID_PROGRESS_POSITIONS[position]
        or not VALID_PROGRESS_STYLES[style]
        or (data.canCancel ~= nil and type(data.canCancel) ~= 'boolean')
        or (data.useWhileDead ~= nil and type(data.useWhileDead) ~= 'boolean')
    then
        return nil
    end

    local normalized = {
        duration = duration,
        label = label,
        position = position,
        style = style,
        canCancel = data.canCancel == true,
        useWhileDead = data.useWhileDead == true,
        disable = type(data.disable) == 'table' and {
            move = data.disable.move == true,
            car = data.disable.car == true,
            combat = data.disable.combat == true,
            mouse = data.disable.mouse == true,
        } or nil,
    }

    if data.anim ~= nil then
        if type(data.anim) ~= 'table' then return nil end
        if data.anim.dict ~= nil then
            if not boundedString(data.anim.dict, 128, false) or not boundedString(data.anim.clip, 128, false) then return nil end
            local blendIn = data.anim.blendIn == nil and 3.0 or data.anim.blendIn
            local blendOut = data.anim.blendOut == nil and 1.0 or data.anim.blendOut
            local flag = data.anim.flag == nil and 49
                or (type(data.anim.flag) == 'number' and math.tointeger(data.anim.flag) or nil)
            if not isFiniteNumber(blendIn) or blendIn < -100 or blendIn > 100
                or not isFiniteNumber(blendOut) or blendOut < -100 or blendOut > 100
                or not flag or flag < 0 or flag > 2147483647
            then
                return nil
            end
            normalized.anim = {
                dict = data.anim.dict,
                clip = data.anim.clip,
                blendIn = blendIn,
                blendOut = blendOut,
                flag = flag,
            }
        elseif data.anim.scenario ~= nil then
            if not boundedString(data.anim.scenario, 128, false) then return nil end
            normalized.anim = { scenario = data.anim.scenario }
        else
            return nil
        end
    end

    if data.prop ~= nil then
        if type(data.prop) ~= 'table' then return nil end
        local model = normalizeModel(data.prop.model)
        local pos = normalizeVector(data.prop.pos)
        local rot = normalizeVector(data.prop.rot)
        local bone = data.prop.bone == nil and 60309
            or (type(data.prop.bone) == 'number' and math.tointeger(data.prop.bone) or nil)
        if not model or not pos or not rot or not bone or bone < 0 or bone > 65535 then return nil end
        normalized.prop = { model = model, bone = bone, pos = pos, rot = rot }
    end
    return normalized
end

local function cleanupProgress(entry)
    if not entry or entry.cleaned then return false end
    entry.cleaned = true
    entry.cancelled = true
    if activeProgress == entry then activeProgress = nil end

    if entry.sent then
        entry.sent = false
        pcall(SendNUIMessage, { action = 'progressEnd' })
    end

    local ped = entry.ped
    local pedExists = false
    if ped then
        local existsOk, exists = pcall(DoesEntityExist, ped)
        pedExists = existsOk and exists == true
    end
    if pedExists and entry.anim then
        if entry.anim.dict then
            pcall(StopAnimTask, ped, entry.anim.dict, entry.anim.clip, 1.0)
        elseif entry.anim.scenario then
            pcall(ClearPedTasks, ped)
        end
    end
    if entry.animDictRequested and entry.anim and entry.anim.dict then
        pcall(RemoveAnimDict, entry.anim.dict)
        entry.animDictRequested = false
    end
    if entry.propEntity then
        local existsOk, exists = pcall(DoesEntityExist, entry.propEntity)
        if existsOk and exists == true then
            -- Attached progress props (hammer, phone) must be detached first.
            -- DeleteEntity alone on a hand-attached object silently fails and
            -- leaves the prop stuck to the ped.
            pcall(DetachEntity, entry.propEntity, false, true)
            pcall(DeleteEntity, entry.propEntity)
            local stillOk, still = pcall(DoesEntityExist, entry.propEntity)
            if stillOk and still == true then pcall(DeleteObject, entry.propEntity) end
        end
        entry.propEntity = nil
    end
    if entry.propModel then
        pcall(SetModelAsNoLongerNeeded, entry.propModel)
        entry.propModel = nil
    end
    return true
end

local function resolveCurrentPed()
    local cachedPed = lib.cache and lib.cache.ped or nil
    if type(cachedPed) == 'number' and cachedPed > 0 and DoesEntityExist(cachedPed) then return cachedPed end

    local ped = PlayerPedId()
    if type(ped) == 'number' and ped > 0 and DoesEntityExist(ped) then return ped end
    return nil
end

local function progress(data)
    if activeProgress then return false end
    local normalized = normalizeProgress(data)
    if not normalized then return false end

    local entry = { owner = getInvokingOwner(), cancelled = false, sent = false, anim = normalized.anim }
    activeProgress = entry
    local completed = false
    local function trace(value)
        if debug and type(debug.traceback) == 'function' then
            local traceOk, traced = pcall(debug.traceback, value, 2)
            if traceOk then return safeErrorText(traced) end
        end
        return safeErrorText(value)
    end
    local ok, err = xpcall(function()
        local ped = resolveCurrentPed()
        if not ped then return end
        entry.ped = ped

        if normalized.anim and normalized.anim.dict then
            if not requestAnimDict(normalized.anim.dict, 5000) then return end
            entry.animDictRequested = true
            ped = resolveCurrentPed()
            if not ped then return end
            entry.ped = ped
            TaskPlayAnim(ped, normalized.anim.dict, normalized.anim.clip, normalized.anim.blendIn,
                normalized.anim.blendOut, -1, normalized.anim.flag, 0, false, false, false)
        elseif normalized.anim and normalized.anim.scenario then
            ped = resolveCurrentPed()
            if not ped then return end
            entry.ped = ped
            TaskStartScenarioInPlace(ped, normalized.anim.scenario, 0, true)
        end

        if normalized.prop then
            if not requestModel(normalized.prop.model, 5000) then return end
            ped = resolveCurrentPed()
            if not ped then return end
            entry.ped = ped
            local coords = GetEntityCoords(ped)
            entry.propModel = normalized.prop.model
            entry.propEntity = CreateObject(normalized.prop.model, coords.x, coords.y, coords.z, false, false, false)
            if not entry.propEntity or entry.propEntity == 0 or not DoesEntityExist(entry.propEntity) then return end
            AttachEntityToEntity(entry.propEntity, ped, GetPedBoneIndex(ped, normalized.prop.bone),
                normalized.prop.pos.x, normalized.prop.pos.y, normalized.prop.pos.z,
                normalized.prop.rot.x, normalized.prop.rot.y, normalized.prop.rot.z,
                true, true, false, true, 0, true)
        end

        ped = resolveCurrentPed()
        if not ped or ped ~= entry.ped then return end

        SendNUIMessage({
            action = 'progressStart',
            data = {
                duration = normalized.duration,
                label = normalized.label,
                position = normalized.position,
                style = normalized.style,
                canCancel = normalized.canCancel,
            }
        })
        entry.sent = true
        local startTime = GetGameTimer()

        while not entry.cancelled do
            if elapsedSince(GetGameTimer(), startTime) >= normalized.duration then completed = true; break end
            if normalized.canCancel and IsControlJustPressed(0, 177) then break end

            local currentPed = PlayerPedId()
            if currentPed ~= entry.ped or not DoesEntityExist(currentPed)
                or (not normalized.useWhileDead and IsEntityDead(currentPed))
            then
                break
            end

            local disable = normalized.disable
            if disable then
                if disable.move then
                    DisableControlAction(0, 30, true); DisableControlAction(0, 31, true)
                    DisableControlAction(0, 21, true); DisableControlAction(0, 22, true)
                end
                if disable.car then
                    DisableControlAction(0, 63, true); DisableControlAction(0, 64, true)
                    DisableControlAction(0, 71, true); DisableControlAction(0, 72, true)
                end
                if disable.combat then
                    DisablePlayerFiring(PlayerId(), true)
                    DisableControlAction(0, 24, true); DisableControlAction(0, 25, true)
                end
                if disable.mouse then DisableControlAction(0, 1, true); DisableControlAction(0, 2, true) end
            end
            Wait(0)
        end
    end, trace)

    cleanupProgress(entry)
    if not ok then
        pcall(print, ('^1[cortex-lib]^7 progress failed: %s'):format(safeErrorText(err)))
        return false
    end
    return completed
end

local function cancelProgress()
    if activeProgress and (activeProgress.owner == getInvokingOwner() or getInvokingOwner() == CURRENT_RESOURCE) then
        activeProgress.cancelled = true
    end
end

local function isProgressActive() return activeProgress ~= nil end

local function acquireModal(surface, owner)
    if type(lib._acquireModal) == 'function' then return lib._acquireModal(surface, owner) end
    fallbackGeneration = fallbackGeneration + 1
    return fallbackGeneration
end

local function focusModal(surface, generation)
    if type(lib._focusModal) == 'function' then return lib._focusModal(surface, generation, false) end
    SetNuiFocus(true, true)
    return true
end

local function matchesModal(surface, generation, data)
    if type(lib._matchesModal) == 'function' then
        return type(data) == 'table' and lib._matchesModal(surface, generation, data.session)
    end
    return type(data) == 'table' and (data.session == nil or data.session == generation)
end

local function releaseModal(surface, generation)
    if type(lib._releaseModal) == 'function' then return lib._releaseModal(surface, generation) end
    SetNuiFocus(false, false)
    return true
end

local function settleAlert(entry, result)
    if not entry or entry.settled then return false end
    entry.settled = true
    if alertSession == entry then alertSession = nil end
    releaseModal('alert', entry.generation)
    SendNUIMessage({ action = 'alertDialogClose', data = { session = entry.generation } })
    entry.promise:resolve(result == 'confirm' and 'confirm' or 'cancel')
    return true
end

local function settleContext(entry, result)
    if not entry or entry.settled then return false end
    entry.settled = true
    if contextSession == entry then contextSession = nil end
    releaseModal('context', entry.generation)
    SendNUIMessage({ action = 'contextMenuClose', data = { session = entry.generation } })
    entry.promise:resolve(result)
    return true
end

local function normalizeDialogText(data)
    if type(data) ~= 'table' then return nil end
    local header = data.header == nil and '' or normalizeScalarText(data.header, 128, true)
    local content
    if type(data.content) == 'table' then
        if not isDenseArray(data.content, 32) then return nil end
        local parts = {}
        for index = 1, #data.content do
            local part = normalizeScalarText(data.content[index], 512, true)
            if part == nil then return nil end
            parts[index] = part
        end
        content = parts
    else
        content = data.content == nil and '' or normalizeScalarText(data.content, 4096, true)
        if content == nil then return nil end
    end

    local labels = type(data.labels) == 'table' and data.labels or {}
    local confirm = labels.confirm or 'CONFIRM'
    local cancel = labels.cancel or 'CANCEL'
    if header == nil
        or not boundedString(confirm, 64, false)
        or not boundedString(cancel, 64, false)
    then
        return nil
    end

    local timeout = normalizeTimeout(data.timeout, DEFAULT_DIALOG_TIMEOUT, MAX_DIALOG_TIMEOUT)
    if not timeout or timeout < 1000 then return nil end
    local style = normalizeStyle(data.style)
    if style == false then return nil end
    return {
        header = header,
        content = content,
        centered = data.centered == true,
        cancel = data.cancel ~= false,
        labels = { confirm = confirm, cancel = cancel },
        timeout = timeout,
        style = style,
    }
end

local function alertDialog(data)
    if alertSession then return 'cancel' end
    local normalized = normalizeDialogText(data or {})
    if not normalized then return 'cancel' end

    local owner = getInvokingOwner()
    local generation = acquireModal('alert', owner)
    if not generation then return 'cancel' end
    local entry = {
        owner = owner, generation = generation, promise = promise.new(),
        settled = false, cancel = normalized.cancel,
    }
    alertSession = entry

    SendNUIMessage({ action = 'alertDialog', data = {
        header = normalized.header, content = normalized.content, centered = normalized.centered,
        cancel = normalized.cancel, labels = normalized.labels, style = normalized.style, session = generation,
    } })
    if not focusModal('alert', generation) then settleAlert(entry, 'cancel'); return 'cancel' end

    SetTimeout(normalized.timeout, function()
        if alertSession == entry then settleAlert(entry, 'cancel') end
    end)
    local result = Citizen.Await(entry.promise)
    return result == 'confirm' and 'confirm' or 'cancel'
end

RegisterNUICallback('alertDialogResult', function(data, cb)
    local entry = alertSession
    if not entry or not matchesModal('alert', entry.generation, data) then
        cb({ ok = false, error = 'stale_session' }); return
    end
    if data.result ~= 'confirm' and data.result ~= 'cancel' then
        cb({ ok = false, error = 'invalid_result' }); return
    end
    if data.result == 'cancel' and entry.cancel == false then
        cb({ ok = false, error = 'cancel_not_allowed' }); return
    end
    settleAlert(entry, data.result)
    cb({ ok = true })
end)

local function showTextUI(text, opts)
    if opts ~= nil and type(opts) ~= 'table' then return false end
    opts = opts or {}
    if not boundedString(text, 512, false) then return false end
    local position = opts.position or 'bottom-center'
    if not VALID_TEXT_POSITIONS[position] then return false end
    if opts.icon ~= nil and not boundedString(opts.icon, 32, true) then return false end

    local style = normalizeStyle(opts.style)
    if style == false then return false end

    local owner = getInvokingOwner()
    if textUiOwner and textUiOwner ~= owner and owner ~= CURRENT_RESOURCE then return false, 'not_owner' end
    textUiOwner = owner
    SendNUIMessage({ action = 'textUIShow', data = {
        text = text, position = position,
        icon = opts.icon,
        style = style,
        backdrop = opts.backdrop == true,
    } })
    return true
end

local function hideTextUI()
    if textUiOwner and textUiOwner ~= getInvokingOwner() and getInvokingOwner() ~= CURRENT_RESOURCE then return false end
    textUiOwner = nil
    SendNUIMessage({ action = 'textUIHide' })
    return true
end

local VALID_CONTEXT_TYPES = { checkbox = true, select = true, input = true, text = true }
local VALID_CONTEXT_INPUT_TYPES = {
    text = true, number = true, email = true, password = true, search = true, url = true,
}

local function normalizeContextOption(option)
    if type(option) == 'table' then
        local value = option.value
        local label = normalizeScalarText(option.label ~= nil and option.label or value, 128, true)
        if (type(value) ~= 'string' and type(value) ~= 'number' and type(value) ~= 'boolean')
            or (type(value) == 'number' and not isFiniteNumber(value))
            or (type(value) == 'string' and not boundedString(value, 512, true))
            or label == nil
        then
            return nil
        end
        return { value = value, label = label }
    end
    if type(option) == 'number' then return isFiniteNumber(option) and option or nil end
    if type(option) == 'string' then return boundedString(option, 512, true) and option or nil end
    if type(option) == 'boolean' then return option end
    return nil
end

local function contextValueAllowed(field, value)
    if field.type == 'checkbox' then return type(value) == 'boolean' end
    if field.type == 'select' then
        for index = 1, #field.options do
            local option = field.options[index]
            local optionValue
            if type(option) == 'table' then optionValue = option.value else optionValue = option end
            if type(optionValue) == type(value) and optionValue == value then return true end
        end
        return false
    end
    return boundedString(value, 512, true) and (not field.required or value ~= '')
end

local function normalizeContext(data)
    if type(data) ~= 'table' or not boundedString(data.title or '', 128, true) then return nil end
    local fields = data.fields or {}
    if not isDenseArray(fields, MAX_CONTEXT_FIELDS) then return nil end

    local normalizedFields = {}
    local byName = {}
    for index = 1, #fields do
        local field = fields[index]
        local name = type(field) == 'table' and (field.name or field.key) or nil
        local fieldType = type(field) == 'table' and (field.type or 'input') or nil
        if type(field) ~= 'table'
            or not safeObjectKey(name, 96)
            or byName[name]
            or not VALID_CONTEXT_TYPES[fieldType]
            or not boundedString(field.label or name, 128, false)
            or (field.description ~= nil and not boundedString(field.description, 512, true))
            or (field.placeholder ~= nil and not boundedString(field.placeholder, 256, true))
            or (field.icon ~= nil and not boundedString(field.icon, 32, true))
            or (field.required ~= nil and type(field.required) ~= 'boolean')
            or (field.inputType ~= nil and not VALID_CONTEXT_INPUT_TYPES[field.inputType])
            or (field.options ~= nil and not isDenseArray(field.options, 64))
        then
            return nil
        end

        local options = {}
        for optionIndex = 1, #(field.options or {}) do
            local option = normalizeContextOption(field.options[optionIndex])
            if option == nil then return nil end
            options[optionIndex] = option
        end
        local normalized = {
            name = name,
            type = fieldType,
            label = field.label or name,
            description = field.description,
            placeholder = field.placeholder,
            inputType = field.inputType,
            required = field.required == true,
            icon = field.icon,
            options = options,
        }
        normalizedFields[index] = normalized
        byName[name] = normalized
    end

    local values = {}
    local valueCount = 0
    for key, value in next, type(data.values) == 'table' and data.values or {} do
        valueCount = valueCount + 1
        local field = byName[key]
        if valueCount > MAX_CONTEXT_FIELDS or not field or not contextValueAllowed(field, value) then return nil end
        values[key] = value
    end

    local labels = type(data.labels) == 'table' and data.labels or {}
    local confirm = labels.confirm or 'CONFIRM'
    local cancel = labels.cancel or 'CANCEL'
    local timeout = normalizeTimeout(data.timeout, DEFAULT_DIALOG_TIMEOUT, MAX_DIALOG_TIMEOUT)
    if not boundedString(confirm, 64, false) or not boundedString(cancel, 64, false) or not timeout or timeout < 1000 then
        return nil
    end

    return { title = data.title or '', fields = normalizedFields, values = values,
        labels = { confirm = confirm, cancel = cancel }, timeout = timeout }
end

local function contextMenu(data)
    if contextSession then return nil end
    local normalized = normalizeContext(data or {})
    if not normalized then return nil end

    local owner = getInvokingOwner()
    local generation = acquireModal('context', owner)
    if not generation then return nil end
    local entry = {
        owner = owner, generation = generation, promise = promise.new(),
        fields = normalized.fields, settled = false,
    }
    contextSession = entry

    SendNUIMessage({ action = 'contextMenu', data = {
        title = normalized.title, fields = normalized.fields, values = normalized.values,
        labels = normalized.labels, session = generation,
    } })
    if not focusModal('context', generation) then settleContext(entry, nil); return nil end

    SetTimeout(normalized.timeout, function()
        if contextSession == entry then settleContext(entry, nil) end
    end)
    local result = Citizen.Await(entry.promise)
    return result
end

local function hideContextMenu()
    local entry = contextSession
    if not entry or (entry.owner ~= getInvokingOwner() and getInvokingOwner() ~= CURRENT_RESOURCE) then return false end
    return settleContext(entry, nil)
end

local function validateContextResult(entry, values)
    if type(values) ~= 'table' then return nil end
    local result = {}
    local count = 0
    for key, value in next, values do
        count = count + 1
        if count > MAX_CONTEXT_FIELDS then return nil end

        local field
        for index = 1, #entry.fields do
            if entry.fields[index].name == key then field = entry.fields[index]; break end
        end
        if not field then return nil end
        if not contextValueAllowed(field, value) then return nil end
        result[key] = value
    end

    for index = 1, #entry.fields do
        local field = entry.fields[index]
        if field.required and result[field.name] == nil then return nil end
    end
    return result
end

RegisterNUICallback('contextMenuResult', function(data, cb)
    local entry = contextSession
    if not entry or not matchesModal('context', entry.generation, data) then
        cb({ ok = false, error = 'stale_session' }); return
    end

    if data.result == 'confirm' then
        local values = validateContextResult(entry, data.values)
        if not values then cb({ ok = false, error = 'invalid_values' }); return end
        settleContext(entry, values)
    elseif data.result == 'cancel' then
        settleContext(entry, nil)
    else
        cb({ ok = false, error = 'invalid_result' }); return
    end
    cb({ ok = true })
end)

local function closeAlertForModal(generation)
    local entry = alertSession
    if not entry or entry.generation ~= generation then return end
    settleAlert(entry, 'cancel')
end

local function closeContextForModal(generation)
    local entry = contextSession
    if not entry or entry.generation ~= generation then return end
    settleContext(entry, nil)
end

local pendingModalSurfaces = rawget(lib, '_pendingModalSurfaces') or {}
pendingModalSurfaces.alert = closeAlertForModal
pendingModalSurfaces.context = closeContextForModal
rawset(lib, '_pendingModalSurfaces', pendingModalSurfaces)
if type(lib._registerModalSurface) == 'function' then
    lib._registerModalSurface('alert', closeAlertForModal)
    lib._registerModalSurface('context', closeContextForModal)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == CURRENT_RESOURCE then
        notificationOwners = {}
        SendNUIMessage({ action = 'clearNotifications', data = { all = true } })
    else
        removeOwnerNotifications(resourceName, true)
    end
    if activeProgress and (activeProgress.owner == resourceName or resourceName == CURRENT_RESOURCE) then
        cleanupProgress(activeProgress)
    end
    if alertSession and (alertSession.owner == resourceName or resourceName == CURRENT_RESOURCE) then
        settleAlert(alertSession, 'cancel')
    end
    if contextSession and (contextSession.owner == resourceName or resourceName == CURRENT_RESOURCE) then
        settleContext(contextSession, nil)
    end
    if textUiOwner == resourceName or resourceName == CURRENT_RESOURCE then
        textUiOwner = nil
        SendNUIMessage({ action = 'textUIHide' })
    end
end)

RegisterNetEvent('cortex-lib:notify', function(data) notify(data) end)

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
    return notify({ type = notifyType or 'info', description = message or '', duration = duration or 3000 })
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
