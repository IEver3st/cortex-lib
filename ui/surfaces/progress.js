/* Progress: a timed or controlled bar and ring. Frameless over the scene.
 * Bar: display-caps label left, tabular percent right, 8u meter below.
 * Ring: 96u, stroke 12 of 100, percent inside, label under.
 * States: running, controlled, complete (fill pulses to paper, then leaves),
 * cancelled (sand, then leaves), non-cancelable (no hint), reduced motion. */

function normalizeProgressData(data) {
    if (!isRecord(data)) return null;
    const rawDuration = Number(data.duration);
    const position = data.position === 'center' ? 'middle' : data.position;
    return {
        duration: Number.isFinite(rawDuration) ? Math.max(0, Math.min(rawDuration, 600000)) : 0,
        label: boundedText(data.label, '', 256),
        position: ['top', 'middle', 'bottom'].includes(position) ? position : 'bottom',
        style: data.style === 'circle' ? 'circle' : 'bar',
        canCancel: data.canCancel === true
    };
}

/** `progressEnd` may say how the action ended; older senders say nothing. */
function normalizeProgressOutcome(data) {
    if (!isRecord(data)) return null;
    if (data.completed === true) return 'complete';
    if (data.completed === false) return 'cancel';
    return null;
}

// How long each outcome stays readable before the surface leaves.
const PROGRESS_OUTCOME_HOLD_MS = { complete: 480, cancel: 900 };
// A timed bar that ends within this window of its duration counts as complete.
const PROGRESS_COMPLETE_TOLERANCE_MS = 150;
const PROGRESS_RING_STROKE = 12;
const PROGRESS_RING_RADIUS = 50 - PROGRESS_RING_STROKE / 2;

function resolveProgressOutcome(explicit, controlled, value, elapsed, duration) {
    if (explicit === 'complete' || explicit === 'cancel') return explicit;
    if (controlled) return value >= 100 ? 'complete' : 'cancel';
    if (!duration || duration <= 0) return 'complete';
    return elapsed >= duration - PROGRESS_COMPLETE_TOLERANCE_MS ? 'complete' : 'cancel';
}

/** Hint text with `[KEY]` tokens as keycaps (e.g. a consumer-supplied hint). */
function ProgressHintText({ text }) {
    const kit = window.CortexKit;
    return kit.parseKeyText(text).map((part, index) => part.type === 'key'
        ? React.createElement(kit.Keycap, { key: index, value: part.value, size: 'sm' })
        : React.createElement('span', { key: index, className: 'cx-hint-label' }, part.value.trim()));
}

// ============================================================================
// PROGRESS COMPONENT
// ============================================================================

