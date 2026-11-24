local RESOURCE = GetCurrentResourceName()

local FRAMEWORK_ORDER = { { 'qbx_core', 'qbx' }, { 'qb-core', 'qb' }, { 'es_extended', 'esx' } }
local FRAMEWORK_RESOURCES = { qbx_core = true, ['qb-core'] = true, es_extended = true }
local FORCED_FRAMEWORKS = { qbx = true, qb = true, esx = true, standalone = true }

local framework = { version = 1 }

local detectedKind
local coreObject

local function try(fn, ...)
    local results = table.pack(pcall(fn, ...))
    if not results[1] then return false end
    return true, table.unpack(results, 2, results.n)
end

local function nonEmpty(value)
    return type(value) == 'string' and value ~= '' and value or nil
end

local function kind()
    if detectedKind then return detectedKind end
    local forced = GetConvar('cortex_framework', 'auto'):lower()
    if FORCED_FRAMEWORKS[forced] then
        detectedKind = forced
        return forced
    end
    for index = 1, #FRAMEWORK_ORDER do
        if GetResourceState(FRAMEWORK_ORDER[index][1]) == 'started' then
            detectedKind = FRAMEWORK_ORDER[index][2]
            return detectedKind
        end
    end
    for index = 1, #FRAMEWORK_ORDER do
        local state = GetResourceState(FRAMEWORK_ORDER[index][1])
        if state == 'starting' or state == 'stopping' then return FRAMEWORK_ORDER[index][2] end
    end
    detectedKind = 'standalone'
    return 'standalone'
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

local function isLoaded()
    local current = kind()
    if current == 'standalone' then return NetworkIsPlayerActive(PlayerId()) end
    if current == 'qbx' or current == 'qb' then return LocalPlayer.state.isLoggedIn == true end
    local object = core()
    if not object then return false end
    if object.IsPlayerLoaded then
        local ok, value = try(object.IsPlayerLoaded)
        return ok and value == true
    end
    local ok, fresh = try(function() return exports.es_extended:getSharedObject() end)
    return ok and type(fresh) == 'table' and fresh.PlayerLoaded == true
end

local function rawData()
    local current = kind()
    if not isLoaded() then return nil, current end
    local ok, data
    if current == 'qbx' then
        ok, data = try(function() return exports.qbx_core:GetPlayerData() end)
    elseif current == 'qb' then
        local object = core()
        if not object or type(object.Functions) ~= 'table' then return nil, current end
        ok, data = try(object.Functions.GetPlayerData)
    elseif current == 'esx' then
        local object = core()
        if not object then return nil, current end
        ok, data = try(object.GetPlayerData)
    end
    if ok and type(data) == 'table' and next(data) ~= nil then return data, current end
    return nil, current
end

local function normalJob(job, current)
    if type(job) ~= 'table' or not nonEmpty(job.name) then return nil end
    local grade, onDuty
    if current == 'esx' then
        grade = tonumber(job.grade) or 0
        onDuty = job.onDuty ~= false
    else
        grade = type(job.grade) == 'table' and (job.grade.level or 0) or tonumber(job.grade) or 0
        onDuty = job.onduty == true
    end
    grade = tonumber(grade) or 0
    return {
        name = job.name,
        grade = math.tointeger(grade) or math.floor(grade),
        onDuty = onDuty,
        label = nonEmpty(job.label),
        type = nonEmpty(job.type),
    }
end

function framework.kind()
    return kind()
end

function framework.raw()
    return (rawData())
end

function framework.isLoaded()
    return isLoaded()
end

function framework.playerData()
    local data, current = rawData()
    if not data then return nil end
    if current == 'esx' then
        local first, last = nonEmpty(data.firstName), nonEmpty(data.lastName)
        return {
            characterId = nonEmpty(data.identifier),
            name = first and (last and ('%s %s'):format(first, last) or first) or nonEmpty(data.name),
            job = normalJob(data.job, current),
        }
    end
    local info = type(data.charinfo) == 'table' and data.charinfo or {}
    local first, last = nonEmpty(info.firstname), nonEmpty(info.lastname)
    return {
        characterId = nonEmpty(data.citizenid),
        name = first and (last and ('%s %s'):format(first, last) or first) or nil,
        job = normalJob(data.job, current),
    }
end

