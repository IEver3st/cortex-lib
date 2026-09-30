# Developer API

For installation and player settings, read the [customer guide](../README.md). This reference is for developers integrating Cortex resources.

## Features

| Module | Context | What it does |
| :--- | :---: | :--- |
| `notify` | client | HUD toasts, progress bars, alert dialogs, text UI and helpers (`success`, `error`, `info`) |
| `callback` | shared | Promise-style client ↔ server RPC with `await` support |
| `menu` | client | Keyboard and mouse NUI menus with nested options |
| `radial` | client | Radial menu picked by direction, with pages and nested submenus |
| `zones` | client | Poly, box and sphere zones — `onEnter`, `onExit`, `inside` |
| `points` | client | Distance-based point triggers — `onEnter`, `onExit`, `nearby` |
| `raycast` | client | Camera and coordinate raycasts |
| `getters` | client | Closest / nearby player, vehicle, ped and object queries |
| `disablecontrols` | client | Instance-based control locks (movement, combat, vehicle, mouse) |
| `help` | client | GTA-style controls legend (label + keycaps) at the bottom-right of the safe zone |
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

Notices are frameless: a 4u severity rule, a display-caps title and a 4u lifetime meter. `[KEY]` tokens in a
description render as keycaps. The player's **Notifications** settings apply on top of your `duration`
(a 0.5-3x lifetime multiplier) and cap how many are visible (1-12). Past the cap, timed notices leave;
persistent ones are held and come back as space frees.

### Progress, text UI and the controls legend

```lua
-- Progress: bar (label, percent, 8u meter) or circle (96u ring). Returns true when it ran its duration.
local done = lib.progress({ duration = 5000, label = 'Lockpicking', style = 'circle', canCancel = true })

-- Text UI: [KEY] tokens become keycaps. Short copy reads as a display-caps action; long copy as a sentence.
lib.showTextUI('[E] Open trunk  [SHIFT+G] Lock', { position = 'bottom-center' })
lib.hideTextUI()

-- Help: a GTA-style controls legend, bottom-right inside the safe zone. `value` is space-separated keys
-- ("W S A D", "SHIFT+E", "LEFT ALT", "Esc · Backspace"); a value that is not keys renders as plain text.
lib.showHelp({ { label = 'Grab', value = 'E' }, { label = 'Back', value = 'BACKSPACE' } }, { compact = false })
lib.hideHelp()
```

- On completion the progress fill pulses to paper; on cancellation it turns sand and reads CANCELLED before
  leaving. The percent readout follows the player's **Show percentage** setting.
- The legend stays visible when the player turns control hints off, because it carries the only instructions.
  It publishes its height as `--cx-help-legend-height` so bottom-right neighbours can sit above it.

### Dialogs

Both dialogs yield, take NUI focus, and open as a 520u slip centre-low over a light scrim. Enter confirms,
Escape cancels (unless `cancel = false`), and the focused action flips to paper.

```lua
-- Alert: returns 'confirm' or 'cancel' (timeout, stop or a second open also return 'cancel').
local answer = lib.alertDialog({
  header = 'Replace equipment?',
  content = 'Your current equipment will be returned.\n\nThis cannot be undone.', -- blank line = new paragraph
  centered = false,          -- true centres title, copy and actions
  cancel = true,             -- false = confirm-only, Escape and outside clicks do nothing
  labels = { confirm = 'Replace', cancel = 'Keep current' },
})

-- Form: returns a values table, or nil on cancel/timeout/invalid input.
local values = lib.contextMenu({
  title = 'Equipment profile',
  labels = { confirm = 'Save', cancel = 'Discard' },
  values = { name = 'Patrol', count = '2', enabled = true, mode = 'standard' },
  fields = {
    { name = 'name', type = 'input', label = 'Profile name', required = true, placeholder = 'Name this loadout' },
    { name = 'count', type = 'input', inputType = 'number', label = 'Quantity', min = 1, max = 10, step = 1 },
    { name = 'code', type = 'input', inputType = 'password', label = 'Locker code' },
    { name = 'enabled', type = 'checkbox', label = 'Audio feedback', description = 'Play a click when it opens.' },
    { name = 'mode', type = 'select', label = 'Operation', required = true,
      options = { { value = 'standard', label = 'Standard' }, { value = 'night', label = 'Night patrol' } } },
  },
})
```

