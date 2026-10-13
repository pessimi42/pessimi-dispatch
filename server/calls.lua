-- Call lifecycle: pending -> broadcast -> active -> closed

Calls = { list = {}, nextId = 1 }

local CALL_STATUSES = { pending = true, broadcast = true, active = true, closed = true }

local function now() return os.time() end

--- Copy without server-only fields (prefixed with _); unit set becomes an array.
function Calls.Public(call)
    if not call then return nil end
    local out = {}
    for k, v in pairs(call) do
        if type(k) ~= 'string' or k:sub(1, 1) ~= '_' then out[k] = v end
    end
    local units = {}
    for src in pairs(call._units) do units[#units + 1] = src end
    out.units = units
    out.canSms = call.status ~= 'closed' and Sms.CallerNumber(call) ~= nil and Sms.Available()
    return out
end

function Calls.Get(id) return Calls.list[tonumber(id)] end

local function unitCount(call)
    local n = 0
    for _ in pairs(call._units) do n = n + 1 end
    return n
end

--- Push a change to dispatchers, to units on the call and to listening resources.
local function changed(call, kind)
    call.updatedAt = now()
    local pub = Calls.Public(call)
    Dispatch.Send('client:callChanged', pub, kind)
    if call.status ~= 'closed' then
        for src in pairs(call._units) do
            TriggerClientEvent(Ev('client:myCall'), src, pub)
        end
    end
    local event = ({ created = 'onCallCreated', closed = 'onCallClosed' })[kind] or 'onCallUpdated'
    TriggerEvent(Ev(event), pub)
end

--- Keep only the newest Config.Calls.keepClosed closed calls.
local function prune()
    local closed = {}
    for id, c in pairs(Calls.list) do
        if c.status == 'closed' then closed[#closed + 1] = id end
    end
    table.sort(closed)
    for i = 1, #closed - Config.Calls.keepClosed do
        Calls.list[closed[i]] = nil
    end
end

---------------------------------------------------------------------------
-- Create
---------------------------------------------------------------------------
--[[ data:
    service, type, priority, message, information, code, coords, street,
    caller = { name, phone }, origin ('112'|'dispatcher'|'alert'|'api'|<integration>),
    callerSrc (server only), meta (any table)
  opts:
    skipFallback  don't auto-dispatch when no dispatcher is on duty
    smsReceived   text the caller "your call has been received" (if a phone is running)
]]
function Calls.Create(data, opts)
    opts = opts or {}
    local service = Utils.ServiceEnabled(data.service) and data.service or nil
    local svc = service and Services[service]

    local id = Calls.nextId
    Calls.nextId = id + 1

    local call = {
        id = id,
        service = service,
        type = Utils.ValidCallType(service, data.type) or 'general',
        priority = Utils.ValidPriority(data.priority) or (svc and svc.defaultPriority) or Config.DefaultPriority,
        status = 'pending',
        message = Utils.Sanitize(data.message, Config.EmergencyCall.maxLength) or '',
        information = Utils.Sanitize(data.information, 500),
        code = Utils.Sanitize(data.code, 16),
        coords = Utils.Coords(data.coords),
        street = Utils.Sanitize(data.street, 120),
        caller = type(data.caller) == 'table' and {
            name = Utils.Sanitize(data.caller.name, 60),
            phone = Utils.Sanitize(data.caller.phone, 30),
        } or nil,
        origin = Utils.Sanitize(data.origin, 32) or 'api',
        createdAt = now(),
        updatedAt = now(),
        notes = {},
        meta = type(data.meta) == 'table' and data.meta or nil,
        _units = {},
        _callerSrc = data.callerSrc,
    }

    Calls.list[id] = call
    changed(call, 'created')

    if opts.smsReceived then Sms.AutoCaller(call, 'received') end

    if not opts.skipFallback and not Dispatch.HasDispatcher() then
        Calls.AutoDispatch(id)
    end
    return id
end

---------------------------------------------------------------------------
-- Auto-dispatch when no dispatcher is on duty
---------------------------------------------------------------------------
--- Nearest unit of `service` whose status is 'available'. Positions are read
--- server-side only at the moment of the call; nothing is tracked or shown.
function Calls.FindNearestUnit(coords, service)
    if not coords then return nil end
    local maxDist = Config.Fallback.maxDistance or 0
    local best, bestDist
    for src, u in pairs(Units.list) do
        if u.status == 'available' and not u.call and (service == nil or u.service == service) then
            local ped = GetPlayerPed(src)
            if ped and ped ~= 0 then
                local d = Utils.Distance2D(GetEntityCoords(ped), coords)
                if (maxDist <= 0 or d <= maxDist) and (not bestDist or d < bestDist) then
                    best, bestDist = src, d
                end
            end
        end
    end
    return best, bestDist
end

function Calls.AutoDispatch(id)
    local call = Calls.Get(id)
    if not call then return false end
    local mode = Config.Fallback.mode

    if mode == 'nearest' then
        local service = call.service
        if not service and Utils.ServiceEnabled(Config.Fallback.unspecifiedService) then
            service = Config.Fallback.unspecifiedService
        end
        local src = Calls.FindNearestUnit(call.coords, service)
        if src then
            Utils.Debug(('auto-assigned call #%d to %d'):format(id, src))
            return Calls.Assign(id, src)
        end
        if Config.Fallback.broadcastIfNoUnit then return Calls.Broadcast(id) end
        return false
    elseif mode == 'broadcast' then
        return Calls.Broadcast(id)
    end
    return false
end

---------------------------------------------------------------------------
-- Update fields (dispatcher or API)
---------------------------------------------------------------------------
function Calls.Update(id, patch)
    local call = Calls.Get(id)
    if not call or call.status == 'closed' or type(patch) ~= 'table' then return false end

    if patch.service ~= nil then
        if patch.service == false or patch.service == '' then
            call.service = nil
        elseif Utils.ServiceEnabled(patch.service) then
            call.service = patch.service
            if not Utils.ValidCallType(call.service, call.type) then call.type = 'general' end
        end
    end
    if patch.type and Utils.ValidCallType(call.service, patch.type) then call.type = patch.type end
    if patch.priority and Utils.ValidPriority(patch.priority) then call.priority = patch.priority end
    if patch.message then call.message = Utils.Sanitize(patch.message, Config.EmergencyCall.maxLength) or call.message end
    if patch.information then call.information = Utils.Sanitize(patch.information, 500) end
    if patch.code then call.code = Utils.Sanitize(patch.code, 16) end
    if patch.coords then call.coords = Utils.Coords(patch.coords) or call.coords end
    if patch.street then call.street = Utils.Sanitize(patch.street, 120) end
    if patch.status and CALL_STATUSES[patch.status] and patch.status ~= 'closed' then call.status = patch.status end

    changed(call, 'updated')
    return true
end

--- kind: nil (note) | 'sms_out' (sent to caller) | 'sms_in' (text from caller)
function Calls.AddNote(id, text, author, kind)
    local call = Calls.Get(id)
    text = Utils.Sanitize(text, 300)
    if not call or not text then return false end
    call.notes[#call.notes + 1] = { text = text, author = Utils.Sanitize(author, 60), at = now(), kind = kind }
    changed(call, 'updated')
    return true
end

---------------------------------------------------------------------------
-- Units on calls
---------------------------------------------------------------------------
--- Dispatcher-assigned (or self-attached via Calls.Respond).
function Calls.Assign(id, unitSrc)
    local call, unit = Calls.Get(id), Units.Get(unitSrc)
    if not call or call.status == 'closed' or not unit then return false end
    unitSrc = unit.src
    if call._units[unitSrc] then return true end

    if unit.call and unit.call ~= call.id then
        Calls.Unassign(unit.call, unitSrc, { keepStatus = true })
    end

    call._units[unitSrc] = true
    call.status = 'active'
    unit.call = call.id
    Units.SetStatus(unitSrc, 'enroute', true)
    -- SetStatus only pushes on change; make sure the dispatcher sees the new call link
    Dispatch.Send('client:unitChanged', Units.Public(unit))

    changed(call, 'updated')
    Adapters.Assign(call, { unitSrc })
    TriggerEvent(Ev('onUnitAssigned'), call.id, unitSrc)

    Sms.ToUnit(unitSrc, call)
    if Config.EmergencyCall.notifyCaller and not call._callerNotified then
        call._callerNotified = true
        Sms.AutoCaller(call, 'assigned', 'caller.units_assigned')
    end
    return true
end

--[[ opts.keepStatus  don't reset the unit to available (it is changing status itself)
     opts.silent      unit is leaving the server; don't message it ]]
function Calls.Unassign(id, unitSrc, opts)
    opts = opts or {}
    local call = Calls.Get(id)
    unitSrc = tonumber(unitSrc)
    if not call or not call._units[unitSrc] then return false end

    call._units[unitSrc] = nil
    local unit = Units.Get(unitSrc)
    if unit and unit.call == call.id then
        unit.call = nil
        if not opts.keepStatus then Units.SetStatus(unitSrc, 'available', true) end
        Dispatch.Send('client:unitChanged', Units.Public(unit))
    end
    if not opts.silent then
        TriggerClientEvent(Ev('client:myCall'), unitSrc, nil)
        -- keepStatus = the unit cleared itself or moved to another call; no need to tell it
        if not opts.keepStatus then Notify(unitSrc, 'unit.unassigned', { id = call.id }, 'inform') end
    end

    TriggerEvent(Ev('onUnitUnassigned'), call.id, unitSrc)

    if call.status == 'active' and unitCount(call) == 0 then
        if not Dispatch.HasDispatcher() and not opts.byDispatcher then
            -- Nobody can manage the queue: a unit clearing means the job is done,
            -- a unit disconnecting means someone else should take it.
            if opts.silent then
                call.status = 'pending'
                changed(call, 'updated')
                return Calls.AutoDispatch(call.id) or true
            elseif Config.Fallback.closeWhenUnitsDone then
                return Calls.Close(call.id) or true
            end
        end
        call.status = call._broadcast and 'broadcast' or 'pending'
    end
    changed(call, 'updated')
    return true
end

--- Alert every on-duty unit of the call's service (all services if unspecified).
function Calls.Broadcast(id)
    local call = Calls.Get(id)
    if not call or call.status == 'closed' then return false end
    local targets = Units.OnDutyIn(call.service)
    call._broadcast = true
    if call.status == 'pending' then call.status = 'broadcast' end
    changed(call, 'updated')
    if #targets > 0 then Adapters.Broadcast(call, targets) end
    return true
end

--- A unit attaches itself to a broadcast call.
function Calls.Respond(id, unitSrc)
    local call, unit = Calls.Get(id), Units.Get(unitSrc)
    if not call or call.status == 'closed' or not unit then return false end
    if not call._broadcast and call.status ~= 'active' then return false end
    if call.service and unit.service ~= call.service and not Config.Units.allowCrossService then
        return false
    end
    return Calls.Assign(id, unitSrc)
end

function Calls.Close(id)
    local call = Calls.Get(id)
    if not call or call.status == 'closed' then return false end
    Sms.AutoCaller(call, 'closed')
    call.status = 'closed'
    call.closedAt = now()
    for src in pairs(call._units) do
        local unit = Units.Get(src)
        if unit and unit.call == call.id then
            unit.call = nil
            Units.SetStatus(src, 'available', true)
            Dispatch.Send('client:unitChanged', Units.Public(unit))
        end
        TriggerClientEvent(Ev('client:myCall'), src, nil)
        Notify(src, 'unit.call_closed', { id = call.id }, 'inform')
    end
    changed(call, 'closed')
    prune()
    return true
end

---------------------------------------------------------------------------
-- Housekeeping: close stale calls nobody is working
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(60000)
        local limit = (Config.Calls.autoCloseMinutes or 0) * 60
        if limit > 0 then
            local t = now()
            for id, c in pairs(Calls.list) do
                if c.status ~= 'closed' and unitCount(c) == 0 and t - c.updatedAt > limit then
                    Calls.Close(id)
                end
            end
        end
    end
end)
