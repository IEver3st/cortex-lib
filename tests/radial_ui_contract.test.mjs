import { uiSource, uiStyles } from './ui_source.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import vm from 'node:vm';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const styles = uiStyles;
const clientSource = readFileSync(
    path.join(testDir, '..', 'imports', 'radial', 'client.lua'),
    'utf8'
).replace(/\r\n/g, '\n');
const radialSource = readFileSync(path.join(testDir, '..', 'ui', 'surfaces', 'radial.js'), 'utf8').replace(/\r\n/g, '\n');
const radialStyles = readFileSync(path.join(testDir, '..', 'ui', 'surfaces', 'radial.css'), 'utf8').replace(/\r\n/g, '\n');

const radialMatch = uiSource.match(/function RadialMenu\([\s\S]*?\n}\n/);
assert.ok(radialMatch, 'RadialMenu must remain discoverable by the UI regression test');
const radial = radialMatch[0];

// Geometry: the pointer is measured against the rendered SVG, never the overlay.
assert.match(radial, /const radialSvgRef = useRef\(null\)/, 'radial pointer geometry must own a ref to the rendered SVG');
assert.match(uiSource, /function getRadialPointer[\s\S]*?element\.getBoundingClientRect\(\)/,
    'radial pointer geometry must measure the supplied visible wheel');
