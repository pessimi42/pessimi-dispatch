-- Client side only needs notifications; roles come from the server.

function Bridge.Notify(text, kind)
    kind = kind or 'inform'
    if GetResourceState('ox_lib') == 'started' then
        exports.ox_lib:notify({ description = text, type = kind })
    elseif Bridge.name == 'qbox' then
        exports.qbx_core:Notify(text, kind)
    elseif Bridge.name == 'qbcore' then
        TriggerEvent('QBCore:Notify', text, kind == 'inform' and 'primary' or kind)
    elseif Bridge.name == 'esx' then
        TriggerEvent('esx:showNotification', text, kind == 'inform' and 'info' or kind)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandThefeedPostTicker(false, true)
    end
end
