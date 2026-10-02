# cortex-lib

Shared UI and Lua utilities for FiveM resources, maintained by Ever3st and GSD Modifications.

[![Version 3.0.0](https://img.shields.io/badge/version-3.0.0-blue?style=flat-square)](https://github.com/IEver3st/cortex-lib/releases)
[![MIT license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

![Cortex Lib: menus, radial menus and interaction prompts](https://raw.githubusercontent.com/IEver3st/cortex-lib/main/marketing/2026-09-27/final/01-cortex-lib.png)

**[Download cortex-lib.zip](https://github.com/IEver3st/cortex-lib/releases/latest/download/cortex-lib.zip)** · [Release notes](https://github.com/IEver3st/cortex-lib/releases) · [API reference](https://github.com/IEver3st/cortex-lib/blob/main/docs/api.md) · [Report a problem](https://github.com/IEver3st/cortex-lib/issues)

Install the library once and start it before the scripts that use it. The release ZIP includes the interface, React runtime and fonts. Server owners need no frontend tools or build step.

## What you can use

| Feature | Included behavior |
| --- | --- |
| Notifications | Success, info, warning and error notices, with configurable position, duration and sound. |
| Menus | Keyboard and mouse list menus, disabled rows, selectable values, nested radial menus and paging. |
| Dialogs | Text, password, number, select and checkbox inputs; required fields; confirmation and cancellation. |
| Progress and skill checks | Bars and circles with cancellation, completion feedback and configurable skill checks. |
| Interaction prompts | Screen prompts and world, entity or bone anchors; distant markers; merged lists; hold indicators. |
| Shared settings | Resource-owned tabs, search, live previews, Apply, Save and Discard, with preferences stored on the client. |
| Shared appearance | Accent, opacity, scale, text size, motion preferences and placement around participating overlays. |
| Lua utilities | Client/server callbacks, zones, points, raycasts, entity queries, control locks, timers and a live player cache. |
| Optional integrations | Server group-job helpers over `cortex-phone` and client vehicle replay telemetry. |

The library itself requires no framework or database. The `groups` module requires a running `cortex-phone` for group operations. Each consumer resource has its own gameplay, permissions and dependencies.

<details>
<summary><strong>View the interface</strong></summary>

| Notifications | List and radial menus |
| --- | --- |
| ![Notification examples](https://raw.githubusercontent.com/IEver3st/cortex-lib/main/marketing/2026-09-27/final/02-notifications.png) | ![List and radial menu examples](https://raw.githubusercontent.com/IEver3st/cortex-lib/main/marketing/2026-09-27/final/03-menus-and-radial.png) |
| **Input dialogs** | **Interaction prompts** |
| ![Input dialog example](https://raw.githubusercontent.com/IEver3st/cortex-lib/main/marketing/2026-09-27/final/04-input-dialogs.png) | ![Screen interaction prompt examples](https://raw.githubusercontent.com/IEver3st/cortex-lib/main/marketing/2026-09-27/final/06-interaction-prompts.png) |

![Shared settings interface](https://raw.githubusercontent.com/IEver3st/cortex-lib/main/marketing/2026-09-27/final/05-shared-settings.png)

These images use the bundled UI with browser demo data. They show the interface, not gameplay or performance measurements.

</details>

## Install

1. Download the attached **`cortex-lib.zip`** from [Releases](https://github.com/IEver3st/cortex-lib/releases). Use the version required by your consumer script.
2. Extract the complete `cortex-lib` folder into your server's `resources` directory. Keep that exact folder name, with `fxmanifest.lua` directly inside it.
3. Add the library before its consumers in `server.cfg`:

```cfg
ensure cortex-lib
ensure your-resource
```

A resource category such as `[cortex]` is optional. Install one copy of the library and keep every file in the release ZIP. Use the attached ZIP and its checksum; GitHub's generic source archives also contain development files.

After a new installation, run `refresh` in the server console, start the resources in that order and join the server. Open `/cortexsettings`, close it, then exercise the consumer's main feature. Check the server and F8 consoles for errors.

## Settings and server configuration

Players open **`/cortexsettings`** for the library and registered resource tabs. The Cortex tab controls interface size, text size, accent, opacity, motion, overlay placement, notifications, prompts and progress readouts. See the [settings reference](https://github.com/IEver3st/cortex-lib/blob/main/docs/api.md#settings) for defaults and field definitions.

Changes can preview while the menu is open. **Apply** saves and keeps it open; **Save & Resume** saves and closes; **Discard & Resume** restores the values from opening or the latest Apply. Closing with Escape discards unsaved changes. Preferences live in the player's client KVP storage and survive resource updates.

The optional Cortex quick menu is disabled by default. Configure it before the resource starts:

```cfg
# 0 keeps the native pause menu or another resource's menu. 1 enables Cortex.
setr cortex_pause_replace_native 0
setr cortex_pause_title "CORTEX"

# Keep diagnostics disabled on a normal server.
setr cortex_debug 0

ensure cortex-lib
```

Only the server controls the quick-menu switch. Players use FiveM's native keybinding editor for script controls.

| Command | Behavior |
| --- | --- |
| `/cortexsettings` | Opens shared settings. |
| `/cortexpause` | Opens the quick menu when enabled; otherwise opens settings. |
| `/cortexnative` | Opens the native map/pause frontend when input is available. |

## Update to 3.0

Version 3.0 redesigns the shared surfaces and changes these public contracts:

- The UI app API is removed: `registerUiApp`, `unregisterUiApp`, `openUiApp`, `updateUiApp`, `closeUiApp`, their exports and the `cortex:uiEvent` callback. Update consumers that use them before installing 3.0.
- Shared appearance settings now live in the **Cortex** tab. The separate Dynamic UI tab and per-resource appearance opt-outs are removed. Saved values for the retained appearance keys migrate automatically.
- World prompts gain distant markers and merged lists with mouse-wheel selection. Existing prompt registration remains valid; consumers still own the action and must check visibility and gameplay state.

See the [full changelog](https://github.com/IEver3st/cortex-lib/blob/main/CHANGELOG.md) before upgrading from 2.x.

Back up the installed library and any local edits, stop consumers, then replace the whole library folder. Start `cortex-lib` first and restart consumers afterward. Confirm settings, notifications, menu close behavior and each consumer's main flow. This update requires no SQL migration. Keep matching library and consumer versions together for rollback.

## Use it in a resource

Add the loader and dependency to your resource's `fxmanifest.lua`:

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

shared_script '@cortex-lib/init.lua'
dependency 'cortex-lib'

client_script 'client.lua'
```

The loader exposes `lib` and `cache` and resolves modules when they are used. The current loader explicitly checks the `lua54` declaration.

Show a notification from `client.lua`:

```lua
lib.notify({
    type = 'success',
    title = 'Vehicle stored',
    description = 'Your vehicle is safe in the garage.'
})
```

Register a menu once, then open it when the player needs it:

```lua
lib.registerMenu({
    id = 'garage',
    title = 'Garage',
    options = {
        { label = 'View stored vehicles', args = { action = 'list' } },
        { label = 'Close', args = { action = 'close' } }
    }
}, function(selected, _, args)
    print(('Garage selection: %s'):format(args.action))
end)

lib.showMenu('garage')
```

The [API reference](https://github.com/IEver3st/cortex-lib/blob/main/docs/api.md) covers callbacks, settings registration, zones, points, radial menus, prompts and telemetry. For prompts, register on state changes and remove them on exit. The consumer owns commands, key mappings, distance checks and permissions; privileged actions need server validation. Anchored prompts require `lib.isInteractionVisible(id)` before acting. A hold indicator only displays progress.

## Develop and validate

The source checkout includes a browser lab. With Bun installed, run:

```sh
bun run dev
```

Open `http://127.0.0.1:5196` for UI scenarios, mock callbacks, failure cases and viewport presets. No package installation or frontend build is needed. Read the [browser lab guide](https://github.com/IEver3st/cortex-lib/blob/main/docs/browser-lab.md) and [maintainer checks](https://github.com/IEver3st/cortex-lib/blob/main/tests/README.md) for coverage.

Pushes to `main` run contract tests, Lua specs and archive validation before the [release workflow](https://github.com/IEver3st/cortex-lib/blob/main/docs/automatic-releases.md) publishes a versioned ZIP and SHA-256 checksum. Static checks and browser fixtures do not establish FiveM, CEF, multiplayer or performance results. The [runtime acceptance checklist](https://github.com/IEver3st/cortex-lib/blob/main/docs/release.md) covers those checks.

## Troubleshooting and support

| Problem | Check |
| --- | --- |
| Resource not found or loader fails | Exact folder name, `fxmanifest.lua` location, consumer `lua54` declaration and start order. |
| Missing export or interface asset | Required library version; replace the complete folder instead of mixing releases. |
| Blank UI | F8 errors and the bundled `ui/`, `ui/vendor/` and manifest files. |
| Missing settings tab | The consumer must register a tab and start successfully after the library. |
| Unexpected Escape behavior | `cortex_pause_replace_native` and other pause-menu resources. |
| A setting reverted | Use Apply or Save & Resume; unsaved close paths roll back changes. |
| Input stays captured | Record the surface and close action, check F8, then restart the library and affected consumer. |

[Open an issue](https://github.com/IEver3st/cortex-lib/issues) with the library and consumer versions, start order, reproduction steps and exact console errors. For layout problems, include resolution, safe zone and a screenshot. Remove credentials and private player or server details from logs. Consumer gameplay and permissions belong to that resource's author.

## License

[MIT](LICENSE), copyright 2026 Ever3st. Bundled React and Barlow Condensed retain their licenses; see [Third-party notices](THIRD_PARTY_NOTICES.md). Consumer resources may have different terms.
