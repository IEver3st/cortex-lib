/* Screen and world interaction prompts.
 *
 * World prompts arrive from client/interaction_renderer.lua already tiered and
 * grouped: `tier: 'marker'` items are distant dots, `tier: 'prompt'` items that
 * share a `group` form one list at the head's anchor. Every surface here uses
 * one anatomy: a key disc (or a dot on the rail) and a display-caps label,
 * sized by --ix = --u x --cx-prompt-scale. Local primitives: WorldPromptRow,
 * WorldPromptGroup (rail, dots, fade tail), no kit changes. */

const INTERACTION_LIST_VISIBLE_ROWS = 4;
const INTERACTION_WORLD_LIMIT = 16;
const INTERACTION_FLIP_X = 0.68;
const VEHICLE_ACCESS_ACTIONS = Object.freeze({
    'vehicle-clone-key': { order: 0, icon: 'clone-key' },
    'vehicle-smash-window': { order: 1, icon: 'smash-window' }
});

function clampInteractionNumber(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, Number(value) || 0));
}

function getInteractionHoldDuration(value) {
    const duration = Number(value);
    if (!Number.isFinite(duration) || duration < 100 || duration > 600000) return null;
    return Math.floor(duration);
}

function getInteractionPanelKey(item) {
    if (item?.panelVariant !== 'target' || !item.panelId || !item.panelLabel) return null;
    return `${item.owner}\u0000${item.panelId}\u0000${item.panelVariant}\u0000${item.panelLabel}\u0000${item.panelMarker || '?'}`;
}

function buildInteractionBlocks(items) {
    const blocks = [];
    const panelBlocks = new Map();

    for (const item of items) {
        const panelKey = getInteractionPanelKey(item);
        if (!panelKey) {
            blocks.push({ type: 'item', key: `${item.owner}:${item.id}`, item });
            continue;
        }

        const existing = panelBlocks.get(panelKey);
        if (existing) {
            existing.items.push(item);
            continue;
        }

        const block = {
            type: 'panel',
            key: panelKey,
            panel: {
                id: item.panelId,
                label: item.panelLabel,
                variant: item.panelVariant,
                marker: item.panelMarker
            },
            items: [item]
        };
        panelBlocks.set(panelKey, block);
        blocks.push(block);
    }

    return blocks;
}

function InteractionKey(props) {
    return window.CortexInteractionKey.render(React.createElement, props);
}

function getVehicleAccessPresentation(item) {
    if (item?.owner !== 'cortex-hud') return null;
    return VEHICLE_ACCESS_ACTIONS[item.id] || null;
}

function VehicleAccessIcon({ type }) {
    if (type === 'clone-key') {
        return React.createElement('svg', {
            viewBox: '0 0 20 20',
            focusable: 'false',
            'aria-hidden': 'true'
        },
            React.createElement('circle', {
                cx: '4',
                cy: '10',
                r: '1.65',
                fill: 'currentColor',
                stroke: 'none'
            }),
            React.createElement('path', { d: 'M7 6.8a4.55 4.55 0 0 1 0 6.4' }),
            React.createElement('path', { d: 'M9.5 4.3a8.1 8.1 0 0 1 0 11.4' })
        );
    }

    return React.createElement('svg', {
        viewBox: '0 0 20 20',
        focusable: 'false',
        'aria-hidden': 'true'
    },
        React.createElement('path', { d: 'M10 2.4 16 4.9v4.35c0 3.85-2.25 6.65-6 8.35-3.75-1.7-6-4.5-6-8.35V4.9L10 2.4Z' }),
        React.createElement('path', { d: 'm7.5 7.45 5 5m0-5-5 5' })
    );
}

function TargetInteractionPanel({ panel, items }) {
    return React.createElement('section', {
        className: 'cortex-target-panel',
        role: 'listitem',
        'aria-label': `${panel.label} actions`
    },
        React.createElement('div', {
            className: 'cortex-target-actions',
            role: 'list'
        }, items.map((item) => React.createElement('div', {
            className: 'cortex-target-action',
            key: `${item.owner}:${item.id}`,
            role: 'listitem'
        },
            React.createElement('span', {
                className: 'cortex-target-action-label'
            }, item.label),
            React.createElement(InteractionKey, {
                item,
                className: 'cortex-interaction-key',
                ariaLabel: `Press ${item.key} to ${item.label.toLowerCase()}`
            })
        ))),
        React.createElement('span', {
            className: 'cortex-target-divider',
            'aria-hidden': 'true'
        }),
        React.createElement('div', { className: 'cortex-target-context' },
            React.createElement('span', {
                className: `cortex-target-context-label${panel.label.length > 12 ? ' is-long' : ''}`
            }, panel.label),
            React.createElement(InteractionKey, {
                item: { key: panel.marker || '?' },
                className: 'cortex-target-marker',
                decorative: true
            })
        )
    );
}

