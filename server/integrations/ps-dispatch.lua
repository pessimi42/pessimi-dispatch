-- ps-dispatch (Project Sloth) – https://github.com/Project-Sloth/ps-dispatch
--
-- Inbound:  every alert sent through 'ps-dispatch:server:notify' is mirrored to
--           the dispatcher panel. ps-dispatch has already alerted the units, so
--           we do not broadcast it again.
-- Outbound: adapter 'ps-dispatch' sends our assignments/broadcasts into the
--           ps-dispatch UI with SendTargetedAlert. Enable it per service with
--           notify = { 'ps-dispatch' } (or { 'native', 'ps-dispatch' }).

local cfg = Integrations and Integrations['ps-dispatch']
if not cfg or cfg.enabled == false then return end

local RES = 'ps-dispatch'

local function active()
    return GetResourceState(RES) == 'started'
end

-- ps-dispatch: 0 critical, 1 urgent, 2 routine, 3 low  <->  A B C D
local toOurs = { [0] = 'A', [1] = 'B', [2] = 'C', [3] = 'D' }
local toTheirs = { A = 0, B = 1, C = 2, D = 3 }

local function mapService(jobs)
    if type(jobs) == 'string' then jobs = { jobs } end
    if type(jobs) ~= 'table' then return nil end
    for _, job in ipairs(jobs) do
        local s = cfg.jobMap[job]
        if s and Utils.ServiceEnabled(s) then return s end
    end
    return nil
end

if cfg.inbound then
    RegisterNetEvent('ps-dispatch:server:notify', function(data)
        local src = source
        if type(data) ~= 'table' or data.pessimi42Origin then return end
        if cfg.enabled == 'auto' and not active() then return end
        if data.codeName and Utils.Contains(cfg.ignoreCodeNames, data.codeName) then return end

        local coords = data.coords or (src and src > 0 and GetEntityCoords(GetPlayerPed(src)))
        Calls.Create({
            service = mapService(data.jobs),
            type = 'general',
            priority = toOurs[tonumber(data.priority) or 2],
            message = data.message,
            information = data.information,
            code = data.code,
            coords = coords,
            street = data.street,
            caller = (data.name or data.number) and { name = data.name, phone = data.number } or nil,
            origin = 'ps-dispatch',
            meta = { codeName = data.codeName },
        }, { skipFallback = true })
    end)
end

if cfg.outbound then
    local function send(call, srcs, assigned)
        if not active() then return end
        local c = call.coords
        exports[RES]:SendTargetedAlert(srcs, {
            message = (call.message ~= '' and call.message) or Locale.T('calltype.' .. call.type),
            codeName = cfg.codeName or 'pessimi42_dispatch',
            code = call.code or ('112-' .. call.id),
            icon = 'fas fa-headset',
            priority = toTheirs[call.priority] or 2,
            coords = c and vector3(c.x, c.y, c.z) or nil,
            street = call.street,
            information = call.information,
            name = call.caller and call.caller.name or nil,
            number = call.caller and call.caller.phone or nil,
            assigned = assigned,
            pessimi42Origin = true,
        })
    end

    Adapters.Register('ps-dispatch', {
        assign = function(call, srcs) send(call, srcs, true) end,
        broadcast = function(call, srcs) send(call, srcs, false) end,
    })
end
