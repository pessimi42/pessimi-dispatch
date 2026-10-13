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
local function pickService()
    local hasDispatcher = Dispatch.HasDispatcher()
    local pool, total = {}, 0
    for service, weight in pairs(cfg.weights) do
        if Utils.ServiceEnabled(service) and cfg.types[service] and weight > 0
            and (hasDispatcher or #Units.OnDutyIn(service) > 0) then
            pool[#pool + 1] = { service = service, weight = weight }
            total = total + weight
        end
    end
    if total == 0 then return nil end
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
    service = service or pickService()
    if not service then return nil, 'no_responders' end
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
        local minM, maxM = cfg.interval[1], cfg.interval[2]
        Wait(math.random(minM * 60, maxM * 60) * 1000)
        if AiCalls.Enabled()
            and os.time() - AiCalls.lastPlayerCall >= cfg.quietMinutes * 60
            and openCount() < cfg.maxOpen then
            AiCalls.Generate()
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
