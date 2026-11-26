# Developer API

For installation and player settings, read the [customer guide](../README.md). This reference is for developers integrating Cortex resources.

## Features

| Module | Context | What it does |
| :--- | :---: | :--- |
| `notify` | client | HUD toasts, progress bars, alert dialogs, text UI and helpers (`success`, `error`, `info`) |
| `callback` | shared | Promise-style client ↔ server RPC with `await` support |
| `groups` | server | Crew and group-job helpers over cortex-phone (members, jobs board, stages, payouts); nil-safe when the phone is stopped |
| `menu` | client | Keyboard and mouse NUI menus with nested options |
| `radial` | client | Radial menu picked by direction, with pages and nested submenus |
| `zones` | client | Poly, box and sphere zones — `onEnter`, `onExit`, `inside` |
| `points` | client | Distance-based point triggers — `onEnter`, `onExit`, `nearby` |
| `raycast` | client | Camera and coordinate raycasts |
| `getters` | client | Closest / nearby player, vehicle, ped and object queries |
| `vehicleReplay` | client | Shared wheel-speed and suspension telemetry for Director and Rewind |
| `disablecontrols` | client | Instance-based control locks (movement, combat, vehicle, mouse) |
| `help` | client | GTA-style controls legend (label + keycaps) at the bottom-right of the safe zone |
| `interaction` | client | Owner-scoped screen and world prompt registry + 3D NUI renderer |
| `callouts` | client | Pins, leaders and labels on an entity's parts, with a switch block, picked with the game cursor |
| `settings` | client | KVP-backed settings registry with built-in NUI settings menu |
| `timer` | shared | Pausable / resumable timer class |
| `waitFor` | shared | `waitFor(condition, timeout)` helper |
| `utils` | shared | JSON, KVP, distance, table and number utilities |
| `worldScreen` | client | DUI pages on props: texture replace with a held model, variant pools, projected-quad cursor mapping and key hit tests |
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

