fx_version 'cerulean'
game 'gta5'

name 'cortex-lib'
author 'Cortex & GSD Modifications'
version '3.0.0'
description 'Shared UI and Lua utilities for FiveM resources'

shared_script 'resource/init.lua'

client_scripts {
    'client/utils.lua',
    'client/presentation.lua',
    'presentation-client.lua',
    'client/pause.lua',
    'client/interaction_renderer.lua',
    'client/debug_panel.lua',
    'client/debug_workbench.lua',
}

server_scripts {
    'server/config.lua',
    'server/debug_workbench.lua',
}

ui_page 'ui/index.html'

files {
    'init.lua',
    'presentation-client.lua',
    'ui/dynamic-layout.js',
    'ui/dynamic-ui.js',
    'ui/dynamic-ui.css',
    'ui/cortex-display.woff2',
    'ui/barlow-condensed-OFL.txt',
    'ui/index.html',
    'ui/core/tokens.css',
    'ui/core/base.css',
    'ui/core/kit.css',
    'ui/core/base.js',
    'ui/core/kit.js',
    'ui/surfaces/notify.css',
    'ui/surfaces/notify.js',
    'ui/surfaces/progress.css',
    'ui/surfaces/progress.js',
    'ui/surfaces/text.css',
    'ui/surfaces/text.js',
    'ui/surfaces/menu.css',
    'ui/surfaces/menu.js',
    'ui/surfaces/dialogs.css',
    'ui/surfaces/dialogs.js',
    'ui/surfaces/radial.css',
    'ui/surfaces/radial.js',
    'ui/surfaces/interactions.css',
    'ui/surfaces/interactions.js',
    'ui/surfaces/settings.css',
    'ui/surfaces/settings.js',
    'ui/notify-grain.svg',
    'ui/app.js',
    'ui/interaction-key.js',
    'ui/interaction-key.css',
    'ui/skill-engine.js',
    'ui/skill-checks.js',
    'ui/skill-checks.css',
    'ui/pause.js',
    'ui/pause.css',
    'ui/debug.js',
    'ui/debug.css',
    'ui/vendor/react.production.min.js',
    'ui/vendor/react-dom.production.min.js',
    'ui/vendor/LICENSE-react.txt',
    'imports/notify/client.lua',
    'imports/callback/client.lua',
    'imports/menu/client.lua',
    'imports/radial/client.lua',
    'imports/zones/client.lua',
    'imports/points/client.lua',
    'imports/raycast/client.lua',
    'imports/getters/client.lua',
    'imports/vehicleReplay/client.lua',
    'imports/disablecontrols/client.lua',
    'imports/help/client.lua',
    'imports/interaction/client.lua',
    'imports/skillCheck/client.lua',
    'imports/skillCheck/shared.lua',
    'imports/settings/client.lua',
    'imports/notify/server.lua',
    'imports/callback/server.lua',
    'imports/groups/server.lua',
    'imports/timer/shared.lua',
    'imports/waitFor/shared.lua',
    'imports/utils/shared.lua',
}

lua54 'yes'
