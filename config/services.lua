-- Every emergency service is just a table here. Adding a new one (coast guard,
-- security, taxi...) needs a new entry plus `service.<id>` and its call types in
-- the locale files. Other resources can also add services at runtime with
-- exports.pessimi42_dispatch:RegisterService(id, definition).
--
-- jobs       [framework job name] = minimum grade that counts as a unit
-- notify     how units of this service are alerted: 'native' (built-in toast)
--            and/or any registered adapter such as 'ps-dispatch'
-- callTypes  keys translated as calltype.<key>; 'general' always exists

Services = {
    police = {
        enabled = true,
        order = 1,
        jobs = { police = 0, sheriff = 0 },
        color = '#3b82f6',
        icon = 'shield',
        blip = { sprite = 60, color = 3, callSprite = 161 },
        defaultPriority = 'B',
        notify = { 'native' },
        callTypes = { 'general', 'robbery', 'shooting', 'assault', 'theft', 'traffic', 'domestic', 'suspicious' },
    },

    ems = {
        enabled = true,
        order = 2,
        jobs = { ambulance = 0 },
        color = '#ef4444',
        icon = 'cross',
        blip = { sprite = 61, color = 1, callSprite = 153 },
        defaultPriority = 'B',
        notify = { 'native' },
        callTypes = { 'general', 'injury', 'unconscious', 'breathing', 'chest_pain', 'traffic_accident', 'overdose' },
    },

    -- Ready for later: set enabled = true and check the job names.
    fire = {
        enabled = false,
        order = 3,
        jobs = { fire = 0 },
        color = '#f59e0b',
        icon = 'flame',
        blip = { sprite = 436, color = 47, callSprite = 436 },
        defaultPriority = 'B',
        notify = { 'native' },
        callTypes = { 'general', 'building_fire', 'vehicle_fire', 'wildfire', 'rescue', 'hazmat' },
    },

    mechanic = {
        enabled = false,
        order = 4,
        jobs = { mechanic = 0 },
        color = '#14b8a6',
        icon = 'wrench',
        blip = { sprite = 446, color = 25, callSprite = 446 },
        defaultPriority = 'D',
        notify = { 'native' },
        callTypes = { 'general', 'breakdown', 'tow', 'flat_tyre' },
    },
}
