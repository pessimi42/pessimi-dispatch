-- AI calls: realistic 112 calls and texts generated while players are quiet, so
-- on-duty units and dispatchers have something to do. Switch with /aicalls.

AiCalls = { lastPlayerCall = 0 }

local cfg = Config.AiCalls
local KVP = 'aicalls:enabled'
local KVP_FAST = 'aicalls:fast'

function AiCalls.Enabled()
    local v = GetResourceKvpInt(KVP)
    if v == 1 then return true elseif v == 2 then return false end
    return cfg.enabled == true
end

--- Fast mode (testing): frequent AI calls, no quiet time.
function AiCalls.Fast()
    return GetResourceKvpInt(KVP_FAST) == 1
end

--- Timing in effect: { interval = {min, max} minutes, quietMinutes, maxOpen }
local FAST_DEFAULTS = { interval = { 0.5, 1 }, quietMinutes = 0, maxOpen = 5 }

local function timing()
    if AiCalls.Fast() then
        local f = cfg.fast or FAST_DEFAULTS          -- works without the config line too
        return {
            interval = f.interval or FAST_DEFAULTS.interval,
            quietMinutes = f.quietMinutes or FAST_DEFAULTS.quietMinutes,
            maxOpen = f.maxOpen or FAST_DEFAULTS.maxOpen,
        }
    end
    return { interval = cfg.interval, quietMinutes = cfg.quietMinutes, maxOpen = cfg.maxOpen }
end

local nextAt = 0      -- os.time() of the next generation attempt

local function scheduleNext()
    local t = timing()
    local minS = math.max(10, math.floor(t.interval[1] * 60))
    local maxS = math.max(minS, math.floor(t.interval[2] * 60))
    local wait = math.random(minS, maxS)
    nextAt = os.time() + wait
    Utils.Debug(('next AI call check in %d s%s'):format(wait, AiCalls.Fast() and ' (fast mode)' or ''))
end

--- Seconds until the next generation attempt.
function AiCalls.SecondsToNext() return math.max(0, nextAt - os.time()) end

local function broadcastState()
    Dispatch.Send('client:aiCallsState', { enabled = AiCalls.Enabled(), fast = AiCalls.Fast() })
end

function AiCalls.SetFast(state)
    SetResourceKvpInt(KVP_FAST, state and 1 or 0)
    scheduleNext()            -- the new pace applies right away, not after the old wait
    broadcastState()
end

function AiCalls.Set(state)
    SetResourceKvpInt(KVP, state and 1 or 2)
    broadcastState()
    Utils.Debug('AI calls', state and 'on' or 'off')
end

--- Player-made calls and texts reset the quiet timer (called from Calls.Create).
function AiCalls.NotePlayerCall()
    AiCalls.lastPlayerCall = os.time()
end

local function openCount()
    local n = 0
    for _, c in pairs(Calls.list) do
        if c._ai and c.status ~= 'closed' then n = n + 1 end
    end
    return n
end

