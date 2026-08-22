# cortex-lib

<p align="center">
  <img src="https://img.shields.io/badge/version-2.2.0-blue?style=flat-square" alt="Version 2.2.0" />
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License MIT" />
  <img src="https://img.shields.io/badge/FiveM-cerulean-0ea5e9?style=flat-square" alt="FiveM cerulean" />
  <img src="https://img.shields.io/badge/Lua-5.4-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua 5.4" />
  <img src="https://img.shields.io/badge/React-18-61DAFB?style=flat-square&logo=react&logoColor=black" alt="React 18" />
</p>

<p align="center">
  Lightweight, modular UI and utility library for the <strong>Cortex</strong> ecosystem on FiveM.<br />
  Shared client / server helpers, NUI components, and game utilities through a single <code>lib</code> global.
</p>

<p align="center">
  <sub>Not affiliated with Cfx, FiveM, Rockstar Games, Take-Two Interactive, or any related entity.</sub>
</p>

---

## Overview

**cortex-lib** is the shared foundation for Cortex resources. It lazy-loads only what you use, exposes a consistent `lib` API on both client and server, and ships a vendored React 18 NUI bundle so your UI never depends on a CDN.

Use it for notifications, progress bars, menus, radial menus, zones, callbacks, interactions, settings, and common game utilities without reimplementing the same helpers in every resource.

```lua
-- any resource that includes @cortex-lib/init.lua
lib.notify({ type = 'success', description = 'Hello from cortex-lib!' })

lib.zones.box({
  coords = GetEntityCoords(PlayerPedId()),
  size = vector3(10, 10, 5),
  onEnter = function() print('entered') end,
  onExit  = function() print('exited') end,
})
```

---

## Features

| Module | Context | What it does |
| :--- | :---: | :--- |
| `notify` | client | HUD toasts, progress bars, alert dialogs, text UI and helpers (`success`, `error`, `info`) |
| `callback` | shared | Promise-style client ↔ server RPC with `await` support |
| `menu` | client | Keyboard and mouse NUI menus with nested options |
| `radial` | client | Pie / radial menu with nested submenus |
| `zones` | client | Poly, box and sphere zones — `onEnter`, `onExit`, `inside` |
| `points` | client | Distance-based point triggers — `onEnter`, `onExit`, `nearby` |
| `raycast` | client | Camera and coordinate raycasts |
| `getters` | client | Closest / nearby player, vehicle, ped and object queries |
| `disablecontrols` | client | Instance-based control locks (movement, combat, vehicle, mouse) |
| `help` | client | Persistent key-hint bar at the bottom of the screen |
| `interaction` | client | Owner-scoped screen and world prompt registry + 3D NUI renderer |
| `settings` | client | KVP-backed settings registry with built-in NUI settings menu |
| `timer` | shared | Pausable / resumable timer class |
| `waitFor` | shared | `waitFor(condition, timeout)` helper |
| `utils` | shared | JSON, KVP, distance, table and number utilities |
| `cache` | client | Live `ped`, `playerId`, `serverId`, `vehicle`, `seat` cache updated every 100ms |

> Client utilities from `client/utils.lua` and `client/debug_panel.lua` are also available (pool clearing, ped/vehicle helpers, camera direction, clipboard, debug panel).

---

## Requirements

- **FiveM** `cerulean` (fx_version `cerulean`, game `gta5`)
- **Lua 5.4** — every dependent resource must have `lua54 'yes'` in its `fxmanifest.lua`
- **cortex-lib must start first** — before any resource that uses `lib`

---

## Installation

**1. Install the resource**

Copy or clone into your server's resources, e.g.:

```
resources/[eco]/cortex-lib
```

**2. Ensure start order**

In `server.cfg` — before any dependent resource:

```cfg
ensure cortex-lib
```

**3. Load it in each dependent resource**

In your resource's `fxmanifest.lua`:

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

shared_script '@cortex-lib/init.lua'
```

That's it. `lib` and `cache` are now available globally in that resource.

> [!CAUTION]
> If `lua54 'yes'` is missing, cortex-lib will throw on load.

---

## Quick Start

### Notifications

```lua
lib.notify({ type = 'info', title = 'Hello', description = 'World!' })
lib.notify({ type = 'success', description = 'Saved!' })
lib.notify({ type = 'error', title = 'Failed', description = 'Try again.' })

