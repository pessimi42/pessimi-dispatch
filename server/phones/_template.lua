-- Template for another phone script. Copy to server/phones/<phone>.lua and
-- remove the `do return end` below. Set Config.Phone.provider = 'my-phone'
-- (or leave 'auto'). Look up the real export names in your phone's docs.
do return end

local RES = 'my-phone'

Phone.Register('my-phone', {
    detect = function() return GetResourceState(RES) == 'started' end,
    getNumber = function(src) --[[ return exports[RES]:GetNumber(src) ]] end,
    getSource = function(number) --[[ return exports[RES]:GetSource(number) ]] end,
    sendSms = function(from, to, text)
        -- exports[RES]:SendMessage(from, to, text)
        return true
    end,
    sendCoords = function(from, to, coords) end,
    notify = function(to, title, text) end,
})

-- Call Sms.Incoming(senderNumber, text) when someone texts Config.Phone.number:
-- AddEventHandler('my-phone:messageSent', function(from, to, text)
--     if tostring(to) == tostring(Config.Phone.number) then Sms.Incoming(from, text) end
-- end)
