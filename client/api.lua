--[[ Client exports

  Automatic alert from a client script (robbery, shots fired, ...):
    exports.pessimi42_dispatch:CreateAlert({
        service = 'police', type = 'robbery', priority = 'B',
        message = 'Store alarm triggered', code = '10-90',
    })
  coords default to the player's position.
]]

exports('CreateAlert', function(data)
    if type(data) ~= 'table' then return end
    local c = data.coords and Utils.Coords(data.coords)
    if not c then
        local p = GetEntityCoords(PlayerPedId())
        c = { x = p.x, y = p.y, z = p.z }
    end
    data.coords = c
    data.street = data.street or ClientState.StreetAt(c)
    TriggerServerEvent(Ev('server:clientAlert'), data)
end)

exports('OpenCallerForm', function()
    NUI.Send('openCaller')
    NUI.Focus(true)
end)

exports('IsDispatcher', function() return ClientState.IsDispatcher() end)
exports('GetService', function() return ClientState.GetService() end)
exports('GetMyCall', function() return ClientState.GetMyCall() end)
exports('GetStatus', function() return ClientState.GetStatus() end)
