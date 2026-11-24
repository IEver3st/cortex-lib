/* Settings panel inside the pause shell (pause.js owns the frame, focus and
 * gamepad input). Choice controls come from CortexKit: Toggle, Segmented and
 * the one custom Dropdown. Local primitives here: SettingsSlider (native range
 * semantics, Cortex track), SettingsSwatches (colour choice) and the sound
 * picker (Dropdown + play). Lua owns preview, rollback and persistence. */

function normalizeSettingsChoice(option, index) {
    if (!isRecord(option)) return null;
    const value = typeof option.value === 'string' || typeof option.value === 'number' || typeof option.value === 'boolean'
        ? option.value
        : `option-${index + 1}`;
    return {
        value,
        label: boundedText(option.label, boundedText(value), 160),
        name: boundedText(option.name, '', 96),
        set: boundedText(option.set, '', 128)
    };
}

function normalizeSettingsField(field, index) {
    if (!isRecord(field)) return null;
    const allowedTypes = new Set(['toggle', 'select', 'color', 'slider', 'buttons', 'text', 'input', 'soundList']);
    const type = allowedTypes.has(field.type) ? field.type : null;
    const key = boundedText(field.key, '', 96);
    if (!type || !isSafeObjectKey(key)) return null;
    const choices = Array.isArray(field.options)
        ? field.options.slice(0, 64).map(normalizeSettingsChoice).filter(Boolean)
        : [];
    const buttons = Array.isArray(field.buttons)
        ? field.buttons.slice(0, 32).map((button, buttonIndex) => normalizeSettingsChoice(button, buttonIndex)).filter(Boolean)
        : [];

    return {
        ...field,
        type,
        key,
        label: boundedText(field.label, key, 160),
        description: boundedText(field.description, '', 512),
        section: boundedText(field.section, '', 160),
        placeholder: boundedText(field.placeholder, '', 256),
        suffix: boundedText(field.suffix, '%', 24),
        inputType: ['text', 'number', 'email', 'password', 'search', 'url'].includes(field.inputType) ? field.inputType : 'text',
        min: Number.isFinite(field.min) ? field.min : undefined,
        max: Number.isFinite(field.max) ? field.max : undefined,
        step: Number.isFinite(field.step) && field.step > 0 ? field.step : undefined,
        maxLength: Number.isInteger(field.maxLength) ? Math.max(1, Math.min(field.maxLength, NUI_MAX_TEXT_LENGTH)) : undefined,
        options: choices,
        buttons,
        _sourceIndex: index
    };
}

function normalizeSettingsTabs(tabs) {
    if (!Array.isArray(tabs)) return [];
    return tabs.slice(0, 33).map((tab, index) => {
        if (!isRecord(tab)) return null;
        const id = boundedText(tab.id, '', 96);
        if (!isSafeObjectKey(id)) return null;
        const fields = Array.isArray(tab.fields)
            ? tab.fields.slice(0, NUI_MAX_MENU_OPTIONS).map(normalizeSettingsField).filter(Boolean)
            : [];
        const values = {};
        const defaults = {};
        const sourceValues = isRecord(tab.values) ? tab.values : {};
        const sourceDefaults = isRecord(tab.defaults) ? tab.defaults : {};
        for (const field of fields) {
            if (Object.prototype.hasOwnProperty.call(sourceValues, field.key)) {
                values[field.key] = normalizeScalarValue(sourceValues[field.key]);
            }
            if (Object.prototype.hasOwnProperty.call(sourceDefaults, field.key)) {
                defaults[field.key] = normalizeScalarValue(sourceDefaults[field.key]);
            }
        }
        return {
            id,
            label: boundedText(tab.label, id, 160),
            group: boundedText(tab.group, '', 32).trim(),
            fields,
            values,
            defaults
        };
    }).filter(Boolean);
}

// ============================================================================
// PLAYER PREFERENCES HANDSHAKE
// ============================================================================

// Lua pushes `cortex:prefs` on every change; this asks for the current set once
// the page has mounted, retrying while the Lua callback is still registering.
(function requestCortexPrefs(attempt) {
    if (typeof window === 'undefined' || typeof window.GetParentResourceName !== 'function') return;
    void nuiPost('cortexPrefsReady', {}, { timeoutMs: 2000 }).then(response => {
        if (response?.ok !== true && attempt < 5) {
            window.setTimeout(() => requestCortexPrefs(attempt + 1), 1000 * (attempt + 1));
        }
    });
})(0);

const SETTINGS_HEX_COLOR = /^#[0-9a-f]{6}$/i;
const SETTINGS_LIST_AT = 5;
const SETTINGS_MAX_PIPS = 10;

function settingsChoiceKind(field) {
    const options = field.options || [];
    if (field.type === 'color' && options.length > 0 && options.length <= 8
        && options.every(option => typeof option.value === 'string' && SETTINGS_HEX_COLOR.test(option.value))) {
        return 'swatches';
    }
    return 'stepper';
}

function settingsVerticalNav(event) {
    if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
    const target = event.target;
    const kind = target?.getAttribute?.('role');
    const isText = target?.tagName === 'INPUT' && target.type !== 'range';
    if (kind !== 'radio' && target?.type !== 'range' && !isText) return;
    event.preventDefault();
    event.stopPropagation();
    const root = target.closest?.('.cortex-settings-panel');
    window.CortexPause?.moveFocus?.(root, event.key === 'ArrowUp' ? -1 : 1);
}

function formatSettingsNumber(value) {
    if (!Number.isFinite(value)) return '';
    return Number.isInteger(value) ? String(value) : String(Math.round(value * 100) / 100);
}

function settingsStep(options, value, delta) {
    if (!options.length) return value;
    const at = options.findIndex(option => Object.is(option.value, value));
    const from = at < 0 ? (delta > 0 ? -1 : 0) : at;
    return options[(from + delta + options.length * 2) % options.length].value;
}

