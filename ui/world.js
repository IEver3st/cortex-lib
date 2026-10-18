/* World prompts as a texture the game draws (client/interaction_dui.lua).
 *
 * The game renders this page into a DUI texture and draws one cell of it at
 * each prompt's anchor with SetDrawOrigin, which the game resolves at render
 * time with the current camera. A NUI element is positioned from the previous
 * frame's projection and reaches the screen a frame or two later through CEF,
 * so it trails its anchor whenever the camera turns. Positions never come
 * here: Lua sends the atlas layout and each cell's rows only when they change,
 * numbered by revision. The page reports each revision once it is painted, so
 * Lua draws a cell's new content only when it is on the texture (and stops
 * resending: messages sent before this page listens are lost).
 * Cells reuse the main NUI's world prompt components (surfaces/interactions.js). */
(function () {
    'use strict';
    const h = React.createElement;
    const { useState, useEffect, useRef } = React;
    const MAX_CELLS = 8;
    const root = document.documentElement;
    const resource = window.CORTEX_WORLD_RESOURCE || 'cortex-lib';
    // Which DUI this is: Lua may run two while it swaps sizes.
    const dui = Number(new URLSearchParams(window.location.search).get('dui')) || 0;

    function report(revision) {
        fetch(`https://${resource}/interactionWorldReady`, {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ dui, revision })
        }).catch(() => undefined);
    }

    const finite = (value, minimum, maximum) => Number.isFinite(value) && value >= minimum && value <= maximum;

    // The accent's hue at the lightness mint-deep (#2f6e62) has against mint
    // (same rule as dynamic-ui.js, which this page does not load: it reports
    // layout for the main NUI).
    function deepen([r, g, b]) {
        const max = Math.max(r, g, b) / 255, min = Math.min(r, g, b) / 255, d = max - min;
        const l = (max + min) / 2;
        const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
        let hue = 0;
        if (d) {
            const [rn, gn, bn] = [r / 255, g / 255, b / 255];
            hue = max === rn ? ((gn - bn) / d) % 6 : max === gn ? (bn - rn) / d + 2 : (rn - gn) / d + 4;
            hue = Math.round(hue * 60 + 360) % 360;
        }
        return `hsl(${hue}, ${Math.round(Math.min(1, s * 1.1) * 100)}%, 31%)`;
    }

    function applyTheme(profile) {
        if (!profile || typeof profile !== 'object') return;
        const accent = /^#[0-9a-f]{6}$/i.test(profile.accent) ? profile.accent : '#8fcbbf';
        const rgb = [1, 3, 5].map(start => parseInt(accent.slice(start, start + 2), 16));
        root.style.setProperty('--cx-accent', accent);
        root.style.setProperty('--cx-accent-rgb', rgb.join(', '));
        root.style.setProperty('--cx-accent-deep', deepen(rgb));
        const opacity = Math.max(65, Math.min(100, Number(profile.opacity) || 92)) / 100;
        root.style.setProperty('--cx-surface-alpha', String(opacity));
        const reduce = profile.motion === 'reduced'
            || (profile.motion !== 'full' && matchMedia('(prefers-reduced-motion: reduce)').matches);
        root.classList.toggle('cortex-reduced-motion', reduce);
        root.dataset.cxMotion = reduce ? 'reduced' : 'full';
    }

    function readCell(cell) {
        if (!cell || typeof cell !== 'object' || typeof cell.group !== 'string' || !cell.group
            || cell.group.length > 160) return null;
        const items = normalizeInteractionItems(cell.items, true).filter(item => item.tier === 'prompt');
        return items.length ? { group: cell.group, flipped: cell.flipped === true, items } : null;
    }

    function readState(data) {
        if (!Number.isInteger(data.revision) || data.revision < 0 || !finite(data.u, 0.3, 8) || !finite(data.scale, 0.5, 2)
            || !finite(data.cellWidth, 16, 4096) || !finite(data.cellHeight, 16, 4096)
            || !Number.isInteger(data.columns) || !finite(data.columns, 1, MAX_CELLS)
            || !finite(data.anchorX, 0, 4096) || !finite(data.anchorRight, 0, 4096) || !finite(data.anchorY, 0, 4096)
            || !Array.isArray(data.cells) || data.cells.length > MAX_CELLS) return null;
        return {
            revision: data.revision, u: data.u, scale: data.scale, cellWidth: data.cellWidth, cellHeight: data.cellHeight,
            columns: data.columns, anchorX: data.anchorX, anchorRight: data.anchorRight, anchorY: data.anchorY,
            theme: data.theme, cells: data.cells.map(readCell)
        };
    }

    function WorldAtlas() {
        const [state, setState] = useState(null);
        const painted = useRef(0);

        useEffect(() => {
            let last = '';
            const onMessage = (event) => {
                const message = normalizeNuiMessage(event);
                if (!message || message.action !== 'world:state') return;
                // A resend of the last state means Lua missed the report.
                const text = JSON.stringify(message.data);
                if (text === last) {
                    if (painted.current === message.data.revision) report(painted.current);
                    return;
                }
                const next = readState(message.data);
                if (!next) return;
                last = text;
                applyTheme(next.theme);
                setState(next);
            };
            window.addEventListener('message', onMessage);
            // Listening now: Lua resends whatever it sent before this.
            report(0);
            return () => window.removeEventListener('message', onMessage);
        }, []);

        // Reported after the commit has reached a frame (two animation frames).
        useEffect(() => {
            if (!state) return undefined;
            let second = 0;
            const first = window.requestAnimationFrame(() => {
                second = window.requestAnimationFrame(() => {
                    painted.current = state.revision;
                    report(state.revision);
                });
            });
            return () => {
                window.cancelAnimationFrame(first);
                window.cancelAnimationFrame(second);
            };
        }, [state]);

        if (!state) return null;
        return h('div', {
            className: 'cx-world-atlas',
            style: { '--u': `${state.u}px`, '--cx-prompt-scale': state.scale }
        }, state.cells.map((cell, index) => h('div', {
            key: index,
            className: 'cx-world-cell',
            style: {
                left: `${(index % state.columns) * state.cellWidth}px`,
                top: `${Math.floor(index / state.columns) * state.cellHeight}px`,
                width: `${state.cellWidth}px`,
                height: `${state.cellHeight}px`
            }
        }, cell ? h(WorldInteractionPrompts, {
            // A new group remounts, so its entrance animation plays.
            key: cell.group,
            items: cell.items,
            place: { x: cell.flipped ? state.anchorRight : state.anchorX, y: state.anchorY, flipped: cell.flipped }
        }) : null)));
    }

    const container = document.getElementById('root');
    if (ReactDOM.createRoot) ReactDOM.createRoot(container).render(h(WorldAtlas));
    else ReactDOM.render(h(WorldAtlas), container);
})();