| Field key | Notes |
| --- | --- |
| `type` | `input` (default), `text`, `checkbox`, `select` |
| `label`, `description`, `placeholder` | Eyebrow label; `description` renders under it |
| `inputType` | `text`, `number`, `email`, `password` (Show/Hide toggle), `search`, `url` |
| `required` | Marked with a soft-red pip; Confirm is blocked with an inline error until filled |
| `min`, `max`, `step` | Optional, number inputs only: finite, `min <= max`, `step > 0`. Adds a stepper (buttons, Arrow keys, Shift = x10); results outside the bounds are rejected |
| `options` | `select` only: `{ value, label }` records or scalars (string, number, boolean) |

Text and number results are strings; checkboxes are booleans; selects return the option's value with its
type preserved. Untouched optional fields are omitted from the result.

### Callbacks

```lua
-- server
lib.callback.register('myResource:getData', function(source, key)
  -- Treat source/key as hostile input. Revalidate permissions, session state,
  -- ownership and gameplay prerequisites on the server before any mutation.
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
lib.registerMenu({
  id = 'actions',
  title = 'Actions',
  options = {
    { label = 'Repair', icon = 'wrench', args = { action = 'repair' } },
    { label = 'Clean', args = { action = 'clean' } },
  }
}, function(selected, _, args)
  print(('selected %d: %s'):format(selected, args.action))
end)
lib.showMenu('actions')

lib.registerRadial({
  id = 'doors',
  items = {
    { id = 'door_fl', label = 'Front Left', icon = 'door', onSelect = function() print('front left') end },
    { id = 'hood', label = 'Hood', icon = 'car', disabled = true, description = 'Stand at the front of the vehicle.' },
  }
})

lib.registerRadial({
  id = 'vehicle',
  items = {
    { id = 'engine', label = 'Engine', icon = 'bolt', description = 'Start or stop the engine.',
      onSelect = function() print('engine') end },
    { id = 'doors', label = 'Doors', icon = 'door', menu = 'doors' },
  }
})
lib.showRadial('vehicle')
```

Menu input modes:

- Default: the menu takes NUI focus with a cursor. Up/Down move (wrapping), Left/Right change value rows, Enter selects, Space toggles check rows, Backspace and Esc close (the reason passed to `onClose` is the key). Home/End jump to the first/last row, PageUp/PageDown move a page, and the mouse wheel moves the selection. Moving the mouse over a row selects it; clicking submits, except on a check row, where a click toggles. Right-click closes with reason `'Backspace'`.
- `gameControls = true`: vMenu style. There's no NUI focus, so the player keeps moving, driving and looking around with the mouse. The scroll wheel or arrows move the selection; left click, Enter or pad A selects (and toggles checkbox rows); right click, Backspace or pad B closes with reason `'Backspace'`; Esc closes with `'Escape'`. Left/right arrows and the D-pad change value rows. Firing, aiming and weapon-wheel scrolling are blocked while the menu is open and for 300 ms after it closes. Input pauses while another UI holds NUI focus (for example chat) or the pause menu is open.
- `gamepad = false`: in game-control mode, ignores controller input.
- `startIndex = n`: highlights row `n` when the menu opens. Use it with `onSelected` to keep the player's place when you re-register a menu after a change.

