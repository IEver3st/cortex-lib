/* Notifications: frameless status callouts stacked at a screen edge.
 * Signature: a 4u severity rule + display-caps title, lifetime shown as a 4u
 * meter under the text. The player's duration and limit preferences apply here. */

// ----------------------------------------------------------------------------
// Runtime safe zone. The Lua interaction renderer publishes the game's safe
// zone as `interaction:layout` (on NUI ready and whenever it changes). Edge
// overlays (notifications, progress, text UI, the controls legend) read it as
// --cx-safezone-x / --cx-safezone-y so they sit inside the player's safe zone
// instead of a guessed margin. Candidate for promotion to the shared kit.
// ----------------------------------------------------------------------------
(function trackCortexSafeZone() {
    const root = document.documentElement;
    const apply = (data) => {
        if (!isRecord(data)) return;
        const screenWidth = Number(data.screenWidth);
        const screenHeight = Number(data.screenHeight);
        const insetRight = Number(data.insetRight);
        const insetBottom = Number(data.insetBottom);
        if (![screenWidth, screenHeight, insetRight, insetBottom].every(Number.isFinite)) return;
        if (screenWidth < 1 || screenHeight < 1 || screenWidth > 20000 || screenHeight > 20000) return;
        const width = window.innerWidth || screenWidth;
        const height = window.innerHeight || screenHeight;
        // Screen pixels to CSS pixels, capped so a hostile value cannot push
        // overlays off-screen.
        const x = Math.max(0, Math.min(insetRight * (width / screenWidth), width * 0.15));
        const y = Math.max(0, Math.min(insetBottom * (height / screenHeight), height * 0.15));
        root.style.setProperty('--cx-safezone-x', `${Math.round(x)}px`);
        root.style.setProperty('--cx-safezone-y', `${Math.round(y)}px`);
    };
    window.addEventListener('message', (event) => {
        const message = event && isRecord(event.data) ? event.data : null;
        if (message && message.action === 'interaction:layout') apply(message.data);
    });
})();

function normalizeNotificationData(data) {
    if (!isRecord(data)) return null;
    const allowedTypes = new Set(['info', 'inform', 'success', 'warning', 'error']);
    const allowedPositions = new Set(['top', 'top-right', 'top-left', 'bottom', 'bottom-right', 'bottom-left']);
    const rawDuration = Number(data.duration);
    const duration = Number.isFinite(rawDuration) ? Math.max(0, Math.min(rawDuration, 600000)) : 3000;
    const id = boundedText(data.id, '', 128) || null;
    return {
        id,
        explicitId: id !== null && data.explicitId !== false,
        owner: boundedText(data.owner, 'cortex-lib', 96) || 'cortex-lib',
        title: boundedText(data.title, '', 256),
        description: boundedText(data.description, '', 2048),
        duration,
        position: allowedPositions.has(data.position) ? data.position : null,
        type: allowedTypes.has(data.type) ? data.type : 'info',
        showDuration: data.showDuration !== false,
        persistent: data.persistent === true || duration === 0,
        dedupe: data.dedupe !== false,
        plain: data.plain === true,
        hideIcon: data.hideIcon === true || data.icon === false
    };
}

function filterNotificationsForClear(notifications, data) {
    if (!Array.isArray(notifications) || !isRecord(data)) return notifications;
    if (data.all === true) return [];
    const owner = boundedText(data.owner, '', 96);
    if (!owner) return notifications;
    return notifications.filter(notification => notification.owner !== owner);
}

function getNotificationDedupeKey(notification) {
    return `${notification.owner}\u0000${notification.type}\u0000${notification.title}\u0000${notification.description}`;
}

