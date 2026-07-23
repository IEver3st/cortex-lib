# es_lib

![Version](https://img.shields.io/badge/version-2.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![FiveM](https://img.shields.io/badge/FiveM-cerulean-blue)
![Lua](https://img.shields.io/badge/Lua-5.4-purple)
![React](https://img.shields.io/badge/React-18-61DAFB?logo=react)

A lightweight, modular UI and utility library for the **Everest ecosystem** on **FiveM**. es_lib provides shared client/server helpers, lazy-loaded modules, HUD notifications, progress bars, menus, radial menus, zones, callbacks, and more through a single `lib` global.

> **Not affiliated with Cfx, FiveM, Rockstar Games, Take-Two Interactive, or any related entity.**

---

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Limitations](#limitations)
- [License](#license)

---

## Features

es_lib ships with the following modules:

| Module | Description |
|--------|-------------|
| `notify` | HUD notifications, progress bars, alert dialogs, text UI, helper methods |
| `callback` | Client/server callbacks with async and sync/await support |
| `menu` | Keyboard/mouse-driven NUI menus |
| `radial` | Radial (pie) menu with nested submenus |
| `zones` | Polygon, box, and sphere zone detection (`onEnter`, `onExit`, `inside`) |
| `points` | Distance-based point callbacks (`onEnter`, `onExit`, `nearby`) |
| `raycast` | Camera and coordinate raycast utilities |
| `getters` | Closest/nearby player, vehicle, ped, and object lookups |
| `disablecontrols` | Instance-based control disabling for movement, combat, car, mouse |
| `help` | Persistent keybind hint bar at the bottom of the screen |
| `settings` | KVP-backed settings registry with NUI settings menu |
| `timer` | Pausable/resumable timer class |
| `waitFor` | Repeat-condition helper with timeout |
| `utils` | Shared JSON, KVP, distance, table, and number utilities |

Additional client-only helpers are also exported from `client/utils.lua` and `client/debug_panel.lua` (pool clearing, ped/vehicle getters, camera direction, clipboard, debug panel).

---

## Installation

1. Copy or clone this repository into your FiveM `resources` directory (for example, `resources/[eco]/es_lib`).
2. Ensure `es_lib` starts **before** any resource that depends on it:

```
ensure es_lib
```

3. In each resource that uses es_lib, add to `fxmanifest.lua`:

```lua
shared_script '@es_lib/init.lua'
lua54 'yes'
```

> Lua 5.4 is **required**. es_lib will throw an error if `lua54 'yes'` is missing.

---

## Configuration

es_lib stores settings using the FiveM native `SetResourceKvp` / `GetResourceKvpString` API. The built-in settings tab lets clients configure:

- `notifySound` (boolean) — master toggle for notification audio
- `notifySoundPreset` (string) — default sound preset
- `notifyPosition` (string) — default notification position

Resources can register their own settings tabs via `lib.registerSettings` / `exports['es_lib']:registerSettings` and read values with `lib.getSetting`.

Example:

```lua
local settings = lib('settings') -- lazy-load the settings module
local value = settings.getSetting('notifySound')
```

---

## Architecture

- **`fxmanifest.lua`** — resource manifest: `cerulean`, `gta5`, Lua 5.4 enabled.
- **`resource/init.lua`** — internal `lib`/`cache` bootstrap for scripts inside es_lib.
- **`init.lua`** — external loader for other resources via `@es_lib/init.lua`; provides the same `lib` and `cache` globals with lazy module loading.
- **`imports/`** — modular, lazy-loaded Lua modules organized by `client/`, `server/`, and `shared/`.
- **`client/`** — directly loaded client utilities and the debug-panel bridge.
- **`ui/`** — React 18 NUI bundle (`index.html`, `app.js`, `style.css`) with vendored production React runtimes for notifications, menus, settings, and other UI surfaces.
- **`tests/`** — test commands and `debug_commands.lua` for in-game `/eslib` testing.

Module loading uses a lazy `__index` metatable: accessing `lib.notify`, `lib.zones`, etc. loads the corresponding `imports/<module>/<context>.lua` file. Shared files (`shared.lua`) are automatically prepended.

### Key exports

All functionality is available through the global `lib` table inside dependent resources. Cross-resource access is available via `exports['es_lib']`:

```lua
-- From another resource
exports['es_lib']:notify({ type = 'success', description = 'Hello!' })

-- Or use the lib global after loading the init
lib.notify({ type = 'success', description = 'Hello!' })
```

---

## Quick Start

```lua
-- Notification
lib.notify({ type = 'info', title = 'Hello', description = 'World!' })

-- Callback (server side)
lib.callback.register('myResource:getData', function(source, key)
    return { source = source, key = key }
end)

-- Callback (client awaits server response)
CreateThread(function()
    local data = lib.callback.await('myResource:getData', false, 'test')
    print(json.encode(data))
end)

-- Zone
lib.zones.box({
    coords = GetEntityCoords(PlayerPedId()),
    size = vector3(10, 10, 5),
    onEnter = function() print('entered') end,
    onExit = function() print('exited') end,
})
```

---

## Limitations

- Requires **Lua 5.4** (`lua54 'yes'`).
- `es_lib` must be started before dependent resources; startup order matters.
- Some modules are **client-only** (e.g., `zones`, `points`, `raycast`, `getters`, `radial`, `menu`, `help`, `disablecontrols`).
- Settings are stored per client in FiveM KVP storage; values are not shared between players.
- React and ReactDOM are vendored under `ui/vendor/`, so the runtime UI does not depend on a CDN.
- The bundled test command file is intended for development and should not be enabled in production.

---

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.

Copyright (c) 2026 Ever3st