function SettingsSlider({ field, value, inputId, labelId, descriptionId, onCommit }) {
    const min = Number.isFinite(field.min) ? field.min : 0;
    const max = Number.isFinite(field.max) && field.max > min ? field.max : Math.max(min + 1, 100);
    const step = Number.isFinite(field.step) && field.step > 0 ? field.step : 1;
    const committed = Number.isFinite(value) ? Math.max(min, Math.min(max, value)) : min;
    const [draft, setDraft] = useState(committed);
    const inputRef = useRef(null);
    const commitRef = useRef(onCommit);
    commitRef.current = onCommit;

    useEffect(() => { setDraft(committed); }, [committed]);
    useEffect(() => {
        const input = inputRef.current;
        if (!input) return undefined;
        const commit = () => {
            const next = Number(input.value);
            if (Number.isFinite(next)) commitRef.current(next);
        };
        input.addEventListener('change', commit);
        return () => input.removeEventListener('change', commit);
    }, []);

    const fill = Math.max(0, Math.min(1, (draft - min) / (max - min)));
    const levels = Math.max(2, Math.min(SETTINGS_MAX_PIPS, Math.round((max - min) / step)));
    const lit = Math.round(fill * levels);
    return React.createElement('div', { className: 'cx-settings-slider' },
        React.createElement('span', { className: 'cx-settings-range' },
            React.createElement('span', { className: 'cx-settings-pips', 'aria-hidden': 'true' },
                Array.from({ length: levels }, (_, index) => React.createElement('i', { key: index, className: index < lit ? 'is-lit' : undefined }))),
            React.createElement('input', {
                ref: inputRef,
                id: inputId,
                type: 'range',
                min, max, step,
                value: draft,
                'aria-labelledby': labelId,
                'aria-describedby': field.description ? descriptionId : undefined,
                'aria-valuetext': `${formatSettingsNumber(draft)}${field.suffix || ''}`,
                onChange: event => setDraft(Number(event.target.value))
            })
        ),
        React.createElement('output', { className: 'cx-settings-slider-value', htmlFor: inputId, 'aria-hidden': 'true' },
            formatSettingsNumber(draft), React.createElement('small', null, field.suffix || ''))
    );
}

function SettingsSwatches({ options, value, onChange, labelledBy, custom }) {
    const refs = useRef([]);
    const found = options.findIndex(option => Object.is(option.value, value));
    const isCustom = custom && found < 0 && typeof value === 'string' && SETTINGS_HEX_COLOR.test(value);
    const selectedIndex = isCustom ? -1 : Math.max(0, found);
    const selected = options[selectedIndex];
    const [draft, setDraft] = useState(null);
    const shown = draft ?? (typeof value === 'string' ? value.toUpperCase() : '');
    const typeHex = event => {
        const typed = event.target.value.trim();
        const next = (typed.startsWith('#') ? typed : `#${typed}`).slice(0, 7);
        setDraft(next.toUpperCase());
        if (SETTINGS_HEX_COLOR.test(next)) onChange(next.toLowerCase());
    };
    const move = index => {
        const next = (index + options.length) % options.length;
        onChange(options[next].value);
        window.requestAnimationFrame(() => refs.current[next]?.focus({ preventScroll: true }));
    };
    return React.createElement('div', { className: 'cx-settings-swatches' },
        React.createElement('span', { className: 'cx-settings-swatch-name', 'aria-hidden': 'true' }, isCustom ? 'Custom' : (selected?.label || '')),
        React.createElement('div', { className: 'cx-settings-swatch-row', role: 'radiogroup', 'aria-labelledby': labelledBy },
            options.map((option, index) => React.createElement('button', {
                key: `${option.value}-${index}`,
                ref: element => { refs.current[index] = element; },
                type: 'button',
                role: 'radio',
                className: `cx-settings-swatch${index === selectedIndex ? ' is-selected' : ''}`,
                'aria-checked': index === selectedIndex,
                'aria-label': option.label,
                title: option.label,
                tabIndex: index === Math.max(0, selectedIndex) ? 0 : -1,
                style: { '--swatch': option.value },
                onClick: () => onChange(option.value),
                onKeyDown: event => {
                    if (event.key === 'ArrowRight') { event.preventDefault(); move(index + 1); }
                    else if (event.key === 'ArrowLeft') { event.preventDefault(); move(index - 1); }
                }
            }))
        ),
        custom && React.createElement('input', {
            className: `cx-settings-hex${isCustom ? ' is-selected' : ''}`,
            type: 'text',
            value: shown,
            maxLength: 7,
            spellCheck: false,
            autoComplete: 'off',
            'aria-label': 'Custom colour, hex',
            placeholder: '#8FCBBF',
            style: { '--swatch': isCustom ? value : 'transparent' },
            onChange: typeHex,
            onBlur: () => setDraft(null),
            onKeyDown: event => { if (event.key !== 'Escape' && event.key !== 'Tab') event.stopPropagation(); }
        })
    );
}

const SETTINGS_GLYPHS = {
    play: [['fill', 'M7 4.5v15l12.5-7.5Z']],
    search: [['line', 'M10.5 4a6.5 6.5 0 1 0 0 13a6.5 6.5 0 1 0 0-13Z'], ['line', 'M15.5 15.5 20.5 20.5']],
    reset: [['line', 'M5.5 12a6.5 6.5 0 1 0 2-4.7'], ['line', 'M4 3.5v5.5h5.5']],
    left: [['line', 'M15 5 8 12l7 7']],
    right: [['line', 'M9 5l7 7-7 7']],
    everyday: [['line', 'M12 8a4 4 0 1 0 0 8a4 4 0 1 0 0-8Z'], ['line', 'M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4']],
    equipment: [['line', 'M14.5 4.5a4.5 4.5 0 0 0 5 5L10 19a2.1 2.1 0 0 1-3-3Z']],
    activities: [['line', 'M5.5 21V4h11l-2.5 4.5 2.5 4.5h-11']],
    staff: [['line', 'M12 3l8 3v6c0 4.5-3.4 8-8 9-4.6-1-8-4.5-8-9V6Z']],
    other: [['line', 'M4.5 4.5h5.5v5.5H4.5ZM14 4.5h5.5v5.5H14ZM4.5 14h5.5v5.5H4.5ZM14 14h5.5v5.5H14Z']]
};

function SettingsGlyph({ kind }) {
    const paths = SETTINGS_GLYPHS[kind] || SETTINGS_GLYPHS.other;
    return React.createElement('svg', { viewBox: '0 0 24 24', 'aria-hidden': 'true', focusable: 'false' },
        paths.map(([style, d], index) => React.createElement('path', {
            key: index, d, className: style === 'fill' ? 'cx-settings-glyph-fill' : 'cx-settings-glyph-line'
        })));
}