-- server -> client
TriggerClientEvent('cortex-lib:notify', source, {
  type = 'info', description = 'Sent from server!'
})
```

### Callbacks

```lua
-- server
lib.callback.register('myResource:getData', function(source, key)
  return { source = source, key = key }
end)

-- client
CreateThread(function()
  local data = lib.callback.await('myResource:getData', false, 'test')
  print(json.encode(data))
end)
```

### Zones & Points

```lua
-- box zone
lib.zones.box({
  coords = vector3(0, 0, 0),
  size = vector3(10, 10, 5),
  debug = false,
  onEnter = function() print('entered') end,
  onExit  = function() print('exited') end,
})

-- distance point
lib.points.new({
  coords = vector3(100.0, 200.0, 30.0),
  distance = 3.0,
  onEnter = function() lib.notify({ description = 'Near point' }) end,
})
```

### Menus & Radial

```lua
lib.menu.open({
  title = 'Actions',
  options = {
    { label = 'Repair', icon = 'wrench', onSelect = function() print('repair') end },
    { label = 'Clean',  onSelect = function() print('clean') end },
  }
})

lib.radial.open({
  items = {
    { id = 'engine', label = 'Engine', icon = 'engine' },
    { id = 'doors',  label = 'Doors',  submenu = {
        { id = 'door_fl', label = 'Front Left' },
    }},
  }
})
```

---

## Interaction Prompts

Display-only prompts. Your resource owns the input — cortex-lib only renders.

```lua
RegisterKeyMapping('+exampleAction', 'Example action', 'keyboard', 'E')
RegisterCommand('+exampleAction', function()
  -- your own distance / state / permission checks here
end, false)

lib.showInteraction({
  id = 'example-action',
  label = 'INTERACT',
  key = 'E',
  priority = 10,
})

-- replace all prompts owned by this resource
lib.setInteractions({
  { id = 'throw', label = 'THROW', key = 'G', priority = 20 },
  { id = 'aim',   label = 'AIM',   key = 'RMB', priority = 10 },
})

-- GTA-style target context: actions sharing this validated panel render as
-- labeled key discs, a divider, and one filled-center context marker.
local targetPanel = {
  id = 'social-target',
  label = 'STRANGER',
  variant = 'target',
}

lib.setInteractions({
  { id = 'greet', label = 'GREET', key = 'G', priority = 20, panel = targetPanel },
  { id = 'taunt', label = 'TAUNT', key = 'H', priority = 19, panel = targetPanel },
})

lib.hideInteraction('example-action')
lib.clearInteractions()
```

Screen interactions are press-only: perform the action once from the mapped
`+command` after checking `lib.isInteractionActive(id)`. Supplying
`holdDuration` without a world anchor is rejected so the input behavior cannot
contradict the one-press screen UI.

`panel` is optional and screen-only. The supported `target` variant shows each
caller-supplied key label inside its white action disc and uses an outer ring with a
filled center for the context marker. `id` and `label` are bounded and sanitized
at the registry boundary; panel data is copied in public snapshots so callers
cannot mutate live renderer state.

<details>
<summary><strong>World anchors (position / entity / bone)</strong></summary>

Follow a bone-less or moving object's root transform:

```lua
lib.showInteraction({
  id = 'wallet-pickup',
  label = 'PICK UP WALLET',
  key = 'E',
  holdDuration = 350,
  anchor = {
    type = 'entity',
    entity = wallet,
    model = GetEntityModel(wallet), -- optional handle-reuse guard
    offset = { z = 0.08 },
    maxDistance = 2.0,
  },
})
```

Use a named entity bone when the exact moving part matters:

```lua
lib.showInteraction({
  id = 'vehicle-door',
  label = 'OPEN',
  key = 'E',
  priority = 100,
  holdDuration = 1200,
  anchor = {
    type = 'entity-bone',
    entity = vehicle,
    bone = 'door_dside_f',
    offset = { z = 0.08 },
    maxDistance = 2.0,
  },
})

