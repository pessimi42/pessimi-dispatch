Utils = {}

local RES = GetCurrentResourceName()
Utils.Resource = RES

--- Namespaced event name, so the resource can be renamed freely.
function Ev(name) return RES .. ':' .. name end

function Utils.Debug(...)
    if Config.Debug then print(('^5[%s]^7'):format(RES), ...) end
end

function Utils.Warn(msg)
    print(('^3[%s] %s^7'):format(RES, msg))
end

--- Trim, strip control characters and cap the length. Returns nil for empty input.
function Utils.Sanitize(value, maxLen)
    if value == nil then return nil end
    local s = tostring(value):gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

function Utils.Contains(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

-- Lookups built from the ordered config arrays
Utils.PriorityIndex = {}
for i, p in ipairs(Config.Priorities) do Utils.PriorityIndex[p.id] = i end

Utils.StatusById = {}
for _, s in ipairs(Config.UnitStatuses) do Utils.StatusById[s.id] = s end

function Utils.ValidPriority(id)
    if id and Utils.PriorityIndex[id] then return id end
    return nil
end

function Utils.PriorityDef(id)
    local i = Utils.PriorityIndex[id]
    return i and Config.Priorities[i] or nil
end

--- Accepts a status id ('available') or its radio code ('10-8').
function Utils.ResolveStatus(value)
    if not value then return nil end
    value = tostring(value):lower()
    if Utils.StatusById[value] then return value end
    for _, s in ipairs(Config.UnitStatuses) do
        if s.code and s.code:lower() == value then return s.id end
    end
    return nil
end

function Utils.ServiceEnabled(id)
    return id ~= nil and Services[id] ~= nil and Services[id].enabled == true
end

--- Call type is valid when the service lists it; with no service, any listed type is accepted.
function Utils.ValidCallType(service, callType)
    if callType == 'general' then return 'general' end
    if not callType then return nil end
    if service and Services[service] then
        return Utils.Contains(Services[service].callTypes, callType) and callType or nil
    end
    for _, s in pairs(Services) do
        if Utils.Contains(s.callTypes, callType) then return callType end
    end
    return nil
end

--- Accepts vector3, {x,y,z} or {1,2,3}; returns a plain table (safe for JSON/NUI).
function Utils.Coords(c)
    if type(c) ~= 'table' and type(c) ~= 'vector3' and type(c) ~= 'vector4' then return nil end
    local x = tonumber(c.x or c[1])
    local y = tonumber(c.y or c[2])
    local z = tonumber(c.z or c[3]) or 0.0
    if not x or not y then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
end

function Utils.Distance2D(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
