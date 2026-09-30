# Release preparation: 2.2.1

This is a local release candidate from the working tree. No commit, tag or public release was created during this preparation. On September 24, 2026, GitHub's latest published library release was 2.2.0; 2.2.1 was available as a new version. Recheck tags before publishing.

PolCam's current 1.0.2 source needs this candidate's `presentation-client.lua`, shared Dynamic UI assets and font. Those files are absent from the library's 2.2.0 tag. Publish or supply the matching library package with PolCam; do not direct these customers to an older dependency ZIP.

## Defaults

- Quick menu: disabled. Only the server can enable it with `setr cortex_pause_replace_native 1`; use `0` to disable it. No player preference can override the server. The command also takes effect live.
- Notification position: top-right. Notification audio: enabled, MP Idle Kick preset.
- Diagnostic workbench and its server callback: disabled. Enable only for development with `setr cortex_debug 1` before startup; remove the override after testing.
- The legacy `/cortex` demo script is excluded from the manifest and runtime archive.

Saved client KVP preferences and FiveM keybindings take precedence over defaults. Installing an archive does not erase them. Use a fresh client profile when checking first-install defaults, or adjust preferences in `/cortexsettings`. No database migration is required.

## Install

Extract the archive as one `cortex-lib` folder. Add `ensure cortex-lib` before its consumers. The bundled HTML, JavaScript, CSS, React runtime and font are ready to serve; there is no frontend build or CDN dependency.

Runtime archives contain the manifest, Lua entrypoints/modules, UI, customer README files and license notices. Developer documentation, tests, tools, agent context, package-manager files and Git metadata are excluded. Source checks run before packaging; the extracted archive is checked separately.

The custom binding editor, metadata bridge, managed-binding APIs and control catalog have been removed. Cortex Settings contains only library and script preferences. The optional quick menu retains a native Key bindings shortcut. The debug mash specimen uses its own native FiveM mapping. Old custom-editor client KVP records are no longer read; they are not deleted or migrated into native bindings.

The release workflow publishes on a push to `main` or `master` when the manifest's version tag does not yet exist. Commit all required runtime files, including newly added assets, together. Do not push the release commit until runtime acceptance is complete. A working-tree candidate is not yet a reproducible tagged release.

## User-run acceptance

Static checks cannot establish a clean FiveM installation. On an isolated server/client profile:

1. Start the extracted resource, then consumers, and check F8/server logs for missing files or startup errors.
2. With the default config, confirm Escape retains the native/other pause menu. Open `/cortexsettings`: check the blurred game background, no back arrow or game/keybinding tabs, and preview, Apply, Discard, Save and Escape behavior. Verify focus and blur clear on close.
3. Enable the quick menu from the server console with `setr cortex_pause_replace_native 1`. Check Escape, map and native keybindings, then disable it while open with value `0`. It must show only Cortex Settings. Players must have no quick-menu toggle.
4. Confirm `/cortexdebug` is unavailable with the default config. On a development server, enable it, restart, run representative menu, interaction and skill checks, then disable it again.
5. Restart `cortex-lib`, then consumers, while menus or interactions are active. Check cleanup, focus recovery and registration after restart.
6. Check transparent NUI backing and layout at your normal resolution/safe-zone settings. Verify active and idle resource cost in game.

For the PolCam dependency gate:

1. Install the exact library archive alongside the matching PolCam candidate. Start `cortex-lib`, then `cortex-polcam`; no other Cortex resource should be necessary for its settings or shared presentation.
2. Open the PolCam settings page. Preview contrast and target-label changes, Discard, then change and Save. Reopen and reconnect to check persistence. Confirm focus returns to the game each time.
3. In a supported helicopter, open and close the camera, check its shared font and overlays, and trigger a normal notification. Test Escape with the quick menu enabled and with `cortex_pause_replace_native 0`.
4. Restart the library, then PolCam, with the camera or settings previously active. Check registration, overlays, input and error logs afterward.
5. Use two clients to confirm PolCam camera handoff, spotlight synchronization and cleanup. PolCam's gameplay/server checks are separate from library readiness.

For shared interactions, use the opt-in workbench: screen, world, entity and entity-bone prompts; range and off-screen transitions; entity deletion/model reuse; key collisions; press, hold and cancel; resolution/safe-zone changes; consumer stop cleanup. Record unavailable scenarios rather than treating them as passed.

Record the ZIP SHA-256, server/game build, resolution/safe zone, consumers, test date and pass/fail results with any console errors. The archive that passes is the one to publish. If source files change afterward, rebuild and repeat the affected checks.

Framework integrations, multiplayer behavior and live CEF rendering still require your environment. Keep the archive checksum with the runtime acceptance record; publish only the artifact that passes those checks.
