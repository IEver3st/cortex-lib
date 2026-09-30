import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

function harness(resource = 'opticom', selectorOverride) {
    const callbacks = new Map(), timers = new Map(), requests = [];
    let nextTimer = 0, fail = false;
    function element() {
        const styles = new Map(), classes = new Set();
        return { nodeType: 1, parentElement: null, hidden: false, dataset: {},
            style: { getPropertyValue: key => styles.get(key) || '', setProperty: (key, value) => styles.set(key, value), removeProperty: key => styles.delete(key) },
            classList: { contains: key => classes.has(key), remove: key => classes.delete(key),
                toggle: (key, on) => on ? classes.add(key) : classes.delete(key) },
            getAttribute: () => null, removeAttribute() {},
        };
    }
    const root = element(), body = element(), chat = element();
    chat.parentElement = body; body.parentElement = root;
    chat.classList.toggle('chat-open', true);
    chat.querySelectorAll = () => [];
    chat.getBoundingClientRect = () => {
        const [dx = 0, dy = 0] = chat.style.getPropertyValue('translate').split(' ').filter(Boolean).map(parseFloat);
        return { x: 20 + dx, y: 20 + dy, width: 480, height: 350 };
    };
    const document = { documentElement: root, body,
        querySelectorAll: selector => selector === (selectorOverride || (resource === 'cortex-chat' ? '.es-chat' : '.receiver')) ? [chat] : [],
        addEventListener() {}, removeEventListener() {},
    };
    const window = { addEventListener: (key, fn) => callbacks.set(key, fn), removeEventListener: key => callbacks.delete(key) };
    const context = vm.createContext({ window, document, GetParentResourceName: () => resource,
        getComputedStyle: el => ({ display: el.hidden ? 'none' : 'block', visibility: 'visible', opacity: '1' }),
        innerWidth: 1920, innerHeight: 1080, AbortController,
        matchMedia: () => ({ matches: false, addEventListener() {}, removeEventListener() {} }),
        MutationObserver: class { observe() {} disconnect() {} }, ResizeObserver: class { observe() {} unobserve() {} disconnect() {} },
        setTimeout: (fn, delay) => { const id = ++nextTimer; timers.set(id, { fn, delay }); return id; },
        clearTimeout: id => timers.delete(id), setInterval: () => 999, clearInterval() {},
        fetch: async (url, options) => { requests.push({ url, data: JSON.parse(options.body) }); return { json: async () => ({ ok: !fail }) }; },
    });
    vm.runInContext(readFileSync(new URL('../ui/dynamic-layout.js', import.meta.url), 'utf8'), context);
    context.CortexLayout = window.CortexLayout;
    vm.runInContext(readFileSync(new URL('../ui/dynamic-ui.js', import.meta.url), 'utf8'), context);
    const settle = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
    return { chat, root, requests, fail: value => { fail = value; },
        message: data => callbacks.get('message')({ data }),
        tick: async () => { await settle(); for (const [id, timer] of [...timers]) if (timer.delay === 200) { timers.delete(id); timer.fn(); } await settle(); },
    };
}
const snapshot = {
    action: 'cortex:presentation', data: { v: 1, revision: 1, profile: { accent: '#9bbcd3', opacity: 85, layout: true },
        viewport: { width: 1920, height: 1080, inset: 20 }, surfaces: [
            { key: 'opticom:receiver-0', owner: 'opticom', id: 'receiver-0', x: 20, y: 20, width: 480, height: 350, priority: 85, fixed: false },
            { key: 'camera:panel', owner: 'camera', id: 'panel', x: 20, y: 20, width: 500, height: 200, priority: 100, fixed: true },
        ] },
};
test('modal suppression applies only to passive chat, never a newly focused composer', () => {
    const css = readFileSync(new URL('../ui/dynamic-ui.css', import.meta.url), 'utf8');
    const chatHideRule = css.match(/([^{}]+)\{\s*visibility:\s*hidden;\s*pointer-events:\s*none;\s*\}/g)
        .find(rule => rule.includes('data-cortex-resource="cortex-chat"'));
    assert.ok(chatHideRule, 'passive chat still yields to modal menus');
    assert.match(chatHideRule, /\.es-chat:not\(\.chat-open\)/,
        'a delayed modal snapshot must not hide focused chat and trigger its heartbeat close');
});
test('adapter measures preferred geometry, deduplicates and releases hidden surfaces', async () => {
    const h = harness(); await h.tick();
    h.message(snapshot); await h.tick(); await h.tick();
    assert.equal(h.chat.style.getPropertyValue('translate'), '0px 210px');
    const writes = () => h.requests.filter(request => request.url.endsWith('cortexPresentationSurfaces'));
    assert.equal(writes().length, 1, 'applying displacement must not echo a changed preferred position');
    assert.equal(writes()[0].data.surfaces[0].y, 20);
    assert.equal(h.root.style.getPropertyValue('--cx-accent'), '#9bbcd3');
    assert.equal(h.root.style.getPropertyValue('--cx-accent-rgb'), '155, 188, 211');
    assert.equal(h.root.style.getPropertyValue('--cx-accent-deep'), 'hsl(205, 43%, 31%)');
    assert.equal(h.root.style.getPropertyValue('--cx-surface-alpha'), '0.85');
    h.chat.hidden = true; h.message({ action: 'close' }); await h.tick();
    assert.equal(writes().at(-1).data.surfaces.length, 0);
    assert.equal(h.chat.style.getPropertyValue('translate'), '');
});
test('failed writes retry and broker restart republishes unchanged geometry', async () => {
    const h = harness(); h.fail(true); await h.tick();
    h.fail(false); await h.tick();
    let writes = h.requests.filter(request => request.url.endsWith('cortexPresentationSurfaces'));
    assert.equal(writes.length, 2);
    h.message({ action: 'cortex:presentationReset' }); await h.tick();
    writes = h.requests.filter(request => request.url.endsWith('cortexPresentationSurfaces'));
    assert.equal(writes.length, 3);
});
test('every resource follows the shared profile; disabling layout restores placement', async () => {
    const h = harness(); await h.tick(); h.message(snapshot);
    assert.equal(h.root.classList.contains('cortex-shared-style'), true);
    const data = structuredClone(snapshot);
    data.data.revision = 2;
    data.data.profile.layout = false;
    // A snapshot from an older cortex-lib may still carry the retired opt-out.
    data.data.profile.independent = { opticom: true };
    data.data.profile.motion = 'reduced';
    h.message(data);
    assert.equal(h.root.classList.contains('cortex-shared-style'), true, 'the retired independent opt-out is ignored');
    assert.equal(h.root.classList.contains('cortex-reduced-motion'), true);
    assert.equal(h.root.dataset.cxMotion, 'reduced');
    assert.equal(h.chat.style.getPropertyValue('translate'), '');
});
test('malformed and stale snapshots cannot corrupt current placement', async () => {
    const h = harness(); await h.tick(); h.message(snapshot);
    h.message({ action: 'cortex:presentation', data: { ...snapshot.data, surfaces: [null] } });
    h.message({ action: 'cortex:presentation', data: { ...snapshot.data, revision: 0, surfaces: [] } });
    assert.equal(h.chat.style.getPropertyValue('translate'), '0px 210px');
});

