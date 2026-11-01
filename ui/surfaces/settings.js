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

// ============================================================================
// SETTINGS CONTROLS
// ============================================================================

const SETTINGS_HEX_COLOR = /^#[0-9a-f]{6}$/i;

/** Which custom control renders a choice field: never a native select. */
function settingsChoiceKind(field) {
    const options = field.options || [];
    if (field.type === 'color' && options.length > 0 && options.length <= 8
        && options.every(option => typeof option.value === 'string' && SETTINGS_HEX_COLOR.test(option.value))) {
        return 'swatches';
    }
    const labelLength = options.reduce((total, option) => total + String(option.label ?? option.value).length, 0);
    return options.length > 1 && options.length <= 4 && labelLength <= 34 ? 'segmented' : 'dropdown';
}

/** Up/Down always travels between rows; Left/Right stays inside a choice. */
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

/**
 * Native range input for semantics and keyboard/pad stepping; Cortex draws the
 * track. The value readout follows the drag, but the preview (and so any live
 * change of UI scale) is committed on release or on each key step.
 */
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
    return React.createElement('div', { className: 'cx-settings-slider' },
        React.createElement('span', { className: 'cx-settings-range', style: { '--fill': fill } },
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

/** Colour choice as a radio row of chips; the selected chip flips to paper. */
function SettingsSwatches({ options, value, onChange, labelledBy, custom }) {
    const refs = useRef([]);
    const found = options.findIndex(option => Object.is(option.value, value));
    // A custom colour matches no swatch: none is selected, the first still takes Tab.
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
            }, React.createElement('i', { 'aria-hidden': 'true' })))
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
        }),
        React.createElement('span', { className: 'cx-settings-swatch-name', 'aria-hidden': 'true' }, isCustom ? 'Custom' : (selected?.label || ''))
    );
}

function SettingsGlyph({ kind }) {
    // 24-unit boxes rendered at 18-20u: a 4-unit stroke stays above 3u.
    if (kind === 'play') {
        return React.createElement('svg', { viewBox: '0 0 24 24', 'aria-hidden': 'true', focusable: 'false' },
            React.createElement('path', { d: 'M7 4.5v15l12.5-7.5Z', className: 'cx-settings-glyph-fill' }));
    }
    if (kind === 'search') {
        return React.createElement('svg', { viewBox: '0 0 24 24', 'aria-hidden': 'true', focusable: 'false' },
            React.createElement('circle', { cx: 10.5, cy: 10.5, r: 6.5, className: 'cx-settings-glyph-line' }),
            React.createElement('path', { d: 'M15.5 15.5 20.5 20.5', className: 'cx-settings-glyph-line' }));
    }
    return React.createElement('svg', { viewBox: '0 0 24 24', 'aria-hidden': 'true', focusable: 'false' },
        React.createElement('path', { d: 'M5.5 12a6.5 6.5 0 1 0 2-4.7', className: 'cx-settings-glyph-line' }),
        React.createElement('path', { d: 'M4 3.5v5.5h5.5', className: 'cx-settings-glyph-line' }));
}

function SettingsSound({ field, value, onChange, onPreviewSound, labelId, descriptionId }) {
    const Kit = window.CortexKit;
    const options = field.options || [];
    const play = next => {
        const option = options.find(item => Object.is(item.value, next));
        if (option?.name && option?.set) onPreviewSound(option.name, option.set);
    };
    return React.createElement('div', { className: 'cx-settings-sound' },
        React.createElement(Kit.Dropdown, {
            options, value, labelledBy: labelId,
            describedBy: field.description ? descriptionId : undefined,
            scope: 'cx-settings-menu',
            onChange: next => { onChange(next); play(next); }
        }),
        React.createElement('button', {
            type: 'button', className: 'cx-settings-icon-button',
            'aria-label': `Play ${boundedText(options.find(item => Object.is(item.value, value))?.label, 'sound', 96)}`,
            title: 'Play', onClick: () => play(value)
        }, React.createElement(SettingsGlyph, { kind: 'play' }))
    );
}