Option fields: `label`, `description`, `icon`, `iconColor` (`#hex` or `var(--token)`), `values` (with `defaultIndex`), `checked`, `progress` (0-100), `close`, `args`, and `disabled = true`. Disabled rows are shown dimmed, skipped by navigation, and refused by Lua: submit, check and side-scroll callbacks for them return `option_disabled` and never reach your handlers. `icon` accepts a Cortex glyph name or a Font Awesome style string (`'car'`, `'fa-solid fa-key'`, `'wrench'`, `'shield'`, `'heart'`, `'lock'`, `'pin'`, `'money'`, …). Unknown names fall back to a monogram, and emoji render as a single-colour silhouette. Lists longer than the screen allows (at most 10 rows) scroll as a window with faded edges and a scroll rail. The header shows the position (`3 / 40`), and the footer lists the controls available for the selected row.

Radial menus:

- Selection is by direction. The player moves the mouse anywhere on screen past a small dead zone around the centre, holds arrow keys (two arrows aim diagonally), or presses `1`-`8` to pick a slip on the current page directly. The first slip sits at 12 o'clock and the rest run clockwise. Left click or Enter confirms. A click confirms only the slip that is visibly selected, so a double-click that opens a submenu can't also fire an action inside it. Right click, Backspace or a click in the centre goes back from a submenu and closes at the root. Esc always closes. Tab / Shift+Tab cycle through enabled slips.
- More than 8 items are split into pages of 8, shown as dots with `Q` / `E` under the wheel. The mouse wheel, `Q` / `E` or PageUp / PageDown change pages, and paging wraps. The last page keeps empty ghost slots, so every direction means the same position on every page. The wheel remembers the last page per menu for the rest of the client session.
- Item fields: `id`, `label`, `icon`, `iconColor`, `menu`, `keepOpen`, `onSelect`, plus the optional `description` (a string of at most 256 characters, shown in the hub) and `disabled` (boolean). A disabled item is drawn dimmed and never flips to paper. Lua refuses it with `disabled_item`, so its `onSelect` never runs, even from a forged NUI click. `icon` uses the same glyph names as menus. A one- or two-character string (`'1'`, `'?'`) renders in display type, and an emoji renders as a silhouette.
- Submenus: the hub shows a breadcrumb built from the labels of the items that opened each level, and slips that open a submenu show an outward chevron. Going back re-selects the item that opened the submenu.
- `appearance = 'compact-control'` gives a smaller wheel with icon-only slips. The hub carries the label, and there's no description or controls legend.
- Show/hide/refresh/transition messages add the optional fields `trail` (the breadcrumb labels) and `focusIndex` (the zero-based item to re-select after a back). `radialClick`, `radialBack` and `radialClose` payloads are unchanged: `index` is still the source index across pages.

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
filled center for the context marker. Optional `panel.marker` accepts one letter,
digit, or `?` and defaults to `?`; for example, equipment can supply `marker = 'A'`.
Numpad action discs stack a small `NUM` caption over the digit or Enter arrow,
while the original key string remains the arbitration and accessible identity.
`id` and `label` are bounded and sanitized
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
- `anchor.markerDistance` (optional, **0-25**) sets the marker range described below. It defaults to `min(25, max(maxDistance + 4, maxDistance * 2.5))`; `0` (or any value at or below `maxDistance`) disables the marker tier for that anchor.
- The renderer revalidates entity existence, the optional expected model, range, and screen projection every frame. Bone indices are cached per entity/model pair and rebuilt automatically if the handle resolves to a different model.
- World anchors use the same key disc and may opt into the outer hold-progress ring with `holdDuration` (**100-600000 ms**).
- Start and cancel that ring from the owning `+command` / `-command` pair with `lib.startInteractionHold(id)` and `lib.cancelInteractionHold(id)`. The ring is presentation only; the resource still measures elapsed time, revalidates the target, and owns the action.
- `lib.getInteractionState(id)` returns an owner-scoped copy with `active`, `visible`, and (for a visible world prompt) `distance`. `lib.isInteractionVisible(id)` is the cheap boolean form. Check it before starting an anchored action, then revalidate entity identity and gameplay rules again before mutating anything.

</details>

### Markers and merged lists

World prompts are presented in two tiers, entirely by the renderer:

