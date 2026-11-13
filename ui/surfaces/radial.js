const RADIAL_MAX_ITEMS = NUI_MAX_MENU_OPTIONS;
const RADIAL_MAX_TRAIL = 8;
const RADIAL_CONFIRM_TEXT = 'Press again to confirm.';
const RADIAL_CONFIRM_MS = 3000;
const isRadialSpacer = item => Boolean(item && item.disabled && !String(item.label || '').trim() && !item.icon);

function normalizeRadialBadge(value) {
    if (Number.isInteger(value) && value >= 0) return value > 999 ? '999+' : String(value);
    return typeof value === 'string' ? value.slice(0, 8).trim() : '';
}

function normalizeRadialConfirm(value) {
    if (value === true) return RADIAL_CONFIRM_TEXT;
    return typeof value === 'string' ? value.slice(0, 128).trim() : '';
}

function normalizeRadialItems(items) {
    if (!Array.isArray(items)) return [];
    return items.slice(0, NUI_MAX_MENU_OPTIONS).map((item, index) => {
        if (!isRecord(item)) return null;
        const id = boundedText(item.id, `item-${index + 1}`, 96);
        return {
            id,
            label: boundedText(item.label, '', 160) || id,
            icon: boundedText(item.icon, '', 64).trim(),
            iconColor: normalizeIconColor(item.iconColor),
            description: boundedText(item.description, '', 256).trim(),
            disabled: item.disabled === true,
            hasMenu: (typeof item.menu === 'string' && item.menu !== '') || item.hasMenu === true,
            badge: normalizeRadialBadge(item.badge),
            confirm: normalizeRadialConfirm(item.confirm)
        };
    }).filter(Boolean);
}

function normalizeRadialTitle(value) {
    return typeof value === 'string' ? value.slice(0, 64).trim() : '';
}

function normalizeRadialTrail(value) {
    if (!Array.isArray(value)) return [];
    return value.slice(-RADIAL_MAX_TRAIL)
        .map(entry => boundedText(entry, '', 64).trim())
        .filter(Boolean);
}

function normalizeRadialFocusIndex(value) {
    return Number.isInteger(value) && value >= 0 && value < RADIAL_MAX_ITEMS ? value : null;
}

const RADIAL_PAGE_ITEMS = 8;
const RADIAL_SIZE = 460;
const RADIAL_CENTER = RADIAL_SIZE / 2;
const RADIAL_OUTER_RADIUS = 200;
const RADIAL_INNER_RADIUS = 126;
const RADIAL_HUB_RADIUS = 114;
const RADIAL_LABEL_RADIUS = 163;
const RADIAL_ARC_RADIUS = 212;
const RADIAL_GAP = 8;
const RADIAL_CORNER = 3;
const RADIAL_PUSH = 4;
const RADIAL_DEAD_ZONE = 48;
const RADIAL_HYSTERESIS = 6;
const RADIAL_WHEEL_COOLDOWN_MS = 180;
const RADIAL_EXIT_MS = 170;
const RADIAL_KEY_REARM_PX = 8;
const RADIAL_PETAL_SWEEP = 104;
const RADIAL_PAD_DEAD = 0.42;

const RADIAL_FAN_ROW_GAP = 58;
const RADIAL_FAN_SPREAD = 12;
const RADIAL_FAN_HUB = 26;
const RADIAL_FAN_HYSTERESIS = 3;

const radialMemory = new Map();

function rememberRadialPage(key, page) {
    radialMemory.delete(key);
    radialMemory.set(key, page);
    if (radialMemory.size > 32) radialMemory.delete(radialMemory.keys().next().value);
}

const radialSlotOffset = slotCount => slotCount === 2 ? 270 : 0;
const radialSlotAngle = (index, slotCount) => (radialSlotOffset(slotCount) + index * 360 / Math.max(1, slotCount)) % 360;

function radialPoint(radius, angle) {
    const radians = (angle - 90) * Math.PI / 180;
    return {
        x: RADIAL_CENTER + radius * Math.cos(radians),
        y: RADIAL_CENTER + radius * Math.sin(radians)
    };
}

const radialFixed = value => Math.round(value * 100) / 100;
const radialPad = (radius, gap) => Math.asin(Math.min(1, (gap / 2) / radius)) * 180 / Math.PI;

function describeRadialRing(outer, inner) {
    const c = RADIAL_CENTER;
    return [
        `M ${c} ${c - outer} A ${outer} ${outer} 0 1 1 ${c} ${c + outer} A ${outer} ${outer} 0 1 1 ${c} ${c - outer} Z`,
        `M ${c} ${c - inner} A ${inner} ${inner} 0 1 0 ${c} ${c + inner} A ${inner} ${inner} 0 1 0 ${c} ${c - inner} Z`
    ].join(' ');
}

