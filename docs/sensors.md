# Optics sensors

`imports/sensors/client.lua` is the thermal and night vision engine shared by Cortex cameras and scopes. cortex-polcam and cortex-binoculars both run on it, so a palette looks the same through either. It runs in the caller's runtime and drives global game state (seethrough, visual settings, timecycle), so only one camera should own it at a time.

## Loading

```lua
local sensors = lib.sensors                       -- with shared_script '@cortex-lib/init.lua'
-- or, without the loader:
client_script '@cortex-lib/imports/sensors/client.lua'  -- then use the CortexSensors global
```

## Thermal

```lua
local d = sensors.defaults.thermal
local palette = sensors.find(d.Palettes, 'whitehot')
sensors.thermal.enable(palette, d.Sensor)   -- captures visual settings, applies, SetSeethrough(true)
sensors.thermal.apply(sensors.after(d.Palettes, palette.id), d.Sensor) -- switch palette live
sensors.thermal.disable()                   -- restores visual settings; returns whether it was live
```

A palette is `{ id, label, short, near, far, base, warm, hot, Sensor? }` with 0-1 RGB colours. `Sensor` values (`SeeThroughWalls`, `MaxThickness`, noise, highlight, fade distances, `HeatScales`) come from the palette's own `Sensor` table first, then the sensor table passed in.

## Night vision

```lua
local d = sensors.defaults.night
sensors.night.enable(sensors.find(d.Profiles, 'white'), d, {
    prefix = 'my_resource_nv_',                   -- timecycle modifier name prefix
    protected = function() return spotlightOn end, -- optional bright-source protection
})
sensors.night.setProfile(sensors.find(d.Profiles, 'green'))
sensors.night.step(1) / sensors.night.resetGain()   -- manual gain knob / back to auto
sensors.night.disable(keepManualGain)
sensors.night.release()                             -- on resource stop: remove authored modifiers
```

`sensors.night.state` exposes `Active`, `Gain`, `ManualGain`, `Protected` and `ModifierName` for HUDs. `cfg.RenderMode = 'game'` keeps GTA's green night vision instead of the phosphor grade. Gain follows the clock (`Gain.Mode = 'auto'`) or holds `Gain.Fixed`, and the live modifier is reasserted if another script replaces it.

Tests: cortex-polcam's `tests/flir-state.test.lua` and `tests/nightvision-state.test.lua` load this module directly; cortex-binoculars' `tests/client_spec.lua` drives it through the binoculars.
