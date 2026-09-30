# Cortex Settings and the optional quick menu

Cortex Settings uses the existing React root, resource-owned tabs, settings
schemas and KVP persistence. The game stays visible behind a 55% ink scrim
(`surfaces/settings.css`) and a heavy native blur: `client/pause.lua` layers a
clone of `hud_def_blur` with its blur variables scaled x8 as the extra
timecycle modifier, plus `TriggerScreenblurFadeIn`. Every settings session gets
it, whether opened from the quick menu, `/cortexsettings` or
`openSettingsMenu()`. No CSS backdrop filter is used. The header has no back
arrow; game settings and keybindings are absent from the settings surface.

Apply saves without closing. Save & Resume saves and closes. Discard, Escape,
the readiness timeout, another modal taking focus, a native frontend handoff
and resource stop roll back unsaved previews and release focus and owned blur
(all through `lib._settingsVisibilityChanged(false)`); the pause loop also
releases any blur still owned while nothing is visible. An extra timecycle
effect owned by another resource is never replaced or cleared.
An open dropdown handles Escape before the settings modal does.

## Server configuration

The quick menu defaults to off. `server/config.lua` publishes
`cortex_pause_replace_native` as a replicated server convar even when omitted
from `server.cfg`. Only the server controls it; the old player KVP is ignored.

```cfg
# Optional. Put before ensure cortex-lib; omit or use 0 to disable.
setr cortex_pause_replace_native 1
setr cortex_pause_title "CORTEX"
```

The switch also takes effect live from the server console. Disabling an open
quick menu routes it to Settings. `/cortexpause` opens Settings when disabled.
`/cortexsettings` and `openSettingsMenu()` always open Settings directly.

## Ownership and input

`imports/settings/client.lua` owns values, preview snapshots, persistence and
modal focus. `client/pause.lua` owns pause input, native handoffs, blur and
extension registries. `ui/pause.js` and `ui/pause.css` render inside `ui/app.js`.

When enabled, native Escape/P/Start entry requires a matching gameplay press and
release. Foreign NUI focus, native text entry, warnings, frontend ownership or
a disabled pause control cancel pending entry. Closed default-mode polling
sleeps for 250 ms and does not suppress native controls. Open settings suppress
world input; controller navigation forwards input edges only.

The optional quick menu offers Resume, Map, Settings, Key bindings and confirmed
Leave server. Map uses GTA's native map and preserves its blips, legend and
controls. Key bindings uses GTA's native editor. Both release the modal before
handoff and return to the quick menu when the owned frontend closes. A foreign
frontend takeover cancels that return. There is no custom keybinding registry,
Scaleform settings bridge or mouse-input forwarding bridge.

Registered pages and locations are copied, bounded and scoped to their owner.
NUI actions identify registry entries, not arbitrary commands. Each callback
validates the active session and completes once. Consumers remain responsible
for gameplay permissions and server authority. Owner stop removes entries;
consumers must re-register after cortex-lib restarts.

## Validation

`tests/pause_lifecycle_spec.lua` exercises the real controller/settings modules
with stubbed natives. `tests/pause_ui.test.mjs` and
`tests/settings_hidden_work.test.mjs` inspect component behavior without rendering
pixels. These checks cover default-off configuration, focus, rollback, input
ownership, native handoffs and the stripped settings navigation.

See [release acceptance](release.md) for the user-run game checks. Native blur,
CEF appearance, actual controller input and resource timing require FiveM proof.
