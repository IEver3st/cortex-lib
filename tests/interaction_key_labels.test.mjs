import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../ui/app.js', import.meta.url), 'utf8');
const formatter = source.match(/function formatInteractionKey\([\s\S]*?\n}/);
assert.ok(formatter, 'key labels need a compact presentation independent of their binding identity');
const formatInteractionKey = Function(`${formatter[0]}; return formatInteractionKey;`)();
assert.deepEqual(formatInteractionKey('NUMPAD5'), { prefix: 'NUM', label: '5' });
assert.deepEqual(formatInteractionKey('NUMPADENTER'), { prefix: 'NUM', label: '↵' });
assert.deepEqual(formatInteractionKey('numpad0'), { prefix: 'NUM', label: '0' });
assert.deepEqual(formatInteractionKey('G'), { prefix: '', label: 'G' });
assert.deepEqual(formatInteractionKey('F10'), { prefix: '', label: 'F10' });
assert.deepEqual(formatInteractionKey('DELETE'), { prefix: '', label: 'DEL' });

const panelSource = source.match(/function normalizeInteractionPanel\([\s\S]*?\n}/)[0];
const normalizePanel = Function(`${panelSource}; return normalizeInteractionPanel;`)();
assert.equal(normalizePanel({ id: 'remote', label: 'Remote Spotlight', marker: 'A' }).panelMarker, 'A');
assert.equal(normalizePanel({ id: 'npc', label: 'STRANGER' }).panelMarker, '?');
assert.equal(normalizePanel({ id: 'remote', label: 'Remote Spotlight', marker: 'overflow' }).panelMarker, '?');

const React = { createElement: (type, props, ...children) => ({ type, props, children }) };
const panelComponent = source.match(/function TargetInteractionPanel\([\s\S]*?\n}/)[0];
const TargetInteractionPanel = Function('React', 'InteractionKey', 'TargetInteractionKeyLabel',
    `${panelComponent}; return TargetInteractionPanel;`)(React, 'InteractionKey', 'TargetInteractionKeyLabel');
const tree = TargetInteractionPanel({ panel: { label: 'Remote Spotlight', marker: 'A' }, items: [
    { id: 'power', owner: 'arges', label: 'TOGGLE POWER', key: 'NUMPAD5' }
] });
const context = tree.children[2];
assert.equal(context.children[0].children[0], 'Remote Spotlight');
assert.match(context.children[0].props.className, /is-long/, 'the full title needs the compact context typography');
assert.equal(context.children[1].props.item.key, 'A');
const action = tree.children[0].children[0][0].children[1];
assert.equal(action.props['data-key'], 'NUMPAD5', 'display shortening must not change binding identity');
assert.equal(action.children[0].type, 'TargetInteractionKeyLabel');
assert.equal(action.children[0].props.value, 'NUMPAD5');
