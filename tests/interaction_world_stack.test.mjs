import { uiSource, uiStyles } from './ui_source.mjs';
import assert from 'node:assert/strict';

const source = uiSource;
const styles = uiStyles;
const pick = (name) => {
    const match = source.match(new RegExp(`function ${name}\\([\\s\\S]*?\\n}\\n`));
    assert.ok(match, `${name} must remain independently testable`);
    return match[0];
};
const constants = ['INTERACTION_LIST_VISIBLE_ROWS', 'INTERACTION_FLIP_X']
    .map((name) => source.match(new RegExp(`const ${name} = [^;]+;`))[0]).join('\n');
const vehicleActions = source.match(/const VEHICLE_ACCESS_ACTIONS = Object\.freeze\(\{[\s\S]*?\n\}\);/)[0];

// A tiny synchronous renderer: expands function components into a plain tree.
const React = { createElement: (type, props, ...children) => ({ type, props: props || {}, children }) };
const expand = (node) => {
    if (Array.isArray(node)) return node.map(expand);
    if (!node || typeof node !== 'object') return node;
    if (typeof node.type === 'function') return expand(node.type({ ...node.props, children: node.children }));
    return { ...node, children: node.children.map(expand) };
};
const flat = (node, out = []) => {
    if (Array.isArray(node)) node.forEach((child) => flat(child, out));
    else if (node && typeof node === 'object') { out.push(node); flat(node.children, out); }
    return out;
};
const byClass = (tree, name) => flat(tree).filter((node) => typeof node.props?.className === 'string'
    && node.props.className.split(' ').includes(name));
const text = (node) => flat(node).flatMap((child) => child.children.filter((value) => typeof value === 'string')).join('');

const window = {
    CortexSkillChecks: { WorldKey: ({ item, fallback }) => fallback },
    CortexKit: { ControlsLegend: (props) => ({ type: 'legend', props, children: [] }) },
    CortexInteractionKey: { render: (h, props) => h('span', { className: props.className, 'data-key': props.item.key }) }
};
const api = Function('React', 'window', `
    ${constants}
    ${vehicleActions}
    ${pick('clampInteractionNumber')}
    ${pick('InteractionKey')}
    ${pick('getVehicleAccessPresentation')}
    ${pick('VehicleAccessIcon')}
    ${pick('buildWorldInteractionGroups')}
    ${pick('getInteractionListWindow')}
    ${pick('worldActionText')}
    ${pick('WorldPromptRow')}
    ${pick('WorldPromptGroup')}
    ${pick('WorldInteractionPrompts')}
    return { buildWorldInteractionGroups, getInteractionListWindow, WorldInteractionPrompts };
`)(React, window);
const render = (items) => expand(api.WorldInteractionPrompts({ items }));

// Window: four rows, keeping one row below the selection when possible.
assert.deepEqual(api.getInteractionListWindow(3, 2), { start: 0, end: 3 });
assert.deepEqual(api.getInteractionListWindow(8, 0), { start: 0, end: 4 });
assert.deepEqual(api.getInteractionListWindow(8, 3), { start: 1, end: 5 });
assert.deepEqual(api.getInteractionListWindow(8, 7), { start: 4, end: 8 });

// Grouping: `group` wins; without it (older renderer) an exact anchor stacks.
const row = (id, key, more = {}) => ({ owner: 'lab', id, key, label: id.toUpperCase(), x: 0.3, y: 0.4, distance: 1, tier: 'prompt', active: true, ...more });
const legacy = api.buildWorldInteractionGroups([row('take', 'E'), row('kick', 'G'), row('far', 'H', { x: 0.8 })]);
assert.equal(legacy.length, 2, 'rows at one exact anchor share a list');
assert.deepEqual(legacy[0].rows.map((item) => item.id), ['take', 'kick']);
const grouped = api.buildWorldInteractionGroups([
    row('a', 'E', { group: 'lab:a' }), { owner: 'lab', id: 'm', tier: 'marker', x: 0.1, y: 0.1, fade: 0.5 },
    row('b', 'E', { group: 'lab:a', x: 0.31 })
]);
assert.equal(grouped.length, 2);
assert.equal(grouped[0].key, 'lab:a', 'a list is keyed by its head so a marker grows into it');
assert.equal(grouped[1].key, 'lab:m');
assert.equal(grouped[1].marker, true);

