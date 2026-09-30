# Dynamic UI

## Design contract

The game remains the primary surface. Cortex overlays share paper-colored text,
ink surfaces, mint focus, compact spacing, small radii, and quiet motion. Chat is
a readable edge-anchored conversation stream, with a condensed command prefix
and body type for messages. Hardware controllers retain their physical grammar.
No gradients, backdrop filters, full-screen backing, or decorative cards.

One shared profile controls accent, surface opacity, motion, and automatic
placement, and every participating resource follows it (the per-resource
"independent appearance" opt-out was removed; `dynamic-ui.js` ignores a legacy
`profile.independent` map). The four settings live in the Interface section of
the Cortex settings tab under their original keys (`dynamic_accent`,
`dynamic_opacity`, `dynamic_motion`, `dynamic_layout`). Preview, Apply, Save,
and Discard use the existing settings transaction. No gameplay or server
authorization moves into the UI.

The coordinator observes declared surfaces, reserves chat and fixed instruments
and notification/progress anchors first, then places the remaining overlays by priority. Positions
remain preferences; automatic displacement never overwrites saved placement.
Off-screen and hidden surfaces release their reservations. Layout messages are
bounded, deduplicated and local; they never travel over server events.

Critical states: long chat, suggestions open, notification burst, prompt stack,
camera active, pause/settings, dependency restart, owner stop, full safe zone,
no free space, and reduced motion. Validate 1280x720,
1920x1080 and 3440x1440 in game. Source and fixture checks cannot certify CEF.

## Using the system

Open settings, then the **CORTEX** tab, **Interface** section. Choose the
shared accent, opacity, motion preference, and automatic placement. Changes
preview through the existing settings system. **Apply** persists without closing
the menu and establishes the new Discard baseline. **Save & Resume** persists
and closes; **Discard & Resume** restores the last applied values and closes.
Each feature retains its own composition.
Instrument and cinematic groups stay unboxed. Surface opacity reaches actual
dark, raised, and paper backgrounds, including the
library pause, script-settings, and keybind menus; text and icons remain opaque.

Connected resources: `cortex-lib`, `cortex-chat`, `cortex-hud`, `cortex-polcam`,
`cortex-rewind`, `cortex-admin`, `cortex-emotemenu`, `cortex_mdtsv`,
`cortex_soundtool`, `cortex-death`, `gsd-arges`, and `opticom`.

Native/gameplay-only scripts already use the library's prompts and notifications
where applicable. `cortex-loading` runs before the gameplay resource lifecycle
and retains its standalone loading-screen configuration. The exhaustion effect
in `cortex-subtleadditions` is a screen effect, not a panel reservation.

Chat, notifications, progress, fixed HUD instruments, minimap, camera panels, equipment controller, and
open application panels reserve their measured rectangles. Chat keeps its chosen
anchor when opened or resized; delayed broker snapshots cannot translate it.
Screen prompts, text UI, rewind, and Opticom can move temporarily. Notification
stacks and progress never shift after appearing. Their source position remains
the player-selected anchor. World-anchored
prompts remain at their world projection. Chat and screen prompts recede while
the shared pause/settings menu or a participating application menu is open.
Camera contrast/vision modes and semantic equipment lamps retain their meanings.

Positions are deterministic: fixed surfaces first, then priority, then owner/ID.
Chat takes precedence over notification stacks. Within a priority, stable keys
prevent arrival-order oscillation. Candidate searches are bounded. If the screen
is saturated, content remains visible at its clamped preference with
`data-cortex-crowded="true"`; the system cannot guarantee zero overlap when the
visible content does not fit. It does not alter saved resource positions.

## Adding a resource

Start after `cortex-lib` and add this client script to the consumer manifest:

```lua
dependency 'cortex-lib'
client_script '@cortex-lib/presentation-client.lua'
```

Load these after the consumer stylesheet and near the end of its HTML body,
before consumer code calls `CortexUI`. Include them in source HTML as well as
the shipped page, so rebuilding retains the integration:

```html
<link rel="stylesheet" href="https://cfx-nui-cortex-lib/ui/dynamic-ui.css">
<script src="https://cfx-nui-cortex-lib/ui/dynamic-layout.js"></script>
<script src="https://cfx-nui-cortex-lib/ui/dynamic-ui.js"></script>
```

Use the `--cx-paper`, `--cx-muted`, `--cx-panel`, `--cx-raised`, `--cx-rule`,
`--cx-accent` (with `--cx-accent-rgb` and `--cx-accent-deep`), `--cx-body`, `--cx-display`, and `--cx-data` variables. Never hard-code mint: the
accent is the player's shared accent and changes live. Lua that paints native
colours reads `getPresentation().profile.accent` and handles
`cortex-lib:presentation`. These are
served from the installed resource, not a CDN. The display font is the existing
OFL-licensed Barlow Condensed face. No additional framework is required.