// Screen prompts stack bottom-right on the help legend's edge and lift above
// it through --cx-help-legend-height (published by the help surface), so the
// two bottom-right surfaces never overlap.
function InteractionPrompts({ items, layout, listHint = false }) {
    if (!listHint && (!Array.isArray(items) || items.length === 0)) return null;

    const style = {
        '--cortex-interaction-safe-right': `${Math.max(0, Number(layout?.insetRight) || 0)}px`,
        '--cortex-interaction-safe-bottom': `${Math.max(0, Number(layout?.insetBottom) || 0)}px`
    };

    const blocks = buildInteractionBlocks(Array.isArray(items) ? items : []);
    // A focused world list owns the wheel: its control hint joins this
    // bottom-right column (same anatomy as a prompt) instead of the list.
    const hint = listHint ? React.createElement('div', {
        className: 'cortex-interaction is-hint',
        key: 'list-hint',
        role: 'listitem'
    },
        React.createElement('span', { className: 'cortex-interaction-label' }, 'Select'),
        React.createElement(InteractionKey, {
            item: { key: 'WHEEL' },
            className: 'cortex-interaction-key',
            ariaLabel: 'Scroll the mouse wheel to choose an action'
        })
    ) : null;

    return React.createElement('div', {
        className: 'cortex-interactions',
        style,
        role: 'list',
        'aria-label': 'Available actions'
    }, blocks.map((block) => block.type === 'panel'
        ? React.createElement(TargetInteractionPanel, {
            key: block.key,
            panel: block.panel,
            items: block.items
        })
        : React.createElement('div', {
            className: 'cortex-interaction',
            key: block.key,
            role: 'listitem'
        },
            React.createElement('span', {
                className: 'cortex-interaction-label'
            }, block.item.label),
            React.createElement(InteractionKey, {
                item: block.item,
                className: 'cortex-interaction-key',
                ariaLabel: `Press ${block.item.key} to ${block.item.label.toLowerCase()}`
            })
        )).concat(hint ? [hint] : []));
}

/** Groups world items: markers stand alone; prompts join their `group` list. */
function buildWorldInteractionGroups(items) {
    const groups = [];
    const byKey = new Map();

    for (const item of items) {
        if (item.tier === 'marker') {
            groups.push({ key: `${item.owner}:${item.id}`, marker: true, rows: [item] });
            continue;
        }

        // Older renderers sent no group: rows at one exact anchor still stack.
        const groupKey = item.group
            ? `g\u0000${item.group}`
            : `xy\u0000${item.x}\u0000${item.y}\u0000${item.distance}`;
        const existing = byKey.get(groupKey);
        if (existing) {
            existing.rows.push(item);
            continue;
        }

        const group = { key: item.group || `${item.owner}:${item.id}`, marker: false, rows: [item] };
        byKey.set(groupKey, group);
        groups.push(group);
    }

    return groups;
}

/** Visible slice of a list: up to four rows, keeping one row below the selection. */
function getInteractionListWindow(count, selectedIndex, visible = INTERACTION_LIST_VISIBLE_ROWS) {
    if (count <= visible) return { start: 0, end: count };
    const start = Math.max(0, Math.min(count - visible, selectedIndex - (visible - 2)));
    return { start, end: start + visible };
}

function worldActionText(item) {
    const action = String(item.label || '').toLowerCase();
    return item.holdDuration
        ? `Hold ${item.key} to ${action}`
        : `Press ${item.key} to ${action}`;
}

