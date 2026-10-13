-- Include once in each resource with a Dynamic UI browser adapter.
-- Every surface change anywhere is broadcast to every consumer, and each
-- SendNUIMessage of the snapshot costs hundreds of microseconds. A page whose
-- own surfaces are all fixed only uses the profile, viewport, modal/settings
-- flags and which owners are present, so it is sent a snapshot only when one
-- of those changes. A page that reported a movable surface gets every one.
local lastKey, needsLayout = nil, false

local function pageKey(data)
    local profile = type(data.profile) == 'table' and data.profile or {}
    local viewport = type(data.viewport) == 'table' and data.viewport or {}
    local owners, seen = {}, {}
    if type(data.surfaces) == 'table' then
        for _, surface in ipairs(data.surfaces) do
            local owner = type(surface) == 'table' and surface.owner
            if type(owner) == 'string' and not seen[owner] then
                seen[owner] = true
                owners[#owners + 1] = owner
            end
        end
    end
    table.sort(owners)
    return table.concat({
        tostring(profile.accent), tostring(profile.opacity), tostring(profile.motion), tostring(profile.layout),
        tostring(viewport.width), tostring(viewport.height), tostring(viewport.inset),
        tostring(data.modal), tostring(data.settings), table.concat(owners, ','),
    }, '|')
end

local function forward(data, force)
    if type(data) ~= 'table' then return end
    local key = pageKey(data)
    if not force and not needsLayout and key == lastKey then return end
    lastKey = key
    SendNUIMessage({ action = 'cortex:presentation', data = data })
end

local function sync()
    local ok, data = pcall(function() return exports['cortex-lib']:getPresentation() end)
    if ok then forward(data, true) end
end
AddEventHandler('cortex-lib:presentation', function(data)
    forward(data, false)
end)
RegisterNUICallback('cortexPresentationReady', function(_, cb)
    sync()
    cb({ ok = true })
end)
RegisterNUICallback('cortexPresentationSurfaces', function(data, cb)
    local surfaces = type(data) == 'table' and data.surfaces or nil
    local movable = false
    if type(surfaces) == 'table' then
        for _, surface in ipairs(surfaces) do
            if type(surface) == 'table' and surface.fixed == false then movable = true; break end
        end
    end
    needsLayout = movable
    local called, ok, err = pcall(function()
        return exports['cortex-lib']:setPresentationSurfaces(surfaces)
    end)
    if called and ok == true then cb({ ok = true })
    else cb({ ok = false, error = called and err or 'unavailable' }) end
end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'cortex-lib' then
        lastKey = nil
        SendNUIMessage({ action = 'cortex:presentationReset' })
        sync()
    end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == 'cortex-lib' then
        lastKey = nil
        SendNUIMessage({ action = 'cortex:presentationReset' })
    end
end)
