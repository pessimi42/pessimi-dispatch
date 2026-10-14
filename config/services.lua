-- Every emergency service is just a table here. Adding a new one (coast guard,
-- security, taxi...) needs a new entry plus `service.<id>` and its call types in
-- the locale files. Other resources can also add services at runtime with
-- exports.pessimi42_dispatch:RegisterService(id, definition).
--
-- jobs       [framework job name] = minimum grade that counts as a unit
-- notify     how units of this service are alerted: 'native' (built-in toast)
--            and/or any registered adapter such as 'ps-dispatch'
-- callTypes  keys translated as calltype.<key>; 'general' always exists
-- allowedPriorities  optional: the only priorities this service's calls can have; anything
--                else is moved to the nearest allowed one. Labels can be given per service in
--                the locales as priority_<service>.<A-D>. (fixedPriority = 'D' = one allowed.)
-- typePriority   optional: default priority per call type

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
        -- Modelled on the Finnish emergency response centre's EMS task classes.
        callTypes = {
            'general',
            'cardiac_arrest', 'unconscious', 'breathing', 'chest_pain', 'arrhythmia', 'stroke',
            'seizure', 'bleeding', 'allergy', 'overdose', 'hypoglycemia', 'childbirth',
            'gunshot', 'stabbing', 'blunt_trauma', 'fall_height', 'fall', 'injury',
            'traffic_accident', 'drowning', 'electric_shock', 'burn',
            'abdominal_pain', 'back_pain', 'fever', 'weakness', 'mental_health',
            'other_illness', 'transfer',
        },
        -- Default urgency per task class (A immediate & life-threatening, B immediate,
        -- C within 30 min, D within 2 h). Used for new calls and when the dispatcher
        -- changes the type; the dispatcher can still set another class.
        typePriority = {
            cardiac_arrest = 'A', unconscious = 'A', breathing = 'A', gunshot = 'A',
            stabbing = 'A', drowning = 'A',
            chest_pain = 'B', arrhythmia = 'B', stroke = 'B', seizure = 'B', bleeding = 'B',
            allergy = 'B', overdose = 'B', childbirth = 'B', blunt_trauma = 'B',
            fall_height = 'B', traffic_accident = 'B', electric_shock = 'B', burn = 'B',
            hypoglycemia = 'C', fall = 'C', injury = 'C', abdominal_pain = 'C',
            weakness = 'C', mental_health = 'C', other_illness = 'C',
            back_pain = 'D', fever = 'D', transfer = 'D',
        },
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
        enabled = true,             -- roadside assistance: player mechanics or the NPC mechanic
        order = 4,
        jobs = { mechanic = 0 },
        color = '#14b8a6',
        icon = 'wrench',
        blip = { sprite = 446, color = 25, callSprite = 446 },
        defaultPriority = 'D',
        -- Roadside calls are C (disrupting traffic) or D (not affecting other road users)
        allowedPriorities = { 'C', 'D' },
        notify = { 'native' },
        callTypes = { 'general', 'breakdown', 'tow', 'flat_tyre' },
    },
}
