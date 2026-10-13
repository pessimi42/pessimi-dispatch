-- AI units: NPC responders for calls no player unit can take.
--
-- A player near the call ("host") spawns and drives the NPCs; the server decides
-- everything else (when to act, revive, leave). Without a host in range the unit
-- is "virtual": it arrives after a delay and does its job without visible NPCs.

Ai = { active = {}, nextId = 1 }

local cfg = Config.AiUnits

local function serviceCfg(service)
    if not cfg.enabled or not service or not Utils.ServiceEnabled(service) then return nil end
    local s = cfg.services[service]
    return (s and s.enabled) and s or nil
end

--- Service an AI unit would come from for this call, or nil.
function Ai.ServiceFor(call)
    local service = call.service or Config.Fallback.unspecifiedService
    return serviceCfg(service) and service or nil
end

function Ai.Count()
    local n = 0
    for _ in pairs(Ai.active) do n = n + 1 end
    return n
end

--- True if an AI unit is currently working this call.
function Ai.OnCall(callId)
    for _, a in pairs(Ai.active) do
        if a.callId == callId then return true end
    end
    return false
end

local function entry(a)
    local call = Calls.Get(a.callId)
    if not call or not call.ai then return nil, call end
    for _, e in ipairs(call.ai) do
        if e.id == a.id then return e, call end
    end
    return nil, call
end

local function setStatus(a, status)
    a.status = status
    local e, call = entry(a)
    if e then e.status = status end
    if call then Calls.Touch(call) end
end

local function note(a, key)
    Calls.AddNote(a.callId, key, 'AI', 'ai')
end

local function deleteEntities(a)
    for _, netId in ipairs(a.netIds or {}) do
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    a.netIds = {}
end

local function hostValid(src, coords)
    if not src or not GetPlayerName(src) then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return Utils.Distance2D(GetEntityCoords(ped), coords) <= cfg.hostRange
end

--- Caller first (they are at the scene), otherwise the nearest player in range.
local function pickHost(call)
    if hostValid(call._callerSrc, call.coords) then return call._callerSrc end
    local best, bestDist
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local d = Utils.Distance2D(GetEntityCoords(ped), call.coords)
            if d <= cfg.hostRange and (not bestDist or d < bestDist) then best, bestDist = src, d end
        end
    end
    return best
end

--- What the host client needs to spawn the unit.
local function payload(a, call)
    local s = cfg.services[a.service]
    return {
        callId = call.id,
        service = a.service,
        coords = call.coords,
        vehicle = s.vehicle,
        ped = s.ped,
        scenario = s.scenario,
        target = call._callerSrc,
        targetNetId = Scenes.PedNetId(call.id),
        spawnDistance = cfg.spawnDistance,
        driveTimeout = cfg.driveTimeout,
        arriveDistance = cfg.arriveDistance,
        drivingStyle = cfg.drivingStyle,
    }
end

--- Virtual travel: the unit "arrives" after virtualTravelSeconds unless a player has
--- taken it over in the meantime (the token changes then).
local function startVirtualTravel(a)
    local token = {}
    a.travelToken = token
    SetTimeout(cfg.virtualTravelSeconds * 1000, function()
        local cur = Ai.active[a.id]
        if cur and cur.travelToken == token and not cur.host then Ai.Arrived(a.id) end
    end)
end

--- Safety net: a unit that never reports arrival is moved on scene anyway.
local function startSafetyNet(a)
    local token = {}
    a.safetyToken = token
    SetTimeout((cfg.driveTimeout + 60) * 1000, function()
        local cur = Ai.active[a.id]
        if cur and cur.safetyToken == token and cur.status == 'enroute' then Ai.Arrived(a.id) end
    end)
end

---------------------------------------------------------------------------
-- Send
---------------------------------------------------------------------------
--- True if Config.AiUnits.trigger keeps AI away because players of `service` are on duty.
function Ai.PlayersOnDuty(service)
    return cfg.trigger == 'no_on_duty' and #Units.OnDutyIn(service) > 0
end

--- Returns the AI id, or nil and a reason
--- ('closed'|'no_coords'|'no_service'|'players_on_duty'|'busy'|'limit').
local function refuse(callId, why)
    Utils.Debug(('AI unit NOT sent to call #%s: %s'):format(tostring(callId), why))
    return nil, why
end

