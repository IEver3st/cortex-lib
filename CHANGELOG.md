# Changelog

## 3.7.0 (2026-11-13)

### Added
- World screens: `lib.worldScreen` puts a web page on a prop's screen and lets the player point at it, with texture swaps, variant pools and cursor hit tests. See docs/api.md.
- Radial: a second style. Players pick **Wheel** or **Fan** in Settings > Interface > Radial menu style; `setr cortex_lib_radial_style fan` sets the server default. Fan lists the actions by name in a curved column to the right of the pointer, with the aimed row's description under it, so a radial can replace a small list menu.
- Radial: `title` on `lib.registerRadial` names the menu, shown in the idle hub or above the fan.
- Radial: items take `badge` (a count or short tag) and `confirm` (true or a message). A confirm item turns red on the first select and runs on the second, a guard against slips on destructive actions (not a permission check).
- Radial: controller support. The right stick aims, A selects, B goes back, RB / LB change pages.
- Server accent colours: `setr cortex_lib_accents "Name=#rrggbb;Other=#rrggbb"` puts up to 8 of your own swatches first in Settings > Shared accent, and `setr cortex_lib_accent_default "#rrggbb"` sets the default (on its own, it adds that colour as a "Server" swatch when it isn't one of the built-in ones).

### Changed
- Settings: a resource's tab can hold up to 128 fields instead of 64. Cortex Echo needs this to show shape and colour pickers for all of its sounds.
- Radial: redesigned. One to three items are wide petals instead of thin slips, and two items sit left and right. The hub shows the menu title (or the label that opened a submenu) instead of the full breadcrumb, and an unknown icon name shows the item's label instead of a monogram.

### Fixed
- Italic titles, values and key hints in menus, dialogs, the radial, the pause menu and Settings no longer lose the edge of their last letter.
- A progress bar cancelled while its animation or prop was still loading no longer starts that animation or spawns the prop afterwards.
- Thermal: night light volumes (streetlight and lamp haze from graphics packs such as QuantV) no longer show as large flat blobs in thermal views. Cortex PolCam and Cortex Binoculars both get the fix.
- Copy to clipboard works in the FiveM browser again.

## 3.6.0 (2026-11-04)

### Added
- Volumetric lights: `glareSize`, `glareGrowth`, `glareFocus` and `glareLift` shape the glare at the lamp. The defaults keep the old glare.

### Fixed
- Settings: a resource's saved settings could read back as defaults after a relog, or after that resource restarted, so Cortex Chat and other scripts ignored what the player had saved even though Settings showed it. cortex-lib now finds a resource's settings the first time it asks for them, not only at startup.

## 3.5.0 (2026-11-01)

### Added
- Settings has its own key: **I** opens it on every server, with or without cortex-hud. Players rebind it in Settings > Key Bindings > FiveM ("Cortex: open settings"); `setr cortex_lib_settings_key <key>` changes the default, and `""` leaves it unbound. The manifest declares `cortex_settings_key '1'` so consumers can skip binding their own.
- Callout styles: `lib.showCallouts({ style = ... })` picks one of four looks. `ink` is the default and unchanged; `slip` puts each row on an ink slip with square pins; `paper` makes paper tags with ink chips, paper leaders and diamond pins; `draft` uses upright lettering, underlined chips, leaders that end on a bar and ring pins. Every style keeps the same sizes, so labels sit in the same places. `lib.getCalloutStyles()` lists them, and `lib.prepareCallouts(style)` paints the pins in the style the first session will use.

### Changed
- Settings is a script library: scripts are listed down the left, grouped Everyday, Equipment, Activities, Staff and Other with a setting count each, with search at the top. The open script's title and count sit above its settings, and its sections are chips beside the Advanced switch. The horizontal tab strip and the section list are gone. Resources pick their group with `{ group = '...' }` on `registerSettings` or a `group` field in their settings definition; Cortex resources are placed automatically.
- Keycaps: menus, Settings, dialogs and the quick menu draw an opposite arrow pair as one axis keycap, as world prompts already did, and Backspace reads BKSP everywhere.
- Quick menu: brought in line with the Cortex design rules with the same layout. Panels use the shared neutral ink instead of a teal tint, every colour comes from a token, rings and rules are at least 3u, and the clock colon, session dot, beacons and terrain no longer loop. Small labels are larger and higher in contrast.
- Radial: the legend no longer repeats RMB Back/Close; the centre already names it.
- Settings: the Escape hint reads "Discard & resume", which is what it does.

### Fixed
- Settings: Save and Apply only write the settings that changed. They used to rewrite every setting of every tab to disk, which spiked cortex-lib's CPU for a second or two on each save.
- Settings: Escape while searching clears the search and keeps unsaved changes; the next Escape leaves. It used to discard and close at once.
- Settings: the count reads "1 RESULT" and "1 SETTING" instead of "1 RESULTS".
- Dialogs: the Cancel and Confirm row lines up with the fields above it.
- Notifications: the "+N held" count, and the progress cancel hint, are body size so they stay legible at 720p.
- Settings: the search bar and text fields drew the browser's grey input border inside their ink well, so search showed a box within a box. Both now reset it, like the hex and dialog inputs.
- Settings reopens on the tab, section and Advanced switch the player last used instead of jumping back to Cortex. The place is matched by tab id and kept across reconnects; if that tab is gone, Settings opens on the first tab.
- Notifications: a notice sent without a title and longer than one short line used to show as bare body text with no display title. It now takes its title from its own lead: the text before a colon ("Applied Parka layers: ..."), or a short first line or first sentence. Copy with no lead is titled by its type (Done, Notice, Warning, Error). Notices that already have a title, and short single lines, are unchanged.
- Callouts: a leader that ran straight into another pin used to lose its label to hover. It now steps round the pin: a label beside the entity steps up or down within its first row, and a label above goes along to either end first. Layouts that already routed clear are unchanged. The `draft` bar sits across the first row wherever the leader meets it.

## 3.4.0 (2026-10-18)

### Added
- World prompts and lists are drawn by the game from one DUI texture and pinned to their anchors at render time, so they no longer trail or stutter when the camera turns. If the DUI cannot load, the previous NUI layer takes over. Turn it off with `set cortex_lib_world_dui 0`.
- World markers (the dot and ring) are drawn natively for the same reason, and fade in.
- Key glyphs: an opposite arrow pair ("← →", "↑ ↓") shows as one axis glyph.
- Callouts (`lib.showCallouts`): pins on the parts of a vehicle or any entity, each joined by a square leader to a label beside it, with a block of switches. The player points with the game's cursor and clicks while still driving or walking; nothing takes NUI focus. Display only: the calling resource decides what every label says and acts on `select`, `wheel` and `closed` events. Labels are drawn by the game from one DUI texture pinned at render time and fall back to game text if the DUI cannot load. See **Callouts** in `docs/api.md`.

### Changed
- Settings: when the tabs no longer fit on one row, the row scrolls sideways, with arrows at both ends that page it. An arrow shows a dot when a tab with unsaved changes is scrolled out of view on that side.
- License: Cortex Library now ships under the Cortex Library Free Use License instead of MIT. It stays free to use and modify on servers you own or run, including commercial ones; it may not be sold or redistributed. Share the official download link.
- Drop-in update. Restart cortex-lib before the resources that use it.

### Fixed
- Settings: a controller's left and right switch tabs. They used to move focus off the tab row, so only the first tab could be opened.

## 3.3.1 (2026-10-12)

### Added
- Update check: on start the server asks GitHub once for the latest release and prints `Update available: <version>` with the download link when it is newer than the installed library, or `Version <x> is up to date`. A failed check prints one line and changes nothing. Turn it off with `set cortex_lib_version_check 0` in server.cfg.

## 3.3.0 (2026-10-12)

### Added
- Radial menus: `releaseSelect = true` on `lib.registerRadial` lets a hold-to-open key select the item under the pointer when released. Releasing over nothing leaves the menu open. Off by default.
- Menu icons: `traffic-cone`, `road-barrier`, `work-light` and `scene-marker`.
- Prompts and notices step around the voice indicator (`.cx-voice-shell`, `.voip-container-modern`) as they do around the location plaque.

### Fixed
- `lib.placement`: mouse-button bindings register through the mouse mapper (they were left unbound), left click confirms whatever an older saved binding says, and map geometry no longer reads as an invalid surface. Only peds and vehicles are refused.
- Target interaction panels keep their keys inside the panel when a long
  player or target label truncates, including at 720p.
- The controls legend reports its full height to HUDs that share the bottom-right corner (`LocalPlayer.state.cortexHelpLegend`). It was measured while still sliding in, so it came up about 6 units short and the cortex-hud voice indicator sat on the legend's top edge. It is now measured from layout, and measured again after the entrance, on resize and when the safe zone changes.

## 3.2.0

### Added
- Cortex settings → Graphics → **Volumetric lights** (`volumetricLights`, off by default). `lib.volumetric.playerEnabled()` and
  `onPlayerSetting(fn)` let a lamp follow it live (preview, Discard, Save); cortex-flashlight and gsd-arges
  use it, cortex-polcam does not and keeps its beam.
- `lib.volumetric` option `openFade`: how much of a beam that lands on nothing fades out (default 0.2, unchanged for cortex-polcam and gsd-arges). Rings are packed towards the lamp, so 0.2 is a single segment and seen down the beam it reads as a straight cut; cortex-flashlight uses 0.65.
- Interaction prompts and markers hide while `LocalPlayer.state.cortexCharacterSelect` is true (set by cortex-multicharacter) and come back when it clears; registrations are kept.

### Fixed
- `lib.volumetric`: a moving lamp's beam ends where its axis meets the surface this frame. The length came from a ray up to 90 ms old, cast from where the lamp was then, so a torch swinging as its holder walked had its beam end step about ten times a second. The ray now only finds the surface; the distance is re-solved against it every frame, except when the axis has swung off it, where the ray distance stands until the next ray.
- Settings: nothing could be saved (Apply failed / Save failed) when any registered tab had a stale stored value, such as an option the tab no longer offers or a slider value outside its range. Save sends every tab and one invalid value rejected the whole batch. Registered tab values are now checked on load like the Cortex tab's and fall back to the default; a rejected Save names the tab and key in the F8 console. `tests/settings_stale_values_spec.lua`.
- `lib.vehicleReplay`: wheel natives are looked up through the environment instead of `rawget`, so FiveM's lazily created native wrappers are found.

## 3.1.0

### Added
- Consumer-local `lib.placement` model loading and cancellable placement preview with bounded asynchronous surface probes, session-owned input and independent cleanup. The consumer server owns authorization, accounting and entity creation. See `docs/placement.md`.
- Help legend: publishes how far it reaches up from the bottom of the screen as `LocalPlayer.state.cortexHelpLegend` (NUI px, 0 when hidden, local only), so HUDs in other resources can keep the bottom-right corner clear.
- `lib.sensors` (`imports/sensors/client.lua`): the FLIR thermal and phosphor night vision sensors,
  moved out of cortex-polcam so other optics share them. Thermal palettes override and restore the
  seethrough visual settings; night vision grades a timecycle modifier with automatic gain, a manual
  knob and caller-supplied bright-source protection. Resources without the `lib` loader can include
  the file as a client script and use the `CortexSensors` global. See `docs/sensors.md`.

### Fixed
- Radial items registered from another resource were rejected (`invalid_item`) or never fired: their
  `onSelect` arrives as a Cfx funcref (a callable table), and validation and dispatch only accepted Lua
  functions. Both now accept callables; `tests/radial_funcref_spec.lua` covers it. The removed per-resource
  `.menu-shell` background for `cortex-emotemenu` no longer overrides that resource's own surface.

### Validation
- Six placement fixture scenarios and two independent cleanup regression probes pass. FiveM input, model grounding and CEF calibration remain pending user acceptance.

## 3.0.0

### Action required
- Update consumers using the removed UI app API before upgrading. Replace the complete library folder, then restart cortex-lib before consumers. No SQL migration is required.

Every shared surface redesigned to `CORTEX-DESIGN.md`; see `DESIGN.md` for the brief behind each one.

### Breaking
- Removed registered UI apps: `registerUiApp`, `unregisterUiApp`, `openUiApp`, `updateUiApp`, `closeUiApp`
  (and their exports), the `cortex:uiEvent` callback and the bundled weather-zone editor.
- Removed the **Dynamic UI** settings tab and the per-resource "independent appearance" switches. Shared
  accent, surface opacity, motion and overlap avoidance moved to the Cortex tab under the same storage keys;
  saved values migrate automatically.
- World prompts now sit with the key disc on the anchor and the label to its right (lists, markers and single
  prompts share one anatomy). Consumers need no changes.

### Added
- Server group-job helpers over cortex-phone, with unavailable-service fallbacks and registration replay after phone restarts.
- Shared vehicle wheel-speed and suspension telemetry for Director and Rewind.
- Custom six-digit hex accents alongside the built-in colour presets. Dark accents are lightened for readable ink text.
- The shared presentation adapter supplies an accent-derived deep colour for marks on paper.
- Interaction **markers** (a small dot in a ring between `maxDistance` and the new optional
  `anchor.markerDistance`) that grow into the full prompt in range.
- Merged interaction **lists**: nearby prompts become one GTA-style list; the mouse wheel picks the row that
  owns a shared key. `isInteractionActive` follows the selection.
- Player settings: UI scale, text size, control hints, notification duration and limit, distant markers,
  prompt size, invert list scroll, progress percentage. Pushed to the NUI as `cortex:prefs`.
- Settings darken the screen and blur the game natively while open.
- Menu: `disabled` rows, Home/End/PageUp/PageDown, wheel scrolling, `‹ value ›` chevrons.
- Radial: direction selection from anywhere on screen, number keys 1–8, Q/E/wheel paging with page dots,
  optional `description` and `disabled` items, breadcrumbs, remembered page.
- Dialogs: number stepper with optional `min`/`max`/`step`, password reveal, required-field validation.
- Help (`lib.showHelp`) is a bottom-right controls legend; text UI renders `[KEY]` tokens as keycaps.
- Progress end reports completion; completed and cancelled states are shown.
- Skill checks: `sensitivity` option for trace; one smooth sweep completes it (wobble and pauses no longer
  reset it). `mash` and `trace` games added to cortex-minigames.

### Changed
- Focus tint follows the selected shared accent.
- NUI split into `ui/core` (tokens, base helpers, shared kit) and one module per surface in `ui/surfaces`.
- Skill checks restyled to match cortex-minigames.
- Quick menu: removed the coloured edge glow and hairlines; hints use the shared keycaps.