function SettingsChoiceList({ options, value, anchorRef, labelId, onChoose, onClose }) {
    const menuRef = useRef(null);
    const optionRefs = useRef([]);
    const selected = options.findIndex(option => Object.is(option.value, value));
    const [active, setActive] = useState(Math.max(0, selected));
    const placeMenu = () => {
        const rect = anchorRef.current?.getBoundingClientRect();
        if (!rect) return { visibility: 'hidden' };
        const pad = 12, gap = 8;
        const width = Math.min(Math.max(rect.width + 40, 240), window.innerWidth - pad * 2);
        const below = window.innerHeight - rect.bottom - pad;
        const above = rect.top - pad;
        const up = below < 220 && above > below;
        const left = Math.min(Math.max(pad, rect.right - width), window.innerWidth - pad - width);
        const maxHeight = `${Math.max(96, Math.min(window.innerHeight * 0.42, (up ? above : below) - gap))}px`;
        return up
            ? { left: `${left}px`, bottom: `${window.innerHeight - rect.top + gap}px`, width: `${width}px`, maxHeight }
            : { left: `${left}px`, top: `${rect.bottom + gap}px`, width: `${width}px`, maxHeight };
    };
    const [style, setStyle] = useState(placeMenu);
    const closeRef = useRef(onClose);
    closeRef.current = onClose;

    useEffect(() => {
        const place = () => setStyle(placeMenu());
        place();
        const outside = event => {
            if (menuRef.current?.contains(event.target) || anchorRef.current?.parentElement?.contains(event.target)) return;
            closeRef.current(false);
        };
        document.addEventListener('mousedown', outside);
        window.addEventListener('resize', place);
        return () => {
            document.removeEventListener('mousedown', outside);
            window.removeEventListener('resize', place);
        };
    }, [anchorRef]);

    useEffect(() => {
        const frame = window.requestAnimationFrame(() => {
            const option = optionRefs.current[active];
            option?.focus({ preventScroll: true });
            option?.scrollIntoView({ block: 'nearest' });
        });
        return () => window.cancelAnimationFrame(frame);
    }, [active]);

    const move = index => setActive(Math.max(0, Math.min(options.length - 1, index)));
    return ReactDOM.createPortal(React.createElement('div', {
        ref: menuRef,
        className: 'cx-dropdown-menu cx-settings-menu',
        style,
        role: 'listbox',
        'aria-labelledby': labelId,
        onKeyDown: event => {
            if (event.key === 'ArrowDown') { event.preventDefault(); move(active + 1); }
            else if (event.key === 'ArrowUp') { event.preventDefault(); move(active - 1); }
            else if (event.key === 'Home') { event.preventDefault(); move(0); }
            else if (event.key === 'End') { event.preventDefault(); move(options.length - 1); }
            else if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onChoose(options[active].value); }
            else if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); onClose(true); }
            else if (event.key === 'Tab' || event.key === 'ArrowLeft' || event.key === 'ArrowRight') { event.preventDefault(); onClose(true); }
        }
    }, options.map((option, index) => React.createElement('button', {
        key: `${String(option.value)}-${index}`,
        ref: element => { optionRefs.current[index] = element; },
        type: 'button',
        role: 'option',
        tabIndex: index === active ? 0 : -1,
        'aria-selected': index === selected,
        className: `cx-dropdown-option${index === selected ? ' is-selected' : ''}${index === active ? ' is-active' : ''}`,
        onMouseMove: () => { if (active !== index) setActive(index); },
        onClick: () => onChoose(option.value)
    }, React.createElement('span', null, option.label)))), document.body);
}

function SettingsStepper({ options, value, onChange, labelId, describedBy, valueId }) {
    const [open, setOpen] = useState(false);
    const buttonRef = useRef(null);
    const at = options.findIndex(option => Object.is(option.value, value));
    const shown = at >= 0 ? options[at].label : (value === undefined || value === null || value === '' ? 'Not set' : String(value));
    const listed = options.length >= SETTINGS_LIST_AT;
    const canStep = options.length > 1 || (options.length === 1 && at < 0);
    const step = delta => { if (canStep) onChange(settingsStep(options, value, delta)); };
    const close = restore => {
        setOpen(false);
        if (restore) window.requestAnimationFrame(() => buttonRef.current?.focus({ preventScroll: true }));
    };
    const chevron = (delta, kind) => React.createElement('button', {
        type: 'button', className: 'cx-settings-chev', tabIndex: -1, 'aria-hidden': 'true', disabled: !canStep,
        onMouseDown: event => event.preventDefault(),
        onClick: () => { buttonRef.current?.focus({ preventScroll: true }); step(delta); }
    }, React.createElement(SettingsGlyph, { kind }));
    return React.createElement('div', { className: `cx-settings-stepper${open ? ' is-open' : ''}` },
        chevron(-1, 'left'),
        React.createElement('button', {
            ref: buttonRef,
            type: 'button',
            className: 'cx-settings-step',
            'data-cx-step': '',
            'aria-labelledby': `${labelId} ${valueId}`,
            'aria-describedby': describedBy,
            'aria-haspopup': listed ? 'listbox' : undefined,
            'aria-expanded': listed ? open : undefined,
            disabled: options.length === 0,
            onClick: () => { if (listed) setOpen(current => !current); else step(1); },
            onKeyDown: event => {
                if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
                event.preventDefault();
                step(event.key === 'ArrowLeft' ? -1 : 1);
            }
        }, React.createElement('span', { id: valueId, className: 'cx-settings-step-value' }, shown)),
        chevron(1, 'right'),
        open && React.createElement(SettingsChoiceList, {
            options, value, anchorRef: buttonRef, labelId,
            onChoose: next => { onChange(next); close(true); },
            onClose: close
        })
    );
}

function SettingsSwitch({ checked, onChange, labelId, describedBy }) {
    return React.createElement('button', {
        type: 'button',
        role: 'switch',
        className: `cx-settings-onoff${checked ? ' is-on' : ''}`,
        'data-cx-step': '',
        'aria-checked': checked,
        'aria-labelledby': labelId,
        'aria-describedby': describedBy,
        onClick: () => onChange(!checked),
        onKeyDown: event => {
            if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
            event.preventDefault();
            onChange(!checked);
        }
    },
        React.createElement('span', { className: 'cx-settings-on', 'aria-hidden': 'true' }, 'On'),
        React.createElement('span', { className: 'cx-settings-off', 'aria-hidden': 'true' }, 'Off'));
}

