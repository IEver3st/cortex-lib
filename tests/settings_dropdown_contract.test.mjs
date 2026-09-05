import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...segments) => readFileSync(path.join(testDir, '..', ...segments), 'utf8')
    .replace(/\r\n/g, '\n');

const uiSource = read('ui', 'app.js');
const styles = read('ui', 'style.css');

assert.doesNotMatch(
    uiSource,
    /React\.createElement\('select',[\s\S]{0,240}cortex-settings-select/,
    'settings fields must not use the unstyleable native CEF select popup'
);
assert.match(uiSource, /function SettingsSelect\(/, 'settings must own a custom select control');
assert.match(uiSource, /ReactDOM\.createPortal\(/, 'the options layer must escape the scrolling panel');
assert.match(uiSource, /role:\s*'combobox'/, 'the select trigger must expose combobox semantics');
assert.match(uiSource, /role:\s*'listbox'/, 'the options layer must expose listbox semantics');
assert.match(uiSource, /role:\s*'option'/, 'each choice must expose option semantics');
assert.match(uiSource, /const selectedIndex = options\.findIndex\(\(option\) => Object\.is\(option\.value, value\)\)/,
    'settings selections must retain exact scalar type identity');
assert.doesNotMatch(uiSource, /Object\.is\(option\.value, value\)\s*\|\|/,
    'numeric and string settings option values must not select each other');
assert.match(uiSource, /event\.key === 'ArrowDown'/, 'keyboard users must be able to move through choices');
assert.match(uiSource, /event\.key === 'Escape'[\s\S]*?event\.stopPropagation\(\)/, 'Escape must close only the dropdown first');
assert.match(uiSource, /window\.addEventListener\('scroll', handleViewportChange, true\)/, 'the floating menu must track the scrolling settings pane');

assert.match(styles, /\.cortex-settings-select-menu\s*{[\s\S]*?position:\s*fixed;/, 'the menu must use viewport positioning');
assert.match(styles, /\.cortex-settings-select-menu\s*{[\s\S]*?background:\s*var\(--cortex-surface-raised\);/, 'the menu must use an opaque controlled surface');
assert.match(styles, /\.cortex-settings-select-option\.selected\s*{[\s\S]*?var\(--state-selection-surface\)/, 'the selected option needs a clear pastel state');
assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.cortex-settings-select-menu/, 'dropdown motion must respect reduced-motion preferences');

console.log('Settings dropdown contract: PASS');
