/* List menu (lib.registerMenu / lib.showMenu). A --slip column: SlipHeader with
 * a position meta, display-caps rows that flip to paper when selected, value /
 * check / progress rows, a windowed list with faded edges and a 4u rail, a
 * description area and a keycap legend. Lua owns every decision; this surface
 * renders, reports input and rolls optimistic changes back on refusal. */

// ============================================================================
// MENU COMPONENT
// ============================================================================

const menuKeyMap = {
    up: ['ArrowUp'],
    down: ['ArrowDown'],
    left: ['ArrowLeft'],
    right: ['ArrowRight'],
    first: ['Home'],
    last: ['End'],
    pageUp: ['PageUp'],
    pageDown: ['PageDown'],
    select: ['Enter'],
    toggle: [' '],
    back: ['Escape', 'Backspace']
};

// Which legend keycap a key press belongs to, so the keycap can invert.
const menuPressedHint = {
    ArrowUp: 'move', ArrowDown: 'move', Home: 'move', End: 'move', PageUp: 'move', PageDown: 'move',
    ArrowLeft: 'change', ArrowRight: 'change', ' ': 'toggle', Enter: 'select', Backspace: 'back', Escape: 'close'
};

const MENU_MAX_ROWS = 10;
const MENU_MIN_ROWS = 3;
const MENU_ROW_STRIDE_U = 46; // 44u row + 2u gap; mirrors --cx-menu-stride in menu.css
const MENU_CHROME_U = 250;    // header, description and legend reserve
const MENU_WHEEL_STEP = 50;

function normalizeOption(option) {
    if (!isRecord(option)) option = {};
    const values = Array.isArray(option.values) ? option.values.slice(0, 64).map(value => {
        if (isRecord(value)) {
            return {
                label: boundedText(value.label, '', 160),
                description: boundedText(value.description, '', 512)
            };
        }
        return boundedText(value, '', 160);
    }) : null;
    const hasValues = Boolean(values && values.length);
    const hasCheck = typeof option.checked === 'boolean';

    const defaultIndex = Number.isInteger(option.defaultIndex) ? option.defaultIndex : 1;
    const scrollIndex = hasValues ? Math.max(1, Math.min(defaultIndex, values.length)) : 1;

    return {
        label: boundedText(option.label, '', 160),
        description: boundedText(option.description, '', 1024),
        icon: boundedText(option.icon, '', 128) || null,
        iconColor: normalizeIconColor(option.iconColor),
        progress: Number.isFinite(option.progress) ? Math.max(0, Math.min(100, option.progress)) : null,
        values,
        hasValues,
        checked: hasCheck ? option.checked : null,
        hasCheck,
        disabled: option.disabled === true,
        scrollIndex
    };
}

function getValueLabel(value) {
    if (typeof value === 'string') return value;
    if (value && typeof value === 'object') return value.label || '';
    return '';
}

function getValueDescription(value) {
    if (value && typeof value === 'object') return value.description || '';
    return '';
}

function getOptionTooltip(option) {
    if (!option) return '';
    const value = option.hasValues ? option.values[(option.scrollIndex || 1) - 1] : null;
    return getValueDescription(value) || option.description || '';
}

/** Next enabled row from `from` (1-based) moving `direction`; wraps when asked. */
function findMenuRow(options, from, direction, wrap) {
    const count = options.length;
    if (!count) return 0;
    let index = from;
    for (let step = 0; step < count; step += 1) {
        index += direction;
        if (index < 1 || index > count) {
            if (!wrap) return 0;
            index = index < 1 ? count : 1;
        }
        if (!options[index - 1]?.disabled) return index;
    }
    return 0;
}

/** Rows that fit between the safe zone edges once header, description and legend are reserved. */
function getMenuRowBudget(scale) {
    const width = window.innerWidth || 1920;
    const height = window.innerHeight || 1080;
    const unit = Math.max(0.72, Math.min(width, height) / 1080) * (Number.isFinite(scale) ? scale : 1);
    const safeValue = parseFloat(window.getComputedStyle(document.documentElement).getPropertyValue('--cx-safe'));
    const safe = Number.isFinite(safeValue) ? safeValue : 56 * unit;
    const fit = Math.floor((height - safe * 2 - MENU_CHROME_U * unit) / (MENU_ROW_STRIDE_U * unit));
    return Math.max(MENU_MIN_ROWS, Math.min(MENU_MAX_ROWS, fit));
}

/** Keeps one row of lookahead above and below the selection, GTA style. */
function getMenuWindowStart(previous, selectedIndex, count, rows) {
    if (count <= rows) return 0;
    const index = Math.max(0, selectedIndex - 1);
    const lookahead = rows >= 5 ? 1 : 0;
    let start = Math.max(0, Math.min(previous, count - rows));
    if (index < start + lookahead) start = index - lookahead;
    if (index > start + rows - 1 - lookahead) start = index - rows + 1 + lookahead;
    return Math.max(0, Math.min(start, count - rows));
}

