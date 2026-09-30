# Cortex debug menu

Diagnostics are disabled in the release defaults. On a development server, add
`setr cortex_debug 1` before `ensure cortex-lib` in `server.cfg`.
Remove that override (or set it to `0`) and restart after testing. This enables
local diagnostics for all clients; it is not an ACE permission.

Restart `cortex-lib`, then its consumers. Enter `/cortexdebug` in chat (or
`cortexdebug` in F8). The shipped command opens a resolution-scaled right-side menu (310px at 1080p, 620px at 4K);
the legacy development-only `/cortex` script does not need to be enabled.

Movement and camera stay available, with no mouse cursor or fullscreen backing.
Scroll up/down to select; left-click enters a category or runs a test; right-click
goes back and closes at the root. Arrow keys, Enter and Escape also work.
**Test All** runs every catalog scenario sequentially, including the native skill
checks. Passive samples stay visible for the selected duration after execution;
interactive samples wait for you to complete or close them. The run shows the
completed count, percentage and current test in Cortex's shared progress bar at
screen center. The debug menu stays hidden throughout, including between tests;
it returns when the run finishes. Progress advances by completed scenarios, not
an estimated timer. The aggregate meter remains independent of progress samples.
Unavailable integrations record an error and the walkthrough continues.
Use `/cortexdebug` to stop and return to the menu.
**All tests** lists individual scenarios and results. **Test options** cycles duration, notification
placement and sample messages using left/right arrows or left-click.

Passive tests keep the menu visible and put their result below the selected row.
Starting another test removes the previous test's fixtures. Tests that open a
dialog/menu/settings or external minigame receive focus and hide the debug menu;
closing or completing the sample returns automatically to the same category and
selected row. Native map/settings handoffs finish before the workbench returns. **Clear active tests** removes fixtures and history.
Closing the menu cancels the walkthrough and removes its temporary fixtures. Mouse buttons/weapon scrolling are consumed while navigating, including
the closing click until release. Nothing runs on startup.

## Catalog

| Category | Scenarios |
| --- | --- |
| Notifications | Single event, four status types, long text, persistent/update, plain/icon-free; six placements, four message samples and 1–15 second duration |
| Progress | Linear, circular, non-cancelable |
| Prompts | Floating/backed Text UI, compound key hints, local debug telemetry |
| Menus | List controls, long scrolling list, standard/paginated/compact radial |
| Dialogs | Confirmation, input/checkbox/select form |
| Interactions | Screen, target panel, world/entity/bone anchors, hold/cancel ring, key arbitration |
| Settings and input | Real settings, quick menu/native handoffs, timed combat suppression |
| World and utilities | Sphere/box/poly zones, proximity point, camera raycast, nearby entities/cache, timer, waitFor, JSON/math/table helpers, asset loading, server callback |
| Integrations | Installed ox_lib skill check |
| Skill checks | Native radial timing, upper/lower trace, hold/release, key sequence and 3D reactive mash |

These catalog scenarios exercise public features, not every argument combination.
World tests use your current location; walk out of and back into their range.
The F7 interaction prompt is display-only and runs no gameplay action. The hold
scenario starts and cancels its presentation ring automatically.

## State and prerequisites

- Temporary notices and interactions use reserved debug IDs. Most fixtures
  expire after 20 seconds when run individually. Interactive samples wait for
  their own close lifecycle. Returning to the workbench or stopping the resource also cleans them up.
- Actual settings retain their normal Save/Discard lifecycle. Saving changes
  your preferences. The native debug mash binding is inert outside its specimen;
  cleanup releases its input state.
- A menu owned by another consumer must be closed before opening the workbench.
  Settings, dialogs and native handoffs keep their own close/rollback lifecycle.
- The external timing minigame requires a started `ox_lib`; the separate native
  skill-check category has no ox_lib dependency.
- The server probe returns a fixed diagnostic response through the existing
  callback transport. It performs no gameplay mutation or privileged command.
- Only catalog IDs execute; the NUI cannot supply code, event names, commands,
  or resource names. Stale sessions and malformed options are rejected.

## Validation and user-run acceptance

Static checks: `node --test tests/*.test.mjs`, `node --check ui/app.js`,
`node --check ui/debug.js`, `lua tests/debug_workbench_spec.lua`, relevant
existing lifecycle specs, and the resource/NUI validators. Component tests
execute element trees, not browser or FiveM rendering.

In game:

1. Open and walk/drive while moving the camera. Scroll both directions, use
   left-click to enter/run and right-click to back out. Check keyboard arrows,
   Enter/Escape, list wrapping, all tests and test options. Hold the closing click
   briefly and release: it must not fire a weapon or aim after the menu closes.
   Confirm passive tests retain the menu, modal tests receive focus, and stopping
   the resource restores input with no overlay. Close a sample and confirm the
   same category/selection returns; close the root to exit entirely. Run Test All,
   finish/close interactive samples, and confirm every catalog entry is attempted.
   Check that the menu stays hidden, the centered bar counts completed tests,
   progress samples still work independently, and 100% returns to the menu.
   Stop midway and confirm nothing advances or reopens. Repeat during a native
   pause handoff and with an unavailable integration.
2. Inspect all notice types, long text, six positions and plain/persistent
   variants against bright and dark scenes at 720p, 1080p, ultrawide and 4K where
   available. Check the fine grain, compact sentence-case text, wrapping and countdown.
3. Complete/cancel both progress shapes; reopen during progress. Test list and
   radial choices, form values, dropdown scrolling, Save/Discard and Escape.
4. Check anchors in/out of range, off-screen, entity deletion/model changes,
   key collisions, hold cancellation and resolution/safe-zone changes.
5. Stop/restart during a test and confirm temporary overlays and input ownership
   disappear. Test integration prerequisites and the real server callback.

Live FiveM/CEF appearance, focus, safe-zone projection and performance remain
user-run acceptance checks. Static success does not establish those results.
