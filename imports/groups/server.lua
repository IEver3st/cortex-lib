-- lib.groups: server helpers for group jobs (heists, deliveries, runs, legal work).
-- Thin wrapper over cortex-phone's group exports. Every call is nil-safe: while cortex-phone is
-- stopped, queries return their empty fallback and mutations return false, 'phone_unavailable'.
-- cortex-phone stays authoritative for membership, ownership and payouts.

local PHONE = 'cortex-phone'
local EVENTS = {
    memberJoined = true, memberLeft = true, memberRejoined = true, leaderChanged = true,
    disbanded = true, jobQueued = true, jobStarted = true, jobEnded = true,
}

local groups = {}
local registered = {} -- jobs this resource registered, replayed when cortex-phone restarts
local watching = false

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    if not ok or type(text) ~= 'string' then return '<unprintable error>' end
    if #text > 512 then return text:sub(1, 512) .. '...' end
    return text
end

function groups.isAvailable()
    return GetResourceState(PHONE) == 'started'
end

local function call(name, fallback, ...)
    if not groups.isAvailable() then return fallback, 'phone_unavailable' end
    local resourceExports = exports[PHONE]
    local results = table.pack(pcall(function(...) return resourceExports[name](resourceExports, ...) end, ...))
    if not results[1] then
        pcall(print, ('^1[cortex-lib] groups.%s failed: %s^0'):format(name, safeErrorText(results[2])))
        return fallback, 'phone_error'
    end
    if results.n < 2 or results[2] == nil then return fallback, results[3] end
    return table.unpack(results, 2, results.n)
end

-- Accepts a group ID (string) or a player source (number) and returns the group ID.
local function resolve(target)
    if type(target) == 'string' then return target end
    if type(target) == 'number' then
        local group = call('GetPlayerGroup', nil, target)
        return group and group.id or nil
    end
    return nil
end

-- Queries ---------------------------------------------------------------

--- Group details: `{ id, title, job, leader, size, members, waypoint, run }` or nil.
function groups.get(target)
    if type(target) == 'number' then return call('GetPlayerGroup', nil, target) end
    return call('GetGroup', nil, target)
end

--- The group a job should use for this player: the one on a job or queued, else their only crew.
function groups.getPlayerGroup(source) return call('GetPlayerGroup', nil, source) end

--- Every group summary for a player, including invitations.
function groups.getPlayerGroups(source) return call('GetPlayerGroups', {}, source) end

--- Members with `citizenid`, `name`, `number`, `source` (nil when offline), `online`, `leader`, `ready`, `participant`.
function groups.getMembers(target)
    local id = resolve(target)
    if not id then return {} end
    return call('GetGroupMembers', {}, id)
end

--- Server IDs of members online now. Pass `true` to keep only members taking part in the current job.
function groups.getSources(target, participantsOnly)
    local sources = {}
    for _, member in ipairs(groups.getMembers(target)) do
        if member.source and member.status == 'active' and (not participantsOnly or member.participant) then
            sources[#sources + 1] = member.source
        end
    end
    return sources
end

--- Active members and how many of them are online.
function groups.getSize(target)
    local id = resolve(target)
    if not id then return 0, 0 end
    local size, online = call('GetGroupSize', 0, id)
    return tonumber(size) or 0, tonumber(online) or 0
end

function groups.isLeader(source, groupId) return call('IsGroupLeader', false, source, groupId) == true end

--- The running or queued job: `{ id, label, state, owner, startedAt, stage, leader, size }` or nil.
function groups.getJob(target)
    local id = resolve(target)
    if not id then return nil end
    return call('GetGroupJob', nil, id)
end

-- Job registration ---------------------------------------------------------

local function register(id, entry)
    return call('RegisterGroupJob', false, id, entry.definition, entry.handlers)
end

local function watch()
    if watching then return end
    watching = true
    local function replay()
        for id, entry in pairs(registered) do
            local ok, reason = register(id, entry)
            if not ok then pcall(print, ('^3[cortex-lib] groups: could not register %s again: %s^0'):format(id, safeErrorText(reason))) end
        end
    end
    AddEventHandler('onResourceStart', function(resource) if resource == PHONE then replay() end end)
    AddEventHandler('cortex-phone:ready', replay)
end

--- Registers a job on the Groups jobs board. Re-registers automatically when cortex-phone restarts.
--- handlers: onStart(groupId, members, group) -> true | false, reason; onEnd(groupId, result);
--- onMemberLeft(groupId, member, reason); onMemberRejoined(groupId, member); onLeaderChanged(groupId, leader)
function groups.registerJob(id, definition, handlers)
    if type(id) ~= 'string' or type(definition) ~= 'table' then return false, 'invalid_job' end
    registered[id] = { definition = definition, handlers = handlers }
    watch()
    return register(id, registered[id])
end

function groups.unregisterJob(id)
    registered[id] = nil
    return call('UnregisterGroupJob', false, id)
end

function groups.setJobAvailable(id, available, reason) return call('SetGroupJobAvailable', false, id, available, reason) end

--- Starts a registered job for a group from your own flow (an NPC, a laptop). Returns ok, state|reason.
function groups.startJob(groupId, jobId) return call('StartGroupJob', false, groupId, jobId) end

-- During a job (only the resource that registered the job may call these) ----

function groups.setStage(groupId, stage) return call('SetGroupJobStage', false, groupId, stage) end
function groups.setWaypoint(groupId, point) return call('SetGroupWaypoint', false, groupId, point) end
function groups.clearWaypoint(groupId) return call('SetGroupWaypoint', false, groupId, nil) end
function groups.setBlip(groupId, key, blip) return call('SetGroupBlip', false, groupId, key, blip) end
function groups.addObjective(groupId, externalId, title) return call('AddGroupObjective', false, groupId, externalId, title) end
function groups.setObjective(groupId, externalId, completed) return call('SetGroupObjective', false, groupId, externalId, completed) end
function groups.notify(groupId, title, text) return call('NotifyGroup', false, groupId, title, text) end
function groups.endJob(groupId, result) return call('EndGroupJob', false, groupId, result) end

--- Pays everyone still taking part. payout: { amount, split?, account = 'cash'|'bank', reason?, id? }
function groups.pay(groupId, payout) return call('PayGroup', false, groupId, payout) end

-- Events -------------------------------------------------------------------

--- Listens to a cortex-phone group event: memberJoined, memberLeft, memberRejoined, leaderChanged,
--- disbanded, jobQueued, jobStarted, jobEnded. The handler receives one payload table.
function groups.on(event, handler)
    if not EVENTS[event] or type(handler) ~= 'function' then return nil end
    return AddEventHandler('cortex-phone:groups:' .. event, function(payload)
        -- Local server events only. A client cannot trigger these.
        if source ~= '' and source ~= nil and tonumber(source) then return end
        handler(payload)
    end)
end

lib.groups = groups

return groups
