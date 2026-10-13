Config = {}

-- 'auto' detects qbx_core -> qb-core -> es_extended. Force with 'qbox' | 'qbcore' | 'esx' | 'standalone'.
Config.Framework = 'auto'
Config.Debug = false

---------------------------------------------------------------------------
-- Language
---------------------------------------------------------------------------
-- Default language. Players can pick their own with /dispatchlang when
-- AllowPlayerLanguage is true (handy on bilingual fi/sv servers).
Config.Locale = 'fi'
-- Every code listed here must have locales/<code>.json. To add a language,
-- copy locales/en.json, translate it and add the code here.
Config.Languages = { 'en', 'fi', 'sv' }
Config.AllowPlayerLanguage = true
Config.LanguageCommand = 'dispatchlang'

---------------------------------------------------------------------------
-- Dispatcher job
---------------------------------------------------------------------------
Config.Dispatcher = {
    jobs = { dispatch = 0 },     -- [job name] = minimum grade
    requireDuty = true,
    command = 'dispatch',        -- opens the panel
    key = 'F6',                  -- default key, players can rebind in GTA settings
    dutyCommand = 'dispatchduty',
}

---------------------------------------------------------------------------
-- Emergency calls (players)
---------------------------------------------------------------------------
Config.EmergencyCall = {
    commands = { '112' },        -- add '911' etc. if you like
    cooldown = 30,               -- seconds between calls per player
    minLength = 3,
    maxLength = 300,
    requireItem = false,         -- require a phone item to call
    items = { 'phone' },
    notifyCaller = true,         -- tell the caller when units are assigned
}

---------------------------------------------------------------------------
-- Phone & SMS
---------------------------------------------------------------------------
-- 'auto' uses the first supported phone that is running (currently lb-phone),
-- 'lb-phone' forces it, 'none' disables phone features. Other phones can be
-- added with exports.pessimi42_dispatch:RegisterPhone() – see server/phones/_template.lua.
Config.Phone = {
    provider = 'auto',
    number = '112',              -- number players text, and the sender of our SMS
    requirePhone = false,        -- calling 112 needs an equipped phone (replaces requireItem when a phone is running)
}

Config.Sms = {
    enabled = true,              -- needs a supported phone; without one everything falls back to notifications
    maxLength = 250,
    incoming = true,             -- texts to Config.Phone.number create calls or are added to the caller's open call
    incomingCooldown = 10,       -- seconds between texts that create a NEW call (per number)
    -- Automatic texts to the caller
    auto = {
        received = true,         -- "Your call has been received"
        assigned = true,         -- "Help is on the way"
        closed = true,           -- "Your case has been closed"
    },
    toUnits = true,              -- assigned units get the call details + location pin by SMS
    -- Quick replies in the dispatcher panel (translated as sms.quick.<key>, in the caller's language)
    quickReplies = { 'on_the_way', 'stay_put', 'safe_place', 'describe', 'call_back' },
}

-- Automatic alerts sent by other client scripts through exports.pessimi42_dispatch:CreateAlert()
Config.ClientAlerts = {
    enabled = true,
    cooldown = 5,                -- seconds per player
}

-- What happens to new calls when nobody is on duty as a dispatcher
Config.Fallback = {
    -- 'nearest'   assign the nearest available unit of the call's service
    -- 'broadcast' alert every on-duty unit of the service and let them respond
    -- 'none'      calls wait in the queue for a dispatcher
    mode = 'nearest',
    maxDistance = 0,             -- metres; 0 = no limit. Units further away are skipped.
    broadcastIfNoUnit = true,    -- 'nearest' found nobody -> broadcast instead
    unspecifiedService = 'police', -- service used to pick a unit when the caller chose "not sure"
    closeWhenUnitsDone = true,   -- last unit sets itself available -> call is closed
                                 -- (a unit that disconnects instead hands the call to the next nearest)
}

---------------------------------------------------------------------------
-- Units (police, EMS, ...)
---------------------------------------------------------------------------
Config.Units = {
    statusCommand = 'status',
    callsignCommand = 'callsign',
    respondCommand = 'respond',
    respondKey = '',             -- e.g. 'Y'; empty = unbound, players can bind it
    callsignMaxLength = 10,
    autoWaypoint = true,
    autoOnScene = true,          -- switch to 'onscene' when close to the call
    onSceneDistance = 40.0,
    allowCrossService = true,    -- e.g. police may respond to an EMS broadcast
    hud = true,                  -- small status card for on-duty units
}

-- Order matters: it is the order shown in the panel.
-- `code` is an optional radio code shown next to the label and accepted by /status.
Config.UnitStatuses = {
    { id = 'available',   color = '#22c55e', code = '10-8' },
    { id = 'enroute',     color = '#3b82f6', code = '10-76' },
    { id = 'onscene',     color = '#a855f7', code = '10-23' },
    { id = 'busy',        color = '#f97316', code = '10-6' },
    { id = 'unavailable', color = '#6b7280', code = '10-7' },
}

---------------------------------------------------------------------------
-- Calls
---------------------------------------------------------------------------
-- Highest first. Modelled on the Finnish A-D urgency classes.
Config.Priorities = {
    { id = 'A', color = '#ef4444', sound = 'critical', flash = true },
    { id = 'B', color = '#f97316', sound = 'urgent' },
    { id = 'C', color = '#eab308', sound = 'default' },
    { id = 'D', color = '#22c55e', sound = 'default' },
}
Config.DefaultPriority = 'C'

Config.Calls = {
    autoCloseMinutes = 45,       -- close calls nobody has touched for this long (0 = never)
    keepClosed = 25,             -- closed calls kept in memory for the history view
}

Config.Sounds = {
    critical = { name = 'TIMER_STOP',        set = 'HUD_MINI_GAME_SOUNDSET', repeats = 2 },
    urgent   = { name = 'CHECKPOINT_MISSED', set = 'HUD_MINI_GAME_SOUNDSET' },
    default  = { name = 'Lose_1st',          set = 'GTAO_FM_Events_Soundset' },
}

-- Blip used for calls with no service yet
Config.UnknownBlip = { sprite = 280, color = 0 }

-- Standalone mode only: ACE permissions decide roles.
-- add_ace group.dispatch pessimi42_dispatch.dispatcher allow
-- add_ace group.police   pessimi42_dispatch.service.police allow
Config.StandaloneAce = 'pessimi42_dispatch'
