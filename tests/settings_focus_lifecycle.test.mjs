import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const source = readFileSync(
    path.join(testDir, '..', 'imports', 'settings', 'client.lua'),
    'utf8'
).replace(/\r\n/g, '\n');
const uiSource = readFileSync(
    path.join(testDir, '..', 'ui', 'app.js'),
    'utf8'
).replace(/\r\n/g, '\n');

const openSettingsMatch = source.match(
    /function lib\.openSettings\(\)([\s\S]*?)\nend\n\nfunction lib\.openSettingsMenu/
);

assert.ok(openSettingsMatch, 'lib.openSettings() must remain discoverable by the lifecycle regression test');

const openSettings = openSettingsMatch[1];
const payloadIndex = openSettings.indexOf('buildTabsPayload()');
const messageIndex = openSettings.indexOf('SendNUIMessage({');

assert.notEqual(payloadIndex, -1, 'openSettings() must build the settings payload');
assert.notEqual(messageIndex, -1, 'openSettings() must send the settings payload');
assert.ok(
    payloadIndex < messageIndex,
    'settings payload construction must finish before the panel is opened'
);
assert.doesNotMatch(
    openSettings,
    /SetNuiFocus\(true, true\)/,
    'openSettings() must wait for a rendered-panel acknowledgement before acquiring NUI focus'
);

const readyMatch = source.match(
    /RegisterNUICallback\('settingsReady',[\s\S]*?function\(data, cb\)([\s\S]*?)\nend\)/
);
assert.ok(readyMatch, 'settingsReady callback must remain registered');
assert.match(readyMatch[1], /matchesSettingsModal\(data\)/, 'settingsReady must reject a stale session');
assert.match(readyMatch[1], /focusSettingsModal\(settingsSession\)/, 'settingsReady must acquire focus for the active session');
assert.match(
    source,
    /local function focusSettingsModal\(session\)[\s\S]*?SetNuiFocus\(true, true\)/,
    'the settings focus helper must preserve the native focus fallback'
);
assert.match(
    uiSource,
    /function SettingsPanel[\s\S]*?if \(!open\) return;[\s\S]*?nuiPost\('settingsReady', \{ session \}\)/,
    'the rendered settings panel must acknowledge readiness before Lua acquires focus'
);

const releaseMatch = source.match(
    /local function releaseSettingsFocus\(\)([\s\S]*?)\nend/
);
assert.ok(releaseMatch, 'settings focus release must be centralized');
assert.match(releaseMatch[1], /settingsOpen\s*=\s*false/);
assert.match(releaseMatch[1], /SetNuiFocus\(false, false\)/);

const saveMatch = source.match(
    /RegisterNUICallback\('settingsSave',[\s\S]*?function\(data, cb\)([\s\S]*?)\nend\)/
);
assert.ok(saveMatch, 'settingsSave callback must remain registered');
assert.ok(
    saveMatch[1].indexOf('commitPreviewValues(') < saveMatch[1].indexOf('releaseSettingsFocus()'),
    'settingsSave must keep the modal session active until the transactional commit succeeds'
);
assert.match(
    saveMatch[1],
    /if not ok then[\s\S]*?restorePersistedValues[\s\S]*?rollbackPreviewValues\(\)[\s\S]*?beginPreviewSession\(\)[\s\S]*?cb\(\{ ok = false/,
    'a failed settings commit must restore data and leave a retryable preview session open'
);

const cancelMatch = source.match(
    /RegisterNUICallback\('settingsCancel',[\s\S]*?function\(data, cb\)([\s\S]*?)\nend\)/
);
assert.ok(cancelMatch, 'settingsCancel callback must remain registered');
assert.match(cancelMatch[1], /matchesSettingsModal\(data\)/, 'settingsCancel must reject a stale session');
assert.match(cancelMatch[1], /releaseSettingsFocus\(\)/);

assert.match(
    source,
    /AddEventHandler\('onResourceStop',[\s\S]*?resourceName\s*==\s*CURRENT_RESOURCE[\s\S]*?releaseSettingsFocus\(\)/,
    'stopping cortex-lib must release settings focus'
);

console.log('settings focus lifecycle: PASS');
