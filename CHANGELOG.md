# Changelog

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
