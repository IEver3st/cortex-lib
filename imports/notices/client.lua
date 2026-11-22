local CURRENT_RESOURCE = GetCurrentResourceName()
local MAX_SENDERS = 64
local MAX_SENDERS_PER_OWNER = 16
local MAX_LOG_ENTRIES = 40
local MAX_PEEK_ENTRIES = 20
local MAX_PEEK_OWNER_HOLDS = 32
local PEEK_TAP_MS = 300
local PEEK_LATCH_MS = 3500
local PEEK_KEY_LIMIT_MS = 60000
local PEEK_OWNER_LIMIT_MS = 600000
local OWNER_HOLD_PREFIX = 'owner:'
local PEEK_WATCH_INTERVAL_MS = 250

local VALID_IMAGE_EXTENSIONS = { png = true, svg = true, webp = true }

local senders = {}
local senderCounts = {}
local noticeLog = {}
local noticeSequence = 0
local peekHolds = {}
local peekHoldCount = 0
local peekOwnerHoldCount = 0
local peekOwnerRefreshedAt = {}
local peekOwnerTimers = {}
local peekActive = false
local peekKeyToken = 0
local peekKeyPressedAt = nil

local function getInvokingOwner()
    local owner = GetInvokingResource and GetInvokingResource() or nil
    return owner or CURRENT_RESOURCE
end

local function boundedString(value, maxLength)
    return type(value) == 'string'
        and value ~= ''
        and #value <= maxLength
        and not value:find('%c')
end

local function elapsedSince(now, startedAt)
    local elapsed = now - startedAt
    return elapsed < 0 and elapsed + 4294967296 or elapsed
end

local function validSenderId(value)
    return boundedString(value, 48) and value:match('^[%w][%w_%-%.:]*$') ~= nil
end

local function validImage(value)
    if not boundedString(value, 160) or value:find('..', 1, true) then return false end
    local resource, path, extension = value:match('^nui://([%w_%-]+)/([%w_%-%./]+)%.(%a+)$')
    return resource ~= nil and path ~= nil and VALID_IMAGE_EXTENSIONS[extension:lower()] == true
end

local function normalizeSender(data)
    if type(data) ~= 'table' then return nil, 'invalid_sender' end
    local label = rawget(data, 'label')
    local color = rawget(data, 'color')
    local icon = rawget(data, 'icon')
    local image = rawget(data, 'image')
    if not boundedString(label, 48) then return nil, 'invalid_sender_label' end
    if color ~= nil and not (type(color) == 'string' and color:match('^#%x%x%x%x%x%x$')) then
        return nil, 'invalid_sender_color'
    end
    if icon ~= nil and not boundedString(icon, 64) then return nil, 'invalid_sender_icon' end
    if image ~= nil and not validImage(image) then return nil, 'invalid_sender_image' end
    return {
        label = label,
        color = color and color:lower() or nil,
        icon = icon,
        image = image,
    }
end

local function copySender(sender, id)
    return {
        id = id or sender.id,
        label = sender.label,
        color = sender.color,
        icon = sender.icon,
        image = sender.image,
    }
end

local function registerSender(id, data)
    if not validSenderId(id) then return false, 'invalid_sender_id' end
    local normalized, reason = normalizeSender(data)
    if not normalized then return false, reason end

    local owner = getInvokingOwner()
    local existing = senders[id]
    if existing and existing.owner ~= owner then return false, 'sender_owned' end
    if not existing then
        local total = 0
        for _ in next, senders do total = total + 1 end
        if total >= MAX_SENDERS then return false, 'capacity_exceeded' end
        local owned = senderCounts[owner] or 0
        if owned >= MAX_SENDERS_PER_OWNER then return false, 'capacity_exceeded' end
        senderCounts[owner] = owned + 1
    end

    normalized.id = id
    normalized.owner = owner
    senders[id] = normalized
    return true
end

local function releaseSender(id)
    local sender = senders[id]
    if not sender then return end
    senders[id] = nil
    local owned = (senderCounts[sender.owner] or 1) - 1
    senderCounts[sender.owner] = owned > 0 and owned or nil
end

local function removeSender(id)
    local sender = type(id) == 'string' and senders[id] or nil
    if not sender or sender.owner ~= getInvokingOwner() then return false end
    releaseSender(id)
    return true
end

local function getSender(id)
    local sender = type(id) == 'string' and senders[id] or nil
    return sender and copySender(sender) or nil
end

