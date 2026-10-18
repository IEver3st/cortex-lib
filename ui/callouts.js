/* The callout label atlas (client/callout_dui.lua).
 *
 * The game renders this page into a DUI texture and draws pieces of it on an
 * entity: every label row, switch and pin is a cell here, and Lua draws each
 * cell where it belongs with SetDrawOrigin. Lua sends what every cell says and
 * where it sits in the atlas (in u, padding included) only when that changes,
 * numbered by revision; this page paints them and reports each revision once
 * it has reached a frame, so Lua draws moved cells only when they are on the
 * texture (and stops resending: messages sent before this page listens are
 * lost). Nothing here is seen as a page or takes input. */
(function () {
    'use strict';
    const h = React.createElement;
    const { useState, useEffect, useRef } = React;
    const MAX_CELLS = 512;
    const TONES = new Set(['off', 'on', 'you', 'no']);
    const params = new URLSearchParams(window.location.search);
    const resource = params.get('resource') || 'cortex-lib';
    // Which DUI this is: a replaced page may still report.
    const dui = Number(params.get('dui')) || 0;

    // No Content-Type header: a JSON content type makes the request preflighted,
    // and FiveM parses a text/plain body as JSON anyway.
    function report(revision) {
        fetch(`https://${resource}/calloutsPainted`, {
            method: 'POST',
            body: JSON.stringify({ dui, revision })
        }).catch(() => undefined);
    }

    const num = (value) => typeof value === 'number' && Number.isFinite(value);
    const str = (value) => typeof value === 'string';

    function readCell(raw) {
        if (!raw || typeof raw !== 'object') return null;
        if (!num(raw.x) || !num(raw.y) || !num(raw.w) || !num(raw.h)) return null;
        const box = { x: raw.x, y: raw.y, w: raw.w, h: raw.h };
        const tone = TONES.has(raw.tone) ? raw.tone : 'off';
        if (raw.k === 'pin' && (raw.v === 'idle' || raw.v === 'on' || raw.v === 'hot')) return { ...box, k: 'pin', v: raw.v };
        if (raw.k === 'row' && (raw.size === 'lg' || raw.size === 'sm') && str(raw.name)) {
            return { ...box, k: 'row', size: raw.size, name: raw.name, chip: str(raw.chip) ? raw.chip : '', tone,
                rw: num(raw.rw) ? raw.rw : raw.w, hot: raw.hot === true };
        }
        if (raw.k === 'switch' && str(raw.text)) {
            return { ...box, k: 'switch', text: raw.text, tone, rw: num(raw.rw) ? raw.rw : raw.w, hot: raw.hot === true };
        }
        return null;
    }

    function readMetrics(m) {
        if (!m || typeof m !== 'object' || !m.row || !m.row.lg || !m.row.sm || !m.switch) return null;
        if (!num(m.pad) || !num(m.nameSpacing) || !num(m.chipSpacing)) return null;
        return m;
    }

    // SendDuiMessage arrives as a string or as the decoded object.
    function readAtlas(raw) {
        let message = raw;
        if (str(message)) {
            try { message = JSON.parse(message); } catch { return null; }
        }
        if (!message || typeof message !== 'object' || message.action !== 'callouts:atlas') return null;
        const data = message.data;
        if (!data || !Number.isInteger(data.revision) || data.revision < 1 || !num(data.r) || data.r <= 0 || data.r > 8
            || !Array.isArray(data.cells) || data.cells.length > MAX_CELLS) return null;
        const metrics = readMetrics(data.metrics);
        if (!metrics) return null;
        const cells = data.cells.map(readCell).filter(Boolean);
        const accent = str(data.accent) && /^#[0-9a-f]{6}$/i.test(data.accent) ? data.accent : '#8fcbbf';
        return { revision: data.revision, r: data.r, accent, cells, metrics };
    }

    const u = (value) => `calc(${value} * var(--u))`;

    // One cell: a label row, a switch or a pin, painted `pad` inside its box
    // so the halo and the paper flip's shadow are never cut.
    function Cell({ cell, metrics }) {
        let inner;
        if (cell.k === 'pin') {
            inner = h('span', { className: `pin ${cell.v}` });
        } else if (cell.k === 'row') {
            const m = metrics.row[cell.size];
            inner = h('div', {
                className: `row ${cell.size} tone-${cell.tone}${cell.hot ? ' hot' : ''}`,
                style: {
                    left: u(metrics.pad), top: u(metrics.pad), width: u(cell.rw), height: u(m.h),
                    paddingLeft: u(m.padL), paddingRight: u(m.padR), gap: u(m.gap),
                    fontSize: u(m.name), letterSpacing: `${metrics.nameSpacing}em`
                }
            },
            h('span', { className: 'name' }, cell.name),
            cell.chip ? h('span', {
                className: 'chip',
                style: {
                    fontSize: u(m.chip), letterSpacing: `${metrics.chipSpacing}em`,
                    paddingLeft: u(m.chipPadL), paddingRight: u(m.chipPadR)
                }
            }, cell.chip) : null);
        } else {
            const m = metrics.switch;
            inner = h('div', {
                className: `switch tone-${cell.tone}${cell.hot ? ' hot' : ''}`,
                style: {
                    left: u(metrics.pad), top: u(metrics.pad), width: u(cell.rw), height: u(m.h),
                    paddingLeft: u(m.padL), paddingRight: u(m.padR),
                    fontSize: u(m.text), letterSpacing: `${metrics.chipSpacing}em`
                }
            }, cell.text);
        }
        return h('div', {
            className: 'cell',
            style: { left: u(cell.x), top: u(cell.y), width: u(cell.w), height: u(cell.h) }
        }, inner);
    }

    function CalloutAtlas() {
        const [atlas, setAtlas] = useState(null);
        const painted = useRef(0);

        useEffect(() => {
            let alive = true;
            let latest = 0;
            // Text measured by Lua needs the display face, so nothing paints before it.
            const fonts = document.fonts.load('italic 800 25px "Barlow Condensed"').catch(() => []);
            const onMessage = (event) => {
                const next = readAtlas(event.data);
                if (!next) return;
                fonts.then(() => {
                    if (!alive) return;
                    // A resend of what is painted already: say so again. A resend
                    // of what is still painting reports when it lands; anything
                    // older is stale.
                    if (next.revision === painted.current) report(next.revision);
                    else if (next.revision > latest) {
                        latest = next.revision;
                        setAtlas(next);
                    }
                });
            };
            window.addEventListener('message', onMessage);
            // Listening now: Lua resends whatever it sent before this.
            fonts.then(() => { if (alive) report(0); });
            return () => {
                alive = false;
                window.removeEventListener('message', onMessage);
            };
        }, []);

        // Reported after the commit has reached a frame (two animation frames).
        useEffect(() => {
            if (!atlas) return undefined;
            let second = 0;
            const first = window.requestAnimationFrame(() => {
                second = window.requestAnimationFrame(() => {
                    painted.current = atlas.revision;
                    report(atlas.revision);
                });
            });
            return () => {
                window.cancelAnimationFrame(first);
                window.cancelAnimationFrame(second);
            };
        }, [atlas]);

        if (!atlas) return null;
        return h('div', {
            className: 'atlas',
            style: { '--u': `${atlas.r}px`, '--accent': atlas.accent }
        }, atlas.cells.map((cell, index) => h(Cell, { key: index, cell, metrics: atlas.metrics })));
    }

    const container = document.getElementById('root');
    if (ReactDOM.createRoot) ReactDOM.createRoot(container).render(h(CalloutAtlas));
    else ReactDOM.render(h(CalloutAtlas), container);
})();
