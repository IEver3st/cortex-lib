-- Shared optics sensors for Cortex cameras and scopes (cortex-polcam, cortex-binoculars).
--
--   thermal  FLIR over GTA's seethrough pass. Palette colours live in visualsettings.dat
--            (seeThrough.*); they are overridden while the sensor is live and restored afterwards,
--            so other thermal users are untouched.
--   night    Phosphor night vision built as a timecycle colour grade, with automatic gain
--            (exposure) that follows the time of day, a manual gain knob and bright-source
--            protection supplied by the caller.
--
-- Use through the loader (`lib.sensors`) or include it directly as a client script
-- (`@cortex-lib/imports/sensors/client.lua`, which also exposes the global `CortexSensors`).
-- It runs in the caller's runtime; one camera owns the sensors at a time.
local GetGameTimer = GetGameTimer
local CreateThread = CreateThread
local Wait = Wait
local math_floor = math.floor
local math_abs = math.abs
local math_min = math.min
local math_max = math.max
local type = type
local tonumber = tonumber
local ipairs = ipairs
local pairs = pairs

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local sensors = { thermal = {}, night = {} }

-- Shipped looks, shared so every Cortex optic reads the same. Callers may pass their own.
sensors.defaults = {
    thermal = {
        DefaultPalette = 'whitehot',
        -- near/far: cold background by distance. base/warm/hot: the heat ramp. The near/far gap is
        -- the only terrain detail the game's thermal pass draws; ~0.10 balances detail and stair-steps.
        Palettes = {
            { id = 'whitehot', label = 'White Hot', short = 'WHT',
              near = { 0.20, 0.20, 0.20 }, far = { 0.10, 0.10, 0.10 },
              base = { 0.58, 0.58, 0.58 }, warm = { 0.84, 0.84, 0.84 }, hot = { 1.00, 1.00, 1.00 } },
            { id = 'blackhot', label = 'Black Hot', short = 'BLK',
              near = { 0.66, 0.66, 0.66 }, far = { 0.56, 0.56, 0.56 },
              base = { 0.32, 0.32, 0.32 }, warm = { 0.14, 0.14, 0.14 }, hot = { 0.00, 0.00, 0.00 },
              Sensor = { HighlightIntensity = 0.0 } },
            { id = 'ironbow', label = 'Ironbow', short = 'IRON',
              near = { 0.08, 0.02, 0.16 }, far = { 0.02, 0.01, 0.06 },
              base = { 0.58, 0.06, 0.38 }, warm = { 0.96, 0.46, 0.04 }, hot = { 1.00, 0.96, 0.78 } },
            { id = 'rainbow', label = 'Rainbow', short = 'RNBW',
              near = { 0.02, 0.06, 0.30 }, far = { 0.01, 0.02, 0.20 },
              base = { 0.00, 0.78, 0.36 }, warm = { 1.00, 0.86, 0.00 }, hot = { 1.00, 0.16, 0.06 } },
        },
        -- Stock GTA thermal sees through walls (MaxThickness 10000); a real FLIR cannot.
        Sensor = {
            SeeThroughWalls = false, MaxThickness = 1.0,
            NoiseMin = 0.04, NoiseMax = 0.22,
            HighlightIntensity = 0.45, HighlightNoise = 0.25,
            FadeStartDistance = 150.0, FadeEndDistance = 2000.0,
        },
    },
    night = {
        Intensity = 0.7,     -- heliGunCam strength for RenderMode 'game'
        RenderMode = 'custom', -- 'custom' grades a phosphor image; 'game' keeps GTA's green pass
        DefaultProfile = 'white',
        Profiles = {
            { id = 'white', label = 'White Phosphor', short = 'WP',
              tint = { 0.86, 0.93, 1.00 }, grain = 0.8, halo = 0.30, vignette = 0.35 },
            { id = 'green', label = 'Green Phosphor', short = 'GRN',
              tint = { 0.36, 1.00, 0.42 }, grain = 1.0, halo = 0.35, vignette = 0.35 },
        },
        Gain = {
            Mode = 'auto', Fixed = 0.85, DayGain = 0.15,
            MinExposure = 0.5, MaxExposure = 4.5,
            SpotlightProtection = 0.55, ResponseSeconds = 1.5, UpdateIntervalMs = 250,
            ManualStep = 0.05, ManualMin = 0.05, ManualMax = 2.0,
        },
    },
}

