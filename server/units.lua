-- Who is a dispatcher, who is a unit, and what each unit is doing.

Units = { list = {} }        -- [src] = unit
Dispatch = { list = {} }     -- [src] = { name }

---------------------------------------------------------------------------
-- Messaging helpers
---------------------------------------------------------------------------
--- Translated on the receiving client, so each player sees their own language.
function Notify(src, key, vars, kind)
    TriggerClientEvent(Ev('client:notify'), src, key, vars, kind)
end

function Dispatch.HasDispatcher()
    return next(Dispatch.list) ~= nil
end

--- Dispatcher went off duty or left. If nobody is left, waiting calls are auto-dispatched.
function Dispatch.Leave(src)
    if not Dispatch.list[src] then return end
    Dispatch.list[src] = nil
    Utils.Debug('dispatcher off', src)
    if Dispatch.HasDispatcher() then return end
    for id, c in pairs(Calls.list) do
        if c.status == 'pending' then Calls.AutoDispatch(id) end
    end
end

function Dispatch.Send(event, ...)
    for src in pairs(Dispatch.list) do
        TriggerClientEvent(Ev(event), src, ...)
    end
end

---------------------------------------------------------------------------
-- Callsigns, persisted per character in resource KVP (no database needed)
---------------------------------------------------------------------------
Callsigns = {}

function Callsigns.Get(src)
    local id = Bridge.GetIdentifier(src)
    return id and GetResourceKvpString('callsign:' .. id) or nil
end

function Callsigns.Set(src, value)
    local id = Bridge.GetIdentifier(src)
    if not id then return end
    if value then SetResourceKvp('callsign:' .. id, value) else DeleteResourceKvp('callsign:' .. id) end
end

---------------------------------------------------------------------------
-- Units
---------------------------------------------------------------------------
function Units.Get(src) return Units.list[tonumber(src)] end

function Units.Public(u)
    return {
        src = u.src, service = u.service, name = u.name, callsign = u.callsign,
        status = u.status, call = u.call, gradeLabel = u.gradeLabel,
    }
end

function Units.All(service)
    local out = {}
    for _, u in pairs(Units.list) do
        if not service or u.service == service then out[#out + 1] = Units.Public(u) end
    end
    return out
end

function Units.OnDutyIn(service)
    local out = {}
    for src, u in pairs(Units.list) do
        if service == nil or u.service == service then out[#out + 1] = src end
    end
    return out
end

local function pushUnit(u)
    Dispatch.Send('client:unitChanged', Units.Public(u))
    TriggerClientEvent(Ev('client:unitStatus'), u.src, u.status, u.callsign)
end

--- Returns true if the status changed.
function Units.SetStatus(src, status, quiet)
    local u = Units.Get(src)
    if not u or not Utils.StatusById[status] then return false end
    if u.status == status then return false end
    u.status = status
    -- Going available/unavailable releases the unit from its call
    if (status == 'available' or status == 'unavailable') and u.call then
        Calls.Unassign(u.call, src, { keepStatus = true })
    end
    pushUnit(u)
    if not quiet then
        TriggerEvent(Ev('onUnitStatus'), src, status)
    end
    return true
end

function Units.SetCallsign(src, callsign)
    local u = Units.Get(src)
    Callsigns.Set(src, callsign)
    if u then
        u.callsign = callsign
        pushUnit(u)
    end
end

function Units.Remove(src)
    local u = Units.list[src]
    if not u then return end
    Units.list[src] = nil -- first, so auto-dispatch can't hand the call straight back
    if u.call then Calls.Unassign(u.call, src, { keepStatus = true, silent = true }) end
    Dispatch.Send('client:unitRemoved', src)
    TriggerEvent(Ev('onUnitRemoved'), src)
end

---------------------------------------------------------------------------
-- Role resolution: called on load, job change, duty change and resource start
---------------------------------------------------------------------------
local function matches(jobs, job)
    local minGrade = jobs[job.name]
    return minGrade ~= nil and (job.grade or 0) >= minGrade
end

function Units.Refresh(src)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return end

    local job = Bridge.GetJob(src)
    local isDispatcher, service = false, nil

    if job then
        local onDuty = job.onDuty ~= false
        if matches(Config.Dispatcher.jobs, job) and (onDuty or not Config.Dispatcher.requireDuty) then
            isDispatcher = true
        elseif onDuty then
            for id, s in pairs(Services) do
                if s.enabled and matches(s.jobs, job) then service = id break end
            end
        end
    end

    -- Dispatcher role
    if isDispatcher and not Dispatch.list[src] then
        Dispatch.list[src] = { name = Bridge.GetCharName(src) }
        Utils.Debug('dispatcher on', src)
    elseif not isDispatcher and Dispatch.list[src] then
        Dispatch.Leave(src)
    end

    -- Unit role
    local current = Units.list[src]
    if service then
        if not current or current.service ~= service then
            if current then
                Units.Remove(src)
                TriggerClientEvent(Ev('client:myCall'), src, nil)
            end
            local u = {
                src = src,
                service = service,
                name = Bridge.GetCharName(src),
                callsign = Callsigns.Get(src),
                status = 'available',
                call = nil,
                gradeLabel = job and job.gradeLabel,
            }
            Units.list[src] = u
            pushUnit(u)
            TriggerEvent(Ev('onUnitAdded'), src, service)
        elseif job then
            current.gradeLabel = job.gradeLabel
        end
    elseif current then
        Units.Remove(src)
    end

    TriggerClientEvent(Ev('client:role'), src, {
        dispatcher = isDispatcher,
        service = service,
    })
    if isDispatcher then Dispatch.SendState(src) end
    if service then
        local u = Units.list[src]
        TriggerClientEvent(Ev('client:unitStatus'), src, u.status, u.callsign)
        TriggerClientEvent(Ev('client:myCall'), src, u.call and Calls.Public(Calls.list[u.call]) or nil)
    end
end

--- Full snapshot for one dispatcher.
function Dispatch.SendState(src)
    local calls = {}
    for _, c in pairs(Calls.list) do calls[#calls + 1] = Calls.Public(c) end
    TriggerClientEvent(Ev('client:state'), src, {
        calls = calls, units = Units.All(), sms = Sms.Available(),
        aiCalls = AiCalls.Enabled(), canToggleAiCalls = AiCalls.CanToggle(src),
    })
end
