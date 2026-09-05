local GetGameTimer = GetGameTimer
local Wait = Wait

local Timer = {}
Timer.__index = Timer
local MAX_TIMER_DURATION = 2147483647

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function elapsedSince(now, startedAt)
    local elapsed = now - startedAt
    return elapsed < 0 and elapsed + 4294967296 or elapsed
end

local function safeErrorText(value)
    local ok, text = pcall(tostring, value)
    if not ok or type(text) ~= 'string' then return '<unprintable error>' end
    if #text > 512 then return text:sub(1, 512) .. '...' end
    return text
end

local function runEndCallback(self)
    if not self._onEnd then return end
    local ok, err = pcall(self._onEnd)
    if not ok then pcall(print, ('^1[cortex-lib]^7 timer callback failed: %s'):format(safeErrorText(err))) end
end

local function runTimer(self, runId)
    while not self._ended and self._runId == runId do
        if not self._paused then
            local elapsed = elapsedSince(GetGameTimer(), self._startTime)
            self._remaining = self._duration - elapsed

            if self._remaining <= 0 then
                self._remaining = 0
                self._ended = true

                runEndCallback(self)
                break
            end
        end

        Wait(50)
    end
end

local function timer(duration, onEnd, async)
    if not isFiniteNumber(duration) or duration < 0 or duration > MAX_TIMER_DURATION then
        error('cortex-lib.timer: duration must be a finite number between 0 and 2147483647 ms')
    end
    if onEnd ~= nil and type(onEnd) ~= 'function' then
        error('cortex-lib.timer: onEnd must be a function or nil')
    end
    if async ~= nil and type(async) ~= 'boolean' then
        error('cortex-lib.timer: async must be a boolean or nil')
    end

    duration = math.floor(duration)
    if async == nil then async = true end
    
    local self = setmetatable({
        _duration = duration,
        _remaining = duration,
        _startTime = GetGameTimer(),
        _onEnd = onEnd,
        _paused = false,
        _ended = false,
        _pauseTime = 0,
        _runId = 0
    }, Timer)

    self._runId = self._runId + 1
    local runId = self._runId

    if async then
        CreateThread(function()
            runTimer(self, runId)
        end)
    else
        runTimer(self, runId)
    end
    
    return self
end

function Timer:pause()
    if not self._paused and not self._ended then
        self._pauseTime = GetGameTimer()
        self._remaining = math.max(0, self._duration - elapsedSince(self._pauseTime, self._startTime))
        if self._remaining == 0 then
            self._ended = true
            runEndCallback(self)
        else
            self._paused = true
        end
    end
    return self
end

function Timer:play()
    if self._paused and not self._ended then
        self._paused = false
        self._startTime = GetGameTimer() - (self._duration - self._remaining)
    end
    return self
end

Timer.resume = Timer.play

function Timer:forceEnd(triggerCallback)
    if self._ended then return end
    
    self._ended = true
    self._remaining = 0
    
    if triggerCallback ~= false then runEndCallback(self) end
end

function Timer:restart()
    self._startTime = GetGameTimer()
    self._remaining = self._duration
    self._paused = false
    self._ended = false
    self._runId = self._runId + 1

    local runId = self._runId
    CreateThread(function()
        runTimer(self, runId)
    end)
    
    return self
end

function Timer:isPaused()
    return self._paused
end

function Timer:hasEnded()
    return self._ended
end

function Timer:getTimeLeft()
    if self._ended then return 0 end
    if self._paused then return self._remaining end
    
    local elapsed = elapsedSince(GetGameTimer(), self._startTime)
    local remaining = self._duration - elapsed
    return remaining > 0 and remaining or 0
end

function Timer:getTimeLeftFormatted()
    local ms = self:getTimeLeft()
    local seconds = math.floor(ms / 1000)
    local minutes = math.floor(seconds / 60)
    seconds = seconds % 60
    return string.format('%02d:%02d', minutes, seconds)
end

exports('timer', timer)

lib.timer = timer

return timer