function SettingsField({ field, value, defaultValue, hasDefault, dirty, tabId, onChange, onAction, onPreviewSound }) {
    if (!field || typeof field !== 'object') return null;
    if (!field.type || !field.key) return null;
    const Kit = window.CortexKit;

    const fieldId = `cortex-setting-${String(tabId).replace(/[^a-z0-9_-]/gi, '-')}-${String(field.key).replace(/[^a-z0-9_-]/gi, '-')}`;
    const labelId = `${fieldId}-label`;
    const descriptionId = `${fieldId}-description`;
    const set = next => onChange(tabId, field.key, next);

    const renderControl = () => {
        switch (field.type) {
            case 'toggle':
                return React.createElement(Kit.Toggle, {
                    checked: value === true, labelledBy: labelId,
                    describedBy: field.description ? descriptionId : undefined,
                    onChange: set
                });

            case 'select':
            case 'color': {
                const kind = settingsChoiceKind(field);
                if (kind === 'swatches') {
                    return React.createElement(SettingsSwatches, { options: field.options, value, onChange: set, labelledBy: labelId, custom: field.custom === true });
                }
                if (kind === 'segmented') {
                    return React.createElement(Kit.Segmented, { options: field.options, value, onChange: set, labelledBy: labelId });
                }
                return React.createElement(Kit.Dropdown, {
                    options: field.options, value, onChange: set, labelledBy: labelId,
                    describedBy: field.description ? descriptionId : undefined, scope: 'cx-settings-menu'
                });
            }

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
                        onClick: () => onAction(tabId, field.key, btn.value)
                    }, btn.label))
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
                return React.createElement(SettingsSound, { field, value, onChange: set, onPreviewSound, labelId, descriptionId });

            default:
                return null;
        }
    };

    // Per-row reset: only when a default exists and the value has moved off it.
    const canReset = hasDefault === true && field.type !== 'buttons' && !Object.is(value, defaultValue);

    return React.createElement('div', {
        className: `cortex-settings-row${dirty ? ' is-dirty' : ''}`,
        'data-setting': field.key,
        onKeyDownCapture: settingsVerticalNav
    },
        React.createElement('div', { className: 'cortex-settings-row-info' },
            React.createElement('div', { id: labelId, className: 'cortex-settings-row-label' },
                field.label,
                dirty ? React.createElement('span', { className: 'cortex-settings-row-dirty', title: 'Unsaved change' },
                    React.createElement('span', { className: 'cortex-sr-only' }, ' (unsaved change)')) : null
            ),
            field.description
                ? React.createElement('div', { id: descriptionId, className: 'cortex-settings-row-desc' }, field.description)
                : null
        ),
        React.createElement('div', { className: 'cortex-settings-row-ctrl' }, renderControl()),
        React.createElement('button', {
            type: 'button',
            className: 'cortex-settings-row-reset',
            disabled: !canReset,
            'aria-hidden': canReset ? undefined : 'true',
            tabIndex: canReset ? 0 : -1,
            title: 'Reset to default',
            'aria-label': `Reset ${field.label} to default`,
            onClick: () => { if (canReset) set(defaultValue); }
        }, React.createElement(SettingsGlyph, { kind: 'reset' }))
    );
}

function settingsScrollBehavior() {
    const motion = document.documentElement.dataset.cxMotion;
    return (motion ? motion === 'reduced' : window.matchMedia('(prefers-reduced-motion: reduce)').matches) ? 'auto' : 'smooth';
}

function SettingsRail({ active, label, children }) {
    const listRef = useRef(null);
    useEffect(() => {
        const node = listRef.current;
        const tab = node?.querySelector(`#cortex-settings-tab-${active}`);
        if (!tab) return;
        const top = tab.offsetTop, bottom = top + tab.offsetHeight;
        if (top < node.scrollTop) node.scrollTo({ top, behavior: settingsScrollBehavior() });
        else if (bottom > node.scrollTop + node.clientHeight) node.scrollTo({ top: bottom - node.clientHeight, behavior: settingsScrollBehavior() });
    }, [active]);

    return React.createElement('div', {
        ref: listRef, className: 'cortex-settings-tabs', role: 'tablist', 'aria-label': label, 'aria-orientation': 'vertical'
    }, children);
}

// ============================================================================
// PLACE. Reopening Settings returns to the tab, section and Advanced switch the
// player last used. Tabs are matched by id, so scripts that register or stop
// between opens cannot shift it. Navigation only: values never live here. CEF
// storage carries it across reconnects; without storage it lasts the session.
// ============================================================================

const SETTINGS_PLACE_KEY = 'cortex-lib:settings-place';
let settingsPlace = null;

