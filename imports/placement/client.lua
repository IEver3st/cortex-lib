-- Local presentation only. The owning resource must authorize the returned
-- transform on its server before consuming items or creating shared entities.
local placement = {}
local owner = GetCurrentResourceName()
local active, mapped = nil, false
local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
local function elapsed(start) return (GetGameTimer() - start) % 4294967296 end
local function coords(v)
    local ok, x, y, z = pcall(function() return v.x, v.y, v.z end)
    if ok and finite(x) and finite(y) and finite(z) and math.abs(x) <= 100000
        and math.abs(y) <= 100000 and math.abs(z) <= 100000 then return { x = x, y = y, z = z } end
end
local function failure(code) return { ok = false, error = { code = code } } end
local function cleanup(session)
    local ownsInput = active == session
    if ownsInput then active = nil end
    local ghost, model, help = session.ghost, session.model, session.help
    session.ghost, session.model, session.help = nil, nil, false
    for key in pairs(session.pressed) do session.pressed[key] = false end
    -- Release ownership before calling providers. One stopped provider cannot
    -- strand the session or prevent the remaining independent cleanup.
    if ghost then pcall(function() if DoesEntityExist(ghost) then DeleteEntity(ghost) end end) end
    if model then pcall(SetModelAsNoLongerNeeded, model) end
    if help and ownsInput then pcall(function() lib.hideHelp() end) end
end
function placement.cancel(reason)
    if not active then return false end
    active.cancelled = reason or 'cancelled'
    cleanup(active)
    return true
end
function placement.isBusy() return active ~= nil end

function placement.loadModel(model, timeoutMs, cancelled)
    if type(model) == 'string' then
        if #model < 1 or #model > 64 or model:find('[%z\1-\31]') then return nil, 'invalid_model' end
        model = joaat(model)
    end
    if not finite(model) or model % 1 ~= 0 or model < -2147483648 or model > 4294967295
        or not IsModelInCdimage(model) or not IsModelValid(model) then return nil, 'invalid_model' end
    timeoutMs = timeoutMs or 4000
    if not finite(timeoutMs) or timeoutMs < 1 or timeoutMs > 10000 then return nil, 'invalid_timeout' end
    local start = GetGameTimer()
    RequestModel(model)
    while not HasModelLoaded(model) do
        if cancelled and cancelled() then SetModelAsNoLongerNeeded(model); return nil, 'cancelled' end
        if elapsed(start) >= timeoutMs then SetModelAsNoLongerNeeded(model); return nil, 'model_timeout' end
        Wait(0)
    end
    return model
end

local function mappings(bindings)
    if mapped then return end
    mapped = true
    local defaults = { confirm = 'MOUSE_LEFT', cancel = 'BACK', left = 'LEFT', right = 'RIGHT' }
    for _, action in ipairs({ 'confirm', 'cancel', 'left', 'right' }) do
        local command = owner .. '_placement_' .. action
        RegisterCommand('+' .. command, function() if active then active.pressed[action] = true end end, false)
        RegisterCommand('-' .. command, function() if active then active.pressed[action] = false end end, false)
        local key = bindings and bindings[action] or defaults[action]
        -- Mouse buttons only bind through the MOUSE_BUTTON mapper; 'keyboard' leaves them unbound.
        RegisterKeyMapping('+' .. command, 'Placement: ' .. action, key:sub(1, 6) == 'MOUSE_' and 'MOUSE_BUTTON' or 'keyboard', key)
    end
end

local function surface(session, point, normal, hitEntity)
    point, normal = coords(point), coords(normal)
    if not point or not normal or normal.z < session.minNormalZ then return nil end
    -- Map geometry reports a non-zero handle that is not a script entity (GetEntityType 0), so
    -- only refuse moving surfaces: peds and vehicles.
    if hitEntity ~= 0 and hitEntity ~= nil and DoesEntityExist(hitEntity) then
        local kind = GetEntityType(hitEntity)
        if kind == 1 or kind == 2 then return nil end
    end
    local position = coords(GetEntityCoords(session.ped))
    if not position then return nil end
    if (point.x - position.x)^2 + (point.y - position.y)^2 + (point.z - position.z)^2 > session.maxDistance^2 then return nil end
    return { model = session.model, coords = { x = point.x, y = point.y, z = point.z - session.minZ },
        normal = normal, heading = session.heading }
end

local function probe(session)
    local cam = coords(GetGameplayCamCoord())
    local rotation = coords(GetGameplayCamRot(2))
    if not cam or not rotation then return nil end
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local distance = session.maxDistance + 4
    local dx, dy, dz = -math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)
    return StartShapeTestLosProbe(cam.x, cam.y, cam.z, cam.x + dx * distance,
        cam.y + dy * distance, cam.z + dz * distance, 17, session.ped, 7)
end