function describeRadialSlip(start, end) {
    const outer = RADIAL_OUTER_RADIUS - RADIAL_CORNER;
    const inner = RADIAL_INNER_RADIUS + RADIAL_CORNER;
    if (end - start >= 359.9) return describeRadialRing(outer, inner);
    const gap = RADIAL_GAP + RADIAL_CORNER * 2;
    const outerPad = radialPad(outer, gap);
    const innerPad = radialPad(inner, gap);
    const p1 = radialPoint(outer, start + outerPad);
    const p2 = radialPoint(outer, end - outerPad);
    const p3 = radialPoint(inner, end - innerPad);
    const p4 = radialPoint(inner, start + innerPad);
    const outerLarge = end - start - outerPad * 2 > 180 ? 1 : 0;
    const innerLarge = end - start - innerPad * 2 > 180 ? 1 : 0;
    return [
        'M', radialFixed(p1.x), radialFixed(p1.y),
        'A', outer, outer, 0, outerLarge, 1, radialFixed(p2.x), radialFixed(p2.y),
        'L', radialFixed(p3.x), radialFixed(p3.y),
        'A', inner, inner, 0, innerLarge, 0, radialFixed(p4.x), radialFixed(p4.y),
        'Z'
    ].join(' ');
}

function describeRadialArc(start, end) {
    const radius = RADIAL_ARC_RADIUS;
    if (end - start >= 359.9) {
        const c = RADIAL_CENTER;
        return `M ${c} ${c - radius} A ${radius} ${radius} 0 1 1 ${c} ${c + radius} A ${radius} ${radius} 0 1 1 ${c} ${c - radius}`;
    }
    const pad = radialPad(radius, RADIAL_GAP);
    const a = radialPoint(radius, start + pad);
    const b = radialPoint(radius, end - pad);
    const large = end - start - pad * 2 > 180 ? 1 : 0;
    return `M ${radialFixed(a.x)} ${radialFixed(a.y)} A ${radius} ${radius} 0 ${large} 1 ${radialFixed(b.x)} ${radialFixed(b.y)}`;
}

function radialDirectionIndex(angle, slotCount, current = -1) {
    const count = Math.max(1, Math.floor(slotCount) || 1);
    const step = 360 / count;
    const normalized = (((angle - radialSlotOffset(count)) % 360) + 360) % 360;
    if (count > 1 && current >= 0 && current < count) {
        const offset = Math.abs(((normalized - current * step) % 360 + 540) % 360 - 180);
        if (offset <= step / 2 + RADIAL_HYSTERESIS) return current;
    }
    return Math.floor((normalized + step / 2) / step) % count;
}

function radialFanRadius(slotCount) {
    return slotCount <= 2 ? 150 : slotCount <= 4 ? 210 : 270;
}

function radialFanRows(slotCount) {
    const count = Math.max(0, Math.floor(slotCount) || 0);
    const radius = radialFanRadius(count);
    return Array.from({ length: count }, (_, index) => {
        const y = (index - (count - 1) / 2) * RADIAL_FAN_ROW_GAP;
        const x = Math.sqrt(Math.max(0, radius * radius - y * y));
        return { x, y, angle: Math.atan2(y, x) * 180 / Math.PI };
    });
}

function radialFanIndex(dx, dy, rows, current = -1) {
    if (!rows.length) return -1;
    const angle = Math.atan2(dy, Math.abs(dx)) * 180 / Math.PI;
    const bounds = index => [
        index === 0 ? -90 : (rows[index - 1].angle + rows[index].angle) / 2,
        index === rows.length - 1 ? 90 : (rows[index].angle + rows[index + 1].angle) / 2
    ];
    if (current >= 0 && current < rows.length) {
        const [low, high] = bounds(current);
        if (angle >= low - RADIAL_FAN_HYSTERESIS && angle <= high + RADIAL_FAN_HYSTERESIS) return current;
    }
    for (let index = 0; index < rows.length; index += 1) {
        const [low, high] = bounds(index);
        if (angle >= low && angle <= high) return index;
    }
    return rows.length - 1;
}

function getRadialPointer(clientX, clientY, element, slotCount, current = -1, style = 'wheel') {
    if (!element || !(slotCount > 0)) return { type: 'center', index: -1 };
    const rect = element.getBoundingClientRect();
    const scale = rect.width / RADIAL_SIZE;
    if (!Number.isFinite(scale) || scale <= 0) return { type: 'center', index: -1 };
    const dx = (clientX - (rect.left + rect.width / 2)) / scale;
    const dy = (clientY - (rect.top + rect.height / 2)) / scale;
    if (Math.hypot(dx, dy) < RADIAL_DEAD_ZONE) return { type: 'center', index: -1 };
    if (style === 'fan') return { type: 'item', index: radialFanIndex(dx, dy, radialFanRows(slotCount), current) };
    const angle = Math.atan2(dx, -dy) * 180 / Math.PI;
    return { type: 'item', index: radialDirectionIndex(angle, slotCount, current) };
}

