import { uiSource, uiStyles } from './ui_source.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...parts) => readFileSync(path.join(testDir, '..', ...parts), 'utf8').replace(/\r\n/g, '\n');
const styles = uiStyles;
const notifyClient = read('imports', 'notify', 'client.lua');

const progressNormalizer = uiSource.match(/function normalizeProgressData\(data\) \{[\s\S]*?\n\}/);
assert.ok(progressNormalizer, 'progress payload normalization must remain discoverable');
const normalizeProgressData = Function(
    'isRecord',
    'boundedText',
    `${progressNormalizer[0]}\nreturn normalizeProgressData;`
)(
    value => value !== null && typeof value === 'object' && !Array.isArray(value),
    (value, fallback = '', maxLength = 4096) => typeof value === 'string' ? value.slice(0, maxLength) : fallback
);
assert.equal(normalizeProgressData({ position: 'top' }).position, 'top');
assert.equal(normalizeProgressData({ position: 'middle' }).position, 'middle');
assert.equal(normalizeProgressData({ position: 'center' }).position, 'middle', 'center must use the canonical middle layout');
assert.equal(normalizeProgressData({ position: 'invalid' }).position, 'bottom');

const focusHook = uiSource.match(/function useModalFocus\(open, dialogRef, onEscape, focusKey = null\) \{[\s\S]*?\n\}/);
assert.ok(focusHook, 'the shared modal focus lifecycle must remain discoverable');
assert.match(focusHook[0], /document\.activeElement/);
assert.match(focusHook[0], /event\.key === 'Escape'/);
assert.match(focusHook[0], /event\.key !== 'Tab'/);
assert.match(focusHook[0], /document\.addEventListener\('keydown', handleKeyDown\)/);
assert.match(focusHook[0], /document\.removeEventListener\('keydown', handleKeyDown\)/);
assert.match(focusHook[0], /focusElement\(previousFocus\)/, 'closing a modal must restore the prior focus owner');
assert.match(focusHook[0], /\[open, dialogRef, focusKey\]/, 'a replacement session must re-enter the focus lifecycle');