function mergeNotificationState(notifications, normalized, generatedId) {
    const previous = Array.isArray(notifications) ? notifications : [];
    const dedupeKey = getNotificationDedupeKey(normalized);
    const explicitIndex = normalized.explicitId && normalized.id ? previous.findIndex(item => item.id === normalized.id) : -1;
    const dedupeIndex = explicitIndex === -1 && !normalized.explicitId && normalized.dedupe ? previous.findIndex(item => !item.explicitId && item.dedupeKey === dedupeKey) : -1;
    const matchIndex = explicitIndex !== -1 ? explicitIndex : dedupeIndex;
    const existing = matchIndex === -1 ? null : previous[matchIndex];
    const notification = {
        id: existing?.id || normalized.id || generatedId,
        explicitId: normalized.explicitId,
        owner: normalized.owner,
        dedupeKey,
        type: normalized.type,
        title: normalized.title,
        description: normalized.description,
        duration: normalized.duration,
        showDuration: normalized.showDuration,
        persistent: normalized.persistent,
        plain: normalized.plain,
        hideIcon: normalized.hideIcon,
        refreshTick: existing ? (existing.refreshTick || 0) + 1 : 0
    };
    const next = matchIndex === -1 ? [...previous, notification] : previous.map((item, index) => index === matchIndex ? notification : item);
    return next.slice(-NUI_MAX_NOTIFICATIONS);
}

/**
 * Applies the player's visible cap. The newest `limit` notices are shown.
 * Timed notices pushed past the cap leave (a feed, not a queue); persistent
 * notices are held and resurface as space frees, counted by the overflow tag.
 */
function partitionNotifications(notifications, limit) {
    const list = Array.isArray(notifications) ? notifications : [];
    const cap = Number.isInteger(limit) ? Math.max(1, Math.min(limit, NUI_MAX_NOTIFICATIONS)) : 5;
    const hidden = list.slice(0, Math.max(0, list.length - cap));
    return {
        visible: list.slice(-cap),
        held: hidden.filter(item => item.persistent).length,
        dropped: hidden.filter(item => !item.persistent).map(item => item.id)
    };
}

/** Lifetime after the player's duration multiplier (0.5-3), bounded to 30 minutes. */
function scaleNotificationLifetime(duration, multiplier) {
    const base = Number.isFinite(duration) ? Math.max(0, duration) : 0;
    const scale = Number.isFinite(multiplier) ? Math.max(0.5, Math.min(multiplier, 3)) : 1;
    return Math.min(Math.round(base * scale), 1800000);
}

// ============================================================================
// GLYPHS. One open-stroke family, no enclosing circles or triangles; the
// severity rule already carries the colour. Stroke 4 of 24 is 3.7u at 22u.
// ============================================================================

const notifyGlyphPaths = {
    success: ['M4.5 12.8l4.6 4.6L19.5 7'],
    error: ['M6.5 6.5l11 11', 'M17.5 6.5l-11 11'],
    warning: ['M12 4.5v9.5', 'M12 19.4v.1'],
    info: ['M12 10.6v8.9', 'M12 4.9v.1']
};
notifyGlyphPaths.inform = notifyGlyphPaths.info;

function NotifyGlyph({ type }) {
    const paths = notifyGlyphPaths[type] || notifyGlyphPaths.info;
    return React.createElement('svg', { viewBox: '0 0 24 24', focusable: 'false', 'aria-hidden': 'true' },
        paths.map((d, index) => React.createElement('path', { key: index, d })));
}

/** Text with `[E]` tokens as inline keycaps. */
function NotifyText({ text }) {
    const kit = window.CortexKit;
    const parts = kit.parseKeyText(text);
    if (!parts.some(part => part.type === 'key')) return text;
    return parts.map((part, index) => part.type === 'key'
        ? React.createElement(kit.Keycap, { key: index, value: part.value, size: 'sm', className: 'notify-key' })
        : part.value);
}

// ============================================================================
// NOTIFICATION COMPONENT
// ============================================================================

