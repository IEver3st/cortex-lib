fx_version 'cerulean'
game 'gta5'

name 'es_lib'
author 'Cortex Software'
version '2.0.0'
description 'Lightweight UI and utility library for the Cortex ecosystem (module-based)'


shared_script 'resource/init.lua'


client_scripts {
    'client/utils.lua',
    'client/debug_panel.lua',
}

client_script 'tests/client/debug_commands.lua'


ui_page 'ui/index.html'

files {
    -- External init for other resources
    'init.lua',
    
    -- UI assets
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    
    -- Client modules
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
    'imports/settings/client.lua',
    
    -- Server modules
    'imports/notify/server.lua',
    'imports/callback/server.lua',
    
    -- Shared modules
    'imports/timer/shared.lua',
    'imports/waitFor/shared.lua',
    'imports/utils/shared.lua',
}

lua54 'yes'
