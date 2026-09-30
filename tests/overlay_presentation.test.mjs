import { uiSource, uiStyles } from './ui_source.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = uiSource;
const css = uiStyles;

// Execute the production component functions as element trees, without a browser
// or FiveM runtime. This verifies presentation contracts, not rendered geometry.
function component(name, states = [], extra = {}) {
    let index = 0;
    const context = vm.createContext({
        React: { createElement: (type, props, ...children) => ({ type, props: props || {}, children: children.flat(Infinity) }) },
        useState: initial => [index < states.length ? states[index++] : initial, () => {}],
        useRef: current => ({ current }),
        useEffect: () => {},
        useCallback: fn => fn,
        useModalFocus: () => {},
        ...extra,
    });
    const match = source.match(new RegExp(`function ${name}\\([\\s\\S]*?\\n}`));
    assert.ok(match, `${name} must be available`);
    vm.runInContext(match[0], context);
    return context[name];
}

function elements(tree) {
    if (!tree || typeof tree !== 'object') return [];
    return [tree, ...(tree.children || []).flatMap(elements)];
}
const byClass = (tree, name) => elements(tree).find(node => (node.props.className || '').split(' ').includes(name));
const text = tree => typeof tree === 'string' || typeof tree === 'number'
    ? String(tree) : (tree?.children || []).map(text).join('');

// Loads the real shared kit (keycap parsing, key normalisation) with a mock React.
function loadKit() {
    const root = {};
    const context = vm.createContext({
        React: { createElement: (type, props, ...children) => ({ type, props: props || {}, children: children.flat(Infinity) }),
            useState: v => [v, () => {}], useEffect: () => {}, useRef: current => ({ current }), useCallback: fn => fn,
            useSyncExternalStore: (_, get) => get() },
        ReactDOM: {},
        window: root,
        document: { documentElement: { style: { setProperty() {} }, dataset: {} } }
    });
    vm.runInContext(readFileSync(new URL('../ui/core/kit.js', import.meta.url), 'utf8'), context);
    return root.CortexKit;
}
const realKit = loadKit();