function radialKeyIndex(held, slotCount, itemCount) {
    const x = (held.has('ArrowRight') ? 1 : 0) - (held.has('ArrowLeft') ? 1 : 0);
    const y = (held.has('ArrowDown') ? 1 : 0) - (held.has('ArrowUp') ? 1 : 0);
    if ((x === 0 && y === 0) || itemCount <= 0) return -1;
    const angle = ((Math.atan2(x, -y) * 180 / Math.PI) + 360) % 360;
    let best = 0;
    let bestOffset = Infinity;
    for (let index = 0; index < Math.min(itemCount, slotCount); index += 1) {
        const offset = Math.abs(((angle - radialSlotAngle(index, slotCount)) % 360 + 540) % 360 - 180);
        if (offset < bestOffset - 0.001) { best = index; bestOffset = offset; }
    }
    return best;
}

function radialStepIndex(items, current, direction) {
    const count = items.length;
    if (count === 0) return -1;
    let next = current;
    for (let step = 0; step < count; step += 1) {
        next = next < 0 ? (direction > 0 ? 0 : count - 1) : (next + direction + count) % count;
        if (!items[next].disabled) return next;
    }
    return next;
}

function resolveRadialIcon(value) {
    const raw = typeof value === 'string' ? value.trim() : '';
    if (!raw) return null;
    if (typeof resolveMenuIcon === 'function') {
        const resolved = resolveMenuIcon(raw);
        return resolved && resolved.type === 'text' && Array.from(raw).length > 2 ? null : resolved;
    }
    const glyphs = Array.from(raw);
    if (/\p{Extended_Pictographic}/u.test(raw)) return { type: 'silhouette', text: glyphs[0] };
    return glyphs.length <= 2 ? { type: 'text', text: raw } : null;
}

function RadialIcon({ icon }) {
    const resolved = resolveRadialIcon(icon);
    if (!resolved) return null;
    if (resolved.type === 'path') {
        return React.createElement('svg', { className: 'cortex-radial-icon', viewBox: '0 0 20 20', focusable: 'false', 'aria-hidden': 'true' },
            React.createElement('path', { d: resolved.d }));
    }
    return React.createElement('span', {
        className: `cortex-radial-glyph${resolved.type === 'silhouette' ? ' is-silhouette' : ''}`,
        'aria-hidden': 'true'
    }, resolved.text);
}

function RadialChevron({ angle = 90, distance = 0 }) {
    return React.createElement('svg', {
        className: 'cortex-radial-chevron', viewBox: '0 0 12 12', focusable: 'false', 'aria-hidden': 'true',
        style: { transform: `rotate(${radialFixed(angle)}deg) translateY(calc(${-distance} * var(--ru)))` }
    }, React.createElement('path', { d: 'M2.5 8 6 4.5 9.5 8' }));
}

const radialLabelSize = label => label.length > 26 ? ' is-longer' : label.length > 12 ? ' is-long' : '';