// ----------------------------------------------------------------------------
// Icons. One stroked family in a 20-unit box (2.6 stroke), so consumer icon
// names read as Cortex glyphs; emoji collapse to a single-colour silhouette.
// ----------------------------------------------------------------------------
const MENU_ICON_PATHS = {
    check: 'M4 10.5 8 14.5 16 5.5',
    xmark: 'M5 5 15 15M15 5 5 15',
    plus: 'M10 4v12M4 10h12',
    minus: 'M4 10h12',
    'chevron-right': 'M7.5 4l6 6-6 6',
    'chevron-left': 'M12.5 4l-6 6 6 6',
    sliders: 'M3 6h7M15 6h2M3 14h2M9.5 14h7.5M12.5 3.8v4.4M7 11.8v4.4',
    user: 'M10 3.8a3.2 3.2 0 1 1 0 6.4 3.2 3.2 0 0 1 0-6.4ZM4 17c.8-3.2 3.2-5 6-5s5.2 1.8 6 5',
    car: 'M3.5 14.5V10l2-4.5h9l2 4.5v4.5ZM3.5 10h13M6.5 12.5v4M13.5 12.5v4',
    wrench: 'M12.6 3.4a4 4 0 0 0-3.9 5.2L3.4 13.9l2.7 2.7 5.3-5.3a4 4 0 0 0 5.2-3.9l-2.5 2.2-2.6-.6-.6-2.6Z',
    key: 'M7 6.5a3.5 3.5 0 1 1 0 7 3.5 3.5 0 0 1 0-7ZM10.5 10H17M14.5 10v3M17 10v2.5',
    lock: 'M4.5 9h11v8h-11ZM7 9V6.5a3 3 0 0 1 6 0V9',
    unlock: 'M4.5 9h11v8h-11ZM7 9V6.5a3 3 0 0 1 5.8-1.1',
    pin: 'M10 17.5s5.5-5 5.5-9.5a5.5 5.5 0 0 0-11 0c0 4.5 5.5 9.5 5.5 9.5ZM10 6.4a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2Z',
    bolt: 'M11 2.5 4.5 11H10l-1 6.5L15.5 9H10Z',
    box: 'M3.5 6.5 10 3.5l6.5 3v7.5L10 17l-6.5-3ZM3.5 6.5 10 9.5l6.5-3M10 9.5V17',
    heart: 'M10 16.5S3.5 12.5 3.5 8a3.2 3.2 0 0 1 6.5-1.2A3.2 3.2 0 0 1 16.5 8c0 4.5-6.5 8.5-6.5 8.5Z',
    shield: 'M10 3 16 5.5v4c0 3.8-2.6 6.3-6 7.5-3.4-1.2-6-3.7-6-7.5v-4Z',
    star: 'M10 3l2.1 4.4 4.8.6-3.5 3.3.9 4.7L10 13.7 5.7 16l.9-4.7L3.1 8l4.8-.6Z',
    trash: 'M4 6h12M8 6V4h4v2M5.5 6l.8 10.5h7.4L14.5 6',
    pen: 'M4 16l1-4 8-8 3 3-8 8ZM11.5 5.5l3 3',
    house: 'M3.5 9.5 10 4l6.5 5.5M5.5 8v8.5h9V8',
    phone: 'M6 2.5h8v15H6ZM9 14.5h2',
    money: 'M2.5 5.5h15v9h-15ZM10 8a2 2 0 1 1 0 4 2 2 0 0 1 0-4Z',
    clock: 'M10 3.5a6.5 6.5 0 1 1 0 13 6.5 6.5 0 0 1 0-13ZM10 6.5V10l2.5 2',
    bell: 'M5 14h10l-1.5-2V9a3.5 3.5 0 0 0-7 0v3ZM8.5 16.5h3',
    eye: 'M2.5 10S5.5 4.5 10 4.5 17.5 10 17.5 10 14.5 15.5 10 15.5 2.5 10 2.5 10ZM10 7.8a2.2 2.2 0 1 1 0 4.4 2.2 2.2 0 0 1 0-4.4Z',
    info: 'M10 3a7 7 0 1 1 0 14 7 7 0 0 1 0-14ZM10 9v5M10 6.3v.1',
    warning: 'M10 3.5 17 16H3ZM10 8.5v3.5M10 14.2v.1',
    list: 'M4 6h12M4 10h12M4 14h12',
    search: 'M9 4a5 5 0 1 1 0 10A5 5 0 0 1 9 4ZM12.6 12.6 17 17',
    flag: 'M5 17V3.5M5 4h9.5l-2 3 2 3H5',
    volume: 'M3.5 8v4h3l4 3.5v-11l-4 3.5ZM13.5 7.5a3.5 3.5 0 0 1 0 5',
    camera: 'M3 6.5h14v9.5H3ZM10 8.5a2.7 2.7 0 1 1 0 5.4 2.7 2.7 0 0 1 0-5.4ZM7 6.5l1.2-2h3.6l1.2 2',
    door: 'M5 3h10v14H5ZM12 10h.1',
    fuel: 'M4 17V3.5h7V17M4 8h7M11 7.5l3 2v5.5a1.2 1.2 0 0 0 2.4 0V8.5l-2-2',
    'arrow-right': 'M4 10h11M11 5.5l4.5 4.5-4.5 4.5',
    'arrow-left': 'M16 10H5M9 5.5 4.5 10 9 14.5'
};

