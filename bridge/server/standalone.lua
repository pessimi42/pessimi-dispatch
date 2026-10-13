if Bridge.name ~= 'standalone' then return end

-- No framework: roles come from ACE permissions.
--   add_ace group.dispatch pessimi42_dispatch.dispatcher allow
--   add_ace group.police   pessimi42_dispatch.service.police allow

local ace = Config.StandaloneAce

local function firstJob(jobs)
    for name in pairs(jobs) do return name end
end

function Bridge.GetJob(src)
    if IsPlayerAceAllowed(src, ace .. '.dispatcher') then
        return { name = firstJob(Config.Dispatcher.jobs), grade = 99, onDuty = true }
    end
    for id, s in pairs(Services) do
        if s.enabled and IsPlayerAceAllowed(src, ('%s.service.%s'):format(ace, id)) then
            return { name = firstJob(s.jobs), grade = 99, onDuty = true }
        end
    end
    return nil
end

function Bridge.GetCharName(src) return GetPlayerName(src) end
function Bridge.GetIdentifier(src) return GetPlayerIdentifierByType(src, 'license') end
function Bridge.GetPhone() return nil end
function Bridge.SetDuty() end

function Bridge.HasAnyItem(src, items)
    local ox = Bridge.OxHasAnyItem(src, items)
    if ox ~= nil then return ox end
    return true
end

--- No framework medical system: set Config.AiUnits.reviveEvent to your script's event.
function Bridge.Revive(src)
    Utils.Warn('AI medic: no revive event configured (Config.AiUnits.reviveEvent)')
end
