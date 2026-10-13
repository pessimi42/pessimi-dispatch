-- AI units, client side. Runs only on the "host" player the server picked:
-- spawns the vehicle and crew, drives to the call with sirens, plays a scenario
-- on scene and leaves when the server says so.

local units = {}   -- [aiId] = { veh, ped }

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

local function v3(c) return vector3(c.x, c.y, c.z) end

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

local function cleanup(id)
    local u = units[id]
    if not u then return end
    if DoesEntityExist(u.ped) then DeleteEntity(u.ped) end
    if DoesEntityExist(u.veh) then DeleteEntity(u.veh) end
    units[id] = nil
end

RegisterNetEvent(Ev('client:aiSpawn'), function(id, d)
    CreateThread(function()
        local target = v3(d.coords)
        local vehHash, pedHash = loadModel(d.vehicle), loadModel(d.ped)
        local pos, heading = findSpawn(target, d.spawnDistance[1], d.spawnDistance[2])
        if not vehHash or not pedHash or not pos then
            return TriggerServerEvent(Ev('server:aiSpawnFailed'), id)
        end

        local veh = CreateVehicle(vehHash, pos.x, pos.y, pos.z, heading, true, false)
        local t = GetGameTimer() + 3000
        while not DoesEntityExist(veh) and GetGameTimer() < t do Wait(0) end
        if not DoesEntityExist(veh) then return TriggerServerEvent(Ev('server:aiSpawnFailed'), id) end
        SetVehicleOnGroundProperly(veh)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleEngineOn(veh, true, true, false)
        SetVehicleSiren(veh, true)
        SetVehicleHasMutedSirens(veh, false)

        local ped = CreatePedInsideVehicle(veh, 4, pedHash, -1, true, false)
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedKeepTask(ped, true)
        SetPedCanBeDraggedOut(ped, false)
        SetModelAsNoLongerNeeded(vehHash)
        SetModelAsNoLongerNeeded(pedHash)

        units[id] = { veh = veh, ped = ped }
        TriggerServerEvent(Ev('server:aiSpawned'), id, {
            NetworkGetNetworkIdFromEntity(veh), NetworkGetNetworkIdFromEntity(ped),
        })

        TaskVehicleDriveToCoordLongrange(ped, veh, target.x, target.y, target.z, 28.0, d.drivingStyle, d.arriveDistance * 0.5)

        -- Drive until close, or move the vehicle nearby if it takes too long
        local deadline = GetGameTimer() + d.driveTimeout * 1000
        while units[id] do
            if not DoesEntityExist(veh) or not DoesEntityExist(ped) then
                cleanup(id)
                return TriggerServerEvent(Ev('server:aiSpawnFailed'), id)
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
        Wait(1500)
        TaskLeaveVehicle(ped, veh, 256)
        Wait(2500)

        local goal = target
        if d.targetNetId and NetworkDoesNetworkIdExist(d.targetNetId) then
            local npc = NetworkGetEntityFromNetworkId(d.targetNetId)    -- scene patient / caller
            if npc ~= 0 and DoesEntityExist(npc) then goal = GetEntityCoords(npc) end
        elseif d.target then
            local player = GetPlayerFromServerId(d.target)
            local tped = player ~= -1 and GetPlayerPed(player) or 0
            if tped ~= 0 and #(GetEntityCoords(tped) - target) < 60.0 then goal = GetEntityCoords(tped) end
        end
        TaskGoStraightToCoord(ped, goal.x, goal.y, goal.z, 2.0, 20000, 0.0, 1.5)
        local walkUntil = GetGameTimer() + 20000
        while units[id] and DoesEntityExist(ped) and #(GetEntityCoords(ped) - goal) > 2.5 and GetGameTimer() < walkUntil do
            Wait(500)
        end
        if not units[id] then return end
        if d.scenario then TaskStartScenarioInPlace(ped, d.scenario, 0, true) end

        TriggerServerEvent(Ev('server:aiArrived'), id)
    end)
end)

-- A unit that is already working at the scene (it arrived while nobody was near):
-- park the vehicle with lights on and put the crew to work next to the patient/scene.
RegisterNetEvent(Ev('client:aiSpawnOnScene'), function(id, d)
    CreateThread(function()
        local target = v3(d.coords)
        local vehHash, pedHash = loadModel(d.vehicle), loadModel(d.ped)
        local found, pos, heading = GetClosestVehicleNodeWithHeading(target.x, target.y, target.z, 1, 3.0, 0)
        if not vehHash or not pedHash or not found then
            return TriggerServerEvent(Ev('server:aiSpawnFailed'), id)
        end

        local veh = CreateVehicle(vehHash, pos.x, pos.y, pos.z, heading, true, false)
        local t = GetGameTimer() + 3000
        while not DoesEntityExist(veh) and GetGameTimer() < t do Wait(0) end
        if not DoesEntityExist(veh) then return TriggerServerEvent(Ev('server:aiSpawnFailed'), id) end
        SetVehicleOnGroundProperly(veh)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleSiren(veh, true)
        SetVehicleHasMutedSirens(veh, true)   -- lights on, no siren sound on scene

        local goal = target
        if d.targetNetId and NetworkDoesNetworkIdExist(d.targetNetId) then
            local npc = NetworkGetEntityFromNetworkId(d.targetNetId)
            if npc ~= 0 and DoesEntityExist(npc) then goal = GetEntityCoords(npc) end
        elseif d.target then
            local player = GetPlayerFromServerId(d.target)
            local tped = player ~= -1 and GetPlayerPed(player) or 0
            if tped ~= 0 and #(GetEntityCoords(tped) - target) < 60.0 then goal = GetEntityCoords(tped) end
        end
        local gx, gy = goal.x + 1.2, goal.y + 1.2
        local ok, gz = GetGroundZFor_3dCoord(gx, gy, goal.z + 2.0, false)
        local ped = CreatePed(4, pedHash, gx, gy, ok and gz or goal.z, 0.0, true, false)
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedKeepTask(ped, true)
        TaskTurnPedToFaceCoord(ped, goal.x, goal.y, goal.z, 1000)
        SetModelAsNoLongerNeeded(vehHash)
        SetModelAsNoLongerNeeded(pedHash)

        units[id] = { veh = veh, ped = ped }
        TriggerServerEvent(Ev('server:aiSpawned'), id, {
            NetworkGetNetworkIdFromEntity(veh), NetworkGetNetworkIdFromEntity(ped),
        })
        Wait(1000)
        if d.scenario and DoesEntityExist(ped) then TaskStartScenarioInPlace(ped, d.scenario, 0, true) end
    end)
end)

RegisterNetEvent(Ev('client:aiLeave'), function(id)
    local u = units[id]
    if not u then return end
    CreateThread(function()
        if DoesEntityExist(u.ped) and DoesEntityExist(u.veh) then
            ClearPedTasks(u.ped)
            TaskEnterVehicle(u.ped, u.veh, 15000, -1, 1.5, 1, 0)
            local t = GetGameTimer() + 15000
            while GetGameTimer() < t and not IsPedInVehicle(u.ped, u.veh, false) do Wait(500) end
            SetVehicleSiren(u.veh, false)
            TaskVehicleDriveWander(u.ped, u.veh, 15.0, 786603)
            Wait(25000)
        end
        cleanup(id)
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
    NetworkRequestControlOfEntity(best)
    local t = GetGameTimer() + 2000
    while not NetworkHasControlOfEntity(best) and GetGameTimer() < t do Wait(50) end
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