const MENU_ICON_ALIASES = {
    'circle-check': 'check', 'square-check': 'check', tick: 'check',
    x: 'xmark', close: 'xmark', times: 'xmark', 'circle-xmark': 'xmark', ban: 'xmark',
    add: 'plus', 'circle-plus': 'plus', remove: 'minus', 'circle-minus': 'minus',
    'angle-right': 'chevron-right', next: 'chevron-right', 'angle-left': 'chevron-left', back: 'arrow-left',
    gear: 'sliders', gears: 'sliders', cog: 'sliders', settings: 'sliders', 'sliders-h': 'sliders',
    person: 'user', 'user-large': 'user', 'id-card': 'user', 'id-badge': 'user', player: 'user', users: 'user',
    'car-side': 'car', vehicle: 'car', 'car-rear': 'car', truck: 'car', garage: 'car',
    'screwdriver-wrench': 'wrench', tools: 'wrench', repair: 'wrench', hammer: 'wrench', toolbox: 'wrench',
    'lock-open': 'unlock', 'map-pin': 'pin', 'location-dot': 'pin', location: 'pin', marker: 'pin',
    'map-marker': 'pin', 'map-location': 'pin', 'map-location-dot': 'pin', map: 'pin', gps: 'pin',
    zap: 'bolt', power: 'bolt', energy: 'bolt', 'box-open': 'box', package: 'box', inventory: 'box',
    boxes: 'box', 'boxes-stacked': 'box', health: 'heart', 'heart-pulse': 'heart', medkit: 'heart',
    'kit-medical': 'heart', armor: 'shield', armour: 'shield', 'shield-halved': 'shield', police: 'shield',
    'user-shield': 'shield', favorite: 'star', favourite: 'star', 'trash-can': 'trash', delete: 'trash',
    pencil: 'pen', edit: 'pen', 'pen-to-square': 'pen', home: 'house', 'house-chimney': 'house',
    mobile: 'phone', 'mobile-screen': 'phone', dollar: 'money', 'dollar-sign': 'money', cash: 'money',
    wallet: 'money', 'money-bill': 'money', 'money-bill-wave': 'money', 'credit-card': 'money', bank: 'money',
    time: 'clock', stopwatch: 'clock', hourglass: 'clock', notification: 'bell', view: 'eye',
    'circle-info': 'info', help: 'info', 'circle-question': 'info', question: 'info',
    'triangle-exclamation': 'warning', alert: 'warning', exclamation: 'warning', 'circle-exclamation': 'warning',
    bars: 'list', menu: 'list', 'list-ul': 'list', 'magnifying-glass': 'search', 'flag-checkered': 'flag',
    music: 'volume', radio: 'volume', 'volume-high': 'volume', sound: 'volume', 'camera-retro': 'camera',
    'door-open': 'door', 'door-closed': 'door', 'gas-pump': 'fuel', gas: 'fuel', 'arrow-right-to-bracket': 'arrow-right'
};

function resolveMenuIcon(value) {
    const raw = typeof value === 'string' ? value.trim() : '';
    if (!raw) return null;
    // Accept Font Awesome style class strings ("fa-solid fa-car", "fas fa-car").
    const name = raw.toLowerCase().split(/\s+/).filter(Boolean).pop().replace(/^fa[srlbd]?-/, '');
    const key = MENU_ICON_PATHS[name] ? name : MENU_ICON_ALIASES[name];
    if (key) return { type: 'path', d: MENU_ICON_PATHS[key] };
    if (/\p{Extended_Pictographic}/u.test(raw)) return { type: 'silhouette', text: Array.from(raw)[0] };
    const glyph = Array.from(raw);
    return { type: 'text', text: glyph.length <= 2 ? raw : glyph[0].toUpperCase() };
}

function MenuIcon({ icon }) {
    const resolved = resolveMenuIcon(icon);
    if (!resolved) return null;
    if (resolved.type === 'path') {
        return React.createElement('svg', { className: 'cortex-menu-glyph', viewBox: '0 0 20 20', focusable: 'false' },
            React.createElement('path', { d: resolved.d }));
    }
    return React.createElement('span', { className: `cortex-menu-glyph-text${resolved.type === 'silhouette' ? ' is-silhouette' : ''}` }, resolved.text);
}

