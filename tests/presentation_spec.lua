local api, events, timers, threads = {}, {}, {}, {}
local invoking, now = 'chat', 1000
local definition
lib = {
    registerSettingsScript = function(_, value) definition = value; return true end,
    getSetting = function() return nil end,
    _hasModalSurface = function() return false end,
}
function exports(name, fn) api[name] = fn end
function GetInvokingResource() return invoking end
function GetCurrentResourceName() return 'cortex-lib' end
function GetGameTimer() return now end
function SetTimeout(_, fn) timers[#timers + 1] = fn end
function AddEventHandler(name, fn) events[name] = fn end
function TriggerEvent() end
function CreateThread(fn) threads[#threads + 1] = fn end
function GetActiveScreenResolution() return 1920, 1080 end
function GetSafeZoneSize() return 1 end
function IsPauseMenuActive() return false end
function Wait() coroutine.yield() end
dofile('client/presentation.lua')
local valid = { id = 'chat', x = 20, y = 20, width = 480, height = 350, fixed = false, priority = 85 }
assert(definition == nil, 'the retired Dynamic UI tab is no longer registered')
assert(api.setPresentationSurfaces({ valid }))
local s = api.getPresentation()
assert(s.surfaces[1].owner == 'chat' and s.surfaces[1].key == 'chat:chat')
assert(not api.setPresentationSurfaces({ valid }), 'must rate limit')
now = now + 200
assert(not api.setPresentationSurfaces({ valid, valid }), 'must reject duplicate ids')
assert(not api.setPresentationSurfaces({ bad = valid }), 'must reject object instead of array')
local nan = {}; for k,v in pairs(valid) do nan[k] = v end; nan.x = 0/0
assert(not api.setPresentationSurfaces({ nan }), 'must reject NaN')
invoking = 'hud'
assert(api.setPresentationSurfaces({ valid }))
assert(#api.getPresentation().surfaces == 2, 'same id in another owner must remain separate')
events.onClientResourceStop('chat')
assert(#api.getPresentation().surfaces == 1 and api.getPresentation().surfaces[1].owner == 'hud')
now = now + 200
assert(api.setPresentationSurfaces({}))
assert(#api.getPresentation().surfaces == 0, 'closing removes reservations')
local thread = coroutine.create(threads[1]); assert(coroutine.resume(thread))
assert(api.getPresentation().profile.accent == '#8fcbbf')
assert(api.getPresentation().profile.independent == nil, 'every resource follows the shared profile')
lib.getSetting = function(key)
    if key == 'dynamic_accent' then return '#9bbcd3' end
    if key == 'dynamic_opacity' then return 40 end
    if key == 'dynamic_motion' then return 'reduced' end
    if key == 'dynamic_layout' then return false end
    if key == 'dynamic_independent_chat' then return true end
end
events['cortex-lib:settingChanged']('dynamic_accent', '#9bbcd3', 'cortex')
local profile = api.getPresentation().profile
assert(profile.accent == '#9bbcd3' and profile.opacity == 65 and profile.motion == 'reduced' and profile.layout == false,
    'profile follows the Cortex tab values and clamps opacity')
assert(profile.independent == nil, 'retired independent keys are ignored')
-- A custom accent is used as typed when ink reads on it, and lightened when it would not.
lib.getSetting = function(key) if key == 'dynamic_accent' then return '#ff5a36' end end
events['cortex-lib:settingChanged']('dynamic_accent')
assert(api.getPresentation().profile.accent == '#ff5a36')
lib.getSetting = function(key) if key == 'dynamic_accent' then return '#10204a' end end
events['cortex-lib:settingChanged']('dynamic_accent')
local lightened = api.getPresentation().profile.accent
assert(lightened ~= '#10204a' and lightened:match('^#%x%x%x%x%x%x$') and tonumber(lightened:sub(6, 7), 16) > 0x4a,
    'a dark custom accent is lightened until ink text reads on it')
lib.getSetting = function() return nil end
events['cortex-lib:settingChanged']('dynamic_accent')
assert(api.getPresentation().profile.accent == '#8fcbbf', 'discard must restore profile')
print('presentation broker: validation, owner isolation, cleanup, and preview rollback passed')
