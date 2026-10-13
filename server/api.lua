--[[ Server exports – the integration surface for MDTs, police/EMS dispatch
  scripts and job scripts. Example:

    local id = exports.pessimi42_dispatch:CreateCall({
        service = 'ems', type = 'unconscious', priority = 'A',
        message = 'Person collapsed at the gym', coords = coords,
    })

  Server events you can listen to (AddEventHandler, same server):
    pessimi42_dispatch:onCallCreated   (call)
    pessimi42_dispatch:onCallUpdated   (call)
    pessimi42_dispatch:onCallClosed    (call)
    pessimi42_dispatch:onUnitAssigned  (callId, src)
    pessimi42_dispatch:onUnitUnassigned(callId, src)
    pessimi42_dispatch:onUnitStatus    (src, status)
    pessimi42_dispatch:onUnitAdded     (src, service)
    pessimi42_dispatch:onUnitRemoved   (src)
    pessimi42_dispatch:onAiSent        (callId, aiId, service)
  (the prefix is the resource name)
]]

exports('CreateCall', function(data, opts)
    if type(data) ~= 'table' then return nil end
    data.origin = data.origin or (GetInvokingResource() or 'api')
    data.callerSrc = nil
    return Calls.Create(data, opts)
end)

exports('GetCall', function(id) return Calls.Public(Calls.Get(id)) end)

exports('GetCalls', function(includeClosed)
    local out = {}
    for _, c in pairs(Calls.list) do
        if includeClosed or c.status ~= 'closed' then out[#out + 1] = Calls.Public(c) end
    end
    return out
end)

exports('UpdateCall', function(id, patch) return Calls.Update(id, patch) end)
exports('AddNote', function(id, text, author) return Calls.AddNote(id, text, author or GetInvokingResource()) end)
exports('AssignUnit', function(id, src) return Calls.Assign(id, src) end)
exports('UnassignUnit', function(id, src) return Calls.Unassign(id, src) end)
exports('BroadcastCall', function(id) return Calls.Broadcast(id) end)
exports('AutoDispatch', function(id) return Calls.AutoDispatch(id) end)
exports('CloseCall', function(id) return Calls.Close(id) end)

exports('GetUnit', function(src)
    local u = Units.Get(src)
    return u and Units.Public(u) or nil
end)
exports('GetUnits', function(service) return Units.All(service) end)
exports('SetUnitStatus', function(src, status)
    status = Utils.ResolveStatus(status)
    return status ~= nil and Units.SetStatus(src, status)
end)
exports('FindNearestUnit', function(coords, service)
    return Calls.FindNearestUnit(Utils.Coords(coords), service)
end)

exports('IsDispatcherOnDuty', function() return Dispatch.HasDispatcher() end)
exports('IsDispatcher', function(src) return Dispatch.list[tonumber(src)] ~= nil end)

--- AI units
exports('SendAiUnit', function(id) return Ai.Send(id) end)
exports('GetAiUnits', function()
    local out = {}
    for _, a in pairs(Ai.active) do out[#out + 1] = { id = a.id, callId = a.callId, service = a.service, status = a.status } end
    return out
end)

--- Phone support for another phone script. See server/phones/_template.lua.
exports('RegisterPhone', function(name, impl) return Phone.Register(name, impl) end)
--- Text a call's caller from the dispatch number. Returns the sent text or nil.
exports('SmsCaller', function(id, text)
    local call = Calls.Get(id)
    return call and Sms.ToCaller(call, text, nil, nil, GetInvokingResource()) or nil
end)
--- Feed an incoming text to the dispatch number (for phones without a built-in provider).
exports('IncomingSms', function(number, text) return Sms.Incoming(number, text) end)

--- Outbound adapter for another dispatch script. See server/adapters.lua.
exports('RegisterAdapter', function(name, impl) return Adapters.Register(name, impl) end)

--- Add or replace a service at runtime, e.g. from a fire job resource.
--- Clients only learn about it after their NUI reloads (reconnect), so prefer
--- config/services.lua for permanent services.
exports('RegisterService', function(id, def)
    if type(id) ~= 'string' or type(def) ~= 'table' then return false end
    def.enabled = def.enabled ~= false
    def.jobs = def.jobs or {}
    def.callTypes = def.callTypes or { 'general' }
    def.notify = def.notify or { 'native' }
    def.blip = def.blip or Config.UnknownBlip
    Services[id] = def
    for _, pid in ipairs(GetPlayers()) do Units.Refresh(tonumber(pid)) end
    return true
end)
