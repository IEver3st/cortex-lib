import { uiSource, uiStyles } from './ui_source.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...parts) => readFileSync(path.join(testDir, '..', ...parts), 'utf8').replace(/\r\n/g, '\n');
const styles = uiStyles;
const menuClient = read('imports', 'menu', 'client.lua');

const colorSource = uiSource.match(/function normalizeIconColor\(value\) \{[\s\S]*?\n\}/);
const optionSource = uiSource.match(/function normalizeOption\(option\) \{[\s\S]*?\n\}/);
assert.ok(colorSource && optionSource, 'menu option normalization must remain independently testable');
const { normalizeIconColor, normalizeOption } = Function(
    'isRecord',
    'boundedText',
    `${colorSource[0]}\n${optionSource[0]}\nreturn { normalizeIconColor, normalizeOption };`
)(
    value => value !== null && typeof value === 'object' && !Array.isArray(value),
    (value, fallback = '', maxLength = 4096) => {
        if (typeof value === 'string') return value.slice(0, maxLength);
        if (typeof value === 'number' || typeof value === 'boolean') return String(value).slice(0, maxLength);
        return fallback;
    }
);

for (const color of ['#abc', '#abcd', '#abcdef', '#abcdef12', 'var(--state-success)']) {
    assert.equal(normalizeIconColor(color), color);
}
for (const color of ['red', 'rgb(0,0,0)', 'url(https://example.invalid)', '#12345', 'a'.repeat(65)]) {
    assert.equal(normalizeIconColor(color), null);
}

const normalized = normalizeOption({
    label: 'With icon',
    description: 'Description',
    icon: 'x'.repeat(140),
    iconColor: 'var(--state-success)',
    progress: 42,
    values: [{ label: 'First', description: 'First description' }],
    defaultIndex: 1,
    checked: true,
    close: false
});
assert.equal(normalized.icon.length, 128, 'the UI must preserve the full Lua-accepted icon bound');
assert.equal(normalized.iconColor, 'var(--state-success)');
assert.equal(normalized.progress, 42);
assert.equal(normalized.values[0].description, 'First description');
assert.equal(normalized.checked, true);
assert.equal(normalized.scrollIndex, 1);
assert.equal(Object.hasOwn(normalized, 'close'), false, 'close is Lua callback behavior and must not become misleading UI state');
assert.equal(normalizeOption({ label: 'Unsafe', iconColor: 'red' }).iconColor, null);
assert.equal(normalized.disabled, false, 'rows are enabled unless Lua says otherwise');
assert.equal(normalizeOption({ label: 'Locked', disabled: true }).disabled, true);
assert.equal(normalizeOption({ label: 'Truthy', disabled: 'yes' }).disabled, false, 'only a boolean true disables a row');
assert.equal(normalizeOption({ label: 'Over', progress: 250 }).progress, 100, 'progress is clamped for the meter');
assert.equal(normalizeOption({ label: 'Under', progress: -5 }).progress, 0);

