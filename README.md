# cortex-lib

Shared settings, notifications, menus and UI utilities for Cortex FiveM scripts.

![Version 3.0.0](https://img.shields.io/badge/version-3.0.0-blue?style=flat-square)
![License MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)

If a script you bought requires **cortex-lib**, install it once on your server and start it before that script. You do not need to edit Lua, install Node.js, or build the interface.

This guide covers **3.0.0**. Use the matching ZIP from [Releases](https://github.com/IEver3st/cortex-lib/releases), or the dependency package supplied with your script. The main branch may contain work that has not been released yet.

[Installation](#installation) · [PolCam](#using-cortex-lib-with-polcam) · [Settings](#player-settings) · [Configuration](#server-configuration) · [Updating](#updating) · [Troubleshooting](#troubleshooting)

## What it provides

- Notifications, progress indicators, dialogs and menus.
- On-screen and world interaction prompts.
- A settings menu with pages for compatible scripts.
- Shared appearance and automatic placement for participating overlays.
- An optional quick menu for the map, settings and key bindings.
- Developer utilities, including callbacks, zones and skill checks.

Gameplay, jobs and permissions belong to the script using the library. Installing cortex-lib does not make an unrelated script compatible with it or replace `ox_lib`, ESX or QBCore when another resource requires them.

## Browser UI development

In a source checkout, run `bun run dev` and open **http://127.0.0.1:5196**.
No install or build step is needed. The browser lab loads the real UI with named
scenarios, editable NUI messages, mock callbacks, settings persistence, failure
injection, viewport presets, and automatic reload on edits.

See [the browser lab guide](docs/browser-lab.md) for controls, coverage, and the
FiveM-only acceptance cases. This is development tooling; customer ZIPs keep
the existing offline UI payload.

## Requirements

| Requirement | Details |
| --- | --- |
| FiveM server | GTA V / `cerulean` runtime. Follow the server requirements supplied with your purchased script. |
| Folder name | Exactly `cortex-lib`. |
| Start order | Before every script that depends on it. |
| Framework or database | None required by cortex-lib itself. |
| Frontend tools | None. The interface, React and fonts are bundled. |

OneSync, game-build, framework and access requirements for a consumer such as PolCam still apply. The library does not configure them for you.

## Installation

### 1. Extract the resource

Download the version your script requires from [Releases](https://github.com/IEver3st/cortex-lib/releases). Use the named `cortex-lib-v<version>.zip` release asset when available.

Extract it into your server's `resources` directory. A category such as `[cortex]` is optional:

```text
resources/
└── [cortex]/
    ├── cortex-lib/
    │   ├── fxmanifest.lua
    │   ├── init.lua
    │   ├── client/
    │   ├── imports/
    │   ├── resource/
    │   └── ui/
    └── your-cortex-script/
```

This example shows only part of the library. Keep every file in the release ZIP.

`fxmanifest.lua` must be directly inside `cortex-lib`. Avoid nested folders such as `cortex-lib/cortex-lib/fxmanifest.lua`. Rename `cortex-lib-main` to `cortex-lib` if you downloaded the source archive.

### 2. Set the start order

Add these entries to `server.cfg`, replacing the second resource name with your script's actual folder name:

```cfg
ensure cortex-lib
ensure your-cortex-script
```

Install only one copy of cortex-lib, even when several scripts use it. Check for duplicate copies in other resource categories.

### 3. Choose the Escape behavior

The **quick menu is off by default**. Escape keeps GTA's native pause menu or the menu supplied by another resource. No configuration is required.

Only the server owner can enable the quick menu. To use it, place this before `ensure cortex-lib`:

```cfg
setr cortex_pause_replace_native 1
ensure cortex-lib
ensure your-cortex-script
```

Set the value to `0` to disable it again. Players cannot change this option in Cortex Settings. Shared settings remain available through `/cortexsettings` either way.

### 4. Start and check

Restart the server, or enter these commands in the **server console** after a new installation:

```text
refresh
ensure cortex-lib
ensure your-cortex-script
```

Join and enter `/cortexsettings` in chat. Confirm that settings open and close, then check the dependent script's main feature. Check the server console and the player's F8 console for errors.

Purchased scripts should already include their library integration. Do not add `@cortex-lib/init.lua` to them yourself unless their author instructs you to.

## Using cortex-lib with PolCam

The PolCam 1.0.2 code prepared with this library requires **cortex-lib 2.2.1**. The older 2.2.0 release does not contain its shared presentation files. Install the matching library package before updating PolCam.

Keep both resource names unchanged:

```cfg
# Default: keep the Cortex quick menu disabled.
setr cortex_pause_replace_native 0

ensure cortex-lib
ensure cortex-polcam
```

Configure helicopters, access, camera controls and optional integrations in PolCam's own configuration and documentation. Its **PolCam** settings page provides high-contrast and target-label preferences. Camera operation and key mappings remain part of PolCam.

When updating both, restart cortex-lib first and PolCam second. If its settings page is missing, check both resources' startup errors and the installed library version.

## Player settings

Enter `/cortexsettings`. Cortex Settings opens over a darkened, heavily blurred view of the game, with tabs for the library and compatible scripts. It has no quick-menu back arrow, game-settings tab or keybinding link. A script appears when it registers a settings page; installing a resource does not automatically give it a page.

### Save, Apply and Discard

- **Apply** saves changes and keeps the menu open.
- **Save & Resume** saves changes and closes the menu.
- **Discard & Resume** restores the values from when the menu opened, or from the most recent Apply, then closes it.
- Unsaved changes may preview immediately. Closing without saving rolls them back.

Escape closes an open dropdown first, then closes settings and discards unsaved changes. This works the same way whether the quick menu is enabled or disabled.

Preferences are stored on each player's computer using FiveM client storage. They are not shared between players or synchronized to another computer. Updating the resource does not reset them, so returning players may see different values from a fresh installation.

### Cortex options

The **CORTEX** tab is grouped into Interface, Notifications, Prompts and Progress. Changes preview immediately (Interface size and Text size resize the open menu too); each changed row shows a mint mark and a reset-to-default button.

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

Scripts can supply their own notification options, so these defaults do not override every notification.

Shared accent, surface opacity, motion and overlap avoidance apply to every participating Cortex resource. The former **Dynamic UI** tab and its per-resource "independent appearance" switches were removed; saved values for the four kept settings move to the Cortex tab automatically. Automatic placement does not overwrite saved positions, and crowded screens may still have overlaps. These controls cannot reposition every third-party interface on your server.

## Commands and key bindings

Enter player commands in chat with the slash shown:

| Command | Purpose |
| --- | --- |
| `/cortexsettings` | Opens shared settings. |
| `/cortexpause` | Opens the quick menu if the server enables it; otherwise opens Cortex Settings. |
| `/cortexnative` | Opens GTA's native map/pause frontend when no conflicting menu owns input. |

Use GTA's native keybinding menu for GTA and FiveM script mappings, including PolCam's registered controls. If the server enables the quick menu, its **Key bindings** action also opens this native editor.

The library does not include a separate binding editor. Scripts own their controls and register them with FiveM.

Saved FiveM bindings take precedence over a script's original default keys. Reinstalling cortex-lib does not reset them.

## Server configuration

Configure the library in `server.cfg` **before** it starts. You do not need to edit the resource's Lua files:

```cfg
# Default 0: retain the native/other pause menu. Set 1 to enable Cortex.
setr cortex_pause_replace_native 0

# Quick-menu title, up to 48 bytes.
setr cortex_pause_title "CORTEX"

# Keep development diagnostics disabled on a normal server.
setr cortex_debug 0

ensure cortex-lib
```

The quick-menu switch can also be changed immediately in the **server console** with `setr cortex_pause_replace_native 1` or `setr cortex_pause_replace_native 0`. Keep the same value in `server.cfg` so it survives a server restart. These replicated settings are controlled by the server; there is no player quick-menu preference. Disabling the quick menu while it is open switches it to Cortex Settings.

For a controlled troubleshooting session, `setr cortex_debug 1` enables `/cortexdebug` after a restart. It exposes interactive test actions. Disable it afterward. Normal use does not require it, and the legacy `/cortex` test menu is not shipped.

## Updating

1. Check each dependent script's required version and read the release notes.
2. Back up the library folder and any local modifications.
3. Stop dependent scripts before replacing files. Schedule updates when players are not using their interfaces.
4. Replace the complete `cortex-lib` folder. Do not mix files from different releases.
5. Start cortex-lib, then its dependent scripts.
6. Check settings, notifications and each script's main feature. Confirm that closing menus returns control to the game.

For an installed PolCam pair, server-console restart order is:

```text
restart cortex-lib
restart cortex-polcam
```

Restart other cortex-lib consumers afterward. This version needs no SQL migration. Keep previous library and consumer versions together if you need to roll back.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Server cannot find cortex-lib | Use the exact folder name, with `fxmanifest.lua` directly inside. Run `refresh` after installation. |
| A script says cortex-lib must start first | Place its `ensure` after the library, then restart in that order. |
| Missing export or `presentation-client.lua` | Check the required version and replace the whole library folder. PolCam's current shared UI needs 2.2.1. |
| `Lua 5.4 is required` | The script using the library facade must declare `lua54 'yes'` in its manifest. The loader checks this metadata. Ask its author for a compatible build. |
| Blank or missing interface | Check F8 errors. Keep `ui/`, `ui/vendor/` and the manifest from the same package; do not remove runtime assets. |
| Escape opens an unexpected menu | Check `server.cfg` for `cortex_pause_replace_native 1`. Set it to `0` to disable Cortex's quick menu; check other pause-menu resources too. |
| A menu will not open | Close another focused interface or native pause menu first, then retry. Cortex avoids taking focus from another menu. |
| A script's settings page is missing | Confirm it supports shared settings and started successfully. Restart it after cortex-lib. |
| A preference reverted | Use Apply or Save & Resume. Discard and unsaved close paths restore earlier values. |
| Old settings remain after an update | Client preferences and bindings survive updates. Change them in settings or the native binding editor. |
| Controls stay stuck after closing | Note the menu and closing action, check F8 errors, then restart the library and affected script. Reconnect if necessary. |
| Unexpected overlay position or appearance | Check the Interface section of the Cortex tab, the script's appearance options and GTA's safe-zone/display settings. Other UI resources may have separate controls. |

Avoid deleting a player's entire FiveM storage to fix one preference. Change the relevant setting or binding through its menu first.

## Getting help

Open a [GitHub issue](https://github.com/IEver3st/cortex-lib/issues) for library problems. Include:

- cortex-lib's version from `fxmanifest.lua` and the affected script's version.
- The relevant `server.cfg` start order and Cortex settings.
- Steps to reproduce and the menu or gameplay action involved.
- Exact F8/server errors; for layout issues, a screenshot, resolution and safe-zone setting.
- Whether it happens after a fresh connection, a resource restart, or both.

Remove license keys, tokens, player identifiers and private server details before posting logs. Contact the purchased script's author for its gameplay, permissions or configuration issues.

## For script developers

The [developer API reference](https://github.com/IEver3st/cortex-lib/blob/main/docs/api.md) covers the loader, exports, callbacks, interaction prompts and settings registration. Source checks and developer documentation are excluded from the customer ZIP.

## License and credits

cortex-lib uses the [MIT license](LICENSE), copyright 2026 Ever3st. Dependent scripts may have different licenses and purchase terms.

React and Barlow Condensed are bundled with their licenses; see [Third-party notices](THIRD_PARTY_NOTICES.md). FiveM, GTA V and related marks belong to their respective owners. This project is not affiliated with or endorsed by Cfx.re, Rockstar Games or Take-Two Interactive.
