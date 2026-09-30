/* Radial menu. A donut of slips chosen by direction: the pointer anywhere past
 * a small dead zone, arrows, or number keys pick a slip; the hovered slip flips
 * to paper with a mint arc on its outer edge; the hub names it. Pages are dots
 * under the wheel. See DESIGN.md "Radial". */

const RADIAL_MAX_ITEMS = NUI_MAX_MENU_OPTIONS;
const RADIAL_MAX_TRAIL = 8;

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
            hasMenu: (typeof item.menu === 'string' && item.menu !== '') || item.hasMenu === true
        };
    }).filter(Boolean);
}

/** Breadcrumb labels of the menus above the current one, root first. */
function normalizeRadialTrail(value) {
    if (!Array.isArray(value)) return [];
    return value.slice(-RADIAL_MAX_TRAIL)
        .map(entry => boundedText(entry, '', 64).trim())
        .filter(Boolean);
}

/** Zero-based source index to re-select after returning from a submenu. */
function normalizeRadialFocusIndex(value) {
    return Number.isInteger(value) && value >= 0 && value < RADIAL_MAX_ITEMS ? value : null;
}

// ============================================================================
// GEOMETRY. One viewBox unit is one radial unit (--ru), so strokes stay >= 3u.
// Angles are degrees clockwise from 12 o'clock; slip i is centred on i * step.
// ============================================================================

const RADIAL_PAGE_ITEMS = 8;           // slips per page; paged menus keep all 8 slots
const RADIAL_SIZE = 460;               // viewBox edge
const RADIAL_CENTER = RADIAL_SIZE / 2;
const RADIAL_OUTER_RADIUS = 204;
const RADIAL_INNER_RADIUS = 110;
const RADIAL_HUB_RADIUS = 98;
const RADIAL_LABEL_RADIUS = 157;
const RADIAL_ARC_RADIUS = 216;         // mint selection arc, just outside the slip
const RADIAL_GAP = 8;                  // constant-width gap between slips
const RADIAL_CORNER = 3;               // rounded slip corners (stroke join)
const RADIAL_PUSH = 5;                 // hovered slip moves out along its bisector
const RADIAL_DEAD_ZONE = 48;           // pointer radius that still means "centre"
const RADIAL_HYSTERESIS = 6;           // degrees a hovered slip holds past its edge
const RADIAL_WHEEL_COOLDOWN_MS = 180;
const RADIAL_EXIT_MS = 170;
const RADIAL_KEY_REARM_PX = 8;         // pointer travel that takes over from keys
const RADIAL_SINGLE_SWEEP = 120;       // a lone action is one slip, not a full ring

const radialMemory = new Map();        // menu key -> last page, for reopen / return

function rememberRadialPage(key, page) {
    radialMemory.delete(key);
    radialMemory.set(key, page);
    if (radialMemory.size > 32) radialMemory.delete(radialMemory.keys().next().value);
}

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

/** An annular slip with parallel (constant-width) gaps to its neighbours. */
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

/** The mint arc that rides the hovered slip's outer edge. */
function describeRadialArc(start, end) {
    const radius = RADIAL_ARC_RADIUS;
    if (end - start >= 359.9) {
        const c = RADIAL_CENTER;
        return `M ${c} ${c - radius} A ${radius} ${radius} 0 1 1 ${c} ${c + radius} A ${radius} ${radius} 0 1 1 ${c} ${c - radius}`;
    }
    const pad = radialPad(radius, RADIAL_GAP);   // flush with the slip's straight edges
    const a = radialPoint(radius, start + pad);
    const b = radialPoint(radius, end - pad);
    const large = end - start - pad * 2 > 180 ? 1 : 0;
    return `M ${radialFixed(a.x)} ${radialFixed(a.y)} A ${radius} ${radius} 0 ${large} 1 ${radialFixed(b.x)} ${radialFixed(b.y)}`;
}

/**
 * Maps a direction to a slot. Slot i is centred on i * step; the current slot
 * keeps the pointer for RADIAL_HYSTERESIS degrees past its edge so a hand
 * resting on a boundary does not flicker between neighbours.
 */
function radialDirectionIndex(angle, slotCount, current = -1) {
    const count = Math.max(1, Math.floor(slotCount) || 1);
    const step = 360 / count;
    const normalized = ((angle % 360) + 360) % 360;
    if (count > 1 && current >= 0 && current < count) {
        const offset = Math.abs(((normalized - current * step) % 360 + 540) % 360 - 180);
        if (offset <= step / 2 + RADIAL_HYSTERESIS) return current;
    }
    return Math.floor((normalized + step / 2) / step) % count;
}

