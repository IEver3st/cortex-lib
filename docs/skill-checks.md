# Native skill checks

Cortex owns the UI, input lifecycle and local result. These checks do not award
items or authorize server actions. Consumers must revalidate targets, distance,
permissions and gameplay state, and the server must authorize privileged changes.

## Try them

Restart `cortex-lib`, then its consumers. Open `/cortexdebug`, select **Skill
checks**, and run a specimen. The world mash uses a native debug binding (default
R) and a point in front of the player. Face the point and stay within three metres. Results appear in workbench
history. The legacy `/cortex` test script does not need to be enabled.

## Screen checks

Call from a yieldable client thread. Returns `passed, reason`; concurrent checks
return `false, 'busy'`. Keyboard checks take NUI focus and cancel when replaced by
another Cortex modal, on Escape, death, or owner/library stop. A foreign focused
NUI prevents opening. Mouse traces reserve the shared modal owner without taking
NUI focus or showing a cursor. They read native relative mouse input with camera
look and attack/aim controls disabled for the session. Escape still cancels.

```lua
local passed, reason = lib.skillCheck({
    type = 'radial', label = 'Set the tension', key = 'E',
    duration = 10000, speed = 0.55,
    targetStart = 0.55, targetSize = 0.14,
})

-- Physical mouse sweep, no cursor and no button press; one sweep completes it.
-- lower: 3 -> 6 -> 9 o'clock, clockwise; upper: 3 -> 12 -> 9, counterclockwise.
lib.skillCheck({ type = 'trace', direction = 'upper', label = 'Turn the lock' })
lib.skillCheck({ type = 'trace', direction = 'lower', label = 'Seat the bearing' })

-- Hold E, then release while the needle is in the target zone.
lib.skillCheck({ type = 'hold', label = 'Charge the mechanism', key = 'E' })

-- Every key needs a fresh press; keyboard auto-repeat is ignored.
lib.skillCheck({ type = 'sequence', label = 'Reconnect the circuit', keys = { 'E', 'R', 'E', 'Q' } })
```

### Trace: one sweep

Sweep the physical mouse once, like turning a knob: lower goes right → down → left
under the start, upper goes right → up → left over it. No cursor, no button. The
check recognises the motion with a *virtual knob* (`imports/skillCheck/shared.lua`):

- The knob starts at 3 o'clock on a half ring of radius R. Every native mouse delta
  (`GetDisabledControlUnboundNormal(0, 1/2)`, already a per-frame delta) is added
  to the knob and projected back onto the ring. Tangential motion turns it; radial
  motion does nothing, so the size and roundness of your arc hardly matter.
- A delta that is more than ~75° off the tangent is treated as radial noise, and a
  sub-step that would pass near the centre is ignored. Large deltas are sub-stepped,
  so a fast flick or a low-FPS frame behaves like the same motion drawn slowly. A
  straight swipe in any direction stalls by ~151° and can never complete.
- The knob may slide back at most `tolerance` of a half turn below its best
  position: wobble never resets the attempt and jiggling back and forth nets zero.
- Pauses cost nothing. After 1.5 s without motion progress eases back slowly
  (0.35 of the sweep per second); it never snaps to zero.
- The check completes when the knob reaches 173° (96%) in the requested direction.

R is 0.5 normalized mouse units divided by `sensitivity`. The natives document no
absolute mouse scale, so R is calibrated against the one tuned constant in this
tree: cortex-hud's virtual weapon-wheel selector reaches full deflection after
1 / 2.2 ≈ 0.45 units (one small wrist flick). A knob of that radius needs
π·R ≈ 1.6 units of tangential travel, one comfortable wrist arc; players who draw
bigger arcs simply see the knob run ahead and wait. If players on your server need
too much or too little travel, raise or lower `sensitivity` (2 halves the travel).
GTA's own mouse-look sensitivity setting may scale these values; check in game.

The slip shows the label, the time left, the half ring with a mint knob and fill,
a paper finish cap at 9 o'clock, a direction chevron at the start, and a mouse
keycap. Controller look input neither advances nor resets the mouse variant. Use
radial, hold or sequence for a consumer-selected keyboard alternative.

