# Placement preview

`lib.placement` is a lazy client module executed in the consumer's context. It owns one collisionless local ghost per consumer and returns presentation data only. It never consumes items, creates network objects, or authorizes a placement.

```lua
local result = lib.placement.preview({
    model = 'prop_roadcone02a', maxDistance = 8, minNormalZ = 0.85,
    heading = 0, timeoutMs = 60000, modelTimeoutMs = 4000,
})
if result.ok then
    -- Send the approved definition ID and transform to your own server.
    -- Recheck character, permission, inventory, model, bucket, distance,
    -- surface/footprint and existing props before committing anything.
end
```

Call `preview` from a coroutine. Returns `{ok=true,data={model,coords,normal,heading}}` or `{ok=false,error={code}}`. Ordinary gameplay calls never open NUI or take focus. The ghost is grounded by the configured model's minimum Z, remains upright, and rejects normals below the threshold; this does not prove a whole footprint is free or detect every collision.

`cancel(reason?)` deletes the current ghost immediately and returns whether a preview was active. `isBusy()` is local observation. Death, vehicle/swimming, pause/NUI focus, character unload, owner/Lib stop, timeout and every failure clean the ghost and release the requested model/help. Repeated cancellation is safe; late results cannot resurrect the object.

`loadModel(model,timeoutMs=4000,cancelled?)` returns a loaded hash or `nil,reason`; caller releases successful models with `SetModelAsNoLongerNeeded`. Requests time out and reject invalid model/timeout values. Preview rays are asynchronous, at most 20 starts/second, with a 200 ms probe deadline and 250 ms maximum sample age. Input and cancellation run locally each active frame; no network or database work occurs.

Bindings register once per consumer: Place LMB, Cancel Backspace, Rotate Left/Right. They can be rebound in FiveM; A/B and D-pad remain controller fallbacks. `bindings={confirm,cancel,left,right}` sets first-use defaults; `help` may supply accurate labels for an operator's customized bindings. Combat controls are suppressed only during preview. Consumers should lower active equipment and remove conflicting task prompts before placing.

Tests establish deterministic cleanup, model deadlines and sample validity with native fixtures. Native geometry, pad bindings, surface suitability and model grounding still require the user's in-game acceptance.
