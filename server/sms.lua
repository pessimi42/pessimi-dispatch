-- SMS between the dispatch centre, callers and units. Everything here is a
-- no-op without a phone; callers then get the old on-screen notifications.

Sms = {}
PlayerLang = {}   -- [src] = language chosen on the client

local function langOf(src)
    return (src and PlayerLang[src]) or Config.Locale
end

function Sms.Available()
    return Config.Sms.enabled and Phone.Active() ~= nil
end

--- Number to text for a call, or nil.
function Sms.CallerNumber(call)
    return call and call.caller and call.caller.phone or nil
end

--- AI calls have no real phone: texts are only logged, and the "caller" may reply.
local function isAi(call) return call and call._ai end

local function caller(call)
    local src = call._callerSrc
    if src and not GetPlayerName(src) then src = nil end
    return src
end

--- Text the caller. `text` is final, or nil to use `key`/`vars` in the caller's language.
--- Returns the text that was sent, or nil.
function Sms.ToCaller(call, text, key, vars, author)
    local number = Sms.CallerNumber(call)
    if not number or (not isAi(call) and not Sms.Available()) then return nil end
    text = text or Locale.T(key, vars, langOf(caller(call)))
    text = Utils.Sanitize(text, Config.Sms.maxLength)
    if not text then return nil end
    if isAi(call) then
        -- only dispatcher messages get an answer, not automatic ones
        if author and author ~= Config.Phone.number then AiCalls.OnDispatcherSms(call) end
    else
        Phone.SendSms(number, text)
    end
    Calls.AddNote(call.id, text, author or Config.Phone.number, 'sms_out')
    return text
end

--- Automatic caller messages: 'received' | 'assigned' | 'closed'.
--- `fallbackKey` is shown on screen to an online caller when no SMS could be sent.
function Sms.AutoCaller(call, event, fallbackKey)
    if Config.Sms.auto[event] and Sms.ToCaller(call, nil, 'sms.' .. event, { id = call.id }) then
        return true
    end
    local src = caller(call)
    if src and fallbackKey then Notify(src, fallbackKey, nil, 'success') end
    return false
end

--- Call details + location to a unit that was just assigned.
function Sms.ToUnit(src, call)
    if not Config.Sms.toUnits or not Sms.Available() then return end
    local number = Phone.GetNumber(src)
    if not number then return end
    local lang = langOf(src)
    local text = Locale.T('sms.unit_details', {
        id = call.id,
        priority = call.priority,
        type = Locale.T('calltype.' .. call.type, nil, lang),
        street = call.street or Locale.T('ui.unknown_location', nil, lang),
        message = call.message ~= '' and call.message or '-',
    }, lang)
    Phone.SendSms(number, Utils.Sanitize(text, Config.Sms.maxLength))
    if call.coords then Phone.SendCoords(number, call.coords) end
end

--- Open call where this number (or player) is the caller, newest first.
local function openCallFor(number, src)
    local best
    for _, c in pairs(Calls.list) do
        if c.status ~= 'closed' and ((number and Sms.CallerNumber(c) == number) or (src and c._callerSrc == src)) then
            if not best or c.id > best.id then best = c end
        end
    end
    return best
end

local lastNewCall = {}

--- Someone texted Config.Phone.number.
function Sms.Incoming(number, text)
    if not Config.Sms.enabled or not Config.Sms.incoming then return end
    number = number and tostring(number)
    text = Utils.Sanitize(text, Config.Sms.maxLength)
    if not number or not text then return end

    local src = Phone.GetSource(number)
    if src and not GetPlayerName(src) then src = nil end
    local name = src and Bridge.GetCharName(src) or nil

    local open = openCallFor(number, src)
    if open then
        Calls.AddNote(open.id, text, name or number, 'sms_in')
        return open.id
    end

    local t = os.time()
    if lastNewCall[number] and t - lastNewCall[number] < Config.Sms.incomingCooldown then return end
    lastNewCall[number] = t

    local coords
    if src then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then coords = Utils.Coords(GetEntityCoords(ped)) end
    end

    return Calls.Create({
        message = text,
        coords = coords,
        caller = { name = name, phone = number },
        origin = 'sms',
        callerSrc = src,
    }, { smsReceived = true })
end

RegisterNetEvent(Ev('server:lang'), function(code)
    local src = source
    if type(code) == 'string' and Utils.Contains(Config.Languages, code) then
        PlayerLang[src] = code
    end
end)

AddEventHandler('playerDropped', function()
    PlayerLang[source] = nil
end)
