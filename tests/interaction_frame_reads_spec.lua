-- Run from cortex-lib: lua tests/interaction_frame_reads_spec.lua [baseline-renderer.lua]
-- Native counts are deterministic mock evidence, never runtime timing claims.
-- An optional pre-edit renderer verifies identical message/presentation traces.
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function encode(value)
    local kind = type(value)
    if kind == 'nil' or kind == 'boolean' then return kind .. ':' .. tostring(value) end
    if kind == 'number' or kind == 'string' then return kind .. ':' .. string.format('%q', value) end
    assert(kind == 'table', 'trace contains an unsupported scalar: ' .. kind)
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return a < b
    end)
    for _, key in ipairs(keys) do parts[#parts + 1] = encode(key) .. ':' .. encode(value[key]) end
    return '{' .. table.concat(parts, ',') .. '}'
end

assert(encode(1) ~= encode('1') and encode(false) ~= encode('false'), 'trace comparison must retain scalar types')
assert(encode(1.0) ~= encode(1.0 + 2 ^ -52), 'trace comparison must retain adjacent floating-point values')

local function fixture(rendererPath)
    local f = {
        clock = 0, owner = 'owner-a', counts = {}, trace = {}, messages = {},
        exported = {}, handlers = {}, callbacks = {}, threads = {},
        entities = {
            [1] = { exists = true, model = 10, x = 0, y = 0, z = 0, heading = 0 },
            [500] = { exists = true, model = 100, x = 1, y = 0, z = 0, heading = 0, bones = { bonnet = 2 } },
            [600] = { exists = true, model = 200, x = 1.5, y = 0, z = 0, heading = 0, bones = { bonnet = 7 } },
        },
        projected = true, screenX = 0.4,
    }
    local env = setmetatable({}, { __index = _G })
    env.lib = {
        isInternalResource = function() return true end,
        cache = { ped = 1 },
        getSetting = function() return nil end,
    }
    local function count(name, entity)
        local key = name .. ':' .. tostring(entity or '')
        f.counts[key] = (f.counts[key] or 0) + 1
    end
    function env.exports(name, callback) f.exported[name] = callback end
    function env.GetInvokingResource() return f.owner end
    function env.GetCurrentResourceName() return 'cortex-lib' end
    function env.AddEventHandler(name, callback)
        f.handlers[name] = f.handlers[name] or {}
        table.insert(f.handlers[name], callback)
    end
    function env.TriggerEvent(name, ...)
        for _, callback in ipairs(f.handlers[name] or {}) do callback(...) end
    end
    function env.RegisterNUICallback(name, callback) f.callbacks[name] = callback end
    function env.CreateThread(callback) f.threads[#f.threads + 1] = coroutine.create(callback) end
    function env.Wait(ms) coroutine.yield(ms) end
    function env.SendNUIMessage(message)
        local snapshot = copy(message)
        f.messages[#f.messages + 1] = snapshot
        f.trace[#f.trace + 1] = { clock = f.clock, message = snapshot }
    end
    function env.GetSafeZoneSize() return 1 end
    function env.GetActiveScreenResolution() return 1920, 1080 end
    function env.GetGameTimer() return f.clock end
    function env.PlayerPedId() return 1 end
    function env.PlayerId() return 0 end
    function env.DoesEntityExist(entity)
        count('exists', entity)
        return f.entities[entity] and f.entities[entity].exists or false
    end
    function env.GetEntityModel(entity)
        count('model', entity)
        return f.entities[entity].model
    end
    function env.GetEntityCoords(entity)
        count('coords', entity)
        local e = f.entities[entity]
        if e.coordsNil then return nil end
        return { x = e.x, y = e.y, z = e.z }
    end
    function env.GetEntityBoneIndexByName(entity, bone)
        count('boneIndex', entity)
        return (f.entities[entity].bones or {})[bone] or -1
    end
    function env.GetEntityBonePosition_2(entity, index)
        count('bonePosition', entity)
        local e = f.entities[entity]
        if e.boneCoordsNil then return nil end
        return { x = e.x + index * 0.1, y = e.y + index * 0.05, z = e.z + 0.2 }
    end
    function env.GetOffsetFromEntityInWorldCoords(entity, x, y, z)
        count('offset', entity)
        local e = f.entities[entity]
        if e.offsetNil then return nil end
        local c, s = math.cos(e.heading), math.sin(e.heading)
        return { x = e.x + x * c - y * s, y = e.y + x * s + y * c, z = e.z + z }
    end
    function env.World3dToScreen2d(x, y, z)
        count('projection')
        f.trace[#f.trace + 1] = { clock = f.clock, projection = { x, y, z } }
        return f.projected, f.screenX + x * 0.001, 0.4 + y * 0.001
    end
    function env.DisableControlAction() end
    function env.IsDisabledControlJustPressed() return false end
    function env.IsPauseMenuActive() return false end
    function env.IsPlayerFreeAiming() return false end

    assert(loadfile('imports/interaction/client.lua', 't', env))()
    local writePresentation = env.lib._setInteractionPresentationState
    env.lib._setInteractionPresentationState = function(owner, id, visible, distance)
        f.trace[#f.trace + 1] = { clock = f.clock, presentation = { owner, id, visible, distance } }
        return writePresentation(owner, id, visible, distance)
    end
    assert(loadfile(rendererPath, 't', env))()
    f.callbacks.interactionReady({}, function(result) assert(result.ok) end)

    function f:set(items, owner)
        self.owner = owner or 'owner-a'
        local ok, err = self.exported.setInteractions(items)
        assert(ok, err)
    end
    function f:frame(at)
        self.clock = at
        local ok, wait = coroutine.resume(self.threads[#self.threads])
        assert(ok, wait)
        self.trace[#self.trace + 1] = { clock = at, wait = wait, registry = copy(env.lib.getInteractions()) }
        return wait
    end
    function f:visible(id, owner)
        self.owner = owner or 'owner-a'
        return self.exported.isInteractionVisible(id)
    end
    f.env = env
    return f
end

local function rows(model, count, offset, bone)
    local items = {}
    for index = 1, count or 8 do
        items[index] = {
            id = 'row' .. index, label = 'ACTION ' .. index, key = 'E', priority = 10 - index,
            anchor = {
                type = 'entity-bone', entity = 500, model = model, bone = bone or 'bonnet',
                offset = offset or { x = 0.2, y = 0.4, z = 0.1 }, maxDistance = 4, markerDistance = 10,
            },
        }
    end
    return items
end

local function delta(f, before, name, entity)
    local key = name .. ':' .. tostring(entity or '')
    return (f.counts[key] or 0) - (before[key] or 0)
end

local function exercise(rendererPath)
    local f = fixture(rendererPath)
    f:set(rows(100))
    assert(f:frame(0) == 0)
    local cold = copy(f.counts)
    assert(f:visible('row1') and not f:visible('row2'), 'only the key owner is actionable')
    local before = copy(f.counts)
    local sent = #f.messages
    assert(f:frame(16) == 0)
    local warm = copy(f.counts)
    assert(#f.messages == sent, 'an unchanged frame sends no message')

    f.entities[500].x, f.entities[500].heading = 1.2, math.pi * 0.5
    f.screenX = 0.7
    assert(f:frame(32) == 0)
    assert(f.messages[#f.messages].action == 'interaction:worldMove', 'motion uses the existing move protocol')
    assert(delta(f, before, 'projection') == 16, 'all eight anchors still project on both render passes')

    -- Existing model freshness stays per descriptor, exactly 15 renderer passes.
    f.entities[500].model, f.entities[500].bones.bonnet = 101, 3
    for index = 1, 12 do
        f:frame(32 + index * 16)
        assert(f:visible('row1'), 'model checks retain their existing cadence')
    end
    local rejectedBefore = copy(f.counts)
    f:frame(240)
    local rejectedAfter = copy(f.counts)
    assert(not f:visible('row1'), 'model reuse hides the old expected model on its check')
    f:set(rows(101))
    f:frame(256)
    assert(f:visible('row1'), 'a replacement definition invalidates model-dependent bone reads')

    f.entities[500].exists = false
    local deletedBefore = copy(f.counts)
    f:frame(272)
    local deletedAfter = copy(f.counts)
    assert(not f:visible('row1'), 'deletion is observed on the next rendered pass')
    f.entities[500].exists, f.entities[500].bones.bonnet = true, nil
    f:frame(288)
    assert(not f:visible('row1'), 'a missing bone is hidden')
    local missingBefore = copy(f.counts)
    f:frame(304)
    local missingAfter = copy(f.counts)
    f.entities[500].bones.bonnet = 4
    f:frame(320)
    assert(f:visible('row1'), 'missing bone results expire with the pass and retry immediately')

    local failures = {}
    for index, flag in ipairs({ 'boneCoordsNil', 'coordsNil', 'offsetNil' }) do
        f.entities[500][flag] = true
        local failureBefore = copy(f.counts)
        f:frame(320 + index * 2 - 1)
        failures[flag] = { before = failureBefore, after = copy(f.counts) }
        assert(f:visible('row1') == (flag ~= 'boneCoordsNil'), 'failed reads preserve the existing hide/fallback behavior')
        f.entities[500][flag] = false
        f:frame(320 + index * 2)
        assert(f:visible('row1'), 'failed reads expire on the next pass')
    end

    local mixed = rows(101, 4)
    mixed[2].anchor.offset = { x = -0.3, y = 0.4, z = 0.1 }
    mixed[3].anchor.bone = 'boot'
    mixed[4].anchor.entity, mixed[4].anchor.model = 600, 200
    f.entities[500].bones.boot = 5
    f:set(mixed)
    before = copy(f.counts)
    f:frame(336)
    local distinct = copy(f.counts)
    assert(f:visible('row1'), 'distinct offsets/bones/entities do not poison a shared list')

    -- An entity origin and a bone can share one offset without sharing their final anchor.
    local origins = rows(101, 2)
    origins[1].anchor.type, origins[1].anchor.bone = 'entity', nil
    f:set(origins)
    f:frame(352)
    -- Player-anchored rows reuse the validated player coordinate read for this pass.
    origins[1].anchor.entity, origins[1].anchor.model, origins[1].anchor.offset = 1, 10, nil
    origins[2].anchor.entity, origins[2].anchor.model = 1, 10
    origins[2].anchor.type, origins[2].anchor.bone = 'entity', nil
    f:set(origins)
    local playerBefore = copy(f.counts)
    f:frame(368)
    local playerAfter = copy(f.counts)

    -- Same entity across owners shares reads while owner removal still removes only its prompts.
    f:set(rows(101), 'owner-a')
    f:set(rows(101), 'owner-b')
    local capacityBefore = copy(f.counts)
    f:frame(384)
    local capacityAfter = copy(f.counts)
    f.env.TriggerEvent('onClientResourceStop', 'owner-b')
    f:frame(400)

    f.projected = false
    assert(f:frame(416) == 33, 'offscreen cadence is unchanged')
    assert(not f:visible('row1'), 'offscreen prompts stop being actionable')
    f.projected = true
    f.entities[500].x = 6
    assert(f:frame(432) == 0, 'visible markers still project every render frame')
    local markerMessage = f.messages[#f.messages]
    assert(markerMessage.action == 'interaction:world' and markerMessage.data.items[1].tier == 'marker')
    assert(not f:visible('row1'), 'markers never authorize an interaction')

    -- Keep one world prompt active while the distant entity uses the existing bounded cull.
    f:set({
        { id = 'near', label = 'NEAR', key = 'G', anchor = { type = 'world', x = 1, y = 0, z = 0 } },
        { id = 'far', label = 'FAR', key = 'E', anchor = { type = 'entity', entity = 500, maxDistance = 2 } },
    })
    f.entities[500].x = 50
    f:frame(448)
    local farBefore = copy(f.counts)
    f:frame(464)
    assert(delta(f, farBefore, 'exists', 500) == 0, 'frame read sharing does not bypass distance culling')
    f.entities[500].x = 1
    f:frame(944)
    assert(f:visible('far'), 'arrival is restored when the existing cull expires')
    f:frame(100) -- clock rollback remains accepted by the existing worker

    f:set({})
    local stoppedBefore = copy(f.counts)
    f:frame(116)
    assert(encode(f.counts) == encode(stoppedBefore), 'cleared registrations stop the worker')
    f.env.TriggerEvent('onClientResourceStop', 'cortex-lib')
    return { f = f, cold = cold, warm = warm, distinctBefore = before, distinctAfter = distinct,
        rejectedBefore = rejectedBefore, rejectedAfter = rejectedAfter,
        deletedBefore = deletedBefore, deletedAfter = deletedAfter,
        missingBefore = missingBefore, missingAfter = missingAfter, failures = failures,
        playerBefore = playerBefore, playerAfter = playerAfter,
        capacityBefore = capacityBefore, capacityAfter = capacityAfter }
end

local function exerciseStaggered(rendererPath)
    local f = fixture(rendererPath)
    local items = rows(100, 2)
    items[1].anchor.maxDistance, items[1].anchor.markerDistance = 7, 0
    items[1].anchor.offset = { x = 0, y = 0, z = 0 }
    items[2].key, items[2].anchor.model = 'G', nil
    items[2].anchor.maxDistance, items[2].anchor.markerDistance = 7, 0
    items[2].anchor.offset = { x = 10, y = 0, z = 0 }
    f.entities[500].x = 2
    f:set(items)
    for frame = 0, 15 do f:frame(frame * 3) end
    f.entities[500].x, f.entities[500].model, f.entities[500].bones.bonnet = -4, 101, 3
    local before = copy(f.counts)
    f:frame(54)
    local after = copy(f.counts)
    assert(f:visible('row1') and f:visible('row2'), 'one due model read must not refresh another descriptor early')
    for frame = 17, 29 do
        f:frame(54 + (frame - 16) * 3)
        assert(f:visible('row1'), 'staggered descriptors retain independent freshness')
    end
    f:frame(96)
    assert(not f:visible('row1') and f:visible('row2'), 'the original guard runs when that descriptor is due')
    return { f = f, before = before, after = after }
end

local candidate = exercise('client/interaction_renderer.lua')
local staggered = exerciseStaggered('client/interaction_renderer.lua')
for _, name in ipairs({ 'exists', 'model', 'coords', 'offset', 'boneIndex', 'bonePosition' }) do
    assert((candidate.cold[name .. ':500'] or 0) == 1, name .. ' is shared once for an eight-row cold list')
end
for _, name in ipairs({ 'exists', 'coords', 'offset', 'bonePosition' }) do
    assert(candidate.warm[name .. ':500'] - candidate.cold[name .. ':500'] == 1,
        name .. ' refreshes once on the next pass')
end
assert(candidate.warm['model:500'] == candidate.cold['model:500'], 'model reads retain the existing cadence')
assert(candidate.deletedAfter['exists:500'] - candidate.deletedBefore['exists:500'] == 1, 'false existence results are shared')
assert(candidate.missingAfter['boneIndex:500'] - candidate.missingBefore['boneIndex:500'] == 1, 'missing-bone results are shared')
for _, name in ipairs({ 'coords', 'offset', 'bonePosition', 'boneIndex' }) do
    assert(candidate.rejectedAfter[name .. ':500'] == candidate.rejectedBefore[name .. ':500'], 'expectedModel guard precedes ' .. name)
end
for flag, name in pairs({ boneCoordsNil = 'bonePosition', coordsNil = 'coords', offsetNil = 'offset' }) do
    local failure = candidate.failures[flag]
    assert(failure.after[name .. ':500'] - failure.before[name .. ':500'] == 1, flag .. ' results are shared')
end
assert(staggered.after['bonePosition:500'] - staggered.before['bonePosition:500'] == 2,
    'different cached bone indices of the same named bone must not share positions')
assert(candidate.distinctAfter['offset:500'] - candidate.distinctBefore['offset:500'] == 2, 'distinct offsets stay distinct')
assert(candidate.distinctAfter['bonePosition:500'] - candidate.distinctBefore['bonePosition:500'] == 2, 'distinct bones stay distinct')
assert(candidate.distinctAfter['bonePosition:600'] - (candidate.distinctBefore['bonePosition:600'] or 0) == 1, 'entities stay distinct')
assert(candidate.playerAfter['coords:1'] - candidate.playerBefore['coords:1'] == 1, 'player coordinates are read once per pass')
for _, name in ipairs({ 'exists', 'model', 'coords', 'offset', 'boneIndex', 'bonePosition' }) do
    assert(candidate.capacityAfter[name .. ':500'] - candidate.capacityBefore[name .. ':500'] == 1,
        name .. ' is shared across owners at the sixteen-row capacity')
end
assert(candidate.capacityAfter['projection:'] - candidate.capacityBefore['projection:'] == 16, 'capacity does not cut projections')

if arg and arg[1] then
    local baseline = exercise(arg[1])
    local baselineStaggered = exerciseStaggered(arg[1])
    assert(encode(candidate.f.trace) == encode(baseline.f.trace), 'message, projection, cadence or visibility trace changed')
    assert(encode(staggered.f.trace) == encode(baselineStaggered.f.trace), 'staggered-model trace changed')
    print('baseline parity: identical complete messages, projections, presentation writes and registry states')
    local function total(counts, previous)
        local result = 0
        for _, name in ipairs({ 'exists', 'model', 'coords', 'offset', 'boneIndex', 'bonePosition' }) do
            result = result + (counts[name .. ':500'] or 0) - (previous and previous[name .. ':500'] or 0)
        end
        return result
    end
    print(('mock native counts, eight shared bone-offset rows: cold %d -> %d; warm %d -> %d; projection 8 -> 8 each pass')
        :format(total(baseline.cold), total(candidate.cold), total(baseline.warm, baseline.cold), total(candidate.warm, candidate.cold)))
end
print('interaction frame reads: sharing, freshness, geometry, model/bone invalidation, deletion, capacity, tiers and cleanup passed')