function SettingsSound({ field, value, onChange, onPreviewSound, labelId, descriptionId, valueId }) {
    const options = field.options || [];
    const play = next => {
        const option = options.find(item => Object.is(item.value, next));
        if (option?.name && option?.set) onPreviewSound(option.name, option.set);
    };
    return React.createElement('div', { className: 'cx-settings-sound' },
        React.createElement('button', {
            type: 'button', className: 'cx-settings-icon-button',
            'aria-label': `Play ${boundedText(options.find(item => Object.is(item.value, value))?.label, 'sound', 96)}`,
            title: 'Play', onClick: () => play(value)
        }, React.createElement(SettingsGlyph, { kind: 'play' })),
        React.createElement(SettingsStepper, {
            options, value, labelId, valueId,
            describedBy: field.description ? descriptionId : undefined,
            onChange: next => { onChange(next); play(next); }
        })
    );
}

const SETTINGS_ROW_TARGETS = ['[data-cx-step]:not(:disabled)', 'input:not([tabindex="-1"]):not(:disabled)', '[role="radio"][tabindex="0"]', 'button:not([tabindex="-1"]):not(:disabled)'];
const SETTINGS_ROW_TARGET = SETTINGS_ROW_TARGETS.join(', ');

function focusSettingsRow(event) {
    if (event.target.closest?.('button, input, [role="listbox"]')) return;
    event.currentTarget.querySelector(SETTINGS_ROW_TARGET)?.focus({ preventScroll: true });
}

function SettingsField({ field, value, defaultValue, hasDefault, dirty, tabId, onChange, onAction, onPreviewSound }) {
    if (!field || typeof field !== 'object') return null;
    if (!field.type || !field.key) return null;

    const fieldId = `cortex-setting-${String(tabId).replace(/[^a-z0-9_-]/gi, '-')}-${String(field.key).replace(/[^a-z0-9_-]/gi, '-')}`;
    const labelId = `${fieldId}-label`;
    const descriptionId = `${fieldId}-description`;
    const valueId = `${fieldId}-value`;
    const describedBy = field.description ? descriptionId : undefined;
    const set = next => onChange(tabId, field.key, next);

    const renderControl = () => {
        switch (field.type) {
            case 'toggle':
                return React.createElement(SettingsSwitch, { checked: value === true, onChange: set, labelId, describedBy });

            case 'select':
            case 'color':
                if (settingsChoiceKind(field) === 'swatches') {
                    return React.createElement(SettingsSwatches, { options: field.options, value, onChange: set, labelledBy: labelId, custom: field.custom === true });
                }
                return React.createElement(SettingsStepper, { options: field.options || [], value, onChange: set, labelId, describedBy, valueId });

            case 'slider':
                return React.createElement(SettingsSlider, {
                    field, value, inputId: fieldId, labelId, descriptionId, onCommit: set
                });

            case 'buttons':
                return React.createElement('div', { className: 'cx-settings-actions', role: 'group', 'aria-labelledby': labelId },
                    (field.buttons || []).map(btn => React.createElement('button', {
                        key: String(btn.value),
                        type: 'button',
                        className: 'cx-settings-action',
                        'aria-describedby': describedBy,
                        onClick: () => onAction(tabId, field.key, btn.value)
                    }, btn.label, React.createElement(SettingsGlyph, { kind: 'right' })))
                );

            case 'text':
            case 'input':
                return React.createElement('input', {
                    id: fieldId,
                    type: field.inputType || 'text',
                    className: 'cx-settings-input',
                    placeholder: field.placeholder || '',
                    maxLength: field.maxLength,
                    spellCheck: false,
                    autoCapitalize: 'off',
                    autoCorrect: 'off',
                    value: value !== undefined && value !== null ? value : '',
                    'aria-labelledby': labelId,
                    'aria-describedby': field.description ? descriptionId : undefined,
                    onChange: (e) => set(e.target.value)
                });

            case 'soundList':
                return React.createElement(SettingsSound, { field, value, onChange: set, onPreviewSound, labelId, descriptionId, valueId });

            default:
                return null;
        }
    };

    const canReset = hasDefault === true && field.type !== 'buttons' && !Object.is(value, defaultValue);

    return React.createElement('div', {
        className: `cortex-settings-item${dirty ? ' is-dirty' : ''}`,
        'data-setting': field.key,
        onKeyDownCapture: settingsVerticalNav
    },
        React.createElement('div', { className: 'cortex-settings-row', onClick: focusSettingsRow },
            React.createElement('div', { id: labelId, className: 'cortex-settings-row-label' },
                field.label,
                dirty ? React.createElement('span', { className: 'cortex-settings-row-dirty', title: 'Unsaved change' },
                    React.createElement('span', { className: 'cortex-sr-only' }, ' (unsaved change)')) : null
            ),
            React.createElement('div', { className: 'cortex-settings-row-ctrl' }, renderControl()),
            React.createElement('button', {
                type: 'button',
                className: 'cortex-settings-row-reset',
                disabled: !canReset,
                'aria-hidden': canReset ? undefined : 'true',
                tabIndex: -1,
                title: 'Reset to default',
                'aria-label': `Reset ${field.label} to default`,
                onClick: () => { if (canReset) set(defaultValue); }
            }, React.createElement(SettingsGlyph, { kind: 'reset' }))
        ),
        field.description
            ? React.createElement('div', { id: descriptionId, className: 'cortex-settings-row-desc' }, field.description)
            : null
    );
}

const SETTINGS_PLACE_KEY = 'cortex-lib:settings-place';
let settingsPlace = null;

function normalizeSettingsPlace(data) {
    const record = isRecord(data) ? data : {};
    const advanced = Array.isArray(record.advanced)
        ? [...new Set(record.advanced.filter(id => typeof id === 'string' && id).slice(0, 64).map(id => boundedText(id, '', 128)))]
        : [];
    return {
        tabId: boundedText(record.tabId, '', 128) || null,
        advanced
    };
}

function getSettingsPlace() {
    if (settingsPlace) return settingsPlace;
    let stored = null;
    try { stored = JSON.parse(window.localStorage.getItem(SETTINGS_PLACE_KEY)); } catch { stored = null; }
    settingsPlace = normalizeSettingsPlace(stored);
    return settingsPlace;
}

function rememberSettingsPlace(next) {
    settingsPlace = normalizeSettingsPlace({ ...getSettingsPlace(), ...next });
    try { window.localStorage.setItem(SETTINGS_PLACE_KEY, JSON.stringify(settingsPlace)); } catch { settingsPlace = { ...settingsPlace }; }
}

