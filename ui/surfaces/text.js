/* Text UI, the controls legend (help) and the diagnostics panel.
 * Text UI: a frameless contextual instruction; `[E]` tokens become keycaps.
 * Help: the GTA-style controls legend, label-first, bottom-right, safe-zone aware.
 * Debug panel: a developer slip in the data face, not player chrome. */

function normalizeHelpItems(items) {
    if (!Array.isArray(items)) return [];
    return items.slice(0, NUI_MAX_HELP_ITEMS).map(item => {
        if (!isRecord(item)) return null;
        const value = boundedText(item.value, '', 128);
        if (!value) return null;
        return { label: boundedText(item.label, '', 160), value };
    }).filter(Boolean);
}

function normalizeDebugLines(lines) {
    if (!Array.isArray(lines)) return [];
    return lines.slice(0, 128).map(line => {
        if (typeof line === 'string') return line.slice(0, 1024);
        if (!isRecord(line)) return null;
        return {
            label: boundedText(line.label, '', 160),
            value: isRecord(line.value) || Array.isArray(line.value)
                ? line.value
                : boundedText(line.value, '', 2048),
            color: boundedText(line.color, '', 96) || null
        };
    }).filter(Boolean);
}

/** Mounted while open plus a short exit, so overlays leave instead of vanishing. */
function useOverlayPresence(open, exitMs = 160) {
    const [mounted, setMounted] = useState(Boolean(open));
    useEffect(() => {
        if (open) {
            setMounted(true);
            return undefined;
        }
        const timer = setTimeout(() => setMounted(false), exitMs);
        return () => clearTimeout(timer);
    }, [open, exitMs]);
    return Boolean(open) || mounted;
}

// ============================================================================
// KEY TOKENS. The help `value` is free text from consumers: "W S A D",
// "Esc · Backspace", "SHIFT+E", "LEFT ALT", "Up Down", or prose ("Recording tab").
// ============================================================================

const HELP_KEY_NAMES = new Set([
    'ESC', 'ESCAPE', 'ENTER', 'RETURN', 'SPACE', 'SPACEBAR', 'TAB', 'SHIFT', 'CTRL', 'CONTROL', 'ALT', 'BACKSPACE',
    'BACK', 'BKSP', 'DEL', 'DELETE', 'INS', 'INSERT', 'HOME', 'END', 'PGUP', 'PGDN', 'PAGEUP', 'PAGEDOWN', 'UP', 'DOWN',
    'LEFT', 'RIGHT', 'ARROWS', 'ARROWUP', 'ARROWDOWN', 'ARROWLEFT', 'ARROWRIGHT', 'MOUSE', 'MOUSE1', 'MOUSE2', 'MOUSE3',
    'LMB', 'RMB', 'MMB', 'WHEEL', 'SCROLL', 'CAPS', 'CAPSLOCK', 'LSHIFT', 'RSHIFT', 'LCTRL', 'RCTRL', 'LALT', 'RALT',
    'LCONTROL', 'RCONTROL', 'LMENU', 'RMENU', 'NUM', 'NUMPAD', 'PRTSC', 'PAUSE', 'CLICK', 'LCLICK', 'RCLICK'
]);
const HELP_KEY_SEPARATORS = new Set(['·', '•', '|', '/', ',', 'OR']);
const HELP_KEY_SIDES = new Set(['LEFT', 'RIGHT', 'L', 'R']);
const HELP_KEY_MODIFIERS = new Set(['ALT', 'SHIFT', 'CTRL', 'CONTROL']);
const HELP_MAX_KEYCAPS = 8;

