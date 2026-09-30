import { uiSource, uiStyles } from './ui_source.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...segments) => readFileSync(path.join(testDir, '..', ...segments), 'utf8')
    .replace(/\r\n/g, '\n');

const styles = uiStyles + read('ui', 'interaction-key.css');
const sharedKey = read('ui', 'interaction-key.js');
const registry = read('imports', 'interaction', 'client.lua');
const renderer = read('client', 'interaction_renderer.lua');
const loader = read('init.lua');

const durationSource = uiSource.match(/function getInteractionHoldDuration\([\s\S]*?\n}/);
assert.ok(durationSource, 'hold duration normalizer must remain independently testable');
const getInteractionHoldDuration = Function(
    `${durationSource[0]}; return getInteractionHoldDuration;`
)();

assert.equal(getInteractionHoldDuration(100), 100);
assert.equal(getInteractionHoldDuration(1200.9), 1200);
assert.equal(getInteractionHoldDuration(600000), 600000);
assert.equal(getInteractionHoldDuration(99), null);
assert.equal(getInteractionHoldDuration(Infinity), null);

const clampSource = uiSource.match(/function clampInteractionNumber\([\s\S]*?\n}/);
const panelSource = uiSource.match(/function normalizeInteractionPanel\([\s\S]*?\n}/);
const itemsSource = uiSource.match(/function normalizeInteractionItems\([\s\S]*?\n}/);
assert.ok(clampSource && panelSource && itemsSource, 'interaction payload normalization must remain independently testable');
const worldLimitSource = uiSource.match(/const INTERACTION_WORLD_LIMIT = \d+;/);
assert.ok(worldLimitSource, 'the world item cap must remain statically discoverable');
const normalizeInteractionItems = Function(
    `${worldLimitSource[0]}; ${clampSource[0]}; ${durationSource[0]}; ${panelSource[0]}; ${itemsSource[0]}; return normalizeInteractionItems;`
)();

const screenItems = normalizeInteractionItems(Array.from({ length: 10 }, (_, index) => ({
    label: ` ACTION ${index} `,
    key: ' E ',
    panel: index < 2 ? { id: 'social-target', label: 'STRANGER', variant: 'target' } : null,
    holdDuration: index === 0 ? 1200.9 : null,
    holdActive: index === 0,
    holdRevision: index
})), false);
assert.equal(screenItems.length, 8);
assert.equal(screenItems[0].label, 'ACTION 0');
assert.equal(screenItems[0].key, 'E');
assert.equal(screenItems[0].holdDuration, null, 'screen interactions must ignore hold timing');
assert.equal(screenItems[0].holdActive, false);
assert.equal(screenItems[0].holdRevision, 0);
assert.deepEqual(
    {
        id: screenItems[0].panelId,
        label: screenItems[0].panelLabel,
        variant: screenItems[0].panelVariant
    },
    { id: 'social-target', label: 'STRANGER', variant: 'target' }
);

const panelKeySource = uiSource.match(/function getInteractionPanelKey\([\s\S]*?\n}/);
const blockSource = uiSource.match(/function buildInteractionBlocks\([\s\S]*?\n}/);
assert.ok(panelKeySource && blockSource, 'target-panel grouping must remain independently testable');
const buildInteractionBlocks = Function(
    `${panelKeySource[0]}; ${blockSource[0]}; return buildInteractionBlocks;`
)();
const blocks = buildInteractionBlocks(screenItems.slice(0, 3));
assert.equal(blocks.length, 2);
assert.equal(blocks[0].type, 'panel');
assert.equal(blocks[0].items.length, 2);
assert.equal(blocks[0].panel.label, 'STRANGER');
assert.equal(blocks[1].type, 'item');

const interleavedBlocks = buildInteractionBlocks([
    { owner: 'social', id: 'greet', panelId: 'target', panelLabel: 'STRANGER', panelVariant: 'target' },
    { owner: 'other', id: 'inspect' },
    { owner: 'social', id: 'taunt', panelId: 'target', panelLabel: 'STRANGER', panelVariant: 'target' }
]);
assert.equal(interleavedBlocks.length, 2, 'one explicit panel must stay grouped across other screen prompts');
assert.deepEqual(interleavedBlocks[0].items.map((item) => item.id), ['greet', 'taunt']);
assert.equal(interleavedBlocks[1].item.id, 'inspect');

const worldItems = normalizeInteractionItems([
    {
        label: 'DOOR', key: 'E', x: 2, y: -1, distance: 30,
        holdDuration: 1200.9, holdActive: true, holdRevision: 4
    },
    { label: 'INVALID', key: 'F' }
], true);
assert.equal(worldItems.length, 1);
assert.deepEqual(
    { x: worldItems[0].x, y: worldItems[0].y, distance: worldItems[0].distance },
    { x: 1, y: 0, distance: 25 }
);
assert.equal(worldItems[0].holdDuration, 1200);
assert.equal(worldItems[0].holdActive, true);
assert.equal(worldItems[0].holdRevision, 4);
assert.equal(worldItems[0].tier, 'prompt', 'items without a tier are full prompts (older renderers)');
assert.equal(worldItems[0].active, true, 'items without an active flag own their key');
assert.equal(worldItems[0].group, null);

