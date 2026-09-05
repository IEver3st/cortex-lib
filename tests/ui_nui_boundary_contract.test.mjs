import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const uiSource = readFileSync(path.join(testDir, '..', 'ui', 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const notifyClientSource = readFileSync(path.join(testDir, '..', 'imports', 'notify', 'client.lua'), 'utf8').replace(/\r\n/g, '\n');

const isRecordSource = uiSource.match(/function isRecord\(value\) \{[\s\S]*?\n\}/);
const normalizeMessageSource = uiSource.match(/function normalizeNuiMessage\(event\) \{[\s\S]*?\n\}/);
assert.ok(isRecordSource && normalizeMessageSource, 'the bounded NUI message decoder must remain independently testable');

const normalizeNuiMessage = Function(
    `${isRecordSource[0]}\n${normalizeMessageSource[0]}\nreturn normalizeNuiMessage;`
)();

for (const malformed of [undefined, null, 1, 'message', [], { data: null }, { data: 5 }, { data: [] }]) {
    assert.equal(normalizeNuiMessage(malformed), null, 'scalar and malformed window messages must be ignored');
}
assert.deepEqual(
    normalizeNuiMessage({ data: { action: 'notify', data: 'not-an-object' } }),
    { action: 'notify', data: {} },
    'scalar message payloads must degrade to a safe record'
);
assert.equal(
    normalizeNuiMessage({ data: { action: 'x'.repeat(65), data: {} } }),
    null,
    'action names must remain bounded'
);

assert.equal((uiSource.match(/\bfetch\(/g) || []).length, 1, 'all NUI callbacks must share the single bounded transport');
const nuiPost = uiSource.match(/async function nuiPost\(name, payload, options = \{\}\) \{[\s\S]*?\n\}/);
assert.ok(nuiPost, 'shared NUI transport must remain discoverable');
assert.match(nuiPost[0], /\^\[a-z0-9:_-\]\+\$/i, 'NUI callback routes must be allowlisted');
assert.match(nuiPost[0], /AbortController/);
assert.match(nuiPost[0], /const requestPromise = \(async \(\) =>/);
assert.match(nuiPost[0], /Promise\.race/);
assert.match(nuiPost[0], /error: 'timeout'/);
assert.match(nuiPost[0], /error: 'http_error'/);
assert.match(nuiPost[0], /error: 'network_error'/);
assert.match(nuiPost[0], /JSON\.stringify\(isRecord\(payload\) \? payload : \{\}\)/);
assert.match(nuiPost[0], /finally[\s\S]*?clearTimeout[\s\S]*?removeEventListener/);

const makeNuiPost = (windowMock, fetchMock) => Function(
    'window',
    'fetch',
    'AbortController',
    'GetParentResourceName',
    'uiDebugLog',
    'boundedText',
    'isRecord',
    'NUI_POST_TIMEOUT_MS',
    `${nuiPost[0]}\nreturn nuiPost;`
)(
    windowMock,
    fetchMock,
    class AbortControllerMock { constructor() { this.signal = {}; } abort() {} },
    () => 'cortex-lib',
    () => {},
    (value, fallback = '', maxLength = 4096) => typeof value === 'string' ? value.slice(0, maxLength) : fallback,
    value => value !== null && typeof value === 'object' && !Array.isArray(value),
    5000
);

const realTimerWindow = { setTimeout, clearTimeout };
let requestInit;
const successfulPost = makeNuiPost(realTimerWindow, async (_url, init) => {
    requestInit = init;
    return { ok: true, json: async () => ({ ok: true, accepted: true }) };
});
assert.deepEqual(await successfulPost('valid_route', 'scalar'), { ok: true, accepted: true });
assert.equal(requestInit.body, '{}', 'a scalar POST payload must serialize as an empty record');
assert.deepEqual(await successfulPost('../escape', {}), { ok: false, error: 'invalid_route' });

const networkFailurePost = makeNuiPost(realTimerWindow, async () => { throw new Error('offline'); });
assert.deepEqual(await networkFailurePost('valid_route', {}), { ok: false, error: 'network_error' });

const immediateTimerWindow = {
    setTimeout(callback) { callback(); return 1; },
    clearTimeout() {}
};
const timeoutPost = makeNuiPost(immediateTimerWindow, () => new Promise(() => {}));
assert.deepEqual(await timeoutPost('valid_route', {}), { ok: false, error: 'timeout' });
const bodyTimeoutPost = makeNuiPost(immediateTimerWindow, async () => ({
    ok: true,
    json: () => new Promise(() => {})
}));
assert.deepEqual(
    await bodyTimeoutPost('valid_route', {}),
    { ok: false, error: 'timeout' },
    'the same deadline must cover response body parsing'
);

assert.match(uiSource, /async function copyTextToClipboard[\s\S]*?NUI_MAX_CLIPBOARD_LENGTH/);
assert.match(uiSource, /navigator\.clipboard[\s\S]*?writeText/);
assert.match(uiSource, /document\.createElement\('textarea'\)[\s\S]*?execCommand\('copy'\)[\s\S]*?textarea\.remove\(\)/);
assert.match(uiSource, /case 'copyToClipboard':[\s\S]*?copyTextToClipboard\(data\.text\)[\s\S]*?\.catch\(/);

for (const callback of [
    'cortex_menu_selected',
    'cortex_menu_close',
    'cortex_menu_sideScroll',
    'cortex_menu_check',
    'cortex_menu_submit',
    'radialClick',
    'radialBack',
    'radialClose',
    'settingsReady',
    'settingsPreview',
    'settingsPreviewSound',
    'settingsSave',
    'settingsCancel',
    'settingsAction',
    'alertDialogResult',
    'contextMenuResult',
    'cortex:uiEvent'
]) {
    const escaped = callback.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    assert.match(
        uiSource,
        new RegExp(`nuiPost\\('${escaped}',[\\s\\S]{0,220}?session`),
        `${callback} must echo the active modal session`
    );
}

for (const callback of [
    'cortex_menu_selected',
    'cortex_menu_close',
    'cortex_menu_sideScroll',
    'cortex_menu_check',
    'cortex_menu_submit'
]) {
    assert.match(
        uiSource,
        new RegExp(`nuiPost\\('${callback}',[\\s\\S]{0,220}?revision`),
        `${callback} must echo the currently rendered menu revision`
    );
}
assert.match(uiSource, /case 'menuOpen':[\s\S]*?openMenu\(data\)/);
assert.match(uiSource, /revision: normalizeRevision\(data\?\.revision\)/);
assert.ok(
    (uiSource.match(/nextRevision <= prev\.revision/g) || []).length >= 2,
    'bulk and single-option menu updates must reject stale or duplicate revisions'
);
assert.ok(
    (uiSource.match(/prev\.revision === normalizeRevision\(revision\)/g) || []).length >= 2,
    'an async close or submit response must not close a newer rendered revision'
);
assert.match(uiSource, /menu selection response failed[\s\S]*?selectedRef\.current = previousSelected|selectedRef\.current = previousSelected[\s\S]*?menu selection response failed/);
assert.match(uiSource, /menu side scroll response failed[\s\S]*?rollbackOptions\[idx\] = opt|rollbackOptions\[idx\] = opt[\s\S]*?menu side scroll response failed/);
assert.match(uiSource, /menu check response failed[\s\S]*?rollbackOptions\[idx\] = opt|rollbackOptions\[idx\] = opt[\s\S]*?menu check response failed/);
assert.ok(
    (uiSource.match(/prev\.revision !== normalizeRevision\(revision\)/g) || []).length >= 3,
    'optimistic menu rollbacks must be scoped to the still-rendered revision'
);

for (const action of [
    'menuClose',
    'alertDialogClose',
    'contextMenuClose',
    'uiAppData',
    'uiAppClose',
    'radialHide',
    'radialRefresh',
    'radialTransitionOut',
    'radialTransitionIn',
    'settingsClose'
]) {
    assert.match(
        uiSource,
        new RegExp(`case '${action}':[\\s\\S]{0,420}?session[\\s\\S]{0,160}?normalizeSession\\(data\\.session\\)`),
        `${action} must ignore stale sessions`
    );
}

assert.match(uiSource, /closeAlertDialog[\s\S]*?await nuiPost\('alertDialogResult'[\s\S]*?response\?\.ok !== true[\s\S]*?prev\.session === normalizedSession/);
assert.match(uiSource, /closeContextMenu[\s\S]*?await nuiPost\('contextMenuResult'[\s\S]*?response\?\.ok !== true[\s\S]*?prev\.session === normalizedSession/);
assert.match(uiSource, /closeSettingsPanelLocal[\s\S]*?prev\.session === normalizeSession\(session\)/);
assert.match(
    uiSource,
    /nuiPost\('settingsReady', \{ session \}\)\.then\(response => \{[\s\S]*?response\?\.ok === true[\s\S]*?nuiPost\('settingsCancel', \{ session \}\)[\s\S]*?onClose\(session\)/,
    'a failed settingsReady acknowledgement must clean up and close only its captured session'
);
assert.match(uiSource, /sessionRef\.current = normalizeSession\(session\)/, 'settings async failures must be scoped to the active session');
assert.ok(
    (uiSource.match(/sessionRef\.current !== capturedSession/g) || []).length >= 2,
    'stale Save and Cancel responses must not update a replacement settings session'
);
assert.match(uiSource, /closeEditor[\s\S]*?response\?\.ok !== true[\s\S]*?\?\.session === normalizeSession\(session\)/);
assert.match(uiSource, /closeMenu[\s\S]*?response\?\.ok !== true[\s\S]*?prev\.id === id[\s\S]{0,100}?prev\.session === normalizeSession\(session\)/);

const rootListener = uiSource.match(/\/\/ NUI message handler[\s\S]*?window\.addEventListener\('message', handleMessage\);[\s\S]*?\n    \}, \[([^\]]*)\]\);/);
assert.ok(rootListener, 'the root NUI listener must remain discoverable');
assert.doesNotMatch(rootListener[1], /notifications|notifyPosition/, 'transient state must not churn the root message listener');
assert.match(uiSource, /normalizeNotificationData[\s\S]*?600000/);
const normalizeNotificationSource = uiSource.match(/function normalizeNotificationData\(data\) \{[\s\S]*?\n\}/);
const clearNotificationsSource = uiSource.match(/function filterNotificationsForClear\(notifications, data\) \{[\s\S]*?\n\}/);
const notificationDedupeSource = uiSource.match(/function getNotificationDedupeKey\(notification\) \{[\s\S]*?\n\}/);
const notificationMergeSource = uiSource.match(/function mergeNotificationState\(notifications, normalized, generatedId\) \{[\s\S]*?\n\}/);
assert.ok(normalizeNotificationSource && clearNotificationsSource && notificationDedupeSource && notificationMergeSource,
    'notification ownership and identity helpers must remain independently testable');
const notificationHelpers = Function(
    'isRecord',
    'boundedText',
    'NUI_MAX_NOTIFICATIONS',
    `${normalizeNotificationSource[0]}\n${clearNotificationsSource[0]}\n${notificationDedupeSource[0]}\n${notificationMergeSource[0]}\nreturn { normalizeNotificationData, filterNotificationsForClear, getNotificationDedupeKey, mergeNotificationState };`
)(
    value => value !== null && typeof value === 'object' && !Array.isArray(value),
    (value, fallback = '', maxLength = 4096) => typeof value === 'string' ? value.slice(0, maxLength) : fallback,
    12
);
assert.equal(notificationHelpers.normalizeNotificationData({ owner: 'a'.repeat(120) }).owner.length, 96, 'notification owners must be bounded');
const ownedNotifications = [
    { id: 'one', owner: 'resource-a' },
    { id: 'two', owner: 'resource-b' },
    { id: 'three', owner: 'resource-a' }
];
assert.deepEqual(
    notificationHelpers.filterNotificationsForClear(ownedNotifications, { owner: 'resource-a' }),
    [{ id: 'two', owner: 'resource-b' }],
    'an owner clear must retain other resources notifications'
);
assert.strictEqual(
    notificationHelpers.filterNotificationsForClear(ownedNotifications, {}),
    ownedNotifications,
    'a clear without explicit owner or global authority must be ignored'
);
assert.deepEqual(notificationHelpers.filterNotificationsForClear(ownedNotifications, { all: true }), []);
assert.notEqual(
    notificationHelpers.getNotificationDedupeKey({ owner: 'resource-a', type: 'info', title: '', description: 'same' }),
    notificationHelpers.getNotificationDedupeKey({ owner: 'resource-b', type: 'info', title: '', description: 'same' }),
    'identical notifications from different resources must not dedupe together'
);
const addNotificationState = (state, payload, generatedId) => notificationHelpers.mergeNotificationState(
    state, notificationHelpers.normalizeNotificationData(payload), generatedId
);
let notificationState = addNotificationState([], {
    id: 'transport-a1', explicitId: false, owner: 'resource-a', type: 'info', description: 'same', dedupe: true
}, 'fallback-1');
notificationState = addNotificationState(notificationState, {
    id: 'transport-a2', explicitId: false, owner: 'resource-a', type: 'info', description: 'same', dedupe: true
}, 'fallback-2');
assert.equal(notificationState.length, 1, 'identical anonymous same-owner notifications must visually dedupe');
assert.equal(notificationState[0].id, 'transport-a1', 'anonymous dedupe must refresh the existing rendered identity');
assert.equal(notificationState[0].refreshTick, 1, 'anonymous dedupe must refresh its visual lifetime');
notificationState = addNotificationState(notificationState, {
    id: 'transport-b1', explicitId: false, owner: 'resource-b', type: 'info', description: 'same', dedupe: true
}, 'fallback-3');
assert.equal(notificationState.length, 2, 'identical anonymous notifications from different owners must remain separate');
notificationState = addNotificationState(notificationState, {
    id: 'transport-a3', explicitId: false, owner: 'resource-a', type: 'info', description: 'same', dedupe: false
}, 'fallback-4');
assert.equal(notificationState.length, 3, 'anonymous dedupe=false notifications must remain separate');
notificationState = addNotificationState(notificationState, {
    id: 'explicit-a', explicitId: true, owner: 'resource-a', type: 'success', description: 'old'
}, 'fallback-5');
notificationState = addNotificationState(notificationState, {
    id: 'explicit-a', explicitId: true, owner: 'resource-a', type: 'success', description: 'new'
}, 'fallback-6');
assert.equal(notificationState.filter(item => item.id === 'explicit-a').length, 1,
    'explicit owner-isolated transport IDs must replace their existing entry');
assert.equal(notificationState.find(item => item.id === 'explicit-a').description, 'new');
assert.equal(notificationState.filter(item => item.id !== 'explicit-a').length, 3,
    'explicit replacement must not disturb anonymous or other-owner entries');
assert.equal(notificationState.filter(item => item.id !== 'transport-b1').length, notificationState.length - 1,
    'hide-by-internal-ID filtering must continue to target exactly one notification');
assert.deepEqual(
    notificationHelpers.filterNotificationsForClear(notificationState, { owner: 'resource-a' }),
    notificationState.filter(item => item.owner !== 'resource-a'),
    'owner clear must remain compatible with merged notification state'
);
assert.match(uiSource, /const dedupeKey = getNotificationDedupeKey\(normalized\)/);
assert.match(uiSource, /explicitId: id !== null && data\.explicitId !== false/);
assert.match(uiSource, /owner: normalized\.owner/, 'new and replaced notifications must retain owner state');
assert.match(uiSource, /case 'clearNotifications':[\s\S]*?clearNotifications\(data\)/);
assert.match(notifyClientSource, /normalized\.owner = owner[\s\S]*?SendNUIMessage\(\{ action = 'notify'/);
assert.match(notifyClientSource, /normalized\.id = entry\.internalId/, 'caller IDs must map to owner-isolated internal NUI IDs');
assert.match(notifyClientSource, /explicitId = data\.id ~= nil/, 'Lua must distinguish public IDs from anonymous transport IDs');
assert.match(notifyClientSource, /clearNotifications'[\s\S]*?data = \{ owner = owner \}/);
assert.match(notifyClientSource, /clearNotifications'[\s\S]*?data = \{ all = true \}/);
assert.match(uiSource, /function isSafeObjectKey[\s\S]*?'__proto__'[\s\S]*?'constructor'/);
assert.match(uiSource, /normalizeSettingsTabs[\s\S]*?Object\.prototype\.hasOwnProperty\.call\(sourceValues, field\.key\)/);
assert.match(uiSource, /setFormValues\(nextValues\)/, 'context results must contain only declared, normalized fields');
assert.match(uiSource, /const matchedOption = field\.options\.find\([\s\S]*?return Object\.is\(optionValue, sourceValue\);/,
    'context select initialization must preserve scalar type identity');
assert.doesNotMatch(uiSource, /Object\.is\(optionValue, sourceValue\)\s*\|\|/,
    'numeric and string context options must not initialize as each other');
assert.match(uiSource, /case 'textUIShow'[\s\S]*?style: normalizeAlertStyle\(data\.style\)/);
assert.match(notificationMergeSource[0], /return next\.slice\(-NUI_MAX_NOTIFICATIONS\)/,
    'notification merges must retain the bounded visual state cap');
assert.match(uiSource, /data\.fields\.slice\(0, NUI_MAX_CONTEXT_FIELDS\)/);
assert.match(uiSource, /items\.slice\(0, NUI_MAX_MENU_OPTIONS\)/);

console.log('NUI boundary contract: PASS');