// Runs one production surface file (notify / progress / text) in a mock
// runtime and returns a getter for its declarations. Hook state is scripted:
// successive useState calls receive `states` in order.
function surface(file, { states = [], prefs = {}, extra = {} } = {}) {
    let index = 0;
    const context = vm.createContext({
        React: { createElement: (type, props, ...children) => ({ type, props: props || {}, children: children.flat(Infinity) }), Fragment: 'fragment' },
        useState: initial => [index < states.length ? states[index++] : initial, () => {}],
        useRef: current => ({ current }),
        useEffect: () => {},
        useCallback: fn => fn,
        isRecord: value => value !== null && typeof value === 'object' && !Array.isArray(value),
        boundedText: (value, fallback = '', max = 4096) => typeof value === 'string' ? value.slice(0, max)
            : (typeof value === 'number' || typeof value === 'boolean') ? String(value).slice(0, max) : fallback,
        normalizeIconColor: value => {
            const color = typeof value === 'string' ? value.trim().slice(0, 64) : '';
            return /^(?:var\(--[a-z0-9-]+\)|#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8}))$/i.test(color) ? color : null;
        },
        safeJson: value => JSON.stringify(value),
        NUI_MAX_NOTIFICATIONS: 12,
        NUI_MAX_HELP_ITEMS: 16,
        window: {
            CortexKit: { ...realKit, usePrefs: () => ({ ...realKit.DEFAULT_PREFS, ...prefs }) },
            addEventListener() {}, innerWidth: 1920, innerHeight: 1080
        },
        document: { documentElement: { style: { setProperty() {} } } },
        performance: { now: () => 0 },
        requestAnimationFrame: () => 0,
        cancelAnimationFrame() {},
        setTimeout: () => 0,
        clearTimeout() {},
        ResizeObserver: undefined,
        ...extra
    });
    vm.runInContext(readFileSync(new URL(`../ui/surfaces/${file}`, import.meta.url), 'utf8'), context);
    return name => vm.runInContext(name, context);
}
const byType = (tree, type) => elements(tree).filter(node => node.type === type);

test('bar and circle expose the same bounded progress and retain cancellation semantics', () => {
    for (const style of ['bar', 'circle']) {
        for (const canCancel of [false, true]) {
            const get = surface('progress.js', { states: [42, 'idle'] });
            const ProgressBar = get('ProgressBar');
            const label = 'Installing replacement equipment with a long operation label';
            const tree = ProgressBar({ active: true, duration: 5000, label, style, canCancel });
            const meter = elements(tree).find(node => node.props.role === 'progressbar');
            assert.equal(meter.props['aria-label'], label);
            assert.equal(meter.props['data-cortex-surface'], 'instrument');
            assert.equal(meter.props['aria-valuenow'], 42);
            assert.match(tree.props.className, /\bactive\b/);
            assert.equal(text(byClass(tree, 'progress-label')), label);
            assert.equal(text(byClass(tree, style === 'bar' ? 'progress-value' : 'progress-circle-text')), '42%');
            if (style === 'bar') {
                assert.ok(byClass(tree, 'cx-meter--lg'), 'the bar meter uses the 8u kit meter');
                assert.equal(byClass(tree, 'progress-fill').props.style['--cx-fill'], 0.42);
            } else {
                const ring = elements(tree).filter(node => node.type === 'circle');
                assert.ok(ring.length >= 2 && ring.every(node => node.props.strokeWidth === 12), 'ring stroke is 12 of 100');
                assert.equal(byClass(tree, 'progress-ring-fill').props.strokeDasharray, '42 100');
            }
            const cancel = byClass(tree, 'progress-cancel');
            assert.equal(Boolean(cancel), canCancel, 'a non-cancelable action shows no cancel hint');
            if (canCancel) {
                assert.equal(cancel.props['aria-label'], 'Backspace to cancel');
                const hint = byType(cancel, get('window').CortexKit.KeyHint)[0];
                assert.equal(hint.props.keys, 'BACKSPACE');
                assert.equal(hint.props.label, 'Cancel');
            }
            assert.equal(elements(tree).filter(node => node.type === 'button').length, 0,
                'a passive progress overlay must not introduce clickable gameplay actions');
        }
    }
});

test('progress honours the percent preference and shows complete and cancelled outcomes', () => {
    for (const style of ['bar', 'circle']) {
        const hidden = surface('progress.js', { states: [30, 'idle'], prefs: { showPercent: false } })('ProgressBar')({ active: true, duration: 5000, label: 'Search', style });
        assert.equal(byClass(hidden, 'progress-value'), undefined);
        if (style === 'circle') assert.equal(text(byClass(hidden, 'progress-circle-text')), '');
        assert.equal(elements(hidden).find(node => node.props.role === 'progressbar').props['aria-valuenow'], 30,
            'hiding the readout keeps the accessible value');

        const cancelled = surface('progress.js', { states: [45, 'cancel'] })('ProgressBar')({ active: false, duration: 4000, label: 'Repair', style, canCancel: true });
        assert.match(cancelled.props.className, /\bactive\b.*\bis-cancel\b/, 'a cancelled action stays readable before leaving');
        assert.ok(elements(cancelled).some(node => /cx-tone--warning/.test(node.props.className || '')), 'cancelled turns sand');
        assert.equal(text(byClass(cancelled, style === 'bar' ? 'progress-value' : 'progress-circle-text')), 'Cancelled');
        assert.equal(byClass(cancelled, 'progress-cancel'), undefined, 'no cancel hint after the action ended');

        const complete = surface('progress.js', { states: [97, 'complete'] })('ProgressBar')({ active: false, duration: 4000, label: 'Done', style });
        assert.match(complete.props.className, /\bis-complete\b/);
        assert.equal(elements(complete).find(node => node.props.role === 'progressbar').props['aria-valuenow'], 100);

        const idle = surface('progress.js', { states: [0, 'idle'] })('ProgressBar')({ active: false, duration: 4000, label: 'Gone', style });
        assert.doesNotMatch(idle.props.className, /\bactive\b/);
        assert.equal(idle.props['aria-hidden'], true);
    }
});

test('progress outcomes come from Lua when known and are inferred otherwise', () => {
    const get = surface('progress.js');
    const outcome = get('normalizeProgressOutcome');
    assert.equal(outcome({ completed: true }), 'complete');
    assert.equal(outcome({ completed: false }), 'cancel');
    assert.equal(outcome({}), null);
    assert.equal(outcome({ completed: 'yes' }), null);
    assert.equal(outcome(null), null);
    const resolve = get('resolveProgressOutcome');
    assert.equal(resolve('cancel', false, 0, 5000, 5000), 'cancel', 'an explicit Lua outcome wins');
    assert.equal(resolve(null, true, 100, 0, 0), 'complete');
    assert.equal(resolve(null, true, 40, 0, 0), 'cancel');
    assert.equal(resolve(null, false, 0, 4900, 5000), 'complete', 'timer jitter at the end still completes');
    assert.equal(resolve(null, false, 0, 2000, 5000), 'cancel');
});

// Radial hook state order: hoverIndex, page, mounted, pressed, fired, pageMotion.
function radialTree(props, { hover = -1, page = 1, pressed = null } = {}) {
    const get = surface('radial.js', {
        states: [hover, page, true, pressed, -1, 0],
        extra: { NUI_MAX_MENU_OPTIONS: 128, nuiPost: () => Promise.resolve({ ok: true }), useModalFocus: () => {} }
    });
    const items = get('normalizeRadialItems')(props.items || []);
    return { tree: get('RadialMenu')({ open: true, visible: true, session: 1, view: 1, ...props, items }), Kit: get('window').CortexKit };
}
const legendOf = (tree, Kit) => byType(tree, Kit.ControlsLegend)[0]?.props.items || [];

test('radial hub names the aimed action in full and the idle hub names the centre action', () => {
    const label = 'Open the complete vehicle equipment configuration';
    const items = [{ id: 'equipment', label, icon: 'car', description: 'Doors, engine and seats.' }, { id: 'b', label: 'Keys' }];
    for (const canGoBack of [false, true]) {
        const { tree, Kit } = radialTree({ items, canGoBack }, { hover: 0 });
        assert.equal(text(byClass(tree, 'cortex-radial-hub-label')), label, 'the hub shows the full label');
        assert.equal(text(byClass(tree, 'cortex-radial-hub-desc')), 'Doors, engine and seats.');
        assert.ok(byClass(elements(tree).find(node => node.props.id === 'cortex-radial-item-0'), 'is-hover'),
            'the aimed slip carries the hover (paper) state');
        assert.equal(elements(tree).find(node => node.props.role === 'menuitem').props['aria-label'], label);
        assert.equal(legendOf(tree, Kit).find(item => item.keys === 'RMB').label, canGoBack ? 'Back' : 'Close');
        assert.equal(Boolean(legendOf(tree, Kit).find(item => item.keys === 'ESC')), canGoBack, 'Esc is listed separately only in a submenu');

        const idle = radialTree({ items, canGoBack, trail: canGoBack ? ['Vehicle'] : [] }).tree;
        assert.equal(text(byClass(idle, 'cortex-radial-hub-action')).trim(), canGoBack ? 'Back' : 'Close');
        assert.equal(text(byClass(idle, 'cortex-radial-hub-title')), canGoBack ? 'Vehicle' : '', 'a submenu names itself from the breadcrumb');
    }
    const empty = radialTree({ items: [] });
    assert.equal(text(byClass(empty.tree, 'cortex-radial-hub-title')), 'No actions');
    assert.deepEqual([...legendOf(empty.tree, empty.Kit).map(item => item.keys)], ['RMB'], 'an empty wheel only offers close');

    const compact = radialTree({ items, appearance: 'compact-control' }, { hover: 0 });
    assert.equal(byType(compact.tree, compact.Kit.ControlsLegend).length, 0, 'compact-control carries no legend');
    assert.equal(byClass(compact.tree, 'cortex-radial-hub-desc'), undefined);
    assert.ok(byClass(compact.tree, 'is-compact'));
});

test('radial pages render as dots with ghost slots, and disabled actions cannot be confirmed', () => {
    const items = Array.from({ length: 18 }, (_, i) => ({ id: `i${i}`, label: `Action ${i + 1}` }));
    const { tree, Kit } = radialTree({ items }, { page: 3 });
    const slips = elements(tree).filter(node => (node.props.className || '').split(' ').includes('cortex-radial-slip'));
    assert.equal(slips.length, 8, 'a paged wheel keeps eight slots so directions do not move');
    assert.equal(slips.filter(node => node.props.className.includes('is-ghost')).length, 6);
    assert.deepEqual(elements(tree).filter(node => node.props.role === 'menuitem').map(node => node.props.id),
        ['cortex-radial-item-16', 'cortex-radial-item-17'], 'ids use source indices across pages');
    const dots = elements(tree).filter(node => /cortex-radial-dot\b/.test(node.props.className || ''));
    assert.equal(dots.length, 3);
    assert.ok(dots[2].props.className.includes('is-current'));
    assert.equal(text(tree).includes('More'), false, 'no fake More slip');
    assert.ok(legendOf(tree, Kit).some(item => item.keys === 'WHEEL'));

    const disabled = radialTree({ items: [{ id: 'a', label: 'Open', disabled: true, description: 'Hands full.' }, { id: 'b', label: 'Keys' }] }, { hover: 0 });
    assert.ok(byClass(disabled.tree, 'is-disabled'));
    assert.equal(elements(disabled.tree).find(node => node.props.id === 'cortex-radial-item-0').props['aria-disabled'], true);
    assert.equal(legendOf(disabled.tree, disabled.Kit).find(item => item.keys === 'LMB').disabled, true, 'Select dims on a disabled action');
    assert.equal(text(byClass(disabled.tree, 'cortex-radial-hub-desc')), 'Hands full.');
});

test('radial normalizers bound items, breadcrumbs and focus', () => {
    const get = surface('radial.js', { extra: { NUI_MAX_MENU_OPTIONS: 128 } });
    const items = get('normalizeRadialItems')([{ id: 'a', label: 'A', description: 'x'.repeat(400), disabled: 'yes', menu: 'sub', icon: 'car' }, null, 7]);
    assert.equal(items.length, 1);
    assert.equal(items[0].description.length, 256);
    assert.equal(items[0].disabled, false, 'only a literal true disables');
    assert.equal(items[0].hasMenu, true);
    assert.equal(get('normalizeRadialItems')(Array.from({ length: 300 }, (_, i) => ({ id: `${i}`, label: 'x' }))).length, 128);
    assert.deepEqual([...get('normalizeRadialTrail')(['A', '', 5, { x: 1 }, 'B'.repeat(80)])], ['A', '5', 'B'.repeat(64)]);
    assert.equal(get('normalizeRadialTrail')(Array.from({ length: 20 }, (_, i) => `${i}`)).length, 8);
    for (const bad of [-1, 1.5, '2', 128, null, undefined]) assert.equal(get('normalizeRadialFocusIndex')(bad), null);
    assert.equal(get('normalizeRadialFocusIndex')(3), 3);
});

test('overlay source keeps passive input, transparent roots and CEF-safe surfaces', () => {
    assert.doesNotMatch(css, /(?:-webkit-)?backdrop-filter\s*:\s*(?!none)[^;]+;/);
    assert.doesNotMatch(css, /(?:linear|radial|conic)-gradient\(/);
    for (const selector of ['html', '#root', 'body']) {
        const blocks = [...css.matchAll(new RegExp(`(?:^|\\n)(?:[^{}\\n]*,\\s*)?${selector}(?:\\s*,[^{}]*)?\\s*{([^}]+)}`, 'g'))];
        assert.ok(blocks.some(block => /background:\s*transparent/.test(block[1])), `${selector} must stay transparent`);
    }
    assert.match(css, /\.cortex-radial-overlay\s*{[^}]*pointer-events:\s*none/);
    assert.match(css, /\.cortex-radial-overlay\.visible\s*{[^}]*pointer-events:\s*auto/);
});

test('gameplay meters have no enclosing background in either appearance mode', () => {
    const wrapper = css.match(/\.progress-wrapper\s*\{([^}]+)}/)[1];
    assert.match(wrapper, /background:\s*transparent/);
    assert.match(wrapper, /border:\s*0/);
    assert.match(wrapper, /padding:\s*0/);
    const shared = readFileSync(new URL('../ui/dynamic-ui.css', import.meta.url), 'utf8');
    const roles = shared.slice(shared.indexOf('.cortex-shared-style :is([data-cortex-surface='));
    assert.match(roles, /instrument/); assert.match(roles, /cinematic/);
    assert.match(roles, /background:\s*transparent/);
});

test('notifications preserve message variants, urgency and truthful lifetime cues', () => {
    const get = surface('notify.js');
    const Notification = get('Notification');
    const NotifyText = get('NotifyText');
    for (const type of ['info', 'success', 'warning', 'error']) {
        for (const persistent of [false, true]) {
            const description = 'Equipment ready. ' + 'Long_resource_name_'.repeat(20);
            const tree = Notification({ id: 'notice', type, title: 'Equipment', description, duration: 5000, persistent });
            assert.equal(tree.props['data-cortex-surface'], 'instrument');
            assert.equal(tree.props.role, ['warning', 'error'].includes(type) ? 'alert' : 'status');
            assert.ok(byClass(tree, 'notify-rule'), 'the severity rule carries the type colour');
            assert.equal(byType(tree, NotifyText)[0].props.text, description);
            assert.equal(text(byClass(tree, 'notify-title')), 'Equipment');
            assert.equal(Boolean(byClass(tree, 'notify-close')), persistent);
            assert.equal(Boolean(byClass(tree, 'notify-duration')), !persistent);
            if (!persistent) assert.equal(byClass(tree, 'notify-duration-fill').props.style.animation, 'notifyLifetime 5000ms linear forwards');
        }
    }
    const plain = Notification({ id: 'plain', plain: true, hideIcon: true, description: 'Saved', duration: 5000, showDuration: false });
    assert.equal(byType(plain, NotifyText)[0].props.text, 'Saved');
    assert.match(plain.props.className, /notify-headline/, 'a short title-free line reads as the headline');
    assert.equal(byClass(plain, 'notify-icon'), undefined);
    assert.equal(byClass(plain, 'notify-title'), undefined);
    assert.equal(byClass(plain, 'notify-duration'), undefined);
    const keyed = NotifyText({ text: 'Press [E] to open' });
    assert.equal(keyed[0], 'Press ');
    assert.equal(keyed[1].props.value, 'E');
    assert.equal(NotifyText({ text: 'No keys here' }), 'No keys here');
    const notifyCss = readFileSync(new URL('../ui/surfaces/notify.css', import.meta.url), 'utf8');
    assert.match(notifyCss, /\.notify-rule\s*{[^}]*width:\s*calc\(4 \* var\(--u\)\)/, 'the severity rule is 4u');
    assert.match(notifyCss, /\.notify-duration\s*{[^}]*height:\s*calc\(4 \* var\(--u\)\)/, 'the lifetime cue is a 4u meter, not a hairline');
    assert.match(notifyCss, /\.notify\s*{[^}]*background:\s*transparent/, 'no card behind a notice');
    assert.match(css, /\.notify::before, \.notify::after\s*{\s*content:\s*none/);
    assert.match(css, /@keyframes notifyReveal\s*{\s*from\s*{\s*opacity:\s*0/);
    assert.doesNotMatch(notifyCss, /notify-grain\.svg/);
});

test('notifications apply the player limit and lifetime preferences', () => {
    const get = surface('notify.js', { prefs: { notifyLimit: 2, notifyDuration: 2 } });
    const partition = get('partitionNotifications');
    const list = [
        { id: 'p1', persistent: true }, { id: 't1', persistent: false },
        { id: 't2', persistent: false }, { id: 't3', persistent: false }
    ];
    const result = partition(list, 2);
    assert.deepEqual(result.visible.map(item => item.id), ['t2', 't3'], 'the newest notices stay visible');
    assert.equal(result.held, 1, 'persistent notices past the cap are held, not lost');
    assert.deepEqual([...result.dropped], ['t1'], 'timed notices past the cap leave');
    assert.equal(partition(list, 99).visible.length, 4, 'the cap is bounded by the queue');
    const scale = get('scaleNotificationLifetime');
    assert.equal(scale(5000, 2), 10000);
    assert.equal(scale(5000, 9), 15000, 'the multiplier is clamped to 3');
    assert.equal(scale(5000, 0.1), 2500, 'the multiplier is clamped to 0.5');
    assert.equal(scale(0, 2), 0, 'persistent stays persistent');

    const Container = get('NotificationContainer');
    const tree = Container({ notifications: list.map(item => ({ ...item, type: 'info', title: item.id, description: '', duration: 3000 })), position: 'top-right', onRemove() {} });
    const shown = byType(tree, get('Notification'));
    assert.deepEqual(shown.map(node => node.props.id), ['t2', 't3']);
    assert.ok(shown.every(node => node.props.duration === 6000), 'the lifetime multiplier reaches each notice');
    assert.equal(text(byClass(tree, 'notify-overflow')), '+1 held');
});

test('persistent notification dismissal is idempotent and cleans up on unmount', () => {
    const timers = new Map(), cleanups = [], removed = [];
    let next = 0;
    const Notification = surface('notify.js', { extra: {
        setTimeout: (fn, delay) => { timers.set(++next, { fn, delay }); return next; },
        clearTimeout: id => timers.delete(id),
        useEffect: effect => { const cleanup = effect(); if (cleanup) cleanups.push(cleanup); }
    } })('Notification');
    const tree = Notification({ id: 'persistent', persistent: true, duration: 5000, description: '', onRemove: id => removed.push(id) });
    assert.equal(timers.size, 0);
    const dismiss = byClass(tree, 'notify-close');
    assert.equal(dismiss.props.type, 'button');
    assert.equal(dismiss.props['aria-label'], 'Dismiss notification');
    dismiss.props.onClick({ stopPropagation() {} }); dismiss.props.onClick({ stopPropagation() {} });
    assert.equal(timers.size, 1);
    const exit = [...timers.values()][0];
    assert.equal(exit.delay, 160); exit.fn();
    assert.deepEqual(removed, ['persistent']);
    cleanups.forEach(cleanup => cleanup());
    assert.equal(timers.size, 0);
});

test('controlled Cortex progress displays completed work independently of timed samples', () => {
    const ProgressBar = surface('progress.js', { states: [88, 'idle'], extra: {
        useEffect: fn => fn(),
        requestAnimationFrame: () => assert.fail('controlled progress must not animate a fake timer'),
    } })('ProgressBar');
    const tree = ProgressBar({ active: true, value: 25, id: 'debug-test-all', position: 'middle',
        label: 'Test All · 1 / 4', hint: '/cortexdebug to stop' });
    assert.equal(tree.props.id, 'debug-test-all-container');
    assert.match(tree.props.className, /middle active/);
    assert.equal(elements(tree).find(n => n.props.role === 'progressbar').props['aria-valuenow'], 25);
    assert.equal(byClass(tree, 'progress-fill').props.style['--cx-fill'], 0.25);
    const hint = byClass(tree, 'progress-cancel');
    assert.equal(hint.props['aria-label'], '/cortexdebug to stop');
    assert.match(hint.props.className, /is-always/, 'a consumer hint is the only instruction and ignores the hints preference');
    const ids = elements(tree).map(n => n.props.id).filter(Boolean);
    assert.ok(ids.every(id => id.startsWith('debug-test-all-')), 'parallel sample IDs stay independent');
});

test('help values tokenize into keycaps, separators and prose', () => {
    const tokenize = surface('text.js')('tokenizeHelpKeys');
    const keys = value => [...tokenize(value)].map(token => token.type === 'key' ? token.value : token.type === 'sep' ? '/' : `"${token.value}"`);
    assert.deepEqual(keys('W S A D'), ['W', 'S', 'A', 'D']);
    assert.deepEqual(keys('Esc · Backspace'), ['ESC', '/', 'BACKSPACE']);
    assert.deepEqual(keys('SHIFT+E'), ['SHIFT', 'E']);
    assert.deepEqual(keys('LEFT ALT'), ['L ALT'], 'a side and a modifier are one key');
    assert.deepEqual(keys('Up Down'), ['UP', 'DOWN']);
    assert.deepEqual(keys('NUM 5'), ['NUM 5']);
    assert.deepEqual(keys('Recording tab'), ['"Recording tab"'], 'prose never turns into keycaps');
    assert.deepEqual(keys(''), []);
    assert.equal(keys('A B C D E F G H I J').length, 8, 'at most eight keycaps per control');
});

test('help renders a label-first, right-aligned controls legend that stays on with hints off', () => {
    const get = surface('text.js');
    const HelpBar = get('HelpBar');
    const tree = HelpBar({ open: true, items: [{ label: 'Grab', value: 'E' }, { label: 'Back', value: 'BACKSPACE' }] });
    assert.equal(tree.props.role, 'group');
    for (const name of ['cortex-help-bar', 'cx-legend', 'cx-legend--end', 'is-always']) assert.ok(tree.props.className.split(' ').includes(name), name);
    const items = elements(tree).filter(node => (node.props.className || '').includes('cortex-help-item'));
    assert.equal(items.length, 2);
    assert.match(items[0].props.className, /cx-hint--label-first/);
    assert.equal(items[0].children[0].props.className.includes('cortex-help-label'), true, 'the label comes before the keycaps');
    assert.equal(text(items[0].children[0]), 'Grab');
    assert.equal(byType(items[1], get('HelpKeyTokens'))[0].props.value, 'BACKSPACE');
    const compact = HelpBar({ open: true, compact: true, items: [{ label: 'Zoom', value: 'Up Down' }] });
    assert.match(compact.props.className, /cortex-help-bar--compact/);
    assert.equal(byType(compact, get('HelpKeyTokens'))[0].props.value, 'Up Down', 'compact only resizes the shared key glyph in CSS');
    assert.equal(surface('text.js', { states: [false] })('HelpBar')({ open: false, items: [{ label: 'X', value: 'E' }] }), null);
    assert.equal(HelpBar({ open: true, items: [] }), null);
});

test('text UI renders key tokens as keycaps and chooses action or sentence type', () => {
    const get = surface('text.js');
    const TextUI = get('TextUI');
    const action = TextUI({ open: true, text: '[E] Open trunk  [SHIFT+G] Lock', position: 'bottom-center' });
    assert.equal(action.props.id, 'textui');
    assert.equal(action.props.role, 'status');
    assert.equal(action.props['aria-live'], 'polite');
    assert.match(action.props.className, /textui--action/);
    const groups = elements(action).filter(node => (node.props.className || '').startsWith('textui-keys'));
    assert.deepEqual(groups.map(group => group.children.map(cap => cap.props.value)), [['E'], ['SHIFT', 'G']]);
    assert.ok(groups.every(group => group.children.every(cap => cap.props.size === 'lg')));
    assert.match(groups[1].props.className, /after-text/, 'a second action is spaced from the first label');
    assert.deepEqual(elements(action).filter(node => node.props.className === 'textui-run').map(text), ['Open trunk', 'Lock']);

    const sentence = TextUI({ open: true, text: 'Hold [E] to pick the lock. Release early or press [BACKSPACE] to stop and keep your pick.' });
    assert.match(sentence.props.className, /textui--sentence/);
    assert.match(sentence.props.className, /bottom-center/);

    const plate = { backgroundColor: '#000', border: '2px solid #fff', color: '#abc' };
    assert.deepEqual({ ...TextUI({ open: true, text: 'x', style: plate }).props.style }, { color: '#abc' }, 'frameless text drops plate styles');
    const slip = TextUI({ open: true, text: 'x', style: plate, backdrop: true, icon: 'hand' });
    assert.match(slip.props.className, /textui-backdrop/);
    assert.ok(byClass(slip, 'textui-icon'));
    assert.equal(surface('text.js', { states: [false] })('TextUI')({ open: false, text: 'x' }), null);
});

test('debug panel is a bounded developer slip with validated colours', () => {
    const get = surface('text.js');
    const DebugPanel = get('DebugPanel');
    const tree = DebugPanel({ open: true, title: 'Telemetry', subtitle: 'sample', position: 'top-left', accentColor: 'red; position: fixed',
        lines: [{ label: 'Fuel', value: '14%', color: 'url(x)' }, { label: 'Engine', value: '312', color: 'var(--error)' }, 'raw line'], data: { a: 1 } });
    assert.match(tree.props.className, /cortex-debug-root top-left/);
    assert.equal(tree.props.style, undefined, 'unsafe accent colours are dropped');
    assert.ok(byClass(tree, 'cx-slip'));
    const Line = get('DebugPanelLine');
    const lines = byType(tree, Line);
    assert.equal(lines.length, 3);
    assert.equal(byClass(Line(lines[0].props), 'cortex-debug-value').props.style, undefined);
    assert.deepEqual({ ...byClass(Line(lines[1].props), 'cortex-debug-value').props.style }, { color: 'var(--error)' });
    assert.match(Line(lines[2].props).props.className, /is-text/);
    assert.equal(text(byClass(tree, 'cortex-debug-json')), '{\n  "a": 1\n}');
    const accented = DebugPanel({ open: true, title: 'T', accentColor: 'var(--warning)', lines: [] });
    assert.equal(accented.props.style['--debug-accent'], 'var(--warning)');
    const textCss = readFileSync(new URL('../ui/surfaces/text.css', import.meta.url), 'utf8');
    assert.doesNotMatch(textCss, /border(?:-bottom)?:\s*1px/, 'no hairline rules between rows');
});