function isHelpKeyToken(token) {
    const upper = token.toUpperCase();
    if (HELP_KEY_NAMES.has(upper)) return true;
    if (/^[A-Z0-9]$/i.test(token)) return true;
    if (/^F(?:[1-9]|1[0-9]|2[0-4])$/i.test(token)) return true;
    if (/^NUMPAD[0-9]$/i.test(token) || /^IOM_[A-Z_]+$/.test(token)) return true;
    if (/^[[\];',.`\-=~+?\\<>]$/.test(token)) return true;
    // Consumer-written caps such as "PGUP" or "MOUSE4" read as keys; mixed-case
    // words ("Recording", "tab") read as prose.
    return /^[A-Z0-9_]{2,10}$/.test(token);
}

/**
 * Splits a help value into keycap, separator and text tokens. If any word is
 * not a key the whole value renders as prose, so sentences never become caps.
 */
function tokenizeHelpKeys(value) {
    const source = String(value ?? '').trim().slice(0, 128);
    if (!source) return [];
    const words = source.split(/\s+/).flatMap(word => {
        if (word.length > 1 && word.includes('+')) {
            return word.split('+').filter(Boolean).flatMap((part, index) => index ? [{ join: true }, part] : [part]);
        }
        return [word];
    });
    const tokens = [];
    let keycaps = 0;
    for (let index = 0; index < words.length; index++) {
        const word = words[index];
        if (word && word.join) continue;
        const upper = word.toUpperCase();
        if (HELP_KEY_SEPARATORS.has(upper)) {
            if (tokens.length && tokens[tokens.length - 1].type === 'key') tokens.push({ type: 'sep', value: '/' });
            continue;
        }
        if (!isHelpKeyToken(word)) return [{ type: 'text', value: source }];
        let key = upper;
        const next = words[index + 1];
        if (HELP_KEY_SIDES.has(upper) && typeof next === 'string' && HELP_KEY_MODIFIERS.has(next.toUpperCase())) {
            key = `${upper[0]} ${next.toUpperCase() === 'CONTROL' ? 'CTRL' : next.toUpperCase()}`;
            index += 1;
        } else if ((upper === 'NUM' || upper === 'NUMPAD') && typeof next === 'string' && /^[0-9]$/.test(next)) {
            key = `NUM ${next}`;
            index += 1;
        } else if (upper === 'BKSP') {
            key = 'BACKSPACE';
        }
        if (keycaps >= HELP_MAX_KEYCAPS) break;
        keycaps += 1;
        tokens.push({ type: 'key', value: key });
    }
    if (tokens.length && tokens[tokens.length - 1].type === 'sep') tokens.pop();
    return tokens;
}

// Legend keys use the same disc/pill glyph as the prompts they sit beside.
function HelpKeyTokens({ value }) {
    return tokenizeHelpKeys(value).map((token, index) => {
        if (token.type === 'key') {
            return React.createElement('span', { key: index, className: 'cortex-help-key-slot' },
                window.CortexInteractionKey.render(React.createElement, {
                    item: { key: token.value },
                    className: 'cortex-help-key',
                    decorative: true
                }));
        }
        if (token.type === 'sep') return React.createElement('span', { key: index, className: 'cortex-help-sep', 'aria-hidden': 'true' }, '/');
        return React.createElement('span', { key: index, className: 'cortex-help-text' }, token.value);
    });
}

// ============================================================================
// DEBUG PANEL
// ============================================================================

/** Bounded JSON (safeJson), indented for reading. */
function formatDebugJson(value) {
    const compact = safeJson(value);
    try {
        return JSON.stringify(JSON.parse(compact), null, 2).slice(0, 16384);
    } catch (_) {
        return compact;
    }
}

function DebugPanelLine({ line, index }) {
    if (typeof line === 'string') {
        return React.createElement('div', { className: 'cortex-debug-line is-text' }, line);
    }

    const label = line?.label;
    let value = line?.value;

    if (value == null) value = '';
    if (typeof value === 'object') value = safeJson(value);
    const color = normalizeIconColor(line?.color);

    return React.createElement('div', { className: 'cortex-debug-line', 'data-row': index % 2 ? 'odd' : 'even' },
        React.createElement('span', { className: 'cortex-debug-label' }, label || ''),
        React.createElement('span', { className: 'cortex-debug-value', style: color ? { color } : undefined }, String(value))
    );
}

function DebugPanel({ open, title, subtitle, position, lines, data, accentColor }) {
    const kit = window.CortexKit;
    const present = useOverlayPresence(open);
    if (!present) return null;

    const rootClass = `cortex-debug-root ${position || 'top-right'}${open ? '' : ' is-leaving'}`;
    const hasData = data && typeof data === 'object';
    const accent = normalizeIconColor(accentColor);
    const list = Array.isArray(lines) ? lines : [];

    return React.createElement('div', { className: rootClass, style: accent ? { '--debug-accent': accent } : undefined },
        React.createElement('section', { className: 'cortex-debug-panel cx-slip', 'aria-label': title || 'Debug' },
            React.createElement('div', { className: 'cortex-debug-header' },
                React.createElement(kit.SlipHeader, { eyebrow: subtitle || 'Diagnostics', title: title || 'DEBUG' })
            ),
            React.createElement('div', { className: 'cortex-debug-body' },
                list.map((line, idx) => React.createElement(DebugPanelLine, { key: idx, line, index: idx })),
                hasData ? React.createElement('pre', { className: 'cortex-debug-json' }, formatDebugJson(data)) : null
            )
        )
    );
}

// ============================================================================
// TEXT UI COMPONENT
// ============================================================================

const textUiIcons = {
    hand: React.createElement('svg', { viewBox: '0 0 24 24', focusable: 'false', 'aria-hidden': 'true' },
        // Open palm as single finger strokes, spaced so a 3u stroke never fills in.
        React.createElement('path', { d: 'M7.6 12.2V7.4' }),
        React.createElement('path', { d: 'M11.4 11V4.6' }),
        React.createElement('path', { d: 'M15.2 11V5.4' }),
        React.createElement('path', { d: 'M19 12.4V8.4' }),
        React.createElement('path', { d: 'M19 12.4v2.2a6.4 6.4 0 0 1-6.4 6.4h-1.1a6 6 0 0 1-4.9-2.6L3.8 14.6a1.6 1.6 0 0 1 2.6-1.8l1.2 1.5V12.2' })
    )
};

function isTextUiPlateStyleKey(key) {
    const k = String(key).toLowerCase();
    if (k === 'background' || k === 'backgroundcolor' || k === 'backgroundimage') return true;
    if (k === 'boxshadow' || k === 'outline' || k === 'backdropfilter' || k === 'webkitbackdropfilter') return true;
    if (k.startsWith('border')) return true;
    return false;
}

function partitionTextUiStyle(style, backdrop) {
    if (!style || typeof style !== 'object') return { outer: undefined };
    if (backdrop) return { outer: style };
    const outer = {};
    for (const key of Object.keys(style)) {
        if (isTextUiPlateStyleKey(key)) continue;
        outer[key] = style[key];
    }
    return { outer: Object.keys(outer).length ? outer : undefined };
}

// Short instructions read as a display-caps action; longer copy as a sentence.
const TEXT_UI_ACTION_MAX = 44;

/** Parses text UI copy into keycap groups and text runs. */
function parseTextUiParts(text) {
    const kit = window.CortexKit;
    return kit.parseKeyText(text).map(part => part.type === 'key'
        ? { type: 'key', keys: kit.splitKeys(part.value).slice(0, 4) }
        : { type: 'text', value: part.value }
    ).filter(part => part.type === 'text' ? part.value.length > 0 : part.keys.length > 0);
}

function classifyTextUi(text, parts) {
    const prose = parts.filter(part => part.type === 'text').map(part => part.value).join(' ').replace(/\s+/g, ' ').trim();
    return prose.length <= TEXT_UI_ACTION_MAX && !/\n/.test(text) ? 'action' : 'sentence';
}

function TextUI({ open, text, position, icon, style, backdrop }) {
    const kit = window.CortexKit;
    const present = useOverlayPresence(open);
    if (!present) return null;

    const source = typeof text === 'string' ? text : '';
    const parts = parseTextUiParts(source);
    const mode = classifyTextUi(source, parts);
    const iconEl = icon ? (textUiIcons[icon] || null) : null;
    const keySize = mode === 'action' ? 'lg' : 'md';
    const className = ['textui', position || 'bottom-center', `textui--${mode}`, iconEl ? 'has-icon' : '',
        backdrop ? 'textui-backdrop' : '', open ? '' : 'is-leaving'].filter(Boolean).join(' ');
    const { outer: outerStyle } = partitionTextUiStyle(style, Boolean(backdrop));

    let previous = null;
    const nodes = parts.map((part, index) => {
        const afterText = previous === 'text';
        previous = part.type;
        if (part.type === 'key') {
            return React.createElement('span', { key: index, className: `textui-keys${afterText ? ' after-text' : ''}` },
                part.keys.map((key, keyIndex) => React.createElement(kit.Keycap, { key: keyIndex, value: key, size: keySize })));
        }
        const value = mode === 'action' ? part.value.trim() : part.value;
        return value ? React.createElement('span', { key: index, className: 'textui-run' }, value) : null;
    });

    return React.createElement('div', {
        id: 'textui',
        className,
        style: outerStyle,
        role: 'status',
        'aria-live': 'polite',
        'aria-atomic': 'true'
    },
        iconEl && React.createElement('span', { className: 'textui-icon', 'aria-hidden': 'true' }, iconEl),
        React.createElement('span', { className: 'textui-text' }, nodes)
    );
}

// ============================================================================
// HELP: THE CONTROLS LEGEND
// ============================================================================

function HelpBar({ open, items, compact }) {
    const present = useOverlayPresence(open);
    const legendRef = useRef(null);
    const list = Array.isArray(items) ? items : [];

    // Publish the legend's height so bottom-right neighbours (screen prompts)
    // can sit above it instead of underneath.
    useEffect(() => {
        const rootStyle = document.documentElement.style;
        const element = legendRef.current;
        if (!open || !element || typeof ResizeObserver !== 'function') {
            rootStyle.setProperty('--cx-help-legend-height', '0px');
            return undefined;
        }
        const observer = new ResizeObserver(() => {
            rootStyle.setProperty('--cx-help-legend-height', `${Math.round(element.getBoundingClientRect().height)}px`);
        });
        observer.observe(element);
        return () => {
            observer.disconnect();
            rootStyle.setProperty('--cx-help-legend-height', '0px');
        };
    }, [open, list.length, compact]);

    if (!present || !list.length) return null;

    const className = ['cortex-help-bar', 'cx-legend', 'cx-legend--end', 'is-always',
        compact ? 'cortex-help-bar--compact' : '', open ? '' : 'is-leaving'].filter(Boolean).join(' ');

    return React.createElement('div', { ref: legendRef, className, role: 'group', 'aria-label': 'Controls' },
        list.map((item, index) => React.createElement('span', {
            key: `${item.label}-${index}`,
            className: 'cortex-help-item cx-hint cx-hint--label-first'
        },
            item.label ? React.createElement('span', { className: 'cortex-help-label cx-hint-label' }, item.label) : null,
            React.createElement('span', { className: 'cortex-help-values cx-hint-keys' },
                React.createElement(HelpKeyTokens, { value: item.value }))
        ))
    );
}
