// Shared key glyph and hold ring for React prompts and inline 2D consumers.
// One glyph for every key: a disc for one or two characters that grows into a
// pill for longer names, combos ("SHIFT E") and mouse buttons. The ring is a
// single path that starts at 12 o'clock, so the hold fill reads the same on a
// disc and a pill. Loaded by other Cortex resources: keep render/mount stable.
(function (root) {
    'use strict';
    const VIEW_HEIGHT = 48;
    const RING_INSET = 2;
    // Short forms keep bindings legible inside the glyph; identity is unchanged.
    const SHORT = Object.freeze({
        BACKSPACE: 'BKSP', BACK: 'BKSP', ESCAPE: 'ESC', DELETE: 'DEL', RETURN: 'ENTER', CAPSLOCK: 'CAPS',
        CAPITAL: 'CAPS', LCONTROL: 'CTRL', RCONTROL: 'CTRL', CONTROL: 'CTRL', LSHIFT: 'SHIFT', RSHIFT: 'SHIFT',
        LMENU: 'ALT', RMENU: 'ALT', MENU: 'ALT', PAGEUP: 'PGUP', PAGEDOWN: 'PGDN', PRIOR: 'PGUP', NEXT: 'PGDN',
        INSERT: 'INS', SPACEBAR: 'SPACE', ARROWUP: '↑', ARROWDOWN: '↓', ARROWLEFT: '←',
        ARROWRIGHT: '→', UP: '↑', DOWN: '↓', LEFT: '←', RIGHT: '→'
    });
    const MOUSE = Object.freeze({
        MOUSE1: 'LMB', LMB: 'LMB', MOUSE_LEFT: 'LMB', MOUSE2: 'RMB', RMB: 'RMB', MOUSE_RIGHT: 'RMB',
        MOUSE3: 'MMB', MMB: 'MMB', MOUSE_MIDDLE: 'MMB', IOM_WHEEL_UP: 'WHEEL', IOM_WHEEL_DOWN: 'WHEEL',
        MOUSE_WHEEL: 'WHEEL', WHEEL: 'WHEEL', SCROLL: 'WHEEL', MOUSE: 'MOUSE'
    });
    // Approximate advance of the italic condensed caps in viewBox units.
    const CHAR_UNITS = 9.4;
    const GLYPH_UNITS = { mouse: 13, plus: 8, gap: 3 };

// Column-0 on purpose: contract tests extract this normalizer by its shape.
function getInteractionHoldDuration(value) {
    const duration = Number(value);
    if (!Number.isFinite(duration) || duration < 100 || duration > 600000) return null;
    return Math.floor(duration);
}

    /** "SHIFT+E" / "SHIFT E" / "NUMPAD5" / "MOUSE1" -> display parts. */
    function parseKey(value) {
        const raw = String(value == null ? '' : value).trim().toUpperCase().slice(0, 24);
        if (!raw) return [{ type: 'text', text: '?' }];
        const numpad = /^NUM(?:PAD)?\s*([0-9]|ENTER)$/.exec(raw);
        if (numpad) return [{ type: 'text', text: numpad[1] === 'ENTER' ? 'NUM ↵' : `NUM ${numpad[1]}` }];
        // Sided modifiers ("L CTRL") are one key, not a combo.
        const sided = /^([LR])\s+(CTRL|SHIFT|ALT)$/.exec(raw);
        if (sided) return [{ type: 'text', text: `${sided[1]} ${sided[2]}` }];
        const tokens = raw.split(/\s*\+\s*|\s+/).filter(Boolean).slice(0, 3);
        const parts = [];
        tokens.forEach((token, index) => {
            if (index > 0) parts.push({ type: 'plus' });
            if (MOUSE[token]) parts.push({ type: 'mouse', button: MOUSE[token] });
            else parts.push({ type: 'text', text: SHORT[token] || token });
        });
        return parts;
    }

    function measure(parts) {
        let units = 0;
        parts.forEach((part, index) => {
            if (index > 0) units += GLYPH_UNITS.gap;
            if (part.type === 'mouse') units += GLYPH_UNITS.mouse;
            else if (part.type === 'plus') units += GLYPH_UNITS.plus;
            else units += Math.max(1, part.text.length) * CHAR_UNITS;
        });
        return units;
    }

    /** Ring path from 12 o'clock, clockwise, around a disc (w = 48) or a pill. */
    function ringPath(width) {
        const r = VIEW_HEIGHT / 2 - RING_INSET;
        const top = RING_INSET, bottom = VIEW_HEIGHT - RING_INSET;
        const left = RING_INSET + r, right = width - RING_INSET - r, mid = width / 2;
        return `M${mid} ${top}H${right}A${r} ${r} 0 0 1 ${right} ${bottom}H${left}A${r} ${r} 0 0 1 ${left} ${top}Z`;
    }

    function mouseGlyph(h, button) {
        const lit = button === 'LMB' ? 'M1.2 8.2V7a5.8 5.8 0 0 1 5.3-5.8v7Z'
            : button === 'RMB' ? 'M12.8 8.2V7A5.8 5.8 0 0 0 7.5 1.2v7Z' : null;
        const wheelLit = button === 'MMB' || button === 'WHEEL';
        return h('svg', { className: 'cortex-interaction-key-mouse', viewBox: '0 0 14 20', focusable: 'false', 'aria-hidden': 'true' },
            h('rect', { x: '0.6', y: '0.6', width: '12.8', height: '18.8', rx: '6.4', className: 'cortex-interaction-key-mouse-body' }),
            lit ? h('path', { d: lit, className: 'cortex-interaction-key-mouse-lit' }) : null,
            h('path', { d: 'M0.6 8.7H13.4M7 0.6v8.1', className: 'cortex-interaction-key-mouse-seam' }),
            h('rect', { x: '5.5', y: '2.6', width: '3', height: '4.6', rx: '1.5',
                className: wheelLit ? 'cortex-interaction-key-mouse-lit' : 'cortex-interaction-key-mouse-wheel' }),
            button === 'WHEEL' ? h('path', { d: 'M5.2 12.4 7 10.9l1.8 1.5M5.2 15.2 7 16.7l1.8-1.5', className: 'cortex-interaction-key-mouse-seam' }) : null
        );
    }

    function render(h, { item, className, ariaLabel, decorative = false }) {
        const holdDuration = getInteractionHoldDuration(item.holdDuration);
        const isHolding = holdDuration !== null && item.holdActive === true;
        const parts = parseKey(item.key);
        const single = parts.length === 1 && parts[0].type === 'text';
        const width = Math.max(VIEW_HEIGHT, Math.round(measure(parts) + 26));
        const pill = width > VIEW_HEIGHT;
        const span = width / VIEW_HEIGHT;
        const classes = [
            className,
            pill ? 'is-pill' : '',
            // Two-character keys (F7, F10) stay a disc with a tighter face.
            single && parts[0].text.length > 1 && !pill ? 'is-dense' : '',
            // Kept for consumers that styled long keys before the pill existed.
            pill ? 'is-wide' : '',
            holdDuration !== null ? 'has-hold' : '',
            isHolding ? 'is-holding' : ''
        ].filter(Boolean).join(' ');
        const style = { '--cortex-key-span': String(span) };
        if (isHolding) style['--cortex-interaction-hold-duration'] = `${holdDuration}ms`;
        const path = ringPath(width);
        const insetX = `${(16 / span).toFixed(3)}%`;

        return h('span', {
            className: classes,
            style,
            role: decorative ? undefined : 'img',
            'aria-label': decorative ? undefined : ariaLabel,
            'aria-hidden': decorative ? 'true' : undefined
        },
            h('svg', {
                className: 'cortex-interaction-key-ring',
                viewBox: `0 0 ${width} ${VIEW_HEIGHT}`,
                focusable: 'false',
                'aria-hidden': 'true'
            },
                h('path', { className: 'cortex-interaction-key-ring-track', d: path, pathLength: '100' }),
                isHolding ? h('path', {
                    className: 'cortex-interaction-key-ring-progress',
                    key: `hold-${item.holdRevision || 0}`,
                    d: path,
                    pathLength: '100'
                }) : null
            ),
            h('span', {
                className: 'cortex-interaction-key-value',
                style: { left: insetX, right: insetX },
                'aria-hidden': 'true'
            }, ...parts.map((part, index) => part.type === 'mouse'
                ? h('span', { key: `m${index}`, className: 'cortex-interaction-key-part is-mouse' }, mouseGlyph(h, part.button))
                : part.type === 'plus'
                    ? h('span', { key: `p${index}`, className: 'cortex-interaction-key-part is-plus' }, '+')
                    : h('span', { key: `t${index}`, className: 'cortex-interaction-key-part is-text' }, part.text)))
        );
    }

    function mount(node, initial) {
        let signature;
        const svgTags = ['svg', 'circle', 'path', 'rect'];
        function element(tag, props, ...children) {
            const el = svgTags.includes(tag)
                ? node.ownerDocument.createElementNS('http://www.w3.org/2000/svg', tag)
                : node.ownerDocument.createElement(tag);
            for (const [name, value] of Object.entries(props || {})) {
                if (value == null || name === 'key') continue;
                if (name === 'style') {
                    for (const [property, setting] of Object.entries(value)) el.style.setProperty(property, setting);
                } else el.setAttribute(name === 'className' ? 'class' : name, String(value));
            }
            for (const child of children) {
                if (child != null) el.appendChild(typeof child === 'object' ? child : node.ownerDocument.createTextNode(String(child)));
            }
            return el;
        }
        function update(data) {
            const next = JSON.stringify([data.item.key, data.item.holdDuration, data.item.holdActive,
                data.item.holdRevision, data.className, data.ariaLabel, data.decorative]);
            if (signature === next) return;
            signature = next;
            node.replaceChildren(render(element, data));
        }
        update(initial);
        return { update, destroy() { node.replaceChildren(); } };
    }
    root.CortexInteractionKey = Object.freeze({ render, mount, parseKey });
})(typeof window === 'undefined' ? globalThis : window);
