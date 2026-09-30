import { uiSource, uiStyles } from './ui_source.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...parts) => readFileSync(path.join(testDir, '..', ...parts), 'utf8').replace(/\r\n/g, '\n');
const styles = uiStyles;
const radialClient = read('imports', 'radial', 'client.lua');
const radial = uiSource.match(/function RadialMenu\([\s\S]*?\n\}\n/);
assert.ok(radial, 'RadialMenu must remain discoverable');

// Paging: eight slots per page, every slot an action. Pages are dots.
const renderedMatch = uiSource.match(/const RADIAL_PAGE_ITEMS = (\d+)/);
assert.ok(renderedMatch);
const perPage = Number(renderedMatch[1]);
assert.equal(perPage, 8);
assert.match(radial[0], /Math\.ceil\(itemCount \/ RADIAL_PAGE_ITEMS\)/);
assert.match(radial[0], /slice\(pageStartIndex, pageStartIndex \+ RADIAL_PAGE_ITEMS\)/);
assert.match(radial[0], /const pageStartIndex = \(currentPage - 1\) \* RADIAL_PAGE_ITEMS/);
assert.match(radial[0], /const sourceIndex = pageStartIndex \+ index/);
assert.match(radial[0], /const slotCount = totalPages > 1 \? RADIAL_PAGE_ITEMS/, 'paged menus keep all eight slots so directions stay put');
assert.doesNotMatch(radial[0], /allItems\.findIndex/, 'duplicate IDs must not affect source index mapping');
assert.doesNotMatch(radial[0], /__more__/, 'no fake More sector');
assert.match(radial[0], /cortex-radial-dot/, 'pages render as dots');

function pagesFor(length) {
    const items = Array.from({ length }, (_, index) => ({ id: index % 2 ? 'duplicate' : 'same', source: index }));
    const totalPages = Math.max(1, Math.ceil(items.length / perPage));
    return Array.from({ length: totalPages }, (_, pageIndex) => items.slice(pageIndex * perPage, pageIndex * perPage + perPage));
}

for (const itemCount of [0, 1, 2, 8, 9, 15, 16, 18, 128]) {
    const pages = pagesFor(itemCount);
    assert.deepEqual(pages.flat().map(item => item.source), Array.from({ length: itemCount }, (_, index) => index),
        `all ${itemCount} source indices must remain reachable exactly once`);
    assert.ok(pages.every(page => page.length <= perPage));
}

