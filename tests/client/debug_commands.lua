--[[
    cortex-lib Test Menu
    Single menu interface to test all library features
]]

-- ============================================================================
-- NOTIFICATION TESTS
-- ============================================================================

local function testAllNotifyTypes()
    CreateThread(function()
        lib.notify({ type = 'success', title = 'Success', description = 'Operation completed!', duration = 2000 })
        Wait(200)
        lib.notify({ type = 'error', title = 'Error', description = 'Something went wrong!', duration = 2000 })
        Wait(200)
        lib.notify({ type = 'warning', title = 'Warning', description = 'Proceed with caution!', duration = 2000 })
        Wait(200)
        lib.notify({ type = 'info', title = 'Info', description = 'This is an info message', duration = 2000 })
        Wait(200)
        lib.notify({ type = 'inform', title = 'Inform', description = 'Another info style', duration = 2000 })
    end)
end

local function testAllPositions()
    CreateThread(function()
        lib.notify({ type = 'info', title = 'Top Right', description = 'top-right', position = 'top-right', duration = 1500 })
        Wait(150)
        lib.notify({ type = 'info', title = 'Top Left', description = 'top-left', position = 'top-left', duration = 1500 })
        Wait(150)
        lib.notify({ type = 'info', title = 'Top Center', description = 'top', position = 'top', duration = 1500 })
        Wait(150)
        lib.notify({ type = 'info', title = 'Bottom Right', description = 'bottom-right', position = 'bottom-right', duration = 1500 })
        Wait(150)
        lib.notify({ type = 'info', title = 'Bottom Left', description = 'bottom-left', position = 'bottom-left', duration = 1500 })
        Wait(150)
        lib.notify({ type = 'info', title = 'Bottom Center', description = 'bottom', position = 'bottom', duration = 1500 })
    end)
end

local function testPersistentNotify()
    lib.notify({
        type = 'warning',
        title = 'Persistent',
        description = 'Click X to dismiss this notification',
        persistent = true
    })
end

local function testUpdateById()
    lib.notify({
        id = 'cortex-update-test',
        type = 'info',
        title = 'Update Test',
        description = 'Updating in 3 seconds...',
        duration = 0
    })
    Wait(3000)
    lib.notify({
        id = 'cortex-update-test',
        type = 'success',
        title = 'Update Test',
        description = 'Updated successfully!',
        duration = 3000
    })
end

local function testLongDuration()
    lib.notify({
        type = 'info',
        title = 'Long Duration',
        description = 'This shows for 8 seconds with a progress bar',
        duration = 8000,
        showDuration = true
    })
end

local function testNotifyWithSound()
    lib.notify({
        type = 'success',
        title = 'Sound',
        description = 'Notification with default sound preset',
        sound = true,
        duration = 2500
    })
end

local function testNotifyHelpers()
    CreateThread(function()
        lib.notifySuccess('Helper success', 'Success', true)
        Wait(200)
        lib.notifyError('Helper error', 'Error', true)
        Wait(200)
        lib.notifyWarning('Helper warning', 'Warning', true)
        Wait(200)
        lib.notifyInfo('Helper info', 'Info', true)
    end)
end

local function testHideNotifyById()
    local id = 'cortex-hide-test'
    lib.notify({
        id = id,
        type = 'info',
        title = 'Hide by ID',
        description = 'This will disappear in 2 seconds',
        persistent = true
    })
    CreateThread(function()
        Wait(2000)
        lib.hideNotify(id)
        lib.notify({
            type = 'success',
            title = 'Hide by ID',
            description = 'Notification hidden',
            duration = 1500
        })
    end)
end

local function testClearNotifications()
    lib.clearNotifications()
    lib.notify({
        type = 'info',
        title = 'Notifications',
        description = 'Cleared all notifications',
        duration = 1500
    })
end

-- ============================================================================
-- PROGRESS BAR TESTS
-- ============================================================================

local function testProgressBar()
    local completed = lib.progress({
        label = 'Normal progress bar',
        duration = 5000,
        position = 'bottom',
        style = 'bar',
        canCancel = true
    })
    lib.notify({
        type = completed and 'success' or 'warning',
        title = 'Progress',
        description = completed and 'Completed!' or 'Cancelled!'
    })
end

local function testRadialProgress()
    local completed = lib.progress({
        label = 'Radial/Circle progress',
        duration = 5000,
        position = 'bottom',
        style = 'circle',
        canCancel = true
    })
    lib.notify({
        type = completed and 'success' or 'warning',
        title = 'Progress',
        description = completed and 'Completed!' or 'Cancelled!'
    })
end

local function testMiddleProgress()
    local completed = lib.progress({
        label = 'Middle position progress',
        duration = 3000,
        position = 'middle',
        style = 'bar',
        canCancel = false
    })
    lib.notify({
        type = completed and 'success' or 'warning',
        title = 'Progress',
        description = completed and 'Completed!' or 'Cancelled!'
    })
end

local function testShortProgress()
    local completed = lib.progress({
        label = 'Quick action',
        duration = 1000,
        position = 'bottom',
        style = 'bar',
        canCancel = true
    })
end

local function testLongProgress()
    local completed = lib.progress({
        label = 'Long operation',
        duration = 10000,
        position = 'bottom',
        style = 'bar',
        canCancel = true
    })
end

local function testCancelable()
    lib.notify({
        type = 'info',
        title = 'Cancelable Test',
        description = 'Progress will appear - try cancelling with Backspace',
        duration = 3000
    })
    local completed = lib.progress({
        label = 'Cancel this with Backspace',
        duration = 8000,
        position = 'bottom',
        style = 'bar',
        canCancel = true
    })
    lib.notify({
        type = completed and 'success' or 'warning',
        title = 'Result',
        description = completed and 'You let it complete!' or 'You cancelled it!'
    })
end

local function testDisabledControls()
    local completed = lib.progress({
        label = 'Controls disabled',
        duration = 5000,
        position = 'bottom',
        style = 'bar',
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
            mouse = true
        }
    })
    lib.notify({
        type = completed and 'success' or 'warning',
        title = 'Progress',
        description = completed and 'Completed!' or 'Cancelled!'
    })
end

local function testAnimProgress()
    local completed = lib.progress({
        label = 'Animation + prop progress',
        duration = 5000,
        position = 'bottom',
        style = 'bar',
        canCancel = true,
        anim = {
            dict = 'amb@world_human_clipboard@male@idle_a',
            clip = 'idle_c',
            flag = 49
        },
        prop = {
            model = 'prop_notepad_01',
            bone = 60309,
            pos = vector3(0.1, 0.02, 0.0),
            rot = vector3(10.0, 0.0, 0.0)
        }
    })
    lib.notify({
        type = completed and 'success' or 'warning',
        title = 'Progress',
        description = completed and 'Completed!' or 'Cancelled!'
    })
end

