-- Outbound adapters decide HOW units hear about calls. Every service lists the
-- adapters it wants in Services[id].notify. Units always get the call state
-- (waypoint, HUD, on-scene detection) regardless of which adapter alerts them.
--
-- An adapter is a table with optional functions:
--   assign(call, unitSrcs)     dispatcher assigned these units
--   broadcast(call, unitSrcs)  units of a service were asked to respond
-- `call` is the public call table (coords as {x,y,z}).

Adapters = { registry = {} }

function Adapters.Register(name, impl)
    if type(name) ~= 'string' or type(impl) ~= 'table' then return false end
    Adapters.registry[name] = impl
    Utils.Debug('adapter registered', name)
    return true
end

local function route(kind, call, srcs)
    local groups = {}
    for _, src in ipairs(srcs) do
        local unit = Units.Get(src)
        local svc = unit and Services[unit.service]
        for _, name in ipairs(svc and svc.notify or { 'native' }) do
            groups[name] = groups[name] or {}
            groups[name][#groups[name] + 1] = src
        end
    end

    local pub = Calls.Public(call)
    for name, targets in pairs(groups) do
        local adapter = Adapters.registry[name]
        if not adapter then
            Utils.Warn(('unknown notify adapter "%s" – falling back to native'):format(name))
            adapter = Adapters.registry.native
        end
        if adapter[kind] then
            local ok, err = pcall(adapter[kind], pub, targets)
            if not ok then Utils.Warn(('adapter %s.%s failed: %s'):format(name, kind, err)) end
        end
    end
end

function Adapters.Assign(call, srcs) route('assign', call, srcs) end
function Adapters.Broadcast(call, srcs) route('broadcast', call, srcs) end

-- Built-in: toast + sound in our own NUI
Adapters.Register('native', {
    assign = function(call, srcs)
        for _, src in ipairs(srcs) do TriggerClientEvent(Ev('client:alert'), src, 'assigned', call) end
    end,
    broadcast = function(call, srcs)
        for _, src in ipairs(srcs) do TriggerClientEvent(Ev('client:alert'), src, 'broadcast', call) end
    end,
})
