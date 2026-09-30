import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../ui/debug.js', import.meta.url), 'utf8');
// Production component logic only; this is not pixel or live NUI evidence.
function harness(post = async () => ({ ok: true })) {
    const hooks = [], effects = [], listeners = new Map(); let cursor = 0;
    const React = {
        Fragment: 'fragment',
        createElement: (type, props, ...children) => ({ type, props: props || {}, children: children.flat(Infinity) }),
        useState(value) { const i = cursor++; if (!(i in hooks)) hooks[i] = value; return [hooks[i], next => { hooks[i] = typeof next === 'function' ? next(hooks[i]) : next; }]; },
        useRef(value) { return React.useState({ current: value })[0]; },
        useCallback(fn) { return fn; },
        useEffect(fn, deps) { const i = cursor++; if (!hooks[i] || deps.some((d, n) => d !== hooks[i][n])) { hooks[i] = deps; effects.push(fn); } }
    };
    const window = { addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: name => listeners.delete(name) };
    vm.runInNewContext(source, { React, window });
    return { model: window.CortexDebug, message: data => listeners.get('message')?.({ data }),
        render() { cursor = 0; const tree = window.CortexDebug.Workbench({ post, ProgressBar: 'CortexProgress' }); while (effects.length) effects.shift()(); return tree; } };
}
const all = (tree, predicate) => !tree || typeof tree !== 'object' ? [] : [...(predicate(tree) ? [tree] : []), ...tree.children.flatMap(child => all(child, predicate))];
const content = tree => typeof tree === 'string' ? tree : tree?.children?.map(content).join('') || '';
const button = (tree, label) => all(tree, n => n.type === 'button').find(n => content(n) === label);
const catalog = [
    { id: 'notify', group: 'Notifications', title: 'Single event', description: 'A notification' },
    { id: 'progress_bar', group: 'Progress', title: 'Linear progress', description: 'A progress bar' }
];
test('side menu navigates with wheel commands, opens categories and keeps passive tests visible', async () => {
    const requests = []; const app = harness(async (name, data) => { requests.push({ name, data }); return { ok: true }; });
    const input = command => { app.message({ action: 'debug:input', data: { session: 1, input: command } }); return app.render(); };
    assert.equal(app.render(), null);
    app.message({ action: 'debug:open', data: { session: 1, catalog } });
    let tree = app.render(); await Promise.resolve();
    assert.equal(requests[0].name, 'debugReady');
    assert.equal(all(tree, n => n.props['aria-modal']).length, 0);
    input('down'); tree = input('enter');
    assert.ok(content(tree).includes('Linear progress'));
    input('enter'); await new Promise(setImmediate); tree = app.render();
    assert.equal(requests.at(-1).data.id, 'progress_bar');
    assert.ok(tree, 'passive test does not dismiss the menu');
    tree = input('back'); assert.ok(content(tree).includes('All tests'));
    input('back'); await Promise.resolve(); assert.equal(requests.at(-1).name, 'debugClose');
    app.message({ action: 'debug:close', data: { session: 999 } }); assert.ok(app.render());
    app.message({ action: 'debug:close', data: { session: 1 } }); assert.equal(app.render(), null);
});
test('test options cycle through durations, placements and sample messages without text capture', async () => {
    const requests = []; const app = harness(async (name, data) => { requests.push({ name, data }); return { ok: true }; });
    app.render(); app.message({ action: 'debug:open', data: { session: 1, catalog } });
    let tree = app.render();
    const options = all(tree, n => n.type === 'button').find(n => content(n).startsWith('Test options'));
    options.props.onClick(); tree = app.render();
    const input = command => { app.message({ action: 'debug:input', data: { session: 1, input: command } }); return app.render(); };
    tree = input('right'); assert.match(content(tree), /6s/);
    input('down'); tree = input('enter'); assert.match(content(tree), /top-left/);
    input('down'); tree = input('right'); assert.match(content(tree), /Started cortex_mdtsv/);
    input('back'); input('enter'); input('enter'); await Promise.resolve();
    assert.deepEqual(JSON.parse(JSON.stringify(requests.at(-1).data.options)), { duration: 6000, position: 'top-left', message: 'Started cortex_mdtsv' });
});
test('late replies and input cannot overwrite a newer debug session', async () => {
    let resolve; const app = harness(name => name === 'debugRun' ? new Promise(done => { resolve = done; }) : Promise.resolve({ ok: true }));
    app.render(); app.message({ action: 'debug:open', data: { session: 1, catalog } }); app.render();
    app.message({ action: 'debug:input', data: { session: 1, input: 'enter' } }); app.render();
    const pending = button(app.render(), 'Single event').props.onClick();
    app.message({ action: 'debug:open', data: { session: 2, catalog } });
    app.message({ action: 'debug:history', data: { session: 1, history: [{ id: 'notify', detail: 'STALE' }] } });
    app.message({ action: 'debug:input', data: { session: 1, input: 'back' } });
    resolve({ ok: false, error: 'OLD ERROR' }); await pending;
    assert.doesNotMatch(content(app.render()), /STALE|OLD ERROR/);
    assert.ok(content(app.render()).includes('Single event'));
    assert.equal(app.model.normalizeCatalog([null, { id: 'bad/id', title: 'bad', group: 'x' }, ...catalog]).length, 2);
    assert.equal(app.model.normalizeHistory(Array.from({ length: 50 }, () => ({ id: 'notify', detail: 'x'.repeat(800) }))).length, 50);
});