function WorldPromptRow({ item, selected, peek, head, marker, first, last }) {
    const vehicle = marker ? null : getVehicleAccessPresentation(item);
    const ownsKey = !marker && item.active !== false;
    const classes = ['cx-wp-row',
        selected ? 'is-selected' : '',
        ownsKey ? 'is-active' : '',
        peek ? 'is-peek' : '',
        first ? 'is-first' : '',
        last ? 'is-last' : '',
        vehicle ? `cortex-world-access-row is-${vehicle.icon}` : ''].filter(Boolean).join(' ');

    let glyph = null;
    if (!marker && !peek && (selected || ownsKey)) {
        glyph = React.createElement(window.CortexSkillChecks.WorldKey, {
            item,
            fallback: React.createElement(InteractionKey, {
                item,
                className: `cortex-world-interaction-key${selected ? '' : ' is-small'}`,
                ariaLabel: worldActionText(item)
            })
        });
    } else if (!marker) {
        glyph = React.createElement('span', { className: 'cx-wp-dot', 'aria-hidden': 'true' });
    }

    return React.createElement('div', {
        className: classes,
        role: marker ? undefined : 'listitem',
        'aria-hidden': marker || peek ? 'true' : undefined
    },
        React.createElement('span', { className: 'cx-wp-pip' },
            // The head row keeps the marker layer mounted so a marker grows
            // into the prompt disc instead of popping (and shrinks back).
            head ? React.createElement('span', { className: 'cx-wp-marker', 'aria-hidden': 'true' }) : null,
            glyph
        ),
        vehicle ? React.createElement('span', {
            className: 'cx-wp-icon cortex-world-access-icon',
            'aria-hidden': 'true'
        }, React.createElement(VehicleAccessIcon, { type: vehicle.icon })) : null,
        marker ? null : React.createElement('span', {
            className: 'cx-wp-label cortex-world-interaction-label'
        }, item.label)
    );
}

function WorldPromptGroup({ group }) {
    const head = group.rows[0];
    const x = clampInteractionNumber(head.x, 0, 1);
    const y = clampInteractionNumber(head.y, 0, 1);
    const distanceScale = clampInteractionNumber(1.035 - (Number(head.distance) || 0) * 0.025, 0.96, 1.02);

    if (group.marker) {
        const fade = clampInteractionNumber(head.fade ?? 1, 0, 1);
        return React.createElement('div', {
            className: 'cx-wp is-marker',
            style: {
                '--wx': `${x * 100}vw`,
                '--wy': `${y * 100}vh`,
                '--wscale': distanceScale,
                '--wo': (0.42 + fade * 0.5).toFixed(3)
            },
            'aria-hidden': 'true'
        }, React.createElement('div', { className: 'cx-wp-body is-first-selected' },
            // Same child shape as the prompt body (rows array, hint slot) so
            // React keeps the row and its marker layer mounted through the
            // marker -> prompt swap.
            [React.createElement(WorldPromptRow, { key: group.key, item: head, head: true, marker: true, selected: true, first: true, last: true })],
            null
        ));
    }

    const rows = group.rows;
    const count = rows.length;
    const selectedIndex = Math.max(0, rows.findIndex((row) => row.selected));
    const { start, end } = getInteractionListWindow(count, selectedIndex);
    const list = count > 1;
    const flipped = x > INTERACTION_FLIP_X;
    const focused = list && head.focused === true;
    const moreAbove = start > 0;
    const moreBelow = end < count;
    // Keep the list inside the viewport: estimate its height in --ix units.
    const visibleRows = end - start + (moreBelow ? 1 : 0);
    const estimate = 50 + Math.max(0, visibleRows - 1) * 36;
    const classes = ['cx-wp', 'is-prompt',
        list ? 'is-list' : '',
        flipped ? 'is-flipped' : '',
        focused ? 'is-focused' : '',
        moreAbove ? 'has-more-above' : '',
        moreBelow ? 'has-more-below' : ''].filter(Boolean).join(' ');

    const children = [];
    for (let index = start; index < end; index += 1) {
        const item = rows[index];
        children.push(React.createElement(WorldPromptRow, {
            key: `${item.owner}:${item.id}`,
            item,
            selected: index === selectedIndex,
            head: index === 0,
            first: index === start,
            last: index === end - 1 && !moreBelow
        }));
    }
    if (moreBelow) {
        const item = rows[end];
        children.push(React.createElement(WorldPromptRow, {
            key: `${item.owner}:${item.id}`,
            item,
            peek: true,
            last: true
        }));
    }

    return React.createElement('div', {
        className: classes,
        style: {
            '--wx': `${x * 100}vw`,
            '--wy': `min(${y * 100}vh, calc(100vh - ${estimate} * var(--ix) - 24 * var(--u)))`,
            '--wscale': distanceScale
        },
        role: 'list',
        'aria-label': list ? `${count} nearby actions` : undefined
    },
        React.createElement('div', {
            className: `cx-wp-body${selectedIndex === start ? ' is-first-selected' : ''}`
        },
            children
        )
    );
}

