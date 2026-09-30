# cortex-lib design brief

Follows [`../CORTEX-DESIGN.md`](../CORTEX-DESIGN.md) (the constitution wins on conflict). This file records the
library-specific decisions for every shared surface. The NUI is the grandfathered vendored React 18 stack
(`React.createElement`, no build step); it stays React.

## Structure

```
ui/core/tokens.css    canonical Cortex tokens (verbatim copy of cortex-design/tokens.css)
ui/core/base.css      font face, legacy aliases, reduced motion
ui/core/kit.css       shared primitives (keycap, hint, legend, meter, ring, toggle, check, segmented, dropdown, slip header)
ui/core/base.js       bounded normalizers, nuiPost (the ONE transport), useModalFocus, scale, icons
ui/core/kit.js        window.CortexKit: primitives + player preference store (usePrefs)
ui/surfaces/<name>.js one surface each: notify, progress, text, menu, dialogs, radial, settings, interactions
ui/app.js             composition + message router only
```

Classic scripts share one global scope in `index.html` order. A surface module declares its own component
names and reads shared helpers (`nuiPost`, `boundedText`, `useModalFocus`, …) and `window.CortexKit`.
Every file shipped must be listed in `fxmanifest.lua` `files`.

## System rules (all surfaces)

- Sizes: `calc(N * var(--u))` only. `--u` already includes the player's UI scale. Body copy multiplies by
  `var(--cx-text)` (Large text setting). No raw px except 1px hairline-free borders that are never visible.
- Colour: tokens only (`--paper --ink --accent --muted --dim --warning --error --info --success --slip
  --slip-deep --wash --rule --rule-strong`). `--accent` is the player's shared accent (mint by default).
- Type: display = Barlow Condensed italic 800 caps (`.cx-display` or kit classes); body = Arial; data = Consolas.
  Numbers that change use tabular nums.
- Nothing visible under 3u. Meters 4-8u, rings stroke ≥ 8 viewBox units at their smallest render.
- No gradients, no `backdrop-filter`, no glow, no outline focus rings, no native select/checkbox.
- HUD overlays (notifications, progress, text UI, prompts, legends) are frameless with `--legible`
  text-shadow. Only surfaces that open and take input (menu, dialogs, radial, settings) use `--slip`.
- State language: hover = paper wash + accent bar wipes in from left; selected/focused = flips to paper with
  ink text (keyboard focus is the same flip or a 3u mint edge); on/yours = mint; pressed = down 2u, keycap
  inverts; disabled = `--dim`; caution = sand; critical = soft red.
- Motion: enter = 4-6u rise + fade, 220-280 ms `--ease`; leave 160 ms. Only transform/opacity. Loops only for
  real urgency. `html.cortex-reduced-motion` and the OS preference both remove non-essential motion.
- Controls are shown with `CortexKit.KeyHint` / `ControlsLegend` (keycaps). Legends hide when the player turns
  off "Control hints" (`html[data-cx-hints='off']`), except `always` legends that carry the only instruction.
- Every NUI callback goes through `nuiPost` and echoes the session (and menu revision). Every modal uses
  `useModalFocus`. Normalizers stay bounded; new message fields are optional and backward compatible.

## Kit (reuse, do not re-implement)

| Primitive | Use |
| --- | --- |
| `Keycap({value,size,tone,pressed})` | Any key glyph. Knows LMB/RMB/MMB/WHEEL (mouse icon), arrows, NUM keys |
| `KeyHint({keys,label,order})` | One control hint. `'key-first'` in lists/footers, `'label-first'` for edge legends |
| `ControlsLegend({items,align,order})` | Row of hints. Footers of menu/dialog/radial, the help bar, progress cancel |
| `Meter({value,tone,size})` | Frameless bar (progress, menu row progress, mash) |
| `Ring({value,tone,stroke,arc})` | Thick SVG ring/gauge (progress circle, skill checks, markers) |
| `Toggle`, `CheckMark`, `Segmented`, `Dropdown` | The only choice controls |
| `SlipHeader({eyebrow,title,meta})` | Title block with the mint accent bar for every opened slip |
| `parseKeyText(text)` | `"[E] Inspect"` → text + keycap parts (text UI, notifications, help labels) |
| `usePrefs()` | Player preferences pushed by Lua as `cortex:prefs` |

## Player preferences (`cortex:prefs`)

Sent by `imports/settings/client.lua` on NUI ready and on every change (preview included, rolled back on
cancel). Shared appearance (accent, surface opacity, motion, overlap avoidance) keeps flowing through
`client/presentation.lua` → `dynamic-ui.js` to every Cortex NUI.

