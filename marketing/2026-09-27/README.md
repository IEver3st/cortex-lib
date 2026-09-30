# Cortex-Lib marketing pack

Six 1920 × 1080 feature images, six layered PSDs, and two reusable overlay PSDs with transparent PNG exports.

- `final/`: ready-to-use marketing PNGs.
- `psd/`: named layers for backgrounds, diagonal accents, GSD branding, product captures and captions. Headline/body copy and LIB titles contain editable Photoshop text data. Letter-spaced mastheads and small labels are raster layers.
- `overlays/cortex-lib-frame.png`: blue corner frame and GSD mark, transparent center.
- `overlays/cortex-lib-title.png`: centered Cortex-Lib title treatment, transparent background.
- `raw/`: cropped captures of the real shipped React UI with representative demo data.
- `contact-sheet.png`: all six final images at a glance.

## Local showcase

Running at http://127.0.0.1:5196/ with a gallery at http://127.0.0.1:5196/?gallery=1.

From the Cortex-Lib repository, restart with:

```powershell
node marketing/2026-09-27/source/server.mjs
```

The server binds only to IPv4 loopback. It serves current `ui/` assets, remaps the Cfx asset URLs at response time, and injects the development fixture. No production UI, Lua, manifest or vendored runtime files were edited. The showcase tabs reload a clean sample state. Menus, forms, settings controls and radial selection use the real UI; browser callbacks are simulated and recorded in `window.__demoCallbacks`. No browser action changes FiveM state or persists KVP settings.

## Design and source

Reference: the supplied Cortex-Polcam overlay. Blue `#6b9bfa`, midnight `#0b111b`, paper `#f0f0e9`, diagonal corner edges. The library icon and GSD logo are the exact assets supplied in this conversation, preserved as independent image layers. Original UI colors and typography remain intact.

Each shot has one subject. The overview combines separately captured real components; other shots isolate a feature. Settings uses a wider composition for readability. No gameplay screenshot, performance metric or multiplayer result is implied. Browser captures were made with the T3 collaborative preview, followed by local canvas composition; these are not Cap renders.

The revised set removes the upper-right feature labels, footer category, footer rules and slide numbers. Copy names the feature and describes its controls. GSD branding is above the product layers, with enough space to keep captures from crossing it. The settings capture hides a browser scrollbar caused by one pixel of tab-strip overflow; the controls and scrolling behavior are unchanged. No production UI source was edited.

Main PSD text uses Arial and Arial Black. Photoshop may ask to update text rendering when opening programmatically authored text layers. The stored composite and raster previews are included. PSD structure and composite pixels were checked programmatically; Adobe Photoshop itself was not launched.

## Rebuild and verification

In `source/`, run `npm ci`, then `node build.cjs`. Existing raw captures are reused; `--refresh` re-crops original screenshot paths from `captures.json` and is specific to this workstation. The renderer uses Windows Arial fonts.

The campaign does not enter the FiveM packfile. Keep `marketing/` out of a resource release archive. Repository Node checks and the resource validator cover static contracts only. No Lua or runtime behavior changed, so no new in-game acceptance gate is needed for these marketing files. Before using these images as evidence of your live setup, restart cortex-lib then consumers and personally check notification dismissal, menu/radial input and close, dialog submission/cancel, settings preview/save/discard, and prompt cleanup in FiveM. Native gameplay and CEF remain user-run checks.
