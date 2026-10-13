local function harness(settings)
    settings = settings or {}
    local now, commands, events, exists, deleted, released = 0, {}, {}, {}, 0, 0
    local help, modelRequests, probes, controlFrames = false, 0, 0, 0
    local api
    lib = { showHelp = function() help = true; return true end, hideHelp = function() help = false end }
    GetCurrentResourceName = function() return 'consumer' end
    GetGameTimer = function() return now end
    GetEntityCoords = function() return { x = 0, y = 0, z = 0 } end
    GetGameplayCamCoord = GetEntityCoords
    GetGameplayCamRot = function() return { x = -10, y = 0, z = 0 } end
    PlayerPedId = function() return 1 end
    IsEntityDead = function() return settings.dead == true end
    IsPedInAnyVehicle = function() return settings.vehicle == true end
    IsPedSwimming = function() return false end
    IsPauseMenuActive = function() return false end
    IsNuiFocused = function() return false end
    joaat = function() return 123 end
    IsModelInCdimage = function() return settings.invalid ~= true end
    IsModelValid = IsModelInCdimage
    RequestModel = function() modelRequests = modelRequests + 1 end
    HasModelLoaded = function() return settings.loading ~= true end
    SetModelAsNoLongerNeeded = function() released = released + 1 end
    GetModelDimensions = function() return { x = -1, y = -1, z = -0.5 }, { x = 1, y = 1, z = 1 } end
    CreateObjectNoOffset = function() exists[2] = true; return 2 end
    DoesEntityExist = function(id) return exists[id] == true or id == 1 or (id == settings.hitEntity and settings.hitExists ~= false) end
    DeleteEntity = function(id) exists[id] = false; deleted = deleted + 1 end
    SetEntityCollision = function() end
    FreezeEntityPosition = function() end
    SetEntityAlpha = function() end
    SetEntityVisible = function() end
    SetEntityCoordsNoOffset = function() if settings.renderError then error('render_fixture') end end
    SetEntityHeading = function() end
    GetEntityType = function() return settings.surfaceType or 3 end
    RegisterCommand = function(name, fn) commands[name] = fn end
    RegisterKeyMapping = function() end
    AddEventHandler = function(name, fn) events[name] = fn end
    StartShapeTestLosProbe = function() probes = probes + 1; return probes end
    GetShapeTestResult = function()
        if settings.pending then return 1 end
        return 2, 1, { x = settings.distance or 2, y = 0, z = 0 }, { x = 0, y = 0, z = settings.normal or 1 }, settings.hitEntity or 0
    end
    DisableControlAction = function() controlFrames = controlFrames + 1 end
    IsDisabledControlJustPressed = function() return false end
    IsControlJustPressed = function() return false end
    IsDisabledControlPressed = function() return false end
    Wait = function()
        now = now + 20
        if settings.onWait then settings.onWait(api, commands, events, now, settings) end
    end
    api = dofile('imports/placement/client.lua')
    return api, function() return { deleted = deleted, released = released, help = help, requests = modelRequests,
        probes = probes, controlFrames = controlFrames, active = api.isBusy() } end
end
local passed = 0
local function test(name, fn) fn(); passed = passed + 1; print('PASS ' .. name) end
test('valid transform grounds model rotates and leaves no ghost/help/model', function()
    local api, state = harness({ onWait = function(_, commands, _, now)
        if now == 20 then commands['+consumer_placement_right']() end
        if now == 80 then commands['+consumer_placement_confirm']() end
    end })
    local result = api.preview({ model = 'cone' })
    assert(result.ok and result.data.coords.z == 0.5 and result.data.heading > 0)
    local s = state(); assert(s.deleted == 1 and s.released == 1 and not s.help and not s.active)
end)
test('model deadline and explicit cancellation are bounded without spawning', function()
    local api, state = harness({ loading = true })
    local result = api.preview({ model = 'cone', modelTimeoutMs = 40 })
    assert(not result.ok and result.error.code == 'model_timeout' and state().deleted == 0 and not state().active)
    api, state = harness({ loading = true, onWait = function(api) api.cancel() end })
    result = api.preview({ model = 'cone' })
    assert(result.error.code == 'cancelled' and state().deleted == 0 and not state().active)
end)
test('invalid slope dynamic surface and distance never confirm', function()
    for _, opts in ipairs({ { normal = 0.2 }, { distance = 30 }, { hitEntity = 3, surfaceType = 2 } }) do
        opts.onWait = function(_, commands, _, now)
            if now == 20 then commands['+consumer_placement_confirm']() end
            if now == 60 then commands['+consumer_placement_cancel']() end
        end
        local api, state = harness(opts)
        assert(api.preview({ model = 'cone' }).error.code == 'cancelled' and state().deleted == 1)
    end
end)
test('map geometry hits with a non-script handle still place; peds and vehicles never do', function()
    -- Live probe on Strawberry Ave: the road returned entity 820994 with GetEntityType 0.
    for _, opts in ipairs({ { hitEntity = 820994, hitExists = false, surfaceType = 0 }, { hitEntity = 820994, surfaceType = 0 } }) do
        opts.onWait = function(_, commands, _, now) if now == 60 then commands['+consumer_placement_confirm']() end end
        local api = harness(opts)
        local result = api.preview({ model = 'cone' })
        assert(result.ok, 'world hit was rejected: ' .. tostring(result.error and result.error.code))
    end
    for _, kind in ipairs({ 1, 2 }) do
        local api = harness({ hitEntity = 5, surfaceType = kind, onWait = function(_, commands, _, now)
            if now == 20 then commands['+consumer_placement_confirm']() end
            if now == 60 then commands['+consumer_placement_cancel']() end
        end })
        assert(api.preview({ model = 'cone' }).error.code == 'cancelled', 'moving entity accepted')
    end
end)
test('pending ray does not delay cancellation or leave stale confirmation', function()
    local api, state = harness({ pending = true, onWait = function(_, commands, _, now)
        if now == 20 then commands['+consumer_placement_confirm']() end
        if now == 40 then commands['+consumer_placement_cancel']() end
    end })
    assert(api.preview({ model = 'cone' }).error.code == 'cancelled' and state().probes == 1 and state().deleted == 1)
end)
test('owner stop unload context loss and render failure all clean once', function()
    for _, kind in ipairs({ 'stop', 'unload', 'vehicle', 'error' }) do
        local settings = { renderError = kind == 'error', onWait = function(_, _, events, _, current)
            if kind == 'stop' then events.onResourceStop('consumer')
            elseif kind == 'unload' then events['QBCore:Client:OnPlayerUnload']()
            elseif kind == 'vehicle' then current.vehicle = true end
        end }
        local api, state = harness(settings)
        local result = api.preview({ model = 'cone' })
        assert(not result.ok and state().deleted == 1 and state().released == 1 and not state().help and not state().active)
        assert(api.cancel() == false and state().deleted == 1)
    end
end)
test('bad values fail before requesting assets and simultaneous preview is denied', function()
    local api, state = harness()
    assert(api.preview({ model = 'cone', maxDistance = math.huge }).error.code == 'invalid_options' and state().requests == 0)
    local nested
    api, state = harness({ onWait = function(current, commands, _, now)
        nested = current.preview({ model = 'cone' })
        if now == 20 then commands['+consumer_placement_cancel']() end
    end })
    api.preview({ model = 'cone' }); assert(nested.error.code == 'busy' and state().deleted == 1)
end)
print(('Result: %d passed, 0 failed'):format(passed))