function settingsTabKey(tab) {
    return tab !== null && typeof tab === 'object' && tab.id != null ? String(tab.id) : null;
}

function findSettingsTab(tabs, tabId) {
    if (!Array.isArray(tabs) || !tabId) return -1;
    return tabs.findIndex(tab => settingsTabKey(tab) === tabId);
}

const SETTINGS_GROUP_ORDER = ['everyday', 'equipment', 'activities', 'staff'];
const SETTINGS_OTHER_GROUP = 'Other';

function settingsLibrary(tabs) {
    const groups = new Map();
    tabs.forEach((tab, index) => {
        const name = (typeof tab?.group === 'string' && tab.group.trim()) || SETTINGS_OTHER_GROUP;
        const key = name.toLowerCase();
        if (!groups.has(key)) groups.set(key, { key, name, items: [] });
        groups.get(key).items.push(index);
    });
    const rank = group => {
        const known = SETTINGS_GROUP_ORDER.indexOf(group.key);
        if (known !== -1) return known;
        return group.key === SETTINGS_OTHER_GROUP.toLowerCase() ? SETTINGS_GROUP_ORDER.length + 1 : SETTINGS_GROUP_ORDER.length;
    };
    const label = index => String(tabs[index]?.label ?? '');
    const isCortex = index => settingsTabKey(tabs[index]) === 'cortex';
    const library = [...groups.values()].sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
    for (const group of library) {
        group.items.sort((a, b) => isCortex(b) - isCortex(a) || label(a).localeCompare(label(b), undefined, { sensitivity: 'base' }));
        group.icon = SETTINGS_GROUP_ORDER.includes(group.key) ? group.key : 'other';
    }
    return library;
}

function firstSettingsStop(root) {
    if (!root) return null;
    return root.querySelector(SETTINGS_ROW_TARGETS.map(target => `.cortex-settings-item ${target}`).join(', '))
        || root.querySelector('button:not([tabindex="-1"]):not(:disabled)');
}

function SettingsRail({ label, children }) {
    return React.createElement('div', {
        className: 'cortex-settings-tabs', role: 'tablist', 'aria-label': label, 'aria-orientation': 'vertical'
    }, children);
}