- **Marker** — between `maxDistance` and `markerDistance` the anchor shows a small paper dot inside a ring (a scaled-down key disc) with no label, fading with distance. Nearby markers merge into one. Markers never make an entry `visible` and never authorize anything. Players can turn them off (Cortex settings: `promptMarkers`).
- **Prompt** — inside `maxDistance` the marker grows into the key disc and label.

Prompt-tier anchors that project within ~6% of screen height of each other merge into **one list** at the highest-ranked entry's anchor: a rail with dots, the selected row with the full disc and large label, other rows with a dot (they share the selected row's key) or a small disc (they own a different key and stay usable). Up to four rows are visible; further rows fade out along the rail.

- **Same-key rows compete.** The selected row wins that key. `lib.isInteractionActive(id)` reflects the selection, so a consumer that gates its `+command` with `isInteractionActive` works unchanged. `lib.getInteractionState(id).active` changes when the player scrolls.
- **The wheel selects.** Only while a list that contains a key shared by two or more rows is the focused list (nearest the screen centre) does the renderer block the native weapon-wheel inputs and move the selection; a `WHEEL` hint sits under the list. It never takes the wheel when there is nothing to choose, while free-aiming, or over the pause menu. `invertScroll` flips the direction. The selection is frozen while any row's hold ring is running.
- **Rows are honest.** A row is only offered while its key's natural (priority) owner is in the same list. An entry that loses its key to a prompt elsewhere (or to a screen prompt) degrades to a marker instead of showing a key that would run something else.
- Leaving the list, removing the selected entry, or stopping its owner restores normal priority arbitration. If the selection moves a key away from an entry with a running hold, that hold is cancelled exactly as when it loses arbitration to a higher priority.

Design implication: give actions that belong together the same key (usually `E`) and the list lets the player choose; give an action its own key only when it must stay one press away.

**Rules**

- IDs are scoped to the invoking resource.
- Max **8 prompts per resource**, **16 total** in the client registry.
- Prompts are removed automatically when their owner resource stops.
- When keys collide, only the highest `priority` prompt is active, unless the player selected a same-key row in a merged world list (the selected row wins). Gate gameplay mutations with `lib.isInteractionActive(id)`.
- A world prompt is `visible` only while its winning entry is in range (prompt tier, not marker) and successfully projected on screen; callers cannot set renderer-owned visibility or list selection.
- `lib.startInteractionHold(id)` and `lib.cancelInteractionHold(id)` are owner-scoped and require a world prompt that defines `holdDuration`.

Available via `lib`, `lib.interaction`, and `exports['cortex-lib']`.

### Inline 2D key rings

An existing resource-owned screen can reuse the same key disc and hold ring without
creating a world anchor or showing a separate progress bar. Load
`https://cfx-nui-cortex-lib/ui/interaction-key.css` and `interaction-key.js`, then use
`CortexInteractionKey.mount(element, { item: { key, holdDuration, holdActive, holdRevision }, className: 'cortex-key-inline', decorative: true })`.
The returned `update(data)` preserves the animation for unchanged state; call
`destroy()` when removing the host. Give the host explicit dimensions and the
existing color tokens (`--hud-interaction`, `--text-primary`, `--text-inverse`,
`--state-focus`, `--shadow-color`). Supply an accessible key label on the host.
Optionally set `--cortex-interaction-ring-stroke` / `--cortex-interaction-ring-progress-stroke`
(viewBox units, default `3` / `3.4`) to keep the ring at least 3u on small hosts.

This shares the renderer used by registered prompts, not their registry or input
ownership. The consumer measures the continuous hold, cancels on release/context
loss, and rechecks gameplay eligibility before acting. Send start/cancel state
only; increment `holdRevision` on each new hold. `cortex-death` is the 2D consumer.

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

Key arbitration is recomputed only when the registry changes (including a list selection change), so `lib.isInteractionActive(id)` is a direct owner-scoped lookup. World projection is frame-bound only while a prompt, hold or focused list is on screen; marker-only frames run at ~30 Hz (the NUI eases the steps), and with nothing in range the worker polls at 50-250 ms by distance. Stable entity bones reuse their lookup, unchanged frames (compared at whole pixels) do not cross the NUI bridge, and the React interaction surface is isolated from unrelated UI.