function Notification({ id, type, title, description, duration, showDuration, persistent, plain, hideIcon, onRemove }) {
    const [exiting, setExiting] = useState(false);
    const timeoutRef = useRef(null);
    const removalRef = useRef(null);

    const handleRemove = useCallback(() => {
        if (removalRef.current !== null) return;
        setExiting(true);
        removalRef.current = setTimeout(() => onRemove(id), 160);
    }, [id, onRemove]);

    useEffect(() => {
        if (duration > 0 && !persistent) {
            timeoutRef.current = setTimeout(handleRemove, duration);
        }
        return () => {
            if (removalRef.current !== null) clearTimeout(removalRef.current);
            if (timeoutRef.current) {
                clearTimeout(timeoutRef.current);
            }
        };
    }, [duration, persistent, handleRemove]);

    const notifyType = notifyGlyphPaths[type] ? type : 'info';
    const showLifetime = showDuration !== false && duration > 0 && !persistent;
    const showGlyph = hideIcon !== true;
    // A title-free short line reads as a headline; long copy stays in Arial.
    const headline = !title && description.length > 0 && description.length <= 64 && !description.includes('\n');
    const urgent = notifyType === 'error' || notifyType === 'warning';

    const className = ['notify', notifyType, persistent ? 'persistent' : '', plain ? 'notify-plain' : '',
        headline ? 'notify-headline' : '', showGlyph ? 'has-glyph' : '', exiting ? 'exiting' : ''].filter(Boolean).join(' ');

    return React.createElement('div', {
        className,
        'data-id': id,
        'data-cortex-surface': 'instrument',
        role: urgent ? 'alert' : 'status',
        'aria-live': urgent ? 'assertive' : 'polite',
        'aria-atomic': 'true'
    },
        React.createElement('span', { className: 'notify-rule', 'aria-hidden': 'true' }),
        showGlyph && React.createElement('span', { className: 'notify-icon', 'aria-hidden': 'true' },
            React.createElement(NotifyGlyph, { type: notifyType })),
        React.createElement('div', { className: 'notify-content' },
            title && React.createElement('div', { className: 'notify-title' }, title),
            description && React.createElement('div', { className: 'notify-description' },
                React.createElement(NotifyText, { text: description })),
            showLifetime && React.createElement('span', { className: 'notify-duration', 'aria-hidden': 'true' },
                React.createElement('i', {
                    className: 'notify-duration-fill',
                    style: { animation: `notifyLifetime ${duration}ms linear forwards` }
                }))
        ),
        persistent && React.createElement('button', {
            type: 'button',
            className: 'notify-close',
            'aria-label': 'Dismiss notification',
            onClick: (event) => {
                event.stopPropagation();
                handleRemove();
            }
        }, React.createElement('span', { className: 'notify-close-cap', 'aria-hidden': 'true' },
            React.createElement('svg', { viewBox: '0 0 16 16', focusable: 'false' },
                React.createElement('path', { d: 'M4.5 4.5l7 7M11.5 4.5l-7 7' }))))
    );
}

// ============================================================================
// NOTIFICATION CONTAINER
// ============================================================================

function NotificationContainer({ notifications, position, onRemove }) {
    const prefs = window.CortexKit.usePrefs();
    const { visible, held, dropped } = partitionNotifications(notifications, prefs.notifyLimit);
    const droppedKey = dropped.join('\u0000');

    useEffect(() => {
        if (!droppedKey) return;
        droppedKey.split('\u0000').forEach(id => onRemove(id));
    }, [droppedKey, onRemove]);

    return React.createElement('div', { id: 'notify-container', className: position || 'top-right' },
        held > 0 && React.createElement('div', { className: 'notify-overflow', 'aria-hidden': 'true' }, `+${held} held`),
        visible.map(notif =>
            React.createElement(Notification, {
                key: `${notif.id}-${notif.refreshTick || 0}`,
                ...notif,
                duration: scaleNotificationLifetime(notif.duration, prefs.notifyDuration),
                onRemove
            })
        )
    );
}
