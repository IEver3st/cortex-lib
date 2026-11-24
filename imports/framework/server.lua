local RESOURCE = GetCurrentResourceName()
local MAX_AMOUNT = 2147483647
local USABLE_KVP = 'cortex:framework:usable:'

local FRAMEWORK_RESOURCES = { qbx_core = true, ['qb-core'] = true, es_extended = true }
local INVENTORY_RESOURCES = { ox_inventory = true, ['qb-inventory'] = true }
local FORCED_FRAMEWORKS = { qbx = true, qb = true, esx = true, standalone = true }
local FORCED_INVENTORIES = { ox = true, qb = true, esx = true, none = true }
local ACCOUNTS = {
    cash = { qbx = 'cash', qb = 'cash', esx = 'money' },
    bank = { qbx = 'bank', qb = 'bank', esx = 'bank' },
}

local framework = {
    version = 1,
    money = {},
    items = {},
}

local detectedKind
local detectedInventory
local coreObject

local function started(name)
    return GetResourceState(name) == 'started'
end

local FRAMEWORK_ORDER = { { 'qbx_core', 'qbx' }, { 'qb-core', 'qb' }, { 'es_extended', 'esx' } }

local function inFlight(name)
    local state = GetResourceState(name)
    return state == 'starting' or state == 'stopping'
end

local function try(fn, ...)
    local results = table.pack(pcall(fn, ...))
    if not results[1] then return false end
    return true, table.unpack(results, 2, results.n)
end

local function validSource(src)
    src = tonumber(src)
    if not src or src <= 0 or src ~= math.floor(src) then return nil end
    return math.tointeger(src)
end

local function nonEmpty(value)
    return type(value) == 'string' and value ~= '' and value or nil
end

local function wholeAmount(value)
    if type(value) ~= 'number' or value ~= value then return nil end
    local amount = math.tointeger(value)
    if not amount or amount <= 0 or amount > MAX_AMOUNT then return nil end
    return amount
end

local function reasonText(reason)
    if type(reason) ~= 'string' or reason == '' then return RESOURCE end
    return reason:sub(1, 120)
end

local function kind()
    if detectedKind then return detectedKind end
    local forced = GetConvar('cortex_framework', 'auto'):lower()
    if FORCED_FRAMEWORKS[forced] then
        detectedKind = forced
        return forced
    end
    for index = 1, #FRAMEWORK_ORDER do
        if started(FRAMEWORK_ORDER[index][1]) then
            detectedKind = FRAMEWORK_ORDER[index][2]
            return detectedKind
        end
    end
    for index = 1, #FRAMEWORK_ORDER do
        if inFlight(FRAMEWORK_ORDER[index][1]) then return FRAMEWORK_ORDER[index][2] end
    end
    detectedKind = 'standalone'
    return 'standalone'
end

local function inventory()
    if detectedInventory then return detectedInventory end
    local forced = GetConvar('cortex_framework_inventory', 'auto'):lower()
    local current = kind()
    local found
    if FORCED_INVENTORIES[forced] then
        found = forced
    elseif started('ox_inventory') then
        found = 'ox'
    elseif current == 'qb' then
        found = 'qb'
    elseif current == 'esx' then
        found = 'esx'
    else
        found = 'none'
    end
    if detectedKind and not inFlight('ox_inventory') and not inFlight('qb-inventory') then detectedInventory = found end
    return found
end

local function core()
    if coreObject then return coreObject end
    local current = kind()
    local ok, object
    if current == 'qb' then
        ok, object = try(function() return exports['qb-core']:GetCoreObject() end)
    elseif current == 'esx' then
        ok, object = try(function() return exports.es_extended:getSharedObject() end)
    end
    if ok and type(object) == 'table' then coreObject = object end
    return coreObject
end

