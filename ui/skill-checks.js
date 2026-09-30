/* Skill checks in the cortex-minigames language: a compact slip lower-centre, thick strokes,
 * keycaps that press, mint = the player's live marker, targets paper, misses soft red and a
 * brief outcome slip tag (CLEAR | 92). Lua owns sessions, focus and results; this file only
 * renders `skill:*` messages and reports keyboard results for radial/hold/sequence. */
(function () {
    'use strict';
    const { createElement: h, useState, useEffect, useRef } = React;
    const engine = window.CortexSkillEngine;
    const kit = () => window.CortexKit;
    const TYPES = ['radial', 'trace', 'hold', 'sequence', 'mash'];
    const OUTCOME_MS = 900;
    const listeners = new Set();
    let session = null;
    let outcomeTimer = 0;
    const notify = () => listeners.forEach(fn => fn(session));
    // One bounded transport for the whole NUI (core/base.js).
    const post = (name, data) => nuiPost(name, data, { timeoutMs: 2500 });

    window.addEventListener('message', event => {
        const { action, data } = event.data || {};
        if (!data || !Number.isSafeInteger(data.session)) return;
        if (action === 'skill:open') {
            const config = data.config;
            if (!config || !TYPES.includes(config.type)) return;
            clearTimeout(outcomeTimer);
            session = { ...data, ready: false, progress: 0, updated: performance.now(), startedAt: 0, pulse: 0, outcome: null };
            notify();
            post('skillReady', { session: data.session });
        } else if (session && data.session === session.session && !session.outcome) {
            if (action === 'skill:start') session = { ...session, ready: true, updated: performance.now(), startedAt: performance.now() };
            else if (action === 'skill:progress') session = { ...session, progress: engine.clamp(Number(data.progress) || 0),
                updated: performance.now(), pulse: session.pulse + 1 };
            else if (action === 'skill:trace' && session.config.type === 'trace') session = { ...session,
                progress: engine.clamp(Number(data.progress) || 0), invalid: data.invalid === true };
            else if (action === 'skill:close') {
                // Screen checks keep a brief outcome tag; the world mash disc leaves at once.
                if (!session.ready || session.config.type === 'mash') session = null;
                else {
                    const closed = session.session;
                    session = { ...session, outcome: { success: data.success === true, reason: typeof data.reason === 'string' ? data.reason : 'interrupted' } };
                    outcomeTimer = setTimeout(() => {
                        if (session && session.session === closed) { session = null; notify(); }
                    }, OUTCOME_MS);
                }
            } else return;
            notify();
        }
    });

    function useSession() {
        const [value, setValue] = useState(session);
        useEffect(() => { listeners.add(setValue); setValue(session); return () => listeners.delete(setValue); }, []);
        return value;
    }

    const keyText = key => key === 'SPACE' ? 'SPACE' : String(key || '');
    const OUTCOME_WORDS = { success: 'Clear', missed: 'Missed', timeout: 'Out of time', cancelled: 'Cancelled' };
    const outcomeWord = outcome => outcome.success ? OUTCOME_WORDS.success : OUTCOME_WORDS[outcome.reason] || 'Interrupted';
    const outcomeTone = outcome => outcome.success ? 'success' : ['missed', 'timeout'].includes(outcome.reason) ? 'failed' : 'quiet';

    /** Clock bar under the title, written straight to the DOM each frame (no React re-render). */
    function Clock({ value }) {
        const fill = useRef(null);
        useEffect(() => {
            const node = fill.current;
            if (!node) return undefined;
            if (!value.ready || value.outcome) return undefined;
            let frame = 0;
            const draw = now => {
                const left = engine.clamp(1 - (now - value.startedAt) / value.config.duration);
                node.style.transform = `scaleX(${left})`;
                node.dataset.level = left < 0.15 ? 'critical' : left < 0.3 ? 'low' : 'ok';
                if (left > 0) frame = requestAnimationFrame(draw);
            };
            frame = requestAnimationFrame(draw);
            return () => cancelAnimationFrame(frame);
        }, [value.ready, value.startedAt, value.outcome]);
        return h('div', { className: 'skill-clock', 'aria-hidden': 'true' }, h('i', { ref: fill, 'data-level': 'ok' }));
    }

    /** Mouse keycap: the kit silhouette with no lit button (movement, not a click). */
    function MouseCap() {
        return h('kbd', { className: 'cx-key cx-key--md is-mouse skill-mousecap', 'aria-label': 'Mouse' },
            h(window.CortexKit.MouseGlyph, { button: 'MOUSE' }));
    }

    function OutcomeTag({ outcome, score }) {
        return h('div', { className: `skill-outcome is-${outcomeTone(outcome)}`, role: 'status' },
            h('span', { className: 'skill-tag cx-display' },
                h('span', { className: 'skill-tag-state' }, outcomeWord(outcome)),
                outcome.success && Number.isFinite(score) ? h('span', { className: 'skill-tag-value' }, score) : null));
    }

    /** The shared slip: title, clock, mechanic (with outcome overlay) and control hints. */
    function Slip({ value, meta, hint, score, children, surfaceRef, dialog }) {
        const { KeyHint } = kit();
        const config = value.config;
        return h('section', {
            className: `skill-slip skill-${config.type}${value.ready ? ' is-ready' : ''}${value.outcome ? ' has-outcome' : ''}`,
            ref: surfaceRef, tabIndex: dialog ? -1 : undefined, role: dialog ? 'dialog' : 'group', 'aria-label': config.label
        },
            h('header', { className: 'skill-head' },
                h('h1', { className: 'skill-title cx-display' }, config.label),
                meta ? h('span', { className: 'skill-meta cx-display' }, meta) : null),
            h(Clock, { value }),
            h('div', { className: 'skill-mechanic' }, children,
                value.outcome ? h(OutcomeTag, { outcome: value.outcome, score }) : null),
            h('footer', { className: 'skill-hints' }, hint,
                h('span', { className: 'skill-hint-cancel' }, h(KeyHint, { keys: 'ESC', label: 'Cancel', size: 'sm' }))));
    }

    // ------------------------------------------------------------------ radial
    function Dial({ config, state, down, missed }) {
        const { Keycap } = kit();
        const point = (v, r) => [80 + r * Math.sin(v * Math.PI * 2), 80 - r * Math.cos(v * Math.PI * 2)];
        const arc = (from, to, r) => {
            const [x1, y1] = point(from, r), [x2, y2] = point(to, r);
            return `M ${x1} ${y1} A ${r} ${r} 0 ${to - from > 0.5 ? 1 : 0} 1 ${x2} ${y2}`;
        };
        return h('div', { className: 'skill-dial' },
            h('svg', { viewBox: '0 0 160 160', 'aria-hidden': 'true', focusable: 'false' },
                h('circle', { cx: 80, cy: 80, r: 60, className: 'skill-ring' }),
                h('path', { d: arc(config.targetStart, config.targetStart + config.targetSize, 60), className: 'skill-target-arc' }),
                h('g', { transform: `rotate(${state.progress * 360} 80 80)`, className: missed ? 'is-miss' : '' },
                    h('rect', { x: 75, y: 6, width: 10, height: 32, rx: 3, className: 'skill-marker' }))),
            h('span', { className: 'skill-dial-key' }, h(Keycap, { value: keyText(config.key), size: 'lg', pressed: down })));
    }

    // -------------------------------------------------------------------- hold
    function HoldBar({ config, state, missed }) {
        const { Keycap } = kit();
        return h('div', { className: 'skill-hold-row' },
            h(Keycap, { value: keyText(config.key), size: 'lg', pressed: state.held }),
            h('div', { className: 'skill-sweep' },
                h('span', { className: 'skill-zone', style: { left: `${config.targetStart * 100}%`, width: `${config.targetSize * 100}%` } }),
                h('span', { className: 'skill-sweep-fill', style: { transform: `scaleX(${state.progress})` } }),
                h('span', { className: `skill-cursor${missed ? ' is-miss' : ''}`, style: { left: `${state.progress * 100}%` } })));
    }

    // ---------------------------------------------------------------- sequence
    function SequenceKeys({ config, state, down, missed }) {
        const { Keycap } = kit();
        return h('div', { className: 'skill-keys' }, config.keys.map((key, i) => {
            const status = i < state.index ? 'is-done' : i === state.index ? (missed ? 'is-miss' : 'is-current') : 'is-later';
            return h('span', { key: i, className: `skill-keyslot ${status}` },
                h(Keycap, { value: keyText(key), size: 'lg', tone: i < state.index ? 'ink' : 'paper', pressed: i === state.index && down === key }));
        }));
    }

    /** Keyboard checks: the deterministic engine, driven by keydown/keyup with exact timing. */
    function ActiveCheck({ value }) {
        const { KeyHint } = kit();
        const config = value.config;
        const stateRef = useRef(engine.create(config, performance.now()));
        const [state, setState] = useState({ ...stateRef.current });
        const [down, setDown] = useState(null);
        const surface = useRef(null);
        const finished = useRef(false);
        useEffect(() => {
            if (!value.ready) return undefined;
            const current = engine.create(config, performance.now());
            stateRef.current = current;
            let frame, alive = true;
            function update() {
                if (!alive) return;
                setState({ ...current });
                if (current.result && !finished.current) {
                    finished.current = true;
                    post('skillResult', { session: value.session, success: current.result.success, reason: current.result.reason });
                }
            }
            function animate(now) {
                engine.tick(current, now); update();
                if (!current.result) frame = requestAnimationFrame(animate);
            }
            function keyboard(event, isDown) {
                const key = event.key === ' ' ? 'SPACE' : event.key.toUpperCase();
                if (['SHIFT', 'CONTROL', 'ALT', 'META', 'TAB'].includes(key)) return;
                event.preventDefault(); event.stopImmediatePropagation();
                if (!current.result && !event.repeat) setDown(isDown ? key : null);
                engine.input(current, key, isDown, performance.now(), event.repeat); update();
            }
            const keydown = event => keyboard(event, true), keyup = event => keyboard(event, false);
            const blur = () => { if (!current.result) { current.result = { success: false, reason: 'interrupted' }; update(); } };
            const hidden = () => { if (document.hidden) blur(); };
            window.addEventListener('keydown', keydown, true);
            window.addEventListener('keyup', keyup, true);
            window.addEventListener('blur', blur);
            document.addEventListener('visibilitychange', hidden);
            frame = requestAnimationFrame(animate);
            surface.current?.focus({ preventScroll: true });
            return () => {
                alive = false; cancelAnimationFrame(frame);
                window.removeEventListener('keydown', keydown, true); window.removeEventListener('keyup', keyup, true);
                window.removeEventListener('blur', blur); document.removeEventListener('visibilitychange', hidden);
            };
        }, [value.ready, value.session]);
        const missed = value.outcome ? !value.outcome.success : state.result ? !state.result.success : false;
        const key = keyText(config.key);
        const hint = config.type === 'hold' ? h(KeyHint, { keys: key, label: 'Hold, release in the zone', size: 'sm' })
            : config.type === 'sequence' ? h(KeyHint, { keys: keyText(config.keys[Math.min(state.index, config.keys.length - 1)]), label: 'Type in order', size: 'sm' })
                : h(KeyHint, { keys: key, label: 'Stop in the zone', size: 'sm' });
        const mechanic = config.type === 'sequence' ? h(SequenceKeys, { config, state, down, missed })
            : config.type === 'hold' ? h(HoldBar, { config, state, missed })
                : h(Dial, { config, state, down: down === config.key, missed });
        return h(Slip, {
            value, hint, score: state.score, surfaceRef: surface, dialog: true,
            meta: config.type === 'sequence' ? `${Math.min(state.index, config.keys.length)}/${config.keys.length}` : null
        }, mechanic);
    }

    // ------------------------------------------------------------------- trace
    /** Half ring 3 -> 9 o'clock; the mint knob is the player's live position on it. */
    function TraceArc({ value }) {
        const upper = value.config.direction === 'upper';
        const cy = upper ? 96 : 20, r = 72, sweep = upper ? 0 : 1;
        const track = `M ${100 + r} ${cy} A ${r} ${r} 0 0 ${sweep} ${100 - r} ${cy}`;
        const angle = value.progress * Math.PI;
        const knobX = 100 + r * Math.cos(angle), knobY = cy + (upper ? -1 : 1) * r * Math.sin(angle);
        // Direction chevron beside the start (3 o'clock), pointing along the sweep.
        const arrow = upper ? 'M 184 88 L 191 76 L 198 88 Z' : 'M 184 28 L 191 40 L 198 28 Z';
        return h('div', {
            className: `skill-arc${value.invalid ? ' is-invalid' : ''}`, role: 'progressbar',
            'aria-label': upper ? 'Mouse sweep: right, up, left' : 'Mouse sweep: right, down, left',
            'aria-valuemin': 0, 'aria-valuemax': 100, 'aria-valuenow': Math.round(value.progress * 100)
        },
            h('svg', { viewBox: '0 0 200 116', 'aria-hidden': 'true', focusable: 'false' },
                h('path', { d: track, className: 'skill-arc-track' }),
                h('path', { d: track, className: 'skill-arc-fill', pathLength: 1, strokeDasharray: `${value.progress} 1` }),
                h('rect', { x: 100 - r - 13, y: cy - 3, width: 26, height: 6, rx: 2, className: 'skill-arc-goal' }),
                h('path', { d: arrow, className: 'skill-arc-arrow' }),
                h('circle', { cx: knobX, cy: knobY, r: 11, className: 'skill-arc-knob' })),
            h('span', { className: `skill-arc-cap ${upper ? 'is-upper' : 'is-lower'}` }, h(MouseCap)));
    }

    function TraceCheck({ value }) {
        const hint = h('span', { className: 'cx-hint skill-hint-mouse' }, h(MouseCap),
            h('span', { className: 'cx-hint-label' }, value.config.direction === 'upper' ? 'Sweep up and over' : 'Sweep down and under'));
        return h(Slip, { value, hint }, h(TraceArc, { value }));
    }

    function Surface() {
        const value = useSession();
        if (!value || value.config.type === 'mash') return null;
        if (value.config.type === 'trace') return h(TraceCheck, { key: value.session, value });
        return h(ActiveCheck, { key: value.session, value });
    }

    // -------------------------------------------------------------------- mash
    /** World disc: the interaction keycap inside a thick mint ring that fills against decay. */
    function MashDial({ value, item }) {
        const { Keycap, Ring } = kit();
        const [progress, setProgress] = useState(value.progress);
        const [pressed, setPressed] = useState(false);
        useEffect(() => {
            let frame;
            const tick = now => {
                const next = Math.max(0, value.progress - (now - value.updated) / 1000 * value.config.decay);
                setProgress(next);
                if (next > 0) frame = requestAnimationFrame(tick);
            };
            tick(performance.now());
            return () => cancelAnimationFrame(frame);
        }, [value]);
        useEffect(() => {
            if (!value.pulse) return undefined;
            setPressed(true);
            const timer = setTimeout(() => setPressed(false), 90);
            return () => clearTimeout(timer);
        }, [value.pulse]);
        return h('div', { className: 'skill-mash', role: 'progressbar', 'aria-label': `Tap ${item.key} to ${item.label}`,
            'aria-valuemin': 0, 'aria-valuemax': 100, 'aria-valuenow': Math.round(progress * 100) },
            h(Ring, { value: progress, tone: 'accent', stroke: 14, className: 'skill-mash-ring' },
                h(Keycap, { value: keyText(item.key), size: 'lg', pressed })),
            h('span', { className: 'skill-mash-hint cx-display' }, 'Tap'));
    }
    function WorldKey({ item, fallback }) {
        const value = useSession();
        return value && value.config.type === 'mash' && value.owner === item.owner && value.config.interactionId === item.id
            ? h(MashDial, { value, item }) : fallback;
    }
    window.CortexSkillChecks = { Surface, WorldKey };
})();
