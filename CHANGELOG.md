# Changelog

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
