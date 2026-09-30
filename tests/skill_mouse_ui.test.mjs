import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../ui/skill-checks.js', import.meta.url), 'utf8');
const engineSource = readFileSync(new URL('../ui/skill-engine.js', import.meta.url), 'utf8');

export function skillFixture(config, progress = 0) {
    const handlers = new Map();
    const posts = [];
    const timers = [];
    const stub = name => props => ({ type: name, props: props || {}, children: props?.children ? [props.children] : [] });
    // Kit stubs are host-like nodes so tests can assert which primitive was used.
    const window = {
        addEventListener: (name, fn) => handlers.set(name, fn),
        CortexKit: { Keycap: stub('Keycap'), KeyHint: stub('KeyHint'), Ring: stub('Ring') }
    };
    vm.runInNewContext(engineSource, { window });
    const React = {
        createElement: (type, props, ...children) => ({ type, children,
            props: typeof type === 'function' && children.length ? { ...props, children: children.length === 1 ? children[0] : children } : props || {} }),
        useState: value => [value, () => {}], useEffect() {}, useRef: value => ({ current: value })
    };
    vm.runInNewContext(source, { window, React, performance: { now: () => 0 }, document: {},
        setTimeout: fn => { timers.push(fn); return timers.length; }, clearTimeout() {},
        requestAnimationFrame: () => 1, cancelAnimationFrame() {},
        nuiPost: async (name, data) => { posts.push({ url: `https://cortex-lib/${name}`, data }); return { ok: true }; } });
    const message = (action, data) => handlers.get('message')({ data: { action, data } });
    message('skill:open', { session: 7, owner: 'consumer', config });
    message('skill:start', { session: 7 });
    if (config.type === 'trace') message('skill:trace', { session: 7, progress });
    function expand(node) {
        if (!node || typeof node !== 'object') return node;
        if (typeof node.type === 'function') return expand(node.type(node.props));
        if (typeof node.type === 'string' && /^[A-Z]/.test(node.type)) return { ...node, children: (node.children || []).flat(Infinity).map(expand) };
        return { ...node, children: node.children.flat(Infinity).map(expand) };
    }
    return { render: () => expand(window.CortexSkillChecks.Surface()), message, posts, flush: () => timers.splice(0).forEach(fn => fn()) };
}
const trace = direction => ({ type: 'trace', direction, label: 'Turn the lock', duration: 10000 });
const nodes = tree => !tree || typeof tree !== 'object' ? [] : [tree, ...tree.children.flatMap(nodes)];
const byClass = (tree, name) => nodes(tree).filter(n => typeof n.props.className === 'string' && n.props.className.split(' ').includes(name));

test('trace slip is passive, consumes native knob progress only, and uses the kit', () => {
    const fixture = skillFixture(trace('lower'), .5);
    const tree = fixture.render();
    assert.equal(tree.type, 'section');
    assert.match(tree.props.className, /skill-slip skill-trace is-ready/);
    const bar = nodes(tree).find(n => n.props.role === 'progressbar');
    assert.equal(bar.props['aria-valuenow'], 50);
    for (const node of nodes(tree)) {
        assert.equal(Object.keys(node.props).some(key => /^on(Pointer|Mouse|Click)/.test(key)), false, 'no pointer handlers');
    }
    assert.equal(nodes(tree).filter(n => n.type === 'svg').length >= 1, true);
    assert.equal(nodes(tree).some(n => n.type === 'KeyHint' && n.props.keys === 'ESC'), true, 'Escape hint via CortexKit');
    assert.equal(fixture.posts.length, 1);
    assert.match(fixture.posts[0].url, /skillReady$/);
    fixture.message('skill:trace', { session: 6, progress: 1 });
    assert.equal(nodes(fixture.render()).find(n => n.props.role === 'progressbar').props['aria-valuenow'], 50, 'stale snapshots are ignored');
});

test('half ring runs 3 -> 9 o\'clock with the knob on the arc for each direction', () => {
    for (const direction of ['upper', 'lower']) {
        const tree = skillFixture(trace(direction), .5).render();
        const fill = byClass(tree, 'skill-arc-fill')[0];
        const cy = direction === 'upper' ? 96 : 20;
        assert.equal(fill.props.d, `M 172 ${cy} A 72 72 0 0 ${direction === 'upper' ? 0 : 1} 28 ${cy}`);
        assert.equal(fill.props.strokeDasharray, '0.5 1');
        const knob = byClass(tree, 'skill-arc-knob')[0];
        assert.ok(Math.abs(knob.props.cx - 100) < 1e-9, 'half-way knob sits at the apex');
        assert.ok(Math.abs(knob.props.cy - (direction === 'upper' ? cy - 72 : cy + 72)) < 1e-9);
    }
});

test('close shows a brief outcome slip tag, then leaves', () => {
    const fixture = skillFixture(trace('upper'), .9);
    fixture.message('skill:close', { session: 7, success: true, reason: 'success' });
    const tag = byClass(fixture.render(), 'skill-tag-state')[0];
    assert.equal(tag.children[0], 'Clear');
    fixture.message('skill:trace', { session: 7, progress: .1 });
    assert.equal(nodes(fixture.render()).find(n => n.props.role === 'progressbar').props['aria-valuenow'], 90, 'no updates after close');
    fixture.flush();
    assert.equal(fixture.render(), null);
    const missed = skillFixture({ type: 'radial', label: 'Set', key: 'E', duration: 10000, speed: .5, targetStart: .5, targetSize: .2 });
    missed.message('skill:close', { session: 7, success: false, reason: 'missed' });
    const outcome = byClass(missed.render(), 'skill-outcome')[0];
    assert.match(outcome.props.className, /is-failed/);
});

test('keyboard checks render keycaps, target paper and the mint marker', () => {
    const radial = skillFixture({ type: 'radial', label: 'Set', key: 'E', duration: 10000, speed: .5, targetStart: .5, targetSize: .2 }).render();
    assert.equal(byClass(radial, 'skill-target-arc').length, 1);
    assert.equal(byClass(radial, 'skill-marker').length, 1);
    assert.equal(nodes(radial).some(n => n.type === 'Keycap' && n.props.value === 'E'), true);
    const sequence = skillFixture({ type: 'sequence', label: 'Seq', key: 'E', keys: ['E', 'R', 'Q'], duration: 10000 }).render();
    assert.equal(nodes(sequence).filter(n => n.type === 'Keycap').length, 3);
    assert.equal(byClass(sequence, 'skill-meta')[0].children[0], '0/3');
    const hold = skillFixture({ type: 'hold', label: 'Hold', key: 'SPACE', duration: 10000, speed: .5, targetStart: .5, targetSize: .2 }).render();
    assert.equal(byClass(hold, 'skill-zone').length, 1);
    assert.equal(byClass(hold, 'skill-cursor').length, 1);
});

test('mash renders only on the world key and closes without an outcome tag', () => {
    const fixture = skillFixture({ type: 'mash', label: 'Mash', key: 'R', interactionId: 'pump', decay: .2, duration: 10000 });
    assert.equal(fixture.render(), null, 'no screen slip for mash');
    fixture.message('skill:close', { session: 7, success: true, reason: 'success' });
    assert.equal(fixture.render(), null);
});
