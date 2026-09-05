import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...parts) => readFileSync(path.join(testDir, '..', ...parts), 'utf8').replace(/\r\n/g, '\n');
const uiSource = read('ui', 'app.js');
const styles = read('ui', 'style.css');
const radialClient = read('imports', 'radial', 'client.lua');
const radial = uiSource.match(/function RadialMenu\([\s\S]*?\n\}\n\n\/\/ ={20,}\n\/\/ SETTINGS PANEL/);
assert.ok(radial, 'RadialMenu must remain discoverable');

const renderedMatch = uiSource.match(/const RADIAL_PAGE_ITEMS = (\d+)/);
assert.ok(renderedMatch);
const renderedPerPage = Number(renderedMatch[1]);
const actionsPerPage = renderedPerPage - 1;
assert.equal(renderedPerPage, 8);
assert.match(uiSource, /const RADIAL_PAGE_ACTIONS = RADIAL_PAGE_ITEMS - 1/);
assert.match(radial[0], /Math\.ceil\(allItems\.length \/ RADIAL_PAGE_ACTIONS\)/);
assert.match(radial[0], /slice\(pageStartIndex, pageStartIndex \+ RADIAL_PAGE_ACTIONS\)/);
assert.match(radial[0], /const sourceIndex = pageStartIndex \+ index/);
assert.doesNotMatch(radial[0], /allItems\.findIndex/, 'duplicate IDs must not affect source index mapping');

function pagesFor(length) {
    const items = Array.from({ length }, (_, index) => ({ id: index % 2 ? 'duplicate' : 'same', source: index }));
    if (items.length <= renderedPerPage) return [items];
    const totalPages = Math.ceil(items.length / actionsPerPage);
    return Array.from({ length: totalPages }, (_, pageIndex) =>
        items.slice(pageIndex * actionsPerPage, (pageIndex * actionsPerPage) + actionsPerPage)
    );
}

for (const itemCount of [0, 1, 8, 9, 15, 16, 128]) {
    const pages = pagesFor(itemCount);
    const reached = pages.flat().map(item => item.source);
    assert.deepEqual(
        reached,
        Array.from({ length: itemCount }, (_, index) => index),
        `all ${itemCount} source indices must remain reachable exactly once`
    );
    assert.ok(pages.every(page => page.length <= actionsPerPage || itemCount <= renderedPerPage));
    assert.ok(pages.every(page => page.length + (itemCount > renderedPerPage ? 1 : 0) <= renderedPerPage));
}

assert.match(radial[0], /if \(!isVisible\) return;[\s\S]*?const item = displayItems\[index\]/);
assert.match(radial[0], /if \(!open \|\| !isVisible\) return;[\s\S]*?window\.addEventListener\('keydown'/);
assert.match(radial[0], /if \(!isVisible\) return;[\s\S]*?getRadialPointer/, 'pointer input must stop during transitions');
assert.match(radial[0], /'aria-busy': !isVisible/);
assert.match(radial[0], /tabIndex: isVisible \? 0 : -1/);
assert.match(styles, /\.cortex-radial-overlay:not\(\.visible\)\s*{[\s\S]*?pointer-events: none/);

for (const callback of ['radialClick', 'radialBack', 'radialClose']) {
    assert.match(radial[0], new RegExp(`nuiPost\\('${callback}', \\{[\\s\\S]{0,100}?menuId: id, session`));
}
assert.match(radial[0], /nuiPost\('radialClick', \{ index: sourceIndex, itemId: item\.id, menuId: id, session \}\)/);
assert.match(radial[0], /useModalFocus\(open && isVisible, radialSvgRef, null,/);

const iconColorNormalizer = uiSource.match(/function normalizeIconColor\(value\) \{[\s\S]*?\n\}/);
assert.ok(iconColorNormalizer, 'radial icon color normalization must remain independently testable');
const normalizeIconColor = Function(
    'boundedText',
    `${iconColorNormalizer[0]}\nreturn normalizeIconColor;`
)((value, fallback = '', maxLength = 4096) => typeof value === 'string' ? value.slice(0, maxLength) : fallback);
for (const color of ['#abc', '#abcd', '#abcdef', '#abcdef12', 'var(--state-warning)']) {
    assert.equal(normalizeIconColor(color), color);
}
for (const color of ['red', 'url(https://example.invalid)', 'var(color)', '#12345', 'a'.repeat(65)]) {
    assert.equal(normalizeIconColor(color), null);
}
assert.match(uiSource, /iconColor: normalizeIconColor\(item\.iconColor\)/);
assert.match(radial[0], /'--cortex-radial-icon-color': item\.iconColor/);
assert.match(styles, /fill: var\(--cortex-radial-icon-color, var\(--hud-color\)\)/);
assert.match(radialClient, /iconColor = item\.iconColor/);

console.log('radial pagination and transition contract: PASS');