local function pick(list) return list[math.random(#list)] end

--- Where a call of this type happens: its own places if it has any (drowning by the
--- water, config/waterside.lua), otherwise anywhere in `locations`. Own places get less
--- random offset.
local function locationFor(callType)
    local own = cfg.typeLocations and cfg.typeLocations[callType]
    if not own and callType == 'drowning' then own = Config.Waterside end
    if own and #own > 0 then
        local l = pick(own)
        return { x = l.x + math.random(-3, 3), y = l.y + math.random(-3, 3), z = l.z }
    end
    local l = pick(cfg.locations)
    return { x = l.x + math.random(-15, 15), y = l.y + math.random(-15, 15), z = l.z }
end
AiCalls.LocationFor = locationFor

--- Weighted random service among enabled services someone can respond to.
--- Weighted random service for an automatic AI call, or nil and a reason.
--- Only while a dispatcher is on duty (requireDispatcher). With playersOnDuty = 'any' there
--- are none while any responding service has a player on duty; with 'service' only that
--- service is skipped.
local function pickService()
    if cfg.requireDispatcher ~= false and not Dispatch.HasDispatcher() then
        return nil, 'no_dispatcher'
    end
    local mode = cfg.playersOnDuty
    if mode == 'any' and #Units.OnDutyIn(nil) > 0 then
        return nil, 'players_on_duty'
    end
    local pool, total = {}, 0
    for service, weight in pairs(cfg.weights) do
        if Utils.ServiceEnabled(service) and cfg.types[service] and weight > 0
            and not (mode == 'service' and #Units.OnDutyIn(service) > 0) then
            pool[#pool + 1] = { service = service, weight = weight }
            total = total + weight
        end
    end
    if total == 0 then return nil, 'players_on_duty' end
    local r = math.random() * total
    for _, p in ipairs(pool) do
        r = r - p.weight
        if r <= 0 then return p.service end
    end
    return pool[#pool].service
end

local function randomPhone()
    return ('040%07d'):format(math.random(0, 9999999))
end

--- Create one AI call now. Returns the call id, or nil and a reason.
function AiCalls.Generate(service)
    if service and not (Utils.ServiceEnabled(service) and cfg.types[service]) then return nil, 'bad_service' end
    if not service then
        local why
        service, why = pickService()
        if not service then return nil, why end
    end
    local t = pick(cfg.types[service])
    local asSms = math.random() < cfg.smsChance
    local variant = math.random(1, 2)

    local id = Calls.Create({
        service = service,
        type = t.type,
        priority = t.priority or Utils.TypePriority(service, t.type),
        message = Locale.T(('aicall.%s.%d'):format(t.type, variant)),
        coords = locationFor(t.type),
        caller = { name = pick(cfg.names), phone = randomPhone() },
        origin = asSms and 'sms' or '112',
    }, { ai = true })
    Utils.Debug(('AI call #%d generated (%s / %s)'):format(id, service, t.type))
    return id
end

--- Texts to an AI caller are not sent anywhere; the "caller" may answer instead.
function AiCalls.OnDispatcherSms(call)
    if not cfg.replyToSms or call._aiReplied then return end
    call._aiReplied = true
    SetTimeout(math.random(8, 20) * 1000, function()
        local c = Calls.Get(call.id)
        if not c or c.status == 'closed' then return end
        Calls.AddNote(c.id, Locale.T(('aicall.reply.%d'):format(math.random(1, 3))),
            c.caller and c.caller.name or nil, 'sms_in')
    end)
end

---------------------------------------------------------------------------
-- Generator loop
---------------------------------------------------------------------------
--- One generation attempt (called by the loop when it's time).
function AiCalls.Tick()
    local t = timing()
    local quietLeft = t.quietMinutes * 60 - (os.time() - AiCalls.lastPlayerCall)
    if not AiCalls.Enabled() then
        Utils.Debug('AI call skipped: AI calls are off')
    elseif quietLeft > 0 then
        Utils.Debug(('AI call skipped: a player called recently (%d s of quiet left)'):format(quietLeft))
    elseif openCount() >= t.maxOpen then
        Utils.Debug(('AI call skipped: %d AI calls already open (maxOpen)'):format(openCount()))
    else
        local id, why = AiCalls.Generate()
        if not id then
            Utils.Debug('AI call skipped:', why == 'no_dispatcher' and 'no dispatcher on duty'
                or 'players on duty in a responding service')
        end
        return id
    end
end

CreateThread(function()
    AiCalls.lastPlayerCall = os.time()
    scheduleNext()
    while true do
        Wait(5000)
        if os.time() >= nextAt then
            AiCalls.Tick()
            scheduleNext()
        end
    end
end)

---------------------------------------------------------------------------
-- Switch
---------------------------------------------------------------------------
function AiCalls.CanToggle(src)
    if src == 0 then return true end -- server console
    if IsPlayerAceAllowed(src, Utils.Resource .. '.admin') then return true end
    return cfg.allowDispatchers and Dispatch.list[src] ~= nil
end

--- Why AI calls are (not) being generated right now. Returns a list of lines.
function AiCalls.Status()
    local t = timing()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local blocked

    add(('AI calls: %s, %s pace, next attempt in %d s'):format(
        AiCalls.Enabled() and 'ON' or 'OFF', AiCalls.Fast() and 'fast' or 'normal', AiCalls.SecondsToNext()))
    if not AiCalls.Enabled() then blocked = blocked or 'AI calls are switched off (/aicalls on)' end

    local names = {}
    for src, d in pairs(Dispatch.list) do names[#names + 1] = ('%s [%d]'):format(d.name or '?', src) end
    add('Dispatchers on duty: ' .. (#names > 0 and table.concat(names, ', ') or 'none'))
    if cfg.requireDispatcher ~= false and #names == 0 then
        blocked = blocked or 'no dispatcher on duty (job ' .. next(Config.Dispatcher.jobs) .. ', /' .. Config.Dispatcher.dutyCommand .. ')'
    end

    local units = {}
    for src, u in pairs(Units.list) do units[#units + 1] = ('%s: %s [%d]'):format(u.service, u.name or '?', src) end
    add('Responder players on duty: ' .. (#units > 0 and table.concat(units, ', ') or 'none'))
    if cfg.playersOnDuty == 'any' and #units > 0 then
        blocked = blocked or 'responder players are on duty (playersOnDuty = any)'
    end

    local quietLeft = math.max(0, t.quietMinutes * 60 - (os.time() - AiCalls.lastPlayerCall))
    add(('Quiet time left after the last player call: %d s'):format(quietLeft))
    if quietLeft > 0 then blocked = blocked or ('a player called recently, %d s of quiet left'):format(quietLeft) end

    add(('Open AI calls: %d / %d'):format(openCount(), t.maxOpen))
    if openCount() >= t.maxOpen then blocked = blocked or 'too many AI calls open (close some)' end

    add(blocked and ('=> NOT generating: ' .. blocked) or '=> Calls will be generated')
    return lines, blocked
end

local function sendStatus(src)
    local lines = AiCalls.Status()
    for _, l in ipairs(lines) do
        if src == 0 then
            print(('[%s] %s'):format(Utils.Resource, l))
        else
            TriggerClientEvent('chat:addMessage', src, { args = { 'AI calls', l } })
        end
    end
end

local function toggle(src, arg)
    if not AiCalls.CanToggle(src) then
        if src ~= 0 then Notify(src, 'error.no_permission', nil, 'error') end
        return
    end
    if arg == 'status' then return sendStatus(src) end
    -- /aicalls fast | normal: testing pace (fast also switches AI calls on)
    if arg == 'fast' or arg == 'normal' then
        local fast = arg == 'fast'
        if fast and not AiCalls.Enabled() then AiCalls.Set(true) end
        AiCalls.SetFast(fast)
        if src ~= 0 then
            Notify(src, fast and 'aicalls.fast_on' or 'aicalls.fast_off', nil, 'inform')
        else
            print(('[%s] AI calls: %s pace'):format(Utils.Resource, fast and 'fast' or 'normal'))
        end
        return
    end
    local state
    if arg == 'on' then state = true elseif arg == 'off' then state = false else state = not AiCalls.Enabled() end
    AiCalls.Set(state)
    if src ~= 0 then
        Notify(src, state and 'aicalls.on' or 'aicalls.off', nil, 'inform')
    else
        print(('[%s] AI calls %s'):format(Utils.Resource, state and 'on' or 'off'))
    end
end

RegisterCommand(cfg.command, function(src, args) toggle(src, args[1] and args[1]:lower()) end, false)

RegisterNetEvent(Ev('server:aiCallsToggle'), function(state)
    toggle(source, state == true and 'on' or state == false and 'off' or nil)
end)

--- /aicall [service] – create one AI call right now (testing). Same permission as the switch.
if cfg.testCommand and cfg.testCommand ~= '' then
    RegisterCommand(cfg.testCommand, function(src, args)
        if not AiCalls.CanToggle(src) then
            if src ~= 0 then Notify(src, 'error.no_permission', nil, 'error') end
            return
        end
        local id, why = AiCalls.Generate(args[1] and args[1]:lower() or nil)
        if src == 0 then
            print(('[%s] %s'):format(Utils.Resource, id and ('AI call #' .. id .. ' created') or ('no call: ' .. tostring(why))))
        elseif id then
            Notify(src, 'aicalls.generated', { id = id }, 'success')
        else
            Notify(src, 'aicalls.not_generated', nil, 'error')
        end
    end, false)
end
