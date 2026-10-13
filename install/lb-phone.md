# lb-phone

pessimi42_dispatch detects lb-phone automatically (`Config.Phone.provider = 'auto'`).
Start it **after** lb-phone in `server.cfg`:

```
ensure lb-phone
ensure pessimi42_dispatch
```

With lb-phone running you get:

- **Text 112** – players text `112` (`Config.Phone.number`) from the Messages app. The text
  becomes a new call, or is added to their open call.
- **SMS from the dispatch centre** – automatic "received", "help is on the way" and
  "case closed" texts, plus quick replies and free text from the dispatcher panel. Texts
  are written in the caller's own language.
- **Units** get the call details and a location pin as SMS when assigned.
- **Correct phone numbers** on the panel, and optionally `Config.Phone.requirePhone = true`
  so only players with an equipped phone can call 112.

If lb-phone refuses a message (for example it does not accept `112` as a sender), the
text is shown as a phone notification titled "112" instead.

## Optional: 112 app on the phone

Adds a 112 icon to the phone that opens the emergency call form. Add this inside
`Config.CustomApps` in `lb-phone/config/config.lua` (compare with the example in that
file / the [lb-phone custom apps docs](https://docs.lbscripts.com/phone/custom-apps/) –
field names can change between lb-phone versions):

```lua
["pessimi42_112"] = {
    name = "112",
    description = "Emergency number",
    icon = "https://cfx-nui-pessimi42_dispatch/web/112.svg",
    defaultApp = true,
    onUse = function()
        exports.pessimi42_dispatch:OpenCallerForm()
    end,
},
```

Restart lb-phone after editing its config.
