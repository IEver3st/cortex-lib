CORTEX LIB
==========
Version 2.2.1

Shared settings, notifications, menus and UI utilities for Cortex scripts.
Install it once and start it before every script that requires it.

INSTALL
-------
1. Extract the complete resource into your server's resources directory.
   Keep the folder named cortex-lib, with fxmanifest.lua directly inside.
2. Add this to server.cfg before your dependent scripts:

   ensure cortex-lib

3. Start your dependent scripts after it. For PolCam, for example:

   ensure cortex-polcam

No framework, database or frontend build is required by the library itself.
Use the library version required by your script. PolCam 1.0.2 needs 2.2.1;
the older 2.2.0 package lacks its shared presentation files.

SETTINGS AND CONTROLS
--------------------
  /cortexsettings   Open settings for the library and compatible scripts.
  /cortexpause      Open the quick menu if enabled; otherwise open settings.
  /cortexnative     Open GTA's native map/pause menu.

Use GTA's native keybinding editor for script controls.
Cortex Settings contains only library and script preferences. Escape closes
it; there is no back arrow, game-settings tab or keybinding link.

The quick menu is OFF by default. Only the server owner can enable it.
To use it, put this BEFORE ensure cortex-lib in server.cfg:

   setr cortex_pause_replace_native 1

Set it to 0 to disable it. You can also run either command in the server
console to change it immediately. Save the value in server.cfg for restarts.
Players have no quick-menu toggle. No library Lua edits are needed.
Player preferences are saved locally. Apply saves without closing;
Save & Resume saves and closes; Discard & Resume cancels unsaved changes.

UPDATING OR TROUBLESHOOTING
--------------------------
Back up the old version and stop dependent scripts before replacing files.
Start cortex-lib first, then restart its consumers. Do not mix releases.

Missing UI or settings: check the folder name, required library version,
start order, server console and the player's F8 console. A script only gets
a settings page if it registers one. Keep development diagnostics disabled.

Full instructions and developer reference: README.md
License: LICENSE (MIT)