function placement.preview(options)
    if active then return failure('busy') end
    if type(options) ~= 'table' then return failure('invalid_options') end
    local maxDistance, minNormalZ, timeoutMs = options.maxDistance or 8, options.minNormalZ or 0.85, options.timeoutMs or 60000
    if not finite(maxDistance) or maxDistance < 1 or maxDistance > 20 or not finite(minNormalZ) or minNormalZ < 0.5
        or minNormalZ > 1 or not finite(timeoutMs) or timeoutMs < 1000 or timeoutMs > 180000
        or (options.heading ~= nil and not finite(options.heading)) then return failure('invalid_options') end
    local session = { ped = PlayerPedId(), maxDistance = maxDistance, minNormalZ = minNormalZ,
        heading = (options.heading or 0) % 360, started = GetGameTimer(),
        pressed = { confirm = false, cancel = false, left = false, right = false } }
    local pressed = session.pressed
    active = session
    local ok, result = pcall(function()
        mappings(options.bindings)
        local model, err = placement.loadModel(options.model, options.modelTimeoutMs, function() return session.cancelled ~= nil end)
        if not model then return failure(err) end
        session.model = model
        if session.cancelled or active ~= session then return failure(session.cancelled or 'cancelled') end
        local minimum = GetModelDimensions(model)
        session.minZ = coords(minimum) and minimum.z or 0
        local position = GetEntityCoords(session.ped)
        session.ghost = CreateObjectNoOffset(model, position.x, position.y, position.z, false, false, false)
        if session.ghost == 0 then return failure('object_failed') end
        SetEntityCollision(session.ghost, false, false)
        FreezeEntityPosition(session.ghost, true)
        SetEntityAlpha(session.ghost, 120, false)
        SetEntityVisible(session.ghost, false, false)
        session.help = lib.showHelp(options.help or {
            { label = 'Place', value = 'LMB / A' }, { label = 'Rotate', value = 'ARROWS / D-PAD' },
            { label = 'Cancel', value = 'BACK / B' },
        }, { compact = true }) == true
        local handle, probeStarted, nextProbe, candidate, sampled = nil, 0, 0, nil, 0
        local lastFrame = GetGameTimer()
        while active == session and not session.cancelled do
            if elapsed(session.started) >= timeoutMs then return failure('timeout') end
            if PlayerPedId() ~= session.ped or IsEntityDead(session.ped) or IsPedInAnyVehicle(session.ped, false)
                or IsPedSwimming(session.ped) or IsPauseMenuActive() or IsNuiFocused() then return failure('context_lost') end
            local now = GetGameTimer()
            if not handle and (now - nextProbe) % 4294967296 < 2147483648 then
                handle, probeStarted = probe(session), now
                if not handle or handle == 0 then handle = nil; nextProbe = now + 100 end
            end
            if handle then
                local status, hit, point, normal, entity = GetShapeTestResult(handle)
                if status ~= 1 then
                    candidate = status == 2 and (hit == 1 or hit == true) and surface(session, point, normal, entity) or nil
                    sampled, handle, nextProbe = now, nil, now + 50
                elseif (now - probeStarted) % 4294967296 >= 200 then
                    candidate, handle, nextProbe = nil, nil, now + 50
                end
            end
            local valid = candidate and (now - sampled) % 4294967296 <= 250
            if valid then
                SetEntityCoordsNoOffset(session.ghost, candidate.coords.x, candidate.coords.y, candidate.coords.z, false, false, false)
                SetEntityHeading(session.ghost, session.heading)
            end
            SetEntityVisible(session.ghost, valid ~= nil and valid ~= false, false)
            for _, control in ipairs({ 24, 25, 140, 141, 142, 201, 202, 174, 175 }) do DisableControlAction(0, control, true) end
            if pressed.cancel or IsDisabledControlJustPressed(0, 202) or IsControlJustPressed(0, 177) then return failure('cancelled') end
            -- Left click (attack, disabled above) also confirms, whatever an older saved binding says.
            if pressed.confirm or IsDisabledControlJustPressed(0, 201) or IsDisabledControlJustPressed(0, 24) then
                pressed.confirm = false
                if valid then candidate.heading = session.heading; return { ok = true, data = candidate } end
            end
            local step = math.min((now - lastFrame) % 4294967296, 50) * 0.09
            if pressed.left or IsDisabledControlPressed(0, 174) then session.heading = (session.heading - step) % 360 end
            if pressed.right or IsDisabledControlPressed(0, 175) then session.heading = (session.heading + step) % 360 end
            lastFrame = now
            Wait(0)
        end
        return failure(session.cancelled or 'cancelled')
    end)
    cleanup(session)
    if not ok then
        print(('[cortex-lib] placement failed in %s: %s'):format(owner, type(result) == 'string' and result:sub(1, 256) or type(result)))
        return failure('presentation_failed')
    end
    return result
end

AddEventHandler('onResourceStop', function(resource)
    if resource == owner or resource == 'cortex-lib' then placement.cancel('resource_stopped') end
end)
AddEventHandler('QBCore:Client:OnPlayerUnload', function() placement.cancel('character_unloaded') end)
return placement