| Key | Values | Consumer |
| --- | --- | --- |
| `scale` | 0.8–1.3 | `--cx-scale` → `--u` (all surfaces) |
| `textSize` | `standard`, `large` | `--cx-text` (body copy) |
| `notifyDuration` | 0.5–3 multiplier | notify lifetime |
| `notifyLimit` | 1–12 | visible notification cap |
| `showPercent` | bool | progress readouts |
| `promptMarkers` | bool | Lua renderer: distant marker tier |
| `promptScale` | `small`, `standard`, `large` | `--cx-prompt-scale` (world + screen prompts) |
| `controlHints` | bool | `html[data-cx-hints]` legends |
| `invertScroll` | bool | Lua renderer: prompt list scroll direction |

## Surface briefs

Each brief: situation · primary verb · input · scene budget · show/hide · anchors · signature · rejected
defaults · states.

### Notifications (light polish)
On foot or driving; *read at a glance*; passive; top-right by default (player position setting), never over
minimap. Show on `notify`, hide on timeout (× duration pref), `hideNotify`, `clearNotifications`, cap = limit
pref. Signature: severity rule (4u, left) + display-caps title; lifetime cue is a 4u meter aligned to the text,
not a hairline. Rejected: card per toast, icon circles in brand colours, hairline timers. States: info,
success, warning, error, persistent (dismiss keycap), plain, updated (same id), stacked overflow.

### Progress (rebuild)
During a timed action; *know how long*; passive + optional cancel key; bottom-centre above the chat/radar
band, middle, or top. Bar: display-caps label left, tabular percent right (pref), 8u meter below, cancel as a
`KeyHint` (BACKSPACE Cancel). Circle: 116u ring, stroke 12 viewBox units, percent in display type inside, label
under. Frameless. Rejected: 2u tracks, spinners, boxed plates. States: running, controlled value, complete
(fill pulses once to paper, then leaves), cancelled (sand, leaves), non-cancelable (no hint), reduced motion.

### Text & help (rebuild)
*Text UI* — a contextual instruction (`[E] Open trunk`). Frameless line at its position; `[KEY]` tokens render
as keycaps via `parseKeyText`; display caps for the action, Arial for long sentences; optional `backdrop`
becomes a slip. *Help* (`lib.showHelp`) — the GTA-style controls legend: bottom-right, `label-first`, right
aligned, respecting the safe zone ("GRAB [E]   BACK [BKSP]"); `compact` = smaller keycaps. *Debug panel* —
a dev slip with data font, not player chrome. Rejected: boxed text strip with an icon square, lowercase key
brackets as text. States: short, long wrapping, multiple keys, icon, backdrop, legend of 1-8 items, hidden.

### Menus (rebuild)
Keyboard/pad list opened on demand; *pick an option fast*; arrows/Enter/Space/Backspace, wheel+click for
`gameControls`; top-left default. A 380u `--slip` column: `SlipHeader` (subtitle as eyebrow, `3 / 40` meta),
rows 44u in display caps; selected row flips to paper with a 4u accent bar; value rows show `‹ VALUE ›`;
check rows show `CheckMark`; progress rows show a 4u `Meter`; icons in a fixed 24u column. List scrolls with
fading edges and a 4u scroll rail; description area under the list; `ControlsLegend` footer. Rejected: mint
row fill with outline, a paper header plate, lowercase body-font rows. States: resting, hover, selected,
value, checked, progress 0/partial/100, disabled, long label, empty, 40+ rows, updates by revision.

### Radial (rebuild + QoL)
Opened by a consumer key, used mid-movement; *choose one of ≤8 actions without aiming the cursor precisely*.
Selection by *direction* from centre (mouse anywhere past a dead zone, arrows, number keys 1-8), click/Enter to
confirm, right-click/Backspace back, Escape close, wheel or Q/E pages. A donut of slip segments with gaps
(not a paper pie); hovered segment flips to paper; a mint arc on its outer edge; icon + short label per
segment; the centre shows the hovered label large, a description line, and breadcrumb/back state. Pages are
dots under the wheel, never a fake "More" segment. Rejected: paper pie, text-glyph close button, footer box
with prose instructions. States: 1, 2, 3-8, paged 18, empty, submenu with back, disabled item, compact-control.

### Dialogs (rebuild)
Alert and input form; *answer one question*; keyboard first. A 520u slip placed centre-low, not a giant modal:
`SlipHeader`, body copy in Arial, fields with eyebrow labels, inputs as ink wells with a 3u bottom rule that
turns accent on focus, `CheckMark` rows, `Dropdown`, number stepper, required marker and inline error in soft
red. Actions right-aligned as keycap buttons: primary flips to paper (`ENTER Confirm`), secondary ghost
(`ESC Cancel`). The screen gets a light ink scrim (≤ 40%) only while a dialog owns focus. Rejected: paper
header plate, mint-filled primary with outline, browser-looking inputs. States: confirm, confirm-only, long
scroll, all fields, required empty, error, empty form.

