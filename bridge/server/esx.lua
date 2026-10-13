if Bridge.name ~= 'esx' then return end

local ESX = exports.es_extended:getSharedObject()

local function player(src) return ESX.GetPlayerFromId(src) end

-- ESX Legacy 1.10+ has job.onDuty. Older versions often use an "off" job
-- prefix (offpolice) instead; such a job simply doesn't match a service.
function Bridge.GetJob(src)
    local p = player(src)
    if not p then return nil end
    local job = p.getJob()
    return {
        name = job.name,
        label = job.label,
        grade = tonumber(job.grade) or 0,
        gradeLabel = job.grade_label,
        onDuty = job.onDuty ~= false,
    }
end

function Bridge.GetCharName(src)
    local p = player(src)
    return p and p.getName() or GetPlayerName(src)
end

function Bridge.GetIdentifier(src)
    local p = player(src)
    return p and p.identifier or GetPlayerIdentifierByType(src, 'license')
end

function Bridge.GetPhone(src)
    local p = player(src)
    if not p then return nil end
    local ok, phone = pcall(function() return p.get('phoneNumber') end)
    return ok and phone or nil
end

function Bridge.SetDuty(src, state)
    local p = player(src)
    if not p then return end
    local job = p.getJob()
    if job.onDuty == nil then return end -- this ESX version has no duty system
    p.setJob(job.name, job.grade, state)
end

function Bridge.HasAnyItem(src, items)
    local ox = Bridge.OxHasAnyItem(src, items)
    if ox ~= nil then return ox end
    local p = player(src)
    if not p then return false end
    for _, item in ipairs(items) do
        local it = p.getInventoryItem(item)
        if it and (it.count or 0) > 0 then return true end
    end
    return false
end

AddEventHandler('esx:playerLoaded', function(src) Units.Refresh(src) end)
AddEventHandler('esx:setJob', function(src) Units.Refresh(src) end)
