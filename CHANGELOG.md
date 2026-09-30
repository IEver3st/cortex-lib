# Changelog

## Unreleased

### Added
- The presentation adapter also writes `--cx-accent-deep` (the shared accent at mint-deep's lightness) for accent marks on paper.

### Changed
- The focus tint (`--state-focus-surface`) follows the shared accent instead of fixed mint.

## 3.0.0

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
- NUI split into `ui/core` (tokens, base helpers, shared kit) and one module per surface in `ui/surfaces`.
- Skill checks restyled to match cortex-minigames.
- Quick menu: removed the coloured edge glow and hairlines; hints use the shared keycaps.