/** `‹ VALUE ›`: chevrons only on the selected row, where they are also clickable. */
function MenuValue({ label, active, disabled, onStep }) {
    const chevron = (direction) => active && !disabled ? React.createElement('span', {
        className: `cortex-menu-chevron ${direction < 0 ? 'is-prev' : 'is-next'}`,
        'aria-hidden': 'true',
        onMouseDown: (event) => { event.preventDefault(); event.stopPropagation(); },
        onClick: (event) => { event.preventDefault(); event.stopPropagation(); onStep(direction); }
    }) : null;
    return React.createElement('span', { className: 'cortex-menu-value' },
        chevron(-1),
        React.createElement('span', { className: 'cortex-menu-value-label' }, label),
        chevron(1)
    );
}

/** The footer legend: kit KeyHints whose keycaps invert while their key is held. */
function MenuLegend({ items, pressed }) {
    const list = items.filter(Boolean);
    if (!list.length) return null;
    return React.createElement('div', { className: 'cx-legend cortex-menu-legend', role: 'group', 'aria-label': 'Menu controls' },
        list.map(item => React.createElement(window.CortexKit.KeyHint, {
            key: item.id,
            keys: item.keys,
            label: item.label,
            size: 'sm',
            pressed: pressed === item.id,
            disabled: item.disabled === true
        })));
}

