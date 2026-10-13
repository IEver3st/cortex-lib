-- Explicit, user-run capture only (port of cortex-hud's diagnostics). No
-- worker or profiler natives run during normal gameplay. Scopes must never
-- span a Wait/yield. Code reads lib._profile.enabled before entering a scope.
local Profile = { enabled = false, enter = ProfilerEnterScope, leave = ProfilerExitScope }
lib._profile = Profile
local busy = false
local generation = 0

RegisterCommand('cortex_lib_profile', function(_, args)
    if args and args[1] == 'off' then
        generation = generation + 1
        Profile.enabled, busy = false, false
        print('[cortex-lib] Profiler labels disabled. Any native recording is unchanged.')
        return
    end
    if busy then
        print('[cortex-lib] Labels already armed. Run profiler record 500 directly in F8.')
        return
    end
    if type(ProfilerIsRecording) ~= 'function' or type(Profile.enter) ~= 'function'
        or type(Profile.leave) ~= 'function' then
        print('[cortex-lib] Profiler natives are unavailable on this client.')
        return
    end
    if ProfilerIsRecording() then
        print('[cortex-lib] Another profiler capture is running; let it finish first.')
        return
    end

    busy = true
    generation = generation + 1
    local captureGeneration = generation
    local armedAt = GetGameTimer()
    Profile.enabled = true
    -- Resource ExecuteCommand may not access native developer commands.
    print('[cortex-lib] Labels armed for 30 seconds. Run profiler record 500 directly in F8, then close F8.')
    CreateThread(function()
        local ok, err = xpcall(function()
            while not ProfilerIsRecording() do
                if captureGeneration ~= generation then return end
                local now = GetGameTimer()
                if now < armedAt or now - armedAt >= 30000 then
                    print('[cortex-lib] No recording detected; labels disabled.')
                    return
                end
                Wait(100)
            end
            if captureGeneration ~= generation then return end
            local startedAt = GetGameTimer()
            while ProfilerIsRecording() do
                if captureGeneration ~= generation then return end
                local now = GetGameTimer()
                if now < startedAt or now - startedAt >= 120000 then
                    print('[cortex-lib] Capture timed out. Labels disabled; inspect profiler status manually.')
                    return
                end
                Wait(250)
            end
            if captureGeneration ~= generation then return end
            Profile.enabled = false
            print(('[cortex-lib] Recording finished. Run directly in F8: profiler saveJSON cortex-lib-%d.json'):format(startedAt))
        end, debug.traceback)
        if captureGeneration == generation then Profile.enabled, busy = false, false end
        if not ok then print('[cortex-lib] Capture failed: ' .. tostring(err)) end
    end)
end, false)
