# pessimi42_dispatch – Emergency dispatcher (112)

> **Beta (0.9.0-beta).** Core features work, but it has not been battle-tested on live
> servers yet. Please report problems in [Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

A dispatcher job for FiveM that runs on **Qbox, QBCore and ESX** (or standalone with ACE
permissions). Players call 112, a dispatcher triages the call and assigns police or EMS
units, mechanics, or handles advice calls on the phone. Fire is included but switched off.
When no dispatcher is on duty, calls go automatically to the nearest available unit.

No database needed (calls are saved with oxmysql if you have it, otherwise in the
resource's own store) and no build step: plain Lua + HTML/CSS/JS. `ox_lib` is used for
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

**Caller location:** 112 calls and texts are placed at the caller's position. While the call
is open, the location **follows the caller** automatically (checked every 10 s, updated after
25 m of movement, for up to 30 min) – the dispatcher's map, the units' GPS route and the street
name update with it. Dispatchers can also press **Locate caller** to refresh it immediately.
Settings in `Config.Location`; `requirePhone = true` only locates callers with an equipped phone.

**Task classes and urgency:** EMS calls use task classes modelled on the Finnish emergency
response centre (cardiac arrest, stroke, childbirth, drowning…). Each class has a default
urgency (`typePriority` in `config/services.lua`); A = immediate, life-threatening,
B = immediate, C = within 30 min, D = within 2 h. NPC units use lights and sirens on A and B.

**Call lifecycle:** `received` (new) → `pending` (waiting: the dispatcher has done the first
handling and moves it there with *Move to waiting*) → `broadcast` (units requested) → `active`
(unit assigned) → `closed`. A received call can also be dispatched straight away.

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
- **Only with a dispatcher on duty, and only when no responders are playing:** AI calls are
  generated only while a dispatcher is on duty and no player is on duty as police, EMS,
  fire or mechanic. As soon as any of them clocks in, AI calls stop. (`requireDispatcher`,
  `playersOnDuty` – set it to `'service'` to only skip the services that have players)
- About a quarter arrive as texts. When the dispatcher texts an AI caller, the caller
  answers. Nothing is sent to real phones.
- AI calls are marked **AI** on the panel (`showBadge = false` hides it).
- Drowning calls come from waterside spots – beaches, the Alamo Sea, rivers, lakes and
  canals (`config/waterside.lua`) – and the patient is found on the shoreline. Any call type
  can have its own places with `typeLocations`.
- **Create one now:** `/aicall [police|ems|fire|mechanic]` (same permission as the switch).

**Testing:** `/aicalls fast` switches to a fast pace – an AI call every 30–60 seconds with
no quiet time (`Config.AiCalls.fast`) – and `/aicalls normal` switches back. The panel shows
"AI calls: On (fast)" while it's on, and it's remembered across restarts.
`/aicalls status` shows in the chat whether calls are being generated, and if not, why
(AI calls off, no dispatcher on duty, responder players on duty, quiet time, too many open).

Everything is configurable in `Config.AiCalls`: timings, services and their weights, call
types and priorities, caller names and locations. Caller messages are in the locale files
(`aicall.*`), written in the server's default language.

### NPC scenes

AI calls aren't just text: when a player comes near (150 m), the scene the caller described
appears, and the responding units have something to do there.

| Call | At the scene | Handled by |
|---|---|---|
| Collapse, chest pain, breathing, overdose, injury | patient on the ground, bystander on the phone | EMS: **E** to treat |
| Traffic accident | damaged car, injured driver | EMS: **E** to treat |
| Robbery, assault, theft, suspicious… | witness on the phone | Police: **E** for a statement |
| Shots fired | victim crouching in cover | Police: **E** for a statement |
| Vehicle / building / wildfire | burning car or fires | putting the fires out |
| Breakdown, tow, flat tyre | broken car, hood open, driver waiting | Mechanic: **E** to repair |

Treatments, statements and repairs are logged in the call's notes. NPC units handle scenes
too (an NPC medic treats the patient). NPCs are removed when the call closes, and player calls
never get NPCs. Configure in `Config.Scenes`.

## NPC units

When no player unit can take a call, an NPC unit responds instead: an ambulance, fire truck
or tow truck drives to the scene and does its job – with blue lights and sirens on A and B
calls, without them and at normal speed on C and D calls (`sirenPriorities`). NPC police only work in the
dispatch system – they are dispatched, arrive and secure the scene on the panel, but don't
come to the scene in person (`visible = false`; set it to `true` to have patrol cars drive in).

| Service | On scene |
|---|---|
| Police | secures the scene for a while (panel only) |
| EMS | revives every downed or injured player within 20 m of the scene through your medical script |
| Fire | puts out fires around the scene |
| Mechanic | repairs the nearest vehicle – only for calls made by players, and only when no player mechanic is on duty |

- **Players come first:** AI is only used when nobody of that service is on duty. As soon
  as a police officer or medic clocks in, their service gets no more NPC units. (Set
  `trigger = 'no_available'` to also use AI when units are on duty but all busy, or
  `trigger = 'always'` to send AI to any call left without a unit.)
- **Automatic** when no dispatcher is on duty: a call that still has no unit after
  `waitSeconds` (default 45 s) gets an NPC unit. With a dispatcher on duty this only
  happens if `autoWithDispatcher = true`. If no NPC unit can be sent, the reason is added
  to the call's notes.
- **Dispatchers** can send one with **Send NPC unit** in the call details – the button only
  appears when nobody of that service is on duty.
- The caller (or the nearest player) controls the NPCs. If nobody is near the call, the
  unit still arrives after a short delay and does its job, just without visible NPCs –
  until someone comes near: a player who approaches while it's on its way sees it drive in
  with sirens, and a player who reaches a scene where it's already working sees the vehicle
  (lights on) and crew there. (`handOver`, `visibleOnScene`)
- The call is closed when the NPC unit leaves, unless players are working it too.
- Revive works out of the box with qbx_medical, qb-ambulancejob and esx_ambulancejob. For
  other medical scripts set `Config.AiUnits.reviveEvent`.

Everything is configurable in `Config.AiUnits` (vehicles, peds, timings, limits, per service).

**Vehicle and ped models** can be lists – the first model that spawns and stays is used.
Many Qbox/QBCore servers blacklist `s_m_y_cop_01` and `firetruk` (smallresources) and
delete them on spawn; the defaults already fall back to allowed models, but if an NPC unit
never appears, check that its models aren't blacklisted on your server.

## Saving calls

Calls a dispatcher makes on the panel are saved, so they survive a restart and stay as
history (`Config.Storage`):

- `backend = 'auto'` uses **oxmysql** when it is running – the table
  `pessimi42_dispatch_calls` is created automatically – and otherwise the resource's own
  key-value store, which needs no setup. `'oxmysql'`, `'kvp'` or `'none'` (memory only) pick
  one.
- After a restart, open saved calls come back to the panel (without units, back in the
  queue), the newest closed ones to the history, and call numbers continue where they were.
- `origins` chooses which calls are saved: `dispatcher` by default; add `['112']`, `sms`,
  `alert`, `api`, or `all = true`. `saveAi = true` saves AI calls too.
- Closed calls older than `keepDays` (30) are deleted at start.
- Changes are written in batches every few seconds and when the resource stops.

In the database each call is a row with searchable columns (service, type, priority, status,
origin, created by, times) and the whole call as JSON in `data`, ready for an MDT or a
report page. Another storage (an MDT's own database, an HTTP API…) is one small table in
`server/storage.lua` – see the comment at the top.

## Testing

Set `Config.TestMode = true` (top of `config/config.lua`) to try everything quickly: an AI
call every 30–60 seconds even with nobody on duty, NPC units after 10 seconds (also when
players of the service are on duty) and debug prints in the server console and F8. Turn it
off again on a live server.

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

`allowedPriorities` limits which classes a service's calls can have, with labels of its
own (`priority_<service>.<class>` in the locales). Mechanic calls are
**C – disrupting traffic** or **D – not affecting other road users**; anything higher is
moved to C.

**Advice** (`advice`, *Neuvonta*) is for calls that need guidance, not a unit – task class
*phone advice*, always D. The dispatcher answers by text or on the phone and closes the call;
nobody is sent and there is no NPC unit. When no dispatcher is on duty, the caller gets a
text that advice is not available right now – with an emergency they should call 112 again –
and the call is closed (`unavailableReply`). To let players take these calls (a nurse line,
for example), add their job to `jobs` in its block.

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
IncomingSms, SendAiUnit, GetAiUnits, GenerateAiCall, SetAiCalls, AreAiCallsEnabled, LocateCaller,
ResolveScene`.

Server events (`AddEventHandler`): `pessimi42_dispatch:onCallCreated / onCallUpdated / onCallClosed /
onUnitAssigned / onUnitUnassigned / onUnitStatus / onUnitAdded / onUnitRemoved / onAiSent /
onSceneHandled`.

Client exports: `CreateAlert, OpenCallerForm, IsDispatcher, GetService, GetMyCall, GetStatus`.

## Notes

- Calls live in memory and reset on restart; callsigns persist (resource KVP).
- Every panel action is re-checked on the server (dispatcher role), 112 calls are
  rate-limited and use the server-side player position.

## License

[GPL-3.0](LICENSE). You may use, modify and share this resource. If you distribute it or a
modified version, you must make the source code available under the same licence. Running
it on your own server is not distribution. Releases up to 0.9.0-beta were published under
AGPL-3.0.