-- Entry with this id in a list of { id = ... } tables, and its index.
function sensors.find(list, id)
    if type(list) ~= 'table' then return nil, nil end
    for index, entry in ipairs(list) do
        if type(entry) == 'table' and entry.id == id then return entry, index end
    end
    return nil, nil
end

-- The entry after `id`, wrapping; the first when `id` is unknown.
function sensors.after(list, id)
    if type(list) ~= 'table' or #list == 0 then return nil end
    local _, index = sensors.find(list, id)
    return list[((index or 0) % #list) + 1]
end

-- Thermal ------------------------------------------------------------------------

local T = sensors.thermal
local VISUAL_GROUPS = {
    near = 'seeThrough.ColorNear',
    far = 'seeThrough.ColorFar',
    base = 'seeThrough.ColorVisibleBase',
    warm = 'seeThrough.ColorVisibleWarm',
    hot = 'seeThrough.ColorVisibleHot',
}
local VISUAL_CHANNELS = { 'red', 'green', 'blue' }
T.groups = VISUAL_GROUPS

local thermalActive = false
local originalVisual = nil
local visualOverridden = false

local function ColorChannel(color, index)
    local value = type(color) == 'table' and tonumber(color[index]) or nil
    return value and Clamp(value, 0.0, 1.0) or 0.0
end

-- Captured each time the sensor starts, so changes other resources make between uses survive.
local function CaptureOriginalVisualSettings()
    if visualOverridden or not GetVisualSettingFloat then return end
    originalVisual = {}
    for _, prefix in pairs(VISUAL_GROUPS) do
        for _, channel in ipairs(VISUAL_CHANNELS) do
            local key = prefix .. '.' .. channel
            originalVisual[key] = GetVisualSettingFloat(key)
        end
    end
end

local function RestoreVisualSettings()
    if not visualOverridden or not originalVisual or not SetVisualSettingFloat then return end
    for key, value in pairs(originalVisual) do
        if type(value) == 'number' then SetVisualSettingFloat(key, value + 0.0) end
    end
    visualOverridden = false
end

local function WritePaletteVisualSettings(palette)
    if not SetVisualSettingFloat or not originalVisual then return end
    for group, prefix in pairs(VISUAL_GROUPS) do
        local color = palette[group]
        if type(color) == 'table' then
            for index, channel in ipairs(VISUAL_CHANNELS) do
                SetVisualSettingFloat(prefix .. '.' .. channel, ColorChannel(color, index))
            end
        end
    end
    visualOverridden = true
end

local function SensorValue(palette, sensor, key)
    if type(palette.Sensor) == 'table' and palette.Sensor[key] ~= nil then return palette.Sensor[key] end
    return type(sensor) == 'table' and sensor[key] or nil
end

local function SetIfNumber(native, value, minValue, maxValue)
    value = tonumber(value)
    if native and value then native(Clamp(value, minValue, maxValue) + 0.0) end
end

-- SeethroughReset first so values left by other scripts never leak into the sensor.
local function ApplySensorProfile(palette, sensor)
    if SeethroughReset then SeethroughReset() end

    local near = palette.near
    if type(near) == 'table' and SeethroughSetColorNear then
        SeethroughSetColorNear(
            math_floor(ColorChannel(near, 1) * 255 + 0.5),
            math_floor(ColorChannel(near, 2) * 255 + 0.5),
            math_floor(ColorChannel(near, 3) * 255 + 0.5))
    end

    if SensorValue(palette, sensor, 'SeeThroughWalls') ~= true then
        SetIfNumber(SeethroughSetMaxThickness, SensorValue(palette, sensor, 'MaxThickness') or 1.0, 1.0, 10000.0)
    end
    SetIfNumber(SeethroughSetNoiseAmountMin, SensorValue(palette, sensor, 'NoiseMin'), 0.0, 1.0)
    SetIfNumber(SeethroughSetNoiseAmountMax, SensorValue(palette, sensor, 'NoiseMax'), 0.0, 1.0)
    SetIfNumber(SeethroughSetHiLightIntensity, SensorValue(palette, sensor, 'HighlightIntensity'), 0.0, 1.0)
    SetIfNumber(SeethroughSetHiLightNoise, SensorValue(palette, sensor, 'HighlightNoise'), 0.0, 1.0)
    SetIfNumber(SeethroughSetFadeStartDistance, SensorValue(palette, sensor, 'FadeStartDistance'), 0.0, 10000.0)
    SetIfNumber(SeethroughSetFadeEndDistance, SensorValue(palette, sensor, 'FadeEndDistance'), 0.0, 10000.0)

    local heatScales = SensorValue(palette, sensor, 'HeatScales')
    if type(heatScales) == 'table' and SeethroughSetHeatscale then
        for index = 0, 3 do
            local scale = tonumber(heatScales[index])
            if scale then SeethroughSetHeatscale(index, Clamp(scale, 0.0, 0.75) + 0.0) end
        end
    end
end

-- Re-applies a palette to the live sensor (palette change, tuning).
function T.apply(palette, sensor)
    WritePaletteVisualSettings(palette)
    ApplySensorProfile(palette, sensor)
    SetSeethrough(true)
end

function T.enable(palette, sensor)
    CaptureOriginalVisualSettings()
    SetNightvision(false)
    ClearTimecycleModifier()
    T.apply(palette, sensor)
    thermalActive = true
end

-- Returns whether the sensor was live.
function T.disable()
    local wasActive = thermalActive
    thermalActive = false
    if wasActive then SetSeethrough(false) end
    RestoreVisualSettings()
    if wasActive and SeethroughReset then SeethroughReset() end
    return wasActive
end

function T.isActive() return thermalActive end
function T.isOverridden() return visualOverridden end

-- Night vision -------------------------------------------------------------------

local N = sensors.night
local LEGACY_MODIFIER = 'heliGunCam'
local BASE_NOISE = 0.10 -- stock night postfx_noise is ~0.05; tubes are grainier

N.state = { Active = false, Gain = 0.0, ManualGain = nil, Protected = false, ModifierName = nil }
local state = N.state
local nightCfg, nightProfile, nightOptions = nil, nil, {}
local preparedModifiers = {}
local appliedGain = nil
local gainThreadRunning = false

local function GainConfig()
    local gain = nightCfg and nightCfg.Gain
    return type(gain) == 'table' and gain or sensors.defaults.night.Gain
end

function N.usesGameLook(cfg)
    return (cfg or nightCfg or {}).RenderMode == 'game'
end

local function SetVar(name, var, value)
    value = value + 0.0
    SetTimecycleModifierVar(name, var, value, value)
end
N.setVar = function(var, value)
    if not state.ModifierName then return false end
    SetVar(state.ModifierName, var, value)
    return true
end

-- Static look of a profile: monochrome, multiplied by the phosphor tint through both colour
-- correction bands, plus halo and vignette. Written once; modifiers persist in the game session.
local function PrepareModifier(profile)
    if not (CreateTimecycleModifier and SetTimecycleModifierVar and GetTimecycleModifierIndexByName) then return nil end

    local prefix = nightOptions.prefix or 'cortex_nv_'
    local name = prefix .. tostring(profile.id or 'profile'):gsub('[^%w_]', '')
    if GetTimecycleModifierIndexByName(name) == -1 and CreateTimecycleModifier(name) == -1 then return nil end

    if not preparedModifiers[name] then
        SetVar(name, 'postfx_desaturation', 0.0)
        for index, suffix in ipairs({ '_r', '_g', '_b' }) do
            local channel = Clamp(type(profile.tint) == 'table' and tonumber(profile.tint[index]) or 1.0, 0.0, 1.0)
            SetVar(name, 'postfx_correct_col' .. suffix, channel)
            SetVar(name, 'postfx_shift_col' .. suffix, channel)
        end
        SetVar(name, 'postfx_intensity_bloom', Clamp(tonumber(profile.halo) or 0.3, 0.0, 1.0))
        SetVar(name, 'postfx_vignetting_intensity', Clamp(tonumber(profile.vignette) or 0.35, 0.0, 1.0))
        preparedModifiers[name] = true
    end
    return name
end

-- 1.0 at night, 0.0 in daylight, eased through dawn (05-07) and dusk (19-21).
local function Darkness()
    local hours = (GetClockHours() or 0) + (GetClockMinutes() or 0) / 60
    if hours >= 21 or hours < 5 then return 1.0 end
    if hours < 7 then return 1.0 - (hours - 5) / 2 end
    if hours < 19 then return 0.0 end
    return (hours - 19) / 2
end

local function TargetGain()
    local cfg = GainConfig()
    local gain
    if state.ManualGain then
        gain = state.ManualGain
    elseif cfg.Mode == 'fixed' then
        gain = Clamp(tonumber(cfg.Fixed) or 0.85, 0.0, 1.0)
    else
        local dayGain = Clamp(tonumber(cfg.DayGain) or 0.15, 0.0, 1.0)
        gain = dayGain + (1.0 - dayGain) * Darkness()
    end

    local protected = nightOptions.protected and nightOptions.protected() == true or false
    if protected then gain = gain * Clamp(tonumber(cfg.SpotlightProtection) or 0.55, 0.0, 1.0) end
    return gain, protected
end

-- Gain is exposure. The weather pins night exposure with min = max, so all three move together
-- or auto-exposure wins. More amplification means more scintillation, as on a real tube.
local function WriteGain(name, gain)
    local cfg = GainConfig()
    local minExposure = tonumber(cfg.MinExposure) or 0.5
    local maxExposure = tonumber(cfg.MaxExposure) or 4.5
    local exposure = minExposure + (maxExposure - minExposure) * gain
    SetVar(name, 'postfx_exposure', exposure)
    SetVar(name, 'postfx_exposure_min', exposure)
    SetVar(name, 'postfx_exposure_max', exposure)

    local grain = Clamp(tonumber(nightProfile and nightProfile.grain) or 1.0, 0.0, 1.0) * (0.5 + gain)
    SetVar(name, 'postfx_noise', Clamp(BASE_NOISE * grain, 0.0, 1.0))
end

-- Fast attack, slow release: protection engages quickly and recovers gently.
function N.update(dtSeconds, snap)
    local target, protected = TargetGain()
    local response = math_max(0.05, tonumber(GainConfig().ResponseSeconds) or 1.5)
    if target < state.Gain then response = response * 0.25 end

    if snap then
        state.Gain = target
    else
        state.Gain = state.Gain + (target - state.Gain) * math_min(1.0, dtSeconds / response)
    end
    state.Protected = protected

    local name = state.ModifierName
    if name and (not appliedGain or math_abs(appliedGain - state.Gain) >= 0.01) then
        WriteGain(name, state.Gain)
        appliedGain = state.Gain
    end
end

-- Manual gain knob in ManualStep steps from ManualMin to ManualMax. Leaving AUTO moves one step
-- from the current automatic level; both ends hold. Returns true when the knob moved.
function N.step(direction)
    local cfg = GainConfig()
    local step = Clamp(tonumber(cfg.ManualStep) or 0.05, 0.01, 0.5)
    local minimum = Clamp(tonumber(cfg.ManualMin) or 0.05, 0.0, 1.0)
    local maximum = Clamp(tonumber(cfg.ManualMax) or 2.0, 1.0, 4.0)
    local manual = state.ManualGain
    local start = manual or math_floor(state.Gain / step + 0.5) * step

    local nextGain = Clamp(start + (direction > 0 and step or -step), minimum, maximum)
    if manual and math_abs(nextGain - manual) < 1e-6 then return false end
    state.ManualGain = nextGain
    N.update(0, true)
    return true
end

-- Back to automatic gain. Returns true when it was manual.
function N.resetGain()
    if not state.ManualGain then return false end
    state.ManualGain = nil
    N.update(0, true)
    return true
end

-- Another script replacing the primary modifier would silently drop the sensor back to the scene.
local function ReassertModifier()
    local name = state.ModifierName
    if not name or not GetTimecycleModifierIndex then return end
    local index = GetTimecycleModifierIndexByName(name)
    if index ~= -1 and GetTimecycleModifierIndex() ~= index then
        SetTimecycleModifier(name)
        SetTimecycleModifierStrength(1.0)
    end
end

local function StartGainLoop()
    if gainThreadRunning or not state.ModifierName then return end
    gainThreadRunning = true

    CreateThread(function()
        local interval = math_floor(Clamp(tonumber(GainConfig().UpdateIntervalMs) or 250, 50, 2000))
        while state.Active and state.ModifierName do
            Wait(interval)
            if state.Active then
                ReassertModifier()
                N.update(interval / 1000)
            end
        end
        gainThreadRunning = false
    end)
end

-- profile: { id, tint, grain, halo, vignette }. cfg: { RenderMode, Intensity, Gain }.
-- options: { prefix = modifier name prefix, protected = function() -> bright source present }.
function N.enable(profile, cfg, options)
    nightProfile, nightCfg, nightOptions = profile, cfg or sensors.defaults.night, options or {}
    local name = not N.usesGameLook() and PrepareModifier(profile) or nil

    SetSeethrough(false)
    if name then
        SetNightvision(false)
        SetTimecycleModifier(name)
        SetTimecycleModifierStrength(1.0)
    else
        SetNightvision(true)
        SetTimecycleModifier(LEGACY_MODIFIER)
        SetTimecycleModifierStrength(nightCfg.Intensity or 0.7)
    end

    state.ModifierName = name
    state.Active = true
    appliedGain = nil
    N.update(0, true)
    StartGainLoop()
end

-- Switches the live sensor to another phosphor. Returns true when it applied.
function N.setProfile(profile)
    nightProfile = profile
    if not state.Active then return false end
    local name = PrepareModifier(profile)
    if not name then return false end
    state.ModifierName = name
    SetTimecycleModifier(name)
    SetTimecycleModifierStrength(1.0)
    appliedGain = nil
    N.update(0, true)
    StartGainLoop()
    return true
end

-- Returns whether the sensor was live. keepManual retains the manual gain for the next enable.
function N.disable(keepManual)
    local wasActive = state.Active
    state.Active = false
    if not keepManual then state.ManualGain = nil end
    state.ModifierName = nil
    state.Protected = false
    appliedGain = nil
    if wasActive then
        SetNightvision(false)
        ClearTimecycleModifier()
    end
    return wasActive
end

function N.isActive() return state.Active end

-- Removes the authored modifiers. Call on resource stop, after the sensor is off.
function N.release()
    if not RemoveTimecycleModifier then return end
    for name in pairs(preparedModifiers) do
        if GetTimecycleModifierIndexByName and GetTimecycleModifierIndexByName(name) ~= -1 then
            RemoveTimecycleModifier(name)
        end
        preparedModifiers[name] = nil
    end
end

CortexSensors = sensors
if type(lib) == 'table' then rawset(lib, 'sensors', sensors) end

return sensors
