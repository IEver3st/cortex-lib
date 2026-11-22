local HOST = GetCurrentResourceName()
local ASK = HOST .. ':thing:ask'
local LOCKS = HOST .. ':thing:locks'
local EVENT_LOCK = HOST .. ':thing:lock'
local EVENT_CANCEL = HOST .. ':thing:cancel'

local PUSH_RANGE_SQUARED = 130.0 * 130.0
local EVERY_BUCKET = -1
local ASKS_PER_SECOND = 8
local MAX_ID_BYTES = 48
local MAX_KEYS_PER_QUERY = 64
local MIN_LEASE_SECONDS = 1
local MAX_LEASE_SECONDS = 3600
local DEFAULT_LEASE_SECONDS = 30
local DEFAULT_RANGE = 2.5
local MAX_RANGE = 25.0
local TAG_HOLDER = -1

local served = {}
local locks = {}
local lockCount = 0
local askLocks = {}
local counter = 0
local rates = {}
local cooldowns = {}
local sweeping = false

local function validId(value)
    return type(value) == 'string' and #value > 0 and #value <= MAX_ID_BYTES and not value:find('[%c]')
end

local function keyText(key)
    local whole = type(key) == 'number' and math.tointeger(key)
    if whole then return 'n:' .. whole end
    if validId(key) then return 's:' .. key end
    return nil
end

local function lockKey(owner, thingId, key)
    local text = keyText(key)
    if not text then return nil end
    return owner .. '|' .. thingId .. '|' .. text
end

local function thingOf(owner, thingId)
    local things = served[owner]
    return things and things[thingId] or nil
end

local function position(thing, key)
    local ok, x, y, z, bucket = pcall(thing.dispatch, 'coords', key)
    if not ok then
        print(('^1[%s] thing %s:%s coords failed: %s^7'):format(HOST, thing.owner, thing.id, tostring(x)))
        return nil
    end
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return nil end
    bucket = math.tointeger(tonumber(bucket) or 0) or 0
    return x, y, z, bucket < 0 and EVERY_BUCKET or bucket
end

local function publicHolder(holder)
    return type(holder) == 'number' and holder or TAG_HOLDER
end

local function push(lock, held)
    local holder = held and publicHolder(lock.holder) or 0
    local players = GetPlayers()
    for index = 1, #players do
        local player = tonumber(players[index])
        local ped = player and GetPlayerPed(player) or 0
        if ped ~= 0 and (lock.bucket == EVERY_BUCKET or GetPlayerRoutingBucket(player) == lock.bucket) then
            local coords = GetEntityCoords(ped)
            local dx, dy, dz = coords.x - lock.x, coords.y - lock.y, coords.z - lock.z
            if dx * dx + dy * dy + dz * dz <= PUSH_RANGE_SQUARED then
                TriggerClientEvent(EVENT_LOCK, player, lock.owner, lock.thing, lock.key, holder, lock.counter)
            end
        end
    end
end

local function clear(id, expectedHolder)
    local lock = locks[id]
    if not lock then return true end
    if expectedHolder ~= nil and lock.holder ~= expectedHolder then return false end

    locks[id] = nil
    lockCount = lockCount - 1
    if askLocks[lock.holder] == id then askLocks[lock.holder] = nil end
    counter = counter + 1
    lock.counter = counter
    push(lock, false)
    return true
end