assert.match(radial, /getRadialPointer\([\s\S]*?radialSvgRef\.current/, 'radial interactions must hit-test against the rendered SVG ref');
assert.match(radial, /className: `cortex-radial-svg[\s\S]*?ref: radialSvgRef/, 'the geometry ref must be attached to the rendered SVG');
assert.doesNotMatch(radial, /containerRef\.current\.getBoundingClientRect\(\)/, 'the full-screen overlay must not drive radial hit testing');

// Execute the geometry helpers in isolation (no DOM, no React).
const context = vm.createContext({ NUI_MAX_MENU_OPTIONS: 128, isRecord: () => true, boundedText: v => v, normalizeIconColor: () => null });
vm.runInContext(`${radialSource}\nglobalThis.api = { getRadialPointer, radialDirectionIndex, radialKeyIndex, describeRadialSlip, describeRadialArc, RADIAL_SIZE, RADIAL_DEAD_ZONE, RADIAL_OUTER_RADIUS, RADIAL_INNER_RADIUS, RADIAL_ARC_RADIUS, RADIAL_GAP };`, context);
const api = context.api;

const wheelRect = { left: 100, top: 100, width: 460, height: 460 };
const wheel = { getBoundingClientRect: () => wheelRect };
const centerX = wheelRect.left + wheelRect.width / 2;
const centerY = wheelRect.top + wheelRect.height / 2;
const at = (degrees, radius) => {
    const radians = degrees * Math.PI / 180;
    return [centerX + Math.sin(radians) * radius, centerY - Math.cos(radians) * radius];
};

assert.deepEqual({ ...api.getRadialPointer(centerX, centerY, wheel, 6) }, { type: 'center', index: -1 },
    'the dead zone at the centre is the back / close target');
assert.equal(api.getRadialPointer(...at(90, api.RADIAL_DEAD_ZONE - 2), wheel, 6).type, 'center',
    'small pointer movement inside the dead zone must not select');
assert.deepEqual({ ...api.getRadialPointer(...at(0, 150), wheel, 6) }, { type: 'item', index: 0 },
    'slip 0 is centred on 12 o\'clock');
assert.deepEqual({ ...api.getRadialPointer(...at(60, 150), wheel, 6) }, { type: 'item', index: 1 },
    'slips run clockwise, each centred on its own angle');
assert.deepEqual({ ...api.getRadialPointer(...at(300, 150), wheel, 6) }, { type: 'item', index: 5 });
assert.deepEqual({ ...api.getRadialPointer(...at(60, 2000), wheel, 6) }, { type: 'item', index: 1 },
    'selection is by direction: the pointer may be far outside the wheel');
assert.deepEqual({ ...api.getRadialPointer(...at(200, 60), wheel, 1) }, { type: 'item', index: 0 },
    'a single action is selected from any direction past the dead zone');
assert.deepEqual({ ...api.getRadialPointer(centerX, centerY, wheel, 0) }, { type: 'center', index: -1 },
    'an empty wheel never selects');
assert.deepEqual({ ...api.getRadialPointer(...at(0, 150), null, 6) }, { type: 'center', index: -1 });

// Hysteresis keeps the current slip a few degrees past its edge.
assert.equal(api.radialDirectionIndex(32, 6, -1), 1, 'past the 30 degree edge the next slip wins from rest');
assert.equal(api.radialDirectionIndex(32, 6, 0), 0, 'the hovered slip holds a few degrees past its edge');
assert.equal(api.radialDirectionIndex(45, 6, 0), 1, 'hysteresis is bounded');
assert.equal(api.radialDirectionIndex(-10, 8, -1), 0);
assert.equal(api.radialDirectionIndex(719, 8, -1), 0, 'angles normalise');

// Arrow keys aim; the nearest real slip wins on a partially filled page.
assert.equal(api.radialKeyIndex(new Set(['ArrowUp']), 8, 8), 0);
assert.equal(api.radialKeyIndex(new Set(['ArrowRight']), 8, 8), 2);
assert.equal(api.radialKeyIndex(new Set(['ArrowDown', 'ArrowLeft']), 8, 8), 5, 'two arrows aim diagonally');
assert.equal(api.radialKeyIndex(new Set(['ArrowDown']), 8, 2), 1, 'a ghost slot resolves to the nearest real slip');
assert.equal(api.radialKeyIndex(new Set(['ArrowUp', 'ArrowDown']), 8, 8), -1, 'opposite arrows cancel');
assert.equal(api.radialKeyIndex(new Set(['ArrowUp']), 8, 0), -1);

// Slips and arcs are finite SVG paths with gaps.
for (const [start, end] of [[-22.5, 22.5], [-90, 90], [-60, 60], [-180, 180]]) {
    assert.doesNotMatch(api.describeRadialSlip(start, end), /NaN|Infinity/);
    assert.doesNotMatch(api.describeRadialArc(start, end), /NaN|Infinity/);
}
assert.ok(api.RADIAL_GAP >= 3 && api.RADIAL_ARC_RADIUS > api.RADIAL_OUTER_RADIUS, 'gaps and the mint arc stay visible');

// Appearance and sizing: the donut is sized in --u, compact is a smaller variant.
assert.match(radialStyles, /\.cortex-radial-wheel\s*{[\s\S]*?--radial-size:\s*calc\(460 \* var\(--u\)\)/, 'the default wheel is 460u');
assert.match(radialStyles, /\.cortex-radial-wheel\.is-compact\s*{[\s\S]*?--radial-size:\s*calc\(380 \* var\(--u\)\)/, 'compact-control is a smaller wheel');
assert.match(radial, /appearance === 'compact-control'[\s\S]*?cortex-radial-svg--compact-control/,
    'only menus requesting the compact-control appearance may receive the compact treatment');
assert.match(clientSource,
    /if data\.appearance ~= nil and data\.appearance ~= 'compact-control' then[\s\S]*?return false, 'invalid_appearance'[\s\S]*?appearance = data\.appearance/,
    'the Lua boundary must reject unsupported appearances before storing compact-control');
assert.ok((clientSource.match(/appearance = currentAppearance\(\)/g) || []).length >= 4,
    'show, refresh, submenu, and back payloads must preserve the current menu appearance');
assert.ok((clientSource.match(/trail = buildTrail\(\)/g) || []).length >= 3,
    'refresh, submenu, and back payloads must carry the breadcrumb');
assert.match(clientSource, /focusIndex = meta and meta\.index or nil/, 'back must re-select the item that opened the submenu');

// Design constitution: state language and forbidden treatments.
assert.match(radialStyles, /\.cortex-radial-slip\.is-hover \.cortex-radial-slip-shape\s*{[^}]*fill:\s*var\(--paper\)/, 'hovered slip flips to paper');
assert.match(radialStyles, /\.cortex-radial-arc\s*{[^}]*stroke:\s*var\(--accent\)[^}]*stroke-width:\s*6/, 'mint arc is 6u');
assert.match(radialStyles, /\.cortex-radial-svg:focus[\s\S]*?outline:\s*none/, 'no focus ring on the wheel');
assert.doesNotMatch(radialStyles.replace(/@media[^{]*/g, ''), /(?:linear|radial|conic)-gradient|backdrop-filter|drop-shadow|\d+px/,
    'radial styles use tokens and --u only: no gradients, blur, glow or raw px');
assert.doesNotMatch(radial, /__more__|'More'/, 'pages are dots, never a fake "More" slip');
assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.cortex-radial-overlay/, 'the radial must expose a reduced-motion path');

console.log('radial UI contract: PASS');
