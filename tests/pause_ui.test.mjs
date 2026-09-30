import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../ui/pause.js', import.meta.url), 'utf8');
const styles = readFileSync(new URL('../ui/pause.css', import.meta.url), 'utf8');

// Executes React component logic and inspects element descriptors. This is
// deliberately a static fixture, with no browser/CEF or visual claim.
function harness() {
    const hooks = [], effects = [];
    let cursor = 0;
    const React = {
        Fragment: 'fragment',
        createElement: (type, props, ...children) => ({ type, props: props || {}, children: children.flat(Infinity) }),
        useState(initial) {
            const index = cursor++;
            if (!(index in hooks)) hooks[index] = initial;
            return [hooks[index], next => { hooks[index] = typeof next === 'function' ? next(hooks[index]) : next; }];
        },
        useRef(initial) { return React.useState({ current: initial })[0]; },
        useEffect(callback, deps) {
            const index = cursor++;
            if (!hooks[index] || deps.some((dep, i) => dep !== hooks[index].deps[i])) {
                hooks[index]?.cleanup?.();
                hooks[index] = { deps };
                effects.push(() => { hooks[index].cleanup = callback(); });
            }
        }
    };
    const KeyHint = props => ({ type: 'hint', props, children: [props.label] });
    const window = { addEventListener() {}, removeEventListener() {}, CortexKit: { KeyHint } };
    const context = vm.createContext({ React, window, requestAnimationFrame() { return 1; }, cancelAnimationFrame() {}, setTimeout() { return 1; }, clearTimeout() {} });
    vm.runInContext(source, context);
    return {
        normalize: window.CortexPause.normalize,
        render(props) {
            cursor = 0;
            const tree = window.CortexPause.Frame(props);
            while (effects.length) effects.shift()();
            return tree;
        }
    };
}
const all = (tree, predicate) => {
    if (!tree || typeof tree !== 'object') return [];
    return [...(predicate(tree) ? [tree] : []), ...tree.children.flatMap(child => all(child, predicate))];
};
const content = tree => typeof tree === 'string' ? tree : tree?.children?.map(content).join('') || '';
const button = (tree, label) => all(tree, node => node.type === 'button').find(node => content(node).includes(label));
const defaults = () => ({ open: true, page: 'home', pause: harness().normalize({ quickMenu: true }), session: 1, setPage() {}, dialogRef: { current: null },
    post: async () => ({ ok: true }), onResume() {}, onSave() {}, onBack() {}, submitting: false, dirtyCount: 0 });

test('pause snapshots accept bounded plain presentation data only', () => {
    const app = harness();
    assert.equal(app.normalize(null).title, 'CORTEX');
    const data = app.normalize({ title: 'x'.repeat(90), safezone: Infinity,
        pages: [null, { id: 'r:help', label: 'Help', html: '<script>', sections: [{ body: '<img onerror=evil>', actions: [{ id: 'a', label: 'A', command: 'quit' }] }] }],
        locations: [{ id: 'r:spot', label: 'Spot', x: 1, y: 2 }] });
    assert.equal(data.title.length, 48);
    assert.equal(data.safezone, 1);
    assert.equal(data.pages.length, 1);
    assert.equal(data.pages[0].html, undefined);
    assert.equal(data.pages[0].sections[0].actions[0].command, undefined);
    assert.equal(data.locations[0].x, undefined);
    assert.equal(app.normalize({ pages: Array.from({ length: 100 }, (_, i) => ({ id: String(i), label: 'Page' })) }).pages.length, 24);
});

test('map and key bindings use native menus; Settings stays in the Cortex shell', async () => {
    const app = harness();
    const requests = [], props = defaults();
    let page; props.setPage = next => { page = next; };
    props.post = async (name, data) => { requests.push({ name, data }); return { ok: true }; };
    assert.equal(app.render({ ...props, open: false }), null);
    let tree = app.render(props);
    await button(tree, 'Map').props.onClick();
    assert.equal(requests[0].name, 'pauseNative');
    assert.equal(requests[0].data.target, 'map');
    assert.equal(requests[0].data.session, 1);
    await button(tree, 'Settings').props.onClick();
    assert.equal(page, 'settings', 'Settings opens the standalone Cortex preferences');
    tree = app.render(props);
    await button(tree, 'Key bindings').props.onClick();
    assert.equal(page, 'settings', 'key bindings do not route to a Cortex page');
    assert.equal(requests[1].name, 'pauseNative');
    assert.equal(requests[1].data.target, 'keybindings');
    assert.equal(requests[1].data.returnTo, 'home', 'leaving GTA key mapping returns to the quick menu');
    tree = app.render(props);
    assert.equal(button(tree, 'Script settings'), undefined, 'Cortex preferences use one Settings entry');
    page = 'settings';
    assert.equal(requests.length, 2, 'the map and key bindings hand off on the home screen');
    const scriptChild = { type: 'script-settings-fixture', props: {}, children: [] };
    assert.equal(all(app.render({ ...props, page, children: scriptChild }), node => node === scriptChild).length, 1);
    tree = app.render({ ...props, page: 'game' });
    assert.equal(page, 'home', 'the retired in-shell game page is not a route');
    assert.equal(button(tree, 'Locations'), undefined, 'no fictitious location directory is advertised');
});

