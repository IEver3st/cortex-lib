-- Local minigame results are presentation, never server authorization.
local active, generation = nil, 0
local currentResource = GetCurrentResourceName()
local types = { radial = true, trace = true, mash = true, hold = true, sequence = true }

local function owner()
    return (GetInvokingResource and GetInvokingResource()) or currentResource
end

local function number(value, default, minimum, maximum)
    if value == nil then return default end
    if type(value) ~= 'number' or value ~= value or value < minimum or value > maximum then return nil end
    return value
end

local function text(value, maximum)
    return type(value) == 'string' and #value > 0 and #value <= maximum and not value:find('%c')
end

local function key(value)
    return type(value) == 'string' and (value:match('^[a-zA-Z0-9]$') or value == 'SPACE')
end

local function normalize(data)
    if type(data) ~= 'table' or not types[data.type or 'radial'] then return nil end
    local config = { type = data.type or 'radial', label = data.label or 'Skill check', key = data.key or 'E',
        direction = data.direction or 'upper', interactionId = data.interactionId }
    if not text(config.label, 64) or not key(config.key) then return nil end
    config.key = config.key:upper()
    if config.direction ~= 'upper' and config.direction ~= 'lower' then return nil end
    for name, range in pairs({ duration = { 10000, 1000, 120000 }, speed = { 0.55, 0.1, 2 },
        targetSize = { 0.14, 0.04, 0.35 }, targetStart = { 0.55, 0.1, 0.9 },
        gain = { 0.12, 0.01, 0.5 }, decay = { 0.18, 0.01, 1 }, tolerance = { 0.15, 0.08, 0.4 },
        sensitivity = { 1, 0.25, 4 } }) do
        config[name] = number(data[name], range[1], range[2], range[3])
        if not config[name] then return nil end
    end
    if config.targetStart + config.targetSize > 1 then return nil end
    if config.type == 'mash' and not text(config.interactionId, 64) then return nil end
    if config.type ~= 'mash' and config.interactionId ~= nil then return nil end
    local keys = data.keys or { 'E', 'R', 'E', 'Q' }
    if type(keys) ~= 'table' or #keys < 2 or #keys > 8 then return nil end
    local count = 0
    config.keys = {}
    for index, value in pairs(keys) do
        if type(index) ~= 'number' or index % 1 ~= 0 or index < 1 or index > #keys or not key(value) then return nil end
        count = count + 1
        config.keys[index] = value:upper()
    end
    if count ~= #keys then return nil end
    return config
end

local function send(action, session, extra)
    local data = extra or {}
    data.session = session.id
    SendNUIMessage({ action = action, data = data })
end

local function finish(success, reason)
    local session = active
    if not session then return false end
    active = nil
    if session.modal then lib._releaseModal('skillCheck', session.modal) end
    send('skill:close', session, { success = success, reason = reason })
    session.promise:resolve({ success = success, reason = reason })
    return true
end

local function validTarget(session)
    local entry = lib._getInteractionForSkillCheck(session.owner, session.config.interactionId)
    return entry and entry == session.entry and entry.anchor and entry.active and entry.visible
end

local function decay(session, now)
    session.progress = math.max(0, session.progress - (now - session.updated) / 1000 * session.config.decay)
    session.updated = now
end

local traceControls = { 1, 2, 3, 4, 5, 6, 24, 25, 200, 202 }
local function updateMouseTrace(session, now)
    -- Own look input only during this session. No cursor or NUI focus is taken.
    for index = 1, #traceControls do DisableControlAction(0, traceControls[index], true) end
    DisablePlayerFiring(PlayerId(), true)
    if IsNuiFocused() or IsPauseMenuActive() then finish(false, 'interrupted') return end
    if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 202) then
        finish(false, 'cancelled') return
    end
    if not session.ready then return end
    local state = session.trace
    local completed = false
    -- Pad look input is not a mouse sweep; it neither advances nor resets the knob.
    if IsUsingKeyboard(0) then
        completed = stepMouseTrace(state, GetDisabledControlUnboundNormal(0, 1),
            GetDisabledControlUnboundNormal(0, 2), now, session.config.direction, session.config.tolerance)
    end
    local progress = completed and 1 or math.floor(state.progress * 1000) / 1000
    -- Presentation only: capped at ~30 Hz, completion is sent immediately.
    if completed or (now - session.sentAt >= 33
        and (progress ~= session.sentProgress or state.invalid ~= session.sentInvalid)) then
        send('skill:trace', session, { progress = progress, invalid = state.invalid })
        session.sentProgress, session.sentInvalid, session.sentAt = progress, state.invalid, now
    end
    if completed then finish(true, 'success') end
end

