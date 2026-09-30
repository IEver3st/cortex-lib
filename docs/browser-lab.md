# Browser UI lab

From the resource checkout:

```sh
bun run dev
```

Open **http://127.0.0.1:5196**. No install or build step is required. To use a
different port: `bun run dev --port 5197` (or set `PORT`). The server binds only
to loopback. Ctrl+C stops it. Changes to `ui/` or `dev/` reload the lab and keep
the selected scenario in the URL hash.

The lab serves the actual `ui/index.html`, React vendor files, styles and
components. Only the served preview response receives a browser bridge and
local replacements for the existing Cfx asset URLs. No shipped UI source,
FiveM manifest, or production loader needs a dev flag or localhost URL.
`dev/` and `package.json` are outside the release workflow's allowlist.

## Working with scenarios

- Search the catalog or use Previous / Next. Replay starts the selected scene
  in a fresh iframe; Clear stage removes everything, including active timers.
- Tour all displays every scenario in sequence. Stop it to interact at your own
  pace. **Visited means displayed, not an automated pass.** Switching away from
  the tab stops the tour.
- Choose 720p, 1080p, 1440p, ultrawide, or Fit. Fixed presets set the real iframe
  viewport, then scale its presentation to fit the stage. Zoom up to 3× and pan
  using the stage scrollbars for pixel inspection.
- Switch between dark, bright, and a busy contrast pattern. Image accepts a
  local gameplay screenshot as a backdrop; it stays in the browser.
- Click inside the stage for keyboard input. Menus use their real handlers.
  Progress accepts Backspace or Escape; the world hold specimen uses E; mash
  uses repeated E; sequence uses W, A, S, D. The debug menu additionally maps
  arrows, Enter, Escape, mouse wheel, and right-click to its Lua input messages.
- Open **Message editor & callback log** to edit/send JSON, inspect request and
  response payloads, copy a fixture, or fail the next user callback. Readiness
  and layout telemetry never consume an injected failure.
- Settings preview values stay in the active frame. Apply/Save persist only to
  the lab's localStorage key. Discard, Escape, Replay, and Clear stage drop
  unsaved values. Reset saved settings removes only the lab's saved values.

Coverage includes notification types/positions/plain/persistent/stack/update,
bar and circle progress, text/help, diagnostics, list controls/scrolling/empty/
updates, radial pagination/submenus, alerts and input fields, all settings field
types/search/advanced/conditional/empty/failure, quick menu pages, screen/target/
projected world prompts, holds, skill checks, the debug workbench, dynamic layout, reduced motion, malformed messages, and sessions.

Add scenarios in `dev/scenarios.mjs`. Each has a stable `id`, group, title,
description, and `messages` array. A message has `action`, `data`, and optional
`after` in milliseconds relative to dispatch. Use the same contracts as the
production consumers. JSON changes are sent into the current scene; Replay
restores the catalog fixture. Unknown callbacks return an explicit error.

## Evidence boundary and in-game handoff

This lab runs renderer code and the JavaScript radial/hold/sequence skill
engine. Its callbacks are mocks, not Lua execution. Trace and mash progress,
world anchors, range/deletion/arbitration output, and consumer hold/progress
timers are labelled simulations. Native sound, map,
keybindings, waypoints, disconnect, player coordinates, and calibration return
an unavailable response; the log explains why.

Lua utilities, zones, points, raycasts, cache, asset loading, server callbacks,
control suppression, ownership, focus, permissions, actual world projection,
and external ox_lib UI require FiveM. Use the existing `/cortexdebug` workbench
for these cases; see [debug-workbench.md](debug-workbench.md) for access/setup.

For runtime acceptance after UI edits, the user should restart `cortex-lib`,
then its consumers; exercise the edited surface and repeated open/close/stop;
check focus return, native handoffs, sound, resolution and safe-zone placement.
For interaction edits, additionally test screen/world/entity/bone anchors,
range/off-screen changes, deletion/model reuse, key collisions, hold/release/
cancel, and consumer-stop cleanup. Browser/static checks do not establish CEF,
FiveM, multiplayer, or resmon performance. Do not enable the old development
test script in a customer build.

## Lab design and validation

The surface is a desktop developer workbench: choose a state, inspect the real
UI, and replay its lifecycle. The stage dominates; the catalog is a searchable
index, and message diagnostics stay in a disclosure. Controls use keyboard and
pointer input, visible focus, named actions, and truthful pending/error state.
The host uses a copied canonical `cortex-design/tokens.css`, Barlow display type,
paper selection, and one mint focus accent. It adds no second framework.
No marketing cards, decorative gradients, or altered production components.
Host chrome stacks on narrow windows; the simulated game viewport stays under
explicit control. Dark/bright/busy and custom-image backgrounds belong only to
the lab stage, never the NUI root.

The dev bridge has no production cost. Scenario transitions destroy the old
frame and its timers/listeners. The log is capped at 120 entries; custom message
batches at 256. File changes use filesystem events; only the visible lab polls
the revision endpoint once per second. These are design bounds, not FiveM
performance measurements.

Implementation reference: [Bun HTTP server](https://bun.sh/docs/runtime/http/server).
Toolbar grouping and keyboard access adapt the existing project HIG guidance
to this Windows/browser workbench; this is not a claim of native Apple behavior.