function Menu({ open, id, session, revision, title, subtitle, position, canClose, disableInput, gameControls, options, selected, tooltip, setMenu }) {
    const bodyRef = useRef(null);
    const dialogRef = useRef(null);
    const optionsRef = useRef([]);
    const selectedRef = useRef(1);
    const windowStartRef = useRef(0);
    const wheelRef = useRef(0);
    const pointerRef = useRef({ x: -1, y: -1 });
    const pressTimerRef = useRef(null);
    const rowPressTimerRef = useRef(null);
    const prefs = window.CortexKit.usePrefs();
    const [rowBudget, setRowBudget] = useState(MENU_MAX_ROWS);
    const [pressedHint, setPressedHint] = useState(null);
    const [pressedRow, setPressedRow] = useState(0);
    const [labelOverflow, setLabelOverflow] = useState(false);

    useModalFocus(open, dialogRef, null, session);

    useEffect(() => {
        optionsRef.current = options;
        selectedRef.current = selected;
    }, [options, selected]);

    useEffect(() => {
        if (!open) return undefined;
        const update = () => setRowBudget(getMenuRowBudget(prefs.scale));
        update();
        window.addEventListener('resize', update);
        return () => window.removeEventListener('resize', update);
    }, [open, session, prefs.scale]);

    useEffect(() => () => {
        window.clearTimeout(pressTimerRef.current);
        window.clearTimeout(rowPressTimerRef.current);
    }, []);

    const flashHint = useCallback((hint) => {
        setPressedHint(hint);
        window.clearTimeout(pressTimerRef.current);
        pressTimerRef.current = window.setTimeout(() => setPressedHint(null), 140);
    }, []);

    const flashRow = useCallback((index) => {
        setPressedRow(index);
        window.clearTimeout(rowPressTimerRef.current);
        rowPressTimerRef.current = window.setTimeout(() => setPressedRow(0), 140);
    }, []);

    const setSelectedIndex = useCallback((next, secondary) => {
        const opts = optionsRef.current;
        if (!opts.length) return;

        let clamped = next;

        // Wrap-around navigation
        if (clamped < 1) clamped = opts.length;
        if (clamped > opts.length) clamped = 1;

        clamped = Math.max(1, Math.min(clamped, opts.length));
        if (clamped === selectedRef.current && secondary == null) return;

        const previousSelected = selectedRef.current;
        const previousTooltip = getOptionTooltip(opts[previousSelected - 1]);
        const opt = opts[clamped - 1];
        selectedRef.current = clamped;
        setMenu(prev => {
            const nextTooltip = getOptionTooltip(opt);
            return { ...prev, selected: clamped, tooltip: nextTooltip };
        });

        void nuiPost('cortex_menu_selected', {
            id,
            session,
            revision,
            selected: clamped,
            secondary: secondary ?? false
        }).then(response => {
            if (response?.ok === true) return;
            setMenu(prev => {
                if (prev.id !== id
                    || prev.session !== normalizeSession(session)
                    || prev.revision !== normalizeRevision(revision)
                    || prev.selected !== clamped) return prev;
                selectedRef.current = previousSelected;
                return { ...prev, selected: previousSelected, tooltip: previousTooltip };
            });
        }).catch(error => {
            uiDebugLog('menu selection response failed', error);
        });
    }, [id, revision, session, setMenu]);

    // Arrow keys and the wheel wrap; Home/End/Page keys stop at the ends.
    // Disabled rows are skipped; if nothing else is enabled the selection stays.
    const moveSelection = useCallback((direction, mode = 'step') => {
        const opts = optionsRef.current;
        if (!opts.length) return;
        const current = selectedRef.current || 1;
        let target = 0;
        if (mode === 'first') target = findMenuRow(opts, 0, 1, false);
        else if (mode === 'last') target = findMenuRow(opts, opts.length + 1, -1, false);
        else if (mode === 'page') {
            const jump = Math.max(1, rowBudget - 1);
            const landing = Math.max(1, Math.min(opts.length, current + direction * jump));
            target = opts[landing - 1]?.disabled
                ? (findMenuRow(opts, landing, direction, false) || findMenuRow(opts, landing, -direction, false))
                : landing;
        } else target = findMenuRow(opts, current, direction, true);
        if (target) setSelectedIndex(target);
    }, [rowBudget, setSelectedIndex]);

    const closeMenu = useCallback(async (keyPressed) => {
        if (!canClose) return;
        const response = await nuiPost('cortex_menu_close', { id, session, revision, keyPressed: keyPressed || null });
        if (response?.ok !== true) return;
        setMenu(prev => prev.id === id
            && prev.session === normalizeSession(session)
            && prev.revision === normalizeRevision(revision)
            ? { ...prev, open: false, id: null }
            : prev);
    }, [id, revision, session, canClose, setMenu]);

    const doSideScroll = useCallback((direction) => {
        const opts = optionsRef.current;
        const idx = selectedRef.current - 1;
        const opt = opts[idx];
        if (!opt || !opt.hasValues || opt.disabled) return;

        const currentIndex = opt.scrollIndex || 1;
        const nextIndex = ((currentIndex - 1 + direction + opt.values.length) % opt.values.length) + 1;

        const nextOption = { ...opt, scrollIndex: nextIndex };
        opts[idx] = nextOption;

        const currentValue = opt.values[nextIndex - 1];
        const valueDescription = getValueDescription(currentValue);

        setMenu(prev => ({
            ...prev,
            options: opts.slice(0),
            tooltip: valueDescription || opt.description || ''
        }));

        void nuiPost('cortex_menu_sideScroll', {
            id,
            session,
            revision,
            selected: idx + 1,
            scrollIndex: nextIndex
        }).then(response => {
            if (response?.ok === true) return;
            setMenu(prev => {
                const currentOption = prev.options[idx];
                if (prev.id !== id
                    || prev.session !== normalizeSession(session)
                    || prev.revision !== normalizeRevision(revision)
                    || currentOption?.scrollIndex !== nextIndex) return prev;
                const rollbackOptions = prev.options.slice(0);
                rollbackOptions[idx] = opt;
                optionsRef.current = rollbackOptions;
                return {
                    ...prev,
                    options: rollbackOptions,
                    tooltip: getValueDescription(opt.values[currentIndex - 1]) || opt.description || ''
                };
            });
        }).catch(error => {
            uiDebugLog('menu side scroll response failed', error);
        });
    }, [id, revision, session, setMenu]);

    const toggleCheck = useCallback(() => {
        const opts = optionsRef.current;
        const idx = selectedRef.current - 1;
        const opt = opts[idx];
        if (!opt || !opt.hasCheck || opt.disabled) return;

        const nextChecked = !opt.checked;
        const nextOption = { ...opt, checked: nextChecked };
        opts[idx] = nextOption;
        flashRow(idx + 1);

        setMenu(prev => ({ ...prev, options: opts.slice(0) }));

        void nuiPost('cortex_menu_check', {
            id,
            session,
            revision,
            selected: idx + 1,
            checked: nextChecked
        }).then(response => {
            if (response?.ok === true) return;
            setMenu(prev => {
                const currentOption = prev.options[idx];
                if (prev.id !== id
                    || prev.session !== normalizeSession(session)
                    || prev.revision !== normalizeRevision(revision)
                    || currentOption?.checked !== nextChecked) return prev;
                const rollbackOptions = prev.options.slice(0);
                rollbackOptions[idx] = opt;
                optionsRef.current = rollbackOptions;
                return { ...prev, options: rollbackOptions };
            });
        }).catch(error => {
            uiDebugLog('menu check response failed', error);
        });
    }, [id, revision, session, setMenu, flashRow]);

    const submit = useCallback(async (selectedOverride) => {
        const opts = optionsRef.current;
        const selectedIndex = Number.isInteger(selectedOverride) ? selectedOverride : selectedRef.current;
        const idx = selectedIndex - 1;
        const opt = opts[idx];
        if (!opt || opt.disabled) return;
        flashRow(idx + 1);

        const res = await nuiPost('cortex_menu_submit', {
            id,
            session,
            revision,
            selected: idx + 1,
            scrollIndex: opt.scrollIndex || 1
        });

        if (res && res.close) {
            setMenu(prev => prev.id === id
                && prev.session === normalizeSession(session)
                && prev.revision === normalizeRevision(revision)
                ? { ...prev, open: false, id: null }
                : prev);
        }
    }, [id, revision, session, setMenu, flashRow]);

    useEffect(() => {
        if (!open) return undefined;
        const handleKeyDown = (e) => {
            const key = e.key;
            if (menuPressedHint[key]) setPressedHint(menuPressedHint[key]);

            if (menuKeyMap.up.includes(key)) { e.preventDefault(); moveSelection(-1); return; }
            if (menuKeyMap.down.includes(key)) { e.preventDefault(); moveSelection(1); return; }
            if (menuKeyMap.first.includes(key)) { e.preventDefault(); moveSelection(1, 'first'); return; }
            if (menuKeyMap.last.includes(key)) { e.preventDefault(); moveSelection(-1, 'last'); return; }
            if (menuKeyMap.pageUp.includes(key)) { e.preventDefault(); moveSelection(-1, 'page'); return; }
            if (menuKeyMap.pageDown.includes(key)) { e.preventDefault(); moveSelection(1, 'page'); return; }
            if (menuKeyMap.left.includes(key)) { e.preventDefault(); doSideScroll(-1); return; }
            if (menuKeyMap.right.includes(key)) { e.preventDefault(); doSideScroll(1); return; }

            if (menuKeyMap.select.includes(key)) {
                e.preventDefault();
                if (!e.repeat) submit();
                return;
            }

            if (menuKeyMap.toggle.includes(key)) {
                e.preventDefault();
                if (!e.repeat) toggleCheck();
                return;
            }

            if (menuKeyMap.back.includes(key)) {
                e.preventDefault();
                if (!e.repeat) closeMenu(key);
            }
        };
        const handleKeyUp = (e) => {
            if (menuPressedHint[e.key]) setPressedHint(prev => prev === menuPressedHint[e.key] ? null : prev);
        };
        const releaseAll = () => setPressedHint(null);

        window.addEventListener('keydown', handleKeyDown, { passive: false });
        window.addEventListener('keyup', handleKeyUp);
        window.addEventListener('blur', releaseAll);
        return () => {
            window.removeEventListener('keydown', handleKeyDown);
            window.removeEventListener('keyup', handleKeyUp);
            window.removeEventListener('blur', releaseAll);
        };
    }, [open, moveSelection, doSideScroll, submit, toggleCheck, closeMenu]);

    // Game-control menus have no NUI focus: Lua forwards wheel, clicks, arrows
    // and pad input as `menuNav`, scoped to the session that opened the menu.
    useEffect(() => {
        if (!open || !gameControls) return undefined;
        const handleNav = (event) => {
            const detail = event.detail || {};
            if (normalizeSession(detail.session) !== normalizeSession(session)) return;
            switch (detail.input) {
                case 'up': flashHint('move'); moveSelection(-1); break;
                case 'down': flashHint('move'); moveSelection(1); break;
                case 'left': flashHint('change'); doSideScroll(-1); break;
                case 'right': flashHint('change'); doSideScroll(1); break;
                case 'select': {
                    flashHint('select');
                    const option = optionsRef.current[selectedRef.current - 1];
                    if (option?.hasCheck) toggleCheck(); else submit();
                    break;
                }
                case 'back': flashHint('back'); closeMenu(detail.key === 'Escape' ? 'Escape' : 'Backspace'); break;
                default: break;
            }
        };
        window.addEventListener('cortex-menu-nav', handleNav);
        return () => window.removeEventListener('cortex-menu-nav', handleNav);
    }, [open, gameControls, session, moveSelection, doSideScroll, submit, toggleCheck, closeMenu, flashHint]);

    // Keep keyboard focus on the selected row without letting the browser scroll
    // the windowed list; the window itself moves by transform.
    useEffect(() => {
        if (!open || !bodyRef.current) return;
        const body = bodyRef.current;
        const viewport = body.querySelector('.cortex-menu-viewport');
        if (viewport && viewport.scrollTop) viewport.scrollTop = 0;
        const active = body.querySelector('.cortex-menu-option.active');
        if (active && document.activeElement !== active) active.focus({ preventScroll: true });
    }, [id, open, options.length, selected, session]);

    // A long label is ellipsized in its row; the description area then repeats it in full.
    React.useLayoutEffect(() => {
        if (!open || !bodyRef.current) return;
        const label = bodyRef.current.querySelector('.cortex-menu-option.active .cortex-menu-option-label');
        const overflowing = Boolean(label && label.scrollWidth > label.clientWidth + 1);
        setLabelOverflow(prev => prev === overflowing ? prev : overflowing);
    }, [open, selected, options, rowBudget]);

    if (!open) return null;

    const count = options.length;
    const rows = Math.max(1, Math.min(count, rowBudget));
    const windowStart = getMenuWindowStart(windowStartRef.current, selected, count, rows);
    windowStartRef.current = windowStart;
    const windowEnd = windowStart + rows;
    const scrollable = count > rows;
    const current = selected >= 1 && selected <= count ? options[selected - 1] : null;
    const hasIcons = options.some(option => Boolean(option.icon));
    const currentDisabled = Boolean(current?.disabled);

    // The legend is stable for a menu: hints that do not apply to the selected
    // row dim instead of disappearing, so a bottom-anchored menu never jumps.
    const anyValues = options.some(option => option.hasValues);
    const anyCheck = options.some(option => option.hasCheck);
    const hasDescriptions = options.some(option => option.description
        || (option.hasValues && option.values.some(value => getValueDescription(value))));
    const legend = gameControls
        ? [
            { id: 'move', keys: 'WHEEL', label: 'Move', disabled: count < 2 },
            anyValues ? { id: 'change', keys: 'LEFT RIGHT', label: 'Change', disabled: !current?.hasValues || currentDisabled } : null,
            { id: 'select', keys: 'LMB', label: current?.hasCheck ? 'Toggle' : 'Select', disabled: !current || currentDisabled },
            canClose ? { id: 'back', keys: 'RMB', label: 'Back' } : null
        ]
        : [
            { id: 'move', keys: 'ARROWS', label: 'Move', disabled: count < 2 },
            anyValues ? { id: 'change', keys: 'LEFT RIGHT', label: 'Change', disabled: !current?.hasValues || currentDisabled } : null,
            anyCheck ? { id: 'toggle', keys: 'SPACE', label: 'Toggle', disabled: !current?.hasCheck || currentDisabled } : null,
            { id: 'select', keys: 'ENTER', label: 'Select', disabled: !current || currentDisabled },
            canClose ? { id: 'back', keys: 'BKSP', label: 'Back' } : null,
            canClose ? { id: 'close', keys: 'ESC', label: 'Close' } : null
        ];

    const onWheel = (event) => {
        if (!count || event.deltaY === 0) return;
        // A mouse notch is one row however large its delta; small trackpad
        // deltas accumulate until they add up to one.
        if (event.deltaMode !== 0 || Math.abs(event.deltaY) >= MENU_WHEEL_STEP) {
            wheelRef.current = 0;
            moveSelection(Math.sign(event.deltaY));
            return;
        }
        if (Math.sign(event.deltaY) !== Math.sign(wheelRef.current)) wheelRef.current = 0;
        wheelRef.current += event.deltaMode === 0 ? event.deltaY : event.deltaY * MENU_WHEEL_STEP;
        while (Math.abs(wheelRef.current) >= MENU_WHEEL_STEP) {
            const direction = Math.sign(wheelRef.current);
            wheelRef.current -= direction * MENU_WHEEL_STEP;
            moveSelection(direction);
        }
    };

    const rootClass = `cortex-menu-root ${position || 'top-left'}${disableInput ? ' input-disabled' : ''}${gameControls ? ' game-controls' : ''}`;
    const meta = count
        ? React.createElement('span', { className: 'cortex-menu-count' },
            React.createElement('b', null, Math.max(1, selected)), ` / ${count}`)
        : null;
    const description = tooltip || '';

    return React.createElement('div', {
        className: rootClass,
        onMouseDown: (e) => {
            if (e.target === e.currentTarget) {
                closeMenu('Escape');
            }
        }
    },
        React.createElement('div', {
            key: `${session ?? 'menu'}`,
            ref: dialogRef,
            className: `cortex-menu${hasIcons ? ' has-icons' : ''}`,
            role: 'dialog',
            'aria-modal': true,
            'aria-labelledby': 'cortex-menu-title',
            onContextMenu: (e) => {
                e.preventDefault();
                closeMenu('Backspace');
            }
        },
            React.createElement('div', { className: 'cortex-menu-header' },
                React.createElement(window.CortexKit.SlipHeader, {
                    id: 'cortex-menu-title',
                    eyebrow: subtitle || null,
                    title: title || '',
                    meta
                })
            ),
            React.createElement('div', {
                className: 'cortex-menu-body',
                ref: bodyRef,
                role: 'listbox',
                'aria-label': title || 'Menu options',
                style: { '--cx-menu-rows': count ? rows : 1 },
                onWheel
            },
                count === 0 && React.createElement('div', { className: 'cortex-menu-empty', role: 'status' },
                    React.createElement('span', { className: 'cortex-menu-empty-title' }, 'Nothing here'),
                    React.createElement('span', { className: 'cortex-menu-empty-copy' }, 'No options available')
                ),
                count > 0 && React.createElement('div', { className: 'cortex-menu-viewport' }, React.createElement('div', {
                    className: 'cortex-menu-track',
                    style: { transform: `translateY(calc(${-windowStart} * var(--cx-menu-stride)))` }
                },
                    options.map((opt, i) => {
                        const optionIndex = i + 1;
                        const active = optionIndex === selected;
                        const inWindow = i >= windowStart && i < windowEnd;
                        const fadeTop = inWindow && i === windowStart && windowStart > 0;
                        const fadeBottom = inWindow && i === windowEnd - 1 && windowEnd < count;
                        const value = opt.hasValues ? opt.values[(opt.scrollIndex || 1) - 1] : null;
                        const valueLabel = value ? getValueLabel(value) : '';
                        const progress = opt.progress != null ? Math.round(opt.progress) : null;
                        const stateText = opt.hasCheck
                            ? (opt.checked ? 'on' : 'off')
                            : (opt.hasValues ? valueLabel : (progress != null ? `${progress}%` : ''));
                        const rowState = ['',
                            active ? 'active' : '',
                            opt.disabled ? 'is-disabled' : '',
                            opt.progress != null ? 'has-progress' : '',
                            !inWindow ? 'is-outside' : '',
                            fadeTop || fadeBottom ? 'is-edge' : '',
                            pressedRow === optionIndex ? 'is-pressed' : ''].filter(Boolean).map(name => ` ${name}`).join('');

                        return React.createElement('button', {
                            key: `${id || 'menu'}:${optionIndex}:${opt.label}`,
                            type: 'button',
                            className: `cortex-menu-option${rowState}`,
                            role: 'option',
                            'aria-selected': active,
                            'aria-disabled': opt.disabled || undefined,
                            'aria-label': stateText ? `${opt.label}, ${stateText}` : opt.label,
                            tabIndex: active ? 0 : -1,
                            // useModalFocus lands on the selected row, so startIndex survives opening.
                            'data-autofocus': active ? 'true' : undefined,
                            onFocus: () => { if (!opt.disabled) setSelectedIndex(optionIndex); },
                            onMouseMove: (e) => {
                                // Only real pointer movement selects; a row sliding under a
                                // resting cursor (wheel, keys) must not steal the selection.
                                const last = pointerRef.current;
                                if (last.x === e.clientX && last.y === e.clientY) return;
                                pointerRef.current = { x: e.clientX, y: e.clientY };
                                if (!opt.disabled && !active) setSelectedIndex(optionIndex);
                            },
                            onMouseDown: (e) => { e.preventDefault(); e.stopPropagation(); },
                            onClick: (e) => {
                                e.preventDefault();
                                e.stopPropagation();
                                if (opt.disabled) return;
                                setSelectedIndex(optionIndex);
                                if (opt.hasCheck) toggleCheck(); else submit(optionIndex);
                            }
                        },
                            hasIcons ? React.createElement('span', {
                                className: 'cortex-menu-option-icon',
                                style: opt.iconColor ? { '--cortex-menu-icon-color': opt.iconColor } : undefined,
                                'aria-hidden': 'true'
                            }, React.createElement(MenuIcon, { icon: opt.icon })) : null,
                            React.createElement('span', { className: 'cortex-menu-option-main' },
                                React.createElement('span', { className: 'cortex-menu-option-line' },
                                    React.createElement('span', { className: 'cortex-menu-option-label' }, opt.label),
                                    opt.hasValues ? React.createElement(MenuValue, {
                                        label: valueLabel,
                                        active,
                                        disabled: opt.disabled,
                                        onStep: doSideScroll
                                    }) : null,
                                    opt.hasCheck ? React.createElement(window.CortexKit.CheckMark, { checked: opt.checked }) : null,
                                    !opt.hasValues && !opt.hasCheck && progress != null
                                        ? React.createElement('span', { className: 'cortex-menu-option-percent' }, `${progress}%`)
                                        : null
                                ),
                                opt.progress != null ? React.createElement(window.CortexKit.Meter, {
                                    value: opt.progress / 100,
                                    size: 'sm',
                                    className: 'cortex-menu-option-meter'
                                }) : null
                            )
                        );
                    })
                )),
                scrollable ? React.createElement('span', {
                    className: 'cortex-menu-rail',
                    'aria-hidden': 'true',
                    style: { '--cx-rail-size': rows / count, '--cx-rail-offset': windowStart / rows }
                }, React.createElement('i', null)) : null
            ),
            description || labelOverflow || hasDescriptions ? React.createElement('div', {
                className: `cortex-menu-description${hasDescriptions ? ' is-reserved' : ''}`,
                'aria-live': 'polite'
            },
                labelOverflow && current ? React.createElement('span', { className: 'cortex-menu-description-title' }, current.label) : null,
                description ? React.createElement('span', { className: 'cortex-menu-tooltip' }, description) : null
            ) : null,
            React.createElement('div', { className: 'cortex-menu-footer' },
                React.createElement(MenuLegend, { items: legend, pressed: pressedHint })
            )
        )
    );
}