// Pages wrap and are remembered per menu for reopen / return.
assert.match(radial[0], /const changePage = useCallback\(\(delta\) => \{[\s\S]*?% totalPages[\s\S]*?rememberRadialPage\(memoryKey, next\)/);
assert.match(radial[0], /radialMemory\.get\(memoryKey\)/, 'a reopened menu restores its page');
assert.match(uiSource, /function rememberRadialPage[\s\S]*?radialMemory\.size > 32/, 'the page memory is bounded');
assert.match(radial[0], /focusIndex !== null && focusIndex !== undefined && focusIndex < allItems\.length/,
    'returning from a submenu re-selects the parent item only when it still exists');
assert.match(radial[0], /\(key === 'Enter' \|\| key === ' '\) && hovered >= 0/);
assert.match(radial[0], /\/\^\(\?:Digit\|Numpad\)\[1-8\]\$\//, 'number keys 1-8 pick directly');
assert.match(radial[0], /code === 'KeyQ'[\s\S]*?changePage\(-1\)[\s\S]*?code === 'KeyE'[\s\S]*?changePage\(1\)/, 'Q / E page');
assert.match(radial[0], /onWheel: handleWheel/);
assert.match(radial[0], /RADIAL_WHEEL_COOLDOWN_MS/, 'one wheel notch pages once');

// Transitions and focus.
assert.match(radial[0], /const isVisible = Boolean\(open\) && visible !== false/);
assert.match(radial[0], /const activateItem = useCallback\(\(index\) => \{\s*if \(!isVisible \|\| pendingRef\.current\) return;\s*const item = displayItems\[index\];\s*if \(!item \|\| item\.disabled\) return;/,
    'activation stops during transitions, while a click is in flight, and on disabled items');
assert.match(radial[0], /if \(!open \|\| !isVisible\) return undefined;[\s\S]*?window\.addEventListener\('keydown'/);
assert.match(radial[0], /if \(!isVisible\) return;[\s\S]*?pointerHit/, 'pointer input must stop during transitions');
assert.match(radial[0], /if \(hit\.index === hovered\) activateItem\(hit\.index\)/, 'a click confirms only the visibly selected slip');
assert.match(radial[0], /'aria-busy': !isVisible/);
assert.match(radial[0], /tabIndex: isVisible \? 0 : -1/);
assert.match(styles, /\.cortex-radial-overlay:not\(\.visible\)\s*{[\s\S]*?pointer-events: none/);

// Callback payloads keep their contract.
for (const callback of ['radialClick', 'radialBack', 'radialClose']) {
    assert.match(radial[0], new RegExp(`nuiPost\\('${callback}', \\{[\\s\\S]{0,100}?menuId: id, session`));
}
assert.match(radial[0], /nuiPost\('radialClick', \{ index: sourceIndex, itemId: item\.id, menuId: id, session \}\)/);
assert.match(radial[0], /useModalFocus\(open && isVisible, radialSvgRef, null,/);

// Normalizers stay bounded.
assert.match(uiSource, /function normalizeRadialItems[\s\S]*?items\.slice\(0, NUI_MAX_MENU_OPTIONS\)[\s\S]*?description: boundedText\(item\.description, '', 256\)[\s\S]*?disabled: item\.disabled === true/);
assert.match(uiSource, /function normalizeRadialTrail[\s\S]*?slice\(-RADIAL_MAX_TRAIL\)[\s\S]*?boundedText\(entry, '', 64\)/);
assert.match(uiSource, /function normalizeRadialFocusIndex[\s\S]*?Number\.isInteger\(value\) && value >= 0 && value < RADIAL_MAX_ITEMS/);
assert.match(uiSource, /case 'radialTransitionIn':[\s\S]*?focusIndex: normalizeRadialFocusIndex\(data\.focusIndex\)[\s\S]*?view: prev\.view \+ 1/);

const iconColorNormalizer = uiSource.match(/function normalizeIconColor\(value\) \{[\s\S]*?\n\}/);
assert.ok(iconColorNormalizer, 'radial icon color normalization must remain independently testable');
const normalizeIconColor = Function('boundedText', `${iconColorNormalizer[0]}\nreturn normalizeIconColor;`)(
    (value, fallback = '', maxLength = 4096) => typeof value === 'string' ? value.slice(0, maxLength) : fallback);
for (const color of ['#abc', '#abcd', '#abcdef', '#abcdef12', 'var(--state-warning)']) {
    assert.equal(normalizeIconColor(color), color);
}
for (const color of ['red', 'url(https://example.invalid)', 'var(color)', '#12345', 'a'.repeat(65)]) {
    assert.equal(normalizeIconColor(color), null);
}
assert.match(uiSource, /iconColor: normalizeIconColor\(item\.iconColor\)/);
assert.match(radial[0], /style\['--cortex-radial-icon-color'\] = item\.iconColor/);
assert.match(styles, /stroke: var\(--cortex-radial-icon-color, var\(--cortex-radial-content\)\)/);
assert.match(radialClient, /iconColor = item\.iconColor/);
assert.match(radialClient, /item\.description ~= nil and not boundedString\(item\.description, 256, true\)/);
assert.match(radialClient, /item\.disabled ~= nil and type\(item\.disabled\) ~= 'boolean'/);
assert.match(radialClient, /if item\.disabled then\s*cb\(\{ ok = false, error = 'disabled_item' \}\); return/, 'Lua rejects disabled clicks');

console.log('radial pagination and transition contract: PASS');