function WorldInteractionPrompts({ items }) {
    if (!Array.isArray(items) || items.length === 0) return null;

    const groups = buildWorldInteractionGroups(items);
    for (const group of groups) {
        // Vehicle access actions keep their fixed order inside their list.
        if (group.rows.length > 1 && group.rows.every(getVehicleAccessPresentation)) {
            group.rows.sort((left, right) => getVehicleAccessPresentation(left).order
                - getVehicleAccessPresentation(right).order);
        }
    }

    return React.createElement('div', {
        className: 'cortex-world-interactions',
        role: 'list',
        'aria-label': 'Nearby world actions'
    }, groups.map((group) => React.createElement(WorldPromptGroup, { key: group.key, group })));
}

const INTERACTION_BASE_FIELDS = Object.freeze([
    'id',
    'owner',
    'label',
    'key',
    'holdDuration',
    'holdActive',
    'holdRevision',
    'panelId',
    'panelLabel',
    'panelVariant',
    'panelMarker'
]);
const INTERACTION_WORLD_FIELDS = Object.freeze([
    ...INTERACTION_BASE_FIELDS,
    'x',
    'y',
    'distance',
    'tier',
    'group',
    'selected',
    'active',
    'focused',
    'fade'
]);

function normalizeInteractionPanel(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;

    const id = typeof value.id === 'string' ? value.id.trim().slice(0, 64) : '';
    const label = typeof value.label === 'string' ? value.label.trim().slice(0, 96) : '';
    const variant = value.variant === undefined ? 'target' : value.variant;
    if (!id || !label || variant !== 'target') return null;

    return {
        panelId: id,
        panelLabel: label,
        panelVariant: variant,
        panelMarker: typeof value.marker === 'string' && /^[A-Za-z0-9?]$/.test(value.marker) ? value.marker : '?'
    };
}

function normalizeInteractionItems(items, world) {
    if (!Array.isArray(items)) return [];

    const limit = world ? INTERACTION_WORLD_LIMIT : 8;
    const normalized = [];

    for (let index = 0; index < items.length && normalized.length < limit; index += 1) {
        const item = items[index];
        if (!item || typeof item !== 'object') continue;
        const marker = world && item.tier === 'marker';
        if (!marker && (typeof item.label !== 'string' || typeof item.key !== 'string')) continue;
        if (world && (!Number.isFinite(Number(item.x)) || !Number.isFinite(Number(item.y)))) continue;

        const normalizedIndex = normalized.length;
        const nextItem = {
            id: typeof item.id === 'string' ? item.id.slice(0, 64) : `${world ? 'world' : 'screen'}-${normalizedIndex}`,
            owner: typeof item.owner === 'string' ? item.owner.slice(0, 64) : 'unknown',
            label: marker ? '' : item.label.trim().slice(0, 96),
            key: marker ? '' : item.key.trim().slice(0, 16),
            holdDuration: world && !marker ? getInteractionHoldDuration(item.holdDuration) : null,
            holdActive: world && !marker && item.holdActive === true,
            holdRevision: world && !marker ? clampInteractionNumber(item.holdRevision, 0, 1000000000) : 0
        };
        const panel = marker ? null : normalizeInteractionPanel(item.panel);
        if (panel) Object.assign(nextItem, panel);

        if (world) {
            nextItem.x = clampInteractionNumber(item.x, 0, 1);
            nextItem.y = clampInteractionNumber(item.y, 0, 1);
            nextItem.distance = clampInteractionNumber(item.distance, 0, 25);
            nextItem.tier = marker ? 'marker' : 'prompt';
            nextItem.group = !marker && typeof item.group === 'string' && item.group ? item.group.slice(0, 160) : null;
            nextItem.selected = !marker && item.selected === true;
            nextItem.active = !marker && item.active !== false;
            nextItem.focused = !marker && item.focused === true;
            nextItem.fade = marker ? clampInteractionNumber(item.fade ?? 1, 0, 1) : 1;
        }

        normalized.push(nextItem);
    }

    return normalized;
}

function interactionItemsEqual(left, right, world) {
    if (left === right) return true;
    if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) return false;

    const fields = world ? INTERACTION_WORLD_FIELDS : INTERACTION_BASE_FIELDS;
    for (let index = 0; index < left.length; index += 1) {
        for (let fieldIndex = 0; fieldIndex < fields.length; fieldIndex += 1) {
            const field = fields[fieldIndex];
            if (!Object.is(left[index][field], right[index][field])) return false;
        }
    }

    return true;
}

