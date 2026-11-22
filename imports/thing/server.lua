local HOST = rawget(_G, 'CortexThingHost') or 'cortex-lib'

local handlers = {}

local function dispatcher(thingId)
    return function(kind, key, verbId, src)
        local def = handlers[thingId]
        if not def then return nil end

        if kind == 'coords' then
            local coords, bucket = def.coords(key)
            if not coords then return nil end
            return coords.x, coords.y, coords.z, bucket
        end

        local verb = def.verbs[verbId]
        if not verb then return false end
        if type(verb.run) ~= 'function' then return true end
        return verb.run(src, key)
    end
end

local thing = {}

function thing.serve(thingId, def)
    if type(def) ~= 'table' or type(def.coords) ~= 'function' or type(def.verbs) ~= 'table' then
        error('lib.thing.serve needs coords(key) and verbs', 2)
    end

    local plain = {}
    for verbId, verb in pairs(def.verbs) do
        plain[verbId] = { range = verb.range, cooldown = verb.cooldown, lock = verb.lock }
    end

    handlers[thingId] = def
    local ok, err = exports[HOST]:thingServe(thingId, plain, dispatcher(thingId))
    if not ok then error(('lib.thing.serve(%s): %s'):format(tostring(thingId), tostring(err)), 2) end
    return true
end

function thing.lock(thingId, key, holder, seconds)
    return exports[HOST]:thingLock(thingId, key, holder, seconds) == true
end

function thing.touch(thingId, key, holder, seconds)
    return exports[HOST]:thingTouch(thingId, key, holder, seconds) == true
end

function thing.release(thingId, key, holder)
    return exports[HOST]:thingRelease(thingId, key, holder) == true
end

function thing.holder(thingId, key)
    local holder = exports[HOST]:thingHolder(thingId, key)
    return holder
end

return thing
