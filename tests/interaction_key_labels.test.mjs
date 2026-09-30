import { uiSource } from './ui_source.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

// Key glyphs shorten and split labels for display only; binding identity is untouched.
const context = vm.createContext({});
vm.runInContext(readFileSync(new URL('../ui/interaction-key.js', import.meta.url), 'utf8'), context);
const { parseKey, render } = context.CortexInteractionKey;
const text = parts => parts.map(part => part.type === 'text' ? part.text : part.type === 'plus' ? '+' : `<${part.button}>`).join(' ');
assert.equal(text(parseKey('NUMPAD5')), 'NUM 5');
assert.equal(text(parseKey('NUMPADENTER')), 'NUM \u21b5');
assert.equal(text(parseKey('numpad0')), 'NUM 0');
assert.equal(text(parseKey('G')), 'G');
assert.equal(text(parseKey('F10')), 'F10');
assert.equal(text(parseKey('DELETE')), 'DEL');
assert.equal(text(parseKey('BACKSPACE')), 'BKSP');
assert.equal(text(parseKey('SHIFT E')), 'SHIFT + E');
assert.equal(text(parseKey('LSHIFT+E')), 'SHIFT + E');
assert.equal(text(parseKey('MOUSE1')), '<LMB>');
assert.equal(text(parseKey('')), '?');

// One and two characters stay a disc; longer names, combos and mouse buttons become a pill.
const h = (tag, props, ...children) => ({ tag, props, children });
const glyph = key => render(h, { item: { key }, className: 'k', decorative: true });
assert.doesNotMatch(glyph('E').props.className, /is-pill/);
assert.match(glyph('F7').props.className, /is-dense/);
assert.match(glyph('MOUSE1').props.className, /^k( |$)/, 'a lone mouse button is a disc with the mouse silhouette');
for (const key of ['SHIFT E', 'BACKSPACE', 'SPACE', 'SHIFT MOUSE1']) {
    const node = glyph(key);
    assert.match(node.props.className, /is-pill/, key);
    assert.ok(Number(node.props.style['--cortex-key-span']) > 1, key);
    assert.match(node.children[0].props.viewBox, /^0 0 \d+ 48$/, key);
}

const panelSource = uiSource.match(/function normalizeInteractionPanel\([\s\S]*?\n}/)[0];
const normalizePanel = Function(`${panelSource}; return normalizeInteractionPanel;`)();
assert.equal(normalizePanel({ id: 'remote', label: 'Remote Spotlight', marker: 'A' }).panelMarker, 'A');
assert.equal(normalizePanel({ id: 'npc', label: 'STRANGER' }).panelMarker, '?');
assert.equal(normalizePanel({ id: 'remote', label: 'Remote Spotlight', marker: 'overflow' }).panelMarker, '?');

const React = { createElement: (type, props, ...children) => ({ type, props, children }) };
const panelComponent = uiSource.match(/function TargetInteractionPanel\([\s\S]*?\n}/)[0];
const TargetInteractionPanel = Function('React', 'InteractionKey', `${panelComponent}; return TargetInteractionPanel;`)(React, 'InteractionKey');
const tree = TargetInteractionPanel({ panel: { label: 'Remote Spotlight', marker: 'A' }, items: [
    { id: 'power', owner: 'arges', label: 'TOGGLE POWER', key: 'NUMPAD5' }
] });
const context2 = tree.children[2];
assert.equal(context2.children[0].children[0], 'Remote Spotlight');
assert.match(context2.children[0].props.className, /is-long/, 'the full title needs the compact context typography');
assert.equal(context2.children[1].props.item.key, 'A');
const action = tree.children[0].children[0][0].children[1];
assert.equal(action.type, 'InteractionKey', 'target actions share the prompt key glyph');
assert.equal(action.props.item.key, 'NUMPAD5', 'display shortening must not change binding identity');
