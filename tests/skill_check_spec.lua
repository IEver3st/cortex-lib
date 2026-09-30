-- Standalone deterministic lifecycle fixture; no FiveM/CEF claims.
local callbacks, events, jobs, messages = {}, {}, {}, {}
local now, caller, modal, focus, dead = 0, 'consumer', nil, false, false
local entry = { anchor={}, active=true, visible=true, key='R' }
local mouseX, mouseY, cancelled, disabled = 0, 0, false, {}
function DisableControlAction(_, control) disabled[control]=true end
function DisablePlayerFiring() end
function PlayerId() return 1 end
function IsDisabledControlJustPressed(_, control) return control==200 and cancelled end
function IsUsingKeyboard() return true end
function GetDisabledControlUnboundNormal(_, control) return control==1 and mouseX or mouseY end
function GetCurrentResourceName() return 'cortex-lib' end
function GetInvokingResource() return caller end
function GetGameTimer() return now end
function PlayerPedId() return 1 end
function IsEntityDead() return dead end
function IsNuiFocused() return focus end
function IsPauseMenuActive() return false end
function RegisterNUICallback(name, fn) callbacks[name] = fn end
function AddEventHandler(name, fn) events[name] = fn end
function SendNUIMessage(data) messages[#messages+1] = data end
function exports() end
function Wait() coroutine.yield() end
function CreateThread(fn) jobs[#jobs+1] = coroutine.create(fn) end
promise = { new=function() return { resolve=function(self, result) self.result=result end } end }
Citizen = { Await=function(p) while not p.result do coroutine.yield() end return p.result end }
local closer
lib = {
    _registerModalSurface=function(_, fn) closer=fn end,
    _acquireModal=function() if focus then return nil end modal=1 return modal end,
    _focusModal=function() focus=true return true end,
    _releaseModal=function() modal=nil focus=false end,
    _hasModalSurface=function() return modal~=nil end,
    _getInteractionForSkillCheck=function(owner, id) if owner=='consumer' and id=='target' then return entry end end,
}
local function read(path) local file=assert(io.open(path)); local source=file:read('*a'); file:close(); return source end
assert(load(read('imports/skillCheck/shared.lua') .. '\n' .. read('imports/skillCheck/client.lua')))()
local function invoke(name, data)
    local count, result = 0
    callbacks[name](data, function(value) count=count+1 result=value end)
    assert(count==1, name .. ' must reply exactly once')
    return result
end
local function resume(co) local ok, err=coroutine.resume(co) assert(ok, err) end
local function start(config)
    local result = {}
    local co=coroutine.create(function() result.success,result.reason=lib.skillCheck(config) end)
    resume(co)
    return co,result,messages[#messages].data.session
end
local function pump() for _, job in ipairs(jobs) do if coroutine.status(job)~='dead' then resume(job) end end end
for _,bad in ipairs({ {type='bad'}, {duration=0/0}, {targetStart=.9,targetSize=.2}, {keys={ [1]='E',[3]='R' }}, {type='mash'}, {key='ESCAPE'}, {type='trace',sensitivity=0}, {type='trace',sensitivity=5}, {type='trace',tolerance=1} }) do
    local ok, reason=lib.skillCheck(bad) assert(ok==false and reason=='invalid_options')
end
local co,result,id=start({type='radial'})
assert(not focus)
assert(select(2,lib.skillCheck({}))=='busy')
assert(not invoke('skillReady',{session=id-1}).ok)
assert(invoke('skillReady',{session=id}).ok and focus)
assert(not invoke('skillResult',{session=id,success='true',reason='success'}).ok)
assert(not invoke('skillResult',{session=id,success=true,reason={}}).ok)
assert(invoke('skillResult',{session=id,success=true,reason='success'}).ok)
resume(co) assert(result.success and not focus)
assert(not invoke('skillResult',{session=id,success=true,reason='success'}).ok)

co,result,id=start({type='trace'})
invoke('skillReady',{session=id})
assert(not focus, 'mouse gestures must never take cursor or keyboard NUI focus')
assert(not invoke('skillResult',{session=id,success=true,reason='success'}).ok, 'NUI cannot complete native gestures')
pump()
assert(disabled[1] and disabled[2], 'camera axes must be suppressed while native mouse input is sampled')
closer() resume(co) assert(result.reason=='interrupted' and not focus)
disabled={}; pump(); assert(next(disabled)==nil, 'look suppression must stop immediately after cleanup')
co,result,id=start({type='trace',direction='lower'}) invoke('skillReady',{session=id})
local previousX, previousY = 1, 0
for i=1,60 do
    local angle=math.pi*i/60
    local x,y=math.cos(angle),math.sin(angle)
    mouseX,mouseY=x-previousX,y-previousY
    previousX,previousY=x,y
    now=now+16; pump()
end
mouseX,mouseY=0,0
resume(co) assert(result.success, 'native relative mouse arc must complete without a NUI result')
local traceMessages={}
for _,message in ipairs(messages) do if message.action=='skill:trace' and message.data.session==id then traceMessages[#traceMessages+1]=message.data end end
assert(#traceMessages>=2 and #traceMessages<=40, 'trace presentation is rate limited')
assert(traceMessages[#traceMessages].progress==1, 'completion is sent immediately as a full knob')
co,result,id=start({type='trace',direction='upper',sensitivity=2}) invoke('skillReady',{session=id})
previousX, previousY = .5, 0
for i=1,40 do
    local angle=math.pi*i/40
    local x,y=.5*math.cos(angle),-.5*math.sin(angle)
    mouseX,mouseY=x-previousX,y-previousY
    previousX,previousY=x,y
    now=now+16; pump()
end
mouseX,mouseY=0,0
resume(co) assert(result.success, 'sensitivity 2 completes a half-size upper arc')
co,result,id=start({type='trace'}) invoke('skillReady',{session=id})
cancelled=true; pump(); cancelled=false; resume(co); assert(result.reason=='cancelled')
co,result,id=start({type='trace'}) invoke('skillReady',{session=id})
focus=true; pump(); resume(co); assert(result.reason=='interrupted')
co,result,id=start({type='hold'})
pump() now=now+3100 pump() resume(co) assert(result.reason=='ui_timeout')
co,result,id=start({type='sequence',duration=1000})
invoke('skillReady',{session=id}) now=now+1001 pump() resume(co) assert(result.reason=='timeout')

co,result,id=start({type='mash',interactionId='target',gain=.5,decay=.1})
assert(not focus)
assert(not lib.skillCheckPress('target',true))
invoke('skillReady',{session=id})
assert(not invoke('skillResult',{session=id,success=true,reason='success'}).ok)
caller='other' assert(not lib.skillCheckPress('target',true)) assert(not lib.cancelSkillCheck()) caller='consumer'
assert(lib.skillCheckPress('target',true))
assert(not lib.skillCheckPress('target',true), 'held key cannot repeat')
now=now+1000 pump()
assert(lib.skillCheckPress('target',false)) assert(lib.skillCheckPress('target',true))
local progress=messages[#messages].data.progress
assert(math.abs(progress-.9)<.0001, 'decay uses elapsed time')
lib.skillCheckPress('target',false) now=now+100 lib.skillCheckPress('target',true)
resume(co) assert(result.success)

co,result,id=start({type='mash',interactionId='target'}) invoke('skillReady',{session=id})
entry.visible=false pump() resume(co) assert(result.reason=='interaction_unavailable') entry.visible=true
co,result,id=start({type='mash',interactionId='target'}) invoke('skillReady',{session=id})
entry={anchor={},active=true,visible=true,key='R'} pump() resume(co) assert(result.reason=='interaction_unavailable')
co,result,id=start({type='radial'}) invoke('skillReady',{session=id})
events.onClientResourceStop('other') assert(lib.isSkillCheckActive())
events.onClientResourceStop('consumer') resume(co) assert(result.reason=='resource_stopped' and not focus)
co,result,id=start({type='radial'}) invoke('skillReady',{session=id}) dead=true pump() resume(co) assert(result.reason=='dead')
print('skill check lifecycle spec: PASS')
