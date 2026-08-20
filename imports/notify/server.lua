local function notify(source, data)
    if type(data) == 'string' then
        data = { description = data }
    end
    TriggerClientEvent('cortex-lib:notify', source, data)
end

local function notifyAll(data)
    if type(data) == 'string' then
        data = { description = data }
    end
    TriggerClientEvent('cortex-lib:notify', -1, data)
end

exports('notify', notify)
exports('notifyAll', notifyAll)

exports('Notify', function(source, notifyType, message, duration)
    notify(source, {
        type = notifyType or 'info',
        description = message or '',
        duration = duration or 3000
    })
end)

lib.notify = notify
lib.notifyAll = notifyAll

return notify
