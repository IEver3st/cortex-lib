import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...parts) => readFileSync(path.join(testDir, '..', ...parts), 'utf8').replace(/\r\n/g, '\n');
const uiSource = read('ui', 'app.js');
const styles = read('ui', 'style.css');
const menuClient = read('imports', 'menu', 'client.lua');
const debugCommands = read('tests', 'client', 'debug_commands.lua');

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

const menuComponent = uiSource.match(/function Menu\([\s\S]*?\n\}\n\n\/\/ ={20,}\n\/\/ ALERT DIALOG COMPONENT/);
assert.ok(menuComponent, 'Menu must remain discoverable');
assert.match(menuComponent[0], /const hasIcons = options\.some\(option => Boolean\(option\.icon\)\)/);
assert.match(menuComponent[0], /className: 'cortex-menu-option-icon'/);
assert.match(menuComponent[0], /'--cortex-menu-icon-color': opt\.iconColor/);
assert.match(menuComponent[0], /'aria-hidden': 'true'/, 'decorative icons must not duplicate the native option name');
assert.match(menuComponent[0], /'aria-label': rightBadge \? `\$\{opt\.label\}, \$\{rightBadge\}` : opt\.label/);
assert.match(styles, /\.cortex-menu-option-icon\s*{[\s\S]*?color: var\(--cortex-menu-icon-color, var\(--hud-dim\)\)/);

// Accepted presentation fields: label/icon/iconColor/progress/values/checked/defaultIndex.
assert.match(menuComponent[0], /cortex-menu-option-label'[\s\S]*?opt\.label/);
assert.match(menuComponent[0], /opt\.progress != null[\s\S]*?cortex-menu-option-progressFill/);
assert.match(menuComponent[0], /opt\.hasValues[\s\S]*?valueLabel/);
assert.match(menuComponent[0], /opt\.hasCheck[\s\S]*?opt\.checked/);
assert.match(optionSource[0], /defaultIndex[\s\S]*?scrollIndex/);
assert.ok((uiSource.match(/getOptionTooltip\(/g) || []).length >= 4, 'option and selected-value descriptions must feed the rendered tooltip');

// `close` and `args` intentionally remain callback-only in Lua.
assert.match(menuClient, /local shouldClose = option\.close ~= false/);
assert.match(menuClient, /stored\.args = option\.args/);
assert.match(menuClient, /getOptionArgs\(option\)/);
assert.match(menuClient, /local function safeColor\(value\)[\s\S]*?value:match\('\^var/);
assert.match(menuClient, /option\.iconColor ~= nil and not safeColor\(option\.iconColor\)/);
assert.match(debugCommands, /icon = '⚙️', iconColor = 'var\(--state-success\)'/);

console.log('menu option rendering contract: PASS');