const menuComponent = uiSource.match(/function Menu\([\s\S]*?\n\}\n/);
assert.ok(menuComponent, 'Menu must remain discoverable');
assert.match(menuComponent[0], /const hasIcons = options\.some\(option => Boolean\(option\.icon\)\)/);
assert.match(menuComponent[0], /className: 'cortex-menu-option-icon'/);
assert.match(menuComponent[0], /'--cortex-menu-icon-color': opt\.iconColor/);
assert.match(menuComponent[0], /'aria-hidden': 'true'/, 'decorative icons must not duplicate the native option name');
assert.match(menuComponent[0], /'aria-label': stateText \? `\$\{opt\.label\}, \$\{stateText\}` : opt\.label/);
assert.match(menuComponent[0], /'aria-disabled': opt\.disabled/);
assert.match(styles, /\.cortex-menu-option-icon\s*{[\s\S]*?color: var\(--cortex-menu-icon-color, var\(--muted\)\)/);

// Accepted presentation fields: label/icon/iconColor/progress/values/checked/defaultIndex.
assert.match(menuComponent[0], /cortex-menu-option-label'[\s\S]*?opt\.label/);
assert.match(menuComponent[0], /opt\.progress != null[\s\S]*?CortexKit\.Meter/);
assert.match(menuComponent[0], /CortexKit\.CheckMark, \{ checked: opt\.checked \}/);
assert.match(menuComponent[0], /CortexKit\.SlipHeader/);
assert.match(menuComponent[0], /opt\.hasValues[\s\S]*?valueLabel/);
assert.match(menuComponent[0], /opt\.hasCheck[\s\S]*?opt\.checked/);
assert.match(optionSource[0], /defaultIndex[\s\S]*?scrollIndex/);
assert.ok((uiSource.match(/getOptionTooltip\(/g) || []).length >= 4, 'option and selected-value descriptions must feed the rendered tooltip');

// Selection starts where Lua asked: the modal focus lands on the selected row,
// whose onFocus would otherwise reset selection to the first button.
assert.match(menuComponent[0], /'data-autofocus': active \? 'true' : undefined/);

// Disabled rows: skipped by navigation, never actioned by the UI, refused by Lua.
const findRowSource = uiSource.match(/function findMenuRow\(options, from, direction, wrap\) \{[\s\S]*?\n\}/);
const windowSource = uiSource.match(/function getMenuWindowStart\(previous, selectedIndex, count, rows\) \{[\s\S]*?\n\}/);
assert.ok(findRowSource && windowSource, 'menu navigation helpers must remain independently testable');
const { findMenuRow, getMenuWindowStart } = Function(`${findRowSource[0]}
${windowSource[0]}
return { findMenuRow, getMenuWindowStart };`)();
const rows = [{}, { disabled: true }, { disabled: true }, {}];
assert.equal(findMenuRow(rows, 1, 1, true), 4, 'down skips disabled rows');
assert.equal(findMenuRow(rows, 4, 1, true), 1, 'down wraps to the first enabled row');
assert.equal(findMenuRow(rows, 1, -1, true), 4, 'up wraps to the last enabled row');
assert.equal(findMenuRow(rows, 4, 1, false), 0, 'Page/Home/End do not wrap');
assert.equal(findMenuRow([{ disabled: true }], 1, 1, true), 0, 'an all-disabled list keeps its selection');
assert.equal(findMenuRow([], 1, 1, true), 0, 'an empty list never divides by zero');
for (const guard of [/doSideScroll[\s\S]*?opt\.disabled\) return/, /toggleCheck = useCallback[\s\S]*?opt\.disabled\) return/, /submit = useCallback[\s\S]*?opt\.disabled\) return/]) {
    assert.match(menuComponent[0], guard);
}
assert.match(menuClient, /option\.disabled ~= nil and type\(option\.disabled\) ~= 'boolean'/);
assert.equal((menuClient.match(/if option\.disabled then cb\(\{ ok = false, error = 'option_disabled' \}\)/g) || []).length, 3,
    'submit, check and side scroll must each refuse disabled rows in Lua');

// The windowed list keeps a row of lookahead and never leaves the bounds.
assert.equal(getMenuWindowStart(0, 1, 5, 10), 0, 'short lists never scroll');
assert.equal(getMenuWindowStart(0, 10, 40, 10), 1, 'the selection keeps one row of lookahead below');
assert.equal(getMenuWindowStart(20, 21, 40, 10), 19, 'and one row above');
assert.equal(getMenuWindowStart(0, 40, 40, 10), 30, 'the window stops at the end');
assert.equal(getMenuWindowStart(30, 1, 40, 10), 0, 'wrapping to the top resets the window');
assert.equal(getMenuWindowStart(99, 5, 3, 10), 0);

// Legend: kit keycaps, stable per menu, mode-specific.
assert.match(menuComponent[0], /keys: 'WHEEL', label: 'Move'[\s\S]*?keys: 'LMB'[\s\S]*?keys: 'RMB', label: 'Back'/);
assert.match(menuComponent[0], /keys: 'ARROWS', label: 'Move'[\s\S]*?keys: 'SPACE', label: 'Toggle'[\s\S]*?keys: 'ENTER', label: 'Select'[\s\S]*?canClose \? \{ id: 'close', keys: 'ESC', label: 'Close' \}/);
assert.match(uiSource, /function MenuLegend[\s\S]*?className: 'cx-legend cortex-menu-legend'[\s\S]*?CortexKit\.KeyHint/);

// Design rules: tokens, no gradients or outlines in the menu stylesheet.
const menuStyles = read('ui', 'surfaces', 'menu.css');
assert.doesNotMatch(menuStyles.replace(/@media[^{]*\{/g, '').replace(/\b0px\b/g, ''), /gradient|backdrop-filter|outline:|#[0-9a-f]{3,8}\b|\d+px/i,
    'the menu uses tokens and --u only: no gradients, outlines, raw colours or px');

// `close` and `args` intentionally remain callback-only in Lua.
assert.match(menuClient, /local shouldClose = option\.close ~= false/);
assert.match(menuClient, /stored\.args = option\.args/);
assert.match(menuClient, /getOptionArgs\(option\)/);
assert.match(menuClient, /local function safeColor\(value\)[\s\S]*?value:match\('\^var/);
assert.match(menuClient, /option\.iconColor ~= nil and not safeColor\(option\.iconColor\)/);

console.log('menu option rendering contract: PASS');
