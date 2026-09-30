/* Deterministic local mechanics. No timers, DOM, bridge traffic or gameplay. */
(function (root) {
    'use strict';
    const clamp = (n, low = 0, high = 1) => Math.min(high, Math.max(low, n));
    const inTarget = (value, config) => value >= config.targetStart && value <= config.targetStart + config.targetSize;
    /** 1 at the centre of the target zone, 0 at its edge. Presentation only (outcome tag). */
    const accuracy = (value, config) => clamp(1 - Math.abs(value - (config.targetStart + config.targetSize / 2)) / (config.targetSize / 2));
    function create(config, now) {
        return { config, started: now, progress: 0, index: 0, held: false, holdStart: null,
            result: null, score: null };
    }
    function end(state, success, reason = success ? 'success' : 'missed', score = null) {
        if (state.result) return;
        state.result = { success, reason };
        state.score = success && Number.isFinite(score) ? Math.round(clamp(score) * 100) : null;
    }
    function tick(state, now) {
        if (state.result) return state;
        const c = state.config;
        if (now - state.started >= c.duration) end(state, false, 'timeout');
        if (c.type === 'radial') state.progress = ((now - state.started) / 1000 * c.speed) % 1;
        if (c.type === 'hold' && state.held) {
            state.progress = clamp((now - state.holdStart) / 1000 * c.speed);
            if (state.progress >= 1) end(state, false);
        }
        return state;
    }
    function input(state, value, down, now, repeat = false) {
        tick(state, now);
        if (state.result || repeat) return;
        const c = state.config;
        if (value === 'ESCAPE' && down) { end(state, false, 'cancelled'); return; }
        if (!down) {
            if (c.type === 'hold' && value === c.key && state.held) {
                state.held = false;
                const hit = inTarget(state.progress, c);
                end(state, hit, undefined, accuracy(state.progress, c));
            }
            return;
        }
        if (c.type === 'sequence') {
            if (value !== c.keys[state.index]) { end(state, false); return; }
            state.index++;
            state.progress = state.index / c.keys.length;
            // Sequence score is speed: full marks inside the first quarter of the budget.
            if (state.index === c.keys.length) end(state, true, undefined, 1 - Math.max(0, (now - state.started) / c.duration - 0.25) / 1.5);
        } else if (value === c.key && c.type === 'radial') end(state, inTarget(state.progress, c), undefined, accuracy(state.progress, c));
        else if (value === c.key && c.type === 'hold' && !state.held) {
            state.held = true;
            state.holdStart = now;
        }
    }
    root.CortexSkillEngine = { create, tick, input, clamp, inTarget, accuracy };
})(typeof window === 'undefined' ? globalThis : window);