// A five-row same-key list: selected disc, dots, a faded peek row; no hint under it.
const fridge = ['logger', 'lavazas', 'berry', 'green', 'shake'].map((id, index) => row(id, 'E', {
    group: 'lab:logger', selected: index === 1, active: index === 1, focused: true
}));
let tree = render(fridge);
const list = byClass(tree, 'cx-wp')[0];
assert.match(list.props.className, /is-prompt/);
assert.match(list.props.className, /is-list/);
assert.match(list.props.className, /has-more-below/, 'hidden rows fade out below');
const rows = byClass(tree, 'cx-wp-row');
assert.equal(rows.length, 5, 'four rows plus one peek row');
assert.match(rows[1].props.className, /is-selected/);
assert.match(rows[4].props.className, /is-peek/);
assert.equal(byClass(rows[1], 'cortex-world-interaction-key').length, 1, 'the selected row has the full disc');
assert.equal(byClass(rows[0], 'cx-wp-dot').length, 1, 'rows sharing the selected key show a dot');
assert.equal(byClass(tree, 'cx-wp-hint').length, 0, 'the wheel hint lives bottom-right, never under the list');
assert.match(source, /listHint: latestWorldItemsRef\.current\.some\(\(item\) => item\.focused === true && item\.tier !== 'marker'\)/,
    'a focused list shows its WHEEL hint in the bottom-right prompt column');
assert.match(source, /item: \{ key: 'WHEEL' \},\s*className: 'cortex-interaction-key'/, 'the hint uses the shared key glyph');
assert.ok(text(rows[1]).includes('LAVAZAS'));

// Mixed keys: unique-key rows keep a small disc; no focus, no hint.
tree = render([row('take', 'E', { group: 'lab:t', selected: true }), row('drink', 'E', { group: 'lab:t', active: false }),
    row('inspect', 'G', { group: 'lab:t', holdDuration: 1000, holdActive: true, holdRevision: 3 })]);
const mixed = byClass(tree, 'cx-wp-row');
assert.equal(byClass(mixed[1], 'cx-wp-dot').length, 1);
const small = byClass(mixed[2], 'is-small');
assert.equal(small.length, 1, 'a unique-key row keeps its own small disc');
assert.equal(small[0].props['data-key'], 'G');
assert.equal(byClass(tree, 'cx-wp-hint').length, 0, 'nothing to choose: no wheel hint');

// Single prompt: one row, no rail class; markers carry no label.
tree = render([row('door', 'E', { group: 'lab:door', selected: true })]);
assert.doesNotMatch(byClass(tree, 'cx-wp')[0].props.className, /is-list/);
tree = render([{ owner: 'lab', id: 'far', tier: 'marker', x: 0.5, y: 0.5, fade: 0.2 }]);
assert.match(byClass(tree, 'cx-wp')[0].props.className, /is-marker/);
assert.equal(byClass(tree, 'cx-wp-marker').length, 1);
assert.equal(byClass(tree, 'cx-wp-label').length, 0, 'markers never show a label');
assert.equal(render([]), null, 'clearing prompts removes the layer');

// Vehicle access rows keep their icon and fixed order inside the list.
tree = render([
    row('vehicle-smash-window', 'G', { owner: 'cortex-hud', group: 'cortex-hud:vehicle-smash-window', selected: true }),
    row('vehicle-clone-key', 'E', { owner: 'cortex-hud', group: 'cortex-hud:vehicle-smash-window' })
]);
const access = byClass(tree, 'cortex-world-access-row');
assert.deepEqual(access.map((node) => node.props.className.match(/is-(clone-key|smash-window)/)[1]), ['clone-key', 'smash-window']);
assert.equal(byClass(tree, 'cx-wp-icon').length, 2);

// Right edge: labels flip to the left of the rail.
tree = render([row('edge', 'E', { x: 0.9, group: 'lab:edge', selected: true })]);
assert.match(byClass(tree, 'cx-wp')[0].props.className, /is-flipped/);

assert.match(styles, /\.cx-wp\s*\{[^}]*transform:\s*translate3d\(var\(--wx, 50vw\), var\(--wy, 50vh\), 0\) scale\(var\(--wscale, 1\)\);/,
    'world groups move with transform only');
assert.match(styles, /\.cx-wp-row\s*\{[^}]*position:\s*relative;[^}]*display:\s*flex;/,
    'rows participate in layout instead of overlapping at a fixed coordinate');
console.log('world interaction lists: PASS');