test('extension pages and locations use registry IDs; HTML remains text', async () => {
    const app = harness();
    const requests = [], props = defaults();
    props.pause = app.normalize({ quickMenu: true, pages: [{ id: 'guide:help', label: 'Help', sections: [{ body: '<script>evil()</script>', actions: [{ id: 'open', label: 'Open help' }] }] }],
        locations: [{ id: 'hospital:front', label: 'Pillbox', category: 'Medical' }] });
    props.post = async (name, data) => { requests.push({ name, data }); return { ok: true }; };
    let tree = app.render({ ...props, page: 'guide:help' });
    assert.equal(all(tree, node => 'dangerouslySetInnerHTML' in node.props).length, 0);
    assert.ok(content(tree).includes('<script>evil()</script>'));
    await button(tree, 'Open help').props.onClick();
    assert.equal(requests[0].data.page, 'guide:help');
    assert.equal(requests[0].data.id, 'open');
    tree = app.render({ ...props, page: 'locations' });
    await button(tree, 'Pillbox').props.onClick();
    assert.equal(requests[1].name, 'pauseWaypoint');
    assert.equal(requests[1].data.id, 'hospital:front');
    tree = app.render({ ...props, page: 'locations' });
    assert.ok(content(tree).includes('Waypoint set: Pillbox'));
});

test('leaving requires a separate confirmation; failures and unsaved edits stay visible', async () => {
    const app = harness();
    let nextPage, requestCount = 0;
    const props = { ...defaults(), dirtyCount: 2, setPage: page => { nextPage = page; },
        post: async () => { requestCount++; return { ok: false }; } };
    let tree = app.render(props);
    button(tree, 'Leave server').props.onClick();
    assert.equal(nextPage, 'leave');
    assert.equal(requestCount, 0);
    assert.ok(button(tree, 'Resume / discard changes'));
    assert.ok(button(tree, 'Save & resume'));
    tree = app.render({ ...props, page: 'leave' });
    assert.ok(button(tree, 'Stay here').props['data-pause-autofocus']);
    await button(tree, 'Leave server').props.onClick();
    tree = app.render({ ...props, page: 'leave' });
    assert.ok(content(tree).includes('Unable to complete that action'));
    tree = app.render({ ...props, error: 'SAVE FAILED' });
    tree = app.render({ ...props, error: 'SAVE FAILED' });
    assert.ok(content(tree).includes('SAVE FAILED'));
});

