-- AI units, client side. Runs only on the "host" player the server picked:
-- spawns the vehicle and crew, drives to the call with sirens, plays a scenario
-- on scene and leaves when the server says so.

local units = {}      -- [aiId] = { veh, ped }
local cancelled = {}  -- [aiId] = true: the server sent it home before the spawn finished

local function debug(...)
    if Config.Debug then print('^5[' .. GetCurrentResourceName() .. ']^7', ...) end
end

local function loadModel(name)
    local hash = type(name) == 'number' and name or joaat(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > t then return nil end
        Wait(50)
    end
    return hash
end

local function asList(v) return type(v) == 'table' and v or { v } end

local function v3(c) return vector3(c.x, c.y, c.z) end

local function control(ent)
    if not DoesEntityExist(ent) then return false end
    if NetworkHasControlOfEntity(ent) then return true end
    NetworkRequestControlOfEntity(ent)
    local t = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do
        Wait(50)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

local function delete(ent)
    if ent and DoesEntityExist(ent) and control(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

--- Waits a moment and checks the entity is still there. Servers that blacklist models
--- (e.g. smallresources deleting cop peds) remove them right after creation.
local function survives(ent)
    if not ent or ent == 0 then return false end
    local t = GetGameTimer() + 1000
    while GetGameTimer() < t do
        if not DoesEntityExist(ent) then return false end
        Wait(100)
    end
    return DoesEntityExist(ent)
end

--- Create a vehicle from the first model in `models` that spawns and stays.
local function createVehicle(models, pos, heading)
    for _, model in ipairs(asList(models)) do
        local hash = loadModel(model)
        if hash then
            local veh = CreateVehicle(hash, pos.x, pos.y, pos.z, heading, true, false)
            SetModelAsNoLongerNeeded(hash)
            if survives(veh) then return veh end
            debug(('AI vehicle %s was removed right after spawning (blacklisted?), trying the next one'):format(model))
        else
            debug(('AI vehicle model %s not found'):format(model))
        end
    end
    return nil
end

--- Create the crew ped (inside `veh`, or at `pos`) from the first model that stays.
local function createPed(models, veh, pos, heading)
    for _, model in ipairs(asList(models)) do
        local hash = loadModel(model)
        if hash then
            local ped = veh and CreatePedInsideVehicle(veh, 4, hash, -1, true, false)
                or CreatePed(4, hash, pos.x, pos.y, pos.z, heading or 0.0, true, false)
            SetModelAsNoLongerNeeded(hash)
            if survives(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedKeepTask(ped, true)
                SetPedCanBeDraggedOut(ped, false)
                SetPedFleeAttributes(ped, 0, false)
                return ped
            end
            debug(('AI ped %s was removed right after spawning (blacklisted?), trying the next one'):format(model))
        else
            debug(('AI ped model %s not found'):format(model))
        end
    end
    return nil
end

--- A road node between min and max metres from the target.
local function findSpawn(target, minD, maxD)
    for _ = 1, 20 do
        local a = math.random() * 2.0 * math.pi
        local d = minD + math.random() * (maxD - minD)
        local x, y = target.x + math.cos(a) * d, target.y + math.sin(a) * d
        local found, pos, heading = GetClosestVehicleNodeWithHeading(x, y, target.z, 1, 3.0, 0)
        if found and #(pos - target) >= minD * 0.6 then return pos, heading end
    end
    local found, pos, heading = GetClosestVehicleNodeWithHeading(target.x, target.y, target.z, 1, 3.0, 0)
    if found then return pos, heading end
    return nil
end

--- Where the crew should walk: the scene's patient/witness (looked up now, because the
--- scene often spawns after the unit was sent), the caller, or the call location.
local function workGoal(d, target)
    local npc = DispatchScenePed and DispatchScenePed(d.callId) or 0
    if npc == 0 and d.targetNetId and NetworkDoesNetworkIdExist(d.targetNetId) then
        npc = NetworkGetEntityFromNetworkId(d.targetNetId)
    end
    if npc ~= 0 and DoesEntityExist(npc) then return GetEntityCoords(npc), npc end
    if d.target then
        local player = GetPlayerFromServerId(d.target)
        local tped = player ~= -1 and GetPlayerPed(player) or 0
        if tped ~= 0 and #(GetEntityCoords(tped) - target) < 60.0 then return GetEntityCoords(tped), tped end
    end
    return target, nil
end

local function cleanup(id)
    local u = units[id]
    units[id] = nil
    if not u then return end
    delete(u.ped)
    delete(u.veh)
end

--- Spawned fine: register, or drop it straight away if the server already sent it home.
local function register(id, veh, ped)
    units[id] = { veh = veh, ped = ped }
    if cancelled[id] then
        cancelled[id] = nil
        cleanup(id)
        return false
    end
    TriggerServerEvent(Ev('server:aiSpawned'), id, {
        NetworkGetNetworkIdFromEntity(veh), NetworkGetNetworkIdFromEntity(ped),
    })
    return true
end

local function fail(id, why, veh, ped)
    debug(('AI unit %d could not spawn: %s'):format(id, why))
    delete(ped)
    delete(veh)
    units[id] = nil
    TriggerServerEvent(Ev('server:aiSpawnFailed'), id)
end

RegisterNetEvent(Ev('client:aiSpawn'), function(id, d)
    CreateThread(function()
        local target = v3(d.coords)
        local pos, heading = findSpawn(target, d.spawnDistance[1], d.spawnDistance[2])
        if not pos then return fail(id, 'no road found near the call') end

        local veh = createVehicle(d.vehicle, pos, heading)
        if not veh then return fail(id, 'no vehicle model could be spawned') end
        SetVehicleOnGroundProperly(veh)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleEngineOn(veh, true, true, false)
        SetVehicleSiren(veh, true)
        SetVehicleHasMutedSirens(veh, false)

        local ped = createPed(d.ped, veh)
        if not ped then return fail(id, 'no crew model could be spawned', veh) end
        if not register(id, veh, ped) then return end
        debug(('AI unit %d spawned %.0fm from the call'):format(id, #(pos - target)))

        TaskVehicleDriveToCoordLongrange(ped, veh, target.x, target.y, target.z, 28.0, d.drivingStyle, d.arriveDistance * 0.5)

        -- Drive until close, or move the vehicle nearby if it takes too long
        local deadline = GetGameTimer() + d.driveTimeout * 1000
        while units[id] do
            if not DoesEntityExist(veh) or not DoesEntityExist(ped) then
                return fail(id, 'vehicle or crew was removed while driving', veh, ped)
            end
            if #(GetEntityCoords(veh) - target) <= d.arriveDistance then break end
            if GetGameTimer() > deadline then
                local found, near, h = GetClosestVehicleNodeWithHeading(target.x + 15.0, target.y + 15.0, target.z, 1, 3.0, 0)
                if found then
                    SetEntityCoords(veh, near.x, near.y, near.z, false, false, false, false)
                    SetEntityHeading(veh, h)
                end
                break
            end
            Wait(1000)
        end
        if not units[id] then return end

        -- On scene: stop, get out, walk to the patient/scene and work
        TaskVehicleTempAction(ped, veh, 27, 3000)
        SetVehicleHasMutedSirens(veh, true)   -- lights stay on, siren off
        Wait(1500)
        TaskLeaveVehicle(ped, veh, 256)
        Wait(2500)

        local goal, npc = workGoal(d, target)
        TaskGoStraightToCoord(ped, goal.x, goal.y, goal.z, 2.0, 20000, 0.0, 1.5)
        local walkUntil = GetGameTimer() + 20000
        while units[id] and DoesEntityExist(ped) and #(GetEntityCoords(ped) - goal) > 2.5 and GetGameTimer() < walkUntil do
            Wait(500)
        end
        if not units[id] then return end
        if npc then TaskTurnPedToFaceEntity(ped, npc, 1000) Wait(1000) end
        if d.scenario then TaskStartScenarioInPlace(ped, d.scenario, 0, true) end

        TriggerServerEvent(Ev('server:aiArrived'), id)
    end)
end)

-- A unit that is already working at the scene (it arrived while nobody was near):
-- park the vehicle with lights on and put the crew to work next to the patient/scene.
RegisterNetEvent(Ev('client:aiSpawnOnScene'), function(id, d)
    CreateThread(function()
        local target = v3(d.coords)
        local found, pos, heading = GetClosestVehicleNodeWithHeading(target.x, target.y, target.z, 1, 3.0, 0)
        if not found then return fail(id, 'no road found near the call') end

        local veh = createVehicle(d.vehicle, pos, heading)
        if not veh then return fail(id, 'no vehicle model could be spawned') end
        SetVehicleOnGroundProperly(veh)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleSiren(veh, true)
        SetVehicleHasMutedSirens(veh, true)

        local goal, npc = workGoal(d, target)
        local gx, gy = goal.x + 1.2, goal.y + 1.2
        local ok, gz = GetGroundZFor_3dCoord(gx, gy, goal.z + 2.0, false)
        local ped = createPed(d.ped, nil, vector3(gx, gy, ok and gz or goal.z), 0.0)
        if not ped then return fail(id, 'no crew model could be spawned', veh) end
        if not register(id, veh, ped) then return end

        if npc then TaskTurnPedToFaceEntity(ped, npc, 1000) else TaskTurnPedToFaceCoord(ped, goal.x, goal.y, goal.z, 1000) end
        Wait(1000)
        if d.scenario and DoesEntityExist(ped) then TaskStartScenarioInPlace(ped, d.scenario, 0, true) end
    end)
end)

RegisterNetEvent(Ev('client:aiLeave'), function(id)
    local u = units[id]
    if not u then
        cancelled[id] = true   -- still spawning: it is removed as soon as it exists
        SetTimeout(30000, function() cancelled[id] = nil end)
        return
    end
    units[id] = nil   -- stops the drive/walk threads
    CreateThread(function()
        local ped, veh = u.ped, u.veh
        if DoesEntityExist(ped) and DoesEntityExist(veh) and control(ped) and control(veh) then
            -- Scenarios (kneeling medic) ignore a soft ClearPedTasks
            ClearPedTasksImmediately(ped)
            SetVehicleSiren(veh, false)
            if not IsPedInVehicle(ped, veh, false) then
                TaskEnterVehicle(ped, veh, 10000, -1, 2.0, 1, 0)
                local t = GetGameTimer() + 10000
                while GetGameTimer() < t and DoesEntityExist(ped) and not IsPedInVehicle(ped, veh, false) do Wait(500) end
                if DoesEntityExist(ped) and not IsPedInVehicle(ped, veh, false) then
                    SetPedIntoVehicle(ped, veh, -1)   -- stuck: warp in
                end
            end
            TaskVehicleDriveWander(ped, veh, 15.0, 786603)
            SetPedKeepTask(ped, true)
            -- Drive off; delete once out of sight or after 40 s
            local t = GetGameTimer() + 40000
            while GetGameTimer() < t and DoesEntityExist(veh) do
                if #(GetEntityCoords(veh) - GetEntityCoords(PlayerPedId())) > 120.0 then break end
                Wait(1000)
            end
        end
        delete(ped)
        delete(veh)
    end)
end)

-- Mechanic: fix the vehicle closest to the scene
RegisterNetEvent(Ev('client:aiRepair'), function(coords)
    local target, best = v3(coords), nil
    local bestDist = 15.0
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local dist = #(GetEntityCoords(veh) - target)
        if dist < bestDist then best, bestDist = veh, dist end
    end
    if not best then return end
    control(best)
    SetVehicleFixed(best)
    SetVehicleDeformationFixed(best)
    SetVehicleEngineHealth(best, 1000.0)
    SetVehicleBodyHealth(best, 1000.0)
    SetVehicleUndriveable(best, false)
end)

-- Fire: put out fires around the scene
RegisterNetEvent(Ev('client:aiExtinguish'), function(coords, radius)
    StopFireInRange(coords.x, coords.y, coords.z, radius or 40.0)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(units) do cleanup(id) end
end)