local function skillCheck(data)
    local config = normalize(data)
    if not config then return false, 'invalid_options' end
    if active then return false, 'busy' end
    local caller = owner()
    local entry, modal
    if config.type == 'mash' then
        if lib._hasModalSurface() or IsNuiFocused() then return false, 'busy' end
        entry = lib._getInteractionForSkillCheck(caller, config.interactionId)
        if not entry or not entry.anchor or entry.holdDuration or not entry.active or not entry.visible then
            return false, 'interaction_unavailable'
        end
        config.key = entry.key
    else
        modal = lib._acquireModal('skillCheck', caller)
        if not modal then return false, 'busy' end
    end
    generation = generation + 1
    local session = { id = generation, owner = caller, config = config, modal = modal, entry = entry,
        promise = promise.new(), progress = 0, updated = GetGameTimer(), down = false, lastPress = -1000 }
    if config.type == 'trace' then
        session.trace, session.sentAt = newMouseTrace(TRACE_RADIUS / config.sensitivity), 0
    end
    active = session
    send('skill:open', session, { config = config, owner = caller })
    CreateThread(function()
        local opened = GetGameTimer()
        while active == session do
            local now = GetGameTimer()
            if not session.ready and now - opened >= 3000 then finish(false, 'ui_timeout')
            elseif session.ready and now - session.started >= config.duration then finish(false, 'timeout')
            elseif IsEntityDead(PlayerPedId()) then finish(false, 'dead')
            elseif config.type == 'trace' then updateMouseTrace(session, now)
            elseif config.type == 'mash' then
                if not validTarget(session) then finish(false, 'interaction_unavailable')
                elseif lib._hasModalSurface() or IsNuiFocused() or IsPauseMenuActive() then finish(false, 'interrupted')
                else decay(session, now) end
            end
            Wait(config.type == 'trace' and 0 or 50)
        end
    end)
    local result = Citizen.Await(session.promise)
    return result.success, result.reason
end

-- Consumer-owned +/- commands forward edges. Holding a key cannot auto-repeat.
local function skillCheckPress(id, down)
    local session = active
    if not session or session.owner ~= owner() or session.config.type ~= 'mash'
        or session.config.interactionId ~= id or type(down) ~= 'boolean' then return false, 'not_active' end
    if not down then session.down = false return true end
    if not session.ready then return false, 'not_ready' end
    if not validTarget(session) then finish(false, 'interaction_unavailable') return false, 'interaction_unavailable' end
    if lib._hasModalSurface() or IsNuiFocused() or IsPauseMenuActive() then
        finish(false, 'interrupted') return false, 'interrupted'
    end
    if session.down then return false, 'held' end
    session.down = true
    local now = GetGameTimer()
    if now - session.started >= session.config.duration then finish(false, 'timeout') return false, 'timeout' end
    if now - session.lastPress < 50 then return false, 'too_fast' end
    session.lastPress = now
    decay(session, now)
    session.progress = math.min(1, session.progress + session.config.gain)
    send('skill:progress', session, { progress = session.progress })
    if session.progress >= 1 then finish(true, 'success') end
    return true
end

local function cancelSkillCheck()
    if not active or active.owner ~= owner() then return false end
    return finish(false, 'cancelled')
end

local function isSkillCheckActive()
    return active ~= nil and active.owner == owner()
end

RegisterNUICallback('skillReady', function(data, cb)
    local session = active
    if type(data) ~= 'table' or not session or data.session ~= session.id then cb({ ok = false, error = 'stale_session' }) return end
    if not session.ready then
        if session.modal and session.config.type ~= 'trace' and not lib._focusModal('skillCheck', session.modal, false, false) then
            finish(false, 'focus_failed') cb({ ok = false, error = 'focus_failed' }) return
        end
        session.ready, session.started = true, GetGameTimer()
        session.updated = session.started
        send('skill:start', session)
    end
    cb({ ok = true })
end)

RegisterNUICallback('skillResult', function(data, cb)
    local session = active
    if type(data) ~= 'table' or not session or data.session ~= session.id or not session.ready then
        cb({ ok = false, error = 'stale_session' }) return
    end
    local reasons = { success = true, missed = true, timeout = true, cancelled = true, interrupted = true }
    if type(data.success) ~= 'boolean' or not reasons[data.reason]
        or data.success ~= (data.reason == 'success') or session.config.type == 'mash' or session.config.type == 'trace' then
        cb({ ok = false, error = 'invalid_result' }) return
    end
    if GetGameTimer() - session.started >= session.config.duration then finish(false, 'timeout')
    else finish(data.success, data.reason) end
    cb({ ok = true })
end)

local closer = function() finish(false, 'interrupted') end
if rawget(lib, '_registerModalSurface') then lib._registerModalSurface('skillCheck', closer)
else
    lib._pendingModalSurfaces = rawget(lib, '_pendingModalSurfaces') or {}
    lib._pendingModalSurfaces.skillCheck = closer
end
AddEventHandler('onClientResourceStop', function(resource)
    if active and (resource == currentResource or resource == active.owner) then finish(false, 'resource_stopped') end
end)

for name, fn in pairs({ skillCheck = skillCheck, cancelSkillCheck = cancelSkillCheck,
    isSkillCheckActive = isSkillCheckActive, skillCheckPress = skillCheckPress }) do
    lib[name] = fn
    exports(name, fn)
end
return skillCheck
