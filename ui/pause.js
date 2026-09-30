/* The pause shell uses the existing React root and settings session. No second
 * bridge, runtime, focus owner, or independent persistence store lives here. */
(() => {
    'use strict';
    const h = React.createElement;
    const { useState, useEffect, useRef } = React;
    const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
    const text = (value, max = 96) => typeof value === 'string' ? value.slice(0, max) : '';
    const list = (value, max) => Array.isArray(value) ? value.slice(0, max).filter(record) : [];

    /** @typedef {{version: 1, title: string, player: string, zone: string,
     * serverId: number|null, safezone: number, notice: string, pages: Array, locations: Array}} PauseSnapshot */
    /** @returns {PauseSnapshot} */
    function normalize(value) {
        const data = record(value) ? value : {};
        return {
            version: 1,
            title: text(data.title, 48) || 'CORTEX',
            player: text(data.player, 96),
            zone: text(data.zone, 96),
            notice: text(data.notice, 256),
            serverId: Number.isInteger(data.serverId) ? data.serverId : null,
            safezone: Number.isFinite(data.safezone) ? Math.max(0.8, Math.min(1, data.safezone)) : 1,
            // Only an explicit server opt-in enables the quick menu.
            quickMenu: data.quickMenu === true,
            pages: list(data.pages, 24).map(page => ({
                id: text(page.id, 160), label: text(page.label, 48), description: text(page.description, 256),
                sections: list(page.sections, 16).map(section => ({
                    title: text(section.title, 96), body: text(section.body, 2048),
                    actions: list(section.actions, 8).map(action => ({ id: text(action.id, 64), label: text(action.label, 64) }))
                }))
            })).filter(page => page.id && page.label),
            locations: list(data.locations, 256).map(location => ({
                id: text(location.id, 160), label: text(location.label, 96), category: text(location.category, 64)
            })).filter(location => location.id && location.label)
        };
    }

    // Hex terrain for the quick-menu paper column. Built once at load: a
    // deterministic height field extrudes pointy-top hexes that rise toward the
    // bottom edge. The terrain is static geometry; only its layer floats, and
    // the few mint beacons live in a separate small SVG so the large drawing
    // never repaints per frame.
    const TERRAIN = (() => {
        const r = 21, w = Math.sqrt(3) * r, rowStep = 1.5 * r, top = 440, bottom = 1060;
        const noise = (x, y) => (Math.sin(x * 0.011 + y * 0.004) + Math.sin(y * 0.017 - x * 0.006 + 1.7)
            + Math.sin((x + y) * 0.023 + 0.4) * 0.6) / 2.6;
        const point = (x, y) => `${x.toFixed(1)},${y.toFixed(1)}`;
        const hexes = [];
        for (let row = 0; top + row * rowStep <= bottom; row++) {
            const cy = top + row * rowStep;
            for (let col = -1; col * w <= 640; col++) {
                const cx = col * w + (row % 2 ? w / 2 : 0);
                const rise = Math.min(1, (cy - top) / (bottom - top - 120));
                const lift = Math.max(0, (0.55 + 0.45 * noise(cx, cy)) * rise * rise * 34);
                hexes.push({ cx, cy, lift, rise });
            }
        }
        const faces = hexes.map(({ cx, cy, lift, rise }) => {
            const y = cy - lift;
            const v = [0, 1, 2, 3, 4, 5].map(i => {
                const a = Math.PI / 180 * (60 * i - 90);
                return [cx + r * Math.cos(a), y + r * Math.sin(a)];
            });
            // v[2] lower-right, v[3] bottom, v[4] lower-left in screen space.
            const down = ([x, yy]) => [x, yy + lift];
            return {
                top: v.map(([x, yy]) => point(x, yy)).join(' '),
                right: lift > 0.8 ? [v[1], v[2], down(v[2]), down(v[1])].map(q => point(...q)).join(' ') : null,
                left: lift > 0.8 ? [v[2], v[3], down(v[3]), down(v[2])].map(q => point(...q)).join(' ') : null,
                front: lift > 0.8 ? [v[3], v[4], down(v[4]), down(v[3])].map(q => point(...q)).join(' ') : null,
                west: lift > 0.8 ? [v[4], v[5], down(v[5]), down(v[4])].map(q => point(...q)).join(' ') : null,
                tone: rise * (0.02 + 0.06 * (0.5 + 0.5 * Math.sin(cx * 0.05 + cy * 0.03))), rise, lift
            };
        });
        const beacons = faces.map((face, i) => ({ face, i })).filter(({ face }) => face.lift > 20)
            .filter((_, i) => i % 7 === 3).slice(0, 9).map(({ face, i }) => ({ points: face.top, delay: (i * 0.61) % 7 }));
        return { faces, beacons };
    })();
    function HexTerrain() {
        return h(React.Fragment, null,
            h('svg', { className: 'pause-terrain', viewBox: '0 0 620 1000', preserveAspectRatio: 'xMidYMax slice' },
                TERRAIN.faces.map((face, i) => h('g', { key: i },
                    face.west && h('polygon', { points: face.west, className: 'hex-side-a', style: { opacity: face.rise } }),
                    face.front && h('polygon', { points: face.front, className: 'hex-side-a', style: { opacity: face.rise } }),
                    face.left && h('polygon', { points: face.left, className: 'hex-side-b', style: { opacity: face.rise } }),
                    face.right && h('polygon', { points: face.right, className: 'hex-side-b', style: { opacity: face.rise } }),
                    h('polygon', { points: face.top, className: 'hex-top', style: { fillOpacity: face.tone, strokeOpacity: face.rise * 0.16 } })))),
            h('svg', { className: 'pause-terrain pause-beacons', viewBox: '0 0 620 1000', preserveAspectRatio: 'xMidYMax slice' },
                TERRAIN.beacons.map((beacon, i) => h('polygon', { key: i, points: beacon.points, style: { '--d': `${beacon.delay.toFixed(2)}s` } }))));
    }

    // Local wall clock for the playfield corner; one timer, aligned to the minute.
    function Clock() {
        const [now, setNow] = useState(() => new Date());
        useEffect(() => {
            let timer;
            const tick = () => { const next = new Date(); setNow(next); timer = setTimeout(tick, 60000 - next.getSeconds() * 1000 - next.getMilliseconds() + 50); };
            timer = setTimeout(tick, 60000 - now.getSeconds() * 1000 - now.getMilliseconds() + 50);
            return () => clearTimeout(timer);
        }, []);
        const pad = value => String(value).padStart(2, '0');
        const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return h('div', { className: 'pause-clock', 'aria-hidden': true },
            h('span', { className: 'pause-clock-time' }, pad(now.getHours()), h('span', { className: 'pause-clock-colon' }, ':'), pad(now.getMinutes())),
            h('span', { className: 'pause-clock-date' }, `${days[now.getDay()]} ${now.getDate()} ${months[now.getMonth()]}`));
    }

    const focusable = root => Array.from(root?.querySelectorAll(
        // Roving-tabindex children (segmented, swatches) are one stop per row.
        'button:not([disabled]):not([tabindex="-1"]), input:not([disabled]):not([tabindex="-1"]), [tabindex="0"]'
    ) || []).filter(node => node.getClientRects().length && !node.closest('[hidden], [inert]'));

    function moveFocus(root, direction) {
        if (!root) return;
        const current = document.activeElement;
        // Portaled select menus own navigation until dismissed.
        const scope = current?.closest('[role="listbox"], [role="alertdialog"]') || root;
        const nodes = focusable(scope);
        if (!nodes.length) return;
        const index = nodes.indexOf(current);
        const next = nodes[(index + direction + nodes.length) % nodes.length];
        next.focus();
        next.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    }

    function Frame({ open, page, setPage, pause, dialogRef, session, post, onResume,
        onSave, onApply, onBack, submitting, dirtyCount, error, children }) {
        const data = pause || normalize(null);
        const [query, setQuery] = useState('');
        const [notice, setNotice] = useState('');
        const [pending, setPending] = useState(false);
        const activeSession = useRef(session);
        const busy = useRef(false);
        activeSession.current = session;
        const extension = data.pages.find(item => item.id === page);
        const isHome = page === 'home';

        useEffect(() => {
            setQuery(''); setNotice(''); setPending(false); busy.current = false;
        }, [page, session]);

        useEffect(() => () => { activeSession.current = null; }, []);

        useEffect(() => {
            if (!open) return;
            if (!data.quickMenu && page !== 'settings') setPage('settings');
            else if (!['home', 'settings', 'locations', 'leave', 'map'].includes(page) && !extension) setPage('home');
        }, [open, page, extension, data.quickMenu, setPage]);

        useEffect(() => {
            if (!open) return;
            const frame = requestAnimationFrame(() => {
                const root = dialogRef.current;
                const first = root?.querySelector('[data-pause-autofocus]') || focusable(root)[0];
                first?.focus();
            });
            return () => cancelAnimationFrame(frame);
        }, [open, page, session, dialogRef]);

        useEffect(() => {
            if (!open) return;
            const handleInput = event => {
                if (event.detail?.session !== session || submitting || busy.current) return;
                const input = event.detail.input;
                const current = document.activeElement;
                const dropdown = current?.closest('[role="listbox"]');
                if (input === 'back') {
                    if (dropdown) current.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
                    else onBack();
                } else if (input === 'up' || input === 'down') {
                    if (dropdown) current.dispatchEvent(new KeyboardEvent('keydown', { key: input === 'up' ? 'ArrowUp' : 'ArrowDown', bubbles: true }));
                    else moveFocus(dialogRef.current, input === 'up' ? -1 : 1);
                } else if (input === 'accept') current?.click();
                else if (input === 'left' || input === 'right') {
                    if (current?.getAttribute?.('role') === 'radio') {
                        // Segmented and swatch choices step their own value.
                        current.dispatchEvent(new KeyboardEvent('keydown', { key: input === 'left' ? 'ArrowLeft' : 'ArrowRight', bubbles: true }));
                    } else if (current?.type === 'range') {
                        const next = Math.max(Number(current.min), Math.min(Number(current.max),
                            Number(current.value) + Number(current.step || 1) * (input === 'left' ? -1 : 1)));
                        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(current, String(next));
                        current.dispatchEvent(new Event('input', { bubbles: true }));
                        current.dispatchEvent(new Event('change', { bubbles: true }));
                        current.dispatchEvent(new KeyboardEvent('keyup', { key: input === 'left' ? 'ArrowLeft' : 'ArrowRight', bubbles: true }));
                    } else moveFocus(dialogRef.current, input === 'left' ? -1 : 1);
                }
            };
            window.addEventListener('cortex-pause-input', handleInput);
            return () => window.removeEventListener('cortex-pause-input', handleInput);
        }, [open, page, session, submitting, dialogRef, onBack]);

        const request = async (callback, payload, success) => {
            if (busy.current || submitting) return;
            const captured = session;
            busy.current = true; setPending(true); setNotice('');
            try {
                const response = await post(callback, { ...payload, session });
                if (activeSession.current !== captured) return;
                setNotice(response?.ok === true ? (success || '') : 'Unable to complete that action. Try again.');
            } catch (_) {
                if (activeSession.current === captured) setNotice('Connection interrupted. Try again.');
            } finally {
                if (activeSession.current === captured) { busy.current = false; setPending(false); }
            }
        };

        const nav = [
            { id: 'resume', label: dirtyCount ? 'Resume / discard changes' : 'Resume', caption: 'Back to the city', action: onResume },
            { id: 'map', label: 'Map', caption: 'Fullscreen GTA map', action: () => request('pauseNative', { target: 'map' }) },
            { id: 'settings', label: 'Settings', caption: 'Game and Cortex preferences', action: () => setPage('settings') },
            { id: 'keys', label: 'Key bindings', caption: 'GTA and FiveM key bindings',
                action: () => request('pauseNative', { target: 'keybindings', returnTo: 'home' }) },
            ...(data.locations.length ? [{ id: 'locations', label: 'Locations', caption: 'Set a waypoint', action: () => setPage('locations') }] : []),
            ...data.pages.map(item => ({ ...item, caption: item.description, action: () => setPage(item.id) })),
            { id: 'leave', label: 'Leave server', caption: 'Disconnect from this session', danger: true, action: () => setPage('leave') }
        ];
        const disabled = submitting || pending;
        const isSettings = page === 'settings';
        const heading = isHome ? 'QUICK MENU' : page === 'map' ? 'MAP' : isSettings ? 'SETTINGS' : page === 'locations' ? 'LOCATIONS' : page === 'leave' ? 'LEAVE SERVER' : extension?.label;
        const status = notice || error || data.notice || (pending ? 'Opening…' : '');
        const Kit = window.CortexKit;
        const locationQuery = page === 'locations' ? query.toLowerCase() : '';
        const matchingLocations = page === 'locations'
            ? data.locations.filter(item => `${item.label} ${item.category}`.toLowerCase().includes(locationQuery)) : [];

        if (!open) return null;
        return h('div', { className: `cortex-pause-overlay${isHome ? ' is-home' : ''}${page === 'settings' ? ' is-settings-page' : ''}`,
            style: { '--pause-safe': `${Math.max(3, (1 - data.safezone) * 50)}vmin` } },
            isHome && h(Clock),
            isHome && h('div', { className: 'pause-rail', 'aria-hidden': true }, h(HexTerrain)),
            h('div', { ref: dialogRef, className: 'cortex-pause cortex-settings-panel', role: 'dialog',
                'aria-modal': true, 'aria-labelledby': 'cortex-settings-title', tabIndex: -1,
                onKeyDown: event => {
                    if (event.defaultPrevented || event.target.closest('[role="tablist"], [role="listbox"]') || ['INPUT', 'SELECT'].includes(event.target.tagName)) return;
                    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
                        event.preventDefault(); moveFocus(dialogRef.current, event.key === 'ArrowUp' ? -1 : 1);
                    }
                } },
                isSettings ? h('header', { className: 'pause-heading cortex-settings-heading' },
                    // Settings speaks the kit: eyebrow + display title with the
                    // accent bar, and the controls legend where the eye starts.
                    h('div', { className: 'cortex-settings-title-block' },
                        h('span', { className: 'cx-eyebrow' }, data.title),
                        h('h1', { id: 'cortex-settings-title' }, heading)),
                    Kit ? h(Kit.ControlsLegend, { className: 'cortex-settings-legend', align: 'end', label: 'Settings controls', items: [
                        { keys: ['UP', 'DOWN'], label: 'Move' }, { keys: ['LEFT', 'RIGHT'], label: 'Adjust' },
                        { keys: 'ENTER', label: 'Select' }, { keys: 'ESC', label: 'Discard & close' }] }) : null
                ) : h('header', { className: 'pause-heading' },
                    h('div', { className: 'pause-brand' }, h('span', { className: 'pause-mark', 'aria-hidden': true }, '//'), data.title),
                    h('h1', { id: 'cortex-settings-title' }, heading),
                    !isHome && h('button', { type: 'button', className: 'pause-back', onClick: onBack, disabled }, '← Quick menu')
                ),
                isHome ? h(React.Fragment, null,
                    // Identity: server ID in a hex badge (the menu's glyph), then the
                    // player's name as typed and the live zone beneath it.
                    (data.zone || data.player || data.serverId !== null) && h('section', { className: 'pause-identity', 'aria-label': 'Session' },
                        data.serverId !== null && h('div', { className: `pause-id-badge${String(data.serverId).length > 3 ? ' is-long' : ''}` },
                            h('svg', { viewBox: '0 0 56 64', 'aria-hidden': true },
                                h('polygon', { className: 'pause-id-hex', points: '28,1.5 54.5,16.75 54.5,47.25 28,62.5 1.5,47.25 1.5,16.75' }),
                                h('polygon', { className: 'pause-id-ring', points: '28,7 49.5,19.4 49.5,44.6 28,57 6.5,44.6 6.5,19.4' })),
                            h('span', { className: 'pause-id-label' }, 'ID'),
                            h('strong', { className: 'pause-id-value' }, data.serverId)),
                        h('div', { className: 'pause-identity-text' },
                            data.player && h('strong', { className: 'pause-player', title: data.player }, data.player),
                            data.zone && h('span', { className: 'pause-location' },
                                h('span', { className: 'pause-session-dot', 'aria-hidden': true }), data.zone))),
                    // Hex glyph options; the selected one becomes an ink tag.
                    h('nav', { className: 'pause-main-nav', 'aria-label': 'Pause menu' }, nav.map((item, index) =>
                        h('button', { key: item.id, type: 'button', className: `pause-nav-item${item.danger ? ' is-danger' : ''}`, disabled,
                            style: { '--i': index }, 'data-pause-autofocus': index === 0 ? true : undefined, onClick: item.action,
                            // Pointer and controller share one selection: hovering moves focus.
                            onMouseEnter: event => event.currentTarget.focus({ preventScroll: true }) },
                            h('svg', { className: 'pause-nav-hex', viewBox: '0 0 24 24', 'aria-hidden': true },
                                h('polygon', { points: '12,2.5 20.5,7.25 20.5,16.75 12,21.5 3.5,16.75 3.5,7.25' })),
                            h('span', { className: 'pause-nav-text' },
                                h('span', { className: 'pause-nav-label' }, item.label),
                                item.caption && h('span', { className: 'pause-nav-caption' }, item.caption)),
                            h('span', { className: 'pause-nav-arrow', 'aria-hidden': true }, '→')))),
                    dirtyCount > 0 && h('div', { className: 'pause-changes' },
                        h('span', null, `${dirtyCount} unsaved ${dirtyCount === 1 ? 'change' : 'changes'}`),
                        h('button', { type: 'button', onClick: onApply, disabled }, 'Apply'),
                        h('button', { type: 'button', onClick: onSave, disabled }, 'Save & resume'))
                ) : page === 'settings' ? children
                    : page === 'map' ? h('main', { className: 'pause-page-content' },
                        h('button', { type: 'button', className: 'pause-action', disabled,
                            onClick: () => request('pauseNative', { target: 'map' }) }, 'Open fullscreen map'))
                    : h('main', { className: 'pause-page-content' },
                    page === 'leave' ? h('section', { className: 'pause-extension-section pause-leave' },
                        h('h2', null, 'Leave this session?'),
                        h('p', null, 'You’ll return to the FiveM home screen. Unsaved script settings will be discarded.'),
                        h('button', { type: 'button', className: 'pause-action', disabled, onClick: () => setPage('home'), 'data-pause-autofocus': true }, 'Stay here'),
                        h('button', { type: 'button', className: 'pause-action pause-danger', disabled,
                            onClick: () => request('pauseDisconnect', { confirmed: true }) }, 'Leave server')
                    ) : page === 'locations' ? h(React.Fragment, null,
                        h('div', { className: 'pause-location-toolbar' },
                            h('input', { type: 'search', value: query, maxLength: 128, placeholder: 'Search locations…', 'aria-label': 'Search locations', onChange: event => setQuery(event.target.value) }),
                            h('button', { type: 'button', className: 'pause-action', disabled, onClick: () => request('pauseNative', { target: 'map' }) }, 'Open map ↗')),
                        matchingLocations.length ? matchingLocations.map(item => h('button', {
                            key: item.id, type: 'button', className: 'pause-location-row', disabled,
                            onClick: () => request('pauseWaypoint', { id: item.id }, `Waypoint set: ${item.label}`)
                        }, h('span', null, h('small', null, item.category), h('strong', null, item.label)), h('span', null, 'Set waypoint ↗')))
                            : h('p', { className: 'pause-empty' }, 'No matching locations.')
                    ) : extension && h(React.Fragment, null,
                        extension.description && h('p', { className: 'pause-page-intro' }, extension.description),
                        extension.sections.map((section, index) => h('section', { key: index, className: 'pause-extension-section' },
                            section.title && h('h2', null, section.title), section.body && h('p', null, section.body),
                            section.actions.map(action => h('button', { key: action.id, type: 'button', className: 'pause-action', disabled,
                                onClick: () => request('pauseAction', { page: extension.id, id: action.id }) }, action.label)))))
                ),
                isSettings ? (status && h('footer', { className: 'pause-footer cortex-settings-status' },
                    h('span', { className: 'pause-status', role: 'status', 'aria-live': 'polite' }, status)))
                : h('footer', { className: 'pause-footer' },
                    h('span', { className: 'pause-status', role: 'status', 'aria-live': 'polite' }, status),
                    h('div', { className: 'pause-hints', 'aria-label': 'Menu controls' },
                        // Kit keycaps: ink on the paper home column, paper on ink pages.
                        [['UP DOWN', 'Move'], ['ENTER', 'Select'], ['ESC', isHome ? 'Close' : 'Back']].map(([keys, label]) =>
                            h(window.CortexKit.KeyHint, { key: label, keys, label, size: 'sm', tone: isHome ? 'ink' : 'paper' }))))
            )
        );
    }

    window.CortexPause = Object.freeze({ Frame, normalize, moveFocus });
})();