The scheduling follows the [Cfx `Citizen.Wait` guidance](https://docs.fivem.net/docs/scripting-reference/runtimes/lua/functions/Citizen.Wait): reserve `Wait(0)` for genuinely frame-bound work, adapt idle waits, and cache infrequently changing native results. The cache and points lifecycles are adapted from proven [ox_lib cache](https://github.com/overextended/ox_lib/blob/main/resource/cache/client.lua) and [points](https://github.com/overextended/ox_lib/blob/main/imports/points/client.lua) patterns while retaining cortex-lib's existing public values and callback timing.

---

## Settings

Settings are stored per-client with `SetResourceKvp` / `GetResourceKvpString` under `cortex:<key>`. Built-ins (the **CORTEX** tab) are readable with `lib.getSetting(key)`, change through the settings transaction or `lib.setSetting`, and emit `cortex-lib:settingChanged(key, value, 'cortex')` on preview, rollback and save:

| Section | Setting | Default | Control | Purpose |
| --- | --- | --- | --- | --- |
| Interface | Interface size (`uiScale`) | 100 % | Slider 80-130 % | Scales every Cortex prompt, menu and notification. Previews on release. |
| Interface | Text size (`textSize`) | Standard | Standard / Large | Larger body text in menus, dialogs and notifications. |
| Interface | Shared accent (`dynamic_accent`) | Mint | Colour swatches | Highlight colour in every Cortex interface. |
| Interface | Surface opacity (`dynamic_opacity`) | 92 % | Slider 65-100 % | How solid menus and panels look. |
| Interface | Motion (`dynamic_motion`) | System | System / Reduced / Full | Follows the OS preference or forces reduced/full animation. |
| Interface | Avoid overlapping overlays (`dynamic_layout`) | On | Toggle | Moves notifications and prompts aside from chat, the HUD and each other. |
| Interface | Control hints (`controlHints`) | On | Toggle | Key hints under menus and prompts; a hint that is the only instruction stays. |
| Notifications | Position (`notifyPosition`) | Top right | Dropdown (6) | Where notifications appear. |
| Notifications | Display time (`notifyDuration`) | Standard | Short / Standard / Long | Lifetime multiplier 0.75 / 1 / 1.5. |
| Notifications | Visible at once (`notifyLimit`) | 5 | 3 / 5 / 8 | Most notifications shown together. |
| Notifications | Sound (`notifySound`) | On | Toggle | Plays a sound when a notification arrives. |
| Notifications | Sound preset (`notifySoundPreset`) | MP Idle Kick | Dropdown + play | Shown while Sound is on; choosing one plays it. |
| Prompts | Distant interaction markers (`promptMarkers`) | On | Toggle | Small marker for interactions that are near but not yet in reach. |
| Prompts | Prompt size (`promptScale`) | Standard | Small / Standard / Large | Size of world and screen prompts. |
| Prompts | Invert list scroll (`invertScroll`) | Off | Toggle | Flips the wheel direction in stacked prompt lists. |
| Progress | Show percentage (`showPercent`) | On | Toggle | Percent readout on progress bars and circles. |

`notifyDuration` is stored as the enum; the NUI receives the multiplier. A consumer tab that declares its own key with one of these names keeps its own value when that consumer calls `getSetting`/`setSetting`.

The shared NUI receives `SendNUIMessage({ action = 'cortex:prefs', data = { prefs = { scale, textSize, notifyDuration, notifyLimit, showPercent, promptMarkers, promptScale, controlHints, invertScroll } } })` when it posts `cortexPrefsReady` (once mounted, retried until answered), on every preview, on Discard/rollback, on Save/Apply and on `lib.setSetting`. `scale` is `uiScale / 100`; `notifyDuration` is 0.75 / 1 / 1.5. Shared appearance (`dynamic_*`) keeps flowing through `client/presentation.lua` → `dynamic-ui.js`.

Migration: values saved by the retired `cortex-dynamic` tab (`cortex:cortex-dynamic:dynamic_*`) are copied to `cortex:dynamic_*` once when an existing value is absent, then removed; its twelve `dynamic_independent_*` keys are deleted. Stored values outside a field's range or options fall back to the default.

Register your own tab:

```lua
-- lazy-load to avoid paying for what you don't use
local settings = lib('settings')
local soundOn = settings.getSetting('notifySound')

-- from another resource via exports
exports['cortex-lib']:registerSettings(
  'myResource',
  'My Resource',
  'myResource:',
  {
    { key = 'enabled', type = 'toggle', label = 'Enabled', default = true },
  },
  { enabled = true }
)
```

The third argument is either the legacy icon value or a validated KVP namespace ending in `:`. Built-in Cortex settings keep their existing `cortex:` keys; consumer tabs should use a stable resource-specific namespace such as `myResource:`. Duplicate tab IDs, field keys, and cross-resource registrations are rejected instead of silently overwriting another owner. Registration also rejects any concrete KVP key that would overlap a built-in field or a field owned by another registered tab; a prefix may be shared only when the resulting field keys remain distinct.

## Pause menu

The quick menu is disabled by default. `/cortexsettings` and
`openSettingsMenu()` open standalone Cortex Settings. It uses the shared modal,
script tabs and native game blur, with no back arrow, game-settings tab or
keybinding link. Escape closes a dropdown first, then closes settings and rolls
back unsaved changes. Apply saves without closing; Save & Resume saves and closes.

Only the server can enable the quick menu. Put this before `ensure cortex-lib`:

```cfg
setr cortex_pause_replace_native 1
setr cortex_pause_title "CORTEX"
```

Use `0` to disable it. The switch also takes effect from the server console;
keep the value in `server.cfg` for restarts. There is no per-player `pauseMenu`
setting. Disabling an open quick menu takes the player to Cortex Settings.

When enabled, Escape, P and controller Start open the quick menu during gameplay.
It offers Resume, Map, Settings, native Key bindings and confirmed Leave server,
plus registered extension pages and locations. Settings always closes directly
back to gameplay. Map and Key bindings release NUI focus and open GTA's native
frontend, then return to the quick menu unless another frontend takes ownership.
The game retains its map, blips, legend and controls. Consumers own their native
commands and mappings; the library has no custom binding registry or editor.

`/cortexpause` and `openPauseMenu()` open the quick menu when enabled, otherwise
settings. `/cortexnative` opens the native map. Entry respects other focused NUI,
native frontends, text entry and pause-control locks. A missing NUI readiness
acknowledgement releases focus after ten seconds and temporarily bypasses Cortex
pause entry. The world keeps running while either menu is open.

Existing settings registration, listeners, action events and KVP namespaces are
unchanged. Consumers must re-register after the library restarts.

### Resource-owned pages and locations

These are **client exports** with matching `lib` facade methods. Definitions are
copied; IDs are scoped to the invoking resource. Re-registering an ID replaces
that owner's entry. Pages and locations disappear on owner stop and must be
registered again after a cortex-lib restart. Register on `onClientResourceStart`
for your own resource and for `cortex-lib`.

| API | Result and behavior |
| --- | --- |
| `openPauseMenu()` | `true` when the opening request is accepted; otherwise `false, 'ui_busy'` or `false`. Focus follows NUI readiness. |
| `closePauseMenu()` | `true` when the caller owns the custom session and it closes; otherwise `false`. Discards previews; does not close a native handoff. |
| `isPauseMenuOpen()` | Boolean covering the custom shell and its native handoff. Observation only. |
| `registerPausePage(definition)` | `true, scopedId` or `false, error`; adds/replaces a navigation page. |
| `unregisterPausePage(id)` | Removes only the caller's page; idempotent, returns `true` or `false, 'invalid_id'`. |
| `registerPauseLocation(definition)` | `true, scopedId` or `false, error`; adds/replaces a waypoint destination. |
| `unregisterPauseLocation(id)` | Removes only the caller's location; same result contract as page removal. |

A page accepts `id`, `label`, optional `description`, optional numeric `order`
(default 100, range -1000..1000), and `sections`. Each section accepts `title`,
plain-text `body`, and optional `actions = { { id, label } }`. Actions require an
`onAction(actionId)` callback in the page definition. It runs after the shell
discards previews and releases focus, allowing the resource to open its own UI.
The NUI reply acknowledges dispatch, not completion of the resource's work.
Exceptions and an explicit `false` callback result produce a failure notification.
Any privileged operation still needs the consumer's server-side authorization.
The browser cannot supply executable commands or event names.

```lua
local function registerPausePage()
    if GetResourceState('cortex-lib') ~= 'started' then return end
    local ok, result = exports['cortex-lib']:registerPausePage({
        id = 'guide',
        label = 'Player guide',
        order = 10,
        sections = {
            {
                title = 'Your preferences',
                body = 'Script preferences are stored on this computer. Use Save to keep your changes.',
                actions = { { id = 'settings', label = 'Open script settings' } },
            },
        },
        onAction = function(actionId)
            if actionId == 'settings' then
                return exports['cortex-lib']:openSettingsMenu()
            end
            return false
        end,
    })
    if not ok then print(('Pause page registration failed: %s'):format(result)) end
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() or resource == 'cortex-lib' then
        registerPausePage()
    end
end)
```

A location definition is `{ id, label, category, x, y }`. Category defaults to
`Locations`; finite world coordinates must be within -20000..20000. Selecting a
location calls `SetNewWaypoint` using the registered coordinates. This adds a
directory without creating, deleting, or taking ownership of existing map blips.
The Locations navigation item appears only when destinations are registered.

Registry limits: 24 pages, 16 sections per page, 8 actions per section, 256
locations. IDs use letters/digits/underscore/hyphen, up to 64 bytes; prototype
property names are rejected. Page labels are limited to 48 bytes, descriptions
256, section titles 96, section bodies 2048, action labels 64, location labels 96,
and categories 64. Duplicate action IDs within a page are rejected.

`cortex-lib:pauseChanged(active, mode)` is a local observation event, with mode
`custom`, `native`, or `closed`. `LocalPlayer.state.cortexPauseOpen` mirrors it
locally with replication disabled. Custom NUI does not change the return value of
GTA's `IsPauseMenuActive()`. A resource that needs to gate its own script commands
should check `isPauseMenuOpen()` or this local flag as well as its normal gameplay
conditions. Do not treat that flag as server authorization.

See [pause research and runtime acceptance](pause-system.md) for native
boundaries, compatibility evidence, and the user-run checks.

---

## How It Works

**Lazy loading** — `lib` is a metatable with `__index` / `__call`. Consumer-local modules are loaded from `imports/<module>/<context>.lua` once and cached; shared files (`shared.lua`) are prepended automatically. UI-backed modules and direct client utilities resolve to cortex-lib exports so callbacks, NUI messages, focus and owner cleanup stay in the resource that owns the shared UI.

```
fxmanifest.lua          →  cerulean, gta5, lua54
resource/init.lua       →  internal lib / cache bootstrap
init.lua                →  external loader for other resources (@cortex-lib/init.lua)
imports/                →  modular lazy-loaded modules (client / server / shared)
client/                 →  directly loaded helpers + interaction renderer + debug panel
ui/                     →  React 18 NUI bundle (index.html, app.js, style.css) + vendored React
tests/                  →  in-game /cortex test menu and specs
```

Public functions are available through the global `lib`. Cortex-owned functions are also exported for explicit cross-resource use:

```lua
-- inside a dependent resource
lib.notify({ type = 'success', description = 'Hello!' })
local notify = lib('notify')
notify({ type = 'success', description = 'Hello!' })

-- cross-resource
exports['cortex-lib']:notify({ type = 'success', description = 'Hello!' })
```

---

