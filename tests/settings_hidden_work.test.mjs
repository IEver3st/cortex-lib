import { uiSource, uiStyles } from './ui_source.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = uiSource;
const panel = source.slice(source.indexOf('function SettingsPanel('), source.indexOf('\n// ============================================================================', source.indexOf('function SettingsPanel(')));

test('advanced and contextual controls stay discoverable without losing pending values', () => {
    const hooks = [];
    let cursor = 0;
    function SettingsField() {}
    const context = vm.createContext({
        React: { createElement: (type, props, ...children) => ({ type, props, children }) },
        SettingsField,
        useState(initial) {
            const index = cursor++;
            if (!(index in hooks)) hooks[index] = initial;
            return [hooks[index], value => { hooks[index] = typeof value === 'function' ? value(hooks[index]) : value; }];
        },
        useRef: initial => ({ current: initial }), useCallback: callback => callback,
        useEffect() {}, useModalFocus() {}, normalizeSession: value => value,
        nuiPost: async () => ({ ok: true }),
        window: { CortexPause: { Frame() {} }, requestAnimationFrame() {} }
    });
    vm.runInContext(panel, context);
    const props = { open: true, session: 1, onClose() {}, tabs: [
        { id: 'hud', label: 'HUD', values: { style: false, color: 'green' }, fields: [
            { key: 'style', label: 'Lore Friendly', type: 'toggle', section: 'Appearance' },
            { key: 'color', label: 'Health Color', type: 'select', section: 'Colors', advanced: true },
            { key: 'weapon', label: 'Weapon Name', type: 'toggle', section: 'Weapons', showWhen: { style: true } }
        ] },
        { id: 'other', label: 'Other', values: {}, fields: [{ key: 'enabled', label: 'Enabled', type: 'toggle' }] }
    ] };
    const render = () => { cursor = 0; return context.SettingsPanel(props); };
    const nodes = tree => !tree || typeof tree !== 'object' ? [] : [tree, ...(tree.children || []).flat(Infinity).flatMap(nodes)];
    const fields = tree => nodes(tree).filter(node => node.type === SettingsField);
    const advancedButton = tree => nodes(tree).find(node => node.props?.className === 'pause-advanced-toggle');
    const searchBox = tree => nodes(tree).find(node => node.props?.type === 'search');
    let tree = render();
    assert.deepEqual(fields(tree).map(node => node.props.field.key), ['style']);
    advancedButton(tree).props.onClick(); tree = render();
    assert.deepEqual(fields(tree).map(node => node.props.field.key), ['style', 'color']);
    fields(tree)[1].props.onChange('hud', 'color', 'blue'); tree = render();
    advancedButton(tree).props.onClick(); tree = render();
    assert.equal(fields(tree).length, 1);
    assert.equal(tree.props.dirtyCount, 1, 'collapsing advanced must retain edits');
    searchBox(tree).props.onChange({ target: { value: 'Health Color' } }); tree = render();
    assert.equal(fields(tree)[0].props.field.key, 'color', 'search reveals advanced controls');
    assert.equal(fields(tree)[0].props.value, 'blue');
    searchBox(tree).props.onChange({ target: { value: '' } }); tree = render();
    fields(tree)[0].props.onChange('hud', 'style', true); tree = render();
    assert.deepEqual(fields(tree).map(node => node.props.field.key), ['style', 'weapon']);
    fields(tree)[0].props.onChange('hud', 'style', false); tree = render();
    searchBox(tree).props.onChange({ target: { value: 'Weapon Name' } }); tree = render();
    assert.equal(fields(tree).length, 0, 'search must not expose inapplicable controls');
    nodes(tree).find(node => node.props?.role === 'tab' && node.props.id === 'cortex-settings-tab-1').props.onClick();
    tree = render();
    assert.equal(advancedButton(tree), undefined, 'unmodified scripts gain no advanced switch');
    assert.equal(fields(tree).length, 1);
});

