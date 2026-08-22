import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...segments) => readFileSync(path.join(testDir, '..', ...segments), 'utf8')
    .replace(/\r\n/g, '\n');

const styles = read('ui', 'style.css');
const uiSource = read('ui', 'app.js');
const rootBlock = styles.match(/:root\s*{[\s\S]*?\n}/);

assert.ok(rootBlock, 'the shared UI palette must remain centralized in :root');

for (const [token, value] of [
    ['cortex-black', '#09090a'],
    ['cortex-surface', '#151516'],
    ['cortex-surface-raised', '#1d1c1e'],
    ['cortex-white', '#ebe9e6'],
    ['cortex-lavender', '#bea9de'],
    ['cortex-blue', '#9bbcd3'],
    ['cortex-aqua', '#8fcbbf'],
    ['cortex-rose', '#d6a5b6'],
    ['cortex-sage', '#9bc2ae'],
    ['cortex-amber', '#d8ba82']
]) {
    assert.match(rootBlock[0], new RegExp(`--${token}:\\s*${value};`, 'i'), `${token} must remain in the shared palette`);
}

for (const semanticToken of [
    'text-primary',
    'text-secondary',
    'surface-hud',
    'surface-panel',
    'state-success',
    'state-error',
    'state-warning',
    'state-info',
    'state-focus',
    'state-selection'
]) {
    assert.match(rootBlock[0], new RegExp(`--${semanticToken}:`), `${semanticToken} must remain centralized`);
}

const declarations = new Map(
    [...rootBlock[0].matchAll(/--([a-z0-9-]+):\s*([^;]+);/gi)]
        .map((match) => [match[1], match[2].trim()])
);

function resolveHexToken(name, seen = new Set()) {
    assert.ok(!seen.has(name), `token cycle detected at ${name}`);
    seen.add(name);
    const value = declarations.get(name);
    assert.ok(value, `missing token ${name}`);
    const reference = value.match(/^var\(--([a-z0-9-]+)\)$/i);
    return reference ? resolveHexToken(reference[1], seen) : value;
}

function relativeLuminance(hex) {
    assert.match(hex, /^#[0-9a-f]{6}$/i, `${hex} must resolve to a six-digit hex color`);
    const channels = [1, 3, 5].map((index) => Number.parseInt(hex.slice(index, index + 2), 16) / 255);
    const linear = channels.map((channel) => channel <= 0.04045
        ? channel / 12.92
        : ((channel + 0.055) / 1.055) ** 2.4);
    return (0.2126 * linear[0]) + (0.7152 * linear[1]) + (0.0722 * linear[2]);
}

function contrastRatio(foreground, background) {
    const foregroundLuminance = relativeLuminance(resolveHexToken(foreground));
    const backgroundLuminance = relativeLuminance(resolveHexToken(background));
    const lighter = Math.max(foregroundLuminance, backgroundLuminance);
    const darker = Math.min(foregroundLuminance, backgroundLuminance);
    return (lighter + 0.05) / (darker + 0.05);
}

for (const [foreground, background] of [
    ['text-primary', 'cortex-surface-raised'],
    ['text-secondary', 'cortex-surface-raised'],
    ['state-success', 'cortex-surface-raised'],
    ['state-error', 'cortex-surface-raised'],
    ['state-warning', 'cortex-surface-raised'],
    ['state-info', 'cortex-surface-raised'],
    ['state-focus', 'cortex-surface-raised'],
    ['state-selection', 'cortex-surface-raised'],
    ['text-inverse', 'state-focus']
]) {
    assert.ok(
        contrastRatio(foreground, background) >= 4.5,
        `${foreground} must retain at least 4.5:1 contrast against ${background}`
    );
}

const componentStyles = styles.replace(rootBlock[0], '');
assert.doesNotMatch(
    componentStyles,
    /#[0-9a-f]{3,8}\b|rgba?\(|hsla?\(/i,
    'component rules must consume shared palette or semantic tokens instead of local color literals'
);
assert.doesNotMatch(
    styles,
    /#(?:10b981|34d399|3b82f6|60a5fa|ef4444|f87171|ff4444|ffaa00|00d9a3|00e6b8|00ffcc)\b/i,
    'legacy saturated web-app colors must not return'
);
assert.doesNotMatch(styles, /(?:linear|radial)-gradient\(/i, 'the restrained HUD palette must not introduce gradients');

assert.match(styles, /\.notify\.info[\s\S]*?border-color:\s*var\(--state-info\)/);
assert.match(styles, /\.cortex-menu-option\.active[\s\S]*?var\(--state-selection-surface\)/);
assert.match(styles, /\.progress-fill[\s\S]*?background:\s*var\(--hud-progress\)/);
assert.match(styles, /\.cortex-interaction-key-ring-progress[\s\S]*?stroke:\s*var\(--state-focus\)/);
assert.match(styles, /\.cortex-radial-sector\.hover \.cortex-radial-sector-bg[\s\S]*?var\(--state-selection\)/);
assert.match(styles, /\.cortex-context-checkbox-box\.checked[\s\S]*?background:\s*var\(--state-focus\)/);
assert.match(styles, /\.cortex-settings-tab\.active[\s\S]*?var\(--state-selection\)/);
assert.match(styles, /\.cortex-settings-btn\.save[\s\S]*?var\(--state-focus-surface\)/);
assert.match(styles, /\.cortex-settings-btn\.reset[\s\S]*?var\(--state-error-surface\)/);
assert.match(styles, /button:focus-visible,[\s\S]*?outline:\s*2px solid var\(--state-focus\)/);

assert.match(uiSource, /color:\s*'var\(--cortex-accent\)'/, 'Cortex branding should use the restrained aqua accent');
assert.match(uiSource, /line\?\.color \? \{ color: line\.color \}/, 'caller-provided debug colors remain an intentional public override');

console.log('UI palette contract: PASS');