local function testScenarioProgress()
    local completed = lib.progress({
        label = 'Scenario progress',
        duration = 5000,
        position = 'bottom',
        style = 'bar',
        canCancel = true,
        anim = {
            scenario = 'WORLD_HUMAN_HAMMERING'
        }
    })
    lib.notify({
        type = completed and 'success' or 'warning',
        title = 'Progress',
        description = completed and 'Completed!' or 'Cancelled!'
    })
end

local function testScriptCancel()
    CreateThread(function()
        lib.progress({
            label = 'Script will cancel after 2 seconds',
            duration = 10000,
            position = 'bottom',
            style = 'bar',
            canCancel = false
        })
    end)

    CreateThread(function()
        Wait(2000)
        lib.cancelProgress()
        lib.notify({
            type = 'warning',
            title = 'Progress',
            description = 'Cancelled via lib.cancelProgress()',
            duration = 1500
        })
    end)
end

local function testProgressActiveState()
    CreateThread(function()
        lib.progress({
            label = 'Checking active state',
            duration = 4000,
            position = 'bottom',
            style = 'bar',
            canCancel = true
        })
    end)

    CreateThread(function()
        Wait(500)
        lib.notify({
            type = 'info',
            title = 'Progress Active',
            description = lib.isProgressActive() and 'Active' or 'Inactive',
            duration = 1500
        })
    end)
end

-- ============================================================================
-- MENU TESTS
-- ============================================================================

local function showTestMenu()
    local scrollValues = {
        { label = 'Low', description = 'Slow speed' },
        { label = 'Medium', description = 'Balanced' },
        { label = 'High', description = 'Fast' },
    }

    lib.registerMenu({
        id = 'cortex_test_menu',
        title = 'CORTEX',
        subtitle = 'Menu Option Showcase',
        position = 'top-right',
        canClose = true,
        disableInput = false,
        options = {
            { label = 'Simple button', description = 'Runs a callback and closes.', args = { message = 'Simple button pressed' } },
            { label = 'Keep open button', description = 'Does not close on select.', close = false, args = { message = 'Keep-open button pressed' } },
            { label = 'Checkbox option', checked = true, description = 'Space toggles. Enter selects.', args = { message = 'Checkbox option selected' } },
            { label = 'Side scroll option', values = scrollValues, defaultIndex = 2, description = 'Left/Right switches value.' },
            { label = 'Progress option', progress = 65, description = 'Static progress bar.' },
            { label = 'With icon', description = 'Menu option with icon', icon = '⚙️', iconColor = 'var(--state-success)' },
            { label = 'Args option', description = 'Shows data passed through args', args = { message = 'Hello from args!' } },
            { label = 'Long description option', description = 'This is a much longer description to test text wrapping and layout.' },
        }
    }, function(selected, scrollIndex, args)
        if selected == 1 or selected == 2 or selected == 3 or selected == 7 then
            lib.notify({ type = 'info', title = 'Menu', description = args.message or 'Option selected', duration = 1500 })
        elseif selected == 4 then
            local value = scrollValues[scrollIndex or 1]
            lib.notify({ type = 'info', title = 'Menu', description = 'Scroll value: ' .. (value and value.label or 'Unknown'), duration = 1500 })
        elseif selected == 5 then
            lib.notify({ type = 'info', title = 'Menu', description = 'Progress option selected', duration = 1500 })
        elseif selected == 6 then
            lib.notify({ type = 'success', title = 'Menu', description = 'Icon button pressed', duration = 1500 })
        elseif selected == 8 then
            lib.notify({ type = 'info', title = 'Menu', description = 'Long description option', duration = 1500 })
        end
    end)

    lib.showMenu('cortex_test_menu')
end

local function showSubMenu()
    lib.registerMenu({
        id = 'cortex_submenu',
        title = 'SUB MENU',
        subtitle = 'Nested menu test',
        position = 'top-right',
        options = {
            { label = 'Back to main', description = 'Return to main menu' },
            { label = 'Action 1', description = 'First action' },
            { label = 'Action 2', description = 'Second action' },
        }
    }, function(selected, scrollIndex, args)
        if selected == 1 then
            lib.showMenu('cortex_main_menu')
        else
            lib.notify({ type = 'info', title = 'Sub Menu', description = 'Action ' .. selected, duration = 1500 })
        end
    end)

    lib.showMenu('cortex_submenu')
end

local function showLargeMenu()
    local options = {}
    for i = 1, 20 do
        table.insert(options, {
            label = 'Option ' .. i,
            description = 'This is option number ' .. i .. ' in a long list',
            checked = i % 3 == 0
        })
    end

    lib.registerMenu({
        id = 'cortex_large_menu',
        title = 'LARGE MENU',
        subtitle = '20 options test',
        position = 'top-right',
        options = options
    }, function(selected, scrollIndex, args)
        lib.notify({ type = 'info', title = 'Large Menu', description = 'Selected option ' .. selected, duration = 1000 })
    end)

    lib.showMenu('cortex_large_menu')
end

local function showCallbackMenu()
    local sideScrollValues = { 'One', 'Two', 'Three' }

    lib.registerMenu({
        id = 'cortex_callback_menu',
        title = 'CALLBACKS',
        subtitle = 'onClose / onSelected / onCheck / onSideScroll',
        position = 'top-right',
        canClose = true,
        onClose = function(keyPressed)
            lib.hideTextUI()
            lib.notify({
                type = 'info',
                title = 'Menu',
                description = ('Closed with %s'):format(keyPressed or 'API'),
                duration = 1500
            })
        end,
        onSelected = function(selected)
            lib.showTextUI('Selected option: ' .. selected, {
                position = 'bottom-center',
                icon = '📌'
            })
        end,
        onSideScroll = function(selected, scrollIndex)
            local value = sideScrollValues[scrollIndex or 1] or 'Unknown'
            lib.notify({
                type = 'info',
                title = 'Side Scroll',
                description = ('Option %d → %s'):format(selected, value),
                duration = 1200
            })
        end,
        onCheck = function(selected, checked)
            lib.notify({
                type = 'info',
                title = 'Check',
                description = ('Option %d checked: %s'):format(selected, checked and 'true' or 'false'),
                duration = 1200
            })
        end,
        options = {
            { label = 'Toggle check', checked = true, description = 'Triggers onCheck event' },
            { label = 'Side scroll', values = sideScrollValues, defaultIndex = 2, description = 'Triggers onSideScroll event' },
            { label = 'Close via API', description = 'Calls lib.hideMenu(true)', close = false },
        }
    }, function(selected, scrollIndex, args)
        if selected == 3 then
            lib.hideMenu(true)
            return
        end

        lib.notify({
            type = 'success',
            title = 'Submit',
            description = 'Selected option ' .. selected,
            duration = 1200
        })
    end)

    lib.showMenu('cortex_callback_menu')
end

