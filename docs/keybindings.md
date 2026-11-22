# Key bindings

**Key bindings** in the optional quick menu opens GTA's native binding
editor. Closing the native frontend returns to the Cortex page that opened
it, unless another frontend has taken ownership. There is no Cortex binding
editor.

Consumers own their own `RegisterCommand` and `RegisterKeyMapping` handlers,
with one exception: the four shared keys below. A player binds each of them
once, and every Cortex resource uses the same key for the same job.

Every `RegisterKeyMapping` is listed for every player under Settings › Key
Bindings › FiveM, so keep that list to actions a player starts from free
gameplay. Keys that only work inside a mode (placing, carrying, an open
editor) should be GTA controls read with `IsDisabledControlJustPressed` in that
mode's frame loop and disabled there. Developer and admin tools should register
their mapping only once the player is known to be allowed to use them.

## Cortex keys

| Command | Description | Default | Convar |
| --- | --- | --- | --- |
| `+cortex_cancel` | Cortex: cancel or put away | X | `cortex_lib_cancel_key` |
| `+cortex_answer` | Cortex: answer | Y | `cortex_lib_answer_key` |
| `+cortex_actions` | Cortex: actions | M | `cortex_lib_actions_key` |
| `+cortex_point` | Cortex: point (tap) or hold | B | `cortex_lib_point_key` |

A convar changes the default for players who have never bound the key. A
player's own binding always wins.

- **Cancel (X)** stops the newest thing the player started: a progress bar, a
  carry, an emote, a held tool. Each resource registers a cancelable while its
  thing runs. In a vehicle, GTA's duck is disabled only while a cancelable
  exists. Backspace, Esc and right mouse still cancel a progress bar.
- **Answer (Y)** answers the newest open ask (an invite, a ready check, a seat
  swap). On foot with nothing to cancel, the ask also shows `X Decline`. An ask
  with a decline times out to decline; one without times out silently.
- **Actions (M)** opens one radial built from every resource's actions for the
  place the player is in. A choice runs once the radial has released focus.
- **Point (B)** gives a tap to the highest-priority tap owner. When a hold
  owner also matches, the press waits 200 ms: release before is a tap, holding
  past it starts the hold. A press is never both.

Presses are ignored while NUI has focus (this covers chat input), the pause
menu is open or a radial is open.

### Using them

Facade consumers (`shared_script '@cortex-lib/init.lua'`) use `lib.keys`.
Resources that reach cortex-lib only through exports, or not at all, carry a
copy of `imports/keys/client.lua` as `client/cortex_keys.lua` and use the
global `CortexKeys`. Both check `available` first: it is false when cortex-lib
is missing or older than the keys, and the resource then registers its own
mapping as it did before.

```lua
local keys = lib.keys
if keys and keys.available then
    keys.cancelable('carry', function()
        if not carrying then return false end
        stopCarry()
    end)
end
```

| Call | Meaning |
| --- | --- |
| `cancelable(id, fn)` / `cancelable(id, false)` | `fn()` returns `false` when stale. It must be idempotent and must not yield. |
| `ask(id, { label, decline, seconds = 20 }, fn)` / `endAsk(id)` | `fn(accepted)` gets `true` or `false`. The same id replaces. |
| `isAsking()` | True while an ask is open and for 300 ms after. |
| `addAction(id, { label, icon, where, order, items }, fn)` / `removeAction(id)` | `fn(itemId)`; `items` become a submenu. |
| `onPoint(id, { tap, hold, where, priority }, fn)` / `onPoint(id, false)` | `fn('tap' | 'holdStart' | 'holdEnd')`. Unregistering mid-hold sends `holdEnd`. |
| `label(kind)` | The bound key for `'cancel'`, `'answer'`, `'actions'` or `'point'`. |

`where` is `'foot'`, `'vehicle'` or `'any'`. Register on state changes, never
from a frame loop, and remove the entry when the state ends. Everything an
owner registered is removed when it stops.

A cancel callback that yields is a bug: the host waits 100 ms for its answer,
then counts it as handled and prints a warning naming the resource.

## Other mappings

cortex-lib also registers:

| Command | Description | Default | Registered |
| --- | --- | --- | --- |
| `cortexpause` | Cortex: open pause menu | unbound | Always |
| `+cortexdebug_mash` | Cortex: debug reactive mash | R | Only with `setr cortex_debug 1` |

The retired prototype's custom KVP bindings are no longer read and were not
migrated.

## Runtime acceptance

1. Open Key bindings from the quick menu and confirm the native editor opens.
2. Close it and confirm return to the quick menu with normal input restored.
3. Confirm Cortex Settings has no keybinding link. With the quick menu off, use GTA's native pause menu to edit bindings.
4. The four Cortex keys appear under Key Bindings › FiveM with their defaults. Rebinding one changes the key every resource's hints show.
5. X stops an emote, cancels a progress bar, and in a car ducks only when nothing is running.
6. An invite on foot shows `Y` and `X Decline`; Y answers it.
7. M opens Actions; an action that opens its own UI (the emote wheel) opens.
8. B taps and holds go to the right owner; opening chat during a hold ends it.
9. With development diagnostics enabled, verify the **Cortex: debug reactive
   mash** mapping (default R) presses and releases only during its specimen.
   With `cortex_debug` unset, confirm the mapping is absent from the list.

The native handoff and focus lifecycle have deterministic coverage in
`tests/pause_lifecycle_spec.lua` and `tests/pause_ui.test.mjs`. CEF and actual
input behavior still require an in-game check.
