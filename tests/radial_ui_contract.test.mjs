import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const uiSource = readFileSync(
    path.join(testDir, '..', 'ui', 'app.js'),
    'utf8'
).replace(/\r\n/g, '\n');
const styles = readFileSync(
    path.join(testDir, '..', 'ui', 'style.css'),
    'utf8'
).replace(/\r\n/g, '\n');
const clientSource = readFileSync(
    path.join(testDir, '..', 'imports', 'radial', 'client.lua'),
    'utf8'
).replace(/\r\n/g, '\n');

const radialMatch = uiSource.match(
    /function RadialMenu\([\s\S]*?\n}\n\n\/\/ ={20,}\n\/\/ SETTINGS PANEL/
);

assert.ok(radialMatch, 'RadialMenu must remain discoverable by the UI regression test');
const radial = radialMatch[0];

assert.match(
    radial,
    /const radialSvgRef = useRef\(null\)/,
    'radial pointer geometry must own a ref to the rendered SVG'
);
assert.match(
    uiSource,
    /function getRadialPointer[\s\S]*?element\.getBoundingClientRect\(\)/,
    'radial pointer geometry must measure the supplied visible wheel'
);
assert.match(
    radial,
    /getRadialPointer\([\s\S]*?radialSvgRef\.current/,
    'radial interactions must hit-test against the rendered SVG ref'
);
assert.match(
    radial,
    /className: `cortex-radial-svg[\s\S]*?ref: radialSvgRef/,
    'the geometry ref must be attached to the rendered SVG'
);
assert.doesNotMatch(
    radial,
    /containerRef\.current\.getBoundingClientRect\(\)/,
    'the full-screen overlay must not drive radial hit testing'
);
assert.match(
    uiSource,
    /const index = Math\.floor\(angle \/ angleStep\) % itemCount/,
    'pointer sectors must align with the angles used to draw each sector'
);

const pointerSource = uiSource.match(
    /function getRadialPointer\([\s\S]*?\n}/
);
assert.ok(pointerSource, 'the pointer geometry helper must remain independently testable');
const getRadialPointer = Function(
    'RADIAL_SIZE',
    'RADIAL_INNER_RADIUS',
    'RADIAL_OUTER_RADIUS',
    `${pointerSource[0]}; return getRadialPointer;`
)(350, 45, 175);

const wheelRect = {
    left: 100,
    top: 100,
    width: 297.5,
    height: 297.5,
};
const wheel = { getBoundingClientRect: () => wheelRect };
const centerX = wheelRect.left + wheelRect.width / 2;
const centerY = wheelRect.top + wheelRect.height / 2;
const radius = 95;
const atAngle = degrees => {
    const radians = degrees * Math.PI / 180;
    return {
        x: centerX + Math.sin(radians) * radius,
        y: centerY - Math.cos(radians) * radius,
    };
};

assert.deepEqual(
    getRadialPointer(centerX, centerY, wheel, 6, 6),
    { type: 'center', index: -1 },
    'the visible center must remain the close/back target'
);
const firstSector = atAngle(30);
assert.deepEqual(
    getRadialPointer(firstSector.x, firstSector.y, wheel, 6, 6),
    { type: 'item', index: 0 },
    'the first visible sector must activate the first action'
);
const secondSector = atAngle(90);
assert.deepEqual(
    getRadialPointer(secondSector.x, secondSector.y, wheel, 6, 6),
    { type: 'item', index: 1 },
    'the second visible sector must activate the second action without an angle offset'
);

assert.match(
    styles,
    /\.cortex-radial-svg\s*{[\s\S]*?width:\s*calc\(350px \* var\(--cortex-ui-scale\)\);[\s\S]*?height:\s*calc\(350px \* var\(--cortex-ui-scale\)\);/,
    'the shared radial default must retain its existing dimensions'
);
assert.match(
    styles,
    /\.cortex-radial-svg--compact-control\s*{[\s\S]*?width:\s*calc\(297\.5px \* var\(--cortex-ui-scale\)\);[\s\S]*?height:\s*calc\(297\.5px \* var\(--cortex-ui-scale\)\);/,
    'the compact-control appearance must be exactly 15 percent smaller than the 350px default'
);
assert.match(
    radial,
    /appearance === 'compact-control'[\s\S]*?cortex-radial-svg--compact-control/,
    'only menus requesting the compact-control appearance may receive the redesign'
);
assert.match(
    clientSource,
    /if data\.appearance ~= nil and data\.appearance ~= 'compact-control' then[\s\S]*?return false, 'invalid_appearance'[\s\S]*?appearance = data\.appearance/,
    'the Lua boundary must reject unsupported appearances before storing compact-control'
);
assert.ok(
    (clientSource.match(/appearance = currentAppearance\(\)/g) || []).length >= 4,
    'show, refresh, submenu, and back payloads must preserve the current menu appearance'
);
assert.match(
    styles,
    /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.cortex-radial-overlay/,
    'the radial must expose a reduced-motion path'
);

console.log('radial UI contract: PASS');
