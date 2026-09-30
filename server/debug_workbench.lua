-- Read-only callback probe. The callback transport owns argument limits and
-- per-player rate limiting; no caller-supplied event/command/resource is invoked.
if GetConvarInt('cortex_debug', 0) ~= 1 then return end

lib.callback.register('cortex-lib:debugProbe',function(_,probe)
    if probe~='cortexdebug' then return nil,'invalid_probe' end
    return {ok=true,probe='cortexdebug'}
end)
