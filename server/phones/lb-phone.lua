-- lb-phone – https://docs.lbscripts.com/phone/
-- Uses: GetEquippedPhoneNumber, GetSourceFromNumber, SendMessage, SendCoords,
-- SendNotification and the server event lb-phone:messages:messageSent.

local RES = 'lb-phone'

local function started() return GetResourceState(RES) == 'started' end

Phone.Register('lb-phone', {
    detect = started,

    getNumber = function(src)
        return exports[RES]:GetEquippedPhoneNumber(src)
    end,

    getSource = function(number)
        return exports[RES]:GetSourceFromNumber(number)
    end,

    sendSms = function(from, to, text)
        exports[RES]:SendMessage(from, to, text)
        return true
    end,

    sendCoords = function(from, to, coords)
        exports[RES]:SendCoords(from, to, vector2(coords.x, coords.y))
    end,

    notify = function(to, title, text)
        exports[RES]:SendNotification(to, { title = title, content = text })
    end,
})

-- Texts sent to our number
AddEventHandler('lb-phone:messages:messageSent', function(message)
    if type(message) ~= 'table' then return end
    if tostring(message.recipient) ~= tostring(Config.Phone.number) then return end
    local _, active = Phone.Active()
    if active ~= 'lb-phone' then return end
    Sms.Incoming(message.sender, message.message)
end)
