fx_version 'cerulean'
game 'gta5'

author 'DEV-JARMZ'
description 'Syncs gang data between rcore_gangs and Qbox Core, including gangs, player_groups, metadata, and ganginfo.'
version '1.0.0'

-- Server scripts
server_scripts {
    '@oxmysql/lib/MySQL.lua',  -- Ensure oxmysql is installed
    'server.lua',              -- Your main server bridge logic
}

-- Client scripts (none needed if bridge is server-only)
client_scripts {
    -- If your resource includes client functionality, list them here
}

-- Dependency (make sure these resources are started)
dependencies {
    'rcore_gangs',
    'qbx_core'
}

-- This resource automatically keeps rcore_gangs and Qbox Core gang data in sync.