local function sweep()
    if sweeping then return end
    sweeping = true
    CreateThread(function()
        while lockCount > 0 do
            Wait(1000)
            local now = GetGameTimer()
            local expired = {}
            for id, lock in pairs(locks) do
                if now >= lock.expires then expired[#expired + 1] = id end
            end
            for index = 1, #expired do clear(expired[index]) end
        end
        sweeping = false
    end)
end

local function adopt(id, lock)
    lock.ask = false
    if askLocks[lock.holder] == id then askLocks[lock.holder] = nil end
end

local function leaseMs(seconds)
    seconds = tonumber(seconds) or DEFAULT_LEASE_SECONDS
    return math.floor(math.max(MIN_LEASE_SECONDS, math.min(MAX_LEASE_SECONDS, seconds)) * 1000)
end

local function take(thing, key, holder, seconds, viaAsk)
    local id = lockKey(thing.owner, thing.id, key)
    if not id then return false end

    local now = GetGameTimer()
    local lock = locks[id]
    if lock and now < lock.expires then
        if lock.holder ~= holder then return false end
        lock.expires = now + leaseMs(seconds)
        if not viaAsk then adopt(id, lock) end
        return true
    end
    if lock then clear(id) end

    local x, y, z, bucket = position(thing, key)
    if not x then return false end

    if viaAsk then
        local previous = askLocks[holder]
        if previous and previous ~= id then clear(previous) end
        askLocks[holder] = id
    end

    counter = counter + 1
    lock = {
        owner = thing.owner, thing = thing.id, key = key, holder = holder,
        expires = now + leaseMs(seconds), counter = counter, ask = viaAsk == true,
        x = x, y = y, z = z, bucket = bucket,
    }
    locks[id] = lock
    lockCount = lockCount + 1
    push(lock, true)
    sweep()
    return true
end

local function validHolder(holder)
    return (math.type(holder) == 'integer' and holder > 0) or validId(holder)
end

local function ownedThing(thingId)
    local owner = GetInvokingResource() or HOST
    return validId(thingId) and thingOf(owner, thingId) or nil, owner
end

local function serve(thingId, verbs, dispatch)
    local owner = GetInvokingResource() or HOST
    if not validId(thingId) then return false, 'thing id must be a short string' end
    if type(verbs) ~= 'table' or (type(dispatch) ~= 'table' and type(dispatch) ~= 'function') then
        return false, 'verbs and a dispatcher are required'
    end

    local plain = {}
    for verbId, verb in pairs(verbs) do
        if not validId(verbId) or type(verb) ~= 'table' then return false, 'verb ids must be short strings' end
        plain[verbId] = {
            range = math.max(0.5, math.min(MAX_RANGE, tonumber(verb.range) or DEFAULT_RANGE)),
            cooldown = math.max(0, math.min(600000, math.floor(tonumber(verb.cooldown) or 500))),
            lock = verb.lock and leaseMs(verb.lock) / 1000 or nil,
        }
    end

    served[owner] = served[owner] or {}
    served[owner][thingId] = { owner = owner, id = thingId, verbs = plain, dispatch = dispatch }
    return true
end

local function allowAsk(src, now)
    local rate = rates[src]
    if not rate then
        rate = { tokens = ASKS_PER_SECOND, at = now }
        rates[src] = rate
    end
    rate.tokens = math.min(ASKS_PER_SECOND, rate.tokens + (now - rate.at) * ASKS_PER_SECOND / 1000)
    rate.at = now
    if rate.tokens < 1 then return false end
    rate.tokens = rate.tokens - 1
    return true
end

local function ask(src, owner, thingId, key, verbId)
    local now = GetGameTimer()
    if not allowAsk(src, now) then return false, 'One moment' end
    if not validId(owner) or not validId(thingId) or not validId(verbId) or not keyText(key) then
        return false, 'Not available'
    end

    local thing = thingOf(owner, thingId)
    local verb = thing and thing.verbs[verbId]
    if not verb then return false, 'Not available' end

    local cooling = cooldowns[src]
    if not cooling then
        cooling = {}
        cooldowns[src] = cooling
    end
    local verbKey = owner .. '|' .. thingId .. '|' .. verbId
    if cooling[verbKey] and now < cooling[verbKey] then return false, 'One moment' end

    local x, y, z, bucket = position(thing, key)
    if not x then return false, 'Not available' end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false, 'Too far' end
    local state = Player(src).state
    if state.isDead or state.inLaststand then return false, 'Not available' end
    if bucket ~= EVERY_BUCKET and GetPlayerRoutingBucket(src) ~= bucket then return false, 'Too far' end
    local coords = GetEntityCoords(ped)
    local dx, dy, dz = coords.x - x, coords.y - y, coords.z - z
    if dx * dx + dy * dy + dz * dz > verb.range * verb.range then return false, 'Too far' end

    local id = lockKey(owner, thingId, key)
    local held = locks[id]
    if held and now < held.expires and held.holder ~= src then return false, 'In use' end
    if verb.cooldown > 0 then cooling[verbKey] = now + verb.cooldown end

    local took = false
    if verb.lock then
        local mine = held ~= nil and held.holder == src and now < held.expires
        if not take(thing, key, src, verb.lock, true) then return false, 'In use' end
        took = not mine
    end

    local ok, allowed, reason = pcall(thing.dispatch, 'run', key, verbId, src)
    if not ok then
        print(('^1[%s] thing %s:%s verb %s failed: %s^7'):format(HOST, owner, thingId, verbId, tostring(allowed)))
        allowed, reason = false, 'Not available'
    end
    if allowed ~= true then
        if took then clear(id, src) end
        return false, type(reason) == 'string' and reason:sub(1, 64) or 'Not available'
    end

    return true, reason
end

local function lockStates(_, owner, thingId, keys)
    local out = {}
    if not validId(owner) or not validId(thingId) or type(keys) ~= 'table' then return out, counter end
    local now = GetGameTimer()
    for index = 1, math.min(#keys, MAX_KEYS_PER_QUERY) do
        local id = lockKey(owner, thingId, keys[index])
        local lock = id and locks[id]
        if lock and now < lock.expires then
            out[#out + 1] = { key = lock.key, holder = publicHolder(lock.holder), counter = lock.counter }
        end
    end
    return out, counter
end

lib.callback.register(ASK, ask)
lib.callback.register(LOCKS, lockStates)

RegisterNetEvent(EVENT_CANCEL, function(owner, thingId, key)
    local src = source
    if not validId(owner) or not validId(thingId) then return end
    local id = lockKey(owner, thingId, key)
    local lock = id and locks[id]
    if lock and lock.holder == src and lock.ask then clear(id, src) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local held = {}
    for id, lock in pairs(locks) do
        if lock.holder == src then held[#held + 1] = id end
    end
    for index = 1, #held do clear(held[index]) end
    rates[src] = nil
    cooldowns[src] = nil
    askLocks[src] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if not served[resource] then return end
    local held = {}
    for id, lock in pairs(locks) do
        if lock.owner == resource then held[#held + 1] = id end
    end
    for index = 1, #held do clear(held[index]) end
    served[resource] = nil
end)

exports('thingServe', serve)

exports('thingLock', function(thingId, key, holder, seconds)
    local thing = ownedThing(thingId)
    if not thing or not validHolder(holder) then return false end
    return take(thing, key, holder, seconds, false)
end)

exports('thingTouch', function(thingId, key, holder, seconds)
    local thing, owner = ownedThing(thingId)
    local id = thing and lockKey(owner, thingId, key)
    local lock = id and locks[id]
    if not lock or lock.holder ~= holder or GetGameTimer() >= lock.expires then return false end
    lock.expires = GetGameTimer() + leaseMs(seconds)
    adopt(id, lock)
    return true
end)

exports('thingRelease', function(thingId, key, holder)
    local thing, owner = ownedThing(thingId)
    local id = thing and lockKey(owner, thingId, key)
    if not id then return false end
    return clear(id, holder)
end)

exports('thingHolder', function(thingId, key)
    local thing, owner = ownedThing(thingId)
    local id = thing and lockKey(owner, thingId, key)
    local lock = id and locks[id]
    if not lock or GetGameTimer() >= lock.expires then return nil end
    return lock.holder
end)