function ProgressBar({ active, duration, label, position, style, canCancel, value, id = 'progress', hint, outcome = null, token }) {
    const kit = window.CortexKit;
    const prefs = kit.usePrefs();
    const [percent, setPercent] = useState(0);
    const [phase, setPhase] = useState('idle');
    const controlled = Number.isFinite(value);
    const fillRef = useRef(null);
    const ringRef = useRef(null);
    const rafRef = useRef(0);
    const holdRef = useRef(null);
    const startRef = useRef(0);
    const runningRef = useRef(false);
    const lastRef = useRef({ controlled: false, value: 0, duration: 0 });
    const outcomeRef = useRef(outcome);
    outcomeRef.current = outcome;
    lastRef.current = active ? { controlled, value: Number(value) || 0, duration: Number(duration) || 0 } : lastRef.current;

    useEffect(() => {
        if (rafRef.current) {
            cancelAnimationFrame(rafRef.current);
            rafRef.current = 0;
        }

        if (!active) {
            if (!runningRef.current) return undefined;
            runningRef.current = false;
            const last = lastRef.current;
            const elapsed = performance.now() - startRef.current;
            const result = resolveProgressOutcome(outcomeRef.current, last.controlled, last.value, elapsed, last.duration);
            if (result === 'complete') {
                if (fillRef.current) fillRef.current.style.setProperty('--cx-fill', '1');
                if (ringRef.current) ringRef.current.setAttribute('stroke-dasharray', '100 100');
                setPercent(100);
            }
            setPhase(result);
            holdRef.current = setTimeout(() => {
                holdRef.current = null;
                setPhase('idle');
            }, PROGRESS_OUTCOME_HOLD_MS[result]);
            return undefined;
        }

        if (holdRef.current) {
            clearTimeout(holdRef.current);
            holdRef.current = null;
        }
        runningRef.current = true;
        startRef.current = performance.now();
        setPhase('running');
        if (controlled) return undefined;

        if (!duration || duration <= 0) {
            setPercent(100);
            return undefined;
        }

        setPercent(0);
        let shown = 0;
        // The fill is written straight to the DOM every frame (transform and
        // stroke only); React re-renders only when the whole percent changes.
        const step = (now) => {
            const fraction = Math.min(1, Math.max(0, (now - startRef.current) / duration));
            if (fillRef.current) fillRef.current.style.setProperty('--cx-fill', fraction.toFixed(4));
            if (ringRef.current) ringRef.current.setAttribute('stroke-dasharray', `${(fraction * 100).toFixed(2)} 100`);
            const whole = Math.floor(fraction * 100);
            if (whole !== shown) {
                shown = whole;
                setPercent(whole);
            }
            rafRef.current = fraction < 1 ? requestAnimationFrame(step) : 0;
        };
        rafRef.current = requestAnimationFrame(step);

        return () => {
            if (rafRef.current) {
                cancelAnimationFrame(rafRef.current);
                rafRef.current = 0;
            }
        };
    }, [active, duration, controlled, token]);

    useEffect(() => () => {
        if (holdRef.current) clearTimeout(holdRef.current);
        if (rafRef.current) cancelAnimationFrame(rafRef.current);
    }, []);

    const shownPhase = active ? 'running' : phase;
    const visible = Boolean(active) || phase === 'complete' || phase === 'cancel';
    const circle = style === 'circle';
    const pct = Math.max(0, Math.min(100, controlled ? value : (shownPhase === 'complete' ? 100 : percent)));
    const fraction = pct / 100;
    const cancelled = shownPhase === 'cancel';
    const showPercent = prefs.showPercent !== false;
    const readout = cancelled ? 'Cancelled' : (showPercent ? `${Math.round(pct)}%` : '');
    const tone = cancelled ? 'warning' : 'accent';

    const containerClass = ['progress-container', position || 'bottom', visible ? 'active' : '',
        `is-${shownPhase}`].filter(Boolean).join(' ');

    let hintNode = null;
    if (shownPhase === 'running' && (hint || canCancel)) {
        hintNode = React.createElement('div', {
            id: `${id}-cancel`,
            className: `progress-cancel cx-legend${hint ? ' is-always' : ''}`,
            'aria-label': hint || 'Backspace to cancel'
        }, hint
            ? React.createElement('span', { className: 'cx-hint' }, React.createElement(ProgressHintText, { text: hint }))
            : React.createElement(kit.KeyHint, { keys: 'BACKSPACE', label: 'Cancel', size: 'sm' }));
    }

    const labelNode = React.createElement('div', {
        id: `${id}-label`, className: 'progress-label', role: 'status', 'aria-live': 'polite'
    }, label || '');

    const barBody = !circle && React.createElement(React.Fragment, null,
        React.createElement('div', { className: 'progress-head' },
            labelNode,
            readout && React.createElement('div', { className: 'progress-value', 'aria-hidden': 'true' }, readout)
        ),
        React.createElement('span', { className: `cx-meter cx-meter--lg cx-tone--${tone} progress-meter`, 'aria-hidden': 'true' },
            React.createElement('i', {
                id: `${id}-bar`,
                ref: fillRef,
                className: 'cx-meter-fill progress-fill',
                style: { '--cx-fill': fraction }
            }))
    );

    const common = { cx: 50, cy: 50, r: PROGRESS_RING_RADIUS, pathLength: 100, strokeWidth: PROGRESS_RING_STROKE, fill: 'none' };
    const circleBody = circle && React.createElement(React.Fragment, null,
        React.createElement('span', { className: `cx-ring cx-tone--${tone} progress-ring`, 'aria-hidden': 'true' },
            React.createElement('svg', { viewBox: '0 0 100 100', focusable: 'false', style: { transform: 'rotate(-90deg)' } },
                React.createElement('circle', { ...common, className: 'cx-ring-track' }),
                React.createElement('circle', {
                    ...common,
                    ref: ringRef,
                    id: `${id}-ring`,
                    className: 'cx-ring-fill progress-ring-fill',
                    strokeDasharray: `${fraction * 100} 100`
                }),
                React.createElement('circle', { ...common, className: 'progress-ring-flash' })
            ),
            React.createElement('span', { className: 'cx-ring-center' },
                React.createElement('span', { className: `progress-circle-text${cancelled ? ' is-word' : ''}` }, readout))
        ),
        labelNode
    );

    return React.createElement('div', { id: `${id}-container`, className: containerClass, 'aria-hidden': !visible },
        React.createElement('div', {
            className: `progress-wrapper ${circle ? 'is-circle' : 'is-bar'}${canCancel ? ' is-cancelable' : ''}`,
            'data-cortex-surface': 'instrument',
            role: 'progressbar',
            'aria-label': label || 'Progress',
            'aria-valuemin': 0,
            'aria-valuemax': 100,
            'aria-valuenow': Math.round(pct),
            'aria-valuetext': cancelled ? 'Cancelled' : `${Math.round(pct)}%`
        },
            barBody,
            circleBody,
            hintNode
        )
    );
}
