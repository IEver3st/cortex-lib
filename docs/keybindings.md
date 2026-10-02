# Native key bindings

**Key bindings** in the optional quick menu opens GTA's native binding
editor. FiveM script mappings remain registered and owned by their consumer
resources. Closing the native frontend returns to the Cortex page that opened
it, unless another frontend has taken ownership.

There is no Cortex binding editor, metadata bridge, control catalog or managed
input registry. Consumers should register their own `RegisterCommand` and
`RegisterKeyMapping` handlers. Shared interaction prompts display controls; they
do not register or execute gameplay actions.

Every `RegisterKeyMapping` is listed for every player under Settings › Key
Bindings › FiveM, so keep that list to actions a player starts from free
gameplay. Keys that only work inside a mode (placing, carrying, an open
editor) should be GTA controls read with `IsDisabledControlJustPressed` in that
mode's frame loop and disabled there. Developer and admin tools should register
their mapping only once the player is known to be allowed to use them.

cortex-lib registers two mappings, both prefixed `Cortex: `:

| Command | Description | Default | Registered |
| --- | --- | --- | --- |
| `cortexpause` | Cortex: open pause menu | unbound | Always |
| `+cortexdebug_mash` | Cortex: debug reactive mash | R | Only with `setr cortex_debug 1` |

The retired prototype's custom KVP bindings are no longer read. They are not
automatically migrated to native bindings, and existing native mappings are
unchanged. Configure script mappings in GTA's native keybinding menu.

## Runtime acceptance

1. Open Key bindings from the quick menu and confirm the native editor opens.
2. Close it and confirm return to the quick menu with normal input restored.
3. Confirm Cortex Settings has no keybinding link. With the quick menu off, use GTA's native pause menu to edit bindings.
4. Check a consumer's native mapping, such as PolCam's camera control.
5. With development diagnostics enabled, verify the **Cortex: debug reactive
   mash** mapping (default R) presses and releases only during its specimen.
   Cancel the specimen or restart the resource and check that input stops.
   With `cortex_debug` unset, confirm the mapping is absent from the list.

The native handoff and focus lifecycle have deterministic coverage in
`tests/pause_lifecycle_spec.lua` and `tests/pause_ui.test.mjs`. CEF and actual
input behavior still require an in-game check.