test('chat remains anchored across opening, delayed snapshots and closing', async () => {
    const h = harness('cortex-chat');
    h.chat.classList.toggle('chat-open', false);
    await h.tick();
    const writes = () => h.requests.filter(request => request.url.endsWith('cortexPresentationSurfaces'));
    assert.equal(writes().at(-1).data.surfaces.length, 0);
    for (let cycle = 0; cycle < 3; cycle++) {
        h.chat.classList.toggle('chat-open', true);
        h.message({ action: 'ON_OPEN' }); await h.tick();
        assert.equal(writes().at(-1).data.surfaces[0].fixed, true);
        const delayed = structuredClone(snapshot);
        Object.assign(delayed.data.surfaces[0], { key: 'cortex-chat:chat-0', owner: 'cortex-chat', id: 'chat-0' });
        // Even a stale pre-fix registration must never move an active input.
        h.message(delayed); await h.tick();
        assert.equal(h.chat.style.getPropertyValue('translate'), '');
        assert.equal(h.chat.getBoundingClientRect().y, 20);
        h.chat.classList.toggle('chat-open', false);
        h.message({ action: 'ON_CLOSE' }); await h.tick();
        assert.equal(writes().at(-1).data.surfaces.length, 0);
    }
});

test('notifications yield to visible chat and return when chat clears without geometry feedback', async () => {
    const chat = harness('cortex-chat');
    const notices = harness('cortex-lib', '#notify-container');
    // Closed chat with visible history must still reserve its screen area.
    chat.chat.classList.toggle('chat-open', false);
    chat.chat.querySelectorAll = () => [chat.chat];
    await chat.tick(); await notices.tick();
    const writes = h => h.requests.filter(request => request.url.endsWith('cortexPresentationSurfaces'));
    const reservation = (h, owner) => {
        const surface = writes(h).at(-1).data.surfaces[0];
        return { ...surface, owner, key: `${owner}:${surface.id}` };
    };
    const data = structuredClone(snapshot.data);
    data.surfaces = [reservation(chat, 'cortex-chat'), reservation(notices, 'cortex-lib')];
    const publish = () => {
        const message = { action: 'cortex:presentation', data: structuredClone(data) };
        chat.message(message); notices.message(message);
    };
    publish(); await notices.tick();
    const chatBounds = chat.chat.getBoundingClientRect();
    const noticeBounds = notices.chat.getBoundingClientRect();
    assert.ok(noticeBounds.y >= chatBounds.y + chatBounds.height + 10,
        'the real notification registration must let the stack move below visible chat');
    assert.equal(chat.chat.style.getPropertyValue('translate'), '', 'chat stays anchored');
    assert.equal(writes(notices).length, 1, 'displacement must not change preferred geometry');

    chat.chat.querySelectorAll = () => [];
    chat.message({ action: 'ON_CLOSE' }); await chat.tick();
    assert.equal(writes(chat).at(-1).data.surfaces.length, 0);
    data.revision++;
    data.surfaces = data.surfaces.filter(surface => surface.owner !== 'cortex-chat');
    publish(); await notices.tick();
    assert.equal(notices.chat.getBoundingClientRect().y, 20, 'notices return when chat clears');
    assert.equal(writes(notices).length, 1, 'restoring the anchor must not cause drift');
});

