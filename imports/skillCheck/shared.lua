-- Relative mouse trace as a forgiving "virtual knob", independent of cursor/screen coordinates.
--
-- A knob sits on a half ring of radius R (normalized mouse units) at 3 o'clock. Each native
-- mouse delta is added to the knob and the result is projected back onto the ring, so only
-- tangential motion turns it; radial motion is ignored. Lower: 3 -> 6 -> 9 (clockwise on
-- screen); upper mirrors Y: 3 -> 12 -> 9. One sweep in the right direction completes it.
--
-- Scale: GetDisabledControlUnboundNormal(0, 1/2) returns the mouse delta for the current frame
-- (already frame-scaled; summing samples is frame-rate independent). The natives document no
-- absolute scale, so R is calibrated against the one tuned mouse-normal constant in this tree:
-- cortex-hud's virtual weapon-wheel selector reaches full deflection after 1 / 2.2 ~= 0.45
-- units, i.e. one small wrist flick. R = 0.5 makes the knob circle about one such flick in
-- radius: a sweep needs about pi * R ~= 1.6 units of tangential travel, and because people
-- draw arcs larger than necessary the knob usually runs ahead of the hand and simply waits.
-- `sensitivity` (0.25-4) divides R for servers whose players report too much/too little travel.
local TRACE_RADIUS = 0.5
local TRACE_MIN_TANGENT = 0.25 -- |tangential| / |delta| below this is radial noise (~75 degrees)
local TRACE_CENTRE_GUARD = 0.5 -- a sub-step landing inside 0.5 R would cross the centre: ignored
local TRACE_COMPLETE = 0.96 -- 173 degrees; a straight swipe stalls by ~151 degrees
local TRACE_IDLE_MS = 1500 -- pauses shorter than this cost nothing
local TRACE_EASE_PER_SECOND = 0.35 -- progress eased back per second after a long idle
local TRACE_MAX_CHUNKS = 64

local function newMouseTrace(radius)
    return { angle = 0, peak = 0, progress = 0, invalid = false, radius = radius or TRACE_RADIUS,
        lastMotion = nil, lastSample = nil }
end

local function easeIdle(state, now)
    local previous = state.lastSample or now
    state.lastSample = now
    if not state.lastMotion or state.angle <= 0 then return end
    local from = math.max(previous, state.lastMotion + TRACE_IDLE_MS)
    if now <= from then return end
    state.angle = math.max(0, state.angle - (now - from) / 1000 * TRACE_EASE_PER_SECOND * math.pi)
    state.peak = state.angle
end

local function stepMouseTrace(state, dx, dy, now, direction, tolerance)
    easeIdle(state, now)
    if type(dx) ~= 'number' or type(dy) ~= 'number' or dx ~= dx or dy ~= dy
        or math.abs(dx) > 10 or math.abs(dy) > 10 then
        -- A corrupt native sample is dropped; it never advances or resets progress.
        state.invalid = true
        return false
    end
    if direction == 'upper' then dy = -dy end
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.00001 then
        state.progress = state.angle / math.pi
        return false
    end
    state.lastMotion, state.invalid = now, false
    local radius = state.radius
    -- Sub-step large deltas (fast flicks, low FPS) so they behave like the same motion drawn
    -- slowly: a single hitch can never jump the knob across the ring.
    local chunks = math.min(TRACE_MAX_CHUNKS, math.max(1, math.ceil(distance / (radius * 0.25))))
    local sx, sy = dx / chunks, dy / chunks
    local step = distance / chunks
    local guard = (radius * TRACE_CENTRE_GUARD) ^ 2
    for _ = 1, chunks do
        local angle = state.angle
        local c, s = math.cos(angle), math.sin(angle)
        local tangential = -s * sx + c * sy
        if math.abs(tangential) >= TRACE_MIN_TANGENT * step then
            local px, py = radius * c + sx, radius * s + sy
            if px * px + py * py >= guard then
                local delta = math.atan(py, px) - angle
                if delta > math.pi then delta = delta - 2 * math.pi
                elseif delta < -math.pi then delta = delta + 2 * math.pi end
                -- Small reversals are tolerated: the knob may slide back at most `tolerance` of a
                -- half turn below its best position, so wobble never resets and jiggling nets zero.
                local floor = math.max(0, state.peak - tolerance * math.pi)
                state.angle = math.min(math.pi, math.max(floor, angle + delta))
                if state.angle > state.peak then state.peak = state.angle end
            end
        end
    end
    state.progress = state.angle / math.pi
    return state.progress >= TRACE_COMPLETE
end