Notices are frameless: an ink coin holding the severity glyph (or the sender's mark, see
[Senders](#senders-recent-notices-and-the-look-key)), a display-caps title and a 4u lifetime meter. `[KEY]` tokens in a
description render as keycaps. The player's **Notifications** settings apply on top of your `duration`
(a 0.75, 1 or 1.5x lifetime multiplier) and cap how many are visible (3, 5 or 8). Past the cap, timed notices leave;
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
  It publishes its height as `--cx-help-legend-height` so bottom-right neighbours can sit above it. Other
  resources' HUDs read `LocalPlayer.state.cortexHelpLegend`: how far the legend reaches up from the bottom of the
  screen in NUI px (0 when hidden; local only).

### Dialogs

Both dialogs yield, take NUI focus, and open as a 520u slip centre-low over a light scrim. Enter confirms,
Escape cancels (unless `cancel = false`), and the focused action flips to paper.

```lua
-- Alert: returns 'confirm' or 'cancel' (timeout, stop or a second open also return 'cancel'),
-- then why it closed: 'chosen' (the player picked), 'timeout', 'busy' (another alert was open),
-- 'focus' (NUI focus failed), 'replaced' (another modal took over), 'stopped' or 'invalid'.
local answer, why = lib.alertDialog({
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

### Groups (server)

`lib.groups` wraps the cortex-phone group exports for job scripts. Crews form in the phone's Groups app; your job registers on its jobs board and the crew leader starts it. While cortex-phone is stopped, queries return `nil`, `{}` or `0` and mutations return `false, 'phone_unavailable'`, so your resource can start in any order. cortex-phone remains the authority for membership, job ownership and payouts; see its `APP_API.md` for limits.

```lua
lib.groups.registerJob('armoured_truck', {
  label = 'Armoured truck', description = 'Stop the truck and empty it before the cops arrive.',
  icon = 'bank', color = '#30d158', category = 'Heist', payout = 'Up to $4,000 each',
  minMembers = 2, maxMembers = 4, requireReady = true, maxActive = 1, -- extra crews queue
}, {
  onStart = function(groupId, members)
    if not enoughPolice() then return false, 'Not enough police in the city.' end
    lib.groups.setStage(groupId, { title = 'Find the truck', subtitle = 'Route 68', progress = 0 })
    lib.groups.setWaypoint(groupId, { x = 1203.4, y = 2650.1, z = 37.8, label = 'Truck route' })
    return true
  end,
  onMemberLeft = function(groupId, member, reason) end, -- 'left', 'kicked', 'dropped', 'job'
  onEnd = function(groupId, result) cleanup(groupId) end, -- abandoned, disbanded or crew too small
})

-- Later, after your own server checks:
lib.groups.pay(groupId, { amount = 8000, split = true, account = 'cash', reason = 'Armoured truck', id = 'final' })
lib.groups.endJob(groupId, { success = true, summary = 'Clean getaway.' })
```

| Function | Returns |
| --- | --- |
| `get(groupIdOrSource)`, `getPlayerGroup(source)` | Group table or `nil` |
| `getMembers(groupIdOrSource)` | Members with `citizenid`, `name`, `number`, `source` (nil offline), `online`, `leader`, `ready`, `participant` |
| `getSources(groupIdOrSource, participantsOnly?)` | Online server IDs, for `TriggerClientEvent` |
| `getSize(groupIdOrSource)` | Active members, online members |
| `isLeader(source, groupId?)`, `getJob(groupIdOrSource)`, `getPlayerGroups(source)` | Leader flag, running/queued job, summaries |
| `registerJob(id, definition, handlers)`, `unregisterJob(id)`, `setJobAvailable(id, available, reason?)`, `startJob(groupId, jobId)` | `ok, reason` |
| `setStage`, `setWaypoint`, `clearWaypoint`, `setBlip`, `addObjective`, `setObjective`, `notify`, `endJob`, `pay` | `ok` (`pay` also returns `{ paid, failed, each }`) |
| `on(event, handler)` | Listens to `memberJoined`, `memberLeft`, `memberRejoined`, `leaderChanged`, `disbanded`, `jobQueued`, `jobStarted`, `jobEnded` |

Only the resource that registered a job can change its runs. `registerJob` stores the definition and registers it again when cortex-phone restarts.

### Framework (server and client)

`lib.framework` gives a resource one API for Qbox (`qbx_core`), QBCore (`qb-core`) and ESX (`es_extended`), so it does not carry its own bridge. It loads only in resources that use it and changes nothing for the rest.

Status: checked in game on Qbox against direct `qbx_core` calls. The QBCore and ESX adapters are written against qb-core 1.3.0, qb-inventory 2.2.3 and es_extended 1.16.3 and have not been run on a live server yet.

```lua
local fw = lib.framework

local job, grade, onDuty = fw.job(source)
if job ~= 'police' or not onDuty then return end

local paid, code = fw.money.remove(source, 'bank', 250, 'Impound fee')
if not paid then
  if code == 'unknown' then return end -- may have gone through: do not retry or refund
  return lib.notify(source, { description = code == 'insufficient' and 'Not enough in the bank.' or 'Payment failed.', type = 'error' })
end
```

The framework and inventory are detected from what is started. Force either one in `server.cfg` when detection is wrong:

```cfg
setr cortex_framework qbx              # qbx | qb | esx | standalone
setr cortex_framework_inventory ox     # ox | qb | esx | none
```

Without a framework, `kind()` is `standalone`: identity falls back to the player name and license, jobs are `nil`, and money and items return `false, 'no_framework'` or `'no_inventory'`.

Server:

| Function | Returns |
| --- | --- |
| `kind()`, `inventory()`, `describe()` | `'qbx'`, `'qb'`, `'esx'` or `'standalone'`; `'ox'`, `'qb'`, `'esx'` or `'none'`; both as one line for a start message |
| `isLoaded(source)` | `true` once the player has a character |
| `characterId(source)`, `characterName(source)` | Citizen ID or ESX identifier (`nil` without a character); character name, else the player name |
| `license(source)`, `identifier(source, prefix)` | `license:...` or any other identifier, `nil` when absent |
| `meta(source, key)` | Player metadata value |
| `sourceOf(characterId)` | Server ID of that character while online |
| `job(source)` | `name, grade, onDuty, label, type`. Duty is `true` on ESX unless the job says otherwise |
| `hasGroup(source, filter)` | `filter` is a name, a list of names, or `{ name = minimumGrade }`. Jobs everywhere, gangs on Qbox and QBCore |
| `money.get(source, account)` | Balance of `'cash'` or `'bank'`, `nil` when unreadable |
| `money.add(source, account, amount, reason?)`, `money.remove(...)` | `true`, or `false, code` |
| `items.count(source, item)`, `items.has(source, item, amount?)`, `items.canCarry(source, item, amount?)` | Count; booleans |
| `items.add(source, item, amount?, metadata?)`, `items.remove(source, item, amount?, metadata?, slot?)` | `true`, or `false, code` |
| `items.usable(item, handler, { force? })`, `items.releaseUsable(item)` | `ok, code`. `handler(source, { name, slot, metadata })` |
| `onLoaded(handler)`, `onUnloaded(handler)` | `handler(source)` for every character that loads, including the ones already in; `handler(source, 'logout' or 'drop')` |
| `raw(source)` | The framework's own player object, for what the layer does not cover |

Money and item changes only return `true` when the change is confirmed. Amounts are whole numbers above zero. A removal checks the balance first on every framework, so a bank account never goes negative through this API.

| Code | Meaning |
| --- | --- |
| `no_player`, `no_framework`, `no_inventory` | Nothing to act on |
| `bad_account`, `bad_amount`, `bad_item` | The call was wrong |
| `insufficient` | Not enough money or items; nothing changed |
| `rejected` | The framework or inventory refused; nothing changed |
| `unsupported` | Metadata or slot on an inventory without them (ESX default) |
| `taken` | Another resource already registered that usable item. Pass `{ force = true }` to replace it |
| `error` | The framework is missing the method |
| `unknown` | The change may have applied. Never retry and never refund; log it |

Client:

| Function | Returns |
| --- | --- |
| `kind()`, `isLoaded()` | As on the server, for the local player |
| `playerData()` | `{ characterId, name, job = { name, grade, onDuty, label, type } }` or `nil` |
| `job()` | `name, grade, onDuty, label, type` |
| `onLoaded(handler)`, `onUnloaded(handler)`, `onJobChanged(handler)` | `onLoaded` runs once the character's data can be read, and at once for a character already in. `onUnloaded` runs as the character leaves. On Qbox its data can still be read inside the handler; on QBCore and ESX it may already be gone, so keep what you need from `onLoaded`. `onJobChanged` passes `name, grade, onDuty, label, type` and fires once per real change, duty included |
| `raw()` | The framework's own player data |

Client values are for display. Decide permissions, prices and rewards on the server.

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
  title = 'Vehicle',
  items = {
    { id = 'engine', label = 'Engine', icon = 'bolt', description = 'Start or stop the engine.',
      onSelect = function() print('engine') end },
    { id = 'doors', label = 'Doors', icon = 'door', menu = 'doors', badge = 4 },
    { id = 'scrap', label = 'Scrap vehicle', icon = 'trash', confirm = 'Press again to scrap it. This cannot be undone.',
      onSelect = function() print('scrap') end },
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

- Two styles, picked by the player in Settings > Interface > Radial menu style (`radialStyle`, `'wheel'` or `'fan'`). `setr cortex_lib_radial_style fan` changes the server default; the player's choice wins. Consumers register one menu and get both.
  - **Wheel** (default): a ring of icon slips around a hub. The hub names the aimed item and shows its description, or the menu title and RMB Back/Close when nothing is aimed. With one to three items the slips become wide petals; two items sit left and right.
  - **Fan**: a pointer origin at the centre of the screen and a column of named rows curving to its right, with the title above and the legend below. The aimed row flips to paper and shows its description under the label. It suits menus that replace a small list menu, where the names matter more than the icons. Pointing left of the origin aims the mirrored row on the right. Up / Down step through enabled rows, Right opens a submenu and Left goes back. `appearance = 'compact-control'` and empty menus always use the wheel.
- Selection is by direction. The player moves the mouse anywhere on screen past a small dead zone around the centre, holds arrow keys (two arrows aim diagonally on the wheel), or presses `1`-`8` to pick a slip on the current page directly. On the wheel the first slip sits at 12 o'clock and the rest run clockwise. Left click or Enter confirms. A click confirms only the slip that is visibly selected, so a double-click that opens a submenu can't also fire an action inside it. Right click, Backspace or a click in the centre goes back from a submenu and closes at the root. Esc always closes. Tab / Shift+Tab cycle through enabled slips.
- More than 8 items are split into pages of 8, shown as dots with `Q` / `E` under the wheel. The mouse wheel, `Q` / `E` or PageUp / PageDown change pages, and paging wraps. The last page keeps empty ghost slots, so every direction means the same position on every page. The wheel remembers the last page per menu for the rest of the client session.
- Controller: while the player is on a gamepad, the right stick aims (same directions as the mouse), A selects, B goes back or closes, and RB / LB change pages. Pad gameplay buttons are blocked while the radial is open.
- `title` (optional string, at most 64 characters) on `lib.registerRadial` names the menu: the wheel shows it in the idle hub and the fan above the rows. A submenu without its own title shows the label of the item that opened it. Anything else returns `false, 'invalid_title'`.
- Item fields: `id`, `label`, `icon`, `iconColor`, `menu`, `keepOpen`, `onSelect`, plus the optional `description` (a string of at most 256 characters, shown in the hub or under the aimed fan row), `disabled` (boolean), `badge` and `confirm`.
  - `badge`: a non-negative integer (shown as `999+` past 999) or a string of at most 8 characters, drawn as a chip beside the item. Use it for counts such as boards placed or unread items.
  - `confirm`: `true` or a string of at most 128 characters. The first select arms the item: it turns soft red and shows the string (or "Press again to confirm.") in place of its description. A second select within 3 seconds runs it; aiming elsewhere or waiting disarms it. Use it for destructive actions. It guards against slips and is not a permission check.
  - An invalid `badge` or `confirm` returns `false, 'invalid_item'`. A disabled item is drawn dimmed and never flips to paper. Lua refuses it with `disabled_item`, so its `onSelect` never runs, even from a forged NUI click. `icon` uses the same glyph names as menus, but an unknown name shows the label instead of a monogram. A one- or two-character string (`'1'`, `'?'`) renders in display type, and an emoji renders as a silhouette.
- Submenus: the hub shows the menu's `title`, or, when it has none, the label of the item that opened the current level. Slips that open a submenu show an outward chevron. Going back re-selects the item that opened the submenu.
- `releaseSelect = true` (boolean, default off) is for menus opened while a key or mouse button is held. Releasing the right mouse button over a slip selects it, so the player can hold, drag and let go. Releasing over nothing leaves the wheel open for a normal click, and a later right click backs out as usual. It applies to the root view only; a submenu reached by release uses the normal controls. Any other type returns `false, 'invalid_release_select'`.
- `appearance = 'compact-control'` gives a smaller wheel with icon-only slips. The hub carries the label, and there's no description or controls legend.
- Show/hide/refresh/transition messages add the optional fields `trail` (the breadcrumb labels), `focusIndex` (the zero-based item to re-select after a back) and `title`; items carry `badge` and `confirm`. Controller input arrives as `radialPadAim` and `radialPadPress` for the open session. `radialClick`, `radialBack` and `radialClose` payloads are unchanged: `index` is still the source index across pages.

---

## Senders, recent notices and the Look key

Notices come from someone, what the player missed can be read again, and one deliberate look shows everything.

### Senders

```lua
lib.registerSender('fleeca', { label = 'Fleeca', color = '#7fcf94', icon = 'F' })

lib.notify({ sender = 'fleeca', type = 'success', title = 'Deposit', description = '$2,500 deposited to checking.' })

-- a one-off sender, nothing registered
lib.notify({ sender = { label = 'Elena', color = '#e58cb4' }, description = "Car's out front." })
```

With a sender, the title line is the sender's label, your `title` becomes a bold lead line above the
description, and the coin holds the sender's mark in the sender's colour. A warning or error still turns the
label sand or red, so colour says whose and the state language says how bad.

| Field | Notes |
| --- | --- |
| `id` | 1-48 characters: letters, digits, `_ - . :`, starting with a letter or digit. Ids are shared by every resource; the first one to register an id owns it until it stops. |
| `label` | Required, up to 48 characters. Shown as the title. |
| `color` | `#rrggbb`. A colour too dark to read on the ink coin is lifted toward paper on screen. |
| `icon` | A built-in menu icon name, or one or two letters or digits, shown in capitals. Up to 64 characters. The first letter of the label is used when it is missing, unknown or an emoji. |
| `image` | `nui://resource/path.png` (png, svg or webp with transparency). Drawn as a one-colour mask in the sender's colour. |

`lib.registerSender(id, data)` returns `true`, or `false` and a reason: `invalid_sender_id`, `invalid_sender`,
`invalid_sender_label`, `invalid_sender_color`, `invalid_sender_icon`, `invalid_sender_image`, `sender_owned`,
`capacity_exceeded` (64 senders, 16 per resource). Registering your own id again replaces it.
`lib.removeSender(id)`, `lib.getSender(id)` and `lib.getSenders()` do what they say. A resource's senders are
removed when it stops. An unknown sender id on a notice is ignored and the notice shows without one.

From the server, pass `sender` (an id or a table) on the `cortex-lib:notify` event data. A malformed sender is
dropped on either side and the notice still shows, without one.

### Recent notices

Notices are kept in a log of the last 40, per client and for the session only.

| Notify field | Default | Effect |
| --- | --- | --- |
| `log` | `true` | `false` keeps this notice out of the log. Use it for noise such as a repeating hint. A notice that is not shown (Quiet notifications, or `capacity_exceeded`) is logged anyway, so nothing is lost. |
| `important` | `false` | `true` shows the notice even when the player has Quiet notifications on. |

A notice sent again under the same `id`, or repeated as a `dedupe` duplicate, updates its row and raises its
`count` instead of adding a row.

```lua
local entries = lib.getNoticeLog(10) -- newest first: id, noticeId (the id you gave lib.notify, if any), owner, type, title, description, sender, age (ms), seen, count, shown
lib.clearNoticeLog()                 -- removes your resource's entries

AddEventHandler('cortex-lib:noticeLogged', function(entry) end)
```

**Quiet notifications** (Settings > Notifications, off by default): only warnings, errors, persistent notices
and notices marked `important` appear. Everything else goes straight to the log with `shown = false`. An update
to a notice that is still on screen always goes through, so a persistent notice can be replaced or finished.
The NUI tells Lua when a notice leaves the screen (timed out, dismissed or pushed out by the visible limit), so
"on screen" follows what the player sees.

### The Look key

`+cortexpeek`, default `Z` (`setr cortex_lib_peek_key "Z"` sets the server default; players rebind it under
FiveM key bindings as "Cortex: look (HUD and recent notices)"). A tap shows for 3.5 seconds and a second tap
dismisses it; a hold shows until release, for at most a minute. While it is on, up to five logged notices that
are not already on screen (fewer when many are live, never fewer than two) list next to the live ones, away from the screen edge, newest first, with their age; ones the player
has already looked at are muted. Opening a radial counts as looking.

```lua
AddEventHandler('cortex-lib:peek', function(active) end) -- fires on each edge; false when cortex-lib stops
local looking = lib.isPeeking()

lib.peek(true)  -- hold the look open for your own surface (a phone, a wheel); false if 32 resources already hold it
lib.peek(false) -- release it; released for you if your resource stops
```

A hold from `lib.peek(true)` lapses after 10 minutes; call it again to keep it. A HUD wakes its hidden elements
while the look is on instead of binding its own "show" key. `cortex-hud` does.
While `LocalPlayer.state.cortexStreamerMode` is true (cortex-hud's Streamer Mode), sender notices in the list
show their sender and title only. `lib.getNoticeLog` is not masked.

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

- `note`, `more` and `blocked` are optional and only for anchored prompts. `note` (up to 64 bytes) is one line under the selected row. `more` (1 to 15) marks a row whose list should stay folded to its selected row, with a `+N` mark, until the wheel moves. Only rows on the selected row's key fold; rows on other keys and `blocked` rows stay on screen, and the selection starts on the first row that is not `blocked`. `blocked = true` draws a hollow disc with the label as the reason; a blocked row never takes a key, cannot hold, and reports `isInteractionVisible` only as "drawn".

### Markers and merged lists

World prompts are presented in two tiers, entirely by the renderer:

- **Marker** — a small 12u paper ring with no label, fading with distance. It shows between `maxDistance` and `markerDistance`, and also inside `maxDistance` while the player is neither next to the anchor nor looking at it. Nearby markers merge into one. Markers never make an entry `visible` and never authorize anything. Players can turn them off (Cortex settings: `promptMarkers`).
- **Prompt** — inside `maxDistance` the marker grows into the key disc and label once the player is within 1.5 m of the anchor or the anchor is within 16% of the screen height of the screen centre. It drops back to a marker past 1.8 m and 21%. A running hold keeps its prompt. Set `anchor.alwaysPrompt = true` to show the prompt anywhere inside `maxDistance`, as before.

While a prompt's key is physically held, its key disc sinks and its ring takes the accent colour, in world and screen prompts. This needs FiveM's `IsRawKeyDown`; without it prompts stay still. Punctuation keys are not tracked.

Prompt-tier anchors that project within ~6% of screen height of each other merge into **one list** at the highest-ranked entry's anchor: a rail with dots, the selected row with the full disc and large label, other rows with a dot (they share the selected row's key) or a small disc (they own a different key and stay usable). Up to four rows are visible; further rows fade out along the rail.

- **Same-key rows compete.** The selected row wins that key. `lib.isInteractionActive(id)` reflects the selection, so a consumer that gates its `+command` with `isInteractionActive` works unchanged. `lib.getInteractionState(id).active` changes when the player scrolls.
- **The wheel selects.** Only while a list that contains a key shared by two or more rows is the focused list (nearest the screen centre) does the renderer block the native weapon-wheel inputs and move the selection; a `WHEEL` hint sits under the list. It never takes the wheel when there is nothing to choose, while free-aiming, or over the pause menu. `invertScroll` flips the direction. The selection is frozen while any row's hold ring is running.
- **What the player can use wins.** An anchored entry in reach (inside `maxDistance` and on screen) claims its key ahead of any anchored entry that is out of range, off screen or only a marker, so a far registration can no longer silence the prompt in front of the player. When two separate lists in reach share a key, the list nearest the screen centre owns it whatever the priorities, so the player picks by looking; the owner keeps the key until another list is clearly closer to the centre (5% of screen height), and a running hold keeps it while its anchor stays in range, even if the player looks away. A prompt appears inside `maxDistance` and stays until the player is 0.15 m past it, so standing on the edge does not flicker. Inside one list, rows keep registry rank.
- **Rows are honest.** A row is only offered while its key's owner is in the same list. An entry that loses its key to another list (or to a higher-ranked screen prompt) degrades to a marker instead of showing a key that would run something else.
- **Screen prompts.** A screen prompt competes by `priority` only with anchored entries in reach. One that outranks every in-reach anchor sharing its key keeps world rows of that key out; one that is outranked is hidden only while that anchor is in reach, and returns when the player walks away or looks elsewhere.
- Leaving the list, removing the selected entry, or stopping its owner restores normal arbitration. If the selection moves a key away from an entry with a running hold, that hold is cancelled exactly as when it loses arbitration to a higher priority.

Design implication: give actions that belong together the same key (usually `E`) and the list lets the player choose; give an action its own key only when it must stay one press away.

**Rules**

- IDs are scoped to the invoking resource.
- Max **8 prompts per resource**, **16 total** in the client registry.
- Prompts are removed automatically when their owner resource stops.
- When keys collide, one prompt is active: the selected row of a merged world list first, then anchored prompts in reach (most-centred list first), then everything else by `priority` with screen prompts ahead of out-of-reach anchors. Gate screen actions with `lib.isInteractionActive(id)` and world actions with `lib.isInteractionVisible(id)`.
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

Key arbitration is recomputed only when the registry, the list selection or the set of in-reach key owners changes, so `lib.isInteractionActive(id)` is a direct owner-scoped lookup. World projection is frame-bound only while a prompt, hold or focused list is on screen; marker-only frames run at ~30 Hz (the NUI eases the steps), and with nothing in range the worker polls at 50-250 ms by distance. Stable entity bones reuse their lookup, unchanged frames (compared at whole pixels) do not cross the NUI bridge, and the React interaction surface is isolated from unrelated UI.

The scheduling follows the [Cfx `Citizen.Wait` guidance](https://docs.fivem.net/docs/scripting-reference/runtimes/lua/functions/Citizen.Wait): reserve `Wait(0)` for genuinely frame-bound work, adapt idle waits, and cache infrequently changing native results. The cache and points lifecycles are adapted from proven [ox_lib cache](https://github.com/overextended/ox_lib/blob/main/resource/cache/client.lua) and [points](https://github.com/overextended/ox_lib/blob/main/imports/points/client.lua) patterns while retaining cortex-lib's existing public values and callback timing.

---

## Things

A thing is an entity your script hands to cortex-lib together with what can be done to it. You stop drawing prompts, registering a key and checking distance. Needs the cortex-lib release after 3.7.0.

Client:

```lua
local machines = lib.thing({
    id = 'machine',
    range = 2.2,
    markerRange = 9.0,
    status = function(ctx) return ctx.data.soldOut and 'Sold out' or nil end,
    verbs = {
        { id = 'use', label = 'Use', server = true,
          run = function(ctx) openKeypad(ctx.data) end },
        { id = 'service', label = 'Service', server = true,
          can = function(ctx) return isMine(ctx.key) end,
          run = function(ctx) openService(ctx.data) end },
    },
})

machines:add(entity, { key = rec.id, data = rec, anchor = { offset = vec3(0.0, 0.0, 0.3) } })
machines:remove(entity)
machines:destroy()
```

- `key` is your own id for one instance: an integer or a short string. The server sees the key, never the entity.
- `can(ctx)` returns `true`, `false` (the verb is absent) or `false, 'reason'` (the reason shows as the status line).
- `label` is a string of up to 24 characters or a function returning one. Status lines and reasons are cut at 40.
- `hold = ms` makes the verb a hold. cortex-lib measures it and cancels it if the key is released or the prompt stops being usable.
- `stand = function(ctx) return coords, heading end` is where the character walks first. A point farther than `range` + 1 m from the entity is ignored. Reduced motion skips the walk.
- `run(ctx, reply)` is called after the server said yes and the walk ended. `reply` is whatever the server handler returned after `true`. `cancel(ctx, why)` is called if the use ends between the yes and `run`.
- `ctx` has `entity`, `key`, `data`, `coords`, `distance`, `verb`, `locked`, `hold()` and `done()`. The thing's prompt is hidden while `run` executes. Call `ctx.hold()` to keep it hidden after `run` returns and `ctx.done()` when the player is free again. The prompt also returns when the player's lock on the thing is released or runs out.
- `lib.thing.busy(true)` hides every thing while your script has the player (a phone, cuffs, a carry). It is cleared when your resource stops.
- Nothing shows while the player is dead or downed (`isDead` or `inLaststand` player state), ragdolling, in a vehicle, swimming, in NUI focus, in the pause menu, placing an object with `lib.placement` or in a skill check.

Server:

```lua
lib.thing.serve('machine', {
    coords = function(key)
        local m = Machines.get(key)
        return m and vec3(m.x, m.y, m.z), m and m.bucket
    end,
    verbs = {
        use = { range = 2.5, cooldown = 800, lock = 30,
                run = function(src, key) return canOpen(src, key) end },
    },
})

lib.thing.lock('machine', key, holder, seconds)
lib.thing.touch('machine', key, holder, seconds)
lib.thing.release('machine', key, holder)
lib.thing.holder('machine', key)
```

- `coords(key)` is required. A use is refused unless the player's ped is within the verb's `range` of that position and in that routing bucket. Return bucket `-1` for a thing that exists in every bucket.
- `coords` and `run` are called across resources: do not yield in them (no `Wait`, no awaited callback or query).
- `run(src, key)` returns `true`, `true, reply` or `false, 'reason'`. An error is a refusal.
- `lock = seconds` takes the thing's lock for the asking player before `run` and gives it back if `run` refuses. A player holds one such lock at a time until you renew it: after `touch` or `lock` it is yours and a later use elsewhere does not move it. Renew it with `touch` for as long as your session lasts; a lock you have not renewed is given back when the use ends on the client.
- `holder` is a player source or a string tag, so a script can hold the lock for an NPC. The four lock calls only reach things your own resource serves.
- A lock ends at `release`, when its lease runs out, when its player drops, or when your resource stops. It lives in cortex-lib's memory, so keep your own rules underneath it.
- The lock keeps two people off one thing. It is not a till: who gets the last item is still your sale code's decision.

Every thing shares the `+cortex_use` key and one quota of 8 prompt rows. Do not keep your own key mapping for a prompt you moved to a thing. List cortex-lib in your `dependencies` so your script restarts with it; things are not re-registered for a script that outlives a cortex-lib restart.