/**
 * Direction from the wheel centre to the pointer. The pointer may be anywhere
 * on screen: past the dead zone it selects by angle, inside it means "centre".
 */
function getRadialPointer(clientX, clientY, element, slotCount, current = -1) {
    if (!element || !(slotCount > 0)) return { type: 'center', index: -1 };
    const rect = element.getBoundingClientRect();
    const scale = rect.width / RADIAL_SIZE;
    if (!Number.isFinite(scale) || scale <= 0) return { type: 'center', index: -1 };
    const dx = clientX - (rect.left + rect.width / 2);
    const dy = clientY - (rect.top + rect.height / 2);
    if (Math.hypot(dx, dy) / scale < RADIAL_DEAD_ZONE) return { type: 'center', index: -1 };
    const angle = Math.atan2(dx, -dy) * 180 / Math.PI;
    return { type: 'item', index: radialDirectionIndex(angle, slotCount, current) };
}

/** Held arrow keys as a direction; the nearest real (non-ghost) slip wins. */
function radialKeyIndex(held, slotCount, itemCount) {
    const x = (held.has('ArrowRight') ? 1 : 0) - (held.has('ArrowLeft') ? 1 : 0);
    const y = (held.has('ArrowDown') ? 1 : 0) - (held.has('ArrowUp') ? 1 : 0);
    if ((x === 0 && y === 0) || itemCount <= 0) return -1;
    const angle = ((Math.atan2(x, -y) * 180 / Math.PI) + 360) % 360;
    const step = 360 / Math.max(1, slotCount);
    let best = 0;
    let bestOffset = Infinity;
    for (let index = 0; index < Math.min(itemCount, slotCount); index += 1) {
        const offset = Math.abs(((angle - index * step) % 360 + 540) % 360 - 180);
        if (offset < bestOffset - 0.001) { best = index; bestOffset = offset; }
    }
    return best;
}

// ============================================================================
// ICONS. Named icons share the menu's stroked family when it is loaded; single
// glyphs ('1', 'A', '?') render in display type; emoji become a silhouette.
// ============================================================================

