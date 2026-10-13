-- presentation-client.lua: a page with only fixed surfaces is sent a snapshot
-- only when something it uses changes; a page with a movable surface gets all.
local sent, handlers, callbacks = {}, {}, {}
local function snapshot(revision, surfaces, accent)
    return { v = 1, revision = revision, profile = { accent = accent or '#8fcbbf', opacity = 92, motion = 'system', layout = true },
        viewport = { width = 1920, height = 1080, inset = 20 }, surfaces = surfaces or {}, modal = false, settings = false }
end
local current = snapshot(1)
function SendNUIMessage(message) sent[#sent + 1] = message end
function AddEventHandler(name, fn) handlers[name] = fn end
function RegisterNUICallback(name, fn) callbacks[name] = fn end
exports = setmetatable({}, { __index = function() return {
    getPresentation = function() return current end,
    setPresentationSurfaces = function() return true end,
} end })
dofile('presentation-client.lua')
local function reply() local result; return function(value) result = value end, function() return result end end

local cb = reply()
callbacks.cortexPresentationReady({}, cb)
assert(#sent == 1 and sent[1].action == 'cortex:presentation', 'ready always gets a snapshot')

local hud = { key = 'hud:speed-0', owner = 'cortex-hud', id = 'speed-0', x = 0, y = 0, width = 10, height = 10, fixed = true, priority = 100 }
local cam = { key = 'polcam:camera-0', owner = 'cortex-polcam', id = 'camera-0', x = 0, y = 0, width = 10, height = 10, fixed = true, priority = 100 }
handlers['cortex-lib:presentation'](snapshot(2, { hud }))
assert(#sent == 2, 'a new owner changes what the page uses')
for revision = 3, 12 do
    local moved = {}; for k, v in pairs(cam) do moved[k] = v end; moved.width = revision
    handlers['cortex-lib:presentation'](snapshot(revision, { hud, moved }))
end
assert(#sent == 3, 'surface geometry changes reach a fixed-only page once, for the new owner')
handlers['cortex-lib:presentation'](snapshot(13, { hud, cam }, '#d8ba82'))
assert(#sent == 4, 'an accent change always reaches the page')

callbacks.cortexPresentationSurfaces({ surfaces = { { id = 'receiver-0', x = 0, y = 0, width = 5, height = 5, fixed = false, priority = 80 } } }, reply())
handlers['cortex-lib:presentation'](snapshot(14, { hud, cam }, '#d8ba82'))
handlers['cortex-lib:presentation'](snapshot(15, { hud, cam }, '#d8ba82'))
assert(#sent == 6, 'a page with a movable surface receives every snapshot')
callbacks.cortexPresentationSurfaces({ surfaces = {} }, reply())
handlers['cortex-lib:presentation'](snapshot(16, { hud, cam }, '#d8ba82'))
assert(#sent == 6, 'the page stops receiving geometry once its movable surface is gone')

handlers.onClientResourceStop('cortex-lib')
assert(sent[#sent].action == 'cortex:presentationReset')
local count = #sent
handlers['cortex-lib:presentation'](snapshot(17, { hud, cam }, '#d8ba82'))
assert(#sent == count + 1, 'after a cortex-lib reset the next snapshot is always sent')
print('presentation client: fixed-only pages skip geometry-only snapshots; ready, accent, owners, movable surfaces and reset passed')
