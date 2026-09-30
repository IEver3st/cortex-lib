-- Include once in each resource with a Dynamic UI browser adapter.
local function sync()
    local ok, data = pcall(function() return exports['cortex-lib']:getPresentation() end)
    if ok then SendNUIMessage({ action = 'cortex:presentation', data = data }) end
end
AddEventHandler('cortex-lib:presentation', function(data)
    SendNUIMessage({ action = 'cortex:presentation', data = data })
end)
RegisterNUICallback('cortexPresentationReady', function(_, cb)
    sync()
    cb({ ok = true })
end)
RegisterNUICallback('cortexPresentationSurfaces', function(data, cb)
    local called, ok, err = pcall(function()
        return exports['cortex-lib']:setPresentationSurfaces(type(data) == 'table' and data.surfaces or nil)
    end)
    if called and ok == true then cb({ ok = true })
    else cb({ ok = false, error = called and err or 'unavailable' }) end
end)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'cortex-lib' then
        SendNUIMessage({ action = 'cortex:presentationReset' })
        sync()
    end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == 'cortex-lib' then SendNUIMessage({ action = 'cortex:presentationReset' }) end
end)