### Interactions (evolve)
The world prompt the player loves stays: label + key disc with hold ring. Changes:
1. **Two tiers.** Beyond `maxDistance` but within `markerDistance` (default `min(25, max(maxDistance + 4,
   maxDistance × 2.5))`, `anchor.markerDistance = 0` disables, player pref can disable all) the anchor shows a
   *marker*: a 10u paper dot inside a 22u ring — a scaled-down disc, no label. Inside `maxDistance` it grows into
   the full prompt. Markers are presentation only: never `visible`, never authorization.
2. **Merged list.** Full-tier prompts whose projected points fall within ~6% of screen height merge into one
   GTA-style list at the first entry's anchor: a 4u rail with dots; the selected row has the full disc and a
   large label; other rows a small dot and muted label; rows past the fourth fade out along the rail. Same-key
   rows compete: the selected row wins its key. The mouse wheel moves the selection (native weapon-wheel inputs
   disabled only while a multi-row list is focused); the `invertScroll` pref flips it. A `WHEEL` hint sits
   under the list. Rows with a unique key keep their own small keycap and stay usable.
3. **Consistency.** Screen prompts, world prompts and legends share `Keycap`/disc sizing and
   `--cx-prompt-scale`; target panels and vehicle access rows use the same rail/row anatomy.
Rejected: labels on every distant anchor, stacked independent labels overlapping, a scroll list that hijacks
the wheel when there is nothing to choose. States: marker, prompt, list (2-8), hold, hold complete/cancel,
off-screen, out of range, deleted entity, key collision, reduced motion.

### Settings (polish)
Paused; configure. Opening darkens (ink scrim 55%) and blurs the game natively (timecycle blur the quick menu
already owns; never CSS blur). The Dynamic UI tab is removed; its four settings join the Cortex tab. The
Cortex tab gains player-facing sections: **Interface** (UI scale, text size, accent, surface opacity, motion,
avoid overlapping overlays, control hints), **Notifications** (position, duration, limit, sounds, sound preset),
**Prompts** (nearby markers, prompt size, invert list scroll), **Progress** (show percentage). Choices of ≤4
use `Segmented`, longer lists `Dropdown`.

### Skill checks (restyle + trace fix)
Match cortex-minigames: compact slip lower-centre (480u, 150u above bottom), keycaps that follow input, mint =
the player's marker, targets paper, misses soft red, outcome slip tag `CLEAR | 92`. Trace is one smooth
semicircle: a virtual knob on the arc follows the mouse's tangential motion; no reset on small wobble or a
pause; completes at the end of one sweep. Mash and trace also exist as cortex-minigames games.

### Layout & lifecycle
Browser-lab scenes updated to the new surfaces; presentation/reduced-motion/stale-session/malformed scenes kept.
Registered UI apps (the weather editor) are removed from the library.

## Decisions from review (3.0.0)

- World prompts put the key disc on the anchor with the label to its right, for single prompts, lists and the
  marker→prompt growth alike, so the dot the player sees from afar is exactly where the disc lands.
- A list row is offered only when its key's normal winner is in the same list; a key owned by a prompt
  elsewhere turns the row into a marker, so a list never shows a key that would trigger something else.
- Hint labels carry a tight halo instead of `--legible`: ellipsis clipping would cut the wide halo into a
  grey box on bright scenes. Italic display text that can ellipsize gets 0.16em right padding.
- Mouse keycaps are a solid silhouette cut by button seams (never a hollow outline, which reads as "0").
- The quick menu lost its coloured edge glow and breathing loop (Law 2) and its hairlines (Law 4).
- The settings scrim is the one sanctioned full-screen fill: it exists only while settings own focus, and the
  heavy blur is the game's own timecycle blur, never CSS.
- Every key the player presses on the scene uses one glyph (`ui/interaction-key.js`): a disc for one or two
  characters that grows into a pill of the same height for longer names, combos (`SHIFT + E`) and mouse
  buttons, with short forms (BKSP, ESC, CTRL). Text is optically centred (measured at 4x: italic caps are
  pulled left 0.09em and up 0.07em in discs, 0.022em in pills). Prompts, target panels, the help legend and
  the list's wheel hint all share it; the kit's square keycap stays for slips (menus, dialogs, settings).
- A focused list's WHEEL hint is a quiet row at the foot of the bottom-right prompt column, never under the
  list itself.
- Settings blur is layered because graphics packs neuter single effects: the scaled `hud_def_blur` extra
  timecycle, the screen blur fade, and the `MenuMGSelectionIn` postfx (never started or stopped if another
  resource owns it). `/cortexblur` prints which layers are live. While settings are open the native HUD and
  radar are hidden every frame, and every other Cortex NUI hides via `cortex-settings-active` (pushed on the
  transition by `lib._presentationSettingsOpen`, not the one-second modal poll). The ink scrim is 66%.
