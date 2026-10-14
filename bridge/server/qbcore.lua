if Bridge.name ~= 'qbcore' then return end

local QBCore = exports['qb-core']:GetCoreObject()

local function player(src) return QBCore.Functions.GetPlayer(src) end

function Bridge.GetJob(src)
    local p = player(src)
    if not p then return nil end
    local job = p.PlayerData.job
    return {
        name = job.name,
        label = job.label,
        grade = job.grade and tonumber(job.grade.level) or 0,
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
    local p = player(src)
    if not p then return false end
    for _, item in ipairs(items) do
        if p.Functions.GetItemByName(item) then return true end
    end
    return false
end

--- Used by NPC medics (qb-ambulancejob).
function Bridge.Revive(src)
    TriggerClientEvent('hospital:client:Revive', src)
end

--- Downed (dead / last stand) according to the framework, used by NPC medics.
function Bridge.IsDowned(src)
    local p = player(src)
    local m = p and p.PlayerData.metadata
    return m ~= nil and (m.isdead == true or m.inlaststand == true)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(p)
    Units.Refresh(p.PlayerData.source)
end)
AddEventHandler('QBCore:Server:OnJobUpdate', function(src) Units.Refresh(src) end)
AddEventHandler('QBCore:Server:SetDuty', function(src) Units.Refresh(src) end)
