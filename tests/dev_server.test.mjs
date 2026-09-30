import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { handleRequest, previewHtml } from '../dev/server.mjs';
import { scenarios } from '../dev/scenarios.mjs';

test('dev server serves the real offline NUI with an injected browser-only bridge', async () => {
    const source = await readFile(new URL('../ui/index.html', import.meta.url), 'utf8');
    const response = await handleRequest(new Request('http://localhost/preview'));
    assert.equal(response.status, 200);
    const html = await response.text();
    assert.equal(html, previewHtml(source));
    assert.ok(html.indexOf('/dev/bridge.js') < html.indexOf('app.js'));
    assert.match(html, /vendor\/react\.production\.min\.js/);
    assert.doesNotMatch(html, /https:\/\/cfx-nui/);
    assert.doesNotMatch(source, /dev\/|localhost|127\.0\.0\.1/);
    assert.match(await (await handleRequest(new Request('http://localhost/ui/app.js'))).text(), /function App/);
});

test('dev server limits files and methods, including encoded traversal and Windows paths', async () => {
    for (const path of ['/fxmanifest.lua', '/AGENTS.md', '/.env', '/dev/server.mjs', '/dev/../server/config.lua',
        '/ui/%2e%2e%2fREADME.md', '/ui/%5c..%5cREADME.md', '/ui/C:/Windows/win.ini', '/ui/missing.js']) {
        assert.equal((await handleRequest(new Request(`http://localhost${path}`))).status, 404, path);
    }
    assert.equal((await handleRequest(new Request('http://localhost/%zz'))).status, 400);
    assert.equal((await handleRequest(new Request('http://localhost/', { method: 'POST' }))).status, 405);
    const head = await handleRequest(new Request('http://localhost/ui/core/base.css', { method: 'HEAD' }));
    assert.equal(head.status, 200);
    assert.equal(head.headers.get('content-type'), 'text/css');
    assert.equal(await head.text(), '');
    assert.deepEqual(await (await handleRequest(new Request('http://localhost/__revision'), 'changed')).json(), { revision: 'changed' });
});

test('catalog covers every renderer family without duplicating production code', () => {
    assert.equal(new Set(scenarios.map(item => item.id)).size, scenarios.length);
    const actions = new Set(scenarios.flatMap(item => item.messages.map(message => message.action)));
    for (const action of ['notify', 'progressStart', 'menuOpen', 'radialShow', 'alertDialog', 'contextMenu',
        'textUIShow', 'helpShow', 'debugPanelShow', 'interaction:update', 'interaction:world', 'settingsOpen',
        'skill:open', 'debug:open', 'debug:walkthrough', 'cortex:presentation']) assert.ok(actions.has(action), action);
    for (const item of scenarios) {
        assert.ok(item.id && item.title && item.group && item.description);
        for (const message of item.messages) {
            assert.equal(typeof message.action, 'string');
            assert.ok(message.data && typeof message.data === 'object');
            assert.ok(!message.after || (Number.isFinite(message.after) && message.after >= 0));
        }
    }
});
