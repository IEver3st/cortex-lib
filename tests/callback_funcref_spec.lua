-- Cfx funcrefs are callable tables; indexing any field throws in the runtime.
local function funcref(fn)
    return setmetatable({}, {
        __index = function() error('Cannot index a funcref') end,
        __call = function(_, ...) return fn(...) end,
    })
end
local function eq(a,b) assert(a==b, ('expected %s, got %s'):format(tostring(b),tostring(a))) end

for _, side in ipairs({'client','server'}) do
    local events, exports, sent = {}, {}, {}
    local env = setmetatable({lib={},source=41}, {__index=_G})
    env.GetCurrentResourceName=function() return 'cortex-lib' end
    env.GetInvokingResource=function() return 'inventory-consumer' end
    env.GetGameTimer=function() return 100 end
    env.RegisterNetEvent=function(name,fn) events[name]=fn end
    env.AddEventHandler=env.RegisterNetEvent
    env.exports=function(name,fn) exports[name]=fn end
    env.CreateThread=function() end
    env.SetTimeout=function(_,fn) fn() end
    env.TriggerServerEvent=function(...) sent[#sent+1]=table.pack(...) end
    env.TriggerClientEvent=env.TriggerServerEvent
    assert(loadfile('imports/callback/'..side..'.lua','t',env))()
    local function request(name,responder)
        return exports.callback(name,side=='client' and false or 41,responder,'payload')
    end
    -- Lua's and/or cannot represent false as its middle value.
    if side=='client' then request=function(name,responder) return exports.callback(name,false,responder,'payload') end end
    local function respond(...)
        local outgoing=sent[#sent]
        if side=='client' then events['cortex-lib:callbackResponse'](outgoing[3],outgoing[4],...)
        else events['cortex-lib:clientCallbackResponse'](outgoing[4],outgoing[5],...) end
    end
    local calls, answer=0
    local responder=funcref(function(...) calls=calls+1; answer=table.pack(...) end)
    eq(request('inventory:request',responder),nil)
    respond(nil,'middle',nil); eq(calls,1); eq(answer.n,3); eq(answer[2],'middle')
    respond('duplicate'); eq(calls,1)

    local ok,reason=request('',responder)
    eq(ok,false); eq(reason,'invalid_callback_name'); eq(calls,2); eq(answer[2],reason)

    local hostile=setmetatable({}, {__index=function() error('not a promise') end})
    ok,reason=request('invalid:responder',hostile)
    eq(ok,false); eq(reason,'invalid_callback_responder')
    local promise=setmetatable({}, {__index={resolve=function(self,result) self.result=result end}})
    request('promise:request',promise); respond(nil,'promise-result',nil)
    eq(promise.result.n,3); eq(promise.result[2],'promise-result')

    local received
    eq(exports.registerCallback('inventory:registered',funcref(function(...)
        received=table.pack(...); return nil,'registered-result',nil
    end)),nil)
    if side=='client' then
        events['cortex-lib:clientCallback']('inventory:registered','incoming:1','token:1','payload')
        eq(received[1],'payload'); eq(sent[#sent][5],'registered-result'); eq(sent[#sent].n,6)
    else
        events['cortex-lib:callback']('inventory:registered','incoming:1','token:1','payload')
        eq(received[1],41); eq(received[2],'payload'); eq(sent[#sent][6],'registered-result'); eq(sent[#sent].n,7)
    end

    request('pending:request',responder)
    events[side=='client' and 'onClientResourceStop' or 'onResourceStop']('inventory-consumer')
    eq(calls,3); eq(answer[2],'resource_stopped')
    respond('late'); eq(calls,3)
    print('PASS '..side..' funcref responder, registration, rejection, promise and owner cleanup')
end
