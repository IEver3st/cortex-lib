import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...segments) => readFileSync(path.join(testDir, '..', ...segments), 'utf8')
    .replace(/\r\n/g, '\n');

const uiSource = read('ui', 'app.js');
const styles = read('ui', 'style.css');
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
const normalizeInteractionItems = Function(
    `${clampSource[0]}; ${durationSource[0]}; ${panelSource[0]}; ${itemsSource[0]}; return normalizeInteractionItems;`
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

const keyComponent = uiSource.match(/function InteractionKey\([\s\S]*?\n}\n\nfunction getVehicleAccessPresentation/);
assert.ok(keyComponent, 'the shared interaction key component must remain discoverable');
assert.match(keyComponent[0], /cortex-interaction-key-ring-track/);
assert.match(keyComponent[0], /cortex-interaction-key-ring-progress/);
assert.match(keyComponent[0], /pathLength: '100'/);
assert.match(keyComponent[0], /decorative = false/);
assert.match(keyComponent[0], /'aria-hidden': decorative \? 'true' : undefined/);
const screenPrompts = uiSource.match(/function InteractionPrompts\([\s\S]*?\n}\n\nfunction WorldInteractionPrompts/);
assert.ok(screenPrompts, 'screen interaction prompts must remain independently inspectable');
assert.doesNotMatch(screenPrompts[0], /`Hold \$\{/, 'screen prompts must communicate a key press');
assert.match(screenPrompts[0], /`Press \$\{block\.item\.key\}/);

const worldPrompts = uiSource.match(/function WorldInteractionPrompts\([\s\S]*?\n}\n\nconst INTERACTION_BASE_FIELDS/);
assert.ok(worldPrompts, 'world interaction prompts must remain independently inspectable');
assert.match(worldPrompts[0], /`Hold \$\{item\.key\}/, 'world holds need an accessible instruction');

const targetPanel = uiSource.match(/function TargetInteractionPanel\([\s\S]*?\n}\n\nfunction InteractionPrompts/);
assert.ok(targetPanel, 'the shared target-panel component must remain discoverable');
for (const className of [
    'cortex-target-action-dot',
    'cortex-target-divider',
    'cortex-target-context-label',
    'cortex-target-marker'
]) {
    assert.match(targetPanel[0], new RegExp(className));
}
assert.match(
    targetPanel[0],
    /className: 'cortex-target-action-dot'[\s\S]*?}, item\.key\)/,
    'the caller-provided interaction key must be visible inside each action disc'
);

assert.match(
    styles,
    /\.cortex-target-panel\s*\{[\s\S]*?width:\s*calc\(278px \* var\(--cortex-interaction-scale, 1\)\);/,
    'the target panel must retain the reference-matched width'
);
assert.match(
    styles,
    /\.cortex-target-action-label,\s*\.cortex-target-context-label\s*\{[\s\S]*?box-sizing:\s*border-box;[\s\S]*?min-width:\s*0;[\s\S]*?max-width:\s*100%;[\s\S]*?overflow:\s*hidden;[\s\S]*?text-overflow:\s*ellipsis;/,
    'target-panel labels must shrink and clip inside their reserved grid column'
);
assert.match(
    styles,
    /\.cortex-target-action-dot\s*\{[\s\S]*?width:\s*calc\(42px \* var\(--cortex-interaction-scale, 1\)\);[\s\S]*?height:\s*calc\(42px \* var\(--cortex-interaction-scale, 1\)\);[\s\S]*?background:\s*var\(--hud-interaction\);[\s\S]*?color:\s*var\(--cortex-black\);/,
    'target actions must use labeled white key discs'
);
assert.match(
    styles,
    /\.cortex-target-divider\s*\{[\s\S]*?height:\s*calc\(3px \* var\(--cortex-interaction-scale, 1\)\);[\s\S]*?background:\s*var\(--hud-interaction\);/,
    'the target context must keep its full white divider'
);
assert.match(
    targetPanel[0],
    /React\.createElement\(InteractionKey,\s*\{[\s\S]*?className:\s*'cortex-target-marker',[\s\S]*?decorative:\s*true/,
    'the STRANGER marker must reuse the shared radial key geometry'
);
assert.match(
    styles,
    /\.cortex-target-context\s*\{[\s\S]*?--cortex-target-marker-size:\s*calc\(43\.2px \* var\(--cortex-ui-scale\)\);[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\) var\(--cortex-target-marker-size\);[\s\S]*?min-height:\s*var\(--cortex-target-marker-size\);/,
    'the STRANGER row must reserve the world-scaled marker footprint'
);
assert.match(
    styles,
    /\.cortex-target-marker\s*\{[\s\S]*?width:\s*var\(--cortex-target-marker-size\);[\s\S]*?height:\s*var\(--cortex-target-marker-size\);/,
    'the STRANGER marker must consume the reserved world-scaled footprint'
);
assert.match(
    styles,
    /\.cortex-interaction-key,\s*\.cortex-target-marker,\s*\.cortex-world-interaction-key,/,
    'the STRANGER marker must inherit the shared radial key layout'
);

assert.match(
    styles,
    /\.cortex-world-interaction-key\s*{[\s\S]*?width:\s*calc\(54px \* var\(--cortex-ui-scale\)\);[\s\S]*?height:\s*calc\(54px \* var\(--cortex-ui-scale\)\);/,
    'the world prompt must reserve the larger outer-ring footprint'
);

const interactionScale = Number(uiSource.match(/const INTERACTION_UI_SCALE = ([\d.]+);/)?.[1]);
const targetMarkerDiameter = Number(styles.match(/--cortex-target-marker-size:\s*calc\(([\d.]+)px/)?.[1]);
const worldMarkerDiameter = Number(styles.match(/\.cortex-world-interaction-key\s*\{[\s\S]*?width:\s*calc\(([\d.]+)px/)?.[1]);
assert.ok(
    [interactionScale, targetMarkerDiameter, worldMarkerDiameter].every(Number.isFinite),
    'the interaction scale and radial diameters must remain statically discoverable'
);
assert.equal(
    targetMarkerDiameter,
    worldMarkerDiameter * interactionScale,
    'the target marker diameter must equal the correct world ring at the shared reference scale'
);
assert.match(
    styles,
    /\.cortex-interaction-key-value\s*{[\s\S]*?inset:\s*16%;[\s\S]*?background:\s*var\(--text-primary\);/,
    'the key disc must keep the reduced gap from the thin outer ring'
);

const outerTrackInnerRadius = 21.5 - (3 / 2);
const previousDiscRadius = 24 * (1 - (2 * 0.235));
const reducedDiscRadius = 24 * (1 - (2 * 0.16));
const previousGap = outerTrackInnerRadius - previousDiscRadius;
const reducedGap = outerTrackInnerRadius - reducedDiscRadius;
assert.ok(
    Math.abs((reducedGap / previousGap) - 0.5) < 0.02,
    'the radial gap between the key disc and outer track must be half its previous size'
);

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
assert.match(registry, /holdDuration is only supported for world interactions/);
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