local function showInputLockMenu()
    lib.registerMenu({
        id = 'cortex_lock_menu',
        title = 'INPUT LOCK',
        subtitle = 'disableInput + canClose=false',
        position = 'top-right',
        disableInput = true,
        canClose = false,
        options = {
            { label = 'Close', description = 'Close menu via API', close = false },
            { label = 'Menu ID', description = 'Show getOpenMenu()', close = false },
        }
    }, function(selected, scrollIndex, args)
        if selected == 1 then
            lib.hideMenu(true)
            return
        end

        if selected == 2 then
            local openMenu = lib.getOpenMenu() or 'none'
            lib.notify({ type = 'info', title = 'Menu', description = 'Open menu: ' .. openMenu, duration = 1500 })
        end
    end)

    lib.showMenu('cortex_lock_menu')
end

local function updateMenuOption()
    local progress = math.random(0, 100)
    lib.setMenuOptions('cortex_test_menu', {
        label = 'Progress option',
        progress = progress,
        description = 'Updated progress: ' .. progress .. '%'
    }, 5)
    lib.notify({ type = 'info', title = 'Menu', description = 'Updated progress to ' .. progress .. '%', duration = 1500 })
end

-- ============================================================================
-- ALERT DIALOG TESTS
-- ============================================================================

local function testAlertDialog()
    local result = lib.alertDialog({
        header = 'Confirmation',
        content = 'Are you sure you want to proceed with this action?',
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Yes, proceed',
            cancel = 'No, cancel'
        }
    })
    lib.notify({
        type = result == 'confirm' and 'success' or 'info',
        title = 'Alert Dialog',
        description = result == 'confirm' and 'You confirmed!' or 'You cancelled!'
    })
end

local function testInfoDialog()
    lib.alertDialog({
        header = 'Information',
        content = 'This is an informational dialog. Click OK to dismiss.',
        centered = true,
        cancel = false,
        labels = {
            confirm = 'OK'
        }
    })
end

local function testStyledDialog()
    local result = lib.alertDialog({
        header = 'Styled Dialog',
        content = 'Custom styling and centered layout.',
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Looks good',
            cancel = 'Close'
        },
        style = {
            backgroundColor = 'var(--surface-panel-solid)',
            border = '1px solid var(--state-focus)',
            color = 'var(--text-primary)'
        }
    })
    lib.notify({
        type = result == 'confirm' and 'success' or 'info',
        title = 'Alert Dialog',
        description = result == 'confirm' and 'Styled confirm pressed' or 'Styled dialog closed'
    })
end

-- ============================================================================
-- TEXT UI TESTS
-- ============================================================================

local function showTextUI()
    lib.showTextUI('Press E to interact', {
        position = 'bottom-center',
        icon = '🖐️'
    })
end

local function hideTextUI()
    lib.hideTextUI()
end

local function showTopTextUI()
    lib.showTextUI('System message - Top position', {
        position = 'top-center',
        icon = '⚡'
    })
end

local function showLeftTextUI()
    lib.showTextUI('Left aligned prompt', {
        position = 'bottom-left',
        icon = '⬅️'
    })
end

local function showStyledTextUI()
    lib.showTextUI('Styled prompt', {
        position = 'top-right',
        icon = '✨',
        backdrop = true,
        style = {
            backgroundColor = 'var(--surface-panel-solid)',
            border = '1px solid var(--state-focus)',
            color = 'var(--text-primary)'
        }
    })
end

-- ============================================================================
-- DEBUG PANEL TESTS
-- ============================================================================

local function buildDebugPanelPayload(subtitle)
    local cache = lib.cache or {}

    return {
        title = 'CORTEX',
        subtitle = subtitle,
        position = 'top-right',
        accentColor = 'var(--state-focus)',
        lines = {
            { label = 'Progress', value = lib.isProgressActive() and 'Active' or 'Idle' },
            { label = 'Menu', value = lib.getOpenMenu() or 'None' },
            { label = 'Server ID', value = cache.serverId or GetPlayerServerId(PlayerId()) },
            { label = 'Time', value = GetGameTimer() },
        },
        data = {
            cache = cache,
            progressActive = lib.isProgressActive(),
            openMenu = lib.getOpenMenu()
        }
    }
end

local function showDebugPanel()
    lib.showDebugPanel(buildDebugPanelPayload('Debug Panel'))
end

local function updateDebugPanel()
    lib.updateDebugPanel(buildDebugPanelPayload('Updated'))
end

local function hideDebugPanel()
    lib.hideDebugPanel()
end

local function showDebugPanelStatus()
    lib.notify({
        type = 'info',
        title = 'Debug Panel',
        description = lib.isDebugPanelOpen() and 'Open' or 'Closed',
        duration = 1500
    })
end

-- ============================================================================
-- UTILITY TESTS
-- ============================================================================

local function testRequestAnimDict()
    local dict = 'amb@world_human_clipboard@male@idle_a'
    local loaded = lib.requestAnimDict(dict, 5000)

    if loaded then
        RemoveAnimDict(dict)
    end

    lib.notify({
        type = loaded and 'success' or 'error',
        title = 'Anim Dict',
        description = loaded and ('Loaded ' .. dict) or ('Failed ' .. dict),
        duration = 2000
    })
end

local function testRequestModel()
    local model = 'prop_notepad_01'
    local loaded = lib.requestModel(model, 5000)

    if loaded then
        SetModelAsNoLongerNeeded(joaat(model))
    end

    lib.notify({
        type = loaded and 'success' or 'error',
        title = 'Model',
        description = loaded and ('Loaded ' .. model) or ('Failed ' .. model),
        duration = 2000
    })
end

-- ============================================================================
-- CLEAR ALL
-- ============================================================================

local function clearAll()
    lib.clearNotifications()
    lib.cancelProgress()
    lib.hideTextUI()
    lib.hideDebugPanel()
    if lib.hideRadial then lib.hideRadial() end
    lib.notify({
        type = 'info',
        title = 'Cleared',
        description = 'All notifications, progress, text UI, debug panels, and radial cleared',
        duration = 2000
    })
end

-- ============================================================================
-- REGISTER ALL MENUS
-- ============================================================================

