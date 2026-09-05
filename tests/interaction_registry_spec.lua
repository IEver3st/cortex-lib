local exported = {}
local handlers = {}
local invokingResource = 'resource-low'
local revisionEvents = 0
local sortCalls = 0
local originalSort = table.sort

table.sort = function(items, comparator)
    sortCalls = sortCalls + 1
    return originalSort(items, comparator)
end

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
    panel = {
        id = 'social-target',
        label = 'STRANGER',
        variant = 'target',
    },
})
assert(ok == true)

invokingResource = 'resource-high'
ok = exported.showInteraction({
    id = 'door',
    label = 'OPEN',
    key = 'E',
    priority = 100,
    holdDuration = 1200,
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
assert(snapshot[1].holdDuration == 1200)
assert(snapshot[1].holdActive == false)
assert(snapshot[1].visible == false and snapshot[1].distance == nil)
assert(snapshot[2].owner == 'resource-low')
assert(snapshot[2].active == false)
assert(snapshot[2].panel.id == 'social-target')
assert(snapshot[2].panel.label == 'STRANGER')
assert(snapshot[2].panel.variant == 'target')

invokingResource = 'resource-low'
assert(exported.showInteraction({
    id = 'low',
    label = 'SIT',
    key = 'E',
    priority = 20,
    panel = {
        id = 'social-target',
        label = 'STRANGER',
        variant = 'target',
    },
}) == true)
assert(revisionEvents == 2, 'identical target-panel definitions must be a no-op')
invokingResource = 'resource-high'

local arbitrationSorts = sortCalls
for _ = 1, 1000 do
    assert(exported.isInteractionActive('door') == true)
end
assert(sortCalls == arbitrationSorts, 'active checks must use mutation-time arbitration without sorting')

local repeatedDefinition = {
    id = 'door',
    label = 'OPEN',
    key = 'E',
    priority = 100,
    holdDuration = 1200,
    anchor = {
        type = 'entity-bone',
        entity = 501,
        bone = 'door_dside_f',
        offset = { z = 0.08 },
        maxDistance = 2.0,
    },
}
for _ = 1, 1000 do
    assert(exported.showInteraction(repeatedDefinition) == true)
end
assert(revisionEvents == 2, 'identical show calls must not publish registry changes')
assert(sortCalls == arbitrationSorts, 'identical show calls must not re-arbitrate the registry')

for _ = 1, 1000 do
    assert(exported.setInteractions({ repeatedDefinition }) == true)
end
assert(revisionEvents == 2, 'identical set calls must not publish registry changes')
assert(sortCalls == arbitrationSorts, 'identical set calls must not re-arbitrate the registry')

snapshot[1].label = 'MUTATED'
snapshot[1].anchor.offset.z = 99.0
snapshot[2].panel.label = 'MUTATED'
local protectedSnapshot = exported.getInteractions()
assert(protectedSnapshot[1].label == 'OPEN', 'snapshot mutation leaked into the registry')
assert(protectedSnapshot[1].anchor.offset.z == 0.08, 'nested snapshot mutation leaked into the registry')
assert(protectedSnapshot[2].panel.label == 'STRANGER', 'panel snapshot mutation leaked into the registry')

ok = exported.startInteractionHold('door')
assert(ok == true)
snapshot = exported.getInteractions()
assert(snapshot[1].holdActive == true)
assert(snapshot[1].holdRevision == 1)
assert(revisionEvents == 3)

ok = exported.startInteractionHold('door')
assert(ok == true)
assert(revisionEvents == 3, 'repeated hold start must be idempotent')

invokingResource = 'resource-low'
local ownerOk, ownerError = exported.startInteractionHold('door')
assert(ownerOk == false)
assert(ownerError == 'interaction not found')

invokingResource = 'resource-high'
ok = exported.cancelInteractionHold('door')
assert(ok == true)
snapshot = exported.getInteractions()
assert(snapshot[1].holdActive == false)
assert(snapshot[1].holdRevision == 2)

ok = exported.cancelInteractionHold('door')
assert(ok == true)
assert(revisionEvents == 4, 'repeated hold cancel must be idempotent')

invokingResource = 'resource-low'
assert(exported.isInteractionActive('low') == false)
local holdOk, holdError = exported.startInteractionHold('low')
assert(holdOk == false)
assert(holdError == 'screen interactions are press-only')

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

invalid, errorMessage = exported.showInteraction({
    id = 'bad-hold',
    label = 'BAD',
    key = 'F',
    holdDuration = 99,
})
assert(invalid == false)
assert(type(errorMessage) == 'string')

invalid, errorMessage = exported.showInteraction({
    id = 'screen-hold',
    label = 'BAD',
    key = 'F',
    holdDuration = 1200,
})
assert(invalid == false)
assert(errorMessage == 'holdDuration is only supported for anchored interactions')

invalid, errorMessage = exported.showInteraction({
    id = false,
    label = 'BAD',
    key = 'F',
})
assert(invalid == false and errorMessage == 'id must be a string', 'false ids must not alias the default interaction')

invalid, errorMessage = exported.showInteraction({
    id = 'bad-defaults',
    label = 'BAD',
    key = 'F',
    priority = false,
})
assert(invalid == false and errorMessage == 'priority must be a finite number', 'false priority must not alias zero')

invalid, errorMessage = exported.showInteraction({
    id = 'bad-offset-default',
    label = 'BAD',
    key = 'F',
    anchor = { type = 'world', x = 1, y = 2, z = 3, offset = { x = false } },
})
assert(invalid == false and errorMessage:find('anchor.offset.x', 1, true), 'false offsets must not alias zero')

invalid, errorMessage = exported.showInteraction({
    id = 'bad-panel-variant',
    label = 'BAD',
    key = 'F',
    panel = { id = 'bad', label = 'BAD', variant = 'dialog' },
})
assert(invalid == false)
assert(errorMessage == 'panel.variant must be target')

invalid, errorMessage = exported.showInteraction({
    id = 'anchored-panel',
    label = 'BAD',
    key = 'F',
    anchor = { type = 'world', x = 1.0, y = 2.0, z = 3.0 },
    panel = { id = 'bad', label = 'BAD', variant = 'target' },
})
assert(invalid == false)
assert(errorMessage == 'panel is only supported for screen interactions')

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
assert(revisionEvents == 5)

invokingResource = 'resource-entity'
assert(exported.showInteraction({
    id = 'wallet',
    label = 'PICK UP WALLET',
    key = 'E',
    priority = 80,
    holdDuration = 350,
    anchor = {
        type = 'entity',
        entity = 777,
        model = -123456,
        offset = { z = 0.08 },
        maxDistance = 2.0,
    },
}) == true)

local entityState = exported.getInteractionState('wallet')
assert(entityState.anchor.type == 'entity' and entityState.anchor.entity == 777)
assert(entityState.anchor.model == -123456 and entityState.anchor.bone == nil)
assert(entityState.active == true and entityState.visible == false)
assert(exported.isInteractionVisible('wallet') == false)
assert(lib._setInteractionPresentationState('resource-entity', 'wallet', true, 1.25) == true)

entityState = exported.getInteractionState('wallet')
assert(entityState.visible == true and entityState.distance == 1.25)
assert(exported.isInteractionVisible('wallet') == true)
entityState.anchor.offset.z = 99.0
assert(exported.getInteractionState('wallet').anchor.offset.z == 0.08, 'state snapshots must protect nested anchors')

invokingResource = 'resource-low'
local missingState, missingStateError = exported.getInteractionState('wallet')
assert(missingState == nil and missingStateError == 'interaction not found')
assert(exported.isInteractionVisible('wallet') == false, 'visibility queries must remain owner-scoped')

handlers.onClientResourceStop('resource-entity')

invokingResource = 'resource-hold'
assert(exported.showInteraction({
    id = 'held',
    label = 'HOLD',
    key = 'Z',
    priority = 10,
    holdDuration = 1000,
    anchor = { type = 'world', x = 1.0, y = 2.0, z = 3.0 },
}) == true)
assert(exported.startInteractionHold('held') == true)

invokingResource = 'resource-preempt'
assert(exported.showInteraction({
    id = 'preempt',
    label = 'PREEMPT',
    key = 'Z',
    priority = 20,
}) == true)

snapshot = exported.getInteractions()
local heldState
for index = 1, #snapshot do
    if snapshot[index].owner == 'resource-hold' and snapshot[index].id == 'held' then
        heldState = snapshot[index]
        break
    end
end
assert(heldState ~= nil)
assert(heldState.active == false and heldState.holdActive == false)
assert(heldState.holdRevision == 2, 'losing arbitration must cancel an active hold exactly once')

assert(exported.hideInteraction('preempt') == true)
snapshot = exported.getInteractions()
for index = 1, #snapshot do
    if snapshot[index].owner == 'resource-hold' and snapshot[index].id == 'held' then
        heldState = snapshot[index]
        break
    end
end
assert(heldState.active == true and heldState.holdActive == false)
assert(heldState.holdRevision == 2, 'regaining arbitration must not resurrect or recancel a stale hold')

invokingResource = 'resource-hold'
assert(exported.startInteractionHold('held') == true)
assert(exported.getInteractionState('held').holdRevision == 3, 'a fresh hold must remain possible after preemption')
handlers.onClientResourceStop('resource-hold')

local cappedItems = {}
for index = 1, 8 do
    cappedItems[index] = {
        id = ('cap-%d'):format(index),
        label = ('CAP %d'):format(index),
        key = ('F%d'):format(index),
    }
end

invokingResource = 'resource-cap'
ok = exported.setInteractions(cappedItems)
assert(ok == true)
local limitOk, limitError = exported.showInteraction({ id = 'cap-9', label = 'CAP 9', key = 'F9' })
assert(limitOk == false and limitError == 'resource interaction limit reached (8)')

local fillItems = {}
for index = 1, 7 do
    fillItems[index] = {
        id = ('fill-%d'):format(index),
        label = ('FILL %d'):format(index),
        key = ('NUM%d'):format(index),
    }
end

invokingResource = 'resource-fill'
assert(exported.setInteractions(fillItems) == true)
snapshot = exported.getInteractions()
assert(#snapshot == 16, 'the registry must retain its documented global capacity')

invokingResource = 'resource-overflow'
limitOk, limitError = exported.showInteraction({ id = 'overflow', label = 'OVERFLOW', key = 'HOME' })
assert(limitOk == false and limitError == 'global interaction limit reached (16)')

handlers.onClientResourceStop('resource-cap')
assert(#exported.getInteractions() == 8, 'owner cleanup must update registry capacity counters')
assert(exported.showInteraction({ id = 'recovered', label = 'RECOVERED', key = 'HOME' }) == true)

print('interaction registry tests passed')
