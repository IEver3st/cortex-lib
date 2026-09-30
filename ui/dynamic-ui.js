/* Shared presentation adapter; no framework, focus ownership, or gameplay actions. */
(function () {
    'use strict';
    if (typeof GetParentResourceName !== 'function' || !window.CortexLayout) return;
    const resource = GetParentResourceName();
    const rules = {
        'cortex-lib': [
            ['notifications', '#notify-container', false, 50],
            ['prompts', '.cortex-interactions', false, 75],
            ['text', '#textui', false, 65],
            ['progress', '.progress-container', true, 70],
        ],
        // Typing must never trigger a delayed relocation. Other overlays yield.
        'cortex-chat': [['chat', '.es-chat', true, 85]],
        'cortex-hud': [
            ['status', '.status-cluster, .gta6-vitals', true, 100], ['speed', '.speedo-container', true, 100],
            ['ammo', '.gta6-weapon, .ammo-display', true, 100],
            ['location', '.gta6-location-plaque', true, 100], ['waypoint', '.waypoint-distance', true, 100],
        ],
        'cortex-polcam': [['camera', '.panel', true, 100], ['compass', '.compass-container', true, 100]],
        'cortex-rewind': [['rewind', '.rewind-instrument', false, 90]],
        'cortex-death': [['death', '.incapacitated-overlay .content', true, 100]],
        'cortex-emotemenu': [['menu', '.menu-shell', true, 100]],
        'cortex_mdtsv': [['mdt', '.mdt-shell', true, 100]],
        'cortex_soundtool': [['sound', '.sound-tester-panel', true, 100]],
        'cortex-admin': [['admin', '.admin-shell', true, 100]],
        'gsd-arges': [['controller', '.console-shell', true, 100]],
        'opticom': [['receiver', '.receiver', false, 80], ['debug', '.debug-panel', true, 100]],
    };
    const definitions = [...(rules[resource] || [])];
    const tracked = new Map();
    let state = null;
    let minimap = null;
    let timer = null;
    let inFlight = false;
    let lastSignature = '';
    let destroyed = false;
    const root = document.documentElement;
    root.dataset.cortexResource = resource;

    async function post(route, data) {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 2000);
        try {
            const response = await fetch(`https://${resource}/${route}`, {
                method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data || {}), signal: controller.signal,
            });
            return await response.json();
        } catch { return { ok: false }; }
        finally { clearTimeout(timeout); }
    }
    function setStyle(element, name, value) {
        if (element.style.getPropertyValue(name) !== value) element.style.setProperty(name, value);
    }
    // The accent's hue at the lightness mint-deep (#2f6e62) has against mint,
    // for accent marks that sit on paper.
    function deepen([r, g, b]) {
        const max = Math.max(r, g, b) / 255, min = Math.min(r, g, b) / 255, d = max - min;
        const l = (max + min) / 2;
        const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
        let h = 0;
        if (d) {
            const [rn, gn, bn] = [r / 255, g / 255, b / 255];
            h = max === rn ? ((gn - bn) / d) % 6 : max === gn ? (bn - rn) / d + 2 : (rn - gn) / d + 4;
            h = Math.round(h * 60 + 360) % 360;
        }
        return `hsl(${h}, ${Math.round(Math.min(1, s * 1.1) * 100)}%, 31%)`;
    }
    function theme(profile) {
        // Every participating resource follows the shared profile. A legacy
        // `independent` map from an older cortex-lib is ignored on purpose.
        root.classList.toggle('cortex-shared-style', true);
        const accent = /^#[0-9a-f]{6}$/i.test(profile.accent) ? profile.accent : '#8fcbbf';
        setStyle(root, '--cx-accent', accent);
        const rgb = [1, 3, 5].map(start => parseInt(accent.slice(start, start + 2), 16));
        setStyle(root, '--cx-accent-rgb', rgb.join(', '));
        setStyle(root, '--cx-accent-deep', deepen(rgb));
        const opacity = Math.max(65, Math.min(100, Number(profile.opacity) || 92)) / 100;
        setStyle(root, '--cx-surface-alpha', String(opacity));
        setStyle(root, '--cx-panel', `rgba(17, 23, 21, ${opacity})`);
        const reduce = profile.motion === 'reduced'
            || (profile.motion !== 'full' && matchMedia('(prefers-reduced-motion: reduce)').matches);
        root.classList.toggle('cortex-reduced-motion', reduce);
        root.dataset.cxMotion = reduce ? 'reduced' : 'full';
    }
    function visible(element) {
        for (let node = element; node && node.nodeType === 1; node = node.parentElement) {
            const style = getComputedStyle(node);
            if (node.hidden || style.display === 'none' || style.visibility === 'hidden'
                || Number(style.opacity) === 0 || node.getAttribute('aria-hidden') === 'true') return false;
        }
        return true;
    }
    function resetPlacement(entry) {
        if (entry.applied) entry.element.style.removeProperty('translate');
        entry.applied = false;
        entry.dx = entry.dy = 0;
        entry.element.removeAttribute('data-cortex-crowded');
    }
    function measure() {
        const found = new Set();
        const surfaces = [];
        for (const [base, selector, fixed, priority] of definitions) {
            document.querySelectorAll(selector).forEach((element, index) => {
                if (surfaces.length >= 15) return;
                const id = `${base}-${index}`;
                found.add(id);
                let entry = tracked.get(id);
                if (!entry || entry.element !== element) {
                    if (entry) { resetPlacement(entry); resize.unobserve(entry.element); }
                    entry = { element, dx: 0, dy: 0, fixed }; tracked.set(id, entry);
                    resize.observe(element);
                }
                if (!visible(element)) { resetPlacement(entry); return; }
                // An empty chat and empty notification stack reserve nothing.
                if (base === 'chat' && !element.classList.contains('chat-open')
                    && ![...element.querySelectorAll('.es-chat-message')].some(visible)) return;
                const rect = element.getBoundingClientRect();
                const x = Math.round(rect.x - entry.dx), y = Math.round(rect.y - entry.dy);
                const width = Math.ceil(rect.width), height = Math.ceil(rect.height);
                if (width < 1 || height < 1 || x + width < 0 || y + height < 0
                    || x > innerWidth || y > innerHeight) return;
                surfaces.push({ id, x, y, width, height, fixed, priority });
            });
        }
        for (const [id, entry] of tracked) if (!found.has(id)) {
            resetPlacement(entry); resize.unobserve(entry.element); tracked.delete(id);
        }
        if (minimap) surfaces.push({ id: 'minimap', ...minimap, fixed: true, priority: 100 });
        return surfaces;
    }
    function place() {
        if (!state) return;
        const enabled = state.profile.layout !== false;
        const placements = enabled ? CortexLayout.solve(state.surfaces, state.viewport) : {};
        for (const [id, entry] of tracked) {
            const key = `${resource}:${id}`;
            const source = state.surfaces.find(item => item.key === key);
            const placement = placements[key];
            if (!enabled || entry.fixed || !source || source.fixed || !placement) { resetPlacement(entry); continue; }
            entry.dx = Math.round(placement.x - source.x);
            entry.dy = Math.round(placement.y - source.y);
            entry.applied = true;
            setStyle(entry.element, 'translate', `${entry.dx}px ${entry.dy}px`);
            const crowded = placement.crowded ? 'true' : 'false';
            if (entry.element.dataset.cortexCrowded !== crowded) entry.element.dataset.cortexCrowded = crowded;
        }
    }
    async function update() {
        timer = null;
        if (destroyed || inFlight) return;
        const surfaces = measure();
        const signature = JSON.stringify(surfaces);
        if (signature === lastSignature) return;
        inFlight = true;
        const result = await post('cortexPresentationSurfaces', { surfaces });
        if (result.ok) lastSignature = signature;
        inFlight = false;
        if (!destroyed) schedule();
    }
    function schedule() {
        if (!timer && !destroyed) timer = setTimeout(update, 200);
    }
    function onMessage(event) {
        const message = event.data;
        if (!message || typeof message !== 'object') return;
        if (message.action === 'cortex:presentation' && validSnapshot(message.data)) {
            if (state && message.data.revision < state.revision) return;
            state = message.data;
            setStyle(root, '--cx-safe', `${Math.max(12, state.viewport.inset || 0)}px`);
            const menuOwners = ['cortex-admin', 'cortex-emotemenu', 'cortex_mdtsv', 'cortex_soundtool'];
            root.classList.toggle('cortex-modal-active', state.modal === true
                || state.surfaces.some(surface => menuOwners.includes(surface.owner)));
            root.classList.toggle('cortex-settings-active', state.settings === true);
            theme(state.profile); place(); schedule();
        } else if (message.action === 'cortex:presentationReset') {
            state = null; lastSignature = '';
            root.classList.remove('cortex-modal-active', 'cortex-settings-active');
            for (const entry of tracked.values()) resetPlacement(entry);
            schedule();
        } else if (resource === 'cortex-hud' && message.action === 'interaction:layout') {
            const bounds = message.minimapBounds;
            if (bounds && ['left', 'top', 'width', 'height'].every(key => Number.isFinite(bounds[key]))) {
                minimap = { x: bounds.left, y: bounds.top, width: bounds.width, height: bounds.height };
            }
            schedule();
        } else { schedule(); }
    }
    function validSnapshot(data) {
        const finite = value => Number.isFinite(value) && Math.abs(value) < 100000;
        return data?.v === 1 && Number.isSafeInteger(data.revision) && data.revision >= 0
            && data.profile && typeof data.profile === 'object' && data.viewport
            && ['width', 'height', 'inset'].every(key => finite(data.viewport[key]))
            && data.viewport.width > 0 && data.viewport.height > 0
            && Array.isArray(data.surfaces) && data.surfaces.length <= 512
            && data.surfaces.every(item => item && typeof item.key === 'string' && item.key.length <= 256
                && typeof item.owner === 'string' && typeof item.fixed === 'boolean'
                && ['x', 'y', 'width', 'height', 'priority'].every(key => finite(item[key]))
                && item.width > 0 && item.height > 0);
    }
    window.CortexUI = Object.freeze({
        // Consumer code registers actual bounded surfaces; gameplay stays in Lua.
        registerSurface({ id, selector, fixed = false, priority = 50 }) {
            if (typeof id !== 'string' || !/^[a-zA-Z0-9_-]{1,48}$/.test(id)
                || typeof selector !== 'string' || selector.length > 256
                || typeof fixed !== 'boolean' || !Number.isFinite(priority) || priority < 0 || priority > 100
                || definitions.length >= 16 || definitions.some(rule => rule[0] === id)) {
                throw new TypeError('Invalid or duplicate Cortex UI surface');
            }
            document.querySelectorAll(selector); // Validate selector before registration.
            const rule = [id, selector, fixed, priority];
            definitions.push(rule); schedule();
            return () => {
                const index = definitions.indexOf(rule);
                if (index >= 0) { definitions.splice(index, 1); schedule(); }
            };
        },
    });
    window.addEventListener('message', onMessage);
    window.addEventListener('resize', schedule);
    document.addEventListener('transitionend', schedule);
    document.addEventListener('animationend', schedule);
    const observer = new MutationObserver(schedule);
    observer.observe(document.body, { subtree: true, childList: true, attributes: true,
        attributeFilter: ['style', 'class', 'hidden', 'aria-hidden'] });
    const resize = new ResizeObserver(schedule);
    resize.observe(document.body);
    const motion = matchMedia('(prefers-reduced-motion: reduce)');
    const motionChange = () => { if (state) theme(state.profile); };
    motion.addEventListener('change', motionChange);
    // Low-frequency recovery covers late readiness/restart and CSS-only changes.
    // Once a snapshot arrives, Lua pushes every change, so only an unsynced
    // (or reset) frame asks for a full snapshot.
    const recovery = setInterval(() => { if (!state) post('cortexPresentationReady'); schedule(); }, 5000);
    post('cortexPresentationReady'); schedule();
    window.addEventListener('pagehide', () => {
        destroyed = true; clearTimeout(timer); clearInterval(recovery);
        observer.disconnect(); resize.disconnect(); motion.removeEventListener('change', motionChange);
        window.removeEventListener('message', onMessage); window.removeEventListener('resize', schedule);
        document.removeEventListener('transitionend', schedule); document.removeEventListener('animationend', schedule);
        post('cortexPresentationSurfaces', { surfaces: [] });
    }, { once: true });
})();
