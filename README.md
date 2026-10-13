# pessimi42_dispatch – Emergency dispatcher (112)

> **Beta (0.3.0-beta).** Core features work, but it has not been battle-tested on live
> servers yet. Please report problems in [Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

A dispatcher job for FiveM that runs on **Qbox, QBCore and ESX** (or standalone with ACE
permissions). Players call 112, a dispatcher triages the call and assigns police or EMS
units. Fire and roadside assistance are included but switched off. When no dispatcher is
on duty, calls go automatically to the nearest available unit.

No database and no build step: plain Lua + HTML/CSS/JS. `ox_lib` is used for
notifications if it is running, otherwise the framework's own.

## Install

1. Download the latest release and put it in your resources folder **as `pessimi42_dispatch`**
   (rename the folder if needed – e.g. GitHub's zip unpacks as `pessimi-dispatch-main`).
2. Add the dispatcher job to your framework – see [`install/jobs.md`](install/jobs.md).
3. In `server.cfg`, start it **after** your framework (and after ps-dispatch if you use it):
   ```
   ensure qbx_core        # or qb-core / es_extended
   ensure pessimi42_dispatch
   ```
4. Check `config/config.lua` (language, commands, fallback) and the job names in
   `config/services.lua`.

## How it works

| Who | What |
|---|---|
| Anyone | `/112` opens the call form (pick service, describe). `/112 <text>` sends straight away. |
| Dispatcher | `F6` / `/dispatch` opens the panel: queue sorted by priority A–D, call details, reclassify service/type/priority, notes, assign units, request units (broadcast), close. `/dispatchduty` toggles duty. New calls are created at your map waypoint. |
| Units | Get a toast + sound and a GPS route when assigned. `/status available\|enroute\|onscene\|busy\|unavailable` (or radio codes like `10-8`), `/callsign P-11`, `/respond [id]` to take a broadcast call. Switches to *on scene* automatically on arrival. Small HUD card shows status and current call. |

**Call lifecycle:** `pending` → `broadcast` (units requested) → `active` (unit assigned) → `closed`.

### No dispatcher on duty (`Config.Fallback`)

- `mode = 'nearest'` (default): the call is assigned to the nearest **available** unit of
  the call's service. Distance is checked server-side once, at that moment – no
  positions are tracked or shown anywhere. "Not sure" calls use `unspecifiedService`.
- Nobody free (or further than `maxDistance`) → broadcast to all on-duty units of the
  service, who can `/respond`.
- The last unit setting itself *available* closes the call; a unit that disconnects
  hands its call to the next nearest unit.
- When the last dispatcher goes off duty, everything still waiting in the queue is
  auto-dispatched the same way.
- `mode = 'broadcast'` or `'none'` if you prefer that.

## AI calls

When players aren't calling 112, the server generates realistic emergency calls and texts so
on-duty units and dispatchers have something to do: robberies, collapses, car fires,
breakdowns and more, at locations around the map, from callers with names and numbers.

- **On/off switch:** `/aicalls` toggles, `/aicalls on` / `/aicalls off` sets it. On-duty
  dispatchers can also use the **AI calls** button in the panel header. Admins need the
  ACE permission `pessimi42_dispatch.admin`:
  ```
  add_ace group.admin pessimi42_dispatch.admin allow
  ```
  The choice is remembered across restarts.
- **Only when it's quiet:** a call is generated every 3–8 minutes, and only if no player
  has called or texted 112 for 5 minutes (`quietMinutes`). At most 3 AI calls are open at
  once.
- **Only when someone can respond:** a dispatcher on duty, or units of the call's service.
- About a quarter arrive as texts. When the dispatcher texts an AI caller, the caller
  answers. Nothing is sent to real phones.
- AI calls are marked **AI** on the panel (`showBadge = false` hides it).

Everything is configurable in `Config.AiCalls`: timings, services and their weights, call
types and priorities, caller names and locations. Caller messages are in the locale files
(`aicall.*`), written in the server's default language.

## AI units

When no player unit can take a call, an NPC unit responds instead: a patrol car, ambulance,
fire truck or tow truck drives to the scene with sirens and does its job.

| Service | On scene |
|---|---|
| Police | secures the scene for a while |
| EMS | treats the caller – revives them through your medical script |
| Fire | puts out fires around the scene |
| Mechanic | repairs the nearest vehicle |

- **Players come first:** AI is only used when nobody of that service is on duty. As soon
  as a police officer or medic clocks in, their service gets no more AI units. (Set
  `trigger = 'no_available'` to also use AI when units are on duty but all busy.)
- **Automatic** when no dispatcher is on duty: a call that still has no unit after
  `waitSeconds` (default 45 s) gets an AI unit.
- **Dispatchers** can send one with **Send AI unit** in the call details – the button only
  appears when nobody of that service is on duty.
- The caller (or the nearest player) controls the NPCs. If nobody is near the call, the
  unit still arrives after a short delay and does its job, just without visible NPCs.
- The call is closed when the AI unit leaves, unless players are working it too.
- Revive works out of the box with qbx_medical, qb-ambulancejob and esx_ambulancejob. For
  other medical scripts set `Config.AiUnits.reviveEvent`.

Everything is configurable in `Config.AiUnits` (vehicles, peds, timings, limits, per service).

## Phone & SMS (lb-phone)

With [lb-phone](https://lbscripts.com) running, players can text **112**, callers get
automatic texts ("received", "help is on the way", "case closed"), the dispatcher can
send quick replies or free text from the panel, and assigned units get the call details
and a location pin by SMS. Texts are written in each player's own language, and all SMS
show up in the call's notes. Optional 112 app on the phone – see
[`install/lb-phone.md`](install/lb-phone.md).

Without a supported phone everything works as before with on-screen notifications.
Other phones can be added with `exports.pessimi42_dispatch:RegisterPhone()` or by copying
`server/phones/_template.lua`.

## Languages

English, Finnish and Swedish are included. Each player can switch with
`/dispatchlang fi|sv|en` (or the selector in the panel) – useful on bilingual servers.
Server messages are sent as keys and translated on the player's own client.

**Adding a language:** copy `locales/en.json` to e.g. `locales/de.json`, translate the
values (keep the keys and `{placeholders}`), set `_meta.name`, and add `'de'` to
`Config.Languages`. Missing keys fall back to `Config.Locale`, then English.

## Adding a service (fire, mechanic, anything)

Fire and mechanic are already in `config/services.lua` – set `enabled = true` and check
the job names. For a brand new service, add a block there and add `service.<id>` and its
`calltype.<key>` strings to the locale files. Everything else (panel, filters, caller
form, blips, fallback) picks it up automatically.

## Integrating with police/EMS dispatch scripts and MDTs

**ps-dispatch** (`config/integrations.lua`, on automatically when ps-dispatch runs):
- *Inbound*: every ps-dispatch alert (robberies, shots fired…) also appears on the
  dispatcher panel. ps-dispatch has already alerted the units, so it is not re-sent.
- *Outbound*: set `notify = { 'ps-dispatch' }` (or `{ 'native', 'ps-dispatch' }`) on a
  service and assignments/broadcasts show up in the ps-dispatch UI your units already use.

**Other scripts:** copy `server/integrations/_template.lua`, or from any resource:

```lua
-- server
exports.pessimi42_dispatch:RegisterAdapter('my-mdt', {
    assign = function(call, unitSrcs) --[[ push into your MDT ]] end,
    broadcast = function(call, unitSrcs) end,
})
local id = exports.pessimi42_dispatch:CreateCall({ service = 'ems', type = 'unconscious', priority = 'A', message = '...', coords = coords })

-- client (automatic alerts from robbery scripts etc.)
exports.pessimi42_dispatch:CreateAlert({ service = 'police', type = 'robbery', priority = 'B', message = 'Store alarm' })
```

Server exports: `CreateCall, GetCall, GetCalls, UpdateCall, AddNote, AssignUnit, UnassignUnit,
BroadcastCall, AutoDispatch, CloseCall, GetUnit, GetUnits, SetUnitStatus, FindNearestUnit,
IsDispatcherOnDuty, IsDispatcher, RegisterAdapter, RegisterService, RegisterPhone, SmsCaller,
IncomingSms, SendAiUnit, GetAiUnits, GenerateAiCall, SetAiCalls, AreAiCallsEnabled`.

Server events (`AddEventHandler`): `pessimi42_dispatch:onCallCreated / onCallUpdated / onCallClosed /
onUnitAssigned / onUnitUnassigned / onUnitStatus / onUnitAdded / onUnitRemoved / onAiSent`.

Client exports: `CreateAlert, OpenCallerForm, IsDispatcher, GetService, GetMyCall, GetStatus`.

## Notes

- Calls live in memory and reset on restart; callsigns persist (resource KVP).
- Every panel action is re-checked on the server (dispatcher role), 112 calls are
  rate-limited and use the server-side player position.

## License

[AGPL-3.0](LICENSE). You may use and modify this resource; if you distribute it or run a
modified version on a server others play on, you must make your source code available
under the same licence.