function interactionLayoutsEqual(left, right) {
    return Object.is(left.insetRight, right.insetRight)
        && Object.is(left.insetBottom, right.insetBottom)
        && Object.is(left.screenWidth, right.screenWidth)
        && Object.is(left.screenHeight, right.screenHeight)
        && Object.is(left.safezone, right.safezone);
}

function InteractionSurface({ hidden }) {
    const [interactionItems, setInteractionItems] = useState([]);
    const [, setWorldInteractionItems] = useState([]);
    const [interactionLayout, setInteractionLayout] = useState({
        insetRight: 0,
        insetBottom: 0,
        screenWidth: 1920,
        screenHeight: 1080,
        safezone: 1
    });
    const pendingWorldItemsRef = useRef(null);
    const latestWorldItemsRef = useRef([]);
    const worldFrameRef = useRef(0);
    const hiddenRef = useRef(hidden);
    hiddenRef.current = hidden;

    useEffect(() => {
        if (hidden) return;

        const nextItems = latestWorldItemsRef.current;
        setWorldInteractionItems((currentItems) => (
            interactionItemsEqual(currentItems, nextItems, true) ? currentItems : nextItems
        ));
    }, [hidden]);

    useEffect(() => {
        if (typeof GetParentResourceName !== 'function') return;

        let cancelled = false;
        let retryTimer = 0;
        let activeController = null;

        const announceInteractionReady = async (attempt = 0) => {
            activeController = new AbortController();
            const payload = await nuiPost('interactionReady', {}, {
                timeoutMs: 1500,
                signal: activeController.signal
            });
            activeController = null;
            if (payload?.ok === true || cancelled) return;

            const retryDelay = Math.min(2000, 250 + (attempt * 175));
            retryTimer = window.setTimeout(() => announceInteractionReady(attempt + 1), retryDelay);
        };

        announceInteractionReady();

        return () => {
            cancelled = true;
            window.clearTimeout(retryTimer);
            activeController?.abort();
        };
    }, []);

    useEffect(() => {
        const commitWorldItems = () => {
            worldFrameRef.current = 0;
            const nextItems = pendingWorldItemsRef.current;
            pendingWorldItemsRef.current = null;
            if (!nextItems || hiddenRef.current) return;

            setWorldInteractionItems((currentItems) => (
                interactionItemsEqual(currentItems, nextItems, true) ? currentItems : nextItems
            ));
        };

        const handleInteractionMessage = (event) => {
            const message = normalizeNuiMessage(event);
            if (!message) return;

            const data = message.data;
            switch (message.action) {
                case 'interaction:update': {
                    const nextItems = normalizeInteractionItems(data?.items, false);
                    setInteractionItems((currentItems) => (
                        interactionItemsEqual(currentItems, nextItems, false) ? currentItems : nextItems
                    ));
                    break;
                }
                case 'interaction:world': {
                    const nextItems = normalizeInteractionItems(data?.items, true);
                    latestWorldItemsRef.current = nextItems;
                    if (hiddenRef.current) break;

                    pendingWorldItemsRef.current = nextItems;
                    if (!worldFrameRef.current) {
                        worldFrameRef.current = window.requestAnimationFrame(commitWorldItems);
                    }
                    break;
                }
                case 'interaction:layout':
                    setInteractionLayout((currentLayout) => {
                        const nextLayout = {
                            ...currentLayout,
                            ...(data && typeof data === 'object' ? data : {})
                        };
                        return interactionLayoutsEqual(currentLayout, nextLayout) ? currentLayout : nextLayout;
                    });
                    break;
            }
        };

        window.addEventListener('message', handleInteractionMessage);
        return () => {
            window.removeEventListener('message', handleInteractionMessage);
            pendingWorldItemsRef.current = null;
            latestWorldItemsRef.current = [];
            if (worldFrameRef.current) {
                window.cancelAnimationFrame(worldFrameRef.current);
                worldFrameRef.current = 0;
            }
        };
    }, []);

    if (hidden) return null;

    return React.createElement(React.Fragment, null,
        React.createElement(InteractionPrompts, {
            items: interactionItems,
            layout: interactionLayout,
            listHint: latestWorldItemsRef.current.some((item) => item.focused === true && item.tier !== 'marker')
        }),
        React.createElement(WorldInteractionPrompts, { items: latestWorldItemsRef.current })
    );
}