// Two-tier protocol: markers carry no label/key, lists share a group.
const tiered = normalizeInteractionItems([
    { tier: 'marker', id: 'far', owner: 'x', x: 0.4, y: 0.4, fade: 3, label: 'LEAK', key: 'E', holdActive: true },
    { tier: 'prompt', id: 'a', owner: 'x', label: 'A', key: 'E', x: 0.5, y: 0.5, group: 'x:a', selected: true, active: true, focused: true },
    { tier: 'prompt', id: 'b', owner: 'x', label: 'B', key: 'E', x: 0.5, y: 0.5, group: 'x:a', active: false },
    { tier: 'marker', x: 'bad', y: 0.1 }
], true);
assert.equal(tiered.length, 3, 'malformed markers are dropped');
assert.deepEqual([tiered[0].tier, tiered[0].label, tiered[0].key, tiered[0].fade, tiered[0].holdActive], ['marker', '', '', 1, false],
    'markers are bounded and never forward labels, keys or hold state');
assert.deepEqual([tiered[1].group, tiered[1].selected, tiered[1].active, tiered[1].focused], ['x:a', true, true, true]);
assert.deepEqual([tiered[2].selected, tiered[2].active, tiered[2].focused], [false, false, false]);
const manyWorld = normalizeInteractionItems(Array.from({ length: 40 }, (_, i) => ({ tier: 'marker', id: `m${i}`, x: 0.5, y: 0.5 })), true);
assert.equal(manyWorld.length, 16, 'the world frame is capped at the registry total');

const keyComponent = uiSource.match(/function InteractionKey\([\s\S]*?\n}\n\nfunction getVehicleAccessPresentation/);
assert.ok(keyComponent, 'the shared interaction key component must remain discoverable');
assert.match(keyComponent[0], /CortexInteractionKey\.render\(React\.createElement, props\)/);
assert.match(sharedKey, /cortex-interaction-key-ring-track/);
assert.match(sharedKey, /cortex-interaction-key-ring-progress/);
assert.match(sharedKey, /pathLength: '100'/);
assert.match(sharedKey, /decorative = false/);
assert.match(sharedKey, /'aria-hidden': decorative \? 'true' : undefined/);
const screenPrompts = uiSource.match(/function InteractionPrompts\([\s\S]*?\n}\n/);
assert.ok(screenPrompts, 'screen interaction prompts must remain independently inspectable');
assert.doesNotMatch(screenPrompts[0], /`Hold \$\{/, 'screen prompts must communicate a key press');
assert.match(screenPrompts[0], /`Press \$\{block\.item\.key\}/);

