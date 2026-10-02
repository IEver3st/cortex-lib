-- Shared wheel telemetry for Director and Rewind. Capture never mutates a
-- vehicle. Rotation is angular velocity, not Xrot/YRotation (wheel geometry).
-- Compression is read-only: Cfx has no corresponding per-wheel setter.
local Replay = { MAX_WHEELS = 10, SIZE = 20, UNKNOWN_COMPRESSION = -1 }
local MAX_SPEED = 10000
local function finite(n) return type(n) == 'number' and n == n and math.abs(n) < math.huge end
local function wheelCount(vehicle)
    if not DoesEntityExist(vehicle) then return 0 end
    local count = GetVehicleNumberOfWheels(vehicle)
    return finite(count) and math.max(0, math.min(Replay.MAX_WHEELS, math.floor(count))) or 0
end

function Replay.capture(vehicle, out, offset)
    out, offset = out or {}, offset or 0
    local count = wheelCount(vehicle)
    local rotation = rawget(_ENV, 'GetVehicleWheelRotationSpeed')
    local compression = rawget(_ENV, 'GetVehicleWheelSuspensionCompression')
    for index = 1, Replay.MAX_WHEELS do
        local speed = index <= count and rotation and rotation(vehicle, index - 1) or 0
        local spring = index <= count and compression and compression(vehicle, index - 1) or -1
        out[offset + index] = finite(speed) and math.abs(speed) <= MAX_SPEED and speed or 0
        out[offset + Replay.MAX_WHEELS + index] = finite(spring) and spring >= 0 and spring or -1
    end
    if offset == 0 then out.count = count end
    return out, count
end

function Replay.copy(source, out, offset, rate)
    out, offset, rate = out or {}, offset or 0, rate or 1
    for index = 1, Replay.SIZE do
        out[offset + index] = source[index] * (index <= Replay.MAX_WHEELS and rate or 1)
    end
    if offset == 0 then out.count = source.count end
    return out
end

-- Offsets allow the same interpolation to operate on a flat Director track or
-- a standalone Rewind frame. Missing compression must never blend into a pose.
function Replay.interpolate(a, b, t, out, ao, bo, offset)
    out, ao, bo, offset = out or {}, ao or 0, bo or 0, offset or 0
    for index = 1, Replay.SIZE do
        local one, two = a[ao + index], b[bo + index]
        out[offset + index] = index > Replay.MAX_WHEELS and (one < 0 or two < 0)
            and one or one + (two - one) * t
    end
    if offset == 0 then out.count = a.count end
    return out
end

function Replay.valid(data, offset)
    offset = offset or 0
    for index = 1, Replay.SIZE do
        local value = data[offset + index]
        if not finite(value) or (index <= Replay.MAX_WHEELS and math.abs(value) > MAX_SPEED)
            or (index > Replay.MAX_WHEELS and value < 0 and value ~= -1) then return false end
    end
    return true
end

function Replay.apply(vehicle, data, rate, count, offset)
    offset = offset or 0
    local setter = rawget(_ENV, 'SetVehicleWheelRotationSpeed')
    if not setter or not finite(rate) or not Replay.valid(data, offset) then return false end
    local available = wheelCount(vehicle)
    if available == 0 then return false end
    if NetworkGetEntityIsNetworked(vehicle) and not NetworkHasControlOfEntity(vehicle) then return false end
    count = count or data.count or 0
    if not finite(count) or count < 0 or count % 1 ~= 0 then return false end
    count = math.min(available, count)
    for index = 1, count do
        local speed = data[offset + index] * rate
        setter(vehicle, index - 1, math.max(-MAX_SPEED, math.min(MAX_SPEED, speed)))
    end
    return true
end

-- Repairing a dent must not use the former radius=1000 area impact. Use the
-- documented native example's radius, shared by both callers, not wheel flags
-- or collider edits to undo the damage afterwards.
function Replay.dent(vehicle, dent, force)
    SetVehicleDamage(vehicle, dent.x * 2, dent.y * 2, dent.z * 2, dent.size * force, 100.0, true)
end

return Replay