local function player(src)
    src = validSource(src)
    if not src then return nil end
    local current = kind()
    local ok, found
    if current == 'qbx' then
        ok, found = try(function() return exports.qbx_core:GetPlayer(src) end)
    elseif current == 'qb' then
        local object = core()
        if not object or type(object.Functions) ~= 'table' then return nil, current end
        ok, found = try(object.Functions.GetPlayer, src)
    elseif current == 'esx' then
        local object = core()
        if not object then return nil, current end
        ok, found = try(object.GetPlayerFromId, src)
    end
    if ok and type(found) == 'table' and not found.Offline then return found, current end
    return nil, current
end

local function playerData(src)
    local found, current = player(src)
    if not found then return nil, current, nil end
    if current == 'esx' then return found, current, found end
    local data = found.PlayerData
    if type(data) ~= 'table' then return nil, current, found end
    return data, current, found
end

function framework.kind()
    return kind()
end

function framework.inventory()
    return inventory()
end

function framework.describe()
    return ('%s framework, %s inventory'):format(kind(), inventory())
end

function framework.raw(src)
    return (player(src))
end

function framework.isLoaded(src)
    src = validSource(src)
    if not src then return false end
    if kind() == 'standalone' then return GetPlayerName(src) ~= nil end
    return player(src) ~= nil
end