function normalizeSettingsPlace(data) {
    const record = isRecord(data) ? data : {};
    return {
        tabId: boundedText(record.tabId, '', 128) || null,
        section: boundedText(record.section, '', 160),
        advanced: record.advanced === true
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
    try { window.localStorage.setItem(SETTINGS_PLACE_KEY, JSON.stringify(settingsPlace)); } catch { /* the session copy still holds */ }
}

function settingsTabKey(tab) {
    return isRecord(tab) && tab.id != null ? String(tab.id) : null;
}

/** Index of the remembered tab, or -1 when it is not registered now. */
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
    }
    return library;
}

// ============================================================================
// SETTINGS PANEL
// ============================================================================

function SettingsPanel({ open, session, tabs, page: initialPage, pause, onClose }) {
    const [activeTab, setActiveTab] = useState(0);
    const [page, setPage] = useState(initialPage === 'home' ? 'home' : 'settings');
    const [search, setSearch] = useState('');
    const [section, setSection] = useState('');
    const [showAdvanced, setShowAdvanced] = useState(false);
    const [values, setValues] = useState({});
    const [submitError, setSubmitError] = useState('');
    const [submitting, setSubmitting] = useState(false);
    const [savedValues, setSavedValues] = useState({});
    const [applyStatus, setApplyStatus] = useState('');
    const commitBusy = useRef(false);
    const dialogRef = useRef(null);
    const sessionRef = useRef(normalizeSession(session));
    sessionRef.current = normalizeSession(session);

    useEffect(() => {
        const place = getSettingsPlace();
        const placed = findSettingsTab(tabs, place.tabId) !== -1;
        setPage(initialPage === 'home' ? 'home' : 'settings');
        setSearch('');
        setSection(placed ? place.section : '');
        setShowAdvanced(placed && place.advanced);
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
        setSubmitError('');
        setSubmitting(false);
    }, [open, session, tabs]);

    useEffect(() => {
        if (!open || !tabs || tabs.length === 0) return;
        if (activeTab >= tabs.length) setActiveTab(0);
    }, [open, tabs, activeTab]);

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

    const handleReset = useCallback(() => {
        if (commitBusy.current) return;
        setApplyStatus('');
        if (!tabs) return;
        const tab = tabs[activeTab];
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
    }, [tabs, activeTab, session, values]);

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
        // A search is the innermost state: the first Escape clears it and keeps
        // every unsaved change; the next one leaves.
        if (page === 'settings' && search) { setSearch(''); return; }
        // Script settings is a standalone surface, even on servers that enable
        // the optional quick menu. Escape discards and returns to gameplay.
        const top = pause?.quickMenu === true ? 'home' : 'settings';
        if (page === 'settings') { void handleCancel(); return; }
        if (page !== top) setPage(top);
        else void handleCancel();
    }, [page, pause, submitting, handleCancel, search]);

    useModalFocus(open, dialogRef, handleBack, session);

    if (!open || !tabs || tabs.length === 0) return null;

    const tab = tabs[activeTab] || tabs[0];
    const fields = tab.fields || [];
    const query = search.trim().toLowerCase();
    const baselineOf = item => savedValues[item.id] || item.values || {};
    const isDirty = (item, key) => Object.prototype.hasOwnProperty.call(values[item.id] || {}, key)
        && !Object.is(values[item.id][key], baselineOf(item)[key]);
    const isRelevant = (field, sourceTab) => Object.entries(field.showWhen || {}).every(([key, expected]) =>
        Object.is((values[sourceTab.id] || sourceTab.values || {})[key], expected));
    const visibleFields = page === 'settings' ? fields.filter(field =>
        isRelevant(field, tab) && (query || showAdvanced || !field.advanced)) : [];
    const sections = [...new Set(visibleFields.map(field => field.section || 'General'))];
    const activeSection = sections.includes(section) ? section : '';
    const hasAdvanced = page === 'settings' && fields.some(field => field.advanced && isRelevant(field, tab));
    const dirtyCount = tabs.reduce((total, item) => total + Object.keys(values[item.id] || {}).filter(key =>
        !Object.is(values[item.id][key], (savedValues[item.id] || item.values)?.[key])).length, 0);
    const sectionDirty = name => visibleFields.some(field => (field.section || 'General') === name && isDirty(tab, field.key));

    // Search spans the same registered tabs, without creating another value store.
    const rows = [];
    let visibleCount = 0;
    for (const sourceTab of page === 'settings' ? (query ? tabs : [tab]) : []) {
        let lastSection = null;
        for (const field of sourceTab.fields || []) {
            if (!isRelevant(field, sourceTab)) continue;
            if (!query && field.advanced && !showAdvanced) continue;
            const fieldSection = field.section || 'General';
            if (query && !`${sourceTab.label} ${field.label} ${field.description} ${fieldSection}`.toLowerCase().includes(query)) continue;
            if (!query && activeSection && fieldSection !== activeSection) continue;
            visibleCount++;
            if (fieldSection !== lastSection) {
                lastSection = fieldSection;
                rows.push(React.createElement('div', {
                    key: `sec-${sourceTab.id}-${field.key}`, className: 'cortex-settings-section', role: 'heading', 'aria-level': 3
                }, query ? `${sourceTab.label} / ${fieldSection}` : fieldSection));
            }
            const sourceDefaults = sourceTab.defaults || {};
            rows.push(React.createElement(SettingsField, {
                key: `${sourceTab.id}-${field.key}`, field,
                value: values[sourceTab.id]?.[field.key], tabId: sourceTab.id,
                defaultValue: sourceDefaults[field.key],
                hasDefault: Object.prototype.hasOwnProperty.call(sourceDefaults, field.key),
                dirty: isDirty(sourceTab, field.key),
                onChange: handleChange, onAction: handleAction, onPreviewSound: handlePreviewSound
            }));
        }
    }

    const selectTab = index => {
        setActiveTab(index); setSection(''); setSearch(''); setShowAdvanced(false);
        rememberSettingsPlace({ tabId: settingsTabKey(tabs[index]), section: '', advanced: false });
    };
    const library = page === 'settings' ? settingsLibrary(tabs) : [];
    const order = library.flatMap(group => group.items);
    const handleTabKeyDown = (event, index) => {
        const at = Math.max(0, order.indexOf(index));
        let nextIndex = index;
        if (event.key === 'ArrowRight' || event.key === 'ArrowDown') nextIndex = order[(at + 1) % order.length];
        else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') nextIndex = order[(at - 1 + order.length) % order.length];
        else if (event.key === 'Home') nextIndex = order[0];
        else if (event.key === 'End') nextIndex = order[order.length - 1];
        else return;
        event.preventDefault();
        selectTab(nextIndex);
        window.requestAnimationFrame(() => dialogRef.current?.querySelector(`#cortex-settings-tab-${nextIndex}`)?.focus());
    };
    const shownCount = item => (item.fields || []).filter(field => (showAdvanced || !field.advanced) && isRelevant(field, item)).length;
    const tabButton = (i, groupIndex) => {
        const t = tabs[i];
        const tabDirty = Object.keys(values[t.id] || {}).some(key => isDirty(t, key));
        return React.createElement('button', {
            key: t && t.id != null ? String(t.id) : `tab-${i}`,
            type: 'button',
            id: `cortex-settings-tab-${i}`,
            role: 'tab',
            'aria-selected': i === activeTab,
            'aria-controls': 'cortex-settings-tabpanel',
            'aria-describedby': `cortex-settings-group-${groupIndex}`,
            tabIndex: i === activeTab ? 0 : -1,
            'data-autofocus': i === activeTab ? 'true' : undefined,
            className: `cortex-settings-tab${i === activeTab ? ' active' : ''}${tabDirty ? ' is-dirty' : ''}`,
            onClick: () => selectTab(i),
            onKeyDown: event => handleTabKeyDown(event, i)
        },
            React.createElement('span', { className: 'cortex-settings-tab-name' }, t && t.label != null ? t.label : ''),
            React.createElement('span', { className: 'cortex-settings-tab-count', 'aria-hidden': 'true' }, shownCount(t)));
    };
    const escapeKey = window.CortexKit
        ? React.createElement(window.CortexKit.Keycap, { value: 'ESC', size: 'sm' })
        : null;

    return React.createElement(window.CortexPause.Frame, {
        open, page, setPage, pause, dialogRef, session, post: nuiPost,
        onResume: handleCancel, onSave: handleSave, onApply: () => handleSave(true), onBack: handleBack, submitting, dirtyCount, error: submitError
    },
        page === 'settings' && React.createElement('fieldset', { className: 'pause-settings-body', disabled: submitting, 'aria-busy': submitting },
            React.createElement('div', { className: 'pause-settings-workspace' },
                React.createElement('aside', { className: 'cortex-settings-rail' },
                    React.createElement('label', { className: 'pause-search' },
                        React.createElement(SettingsGlyph, { kind: 'search' }),
                        React.createElement('input', { type: 'search', value: search, maxLength: 128,
                            placeholder: 'Find a setting', 'aria-label': 'Search all script settings',
                            onChange: event => setSearch(event.target.value) })),
                    React.createElement(SettingsRail, { active: activeTab, label: 'Scripts' },
                        library.flatMap((group, groupIndex) => [
                            React.createElement('div', { key: `group-${group.key}`, id: `cortex-settings-group-${groupIndex}`, className: 'cortex-settings-group', 'aria-hidden': 'true' }, group.name),
                            ...group.items.map(i => tabButton(i, groupIndex))
                        ]))
                ),
                React.createElement('div', { className: 'pause-settings-main' },
                    React.createElement('div', { className: 'cortex-settings-script-head' },
                        React.createElement('h2', { className: 'cortex-settings-script-title' }, query ? 'Search results' : tab.label),
                        React.createElement('span', { className: 'pause-search-count' }, `${visibleCount} ${query ? 'RESULT' : 'SETTING'}${visibleCount === 1 ? '' : 'S'}`)),
                    !query && (sections.length > 1 || hasAdvanced) && React.createElement('div', { className: 'cortex-settings-sectionbar' },
                        sections.length > 1 && React.createElement('nav', { className: 'cortex-settings-sections', 'aria-label': `${tab.label} sections` },
                            ['', ...sections].map(name => {
                                const count = name ? visibleFields.filter(field => (field.section || 'General') === name).length : visibleFields.length;
                                const current = activeSection === name;
                                return React.createElement('button', {
                                    key: name, type: 'button',
                                    className: `${current ? 'active' : ''}${(name ? sectionDirty(name) : dirtyCount > 0) ? ' is-dirty' : ''}`.trim(),
                                    'aria-pressed': current,
                                    onClick: () => { setSection(name); setSearch(''); rememberSettingsPlace({ tabId: settingsTabKey(tab), section: name }); }
                                },
                                    React.createElement('span', { className: 'cortex-settings-section-name' }, name || 'All'),
                                    React.createElement('span', { className: 'cortex-settings-section-count', 'aria-hidden': 'true' }, count));
                            })),
                        hasAdvanced && React.createElement('button', {
                            type: 'button', className: 'pause-advanced-toggle',
                            role: 'switch', 'aria-checked': showAdvanced,
                            'aria-controls': 'cortex-settings-tabpanel',
                            onClick: () => {
                                setShowAdvanced(current => !current); setSection('');
                                rememberSettingsPlace({ tabId: settingsTabKey(tab), section: '', advanced: !showAdvanced });
                            }
                        },
                            React.createElement('span', { className: 'pause-advanced-label' }, 'Advanced'),
                            React.createElement('span', { className: `cx-toggle${showAdvanced ? ' is-on' : ''}`, 'aria-hidden': 'true' },
                                React.createElement('span', { className: 'cx-toggle-knob' })))
                    ),
                    React.createElement('div', {
                        id: 'cortex-settings-tabpanel', className: 'cortex-settings-content', role: 'tabpanel',
                        'aria-labelledby': query ? undefined : `cortex-settings-tab-${activeTab}`,
                        'aria-label': query ? 'Search results across all scripts' : undefined
                    }, rows.length ? rows : React.createElement('div', { className: 'cortex-settings-empty' },
                        query ? 'No settings match your search.' : hasAdvanced && !showAdvanced ? 'Turn on Advanced to see these settings.' : 'This tab has no settings yet.'))
                )
            ),
            React.createElement('div', { className: 'cortex-settings-footer' },
                React.createElement('div', { className: 'cortex-settings-footer-left' },
                    React.createElement('button', { type: 'button', className: 'cortex-settings-btn reset', onClick: handleReset, disabled: submitting || Boolean(query) }, 'Reset tab'),
                    React.createElement(
                        'span',
                        {
                            className: `cortex-settings-live-note${submitError ? ' error' : ''}${!submitError && dirtyCount ? ' is-dirty' : ''}`,
                            role: 'status',
                            'aria-live': 'polite'
                        },
                        submitError || (dirtyCount ? `${dirtyCount} UNSAVED` : applyStatus)
                    )
                ),
                React.createElement('div', { className: 'cortex-settings-footer-right' },
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
