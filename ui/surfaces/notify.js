/* Notifications: frameless status callouts stacked at a screen edge.
 * Signature: an ink coin (the sender's mark, or the severity glyph) beside a
 * display-caps title, lifetime shown as a 4u meter under the text. The Look key
 * lists recent notices under the live ones. The player's duration and limit preferences apply here. */

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
        // Overlays measured from these insets (the help legend) re-measure.
        window.dispatchEvent(new Event('cx-safezone'));
    };
    window.addEventListener('message', (event) => {
        const message = event && isRecord(event.data) ? event.data : null;
        if (message && message.action === 'interaction:layout') apply(message.data);
    });
})();

const NOTIFY_INK_RGB = [15, 16, 18];
const NOTIFY_PAPER_RGB = [240, 240, 233];
const NOTIFY_SENDER_CONTRAST = 4.5;
const NOTIFY_PEEK_ROWS = 5;
const NOTIFY_PEEK_MIN_ROWS = 2;
const NOTIFY_PEEK_COLUMN_ROWS = 9;
const NOTIFY_PEEK_LEAVE_MS = 180;
const allowedNotifyTypes = new Set(['info', 'inform', 'success', 'warning', 'error']);

function parseNotifyHex(value) {
    const match = typeof value === 'string' ? /^#([0-9a-f]{6})$/i.exec(value.trim()) : null;
    if (!match) return null;
    const packed = parseInt(match[1], 16);
    return [(packed >> 16) & 255, (packed >> 8) & 255, packed & 255];
}