test('hidden script pages build no fields and retain edits when returning to settings', () => {
    const hooks = [];
    let cursor = 0, allocations = 0;
    function SettingsField() {}
    const context = vm.createContext({
        React: { createElement(type, props, ...children) {
            if (type === SettingsField) allocations++;
            return { type, props, children };
        } },
        SettingsField,
        useState(initial) {
            const index = cursor++;
            if (!(index in hooks)) hooks[index] = initial;
            return [hooks[index], value => { hooks[index] = typeof value === 'function' ? value(hooks[index]) : value; }];
        },
        useRef: initial => ({ current: initial }),
        useCallback: callback => callback,
        useEffect() {}, useModalFocus() {}, normalizeSession: value => value,
        nuiPost: async () => ({ ok: true }),
        window: { CortexPause: { Frame() {} }, requestAnimationFrame() {} }
    });
    vm.runInContext(panel, context);
    const props = { open: true, session: 1, page: 'home', onClose() {},
        tabs: [{ id: 'example', label: 'Example', values: {}, fields: Array.from({ length: 128 }, (_, i) => ({
            key: `field${i}`, label: `Field ${i}`, section: 'General', type: 'toggle'
        })) }] };
    const render = () => { cursor = 0; allocations = 0; return context.SettingsPanel(props); };
    let tree = render();
    assert.equal(allocations, 0, 'initial quick menu does not build a hidden script page');
    tree.props.setPage('settings'); tree = render();
    assert.equal(allocations, 128);
    const findField = node => {
        if (!node || typeof node !== 'object') return null;
        if (node.type === SettingsField) return node;
        for (const child of (node.children || []).flat(Infinity)) {
            const match = findField(child); if (match) return match;
        }
        return null;
    };
    findField(tree).props.onChange('example', 'field0', true);
    tree = render();
    assert.equal(tree.props.dirtyCount, 1);
    for (const page of ['home', 'locations']) {
        tree.props.setPage(page); tree = render();
        assert.equal(allocations, 0);
        assert.equal(tree.props.dirtyCount, 1, 'hidden page retains the pending edit');
    }
    tree.props.setPage('settings'); tree = render();
    assert.equal(allocations, 128);
    assert.equal(findField(tree).props.value, true);
});

test('Apply retains the panel, resets dirty state and protects an in-flight commit', async () => {
    const hooks = [], refs = [], requests = [], closed = [];
    let cursor = 0, refCursor = 0, resolveSave;
    function SettingsField() {}
    const context = vm.createContext({
        React: { createElement: (type, props, ...children) => ({ type, props, children }) },
        SettingsField,
        useState(initial) {
            const index = cursor++;
            if (!(index in hooks)) hooks[index] = initial;
            return [hooks[index], value => { hooks[index] = typeof value === 'function' ? value(hooks[index]) : value; }];
        },
        useRef(initial) { return refs[refCursor++] ??= { current: initial }; },
        useCallback: callback => callback,
        useEffect() {}, useModalFocus() {}, normalizeSession: value => value,
        nuiPost: (route, data) => {
            requests.push({ route, data });
            return route === 'settingsSave' ? new Promise(resolve => { resolveSave = resolve; }) : Promise.resolve({ ok: true });
        },
        window: { CortexPause: { Frame() {} }, requestAnimationFrame() {} }
    });
    vm.runInContext(panel, context);
    const props = { open: true, session: 7, onClose: session => closed.push(session),
        tabs: [{ id: 'dynamic', label: 'Dynamic UI', values: { opacity: 92 },
            fields: [{ key: 'opacity', label: 'Opacity', type: 'slider' }] }] };
    const render = () => { cursor = refCursor = 0; return context.SettingsPanel(props); };
    const find = (node, predicate) => {
        if (!node || typeof node !== 'object') return null;
        if (predicate(node)) return node;
        for (const child of (node.children || []).flat(Infinity)) {
            const match = find(child, predicate); if (match) return match;
        }
        return null;
    };
    const field = tree => find(tree, node => node.type === SettingsField);
    const apply = tree => find(tree, node => node.props?.className === 'cortex-settings-btn apply');
    let tree = render();
    assert.equal(apply(tree).props.disabled, true);
    field(tree).props.onChange('dynamic', 'opacity', 75);
    tree = render();
    assert.equal(tree.props.dirtyCount, 1);
    const pending = apply(tree).props.onClick();
    tree.props.onApply(); // double activation before React commits a render
    field(tree).props.onChange('dynamic', 'opacity', 90);
    assert.equal(requests.filter(item => item.route === 'settingsSave').length, 1);
    assert.equal(requests.at(-1).data.keepOpen, true);
    tree = render();
    assert.equal(field(tree).props.value, 75, 'edits cannot race an in-flight Apply');
    resolveSave({ ok: true }); await pending;
    tree = render();
    assert.equal(closed.length, 0);
    assert.equal(tree.props.dirtyCount, 0);
    assert.equal(apply(tree).props.disabled, true);
    field(tree).props.onChange('dynamic', 'opacity', 85);
    tree = render();
    assert.equal(tree.props.dirtyCount, 1);
    const failed = tree.props.onApply();
    resolveSave({ ok: false }); await failed;
    tree = render();
    assert.equal(tree.props.error, 'APPLY FAILED');
    assert.equal(tree.props.dirtyCount, 1);
    assert.equal(closed.length, 0);
    const save = tree.props.onSave({ type: 'click' });
    assert.equal(requests.at(-1).data.keepOpen, false, 'click event must not turn Save & Resume into Apply');
    resolveSave({ ok: true }); await save;
    assert.deepEqual(closed, [7]);
});

