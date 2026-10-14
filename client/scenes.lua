-- NPC scenes for AI calls.
--  * Host side: spawn the scene the server asked for, react when it is handled,
--    report when fires are out, clean up.
--  * Every player: show the E prompt next to scene NPCs for the right units.

local spawned = {}   -- [callId] = { ped, veh, extra = {}, coords, kind } (host only)
local scenes = {}    -- [callId] = info from the server (all players)

local function loadModel(name)
    local hash = joaat(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > t then return nil end
        Wait(50)
    end
    return hash
end

local function loadDict(dict)
    RequestAnimDict(dict)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(50) end
    return HasAnimDictLoaded(dict)
end

local function debug(...)
    if Config.Debug then print('^5[' .. GetCurrentResourceName() .. ']^7', ...) end
end

--- Ground height at x,y. Loads collision first: far from the player the ground is not
--- loaded and the old one-shot probe returned the config z, which on slopes put NPCs
--- under the terrain (invisible patients).
local function ground(x, y, z)
    RequestCollisionAtCoord(x, y, z)
    local t = GetGameTimer() + 3000
    repeat
        for _, probe in ipairs({ z + 3.0, z + 25.0, z + 100.0 }) do
            local ok, gz = GetGroundZFor_3dCoord(x, y, probe, false)
            if ok and math.abs(gz - z) < 30.0 then return gz, true end
        end
        Wait(100)
        RequestCollisionAtCoord(x, y, z)
    until GetGameTimer() > t
    return z, false
end

--- A walkable spot near c: on the navmesh (pavement, not inside a building or on a
--- roof), with a real ground height.
local function spot(c)
    local gz = ground(c.x, c.y, c.z)
    local found, safe = GetSafeCoordForPed(c.x, c.y, gz, false, 16)
    if found and #(vector2(safe.x, safe.y) - vector2(c.x, c.y)) < 25.0 then
        local sz = ground(safe.x, safe.y, safe.z)
        return vector3(safe.x, safe.y, sz)
    end
    return vector3(c.x, c.y, gz)
end

local function makePed(hash, x, y, z, heading)
    local gz = ground(x, y, z)
    local ped = CreatePed(4, hash, x, y, gz, heading or 0.0, true, false)
    local t = GetGameTimer() + 2000
    while not DoesEntityExist(ped) and GetGameTimer() < t do Wait(0) end
    if not DoesEntityExist(ped) then return nil end
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    SetPedKeepTask(ped, true)
    SetPedCanRagdoll(ped, false)
    return ped
end

local function makeVehicle(hash, near)
    local found, pos, heading = GetClosestVehicleNodeWithHeading(near.x, near.y, near.z, 1, 3.0, 0)
    if not found then pos, heading = near, 0.0 end
    local veh = CreateVehicle(hash, pos.x, pos.y, pos.z, heading, true, false)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(veh) and GetGameTimer() < t do Wait(0) end
    if not DoesEntityExist(veh) then return nil end
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    return veh
end

local function lieDown(ped, unconscious)
    if unconscious then
        if loadDict('dead') then TaskPlayAnim(ped, 'dead', 'dead_a', 8.0, 8.0, -1, 1, 0, false, false, false) end
    elseif loadDict('combat@damage@writhe') then
        TaskPlayAnim(ped, 'combat@damage@writhe', 'writhe_loop', 8.0, 8.0, -1, 1, 0, false, false, false)
    end
end

---------------------------------------------------------------------------
-- Host: spawning
---------------------------------------------------------------------------
local builders = {}

function builders.patient(d, c)
    c = spot(c)
    local ped = makePed(d.pedHash, c.x, c.y, c.z, math.random(0, 359) + 0.0)
    if not ped then return nil end
    lieDown(ped, math.random() < 0.5)
    -- a bystander who made the call
    local bystander = makePed(d.pedHash2, c.x + 1.5, c.y + 1.0, c.z, 0.0)
    if bystander then
        TaskTurnPedToFaceEntity(bystander, ped, 1000)
        TaskStartScenarioInPlace(bystander, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
    end
    return ped, nil, { bystander }
end

function builders.crash(d, c)
    local veh = d.vehHash and makeVehicle(d.vehHash, c)
    if veh then
        SetVehicleEngineHealth(veh, 150.0)
        SetVehicleBodyHealth(veh, 300.0)
        SetVehicleDamage(veh, 0.0, 1.5, 0.3, 600.0, 2.0, true)
        SmashVehicleWindow(veh, 0)
        SetVehicleDoorBroken(veh, 4, true)
        SetVehicleIndicatorLights(veh, 0, true)
        SetVehicleIndicatorLights(veh, 1, true)
    end
    local at = veh and GetOffsetFromEntityInWorldCoords(veh, -2.5, 0.0, 0.0) or vector3(c.x, c.y, c.z)
    local ped = makePed(d.pedHash, at.x, at.y, at.z, 0.0)
    if not ped then return nil, veh end
    lieDown(ped, false)
    return ped, veh, {}
end

function builders.witness(d, c)
    c = spot(c)
    local ped = makePed(d.pedHash, c.x, c.y, c.z, math.random(0, 359) + 0.0)
    if not ped then return nil, veh end
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
    return ped, nil, {}
end

function builders.cower(d, c)
    c = spot(c)
    local ped = makePed(d.pedHash, c.x, c.y, c.z, math.random(0, 359) + 0.0)
    if not ped then return nil, veh end
    TaskStartScenarioInPlace(ped, 'CODE_HUMAN_COWER', 0, true)
    return ped, nil, {}
end

function builders.breakdown(d, c)
    local veh = d.vehHash and makeVehicle(d.vehHash, c)
    if veh then
        SetVehicleEngineHealth(veh, 120.0)     -- smoking engine
        SetVehicleDoorOpen(veh, 4, false, false)
        SetVehicleIndicatorLights(veh, 0, true)
        SetVehicleIndicatorLights(veh, 1, true)
        SetVehicleUndriveable(veh, true)
    end
    local at = veh and GetOffsetFromEntityInWorldCoords(veh, 0.0, 4.0, 0.0) or vector3(c.x, c.y, c.z)
    local ped = makePed(d.pedHash, at.x, at.y, at.z, 0.0)
    if not ped then return nil, veh end
    if veh then TaskTurnPedToFaceEntity(ped, veh, 1000) end
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
    return ped, veh, {}
end

function builders.carfire(d, c)
    local veh = d.vehHash and makeVehicle(d.vehHash, c)
    if veh then
        SetVehicleEngineHealth(veh, 50.0)
        StartEntityFire(veh)
    end
    local ped = makePed(d.pedHash, c.x + 12.0, c.y + 6.0, c.z, 0.0)
    if not ped then return nil, veh end
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
    return ped, veh, {}
end

function builders.fire(d, c)
    for _ = 1, 4 do
        local x, y = c.x + math.random(-8, 8), c.y + math.random(-8, 8)
        StartScriptFire(x, y, ground(x, y, c.z), 25, false)
    end
    local ped = makePed(d.pedHash, c.x + 18.0, c.y + 10.0, c.z, 0.0)
    if not ped then return nil, veh end
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
    return ped, nil, {}
end

RegisterNetEvent(Ev('client:sceneSpawn'), function(callId, d)
    CreateThread(function()
        local c = vector3(d.coords.x, d.coords.y, d.coords.z)
        d.pedHash = loadModel(d.ped)
        d.pedHash2 = d.pedHash
        if d.kind == 'crash' or d.kind == 'breakdown' or d.kind == 'carfire' then d.vehHash = loadModel(d.vehicle) end
        local build = builders[d.kind]
        if not d.pedHash or not build then return TriggerServerEvent(Ev('server:sceneSpawnFailed'), callId) end

        local ped, veh, extra = build(d, c)
        if not ped or not DoesEntityExist(ped) then
            if veh and DoesEntityExist(veh) then DeleteEntity(veh) end
            debug(('scene for call #%d could not spawn (%s)'):format(callId, d.kind))
            return TriggerServerEvent(Ev('server:sceneSpawnFailed'), callId)
        end
        Wait(1000)
        if not DoesEntityExist(ped) then
            debug(('scene NPC for call #%d was removed right after spawning (model %s blacklisted?)'):format(callId, d.ped))
            return TriggerServerEvent(Ev('server:sceneSpawnFailed'), callId)
        end
        SetModelAsNoLongerNeeded(d.pedHash)
        if d.vehHash then SetModelAsNoLongerNeeded(d.vehHash) end

        spawned[callId] = { ped = ped, veh = veh, extra = extra or {}, coords = c, kind = d.kind }
        local ids = { NetworkGetNetworkIdFromEntity(ped) }
        if veh then ids[#ids + 1] = NetworkGetNetworkIdFromEntity(veh) end
        for _, e in ipairs(extra or {}) do ids[#ids + 1] = NetworkGetNetworkIdFromEntity(e) end
        local at = GetEntityCoords(ped)
        debug(('scene %s for call #%d spawned at %.1f %.1f %.1f'):format(d.kind, callId, at.x, at.y, at.z))
        TriggerServerEvent(Ev('server:sceneSpawned'), callId, ids[1], ids, { x = at.x, y = at.y, z = at.z })

        -- Fire scenes: report once everything is out
        if d.kind == 'fire' or d.kind == 'carfire' then
            Wait(10000)
            while spawned[callId] do
                local burning = GetNumberOfFiresInRange(c.x, c.y, c.z, d.fireRadius) > 0
                    or (veh and DoesEntityExist(veh) and IsEntityOnFire(veh))
                if not burning then
                    TriggerServerEvent(Ev('server:sceneFireOut'), callId)
                    break
                end
                Wait(3000)
            end
        end
    end)
end)

--- Scene handled: patients get up, witnesses and drivers calm down, cars get fixed.
RegisterNetEvent(Ev('client:sceneResolve'), function(callId, kind)
    local s = spawned[callId]
    if not s then return end
    if DoesEntityExist(s.ped) then
        ClearPedTasks(s.ped)
        if kind == 'patient' or kind == 'crash' then
            TaskStartScenarioInPlace(s.ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
        elseif kind == 'cower' then
            TaskStartScenarioInPlace(s.ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
        end
    end
    if kind == 'breakdown' and s.veh and DoesEntityExist(s.veh) then
        SetVehicleFixed(s.veh)
        SetVehicleEngineHealth(s.veh, 1000.0)
        SetVehicleUndriveable(s.veh, false)
        SetVehicleDoorShut(s.veh, 4, false)
    end
end)

local function clearScene(callId, coords, radius)
    local s = spawned[callId]
    spawned[callId] = nil
    coords = coords or (s and s.coords)
    if coords then StopFireInRange(coords.x, coords.y, coords.z, radius or 30.0) end
    if not s then return end
    local list = { s.ped, s.veh }               -- s.veh may be nil: no ipairs over this
    local extra = {}
    for _, e in pairs(s.extra) do extra[#extra + 1] = e end
    for _, e in ipairs(extra) do list[#list + 1] = e end
    for i = 1, 2 + #extra do
        local e = list[i]
        if e and DoesEntityExist(e) then DeleteEntity(e) end
    end
end

RegisterNetEvent(Ev('client:sceneClear'), clearScene)

---------------------------------------------------------------------------
-- Everyone: E prompts for the right units
---------------------------------------------------------------------------
--- Entity of a call's scene NPC (patient, witness…), or 0. NPC units walk to it.
function DispatchScenePed(callId)
    local s = callId and scenes[callId]
    if not s or not s.pedNetId or not NetworkDoesNetworkIdExist(s.pedNetId) then return 0 end
    local ped = NetworkGetEntityFromNetworkId(s.pedNetId)
    return (ped ~= 0 and DoesEntityExist(ped)) and ped or 0
end

RegisterNetEvent(Ev('client:sceneInfo'), function(data)
    if type(data) ~= 'table' or not data.callId then return end
    if data.removed then scenes[data.callId] = nil else scenes[data.callId] = data end
end)

local promptKeys = {
    patient = 'scene.prompt_treat', crash = 'scene.prompt_treat',
    witness = 'scene.prompt_statement', cower = 'scene.prompt_statement',
    breakdown = 'scene.prompt_repair',
}

local function helpText(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

CreateThread(function()
    while true do
        local sleep = 750
        local service = ClientState and ClientState.GetService()
        if service then
            local me = GetEntityCoords(PlayerPedId())
            for id, s in pairs(scenes) do
                if not s.handled and s.pedNetId and promptKeys[s.kind] and Utils.Contains(s.services, service) then
                    local ped = NetworkDoesNetworkIdExist(s.pedNetId) and NetworkGetEntityFromNetworkId(s.pedNetId) or 0
                    if ped ~= 0 and DoesEntityExist(ped) then
                        local dist = #(me - GetEntityCoords(ped))
                        if dist < 15.0 then sleep = 0 end
                        if dist <= Config.Scenes.interactDistance then
                            helpText(Locale.T(promptKeys[s.kind]))
                            if IsControlJustReleased(0, Config.Scenes.interactKey) then
                                TriggerServerEvent(Ev('server:sceneInteract'), id)
                                s.handled = true  -- hide the prompt until the server confirms
                                local anim = (s.kind == 'patient' or s.kind == 'crash') and 'CODE_HUMAN_MEDIC_TEND_TO_DEAD'
                                    or (s.kind == 'breakdown' and 'WORLD_HUMAN_VEHICLE_MECHANIC') or 'WORLD_HUMAN_CLIPBOARD'
                                TaskStartScenarioInPlace(PlayerPedId(), anim, 0, true)
                                SetTimeout(6000, function() ClearPedTasks(PlayerPedId()) end)
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do clearScene(id) end
end)