-- static world position
lib.showInteraction({
  id = 'stash',
  label = 'OPEN',
  key = 'E',
  anchor = { type = 'world', x = 0, y = 0, z = 0 },
})
```

- For `world` anchors, `anchor.offset` follows world axes. For `entity` and `entity-bone` anchors, it follows the entity's local axes.
- The renderer revalidates entity existence, the optional expected model, range, and screen projection every frame. Bone indices are cached per entity/model pair and rebuilt automatically if the handle resolves to a different model.
- World anchors use the same key disc and may opt into the outer hold-progress ring with `holdDuration` (**100-600000 ms**).
- Start and cancel that ring from the owning `+command` / `-command` pair with `lib.startInteractionHold(id)` and `lib.cancelInteractionHold(id)`. The ring is presentation only; the resource still measures elapsed time, revalidates the target, and owns the action.
- `lib.getInteractionState(id)` returns an owner-scoped copy with `active`, `visible`, and (for a visible world prompt) `distance`. `lib.isInteractionVisible(id)` is the cheap boolean form. Check it before starting an anchored action, then revalidate entity identity and gameplay rules again before mutating anything.

</details>

**Rules**

- IDs are scoped to the invoking resource.
- Max **8 prompts per resource**, **16 total** in the client registry.
- Prompts are removed automatically when their owner resource stops.
- When keys collide, only the highest `priority` prompt is active. Gate gameplay mutations with `lib.isInteractionActive(id)`.
- A world prompt is `visible` only while its winning entry is in range and successfully projected on screen; callers cannot set renderer-owned visibility.
- `lib.startInteractionHold(id)` and `lib.cancelInteractionHold(id)` are owner-scoped and require a world prompt that defines `holdDuration`.

Available via `lib`, `lib.interaction`, and `exports['cortex-lib']`.

### Performance pattern

Register prompts on state transitions, not in a permanent `Wait(0)` loop. This keeps the export boundary and input normalization off the frame path. Repeating an identical `showInteraction` or `setInteractions` call is an optimized no-op, but event-driven ownership is still cheaper and easier to reason about.

| Hot path | Previous work | Current work |
| :--- | :--- | :--- |
| `isInteractionActive` | Deep-copy and sort the full registry per query | Direct owner/id lookup against mutation-time arbitration |
| Capacity checks | Rebuild the snapshot and scan owners | Constant-time total and per-owner counters |
| Stable visible entity-bone prompt | Resolve the bone and send NUI every frame | Revalidate the model, reuse the bone index, and skip an unchanged NUI frame |
| Moving world prompt in React | Update the root app state | Coalesce to one animation-frame update in an isolated interaction surface |
| Stable vehicle seat cache | Scan fixed seats every 100 ms | Check the cached seat once; scan the vehicle's real seat range only after a change |
| Points with nothing nearby | Resume an empty coroutine every frame | No frame coroutine until the detector finds a nearby point |

```lua
local benchPoint = lib.points.new({
  coords = vector3(-347.14, -133.42, 39.01),
  distance = 2.0,

  onEnter = function()
    lib.showInteraction({
      id = 'mechanic-bench',
      label = 'USE BENCH',
      key = 'E',
      priority = 50,
    })
  end,

  onExit = function()
    lib.hideInteraction('mechanic-bench')
  end,

  nearby = function(self)
    if self.currentDistance <= 1.5
      and IsControlJustReleased(0, 38)
      and lib.isInteractionActive('mechanic-bench')
    then
      -- The server must revalidate the job, inventory and bench proximity.
      TriggerServerEvent('mechanic:server:openBench')
    end
  end,
})
```

Key arbitration is recomputed only when the registry changes, so `lib.isInteractionActive(id)` is a direct owner-scoped lookup. World projection remains frame-bound only while a prompt is visible; distant anchors use an adaptive wait, stable entity bones reuse their lookup, unchanged frames do not cross the NUI bridge, and the React interaction surface is isolated from unrelated UI.

The scheduling follows the [Cfx `Citizen.Wait` guidance](https://docs.fivem.net/docs/scripting-reference/runtimes/lua/functions/Citizen.Wait): reserve `Wait(0)` for genuinely frame-bound work, adapt idle waits, and cache infrequently changing native results. The cache and points lifecycles are adapted from proven [ox_lib cache](https://github.com/overextended/ox_lib/blob/main/resource/cache/client.lua) and [points](https://github.com/overextended/ox_lib/blob/main/imports/points/client.lua) patterns while retaining cortex-lib's existing public values and callback timing.

---

## Settings

Settings are stored per-client with `SetResourceKvp` / `GetResourceKvpString`. Built-ins:

| Key | Type | Description |
| :--- | :--- | :--- |
| `notifySound` | boolean | Master toggle for notification audio |
| `notifySoundPreset` | string | Default sound preset |
| `notifyPosition` | string | Default toast position (`top-right`, `top`, `bottom`, …) |

Register your own tab:

```lua
-- lazy-load to avoid paying for what you don't use
local settings = lib('settings')
local soundOn = settings.getSetting('notifySound')