const worldPrompts = uiSource.match(/function worldActionText\([\s\S]*?\n}\n/);
assert.ok(worldPrompts, 'world interaction prompts must remain independently inspectable');
assert.match(worldPrompts[0], /`Hold \$\{item\.key\}/, 'world holds need an accessible instruction');

const targetPanel = uiSource.match(/function TargetInteractionPanel\([\s\S]*?\n}\n/);
assert.ok(targetPanel, 'the shared target-panel component must remain discoverable');
for (const className of [
    'cortex-target-divider',
    'cortex-target-context-label',
    'cortex-target-marker'
]) {
    assert.match(targetPanel[0], new RegExp(className));
}
assert.match(
    targetPanel[0],
    /React\.createElement\(InteractionKey, \{\s*item,\s*className: 'cortex-interaction-key'/,
    'target actions use the same key glyph as every other prompt'
);

// One anatomy: every prompt size derives from --ix (= --u x prompt size).
assert.match(styles, /\.cortex-interactions,\s*\.cortex-world-interactions\s*\{[^}]*--ix:\s*calc\(var\(--u\) \* var\(--cx-prompt-scale, 1\)\);/,
    'screen and world prompts scale together with the player prompt size');
assert.match(styles, /\.cortex-interaction-key,\s*\.cortex-target-marker,\s*\.cortex-world-interaction-key\s*\{[^}]*width:\s*calc\(44 \* var\(--ix\)\);[^}]*height:\s*calc\(44 \* var\(--ix\)\);/,
    'screen, target and world discs share one 44ix footprint');
assert.match(styles, /\.cortex-target-panel\s*\{[^}]*width:\s*calc\(300 \* var\(--ix\)\);/);
assert.match(
    styles,
    /\.cortex-target-action-label,\s*\.cortex-target-context-label\s*\{[\s\S]*?box-sizing:\s*border-box;[\s\S]*?max-width:\s*100%;/,
    'target-panel labels must shrink inside their reserved grid column'
);
assert.match(styles, /\.cortex-interaction-label,\s*\.cortex-target-action-label,\s*\.cortex-target-context-label,\s*\.cx-wp-label\s*\{[^}]*overflow:\s*hidden;[^}]*text-overflow:\s*ellipsis;/,
    'every prompt label clips with an ellipsis');
assert.match(styles, /\.is-pill:not\(\.cortex-key-inline\)\s*\{[^}]*aspect-ratio:\s*var\(--cortex-key-span, 1\);/,
    'long keys grow into a pill of the same height instead of overflowing the disc');
assert.match(styles, /\.cortex-target-divider\s*\{[^}]*height:\s*calc\(4 \* var\(--ix\)\);[^}]*background:\s*var\(--paper\);/,
    'the target divider is a >= 3u paper rule');
assert.match(
    targetPanel[0],
    /React\.createElement\(InteractionKey,\s*\{[\s\S]*?item:\s*\{\s*key:\s*panel\.marker \|\| '\?'\s*\},[\s\S]*?className:\s*'cortex-target-marker',[\s\S]*?decorative:\s*true/,
    'the STRANGER marker must render a question mark through the shared key geometry'
);
assert.match(styles, /\.cortex-target-action,\s*\.cortex-target-context\s*\{[^}]*display:\s*flex;[^}]*justify-content:\s*flex-end;/,
    'target rows end on the shared key edge like screen prompts');
// Rings stay >= 3u: stroke 4 of a 48 viewBox at 44ix is 3.67ix (3.2u at small).
assert.match(styles, /--cortex-interaction-ring-stroke:\s*4;/);
assert.match(styles, /stroke-width:\s*var\(--cortex-interaction-ring-stroke, 3\);/,
    'external consumers of interaction-key.css keep the default ring');
assert.match(
    styles,
    /\.cortex-interaction-key-value\s*{[\s\S]*?inset:\s*16%;/,
    'the key disc keeps its inset from the outer ring'
);
// Markers: a 22ix ring with a 10ix dot; growth only animates transform/opacity.
assert.match(styles, /\.cx-wp-marker\s*\{[^}]*width:\s*calc\(22 \* var\(--ix\)\);[^}]*inset 0 0 0 calc\(3\.5 \* var\(--ix\)\) var\(--paper\)/);
assert.match(styles, /\.cx-wp-marker::after\s*\{[^}]*width:\s*calc\(10 \* var\(--ix\)\);/);
assert.match(styles, /\.cx-wp\.is-list \.cx-wp-pip::before\s*\{[^}]*width:\s*calc\(4 \* var\(--ix\)\);/, 'the rail is 4ix');
// Screen prompts stack above the help legend.
assert.match(styles, /\.cortex-interactions\s*\{[^}]*var\(--cx-help-legend-height, 0px\)/,
    'screen prompts lift above the bottom-right help legend');
const interactionStyles = read('ui', 'surfaces', 'interactions.css');
assert.doesNotMatch(interactionStyles, /-gradient\(|backdrop-filter|\d+px \*|--cortex-ui-scale/,
    'no gradients, blur or legacy px scaling in the interaction surface');

assert.match(styles, /@keyframes cortex-interaction-hold[\s\S]*?stroke-dashoffset:\s*0/);
assert.match(styles, /animation:\s*cortex-interaction-hold var\(--cortex-interaction-hold-duration, 1000ms\) linear forwards/);
assert.match(
    styles,
    /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.cortex-interaction-key-ring-progress[\s\S]*?steps\(20, end\)/,
    'reduced-motion users must retain time feedback without a continuously sweeping ring'
);

for (const source of [registry, renderer, uiSource]) {
    assert.match(source, /holdDuration/, 'hold duration must cross every registry-renderer-NUI boundary');
    assert.match(source, /holdActive/, 'hold state must cross every registry-renderer-NUI boundary');
}
assert.match(registry, /panel is only supported for screen interactions/);
assert.match(registry, /holdDuration is only supported for anchored interactions/);
assert.match(registry, /screen interactions are press-only/);
assert.match(renderer, /panel = type\(panel\) == ['"]table['"]/);
assert.match(renderer, /frameItem = copyPresentationItem\(item, true\)/);

assert.match(registry, /exports\('startInteractionHold', startInteractionHold\)/);
assert.match(registry, /exports\('cancelInteractionHold', cancelInteractionHold\)/);
assert.match(registry, /exports\('getInteractionState', getInteractionState\)/);
assert.match(registry, /exports\('isInteractionVisible', isInteractionVisible\)/);
assert.match(registry, /anchorType ~= ['"]entity['"]/);
assert.match(renderer, /anchor\.type ~= ['"]entity['"]/);
assert.match(renderer, /descriptor\.expectedModel/);
assert.match(renderer, /_setInteractionPresentationState/);
assert.match(loader, /function lib\.startInteractionHold\(id\)/);
assert.match(loader, /function lib\.cancelInteractionHold\(id\)/);
assert.match(loader, /function lib\.getInteractionState\(id\)/);
assert.match(loader, /function lib\.isInteractionVisible\(id\)/);
assert.match(uiSource, /const announceInteractionReady = async \(attempt = 0\)/);
assert.match(uiSource, /payload\?\.ok === true/);
assert.match(uiSource, /setTimeout\(\(\) => announceInteractionReady\(attempt \+ 1\), retryDelay\)/);
assert.match(uiSource, /activeController\?\.abort\(\)/, 'ready retry must be torn down with the NUI app');

console.log('interaction UI contract: PASS');