function SettingsPanel({ open, session, tabs, page: initialPage, pause, onClose }) {
    const [activeTab, setActiveTab] = useState(0);
    const [page, setPage] = useState(initialPage === 'home' ? 'home' : 'settings');
    const [search, setSearch] = useState('');
    const [advanced, setAdvanced] = useState([]);
    const [values, setValues] = useState({});
    const [submitError, setSubmitError] = useState('');
    const [submitting, setSubmitting] = useState(false);
    const [savedValues, setSavedValues] = useState({});
    const [applyStatus, setApplyStatus] = useState('');
    const commitBusy = useRef(false);
    const dialogRef = useRef(null);
    const listRef = useRef(null);
    const searchRef = useRef(null);
    const spyFrame = useRef(0);
    const pendingJump = useRef(null);
    const sessionRef = useRef(normalizeSession(session));
    sessionRef.current = normalizeSession(session);

    useEffect(() => {
        setPage(initialPage === 'home' ? 'home' : 'settings');
        setSearch('');
        setAdvanced(getSettingsPlace().advanced);
    }, [open, session, initialPage]);

    useEffect(() => {
        if (!open) return;
        let active = true;
        void nuiPost('settingsReady', { session }).then(response => {
            if (!active || response?.ok === true) return;
            void nuiPost('settingsCancel', { session }).catch(error => {
                uiDebugLog('settings readiness cleanup failed', error);
            });
            onClose(session);
        }).catch(error => {
            if (!active) return;
            uiDebugLog('settingsReady failed', error);
            void nuiPost('settingsCancel', { session }).catch(cleanupError => {
                uiDebugLog('settings readiness cleanup failed', cleanupError);
            });
            onClose(session);
        });
        return () => { active = false; };
    }, [onClose, open, session]);

    useEffect(() => {
        if (!open || !tabs) return;
        const init = {};
        for (const tab of tabs) {
            if (!tab || tab.id == null) continue;
            init[tab.id] = Object.assign({}, tab.values || {});
        }
        setValues(init);
        setSavedValues(init);
        setApplyStatus('');
        commitBusy.current = false;
        setActiveTab(Math.max(0, findSettingsTab(tabs, getSettingsPlace().tabId)));
        pendingJump.current = { focus: false };
        setSubmitError('');
        setSubmitting(false);
    }, [open, session, tabs]);

    useEffect(() => {
        if (!open || !tabs || tabs.length === 0) return;
        if (activeTab >= tabs.length) setActiveTab(0);
    }, [open, tabs, activeTab]);

    useEffect(() => {
        const jump = pendingJump.current;
        const list = listRef.current;
        if (!jump || !list) return;
        pendingJump.current = null;
        const block = list.querySelector(`[data-tab-index="${activeTab}"]`);
        if (!block) return;
        list.scrollTo({ top: Math.max(0, block.offsetTop - 4), behavior: 'auto' });
        if (jump.focus) firstSettingsStop(block)?.focus({ preventScroll: true });
    });

    const handleChange = useCallback((tabId, key, value) => {
        if (commitBusy.current) return;
        setApplyStatus('');
        const previousTabValues = values[tabId] || {};
        const hadPreviousValue = Object.prototype.hasOwnProperty.call(previousTabValues, key);
        const previousValue = previousTabValues[key];
        setSubmitError('');
        setValues(prev => ({
            ...prev,
            [tabId]: Object.assign({}, prev[tabId] || {}, { [key]: value })
        }));
        void nuiPost('settingsPreview', { tabId, key, value, session }).then(response => {
            if (response?.ok === true || sessionRef.current !== normalizeSession(session)) return;
            setValues(prev => {
                const currentTabValues = prev[tabId] || {};
                if (!Object.is(currentTabValues[key], value)) return prev;
                const rollbackTabValues = { ...currentTabValues };
                if (hadPreviousValue) rollbackTabValues[key] = previousValue;
                else delete rollbackTabValues[key];
                return { ...prev, [tabId]: rollbackTabValues };
            });
            setSubmitError('PREVIEW FAILED');
        }).catch(error => {
            uiDebugLog('settings preview response failed', error);
        });
    }, [session, values]);

    const handleReset = useCallback(tabIndex => {
        if (commitBusy.current) return;
        setApplyStatus('');
        if (!tabs) return;
        const tab = tabs[tabIndex];
        if (!tab) return;
        const previousValues = Object.assign({}, values[tab.id] || {});
        const nextValues = Object.assign({}, tab.defaults || {});
        setValues(prev => ({
            ...prev,
            [tab.id]: nextValues
        }));
        setSubmitError('');
        void nuiPost('settingsPreview', { tabId: tab.id, values: nextValues, session }).then(response => {
            if (response?.ok === true || sessionRef.current !== normalizeSession(session)) return;
            setValues(prev => prev[tab.id] === nextValues
                ? { ...prev, [tab.id]: previousValues }
                : prev);
            setSubmitError('PREVIEW FAILED');
        }).catch(error => {
            uiDebugLog('settings reset response failed', error);
        });
    }, [tabs, session, values]);

    const handleSave = useCallback(async (keepOpen = false) => {
        if (submitting || commitBusy.current) return;
        keepOpen = keepOpen === true;
        commitBusy.current = true;
        const capturedSession = normalizeSession(session);
        setSubmitting(true);
        setSubmitError('');
        setApplyStatus('');
        let response;
        try { response = await nuiPost('settingsSave', { tabs: values, session, keepOpen }); }
        catch { response = { ok: false }; }
        if (sessionRef.current !== capturedSession) return;
        commitBusy.current = false;
        if (response?.ok === true) {
            if (keepOpen) {
                setSavedValues(values);
                setApplyStatus('APPLIED');
                setSubmitting(false);
                return true;
            }
            onClose(session);
            return true;
        }
        setSubmitError(keepOpen ? 'APPLY FAILED' : 'SAVE FAILED');
        setSubmitting(false);
        return false;
    }, [onClose, session, submitting, values]);

    const handleCancel = useCallback(async () => {
        if (submitting || commitBusy.current) return;
        const capturedSession = normalizeSession(session);
        setSubmitting(true);
        const response = await nuiPost('settingsCancel', { session });
        if (sessionRef.current !== capturedSession) return;
        if (response?.ok === true) {
            onClose(session);
            return;
        }
        setSubmitError('CLOSE FAILED');
        setSubmitting(false);
    }, [onClose, session, submitting]);

    const handleAction = useCallback((tabId, key, value) => {
        setSubmitError('');
        void nuiPost('settingsAction', { tabId, key, value, session }).then(response => {
            if (response?.ok !== true && sessionRef.current === normalizeSession(session)) {
                setSubmitError('ACTION FAILED');
            }
        }).catch(error => {
            uiDebugLog('settings action response failed', error);
        });
    }, [session]);

    const handlePreviewSound = useCallback((name, set) => {
        setSubmitError('');
        void nuiPost('settingsPreviewSound', { name, set, session }).then(response => {
            if (response?.ok !== true && sessionRef.current === normalizeSession(session)) {
                setSubmitError('PREVIEW FAILED');
            }
        }).catch(error => {
            uiDebugLog('settings sound preview response failed', error);
        });
    }, [session]);

    const handleBack = useCallback(() => {
        if (submitting) return;
        if (!window.dispatchEvent(new CustomEvent('cortex-page-back', { cancelable: true }))) return;
        if (page === 'settings' && search) { setSearch(''); return; }
        const top = pause?.quickMenu === true ? 'home' : 'settings';
        if (page === 'settings') { void handleCancel(); return; }
        if (page !== top) setPage(top);
        else void handleCancel();
    }, [page, pause, submitting, handleCancel, search]);

    useModalFocus(open, dialogRef, handleBack, session);

    if (!open || !tabs || tabs.length === 0) return null;

    const tab = tabs[activeTab] || tabs[0];
    const tabIndexNow = tabs.indexOf(tab);
    const query = search.trim().toLowerCase();
    const onSettings = page === 'settings';
    const baselineOf = item => savedValues[item.id] || item.values || {};
    const isDirty = (item, key) => Object.prototype.hasOwnProperty.call(values[item.id] || {}, key)
        && !Object.is(values[item.id][key], baselineOf(item)[key]);
    const tabDirtyCount = item => Object.keys(values[item.id] || {}).filter(key => isDirty(item, key)).length;
    const isRelevant = (field, sourceTab) => Object.entries(field.showWhen || {}).every(([key, expected]) =>
        Object.is((values[sourceTab.id] || sourceTab.values || {})[key], expected));
    const dirtyCount = tabs.reduce((total, item) => total + Object.keys(values[item.id] || {}).filter(key =>
        !Object.is(values[item.id][key], (savedValues[item.id] || item.values)?.[key])).length, 0);
    const isOpenAdvanced = item => advanced.includes(settingsTabKey(item));
    const matches = (field, sourceTab) => `${sourceTab.label} ${field.label} ${field.description} ${field.section || 'General'}`.toLowerCase().includes(query);

    const library = onSettings ? settingsLibrary(tabs) : [];
    const order = library.flatMap(group => group.items);
    const activeGroupIndex = Math.max(0, library.findIndex(group => group.items.includes(tabIndexNow)));
    const activeGroup = library[activeGroupIndex];

    const toggleAdvanced = item => {
        const key = settingsTabKey(item);
        const next = advanced.includes(key) ? advanced.filter(id => id !== key) : [...advanced, key];
        setAdvanced(next);
        rememberSettingsPlace({ advanced: next });
    };

    let visibleCount = 0;
    const groupMatches = new Map();
    const blocks = [];
    const blockIndexes = !onSettings ? [] : query ? order : (activeGroup?.items || []);
    for (const tabIndex of blockIndexes) {
        const sourceTab = tabs[tabIndex];
        const relevant = (sourceTab.fields || []).filter(field => isRelevant(field, sourceTab));
        const advancedCount = relevant.filter(field => field.advanced).length;
        const shown = relevant.filter(field => query ? matches(field, sourceTab) : (!field.advanced || isOpenAdvanced(sourceTab)));
        if (query) {
            if (!shown.length) continue;
            const groupIndex = library.findIndex(group => group.items.includes(tabIndex));
            groupMatches.set(groupIndex, (groupMatches.get(groupIndex) || 0) + shown.length);
        }
        visibleCount += shown.length;
        const headId = `cortex-settings-script-${tabIndex}`;
        const sections = new Set(shown.map(field => field.section || 'General'));
        const sourceDefaults = sourceTab.defaults || {};
        const offDefault = (sourceTab.fields || []).some(field => field.type !== 'buttons'
            && Object.prototype.hasOwnProperty.call(sourceDefaults, field.key)
            && !Object.is((values[sourceTab.id] || {})[field.key], sourceDefaults[field.key]));
        const unsaved = tabDirtyCount(sourceTab);
        const rows = [];
        let lastSection = null;
        for (const field of shown) {
            const fieldSection = field.section || 'General';
            if (sections.size > 1 && fieldSection !== lastSection) {
                lastSection = fieldSection;
                rows.push(React.createElement('div', {
                    key: `sec-${sourceTab.id}-${field.key}`, className: 'cortex-settings-section', role: 'heading', 'aria-level': 3
                }, fieldSection));
            }
            rows.push(React.createElement(SettingsField, {
                key: `${sourceTab.id}-${field.key}`, field,
                value: values[sourceTab.id]?.[field.key], tabId: sourceTab.id,
                defaultValue: sourceDefaults[field.key],
                hasDefault: Object.prototype.hasOwnProperty.call(sourceDefaults, field.key),
                dirty: isDirty(sourceTab, field.key),
                onChange: handleChange, onAction: handleAction, onPreviewSound: handlePreviewSound
            }));
        }
        if (!shown.length && !advancedCount) {
            rows.push(React.createElement('div', { key: 'none', className: 'cortex-settings-empty' }, 'Nothing to set here yet.'));
        }
        const showsAdvanced = isOpenAdvanced(sourceTab);
        blocks.push(React.createElement('section', {
            key: `script-${sourceTab.id}`, className: 'cortex-settings-script', 'data-tab-index': tabIndex, 'aria-labelledby': headId
        },
            React.createElement('div', { className: 'cortex-settings-script-head' },
                React.createElement('h2', { id: headId, className: 'cortex-settings-script-title' }, sourceTab.label),
                unsaved > 0 && React.createElement('span', { className: 'cortex-settings-script-dirty' }, `${unsaved} unsaved`),
                !query && offDefault && React.createElement('button', {
                    type: 'button', className: 'cortex-settings-script-reset',
                    onClick: () => handleReset(tabIndex)
                }, React.createElement(SettingsGlyph, { kind: 'reset' }), 'Reset to defaults')),
            rows,
            !query && advancedCount > 0 && React.createElement('button', {
                type: 'button', className: 'pause-advanced-toggle',
                role: 'switch', 'aria-checked': showsAdvanced,
                onClick: () => toggleAdvanced(sourceTab)
            },
                React.createElement('span', { className: 'pause-advanced-label' },
                    showsAdvanced ? 'Hide advanced' : `${advancedCount} advanced ${advancedCount === 1 ? 'setting' : 'settings'}`),
                React.createElement(SettingsGlyph, { kind: showsAdvanced ? 'left' : 'right' }))
        ));
    }

    const jumpTo = (index, focus) => {
        if (index < 0 || index >= tabs.length) return;
        pendingJump.current = { focus: focus === true };
        setActiveTab(index);
        setSearch('');
        rememberSettingsPlace({ tabId: settingsTabKey(tabs[index]) });
    };
    const cycle = delta => {
        if (!order.length || query) return;
        const at = Math.max(0, order.indexOf(tabIndexNow));
        jumpTo(order[(at + delta + order.length) % order.length], true);
    };
    const selectGroup = (groupIndex, focus) => {
        const target = (groupIndex + library.length) % library.length;
        const group = library[target];
        if (!group) return;
        jumpTo(group.items[0], false);
        if (focus) window.requestAnimationFrame(() => dialogRef.current?.querySelector(`#cortex-settings-group-${target}`)?.focus());
    };
    const enterList = () => {
        window.requestAnimationFrame(() => firstSettingsStop(listRef.current)?.focus({ preventScroll: true }));
    };
    const handleTabKeyDown = (event, groupIndex) => {
        if (event.key === 'ArrowRight') enterList();
        else if (event.key === 'ArrowDown') selectGroup(groupIndex + 1, true);
        else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') selectGroup(groupIndex - 1, true);
        else if (event.key === 'Home') selectGroup(0, true);
        else if (event.key === 'End') selectGroup(library.length - 1, true);
        else return;
        event.preventDefault();
    };

    const showTab = index => {
        if (!Number.isInteger(index) || index === activeTab) return;
        setActiveTab(index);
        rememberSettingsPlace({ tabId: settingsTabKey(tabs[index]) });
    };
    const spy = () => {
        if (spyFrame.current) return;
        spyFrame.current = window.requestAnimationFrame(() => {
            spyFrame.current = 0;
            const list = listRef.current;
            if (!list || pendingJump.current) return;
            const inList = [...list.querySelectorAll('[data-tab-index]')];
            const line = list.scrollTop + 48;
            let current = inList[0];
            for (const block of inList) if (block.offsetTop <= line) current = block;
            const atEnd = list.scrollTop + list.clientHeight >= list.scrollHeight - 2;
            const held = list.querySelector(`[data-tab-index="${activeTab}"]`);
            if (atEnd && held && held.offsetTop < list.scrollTop + list.clientHeight) return;
            showTab(Number(current?.dataset.tabIndex));
        });
    };
    const followFocus = event => {
        event.target.closest?.('.cortex-settings-item, .pause-advanced-toggle, .cortex-settings-script-head')?.scrollIntoView({ block: 'nearest' });
        if (query) return;
        showTab(Number(event.target.closest?.('[data-tab-index]')?.dataset.tabIndex));
    };

    const handleBodyKeyDown = event => {
        if (event.defaultPrevented || event.ctrlKey || event.metaKey || event.altKey) return;
        const target = event.target;
        if (target.closest?.('[role="listbox"]')) return;
        const typing = target.tagName === 'INPUT' && target.type !== 'range';
        if (event.key === 'Tab') {
            if (query) return;
            event.preventDefault();
            cycle(event.shiftKey ? -1 : 1);
            return;
        }
        if (target === searchRef.current) {
            if (event.key === 'ArrowDown' || event.key === 'Enter') { event.preventDefault(); enterList(); }
            else if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) event.preventDefault();
            return;
        }
        if (typing) return;
        if (event.key.length === 1 && (event.key !== ' ' || search)) {
            event.preventDefault();
            setSearch(current => (current + event.key).slice(0, 128));
            searchRef.current?.focus({ preventScroll: true });
        } else if (event.key === 'Backspace' && search) {
            event.preventDefault();
            setSearch(current => current.slice(0, -1));
            searchRef.current?.focus({ preventScroll: true });
        }
    };

    const Kit = window.CortexKit;
    const legend = Kit ? React.createElement(Kit.ControlsLegend, {
        className: 'cortex-settings-legend', align: 'end', label: 'Settings controls',
        items: [
            query ? { keys: 'ESC', label: 'Clear search' } : { keys: 'TAB', label: 'Next script' },
            { keys: ['LEFT', 'RIGHT'], label: 'Change' }
        ]
    }) : null;
    const escapeKey = Kit && !query ? React.createElement(Kit.Keycap, { value: 'ESC', size: 'sm' }) : null;
    const note = submitError || (dirtyCount ? `${dirtyCount} unsaved` : applyStatus);
    const empty = query ? `No settings match "${search.trim()}".` : 'No scripts have registered settings.';

    return React.createElement(window.CortexPause.Frame, {
        open, page, setPage, pause, dialogRef, session, post: nuiPost,
        onResume: handleCancel, onSave: handleSave, onApply: () => handleSave(true), onBack: handleBack, onCycle: cycle,
        submitting, dirtyCount, error: submitError
    },
        onSettings && React.createElement('fieldset', {
            className: 'pause-settings-body', disabled: submitting, 'aria-busy': submitting, onKeyDown: handleBodyKeyDown
        },
            React.createElement('div', { className: 'cortex-settings-brand', 'aria-hidden': 'true' }, pause?.title || 'CORTEX'),
            React.createElement('label', { className: `pause-search${query ? ' is-live' : ''}` },
                React.createElement(SettingsGlyph, { kind: 'search' }),
                React.createElement('span', { className: 'pause-search-field' },
                    React.createElement('input', {
                        ref: searchRef, type: 'search', value: search, maxLength: 128,
                        placeholder: 'Type to search', 'aria-label': 'Search all script settings',
                        spellCheck: false, autoComplete: 'off',
                        onChange: event => setSearch(event.target.value)
                    }),
                    React.createElement('span', { className: `pause-search-mirror${search ? ' has-text' : ''}`, 'aria-hidden': 'true' },
                        React.createElement('span', null, search, React.createElement('i', { className: 'pause-search-caret' })))),
                query && React.createElement('span', { className: 'pause-search-count', role: 'status' },
                    `${visibleCount} ${visibleCount === 1 ? 'result' : 'results'}`)),
            React.createElement('aside', { className: 'cortex-settings-rail' },
                React.createElement(SettingsRail, { label: 'Setting groups' },
                    library.map((group, groupIndex) => {
                        const selected = !query && groupIndex === activeGroupIndex;
                        const found = groupMatches.get(groupIndex) || 0;
                        const groupDirty = group.items.some(index => tabDirtyCount(tabs[index]) > 0);
                        return React.createElement('button', {
                            key: group.key,
                            type: 'button',
                            id: `cortex-settings-group-${groupIndex}`,
                            role: 'tab',
                            'aria-selected': selected,
                            'aria-controls': 'cortex-settings-tabpanel',
                            tabIndex: groupIndex === activeGroupIndex ? 0 : -1,
                            'data-autofocus': groupIndex === activeGroupIndex ? 'true' : undefined,
                            'data-pause-autofocus': groupIndex === activeGroupIndex ? true : undefined,
                            className: `cortex-settings-tab${selected ? ' active' : ''}${groupDirty ? ' is-dirty' : ''}${query && !found ? ' is-empty' : ''}`,
                            onClick: () => (selected ? enterList() : selectGroup(groupIndex, false)),
                            onKeyDown: event => handleTabKeyDown(event, groupIndex)
                        },
                            React.createElement(SettingsGlyph, { kind: group.icon }),
                            React.createElement('span', { className: 'cortex-settings-tab-name' }, group.name),
                            query && React.createElement('span', { className: 'cortex-settings-tab-count', 'aria-hidden': 'true' }, found));
                    })),
                !query && activeGroup && activeGroup.items.length > 1 && React.createElement('nav', { className: 'cortex-settings-scripts', 'aria-label': `${activeGroup.name} scripts` },
                    activeGroup.items.map(index => React.createElement('button', {
                        key: settingsTabKey(tabs[index]) || index,
                        type: 'button',
                        tabIndex: -1,
                        'aria-current': index === tabIndexNow ? 'true' : undefined,
                        className: `cortex-settings-script-link${index === tabIndexNow ? ' active' : ''}${tabDirtyCount(tabs[index]) ? ' is-dirty' : ''}`,
                        onClick: () => jumpTo(index, true)
                    }, React.createElement('span', null, tabs[index].label))))
            ),
            React.createElement('div', {
                id: 'cortex-settings-tabpanel', ref: listRef, className: 'cortex-settings-content', role: 'tabpanel',
                'aria-labelledby': query ? undefined : `cortex-settings-group-${activeGroupIndex}`,
                'aria-label': query ? 'Search results across all scripts' : undefined,
                onScroll: query ? undefined : spy,
                onFocus: followFocus
            }, blocks.length ? blocks : React.createElement('div', { className: 'cortex-settings-empty' }, empty)),
            React.createElement('div', { className: 'cortex-settings-footer' },
                React.createElement('span', {
                    className: `cortex-settings-live-note${submitError ? ' error' : ''}${!submitError && dirtyCount ? ' is-dirty' : ''}`,
                    role: 'status',
                    'aria-live': 'polite'
                }, note),
                React.createElement('div', { className: 'cortex-settings-footer-right' },
                    legend,
                    React.createElement('button', { type: 'button', className: 'cortex-settings-btn cancel', onClick: handleCancel, disabled: submitting }, escapeKey, 'Discard & resume'),
                    React.createElement('button', { type: 'button', className: 'cortex-settings-btn apply', onClick: () => handleSave(true), disabled: submitting || !dirtyCount }, 'Apply'),
                    React.createElement('button', { type: 'button', className: 'cortex-settings-btn save', onClick: handleSave, disabled: submitting }, 'Save & resume')
                )
            )
        )
    );
}

// ============================================================================
// HUD updates must not rebuild the pause tree. Its own state and new settings
// snapshots still render normally through React's default shallow comparison.
const MemoizedSettingsPanel = React.memo(SettingsPanel);
