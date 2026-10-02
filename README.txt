CORTEX LIB
==========
Shared UI and Lua utilities for FiveM resources.
Maintained by Ever3st and GSD Modifications. MIT license.

INSTALL
-------
Download cortex-lib.zip from:
https://github.com/IEver3st/cortex-lib/releases

Extract the complete cortex-lib folder into resources. Keep the exact name,
with fxmanifest.lua directly inside. Add this order to server.cfg:

    ensure cortex-lib
    ensure your-resource

No framework, database or frontend build is required by the library itself.
The optional groups module needs cortex-phone for group operations.

SETTINGS
--------
/cortexsettings opens shared settings. Apply saves without closing.
Save & Resume saves and closes. Discard & Resume and unsaved Escape restore
values from opening or the latest Apply. Preferences are stored per client.

The quick menu is disabled by default. To enable it, put this before startup:

    setr cortex_pause_replace_native 1

Use 0 to disable it. /cortexpause opens the enabled quick menu or settings.
/cortexnative opens the native map/pause frontend when input is available.
Keep setr cortex_debug 0 on a normal server.

UPDATING TO 3.0
---------------
The UI app API and cortex:uiEvent callback are removed. Update consumers
that use them first. Shared appearance moved into the Cortex settings tab;
the separate Dynamic UI tab and per-resource appearance opt-outs are removed.
Retained appearance preferences migrate automatically. No SQL migration.

Back up the old folder, stop consumers and replace the whole library.
Start cortex-lib first, then consumers. Check settings, UI close paths and
each consumer's main feature. Do not mix files from different releases.

DOCS AND SUPPORT
----------------
README.md contains installation, configuration and developer examples.
API: https://github.com/IEver3st/cortex-lib/blob/main/docs/api.md
Issues: https://github.com/IEver3st/cortex-lib/issues
License and bundled component notices: LICENSE and THIRD_PARTY_NOTICES.md
