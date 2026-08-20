fx_version 'cerulean'
game 'gta5'

name 'cortex-lib'
author 'Cortex'
version '2.0.0'
description 'Lightweight UI and utility library for the Cortex ecosystem (module-based)'

shared_script 'resource/init.lua'

client_scripts {
    'client/utils.lua',
    'client/interaction_renderer.lua',
    'client/debug_panel.lua',
}

ui_page 'ui/index.html'

files {
    'init.lua',
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/vendor/react.production.min.js',
    'ui/vendor/react-dom.production.min.js',
    'imports/notify/client.lua',
    'imports/callback/client.lua',
    'imports/menu/client.lua',
    'imports/radial/client.lua',
    'imports/zones/client.lua',
    'imports/points/client.lua',
    'imports/raycast/client.lua',
    'imports/getters/client.lua',
    'imports/disablecontrols/client.lua',
    'imports/help/client.lua',
    'imports/interaction/client.lua',
    'imports/settings/client.lua',
    'imports/notify/server.lua',
    'imports/callback/server.lua',
    'imports/timer/shared.lua',
    'imports/waitFor/shared.lua',
    'imports/utils/shared.lua',
}

lua54 'yes'
