-- Caller location: automatic tracking while a call is open, and on-demand
-- "Locate caller" for dispatchers. Positions are read on the server only.

Location = {}

local cfg = Config.Location

local function callerSrc(call)
    local src = call._callerSrc
    if not src or call._ai or not GetPlayerName(src) then return nil end
    if cfg.requirePhone and Phone.Active() and not Phone.HasPhone(src) then return nil end
    return src
end

local function positionOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return Utils.Coords(GetEntityCoords(ped))
end

--- Can this call's caller be located right now?
function Location.CanLocate(call)
    return call.status ~= 'closed' and callerSrc(call) ~= nil
end

--- Is the call's location following the caller?
function Location.Tracking(call)
    return cfg.track and Location.CanLocate(call)
        and (os.time() - call.createdAt) < cfg.maxMinutes * 60
end

--- Move the call to the caller. `force` ignores minMove. Returns true if the location changed.
function Location.Update(call, force)
    local src = callerSrc(call)
    if not src then return false end
    local pos = positionOf(src)
    if not pos then return false end
    if call.coords and not force and Utils.Distance2D(pos, call.coords) < cfg.minMove then return false end
    call.coords = pos
    call.street = nil          -- resolved again on the clients from the new position
    call.locatedAt = os.time()
    Calls.Touch(call)
    return true
end

--- Dispatcher pressed "Locate caller".
function Location.Locate(callId)
    local call = Calls.Get(callId)
    if not call or not Location.CanLocate(call) then return false end
    Location.Update(call, true)
    Calls.AddNote(call.id, 'loc.note_located', nil, 'sys')
    return true
end

CreateThread(function()
    while true do
        Wait(cfg.interval * 1000)
        if cfg.track then
            for _, call in pairs(Calls.list) do
                if call.status ~= 'closed' and Location.Tracking(call) then
                    Location.Update(call, false)
                end
            end
        end
    end
end)