### Look

All screen checks use the cortex-minigames language: a compact slip lower-centre
(480u wide, 150u above the bottom), the label in display caps, a 4u clock that
turns sand then soft red, the mechanic, and keycap hints (`ESC Cancel`). Mint is
the player's live marker (radial needle, hold cursor, trace knob, current sequence
key), targets are paper, misses soft red. On close the mechanic briefly shows a
slip tag (`CLEAR | 92`, `MISSED`, `OUT OF TIME`, `CANCELLED`) for 0.9 s; the score
is presentation only (zone accuracy for radial/hold, speed for sequence) and is
never sent to Lua. The world mash is a thick mint ring around the prompt keycap
that presses on every accepted tap. Reduced motion removes the entry rise and tag
fade; judged motion never slows.

| Option | Default | Allowed |
| --- | --- | --- |
| `type` | `radial` | `radial`, `trace`, `hold`, `sequence`, `mash` |
| `label` | `Skill check` | 1–64 bytes, no control characters |
| `key` | `E` | One letter/digit or `SPACE`; screen checks only |
| `duration` | `10000` | 1000–120000 ms, measured after UI readiness |
| `speed` | `0.55` | 0.1–2 revolutions/fills per second |
| `targetStart` | `0.55` | 0.1–0.9, clockwise from the top |
| `targetSize` | `0.14` | 0.04–0.35; start + size must not exceed 1 |
| `direction` | `upper` | `upper`, `lower` |
| `tolerance` | `0.15` | 0.08–0.4; trace only: how far the knob may slide back, as a fraction of a half turn |
| `sensitivity` | `1` | 0.25–4; trace only: divides the knob radius (0.5 normalized mouse units) |
| `keys` | `E, R, E, Q` | Dense array of 2–8 letter/digit/`SPACE` keys |
| `interactionId` | none | Required for mash; an existing owner-scoped anchor |
| `gain` | `0.12` | 0.01–0.5 fill per mash press |
| `decay` | `0.18` | 0.01–1 fill lost per second |

## Reactive 3D mash

Register an ordinary anchored interaction on a gameplay state transition. Start
the check only when the prompt is visible. Keep the consumer's command/key mapping
and forward its press/release edges with `lib.skillCheckPress(id, boolean)`.
No cursor or NUI focus is taken. Movement and camera remain available.

```lua
-- State entry: use a current, validated target, never a persisted entity handle.
local id = 'repair-pump'
local ok, err = lib.showInteraction({
    id = id, key = 'R', label = 'Build pressure', priority = 10,
    anchor = { type = 'entity', entity = target,
        model = GetEntityModel(target), maxDistance = 2.5 },
})
if not ok then print(err) return end

-- Register these commands once in the consumer, not every time the target changes.
RegisterCommand('+pump-pressure', function()
    if not lib.isInteractionVisible(id) then return end
    -- Revalidate your current target and gameplay state here on every press.
    local accepted, pressReason = lib.skillCheckPress(id, true)
    if not accepted then return end
end, false)
RegisterCommand('-pump-pressure', function()
    lib.skillCheckPress(id, false)
end, false)
RegisterKeyMapping('+pump-pressure', 'Build pump pressure', 'keyboard', 'R')

-- Start from the consumer's action/session after renderer visibility is available.
CreateThread(function()
    if not lib.isInteractionVisible(id) then return end
    local passed, reason = lib.skillCheck({
        type = 'mash', interactionId = id, duration = 15000,
        gain = 0.12, decay = 0.18,
    })
    lib.hideInteraction(id)
    -- Revalidate current entity/model/range/state after this yield.
    -- A passing client result is not server authorization.
end)

-- On action abort/target exit, cancel before hiding the prompt:
-- lib.cancelSkillCheck()
-- lib.hideInteraction(id)
```

