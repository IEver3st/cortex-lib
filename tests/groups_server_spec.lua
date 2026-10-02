local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(message, tostring(expected), tostring(actual)))
    end
end

local state = 'stopped'
local calls, handlers = {}, {}
local phone = {}
function GetResourceState(name) assertEqual(name, 'cortex-phone', 'only cortex-phone is queried'); return state end
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn); return { name = name } end
exports = setmetatable({}, { __index = function(_, name) assertEqual(name, 'cortex-phone', 'exports target'); return phone end })
setmetatable(phone, { __index = function(_, name)
    return function(self, ...)
        assertEqual(self, phone, name .. ' is called with the export proxy')
        calls[#calls + 1] = { name = name, args = table.pack(...) }
        if name == 'GetPlayerGroup' then return { id = 'crew:1' } end
        if name == 'GetGroupMembers' then return { { source = 4, status = 'active', participant = true }, { status = 'active' }, { source = 7, status = 'invited' } } end
        if name == 'GetGroupSize' then return 3, 2 end
        if name == 'RegisterGroupJob' then return true end
        if name == 'PayGroup' then return false, 'invalid_amount' end
        if name == 'GetGroup' then error('boom') end
        return true
    end
end })

lib = {}
local groups = dofile('imports/groups/server.lua')
assertEqual(lib.groups, groups, 'lib.groups should be the module')

-- Stopped phone: safe fallbacks, no export calls.
assertEqual(groups.isAvailable(), false, 'phone stopped')
assertEqual(groups.get('crew:1'), nil, 'get falls back to nil')
assertEqual(#groups.getMembers(4), 0, 'members fall back to an empty list')
local size, online = groups.getSize('crew:1')
assertEqual(size, 0, 'size fallback'); assertEqual(online, 0, 'online fallback')
assertEqual(groups.isLeader(4), false, 'leader fallback')
local ok, reason = groups.pay('crew:1', { amount = 10 })
assertEqual(ok, false, 'mutation fallback'); assertEqual(reason, 'phone_unavailable', 'mutation reason')
local registered = groups.registerJob('truck', { label = 'Truck' }, {})
assertEqual(registered, false, 'register while stopped returns false')
assertEqual(#calls, 0, 'no export is called while the phone is stopped')

-- Started phone: routes to exports and resolves player sources to group IDs.
state = 'started'
local members = groups.getMembers(4)
assertEqual(calls[1].name, 'GetPlayerGroup', 'a source resolves through GetPlayerGroup')
assertEqual(calls[2].name, 'GetGroupMembers', 'members query')
assertEqual(calls[2].args[1], 'crew:1', 'resolved group ID is passed')
assertEqual(#members, 3, 'members returned')
local sources = groups.getSources('crew:1')
assertEqual(#sources, 1, 'only online active members have sources')
assertEqual(sources[1], 4, 'online source')
size, online = groups.getSize('crew:1')
assertEqual(size, 3, 'size'); assertEqual(online, 2, 'online')
ok, reason = groups.pay('crew:1', { amount = -1 })
assertEqual(ok, false, 'phone rejection is returned'); assertEqual(reason, 'invalid_amount', 'phone reason is returned')
assertEqual(groups.get('crew:1'), nil, 'a failing export falls back without throwing')

-- Registered jobs are replayed when cortex-phone restarts.
assertEqual(groups.registerJob('truck', { label = 'Truck' }, {}), true, 'register while started')
local before = #calls
for _, fn in ipairs(handlers.onResourceStart or {}) do fn('other-resource') end
assertEqual(#calls, before, 'other resources do not replay')
for _, fn in ipairs(handlers.onResourceStart or {}) do fn('cortex-phone') end
assertEqual(calls[#calls].name, 'RegisterGroupJob', 'phone restart replays registration')
assertEqual(calls[#calls].args[1], 'truck', 'same job ID is replayed')

-- Events are limited to the documented names.
assertEqual(groups.on('nope', function() end), nil, 'unknown events are rejected')
local received
groups.on('jobEnded', function(payload) received = payload end)
source = ''
handlers['cortex-phone:groups:jobEnded'][1]({ groupId = 'crew:1' })
assertEqual(received and received.groupId, 'crew:1', 'local event reaches the handler')
received = nil; source = '12'
handlers['cortex-phone:groups:jobEnded'][1]({ groupId = 'spoof' })
assertEqual(received, nil, 'client-sourced events are ignored')

print('groups_server_spec passed')
