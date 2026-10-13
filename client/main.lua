local Role = { dispatcher = false, service = nil }
local MyCall, MyStatus, MyCallsign
local LastBroadcast
local respondCmd = Config.Units.respondCommand

---------------------------------------------------------------------------
-- Language
---------------------------------------------------------------------------
local function savedLanguage()
    if Config.AllowPlayerLanguage then
        local code = GetResourceKvpString('lang')
        if code and Locale.Exists(code) then return code end
    end
    return Config.Locale
end

Locale.Set(savedLanguage())

local function T(key, vars) return Locale.T(key, vars) end

local function aiServices()
    local list = {}
    if not Config.AiUnits.enabled then return list end
    for id, s in pairs(Config.AiUnits.services) do
        if s.enabled and Utils.ServiceEnabled(id) then list[#list + 1] = id end
    end
    return list
end

local function sendInit()
    local services = {}
    for id, s in pairs(Services) do
        if s.enabled then
            services[#services + 1] = { id = id, color = s.color, icon = s.icon, order = s.order or 99, callTypes = s.callTypes }
        end
    end
    table.sort(services, function(a, b) return a.order < b.order end)

    NUI.Send('init', {
        locale = Locale.Merged(Locale.active),
        lang = Locale.active,
        languages = Config.AllowPlayerLanguage and Locale.Available() or {},
        services = services,
        priorities = Config.Priorities,
        statuses = Config.UnitStatuses,
        hud = Config.Units.hud,
        quickReplies = Config.Sms.quickReplies,
        aiServices = aiServices(),
        fallbackService = Config.Fallback.unspecifiedService,
        aiOnlyWhenNoneOnDuty = Config.AiUnits.trigger ~= 'no_available',
        role = Role,
    })
    -- Messages sent before the page loaded were dropped; replay unit state.
    if Role.service then
        NUI.Send('myStatus', { status = MyStatus, callsign = MyCallsign, service = Role.service })
        NUI.Send('myCall', MyCall)
    end
end

local function setLanguage(code)
    if not Config.AllowPlayerLanguage then return false end
    if not Locale.Set(code) then return false end
    SetResourceKvp('lang', code)
    TriggerServerEvent(Ev('server:lang'), code)
    NUI.Send('locale', { locale = Locale.Merged(code), lang = code })
    return true
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function notify(key, vars, kind) Bridge.Notify(T(key, vars), kind) end

local function streetAt(c)
    local s1, s2 = GetStreetNameAtCoord(c.x, c.y, c.z)
    local name = GetStreetNameFromHashKey(s1)
    if s2 and s2 ~= 0 then name = name .. ' / ' .. GetStreetNameFromHashKey(s2) end
    local zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
    if zone and zone ~= '' and zone ~= 'NULL' then name = name .. ', ' .. zone end
    return name
end

--- Calls created server-side (API, other scripts) may lack a street; resolve it here.
local function fillStreet(call)
    if call and call.coords and not call.street then call.street = streetAt(call.coords) end
    return call
end

local function playSound(priority)
    local p = Utils.PriorityDef(priority)
    local s = Config.Sounds[p and p.sound or 'default'] or Config.Sounds.default
    CreateThread(function()
        for _ = 1, s.repeats or 1 do
            PlaySoundFrontend(-1, s.name, s.set, true)
            Wait(700)
        end
    end)
end

local function myCoords()
    local c = GetEntityCoords(PlayerPedId())
    return { x = c.x, y = c.y, z = c.z }
end

---------------------------------------------------------------------------
-- NUI bootstrap
---------------------------------------------------------------------------
RegisterNUICallback('uiReady', function(_, cb)
    sendInit()
    cb(1)
end)

CreateThread(function()
    TriggerServerEvent(Ev('server:lang'), Locale.active)
    TriggerServerEvent(Ev('server:ready'))
end)

---------------------------------------------------------------------------
-- 112
---------------------------------------------------------------------------
local function sendEmergency(service, message)
    local c = myCoords()
    TriggerServerEvent(Ev('server:emergencyCall'), {
        service = service,
        message = message,
        street = streetAt(c),
    })
end

for _, cmd in ipairs(Config.EmergencyCall.commands) do
    RegisterCommand(cmd, function(_, args)
        local message = table.concat(args, ' ')
        if message ~= '' then
            sendEmergency(nil, message)
        else
            NUI.Send('openCaller')
            NUI.Focus(true)
        end
    end, false)
    TriggerEvent('chat:addSuggestion', '/' .. cmd, T('cmd.112'), { { name = T('cmd.message'), help = T('caller.describe') } })
end

RegisterNUICallback('emergencyCall', function(data, cb)
    NUI.Focus(false)
    if type(data) == 'table' then sendEmergency(data.service, data.message) end
    cb(1)
end)

---------------------------------------------------------------------------
-- Dispatcher
---------------------------------------------------------------------------
RegisterCommand(Config.Dispatcher.command, function()
    if not Role.dispatcher then return notify('error.not_dispatcher', nil, 'error') end
    TriggerServerEvent(Ev('server:requestState'))
    NUI.Send('openPanel')
    NUI.Focus(true)
end, false)
RegisterKeyMapping(Config.Dispatcher.command, T('key.panel'), 'keyboard', Config.Dispatcher.key)

RegisterNetEvent(Ev('client:role'), function(role)
    local wasDispatcher = Role.dispatcher
    Role = role
    if wasDispatcher and not role.dispatcher then
        Blips.ClearCalls()
        NUI.Send('closePanel')
        if NUI.focused then NUI.Focus(false) end
    end
    if not role.service then
        MyCall, MyStatus = nil, nil
        Blips.SetMine(nil)
    end
    NUI.Send('role', role)
end)

RegisterNetEvent(Ev('client:state'), function(state)
    Blips.ClearCalls()
    for _, call in ipairs(state.calls) do
        fillStreet(call)
        Blips.SetCall(call)
    end
    NUI.Send('state', state)
end)

RegisterNetEvent(Ev('client:callChanged'), function(call, kind)
    if not Role.dispatcher then return end
    fillStreet(call)
    Blips.SetCall(call)
    NUI.Send('callChanged', { call = call, kind = kind })
    if kind == 'created' then
        playSound(call.priority)
        NUI.Send('toast', { kind = 'newCall', call = call })
    end
end)

RegisterNetEvent(Ev('client:unitChanged'), function(unit) NUI.Send('unitChanged', unit) end)
RegisterNetEvent(Ev('client:unitRemoved'), function(src) NUI.Send('unitRemoved', src) end)

RegisterNUICallback('action', function(data, cb)
    if type(data) ~= 'table' then return cb(0) end
    local payload = data.payload or {}
    if data.type == 'waypoint' then
        if payload.x and payload.y then SetNewWaypoint(payload.x + 0.0, payload.y + 0.0) end
        return cb(1)
    end
    if data.type == 'createCall' then
        local wp = GetFirstBlipInfoId(8)
        if DoesBlipExist(wp) then
            local c = GetBlipInfoIdCoord(wp)
            payload.coords = { x = c.x, y = c.y, z = 0.0 }
            payload.street = streetAt(payload.coords)
        end
    end
    TriggerServerEvent(Ev('server:dispatcherAction'), data.type, payload)
    cb(1)
end)

RegisterNUICallback('setLanguage', function(data, cb)
    cb(setLanguage(data and data.lang) and 1 or 0)
end)

---------------------------------------------------------------------------
-- Units
---------------------------------------------------------------------------
RegisterNetEvent(Ev('client:myCall'), function(call)
    local changedCall = (call and call.id) ~= (MyCall and MyCall.id)
    MyCall = fillStreet(call)
    if changedCall then Blips.SetMine(MyCall) end
    NUI.Send('myCall', MyCall)
end)

RegisterNetEvent(Ev('client:unitStatus'), function(status, callsign)
    MyStatus, MyCallsign = status, callsign
    NUI.Send('myStatus', { status = status, callsign = callsign, service = Role.service })
end)

RegisterNetEvent(Ev('client:statusSet'), function(status)
    notify('unit.status_set', { status = T('unit_status.' .. status) }, 'success')
end)

RegisterNetEvent(Ev('client:alert'), function(kind, call)
    fillStreet(call)
    playSound(call.priority)
    if kind == 'broadcast' then LastBroadcast = call.id end
    NUI.Send('toast', { kind = kind, call = call, respondCmd = respondCmd })
end)

RegisterCommand(respondCmd, function(_, args)
    local id = tonumber(args[1]) or LastBroadcast
    if not id then return notify('error.no_broadcast', nil, 'error') end
    TriggerServerEvent(Ev('server:respond'), id)
end, false)
RegisterKeyMapping(respondCmd, T('key.respond'), 'keyboard', Config.Units.respondKey)

-- Arrival detection: en route -> on scene
CreateThread(function()
    while true do
        local sleep = 2000
        if Config.Units.autoOnScene and MyCall and MyCall.coords and MyStatus == 'enroute' then
            sleep = 1000
            local c = GetEntityCoords(PlayerPedId())
            if #(c - vector3(MyCall.coords.x, MyCall.coords.y, MyCall.coords.z)) < Config.Units.onSceneDistance then
                MyStatus = 'onscene'
                TriggerServerEvent(Ev('server:setStatus'), 'onscene')
            end
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------------
-- Language command & misc
---------------------------------------------------------------------------
RegisterCommand(Config.LanguageCommand, function(_, args)
    local list = {}
    for _, l in ipairs(Locale.Available()) do list[#list + 1] = l.code end
    if not args[1] or not setLanguage(args[1]) then
        return notify('error.lang_unknown', { list = table.concat(list, ', ') }, 'error')
    end
    notify('lang.set', { name = Locale.T('_meta.name') }, 'success')
end, false)

RegisterNetEvent(Ev('client:notify'), function(key, vars, kind)
    if key == 'unit.status_set' and vars and vars.status then
        vars.status = T('unit_status.' .. vars.status)
    end
    notify(key, vars, kind)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Blips.ClearCalls()
    Blips.SetMine(nil)
    if NUI.focused then SetNuiFocus(false, false) end
end)

-- Exposed to client/api.lua
ClientState = {
    IsDispatcher = function() return Role.dispatcher end,
    GetService = function() return Role.service end,
    GetMyCall = function() return MyCall end,
    GetStatus = function() return MyStatus end,
    StreetAt = streetAt,
}
