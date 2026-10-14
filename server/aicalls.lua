-- AI calls: realistic 112 calls and texts generated while players are quiet, so
-- on-duty units and dispatchers have something to do. Switch with /aicalls.

AiCalls = { lastPlayerCall = 0 }

local cfg = Config.AiCalls
local KVP = 'aicalls:enabled'

function AiCalls.Enabled()
    local v = GetResourceKvpInt(KVP)
    if v == 1 then return true elseif v == 2 then return false end
    return cfg.enabled == true
end

local function broadcastState()
    Dispatch.Send('client:aiCallsState', AiCalls.Enabled())
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
    local loc = pick(cfg.locations)
    local asSms = math.random() < cfg.smsChance
    local variant = math.random(1, 2)

    local id = Calls.Create({
        service = service,
        type = t.type,
        priority = t.priority,
        message = Locale.T(('aicall.%s.%d'):format(t.type, variant)),
        coords = { x = loc.x + math.random(-15, 15), y = loc.y + math.random(-15, 15), z = loc.z },
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
CreateThread(function()
    AiCalls.lastPlayerCall = os.time()
    while true do
        local minS = math.max(10, math.floor(cfg.interval[1] * 60))
        local maxS = math.max(minS, math.floor(cfg.interval[2] * 60))
        local wait = math.random(minS, maxS)
        Utils.Debug(('next AI call check in %d s'):format(wait))
        Wait(wait * 1000)
        local quietLeft = cfg.quietMinutes * 60 - (os.time() - AiCalls.lastPlayerCall)
        if not AiCalls.Enabled() then
            Utils.Debug('AI call skipped: AI calls are off')
        elseif quietLeft > 0 then
            Utils.Debug(('AI call skipped: a player called recently (%d s of quiet left)'):format(quietLeft))
        elseif openCount() >= cfg.maxOpen then
            Utils.Debug(('AI call skipped: %d AI calls already open (maxOpen)'):format(openCount()))
        else
            local id, why = AiCalls.Generate()
            if not id then
                Utils.Debug('AI call skipped:', why == 'no_dispatcher' and 'no dispatcher on duty'
                    or 'players on duty in a responding service')
            end
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

local function toggle(src, arg)
    if not AiCalls.CanToggle(src) then
        if src ~= 0 then Notify(src, 'error.no_permission', nil, 'error') end
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