function resolveRadialIcon(value) {
    const raw = typeof value === 'string' ? value.trim() : '';
    if (!raw) return null;
    if (typeof resolveMenuIcon === 'function') return resolveMenuIcon(raw);
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

/** Submenu cue: a chevron that points outward along the slip's bisector. */
function RadialChevron({ angle }) {
    return React.createElement('svg', {
        className: 'cortex-radial-chevron', viewBox: '0 0 12 12', focusable: 'false', 'aria-hidden': 'true',
        style: { transform: `rotate(${radialFixed(angle)}deg)` }
    }, React.createElement('path', { d: 'M2.5 8 6 4.5 9.5 8' }));
}

const radialLabelSize = label => label.length > 26 ? ' is-longer' : label.length > 12 ? ' is-long' : '';

// ============================================================================
// RADIAL MENU
// ============================================================================

function RadialMenu({ open, id, session, items, canGoBack, visible, appearance, trail, focusIndex, view }) {
    const Kit = window.CortexKit;
    const h = React.createElement;
    const [hoverIndex, setHoverIndex] = useState(-1);
    const [page, setPage] = useState(1);
    const [mounted, setMounted] = useState(Boolean(open));
    const [pressed, setPressed] = useState(null);
    const [fired, setFired] = useState(-1);
    const [pageMotion, setPageMotion] = useState(0);
    const radialSvgRef = useRef(null);
    const pointerRef = useRef(null);
    const keyAnchorRef = useRef(null);
    const inputModeRef = useRef('pointer');
    const heldKeysRef = useRef(new Set());
    const pendingRef = useRef(false);
    const wheelAtRef = useRef(0);
    const firedTimerRef = useRef(0);

    const isVisible = Boolean(open) && visible !== false;
    const allItems = Array.isArray(items) ? items : [];
    const itemCount = allItems.length;
    const totalPages = Math.max(1, Math.ceil(itemCount / RADIAL_PAGE_ITEMS));
    const currentPage = Math.min(Math.max(1, page), totalPages);
    const pageStartIndex = (currentPage - 1) * RADIAL_PAGE_ITEMS;
    const displayItems = allItems.slice(pageStartIndex, pageStartIndex + RADIAL_PAGE_ITEMS);
    const slotCount = totalPages > 1 ? RADIAL_PAGE_ITEMS : Math.max(1, displayItems.length);
    const angleStep = 360 / slotCount;
    const hovered = hoverIndex >= 0 && hoverIndex < displayItems.length ? hoverIndex : -1;
    const hoveredItem = hovered >= 0 ? displayItems[hovered] : null;
    const compactControl = appearance === 'compact-control';
    const memoryKey = id || '__root__';
    const crumbs = Array.isArray(trail) ? trail : [];

    // Keep the surface mounted for the exit fade after Lua closes it.
    useEffect(() => {
        if (open) { setMounted(true); return undefined; }
        const timer = window.setTimeout(() => setMounted(false), RADIAL_EXIT_MS);
        return () => window.clearTimeout(timer);
    }, [open]);

    // A new view (open, submenu, back) restores the remembered page, and on
    // return from a submenu re-selects the item that opened it.
    useEffect(() => {
        if (!open) return;
        pendingRef.current = false;
        heldKeysRef.current.clear();
        setPressed(null);
        setPageMotion(0);
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

    useEffect(() => () => window.clearTimeout(firedTimerRef.current), []);

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
        rememberRadialPage(memoryKey, currentPage);
        setFired(sourceIndex);
        window.clearTimeout(firedTimerRef.current);
        firedTimerRef.current = window.setTimeout(() => setFired(-1), 180);
        pendingRef.current = true;
        Promise.resolve(nuiPost('radialClick', { index: sourceIndex, itemId: item.id, menuId: id, session }))
            .finally(() => { pendingRef.current = false; });
    }, [allItems.length, currentPage, displayItems, id, isVisible, memoryKey, pageStartIndex, session]);

    const changePage = useCallback((delta) => {
        if (!isVisible || totalPages <= 1) return;
        const next = (((currentPage - 1 + delta) % totalPages) + totalPages) % totalPages + 1;
        const nextCount = Math.min(RADIAL_PAGE_ITEMS, allItems.length - (next - 1) * RADIAL_PAGE_ITEMS);
        setPage(next);
        setPageMotion(delta > 0 ? 1 : -1);
        rememberRadialPage(memoryKey, next);
        // Same direction, new page: the pointer re-aims (a ghost slot selects
        // nothing); a keyboard selection moves to the nearest real slip.
        const pointer = pointerRef.current;
        if (inputModeRef.current === 'pointer' && pointer) {
            const hit = getRadialPointer(pointer.x, pointer.y, radialSvgRef.current, RADIAL_PAGE_ITEMS);
            setHoverIndex(hit.type === 'item' && hit.index < nextCount ? hit.index : -1);
        } else {
            setHoverIndex(current => Math.min(current, nextCount - 1));
        }
    }, [allItems.length, currentPage, isVisible, memoryKey, totalPages]);

    const pointerHit = useCallback((event, current) => getRadialPointer(
        event.clientX, event.clientY, radialSvgRef.current, slotCount, current
    ), [slotCount]);

    const handleMouseMove = useCallback((e) => {
        if (!isVisible) return;
        pointerRef.current = { x: e.clientX, y: e.clientY };
        if (inputModeRef.current === 'keys') {
            const anchor = keyAnchorRef.current;
            if (anchor && Math.hypot(e.clientX - anchor.x, e.clientY - anchor.y) < RADIAL_KEY_REARM_PX) return;
            inputModeRef.current = 'pointer';
        }
        const hit = pointerHit(e, hovered);
        const next = hit.type === 'item' && hit.index < displayItems.length ? hit.index : -1;
        if (next !== hoverIndex) setHoverIndex(next);
    }, [displayItems.length, hoverIndex, hovered, isVisible, pointerHit]);

    const handleMouseDown = useCallback((e) => {
        if (!isVisible || e.button !== 0) return;
        const hit = pointerHit(e, hovered);
        setPressed(hit.type === 'center' ? 'center' : 'item');
    }, [hovered, isVisible, pointerHit]);

    const handleClick = useCallback((e) => {
        setPressed(null);
        if (!isVisible) return;
        const hit = pointerHit(e, hovered);
        if (hit.type === 'center') { backOrClose(); return; }
        // Confirm only what is visibly selected. A click that arrives before
        // the pointer re-aims (after a submenu opens) only selects.
        if (hit.index === hovered) activateItem(hit.index);
        else if (hit.index < displayItems.length) {
            inputModeRef.current = 'pointer';
            setHoverIndex(hit.index);
        }
    }, [activateItem, backOrClose, displayItems.length, hovered, isVisible, pointerHit]);

    // Right-click = back / close, wherever the pointer is.
    const handleContextMenu = useCallback((e) => {
        e.preventDefault();
        backOrClose();
    }, [backOrClose]);

    const handleWheel = useCallback((e) => {
        if (!isVisible || totalPages <= 1 || !e.deltaY) return;
        const now = Date.now();
        if (now - wheelAtRef.current < RADIAL_WHEEL_COOLDOWN_MS) return;
        wheelAtRef.current = now;
        changePage(e.deltaY > 0 ? 1 : -1);
    }, [changePage, isVisible, totalPages]);

    // Keyboard: arrows aim, 1-8 pick, Enter confirms, Q/E page, Tab cycles.
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
            } else if (displayItems.length > 0 && (key === 'ArrowRight' || key === 'ArrowLeft' || key === 'ArrowUp' || key === 'ArrowDown')) {
                e.preventDefault();
                held.add(key);
                const index = radialKeyIndex(held, slotCount, displayItems.length);
                if (index >= 0) selectByKeys(index);
            } else if (key === 'Tab' && displayItems.length > 0) {
                e.preventDefault();
                const direction = e.shiftKey ? -1 : 1;
                let next = hovered;
                for (let step = 0; step < displayItems.length; step += 1) {
                    next = next < 0 ? (direction > 0 ? 0 : displayItems.length - 1)
                        : (next + direction + displayItems.length) % displayItems.length;
                    if (!displayItems[next].disabled) break;
                }
                selectByKeys(next);
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

        window.addEventListener('keydown', handleKeyDown);
        window.addEventListener('keyup', handleKeyUp);
        window.addEventListener('blur', handleBlur);
        return () => {
            window.removeEventListener('keydown', handleKeyDown);
            window.removeEventListener('keyup', handleKeyUp);
            window.removeEventListener('blur', handleBlur);
        };
    }, [activateItem, backOrClose, changePage, displayItems, hovered, id, isVisible, open, session, slotCount]);

    if (!open && !mounted) return null;

    const slots = Array.from({ length: slotCount }, (_, index) => displayItems[index] || null);
    const pushFor = (index, distance) => {
        if (slotCount === 1 && itemCount === 0) return { x: 0, y: 0 };
        const radians = index * angleStep * Math.PI / 180;
        return { x: radialFixed(Math.sin(radians) * distance), y: radialFixed(-Math.cos(radians) * distance) };
    };
    const labelWidth = slotCount <= 2 ? 160 : slotCount <= 4 ? 124 : slotCount <= 6 ? 108 : 94;
    const layerKey = `${view ?? 0}:${currentPage}`;
    const empty = itemCount === 0;
    const backLabel = canGoBack ? 'Back' : 'Close';
    const crumbText = crumbs.join(' / ');

    const slipNodes = slots.map((item, index) => {
        const sweep = slotCount === 1 && item ? RADIAL_SINGLE_SWEEP : angleStep;
        const start = index * angleStep - sweep / 2;
        const end = start + sweep;
        const sourceIndex = pageStartIndex + index;
        const isHovered = item !== null && index === hovered;
        const isPressed = isHovered && (pressed === 'item' || fired === sourceIndex);
        const push = pushFor(index, isPressed ? RADIAL_PUSH * 0.4 : RADIAL_PUSH);
        const classes = ['cortex-radial-slip',
            item ? '' : 'is-ghost',
            isHovered ? 'is-hover' : '',
            isPressed ? 'is-pressed' : '',
            item?.disabled ? 'is-disabled' : ''].filter(Boolean).join(' ');
        return h('g', {
            key: item ? `${sourceIndex}:${item.id}` : `ghost:${index}`,
            id: item ? `cortex-radial-item-${sourceIndex}` : undefined,
            className: classes,
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
        const angle = index * angleStep;
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
            className: ['cortex-radial-label',
                isHovered ? 'is-hover' : '',
                item.disabled ? 'is-disabled' : '',
                hasIcon ? 'has-icon' : 'no-icon',
                compactControl && hasIcon ? 'is-icon-only' : ''].filter(Boolean).join(' '),
            style
        },
            hasIcon ? h(RadialIcon, { icon: item.icon }) : null,
            h('span', { className: 'cortex-radial-label-text' }, item.label),
            item.hasMenu ? h(RadialChevron, { angle }) : null
        );
    });

    let hubContent;
    if (hoveredItem) {
        const description = hoveredItem.description
            || (hoveredItem.disabled ? 'Unavailable' : hoveredItem.hasMenu ? 'Opens a submenu' : '');
        hubContent = h('div', { key: `item:${pageStartIndex + hovered}`, className: `cortex-radial-hub-content is-item${hoveredItem.disabled ? ' is-disabled' : ''}` },
            h('div', { className: 'cortex-radial-hub-meta' },
                h(Kit.Keycap, { value: String(hovered + 1), size: 'sm', tone: hoveredItem.disabled ? 'ink' : 'paper' }),
                crumbText ? h('span', { className: 'cortex-radial-crumb' }, crumbText) : null
            ),
            h('div', { className: `cortex-radial-hub-label${radialLabelSize(hoveredItem.label)}` }, hoveredItem.label),
            description && !compactControl ? h('div', { className: 'cortex-radial-hub-desc' }, description) : null
        );
    } else {
        const title = empty ? 'No actions' : (crumbs.length ? crumbs[crumbs.length - 1] : '');
        const eyebrow = crumbs.length > 1 ? crumbs.slice(0, -1).join(' / ') : '';
        hubContent = h('div', { key: `idle:${canGoBack}:${crumbText}`, className: `cortex-radial-hub-content is-idle${empty ? ' is-empty' : ''}` },
            eyebrow ? h('span', { className: 'cortex-radial-crumb' }, eyebrow) : null,
            title ? h('div', { className: `cortex-radial-hub-title${radialLabelSize(title)}` }, title) : null,
            h('div', { className: 'cortex-radial-hub-action' },
                h(Kit.Keycap, { value: 'RMB', size: 'sm', pressed: pressed === 'center' }),
                h('span', null, backLabel)
            )
        );
    }

    const legend = [
        empty ? null : { keys: 'LMB', label: 'Select', disabled: !hoveredItem || hoveredItem.disabled },
        { keys: 'RMB', label: backLabel },
        displayItems.length > 0 ? { keys: displayItems.length > 1 ? `1-${displayItems.length}` : '1', label: 'Pick' } : null,
        totalPages > 1 ? { keys: 'WHEEL', label: 'Page' } : null,
        canGoBack ? { keys: 'ESC', label: 'Close' } : null
    ].filter(Boolean);

    const overlayClasses = ['cortex-radial-overlay',
        isVisible ? 'visible' : '',
        compactControl ? 'cortex-radial-overlay--compact-control' : ''].filter(Boolean).join(' ');

    return h('div', {
        className: overlayClasses,
        onMouseMove: handleMouseMove,
        onMouseDown: handleMouseDown,
        onMouseUp: () => setPressed(null),
        onMouseLeave: () => setPressed(null),
        onClick: handleClick,
        onContextMenu: handleContextMenu,
        onWheel: handleWheel,
        role: 'dialog',
        'aria-modal': true,
        'aria-label': 'Radial controls',
        'aria-busy': !isVisible,
        'aria-hidden': !isVisible
    },
        h('div', { className: `cortex-radial-wheel${compactControl ? ' is-compact' : ''}` },
            h('svg', {
                className: `cortex-radial-svg${compactControl ? ' cortex-radial-svg--compact-control' : ''}`,
                viewBox: `0 0 ${RADIAL_SIZE} ${RADIAL_SIZE}`,
                xmlns: 'http://www.w3.org/2000/svg',
                ref: radialSvgRef,
                role: 'menu',
                tabIndex: isVisible ? 0 : -1,
                'aria-label': crumbText || (id ? `${id.replaceAll('_', ' ')} menu` : 'Controls menu'),
                'aria-activedescendant': hovered >= 0 ? `cortex-radial-item-${pageStartIndex + hovered}` : undefined
            },
                h('circle', { className: 'cortex-radial-hub-disc', cx: RADIAL_CENTER, cy: RADIAL_CENTER, r: RADIAL_HUB_RADIUS }),
                h('g', { key: `slips:${layerKey}`, className: `cortex-radial-slips${pageMotion ? (pageMotion > 0 ? ' is-paging-next' : ' is-paging-prev') : ''}` }, slipNodes)
            ),
            h('div', { key: `labels:${layerKey}`, className: 'cortex-radial-labels', 'aria-hidden': 'true' }, labelNodes),
            h('div', { className: 'cortex-radial-hub', 'aria-live': 'polite' }, hubContent),
            h('div', { className: 'cortex-radial-footer' },
                totalPages > 1 ? h('div', { className: 'cortex-radial-pages', role: 'group', 'aria-label': `Page ${currentPage} of ${totalPages}` },
                    h(Kit.Keycap, { value: 'Q', size: 'sm' }),
                    h('span', { className: 'cortex-radial-dots' },
                        Array.from({ length: totalPages }, (_, index) => h('i', {
                            key: index,
                            className: `cortex-radial-dot${index + 1 === currentPage ? ' is-current' : ''}`
                        }))),
                    h(Kit.Keycap, { value: 'E', size: 'sm' })
                ) : null,
                compactControl ? null : h(Kit.ControlsLegend, { items: legend, align: 'center', className: 'cortex-radial-legend', label: 'Radial controls' })
            )
        )
    );
}
