-- Template for integrating another dispatch / MDT script.
-- Copy to server/integrations/<script>.lua, add a block to config/integrations.lua
-- and remove the `do return end` below.
do return end

local cfg = Integrations and Integrations['my-dispatch']
if not cfg or cfg.enabled == false then return end

-- Inbound: listen to the event the other script receives its alerts on and mirror them.
RegisterNetEvent('my-dispatch:server:newAlert', function(data)
    if type(data) ~= 'table' or data.pessimi42Origin then return end -- skip our own outbound alerts
    Calls.Create({
        service = 'police',
        type = 'general',
        priority = 'C',
        message = data.message,
        coords = data.coords,
        street = data.street,
        origin = 'my-dispatch',
    }, { skipFallback = true }) -- the other script already alerted its units
end)

-- Outbound: let a service use it via notify = { 'my-dispatch' }
Adapters.Register('my-dispatch', {
    assign = function(call, srcs)
        -- exports['my-dispatch']:SendTo(srcs, { ... , pessimi42Origin = true })
    end,
    broadcast = function(call, srcs)
    end,
})
