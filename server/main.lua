---------------------------------------------------------------------------
-- Startup / player lifecycle
---------------------------------------------------------------------------
CreateThread(function()
    Wait(1000)
    for _, id in ipairs(GetPlayers()) do Units.Refresh(tonumber(id)) end
end)

RegisterNetEvent(Ev('server:ready'), function()
    Units.Refresh(source)
end)

local callCooldown, alertCooldown = {}, {}

AddEventHandler('playerDropped', function()
    local src = source
    Dispatch.Leave(src)
    Units.Remove(src)
    callCooldown[src], alertCooldown[src] = nil, nil
end)

---------------------------------------------------------------------------
-- 112 calls from players
---------------------------------------------------------------------------
local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return Utils.Coords(GetEntityCoords(ped))
end

RegisterNetEvent(Ev('server:emergencyCall'), function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local cfg = Config.EmergencyCall
    local t = os.time()

    if callCooldown[src] and t - callCooldown[src] < cfg.cooldown then
        return Notify(src, 'caller.cooldown', { seconds = cfg.cooldown - (t - callCooldown[src]) }, 'error')
    end
    if Config.Phone.requirePhone and Phone.Active() then
        if not Phone.HasPhone(src) then return Notify(src, 'caller.no_phone', nil, 'error') end
    elseif cfg.requireItem and not Bridge.HasAnyItem(src, cfg.items) then
        return Notify(src, 'caller.no_phone', nil, 'error')
    end
    local message = Utils.Sanitize(data.message, cfg.maxLength)
    if not message or #message < cfg.minLength then
        return Notify(src, 'caller.too_short', nil, 'error')
    end
    callCooldown[src] = t
    Notify(src, 'caller.sent', nil, 'success')

    Calls.Create({
        service = data.service,
        type = data.type,
        message = message,
        coords = playerCoords(src),   -- server-side position, not trusted from client
        street = data.street,
        caller = { name = Bridge.GetCharName(src), phone = GetPhoneNumber(src) },
        origin = '112',
        callerSrc = src,
    }, { smsReceived = true })
end)

-- Automatic alerts from client scripts (exports['pessimi-dispatch']:CreateAlert)
RegisterNetEvent(Ev('server:clientAlert'), function(data)
    local src = source
    local cfg = Config.ClientAlerts
    if not cfg.enabled or type(data) ~= 'table' then return end
    local t = os.time()
    if alertCooldown[src] and t - alertCooldown[src] < cfg.cooldown then return end
    if not Calls.UnderLimit('alert', cfg.maxPerMinute or 30) then return end
    alertCooldown[src] = t

    Calls.Create({
        service = data.service,
        type = data.type,
        priority = data.priority,
        message = data.message,
        information = data.information,
        code = data.code,
        -- the player's game may lie: only accept a position near where they really are
        coords = Calls.TrustedCoords(src, data.coords, cfg.maxDistance),
        street = data.street,
        origin = 'alert',
    })
end)

