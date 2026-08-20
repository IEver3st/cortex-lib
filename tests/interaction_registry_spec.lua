local exported = {}
local handlers = {}
local invokingResource = 'resource-low'
local revisionEvents = 0

lib = {
    isInternalResource = function()
        return true
    end,
}

function exports(name, callback)
    exported[name] = callback
end

function TriggerEvent(name)
    assert(name == 'cortex-lib:interaction:changed')
    revisionEvents = revisionEvents + 1
end

function AddEventHandler(name, callback)
    handlers[name] = callback
end

function GetInvokingResource()
    return invokingResource
end

function GetCurrentResourceName()
    return 'cortex-lib'
end

dofile('../cortex-lib/imports/interaction/client.lua')

local ok = exported.showInteraction({
    id = 'low',
    label = 'SIT',
    key = 'E',
    priority = 20,
})
assert(ok == true)

invokingResource = 'resource-high'
ok = exported.showInteraction({
    id = 'door',
    label = 'OPEN',
    key = 'E',
    priority = 100,
    anchor = {
        type = 'entity-bone',
        entity = 501,
        bone = 'door_dside_f',
        offset = { z = 0.08 },
        maxDistance = 2.0,
    },
})
assert(ok == true)

local snapshot = exported.getInteractions()
assert(#snapshot == 2)
assert(snapshot[1].owner == 'resource-high')
assert(snapshot[1].active == true)
assert(snapshot[1].anchor.type == 'entity-bone')
assert(snapshot[1].anchor.entity == 501)
assert(snapshot[2].owner == 'resource-low')
assert(snapshot[2].active == false)

assert(exported.isInteractionActive('door') == true)
invokingResource = 'resource-low'
assert(exported.isInteractionActive('low') == false)

invokingResource = 'resource-invalid'
local invalid, errorMessage = exported.showInteraction({
    id = 'bad-anchor',
    label = 'BAD',
    key = 'E',
    anchor = {
        type = 'world',
        x = 1.0,
        y = 2.0,
    },
})
assert(invalid == false)
assert(type(errorMessage) == 'string')

invalid = exported.showInteraction({
    id = 'bad-entity',
    label = 'BAD',
    key = 'F',
    anchor = {
        type = 'entity-bone',
        entity = 1.5,
        bone = 'door_dside_f',
    },
})
assert(invalid == false)

snapshot = exported.getInteractions()
assert(#snapshot == 2, 'malformed anchor changed the registry')

assert(type(handlers.onClientResourceStop) == 'function')
handlers.onClientResourceStop('resource-high')
snapshot = exported.getInteractions()
assert(#snapshot == 1)
assert(snapshot[1].owner == 'resource-low')
assert(snapshot[1].active == true)
assert(revisionEvents == 3)

print('interaction registry tests passed')