test('pause visual source keeps intentional, bounded surfaces without effects or network assets', () => {
    const app = harness();
    const rail = all(app.render(defaults()), node => node.props.className === 'pause-rail');
    assert.equal(rail.length, 1, 'home mounts one decorative navigation column');
    assert.equal(rail[0].props['aria-hidden'], true);
    assert.equal(all(app.render({ ...defaults(), page: 'settings' }), node => node.props.className === 'pause-rail').length, 0);
    assert.doesNotMatch(styles, /(?:linear|radial|conic)-gradient|backdrop-filter|https?:\/\//i);
    assert.doesNotMatch(source, /dangerouslySetInnerHTML|innerHTML|eval\(|new Function/);
    assert.match(styles, /\.cortex-pause\.cortex-settings-panel\s*\{[^}]*inset: var\(--pause-safe\)/);
    assert.match(styles, /@media \(prefers-reduced-motion: reduce\)/);
    assert.match(styles, /\.pause-main-nav\s*\{[^}]*overflow: auto/);
    assert.doesNotMatch(styles, /drop-shadow\(/, 'paper depth does not use viewport-sized filter passes');
});

test('quick menu skips location-search work until the directory is opened', () => {
    const app = harness();
    let reads = 0;
    const pause = app.normalize({ quickMenu: true, locations: Array.from({ length: 256 }, (_, i) => ({
        id: `resource:location${i}`, label: `Location ${i}`, category: 'Places'
    })) });
    for (const location of pause.locations) {
        const label = location.label;
        Object.defineProperty(location, 'label', { get() { reads++; return label; } });
    }
    const props = { ...defaults(), pause };
    app.render(props);
    assert.equal(reads, 0, 'home does not scan hidden location labels');
    const tree = app.render({ ...props, page: 'locations' });
    assert.ok(reads >= 256);
    assert.ok(button(tree, 'Location 255'), 'all registered locations remain available');
});

test('standalone Cortex Settings has no quick-menu back arrow and defaults to server opt-out', () => {
    const app = harness();
    const props = { ...defaults(), page: 'settings', pause: app.normalize({ quickMenu: false }) };
    const tree = app.render(props);
    assert.equal(button(tree, 'Close'), undefined, 'footer actions and Escape close settings');
    assert.equal(button(tree, '← Quick menu'), undefined);
    assert.equal(app.normalize({}).quickMenu, false, 'only an explicit server opt-in enables the quick menu');
    const enabledTree = app.render({ ...props, pause: app.normalize({ quickMenu: true }) });
    assert.equal(button(enabledTree, '← Quick menu'), undefined, 'settings remains standalone when the server enables the menu');
    let nextPage;
    app.render({ ...props, page: 'home', setPage: page => { nextPage = page; } });
    assert.equal(nextPage, 'settings', 'server opt-out routes an open quick menu to settings');
    const settingsStyles = readFileSync(new URL('../ui/surfaces/settings.css', import.meta.url), 'utf8');
    const scrim = settingsStyles.match(/\.cortex-pause-overlay\.is-settings-page\s*\{([^}]*)\}/);
    assert.ok(scrim, 'the settings page owns its scrim');
    assert.match(scrim[1], /--settings-scrim: rgba\(15, 16, 18, 0\.66\)/, 'settings darkens the game with a 66% ink scrim');
    assert.match(scrim[1], /background: var\(--settings-scrim\)/);
    assert.doesNotMatch(settingsStyles, /backdrop-filter|(?:linear|radial|conic)-gradient|outline:\s*(?!none)[^;]*solid/,
        'the game blur is native; CEF never filters the backdrop');
});

test('settings page heading carries the controls legend and no quick-menu footer hints', () => {
    const app = harness();
    const legendItems = [];
    const Kit = { ControlsLegend: props => { legendItems.push(...props.items); return { type: 'legend', props, children: [] }; },
        KeyHint: props => ({ type: 'hint', props, children: [props.label] }) };
    const source = readFileSync(new URL('../ui/pause.js', import.meta.url), 'utf8');
    const hooks = [];
    let cursor = 0;
    const React = { Fragment: 'fragment',
        createElement: (type, props, ...children) => typeof type === 'function' ? type(props || {}) : ({ type, props: props || {}, children: children.flat(Infinity) }),
        useState(initial) { const i = cursor++; if (!(i in hooks)) hooks[i] = initial; return [hooks[i], v => { hooks[i] = v; }]; },
        useRef(initial) { return React.useState({ current: initial })[0]; },
        useEffect() { cursor++; } };
    const window = { addEventListener() {}, removeEventListener() {}, CortexKit: Kit };
    const context = vm.createContext({ React, window, requestAnimationFrame() { return 1; }, cancelAnimationFrame() {}, setTimeout() { return 1; }, clearTimeout() {} });
    vm.runInContext(source, context);
    assert.equal(typeof window.CortexPause.moveFocus, 'function', 'settings rows reuse the shell focus walker');
    const props = { ...defaults(), page: 'settings', pause: app.normalize({ quickMenu: false }) };
    const tree = window.CortexPause.Frame(props);
    assert.ok(legendItems.some(item => item.keys === 'ESC' && /discard/i.test(item.label)), 'Escape is labelled as discard');
    assert.equal(all(tree, node => node.props.className === 'pause-hints').length, 0, 'no second legend in a footer');
    assert.equal(all(tree, node => node.type === 'footer').length, 0, 'an empty status adds no footer row');
    cursor = 0;
    const withNotice = window.CortexPause.Frame({ ...props, error: 'SAVE FAILED' });
    assert.ok(content(withNotice).includes('SAVE FAILED'));
});