function notifyLuminance(rgb) {
    const [r, g, b] = rgb.map(channel => {
        const unit = channel / 255;
        return unit <= 0.03928 ? unit / 12.92 : Math.pow((unit + 0.055) / 1.055, 2.4);
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function notifyContrast(a, b) {
    const lighter = Math.max(notifyLuminance(a), notifyLuminance(b));
    const darker = Math.min(notifyLuminance(a), notifyLuminance(b));
    return (lighter + 0.05) / (darker + 0.05);
}

function readableSenderColor(value) {
    let rgb = parseNotifyHex(value);
    if (!rgb) return null;
    for (let step = 0; step < 12 && notifyContrast(rgb, NOTIFY_INK_RGB) < NOTIFY_SENDER_CONTRAST; step += 1) {
        rgb = rgb.map((channel, index) => Math.round(channel + (NOTIFY_PAPER_RGB[index] - channel) * 0.2));
    }
    return `rgb(${rgb.join(', ')})`;
}

function resolveSenderImage(value) {
    const match = typeof value === 'string' ? /^nui:\/\/([\w-]+)\/([\w\-./]+\.(?:png|svg|webp))$/i.exec(value) : null;
    if (!match || match[2].includes('..')) return null;
    return `https://cfx-nui-${match[1]}/${match[2]}`;
}

function normalizeNotifySender(sender) {
    if (!isRecord(sender)) return null;
    const label = boundedText(sender.label, '', 48).trim();
    if (!label) return null;
    return {
        label,
        color: readableSenderColor(sender.color),
        icon: boundedText(sender.icon, '', 64).trim(),
        image: resolveSenderImage(sender.image)
    };
}

function normalizePeekData(data) {
    if (!isRecord(data) || data.active !== true) return { active: false, entries: [] };
    const entries = (Array.isArray(data.entries) ? data.entries : []).slice(0, 20).filter(isRecord).map(entry => ({
        id: Number.isInteger(entry.id) ? entry.id : 0,
        liveId: boundedText(entry.liveId, '', 128) || null,
        type: allowedNotifyTypes.has(entry.type) ? entry.type : 'info',
        title: boundedText(entry.title, '', 256),
        description: boundedText(entry.description, '', 2048),
        sender: normalizeNotifySender(entry.sender),
        age: Number.isFinite(entry.age) ? Math.max(0, Math.min(entry.age, 86400000)) : 0,
        seen: entry.seen === true
    }));
    return { active: true, entries };
}

function formatNoticeAge(age) {
    const minutes = Math.floor(age / 60000);
    if (minutes < 1) return 'now';
    if (minutes < 60) return `${minutes}m`;
    return `${Math.floor(minutes / 60)}h`;
}

function selectPeekEntries(entries, notifications) {
    const shown = Array.isArray(notifications) ? notifications : [];
    const live = new Set(shown.map(item => item.id));
    const rows = Math.max(NOTIFY_PEEK_MIN_ROWS, Math.min(NOTIFY_PEEK_ROWS, NOTIFY_PEEK_COLUMN_ROWS - shown.length));
    return (Array.isArray(entries) ? entries : [])
        .filter(entry => !entry.liveId || !live.has(entry.liveId))
        .slice(0, rows);
}

function normalizeNotificationData(data) {
    if (!isRecord(data)) return null;
    const allowedTypes = new Set(['info', 'inform', 'success', 'warning', 'error']);
    const allowedPositions = new Set(['right', 'left', 'top', 'top-right', 'top-left', 'bottom', 'bottom-right', 'bottom-left']);
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
        sender: normalizeNotifySender(data.sender),
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
        sender: normalized.sender,
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

// ============================================================================
// HEADING. Every notice leads with a display-caps line. A short title-free
// line is the headline itself; longer title-free copy lends its lead (a
// "Lead: rest" prefix, a short first line or first sentence) to the title, and
// copy with no natural lead is titled by its severity.
// ============================================================================

const NOTIFY_HEADLINE_MAX = 64;
const NOTIFY_LEAD_MAX = 48;
const notifyTypeTitles = { success: 'Done', error: 'Error', warning: 'Warning', info: 'Notice', inform: 'Notice' };

function splitNotificationLead(text) {
    const lines = text.split('\n');
    if (lines.length > 1) {
        const first = lines[0].trim().replace(/[:.]$/, '');
        const rest = lines.slice(1).join('\n').trim();
        if (first.length >= 2 && first.length <= NOTIFY_LEAD_MAX && rest && !/[[\]]/.test(first)) return { title: first, body: rest };
    }
    const colon = /^([^.!?:[\]\n]{3,40}):\s+(\S[\s\S]*)$/.exec(text);
    if (colon) return { title: colon[1].trim(), body: colon[2] };
    const sentence = /^([^.!?[\]\n]{3,47}[.!?])\s+(\S[\s\S]*)$/.exec(text);
    if (sentence) return { title: sentence[1].replace(/\.$/, '').trim(), body: sentence[2] };
    return null;
}

function resolveNotificationHeading(type, title, description) {
    const ownTitle = typeof title === 'string' ? title : '';
    const body = typeof description === 'string' ? description : '';
    if (ownTitle || !body) return { title: ownTitle, description: body, headline: false };
    if (body.length <= NOTIFY_HEADLINE_MAX && !body.includes('\n')) return { title: '', description: body, headline: true };
    const lead = splitNotificationLead(body);
    if (lead) return { title: lead.title, description: lead.body, headline: false };
    return { title: notifyTypeTitles[type] || notifyTypeTitles.info, description: body, headline: false };
}

/** Lifetime after the player's duration multiplier (0.5-3), bounded to 30 minutes. */
function scaleNotificationLifetime(duration, multiplier) {
    const base = Number.isFinite(duration) ? Math.max(0, duration) : 0;
    const scale = Number.isFinite(multiplier) ? Math.max(0.5, Math.min(multiplier, 3)) : 1;
    return Math.min(Math.round(base * scale), 1800000);
}

// ============================================================================
// GLYPHS. One open-stroke family, no enclosing circles or triangles; the ink
// coin carries them in the severity colour. Stroke 4.5 of 24 is 3.1u in the 28u coin.
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

function useNotifyImage(url) {
    const [ready, setReady] = useState(false);
    useEffect(() => {
        setReady(false);
        if (!url) return undefined;
        let live = true;
        const probe = new Image();
        probe.onload = () => { if (live) setReady(true); };
        probe.src = url;
        return () => { live = false; };
    }, [url]);
    return ready;
}

function NotifyCoinMark({ sender, type }) {
    const imageReady = useNotifyImage(sender ? sender.image : null);
    if (!sender) return React.createElement(NotifyGlyph, { type });
    if (imageReady) {
        const mask = `url("${sender.image}")`;
        return React.createElement('span', { className: 'notify-coin-image', style: { WebkitMaskImage: mask, maskImage: mask } });
    }
    const letter = Array.from(sender.label)[0].toUpperCase();
    const resolved = sender.icon && typeof resolveMenuIcon === 'function' ? resolveMenuIcon(sender.icon) : null;
    if (resolved && resolved.type === 'path') {
        return React.createElement('svg', { className: 'notify-coin-path', viewBox: '0 0 20 20', focusable: 'false', 'aria-hidden': 'true' },
            React.createElement('path', { d: resolved.d }));
    }
    const short = resolved && resolved.type === 'text' && /^[\p{L}\p{N}]{1,2}$/u.test(sender.icon);
    return React.createElement('span', { className: 'notify-coin-letter' }, short ? resolved.text : letter);
}

function NoticeCoin({ sender, type }) {
    return React.createElement('span', { className: `notify-coin${sender ? ' is-sender' : ''}`, 'aria-hidden': 'true' },
        React.createElement(NotifyCoinMark, { sender, type }));
}

function senderStyle(sender) {
    return sender && sender.color ? { '--notify-sender': sender.color } : undefined;
}

function resolveNoticeCopy(type, title, description, sender) {
    if (!sender) return { ...resolveNotificationHeading(type, title, description), lead: '' };
    return {
        title: sender.label,
        lead: typeof title === 'string' ? title : '',
        description: typeof description === 'string' ? description : '',
        headline: false
    };
}

function LoggedNotice({ type, title, description, sender, age, seen }) {
    const notifyType = notifyGlyphPaths[type] ? type : 'info';
    const copy = resolveNoticeCopy(notifyType, title, description, sender);
    const ageLabel = React.createElement('span', { className: 'notify-age' }, formatNoticeAge(age));
    const className = ['notify', 'notify-logged', notifyType, 'has-glyph', sender ? 'has-sender' : '',
        copy.headline ? 'notify-headline' : '', seen ? 'is-seen' : ''].filter(Boolean).join(' ');
    return React.createElement('div', { className, style: senderStyle(sender), 'data-cortex-surface': 'instrument' },
        NoticeCoin({ sender, type: notifyType }),
        React.createElement('div', { className: 'notify-content' },
            copy.title && React.createElement('div', { className: 'notify-title' }, copy.title, ageLabel),
            copy.lead && React.createElement('div', { className: 'notify-lead' }, copy.lead),
            copy.description && React.createElement('div', { className: 'notify-description' },
                React.createElement(NotifyText, { text: copy.description }),
                !copy.title && ageLabel)
        )
    );
}

function Notification({ id, type, title, description, sender, duration, showDuration, persistent, plain, hideIcon, onRemove }) {
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
    const showGlyph = hideIcon !== true || Boolean(sender);
    const heading = resolveNoticeCopy(notifyType, title, description, sender);
    const headline = heading.headline;
    const urgent = notifyType === 'error' || notifyType === 'warning';

    const className = ['notify', notifyType, persistent ? 'persistent' : '', plain ? 'notify-plain' : '',
        headline ? 'notify-headline' : '', showGlyph ? 'has-glyph' : '', sender ? 'has-sender' : '', exiting ? 'exiting' : ''].filter(Boolean).join(' ');

    return React.createElement('div', {
        className,
        style: senderStyle(sender),
        'data-id': id,
        'data-cortex-surface': 'instrument',
        role: urgent ? 'alert' : 'status',
        'aria-live': urgent ? 'assertive' : 'polite',
        'aria-atomic': 'true'
    },
        showGlyph && NoticeCoin({ sender, type: notifyType }),
        React.createElement('div', { className: 'notify-content' },
            heading.title && React.createElement('div', { className: 'notify-title' }, heading.title),
            heading.lead && React.createElement('div', { className: 'notify-lead' }, heading.lead),
            heading.description && React.createElement('div', { className: 'notify-description' },
                React.createElement(NotifyText, { text: heading.description })),
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

function NotificationContainer({ notifications, position, onRemove, peek }) {
    const prefs = window.CortexKit.usePrefs();
    const { visible, held, dropped } = partitionNotifications(notifications, prefs.notifyLimit);
    const droppedKey = dropped.join('\u0000');

    useEffect(() => {
        if (!droppedKey) return;
        droppedKey.split('\u0000').forEach(id => onRemove(id));
    }, [droppedKey, onRemove]);

    return React.createElement('div', { className: 'notify-anchor' }, React.createElement('div', { id: 'notify-container', className: position || 'right' },
        held > 0 && React.createElement('div', { className: 'notify-overflow', 'aria-hidden': 'true' }, `+${held} held`),
        visible.map(notif =>
            React.createElement(Notification, {
                key: `${notif.id}-${notif.refreshTick || 0}`,
                ...notif,
                duration: scaleNotificationLifetime(notif.duration, prefs.notifyDuration),
                onRemove
            })
        ),
        peek && peek.entries.length > 0 && React.createElement('div', {
            className: `notify-log${peek.active ? '' : ' exiting'}`,
            'aria-hidden': 'true'
        }, selectPeekEntries(peek.entries, visible).map(entry =>
            React.createElement(LoggedNotice, { key: entry.id, ...entry })))
    ));
}
