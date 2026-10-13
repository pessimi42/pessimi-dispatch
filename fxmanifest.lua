fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pessimi42_dispatch'
description 'Emergency dispatcher job (112) for Qbox, QBCore and ESX'
version '0.3.0-beta'

shared_scripts {
    'config/config.lua',
    'config/services.lua',
    'config/integrations.lua',
    'shared/utils.lua',
    'shared/locale.lua',
    'bridge/shared.lua',
}

server_scripts {
    'bridge/server/*.lua',
    'server/units.lua',
    'server/calls.lua',
    'server/adapters.lua',
    'server/phone.lua',
    'server/phones/*.lua',
    'server/sms.lua',
    'server/ai.lua',
    'server/integrations/*.lua',
    'server/main.lua',
    'server/api.lua',
}

client_scripts {
    'bridge/client/*.lua',
    'client/nui.lua',
    'client/blips.lua',
    'client/ai.lua',
    'client/main.lua',
    'client/api.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'locales/*.json',
    'web/112.svg',
}
