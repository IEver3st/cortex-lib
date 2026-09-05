import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...parts) => readFileSync(path.join(testDir, '..', ...parts), 'utf8').replace(/\r\n/g, '\n');
const uiSource = read('ui', 'app.js');
const styles = read('ui', 'style.css');
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
    /useModalFocus\(Boolean\(open\), editorRef, null, session\)/,
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
assert.match(alertDialog[0], /type: 'button'/);

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
    /className: 'cortex-context-checkbox'[\s\S]*?role: 'checkbox'[\s\S]*?'aria-checked'/,
    /className: 'cortex-context-select-trigger'[\s\S]*?role: 'combobox'[\s\S]*?'aria-expanded'/,
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
assert.match(uiSource, /displayItems\.length > 0 && \(e\.key === 'ArrowRight'/, 'an empty radial must not perform modulo-zero navigation');
assert.match(notifyClient, /normalized\.canCancel and IsControlJustPressed\(0, 177\)/);
assert.match(uiSource, /'Backspace to cancel'/, 'progress help must describe the control 177 keyboard binding');
assert.doesNotMatch(uiSource, /'Right-click to cancel'/, 'progress help must not advertise an unimplemented NUI mouse action');

assert.match(styles, /\.alert-dialog\s*{[\s\S]*?max-width: calc\(100vw - 24px\)[\s\S]*?max-height: calc\(100vh - 24px\)/);
assert.match(styles, /\.cortex-context-dialog\s*{[\s\S]*?max-width: calc\(100vw - 24px\)[\s\S]*?max-height: calc\(100vh - 24px\)/);
assert.match(styles, /--cortex-editor-sidebar-width:[^;]*44vw/);
assert.match(styles, /--cortex-editor-panel-width:[^;]*56vw/);
assert.match(styles, /@media \(max-height: 700px\)[\s\S]*?\.cortex-menu-body/);
assert.match(styles, /@media \(max-width: 560px\)[\s\S]*?\.cortex-settings-live-note[\s\S]*?white-space: normal/);
assert.match(styles, /\.cortex-sr-only\s*{[\s\S]*?clip: rect/);
assert.match(styles, /\.progress-container\s*{[\s\S]*?width: min\([^;]*100vw - 24px/);
assert.match(styles, /\.progress-container\.top\s*{[\s\S]*?top: clamp/);
assert.match(styles, /\.progress-container\.middle\s*{[\s\S]*?top: 50%[\s\S]*?translate\(-50%, -50%\)/);
assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.notify[\s\S]*?animation: none/);
assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.cortex-settings-btn[\s\S]*?transition: none/);

console.log('UI accessibility and lifecycle contract: PASS');