Register a bounded surface once from the consumer's existing UI lifecycle:

```js
const unregister = window.CortexUI.registerSurface({
    id: 'equipment', selector: '.equipment-panel', fixed: true, priority: 100,
});
// Call unregister() when this integration unmounts permanently.
```

Use `fixed: true` for draggable, world-related, or precision equipment surfaces;
other overlays will avoid them. Use `false` for edge overlays that can yield.
Do not register `html`, `body`, a fullscreen coordinate root, or both a panel
and its children. A selector may match multiple instances. IDs are owner-scoped;
the bridge accepts up to 16 rectangles per resource and 32 resource owners.
The current adapter reserves one of its 16 slots for the native minimap.
Panel show/hide, child changes, resizing, and messages trigger deduplicated
measurement with a 200 ms batch delay. The broker coalesces broadcasts at 100 ms.
A five-second readiness refresh recovers from late startup; stop removes an
owner's reservations, and a library restart requests new measurements.

All callbacks are local presentation data. Do not put actions, permissions,
entity ownership, or server mutations in this API. Input remains with each
resource's existing lifecycle. Chat now waits for NUI readiness, refuses to
open over existing focus/native pause, and releases its own focus synchronously.
This is not a universal focus lock for third-party resources.

The cross-resource asset and callback contracts follow the official
[fullscreen NUI documentation](https://docs.fivem.net/docs/scripting-manual/nui-development/full-screen-nui/)
and [NUI callback documentation](https://docs.fivem.net/docs/scripting-manual/nui-development/nui-callbacks/).

## Validation and runtime handoff

Deterministic checks: layout scenarios at three viewport sizes, adapter retries,
hidden-surface cleanup, displacement feedback prevention, stale/malformed
snapshots, owner isolation, settings preview rollback, chat focus lifecycle,
the library Node suite, settings Lua fixtures, Opticom contracts, and Arges's
25 deterministic specs. All six bundled consumers build in isolated output
directories; Arges typecheck passes. Source HTML and shipped HTML both include
the shared files. Existing generated bundles were preserved.

The NUI audits for the shared UI and chat have no errors. Existing shared modal
pointer-capture warnings belong to intentional modal surfaces. Workspace
resource validation still flags existing `node_modules` folders in HUD, admin,
MDT, sound tool and Arges, plus malformed lockfiles in admin's `.opencode` and
MDT. Those local development artifacts were not changed or packaged.

User-run checks, still pending:

1. Restart `cortex-lib`, then the connected consumers. Open Script settings and
   confirm the Cortex tab shows the Interface section (no Dynamic UI tab), all
   shared files load, and F8 has no new errors.
2. Put chat and notifications in the same corner. Open suggestions, add long
   messages, let messages fade, and confirm notifications yield and return.
3. Open the police camera and Arges controller; use Opticom. Confirm overlays
   avoid instruments, controller dragging still works, and saved positions stay
   unchanged after closing the conflicting surface.
4. Open chat with T; send, Escape, reopen quickly. Try T while admin, MDT,
   animations, sound tool, or native pause owns input. Confirm no stolen typing
   or stuck cursor. Confirm death and rewind remain legible.
5. Preview opacity at 65 and 100 with script settings and the quick
   menu visible. Apply without leaving settings, change it again, then Discard:
   the applied value must remain. Save and reconnect: the value persists.
6. Test 1280x720, 1920x1080, and ultrawide with small/large safe zones, bright sky,
   dark interiors, and reduced motion. Inspect long messages and open suggestions.
7. Stop a resource while its panel is visible and restart the library with
   consumers running. Confirm reservations clear/recover. Measure idle and busy
   `resmon` yourself; no in-game performance or visual acceptance is claimed.


### Overlay refinement runtime checks

Restart cortex-lib, then cortex-chat, cortex-death and the connected consumers.
At 720p, 1080p and 4K, check short/long notifications and title/body notices against
bright and dark scenes; compare progress and incapacitation against the supplied
oversized captures. Check the warning countdown, long progress labels and cancel.
Open chat repeatedly, Tab to message history, press Escape, submit a command that
opens another menu, and open a menu over chat. Each close must restore input;
a hidden chat must stop its heartbeat and release its session. If callback
transport fails entirely, the existing five-second Lua watchdog is the fallback.
These steps remain unverified in live FiveM/CEF.
