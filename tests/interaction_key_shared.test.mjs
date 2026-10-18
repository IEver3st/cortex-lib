import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const context = vm.createContext({});
vm.runInContext(readFileSync(new URL('../ui/interaction-key.js', import.meta.url), 'utf8'), context);
const { render, mount } = context.CortexInteractionKey;
const h = (tag, props, ...children) => ({ tag, props, children: children.filter(Boolean) });
const data = (active = false, revision = 0) => ({
    item: { key: 'R', holdDuration: 2000, holdActive: active, holdRevision: revision },
    className: 'cortex-key-inline', decorative: true,
});

test('React and inline consumers share ring geometry, active fill and key text', () => {
    const idle = render(h, data());
    assert.equal(idle.children[0].children.length, 1);
    const active = render(h, data(true, 1));
    const [track, fill] = active.children[0].children;
    assert.match(track.props.d, /^M24 2H24A22 22 0 0 1 24 46H24A22 22 0 0 1 24 2Z$/, 'a one-letter key is a disc ring starting at the top');
    assert.equal(track.props.d, fill.props.d);
    assert.equal(fill.props.pathLength, '100');
    assert.equal(active.props.style['--cortex-interaction-hold-duration'], '2000ms');
    assert.equal(active.children[1].children[0].children[0], 'R');
    assert.equal(active.props['aria-hidden'], 'true');
});

test('inline ring survives unrelated updates and resets on cancel, repress and teardown', () => {
    const document = {
        createElement(tag) { return { tag, attributes: {}, children: [], style: { setProperty() {} },
            setAttribute(name, value) { this.attributes[name] = value; },
            appendChild(child) { this.children.push(child); } }; },
        createElementNS(_, tag) { return this.createElement(tag); },
        createTextNode(text) { return { text }; },
    };
    const node = { ownerDocument: document, children: [], replaceChildren(...children) { this.children = children; } };
    const action = mount(node, data(true, 1));
    const original = node.children[0];
    action.update(data(true, 1));
    assert.equal(node.children[0], original, 'a countdown tick must not restart the animation');
    action.update(data(false, 1));
    assert.equal(node.children[0].children[0].children.length, 1, 'release removes fill immediately');
    action.update(data(true, 2));
    assert.equal(node.children[0].children[0].children.length, 2);
    assert.notEqual(node.children[0], original);
    action.destroy();
    assert.equal(node.children.length, 0);
});

test('an opposite arrow pair is one axis glyph in a disc, not a combo pill', () => {
    const glyph = key => render(h, { item: { key }, className: 'cortex-key-inline', decorative: true });
    for (const [key, axis] of [['← →', 'h'], ['LEFT RIGHT', 'h'], ['↑ ↓', 'v'], ['↕', 'v']]) {
        const node = glyph(key);
        assert.doesNotMatch(node.props.className, /is-pill/, `${key} stays a disc`);
        const [part] = node.children[1].children;
        assert.match(part.props.className, /is-axis/);
        assert.match(part.children[0].props.className, new RegExp(`is-${axis}$`));
    }
    assert.match(glyph('SHIFT E').props.className, /is-pill/, 'real combos keep the pill');
    assert.equal(glyph('←').children[1].children[0].children[0], '←', 'a single arrow stays text');
});
