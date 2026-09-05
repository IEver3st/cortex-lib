local MAX_NOTIFICATION_DURATION = 600000

local VALID_NOTIFICATION_TYPES = {
    info = true,
    inform = true,
    success = true,
    warning = true,
    error = true,
}

local VALID_NOTIFICATION_POSITIONS = {
    top = true,
    ['top-right'] = true,
    ['top-left'] = true,
    bottom = true,
    ['bottom-right'] = true,
    ['bottom-left'] = true,
}

local function isFiniteNumber(value)
    return type(value) == 'number'
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function isPlayerSource(value)
    return isFiniteNumber(value)
        and value > 0
        and value == math.floor(value)
end

local function boundedString(value, maxLength, allowEmpty)
    return type(value) == 'string'
        and (allowEmpty or value ~= '')
        and #value <= maxLength
        and not value:find('\0', 1, true)
end

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    if not ok or type(text) ~= 'string' then return '<unprintable error>' end
    if #text > 512 then return text:sub(1, 512) .. '...' end
    return text
end

local function normalizeText(value, maxLength)
    if value == nil then
        return ''
    end

    local valueType = type(value)

    if valueType ~= 'string' and valueType ~= 'number' and valueType ~= 'boolean' then
        return nil
    end

    if valueType == 'number' and not isFiniteNumber(value) then
        return nil
    end

    value = tostring(value)
    return boundedString(value, maxLength, true) and value or nil
end

local function normalizeSound(sound)
    if sound == nil or type(sound) == 'boolean' then
        return sound
    end

    if type(sound) ~= 'table' then
        return nil, false
    end

    local name = rawget(sound, 'name')
    local soundSet = rawget(sound, 'set')

    if not boundedString(name, 128, false)
        or not boundedString(soundSet, 128, false)
        or not name:match('^[%w_%-]+$')
        or not soundSet:match('^[%w_%-]+$')
    then
        return nil, false
    end

    return {
        name = name,
        set = soundSet,
    }
end

local function normalizeNotification(data)
    if type(data) == 'string' then
        data = { description = data }
    end

    if type(data) ~= 'table' then
        return nil, 'invalid_notification_data'
    end

    local id = rawget(data, 'id')
    local notificationType = rawget(data, 'type')
    local position = rawget(data, 'position')
    local showDuration = rawget(data, 'showDuration')
    local persistent = rawget(data, 'persistent')
    local plain = rawget(data, 'plain')
    local hideIcon = rawget(data, 'hideIcon')
    local icon = rawget(data, 'icon')
    local dedupe = rawget(data, 'dedupe')
    local title = normalizeText(rawget(data, 'title'), 128)
    local description = normalizeText(rawget(data, 'description'), 2048)
    local duration = rawget(data, 'duration')
    local sound, validSound = normalizeSound(rawget(data, 'sound'))

    notificationType = notificationType == nil and 'info' or notificationType
    duration = persistent == true and 0 or (duration == nil and 3000 or duration)

    if type(notificationType) ~= 'string'
        or not VALID_NOTIFICATION_TYPES[notificationType]
        or (position ~= nil and (type(position) ~= 'string' or not VALID_NOTIFICATION_POSITIONS[position]))
        or title == nil
        or description == nil
        or not isFiniteNumber(duration)
        or duration < 0
        or duration > MAX_NOTIFICATION_DURATION
        or (id ~= nil and not boundedString(id, 128, false))
        or (showDuration ~= nil and type(showDuration) ~= 'boolean')
        or (persistent ~= nil and type(persistent) ~= 'boolean')
        or (plain ~= nil and type(plain) ~= 'boolean')
        or (hideIcon ~= nil and type(hideIcon) ~= 'boolean')
        or (dedupe ~= nil and type(dedupe) ~= 'boolean')
        or validSound == false
    then
        return nil, 'invalid_notification_data'
    end

    return {
        id = id,
        title = title,
        description = description,
        duration = math.floor(duration),
        position = position,
        type = notificationType,
        showDuration = showDuration ~= false,
        persistent = persistent == true or duration == 0,
        plain = plain == true,
        hideIcon = hideIcon == true or icon == false,
        dedupe = dedupe ~= false,
        sound = sound,
    }
end

local function transmitNotification(target, data)
    local normalized, normalizationError = normalizeNotification(data)

    if not normalized then
        return false, normalizationError
    end

    local transmitted, transmitError = pcall(TriggerClientEvent, 'cortex-lib:notify', target, normalized)

    if not transmitted then
        pcall(print, ('^1[cortex-lib] failed to transmit notification: %s^0'):format(safeErrorText(transmitError)))
        return false, 'notification_transmit_error'
    end
end

local function notify(source, data)
    if not isPlayerSource(source) then
        return false, 'invalid_notification_source'
    end

    return transmitNotification(source, data)
end

local function notifyAll(data)
    return transmitNotification(-1, data)
end

exports('notify', notify)
exports('notifyAll', notifyAll)

exports('Notify', function(source, notifyType, message, duration)
    return notify(source, {
        type = notifyType or 'info',
        description = message or '',
        duration = duration or 3000,
    })
end)

lib.notify = notify
lib.notifyAll = notifyAll

return notify