for (const invocation of [
    /useModalFocus\(open, dialogRef, null, session\)/,
    /useModalFocus\(open, dialogRef, cancel \? handleCancel : null, session\)/,
    /useModalFocus\(open, dialogRef, handleCancel, session\)/,
    /useModalFocus\(open && isVisible, radialSvgRef, null, `\$\{session/
]) {
    assert.match(uiSource, invocation, 'every interactive modal surface must use the shared focus lifecycle');
}

const alertDialog = uiSource.match(/function AlertDialog\([\s\S]*?\n\}/);
assert.ok(alertDialog, 'AlertDialog must remain discoverable');
assert.match(alertDialog[0], /if \(cancel\) onClose\('cancel', session\)/);
assert.match(alertDialog[0], /cancel \? handleCancel : null/);
assert.match(alertDialog[0], /onMouseDown: handleCancel/);
assert.match(alertDialog[0], /role: 'dialog'/);
assert.match(alertDialog[0], /'aria-modal': true/);
const dialogActions = uiSource.match(/function DialogActions\([\s\S]*?\n\}/);
assert.ok(dialogActions, 'dialog actions must remain discoverable');
assert.match(dialogActions[0], /type: 'button'/);
assert.match(dialogActions[0], /kit\.Keycap, \{ value: key/, 'dialog actions are keycap buttons');
assert.match(dialogActions[0], /'ESC'[\s\S]*?'ENTER'/, 'secondary shows ESC, primary shows ENTER');
assert.match(alertDialog[0], /showCancel: cancel/, 'confirm-only alerts must not render a cancel action');
assert.match(alertDialog[0], /kit\.SlipHeader, \{ id: 'cortex-alert-title'/);

const contextMenu = uiSource.match(/function ContextMenu\(\{[\s\S]*?\n\}/);
assert.ok(contextMenu, 'ContextMenu must remain discoverable');
assert.match(contextMenu[0], /validateContextValues\(list, formValues\)[\s\S]*?if \(firstInvalid >= 0\) \{[\s\S]*?focusContextField[\s\S]*?return;[\s\S]*?onClose\('confirm'/,
    'confirm must be blocked and focus the first invalid field before any result is posted');
assert.match(contextMenu[0], /event\.key !== 'Enter'[\s\S]*?target\?\.tagName === 'INPUT'/, 'Enter must submit from inputs');
assert.match(uiSource, /function ContextMenuField[\s\S]*?kit\.Dropdown, \{/, 'selects must use the kit dropdown, never a native select');
assert.doesNotMatch(uiSource.match(/function normalizeContextField[\s\S]*?function ContextMenu\(\{/)[0], /createElement\('select'|type: 'checkbox'/,
    'dialogs must not render native selects or checkboxes');

// Behaviour of the pure form helpers.
const dialogHelpers = ['normalizeDialogNumber', 'normalizeContextOption', 'normalizeContextField', 'contextOptionValue',
    'parseDialogNumber', 'formatDialogNumber', 'stepDialogNumber', 'validateContextValues', 'contextResultValues']
    .map(name => uiSource.match(new RegExp(`function ${name}\\([\\s\\S]*?\\n\\}`))[0]).join('\n');
const dialogConstants = uiSource.match(/const DIALOG_NUMBER_LIMIT[^\n]*\nconst DIALOG_NUMBER_PATTERN[^\n]*/)[0];
const helpers = Function('isRecord', 'boundedText', 'isSafeObjectKey',
    `${dialogConstants}\n${dialogHelpers}\nreturn { normalizeContextField, stepDialogNumber, validateContextValues, contextResultValues };`)(
    value => value !== null && typeof value === 'object' && !Array.isArray(value),
    (value, fallback = '', maxLength = 4096) => typeof value === 'string' ? value.slice(0, maxLength)
        : (typeof value === 'number' || typeof value === 'boolean' ? String(value) : fallback),
    value => typeof value === 'string' && value.length > 0 && !['__proto__', 'prototype', 'constructor'].includes(value)
);
const bounded = helpers.normalizeContextField({ type: 'input', name: 'n', inputType: 'number', min: 1, max: 10, step: 0.5 });
assert.deepEqual([bounded.min, bounded.max, bounded.step], [1, 10, 0.5]);
const inverted = helpers.normalizeContextField({ type: 'input', name: 'n', min: 9, max: 1, step: -1 });
assert.deepEqual([inverted.min, inverted.max, inverted.step], [undefined, undefined, undefined], 'invalid bounds are dropped');
assert.equal(helpers.normalizeContextField({ type: 'input', name: 'n', max: 1e12 }).max, undefined, 'bounds stay within the numeric limit');
assert.equal(helpers.normalizeContextField({ type: 'input', name: '__proto__' }), null);
assert.equal(helpers.stepDialogNumber(bounded, '', 1), '1', 'stepping from empty starts at min');
assert.equal(helpers.stepDialogNumber(bounded, '9.5', 1, 10), '10', 'stepping clamps at max');
assert.equal(helpers.stepDialogNumber({ step: 0.1 }, '0.2', 1), '0.3', 'stepping removes float noise');
const form = [
    { type: 'input', name: 'name', required: true },
    { type: 'select', name: 'mode', required: true, options: [{ value: false, label: 'Off' }, 'on'] },
    { type: 'input', name: 'count', inputType: 'number', min: 1, max: 10 },
    { type: 'checkbox', name: 'flag', required: true }
];
assert.deepEqual(Object.keys(helpers.validateContextValues(form, {})), ['name', 'mode']);
assert.deepEqual(Object.keys(helpers.validateContextValues(form, { name: '   ', mode: '' })), ['name', 'mode'],
    'blank text and unmatched selects stay invalid');
assert.deepEqual(helpers.validateContextValues(form, { name: 'A', mode: false, count: '' }), {},
    'false is a real select value; optional numbers may be empty');
assert.match(helpers.validateContextValues(form, { name: 'A', mode: 'on', count: 'x' }).count, /number/i);
assert.match(helpers.validateContextValues(form, { name: 'A', mode: 'on', count: '11' }).count, /Maximum is 10/);
assert.match(helpers.validateContextValues(form, { name: 'A', mode: 'on', count: '0' }).count, /Minimum is 1/);
assert.deepEqual(helpers.contextResultValues(form, { name: 'A', count: ' 4 ', stray: 'x' }), { name: 'A', count: '4' },
    'results carry declared fields only, with number text trimmed');

const alertStyle = uiSource.match(/function normalizeAlertStyle\(style\) \{[\s\S]*?\n\}/);
assert.ok(alertStyle, 'alert style normalization must remain discoverable');
assert.match(alertStyle[0], /\['backgroundColor', 'borderColor', 'color'\]/);
assert.match(alertStyle[0], /colorPattern/);
assert.match(alertStyle[0], /borderPattern/);
assert.doesNotMatch(alertStyle[0], /Object\.assign|\.\.\.style/, 'alert styles must not accept arbitrary CSS keys');
const normalizeAlertStyle = Function(
    'isRecord',
    'boundedText',
    `${alertStyle[0]}\nreturn normalizeAlertStyle;`
)(
    value => value !== null && typeof value === 'object' && !Array.isArray(value),
    (value, fallback = '', maxLength = 4096) => typeof value === 'string' ? value.slice(0, maxLength) : fallback
);
assert.deepEqual(normalizeAlertStyle({
    color: 'var(--text-primary)',
    border: '1px solid #abc',
    backgroundImage: 'url(https://example.invalid/tracker)',
    position: 'fixed'
}), {
    color: 'var(--text-primary)',
    border: '1px solid #abc'
});
assert.equal(normalizeAlertStyle({ color: 'red', border: '99px solid red' }), undefined);

for (const semanticContract of [
    /className: 'cortex-menu-body'[\s\S]*?role: 'listbox'/,
    /className: `cortex-menu-option[\s\S]*?role: 'option'[\s\S]*?'aria-selected'/,
    /className: `cx-dialog-check[\s\S]*?role: 'checkbox'[\s\S]*?'aria-checked'/,
    /className: `cx-dropdown-trigger[\s\S]*?role: 'combobox'[\s\S]*?'aria-expanded'/,
    /className: 'cortex-settings-tabs'[\s\S]*?role: 'tablist'/,
    /role: 'tabpanel'[\s\S]*?'aria-labelledby'/,
    /role: 'progressbar'[\s\S]*?'aria-valuenow'/,
    /className,[\s\S]*?role: urgent \? 'alert' : 'status'[\s\S]*?'aria-live'/,
    /id: 'textui'[\s\S]*?role: 'status'[\s\S]*?'aria-live'/
]) {
    assert.match(uiSource, semanticContract);
}

assert.match(uiSource, /htmlFor: inputId/);
assert.match(uiSource, /'aria-describedby': field\.description \? descriptionId : undefined/);
assert.match(uiSource, /handleTabKeyDown[\s\S]*?ArrowRight[\s\S]*?ArrowLeft[\s\S]*?Home[\s\S]*?End/);
assert.match(uiSource, /displayItems\.length > 0 && \(key === 'ArrowRight'/, 'an empty radial must not perform modulo-zero navigation');
assert.match(uiSource, /key === 'Tab' && displayItems\.length > 0/, 'an empty radial must not cycle a modulo-zero selection');
assert.match(notifyClient, /normalized\.canCancel and IsControlJustPressed\(0, 177\)/);
assert.match(uiSource, /'Backspace to cancel'/, 'progress help must describe the control 177 keyboard binding');
assert.doesNotMatch(uiSource, /'Right-click to cancel'/, 'progress help must not advertise an unimplemented NUI mouse action');

const dialogStyles = read('ui', 'surfaces', 'dialogs.css');
assert.match(dialogStyles, /\.cx-dialog-layer\s*{[\s\S]*?position: fixed;[\s\S]*?inset: 0;[\s\S]*?padding: calc\(176 \* var\(--u\)\) calc\(16 \* var\(--u\)\) calc\(72 \* var\(--u\)\)/,
    'dialogs sit centre-low inside viewport padding');
assert.match(dialogStyles, /\.cx-dialog-layer::before\s*{[\s\S]*?background: var\(--ink\);[\s\S]*?opacity: 0\.(?:[0-3]\d*|40?);/,
    'the scrim is ink at 40% or less');
assert.match(dialogStyles, /\.cx-dialog\s*{[\s\S]*?width: min\(calc\(520 \* var\(--u\)\), 100%\);[\s\S]*?max-height: 100%;[\s\S]*?background: var\(--slip\)/,
    'the dialog is a bounded 520u slip');
assert.doesNotMatch(dialogStyles.replace(/@media[^{]*/g, ''), /gradient\(|backdrop-filter|outline:|\d+px/,
    'dialogs use tokens and --u only: no gradients, blur, outlines or raw px');
assert.match(styles, /@media \(max-height: 700px\)[\s\S]*?\.cortex-menu-body/);
assert.match(styles, /@media \(max-width: 560px\)[\s\S]*?\.cortex-settings-live-note[\s\S]*?white-space: normal/);
assert.match(styles, /\.cortex-sr-only\s*{[\s\S]*?clip: rect/);
assert.match(styles, /\.progress-container\s*{[\s\S]*?width: min\([^;]*100vw - 48 \* var\(--u\)/, 'progress stays inside narrow viewports');
assert.match(styles, /\.progress-container\.top\s*{[\s\S]*?top: clamp/);
assert.match(styles, /\.progress-container\.middle\s*{[\s\S]*?top: 50%[\s\S]*?translate\(-50%, -50%\)/);
assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.notify[\s\S]*?animation: none/);
assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.cortex-settings-btn[\s\S]*?transition: none/);

console.log('UI accessibility and lifecycle contract: PASS');
