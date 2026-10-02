-- Local, explicitly invoked diagnostics. This is not the legacy /cortex demo suite.
-- Every scenario calls the public library API; no arbitrary NUI code or commands run.
if GetConvarInt('cortex_debug', 0) ~= 1 then return end

local RESOURCE, SURFACE = GetCurrentResourceName(), 'debugWorkbench'
local PREFIX = 'cortexdebug:'
local catalog, actions, history = {}, {}, {}
local session, generation, running = nil, 0, false
local cleanupTasks, noticeIds, interactionIds = {}, {}, {}
local progressOwned, textOwned, helpOwned, debugOwned = false, false, false, false
local externalFocusOwned = false
local inputSession
local mashInputId
local walkthrough, returnPending
local runRevision = 0
local pauseActive = false
AddEventHandler('cortex-lib:pauseChanged', function(active) pauseActive = active == true end)

local function runState()
    if not walkthrough then return false end
    local item = catalog[walkthrough.index]
    return {index=math.min(walkthrough.index,#catalog),completed=walkthrough.completed,total=#catalog,
        id=item and item.id,title=item and item.title or 'Complete',errors=walkthrough.errors}
end
local function publishRun()
    runRevision=runRevision+1
    SendNUIMessage({action='debug:walkthrough',data={revision=runRevision,run=runState()}})
end
local positions = { ['top-right']=true, ['top-left']=true, top=true, ['bottom-right']=true, ['bottom-left']=true, bottom=true }

local function add(id, group, title, description, run)
    catalog[#catalog + 1] = { id=id, group=group, title=title, description=description }
    actions[id] = run
end

local function record(id, status, detail)
    table.insert(history, 1, { id=id, status=status, detail=tostring(detail or ''):sub(1, 512) })
    while #history > 100 do table.remove(history) end
    if session then SendNUIMessage({ action='debug:history', data={ session=session, history=history } }) end
end

local function notice(data)
    data.id = PREFIX .. (data.id or 'notice')
    noticeIds[data.id] = true
    return lib.notify(data)
end

local function ownCleanup(fn) cleanupTasks[#cleanupTasks + 1] = fn end
local function check(ok, err) if ok == false or ok == nil then error(tostring(err or 'The library rejected the test.'), 0) end return ok end

local function clean()
    if mashInputId then
        lib.skillCheckPress(mashInputId, false)
        mashInputId = nil
    end
    returnPending = nil
    if not walkthrough then publishRun() end
    generation = generation + 1
    running = false
    if progressOwned then pcall(lib.cancelProgress); progressOwned = false end
    if textOwned then pcall(lib.hideTextUI); textOwned = false end
    if helpOwned then pcall(lib.hideHelp); helpOwned = false end
    if debugOwned then pcall(lib.hideDebugPanel); debugOwned = false end
    for id in pairs(noticeIds) do pcall(lib.hideNotify, id) end
    for id in pairs(interactionIds) do pcall(lib.cancelInteractionHold, id); pcall(lib.hideInteraction, id) end
    noticeIds, interactionIds = {}, {}
    for i = #cleanupTasks, 1, -1 do pcall(cleanupTasks[i]) end
    cleanupTasks = {}
    if lib.getOpenMenu() == PREFIX .. 'menu' then lib.hideMenu() end
    local radial = lib.getCurrentRadialId()
    if type(radial) == 'string' and radial:sub(1, #PREFIX) == PREFIX then lib.hideRadial() end
end

local function close()
    local previous = session
    session = nil
    if previous then
        lib._releaseModal(SURFACE, previous)
        SendNUIMessage({ action='debug:close', data={ session=previous } })
    end
end

lib._registerModalSurface(SURFACE, function(previous)
    if previous == session then
        session = nil
        walkthrough = nil
        clean()
        SendNUIMessage({ action='debug:close', data={ session=previous } })
    end
end)

local function prompt(data)
    data.id = PREFIX .. (data.id or 'prompt')
    interactionIds[data.id] = true
    check(lib.showInteraction(data))
    return data.id
end

add('notify', 'Notifications', 'Single event', 'A compact, description-only notification. Choose its message, duration and placement below.', function(o)
    notice({ type='success', description=o.message, duration=o.duration, position=o.position })
    return 'Displayed. Inspect the shape, type and countdown in-game.'
end)
add('notify_types', 'Notifications', 'All status types', 'Success, error, warning and information, with titles and supporting text.', function(o)
    for _, kind in ipairs({'success','error','warning','info'}) do
        notice({ id=kind, type=kind, title=kind, description=o.message, duration=o.duration, position=o.position })
    end
    return 'Four notices displayed.'
end)
add('notify_long', 'Notifications', 'Long content', 'Wrapping, narrow stacks and long words. No message should escape its surface.', function(o)
    notice({ type='warning', title='Equipment configuration updated', description=o.message .. ' The assigned vehicle is unavailable. Return to the depot to collect a replacement. Reference: CORTEX0123456789012345678901234567890123456789', duration=o.duration, position=o.position })
    return 'Long-content notification displayed.'
end)
add('notify_persistent', 'Notifications', 'Persistent / update', 'Keeps one notice visible, then updates that same ID. Return here to clear it.', function(o, token)
    notice({ id='persistent', title='Persistent notice', description=o.message, persistent=true, position=o.position })
    Wait(1500)
    if token ~= generation then return 'Stopped' end
    notice({ id='persistent', title='Updated in place', description='The same notification ID was updated.', persistent=true, position=o.position })
    return 'Persistent notification updated; /cortexdebug cleans it up.'
end)
add('notify_plain', 'Notifications', 'Plain / icon-free', 'The caller-controlled plain and hidden-icon variants.', function(o)
    notice({ plain=true, hideIcon=true, description=o.message, duration=o.duration, position=o.position })
    return 'Plain notice displayed.'
end)

for _, kind in ipairs({'bar','circle','locked'}) do
    local style = kind
    add('progress_' .. style, 'Progress', style == 'locked' and 'Non-cancelable' or (style == 'bar' and 'Linear progress' or 'Circular progress'),
        style == 'locked' and 'Runs to completion. Returning to the workbench still stops the debug test.' or 'Watch the live percentage, then cancel with Backspace or let it finish.', function(o, token)
        if lib.isProgressActive() then error('Another progress operation is already active.', 0) end
        progressOwned = true
        local completed = lib.progress({ label=o.message, duration=o.duration, style=style == 'circle' and 'circle' or 'bar', canCancel=style ~= 'locked' })
        if token == generation then progressOwned = false end
        return completed and 'Completed' or 'Canceled'
    end)
end

for _, backing in ipairs({'plain','backdrop'}) do
    local variant = backing
    add('text_' .. variant, 'Prompts', variant == 'plain' and 'Floating text' or 'Backed text', 'Shows a real Text UI prompt until the test expires or you return.', function(o)
        check(lib.showTextUI(o.message, { position='bottom-center', backdrop=variant == 'backdrop', icon='hand' }))
        textOwned = true
        return 'Text UI displayed.'
    end)
end
add('help', 'Prompts', 'Key hints', 'Multiple controls and compound key labels through lib.showHelp.', function()
    check(lib.showHelp({ {label='Open equipment',value='E'}, {label='Adjust',value='SHIFT E'}, {label='Cancel',value='BACKSPACE'} }))
    helpOwned = true
    return 'Help bar displayed.'
end)
add('debug_panel', 'Prompts', 'Live debug panel', 'Real player/cache data in the shared telemetry overlay.', function()
    check(lib.showDebugPanel({ title='Cortex diagnostics', subtitle='Live local snapshot', lines={
        {label='Player', value=GetPlayerServerId(PlayerId())}, {label='Ped',value=PlayerPedId()},
        {label='Vehicle',value=cache.vehicle or 0}, {label='Seat',value=cache.seat or -1} } }))
    debugOwned = true
    return 'Debug panel displayed with current local values.'
end)

for _, count in ipairs({5,30}) do
    local amount = count
    add(amount == 5 and 'menu' or 'menu_long', 'Menus', amount == 5 and 'List menu / controls' or 'Long scrolling menu', 'Selection, side-scroll values, checkboxes, progress and tooltip text. Escape closes the sample.', function()
        local options = {
            {label='Select this item',description='The callback records your selection in the workbench.'},
            {label='Equipment mode',values={'Standard','Patrol','Emergency'},description='Use left and right arrows.'},
            {label='Enabled',checked=true,description='Space toggles this choice.'},
            {label='Installation',progress=65,description='Static embedded progress: 65 percent.'},
            {label='A longer menu label that should remain readable within a narrow list',description='Description text should wrap without pushing actions off-screen.'},
        }
        for i=6,amount do options[i]={label='Library option ' .. i,description='Scrolling sample ' .. i} end
        check(lib.registerMenu({ id=PREFIX .. 'menu', title='Field equipment', subtitle='Cortex debug specimen', position='top-right', options=options,
            onSideScroll=function(index,value) record('menu','result',('Row %s, value %s'):format(index,value)) end,
            onCheck=function(index,value) record('menu','result',('Row %s: %s'):format(index,tostring(value))) end },
            function(index) record('menu','result','Selected row ' .. index) end))
        check(lib.showMenu(PREFIX .. 'menu'))
        return 'Menu opened. Selection results are recorded here.'
    end)
end
for _, variant in ipairs({'basic','pages','compact'}) do
    local appearance = variant
    add('radial_' .. variant, 'Menus', variant == 'basic' and 'Radial wheel' or (variant == 'pages' and 'Radial pagination' or 'Hardware radial'),
        'Real wheel geometry and keyboard/pointer selection. The center is Back/Close.', function()
        local items = {}
        for i=1,(appearance == 'pages' and 18 or 6) do
            local index=i
            items[i]={id='item' .. i,label=({'Equipment','Inventory','Radio','Vehicle','Actions','Settings'})[(i-1)%6+1],
                onSelect=function() record('radial_' .. appearance,'result','Selected action ' .. index) end}
        end
        check(lib.registerRadial({id=PREFIX .. appearance, appearance=appearance == 'compact' and 'compact-control' or nil, items=items}))
        check(lib.showRadial(PREFIX .. appearance))
        return 'Radial opened.'
    end)
end
add('alert', 'Dialogs', 'Confirmation', 'Confirm, Cancel and Escape through the real alert promise.', function(o)
    local result=lib.alertDialog({header='Replace equipment?',content=o.message,cancel=true,labels={confirm='Replace',cancel='Keep current'}})
    return 'Dialog returned: ' .. tostring(result)
end)
add('context', 'Dialogs', 'Input form', 'Text, checkbox and dropdown values, including a long final option.', function()
    local values=lib.contextMenu({title='Equipment profile', values={name='Patrol',enabled=true,mode='standard'}, fields={
        {name='name',type='input',label='Profile name'},
        {name='enabled',type='checkbox',label='Enable audio feedback'},
        {name='mode',type='select',label='Operation',options={{label='Standard',value='standard'},{label='Extended equipment configuration for night patrol',value='extended'}}},
    }})
    return values and json.encode(values) or 'Canceled'
end)

for _, kind in ipairs({'screen','target','world','entity','bone','hold','collision'}) do
    local variant=kind
    add('interaction_' .. kind, 'Interactions', ({screen='Screen prompt',target='Target panel',world='World anchor',entity='Entity anchor',bone='Bone anchor',hold='Hold / cancel ring',collision='Key arbitration'})[kind],
        'Display-only sample. No gameplay action is attached. Move around to inspect visibility; return to remove the test prompts.', function(o,token)
        local ped=PlayerPedId()
        local coords=GetEntityCoords(ped)
        local data={key='F7',label='Inspect equipment',priority=-100}
        if variant=='target' then data.panel={id=PREFIX .. 'target',label='FIELD EQUIPMENT',variant='target'}
        elseif variant=='world' or variant=='hold' then data.anchor={type='world',x=coords.x+1,y=coords.y,z=coords.z,maxDistance=5.0}
        elseif variant=='entity' or variant=='bone' then
            local vehicle=GetVehiclePedIsIn(ped,false)
            local entity=vehicle ~= 0 and vehicle or ped
            data.anchor={type=variant=='bone' and 'entity-bone' or 'entity',entity=entity,model=GetEntityModel(entity),maxDistance=5.0,
                bone=variant=='bone' and (vehicle ~= 0 and 'chassis' or 'SKEL_Head') or nil}
        end
        if variant=='hold' then data.holdDuration=2000 end
        local id=prompt(data)
        if variant=='collision' then prompt({id='collision',key='F7',label='Higher priority wins',priority=-99}) end
        if variant=='hold' then
            Wait(300)
            if token ~= generation then return 'Stopped' end
            check(lib.startInteractionHold(id))
            Wait(1200)
            if token ~= generation then return 'Stopped' end
            lib.cancelInteractionHold(id)
            return 'Ring started and canceled before completion.'
        end
        return 'Registered; active=' .. tostring(lib.isInteractionActive(id)) .. '. Visibility remains renderer-owned.'
    end)
end

add('settings', 'Settings & input', 'Script settings', 'Opens your real settings, including sound presets. Save changes your preferences; Discard rolls them back.', function()
    check(lib.openSettingsMenu())
    return 'Settings opened.'
end)
add('pause', 'Settings & input', 'Quick menu / native handoffs', 'Opens the shared quick menu. Test map, native settings and script settings there.', function()
    check(exports[RESOURCE]:openPauseMenu())
    return 'Quick menu opened.'
end)
add('controls', 'Settings & input', 'Control suppression', 'Disables attack for two seconds, then restores it. Movement and camera stay available.', function(_,token)
    lib.load('disablecontrols')
    local control=lib.disableControls({combat=true})
    ownCleanup(function() control:Destroy() end)
    Wait(2000)
    control:Destroy()
    return token == generation and 'Combat controls restored.' or 'Stopped'
end)

for _, shape in ipairs({'sphere','box','poly'}) do
    local kind=shape
    add('zone_' .. shape, 'World & utilities', shape .. ' zone', 'Creates a temporary 3-metre zone at your position. Entry and exit callbacks are recorded.', function()
        lib.load('zones')
        local c=GetEntityCoords(PlayerPedId())
        local data={coords=c,radius=3,size=vector3(6,6,4),rotation=0,thickness=4,debug=true,
            points={vector3(c.x-3,c.y-3,c.z),vector3(c.x+3,c.y-3,c.z),vector3(c.x+3,c.y+3,c.z),vector3(c.x-3,c.y+3,c.z)},
            onEnter=function() record('zone_' .. kind,'result','Entered zone') end,
            onExit=function() record('zone_' .. kind,'result','Exited zone') end}
        local zone=lib.zones[kind](data)
        ownCleanup(function() zone:remove() end)
        return 'Zone created. Walk out and back in.'
    end)
end
add('points', 'World & utilities', 'Proximity point', 'Creates a temporary point at your feet. Walk three metres away and return.', function()
    lib.load('points')
    local point=lib.points.new({coords=GetEntityCoords(PlayerPedId()),distance=3,
        onEnter=function() record('points','result','Entered point') end,
        onExit=function() record('points','result','Exited point') end})
    ownCleanup(function() point:remove() end)
    return 'Point created.'
end)
add('raycast', 'World & utilities', 'Camera raycast', 'Reads the current camera ray without modifying the hit entity.', function()
    lib.load('raycast')
    local hit,entity,coords,_,material,err=lib.raycast.fromCamera(511,PlayerPedId(),50.0)
    if err then error(err,0) end
    return ('Hit=%s entity=%s position=%s material=%s'):format(tostring(hit),tostring(entity),tostring(coords),tostring(material))
end)
add('getters', 'World & utilities', 'Nearby entities / cache', 'Reads nearby entities and the current cache. Nothing is spawned, moved or removed.', function()
    local c=GetEntityCoords(PlayerPedId())
    return ('Players=%d vehicles=%d peds=%d objects=%d | cache ped=%s vehicle=%s seat=%s'):format(
        #lib.getNearbyPlayers(c,20.0,true),#lib.getNearbyVehicles(c,20.0,true),#lib.getNearbyPeds(c,20.0),#lib.getNearbyObjects(c,20.0),
        tostring(cache.ped),tostring(cache.vehicle),tostring(cache.seat))
end)
add('timer', 'World & utilities', 'Timer', 'Starts a two-second library timer and records its actual completion.', function(_,token)
    lib.load('timer')
    local timer=lib.timer(2000,function() if token==generation then record('timer','result','Timer callback fired') end end)
    ownCleanup(function() timer:forceEnd(false) end)
    return 'Timer started.'
end)
add('waitfor', 'World & utilities', 'WaitFor', 'Waits for a delayed local condition through the library timeout boundary.', function(_,token)
    lib.load('waitFor')
    local ready=false
    SetTimeout(350,function() ready=true end)
    local result=lib.waitFor(function() if token~=generation then return 'stopped' end if ready then return 'ready' end end,'debug wait timed out',1500)
    return 'waitFor returned: ' .. tostring(result)
end)
add('utils', 'World & utilities', 'JSON / math / table helpers', 'Exercises library utilities using isolated values, without writing player KVPs.', function()
    lib.load('utils')
    local encoded=lib.safeJsonEncode({test='cortexdebug',value=lib.round(1.2345,2)})
    local decoded=lib.safeJsonDecode(encoded)
    local merged=lib.mergeDefaults({one=1},{two=2})
    assert(decoded and decoded.value==1.23 and merged.one==1 and merged.two==2,'utility result mismatch')
    return 'JSON round trip, rounding and default merge matched expected values.'
end)
add('assets', 'World & utilities', 'Asset loaders', 'Loads a stock model and animation dictionary, then releases both. Spawns nothing.', function(_,token)
    local model=GetHashKey('prop_tool_box_04')
    local dict='amb@world_human_hammering@male@base'
    ownCleanup(function() SetModelAsNoLongerNeeded(model); RemoveAnimDict(dict) end)
    check(lib.requestModel(model))
    if token ~= generation then SetModelAsNoLongerNeeded(model); return 'Stopped' end
    check(lib.requestAnimDict(dict))
    SetModelAsNoLongerNeeded(model); RemoveAnimDict(dict)
    return 'Model and animation dictionary loaded and released.'
end)
add('callback', 'World & utilities', 'Server callback round trip', 'Calls the dedicated read-only debug endpoint through lib.callback.await.', function()
    local response,err=lib.callback.await('cortex-lib:debugProbe',false,'cortexdebug')
    if not response then error(err or 'No server response',0) end
    assert(response.probe=='cortexdebug' and response.ok==true,'unexpected callback response')
    return 'Server callback returned the expected probe.'
end)
add('skillcheck', 'Integrations', 'Skill check / ox_lib', 'Runs the installed ox_lib timing minigame with easy, medium and hard stages. This is an external UI, not a Cortex-native minigame.', function()
    if GetResourceState('ox_lib')~='started' then error('Start ox_lib to run its skill check.',0) end
    if exports.ox_lib:skillCheckActive() then error('Another skill check is already running.',0) end
    local active=true
    externalFocusOwned=true
    ownCleanup(function() if active and GetResourceState('ox_lib')=='started' and exports.ox_lib:skillCheckActive() then exports.ox_lib:cancelSkillCheck() end end)
    local ok,passed=pcall(function() return exports.ox_lib:skillCheck({'easy','medium','hard'},{'e'}) end)
    active=false
    externalFocusOwned=false
    if not ok then error(passed,0) end
    return passed and 'Skill check passed' or 'Skill check failed / canceled'
end)

for _, kind in ipairs({'radial', 'trace_upper', 'trace_lower', 'hold', 'sequence'}) do
    local variant = kind
    add('skill_' .. variant, 'Skill checks', ({radial='Radial timing', trace_upper='Trace / upper arc',
        trace_lower='Trace / lower arc', hold='Hold and release', sequence='Key sequence'})[variant],
        variant:match('^trace') and 'Move your physical mouse in one smooth semicircle from right to left. Camera look is locked; no clicking or cursor. Escape cancels.'
            or 'Cortex-native skill check. Escape cancels; the result is recorded here.', function(o)
        if lib.isSkillCheckActive() then error('Another skill check is already active.', 0) end
        local owned = true
        ownCleanup(function() if owned then lib.cancelSkillCheck() end end)
        local passed, reason = lib.skillCheck({ type=variant:match('^trace') and 'trace' or variant,
            direction=variant=='trace_lower' and 'lower' or 'upper',
            label=variant:match('^trace') and 'Mouse sweep' or o.message:sub(1,64), duration=15000 })
        owned = false
        return (passed and 'Passed: ' or 'Ended: ') .. tostring(reason)
    end)
end
-- Debug-only native mapping. The convar gate above keeps it out of players'
-- key binding list unless development diagnostics are enabled. It is inert
-- outside this specimen and follows the same press/release contract as
-- consumer-owned gameplay bindings.
RegisterCommand('+cortexdebug_mash', function()
    if mashInputId and lib.isInteractionVisible(mashInputId) and not IsNuiFocused() and not IsPauseMenuActive() then
        lib.skillCheckPress(mashInputId, true)
    end
end, false)
RegisterCommand('-cortexdebug_mash', function()
    if mashInputId then lib.skillCheckPress(mashInputId, false) end
end, false)
RegisterKeyMapping('+cortexdebug_mash', 'Cortex: debug reactive mash', 'keyboard', 'R')

add('skill_mash', 'Skill checks', '3D reactive mash',
    'Tap the debug mash binding (default R) to fill the world arc. Leaving range or looking away cancels.', function(_, token)
    if lib.isSkillCheckActive() then error('Another skill check is already active.', 0) end
    local point = GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 1.5, 0.0)
    local id = prompt({id='mash', key='MASH', label='Build pressure', priority=-100,
        anchor={type='world', x=point.x, y=point.y, z=point.z, maxDistance=3.0}})
    local owned = true
    ownCleanup(function() if owned then lib.cancelSkillCheck() end end)
    mashInputId = id
    ownCleanup(function()
        lib.skillCheckPress(id, false)
        if mashInputId == id then mashInputId = nil end
    end)
    local deadline = GetGameTimer() + 3000
    while token == generation and not lib.isInteractionVisible(id) and GetGameTimer() < deadline do Wait(50) end
    if token ~= generation then return 'Stopped' end
    local passed, reason = lib.skillCheck({type='mash', interactionId=id, duration=15000})
    owned = false
    lib.skillCheckPress(id, false)
    if mashInputId == id then mashInputId = nil end
    lib.hideInteraction(id)
    interactionIds[id] = nil
    return (passed and 'Passed: ' or 'Ended: ') .. tostring(reason)
end)

local function showWorkbench()
    session=lib._acquireModal(SURFACE,RESOURCE)
    if not session then return false end
    local current=session
    SendNUIMessage({action='debug:open',data={session=session,catalog=catalog,history=history,run=runState()}})
    SetTimeout(5000,function()
        if session==current and not lib._getModalState().focused then
            walkthrough=nil; clean(); close()
        end
    end)
    return true
end

local function open()
    local awaitingExternal = externalFocusOwned
    walkthrough=nil
    clean()
    local state=lib._getModalState()
    if state.surface and state.resource ~= RESOURCE then
        notice({type='info',description='Close the other resource menu before opening Cortex debug.',duration=3000})
        return
    end
    local token=generation
    local function acquire(attempt)
        if token~=generation or session then return end
        local currentState=lib._getModalState()
        if currentState.surface and currentState.resource~=RESOURCE then return end
        if not showWorkbench() then
            -- An owned ox_lib cancel releases focus on its asynchronous NUI reply.
            if awaitingExternal and attempt<10 then SetTimeout(50,function() acquire(attempt+1) end) end
        end
    end
    acquire(0)
end

local function valid(data)
    return type(data)=='table' and session ~= nil and lib._matchesModal(SURFACE,session,data.session)
end
local function startMenuInput(current)
    if inputSession==current then return end
    inputSession=current
    CreateThread(function()
        local controls={24,25,257,140,141,142,14,15,16,17,99,100,241,242,172,173,174,175,191,194,200,202}
        local bindings={{241,'up'},{242,'down'},{172,'up'},{173,'down'},{174,'left'},{175,'right'},
            {24,'enter'},{191,'enter'},{25,'back'},{194,'back'},{200,'back'},{202,'back'}}
        while session==current do
            -- Movement and camera axes remain untouched. Menu clicks must not fire weapons.
            for _,control in ipairs(controls) do DisableControlAction(0,control,true) end
            DisablePlayerFiring(PlayerId(),true)
            for _,binding in ipairs(bindings) do
                if IsDisabledControlJustPressed(0,binding[1]) then
                    SendNUIMessage({action='debug:input',data={session=current,input=binding[2]}})
                    break
                end
            end
            Wait(0)
        end
        -- Consume the closing click until release; it must not become a gunshot.
        repeat
            DisableControlAction(0,24,true); DisableControlAction(0,25,true)
            DisablePlayerFiring(PlayerId(),true)
            local held=IsDisabledControlPressed(0,24) or IsDisabledControlPressed(0,25)
            if not held then break end
            Wait(0)
        until false
        if inputSession==current then inputSession=nil end
    end)
end
RegisterNUICallback('debugReady',function(data,cb)
    if not valid(data) then cb({ok=false,error='stale_session'}); return end
    local ok=lib._focusModal(SURFACE,session,true,false)
    cb({ok=ok})
    if ok then startMenuInput(session) end
end)
RegisterNUICallback('debugClose',function(data,cb)
    if not valid(data) then cb({ok=false,error='stale_session'}); return end
    walkthrough=nil; clean(); close(); cb({ok=true})
end)
RegisterNUICallback('debugClear',function(data,cb)
    if not valid(data) then cb({ok=false,error='stale_session'}); return end
    walkthrough=nil; clean(); history={}; publishRun(); cb({ok=true})
    SendNUIMessage({action='debug:history',data={session=session,history=history}})
end)
local startTest
local function nextTest(run)
    if walkthrough~=run then return end
    run.completed=run.index
    run.index=run.index+1
    if run.index>#catalog then
        clean()
        record('test_all','result',('Finished %d tests; %d unavailable or errored. Review All tests for results.'):format(#catalog,run.errors))
        publishRun() -- Show a truthful 100% before returning to the menu.
        local token=generation
        SetTimeout(800,function()
            if walkthrough~=run or token~=generation then return end
            walkthrough=nil; publishRun()
            if not lib._getModalState().surface and not IsNuiFocused() and not IsPauseMenuActive() and not pauseActive then showWorkbench() end
        end)
        return
    end
    startTest(catalog[run.index].id,run.options)
end

local function awaitReturn(token, done)
    if token~=generation or returnPending~=token then return end
    local state=lib._getModalState()
    if state.surface and state.resource~=RESOURCE then
        -- A different consumer took over. Never reclaim its modal when it closes.
        walkthrough=nil; clean(); return
    end
    if state.surface or externalFocusOwned or pauseActive or IsPauseMenuActive() or IsNuiFocused() then
        SetTimeout(100,function() awaitReturn(token,done) end)
        return
    end
    clean()
    if not walkthrough and not showWorkbench() then return end
    done(generation)
end

startTest=function(id,o)
    if walkthrough and (lib._getModalState().surface or IsNuiFocused() or IsPauseMenuActive() or pauseActive) then
        walkthrough=nil; clean(); return
    end
    clean()
    running=true
    local token,run=generation,walkthrough
    local needsFocus=id:match('^menu') or id:match('^radial') or id=='alert' or id=='context'
        or id=='settings' or id=='pause' or id=='skillcheck'
        or id:match('^skill_')
    publishRun()
    if needsFocus then returnPending=token; close() end
    CreateThread(function()
        if token~=generation then return end
        record(id,'running','Started')
        local ok,result=pcall(actions[id],o,token)
        if token~=generation then return end
        running=false
        record(id,ok and 'result' or 'error',result)
        if run and not ok then run.errors=run.errors+1 end
        if not ok then notice({id='error',type='error',title='Debug test unavailable',description=tostring(result):sub(1,256),duration=5000}) end
        local function advance(currentToken)
            if not run then return end
            SetTimeout(needsFocus and 1200 or o.duration,function()
                if generation==currentToken and walkthrough==run then nextTest(run) end
            end)
        end
        if needsFocus then
            -- Let the child's close callback finish and consume its closing key.
            SetTimeout(100,function() awaitReturn(token,advance) end)
        else
            advance(token)
        end
    end)
    -- Interactive tests retain their own close lifecycle. The observer has one
    -- timer at a time and is invalidated by Stop, replacement, command or restart.
    if not needsFocus and not run then
        SetTimeout(math.max(o.duration+1500,20000),function() if token==generation then clean() end end)
    end
end

local function validOptions(o)
    return type(o)=='table' and type(o.duration)=='number' and o.duration==o.duration and o.duration>=1000 and o.duration<=15000
        and type(o.message)=='string' and #o.message>=1 and #o.message<=256 and not o.message:find('%c')
        and type(o.position)=='string' and positions[o.position]
end
RegisterNUICallback('debugRun',function(data,cb)
    if not valid(data) then cb({ok=false,error='stale_session'}); return end
    if type(data.id)~='string' or not actions[data.id] or not validOptions(data.options) then
        cb({ok=false,error='invalid_test'}); return
    end
    walkthrough=nil
    cb({ok=true})
    startTest(data.id,data.options)
end)
RegisterNUICallback('debugRunAll',function(data,cb)
    if not valid(data) then cb({ok=false,error='stale_session'}); return end
    if not validOptions(data.options) then cb({ok=false,error='invalid_test'}); return end
    if walkthrough then cb({ok=false,error='already_running'}); return end
    walkthrough={index=0,completed=0,errors=0,options=data.options}
    cb({ok=true})
    close()
    nextTest(walkthrough)
end)
RegisterNUICallback('debugStop',function(data,cb)
    if not valid(data) then cb({ok=false,error='stale_session'}); return end
    walkthrough=nil; clean(); publishRun(); cb({ok=true})
end)
RegisterCommand('cortexdebug',function()
    if session then walkthrough=nil; clean(); close() else open() end
end,false)
AddEventHandler('onResourceStop',function(name) if name==RESOURCE then walkthrough=nil; clean(); close() end end)

return {catalog=catalog}
