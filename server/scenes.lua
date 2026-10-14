-- NPC scenes for AI calls: when a player comes near an AI call, the nearest player
-- spawns what the caller described (a patient, a witness, a crash, a fire, a broken-down
-- car). Units interact with it (E) or put the fire out; then the scene is handled.

Scenes = { active = {} }   -- [callId] = scene

local cfg = Config.Scenes

local function kindFor(call)
    return call and call._ai and cfg.kinds[call.type] or nil
end

function Scenes.Count()
    local n = 0
    for _ in pairs(Scenes.active) do n = n + 1 end
    return n
end

local function pick(list) return list[math.random(#list)] end

local function nearestPlayer(coords, range)
    local best, bestDist
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local d = Utils.Distance2D(GetEntityCoords(ped), coords)
            if d <= range and (not bestDist or d < bestDist) then best, bestDist = src, d end
        end
    end
    return best
end

local function deleteEntities(scene)
    for _, netId in ipairs(scene.netIds or {}) do
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    scene.netIds = {}
    scene.pedNetId = nil
end

--- What every client needs to show prompts. Sent to everyone; the server checks on use.
local function info(scene)
    return {
        callId = scene.callId, kind = scene.kind, handled = scene.handled,
        pedNetId = scene.pedNetId, coords = scene.coords,
        services = cfg.interact[scene.kind] or {},
    }
end

local function broadcast(scene)
    TriggerClientEvent(Ev('client:sceneInfo'), -1, info(scene))
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------
local function spawn(scene, call, host)
    scene.host = host
    scene.coords = call.coords
    TriggerClientEvent(Ev('client:sceneSpawn'), host, call.id, {
        kind = scene.kind,
        coords = call.coords,
        ped = scene.pedModel,
        vehicle = scene.vehModel,
        handled = scene.handled,
        fireRadius = cfg.fireRadius,
    })
end

--- Spawn scenes for AI calls that a player has come close to.
function Scenes.Watch()
    if not cfg.enabled then return end
    for _, call in pairs(Calls.list) do
        local kind = call.status ~= 'closed' and call.coords and kindFor(call)
        if kind then
            local scene = Scenes.active[call.id]
            if not scene and Scenes.Count() < cfg.maxActive then
                scene = {
                    callId = call.id, kind = kind, netIds = {}, handled = false,
                    pedModel = pick(cfg.peds), vehModel = pick(cfg.vehicles),
                }
                local host = nearestPlayer(call.coords, cfg.spawnRange)
                if host then
                    Utils.Debug(('spawning %s scene for call #%d on player %d'):format(kind, call.id, host))
                    Scenes.active[call.id] = scene
                    spawn(scene, call, host)
                end
            elseif scene and not scene.host and not scene.handled then
                local host = nearestPlayer(call.coords, cfg.spawnRange)
                if host then spawn(scene, call, host) end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(3000)
        Scenes.Watch()
    end
end)

RegisterNetEvent(Ev('server:sceneSpawned'), function(callId, pedNetId, netIds, at)
    local scene = Scenes.active[tonumber(callId)]
    if not scene or scene.host ~= source or type(netIds) ~= 'table' then return end
    -- The host moved the NPC to a walkable spot; use where it really is (E-prompt range check)
    at = Utils.Coords(at)
    if at and scene.coords and Utils.Distance2D(at, scene.coords) < 40.0 then scene.coords = at end
    Utils.Debug(('scene %s spawned for call #%d by player %d'):format(scene.kind, scene.callId, source))
    scene.netIds = {}
    for _, n in ipairs(netIds) do
        if tonumber(n) then scene.netIds[#scene.netIds + 1] = tonumber(n) end
    end
    scene.pedNetId = tonumber(pedNetId)
    broadcast(scene)
end)

RegisterNetEvent(Ev('server:sceneSpawnFailed'), function(callId)
    local scene = Scenes.active[tonumber(callId)]
    if scene and scene.host == source then
        Utils.Debug(('scene for call #%d failed to spawn on player %d, will retry'):format(scene.callId, source))
        Scenes.active[scene.callId] = nil
    end
end)

---------------------------------------------------------------------------
-- Handling
---------------------------------------------------------------------------
--- Mark the scene handled: log it, let the NPCs react, remove the prompts.
--- by: 'unit' | 'ai' | 'fire'
function Scenes.Resolve(callId, by)
    local scene = Scenes.active[callId]
    if not scene or scene.handled then return false end
    scene.handled = true
    local keyByKind = {
        patient = 'scene.note_treated', crash = 'scene.note_treated',
        witness = 'scene.statement.' .. math.random(1, 3), cower = 'scene.statement.' .. math.random(1, 3),
        breakdown = 'scene.note_repaired', carfire = 'scene.note_fire_out', fire = 'scene.note_fire_out',
    }
    Calls.AddNote(callId, keyByKind[scene.kind] or 'scene.note_handled', nil, 'sys')
    if scene.host and GetPlayerName(scene.host) then
        TriggerClientEvent(Ev('client:sceneResolve'), scene.host, callId, scene.kind)
    end
    broadcast(scene)
    TriggerEvent(Ev('onSceneHandled'), callId, scene.kind, by)
    return true
end

--- A unit pressed E next to the scene's NPC.
RegisterNetEvent(Ev('server:sceneInteract'), function(callId)
    local src = source
    local scene = Scenes.active[tonumber(callId)]
    local unit = Units.Get(src)
    if not scene or scene.handled or not unit or not scene.coords then return end
    if not Utils.Contains(cfg.interact[scene.kind], unit.service) then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or Utils.Distance2D(GetEntityCoords(ped), scene.coords) > 25.0 then return end
    Scenes.Resolve(scene.callId, 'unit')
end)

--- The host saw the fires go out.
RegisterNetEvent(Ev('server:sceneFireOut'), function(callId)
    local scene = Scenes.active[tonumber(callId)]
    if scene and scene.host == source and (scene.kind == 'fire' or scene.kind == 'carfire') then
        Scenes.Resolve(scene.callId, 'fire')
    end
end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
function Scenes.Clear(callId)
    local scene = Scenes.active[callId]
    if not scene then return end
    Scenes.active[callId] = nil
    if scene.host and GetPlayerName(scene.host) then
        TriggerClientEvent(Ev('client:sceneClear'), scene.host, callId, scene.coords, cfg.fireRadius)
    end
    deleteEntities(scene)
    TriggerClientEvent(Ev('client:sceneInfo'), -1, { callId = callId, removed = true })
end

--- Ped netId of a call's scene (NPC medics walk to it).
function Scenes.PedNetId(callId)
    local scene = Scenes.active[callId]
    return scene and scene.pedNetId or nil
end

AddEventHandler('playerDropped', function()
    local src = source
    for _, scene in pairs(Scenes.active) do
        if scene.host == src then
            scene.host = nil
            deleteEntities(scene)          -- respawned when someone comes near again
            broadcast(scene)
        end
    end
end)

--- Late joiners and restarted clients get the current scenes.
RegisterNetEvent(Ev('server:ready'), function()
    local src = source
    for _, scene in pairs(Scenes.active) do
        TriggerClientEvent(Ev('client:sceneInfo'), src, info(scene))
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, scene in pairs(Scenes.active) do deleteEntities(scene) end
end)