function RadialMenu({ open, id, session, items, canGoBack, visible, appearance, trail, focusIndex, view, releaseSelect, title }) {
    const Kit = window.CortexKit;
    const h = React.createElement;
    const [hoverIndex, setHoverIndex] = useState(-1);
    const [page, setPage] = useState(1);
    const [mounted, setMounted] = useState(Boolean(open));
    const [pressed, setPressed] = useState(null);
    const [fired, setFired] = useState(-1);
    const [pageMotion, setPageMotion] = useState(0);
    const [armed, setArmed] = useState(-1);
    const radialSvgRef = useRef(null);
    const pointerRef = useRef(null);
    const keyAnchorRef = useRef(null);
    const inputModeRef = useRef('pointer');
    const heldKeysRef = useRef(new Set());
    const pendingRef = useRef(false);
    const wheelAtRef = useRef(0);
    const firedTimerRef = useRef(0);
    const armedTimerRef = useRef(0);
    const holdRef = useRef(false);
    const sawHeldRef = useRef(false);
    const releasedRef = useRef(false);

    const prefs = typeof Kit?.usePrefs === 'function' ? Kit.usePrefs() : null;
    const isVisible = Boolean(open) && visible !== false;
    const allItems = Array.isArray(items) ? items : [];
    const itemCount = allItems.length;
    const totalPages = Math.max(1, Math.ceil(itemCount / RADIAL_PAGE_ITEMS));
    const currentPage = Math.min(Math.max(1, page), totalPages);
    const pageStartIndex = (currentPage - 1) * RADIAL_PAGE_ITEMS;
    const displayItems = allItems.slice(pageStartIndex, pageStartIndex + RADIAL_PAGE_ITEMS);
    const slotCount = totalPages > 1 ? RADIAL_PAGE_ITEMS : Math.max(1, displayItems.length);
    const hovered = hoverIndex >= 0 && hoverIndex < displayItems.length && !isRadialSpacer(displayItems[hoverIndex]) ? hoverIndex : -1;
    const hoveredItem = hovered >= 0 ? displayItems[hovered] : null;
    const compactControl = appearance === 'compact-control';
    const empty = itemCount === 0;
    const menuStyle = !compactControl && !empty && prefs?.radialStyle === 'fan' ? 'fan' : 'wheel';
    const memoryKey = id || '__root__';
    const crumbs = Array.isArray(trail) ? trail : [];
    const menuTitle = title || (crumbs.length ? crumbs[crumbs.length - 1] : '');
    const armedLocal = armed >= pageStartIndex && armed < pageStartIndex + displayItems.length ? armed - pageStartIndex : -1;

    useEffect(() => {
        if (open) { setMounted(true); return undefined; }
        const timer = window.setTimeout(() => setMounted(false), RADIAL_EXIT_MS);
        return () => window.clearTimeout(timer);
    }, [open]);

    useEffect(() => {
        if (!open) return;
        pendingRef.current = false;
        heldKeysRef.current.clear();
        setPressed(null);
        setPageMotion(0);
        setArmed(-1);
        const pages = Math.max(1, Math.ceil(allItems.length / RADIAL_PAGE_ITEMS));
        if (focusIndex !== null && focusIndex !== undefined && focusIndex < allItems.length) {
            setPage(Math.floor(focusIndex / RADIAL_PAGE_ITEMS) + 1);
            setHoverIndex(focusIndex % RADIAL_PAGE_ITEMS);
            inputModeRef.current = 'keys';
            keyAnchorRef.current = pointerRef.current;
        } else {
            setPage(Math.min(radialMemory.get(memoryKey) || 1, pages));
            setHoverIndex(-1);
            inputModeRef.current = 'pointer';
        }
    }, [open, view, session, id]);

    useEffect(() => {
        holdRef.current = Boolean(open && releaseSelect);
        sawHeldRef.current = false;
        releasedRef.current = false;
    }, [open, view, releaseSelect]);

    useEffect(() => () => {
        window.clearTimeout(firedTimerRef.current);
        window.clearTimeout(armedTimerRef.current);
    }, []);

    useEffect(() => {
        if (armed >= 0 && armed !== pageStartIndex + hovered) setArmed(-1);
    }, [hovered, pageStartIndex]);

    useModalFocus(open && isVisible, radialSvgRef, null, `${session ?? 'none'}:${id ?? ''}:${view ?? 0}`);

    const backOrClose = useCallback(() => {
        if (!isVisible) return;
        if (canGoBack) {
            nuiPost('radialBack', { menuId: id, session });
        } else {
            nuiPost('radialClose', { menuId: id, session });
        }
    }, [canGoBack, id, isVisible, session]);

    const activateItem = useCallback((index) => {
        if (!isVisible || pendingRef.current) return;
        const item = displayItems[index];
        if (!item || item.disabled) return;

        const sourceIndex = pageStartIndex + index;
        if (sourceIndex < 0 || sourceIndex >= allItems.length) return;
        if (item.confirm && armed !== sourceIndex) {
            setArmed(sourceIndex);
            window.clearTimeout(armedTimerRef.current);
            armedTimerRef.current = window.setTimeout(() => setArmed(-1), RADIAL_CONFIRM_MS);
            return;
        }
        window.clearTimeout(armedTimerRef.current);
        setArmed(-1);
        rememberRadialPage(memoryKey, currentPage);
        setFired(sourceIndex);
        window.clearTimeout(firedTimerRef.current);
        firedTimerRef.current = window.setTimeout(() => setFired(-1), 180);
        pendingRef.current = true;
        Promise.resolve(nuiPost('radialClick', { index: sourceIndex, itemId: item.id, menuId: id, session }))
            .finally(() => { pendingRef.current = false; });
    }, [allItems.length, armed, currentPage, displayItems, id, isVisible, memoryKey, pageStartIndex, session]);

    const changePage = useCallback((delta) => {
        if (!isVisible || totalPages <= 1) return;
        const next = (((currentPage - 1 + delta) % totalPages) + totalPages) % totalPages + 1;
        const nextCount = Math.min(RADIAL_PAGE_ITEMS, allItems.length - (next - 1) * RADIAL_PAGE_ITEMS);
        setPage(next);
        setPageMotion(delta > 0 ? 1 : -1);
        rememberRadialPage(memoryKey, next);
        const pointer = pointerRef.current;
        if (inputModeRef.current === 'pointer' && pointer) {
            const hit = getRadialPointer(pointer.x, pointer.y, radialSvgRef.current, RADIAL_PAGE_ITEMS, -1, menuStyle);
            setHoverIndex(hit.type === 'item' && hit.index < nextCount ? hit.index : -1);
        } else {
            setHoverIndex(current => Math.min(current, nextCount - 1));
        }
    }, [allItems.length, currentPage, isVisible, memoryKey, menuStyle, totalPages]);

    const pointerHit = useCallback((event, current) => getRadialPointer(
        event.clientX, event.clientY, radialSvgRef.current, slotCount, current, menuStyle
    ), [slotCount, menuStyle]);

    const releaseHold = useCallback((index) => {
        holdRef.current = false;
        releasedRef.current = true;
        if (index >= 0) activateItem(index);
    }, [activateItem]);

    const handleMouseMove = useCallback((e) => {
        if (!isVisible) return;
        pointerRef.current = { x: e.clientX, y: e.clientY };
        if (holdRef.current) {
            if (e.buttons & 2) sawHeldRef.current = true;
            else if (sawHeldRef.current) { releaseHold(hovered); return; }
        }
        if (inputModeRef.current === 'keys') {
            const anchor = keyAnchorRef.current;
            if (anchor && Math.hypot(e.clientX - anchor.x, e.clientY - anchor.y) < RADIAL_KEY_REARM_PX) return;
            inputModeRef.current = 'pointer';
        }
        const hit = pointerHit(e, hovered);
        const next = hit.type === 'item' && hit.index < displayItems.length ? hit.index : -1;
        if (next !== hoverIndex) setHoverIndex(next);
    }, [displayItems.length, hoverIndex, hovered, isVisible, pointerHit, releaseHold]);

    const handleMouseDown = useCallback((e) => {
        if (e.button === 2) { holdRef.current = false; releasedRef.current = false; }
        if (!isVisible || e.button !== 0) return;
        const hit = pointerHit(e, hovered);
        setPressed(hit.type === 'center' ? 'center' : 'item');
    }, [hovered, isVisible, pointerHit]);

    const handleClick = useCallback((e) => {
        setPressed(null);
        if (!isVisible) return;
        const hit = pointerHit(e, hovered);
        if (hit.type === 'center') { backOrClose(); return; }
        if (hit.index === hovered) activateItem(hit.index);
        else if (hit.index < displayItems.length) {
            inputModeRef.current = 'pointer';
            setHoverIndex(hit.index);
        }
    }, [activateItem, backOrClose, displayItems.length, hovered, isVisible, pointerHit]);

    const handleMouseUp = useCallback((e) => {
        setPressed(null);
        if (isVisible && e.button === 2 && holdRef.current) releaseHold(hovered);
    }, [hovered, isVisible, releaseHold]);

    const handleContextMenu = useCallback((e) => {
        e.preventDefault();
        if (releasedRef.current) { releasedRef.current = false; return; }
        if (holdRef.current) { if (isVisible) releaseHold(hovered); return; }
        backOrClose();
    }, [backOrClose, hovered, isVisible, releaseHold]);

    const handleWheel = useCallback((e) => {
        if (!isVisible || totalPages <= 1 || !e.deltaY) return;
        const now = Date.now();
        if (now - wheelAtRef.current < RADIAL_WHEEL_COOLDOWN_MS) return;
        wheelAtRef.current = now;
        changePage(e.deltaY > 0 ? 1 : -1);
    }, [changePage, isVisible, totalPages]);

    useEffect(() => {
        if (!open || !isVisible) return undefined;
        const held = heldKeysRef.current;

        const selectByKeys = (index) => {
            inputModeRef.current = 'keys';
            keyAnchorRef.current = pointerRef.current;
            setHoverIndex(index);
        };

        const handleKeyDown = (e) => {
            const key = e.key;
            const code = e.code || '';
            if (key === 'Escape') {
                e.preventDefault();
                nuiPost('radialClose', { menuId: id, session });
            } else if (key === 'Backspace') {
                e.preventDefault();
                if (!e.repeat) backOrClose();
            } else if (menuStyle === 'fan' && (key === 'ArrowUp' || key === 'ArrowDown') && displayItems.length > 0) {
                e.preventDefault();
                selectByKeys(radialStepIndex(displayItems, hovered, key === 'ArrowDown' ? 1 : -1));
            } else if (menuStyle === 'fan' && key === 'ArrowRight') {
                e.preventDefault();
                if (!e.repeat && hoveredItem && hoveredItem.hasMenu) activateItem(hovered);
            } else if (menuStyle === 'fan' && key === 'ArrowLeft') {
                e.preventDefault();
                if (!e.repeat) backOrClose();
            } else if (displayItems.length > 0 && (key === 'ArrowRight' || key === 'ArrowLeft' || key === 'ArrowUp' || key === 'ArrowDown')) {
                e.preventDefault();
                held.add(key);
                const index = radialKeyIndex(held, slotCount, displayItems.length);
                if (index >= 0) selectByKeys(index);
            } else if (key === 'Tab' && displayItems.length > 0) {
                e.preventDefault();
                selectByKeys(radialStepIndex(displayItems, hovered, e.shiftKey ? -1 : 1));
            } else if ((key === 'Enter' || key === ' ') && hovered >= 0) {
                e.preventDefault();
                if (!e.repeat) activateItem(hovered);
            } else if (/^(?:Digit|Numpad)[1-8]$/.test(code) || /^[1-8]$/.test(key)) {
                const index = Number(code ? code.slice(-1) : key) - 1;
                if (index < displayItems.length) {
                    e.preventDefault();
                    selectByKeys(index);
                    if (!e.repeat) activateItem(index);
                }
            } else if (code === 'KeyQ' || key === 'q' || key === 'Q' || key === 'PageUp') {
                e.preventDefault();
                changePage(-1);
            } else if (code === 'KeyE' || key === 'e' || key === 'E' || key === 'PageDown') {
                e.preventDefault();
                changePage(1);
            }
        };
        const handleKeyUp = (e) => { held.delete(e.key); };
        const handleBlur = () => { held.clear(); setPressed(null); };

        const handlePad = (event) => {
            const message = event.data;
            if (!isRecord(message) || !isRecord(message.data)) return;
            const data = message.data;
            if (normalizeSession(data.session) !== session) return;
            if (message.action === 'radialPadAim') {
                const x = Number(data.x);
                const y = Number(data.y);
                if (!Number.isFinite(x) || !Number.isFinite(y) || Math.hypot(x, y) < RADIAL_PAD_DEAD || displayItems.length === 0) return;
                const index = menuStyle === 'fan'
                    ? radialFanIndex(x, y, radialFanRows(slotCount), hovered)
                    : radialDirectionIndex(Math.atan2(x, -y) * 180 / Math.PI, slotCount, hovered);
                if (index >= 0 && index < displayItems.length) selectByKeys(index);
            } else if (message.action === 'radialPadPress') {
                if (data.button === 'accept' && hovered >= 0) activateItem(hovered);
                else if (data.button === 'back') backOrClose();
                else if (data.button === 'next') changePage(1);
                else if (data.button === 'prev') changePage(-1);
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        window.addEventListener('keyup', handleKeyUp);
        window.addEventListener('blur', handleBlur);
        window.addEventListener('message', handlePad);
        return () => {
            window.removeEventListener('keydown', handleKeyDown);
            window.removeEventListener('keyup', handleKeyUp);
            window.removeEventListener('blur', handleBlur);
            window.removeEventListener('message', handlePad);
        };
    }, [activateItem, backOrClose, changePage, displayItems, hovered, hoveredItem, id, isVisible, open, session, slotCount, menuStyle]);

    if (!open && !mounted) return null;

    const slots = Array.from({ length: slotCount }, (_, index) => displayItems[index] || null);
    const layerKey = `${view ?? 0}:${currentPage}:${menuStyle}`;
    const backLabel = canGoBack ? 'Back' : 'Close';
    const ariaName = menuTitle || crumbs.join(' / ') || (id ? `${id.replaceAll('_', ' ')} menu` : 'Controls menu');
    const itemClasses = (item, index, base) => [base,
        index === hovered ? 'is-hover' : '',
        index === hovered && (pressed === 'item' || fired === pageStartIndex + index) ? 'is-pressed' : '',
        index === armedLocal ? 'is-armed' : '',
        item.disabled ? 'is-disabled' : ''].filter(Boolean).join(' ');
    const badgeNode = item => item.badge ? h('span', { className: 'cortex-radial-badge' }, item.badge) : null;

    const pageDots = totalPages > 1 ? h('div', { className: 'cortex-radial-pages', role: 'group', 'aria-label': `Page ${currentPage} of ${totalPages}` },
        h(Kit.Keycap, { value: 'Q', size: 'sm' }),
        h('span', { className: 'cortex-radial-dots' },
            Array.from({ length: totalPages }, (_, index) => h('i', {
                key: index,
                className: `cortex-radial-dot${index + 1 === currentPage ? ' is-current' : ''}`
            }))),
        h(Kit.Keycap, { value: 'E', size: 'sm' })
    ) : null;

    const legendFor = (withBack) => [
        empty ? null : { keys: 'LMB', label: 'Select', disabled: !hoveredItem || hoveredItem.disabled },
        withBack && !empty ? { keys: 'RMB', label: backLabel } : null,
        displayItems.length > 0 ? { keys: displayItems.length > 1 ? `1-${displayItems.length}` : '1', label: 'Pick' } : null,
        totalPages > 1 ? { keys: 'WHEEL', label: 'Page' } : null,
        canGoBack ? { keys: 'ESC', label: 'Close' } : null
    ].filter(Boolean);

    const svgProps = {
        className: `cortex-radial-svg${compactControl ? ' cortex-radial-svg--compact-control' : ''}`,
        viewBox: `0 0 ${RADIAL_SIZE} ${RADIAL_SIZE}`,
        xmlns: 'http://www.w3.org/2000/svg',
        ref: radialSvgRef,
        role: 'menu',
        tabIndex: isVisible ? 0 : -1,
        'aria-label': ariaName,
        'aria-activedescendant': hovered >= 0 ? `cortex-radial-item-${pageStartIndex + hovered}` : undefined
    };

    let body;
    if (menuStyle === 'fan') {
        const rows = radialFanRows(slotCount);
        const shift = index => hovered < 0 || index === hovered ? 0 : (index > hovered ? RADIAL_FAN_SPREAD : -RADIAL_FAN_SPREAD);
        const radius = radialFanRadius(slotCount);
        const needleAngle = hovered >= 0 ? rows[hovered].angle : 0;
        const firstIndex = slots.findIndex(item => item && !isRadialSpacer(item));
        const lastIndex = slots.reduce((last, item, index) => item && !isRadialSpacer(item) ? index : last, 0);
        const first = rows[Math.max(0, firstIndex)];
        const last = rows[lastIndex];
        const at = (x, y) => ({ left: `calc(50% + ${radialFixed(x)} * var(--ru))`, top: `calc(50% + ${radialFixed(y)} * var(--ru))` });

        const rowNodes = slots.map((item, index) => {
            if (!item || isRadialSpacer(item)) return null;
            const sourceIndex = pageStartIndex + index;
            const row = rows[index];
            const isHovered = index === hovered;
            const detail = index === armedLocal ? item.confirm : isHovered ? item.description : '';
            const rowStyle = { ...at(row.x, row.y), '--shift': shift(index), '--i': index };
            if (item.iconColor) rowStyle['--cortex-radial-icon-color'] = item.iconColor;
            const hasIcon = resolveRadialIcon(item.icon) !== null;
            return h('div', {
                key: `${sourceIndex}:${item.id}`,
                id: `cortex-radial-item-${sourceIndex}`,
                className: itemClasses(item, index, 'cortex-radial-row'),
                role: 'menuitem',
                'aria-label': item.label,
                'aria-disabled': item.disabled ? true : undefined,
                style: rowStyle
            },
                h('div', { className: 'cortex-radial-row-face' },
                    h('div', { className: 'cortex-radial-row-main' },
                        hasIcon ? h(RadialIcon, { icon: item.icon }) : null,
                        h('span', { className: 'cortex-radial-row-label' }, item.label),
                        badgeNode(item),
                        item.hasMenu ? h(RadialChevron, { angle: 90 }) : null),
                    detail ? h('div', { className: `cortex-radial-row-detail${hasIcon ? ' has-icon' : ''}` }, detail) : null)
            );
        });

        body = h('div', { className: 'cortex-radial-wheel is-fan' },
            h('svg', svgProps,
                h('circle', { className: 'cortex-radial-hub-disc', cx: RADIAL_CENTER, cy: RADIAL_CENTER, r: RADIAL_FAN_HUB }),
                h('g', {
                    className: `cortex-radial-needle${hovered >= 0 ? ' is-live' : ''}${armedLocal >= 0 && armedLocal === hovered ? ' is-armed' : ''}`,
                    style: { transform: `rotate(${radialFixed(needleAngle)}deg)` }
                }, h('line', { x1: RADIAL_CENTER + RADIAL_FAN_HUB + 4, y1: RADIAL_CENTER, x2: RADIAL_CENTER + radius - 16, y2: RADIAL_CENTER })),
                h('circle', { className: `cortex-radial-origin${hovered >= 0 ? ' is-live' : ''}`, cx: RADIAL_CENTER, cy: RADIAL_CENTER, r: 7 })
            ),
            menuTitle ? h('div', { className: 'cortex-radial-fan-title', style: at(first.x, first.y - RADIAL_FAN_ROW_GAP / 2 - RADIAL_FAN_SPREAD - (hovered >= 0 && hovered === firstIndex ? 30 : 6)) }, menuTitle) : null,
            h('div', { key: `rows:${layerKey}`, className: `cortex-radial-rows${pageMotion ? ' is-paging' : ''}` }, rowNodes),
            h('div', { className: 'cortex-radial-fan-footer', style: at(last.x, last.y + RADIAL_FAN_ROW_GAP / 2 + RADIAL_FAN_SPREAD + (hovered >= 0 && hovered === lastIndex ? 34 : 6)) },
                pageDots,
                h(Kit.ControlsLegend, { items: legendFor(true), align: 'start', className: 'cortex-radial-legend', label: 'Radial controls' })
            )
        );
    } else {
        const angleStep = 360 / slotCount;
        const sweep = slotCount <= 3 ? Math.min(angleStep, RADIAL_PETAL_SWEEP) : angleStep;
        const pushFor = (index, distance) => {
            if (slotCount === 1 && itemCount === 0) return { x: 0, y: 0 };
            const radians = radialSlotAngle(index, slotCount) * Math.PI / 180;
            return { x: radialFixed(Math.sin(radians) * distance), y: radialFixed(-Math.cos(radians) * distance) };
        };
        const labelWidth = slotCount <= 2 ? 120 : slotCount <= 4 ? 104 : slotCount <= 6 ? 92 : 78;

        const slipNodes = slots.map((item, index) => {
            const angle = radialSlotAngle(index, slotCount);
            const slotSweep = empty ? 360 : sweep;
            const start = angle - slotSweep / 2;
            const end = start + slotSweep;
            const sourceIndex = pageStartIndex + index;
            const isHovered = item !== null && index === hovered;
            const isPressed = isHovered && (pressed === 'item' || fired === sourceIndex);
            const push = isHovered ? pushFor(index, isPressed ? RADIAL_PUSH * 0.4 : RADIAL_PUSH) : { x: 0, y: 0 };
            return h('g', {
                key: item ? `${sourceIndex}:${item.id}` : `ghost:${index}`,
                id: item ? `cortex-radial-item-${sourceIndex}` : undefined,
                className: item ? itemClasses(item, index, 'cortex-radial-slip') : 'cortex-radial-slip is-ghost',
                role: item ? 'menuitem' : 'presentation',
                'aria-label': item ? item.label : undefined,
                'aria-disabled': item?.disabled ? true : undefined,
                style: { '--i': index }
            },
                h('g', {
                    className: 'cortex-radial-slip-body',
                    style: { '--push-x': `${push.x}px`, '--push-y': `${push.y}px` }
                },
                    h('path', { className: 'cortex-radial-slip-shape', d: describeRadialSlip(start, end), fillRule: 'evenodd' }),
                    item ? h('path', { className: 'cortex-radial-arc', d: describeRadialArc(start, end) }) : null
                )
            );
        });

        const labelNodes = slots.map((item, index) => {
            if (!item) return null;
            const sourceIndex = pageStartIndex + index;
            const angle = radialSlotAngle(index, slotCount);
            const point = radialPoint(RADIAL_LABEL_RADIUS, angle);
            const isHovered = index === hovered;
            const isPressed = isHovered && (pressed === 'item' || fired === sourceIndex);
            const push = isHovered ? pushFor(index, isPressed ? RADIAL_PUSH * 0.4 : RADIAL_PUSH) : { x: 0, y: 0 };
            const hasIcon = resolveRadialIcon(item.icon) !== null;
            const style = {
                left: `${radialFixed(point.x / RADIAL_SIZE * 100)}%`,
                top: `${radialFixed(point.y / RADIAL_SIZE * 100)}%`,
                '--w': labelWidth,
                '--px': push.x,
                '--py': push.y,
                '--i': index
            };
            if (item.iconColor) style['--cortex-radial-icon-color'] = item.iconColor;
            return h('div', {
                key: `${sourceIndex}:${item.id}`,
                className: [itemClasses(item, index, 'cortex-radial-label'), hasIcon ? 'has-icon' : 'no-icon'].join(' '),
                style: style
            },
                hasIcon ? h(RadialIcon, { icon: item.icon }) : h('span', { className: 'cortex-radial-label-text' }, item.label),
                badgeNode(item),
                item.hasMenu ? h(RadialChevron, { angle, distance: 31 }) : null
            );
        });

        let hubContent;
        if (hoveredItem) {
            const isArmed = hovered === armedLocal;
            const description = isArmed ? hoveredItem.confirm
                : hoveredItem.description || (hoveredItem.disabled ? 'Unavailable' : '');
            hubContent = h('div', { key: `item:${pageStartIndex + hovered}`, className: `cortex-radial-hub-content is-item${hoveredItem.disabled ? ' is-disabled' : ''}${isArmed ? ' is-armed' : ''}` },
                h('div', { className: `cortex-radial-hub-label${radialLabelSize(hoveredItem.label)}` }, hoveredItem.label),
                description && (!compactControl || isArmed) ? h('div', { className: 'cortex-radial-hub-desc' }, description) : null
            );
        } else {
            const idleTitle = empty ? 'No actions' : menuTitle;
            hubContent = h('div', { key: `idle:${canGoBack}:${idleTitle}`, className: `cortex-radial-hub-content is-idle${empty ? ' is-empty' : ''}` },
                idleTitle ? h('div', { className: `cortex-radial-hub-title${radialLabelSize(idleTitle)}` }, idleTitle) : null,
                h('div', { className: 'cortex-radial-hub-action' },
                    h(Kit.Keycap, { value: 'RMB', size: 'sm', pressed: pressed === 'center' }),
                    h('span', null, backLabel)
                )
            );
        }

        body = h('div', { className: `cortex-radial-wheel${compactControl ? ' is-compact' : ''}` },
            h('svg', svgProps,
                h('circle', { className: 'cortex-radial-hub-disc', cx: RADIAL_CENTER, cy: RADIAL_CENTER, r: RADIAL_HUB_RADIUS }),
                h('g', { key: `slips:${layerKey}`, className: `cortex-radial-slips${pageMotion ? (pageMotion > 0 ? ' is-paging-next' : ' is-paging-prev') : ''}` }, slipNodes)
            ),
            h('div', { key: `labels:${layerKey}`, className: 'cortex-radial-labels', 'aria-hidden': 'true' }, labelNodes),
            h('div', { className: 'cortex-radial-hub', 'aria-live': 'polite' }, hubContent),
            h('div', { className: 'cortex-radial-footer' },
                pageDots,
                compactControl ? null : h(Kit.ControlsLegend, { items: legendFor(false), align: 'center', className: 'cortex-radial-legend', label: 'Radial controls' })
            )
        );
    }

    const overlayClasses = ['cortex-radial-overlay',
        isVisible ? 'visible' : '',
        `is-${menuStyle}`,
        compactControl ? 'cortex-radial-overlay--compact-control' : ''].filter(Boolean).join(' ');

    return h('div', {
        className: overlayClasses,
        onMouseMove: handleMouseMove,
        onMouseDown: handleMouseDown,
        onMouseUp: handleMouseUp,
        onMouseLeave: () => setPressed(null),
        onClick: handleClick,
        onContextMenu: handleContextMenu,
        onWheel: handleWheel,
        role: 'dialog',
        'aria-modal': true,
        'aria-label': ariaName,
        'aria-busy': !isVisible,
        'aria-hidden': !isVisible
    }, body);
}
