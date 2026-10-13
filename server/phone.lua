-- Phone layer. A provider is a table with these functions (all optional except detect):
--   detect()                    -> bool   is this phone running?
--   getNumber(src)              -> string|nil  the player's phone number (nil = no phone)
--   getSource(number)           -> number|nil  online player owning a number
--   sendSms(from, to, text)     -> bool   send a text message from `from` to `to`
--   sendCoords(from, to, coords)          send a location message
--   notify(to, title, text)               phone notification (fallback when SMS fails)
-- Providers call Sms.Incoming(senderNumber, text) when someone texts Config.Phone.number.

Phone = { providers = {}, order = {} }

function Phone.Register(name, impl)
    if type(name) ~= 'string' or type(impl) ~= 'table' or type(impl.detect) ~= 'function' then return false end
    if not Phone.providers[name] then Phone.order[#Phone.order + 1] = name end
    Phone.providers[name] = impl
    Utils.Debug('phone provider registered', name)
    return true
end

--- The provider in use right now, or nil.
function Phone.Active()
    local want = Config.Phone.provider
    if want == 'none' then return nil end
    if want and want ~= 'auto' then
        local p = Phone.providers[want]
        return (p and p.detect()) and p or nil, want
    end
    for _, name in ipairs(Phone.order) do
        local p = Phone.providers[name]
        if p.detect() then return p, name end
    end
    return nil
end

local function call(fnName, ...)
    local p = Phone.Active()
    if not p or not p[fnName] then return nil end
    local ok, res = pcall(p[fnName], ...)
    if not ok then
        Utils.Warn(('phone.%s failed: %s'):format(fnName, res))
        return nil, true
    end
    return res
end

function Phone.GetNumber(src)
    local n = call('getNumber', src)
    return n and tostring(n) or nil
end

function Phone.GetSource(number)
    return call('getSource', number)
end

--- True if a phone is running and the player has one equipped.
function Phone.HasPhone(src)
    return Phone.Active() ~= nil and Phone.GetNumber(src) ~= nil
end

--- Send a text; falls back to a phone notification if the phone refuses it.
function Phone.SendSms(to, text)
    if not to or not text then return false end
    local from = Config.Phone.number
    local res, failed = call('sendSms', from, to, text)
    if failed or res == false then
        call('notify', to, from, text)
        return false
    end
    return true
end

function Phone.SendCoords(to, coords)
    if not to or not coords then return end
    call('sendCoords', Config.Phone.number, to, coords)
end

--- Phone number for a player: phone script first, framework second.
function GetPhoneNumber(src)
    return Phone.GetNumber(src) or Bridge.GetPhone(src)
end
