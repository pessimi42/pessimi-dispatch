-- Call blips only: every active call for dispatchers, the current call for units.

Blips = { calls = {}, mine = nil }

local function svcBlip(service)
    local s = service and Services[service]
    return (s and s.blip) or Config.UnknownBlip
end

local function make(call, label)
    if not call.coords then return nil end
    local b = svcBlip(call.service)
    local blip = AddBlipForCoord(call.coords.x, call.coords.y, call.coords.z)
    SetBlipSprite(blip, b.callSprite or b.sprite or 280)
    SetBlipColour(blip, b.color or 0)
    SetBlipScale(blip, 0.9)
    SetBlipAsShortRange(blip, false)
    local p = Utils.PriorityDef(call.priority)
    if p and p.flash then SetBlipFlashes(blip, true) end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function label(call)
    return ('#%d %s'):format(call.id, Locale.T('calltype.' .. call.type))
end

function Blips.RemoveCall(id)
    if Blips.calls[id] then
        RemoveBlip(Blips.calls[id])
        Blips.calls[id] = nil
    end
end

function Blips.SetCall(call)
    Blips.RemoveCall(call.id)
    if call.status ~= 'closed' then Blips.calls[call.id] = make(call, label(call)) end
end

function Blips.ClearCalls()
    for id in pairs(Blips.calls) do Blips.RemoveCall(id) end
end

function Blips.SetMine(call)
    if Blips.mine then RemoveBlip(Blips.mine) Blips.mine = nil end
    if call then
        Blips.mine = make(call, label(call))
        if Blips.mine and Config.Units.autoWaypoint then
            SetBlipRoute(Blips.mine, true)
            SetBlipRouteColour(Blips.mine, svcBlip(call.service).color or 5)
        end
    end
end
