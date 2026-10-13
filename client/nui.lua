NUI = { focused = false }

function NUI.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function NUI.Focus(state)
    NUI.focused = state
    SetNuiFocus(state, state)
end

RegisterNUICallback('close', function(_, cb)
    NUI.Focus(false)
    cb(1)
end)