local function getSenders()
    local list = {}
    for id, sender in pairs(senders) do list[#list + 1] = copySender(sender, id) end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function resolveSender(value)
    if type(value) == 'string' then
        local sender = senders[value]
        return sender and copySender(sender) or nil
    end
    if type(value) ~= 'table' then return nil end
    local normalized = normalizeSender(value)
    return normalized
end

local function copyLogEntry(entry, now)
    return {
        id = entry.id,
        noticeId = entry.noticeId,
        owner = entry.owner,
        type = entry.type,
        title = entry.title,
        description = entry.description,
        sender = entry.sender and copySender(entry.sender) or nil,
        age = elapsedSince(now, entry.at),
        seen = entry.seen,
        count = entry.count,
        shown = entry.shown,
    }
end

local function isStreamerMode()
    return LocalPlayer.state.cortexStreamerMode == true
end

local function buildPeekEntries()
    local now = GetGameTimer()
    local masked = isStreamerMode()
    local entries = {}
    for index = #noticeLog, math.max(1, #noticeLog - MAX_PEEK_ENTRIES + 1), -1 do
        local entry = copyLogEntry(noticeLog[index], now)
        entry.liveId = noticeLog[index].liveId
        if masked and entry.sender then
            entry.description = nil
            entry.masked = true
        end
        entries[#entries + 1] = entry
    end
    return entries
end

local function pushPeek()
    SendNUIMessage({
        action = 'peek',
        data = { active = peekActive, entries = peekActive and buildPeekEntries() or nil },
    })
end

local function logNotice(notice)
    if type(notice) ~= 'table' then return nil end
    local now = GetGameTimer()
    local entry

    if notice.key then
        for index = #noticeLog, 1, -1 do
            if noticeLog[index].key == notice.key then
                entry = table.remove(noticeLog, index)
                entry.count = entry.count + 1
                break
            end
        end
    end

    if not entry then
        noticeSequence = noticeSequence + 1
        entry = { id = noticeSequence, key = notice.key, count = 1 }
    end

    entry.noticeId = notice.noticeId
    entry.liveId = notice.liveId
    entry.owner = notice.owner
    entry.type = notice.type
    entry.title = notice.title
    entry.description = notice.description
    entry.sender = notice.sender
    entry.shown = notice.shown ~= false
    entry.at = now
    entry.seen = false

    noticeLog[#noticeLog + 1] = entry
    while #noticeLog > MAX_LOG_ENTRIES do table.remove(noticeLog, 1) end

    local public = copyLogEntry(entry, now)
    TriggerEvent('cortex-lib:noticeLogged', public)
    if peekActive then pushPeek() end
    return entry.id
end

local function getNoticeLog(limit)
    local count = math.tointeger(tonumber(limit)) or MAX_LOG_ENTRIES
    count = math.max(1, math.min(count, MAX_LOG_ENTRIES))
    local now = GetGameTimer()
    local entries = {}
    for index = #noticeLog, math.max(1, #noticeLog - count + 1), -1 do
        entries[#entries + 1] = copyLogEntry(noticeLog[index], now)
    end
    return entries
end

local function clearNoticeLog()
    local owner = getInvokingOwner()
    if owner == CURRENT_RESOURCE then
        noticeLog = {}
    else
        for index = #noticeLog, 1, -1 do
            if noticeLog[index].owner == owner then table.remove(noticeLog, index) end
        end
    end
    if peekActive then pushPeek() end
    return true
end

local function markLogSeen()
    for index = 1, #noticeLog do noticeLog[index].seen = true end
end

local function applyPeekHolds()
    local nextActive = peekHoldCount > 0
    if nextActive == peekActive then return end
    peekActive = nextActive
    if peekActive and #noticeLog > 0 and lib._presentationSettle then lib._presentationSettle() end
    pushPeek()
    if not peekActive then markLogSeen() end
    TriggerEvent('cortex-lib:peek', peekActive)
end

local function setPeekHold(key, active)
    local ownerHold = key:sub(1, #OWNER_HOLD_PREFIX) == OWNER_HOLD_PREFIX
    if active then
        if peekHolds[key] then return true end
        if ownerHold then
            if peekOwnerHoldCount >= MAX_PEEK_OWNER_HOLDS then return false end
            peekOwnerHoldCount = peekOwnerHoldCount + 1
        end
        peekHolds[key] = true
        peekHoldCount = peekHoldCount + 1
    else
        if not peekHolds[key] then return true end
        peekHolds[key] = nil
        peekHoldCount = peekHoldCount - 1
        if ownerHold then
            peekOwnerHoldCount = peekOwnerHoldCount - 1
            peekOwnerRefreshedAt[key] = nil
        end
    end
    applyPeekHolds()
    return true
end

local function watchOwnerHold(key)
    if peekOwnerTimers[key] then return end
    peekOwnerTimers[key] = true

    local function check()
        local refreshedAt = peekOwnerRefreshedAt[key]
        if not refreshedAt then
            peekOwnerTimers[key] = nil
            return
        end
        local remaining = PEEK_OWNER_LIMIT_MS - elapsedSince(GetGameTimer(), refreshedAt)
        if remaining <= 0 then
            peekOwnerTimers[key] = nil
            setPeekHold(key, false)
            return
        end
        SetTimeout(remaining, check)
    end

    SetTimeout(PEEK_OWNER_LIMIT_MS, check)
end

local function peek(active)
    if type(active) ~= 'boolean' then return false end
    local key = OWNER_HOLD_PREFIX .. getInvokingOwner()
    if not setPeekHold(key, active) then return false end
    if not active then return true end

    peekOwnerRefreshedAt[key] = GetGameTimer()
    watchOwnerHold(key)
    return true
end

local function isPeeking()
    return peekActive
end

local function releasePeekKey(token)
    if token ~= peekKeyToken then return end
    peekKeyPressedAt = nil
    setPeekHold('key', false)
end

local function pressPeekKey()
    if IsPauseMenuActive() or IsNuiFocused() then return end
    if peekHolds.key and not peekKeyPressedAt then
        releasePeekKey(peekKeyToken)
        peekKeyToken = peekKeyToken + 1
        return
    end
    peekKeyToken = peekKeyToken + 1
    local token = peekKeyToken
    peekKeyPressedAt = GetGameTimer()
    setPeekHold('key', true)

    CreateThread(function()
        local startedAt = peekKeyPressedAt
        while token == peekKeyToken and peekHolds.key do
            Wait(PEEK_WATCH_INTERVAL_MS)
            if token ~= peekKeyToken then return end
            if IsPauseMenuActive() or IsNuiFocused() or elapsedSince(GetGameTimer(), startedAt) > PEEK_KEY_LIMIT_MS then
                releasePeekKey(token)
                return
            end
        end
    end)
end

local function liftPeekKey()
    local pressedAt = peekKeyPressedAt
    if not pressedAt or not peekHolds.key then return end
    local token = peekKeyToken
    peekKeyPressedAt = nil
    if elapsedSince(GetGameTimer(), pressedAt) < PEEK_TAP_MS then
        SetTimeout(PEEK_LATCH_MS, function() releasePeekKey(token) end)
        return
    end
    releasePeekKey(token)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == CURRENT_RESOURCE then
        if peekActive then TriggerEvent('cortex-lib:peek', false) end
        return
    end
    for id, sender in pairs(senders) do
        if sender.owner == resourceName then releaseSender(id) end
    end
    setPeekHold(OWNER_HOLD_PREFIX .. resourceName, false)
end)

AddEventHandler('cortex-hud:client:streamerMode', function()
    if peekActive then pushPeek() end
end)

RegisterCommand('+cortexpeek', pressPeekKey, false)
RegisterCommand('-cortexpeek', liftPeekKey, false)
RegisterKeyMapping('+cortexpeek', 'Cortex: look (HUD and recent notices)', 'keyboard', GetConvar('cortex_lib_peek_key', 'Z'))

exports('registerSender', registerSender)
exports('removeSender', removeSender)
exports('getSender', getSender)
exports('getSenders', getSenders)
exports('getNoticeLog', getNoticeLog)
exports('clearNoticeLog', clearNoticeLog)
exports('peek', peek)
exports('isPeeking', isPeeking)

lib.registerSender = registerSender
lib.removeSender = removeSender
lib.getSender = getSender
lib.getSenders = getSenders
lib.getNoticeLog = getNoticeLog
lib.clearNoticeLog = clearNoticeLog
lib.peek = peek
lib.isPeeking = isPeeking
lib._resolveSender = resolveSender
lib._logNotice = logNotice
lib._setPeekHold = setPeekHold

return {
    registerSender = registerSender,
    removeSender = removeSender,
    getSender = getSender,
    getSenders = getSenders,
    getNoticeLog = getNoticeLog,
    clearNoticeLog = clearNoticeLog,
    peek = peek,
    isPeeking = isPeeking,
}
