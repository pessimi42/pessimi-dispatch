Config = {}

-- 'auto' detects qbx_core -> qb-core -> es_extended. Force with 'qbox' | 'qbcore' | 'esx' | 'standalone'.
Config.Framework = 'auto'
Config.Debug = false

-- Test mode: frequent AI calls, fast NPC units and debug prints. See the
-- "Test mode" block at the end of this file for exactly what it changes.
-- Turn OFF on a live server.
Config.TestMode = false

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

---------------------------------------------------------------------------
-- Caller location
---------------------------------------------------------------------------
Config.Location = {
    track = true,                -- the call's location follows the caller while the call is open
    interval = 10,               -- seconds between checks
    minMove = 25.0,              -- metres the caller must move before the location is updated
    maxMinutes = 30,             -- stop tracking a call after this long
    locateButton = true,         -- "Locate caller" button for dispatchers
    requirePhone = false,        -- with a phone script running: only callers with an equipped phone can be located
}

---------------------------------------------------------------------------
-- NPC units (responders when no player unit can take a call)
---------------------------------------------------------------------------
Config.AiUnits = {
    enabled = true,
    -- Automatic dispatch: a call that still has no unit after `waitSeconds` gets an NPC unit.
    auto = true,
    waitSeconds = 45,
    -- 'no_on_duty'   = AI only when nobody of that service is on duty (players always come first)
    -- 'no_available' = AI also when units are on duty but all busy
    -- 'always'       = AI whenever a call has no unit after waitSeconds (testing)
    -- Applies to automatic dispatch and to the dispatcher's "Send NPC unit" button.
    trigger = 'no_on_duty',
    autoWithDispatcher = false,  -- true: also send automatically while a dispatcher is on duty
    maxActive = 4,               -- NPC units on the map at the same time
    closeWhenDone = true,        -- close the call when the NPC unit leaves (if no players are on it)

    spawnDistance = { 180.0, 320.0 }, -- metres from the call (on a road)
    driveTimeout = 120,          -- seconds; then the vehicle is moved close to the scene
    arriveDistance = 30.0,
    drivingStyle = 786603,
    -- Lights and sirens only for these call priorities. C and D calls: no blue lights or
    -- sirens, normal driving speed.
    sirenPriorities = { A = true, B = true },
    urgentSpeed = 28.0,          -- m/s with lights and sirens
    normalSpeed = 17.0,          -- m/s without
    -- A player near the call controls the NPCs. With nobody in range the NPC unit still
    -- "arrives" after this many seconds and does its job, just without visible NPCs.
    hostRange = 350.0,
    virtualTravelSeconds = 40,
    -- A virtual unit becomes visible when a player comes within hostRange:
    handOver = true,             -- still driving: the NPCs spawn and drive in
    visibleOnScene = true,       -- already working: the vehicle and crew appear at the scene
    watchInterval = 3,           -- seconds between checks

    -- Revive used by NPC medics. nil = framework default
    -- (Qbox: qbx_medical Revive export, QBCore: hospital:client:Revive, ESX: esx_ambulancejob:revive).
    -- Set a client event name here if you use another medical script.
    reviveEvent = nil,

    -- vehicle / ped: one model or a list. The first one that spawns and stays is used.
    -- Many Qbox/QBCore servers blacklist s_m_y_cop_01 and firetruk (smallresources) and
    -- delete them as soon as they spawn, so put an allowed model first.
    -- action: 'revive' (treat the caller) | 'repair' (fix the nearest vehicle)
    --         'extinguish' (put out fires) | 'secure' (presence only)
    services = {
        -- visible = false: the unit never spawns or drives to the scene; it is only dispatched,
        -- arrives, acts and leaves in the dispatch panel (status and notes as usual).
        police = {
            enabled = true, visible = false, action = 'secure',
            vehicle = { 'police', 'police2', 'police3' }, ped = { 'csb_cop', 's_m_y_cop_01', 's_m_m_security_01' },
            scenario = 'WORLD_HUMAN_COP_IDLES', actSeconds = 20, onSceneSeconds = 150,
        },
        ems = {
            enabled = true, action = 'revive',
            vehicle = { 'ambulance' }, ped = { 's_m_m_paramedic_01' },
            scenario = 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', actSeconds = 15, onSceneSeconds = 60,
            -- Treats every downed or injured player within this many metres of the scene
            -- (the caller too, if they're there). Unhurt players are left alone.
            treatRadius = 20.0,
        },
        fire = {
            enabled = true, action = 'extinguish',
            vehicle = { 'firetruk', 'ambulance' }, ped = { 's_m_y_fireman_01' },
            scenario = 'WORLD_HUMAN_STAND_IMPATIENT', actSeconds = 15, onSceneSeconds = 90,
        },
        -- NPC mechanic: only when no player mechanics are on duty, and only for calls made by
        -- players (never for AI calls). Repairs the nearest vehicle at the scene.
        mechanic = {
            enabled = true, action = 'repair',
            trigger = 'no_on_duty',      -- per-service override of the trigger above
            playerCallsOnly = true,      -- not for generated AI calls
            vehicle = { 'towtruck', 'towtruck2' }, ped = { 's_m_m_trucker_01' },
            scenario = 'WORLD_HUMAN_VEHICLE_MECHANIC', actSeconds = 20, onSceneSeconds = 60,
        },
    },
}

---------------------------------------------------------------------------
-- AI calls (generated 112 calls and texts when players are not calling)
---------------------------------------------------------------------------
Config.AiCalls = {
    enabled = true,              -- default state; the in-game switch overrides it and is remembered
    command = 'aicalls',         -- /aicalls [on|off] – no argument toggles
    testCommand = 'aicall',      -- /aicall [police|ems|fire|mechanic] – create one call right now
    -- Who may use the switch: ACE 'pessimi42_dispatch.admin' (add_ace group.admin pessimi42_dispatch.admin allow)
    allowDispatchers = true,     -- on-duty dispatchers may switch it too (also from the panel)

    quietMinutes = 5,            -- generate only when no player has called or texted 112 for this long
    interval = { 3, 8 },         -- minutes between generated calls (random in range)
    maxOpen = 3,                 -- open AI calls at the same time
    smsChance = 0.25,            -- share of AI calls that arrive as a text instead of a phone call
    replyToSms = true,           -- the "caller" answers the dispatcher's texts
    showBadge = true,            -- mark AI calls with an "AI" tag on the panel
    -- When AI calls are generated:
    requireDispatcher = true,    -- only while a dispatcher is on duty
    -- Players on duty in a responding service (police, EMS, fire, mechanic):
    --   'any'     = no AI calls at all while any of them has a player on duty
    --   'service' = no AI calls for that service only (others still get them)
    --   false     = ignore players on duty
    playersOnDuty = 'any',
    -- How often each service gets a call (among the services allowed above)
    weights = { police = 5, ems = 3, fire = 1, mechanic = 0 },  -- mechanic 0: NPC mechanics only take player calls

    -- Call types per service (texts in locales: aicall.<type>.1 / .2) and their priority
    types = {
        police = {
            { type = 'robbery', priority = 'B' }, { type = 'shooting', priority = 'A' },
            { type = 'assault', priority = 'B' }, { type = 'theft', priority = 'C' },
            { type = 'traffic', priority = 'C' }, { type = 'domestic', priority = 'B' },
            { type = 'suspicious', priority = 'C' },
        },
        -- EMS: priority comes from typePriority in config/services.lua
        ems = {
            { type = 'cardiac_arrest' }, { type = 'unconscious' }, { type = 'breathing' },
            { type = 'chest_pain' }, { type = 'stroke' }, { type = 'seizure' },
            { type = 'bleeding' }, { type = 'allergy' }, { type = 'overdose' },
            { type = 'hypoglycemia' }, { type = 'childbirth' }, { type = 'fall_height' },
            { type = 'fall' }, { type = 'injury' }, { type = 'traffic_accident' },
            { type = 'drowning' }, { type = 'burn' }, { type = 'abdominal_pain' },
            { type = 'mental_health' }, { type = 'weakness' },
        },
        fire = {
            { type = 'building_fire', priority = 'A' }, { type = 'vehicle_fire', priority = 'B' },
            { type = 'wildfire', priority = 'B' }, { type = 'rescue', priority = 'B' },
            { type = 'hazmat', priority = 'B' },
        },
        mechanic = {
            { type = 'breakdown', priority = 'D' }, { type = 'tow', priority = 'D' },
            { type = 'flat_tyre', priority = 'D' },
        },
    },

    names = {
        'Matti Virtanen', 'Anna Korhonen', 'Jukka Nieminen', 'Laura Mäkinen', 'Mikko Hämäläinen',
        'Sanna Laine', 'Erik Lindqvist', 'Sofia Nyström', 'Johan Holmberg', 'Emma Sjöberg',
        'James Miller', 'Sarah Johnson', 'Carlos Ramirez', 'Lisa Chen', 'Tom Walker',
    },

    -- Where AI calls happen (street names are filled in automatically)
    locations = {
        vector3(215.8, -810.1, 30.7),    vector3(-47.0, -1757.5, 29.4),  vector3(373.9, 326.4, 103.6),
        vector3(1135.7, -982.3, 46.4),   vector3(-1222.5, -907.1, 12.3), vector3(-707.3, -914.6, 19.2),
        vector3(25.7, -1347.3, 29.5),    vector3(-1487.6, -380.0, 40.2), vector3(1163.4, -323.8, 69.2),
        vector3(-3038.9, 585.9, 7.9),    vector3(1698.4, 4924.4, 42.1),  vector3(1961.2, 3740.0, 32.3),
        vector3(-1820.5, 792.4, 138.1),  vector3(-321.8, -1545.6, 27.6), vector3(146.9, -1037.4, 29.4),
        vector3(-1050.0, -2731.9, 13.8), vector3(813.7, -1290.1, 26.3),  vector3(-556.0, 286.7, 82.2),
        vector3(1197.7, 2705.6, 38.2),   vector3(-158.6, 6327.2, 31.6),  vector3(2557.3, 382.1, 108.6),
        vector3(-2072.6, -312.7, 13.3),  vector3(287.8, -585.1, 43.2),   vector3(-622.5, -232.9, 38.1),
    },
}

---------------------------------------------------------------------------
-- NPC scenes for AI calls (patients, witnesses, crashes, fires, breakdowns)
---------------------------------------------------------------------------
Config.Scenes = {
    enabled = true,
    spawnRange = 150.0,          -- NPCs appear when a player comes this close to an AI call
    maxActive = 6,
    interactDistance = 2.5,      -- metres from the NPC to get the E prompt
    interactKey = 38,            -- E
    fireRadius = 30.0,           -- fires within this radius must be out for a fire call to count as handled

    -- Call type -> scene kind
    kinds = {
        injury = 'patient', unconscious = 'patient', breathing = 'patient',
        chest_pain = 'patient', overdose = 'patient', cardiac_arrest = 'patient',
        stroke = 'patient', seizure = 'patient', bleeding = 'patient', allergy = 'patient',
        hypoglycemia = 'patient', childbirth = 'patient', fall_height = 'patient',
        fall = 'patient', drowning = 'patient', burn = 'patient', abdominal_pain = 'patient',
        mental_health = 'patient', weakness = 'patient',
        traffic_accident = 'crash',
        robbery = 'witness', assault = 'witness', theft = 'witness', traffic = 'witness',
        domestic = 'witness', suspicious = 'witness', rescue = 'witness', hazmat = 'witness',
        shooting = 'cower',
        vehicle_fire = 'carfire', building_fire = 'fire', wildfire = 'fire',
        breakdown = 'breakdown', tow = 'breakdown', flat_tyre = 'breakdown',
    },

    -- Which units can interact with each kind (E prompt). Fires are handled by putting them out.
    interact = {
        patient = { 'ems' }, crash = { 'ems' },
        witness = { 'police' }, cower = { 'police' },
        breakdown = { 'mechanic' },
    },

    peds = {
        'a_m_y_business_01', 'a_f_y_tourist_01', 'a_m_m_farmer_01', 'a_f_m_bevhills_01',
        'a_m_y_hipster_01', 'a_f_y_business_02', 'a_m_m_genfat_01', 'a_f_m_fatwhite_01',
    },
    vehicles = { 'blista', 'asea', 'premier', 'primo', 'ingot', 'emperor' },
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

---------------------------------------------------------------------------
-- Test mode (Config.TestMode = true at the top)
---------------------------------------------------------------------------
if Config.TestMode then
    Config.Debug = true
    -- An AI call every 30-60 s, right away, even with nobody on duty
    Config.AiCalls.quietMinutes = 0
    Config.AiCalls.interval = { 0.5, 1 }
    Config.AiCalls.maxOpen = 4
    Config.AiCalls.requireDispatcher = false
    Config.AiCalls.playersOnDuty = false
    -- NPC units leave sooner and come even when players of the service are on duty
    Config.AiUnits.waitSeconds = 10
    Config.AiUnits.virtualTravelSeconds = 15
    Config.AiUnits.trigger = 'always'
    Config.AiUnits.services.police.onSceneSeconds = 60
end
