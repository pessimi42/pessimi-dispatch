-- Bridges to the dispatch/alert scripts your police and EMS already use.
--
-- inbound  = alerts sent to that script also appear on the dispatcher panel
-- outbound = register the script as an adapter; then add its name to a
--            service's `notify` list (config/services.lua) to push assignments
--            and broadcasts into that script's UI.
--
-- enabled = 'auto' turns the integration on only when the resource is started.

Integrations = {
    ['ps-dispatch'] = {
        enabled = 'auto',
        inbound = true,
        outbound = true,
        codeName = 'pessimi42_dispatch',             -- add a Config.Blips entry with this name in ps-dispatch for a custom blip
        ignoreCodeNames = { 'platecheck' },   -- inbound alerts to skip
        inboundCooldown = 3,                  -- seconds per player (anyone can send these)
        -- ps-dispatch `jobs` entries -> our service ids
        jobMap = {
            leo = 'police', police = 'police', sheriff = 'police',
            ems = 'ems', ambulance = 'ems',
            fire = 'fire',
            mechanic = 'mechanic',
        },
    },
}
