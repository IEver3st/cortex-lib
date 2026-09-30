/* Injected only into /preview by the loopback development server. Never packaged. */
(() => {
    'use strict';
    const STORAGE = 'cortex-lib-lab-settings-v1';
    const run = new URLSearchParams(location.search).get('run');
    const report = (kind, data) => parent.postMessage({ lab: true, run, kind, data }, location.origin);
    const emit = (action, data = {}) => window.dispatchEvent(new MessageEvent('message', { data: { action, data } }));
    let config = {}, failNext = false, progress = null, skill = null, worldItems = [], settingsState = null;
    let holdStarted = 0, holdTimer = 0, holdRevision = 0, mashProgress = 0, traceProgress = 0;
    let progressTimer = 0, skillTimer = 0, mashTimer = 0, radialState = null, radialFocus = null;
    let debugSession = null;
    let presentation = null;
    let loaded = false, mounted = false, announced = false;
    const announce = () => { if (loaded && mounted && !announced) { announced = true; report('ready'); } };
    const delayed = new Set();
    const later = (fn, ms) => { const id = setTimeout(() => { delayed.delete(id); fn(); }, ms); delayed.add(id); return id; };
    const safeRead = () => { try { const value = JSON.parse(localStorage.getItem(STORAGE) || '{}'); return value && typeof value === 'object' && !Array.isArray(value) ? value : {}; } catch { return {}; } };
    const scheduleEmit = (action, data) => later(() => emit(action, data), 0);
    const log = (name, payload, response) => report('callback', { name, payload, response, simulated: true });
    window.GetParentResourceName = () => 'cortex-lib';

    function deliver(message) {
        const { action } = message;
        const data = structuredClone(message.data || {});
        if (action === 'cortex:presentation') presentation = data;
        if (action === 'cortex:presentationReset') presentation = null;
        if (action === 'settingsOpen') {
            const saved = safeRead();
            for (const tab of data.tabs || []) if (saved[tab.id]) {
                for (const field of tab.fields || []) if (Object.hasOwn(saved[tab.id], field.key)) tab.values[field.key] = saved[tab.id][field.key];
            }
            settingsState = { session: data.session, tabs: data.tabs || [], values: Object.fromEntries((data.tabs || []).map(tab => [tab.id, { ...tab.values }])) };
            settingsState.baseline = structuredClone(settingsState.values);
            if (settingsState.values.cortex) emitCortexPrefs(settingsState.values.cortex);
        }
        if (action === 'interaction:world') worldItems = data.items || [];
        if (action === 'radialShow') radialState = data;
        if (action === 'debug:open') debugSession = data.session;
        if (action === 'debug:close') debugSession = null;
        if (action === 'progressStart') {
            clearTimeout(progressTimer); progress = data;
            progressTimer = later(() => { progress = null; emit('progressEnd'); report('result', 'Simulated consumer progress completed.'); }, Math.max(0, Number(data.duration) || 0));
        }
        if (action === 'progressEnd') { clearTimeout(progressTimer); progress = null; }
        if (action === 'skill:open') {
            skill = data; clearTimeout(skillTimer); clearInterval(mashTimer); mashProgress = 0; traceProgress = 0; traceAngle = 0; tracePeak = 0;
            if (['mash', 'trace'].includes(data.config?.type)) skillTimer = later(() => finishSkill('timeout'), data.config.duration || 15000);
        }
        if (action === 'skill:close') { clearTimeout(skillTimer); clearInterval(mashTimer); skill = null; }
        emit(action, data);
    }

    function finishSkill(reason, success = false) {
        if (!skill) return;
        const session = skill.session;
        clearTimeout(skillTimer); clearInterval(mashTimer); skill = null;
        emit('skill:close', { session, success, reason: success ? 'success' : reason });
        report('result', { simulatedConsumer: true, session, success, reason });
    }

    function cancelHold(reason) {
        if (!holdStarted) return;
        clearTimeout(holdTimer); holdStarted = 0;
        worldItems = worldItems.map(item => ({ ...item, holdActive: false }));
        emit('interaction:world', { items: worldItems });
        report('result', `Simulated hold ${reason}.`);
    }

    // Simulates imports/settings/client.lua: Cortex tab values become cortex:prefs
    // (and the shared appearance profile) on ready, preview, Apply and Discard.
    const durationScale = { short: 0.75, standard: 1, long: 1.5 };
    function emitCortexPrefs(values) {
        if (!values) return;
        const prefs = {};
        if (Number.isFinite(values.uiScale)) prefs.scale = Math.round(values.uiScale) / 100;
        if (values.notifyDuration in durationScale) prefs.notifyDuration = durationScale[values.notifyDuration];
        for (const key of ['textSize', 'notifyLimit', 'showPercent', 'promptMarkers', 'promptScale', 'controlHints', 'invertScroll']) {
            if (Object.hasOwn(values, key)) prefs[key] = values[key];
        }
        scheduleEmit('cortex:prefs', { prefs });
        if (values.notifyPosition) scheduleEmit('notifySetPosition', { position: values.notifyPosition });
        if (!presentation) return;
        presentation = { ...presentation, revision: presentation.revision + 1, profile: { ...presentation.profile,
            accent: values.dynamic_accent, opacity: values.dynamic_opacity, motion: values.dynamic_motion, layout: values.dynamic_layout } };
        scheduleEmit('cortex:presentation', presentation);
    }

    async function callback(name, payload) {
        const maintenance = ['interactionReady', 'cortexPresentationReady', 'cortexPresentationSurfaces', 'cortexPrefsReady', 'settingsReady', 'skillReady', 'debugReady', 'cortex_menu_selected'];
        if (failNext && !maintenance.includes(name)) {
            failNext = false; report('failNext', false);
            return { ok: false, error: 'Intentional browser fixture failure' };
        }
        if (maintenance.includes(name)) {
            if (name === 'interactionReady') { mounted = true; later(announce, 0); }
            if (name === 'cortexPrefsReady') emitCortexPrefs(safeRead().cortex);
            if (name === 'skillReady') { if (skill?.session === payload.session) skill.started = true; scheduleEmit('skill:start', { session: payload.session }); }
            if (name === 'cortexPresentationReady') {
                presentation ||= { v: 1, revision: 0,
                    profile: { accent: '#8fcbbf', opacity: 92, motion: 'system', layout: false },
                    viewport: { width: innerWidth, height: innerHeight, inset: 0 }, surfaces: [] };
                scheduleEmit('cortex:presentation', presentation);
            }
            if (name === 'cortexPresentationSurfaces' && presentation) {
                // Simulate the Lua aggregator, using the renderer's measured surfaces.
                // Foreign occupied rectangles stay fixtures, not actual game geometry.
                presentation = { ...presentation, revision: presentation.revision + 1,
                    surfaces: [...presentation.surfaces.filter(item => item.owner !== 'cortex-lib'),
                        ...(payload.surfaces || []).map(item => ({ ...item, key: `cortex-lib:${item.id}`, owner: 'cortex-lib' }))] };
                scheduleEmit('cortex:presentation', presentation);
            }
            return { ok: true };
        }
        if (name === 'settingsPreview') {
            if (!settingsState || settingsState.session !== payload.session) return { ok: false, error: 'Stale settings session' };
            const tab = settingsState.tabs.find(item => item.id === payload.tabId);
            if (!tab) return { ok: false, error: 'Unknown settings tab' };
            const changes = payload.values || { [payload.key]: payload.value };
            for (const field of tab.fields) if (Object.hasOwn(changes, field.key)) settingsState.values[tab.id][field.key] = changes[field.key];
            if (tab.id === 'cortex') emitCortexPrefs(settingsState.values.cortex);
            return { ok: true, preview: settingsState.values };
        }
        if (name === 'settingsSave') {
            if (!settingsState || settingsState.session !== payload.session) return { ok: false, error: 'Stale settings session' };
            // This store is exclusively for the lab. No KVP/server state is touched.
            const saved = safeRead();
            for (const tab of settingsState.tabs) saved[tab.id] = { ...(payload.tabs?.[tab.id] || {}) };
            try { localStorage.setItem(STORAGE, JSON.stringify(saved)); }
            catch { return { ok: false, error: 'Browser storage is unavailable' }; }
            if (payload.keepOpen === true) settingsState.baseline = structuredClone(settingsState.values);
            return { ok: true, storage: 'browser only' };
        }
        if (name === 'settingsCancel') {
            // Discard restores the values from when the panel opened (or last Apply).
            if (settingsState?.baseline?.cortex) emitCortexPrefs(settingsState.baseline.cortex);
            settingsState = null;
            return { ok: true, rolledBack: true };
        }
        if (name === 'settingsAction') return { ok: true, simulated: true };
        if (name === 'settingsPreviewSound' || name.startsWith('pause')) return { ok: false, error: 'Native/game action requires FiveM' };
        if (['alertDialogResult', 'contextMenuResult', 'cortex_menu_close', 'cortex_menu_check', 'cortex_menu_sideScroll'].includes(name)) return { ok: true };
        if (name === 'cortex_menu_submit') return { ok: true, close: true };
        if (name === 'radialClick') {
            // Mirrors imports/radial/client.lua: out, 100 ms, in with the breadcrumb.
            const item = radialState?.items?.[payload.index];
            if (config.behavior === 'radial-submenu' && item?.menu && payload.menuId === radialState.menuId) {
                const child = { session: payload.session, menuId: item.menu, canGoBack: true, trail: [item.label], items: [
                    { id: 'child-a', label: 'Front left', icon: 'door', description: 'Open or close the door.' },
                    { id: 'child-b', label: 'Front right', icon: 'door' }, { id: 'child-c', label: 'Trunk', icon: 'box' },
                    { id: 'child-d', label: 'Hood', icon: 'car', disabled: true, description: 'Stand at the front of the vehicle.' }] };
                scheduleEmit('radialTransitionOut', { session: payload.session });
                later(() => emit('radialTransitionIn', child), 100);
                radialFocus = payload.index;
            } else scheduleEmit('radialHide', { session: payload.session });
            return { ok: true };
        }
        if (name === 'radialBack') {
            scheduleEmit('radialTransitionOut', { session: payload.session });
            later(() => emit('radialTransitionIn', { ...radialState, canGoBack: false, trail: [], focusIndex: radialFocus }), 100);
            return { ok: true };
        }
        if (name === 'radialClose') { scheduleEmit('radialHide', { session: payload.session }); return { ok: true }; }
        if (name === 'skillResult') { finishSkill(payload.reason, payload.success); return { ok: true }; }
        if (name === 'debugClose' || name === 'debugStop') { debugSession = null; scheduleEmit('debug:close', { session: payload.session }); return { ok: true }; }
        if (name === 'debugRun') { report('navigate', String(payload.id || '').replaceAll('_', '-')); return { ok: true }; }
        if (name === 'debugRunAll') { report('tour'); return { ok: true }; }
        if (name === 'debugClear') { scheduleEmit('debug:history', { session: payload.session, history: [] }); return { ok: true }; }
        if (name === 'cortex:uiEvent') {
            if (payload.type === 'close' || payload.type === 'save' || payload.type === 'saveBounds') return { ok: true, simulated: true };
            return { ok: false, error: 'World coordinates and calibration require FiveM' };
        }
        return { ok: false, error: `No browser mock for ${name}` };
    }

    const originalFetch = window.fetch.bind(window);
    window.fetch = async (input, options = {}) => {
        const url = new URL(typeof input === 'string' ? input : input.url, location.href);
        if (url.origin === location.origin) return originalFetch(input, options);
        if (url.origin !== 'https://cortex-lib') throw new Error(`External request blocked by browser lab: ${url.origin}`);
        const name = decodeURIComponent(url.pathname.slice(1));
        let payload = {};
        try { payload = JSON.parse(options.body || '{}'); } catch { /* malformed callback is logged */ }
        let response;
        try { response = await callback(name, payload); } catch (error) { response = { ok: false, error: error.message }; }
        log(name, payload, response);
        return new Response(JSON.stringify(response), { headers: { 'Content-Type': 'application/json' } });
    };

    window.addEventListener('message', event => {
        if (event.source !== parent || event.origin !== location.origin || !event.data?.lab) return;
        if (event.data.kind === 'configure') { config = event.data.data || {}; failNext = config.failNext === true; }
        if (event.data.kind === 'failNext') failNext = event.data.data === true;
        if (event.data.kind === 'messages') for (const item of event.data.data || []) {
            if (!item || typeof item.action !== 'string') continue;
            later(() => deliver(item), Math.max(0, Math.min(Number(item.after) || 0, 600000)));
        }
        if (event.data.kind === 'clearSettings') { try { localStorage.removeItem(STORAGE); report('result', 'Browser settings reset. Replay to load defaults.'); } catch { report('error', 'Browser storage unavailable'); } }
    });
    window.addEventListener('keydown', event => {
        if (['INPUT', 'TEXTAREA'].includes(event.target.tagName)) return;
        if (debugSession) {
            const input = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', Enter: 'enter', Escape: 'back' }[event.key];
            if (input) { event.preventDefault(); emit('debug:input', { session: debugSession, input }); }
        }
        if (event.key === 'Escape' || event.key === 'Backspace') {
            if (progress?.canCancel) { clearTimeout(progressTimer); progress = null; emit('progressEnd'); report('result', 'Simulated consumer progress canceled.'); }
            if (['trace', 'mash'].includes(skill?.config?.type)) finishSkill('cancelled');
            cancelHold('canceled');
        }
        if (event.key.toUpperCase() !== 'E' || event.repeat) return;
        if (config.behavior === 'hold' && !holdStarted) {
            holdStarted = performance.now();
            worldItems = worldItems.map(item => ({ ...item, holdActive: true, holdRevision: ++holdRevision }));
            emit('interaction:world', { items: worldItems });
            holdTimer = later(() => cancelHold('completed'), 2000);
        }
        if (skill?.config?.type === 'mash') {
            mashProgress = Math.min(1, mashProgress + .16);
            emit('skill:progress', { session: skill.session, progress: mashProgress });
            if (mashProgress >= 1) finishSkill('success', true);
            else if (!mashTimer) mashTimer = setInterval(() => {
                if (document.hidden) return;
                mashProgress = Math.max(0, mashProgress - .012);
                if (skill) emit('skill:progress', { session: skill.session, progress: mashProgress });
            }, 100);
        }
    });
    window.addEventListener('keyup', event => { if (event.key.toUpperCase() === 'E') cancelHold('canceled on release'); });
    window.addEventListener('blur', () => cancelHold('canceled on focus loss'));
    window.addEventListener('resize', () => {
        if (presentation) {
            presentation = { ...presentation, revision: presentation.revision + 1,
                viewport: { ...presentation.viewport, width: innerWidth, height: innerHeight } };
            scheduleEmit('cortex:presentation', presentation);
        }
    });
    window.addEventListener('contextmenu', event => { if (debugSession) { event.preventDefault(); emit('debug:input', { session: debugSession, input: 'back' }); } });
    window.addEventListener('wheel', event => { if (debugSession) { event.preventDefault(); emit('debug:input', { session: debugSession, input: event.deltaY > 0 ? 'down' : 'up' }); } }, { passive: false });
    // Simulates the Lua renderer's list selection: the wheel moves the focused
    // list's selected row; the selected row owns its key (arbitration mock).
    window.addEventListener('wheel', event => {
        if (config.behavior !== 'list' || debugSession) return;
        const rows = worldItems.filter(item => item.focused && item.tier !== 'marker');
        const current = rows.findIndex(item => item.selected);
        if (rows.length < 2 || current < 0 || rows.some(item => item.holdActive)) return;
        const next = Math.max(0, Math.min(rows.length - 1, current + (event.deltaY > 0 ? 1 : -1)));
        if (next === current) return;
        const key = rows[next].key;
        worldItems = worldItems.map(item => !item.focused ? item : { ...item, selected: item === rows[next],
            active: item === rows[next] || item.key !== key });
        emit('interaction:world', { items: worldItems });
        report('result', `Simulated list selection: ${rows[next].label}.`);
    }, { passive: true });
    // Illustrative browser copy of the Lua virtual knob (imports/skillCheck/shared.lua): pointer
    // pixels stand in for native mouse normals (1 unit = 200 px). Lua remains authoritative.
    let lastTrace = 0, traceAngle = 0, tracePeak = 0;
    window.addEventListener('pointermove', event => {
        if (skill?.config?.type !== 'trace' || !skill.started) return;
        const sign = skill.config.direction === 'upper' ? -1 : 1, radius = .5 / (skill.config.sensitivity || 1);
        const dx = event.movementX / 200, dy = sign * event.movementY / 200, distance = Math.hypot(dx, dy);
        const chunks = Math.min(64, Math.max(1, Math.ceil(distance / (radius * .25))));
        for (let i = 0; i < chunks; i++) {
            const sx = dx / chunks, sy = dy / chunks, c = Math.cos(traceAngle), s = Math.sin(traceAngle);
            if (Math.abs(-s * sx + c * sy) < .25 * distance / chunks) continue;
            const px = radius * c + sx, py = radius * s + sy;
            if (Math.hypot(px, py) < radius * .5) continue;
            let delta = Math.atan2(py, px) - traceAngle;
            if (delta > Math.PI) delta -= 2 * Math.PI; else if (delta < -Math.PI) delta += 2 * Math.PI;
            traceAngle = Math.min(Math.PI, Math.max(Math.max(0, tracePeak - (skill.config.tolerance ?? .15) * Math.PI), traceAngle + delta));
            tracePeak = Math.max(tracePeak, traceAngle);
        }
        traceProgress = traceAngle / Math.PI;
        if (traceProgress < .96 && performance.now() - lastTrace < 33) return;
        lastTrace = performance.now();
        emit('skill:trace', { session: skill.session, progress: traceProgress >= .96 ? 1 : traceProgress, invalid: false });
        if (traceProgress >= .96) finishSkill('success', true);
    });
    window.addEventListener('error', event => report('error', event.message || `Asset failed: ${event.target?.src || event.target?.href || 'unknown'}`), true);
    window.addEventListener('unhandledrejection', event => report('error', String(event.reason)));
    window.addEventListener('load', () => { loaded = true; later(announce, 0); });
})();
