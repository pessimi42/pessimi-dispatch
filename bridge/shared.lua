Bridge = {}

local function running(res)
    local state = GetResourceState(res)
    return state == 'started' or state == 'starting'
end

if Config.Framework and Config.Framework ~= 'auto' then
    Bridge.name = Config.Framework
elseif running('qbx_core') then   -- check before qb-core: qbx_core also provides 'qb-core'
    Bridge.name = 'qbox'
elseif running('qb-core') then
    Bridge.name = 'qbcore'
elseif running('es_extended') then
    Bridge.name = 'esx'
else
    Bridge.name = 'standalone'
end

if IsDuplicityVersion() then
    print(('^2[%s] framework: %s^7'):format(GetCurrentResourceName(), Bridge.name))
end

--[[ Server interface every adapter implements:
    Bridge.GetJob(src)          -> { name, label, grade, gradeLabel, onDuty } | nil
    Bridge.GetCharName(src)     -> string
    Bridge.GetIdentifier(src)   -> string
    Bridge.GetPhone(src)        -> string | nil
    Bridge.SetDuty(src, bool)
    Bridge.HasAnyItem(src, items) -> bool
  Adapters call Units.Refresh(src) when a player's job or duty changes.

  Client interface:
    Bridge.Notify(text, type)   type: 'success' | 'error' | 'inform'
]]

--- ox_inventory works the same on every framework, so try it first.
function Bridge.OxHasAnyItem(src, items)
    if GetResourceState('ox_inventory') ~= 'started' then return nil end
    for _, item in ipairs(items) do
        local count = exports.ox_inventory:Search(src, 'count', item)
        if count and count > 0 then return true end
    end
    return false
end