---------------------------------------------------------------------------
-- Dispatcher actions from the panel
---------------------------------------------------------------------------
local actions = {
    assign = function(_, p) Calls.Assign(tonumber(p.callId), tonumber(p.unit)) end,
    unassign = function(_, p) Calls.Unassign(tonumber(p.callId), tonumber(p.unit), { byDispatcher = true }) end,
    update = function(_, p) Calls.Update(tonumber(p.callId), p.patch) end,
    note = function(src, p) Calls.AddNote(tonumber(p.callId), p.text, Dispatch.list[src].name) end,
    close = function(_, p) Calls.Close(tonumber(p.callId)) end,
    locate = function(src, p)
        if not Location.Locate(tonumber(p.callId)) then Notify(src, 'error.locate_unavailable', nil, 'error') end
    end,
    sendAi = function(src, p)
        local ok, why = Ai.Send(tonumber(p.callId))
        if not ok then
            Notify(src, why == 'players_on_duty' and 'error.ai_players_on_duty'
                or why == 'player_calls_only' and 'error.ai_player_calls_only' or 'error.ai_unavailable', nil, 'error')
        end
    end,
    sms = function(src, p)
        local call = Calls.Get(tonumber(p.callId))
        if not call or call.status == 'closed' then return end
        local key = type(p.key) == 'string' and Utils.Contains(Config.Sms.quickReplies, p.key) and ('sms.quick.' .. p.key) or nil
        local text = not key and Utils.Sanitize(p.text, Config.Sms.maxLength) or nil
        if not key and not text then return end
        if not Sms.ToCaller(call, text, key, { id = call.id }, Dispatch.list[src].name) then
            Notify(src, 'error.sms_failed', nil, 'error')
        end
    end,
    broadcast = function(_, p) Calls.Broadcast(tonumber(p.callId)) end,
    wait = function(src, p) Calls.Wait(tonumber(p.callId), Dispatch.list[src].name) end,
    unitStatus = function(_, p)
        local status = Utils.ResolveStatus(p.status)
        if status then Units.SetStatus(tonumber(p.unit), status) end
    end,
    createCall = function(src, p)
        if not Calls.Cooldown('create:' .. src, Config.Dispatcher.createCooldown or 3) then return end
        Calls.Create({
            service = p.service, type = p.type, priority = p.priority,
            message = p.message, coords = p.coords, street = p.street,
            origin = 'dispatcher', createdBy = Dispatch.list[src] and Dispatch.list[src].name,
        }, { skipFallback = true })
    end,
}

RegisterNetEvent(Ev('server:dispatcherAction'), function(kind, payload)
    local src = source
    if not Dispatch.list[src] then return end
    local fn = actions[kind]
    if fn and type(payload) == 'table' then fn(src, payload) end
end)

RegisterNetEvent(Ev('server:requestState'), function()
    local src = source
    if Dispatch.list[src] then Dispatch.SendState(src) end
end)

---------------------------------------------------------------------------
-- Unit actions
---------------------------------------------------------------------------
RegisterNetEvent(Ev('server:setStatus'), function(status)
    local src = source
    status = Utils.ResolveStatus(status)
    if Units.Get(src) and status then Units.SetStatus(src, status) end
end)

RegisterNetEvent(Ev('server:respond'), function(callId)
    local src = source
    if not Units.Get(src) then return Notify(src, 'error.not_unit', nil, 'error') end
    if Calls.Respond(tonumber(callId), src) then
        Notify(src, 'unit.responding', { id = callId }, 'success')
    else
        Notify(src, 'error.no_call', nil, 'error')
    end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function statusList()
    local ids = {}
    for _, s in ipairs(Config.UnitStatuses) do ids[#ids + 1] = s.id end
    return table.concat(ids, ', ')
end

RegisterCommand(Config.Units.statusCommand, function(src, args)
    if src == 0 then return end
    if not Units.Get(src) then return Notify(src, 'error.not_unit', nil, 'error') end
    local status = Utils.ResolveStatus(args[1])
    if not status then
        return Notify(src, 'error.invalid_status', { list = statusList() }, 'error')
    end
    Units.SetStatus(src, status)
    TriggerClientEvent(Ev('client:statusSet'), src, status)
end, false)

RegisterCommand(Config.Units.callsignCommand, function(src, args)
    if src == 0 then return end
    if not Units.Get(src) then return Notify(src, 'error.not_unit', nil, 'error') end
    local cs = Utils.Sanitize(table.concat(args, ' '), Config.Units.callsignMaxLength)
    Units.SetCallsign(src, cs)
    Notify(src, 'unit.callsign_set', { callsign = cs or '-' }, 'success')
end, false)

RegisterCommand(Config.Dispatcher.dutyCommand, function(src)
    if src == 0 then return end
    local job = Bridge.GetJob(src)
    if not job or Config.Dispatcher.jobs[job.name] == nil then
        return Notify(src, 'error.not_dispatcher_job', nil, 'error')
    end
    local goingOn = job.onDuty == false
    Bridge.SetDuty(src, goingOn)
    SetTimeout(300, function() Units.Refresh(src) end)
    Notify(src, goingOn and 'duty.on' or 'duty.off', nil, 'inform')
end, false)
