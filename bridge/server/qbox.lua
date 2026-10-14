if Bridge.name ~= 'qbox' then return end

local function player(src) return exports.qbx_core:GetPlayer(src) end

function Bridge.GetJob(src)
    local p = player(src)
    if not p then return nil end
    local job = p.PlayerData.job
    return {
        name = job.name,
        label = job.label,
        grade = job.grade and job.grade.level or 0,
        gradeLabel = job.grade and job.grade.name or nil,
        onDuty = job.onduty == true,
    }
end

function Bridge.GetCharName(src)
    local p = player(src)
    if not p then return GetPlayerName(src) end
    local c = p.PlayerData.charinfo
    return ('%s %s'):format(c.firstname, c.lastname)
end

function Bridge.GetIdentifier(src)
    local p = player(src)
    return p and p.PlayerData.citizenid or GetPlayerIdentifierByType(src, 'license')
end

function Bridge.GetPhone(src)
    local p = player(src)
    return p and p.PlayerData.charinfo and p.PlayerData.charinfo.phone or nil
end

function Bridge.SetDuty(src, state)
    local p = player(src)
    if p then p.Functions.SetJobDuty(state) end
end

function Bridge.HasAnyItem(src, items)
    local ox = Bridge.OxHasAnyItem(src, items)
    if ox ~= nil then return ox end
    return true -- Qbox ships with ox_inventory; without it we do not block calls
end

--- Used by NPC medics.
function Bridge.Revive(src)
    if GetResourceState('qbx_medical') == 'started' then
        exports.qbx_medical:Revive(src)
    else
        TriggerClientEvent('hospital:client:Revive', src)
    end
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(p)
    Units.Refresh(p.PlayerData.source)
end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(src) Units.Refresh(src) end)
AddEventHandler('QBCore:Server:SetDuty', function(src) Units.Refresh(src) end)
