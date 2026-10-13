# Changelog

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
