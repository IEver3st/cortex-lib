local scriptPath = arg[1] or 'imports/notify/client.lua'

local invoking = 'owner-a'
local callbacks, events, messages, timeouts = {}, {}, {}, {}
local generation, activeSurface, activeSession = 0, nil, nil
local awaitHook = nil
local resolveCount = 0
local now = 0
local sounds = 0
local progressRespawnTest = false
local progressPedCalls = 0
local oldPedExists = true
local removedAnimDicts = 0
local stoppedAnimTasks = 0
local invalidProgressPed = false
local scenarioTasks = 0
local throwingScenario = false
local clearedScenarioTasks = 0
local suspendProgress = false
local propExists = false
local deletedProps = 0
local releasedModels = 0
local hostileError = setmetatable({}, { __tostring = function() error('hostile tostring') end })

function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return invoking end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function RegisterNetEvent() end
function AddEventHandler(name, callback) events[name] = callback end
function SendNUIMessage(message) messages[#messages + 1] = message end
function SetTimeout(delay, callback) timeouts[#timeouts + 1] = { delay = delay, callback = callback } end
function GetGameTimer() return now end
function GetSoundId() return 1 end
function PlaySoundFrontend() sounds = sounds + 1 end
function ReleaseSoundId() end
function SetNuiFocus() end
function PlayerPedId()
    if invalidProgressPed then return 0 end
    if not progressRespawnTest then return 1 end
    progressPedCalls = progressPedCalls + 1
    if progressPedCalls >= 3 then oldPedExists = false; return 2 end
    return 1
end
function DoesEntityExist(entity)
    if entity == 99 then return propExists end
    return entity == 1 and oldPedExists
end
function HasAnimDictLoaded() return true end
function RequestAnimDict() end
function HasModelLoaded() return true end
function RequestModel() end
function GetEntityCoords() return { x = 0, y = 0, z = 0 } end
function CreateObject()
    propExists = true
    return 99
end
function AttachEntityToEntity() end
function GetPedBoneIndex() return 1 end
function DeleteEntity(entity)
    if entity == 99 and propExists then
        propExists = false
        deletedProps = deletedProps + 1
    end
end
function SetModelAsNoLongerNeeded() releasedModels = releasedModels + 1 end
function TaskPlayAnim() end
function TaskStartScenarioInPlace()
    scenarioTasks = scenarioTasks + 1
    if throwingScenario then error(hostileError, 0) end
end
function ClearPedTasks() clearedScenarioTasks = clearedScenarioTasks + 1 end
function StopAnimTask() stoppedAnimTasks = stoppedAnimTasks + 1 end
function RemoveAnimDict() removedAnimDicts = removedAnimDicts + 1 end
function IsControlJustPressed() return false end
function IsEntityDead() return false end
function Wait()
    if suspendProgress then coroutine.yield() end
end

promise = {
    new = function()
        return {
            resolve = function(self, value)
                resolveCount = resolveCount + 1
                self.value = value
                self.resolved = true
            end,
        }
    end,
}
Citizen = {
    Await = function(value)
        if awaitHook then local hook = awaitHook; awaitHook = nil; hook() end
        assert(value.resolved, 'test Await hook must settle the promise')
        return value.value
    end,
}

exports = function() end
lib = {
    cache = { ped = 0 },
    _acquireModal = function(surface)
        generation = generation + 1
        activeSurface, activeSession = surface, generation
        return generation
    end,
    _focusModal = function(surface, session) return activeSurface == surface and activeSession == session end,
    _matchesModal = function(surface, session, supplied)
        return activeSurface == surface and activeSession == session and supplied == session
    end,
    _releaseModal = function(surface, session)
        if activeSurface ~= surface or activeSession ~= session then return false end
        activeSurface, activeSession = nil, nil
        return true
    end,
    _registerModalSurface = function() end,
}

assert(dofile(scriptPath))

local messagesBeforeHostileText = #messages
assert(lib.notify({ title = hostileError, description = 'unsafe' }) == nil
    and lib.progress({ duration = 10, label = hostileError }) == false
    and lib.alertDialog({ header = hostileError, timeout = 1000 }) == 'cancel'
    and lib.contextMenu({ title = 'Unsafe', timeout = 1000, fields = {
        { name = 'choice', type = 'select', options = { { value = 'a', label = hostileError } } },
    } }) == nil
    and #messages == messagesBeforeHostileText,
    'hostile non-scalar text values must be rejected without escaping or reaching NUI')

now = 4294967200
lib.notify({ description = 'first', sound = true })
assert(messages[#messages].data.showDuration == true, 'notification duration bar must remain enabled by default')
now = 10
lib.notify({ description = 'second', sound = true })
assert(sounds == 1, 'sound throttle must measure the short interval across clock wrap')
now = 300
lib.notify({ description = 'third', sound = true })
assert(sounds == 2, 'sound throttle must expire normally after clock wrap')

invoking = 'owner-a'
lib.notify({ description = 'dedupe-me', persistent = true, sound = false })
local anonymousAFirst = messages[#messages].data
lib.notify({ description = 'dedupe-me', persistent = true, sound = false })
local anonymousASecond = messages[#messages].data
assert(anonymousAFirst.explicitId == false and anonymousASecond.explicitId == false
    and anonymousAFirst.id == anonymousASecond.id,
    'anonymous dedupe notifications must reuse one owner-scoped tracked transport identity')
invoking = 'owner-b'
lib.notify({ description = 'dedupe-me', persistent = true, sound = false })
assert(messages[#messages].data.explicitId == false and messages[#messages].data.owner == 'owner-b',
    'anonymous notification markers must retain owner isolation')
invoking = 'owner-a'
lib.notify({ description = 'dedupe-me', persistent = true, sound = false, dedupe = false })
assert(messages[#messages].data.explicitId == false and messages[#messages].data.dedupe == false,
    'dedupe=false must remain explicit in anonymous notification payloads')

invoking = 'dedupe-cap'
local stableDedupeId
for index = 1, 129 do
    local result = lib.notify({ description = 'repeat', persistent = true, sound = false })
    assert(result == nil, 'repeated anonymous dedupe notifications must not exhaust tracked capacity')
    stableDedupeId = stableDedupeId or messages[#messages].data.id
    assert(messages[#messages].data.id == stableDedupeId, 'repeated anonymous dedupe identity must remain stable')
end
assert(lib.clearNotifications() == true and messages[#messages].data.owner == 'dedupe-cap',
    'owner clear must remove its tracked anonymous dedupe identity')
lib.notify({ description = 'repeat', persistent = true, sound = false })
assert(messages[#messages].data.id ~= stableDedupeId,
    'a notification after owner clear must receive a fresh anonymous dedupe identity')
lib.clearNotifications()

invoking = 'unique-cap'
local uniqueIds = {}
for index = 1, 128 do
    local result = lib.notify({ description = 'repeat', persistent = true, sound = false, dedupe = false })
    assert(result == nil and not uniqueIds[messages[#messages].data.id],
        'dedupe=false anonymous notifications must retain unique tracked identities')
    uniqueIds[messages[#messages].data.id] = true
end
local capacityResult, capacityError = lib.notify({ description = 'repeat', persistent = true, sound = false, dedupe = false })
assert(capacityResult == false and capacityError == 'capacity_exceeded',
    'dedupe=false anonymous notifications must remain subject to the owner capacity cap')
lib.clearNotifications()

invoking = 'owner-a'
assert(lib.notify({ id = 'shared', description = 'A', persistent = true, sound = false }) == 'shared')
local ownerAInternal = messages[#messages].data.id
assert(messages[#messages].data.owner == 'owner-a' and messages[#messages].data.explicitId == true,
    'explicit notification payloads must include owner and replacement identity')
invoking = 'owner-b'
assert(lib.notify({ id = 'shared', description = 'B', persistent = true, sound = false }) == 'shared')
local ownerBInternal = messages[#messages].data.id
assert(ownerAInternal ~= ownerBInternal, 'same public notification IDs must not collide across owners')
assert(lib.hideNotify('shared') and messages[#messages].data.id == ownerBInternal,
    'hideNotify must resolve only the invoking owner\'s internal ID')
invoking = 'owner-a'
assert(lib.hideNotify('shared') and messages[#messages].data.id == ownerAInternal,
    'each owner must retain independent hide authority')

local alertFirst, alertReplay
local resolvesBefore = resolveCount
awaitHook = function()
    local session = activeSession
    callbacks.alertDialogResult({ session = session, result = 'confirm' }, function(value) alertFirst = value end)
    callbacks.alertDialogResult({ session = session, result = 'confirm' }, function(value) alertReplay = value end)
end
assert(lib.alertDialog({ header = 'Confirm?', content = 'Safe', timeout = 1000 }) == 'confirm')
assert(alertFirst.ok == true and alertReplay.ok == false and resolveCount == resolvesBefore + 1,
    'alert result replay must settle exactly once')

local cancelReply, confirmReply
awaitHook = function()
    local session = activeSession
    callbacks.alertDialogResult({ session = session, result = 'cancel' }, function(value) cancelReply = value end)
    callbacks.alertDialogResult({ session = session, result = 'confirm' }, function(value) confirmReply = value end)
end
assert(lib.alertDialog({ header = 'Required', content = 'Choose', cancel = false, timeout = 1000 }) == 'confirm')
assert(cancelReply.ok == false and cancelReply.error == 'cancel_not_allowed' and confirmReply.ok == true,
    'forged cancel results must not bypass cancel=false')

local selectOption = { value = 'a', label = 'A', poison = function() end }
selectOption.cycle = selectOption
local contextReplies = {}
awaitHook = function()
    local sent = messages[#messages]
    assert(sent.action == 'contextMenu' and sent.data.fields[2].options[1].poison == nil,
        'context fields/options must be rebuilt from a serializable allowlist')
    local session = activeSession
    callbacks.contextMenuResult({
        session = session, result = 'confirm',
        values = { enabled = true, choice = 'forged', note = 'ok' },
    }, function(value) contextReplies[#contextReplies + 1] = value end)
    callbacks.contextMenuResult({
        session = session, result = 'confirm',
        values = { enabled = true, choice = 'a', note = 'ok' },
    }, function(value) contextReplies[#contextReplies + 1] = value end)
    callbacks.contextMenuResult({
        session = session, result = 'cancel',
    }, function(value) contextReplies[#contextReplies + 1] = value end)
end
local values = lib.contextMenu({
    title = 'Context', timeout = 1000,
    fields = {
        { name = 'enabled', type = 'checkbox', label = 'Enabled' },
        { name = 'choice', type = 'select', label = 'Choice', options = { selectOption }, required = true },
        { name = 'note', type = 'input', label = 'Note', required = true },
    },
})
assert(values and values.enabled == true and values.choice == 'a' and values.note == 'ok',
    'context result must conform to declared field contracts')
assert(contextReplies[1].ok == false and contextReplies[1].error == 'invalid_values'
    and contextReplies[2].ok == true and contextReplies[3].ok == false,
    'context invalid values and replay must be rejected without a second settle')

local falseSelectReply
awaitHook = function()
    callbacks.contextMenuResult({
        session = activeSession,
        result = 'confirm',
        values = { choice = false },
    }, function(value) falseSelectReply = value end)
end
local falseSelectValues = lib.contextMenu({
    title = 'Boolean select', timeout = 1000,
    fields = {
        { name = 'choice', type = 'select', label = 'Choice', options = {
            { value = false, label = 'Disabled' },
            { value = true, label = 'Enabled' },
        }, required = true },
    },
})
assert(falseSelectReply.ok == true and falseSelectValues
    and type(falseSelectValues.choice) == 'boolean' and falseSelectValues.choice == false,
    'table-form false select options must remain selectable at the NUI result boundary')
assert(lib.contextMenu({ title = 'Unsafe', fields = { { name = '__proto__', type = 'input' } } }) == nil
    and lib.contextMenu({ title = 'Unsafe', fields = { { name = 'line\nbreak', type = 'input' } } }) == nil,
    'context field names must reject reserved JavaScript keys and control characters')

local style = {
    backgroundColor = '#000', borderColor = 'var(--state-focus)',
    border = '1px solid #fff', poison = function() end,
}
style.cycle = style
assert(lib.showTextUI('Prompt', { style = style }))
local textMessage = messages[#messages]
assert(textMessage.data.style.backgroundColor == '#000' and textMessage.data.style.borderColor == 'var(--state-focus)'
    and textMessage.data.style.poison == nil,
    'text UI styles must contain only supported string keys')
invoking = 'owner-b'
local textOk, textError = lib.showTextUI('Hijack', {})
assert(textOk == false and textError == 'not_owner', 'an unrelated owner must not replace active text UI')
invoking = 'owner-a'
assert(lib.hideTextUI())
assert(lib.showTextUI('Bad', { style = { color = 'red;position:fixed' } }) == false,
    'text UI must reject unsafe CSS values')

assert(lib.progress({ duration = 10, anim = { dict = 'dict', clip = 'clip', blendIn = math.huge } }) == false,
    'progress must reject unsafe animation blend ranges before mutation')
assert(lib.progress({ duration = 10, prop = { model = 1, bone = 70000 } }) == false,
    'progress must reject unsafe prop bone ranges before mutation')
invalidProgressPed = true
local messageCountBeforeInvalidPed = #messages
assert(lib.progress({ duration = 10, anim = { scenario = 'WORLD_HUMAN_STAND_IMPATIENT' } }) == false
    and scenarioTasks == 0 and #messages == messageCountBeforeInvalidPed and not lib.isProgressActive(),
    'progress must reject a zero/deleted fallback ped before starting tasks, UI, or active state')
invalidProgressPed = false
throwingScenario = true
assert(lib.progress({ duration = 10, anim = { scenario = 'WORLD_HUMAN_STAND_IMPATIENT' } }) == false
    and not lib.isProgressActive() and clearedScenarioTasks == 1,
    'hostile native error objects must remain contained after progress cleanup')
throwingScenario = false
progressRespawnTest = true
assert(lib.progress({ duration = 10, anim = { dict = 'dict', clip = 'clip' } }) == false,
    'progress must cancel when the player ped changes during the operation')
assert(removedAnimDicts == 1 and stoppedAnimTasks == 0,
    'progress cleanup must release its anim dict even when the original ped no longer exists')

progressRespawnTest = false
progressPedCalls = 0
oldPedExists = true
suspendProgress = true
local progressResult
local progressThread = coroutine.create(function()
    progressResult = lib.progress({
        duration = 1000,
        anim = { dict = 'stop-dict', clip = 'stop-clip' },
        prop = {
            model = 77,
            pos = { x = 0, y = 0, z = 0 },
            rot = { x = 0, y = 0, z = 0 },
        },
    })
end)
assert(coroutine.resume(progressThread) == true and coroutine.status(progressThread) == 'suspended')
assert(lib.isProgressActive() and propExists, 'progress fixture must be active before stop cleanup')

local messagesBeforeProgressStop = #messages
local stoppedBeforeProgressStop = stoppedAnimTasks
local dictsBeforeProgressStop = removedAnimDicts
events.onResourceStop('cortex-lib')
local progressEndCount = 0
for index = messagesBeforeProgressStop + 1, #messages do
    if messages[index].action == 'progressEnd' then progressEndCount = progressEndCount + 1 end
end
assert(progressEndCount == 1 and not lib.isProgressActive(),
    'cortex-lib stop must synchronously end active progress without waiting for its worker')
assert(stoppedAnimTasks == stoppedBeforeProgressStop + 1
    and removedAnimDicts == dictsBeforeProgressStop + 1
    and deletedProps == 1 and releasedModels == 1 and not propExists,
    'cortex-lib stop must synchronously release progress animation, prop, model, and anim dict')

suspendProgress = false
assert(coroutine.resume(progressThread) == true and coroutine.status(progressThread) == 'dead')
assert(progressResult == false and stoppedAnimTasks == stoppedBeforeProgressStop + 1
    and removedAnimDicts == dictsBeforeProgressStop + 1 and deletedProps == 1 and releasedModels == 1,
    'late worker cleanup must be an idempotent no-op after synchronous stop cleanup')

invoking = 'owner-stop'
lib.notify({ id = 'persistent', description = 'stop cleanup', persistent = true, sound = false })
events.onResourceStop('owner-stop')
assert(messages[#messages].action == 'clearNotifications' and messages[#messages].data.owner == 'owner-stop',
    'owner stop must clear its persistent notifications')

print('notify and dialog lifecycle: PASS')