for (const [selector, id] of [['.progress-container', 'progress-0']]) {
    test(`${id} reserves its anchor and ignores stale movable registrations`, async () => {
        const h = harness('cortex-lib', selector); await h.tick();
        const write = h.requests.find(request => request.url.endsWith('cortexPresentationSurfaces'));
        assert.equal(write.data.surfaces[0].id, id);
        assert.equal(write.data.surfaces[0].fixed, true);
        const delayed = structuredClone(snapshot);
        Object.assign(delayed.data.surfaces[0], { key: `cortex-lib:${id}`, owner: 'cortex-lib', id });
        h.message(delayed); await h.tick();
        assert.equal(h.chat.style.getPropertyValue('translate'), '');
    });
}

test('hyphenated PolCam registers its camera and compass through the correct NUI endpoint', async () => {
    for (const [selector, id] of [['.panel', 'camera-0'], ['.compass-container', 'compass-0']]) {
        const h = harness('cortex-polcam', selector); await h.tick();
        const write = h.requests.find(request => request.url.endsWith('cortexPresentationSurfaces'));
        assert.ok(write, 'PolCam must participate in shared layout');
        assert.equal(write.url, 'https://cortex-polcam/cortexPresentationSurfaces');
        assert.equal(write.data.surfaces[0].id, id);
        assert.equal(write.data.surfaces[0].fixed, true);
        h.chat.hidden = true; h.message({ action: 'close' }); await h.tick();
        assert.equal(h.requests.filter(request => request.url.endsWith('cortexPresentationSurfaces')).at(-1).data.surfaces.length, 0);
    }
});