test('closing a child restores selection; Test All hides the menu and reuses controlled Cortex progress', async () => {
    const requests = [];
    const app = harness(async (name, data) => { requests.push({ name, data }); return { ok: true }; });
    app.render(); app.message({ action: 'debug:open', data: { session: 1, catalog } }); app.render();
    const input = (session, command) => { app.message({ action: 'debug:input', data: { session, input: command } }); return app.render(); };
    input(1, 'down'); input(1, 'enter');
    app.message({ action: 'debug:close', data: { session: 1 } }); assert.equal(app.render(), null);
    app.message({ action: 'debug:open', data: { session: 2, catalog } });
    assert.ok(content(app.render()).includes('Linear progress'));
    assert.equal(all(app.render(), n => n.props.className?.includes('selected')).map(content)[0], 'Linear progress');
    input(2, 'back');
    button(app.render(), 'Test All').props.onClick(); await new Promise(setImmediate);
    assert.equal(requests.at(-1).name, 'debugRunAll');
    assert.equal(requests.at(-1).data.options.duration, 5000);
    app.message({ action: 'debug:close', data: { session: 2 } });
    app.message({ action: 'debug:walkthrough', data: { revision: 1, run: { index: 1, completed: 0, total: 2, id: 'notify', title: 'Single event' } } });
    let tree = app.render();
    assert.equal(tree.type, 'CortexProgress');
    assert.equal(tree.props.position, 'middle');
    assert.equal(tree.props.value, 0);
    assert.equal(all(tree, n => n.props.className === 'debug-menu').length, 0);
    assert.equal(tree.props.hint, '/cortexdebug to stop');
    app.message({ action: 'debug:walkthrough', data: { revision: 2, run: { index: 2, completed: 1, total: 2, title: 'Linear progress' } } });
    tree = app.render(); assert.equal(tree.props.value, 50);
    assert.match(tree.props.label, /1 \/ 2/);
    app.message({ action: 'debug:walkthrough', data: { revision: 3, run: false } });
    app.message({ action: 'debug:walkthrough', data: { revision: 2, run: { index: 2, completed: 1, total: 2 } } });
    assert.equal(app.render(), null, 'late progress must not restore a canceled run');
    app.message({ action: 'debug:open', data: { session: 3, catalog } });
    assert.ok(button(app.render(), 'Test All'));
});
