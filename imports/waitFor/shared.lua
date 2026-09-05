local function waitFor(cb, errorMessage, timeout)
    if type(cb) ~= 'function' then error('cortex-lib.waitFor: cb must be a function') end
    timeout = timeout or 1000
    if type(timeout) ~= 'number' or timeout ~= timeout or timeout == math.huge or timeout == -math.huge
        or timeout < 0 or timeout > 600000
    then
        error('cortex-lib.waitFor: timeout must be a finite number between 0 and 600000 ms')
    end
    timeout = math.floor(timeout)
    local value = cb()
    
    if value ~= nil then
        return value
    end
    
    local usesGameTimer = type(GetGameTimer) == 'function'
    local start = usesGameTimer and GetGameTimer() or os.time() * 1000
    
    while value == nil do
        local now = usesGameTimer and GetGameTimer() or os.time() * 1000
        local elapsed = now - start
        if usesGameTimer and elapsed < 0 then elapsed = elapsed + 4294967296 end
        
        if elapsed >= timeout then
            if errorMessage then
                error(errorMessage)
            end
            return nil
        end
        
        if type(Wait) ~= 'function' then error('cortex-lib.waitFor: Wait is unavailable') end
        Wait(0)
        
        value = cb()
    end
    
    return value
end

exports('waitFor', waitFor)

lib.waitFor = waitFor

return waitFor