-- from another resource via exports
exports['cortex-lib']:registerSettings({
  id = 'myResource',
  label = 'My Resource',
  options = { ... }
})
```

---

## How It Works

**Lazy loading** — `lib` is a metatable with `__index` / `__call`. Accessing `lib.notify`, `lib.zones`, etc. loads `imports/<module>/<context>.lua` on first use. Shared files (`shared.lua`) are prepended automatically.

```
fxmanifest.lua          →  cerulean, gta5, lua54
resource/init.lua       →  internal lib / cache bootstrap
init.lua                →  external loader for other resources (@cortex-lib/init.lua)
imports/                →  modular lazy-loaded modules (client / server / shared)
client/                 →  directly loaded helpers + interaction renderer + debug panel
ui/                     →  React 18 NUI bundle (index.html, app.js, style.css) + vendored React
tests/                  →  in-game /cortex test menu and specs
```

All functionality is available through the global `lib` and via exports:

```lua
-- inside a dependent resource
lib.notify({ type = 'success', description = 'Hello!' })
lib('notify').notify({ type = 'success', description = 'Hello!' })

-- cross-resource
exports['cortex-lib']:notify({ type = 'success', description = 'Hello!' })
```

---

## Development & Testing

Enable the in-game test menu:

```lua
-- in fxmanifest.lua (development only)
client_scripts {
  'client/utils.lua',
  'client/interaction_renderer.lua',
  'client/debug_panel.lua',
  'tests/client/debug_commands.lua',
}
```

Restart the resource and run `/cortex` in-game. Covers notifications, progress bars, menus, radial, dialogs, text UI, debug panel and utilities.

Quick console checks (F8):

```lua
lib.notify({ type = 'success', title = 'Success', description = 'Works!' })
lib.progress({ label = 'Test', duration = 3000 })
lib.clearNotifications()
```

Node contract tests:

```bash
node --test tests/*.test.mjs
```

For an interaction performance comparison, restart `cortex-lib`, let each state settle for 10-15 seconds, and record the same route and camera movement before and after the change:

```text
resmon 1
profiler record 500
profiler saveJSON cortex-lib-interactions.json
```

Capture at least: no prompts, one screen prompt, four static world prompts, four moving entity-bone prompts, and the 16-prompt collision limit. The Cfx profiler identifies resource threads and source lines; `resmon`/profiler results from a live FiveM client are the release measurement, while the repository tests only prove static contracts and deterministic operation counts.

See the official [Cfx profiler workflow](https://docs.fivem.net/docs/scripting-manual/debugging/using-profiler/) for `profiler status`, `profiler view`, and loading saved captures.

> [!NOTE]
> `tests/client/debug_commands.lua` is for development — don't ship it enabled in production.

---

## Configuration Reference

cortex-lib itself has no `config.lua`. Behaviour is driven by KVP settings and module options passed at call time. To add resource-specific settings, use `lib.registerSettings` as shown above.

---

## Troubleshooting

| Symptom | Cause / Fix |
| :--- | :--- |
| `Lua 5.4 is required` error | Add `lua54 'yes'` to the **calling** resource, not just cortex-lib |
| `cortex-lib must be started before this resource` | Move `ensure cortex-lib` above dependents in `server.cfg` |
| NUI not showing | Check `ui_page` loads and `ui/app.js` + `ui/vendor/` are in `files` |
| Prompts not visible | Max 16 total — check `lib.clearInteractions()` and owner scoping |
| Settings not persisting | KVP is per-client and per-machine — not synced between players |

---

## License

MIT — see [LICENSE](LICENSE).

Copyright (c) 2026 Ever3st

The embedded **Barlow Condensed** interaction font is distributed under the SIL Open Font License — see `ui/barlow-condensed-OFL.txt`.