test('settings contains script tabs without game-settings or keybinding handoffs', () => {
    const hooks = [], refs = [], requests = [];
    let cursor = 0, refCursor = 0;
    function SettingsField() {}
    const context = vm.createContext({
        React: { createElement: (type, props, ...children) => ({ type, props, children }) },
        SettingsField,
        useState(initial) {
            const index = cursor++;
            if (!(index in hooks)) hooks[index] = initial;
            return [hooks[index], value => { hooks[index] = typeof value === 'function' ? value(hooks[index]) : value; }];
        },
        useRef(initial) { return refs[refCursor++] ??= { current: initial }; },
        useCallback: callback => callback,
        useEffect() {}, useModalFocus() {}, normalizeSession: value => value, uiDebugLog() {},
        nuiPost: async (route, data) => { requests.push({ route, data }); return { ok: true }; },
        window: { CortexPause: { Frame() {} }, requestAnimationFrame() {} }
    });
    vm.runInContext(panel, context);
    const props = { open: true, session: 7, onClose() {},
        tabs: [{ id: 'dynamic', label: 'Dynamic UI', values: { opacity: 92 },
            fields: [{ key: 'opacity', label: 'Opacity', type: 'slider' }] }] };
    const render = () => { cursor = refCursor = 0; return context.SettingsPanel(props); };
    const find = (node, predicate) => {
        if (!node || typeof node !== 'object') return null;
        if (predicate(node)) return node;
        for (const child of (node.children || []).flat(Infinity)) {
            const match = find(child, predicate); if (match) return match;
        }
        return null;
    };
    let tree = render();
    find(tree, node => node.type === SettingsField).props.onChange('dynamic', 'opacity', 70);
    tree = render();
    assert.equal(find(tree, node => node.props?.className?.includes('cortex-settings-tab-game')), null);
    assert.equal(find(tree, node => node.props?.className?.includes('cortex-settings-tab-link')), null);
    assert.ok(find(tree, node => node.props?.role === 'tab'), 'registered script tabs remain available');
    assert.equal(tree.props.dirtyCount, 1, 'the reduced navigation preserves pending edits');
    assert.equal(requests.filter(item => item.route !== 'settingsPreview').length, 0);
});

test('Escape closes standalone Settings regardless of the server quick-menu option', async () => {
    const hooks = [], refs = [], requests = [];
    let cursor = 0, refCursor = 0, backHandler;
    function SettingsField() {}
    const context = vm.createContext({
        React: { createElement: (type, props, ...children) => ({ type, props, children }) },
        SettingsField, CustomEvent: class { constructor(type, init) { this.type = type; Object.assign(this, init); } },
        useState(initial) {
            const index = cursor++;
            if (!(index in hooks)) hooks[index] = initial;
            return [hooks[index], value => { hooks[index] = typeof value === 'function' ? value(hooks[index]) : value; }];
        },
        useRef(initial) { return refs[refCursor++] ??= { current: initial }; },
        useCallback: callback => callback,
        useEffect() {}, useModalFocus(open, ref, onBack) { backHandler = onBack; }, normalizeSession: value => value, uiDebugLog() {},
        nuiPost: async (route, data) => { requests.push({ route, data }); return { ok: true }; },
        window: { CortexPause: { Frame() {} }, requestAnimationFrame() {}, dispatchEvent: () => true }
    });
    vm.runInContext(panel, context);
    const props = { open: true, session: 7, onClose() {}, pause: { quickMenu: false },
        tabs: [{ id: 'dynamic', label: 'Dynamic UI', values: { opacity: 92 }, fields: [] }] };
    cursor = refCursor = 0;
    let tree = context.SettingsPanel(props);
    assert.equal(tree.props.page, 'settings');
    backHandler(); await Promise.resolve();
    assert.ok(requests.some(item => item.route === 'settingsCancel'), 'Back closes instead of opening a disabled quick menu');
    const onProps = { ...props, pause: { quickMenu: true } };
    hooks.length = 0; refs.length = 0; // fresh panel: the close above left it submitting
    cursor = refCursor = 0; context.SettingsPanel(onProps);
    requests.length = 0; backHandler();
    cursor = refCursor = 0; tree = context.SettingsPanel(onProps);
    assert.equal(tree.props.page, 'settings', 'settings never routes Back to the quick menu');
    assert.ok(requests.some(item => item.route === 'settingsCancel'));
});