function Ai.Send(callId)
    local call = Calls.Get(callId)
    if not call or call.status == 'closed' then return refuse(callId, 'closed') end
    if not call.coords then return refuse(callId, 'no_coords') end
    local service = Ai.ServiceFor(call)
    if not service then return refuse(callId, 'no_service (service disabled in Config.AiUnits or services.lua)') end
    if Ai.PlayersOnDuty(service) then return refuse(callId, 'players_on_duty (' .. service .. ' units on duty, trigger = no_on_duty)') end
    if Ai.OnCall(call.id) then return refuse(callId, 'busy') end
    if Ai.Count() >= cfg.maxActive then return refuse(callId, 'limit') end

    local a = {
        id = Ai.nextId, callId = call.id, service = service, status = 'enroute',
        host = pickHost(call), netIds = {}, startedAt = os.time(),
    }
    Ai.nextId = Ai.nextId + 1
    Ai.active[a.id] = a

    call.ai = call.ai or {}
    call.ai[#call.ai + 1] = { id = a.id, service = service, status = 'enroute' }
    call.status = 'active'
    note(a, 'ai.note_sent')

    if Config.EmergencyCall.notifyCaller and not call._callerNotified then
        call._callerNotified = true
        Sms.AutoCaller(call, 'assigned', 'caller.units_assigned')
    end

    if a.host then
        Utils.Debug(('AI %s unit %d sent to call #%d, driven by player %d'):format(service, a.id, call.id, a.host))
        TriggerClientEvent(Ev('client:aiSpawn'), a.host, a.id, payload(a, call))
    else
        Utils.Debug(('AI %s unit %d sent to call #%d, virtual (no player within %dm)'):format(service, a.id, call.id, math.floor(cfg.hostRange)))
        startVirtualTravel(a)
    end
    startSafetyNet(a)

    TriggerEvent(Ev('onAiSent'), call.id, a.id, service)
    return a.id
end

---------------------------------------------------------------------------
-- On scene
---------------------------------------------------------------------------
local actions = {
    revive = function(a, call)
        local target = call._callerSrc
        if not target or not GetPlayerName(target) then return false end
        if cfg.reviveEvent then
            TriggerClientEvent(cfg.reviveEvent, target)
        else
            Bridge.Revive(target)
        end
        return true
    end,
    repair = function(a, call)
        local target = (call._callerSrc and GetPlayerName(call._callerSrc)) and call._callerSrc or a.host
        if not target then return false end
        TriggerClientEvent(Ev('client:aiRepair'), target, call.coords)
        return true
    end,
    extinguish = function(a, call)
        local target = a.host or ((call._callerSrc and GetPlayerName(call._callerSrc)) and call._callerSrc)
        if target then TriggerClientEvent(Ev('client:aiExtinguish'), target, call.coords, 40.0) end
        return true
    end,
    secure = function() return true end,
}

function Ai.Arrived(id)
    local a = Ai.active[id]
    if not a or a.status ~= 'enroute' then return end
    Utils.Debug(('AI unit %d on scene (call #%d)'):format(a.id, a.callId))
    setStatus(a, 'onscene')
    note(a, 'ai.note_arrived')
    local s = cfg.services[a.service]

    SetTimeout(s.actSeconds * 1000, function()
        local cur = Ai.active[id]
        local call = cur and Calls.Get(cur.callId)
        if not call or call.status == 'closed' then return end
        local act = actions[s.action] or actions.secure
        if act(cur, call) then note(cur, 'ai.note_' .. (actions[s.action] and s.action or 'secure')) end
        if call._ai then Scenes.Resolve(call.id, 'ai') end
    end)

    SetTimeout(s.onSceneSeconds * 1000, function() Ai.Finish(id) end)
end

--- The unit leaves. Closes the call if nobody else is working it.
function Ai.Finish(id, opts)
    opts = opts or {}
    local a = Ai.active[id]
    if not a then return end
    Ai.active[id] = nil
    setStatus(a, opts.failed and 'failed' or 'done')
    if not opts.silent then note(a, opts.failed and 'ai.note_failed' or 'ai.note_done') end

    Utils.Debug(('AI unit %d leaving call #%d'):format(a.id, a.callId))
    if a.host and GetPlayerName(a.host) then
        TriggerClientEvent(Ev('client:aiLeave'), a.host, a.id)
        -- Safety net: if the host could not drive them away (ownership moved to another
        -- player, ped stuck…), remove the vehicle and crew from the server.
        local s = cfg.services[a.service]
        local ids, models = a.netIds or {}, {}
        for _, list in ipairs({ s.vehicle, s.ped }) do
            for _, m in ipairs(type(list) == 'table' and list or { list }) do models[joaat(m)] = true end
        end
        SetTimeout(75000, function()
            for _, netId in ipairs(ids) do
                local ent = NetworkGetEntityFromNetworkId(netId)
                -- model check: a net id can be reused by another entity
                if ent and ent ~= 0 and DoesEntityExist(ent) and models[GetEntityModel(ent)] then
                    DeleteEntity(ent)
                end
            end
        end)
    else
        deleteEntities(a)
    end

    local call = Calls.Get(a.callId)
    if call and call.status ~= 'closed' and not opts.callClosing then
        if Calls.UnitCount(call) == 0 and not Ai.OnCall(call.id) then
            if cfg.closeWhenDone and not opts.failed then
                Calls.Close(call.id)
            else
                call.status = 'pending'
                Calls.Touch(call)
            end
        end
    end
end

--- Call closed by a dispatcher/unit: send its AI units home.
function Ai.CancelForCall(callId)
    for id, a in pairs(Ai.active) do
        if a.callId == callId then Ai.Finish(id, { callClosing = true, silent = true }) end
    end
end

---------------------------------------------------------------------------
-- Reports from the host client
---------------------------------------------------------------------------
RegisterNetEvent(Ev('server:aiSpawned'), function(id, netIds)
    local a = Ai.active[tonumber(id)]
    -- The unit finished while the client was still spawning it: send it straight home.
    if not a then return TriggerClientEvent(Ev('client:aiLeave'), source, tonumber(id)) end
    if a.host ~= source or type(netIds) ~= 'table' then return end
    a.netIds = {}
    for _, n in ipairs(netIds) do
        if tonumber(n) then a.netIds[#a.netIds + 1] = tonumber(n) end
    end
end)

RegisterNetEvent(Ev('server:aiArrived'), function(id)
    local a = Ai.active[tonumber(id)]
    if a and a.host == source then Ai.Arrived(a.id) end
end)

--- Host could not spawn (model missing, no road found): continue virtually.
RegisterNetEvent(Ev('server:aiSpawnFailed'), function(id)
    local a = Ai.active[tonumber(id)]
    if not a or a.host ~= source then return end
    a.host = nil
    a.noHostUntil = os.time() + 30   -- don't hand it straight back to the same player
    if a.status == 'enroute' then startVirtualTravel(a) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, a in pairs(Ai.active) do
        if a.host == src then
            a.host = nil
            deleteEntities(a)
            if a.status == 'enroute' then startVirtualTravel(a) end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, a in pairs(Ai.active) do deleteEntities(a) end
end)

---------------------------------------------------------------------------
-- Making virtual units visible
---------------------------------------------------------------------------
local function nearestPlayer(coords)
    local best, bestDist
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local d = Utils.Distance2D(GetEntityCoords(ped), coords)
            if d <= cfg.hostRange and (not bestDist or d < bestDist) then best, bestDist = src, d end
        end
    end
    return best
end

--- Hand virtual units to a player who has come near the call:
--- en route -> the NPCs spawn and drive in; on scene -> they appear at the scene.
function Ai.Watch()
    local now = os.time()
    for _, a in pairs(Ai.active) do
        if not a.host and (not a.noHostUntil or now >= a.noHostUntil) then
            local call = Calls.Get(a.callId)
            local enroute = a.status == 'enroute' and cfg.handOver
            local onscene = a.status == 'onscene' and cfg.visibleOnScene
            if call and call.coords and call.status ~= 'closed' and (enroute or onscene) then
                local src = nearestPlayer(call.coords)
                if src then
                    a.host = src
                    a.travelToken = nil
                    if enroute then
                        TriggerClientEvent(Ev('client:aiSpawn'), src, a.id, payload(a, call))
                        startSafetyNet(a)
                    else
                        TriggerClientEvent(Ev('client:aiSpawnOnScene'), src, a.id, payload(a, call))
                    end
                    Utils.Debug(('AI unit %d handed to player %d (%s)'):format(a.id, src, a.status))
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(cfg.watchInterval * 1000)
        if cfg.enabled and (cfg.handOver or cfg.visibleOnScene) then Ai.Watch() end
    end
end)

---------------------------------------------------------------------------
-- Automatic dispatch
---------------------------------------------------------------------------
--- Called when a call could not be given to a player unit. Sends AI after waitSeconds
--- if the call is still unattended.
function Ai.Schedule(callId)
    if not cfg.enabled or not cfg.auto then return end
    Utils.Debug(('call #%d: AI unit in %d s if still unattended'):format(callId, cfg.waitSeconds))
    SetTimeout(cfg.waitSeconds * 1000, function()
        local call = Calls.Get(callId)
        if not call or call.status == 'closed' or call.status == 'active' then return end
        if Calls.UnitCount(call) > 0 or Ai.OnCall(call.id) then return end
        if Dispatch.HasDispatcher() and not cfg.autoWithDispatcher then return end
        if not Ai.ServiceFor(call) then return end
        local ok, why = Ai.Send(call.id)
        if not ok and why ~= 'busy' and why ~= 'closed' then
            local key = why:find('^players_on_duty') and 'ai.note_not_sent_players'
                or why == 'limit' and 'ai.note_not_sent_limit' or 'ai.note_not_sent'
            Calls.AddNote(call.id, key, nil, 'sys')
        end
    end)
end