-- Notifications submenu
lib.registerMenu({
    id = 'cortex_notify_menu',
    title = 'NOTIFICATIONS',
    subtitle = 'Test notification features',
    position = 'top-right',
    options = {
        { label = 'All Types', description = 'Test all notification types (success, error, warning, info, inform)' },
        { label = 'All Positions', description = 'Test all notification positions' },
        { label = 'Persistent', description = 'Test persistent notification' },
        { label = 'Update by ID', description = 'Test updating notification by ID' },
        { label = 'Hide by ID', description = 'Hide a notification by ID' },
        { label = 'Long Duration', description = 'Test 8 second notification with progress bar' },
        { label = 'Sound Notification', description = 'Notification with sound preset' },
        { label = 'Helper Methods', description = 'notifySuccess/Error/Warning/Info helpers' },
        { label = 'Clear Notifications', description = 'Clear all active notifications' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then
        testAllNotifyTypes()
    elseif selected == 2 then
        testAllPositions()
    elseif selected == 3 then
        testPersistentNotify()
    elseif selected == 4 then
        testUpdateById()
    elseif selected == 5 then
        testHideNotifyById()
    elseif selected == 6 then
        testLongDuration()
    elseif selected == 7 then
        testNotifyWithSound()
    elseif selected == 8 then
        testNotifyHelpers()
    elseif selected == 9 then
        testClearNotifications()
    end
end)

-- Progress submenu
lib.registerMenu({
    id = 'cortex_progress_menu',
    title = 'PROGRESS BARS',
    subtitle = 'Test progress bar features',
    position = 'top-right',
    options = {
        { label = 'Normal Bar', description = '5 second bar progress' },
        { label = 'Radial/Circle', description = '5 second circle progress' },
        { label = 'Middle Position', description = '3 second middle progress (no cancel)' },
        { label = 'Short Duration', description = '1 second quick progress' },
        { label = 'Long Duration', description = '10 second long progress' },
        { label = 'Cancelable', description = 'Test canceling with Backspace' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then
        testProgressBar()
    elseif selected == 2 then
        testRadialProgress()
    elseif selected == 3 then
        testMiddleProgress()
    elseif selected == 4 then
        testShortProgress()
    elseif selected == 5 then
        testLongProgress()
    elseif selected == 6 then
        testCancelable()
    end
end)

-- Progress extras submenu
lib.registerMenu({
    id = 'cortex_progress_extra_menu',
    title = 'PROGRESS EXTRAS',
    subtitle = 'Advanced progress features',
    position = 'top-right',
    options = {
        { label = 'Disabled Controls', description = 'Disable move/combat/mouse controls' },
        { label = 'Animation + Prop', description = 'Anim dict with attached prop' },
        { label = 'Scenario', description = 'Scenario-based progress' },
        { label = 'Script Cancel', description = 'Cancel via API after 2 seconds' },
        { label = 'Active State', description = 'Check lib.isProgressActive()' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then
        testDisabledControls()
    elseif selected == 2 then
        testAnimProgress()
    elseif selected == 3 then
        testScenarioProgress()
    elseif selected == 4 then
        testScriptCancel()
    elseif selected == 5 then
        testProgressActiveState()
    end
end)

-- Menu test submenu
lib.registerMenu({
    id = 'cortex_menu_test_menu',
    title = 'MENUS',
    subtitle = 'Test menu features',
    position = 'top-right',
    options = {
        { label = 'Test Menu', description = 'Show test menu with various option types' },
        { label = 'Sub Menu', description = 'Test nested menus' },
        { label = 'Large Menu', description = 'Test menu with 20 options' },
        { label = 'Update Option', description = 'Update progress option in test menu' },
        { label = 'Callback Menu', description = 'Test onClose/onCheck/onSideScroll callbacks' },
        { label = 'Input Lock Menu', description = 'Test disableInput and canClose=false' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then
        showTestMenu()
    elseif selected == 2 then
        showSubMenu()
    elseif selected == 3 then
        showLargeMenu()
    elseif selected == 4 then
        updateMenuOption()
    elseif selected == 5 then
        showCallbackMenu()
    elseif selected == 6 then
        showInputLockMenu()
    end
end)

-- Alert dialogs submenu
lib.registerMenu({
    id = 'cortex_alert_menu',
    title = 'ALERT DIALOGS',
    subtitle = 'Test alert dialog features',
    position = 'top-right',
    options = {
        { label = 'Confirmation', description = 'Test yes/no confirmation dialog' },
        { label = 'Information', description = 'Test info-only dialog' },
        { label = 'Styled', description = 'Test custom dialog styling' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then
        testAlertDialog()
    elseif selected == 2 then
        testInfoDialog()
    elseif selected == 3 then
        testStyledDialog()
    end
end)

-- Text UI submenu
lib.registerMenu({
    id = 'cortex_textui_menu',
    title = 'TEXT UI',
    subtitle = 'Test text UI features',
    position = 'top-right',
    options = {
        { label = 'Show Bottom', description = 'Show text UI at bottom' },
        { label = 'Show Top', description = 'Show text UI at top' },
        { label = 'Show Left', description = 'Show text UI at bottom-left' },
        { label = 'Show Styled', description = 'Show text UI with custom style' },
        { label = 'Hide', description = 'Hide text UI' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then
        showTextUI()
    elseif selected == 2 then
        showTopTextUI()
    elseif selected == 3 then
        showLeftTextUI()
    elseif selected == 4 then
        showStyledTextUI()
    elseif selected == 5 then
        hideTextUI()
    end
end)

-- Debug panel submenu
lib.registerMenu({
    id = 'cortex_debug_panel_menu',
    title = 'DEBUG PANEL',
    subtitle = 'Test debug panel features',
    position = 'top-right',
    options = {
        { label = 'Show Panel', description = 'Display debug panel' },
        { label = 'Update Panel', description = 'Update panel data' },
        { label = 'Hide Panel', description = 'Hide debug panel' },
        { label = 'Panel Status', description = 'Check if panel is open' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then
        showDebugPanel()
    elseif selected == 2 then
        updateDebugPanel()
    elseif selected == 3 then
        hideDebugPanel()
    elseif selected == 4 then
        showDebugPanelStatus()
    end
end)

-- Utilities submenu
lib.registerMenu({
    id = 'cortex_util_menu',
    title = 'UTILITIES',
    subtitle = 'Test helper utilities',
    position = 'top-right',
    options = {
        { label = 'Request Anim Dict', description = 'Test lib.requestAnimDict' },
        { label = 'Request Model', description = 'Test lib.requestModel' },
        { label = 'Open Menu ID', description = 'Show lib.getOpenMenu()', close = false },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then
        testRequestAnimDict()
    elseif selected == 2 then
        testRequestModel()
    elseif selected == 3 then
        local openMenu = lib.getOpenMenu() or 'none'
        lib.notify({ type = 'info', title = 'Menu', description = 'Open menu: ' .. openMenu, duration = 1500 })
    end
end)

-- ============================================================================
-- GETTER TESTS
-- ============================================================================

local function testGetClosestPlayer()
    local coords = GetEntityCoords(PlayerPedId())
    local playerId, playerPed, playerCoords = lib.getClosestPlayer(coords, 50.0)
    
    if playerId then
        lib.notify({
            type = 'success',
            title = 'Closest Player',
            description = ('Player %d found at %.1fm'):format(playerId, #(coords - playerCoords)),
            duration = 3000
        })
    else
        lib.notify({
            type = 'info',
            title = 'Closest Player',
            description = 'No players found within 50m',
            duration = 2000
        })
    end
end

local function testGetClosestVehicle()
    local coords = GetEntityCoords(PlayerPedId())
    local vehicle, vehCoords = lib.getClosestVehicle(coords, 25.0)
    
    if vehicle then
        local model = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
        lib.notify({
            type = 'success',
            title = 'Closest Vehicle',
            description = ('%s found at %.1fm'):format(model, #(coords - vehCoords)),
            duration = 3000
        })
    else
        lib.notify({
            type = 'info',
            title = 'Closest Vehicle',
            description = 'No vehicles found within 25m',
            duration = 2000
        })
    end
end

local function testGetClosestPed()
    local coords = GetEntityCoords(PlayerPedId())
    local ped, pedCoords = lib.getClosestPed(coords, 25.0)
    
    if ped then
        lib.notify({
            type = 'success',
            title = 'Closest Ped',
            description = ('NPC found at %.1fm'):format(#(coords - pedCoords)),
            duration = 3000
        })
    else
        lib.notify({
            type = 'info',
            title = 'Closest Ped',
            description = 'No NPCs found within 25m',
            duration = 2000
        })
    end
end

local function testGetNearbyVehicles()
    local coords = GetEntityCoords(PlayerPedId())
    local vehicles = lib.getNearbyVehicles(coords, 50.0)
    
    lib.notify({
        type = 'info',
        title = 'Nearby Vehicles',
        description = ('Found %d vehicles within 50m'):format(#vehicles),
        duration = 2000
    })
end

local function testGetNearbyPeds()
    local coords = GetEntityCoords(PlayerPedId())
    local peds = lib.getNearbyPeds(coords, 50.0)
    
    lib.notify({
        type = 'info',
        title = 'Nearby Peds',
        description = ('Found %d NPCs within 50m'):format(#peds),
        duration = 2000
    })
end

-- ============================================================================
-- RAYCAST TESTS
-- ============================================================================

local function testRaycastFromCamera()
    local hit, entityHit, endCoords, surfaceNormal, materialHash = lib.raycast.fromCamera(511, PlayerPedId(), 100.0)
    
    if hit then
        local entityType = entityHit > 0 and GetEntityType(entityHit) or 0
        local typeName = ({ 'None', 'Ped', 'Vehicle', 'Object' })[entityType + 1] or 'World'
        
        lib.notify({
            type = 'success',
            title = 'Raycast Hit',
            description = ('Hit %s at distance %.1fm'):format(typeName, #(GetEntityCoords(PlayerPedId()) - endCoords)),
            duration = 3000
        })
        
        -- Draw a marker at hit location for 3 seconds
        CreateThread(function()
            local endTime = GetGameTimer() + 3000
            while GetGameTimer() < endTime do
                DrawMarker(28, endCoords.x, endCoords.y, endCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, 0, 255, 0, 150, false, false, 2, false, nil, nil, false)
                Wait(0)
            end
        end)
    else
        lib.notify({
            type = 'info',
            title = 'Raycast',
            description = 'No hit detected',
            duration = 2000
        })
    end
end

local function testRaycastFromCoords()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local destination = coords + forward * 20.0
    
    local hit, entityHit, endCoords = lib.raycast.fromCoords(coords, destination)
    
    if hit then
        lib.notify({
            type = 'success',
            title = 'Raycast From Coords',
            description = ('Hit at %.1fm forward'):format(#(coords - endCoords)),
            duration = 2000
        })
    else
        lib.notify({
            type = 'info',
            title = 'Raycast From Coords',
            description = 'No obstruction in 20m forward',
            duration = 2000
        })
    end
end

-- ============================================================================
-- ZONE TESTS
-- ============================================================================

local testZone = nil

local function createTestSphereZone()
    if testZone then testZone:remove() end
    
    local coords = GetEntityCoords(PlayerPedId())
    testZone = lib.zones.sphere({
        coords = coords,
        radius = 5.0,
        debug = true,
        onEnter = function(self)
            lib.notify({ type = 'success', title = 'Zone', description = 'Entered sphere zone', duration = 1500 })
        end,
        onExit = function(self)
            lib.notify({ type = 'warning', title = 'Zone', description = 'Exited sphere zone', duration = 1500 })
        end,
        inside = function(self)
            -- Called every tick while inside
        end
    })
    
    lib.notify({
        type = 'info',
        title = 'Zone Created',
        description = 'Sphere zone (5m radius) created at your location',
        duration = 2000
    })
end

local function createTestBoxZone()
    if testZone then testZone:remove() end
    
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    
    testZone = lib.zones.box({
        coords = coords,
        size = vector3(4.0, 6.0, 3.0),
        rotation = heading,
        debug = true,
        onEnter = function(self)
            lib.notify({ type = 'success', title = 'Zone', description = 'Entered box zone', duration = 1500 })
        end,
        onExit = function(self)
            lib.notify({ type = 'warning', title = 'Zone', description = 'Exited box zone', duration = 1500 })
        end
    })
    
    lib.notify({
        type = 'info',
        title = 'Zone Created',
        description = 'Box zone (4x6x3) created at your location',
        duration = 2000
    })
end

local function createTestPolyZone()
    if testZone then testZone:remove() end
    
    local coords = GetEntityCoords(PlayerPedId())
    local x, y, z = coords.x, coords.y, coords.z
    
    -- Create a triangle around the player
    testZone = lib.zones.poly({
        points = {
            vector3(x, y + 5, z),
            vector3(x - 5, y - 3, z),
            vector3(x + 5, y - 3, z),
        },
        thickness = 4.0,
        debug = true,
        onEnter = function(self)
            lib.notify({ type = 'success', title = 'Zone', description = 'Entered poly zone', duration = 1500 })
        end,
        onExit = function(self)
            lib.notify({ type = 'warning', title = 'Zone', description = 'Exited poly zone', duration = 1500 })
        end
    })
    
    lib.notify({
        type = 'info',
        title = 'Zone Created',
        description = 'Triangle poly zone created at your location',
        duration = 2000
    })
end

local function removeTestZone()
    if testZone then
        testZone:remove()
        testZone = nil
        lib.notify({ type = 'info', title = 'Zone', description = 'Test zone removed', duration = 1500 })
    else
        lib.notify({ type = 'warning', title = 'Zone', description = 'No test zone to remove', duration = 1500 })
    end
end

-- ============================================================================
-- POINTS TESTS
-- ============================================================================

local testPoint = nil

local function createTestPoint()
    if testPoint then testPoint:remove() end
    
    local coords = GetEntityCoords(PlayerPedId())
    testPoint = lib.points.new({
        coords = coords,
        distance = 5.0,
        myCustomData = 'Hello from point!',
        onEnter = function(self)
            lib.notify({ type = 'success', title = 'Point', description = 'Entered point radius: ' .. self.myCustomData, duration = 2000 })
        end,
        onExit = function(self)
            lib.notify({ type = 'warning', title = 'Point', description = 'Exited point radius', duration = 1500 })
        end,
        nearby = function(self)
            -- Draw marker while nearby (runs every frame)
            DrawMarker(28, self.coords.x, self.coords.y, self.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0, 255, 0, 100, false, false, 2, false, nil, nil, false)
        end
    })
    
    lib.notify({
        type = 'info',
        title = 'Point Created',
        description = 'Point (5m radius) created with nearby callback',
        duration = 2000
    })
end

local function showNearbyPoints()
    local nearby = lib.points.getNearbyPoints()
    lib.notify({
        type = 'info',
        title = 'Nearby Points',
        description = ('Currently near %d points'):format(#nearby),
        duration = 2000
    })
end

local function showClosestPoint()
    local closest = lib.points.getClosestPoint()
    if closest then
        lib.notify({
            type = 'info',
            title = 'Closest Point',
            description = ('Distance: %.1fm'):format(closest.currentDistance),
            duration = 2000
        })
    else
        lib.notify({
            type = 'warning',
            title = 'Closest Point',
            description = 'No points registered',
            duration = 2000
        })
    end
end

local function removeTestPoint()
    if testPoint then
        testPoint:remove()
        testPoint = nil
        lib.notify({ type = 'info', title = 'Point', description = 'Test point removed', duration = 1500 })
    else
        lib.notify({ type = 'warning', title = 'Point', description = 'No test point to remove', duration = 1500 })
    end
end

-- ============================================================================
-- TIMER TESTS
-- ============================================================================

local testTimer = nil

local function createTestTimer()
    if testTimer and not testTimer:hasEnded() then
        testTimer:forceEnd(false)
    end
    
    lib.notify({ type = 'info', title = 'Timer', description = 'Started 10 second timer', duration = 1500 })
    
    testTimer = lib.timer(10000, function()
        lib.notify({ type = 'success', title = 'Timer', description = 'Timer completed!', duration = 2000 })
    end)
end

local function pauseTestTimer()
    if testTimer and not testTimer:hasEnded() then
        if testTimer:isPaused() then
            testTimer:play()
            lib.notify({ type = 'info', title = 'Timer', description = 'Timer resumed - ' .. testTimer:getTimeLeftFormatted() .. ' remaining', duration = 1500 })
        else
            testTimer:pause()
            lib.notify({ type = 'warning', title = 'Timer', description = 'Timer paused - ' .. testTimer:getTimeLeftFormatted() .. ' remaining', duration = 1500 })
        end
    else
        lib.notify({ type = 'error', title = 'Timer', description = 'No active timer', duration = 1500 })
    end
end

local function showTimerStatus()
    if testTimer then
        local status = testTimer:hasEnded() and 'Ended' or (testTimer:isPaused() and 'Paused' or 'Running')
        lib.notify({
            type = 'info',
            title = 'Timer Status',
            description = ('%s - %s remaining'):format(status, testTimer:getTimeLeftFormatted()),
            duration = 2000
        })
    else
        lib.notify({ type = 'warning', title = 'Timer', description = 'No timer created', duration = 1500 })
    end
end

local function forceEndTimer()
    if testTimer and not testTimer:hasEnded() then
        testTimer:forceEnd(false)
        lib.notify({ type = 'warning', title = 'Timer', description = 'Timer force ended', duration = 1500 })
    else
        lib.notify({ type = 'error', title = 'Timer', description = 'No active timer', duration = 1500 })
    end
end

-- ============================================================================
-- DISABLE CONTROLS TEST
-- ============================================================================

local activeDisableControls = nil

local function testDisableMovement()
    if activeDisableControls then
        activeDisableControls:Destroy()
    end
    
    activeDisableControls = lib.disableControls({
        disableMovement = true
    })
    
    lib.notify({
        type = 'warning',
        title = 'Controls Disabled',
        description = 'Movement disabled for 5 seconds',
        duration = 2000
    })
    
    SetTimeout(5000, function()
        if activeDisableControls then
            activeDisableControls:Destroy()
            activeDisableControls = nil
            lib.notify({ type = 'success', title = 'Controls', description = 'Movement restored', duration = 1500 })
        end
    end)
end

local function testDisableCombat()
    if activeDisableControls then
        activeDisableControls:Destroy()
    end
    
    activeDisableControls = lib.disableControls({
        disableCombat = true
    })
    
    lib.notify({
        type = 'warning',
        title = 'Controls Disabled',
        description = 'Combat disabled for 5 seconds',
        duration = 2000
    })
    
    SetTimeout(5000, function()
        if activeDisableControls then
            activeDisableControls:Destroy()
            activeDisableControls = nil
            lib.notify({ type = 'success', title = 'Controls', description = 'Combat restored', duration = 1500 })
        end
    end)
end

local function testDisableAll()
    if activeDisableControls then
        activeDisableControls:Destroy()
    end
    
    activeDisableControls = lib.disableControls({
        disableAll = true
    })
    
    lib.notify({
        type = 'error',
        title = 'All Controls Disabled',
        description = 'All controls disabled for 3 seconds',
        duration = 2000
    })
    
    SetTimeout(3000, function()
        if activeDisableControls then
            activeDisableControls:Destroy()
            activeDisableControls = nil
            lib.notify({ type = 'success', title = 'Controls', description = 'All controls restored', duration = 1500 })
        end
    end)
end

-- ============================================================================
-- WAITFOR TEST
-- ============================================================================

local function testWaitFor()
    local vehicle = nil
    
    lib.notify({ type = 'info', title = 'WaitFor', description = 'Waiting for you to enter a vehicle (5s timeout)...', duration = 2000 })
    
    CreateThread(function()
        vehicle = lib.waitFor(function()
            local veh = GetVehiclePedIsIn(PlayerPedId(), false)
            if veh ~= 0 then return veh end
            return nil
        end, nil, 5000)
        
        if vehicle then
            lib.notify({ type = 'success', title = 'WaitFor', description = 'Successfully detected vehicle entry!', duration = 2000 })
        else
            lib.notify({ type = 'warning', title = 'WaitFor', description = 'Timed out - no vehicle entered', duration = 2000 })
        end
    end)
end

-- ============================================================================
-- NEW SUBMENUS
-- ============================================================================

-- Getters submenu
lib.registerMenu({
    id = 'cortex_getters_menu',
    title = 'GETTERS',
    subtitle = 'Test get closest/nearby functions',
    position = 'top-right',
    options = {
        { label = 'Closest Player', description = 'Find closest player within 50m' },
        { label = 'Closest Vehicle', description = 'Find closest vehicle within 25m' },
        { label = 'Closest Ped', description = 'Find closest NPC within 25m' },
        { label = 'Nearby Vehicles', description = 'Count vehicles within 50m' },
        { label = 'Nearby Peds', description = 'Count NPCs within 50m' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then testGetClosestPlayer()
    elseif selected == 2 then testGetClosestVehicle()
    elseif selected == 3 then testGetClosestPed()
    elseif selected == 4 then testGetNearbyVehicles()
    elseif selected == 5 then testGetNearbyPeds()
    end
end)

-- Raycast submenu
lib.registerMenu({
    id = 'cortex_raycast_menu',
    title = 'RAYCAST',
    subtitle = 'Test raycast functions',
    position = 'top-right',
    options = {
        { label = 'From Camera', description = 'Raycast from camera (100m)' },
        { label = 'From Coords', description = 'Raycast 20m forward from player' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then testRaycastFromCamera()
    elseif selected == 2 then testRaycastFromCoords()
    end
end)

-- Zones submenu
lib.registerMenu({
    id = 'cortex_zones_menu',
    title = 'ZONES',
    subtitle = 'Test zone system',
    position = 'top-right',
    options = {
        { label = 'Create Sphere Zone', description = 'Create 5m radius sphere at location' },
        { label = 'Create Box Zone', description = 'Create 4x6x3 box at location' },
        { label = 'Create Poly Zone', description = 'Create triangle polygon at location' },
        { label = 'Remove Zone', description = 'Remove the test zone' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then createTestSphereZone()
    elseif selected == 2 then createTestBoxZone()
    elseif selected == 3 then createTestPolyZone()
    elseif selected == 4 then removeTestZone()
    end
end)

-- Points submenu
lib.registerMenu({
    id = 'cortex_points_menu',
    title = 'POINTS',
    subtitle = 'Test points system',
    position = 'top-right',
    options = {
        { label = 'Create Point', description = 'Create point with 5m radius' },
        { label = 'Show Nearby Points', description = 'Count points you are near' },
        { label = 'Show Closest Point', description = 'Distance to closest point' },
        { label = 'Remove Point', description = 'Remove the test point' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then createTestPoint()
    elseif selected == 2 then showNearbyPoints()
    elseif selected == 3 then showClosestPoint()
    elseif selected == 4 then removeTestPoint()
    end
end)

-- Timer submenu
lib.registerMenu({
    id = 'cortex_timer_menu',
    title = 'TIMER',
    subtitle = 'Test timer utility',
    position = 'top-right',
    options = {
        { label = 'Start Timer', description = 'Start a 10 second timer' },
        { label = 'Pause/Resume', description = 'Toggle timer pause state' },
        { label = 'Show Status', description = 'Show timer status and time remaining' },
        { label = 'Force End', description = 'Force end without callback' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then createTestTimer()
    elseif selected == 2 then pauseTestTimer()
    elseif selected == 3 then showTimerStatus()
    elseif selected == 4 then forceEndTimer()
    end
end)

-- Disable Controls submenu
lib.registerMenu({
    id = 'cortex_controls_menu',
    title = 'DISABLE CONTROLS',
    subtitle = 'Test control disabling',
    position = 'top-right',
    options = {
        { label = 'Disable Movement', description = 'Disable WASD for 5 seconds' },
        { label = 'Disable Combat', description = 'Disable combat for 5 seconds' },
        { label = 'Disable All', description = 'Disable all controls for 3 seconds' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then testDisableMovement()
    elseif selected == 2 then testDisableCombat()
    elseif selected == 3 then testDisableAll()
    end
end)

-- WaitFor submenu
lib.registerMenu({
    id = 'cortex_waitfor_menu',
    title = 'WAITFOR',
    subtitle = 'Test waitFor utility',
    position = 'top-right',
    options = {
        { label = 'Wait for Vehicle', description = 'Wait for you to enter a vehicle (5s timeout)' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then testWaitFor()
    end
end)

-- ============================================================================
-- RADIAL MENU TESTS
-- ============================================================================

local function testBasicRadial()
    lib.registerRadial({
        id = 'cortex_test_radial',
        items = {
            { id = 'item1', label = 'Vehicle', icon = '🚗', onSelect = function()
                lib.notify({ type = 'success', title = 'Radial', description = 'Vehicle selected!', duration = 2000 })
            end },
            { id = 'item2', label = 'Inventory', icon = '🎒', onSelect = function()
                lib.notify({ type = 'success', title = 'Radial', description = 'Inventory selected!', duration = 2000 })
            end },
            { id = 'item3', label = 'Phone', icon = '📱', onSelect = function()
                lib.notify({ type = 'success', title = 'Radial', description = 'Phone selected!', duration = 2000 })
            end },
            { id = 'item4', label = 'Settings', icon = '⚙️', onSelect = function()
                lib.notify({ type = 'success', title = 'Radial', description = 'Settings selected!', duration = 2000 })
            end },
        }
    })
    
    lib.showRadial('cortex_test_radial')
end

local function testRadialWithSubMenu()
    lib.registerRadial({
        id = 'cortex_radial_submenu',
        items = {
            { id = 'sub1', label = 'Option A', icon = '🅰️', onSelect = function()
                lib.notify({ type = 'info', title = 'Sub Menu', description = 'Option A selected', duration = 1500 })
            end },
            { id = 'sub2', label = 'Option B', icon = '🅱️', onSelect = function()
                lib.notify({ type = 'info', title = 'Sub Menu', description = 'Option B selected', duration = 1500 })
            end },
            { id = 'sub3', label = 'Option C', icon = '©️', onSelect = function()
                lib.notify({ type = 'info', title = 'Sub Menu', description = 'Option C selected', duration = 1500 })
            end },
        }
    })
    
    lib.registerRadial({
        id = 'cortex_radial_main',
        items = {
            { id = 'main1', label = 'Action 1', icon = '⚡', onSelect = function()
                lib.notify({ type = 'success', title = 'Radial', description = 'Action 1 executed!', duration = 2000 })
            end },
            { id = 'main2', label = 'Sub Menu', icon = '📂', menu = 'cortex_radial_submenu' },
            { id = 'main3', label = 'Action 2', icon = '🔥', onSelect = function()
                lib.notify({ type = 'success', title = 'Radial', description = 'Action 2 executed!', duration = 2000 })
            end },
        }
    })
    
    lib.showRadial('cortex_radial_main')
end

local function testRadialManyItems()
    local items = {}
    local icons = { '🌟', '🎯', '💎', '🔮', '🎪', '🎨', '🎭', '🎬', '🎵', '🎸', '🎹', '🎺' }
    
    -- Create 12 items to test pagination
    for i = 1, 12 do
        table.insert(items, {
            id = 'many_' .. i,
            label = 'Item ' .. i,
            icon = icons[i] or '📌',
            onSelect = function()
                lib.notify({ type = 'info', title = 'Radial', description = 'Item ' .. i .. ' selected', duration = 1500 })
            end
        })
    end
    
    lib.registerRadial({
        id = 'cortex_radial_many',
        items = items
    })
    
    lib.showRadial('cortex_radial_many')
    lib.notify({ type = 'info', title = 'Pagination', description = '12 items - use More button to navigate pages', duration = 3000 })
end

local function testGlobalRadialItems()
    -- Add items to the global radial menu (root menu)
    lib.addRadialItem({
        id = 'global1',
        label = 'Global 1',
        icon = '🌍',
        onSelect = function()
            lib.notify({ type = 'success', title = 'Global', description = 'Global item 1 selected!', duration = 2000 })
        end
    })
    
    lib.addRadialItem({
        id = 'global2', 
        label = 'Global 2',
        icon = '🌎',
        onSelect = function()
            lib.notify({ type = 'success', title = 'Global', description = 'Global item 2 selected!', duration = 2000 })
        end
    })
    
    lib.addRadialItem({
        id = 'global3',
        label = 'Sub Menu',
        icon = '📂',
        menu = 'cortex_test_radial'
    })
    
    lib.notify({ type = 'info', title = 'Global Items', description = 'Added 3 items to global radial menu', duration = 2500 })
    lib.showRadial() -- Open global menu
end

local function testRemoveGlobalItem()
    lib.removeRadialItem('global2')
    lib.notify({ type = 'warning', title = 'Radial', description = 'Removed global2 from root menu', duration = 2000 })
end

local function testClearGlobalItems()
    lib.clearRadialItems()
    lib.notify({ type = 'warning', title = 'Radial', description = 'Cleared all global radial items', duration = 2000 })
end

local function testRadialStatus()
    local isOpen = lib.isRadialOpen()
    local isDisabled = lib.isRadialDisabled()
    local currentMenu = lib.getCurrentRadialId() or 'global'
    
    lib.notify({
        type = 'info',
        title = 'Radial Status',
        description = ('Open: %s | Disabled: %s | Menu: %s'):format(
            isOpen and 'Yes' or 'No',
            isDisabled and 'Yes' or 'No', 
            currentMenu
        ),
        duration = 3000
    })
end

local function testDisableRadial()
    lib.disableRadial(true)
    lib.notify({ type = 'warning', title = 'Radial', description = 'Radial menu DISABLED', duration = 2000 })
end

local function testEnableRadial()
    lib.disableRadial(false)
    lib.notify({ type = 'success', title = 'Radial', description = 'Radial menu ENABLED', duration = 2000 })
end

-- Radial Menu submenu
lib.registerMenu({
    id = 'cortex_radial_menu',
    title = 'RADIAL MENU',
    subtitle = 'Test radial menu system',
    position = 'top-right',
    options = {
        { label = 'Basic Radial', description = 'Simple 4-item radial menu' },
        { label = 'With Sub Menu', description = 'Radial with nested sub-menu' },
        { label = 'Many Items (Pagination)', description = '12-item radial with pagination' },
        { label = 'Global Items', description = 'Add items to global radial menu' },
        { label = 'Remove Global Item', description = 'Remove a global item' },
        { label = 'Clear Global Items', description = 'Clear all global items' },
        { label = 'Check Status', description = 'Check radial state', close = false },
        { label = 'Disable Radial', description = 'Disable radial menu' },
        { label = 'Enable Radial', description = 'Re-enable radial menu' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then testBasicRadial()
    elseif selected == 2 then testRadialWithSubMenu()
    elseif selected == 3 then testRadialManyItems()
    elseif selected == 4 then testGlobalRadialItems()
    elseif selected == 5 then testRemoveGlobalItem()
    elseif selected == 6 then testClearGlobalItems()
    elseif selected == 7 then testRadialStatus()
    elseif selected == 8 then testDisableRadial()
    elseif selected == 9 then testEnableRadial()
    end
end)

-- ============================================================================
-- UPDATE MAIN MENU
-- ============================================================================

-- Re-register main menu with new options
lib.registerMenu({
    id = 'cortex_main_menu',
    title = 'CORTEX',
    subtitle = 'Feature Test Menu',
    position = 'top-right',
    canClose = true,
    disableInput = false,
    options = {
        { label = 'Notifications', description = 'Test notification system', icon = '🔔' },
        { label = 'Progress Bars', description = 'Test standard progress bars', icon = '📊' },
        { label = 'Progress Extras', description = 'Animations, props, control locks', icon = '⏳' },
        { label = 'Menus', description = 'Test menu system', icon = '📋' },
        { label = 'Radial Menu', description = 'Test radial menu system', icon = '🎯' },
        { label = 'Alert Dialogs', description = 'Test alert dialogs', icon = '⚠️' },
        { label = 'Text UI', description = 'Test text UI prompts', icon = '💬' },
        { label = 'Debug Panel', description = 'Test debug overlay', icon = '🧪' },
        { label = 'Utilities', description = 'Asset loading and helpers', icon = '🧰' },
        { label = 'Getters', description = 'Get closest/nearby entities', icon = '🎯' },
        { label = 'Raycast', description = 'Raycast functions', icon = '📍' },
        { label = 'Zones', description = 'Zone system (sphere/box/poly)', icon = '🗺️' },
        { label = 'Points', description = 'Points system with callbacks', icon = '📌' },
        { label = 'Timer', description = 'Timer utility', icon = '⏱️' },
        { label = 'Disable Controls', description = 'Control disabling utility', icon = '🚫' },
        { label = 'WaitFor', description = 'Async condition waiting', icon = '⏳' },
        { label = 'Clear All', description = 'Clear everything', icon = '🗑️' },
    }
}, function(selected, scrollIndex, args)
    if selected == 1 then lib.showMenu('cortex_notify_menu')
    elseif selected == 2 then lib.showMenu('cortex_progress_menu')
    elseif selected == 3 then lib.showMenu('cortex_progress_extra_menu')
    elseif selected == 4 then lib.showMenu('cortex_menu_test_menu')
    elseif selected == 5 then lib.showMenu('cortex_radial_menu')
    elseif selected == 6 then lib.showMenu('cortex_alert_menu')
    elseif selected == 7 then lib.showMenu('cortex_textui_menu')
    elseif selected == 8 then lib.showMenu('cortex_debug_panel_menu')
    elseif selected == 9 then lib.showMenu('cortex_util_menu')
    elseif selected == 10 then lib.showMenu('cortex_getters_menu')
    elseif selected == 11 then lib.showMenu('cortex_raycast_menu')
    elseif selected == 12 then lib.showMenu('cortex_zones_menu')
    elseif selected == 13 then lib.showMenu('cortex_points_menu')
    elseif selected == 14 then lib.showMenu('cortex_timer_menu')
    elseif selected == 15 then lib.showMenu('cortex_controls_menu')
    elseif selected == 16 then lib.showMenu('cortex_waitfor_menu')
    elseif selected == 17 then clearAll()
    end
end)

-- ============================================================================
-- COMMANDS
-- ============================================================================

RegisterCommand('cortex', function()
    lib.showMenu('cortex_main_menu')
end, false)

print('^2[cortex-lib]^7 Test menu loaded. Use /cortex to open the test menu')
