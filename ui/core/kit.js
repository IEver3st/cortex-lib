/* Cortex kit: the shared primitives every library surface composes. One keycap,
 * one control hint, one meter, one ring, one dropdown, one toggle, one segmented
 * control and one player-preference store, so every surface speaks the same
 * state language (CORTEX-DESIGN.md sections 3-5). Sizes live in kit.css in --u. */
(function (root) {
    'use strict';
    const h = React.createElement;
    const { useState, useEffect, useRef, useCallback, useSyncExternalStore } = React;

    // ------------------------------------------------------------------------
    // Player preferences. Lua pushes `cortex:prefs`; surfaces read usePrefs().
    // Shared appearance (accent, opacity, motion) arrives through dynamic-ui.js.
    // ------------------------------------------------------------------------
    const PREF_RULES = Object.freeze({
        scale: value => Number.isFinite(value) && value >= 0.8 && value <= 1.3 ? Math.round(value * 100) / 100 : undefined,
        textSize: value => value === 'large' || value === 'standard' ? value : undefined,
        notifyDuration: value => Number.isFinite(value) && value >= 0.5 && value <= 3 ? value : undefined,
        notifyLimit: value => Number.isInteger(value) && value >= 1 && value <= 12 ? value : undefined,
        showPercent: value => typeof value === 'boolean' ? value : undefined,
        promptMarkers: value => typeof value === 'boolean' ? value : undefined,
        promptScale: value => ['small', 'standard', 'large'].includes(value) ? value : undefined,
        controlHints: value => typeof value === 'boolean' ? value : undefined,
        invertScroll: value => typeof value === 'boolean' ? value : undefined
    });
    const DEFAULT_PREFS = Object.freeze({
        scale: 1,
        textSize: 'standard',
        notifyDuration: 1,
        notifyLimit: 5,
        showPercent: true,
        promptMarkers: true,
        promptScale: 'standard',
        controlHints: true,
        invertScroll: false
    });
    const PROMPT_SCALES = Object.freeze({ small: 0.88, standard: 1, large: 1.16 });
    let prefs = DEFAULT_PREFS;
    const prefListeners = new Set();

    function applyPrefsToDocument(next) {
        const style = document.documentElement.style;
        style.setProperty('--cx-scale', String(next.scale));
        style.setProperty('--cx-text', next.textSize === 'large' ? '1.14' : '1');
        style.setProperty('--cx-prompt-scale', String(PROMPT_SCALES[next.promptScale] || 1));
        document.documentElement.dataset.cxHints = next.controlHints ? 'on' : 'off';
    }

    function setPrefs(partial) {
        if (!partial || typeof partial !== 'object' || Array.isArray(partial)) return false;
        const next = { ...prefs };
        let changed = false;
        for (const [key, rule] of Object.entries(PREF_RULES)) {
            if (!Object.prototype.hasOwnProperty.call(partial, key)) continue;
            const value = rule(partial[key]);
            if (value === undefined || Object.is(value, next[key])) continue;
            next[key] = value;
            changed = true;
        }
        if (!changed) return false;
        prefs = Object.freeze(next);
        applyPrefsToDocument(prefs);
        prefListeners.forEach(listener => listener());
        return true;
    }

    const subscribePrefs = listener => {
        prefListeners.add(listener);
        return () => prefListeners.delete(listener);
    };
    const getPrefs = () => prefs;
    const usePrefs = () => useSyncExternalStore(subscribePrefs, getPrefs, getPrefs);
    applyPrefsToDocument(prefs);

    // ------------------------------------------------------------------------
    // Key labels. One normalisation for prompts, legends, menus and skill checks.
    // ------------------------------------------------------------------------
    const KEY_ALIASES = Object.freeze({
        MOUSE1: 'LMB', MOUSE_LEFT: 'LMB', LEFTMOUSE: 'LMB', 'L-CLICK': 'LMB', LCLICK: 'LMB',
        MOUSE2: 'RMB', MOUSE_RIGHT: 'RMB', RIGHTMOUSE: 'RMB', 'R-CLICK': 'RMB', RCLICK: 'RMB',
        MOUSE3: 'MMB', MOUSE_MIDDLE: 'MMB',
        IOM_WHEEL_UP: 'WHEEL', IOM_WHEEL_DOWN: 'WHEEL', MOUSE_WHEEL: 'WHEEL', SCROLL: 'WHEEL',
        ESCAPE: 'ESC', RETURN: 'ENTER', DELETE: 'DEL', CONTROL: 'CTRL', LCONTROL: 'CTRL', RCONTROL: 'CTRL',
        LSHIFT: 'SHIFT', RSHIFT: 'SHIFT', LMENU: 'ALT', RMENU: 'ALT', SPACEBAR: 'SPACE', BACK: 'BACKSPACE',
        ARROWUP: 'UP', ARROWDOWN: 'DOWN', ARROWLEFT: 'LEFT', ARROWRIGHT: 'RIGHT',
        PAGEUP: 'PGUP', PAGEDOWN: 'PGDN'
    });
    const KEY_GLYPHS = Object.freeze({ UP: '↑', DOWN: '↓', LEFT: '←', RIGHT: '→', ARROWS: '↑↓' });
    const MOUSE_KEYS = new Set(['LMB', 'RMB', 'MMB', 'WHEEL', 'MOUSE']);

    function normalizeKey(value) {
        const raw = String(value ?? '').trim().toUpperCase().slice(0, 24);
        if (!raw) return '';
        const compact = raw.replace(/\s+/g, '');
        if (KEY_ALIASES[compact]) return KEY_ALIASES[compact];
        const numpad = /^NUMPAD([0-9]|ENTER)$/.exec(compact);
        if (numpad) return numpad[1] === 'ENTER' ? 'NUM ENTER' : `NUM ${numpad[1]}`;
        return raw;
    }

    /** Splits "SHIFT E" / "SHIFT+E" into keycaps; keeps "NUM 5" together. */
    function splitKeys(value) {
        const text = String(value ?? '').trim();
        if (!text) return [];
        if (/^NUM(PAD)?\s*[0-9]$/i.test(text)) return [normalizeKey(text.replace(/\s+/g, ''))];
        return text.split(/\s*\+\s*|\s+/).slice(0, 4).map(normalizeKey).filter(Boolean);
    }

    /**
     * Solid mouse silhouette cut by the button seams, so it never reads as a
     * zero at keycap size. The pressed button (LMB/RMB) or the wheel (MMB,
     * WHEEL) is lit; MOVE shows the plain silhouette with travel ticks.
     */
    function MouseGlyph({ button }) {
        const lit = button === 'LMB' ? 'M1.2 8.2V7a5.8 5.8 0 0 1 5.3-5.8v7Z'
            : button === 'RMB' ? 'M12.8 8.2V7A5.8 5.8 0 0 0 7.5 1.2v7Z' : null;
        return h('svg', { className: 'cx-key-mouse', viewBox: '0 0 14 20', 'aria-hidden': 'true', focusable: 'false' },
            h('rect', { x: 0.6, y: 0.6, width: 12.8, height: 18.8, rx: 6.4, className: 'cx-key-mouse-body' }),
            lit ? h('path', { d: lit, className: 'cx-key-mouse-lit' }) : null,
            h('path', { d: 'M0.6 8.7H13.4M7 0.6v8.1', className: 'cx-key-mouse-seam' }),
            h('rect', { x: 5.5, y: 2.6, width: 3, height: 4.6, rx: 1.5,
                className: button === 'MMB' || button === 'WHEEL' ? 'cx-key-mouse-lit' : 'cx-key-mouse-wheel' }),
            button === 'WHEEL' ? h('path', { d: 'M5.2 12.4 7 10.9l1.8 1.5M5.2 15.2 7 16.7l1.8-1.5', className: 'cx-key-mouse-seam' }) : null
        );
    }

    /** The Cortex keycap: paper block, ink italic caps, 2u ink drop shadow. */
    function Keycap({ value, size = 'md', tone = 'paper', pressed = false, className = '' }) {
        const key = normalizeKey(value);
        const mouse = MOUSE_KEYS.has(key);
        const glyph = KEY_GLYPHS[key];
        const classes = ['cx-key', `cx-key--${size}`, `cx-key--${tone}`,
            mouse ? 'is-mouse' : '', glyph ? 'is-glyph' : '', key.length > 3 && !mouse && !glyph ? 'is-wide' : '',
            pressed ? 'is-pressed' : '', className].filter(Boolean).join(' ');
        const mouseNames = { WHEEL: 'Mouse wheel', MOUSE: 'Mouse', LMB: 'Left mouse button', RMB: 'Right mouse button', MMB: 'Middle mouse button' };
        return h('kbd', { className: classes, 'aria-label': mouse ? mouseNames[key] : undefined },
            mouse ? h(MouseGlyph, { button: key }) : (glyph || key));
    }

    /** Label + keycap(s). `order: 'key-first'` for lists, `'label-first'` for edge legends. */
    function KeyHint({ keys, label, order = 'key-first', size = 'md', tone = 'paper', pressed = false, disabled = false }) {
        const caps = (Array.isArray(keys) ? keys.flatMap(splitKeys) : splitKeys(keys));
        const keyNodes = caps.map((key, index) => h(Keycap, { key: `${key}-${index}`, value: key, size, tone, pressed }));
        const labelNode = label ? h('span', { className: 'cx-hint-label' }, label) : null;
        return h('span', { className: `cx-hint cx-hint--${order}${disabled ? ' is-disabled' : ''}` },
            order === 'label-first' ? labelNode : null,
            h('span', { className: 'cx-hint-keys' }, keyNodes),
            order === 'label-first' ? null : labelNode
        );
    }

    /** A row of control hints. Hidden entirely when the player turns hints off. */
    function ControlsLegend({ items, order = 'key-first', align = 'start', size = 'sm', className = '', label = 'Controls', always = false }) {
        const list = (Array.isArray(items) ? items : []).filter(item => item && (item.keys || item.key));
        if (!list.length) return null;
        return h('div', {
            className: `cx-legend cx-legend--${align}${always ? ' is-always' : ''} ${className}`.trim(),
            role: 'group',
            'aria-label': label
        }, list.map((item, index) => h(KeyHint, {
            key: `${item.label || ''}-${index}`,
            keys: item.keys || item.key,
            label: item.label,
            order,
            size,
            disabled: item.disabled === true
        })));
    }

    // ------------------------------------------------------------------------
    // Meters. Frameless: a --rule track, a fill, nothing thinner than 4u.
    // ------------------------------------------------------------------------
    const clamp01 = value => Math.max(0, Math.min(1, Number(value) || 0));
    const TONES = new Set(['accent', 'paper', 'warning', 'error', 'info', 'success']);
    const toneOf = tone => TONES.has(tone) ? tone : 'accent';

    function Meter({ value, tone = 'accent', size = 'md', className = '', label }) {
        const fill = clamp01(value);
        return h('span', {
            className: `cx-meter cx-meter--${size} cx-tone--${toneOf(tone)} ${className}`.trim(),
            role: label ? 'progressbar' : undefined,
            'aria-label': label,
            'aria-valuemin': label ? 0 : undefined,
            'aria-valuemax': label ? 100 : undefined,
            'aria-valuenow': label ? Math.round(fill * 100) : undefined,
            'aria-hidden': label ? undefined : 'true',
            style: { '--cx-fill': fill }
        }, h('i', { className: 'cx-meter-fill' }));
    }

    /**
     * Thick SVG ring. `value` 0..1 fills clockwise from 12 o'clock. `arc` limits
     * the sweep (1 = full circle) for gauges. Stroke is in viewBox units of a
     * 100-unit box so it scales with the element and never drops under 3u.
     */
    function Ring({ value, tone = 'accent', stroke = 10, arc = 1, className = '', children, track = true }) {
        const radius = 50 - stroke / 2;
        const sweep = Math.max(0.05, Math.min(1, arc));
        const fill = clamp01(value) * sweep;
        const rotate = -90 + (1 - sweep) * 180;
        const common = { cx: 50, cy: 50, r: radius, pathLength: 100, strokeWidth: stroke, fill: 'none' };
        return h('span', { className: `cx-ring cx-tone--${toneOf(tone)} ${className}`.trim() },
            h('svg', { viewBox: '0 0 100 100', 'aria-hidden': 'true', focusable: 'false', style: { transform: `rotate(${rotate}deg)` } },
                track ? h('circle', { ...common, className: 'cx-ring-track', strokeDasharray: `${sweep * 100} 100` }) : null,
                fill > 0 ? h('circle', { ...common, className: 'cx-ring-fill', strokeDasharray: `${fill * 100} 100` }) : null
            ),
            children ? h('span', { className: 'cx-ring-center' }, children) : null
        );
    }

    // ------------------------------------------------------------------------
    // Controls: toggle, check, segmented, dropdown. No native select/checkbox.
    // ------------------------------------------------------------------------
    function Toggle({ checked, onChange, label, labelledBy, describedBy, disabled = false, id }) {
        return h('button', {
            id,
            type: 'button',
            role: 'switch',
            className: `cx-toggle${checked ? ' is-on' : ''}`,
            'aria-checked': checked === true,
            'aria-label': labelledBy ? undefined : label,
            'aria-labelledby': labelledBy,
            'aria-describedby': describedBy,
            disabled,
            onClick: () => onChange?.(!checked)
        }, h('span', { className: 'cx-toggle-knob', 'aria-hidden': 'true' }));
    }

    /** A square check mark in the Cortex state language (mint fill when on). */
    function CheckMark({ checked }) {
        return h('span', { className: `cx-check${checked ? ' is-on' : ''}`, 'aria-hidden': 'true' },
            h('svg', { viewBox: '0 0 16 16', focusable: 'false' }, h('path', { d: 'M3.2 8.4 6.6 11.6 12.8 4.6' })));
    }

    function optionValue(option) { return option && typeof option === 'object' ? option.value : option; }
    function optionLabel(option) {
        if (option && typeof option === 'object') return String(option.label ?? option.value ?? '');
        return String(option ?? '');
    }

    function Segmented({ options, value, onChange, label, labelledBy, disabled = false }) {
        const list = Array.isArray(options) ? options : [];
        const refs = useRef([]);
        const selectedIndex = Math.max(0, list.findIndex(option => Object.is(optionValue(option), value)));
        const move = (index) => {
            const next = (index + list.length) % list.length;
            onChange?.(optionValue(list[next]));
            window.requestAnimationFrame(() => refs.current[next]?.focus({ preventScroll: true }));
        };
        return h('div', {
            className: 'cx-segmented',
            role: 'radiogroup',
            'aria-label': labelledBy ? undefined : label,
            'aria-labelledby': labelledBy
        }, list.map((option, index) => {
            const selected = index === selectedIndex;
            return h('button', {
                key: `${String(optionValue(option))}-${index}`,
                ref: element => { refs.current[index] = element; },
                type: 'button',
                role: 'radio',
                className: `cx-segment${selected ? ' is-selected' : ''}`,
                'aria-checked': selected,
                tabIndex: selected ? 0 : -1,
                disabled,
                onClick: () => onChange?.(optionValue(option)),
                onKeyDown: event => {
                    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') { event.preventDefault(); move(index + 1); }
                    else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') { event.preventDefault(); move(index - 1); }
                }
            }, optionLabel(option));
        }));
    }

    let dropdownCounter = 0;

    /**
     * Custom dropdown with a portal list, keyboard path and viewport-aware
     * placement. `options` are `{ value, label }` records or scalars.
     */
    function Dropdown({ options, value, onChange, label, id, labelledBy, describedBy, disabled = false, placeholder = 'Select', scope }) {
        const triggerRef = useRef(null);
        const menuRef = useRef(null);
        const optionRefs = useRef([]);
        const idRef = useRef(null);
        const [open, setOpen] = useState(false);
        const [activeIndex, setActiveIndex] = useState(0);
        const [menuStyle, setMenuStyle] = useState({});
        if (idRef.current === null) idRef.current = `cx-dropdown-${++dropdownCounter}`;
        const list = Array.isArray(options) ? options.filter(option => optionValue(option) !== undefined) : [];
        const selectedIndex = list.findIndex(option => Object.is(optionValue(option), value));
        const selectedLabel = selectedIndex >= 0 ? optionLabel(list[selectedIndex]) : (value == null || value === '' ? placeholder : String(value));
        const menuId = `${idRef.current}-menu`;

        const place = useCallback(() => {
            const trigger = triggerRef.current;
            if (!trigger) return;
            const rect = trigger.getBoundingClientRect();
            const pad = 12, gap = 6;
            const width = Math.min(Math.max(rect.width, 160), Math.max(160, innerWidth - pad * 2));
            const below = innerHeight - rect.bottom - pad;
            const above = rect.top - pad;
            const up = below < 180 && above > below;
            const left = Math.min(Math.max(pad, rect.left), Math.max(pad, innerWidth - pad - width));
            const maxHeight = `${Math.max(96, Math.min(innerHeight * 0.42, (up ? above : below) - gap))}px`;
            setMenuStyle(up
                ? { left: `${left}px`, bottom: `${Math.max(pad, innerHeight - rect.top + gap)}px`, width: `${width}px`, maxHeight }
                : { left: `${left}px`, top: `${Math.min(innerHeight - pad, rect.bottom + gap)}px`, width: `${width}px`, maxHeight });
        }, []);

        const close = useCallback((restore) => {
            setOpen(false);
            if (restore) window.requestAnimationFrame(() => triggerRef.current?.focus({ preventScroll: true }));
        }, []);

        const choose = useCallback((index) => {
            const option = list[index];
            if (option === undefined) return;
            onChange?.(optionValue(option));
            close(true);
        }, [list, onChange, close]);

        useEffect(() => {
            if (!open) return undefined;
            place();
            window.requestAnimationFrame(() => optionRefs.current[activeIndex]?.focus({ preventScroll: true }));
            const outside = event => {
                if (triggerRef.current?.contains(event.target) || menuRef.current?.contains(event.target)) return;
                close(false);
            };
            document.addEventListener('mousedown', outside);
            window.addEventListener('resize', place);
            window.addEventListener('scroll', place, true);
            return () => {
                document.removeEventListener('mousedown', outside);
                window.removeEventListener('resize', place);
                window.removeEventListener('scroll', place, true);
            };
        }, [open, activeIndex, place, close]);

        const openAt = (index) => {
            if (!list.length || disabled) return;
            setActiveIndex(Math.max(0, Math.min(list.length - 1, index)));
            setOpen(true);
        };
        const moveTo = (index) => {
            const bounded = Math.max(0, Math.min(list.length - 1, index));
            setActiveIndex(bounded);
            window.requestAnimationFrame(() => optionRefs.current[bounded]?.focus({ preventScroll: true }));
        };
        const resolved = selectedIndex >= 0 ? selectedIndex : 0;

        const menu = open ? ReactDOM.createPortal(h('div', {
            ref: menuRef,
            id: menuId,
            className: `cx-dropdown-menu${scope ? ` ${scope}` : ''}`,
            style: menuStyle,
            role: 'listbox',
            'aria-label': label,
            onKeyDown: event => {
                if (event.key === 'ArrowDown') { event.preventDefault(); moveTo((activeIndex + 1) % list.length); }
                else if (event.key === 'ArrowUp') { event.preventDefault(); moveTo((activeIndex - 1 + list.length) % list.length); }
                else if (event.key === 'Home') { event.preventDefault(); moveTo(0); }
                else if (event.key === 'End') { event.preventDefault(); moveTo(list.length - 1); }
                else if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); choose(activeIndex); }
                else if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close(true); }
                else if (event.key === 'Tab') { event.preventDefault(); close(true); }
            }
        }, list.map((option, index) => {
            const selected = index === selectedIndex;
            return h('button', {
                ref: element => { optionRefs.current[index] = element; },
                key: `${String(optionValue(option))}-${index}`,
                type: 'button',
                role: 'option',
                tabIndex: index === activeIndex ? 0 : -1,
                'aria-selected': selected,
                className: `cx-dropdown-option${selected ? ' is-selected' : ''}${index === activeIndex ? ' is-active' : ''}`,
                onMouseMove: () => { if (activeIndex !== index) setActiveIndex(index); },
                onClick: () => choose(index)
            }, h('span', null, optionLabel(option)));
        })), document.body) : null;

        return h('span', { className: 'cx-dropdown' },
            h('button', {
                ref: triggerRef,
                id,
                type: 'button',
                className: `cx-dropdown-trigger${open ? ' is-open' : ''}`,
                role: 'combobox',
                'aria-label': labelledBy ? undefined : label,
                'aria-labelledby': labelledBy,
                'aria-describedby': describedBy,
                'aria-haspopup': 'listbox',
                'aria-expanded': open,
                'aria-controls': menuId,
                disabled: disabled || list.length === 0,
                onClick: () => open ? close(false) : openAt(resolved),
                onKeyDown: event => {
                    if (event.key === 'ArrowDown') { event.preventDefault(); openAt(Math.min(list.length - 1, resolved + (open ? 1 : 0))); }
                    else if (event.key === 'ArrowUp') { event.preventDefault(); openAt(Math.max(0, resolved - (open ? 1 : 0))); }
                }
            },
                h('span', { className: 'cx-dropdown-value' }, selectedLabel),
                h('span', { className: 'cx-dropdown-caret', 'aria-hidden': 'true' })
            ),
            menu
        );
    }

    /** Eyebrow + italic display title + optional meta, with the mint accent bar. */
    function SlipHeader({ eyebrow, title, meta, id }) {
        return h('header', { className: 'cx-slip-header' },
            eyebrow ? h('span', { className: 'cx-eyebrow' }, eyebrow) : null,
            h('span', { className: 'cx-slip-title-row' },
                h('span', { id, className: 'cx-slip-title', role: 'heading', 'aria-level': 2 }, title),
                meta != null && meta !== '' ? h('span', { className: 'cx-slip-meta' }, meta) : null
            )
        );
    }

    /**
     * Converts "[E] Inspect crate" / "Press ~INPUT_CONTEXT~" style text into
     * text and keycap parts, so every consumer string reads the same way.
     */
    function parseKeyText(text) {
        const source = String(text ?? '');
        const parts = [];
        const pattern = /\[([^\]\n]{1,24})\]|~INPUT_[A-Z_]+~/g;
        let last = 0;
        let match;
        while ((match = pattern.exec(source)) && parts.length < 32) {
            if (match.index > last) parts.push({ type: 'text', value: source.slice(last, match.index) });
            parts.push({ type: 'key', value: match[1] ? match[1] : 'E' });
            last = pattern.lastIndex;
        }
        if (last < source.length) parts.push({ type: 'text', value: source.slice(last) });
        return parts;
    }

    root.CortexKit = Object.freeze({
        DEFAULT_PREFS,
        setPrefs,
        getPrefs,
        usePrefs,
        normalizeKey,
        splitKeys,
        MouseGlyph,
        parseKeyText,
        Keycap,
        KeyHint,
        ControlsLegend,
        Meter,
        Ring,
        Toggle,
        CheckMark,
        Segmented,
        Dropdown,
        SlipHeader,
        optionValue,
        optionLabel
    });
})(window);
