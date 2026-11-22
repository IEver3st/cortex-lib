-- Client-only presentation broker. Owners come from exports, never NUI payloads.
local owners, lastWrites = {}, {}
local revision, pending = 0, false
local profile = { accent = '#8fcbbf', opacity = 92, motion = 'system', layout = true }
local DESIGNS = { cortex = true, leonida = true, vi = true }
local design, designOwner = nil, nil
local viewport = { width = 1920, height = 1080, inset = 20 }
local modal = false
local settingsOpen = false
local settleToken, settled, waiting, quiet = 0, 0, nil, {}
local function finite(n) return type(n) == 'number' and n == n and math.abs(n) < 100000 end
local function owner() return GetInvokingResource() or GetCurrentResourceName() end
local function snapshot()
    local surfaces = {}
    for resource, entries in pairs(owners) do
        for _, entry in ipairs(entries) do
            local item = {}
            for k, v in pairs(entry) do item[k] = v end
            item.key = resource .. ':' .. item.id
            item.owner = resource
            surfaces[#surfaces + 1] = item
        end
    end
    return { v = 1, revision = revision, profile = profile, viewport = viewport, surfaces = surfaces, modal = modal or settingsOpen, settings = settingsOpen, settled = settled }
end
local function publish()
    if pending then return end
    pending = true
    SetTimeout(100, function()
        pending = false
        revision = revision + 1
        TriggerEvent('cortex-lib:presentation', snapshot())
    end)
end
local function settle(token)
    if token ~= settleToken or not waiting then return end
    for resource in pairs(waiting) do quiet[resource] = true end
    waiting = nil
    settled = token
    revision = revision + 1
    TriggerEvent('cortex-lib:presentation', snapshot())
end
local function answered(resource, token)
    if token ~= settleToken then return end
    quiet[resource] = nil
    if not waiting or not waiting[resource] then return end
    waiting[resource] = nil
    if not next(waiting) then settle(token) end
end
function lib._presentationSettle()
    if profile.layout == false then return end
    local asked, count = {}, 0
    for resource in pairs(owners) do
        if not quiet[resource] then asked[resource] = true; count = count + 1 end
    end
    if count == 0 then return end
    settleToken = settleToken + 1
    local token = settleToken
    waiting = asked
    TriggerEvent('cortex-lib:presentationSettle', token)
    SetTimeout(300, function() settle(token) end)
end
exports('getPresentation', snapshot)
local function write(resource, items, urgent)
    if type(items) ~= 'table' or #items > 16 then return false, 'invalid_surfaces' end
    local count, ids, clean = 0, {}, {}
    for k in pairs(items) do
        if type(k) ~= 'number' or k % 1 ~= 0 or k < 1 or k > #items then return false, 'invalid_surfaces' end
        count = count + 1
    end
    if count ~= #items then return false, 'invalid_surfaces' end
    for _, item in ipairs(items) do
        if type(item) ~= 'table' or type(item.id) ~= 'string' or #item.id > 64
            or not item.id:match('^[%w_-]+$') or ids[item.id]
            or not finite(item.x) or not finite(item.y) or not finite(item.width) or not finite(item.height)
            or item.width < 1 or item.height < 1 or item.width > 16384 or item.height > 16384
            or type(item.fixed) ~= 'boolean' or not finite(item.priority)
            or item.priority < 0 or item.priority > 100 then return false, 'invalid_surface' end
        ids[item.id] = true
        clean[#clean + 1] = { id = item.id, x = item.x, y = item.y, width = item.width,
            height = item.height, fixed = item.fixed, priority = item.priority }
    end
    -- An unchanged report would rebroadcast the whole snapshot to every
    -- Cortex NUI for nothing.
    local current = owners[resource]
    if current and #current == #clean then
        local same = true
        for i = 1, #clean do
            local a, b = current[i], clean[i]
            if a.id ~= b.id or a.x ~= b.x or a.y ~= b.y or a.width ~= b.width or a.height ~= b.height
                or a.fixed ~= b.fixed or a.priority ~= b.priority then same = false; break end
        end
        if same then return true end
    end
    local now = GetGameTimer()
    local elapsed = lastWrites[resource] and now - lastWrites[resource]
    if not urgent and elapsed and elapsed >= 0 and elapsed < 100 then return false, 'rate_limited' end
    local total = 0
    for _ in pairs(owners) do total = total + 1 end
    if not owners[resource] and total >= 32 then return false, 'capacity' end
    lastWrites[resource] = now
    owners[resource] = clean
    if not urgent then publish() end
    return true
end
exports('setPresentationSurfaces', function(items, token)
    local resource = owner()
    local current = type(token) == 'number' and token == settleToken
    local ok, err = write(resource, items, current and waiting ~= nil and waiting[resource] == true)
    if current then answered(resource, token) end
    return ok, err
end)
-- Settings is a full-screen page: every Cortex NUI hides its HUD while it is
-- open (dynamic-ui.js adds cortex-settings-active). Pushed on the transition,
-- not left to the one-second modal poll.
function lib._presentationSettingsOpen(open)
    open = open == true
    if open == settingsOpen then return end
    settingsOpen = open
    publish()
end
AddEventHandler('onClientResourceStop', function(resource)
    if owners[resource] then owners[resource], lastWrites[resource] = nil, nil; publish() end
    quiet[resource] = nil
    if waiting and waiting[resource] then
        waiting[resource] = nil
        if not next(waiting) then settle(settleToken) end
    end
    if designOwner == resource then
        design, designOwner = nil, nil
        profile.design = nil
        publish()
    end
end)
exports('setPresentationDesign', function(id)
    local resource = owner()
    if id == nil then
        if designOwner ~= resource then return true end
        design, designOwner = nil, nil
    elseif type(id) ~= 'string' or not DESIGNS[id] then
        return false, 'invalid_design'
    else
        if design == id and designOwner == resource then return true end
        design, designOwner = id, resource
    end
    profile.design = design
    publish()
    return true
end)

-- Shared appearance comes from the Cortex settings tab (imports/settings). Every
-- participating resource follows it; there is no per-resource opt-out.
-- The accent carries ink text (selected rows, keycaps, tags). A custom colour
-- too dark for that is lightened toward paper until ink reads on it.
local MIN_LUMINANCE = 0.22
local function readableAccent(hex)
    local r, g, b = tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
    local function linear(channel)
        channel = channel / 255
        return channel <= 0.03928 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
    end
    for _ = 1, 20 do
        if 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) >= MIN_LUMINANCE then break end
        r, g, b = r + (240 - r) * 0.12, g + (240 - g) * 0.12, b + (233 - b) * 0.12
    end
    return ('#%02x%02x%02x'):format(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

local function refreshProfile()
    local accent = lib.getSetting('dynamic_accent')
    local opacity = tonumber((lib.getSetting('dynamic_opacity')))
    local motion = lib.getSetting('dynamic_motion')
    profile = {
        accent = type(accent) == 'string' and accent:match('^#%x%x%x%x%x%x$') and readableAccent(accent) or '#8fcbbf',
        opacity = math.max(65, math.min(100, opacity or 92)),
        motion = (motion == 'reduced' or motion == 'full') and motion or 'system',
        layout = lib.getSetting('dynamic_layout') ~= false,
        design = design,
    }
    publish()
end
AddEventHandler('cortex-lib:settingChanged', function(key)
    if type(key) == 'string' and key:sub(1, 8) == 'dynamic_' then refreshProfile() end
end)
CreateThread(function()
    refreshProfile()
    while true do
        local width, height = GetActiveScreenResolution()
        local safe = tonumber(GetSafeZoneSize()) or 1
        local nextViewport = { width = width, height = height,
            inset = math.max(12, math.floor(math.max(width, height) * (1 - math.max(0.8, math.min(1, safe))) / 2)) }
        if nextViewport.width ~= viewport.width or nextViewport.height ~= viewport.height or nextViewport.inset ~= viewport.inset then
            viewport = nextViewport; publish()
        end
        local nextModal = IsPauseMenuActive() or lib._hasModalSurface()
        if nextModal ~= modal then modal = nextModal; publish() end
        Wait(1000)
    end
end)