function framework.job()
    local data, current = rawData()
    local job = data and normalJob(data.job, current)
    if not job then return nil, 0, false, nil, nil end
    return job.name, job.grade, job.onDuty, job.label, job.type
end

local loadedHandlers = {}
local unloadedHandlers = {}
local jobHandlers = {}
local lastJob
local wired = false

local function run(handlers, ...)
    for index = 1, #handlers do
        local ok, err = pcall(handlers[index], ...)
        if not ok then print(('^1[%s] framework handler failed: %s^0'):format(RESOURCE, tostring(err))) end
    end
end

local function jobChanged(job, duty)
    local current = kind()
    local changed = normalJob(job, current)
    if not changed then
        local data = rawData()
        changed = data and normalJob(data.job, current)
    end
    if not changed then return end
    if type(duty) == 'boolean' then changed.onDuty = duty end
    local signature = ('%s|%s|%s'):format(changed.name, changed.grade, tostring(changed.onDuty))
    if signature == lastJob then return end
    lastJob = signature
    run(jobHandlers, changed.name, changed.grade, changed.onDuty, changed.label, changed.type)
end

local loadGeneration = 0
local loadWaiting = false
local loadedFor

local function characterKey(data)
    return data and (nonEmpty(data.citizenid) or nonEmpty(data.identifier)) or nil
end

local function runWhenLoaded()
    if loadedFor and characterKey((rawData())) == loadedFor then return end
    loadGeneration = loadGeneration + 1
    local generation = loadGeneration
    loadWaiting = true
    CreateThread(function()
        local deadline = GetGameTimer() + 30000
        local data = rawData()
        while not data and generation == loadGeneration and GetGameTimer() < deadline do
            Wait(50)
            data = rawData()
        end
        if generation ~= loadGeneration then return end
        loadWaiting = false
        if not data then
            print(('^3[%s] the character did not finish loading on %s within 30 seconds, so its load handlers did not run^0'):format(RESOURCE, kind()))
            return
        end
        loadedFor = characterKey(data) or true
        run(loadedHandlers)
    end)
end

local function runUnloaded()
    loadGeneration = loadGeneration + 1
    loadWaiting = false
    loadedFor = nil
    lastJob = nil
    run(unloadedHandlers)
end

local function wire()
    if wired then return end
    wired = true

    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        local current = kind()
        if current == 'qbx' or current == 'qb' then runWhenLoaded() end
    end)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
        local current = kind()
        if current == 'qbx' or current == 'qb' then runUnloaded() end
    end)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
        local current = kind()
        if current == 'qbx' or current == 'qb' then jobChanged(job) end
    end)
    RegisterNetEvent('QBCore:Client:SetDuty', function(duty)
        local current = kind()
        if current == 'qbx' or current == 'qb' then jobChanged(nil, duty == true) end
    end)
    RegisterNetEvent('esx:playerLoaded', function()
        if kind() == 'esx' then runWhenLoaded() end
    end)
    RegisterNetEvent('esx:onPlayerLogout', function()
        if kind() == 'esx' then runUnloaded() end
    end)
    RegisterNetEvent('esx:setJob', function(job)
        if kind() == 'esx' then jobChanged(job) end
    end)
end

function framework.onLoaded(handler)
    if type(handler) ~= 'function' then return false end
    wire()
    loadedHandlers[#loadedHandlers + 1] = handler
    if loadWaiting then return true end
    local data = rawData()
    if data then
        loadedFor = loadedFor or characterKey(data) or true
        SetTimeout(0, function()
            local ok, err = pcall(handler)
            if not ok then print(('^1[%s] framework handler failed: %s^0'):format(RESOURCE, tostring(err))) end
        end)
    elseif isLoaded() then
        runWhenLoaded()
    end
    return true
end

function framework.onUnloaded(handler)
    if type(handler) ~= 'function' then return false end
    wire()
    unloadedHandlers[#unloadedHandlers + 1] = handler
    return true
end

function framework.onJobChanged(handler)
    if type(handler) ~= 'function' then return false end
    wire()
    jobHandlers[#jobHandlers + 1] = handler
    return true
end

local function forget(name)
    if not FRAMEWORK_RESOURCES[name] then return end
    detectedKind = nil
    coreObject = nil
    lastJob = nil
    loadedFor = nil
end

AddEventHandler('onClientResourceStart', forget)
AddEventHandler('onClientResourceStop', forget)

lib.framework = framework

return framework
