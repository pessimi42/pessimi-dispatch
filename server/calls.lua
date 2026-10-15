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
    out.canSms = call.status ~= 'closed' and Sms.CallerNumber(call) ~= nil and (call._ai or Sms.Available())
    out.tracking = Location.Tracking(call)
    local aiService = call.service or Config.Fallback.unspecifiedService
    out.aiBlocked = Ai.BlockedForCall(call, aiService) or Ai.PlayersOnDuty(aiService) or nil
    out.canLocate = Config.Location.locateButton and Location.CanLocate(call)
    return out
end

function Calls.Get(id) return Calls.list[tonumber(id)] end

local function unitCount(call)
    local n = 0
    for _ in pairs(call._units) do n = n + 1 end
    return n
end
Calls.UnitCount = unitCount

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

--- Push a change made outside this file (e.g. NPC units).
function Calls.Touch(call) changed(call, 'updated') end

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
-- Guards for what players' games send (they can send anything)
---------------------------------------------------------------------------
local lastHit, windows = {}, {}

--- false if `key` was let through less than `seconds` ago (per-player cooldowns).
function Calls.Cooldown(key, seconds)
    local t = now()
    if lastHit[key] and t - lastHit[key] < (seconds or 0) then return false end
    lastHit[key] = t
    return true
end

--- false once `max` events of this kind have been let through in the last minute,
--- counting every player together (stops a flood from many accounts).
function Calls.UnderLimit(bucket, max)
    if not max or max <= 0 then return true end
    local t, w = now(), windows[bucket] or {}
    local keep = {}
    for _, at in ipairs(w) do if t - at < 60 then keep[#keep + 1] = at end end
    if #keep >= max then windows[bucket] = keep return false end
    keep[#keep + 1] = t
    windows[bucket] = keep
    return true
end

--- Coordinates a player's game reported, accepted only near where the server sees that
--- player; otherwise the player's real position.
function Calls.TrustedCoords(src, claimed, maxDistance)
    local ped = src and src > 0 and GetPlayerPed(src)
    local real = ped and ped ~= 0 and Utils.Coords(GetEntityCoords(ped)) or nil
    claimed = Utils.Coords(claimed)
    if claimed and real and Utils.Distance2D(real, claimed) <= (maxDistance or 150.0) then return claimed end
    if claimed and real then
        Utils.Debug(('player %d reported coords %.0f m away, using their position'):format(src, Utils.Distance2D(real, claimed)))
    end
    return real
end

AddEventHandler('playerDropped', function()
    local src = source
    for key in pairs(lastHit) do
        if type(key) == 'string' and key:match(':' .. src .. '$') then lastHit[key] = nil end
    end
end)

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
    ai            generated AI call (no real caller; texts are not sent to a phone)
]]
function Calls.Create(data, opts)
    opts = opts or {}
    local service = Utils.ServiceEnabled(data.service) and data.service or nil
    local svc = service and Services[service]

    local id = Calls.nextId
    Calls.nextId = id + 1
    local ctype = Utils.ValidCallType(service, data.type) or 'general'

    local call = {
        id = id,
        service = service,
        type = ctype,
        priority = Utils.ClampPriority(service, Utils.ValidPriority(data.priority)
            or Utils.TypePriority(service, ctype) or (svc and svc.defaultPriority) or Config.DefaultPriority),
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
        _ai = opts.ai == true,
        aiCall = (opts.ai == true and Config.AiCalls.showBadge) or nil,
    }

    Calls.list[id] = call
    changed(call, 'created')
    if not call._ai and (call.origin == '112' or call.origin == 'sms') then AiCalls.NotePlayerCall() end

    if opts.smsReceived then Sms.AutoCaller(call, 'received') end

    if not opts.skipFallback and not Dispatch.HasDispatcher() then
        Calls.AutoDispatch(id)
    elseif not opts.skipFallback and Config.AiUnits.autoWithDispatcher then
        Ai.Schedule(id)   -- dispatcher on duty: AI only if they leave the call unattended
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
        Ai.Schedule(id)
        if Config.Fallback.broadcastIfNoUnit then return Calls.Broadcast(id) end
        return false
    elseif mode == 'broadcast' then
        Ai.Schedule(id)
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
    if patch.type and Utils.ValidCallType(call.service, patch.type) and patch.type ~= call.type then
        call.type = patch.type
        -- a new task class brings its default urgency, unless one was chosen in the same change
        if not patch.priority then call.priority = Utils.TypePriority(call.service, call.type) or call.priority end
    end
    if patch.priority and Utils.ValidPriority(patch.priority) then call.priority = patch.priority end
    call.priority = Utils.ClampPriority(call.service, call.priority)
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
    local max = Config.Calls.maxNotes or 100
    while #call.notes >= max do table.remove(call.notes, 1) end    -- oldest go first
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

    if call.status == 'active' and unitCount(call) == 0 and not Ai.OnCall(call.id) then
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
    Ai.CancelForCall(call.id)
    Scenes.Clear(call.id)
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
                if c.status ~= 'closed' and unitCount(c) == 0 and not Ai.OnCall(id) and t - c.updatedAt > limit then
                    Calls.Close(id)
                end
            end
        end
    end
end)
