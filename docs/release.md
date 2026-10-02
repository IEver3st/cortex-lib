# Runtime acceptance

The release workflow validates source, runs Node contract tests and Lua specs, packages the runtime and customer docs, then checks the extracted ZIP before publishing. It also downloads the published assets and verifies their checksum and bytes. See [automatic releases](automatic-releases.md) for versioning and publication rules.

FiveM, CEF, native input, multiplayer and resource performance remain user-run checks. No static test or browser fixture establishes those results.

## Install the artifact

Download `cortex-lib.zip` and `cortex-lib.zip.sha256` from the release being tested. Verify SHA-256, extract the single `cortex-lib` folder onto a test server, and follow the shipped README. Start the library before consumers. Use the complete archive, not files from the development checkout.

Default configuration:

```cfg
setr cortex_pause_replace_native 0
setr cortex_debug 0
ensure cortex-lib
ensure your-resource
```

Saved client preferences and FiveM bindings survive updates. Check first-install defaults with a fresh client profile, or record which preferences were already saved.

## Acceptance checklist

These items are **pending** until the tester records results for the exact archive:

- [ ] Clean startup: library, then consumers; no missing packfile assets, loader errors or server/F8 errors.
- [ ] Settings: open `/cortexsettings`; preview scale and a custom accent; Apply, Save, Discard and Escape; reopen and reconnect to check persistence. Native blur and NUI focus must clear on every close and stop path.
- [ ] Notifications, menus, radial menus and dialogs: representative success, cancellation and invalid-input paths; keyboard/mouse navigation; focus returns to gameplay.
- [ ] Progress and skill checks: completion, cancellation and interruption; no stuck controls or overlays.
- [ ] Quick menu: default Escape behavior with the switch off; enable it using `setr cortex_pause_replace_native 1`; test map and native bindings; disable it while open and confirm the settings handoff.
- [ ] Interactions: screen, world, entity and entity-bone anchors; range and off-screen transitions; entity deletion and model reuse; key collisions; markers and merged-list selection; press, hold and cancellation.
- [ ] Lifecycle: restart `cortex-lib`, then consumers, with a surface previously open; stop a consumer with prompts or settings registered; confirm cleanup and registration after restart.
- [ ] Layout: normal and alternate resolution/aspect ratio, safe zone, UI scale and text size; transparent backing and readable surfaces.
- [ ] Callbacks and optional integrations: two clients for changed network behavior; `groups` with `cortex-phone` running and stopped; replay telemetry with and without network control when used by consumers.
- [ ] Performance: record idle and active resmon for the tested flows. Publish only measured results with their conditions.

For development specimens, temporarily set `cortex_debug 1` before restarting and use `/cortexdebug`. Disable it afterward. Do not add the legacy `tests/client/debug_commands.lua` to a production manifest.

## Record the result

Keep the release tag, source SHA, ZIP SHA-256, server/game build, consumers and their versions, test date, resolution, safe zone, pass/fail results and console errors together. Mark unavailable cases as untested. If runtime files change, rebuild and repeat the affected cases against the new archive.