function framework.identifier(src, prefix)
    src = validSource(src)
    if not src or not nonEmpty(prefix) then return nil end
    local ok, identifiers = try(GetPlayerIdentifiers, src)
    if not ok or type(identifiers) ~= 'table' then return nil end
    local head = prefix .. ':'
    for _, identifier in ipairs(identifiers) do
        if type(identifier) == 'string' and identifier:sub(1, #head) == head then return identifier end
    end
    return nil
end

function framework.license(src)
    return framework.identifier(src, 'license')
end

function framework.characterId(src)
    local data, current = playerData(src)
    if not data then return nil end
    if current == 'esx' then
        local identifier = nonEmpty(data.identifier)
        if identifier then return identifier end
        local ok, value = try(data.getIdentifier)
        return ok and nonEmpty(value) or nil
    end
    return nonEmpty(data.citizenid)
end

function framework.characterName(src)
    src = validSource(src)
    if not src then return '#?' end
    local data, current = playerData(src)
    if data and current == 'esx' then
        local okFirst, first = try(data.get, 'firstName')
        local okLast, last = try(data.get, 'lastName')
        first = okFirst and nonEmpty(first) or nil
        last = okLast and nonEmpty(last) or nil
        if first then return last and ('%s %s'):format(first, last) or first end
        local okName, name = try(data.getName)
        if okName and nonEmpty(name) then return name end
    elseif data then
        local info = data.charinfo
        if type(info) == 'table' and nonEmpty(info.firstname) then
            local last = nonEmpty(info.lastname)
            return last and ('%s %s'):format(info.firstname, last) or info.firstname
        end
    end
    return GetPlayerName(src) or ('#' .. src)
end

function framework.meta(src, key)
    if not nonEmpty(key) then return nil end
    local data, current = playerData(src)
    if not data then return nil end
    if current == 'esx' then
        if not data.getMeta then return nil end
        local ok, value = try(data.getMeta, key)
        if ok then return value end
        return nil
    end
    if type(data.metadata) ~= 'table' then return nil end
    return data.metadata[key]
end

function framework.sourceOf(characterId)
    if not nonEmpty(characterId) then return nil end
    local current = kind()
    local ok, found
    if current == 'qbx' then
        ok, found = try(function() return exports.qbx_core:GetPlayerByCitizenId(characterId) end)
    elseif current == 'qb' then
        local object = core()
        if not object or type(object.Functions) ~= 'table' then return nil end
        ok, found = try(object.Functions.GetPlayerByCitizenId, characterId)
    elseif current == 'esx' then
        local object = core()
        if not object then return nil end
        ok, found = try(object.GetPlayerFromIdentifier, characterId)
    end
    if not ok or type(found) ~= 'table' or found.Offline then return nil end
    local src = current == 'esx' and found.source or (type(found.PlayerData) == 'table' and found.PlayerData.source)
    src = validSource(src)
    if not src or GetPlayerName(src) == nil then return nil end
    return src
end

local function jobOf(src)
    local data, current = playerData(src)
    if not data then return nil end
    local job
    if current == 'esx' then
        local ok, value = try(data.getJob)
        job = ok and value or data.job
    else
        job = data.job
    end
    if type(job) ~= 'table' or not nonEmpty(job.name) then return nil end
    return job, current, data
end

function framework.job(src)
    local job, current = jobOf(src)
    if not job then return nil, 0, false, nil, nil end
    local grade, onDuty
    if current == 'esx' then
        grade = tonumber(job.grade) or 0
        onDuty = job.onDuty ~= false
    else
        grade = type(job.grade) == 'table' and (job.grade.level or 0) or tonumber(job.grade) or 0
        onDuty = job.onduty == true
    end
    grade = tonumber(grade) or 0
    return job.name, math.tointeger(grade) or math.floor(grade), onDuty, nonEmpty(job.label), nonEmpty(job.type)
end

local function groupFilter(filter)
    local wanted = {}
    if type(filter) == 'string' then
        if filter ~= '' then wanted[filter] = 0 end
    elseif type(filter) == 'table' then
        for key, value in pairs(filter) do
            if type(key) == 'number' and type(value) == 'string' and value ~= '' then
                wanted[value] = 0
            elseif type(key) == 'string' and key ~= '' then
                wanted[key] = tonumber(value) or 0
            end
        end
    end
    return next(wanted) and wanted or nil
end

function framework.hasGroup(src, filter)
    src = validSource(src)
    local wanted = groupFilter(filter)
    if not src or not wanted then return false end
    local found, current = player(src)
    if not found then return false end
    if current == 'qbx' then
        local ok, allowed = try(function() return exports.qbx_core:HasGroup(src, wanted) end)
        return ok and allowed == true
    end
    local name, grade = framework.job(src)
    if name and wanted[name] and grade >= wanted[name] then return true end
    if current == 'qb' then
        local gang = type(found.PlayerData) == 'table' and found.PlayerData.gang
        if type(gang) == 'table' and nonEmpty(gang.name) and wanted[gang.name] then
            local gangGrade = type(gang.grade) == 'table' and (gang.grade.level or 0) or tonumber(gang.grade) or 0
            return (tonumber(gangGrade) or 0) >= wanted[gang.name]
        end
    end
    return false
end

local function balance(src, account)
    local names = ACCOUNTS[account]
    if not names then return nil, 'bad_account' end
    local found, current = player(src)
    if current == 'standalone' then return nil, 'no_framework' end
    if not found then return nil, 'no_player' end
    local ok, value
    if current == 'qbx' then
        ok, value = try(function() return exports.qbx_core:GetMoney(validSource(src), names.qbx) end)
    elseif current == 'qb' then
        if type(found.Functions) == 'table' and found.Functions.GetMoney then
            ok, value = try(found.Functions.GetMoney, names.qb)
        end
        if (not ok or type(value) ~= 'number') and type(found.PlayerData) == 'table' and type(found.PlayerData.money) == 'table' then
            ok, value = true, found.PlayerData.money[names.qb]
        end
    else
        local okAccount, entry = try(found.getAccount, names.esx)
        ok, value = okAccount, okAccount and type(entry) == 'table' and entry.money or nil
    end
    if not ok or type(value) ~= 'number' then return nil, 'error' end
    return value, nil, found, current, names
end

function framework.money.get(src, account)
    local value = balance(src, account)
    return value
end

local function settled(direction, src, account, before, amount)
    local after = balance(src, account)
    local expected = direction == 'add' and before + amount or before - amount
    if after == expected then return true end
    return false, 'unknown'
end

local function moveMoney(direction, src, account, amount, reason)
    amount = wholeAmount(amount)
    if not amount then return false, 'bad_amount' end
    local before, code, found, current, names = balance(src, account)
    if not before then return false, code end
    if direction == 'remove' and before < amount then return false, 'insufficient' end
    reason = reasonText(reason)
    local ok, result, receipt
    if current == 'qbx' then
        local id = validSource(src)
        if direction == 'add' then
            ok, result, receipt = try(function() return exports.qbx_core:AddMoney(id, names.qbx, amount, reason) end)
        else
            ok, result, receipt = try(function() return exports.qbx_core:RemoveMoney(id, names.qbx, amount, reason) end)
        end
        if not ok then return settled(direction, src, account, before, amount) end
        if result == true then return true end
        if type(receipt) == 'table' and receipt.status ~= 'rejected' then return false, 'unknown' end
        return false, 'rejected'
    end
    if current == 'qb' then
        local method = type(found.Functions) == 'table' and found.Functions[direction == 'add' and 'AddMoney' or 'RemoveMoney']
        if not method then return false, 'error' end
        ok, result = try(method, names.qb, amount, reason)
        if not ok then return settled(direction, src, account, before, amount) end
        if result == true then return true end
        return false, 'rejected'
    end
    local method = found[direction == 'add' and 'addAccountMoney' or 'removeAccountMoney']
    if not method then return false, 'error' end
    ok, result = try(method, names.esx, amount, reason)
    if ok and type(result) == 'boolean' then
        if result then return true end
        return false, 'rejected'
    end
    return settled(direction, src, account, before, amount)
end

function framework.money.add(src, account, amount, reason)
    return moveMoney('add', src, account, amount, reason)
end

function framework.money.remove(src, account, amount, reason)
    return moveMoney('remove', src, account, amount, reason)
end

local function itemName(item)
    if type(item) ~= 'string' or item == '' or #item > 64 then return nil end
    return item
end

local function stackAmount(stack)
    if type(stack) ~= 'table' then return 0 end
    return math.max(0, math.floor(tonumber(stack.amount) or tonumber(stack.count) or 0))
end

local function qbInventory()
    return started('qb-inventory')
end

local function qbMethod(found, name)
    return type(found.Functions) == 'table' and found.Functions[name] or nil
end

local function qbAdd(src, found, item, amount, slot, metadata)
    if qbInventory() then
        return try(function() return exports['qb-inventory']:AddItem(src, item, amount, slot, metadata, RESOURCE) end)
    end
    return try(qbMethod(found, 'AddItem'), item, amount, slot, metadata, RESOURCE)
end

local function qbRemove(src, found, item, amount, slot)
    if qbInventory() then
        return try(function() return exports['qb-inventory']:RemoveItem(src, item, amount, slot, RESOURCE) end)
    end
    return try(qbMethod(found, 'RemoveItem'), item, amount, slot, RESOURCE)
end

local function qbUsable(found)
    return qbInventory() or (qbMethod(found, 'AddItem') ~= nil and qbMethod(found, 'RemoveItem') ~= nil)
end

local function qbStacks(src, found, item)
    if qbInventory() then
        local ok, stacks = try(function() return exports['qb-inventory']:GetItemsByName(src, item) end)
        if ok and type(stacks) == 'table' then return stacks end
        return nil
    end
    if type(found.Functions) ~= 'table' then return nil end
    if found.Functions.GetItemsByName then
        local ok, stacks = try(found.Functions.GetItemsByName, item)
        if ok and type(stacks) == 'table' then return stacks end
    end
    if found.Functions.GetItemByName then
        local ok, stack = try(found.Functions.GetItemByName, item)
        if ok then return type(stack) == 'table' and { stack } or {} end
    end
    return nil
end

local function count(src, item)
    src = validSource(src)
    item = itemName(item)
    if not src or not item then return 0 end
    local current = inventory()
    if current == 'ox' then
        local ok, value = try(function() return exports.ox_inventory:GetItemCount(src, item) end)
        return ok and math.max(0, math.floor(tonumber(value) or 0)) or 0
    end
    local found = player(src)
    if not found then return 0 end
    if current == 'qb' then
        local total = 0
        for _, stack in pairs(qbStacks(src, found, item) or {}) do
            total = total + stackAmount(stack)
        end
        return total
    end
    if current == 'esx' and found.getInventoryItem then
        local ok, entry = try(found.getInventoryItem, item)
        return ok and stackAmount(entry) or 0
    end
    return 0
end

local function canCarry(src, item, amount)
    local current = inventory()
    if current == 'ox' then
        local ok, value = try(function() return exports.ox_inventory:CanCarryItem(src, item, amount) end)
        return ok and value == true
    end
    local found = player(src)
    if not found then return false end
    if current == 'qb' then
        if qbInventory() then
            local ok, value = try(function() return exports['qb-inventory']:CanAddItem(src, item, amount) end)
            return ok and value == true
        end
        return qbMethod(found, 'AddItem') ~= nil
    end
    if current == 'esx' and found.canCarryItem then
        local ok, value = try(found.canCarryItem, item, amount)
        return ok and value == true
    end
    return false
end

function framework.items.count(src, item)
    return count(src, item)
end

function framework.items.has(src, item, amount)
    if amount == nil then amount = 1 else amount = wholeAmount(amount) end
    if not amount then return false end
    return count(src, item) >= amount
end

function framework.items.canCarry(src, item, amount)
    src = validSource(src)
    item = itemName(item)
    if amount == nil then amount = 1 else amount = wholeAmount(amount) end
    if not src or not item or not amount then return false end
    return canCarry(src, item, amount)
end

local function itemBox(src, item, direction, amount)
    if kind() ~= 'qb' or not started('qb-inventory') then return end
    local object = core()
    local definitions = object and type(object.Shared) == 'table' and object.Shared.Items
    local definition = type(definitions) == 'table' and definitions[item]
    if definition then TriggerClientEvent('qb-inventory:client:ItemBox', src, definition, direction, amount) end
end

local function countSettled(direction, src, item, before, amount)
    local after = count(src, item)
    local expected = direction == 'add' and before + amount or before - amount
    if after == expected then return true end
    return false, 'unknown'
end

function framework.items.add(src, item, amount, metadata)
    src = validSource(src)
    item = itemName(item)
    if amount == nil then amount = 1 else amount = wholeAmount(amount) end
    if not src then return false, 'no_player' end
    if not item then return false, 'bad_item' end
    if not amount then return false, 'bad_amount' end
    if metadata ~= nil and type(metadata) ~= 'table' then return false, 'bad_item' end
    local current = inventory()
    if current == 'none' then return false, 'no_inventory' end
    if current == 'ox' then
        local ok, added, response = try(function() return exports.ox_inventory:AddItem(src, item, amount, metadata) end)
        if not ok or response == 'unknown_outcome' then return false, 'unknown' end
        if added == true then return true end
        return false, 'rejected'
    end
    local found = player(src)
    if not found then return false, 'no_player' end
    if current == 'qb' then
        if not qbUsable(found) then return false, 'no_inventory' end
        local before = count(src, item)
        local ok, added = qbAdd(src, found, item, amount, false, metadata)
        if not ok then return countSettled('add', src, item, before, amount) end
        if added ~= true then return false, 'rejected' end
        itemBox(src, item, 'add', amount)
        return true
    end
    if metadata ~= nil then return false, 'unsupported' end
    if not found.addInventoryItem then return false, 'no_inventory' end
    if not canCarry(src, item, amount) then return false, 'rejected' end
    local before = count(src, item)
    local ok, added = try(found.addInventoryItem, item, amount)
    if ok and type(added) == 'boolean' then
        if added then return true end
        return false, 'rejected'
    end
    return countSettled('add', src, item, before, amount)
end

local function removeQb(src, found, item, amount, slot)
    if not qbUsable(found) then return false, 'no_inventory' end
    local before = count(src, item)
    if slot ~= nil then
        local ok, removed = qbRemove(src, found, item, amount, slot)
        if not ok then return countSettled('remove', src, item, before, amount) end
        if removed ~= true then return false, 'rejected' end
        return true
    end
    local stacks = qbStacks(src, found, item)
    if not stacks then return false, 'no_inventory' end
    local plan, planned = {}, 0
    for _, stack in pairs(stacks) do
        if planned >= amount then break end
        local held = stackAmount(stack)
        local stackSlot = type(stack) == 'table' and tonumber(stack.slot)
        if held > 0 and stackSlot then
            local take = math.min(held, amount - planned)
            plan[#plan + 1] = { slot = stackSlot, take = take, info = stack.info }
            planned = planned + take
        end
    end
    if planned < amount then return false, 'insufficient' end
    local done = {}
    for _, step in ipairs(plan) do
        local ok, removed = qbRemove(src, found, item, step.take, step.slot)
        if not ok or removed ~= true then
            for _, undo in ipairs(done) do
                qbAdd(src, found, item, undo.take, undo.slot, undo.info)
            end
            if count(src, item) == before then return false, 'rejected' end
            return false, 'unknown'
        end
        done[#done + 1] = step
    end
    return true
end

function framework.items.remove(src, item, amount, metadata, slot)
    src = validSource(src)
    item = itemName(item)
    if amount == nil then amount = 1 else amount = wholeAmount(amount) end
    if not src then return false, 'no_player' end
    if not item then return false, 'bad_item' end
    if not amount then return false, 'bad_amount' end
    if metadata ~= nil and type(metadata) ~= 'table' then return false, 'bad_item' end
    if slot ~= nil then
        slot = math.tointeger(tonumber(slot) or -1)
        if not slot or slot < 1 then return false, 'bad_item' end
    end
    local current = inventory()
    if current == 'none' then return false, 'no_inventory' end
    if current == 'ox' then
        if slot == nil then
            local counted, held = try(function() return exports.ox_inventory:GetItemCount(src, item, metadata) end)
            if counted and (tonumber(held) or 0) < amount then return false, 'insufficient' end
        end
        local ok, removed, response = try(function() return exports.ox_inventory:RemoveItem(src, item, amount, metadata, slot) end)
        if not ok or response == 'unknown_outcome' then return false, 'unknown' end
        if removed == true then return true end
        return false, 'rejected'
    end
    if metadata ~= nil then return false, 'unsupported' end
    local found = player(src)
    if not found then return false, 'no_player' end
    if current == 'qb' then
        local ok, code = removeQb(src, found, item, amount, slot)
        if ok then itemBox(src, item, 'remove', amount) end
        return ok, code
    end
    if slot ~= nil then return false, 'unsupported' end
    if not found.removeInventoryItem then return false, 'no_inventory' end
    local before = count(src, item)
    if before < amount then return false, 'insufficient' end
    local ok, removed = try(found.removeInventoryItem, item, amount)
    if ok and type(removed) == 'boolean' then
        if removed then return true end
        return false, 'rejected'
    end
    return countSettled('remove', src, item, before, amount)
end

local usableHandlers = {}
local usableBound = {}

local function usedItem(item, data, extra)
    if type(data) ~= 'table' and type(extra) == 'table' then data = extra end
    if type(data) == 'table' then
        return {
            name = nonEmpty(data.name) or item,
            slot = tonumber(data.slot),
            metadata = type(data.metadata) == 'table' and data.metadata or type(data.info) == 'table' and data.info or {},
        }
    end
    return { name = item, metadata = {} }
end

local function usableOwner(item, current)
    local ok, owner
    if current == 'qbx' then
        ok, owner = try(function() return exports.qbx_core:CanUseItem(item) end)
    elseif current == 'qb' then
        local object = core()
        if object and type(object.Functions) == 'table' and object.Functions.CanUseItem then
            ok, owner = try(object.Functions.CanUseItem, item)
        end
        if ok and type(owner) == 'table' and type(owner.resource) == 'string' then
            if owner.resource == RESOURCE then return false, true end
            if owner.resource ~= 'qb-core' and GetResourceState(owner.resource) == 'started' then return true, true end
        end
    elseif current == 'esx' then
        local object = core()
        if object and object.GetUsableItems then
            local listed, items = try(object.GetUsableItems)
            ok, owner = listed, listed and type(items) == 'table' and items[item] or nil
        end
    end
    return ok and owner ~= nil and owner ~= false, false
end

local function ownClaim(item, current)
    local stored = GetResourceKvpString(USABLE_KVP .. item)
    if type(stored) ~= 'string' then return false end
    local claimedKind, claimedAt = stored:match('^(%a+)|(%d+)$')
    if claimedKind ~= current then return false end
    local uptime = GetGameTimer()
    if type(uptime) ~= 'number' or uptime < 0 then return true end
    local bootedAt = os.time() - uptime // 1000
    return tonumber(claimedAt) >= bootedAt - 5
end

local function bindUsable(item, force)
    local current = kind()
    if current == 'standalone' then return false, 'no_framework' end
    if not force and usableBound[item] ~= current then
        local owned, certain = usableOwner(item, current)
        if owned and (certain or not ownClaim(item, current)) then return false, 'taken' end
    end
    local function onUse(src, data, extra)
        local handler = usableHandlers[item]
        src = validSource(src)
        if not handler or not src then return end
        local ok, err = pcall(handler, src, usedItem(item, data, extra))
        if not ok then print(('^1[%s] usable item %s failed: %s^0'):format(RESOURCE, item, tostring(err))) end
    end
    local ok = false
    if current == 'qbx' then
        ok = try(function() exports.qbx_core:CreateUseableItem(item, onUse) end)
    elseif current == 'qb' then
        local object = core()
        if object and type(object.Functions) == 'table' then ok = try(object.Functions.CreateUseableItem, item, onUse) end
    elseif current == 'esx' then
        local object = core()
        if object and object.RegisterUsableItem then ok = try(object.RegisterUsableItem, item, onUse) end
    end
    if not ok then return false, 'error' end
    usableBound[item] = current
    SetResourceKvp(USABLE_KVP .. item, ('%s|%d'):format(current, os.time()))
    return true
end

local function unbindUsable(item)
    local current = usableBound[item]
    usableBound[item] = nil
    if not current then return end
    local cleared = false
    if current == 'qbx' and started('qbx_core') then
        cleared = try(function() exports.qbx_core:CreateUseableItem(item, nil) end)
    elseif current == 'esx' and started('es_extended') then
        local object = core()
        if object and object.RegisterUsableItem then cleared = try(object.RegisterUsableItem, item, nil) end
    end
    if cleared then DeleteResourceKvp(USABLE_KVP .. item) end
end

function framework.items.usable(item, handler, options)
    item = itemName(item)
    if not item or type(handler) ~= 'function' then return false, 'bad_item' end
    local ok, code = bindUsable(item, type(options) == 'table' and options.force == true)
    if ok or code == 'no_framework' or code == 'error' then usableHandlers[item] = handler end
    return ok, code
end

function framework.items.releaseUsable(item)
    if type(item) ~= 'string' then return end
    usableHandlers[item] = nil
    unbindUsable(item)
end

local loadedHandlers = {}
local unloadedHandlers = {}
local loaded = {}
local wired = false

local function runHandler(handler, src, reason)
    local ok, err = pcall(handler, src, reason)
    if not ok then print(('^1[%s] framework handler failed: %s^0'):format(RESOURCE, tostring(err))) end
end

local function markLoaded(src)
    src = validSource(src)
    if not src then return end
    SetTimeout(0, function()
        if loaded[src] or not framework.isLoaded(src) then return end
        loaded[src] = true
        for index = 1, #loadedHandlers do runHandler(loadedHandlers[index], src) end
    end)
end

local function markUnloaded(src, reason)
    src = validSource(src)
    if not src or not loaded[src] then return end
    loaded[src] = nil
    for index = 1, #unloadedHandlers do runHandler(unloadedHandlers[index], src, reason) end
end

local function trusted(src)
    local origin = source
    if origin == nil or origin == '' or origin == 0 then return true end
    return validSource(origin) ~= nil and validSource(origin) == validSource(src)
end

local function wire()
    if wired then return end
    wired = true

    AddEventHandler('QBCore:Server:PlayerLoaded', function(loadedPlayer)
        local current = kind()
        if current ~= 'qbx' and current ~= 'qb' then return end
        local data = type(loadedPlayer) == 'table' and loadedPlayer.PlayerData
        local src = type(data) == 'table' and data.source or nil
        if trusted(src) then markLoaded(src) end
    end)
    AddEventHandler('QBCore:Server:PlayerDropped', function(src)
        if kind() == 'qb' and trusted(src) then markUnloaded(src, 'drop') end
    end)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
        local current = kind()
        if (current == 'qbx' or current == 'qb') and trusted(src) then markUnloaded(src, 'logout') end
    end)
    AddEventHandler('qbx_core:server:playerLoggedOut', function(src)
        if kind() == 'qbx' and trusted(src) then markUnloaded(src, 'logout') end
    end)
    AddEventHandler('esx:playerLoaded', function(src)
        if kind() == 'esx' and trusted(src) then markLoaded(src) end
    end)
    AddEventHandler('esx:playerLogout', function(src)
        if kind() == 'esx' and trusted(src) then markUnloaded(src, 'logout') end
    end)
    AddEventHandler('esx:playerDropped', function(src, reason)
        if kind() == 'esx' and trusted(src) then markUnloaded(src, reason == 'esx_player_logout' and 'logout' or 'drop') end
    end)
    AddEventHandler('playerJoining', function()
        if kind() == 'standalone' then markLoaded(source) end
    end)
    AddEventHandler('playerDropped', function()
        markUnloaded(source, 'drop')
    end)

    for _, id in ipairs(GetPlayers()) do
        local src = validSource(id)
        if src and framework.isLoaded(src) then loaded[src] = true end
    end
end

function framework.onLoaded(handler)
    if type(handler) ~= 'function' then return false end
    wire()
    loadedHandlers[#loadedHandlers + 1] = handler
    local already = {}
    for src in pairs(loaded) do already[#already + 1] = src end
    SetTimeout(0, function()
        for index = 1, #already do
            if loaded[already[index]] then runHandler(handler, already[index]) end
        end
    end)
    return true
end

function framework.onUnloaded(handler)
    if type(handler) ~= 'function' then return false end
    wire()
    unloadedHandlers[#unloadedHandlers + 1] = handler
    return true
end

local function forget(name)
    if not FRAMEWORK_RESOURCES[name] and not INVENTORY_RESOURCES[name] then return false end
    detectedKind = nil
    detectedInventory = nil
    coreObject = nil
    return FRAMEWORK_RESOURCES[name] == true
end

AddEventHandler('onResourceStart', forget)
AddEventHandler('onServerResourceStop', forget)
AddEventHandler('onResourceStop', function(name)
    if name == RESOURCE then
        for item in pairs(usableBound) do unbindUsable(item) end
        return
    end
    if forget(name) then usableBound = {} end
end)
AddEventHandler('onServerResourceStart', function(name)
    if not forget(name) then return end
    usableBound = {}
    SetTimeout(500, function()
        for item in pairs(usableHandlers) do bindUsable(item, true) end
    end)
end)
AddEventHandler('QBCore:Server:UpdateObject', function()
    local origin = source
    if origin == nil or origin == '' or origin == 0 then coreObject = nil end
end)

lib.framework = framework

return framework
