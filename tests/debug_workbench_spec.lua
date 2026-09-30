-- Deterministic command/NUI lifecycle checks; no FiveM or CEF execution.
-- Disabled startup must register nothing on either side.
for _, path in ipairs({'client/debug_workbench.lua', 'server/debug_workbench.lua'}) do
    for _, enabled in ipairs({0, 2}) do
        local env = { GetConvarInt = function(name, default)
            assert(name == 'cortex_debug' and default == 0)
            return enabled
        end }
        assert(loadfile(path, 't', env))()
    end
end
function GetConvarInt(name, default)
    assert(name == 'cortex_debug' and default == 0)
    return 1
end

local callbacks, commands, events, messages, jobs, timers = {}, {}, {}, {}, {}, {}
local modal, sequence, closer = {}, 0, nil
local notices, hidden, cancels = {}, {}, 0
local oxStarted, foreignFocus, oxActive, oxCanceled = false, false, false, false
local disabled, pressed = {}, {}
function PlayerId() return 1 end
function DisableControlAction(_,key) disabled[key]=true end
function DisablePlayerFiring() end
function IsDisabledControlJustPressed(_,key) return pressed[key]==true end
function IsDisabledControlPressed() return false end
function GetCurrentResourceName() return 'cortex-lib' end
function RegisterNUICallback(name, fn) callbacks[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
function RegisterKeyMapping(command, _, mapper, key)
    assert(command == '+cortexdebug_mash' and mapper == 'keyboard' and key == 'R')
end
function AddEventHandler(name, fn) events[name] = fn end
function SendNUIMessage(data) messages[#messages+1] = data end
function SetTimeout(ms, fn) timers[#timers+1] = {ms=ms,run=fn} end
function CreateThread(fn) jobs[#jobs+1] = coroutine.create(fn) end
function Wait() coroutine.yield() end
function GetResourceState(name) return name=='ox_lib' and oxStarted and 'started' or 'missing' end
function GetGameTimer() return 0 end
function IsNuiFocused() return foreignFocus end
function IsPauseMenuActive() return false end
function exports() end
lib = {
    _registerModalSurface=function(_,fn) closer=fn end,
    _getModalState=function() return modal end,
    _acquireModal=function(surface,owner)
        if foreignFocus then return nil end
        sequence=sequence+1; modal={surface=surface,resource=owner,generation=sequence}; return sequence
    end,
    _releaseModal=function(_,generation) if modal.generation==generation then modal={} end end,
    _matchesModal=function(surface,generation,supplied) return modal.surface==surface and modal.generation==generation and supplied==generation end,
    _focusModal=function(_,generation,keepInput,cursor)
        assert(keepInput==true and cursor==false,'debug keeps gameplay input and hides the cursor')
        modal.focused=modal.generation==generation; return modal.focused
    end,
    getOpenMenu=function() return nil end, getCurrentRadialId=function() return nil end,
    notify=function(data) notices[#notices+1]=data; return data.id end,
    hideNotify=function(id) hidden[#hidden+1]=id end,
    isProgressActive=function() return false end,
    progress=function() coroutine.yield(); return false end,
    cancelProgress=function() cancels=cancels+1 end,
    load=function() end,
}
local api=dofile('client/debug_workbench.lua')
local ids={}
for _,item in ipairs(api.catalog) do assert(not ids[item.id]); ids[item.id]=true end
for _,id in ipairs({'notify','progress_bar','progress_circle','progress_locked','menu_long','radial_pages','context','interaction_bone','callback','skillcheck'}) do assert(ids[id],id) end
assert(not ids.keybind, 'retired custom binding editor must not appear in diagnostics')
commands['+cortexdebug_mash']()
commands['-cortexdebug_mash']()
local function invoke(name,data)
    local count,result=0,nil
    callbacks[name](data,function(value) count=count+1; result=value end)
    assert(count==1,name .. ' must acknowledge exactly once')
    return result
end
local function open()
    if modal.surface=='debugWorkbench' then commands.cortexdebug() end
    commands.cortexdebug()
    assert(modal.surface=='debugWorkbench')
    assert(invoke('debugReady',{session=modal.generation}).ok and modal.focused)
    return modal.generation
end
local function run(id)
    local session=open()
    assert(invoke('debugRun',{session=session,id=id,options={duration=3000,message='Vehicle spawned.',position='top-right'}}).ok)
    if id=='skillcheck' then assert(not modal.surface,'external UI must receive focus')
    else assert(modal.surface=='debugWorkbench','passive tests keep the side menu open') end
    local job=jobs[#jobs]; assert(coroutine.resume(job)); return job
end
for _,name in ipairs({'debugReady','debugClose','debugClear','debugRun'}) do assert(invoke(name,{}).error=='stale_session') end
local session=open()
local inputJob=jobs[#jobs]
pressed[241]=true
assert(coroutine.resume(inputJob))
assert(messages[#messages].action=='debug:input' and messages[#messages].data.input=='up')
assert(disabled[24] and disabled[25] and disabled[241])
assert(not disabled[30] and not disabled[31] and not disabled[1] and not disabled[2],'movement and camera must remain free')
pressed={}
local initialJobs=#jobs
assert(invoke('debugRun',{session=session,id='ExecuteCommand',options={}}).error=='invalid_test')
assert(invoke('debugRun',{session=session,id='notify',options={duration=math.huge,message='x',position='top-right'}}).error=='invalid_test')
assert(invoke('debugRun',{session=session,id='notify',options={duration=3000,message='x\0y',position='top-right'}}).error=='invalid_test')
assert(#jobs==initialJobs and modal.focused)
assert(invoke('debugClose',{session=session}).ok)
assert(not modal.surface)
assert(coroutine.resume(inputJob))
assert(coroutine.status(inputJob)=='dead','menu input thread must exit after close')
run('notify')
assert(notices[#notices].id=='cortexdebug:notice')
local previous=session; session=open()
assert(hidden[#hidden]=='cortexdebug:notice')
assert(invoke('debugClose',{session=previous}).error=='stale_session' and modal.focused)
assert(invoke('debugClear',{session=session}).ok)
assert(#messages[#messages].data.history==0)
commands.cortexdebug()
local oldProgress=run('progress_bar')
session=open(); assert(cancels==1); commands.cortexdebug()
local newProgress=run('progress_circle')
assert(coroutine.resume(oldProgress)) -- late completion cannot clear the new ownership flag
session=open(); assert(cancels==2)
assert(coroutine.resume(newProgress))
commands.cortexdebug()
run('skillcheck')
assert(notices[#notices].type=='error' and notices[#notices].description:find('Start ox_lib'))
exports=setmetatable({ox_lib={
    skillCheckActive=function() return oxActive end,
    skillCheck=function() oxActive=true; foreignFocus=true; coroutine.yield(); oxActive=false; return false end,
    cancelSkillCheck=function() oxCanceled=true end,
}}, {__call=function() end})
oxStarted=true
local external=run('skillcheck')
commands.cortexdebug()
assert(oxCanceled and not modal.surface,'owned external focus should be canceled before reacquisition')
local retry=timers[#timers]; assert(retry.ms==50)
foreignFocus=false; assert(coroutine.resume(external)); retry.run()
assert(modal.surface=='debugWorkbench')
commands.cortexdebug()
lib.waitFor=dofile('imports/waitFor/shared.lua')
local waiting=run('waitfor')
assert(coroutine.status(waiting)=='suspended','waitFor must receive nil until ready, not false')
for _,timer in ipairs(timers) do if timer.ms==350 then timer.run() end end
assert(coroutine.resume(waiting))
assert(coroutine.status(waiting)=='dead')
session=open()
closer(session); assert(invoke('debugReady',{session=session}).error=='stale_session')
modal={surface='settings',resource='other-consumer'}
commands.cortexdebug(); assert(modal.resource=='other-consumer','debug must not replace another consumer modal')
modal={}; session=open()
events.onResourceStop('other'); assert(modal.surface=='debugWorkbench')
events.onResourceStop('cortex-lib'); assert(not modal.surface)
session=open()
modal.focused=false
timers[#timers].run(); assert(not modal.surface,'unready UI must time out without trapping focus')
-- A sample's close returns without reclaiming a live child.
local options={duration=3000,message='Vehicle spawned.',position='top-right'}
lib.registerMenu=function() return true end
lib.showMenu=function() modal={surface='menu',resource='cortex-lib',generation=sequence+1}; return true end
session=open()
assert(invoke('debugRun',{session=session,id='menu',options=options}).ok)
assert(coroutine.resume(jobs[#jobs]))
assert(modal.surface=='menu')
local observer=timers[#timers]; assert(observer.ms==100); observer.run()
assert(modal.surface=='menu','return must wait for sample close')
modal={}; timers[#timers].run()
assert(modal.surface=='debugWorkbench','sample must return automatically')
assert(invoke('debugReady',{session=modal.generation}).ok)
assert(invoke('debugClose',{session=session}).error=='stale_session')
-- Native pause handoffs outlive the NUI modal.
session=modal.generation
assert(invoke('debugRun',{session=session,id='menu',options=options}).ok)
assert(coroutine.resume(jobs[#jobs])); modal={}
events['cortex-lib:pauseChanged'](true)
timers[#timers].run(); assert(not modal.surface)
events['cortex-lib:pauseChanged'](false)
timers[#timers].run(); assert(modal.surface=='debugWorkbench')
-- Another consumer cancels the return route permanently.
session=modal.generation
assert(invoke('debugRun',{session=session,id='menu',options=options}).ok)
assert(coroutine.resume(jobs[#jobs]))
modal={surface='settings',resource='other-consumer'}
observer=timers[#timers]; observer.run()
assert(modal.resource=='other-consumer')
modal={}; observer.run(); assert(not modal.surface)
-- All catalog entries serialize, including failures and yielding tests.
-- Missing API fixtures intentionally error: this proves traversal only.
oxStarted=false
session=open()
assert(invoke('debugRunAll',{session=session,options={}}).error=='invalid_test')
assert(invoke('debugRunAll',{session=session,options=options}).ok)
assert(not modal.surface,'Test All must release the workbench immediately')
assert(invoke('debugRunAll',{session=session,options=options}).error=='stale_session')
for _,item in ipairs(api.catalog) do
    local job=jobs[#jobs]
    for resume=1,4 do
        if coroutine.status(job)=='dead' then break end
        assert(coroutine.resume(job))
        for _,timer in ipairs(timers) do if timer.ms==350 then timer.run() end end
    end
    assert(coroutine.status(job)=='dead',item.id .. ' did not settle')
    if timers[#timers].ms==100 then
        modal={} -- Simulated user close.
        timers[#timers].run()
    end
    assert(not modal.surface,item.id .. ' must not reopen the debug menu between tests')
    local advance=timers[#timers]
    assert(advance.ms==options.duration or advance.ms==1200)
    advance.run()
end
local finalProgress=messages[#messages]
assert(finalProgress.action=='debug:walkthrough' and finalProgress.data.run.completed==#api.catalog)
assert(finalProgress.data.run.total==#api.catalog and not modal.surface,'100% is shown before menu return')
assert(timers[#timers].ms==800); timers[#timers].run()
assert(modal.surface=='debugWorkbench')
local returned=messages[#messages].data
for _,item in ipairs(api.catalog) do
    local found=false
    for _,entry in ipairs(returned.history) do if entry.id==item.id and entry.status~='running' then found=true end end
    assert(found,item.id .. ' missing outcome')
end
assert(invoke('debugReady',{session=modal.generation}).ok)
-- The command stops a hidden run and invalidates its scheduled next step.
session=open()
assert(invoke('debugRunAll',{session=session,options=options}).ok)
assert(coroutine.resume(jobs[#jobs]))
local advance=timers[#timers]
commands.cortexdebug()
assert(modal.surface=='debugWorkbench')
local count=#jobs; advance.run(); assert(#jobs==count,'canceled walkthrough restarted')
local cleared=false
for _,message in ipairs(messages) do
    if message.action=='debug:walkthrough' then cleared=message.data.run==false end
end
assert(cleared,'stopping must remove the aggregate meter')
-- Resource stop also removes the meter without reopening the menu.
session=open()
assert(invoke('debugRunAll',{session=session,options=options}).ok)
assert(coroutine.resume(jobs[#jobs])); advance=timers[#timers]
events.onResourceStop('cortex-lib'); advance.run()
assert(not modal.surface and messages[#messages].data.run==false)

-- The native debug mapping owns input only during a mash specimen, including
-- key-up during foreign focus and resource-stop cancellation.
local mashEdges, mashVisible = {}, true
function PlayerPedId() return 1 end
function GetOffsetFromEntityInWorldCoords() return {x=0,y=1.5,z=0} end
lib.isSkillCheckActive=function() return false end
lib.showInteraction=function(data) return true,data.id end
lib.hideInteraction=function() end
lib.cancelInteractionHold=function() end
lib.isInteractionVisible=function() return mashVisible end
lib.skillCheckPress=function(id,pressed) mashEdges[#mashEdges+1]={id=id,pressed=pressed} end
lib.skillCheck=function() coroutine.yield(); return false,'canceled' end
lib.cancelSkillCheck=function() end
session=open()
assert(invoke('debugRun',{session=session,id='skill_mash',options=options}).ok)
local mashJob=jobs[#jobs]
assert(coroutine.resume(mashJob))
commands['+cortexdebug_mash']()
assert(mashEdges[#mashEdges].pressed==true)
local edgeCount=#mashEdges
mashVisible=false; commands['+cortexdebug_mash']()
assert(#mashEdges==edgeCount,'hidden prompts cannot receive a press')
mashVisible=true; foreignFocus=true; commands['+cortexdebug_mash']()
assert(#mashEdges==edgeCount,'foreign focus prevents a press')
commands['-cortexdebug_mash']()
assert(mashEdges[#mashEdges].pressed==false,'key-up must release even after focus loss')
foreignFocus=false
events.onResourceStop('cortex-lib')
edgeCount=#mashEdges
commands['+cortexdebug_mash'](); commands['-cortexdebug_mash']()
assert(#mashEdges==edgeCount,'stopped specimens leave the native mapping inert')
assert(coroutine.resume(mashJob))

local registered
lib.callback={register=function(name,fn) assert(name=='cortex-lib:debugProbe'); registered=fn end}
dofile('server/debug_workbench.lua')
assert(registered(7,'cortexdebug').ok)
assert(registered(7,{probe='cortexdebug'})==nil)
print(('debug workbench lifecycle: PASS (%d scenarios)'):format(#api.catalog))