Mash progress decays continuously to zero and permits recovery until timeout.
A held key cannot repeat; press edges are capped at 20 per second. Progress
messages are sent on accepted taps only; the UI extrapolates decay locally.
There is one active skill session globally, no queue, no idle polling and no
duplicate projection loop. Mash lifecycle checks run at 20 Hz. Mouse trace samples
and camera suppression run per frame only while active; changed trace presentation
is capped at about 30 Hz, with immediate resets/completion. The existing
renderer remains the source of visibility and coordinates.

Mash cancels on key arbitration loss, leaving range, going off-screen, deleted or
model-mismatched entities, replaced/removed prompts, owner stop, death, pause, or
NUI takeover. It cannot attach to a screen prompt or a hold-duration prompt.
The displayed key comes from the interaction; keep it consistent with the actual
consumer binding. Losing all progress alone does not fail the check.

`lib.cancelSkillCheck()` and `lib.isSkillCheckActive()` are scoped to the calling
resource. All four APIs are also available as cortex-lib exports. Reasons include
`success`, `missed`, `timeout`, `cancelled`, `interrupted`, `dead`,
`interaction_unavailable`, `resource_stopped`, `ui_timeout`, `focus_failed`,
`invalid_options` and `busy`. `skillCheckPress` also returns `not_active`,
`not_ready`, `held`, or `too_fast` for rejected input.

## User-run acceptance

Static and browser fixtures do not prove FiveM/CEF behavior. After restarting the
library and consumers:

- Run radial hits/misses, hold early/in-zone/late release, and correct/wrong
  sequences. Check Escape, timeout and the outcome slip tag.
- Trace, both directions: one comfortable wrist sweep completes; a small wobbly
  sweep completes; a straight horizontal swipe, the mirrored arc and back-and-forth
  jiggling do not; pausing mid-sweep (under 1.5 s) then continuing completes. Repeat
  at low (~30) and high (144+) FPS, at two mouse DPI settings and two in-game mouse
  sensitivities, and with inverted look. If the travel feels wrong, try
  `sensitivity = 0.5` and `2` and report which feels right.
- For mouse arcs, confirm no cursor or click is needed, camera look stays fixed,
  and camera/attack input resumes after success, Escape, timeout and resource stop.
  Check lower 3 → 6 → 9 and upper 3 → 12 → 9 at low/high FPS and different mouse
  sensitivities, including inverted-look settings. These native feel/sign checks
  require user-run FiveM validation.
- Tap mash, hold the key, release, stop until zero, and recover to completion.
  Move and turn the camera; confirm the arc stays attached to the prompt.
- Exercise world, entity and entity-bone anchors. Walk out of range, turn away,
  delete the target and reuse its handle with a different model. Each must cancel.
- Introduce a higher-priority key collision, replace/hide the prompt, open a modal,
  pause, die, and stop the consumer/library while active. Check cleanup and focus.
- Inspect 1280×720, 1920×1080 and ultrawide, changed safe zones, bright/dark scenes,
  reduced motion, resource restart, CEF errors and idle/active `resmon`.
- Consumer integrations with privileged actions need their own server rejection
  and two-client checks. This library adds no network mutation or server event.

## Local validation

Validated with `node --test tests/*.test.mjs`, JavaScript syntax checks, standalone
Lua 5.4 skill/session, loader, interaction, menu, pause, settings and debug-workbench
specs, plus the resource/packfile validator. The validator retains the existing
`lua54` deprecation warning; the resource's explicit loader contract is unchanged.

The virtual-knob revision is covered by `tests/skill_mouse_trace_spec.lua` (smooth
sweeps at 12-240 samples and 0.5-4 unit radii in both directions, a small wobbly
sweep, straight swipes in seven directions, a single huge flick, the mirrored arc,
pause-and-continue, long-idle ease back, tangential jiggle, invalid samples) and by
`tests/skill_check_spec.lua` (option bounds, rate-limited presentation, completion
without NUI results, sensitivity, cleanup of look suppression). The browser lab
mirrors the knob with pointer pixels (1 unit = 200 px) for illustration only.
Those checks do not prove physical mouse feel, the real normal scale, camera
suppression or CEF rendering; no FiveM process was driven.
