-- Run from cortex-lib: lua tests/interaction_world_dui_spec.lua
-- World prompts drawn from the DUI (client/interaction_dui.lua) with the real
-- registry and renderer: the NUI layer until the DUI has painted the content,
-- then one native sprite per list at its anchor and no per-frame NUI or DUI
-- traffic while the camera turns; content changes as DUI messages; new cell
-- content shown only once painted; flip hysteresis; held cells; the wheel
-- hint; the cell cap; rescale; cleanup; and the NUI fallback.
-- Natives are deterministic stubs. This proves no FiveM or CEF behaviour.

-- Deterministic JSON stand-in: sorted keys, so equal states encode equally.
local function encode(value)
    local kind = type(value)
    if kind == 'string' then return string.format('%q', value) end
    if kind ~= 'table' then return tostring(value) end
    if #value > 0 or next(value) == nil then
        local parts = {}
        for index = 1, #value do parts[index] = encode(value[index]) end
        return '[' .. table.concat(parts, ',') .. ']'
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = {}
    for index, key in ipairs(keys) do parts[index] = key .. ':' .. encode(value[key]) end
    return '{' .. table.concat(parts, ',') .. '}'
end

local s

local function boot(options)
    options = options or {}
    s = {
        exported = {}, handlers = {}, callbacks = {}, threads = {}, messages = {},
        created = {}, destroyed = {}, sent = {}, sprites = {}, prints = {}, decoded = {},
        clock = 1000, camX = 0.5, available = false, textures = 0, width = 1920, height = 1080,
        player = { x = 0.0, y = 0.0, z = 0.0 }, invoking = 'emotes',
    }
    lib = {
        isInternalResource = function() return true end,
        cache = { ped = 1 },
        getSetting = function() return nil end,
    }
    exports = setmetatable({}, {
        __call = function(_, name, callback) s.exported[name] = callback end,
        __index = function() return { getPresentation = function() return {} end } end,
    })
    json = { encode = function(value) local text = encode(value); s.decoded[text] = value; return text end }
    function print(...) s.prints[#s.prints + 1] = table.concat({ ... }, ' ') end
    function GetInvokingResource() return s.invoking end
    function GetCurrentResourceName() return 'cortex-lib' end
    function GetConvarInt(_, default) return options.convar or default end
    function AddEventHandler(name, callback)
        s.handlers[name] = s.handlers[name] or {}
        table.insert(s.handlers[name], callback)
    end
    function TriggerEvent(name, ...)
        for _, callback in ipairs(s.handlers[name] or {}) do callback(...) end
    end
    function RegisterNUICallback(name, callback) s.callbacks[name] = callback end
    function CreateThread(callback) s.threads[#s.threads + 1] = coroutine.create(callback) end
    function Wait(ms) coroutine.yield(ms) end
    function SendNUIMessage(message) s.messages[#s.messages + 1] = message end
    function GetSafeZoneSize() return 1.0 end
    function GetActiveScreenResolution() return s.width, s.height end
    function GetGameTimer() return s.clock end
    function PlayerPedId() return 1 end
    function PlayerId() return 0 end
    function DoesEntityExist(entity) return entity == 1 end
    function GetEntityCoords() return s.player end
    function GetEntityModel() return 1 end
    -- A camera turn moves every anchor's projection sideways.
    function World3dToScreen2d(x, _, z) return true, s.camX + x * 0.1, 0.5 + z * 0.1 end
    function DisableControlAction() end
    function IsDisabledControlJustPressed() return false end
    function IsPauseMenuActive() return false end
    function IsPlayerFreeAiming() return false end
    function CreateRuntimeTxd(name) return name end
    function CreateRuntimeTexture() return 'dot' end
    function SetRuntimeTexturePixel() end
    function CommitRuntimeTexture() end
    function DrawSprite() end
    function CreateDui(url, width, height)
        s.created[#s.created + 1] = { url = url, width = width, height = height }
        return 'dui' .. #s.created
    end
    function IsDuiAvailable() return s.available end
    function GetDuiHandle(object) return 'handle:' .. object end
    function CreateRuntimeTextureFromDuiHandle() s.textures = s.textures + 1; return 7 end
    function SendDuiMessage(object, text) s.sent[#s.sent + 1] = { object = object, text = text, value = s.decoded[text] } end
    function DestroyDui(object) s.destroyed[#s.destroyed + 1] = object end
    function SetDrawOrigin(x, y, z) s.origin = { x = x, y = y, z = z } end
    function DrawSpriteUv(txd, texture, x, y, width, height, u1, v1, u2, v2)
        s.sprites[#s.sprites + 1] = { txd = txd, texture = texture, x = x, y = y, width = width, height = height,
            u1 = u1, v1 = v1, u2 = u2, v2 = v2, origin = s.origin }
    end
    function ClearDrawOrigin() s.origin = nil end

    dofile('imports/interaction/client.lua')
    dofile('client/interaction_dui.lua')
    dofile('client/interaction_renderer.lua')
    s.callbacks.interactionReady({}, function(data) assert(data.ok) end)
end

local function as(owner, name, ...)
    local previous = s.invoking
    s.invoking = owner
    local a, b = s.exported[name](...)
    s.invoking = previous
    return a, b
end

local function frame(ms)
    s.clock = s.clock + (ms or 16)
    local co = s.threads[#s.threads]
    assert(coroutine.status(co) ~= 'dead', 'projection worker must be running')
    local ok, waitMs = coroutine.resume(co)
    assert(ok, waitMs)
    return waitMs
end

local function lastWorld()
    for index = #s.messages, 1, -1 do
        local message = s.messages[index]
        if message.action == 'interaction:world' then return message.data.items end
    end
    return nil
end

local function worldTraffic(from)
    local count = 0
    for index = from + 1, #s.messages do
        local action = s.messages[index].action
        if action == 'interaction:world' or action == 'interaction:worldMove' then count = count + 1 end
    end
    return count
end

local function messagesOf(action, from)
    local list = {}
    for index = from + 1, #s.messages do
        if s.messages[index].action == action then list[#list + 1] = s.messages[index] end
    end
    return list
end

local function lastState() return s.sent[#s.sent].value.data end

-- The page's report: it listens (revision 0) or has painted a revision.
local function report(dui, revision)
    s.callbacks.interactionWorldReady({ dui = dui, revision = revision }, function(data) assert(data.ok) end)
end

-- The page paints the last state sent to it.
local function paint(dui)
    for index = #s.sent, 1, -1 do
        if s.sent[index].object == 'dui' .. dui then return report(dui, s.sent[index].value.data.revision) end
    end
end

local function near(a, b) return math.abs(a - b) < 1e-6 end

local function prompt(id, key, x, more)
    local item = { id = id, label = id, key = key, anchor = { type = 'world', x = x, y = 0.0, z = 0.0, maxDistance = 3.5 } }
    for field, value in pairs(more or {}) do item[field] = value end
    return item
end

-- A. A page that never reports: the loading DUI is fed while the NUI layer
--    draws, takes over after the warm-up, and is resent to on timers.
boot()
TriggerEvent('cortex-lib:presentation', { profile = { accent = '#8fb2de', opacity = 92, motion = 'full' } })
assert(as('emotes', 'showInteraction', prompt('Sit', 'E', 1.0)))
frame()
assert(#s.created == 1 and s.created[1].url == 'nui://cortex-lib/ui/world.html?resource=cortex-lib&dui=1',
    'the world DUI is created once anchored prompts exist')
assert(s.created[1].width == 960 and s.created[1].height == 864, '2 x 3 cells of 480 x 288 prompt units at 1080p')
assert(#lastWorld() == 1 and #s.sprites == 0, 'until the DUI is available the NUI layer draws the prompt')

s.available = true
frame()
assert(s.textures == 1, 'a runtime texture is made from the DUI handle once')
assert(#s.sent == 1 and s.sent[1].object == 'dui1', 'the loading DUI gets the content at once')
local state = lastState()
local cell = state.cells[1]
assert(state.revision == 1 and cell and cell.group == 'emotes:Sit' and cell.flipped == false
    and cell.items[1].label == 'Sit' and cell.items[1].active == true, 'the list is published to its cell')
assert(state.u == 1 and state.scale == 1 and state.cellWidth == 480 and state.cellHeight == 288
    and state.anchorX == 48 and state.anchorRight == 432 and state.anchorY == 60 and state.columns == 2,
    'atlas geometry in texture pixels at 1080p')
assert(state.theme.accent == '#8fb2de', 'the shared accent reaches the DUI')
assert(cell.items[1].x == 0 and cell.items[1].y == 0, 'positions never cross into the DUI')
assert(#s.sprites == 0 and #lastWorld() == 1, 'the NUI layer draws while the page loads')

frame(260)
assert(#s.sent == 2 and s.sent[2].text == s.sent[1].text, 'a quick resend (messages before the page listens are lost)')
frame(1300)
assert(#lastWorld() == 0, 'after the warm-up the NUI world layer is emptied')
assert(#s.sprites == 1, 'and the prompt is drawn natively in the same pass')
local sprite = s.sprites[1]
assert(sprite.txd == 'cortex_lib_world' and sprite.texture == 'prompts1', 'drawn from the DUI texture')
assert(sprite.origin and sprite.origin.x == 1.0 and sprite.origin.y == 0.0 and sprite.origin.z == 0.0,
    'drawn at the anchor through SetDrawOrigin (resolved at render time)')
assert(near(sprite.width, 480 / 1920) and near(sprite.height, 288 / 1080), 'one cell at 1:1 texture pixels')
assert(near(sprite.u1, 0) and near(sprite.v1, 0) and near(sprite.u2, 0.5) and near(sprite.v2, 1 / 3),
    'the UVs select the first cell')
assert(near(sprite.x, (240 - 48) / 1920) and near(sprite.y, (144 - 60) / 1080),
    'the cell is offset so its anchor point sits on the draw origin')
assert(as('emotes', 'isInteractionVisible', 'Sit'), 'a drawn prompt is visible')
assert(#s.sent == 2, 'the handover itself sends nothing')

frame(3000)
assert(#s.sent == 3, 'quick resends for the first four seconds')
frame(300)
assert(#s.sent == 3, 'then slower')
frame(800)
assert(#s.sent == 4, 'about once a second while a prompt is shown')

-- B. A page that reports: the handover follows its first painted state.
boot()
assert(as('emotes', 'showInteraction', prompt('Sit', 'E', 1.0)))
frame()
s.available = true
frame()
report(1, 0)
frame()
assert(#s.sent == 2, 'a page that starts listening gets the state again at once')
assert(#s.sprites == 0 and #lastWorld() == 1, 'the NUI layer draws until the state is painted')
paint(1)
frame()
assert(#lastWorld() == 0 and #s.sprites == 1, 'the DUI takes over as soon as its page has painted, before the warm-up')

-- Camera turns: drawn every frame, no NUI or DUI traffic at all.
local nuiBefore, duiBefore, spritesBefore = #s.messages, #s.sent, #s.sprites
for step = 1, 8 do
    s.camX = 0.5 - step * 0.01
    assert(frame() == 0, 'drawn prompts keep the worker on every frame')
end
frame(2000)
assert(worldTraffic(nuiBefore) == 0, 'camera motion sends no NUI world messages')
assert(#s.sent == duiBefore, 'a painted state is never resent')
assert(#s.sprites == spritesBefore + 9, 'one sprite per frame')
assert(s.sprites[#s.sprites].origin.x == 1.0, 'still anchored to the same world point')

-- A content change is one DUI message; the cell keeps drawing meanwhile.
nuiBefore, duiBefore, spritesBefore = #s.messages, #s.sent, #s.sprites
assert(as('emotes', 'showInteraction', prompt('Sit', 'E', 1.0, { label = 'Sit down' })))
frame()
assert(#s.sent == duiBefore + 1 and lastState().cells[1].items[1].label == 'Sit down', 'the new label is published')
assert(#s.sprites == spritesBefore + 1, 'the same list stays drawn while its label repaints')
assert(worldTraffic(nuiBefore) == 0, 'content changes do not touch the NUI layer')
frame(300)
assert(#s.sent == duiBefore + 2, 'resent until the page reports painting it')
paint(1)
frame(300)
assert(#s.sent == duiBefore + 2, 'and not after')

-- Flip with hysteresis; a flipped cell shows once the flip is painted.
s.camX = 0.625 -- screen x 0.725 (a whole pixel, so no snap offset)
spritesBefore = #s.sprites
frame()
assert(lastState().cells[1].flipped == true, 'past 0.70 the list flips left')
frame()
assert(#s.sprites == spritesBefore, 'not drawn until the flip is painted')
paint(1)
frame()
sprite = s.sprites[#s.sprites]
assert(#s.sprites == spritesBefore + 1 and near(sprite.x, (240 - 432) / 1920), 'then drawn from the right anchor')
s.camX = 0.57 -- 0.67
duiBefore = #s.sent
frame()
assert(#s.sent == duiBefore and #s.sprites == spritesBefore + 2, 'between 0.66 and 0.70 nothing changes')
s.camX = 0.55 -- 0.65
frame()
assert(lastState().cells[1].flipped == false, 'below 0.66 it flips back')
paint(1)
s.camX = 0.5
frame()

-- A focused list owns the wheel: its hint goes to the NUI, which has no world items.
nuiBefore = #s.messages
assert(as('emotes', 'showInteraction', prompt('Lie', 'E', 1.0)))
frame()
paint(1)
frame()
local hints = messagesOf('interaction:worldHint', nuiBefore)
assert(#hints == 1 and hints[1].data.show == true, 'the wheel hint is shown once')
assert(as('emotes', 'hideInteraction', 'Lie'))
frame()
hints = messagesOf('interaction:worldHint', nuiBefore)
assert(#hints == 2 and hints[2].data.show == false, 'and hidden with the choice')
paint(1)
frame()

-- A released cell keeps its content: the list comes straight back. (An
-- out-of-range prompt keeps the worker running while nothing is in range.)
assert(as('emotes', 'showInteraction', prompt('Far', 'F', 100.0)))
frame()
duiBefore, spritesBefore = #s.sent, #s.sprites
assert(as('emotes', 'hideInteraction', 'Sit'))
frame()
assert(#s.sprites == spritesBefore and #s.sent == duiBefore, 'hidden: nothing drawn, nothing sent')
assert(as('emotes', 'showInteraction', prompt('Sit', 'E', 1.0, { label = 'Sit down' })))
frame(100)
assert(#s.sprites == spritesBefore + 1 and #s.sent == duiBefore, 'back within the hold: drawn at once, no repaint')
assert(as('emotes', 'hideInteraction', 'Sit'))
frame()
frame(500)
assert(lastState().cells[1] == false, 'after the hold the cell is cleared in the DUI')
paint(1)

-- Six cells: a seventh list is not drawn, so it is not visible.
local seven = {}
for index = 1, 7 do seven[index] = prompt('P' .. index, string.char(64 + index), index - 4.0) end
assert(as('emotes', 'setInteractions', seven))
spritesBefore = #s.sprites
frame()
assert(#s.sprites == spritesBefore, 'new cells wait for their first paint')
paint(1)
frame()
assert(#s.sprites == spritesBefore + 6, 'six lists are drawn')
local visible = 0
for index = 1, 7 do
    if as('emotes', 'isInteractionVisible', 'P' .. index) then visible = visible + 1 end
end
assert(visible == 6 and not as('emotes', 'isInteractionVisible', 'P7'), 'the undrawn seventh list is not visible')
local used = {}
for index = spritesBefore + 1, #s.sprites do
    used[s.sprites[index].u1 .. ':' .. s.sprites[index].v1] = true
end
local distinct = 0
for _ in pairs(used) do distinct = distinct + 1 end
assert(distinct == 6, 'each list has its own cell')

-- Rescale: a new DUI is fed while the old one draws, then replaces it.
assert(as('emotes', 'setInteractions', { prompt('Sit', 'E', 1.0) }))
frame()
paint(1)
frame()
TriggerEvent('cortex-lib:settingChanged', 'uiScale', 125)
frame()
frame(500)
assert(#s.created == 2 and s.created[2].url:find('dui=2', 1, true)
    and s.created[2].width == 1200 and s.created[2].height == 1080, 'a DUI at the new size once the size is stable')
frame()
assert(s.sent[#s.sent].object == 'dui2' and lastState().cellWidth == 600, 'the new DUI gets the content')
assert(s.sprites[#s.sprites].texture == 'prompts1', 'the old DUI keeps drawing meanwhile')
report(2, 0)
paint(2)
frame()
sprite = s.sprites[#s.sprites]
assert(sprite.texture == 'prompts2' and near(sprite.width, 600 / 1920), 'then the new one draws, 1:1')
assert(#s.destroyed == 0, 'the old DUI outlives the frames that drew it')
frame(300)
assert(s.destroyed[1] == 'dui1', 'and is destroyed after')

-- Stop destroys the DUI.
TriggerEvent('onClientResourceStop', 'cortex-lib')
assert(s.destroyed[#s.destroyed] == 'dui2', 'the DUI is destroyed with the resource')

-- C. A DUI that never becomes available leaves the NUI layer in charge.
boot()
assert(as('emotes', 'showInteraction', prompt('Sit', 'E', 1.0)))
frame()
frame(8001)
assert(s.destroyed[1] == 'dui1' and s.prints[1]:find('NUI layer', 1, true), 'gives up with one message')
frame()
frame(9000)
assert(#s.created == 1, 'no retry loop')
assert(#lastWorld() == 1 and #s.sprites == 0, 'the NUI layer keeps drawing')

-- D. The convar turns the DUI off.
boot({ convar = 0 })
assert(as('emotes', 'showInteraction', prompt('Sit', 'E', 1.0)))
frame()
assert(#s.created == 0 and #lastWorld() == 1, 'cortex_lib_world_dui 0 keeps the NUI layer')

io.write('interaction world DUI: PASS\n')
