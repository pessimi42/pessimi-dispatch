# Changelog

## v0.9.0-beta – Saved calls, Advice service, received/waiting calls (2026-10-15)

Calls survive restarts, a new Advice service for calls handled on the phone, and a call flow
closer to a real emergency centre: new calls are *Received* and wait after first handling.
Still a beta – please report problems in [Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### New

- **Calls are saved.** Calls a dispatcher makes on the panel are saved to the database
  (oxmysql, table created automatically) or, without one, the resource's own key-value
  store. After a restart they come back to the panel and the history, and call numbers
  continue. Which calls are saved, how long they are kept and the backend are set in
  `Config.Storage`; other storages can be added in `server/storage.lua`.
- Dispatcher-made calls remember who made them (`createdBy`).
- **New service: Advice (Neuvonta / Rådgivning).** Calls that need guidance rather than a
  unit, with the task class *Phone advice* (Puhelinneuvonta), always D. The dispatcher
  answers by text or on the phone and closes the call; nobody is sent. AI calls include
  advice calls too (weight 1), where the caller answers the dispatcher's texts.
  When no dispatcher is on duty, the caller gets a text that advice is not available right
  now (call 112 again in an emergency) and the call is closed (`unavailableReply`).

### Changed

- **New calls are "Received".** A new call now starts as *Received* (highlighted on the
  panel). After the first handling the dispatcher can move it to *Waiting* with **Move to
  waiting** (logged in the notes), to dispatch later; it can also be dispatched or have units
  requested straight away. When the last dispatcher goes off duty, received and waiting calls
  are both auto-dispatched. New export `SetCallWaiting(id)`.
- **Call list order.** Waiting calls (received, waiting, units requested) are on top – most
  urgent first, and within the same class the oldest first – under a *Waiting* heading.
  Calls in progress follow under their own heading, newest first.
- **Texting on every call.** The panel's text section used to be hidden when a call had no
  caller number – e.g. alerts from ps-dispatch or scripts, or calls the dispatcher made –
  so only notes were shown. Now every open call has it: when the number is missing the
  dispatcher can type it in and then text the caller, and when the server has no supported
  phone the section says so.
- The mechanic service is now called **Mechanic** (fi *Mekaanikko*, sv *Mekaniker*) instead
  of Roadside Assistance / Tiepalvelu / Vägassistans.

### Upgrading from 0.8.1-beta

Replace the resource folder. If you changed config files, carry over:

- `fxmanifest.lua` has a new line `'server/storage.lua',` (after `'server/calls.lua',`).
- `config/config.lua`: the new `Config.Storage` block – **without it nothing is saved**.
  Optional (the defaults are built in): `unavailable = true` in `Config.Sms.auto`, and for
  AI advice calls `advice = 1` in `Config.AiCalls.weights` plus
  `advice = { { type = 'phone_advice', priority = 'D' } }` in `Config.AiCalls.types`.
- `config/services.lua`: the new `advice` block (at the end).
- Locale files: new keys for the Advice service, the *Received* status, the *Move to
  waiting* button, list headings and the texting section – use the new files or copy the
  keys over.

With oxmysql running, the table `pessimi42_dispatch_calls` is created on the first start.
Calls that were open before the update are not affected (they live in memory as before).

## v0.8.1-beta – Security fixes, fast AI calls, drowning by the water (2026-10-15)

Security fixes, AI calls at a fast pace for testing, and drowning calls by the water.
Still a beta – please report problems in [Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### New

- **Fast AI calls for testing.** `/aicalls fast` switches AI calls to a fast pace – one
  every 30–60 seconds, with no quiet time after player calls and up to 5 open at once – and
  `/aicalls normal` switches back. It takes effect right away, also switches AI calls on,
  is remembered across restarts and shows as "AI calls: On (fast)" in the panel. The other
  rules still apply (a dispatcher on duty, no responder players); `Config.TestMode` remains
  for testing without them. Timings in `Config.AiCalls.fast`.
- **`/aicalls status`** – shows in the chat (or the server console) whether AI calls are
  being generated right now and, if not, the reason: switched off, no dispatcher on duty,
  responder players on duty (with their names), quiet time after a player call, or too
  many open.

### Fixed

- **Drowning calls happen by the water.** AI drowning calls used to come from random street
  corners. They now come from 115 waterside spots taken from the map – beaches, the rocky
  coast, the Alamo Sea, the Zancudo and Raton Canyon rivers, Vinewood Lake, Land Act
  Reservoir, Mirror Park and the Vespucci canals (`config/waterside.lua`). The scene is built
  on the nearest dry shoreline within 100 m: the patient lies soaking wet and unconscious,
  with the caller kneeling next to them giving first aid (`Config.Scenes.waterTypes`).
  `Config.AiCalls.typeLocations` gives any call type its own places.
- **No more NPCs on rooftops.** Scene NPCs (patients, witnesses, callers) and fires could
  end up on a roof next to the call. Every spot is now checked against the street level of
  the nearest road; a spot clearly above it is moved to the pavement instead.

### Security

- **Alerts from players' games are checked.** Script alerts (`CreateAlert`) and alerts
  arriving through ps-dispatch could be sent by anyone with a mod menu, with any position
  and – for ps-dispatch – without any limit. Now a reported position more than 150 m from
  where the server sees the player is replaced with their real position, ps-dispatch
  alerts have a per-player cooldown, and all alerts together are limited to 30 a minute
  (`Config.ClientAlerts.maxDistance`, `maxPerMinute`; `inboundCooldown` in
  `config/integrations.lua`).
- **NPC units must really arrive.** The player whose game drives an NPC unit could report
  it on scene at once, so an NPC medic revived without travelling. The server now checks
  that the unit's vehicle or crew is at the scene; if not, the unit finishes the trip on
  the server's own timer.
- **Limits against spam:** texts to an open call at most every 3 seconds per number
  (`Config.Sms.noteCooldown`), at most 100 notes per call (oldest go first,
  `Config.Calls.maxNotes`), and one call every 3 seconds per dispatcher
  (`Config.Dispatcher.createCooldown`).

### Upgrading from 0.8.0-beta

Replace the resource folder. If you changed `config/config.lua`, add
`fast = { interval = { 0.5, 1 }, quietMinutes = 0, maxOpen = 5 },` to `Config.AiCalls`
(optional – these are also the defaults). The same goes for `typeLocations = {}` in
`Config.AiCalls` and `waterTypes = { drowning = true }` in `Config.Scenes`. The waterside
spots are in the new file `config/waterside.lua`. The new security settings (`maxPerMinute`
and `maxDistance` in `Config.ClientAlerts`, `noteCooldown` in `Config.Sms`, `createCooldown`
in `Config.Dispatcher`, `maxNotes` in `Config.Calls`, `inboundCooldown` for ps-dispatch) have
the same defaults built in. Locale files have new keys `ui.fast`,
`aicalls.fast_on` and `aicalls.fast_off`.

## v0.8.0-beta – EMS task classes, roadside C/D (2026-10-14)

EMS calls use task classes modelled on the Finnish emergency response centre, each with a
default urgency, and roadside assistance has its own two classes. Still a beta – please
report problems in [Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### Changed

- **EMS task classes modelled on the Finnish emergency response centre.** EMS calls now use
  29 task classes such as cardiac arrest (elvytys), stroke, seizure, childbirth, drowning,
  stab wound, fall from height, low blood sugar and patient transfer, in English, Finnish
  and Swedish. Each class has a default urgency (`typePriority` in `config/services.lua`),
  used for new calls and when the dispatcher changes the class – the dispatcher can still
  pick another one. The A–D labels now describe response times: A immediate and
  life-threatening, B immediate, C within 30 min, D within 2 h.
- **Roadside assistance has two urgency classes: C – disrupting traffic, D – not affecting
  other road users.** Mechanic calls can be C or D (D by default); an A or B is moved to C.
  The panel only offers these two, with their own labels. New service setting
  `allowedPriorities` (replaces `fixedPriority`, which still works) and locale keys
  `priority_<service>.<class>`.
- **AI calls cover the new EMS classes** – 20 of them, with caller messages in all three
  languages and an NPC patient at the scene.

### Upgrading from 0.7.0-beta

Replace the resource folder. If you changed the config files, update them:

- `config/services.lua`, EMS: new `callTypes` list and `typePriority` table.
- `config/services.lua`, mechanic: replace `fixedPriority = 'D'` with
  `allowedPriorities = { 'C', 'D' }`.
- `config/config.lua`: the EMS entries in `Config.AiCalls.types` (no `priority` needed –
  it comes from `typePriority`) and the new EMS types in `Config.Scenes.kinds`.
- Locale files: new `calltype.*` names, new A–D `priority` labels, `priority_mechanic`
  and new `aicall.*` texts – merge them if you translated your own.
- Calls already open keep their old type; nothing to migrate.

## v0.7.0-beta – AI call rules, sirens by priority, NPC mechanic (2026-10-14)

AI calls only come for a dispatcher working without player responders, NPC units use lights
and sirens only on A and B calls, roadside calls are always class D, and an NPC mechanic
helps players when no player mechanic is on duty. Still a beta – please report problems in
[Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### New

- **NPC mechanic.** Roadside assistance (mechanic) is now enabled by default. When no
  player mechanic is on duty, an NPC tow truck takes roadside calls made by players – no
  sirens, as they're class D – and repairs the nearest vehicle at the scene. It never takes
  generated AI calls (`playerCallsOnly`), and AI calls no longer include roadside calls
  (`weights.mechanic = 0`). A service can now override the NPC `trigger` on its own
  (`trigger = 'no_on_duty'` for the mechanic).

### Changed

- **AI calls only for a dispatcher working alone.** Automatic AI calls are now generated
  only while at least one dispatcher is on duty and no player is on duty in any responding
  service (police, EMS, fire, mechanic). As soon as any of them clocks in, AI calls stop.
  Settings `requireDispatcher` and `playersOnDuty` in `Config.AiCalls` replace
  `requireResponders`; `playersOnDuty = 'service'` only skips the services that have
  players. `/aicall` for admins still creates a call right away.
- **No lights or sirens for C and D calls.** NPC units drive to A and B calls with blue
  lights and sirens as before, but to C and D calls without them and at normal speed, and
  don't switch lights on at the scene (`sirenPriorities`, `urgentSpeed`, `normalSpeed` in
  `Config.AiUnits`).
- **Roadside assistance calls are always class D.** A new `fixedPriority` service setting
  (set to `'D'` for mechanic) forces the priority of every call of that service – also when
  a dispatcher changes it or moves a call to the mechanic service. The priority list is
  locked in the panel for such calls.

### Upgrading from 0.6.0-beta

Replace the resource folder. If you changed the config files, update them:

- `config/config.lua`, `Config.AiCalls`: replace `requireResponders` with
  `requireDispatcher = true` and `playersOnDuty = 'any'`, and set `mechanic = 0` in
  `weights`. In the test mode block at the end use `requireDispatcher = false` and
  `playersOnDuty = false`.
- `config/config.lua`, `Config.AiUnits`: add `sirenPriorities = { A = true, B = true }`,
  `urgentSpeed = 28.0` and `normalSpeed = 17.0`; in the mechanic entry of `services` add
  `trigger = 'no_on_duty'` and `playerCallsOnly = true`.
- `config/services.lua`, mechanic: `enabled = true` and `fixedPriority = 'D',`.
- Locale files have a new key `error.ai_player_calls_only`.

## v0.6.0-beta – NPC police on the panel, NPC medics treat everyone (2026-10-14)

NPC police now work only in the dispatch system, and NPC medics treat every hurt player at
the scene. Still a beta – please report problems in
[Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### Changed

- **NPC police no longer come to the scene in person.** An NPC police unit is still
  dispatched, arrives, secures the scene and leaves – its status and notes update in the
  dispatch panel as before – but no patrol car or officers spawn or drive to the call.
  NPC EMS, fire and mechanic units still come in person. Set per service with `visible` in
  `Config.AiUnits.services` (`visible = false` for police by default).
- **NPC medics treat everyone who needs it at the scene.** Instead of reviving only the
  player who called 112, an NPC EMS unit now revives every downed or injured player within
  20 m of the scene (`treatRadius`) – including a friend the caller called for. Unhurt
  players, and a caller who has since left the scene, are not touched.

### Upgrading from 0.5.1-beta

Replace the resource folder. If you changed `config/config.lua`, add to the entries in
`Config.AiUnits.services`: `visible = false,` for police (or `true` to keep patrol cars
driving to the scene) and `treatRadius = 20.0,` for EMS.

## v0.5.1-beta – NPC units (2026-10-14)

Small naming update. Still a beta – please report problems in
[Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### Changed

- **"AI units" are now called "NPC units"** everywhere players and dispatchers see them
  (panel button, call notes, messages) in English, Finnish and Swedish. "AI calls" keep
  their name. Config names and exports (`Config.AiUnits`, `SendAiUnit`, `GetAiUnits`) are
  unchanged, so existing configs and integrations keep working.

### Upgrading from 0.5.0-beta

Replace the resource folder. No config changes. If you translated your own locale files,
update the `ui.send_ai`, `ui.ai_unit`, `error.ai_*` and `ai.note_*` texts.

## v0.5.0-beta – AI units & scenes fixes, test mode (2026-10-13)

Fixes for AI units and NPC scenes found in testing, plus a test mode for trying things
quickly. Still a beta – please report problems in
[Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### Fixed

- **AI police never showed up** – many Qbox/QBCore servers blacklist the `s_m_y_cop_01` ped
  (and `firetruk`) and delete them the moment they spawn, so the unit failed silently.
  AI units now take a list of vehicle and ped models and use the first one that spawns
  and stays (police: `csb_cop` first). Failures are printed with debug on.
- **No patient at EMS calls** – scene NPCs were placed using the ground height before the
  ground had loaded, so on slopes they ended up under the terrain or inside buildings. They
  now wait for collision and stand on a walkable spot (pavement) near the call.
- **AI medics walked to the call marker instead of the patient** – the patient usually
  spawns after the unit is sent; the crew now looks the patient up when it arrives.
- **AI units stayed at the scene** – a kneeling medic ignored the "get back in" order, and a
  unit that finished while it was still spawning was never removed. The crew now stops
  its animation, gets in (or is put in if stuck) and drives off; the server removes the
  vehicle and crew after 75 s if the player's game didn't.
- `Config.AiUnits.autoWithDispatcher = true` had no effect – AI units were only scheduled
  when no dispatcher was on duty.

### New

- **Test mode** (`Config.TestMode`, off by default) – an AI call every 30–60 seconds even
  with nobody on duty, AI units after 10 s, AI units also when players of the service are
  on duty, and debug prints in the server and F8 consoles.
- **`/aicall [police|ems|fire|mechanic]`** – create an AI call right away (admins and
  on-duty dispatchers).
- `Config.AiUnits.trigger = 'always'` and `Config.AiCalls.requireResponders`.
- A call note when an AI unit could not be sent automatically, with the reason.

### Upgrading from 0.4.2-beta

Replace the resource folder. If you changed `config/config.lua`, copy into your version:
`Config.TestMode` (top), `testCommand` and `requireResponders` in `Config.AiCalls`, the
model lists for `vehicle` / `ped` in `Config.AiUnits.services` and the "Test mode" block at
the end of the file. Locale files have new keys (`aicalls.generated`,
`aicalls.not_generated`, `ai.note_not_sent*`) – merge them if you translated your own.

## v0.4.2-beta – NPC scenes & caller location (2026-10-13)

AI calls now have people and things at the scene, the call's location follows the caller,
and AI units become visible when players come near. Still a beta – please report problems
in [Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### New

- **NPC scenes for AI calls** – when a player comes near an AI call, the scene the caller
  described appears:
  - **Patients** (collapse, chest pain, overdose…) lying on the ground with a bystander on
    the phone. EMS players press **E** next to them to treat them – the patient gets up.
  - **Traffic accidents** – a damaged car and an injured driver on the ground (EMS treat).
  - **Witnesses** for police calls, and a victim crouching in cover after shots fired.
    Police press **E** to take a statement – it's added to the call's notes.
  - **Fires** – a burning car, or fires at a building or in the terrain. When they're all
    out, the call is marked handled.
  - **Broken-down cars** with the hood open and the engine smoking, the driver waiting.
    Mechanics press **E** to repair.
  - AI units handle scenes too: an AI medic walks to the patient and treats them.
  - Removed when the call closes; if the player who spawned them leaves, they reappear for
    the next player who comes near. Player calls never get NPCs.
  - Configurable in `Config.Scenes` (which call types get which scene, who can interact,
    peds, vehicles, limits). `ResolveScene` export and `onSceneHandled` event.
- **Caller location follows the caller** – while a call is open, its location moves with
  the caller (e.g. a victim running away or someone driving to hospital). The dispatcher's
  map, the units' GPS route and the street name update automatically. Shown as
  "Tracking caller" in the call details. Settings in `Config.Location`.
- **"Locate caller" button** – dispatchers can refresh the caller's position at any time,
  like positioning a phone. Logged in the call's notes. `LocateCaller` export.
- **AI units become visible when players come near** – a unit sent while nobody was around
  used to stay invisible. Now a player who approaches while it's on its way sees it drive in
  with sirens, and a player who reaches a scene where it's already working sees the vehicle
  (lights on) and crew there (`handOver`, `visibleOnScene`).

### Changed

- Qbox job example: the boss grade is now called **Vuoromestari**.

### Needs testing on live servers

- NPC scenes: animations, fires and the E prompts in game.

### Upgrading from 0.3.0-beta

Replace the resource folder. If you changed `config/config.lua`, copy the new
`Config.Scenes` and `Config.Location` sections and the new `handOver`, `visibleOnScene` and
`watchInterval` settings in `Config.AiUnits` into your version.

## v0.3.0-beta – AI calls & AI units (2026-10-13)

Generated emergency calls for quiet moments, and NPC responders when nobody of a service is
on duty. Still a beta – please report
problems in [Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### New

- **AI calls** – when players aren't calling 112, realistic calls and texts are generated
  (robberies, collapses, car fires, breakdowns…) at locations around the map, so units and
  dispatchers have something to do.
  - Switch on/off in game with `/aicalls` or the **AI calls** button in the panel
    (admins with ACE `pessimi42_dispatch.admin`, and on-duty dispatchers). Remembered
    across restarts.
  - Only when it's quiet (no player call or text for 5 minutes), only when someone can
    respond, at most 3 open at once.
  - About a quarter arrive as texts, and the caller answers the dispatcher's texts.
  - Marked **AI** on the panel. Caller messages in English, Finnish and Swedish.
  - Configurable in `Config.AiCalls`; exports `GenerateAiCall`, `SetAiCalls`,
    `AreAiCallsEnabled`.
- **AI units** – an NPC patrol car, ambulance, fire truck or tow truck drives to the call
  with sirens when nobody of that service is on duty. Players always come first: as soon
  as someone of that service clocks in, no more AI units are sent for it.
  - Police secure the scene for a while.
  - EMS revive the caller through your medical script (qbx_medical, qb-ambulancejob and
    esx_ambulancejob supported out of the box; others via `Config.AiUnits.reviveEvent`).
  - Fire puts out fires around the scene.
  - Mechanics repair the nearest vehicle.
- **Automatic when no dispatcher is on duty** – a call still without a unit after
  45 seconds (`waitSeconds`) gets an AI unit.
- **"Send AI unit" button** in the dispatcher panel, shown only when nobody of the call's
  service is on duty. AI units and their status (en route,
  on scene, left) show in the call details, and their actions are logged in the notes.
- **Works without nearby players** – the caller or the nearest player controls the NPCs.
  If nobody is near the call, the unit still arrives and does its job without visible NPCs.
- **Configurable** in `Config.AiUnits`: vehicles, peds, timings, per-service on/off, the
  maximum number of AI units at once, and `trigger = 'no_available'` to also use AI when
  units are on duty but all busy.
- `SendAiUnit` and `GetAiUnits` exports and an `onAiSent` server event.

### Fixed

- Texts translated on the server without a player's language (for example call-type labels
  sent to ps-dispatch) showed the translation key instead of the text.

### Changed

- A call with an AI unit on it counts as active: it isn't closed automatically while the
  AI unit is working, and players can still respond to it.

### Needs testing on live servers

- NPC driving and on-scene behaviour on busy servers.
- Revive on ESX, which uses the standard `esx_ambulancejob:revive` event.

### Upgrading from 0.2.0-beta

Replace the resource folder. If you changed `config/config.lua`, copy the new
`Config.AiCalls` and `Config.AiUnits` sections into your version. AI calls can be switched
off in game with `/aicalls off`; AI units with `Config.AiUnits.enabled = false`.

## v0.2.0-beta – SMS & lb-phone (2026-10-13)

Adds text messaging between the dispatch centre, callers and units, with lb-phone as the
first supported phone. Still a beta – please report problems in
[Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### New

- **lb-phone support**, detected automatically. Callers' real lb-phone numbers are shown
  on the panel.
- **Text 112** – a text to 112 creates a new call, or is added to the caller's open call.
  Useful when a caller can't talk.
- **SMS from the dispatcher panel** – quick replies ("Help is on the way", "Stay where you
  are", "Move to a safe place", "Describe the people or vehicles", "Call back") and free
  text. Every SMS appears in the call's notes.
- **Automatic texts to callers** – call received, help on the way and case closed. Each
  can be switched off in `Config.Sms.auto`.
- **Texts in the reader's language** – callers and units get messages in the language
  they chose with `/dispatchlang`.
- **Call details for units** – assigned units get the call summary and a location pin by
  SMS (`Config.Sms.toUnits`).
- **Phone required to call 112** (optional) – `Config.Phone.requirePhone`.
- **112 app on the phone** (optional) – opens the emergency call form. Setup in
  `install/lb-phone.md`.
- **Other phones** – `RegisterPhone` export and `server/phones/_template.lua`, plus
  `SmsCaller` and `IncomingSms` exports.

### Changed

- When a phone is running, "help is on the way" reaches the caller as an SMS instead of an
  on-screen notification. Without a phone everything works as in 0.1.0-beta.

### Needs testing on live servers

- Whether lb-phone accepts `112` as the sender of a text. If it doesn't, the message is
  shown as a phone notification titled "112" instead.

### Upgrading from 0.1.0-beta

Replace the resource folder. If you changed `config/config.lua`, copy the new
`Config.Phone` and `Config.Sms` sections into your version.

## v0.1.0-beta – First beta (2026-10-13)

First public beta of **pessimi42_dispatch**, an emergency dispatcher (112) job for FiveM.
Core features work, but the resource has not been tested on live servers yet – please
report problems in [Issues](https://github.com/pessimi42/pessimi-dispatch/issues).

### Highlights

- **Works on Qbox, QBCore and ESX**, detected automatically. Without a framework it runs
  standalone with ACE permissions.
- **112 calls from players** – `/112` opens a form (choose service, describe what
  happened), `/112 <text>` sends straight away. Calls use the player's server-side
  position and are rate-limited.
- **Dispatcher panel** (`F6` / `/dispatch`) – call queue sorted by priority A–D, call
  details, reclassify service, type and priority, notes, assign and remove units,
  request units (broadcast), close calls, history of closed calls. Dispatchers can also
  create calls at their map waypoint.
- **Units** – police and EMS. Toast, sound and GPS route when assigned, `/status`
  (also accepts radio codes such as `10-8`), `/callsign`, `/respond` for broadcast calls,
  automatic *on scene* on arrival, and a small status card on screen.
- **No dispatcher on duty** – calls go to the nearest available unit of the right
  service automatically. If nobody is free, all on-duty units of that service are
  alerted. When the last dispatcher goes off duty, waiting calls are handed out the
  same way.
- **Ready for more services** – fire and roadside assistance are included and can be
  enabled in `config/services.lua`. New services need only a config block and
  translations.
- **Integrations** – ps-dispatch in both directions (its alerts appear on the panel,
  assignments can be shown in the ps-dispatch UI). Exports, server events and a
  template for connecting other dispatch scripts and MDTs.
- **Languages** – English, Finnish and Swedish. Each player can choose their own with
  `/dispatchlang`. New languages are a single JSON file.

### Known limitations

- Calls are kept in memory and are cleared when the resource restarts.
- The dispatcher panel does not show unit positions.
- Not yet tested in game on all frameworks; the ps-dispatch integration follows its
  documented exports and still needs live testing.

### Installation

Download `pessimi42_dispatch-v0.1.0-beta.zip` from the release, put the
`pessimi42_dispatch` folder in your resources and follow the README. Keep the folder
name `pessimi42_dispatch`.
