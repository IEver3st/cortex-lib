/**
 * Cortex Lib - React UI System
 * Notifications + Progress Bars
 */

const { useState, useEffect, useCallback, useRef } = React;

const NUI_POST_TIMEOUT_MS = 5000;
const NUI_MAX_TEXT_LENGTH = 4096;
const NUI_MAX_CLIPBOARD_LENGTH = 32768;
const NUI_MAX_MENU_OPTIONS = 128;
const NUI_MAX_CONTEXT_FIELDS = 32;
const NUI_MAX_HELP_ITEMS = 16;
const NUI_MAX_NOTIFICATIONS = 12;

function isRecord(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function boundedText(value, fallback = '', maxLength = NUI_MAX_TEXT_LENGTH) {
    if (typeof value === 'string') return value.slice(0, maxLength);
    if (typeof value === 'number' || typeof value === 'boolean') return String(value).slice(0, maxLength);
    return fallback;
}

function normalizeSession(value) {
    if (typeof value === 'string') return value.slice(0, 128);
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    return null;
}

function normalizeRevision(value) {
    return Number.isSafeInteger(value) && value > 0 ? value : null;
}

function isSafeObjectKey(value) {
    return typeof value === 'string'
        && value.length > 0
        && value !== '__proto__'
        && value !== 'prototype'
        && value !== 'constructor';
}

function normalizeScalarValue(value, fallback = '') {
    if (typeof value === 'string' || typeof value === 'boolean') return value;
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    return fallback;
}

function normalizeNuiMessage(event) {
    const message = event && isRecord(event.data) ? event.data : null;
    if (!message || typeof message.action !== 'string' || message.action.length === 0 || message.action.length > 64) {
        return null;
    }

    return {
        action: message.action,
        data: isRecord(message.data) ? message.data : {}
    };
}

function normalizeContextOption(option) {
    if (isRecord(option)) {
        const value = typeof option.value === 'string' || typeof option.value === 'number' || typeof option.value === 'boolean'
            ? option.value
            : '';
        return { value, label: boundedText(option.label, boundedText(value), 160) };
    }
    if (typeof option === 'string' || typeof option === 'number' || typeof option === 'boolean') return option;
    return null;
}

function normalizeContextField(field) {
    if (!isRecord(field)) return null;
    const type = ['checkbox', 'select', 'input', 'text'].includes(field.type) ? field.type : null;
    const name = boundedText(field.name, '', 96);
    if (!type || !isSafeObjectKey(name)) return null;

    return {
        type,
        name,
        label: boundedText(field.label, name, 160),
        description: boundedText(field.description, '', 512),
        placeholder: boundedText(field.placeholder, '', 256),
        inputType: ['text', 'number', 'email', 'password', 'search', 'url'].includes(field.inputType) ? field.inputType : 'text',
        required: field.required === true,
        icon: boundedText(field.icon, '', 32),
        options: Array.isArray(field.options)
            ? field.options.slice(0, 64).map(normalizeContextOption).filter(option => option !== null)
            : []
    };
}

function normalizeHelpItems(items) {
    if (!Array.isArray(items)) return [];
    return items.slice(0, NUI_MAX_HELP_ITEMS).map(item => {
        if (!isRecord(item)) return null;
        const value = boundedText(item.value, '', 128);
        if (!value) return null;
        return { label: boundedText(item.label, '', 160), value };
    }).filter(Boolean);
}

function normalizeIconColor(value) {
    const color = boundedText(value, '', 64).trim();
    return /^(?:var\(--[a-z0-9-]+\)|#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8}))$/i.test(color)
        ? color
        : null;
}

function normalizeRadialItems(items) {
    if (!Array.isArray(items)) return [];
    return items.slice(0, NUI_MAX_MENU_OPTIONS).map((item, index) => {
        if (!isRecord(item)) return null;
        return {
            id: boundedText(item.id, `item-${index + 1}`, 96),
            label: boundedText(item.label, '', 160),
            icon: boundedText(item.icon, '•', 32),
            iconColor: normalizeIconColor(item.iconColor)
        };
    }).filter(Boolean);
}

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

function normalizeProgressData(data) {
    if (!isRecord(data)) return null;
    const rawDuration = Number(data.duration);
    const position = data.position === 'center' ? 'middle' : data.position;
    return {
        duration: Number.isFinite(rawDuration) ? Math.max(0, Math.min(rawDuration, 600000)) : 0,
        label: boundedText(data.label, '', 256),
        position: ['top', 'middle', 'bottom'].includes(position) ? position : 'bottom',
        style: data.style === 'circle' ? 'circle' : 'bar',
        canCancel: data.canCancel === true
    };
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
    return tabs.slice(0, 32).map((tab, index) => {
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
            fields,
            values,
            defaults
        };
    }).filter(Boolean);
}

function normalizeWeatherBounds(bounds) {
    if (!isRecord(bounds)) return WEATHER_DEFAULT_BOUNDS;
    const next = {
        minX: Number(bounds.minX),
        maxX: Number(bounds.maxX),
        minY: Number(bounds.minY),
        maxY: Number(bounds.maxY)
    };
    if (!Object.values(next).every(Number.isFinite) || next.maxX <= next.minX || next.maxY <= next.minY) {
        return WEATHER_DEFAULT_BOUNDS;
    }
    return next;
}

function normalizeAlertStyle(style) {
    if (!isRecord(style)) return undefined;
    const normalized = {};
    const colorValue = String.raw`(?:var\(--[a-z0-9-]+\)|#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8}))`;
    const colorPattern = new RegExp(`^${colorValue}$`, 'i');
    const borderPattern = new RegExp(`^(?:[0-3](?:\\.\\d+)?|4(?:\\.0+)?)px\\s+(?:solid|dashed)\\s+${colorValue}$`, 'i');

    for (const key of ['backgroundColor', 'borderColor', 'color']) {
        const value = boundedText(style[key], '', 96).trim();
        if (colorPattern.test(value)) normalized[key] = value;
    }

    const border = boundedText(style.border, '', 128).trim();
    if (borderPattern.test(border)) normalized.border = border;
    return Object.keys(normalized).length ? normalized : undefined;
}

async function copyTextToClipboard(value) {
    const text = boundedText(value, '', NUI_MAX_CLIPBOARD_LENGTH);

    if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
        try {
            await navigator.clipboard.writeText(text);
            return true;
        } catch (_) {
            // Fall through to the CEF-compatible textarea path.
        }
    }

    const textarea = document.createElement('textarea');
    const previousFocus = document.activeElement;
    textarea.value = text;
    textarea.setAttribute('readonly', '');
    textarea.setAttribute('aria-hidden', 'true');
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    textarea.style.opacity = '0';
    document.body.appendChild(textarea);

    try {
        textarea.focus();
        textarea.select();
        return typeof document.execCommand === 'function' && document.execCommand('copy') === true;
    } catch (_) {
        return false;
    } finally {
        textarea.remove();
        if (previousFocus && typeof previousFocus.focus === 'function') {
            focusElement(previousFocus);
        }
    }
}

async function nuiPost(name, payload, options = {}) {
    const route = boundedText(name, '', 96);
    if (!/^[a-z0-9:_-]+$/i.test(route)) {
        return { ok: false, error: 'invalid_route' };
    }

    let timeout = null;
    let externalSignal = null;
    let abortFromExternal = null;
    let externallyAborted = false;
    let timedOut = false;

    try {
        const timeoutMs = Number.isFinite(options.timeoutMs)
            ? Math.max(250, Math.min(options.timeoutMs, 15000))
            : NUI_POST_TIMEOUT_MS;
        const controller = typeof AbortController === 'function' ? new AbortController() : null;
        externalSignal = options.signal;
        externallyAborted = externalSignal?.aborted === true;
        const timeoutResult = Symbol('nui-timeout');
        abortFromExternal = () => {
            externallyAborted = true;
            controller?.abort();
        };
        if (externalSignal?.aborted) {
            abortFromExternal();
            return { ok: false, error: 'aborted' };
        }
        externalSignal?.addEventListener?.('abort', abortFromExternal, { once: true });
        const timeoutPromise = new Promise(resolve => {
            timeout = window.setTimeout(() => {
                timedOut = true;
                controller?.abort();
                resolve(timeoutResult);
            }, timeoutMs);
        });

        const requestPromise = (async () => {
            const response = await fetch(`https://${GetParentResourceName()}/${route}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(isRecord(payload) ? payload : {}),
                signal: controller?.signal
            });
            if (!response.ok) return { type: 'http_error', status: response.status };
            const result = await response.json().catch(error => {
                if (timedOut || error?.name === 'AbortError') throw error;
                return null;
            });
            return { type: 'success', result };
        })();
        const outcome = await Promise.race([requestPromise, timeoutPromise]);
        if (outcome === timeoutResult) return { ok: false, error: 'timeout' };
        if (outcome.type === 'http_error') return { ok: false, error: 'http_error', status: outcome.status };
        return isRecord(outcome.result) ? outcome.result : { ok: true, result: outcome.result };
    } catch (error) {
        uiDebugLog('nui post failed', route, error);
        if (timedOut) return { ok: false, error: 'timeout' };
        if (externallyAborted || error?.name === 'AbortError') return { ok: false, error: 'aborted' };
        return { ok: false, error: 'network_error' };
    } finally {
        try { if (timeout !== null) window.clearTimeout(timeout); } catch (_) { /* no-op */ }
        try { externalSignal?.removeEventListener?.('abort', abortFromExternal); } catch (_) { /* no-op */ }
    }
}

function getFocusableElements(container) {
    if (!container) return [];
    return Array.from(container.querySelectorAll(
        'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [href], [tabindex]:not([tabindex="-1"])'
    )).filter(element => element.getAttribute('aria-hidden') !== 'true');
}

function focusElement(element) {
    if (!element || typeof element.focus !== 'function') return false;
    try {
        element.focus({ preventScroll: true });
        return true;
    } catch (_) {
        try {
            element.focus();
            return true;
        } catch (_) {
            return false;
        }
    }
}

function useModalFocus(open, dialogRef, onEscape, focusKey = null) {
    const escapeRef = useRef(onEscape);
    escapeRef.current = onEscape;

    useEffect(() => {
        if (!open) return;

        const previousFocus = document.activeElement;
        const focusFrame = window.requestAnimationFrame(() => {
            const dialog = dialogRef.current;
            if (!dialog) return;
            const autofocusTarget = dialog.querySelector('[data-autofocus="true"]');
            const firstFocusable = getFocusableElements(dialog)[0];
            focusElement(autofocusTarget || firstFocusable || dialog);
        });

        const handleKeyDown = (event) => {
            if (event.key === 'Escape' && typeof escapeRef.current === 'function') {
                event.preventDefault();
                escapeRef.current();
                return;
            }

            if (event.key !== 'Tab') return;
            const dialog = dialogRef.current;
            const focusable = getFocusableElements(dialog);
            if (focusable.length === 0) {
                event.preventDefault();
                focusElement(dialog);
                return;
            }

            const first = focusable[0];
            const last = focusable[focusable.length - 1];
            if (event.shiftKey && document.activeElement === first) {
                event.preventDefault();
                focusElement(last);
            } else if (!event.shiftKey && document.activeElement === last) {
                event.preventDefault();
                focusElement(first);
            }
        };

        document.addEventListener('keydown', handleKeyDown);
        return () => {
            window.cancelAnimationFrame(focusFrame);
            document.removeEventListener('keydown', handleKeyDown);
            if (previousFocus && document.contains(previousFocus) && typeof previousFocus.focus === 'function') {
                focusElement(previousFocus);
            }
        };
    }, [open, dialogRef, focusKey]);
}

// ============================================================================
// WEATHER ZONE EDITOR APP
// ============================================================================

const WEATHER_EDITOR_APP_ID = 'weatherzonesEditor';
const WEATHER_EDITOR_MAP_URL = 'https://cfx-nui-es_weatherzones/assets/atlasmap.png';
const WEATHER_EDITOR_MAP_SIZE = 2048;

const WEATHER_DEFAULT_BOUNDS = {
    minX: -4700,
    maxX: 4600,
    minY: -4870,
    maxY: 8600
};

function WeatherZoneEditorApp({ appState, setUiApps }) {
    const open = appState && appState.open;
    const payload = appState && isRecord(appState.payload) ? appState.payload : {};
    const session = normalizeSession(appState?.session);

    const [zones, setZones] = useState([]);
    const [selectedId, setSelectedId] = useState(null);
    const [view, setView] = useState({ x: 0, y: 0, scale: 1 });
    const [status, setStatus] = useState(null);
    const [drawMode, setDrawMode] = useState(false);

    const minScaleRef = useRef(1);
    const openedRef = useRef(false);
    const editorRef = useRef(null);

    const requestedMapSize = Number(payload.mapSize);
    const editorMapSize = Number.isFinite(requestedMapSize)
        ? Math.max(256, Math.min(requestedMapSize, 8192))
        : WEATHER_EDITOR_MAP_SIZE;
    const [calibration, setCalibration] = useState({
        active: false,
        stage: 'idle',
        anchor: null,
        point: null
    });

    const lastPayloadRef = useRef(null);

    useEffect(() => {
        if (!open) {
            openedRef.current = false;
            return;
        }

        if (payload && payload.zones && payload !== lastPayloadRef.current) {
            const incoming = Array.isArray(payload.zones) ? payload.zones : [];
            const normalizedZones = incoming.slice(0, 256).map(normalizeZone).filter(Boolean);
            setZones(normalizedZones);
            setSelectedId(normalizedZones[0]?.id || null);
            lastPayloadRef.current = payload;
        }

        if (open) {
            const scale = Math.max(0.1, WEATHER_EDITOR_MAP_SIZE / editorMapSize);
            minScaleRef.current = scale;
            setView(prev => ({ ...prev, scale: Math.max(prev.scale, scale) }));
        }

        if (!openedRef.current) {
            openedRef.current = true;
            setView(prev => ({ ...prev, scale: Math.max(prev.scale, minScaleRef.current || 1) }));
        }
    }, [editorMapSize, open, payload]);

    const closeEditor = useCallback(async () => {
        const response = await nuiPost('cortex:uiEvent', { appId: WEATHER_EDITOR_APP_ID, type: 'close', session });
        if (response?.ok !== true) return;
        setUiApps(prev => prev[WEATHER_EDITOR_APP_ID]?.session === normalizeSession(session) ? ({
            ...prev,
            [WEATHER_EDITOR_APP_ID]: { ...prev[WEATHER_EDITOR_APP_ID], open: false }
        }) : prev);
    }, [session, setUiApps]);

    useModalFocus(Boolean(open), editorRef, null, session);

    const sendEvent = useCallback(async (type, eventPayload) => {
        return nuiPost('cortex:uiEvent', {
            appId: WEATHER_EDITOR_APP_ID,
            type: boundedText(type, '', 64),
            payload: isRecord(eventPayload) ? eventPayload : {},
            session
        });
    }, [session]);

    const selectZone = useCallback((zoneId) => {
        setSelectedId(zoneId);
        // Disable draw mode when switching zones to prevent accidents
        setDrawMode(false);
    }, []);

    const addPointToZone = useCallback((zoneId, point) => {
        setZones(prev => prev.map(zone => {
            if (zone.id !== zoneId) return zone;
            return { ...zone, points: [...zone.points, point] };
        }));
    }, []);

    const removePointFromZone = useCallback((zoneId, index) => {
        setZones(prev => prev.map(zone => {
            if (zone.id !== zoneId) return zone;
            return { ...zone, points: zone.points.filter((_, idx) => idx !== index) };
        }));
    }, []);

    const undoLastPoint = useCallback((zoneId) => {
        setZones(prev => prev.map(zone => {
            if (zone.id !== zoneId) return zone;
            if (zone.points.length === 0) return zone;
            return { ...zone, points: zone.points.slice(0, -1) };
        }));
    }, []);

    const clearPoints = useCallback((zoneId) => {
        setZones(prev => prev.map(zone => {
            if (zone.id !== zoneId) return zone;
            return { ...zone, points: [] };
        }));
    }, []);

    const updateZone = useCallback((zoneId, patch) => {
        setZones(prev => prev.map(zone => {
            if (zone.id !== zoneId) return zone;
            return { ...zone, ...patch };
        }));
    }, []);

    // Declare bounds and mapSize BEFORE they are used in addZone callback
    const bounds = normalizeWeatherBounds(payload.bounds);
    const mapSize = editorMapSize;

    const centerOnZone = useCallback((zone) => {
        if (!zone || !zone.points || zone.points.length === 0) return;

        // Calculate centroid of zone points
        let sumX = 0, sumY = 0;
        for (const pt of zone.points) {
            sumX += pt.x;
            sumY += pt.y;
        }
        const centroidX = sumX / zone.points.length;
        const centroidY = sumY / zone.points.length;

        // Convert world coords to map coords
        const mapX = ((centroidX - bounds.minX) / (bounds.maxX - bounds.minX)) * mapSize;
        const mapY = (1 - (centroidY - bounds.minY) / (bounds.maxY - bounds.minY)) * mapSize;

        // Calculate zone size to determine zoom
        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        for (const pt of zone.points) {
            if (pt.x < minX) minX = pt.x;
            if (pt.x > maxX) maxX = pt.x;
            if (pt.y < minY) minY = pt.y;
            if (pt.y > maxY) maxY = pt.y;
        }
        const zoneWidth = ((maxX - minX) / (bounds.maxX - bounds.minX)) * mapSize;
        const zoneHeight = ((maxY - minY) / (bounds.maxY - bounds.minY)) * mapSize;
        const zoneDim = Math.max(zoneWidth, zoneHeight, 100);

        // Set scale to fit zone with some padding (aim for zone to be ~40% of viewport)
        const mapViewport = document.querySelector('.cortex-editor-map')?.getBoundingClientRect();
        const viewportWidth = Math.max(1, mapViewport?.width || window.innerWidth);
        const viewportHeight = Math.max(1, mapViewport?.height || (window.innerHeight - 48));
        const viewportSize = Math.min(viewportWidth, viewportHeight);
        const targetScale = Math.min(2.5, Math.max(0.5, (viewportSize * 0.4) / zoneDim));

        // Center the view
        const viewportCenterX = viewportWidth / 2;
        const viewportCenterY = viewportHeight / 2;

        setView({
            x: viewportCenterX - (mapX * targetScale),
            y: viewportCenterY - (mapY * targetScale),
            scale: targetScale
        });
    }, [bounds, mapSize]);

    const addZone = useCallback(() => {
        const center = {
            x: (bounds.minX + bounds.maxX) / 2,
            y: (bounds.minY + bounds.maxY) / 2
        };
        const size = (bounds.maxX - bounds.minX) * 0.02;
        const newZone = {
            id: `zone_${Date.now()}`,
            label: 'New Zone',
            mode: 'dynamic',
            weather: 'CLEAR',
            weathers: ['CLEAR', 'CLOUDS'],
            intervalMinutes: 10,
            thickness: 200,
            points: [
                { x: center.x - size, y: center.y - size, z: 0 },
                { x: center.x + size, y: center.y - size, z: 0 },
                { x: center.x + size, y: center.y + size, z: 0 },
                { x: center.x - size, y: center.y + size, z: 0 }
            ]
        };

        setZones(prev => [...prev, newZone]);
        setSelectedId(newZone.id);
        setDrawMode(true);
        // Defer centering slightly to ensure state update has processed/zone exists in context if needed
        // But since we pass the object directly, it should be fine.
        setTimeout(() => centerOnZone(newZone), 50);
    }, [bounds, centerOnZone]);

    const removeZone = useCallback((zoneId) => {
        setZones(prev => prev.filter(zone => zone.id !== zoneId));
        setSelectedId(prev => (prev === zoneId ? null : prev));
        if (selectedId === zoneId) setDrawMode(false);
    }, [selectedId]);

    const saveZones = useCallback(async () => {
        setStatus('Saving...');
        const res = await sendEvent('save', { zones });
        if (res && res.ok) {
            setStatus('Saved');
            setTimeout(() => setStatus(null), 1200);
        } else {
            setStatus('Save failed');
            setTimeout(() => setStatus(null), 2000);
        }
    }, [sendEvent, zones]);

    const zoomIn = useCallback(() => {
        setView(prev => ({ ...prev, scale: Math.min(3, prev.scale + 0.2) }));
    }, []);

    const zoomOut = useCallback(() => {
        const minScale = minScaleRef.current || 0.1;
        setView(prev => ({ ...prev, scale: Math.max(minScale, prev.scale - 0.2) }));
    }, []);

    const startCalibration = useCallback(() => {
        setCalibration({ active: true, stage: 'pickAnchor', anchor: null, point: null });
        setStatus('Calibration active - follow instructions on map');
    }, []);

    const setCalibrationAnchor = useCallback(async (anchorPayload) => {
        setCalibration({
            active: true,
            stage: 'pickPoint',
            anchor: { map: anchorPayload, world: null },
            point: null
        });
        setStatus('Anchor A placed - now place anchor B');

        const res = await sendEvent('getPlayerCoords', {});
        if (!res || !res.ok || !res.coords) {
            const reason = res && res.error ? res.error : 'no_coords';
            setStatus(`Calibration failed: ${reason}`);
            setTimeout(() => setStatus(null), 2500);
            setCalibration({ active: false, stage: 'idle', anchor: null, point: null });
            return;
        }

        setCalibration(prev => ({
            ...prev,
            anchor: { map: anchorPayload, world: res.coords }
        }));
    }, [sendEvent]);

    const finishCalibration = useCallback(async (pointPayload) => {
        if (!calibration.anchor) return;

        setCalibration(prev => ({
            ...prev,
            point: { map: pointPayload, world: null }
        }));

        const res = await sendEvent('getPlayerCoords', {});
        if (!res || !res.ok || !res.coords) {
            const reason = res && res.error ? res.error : 'no_coords';
            setStatus(`Calibration failed: ${reason}`);
            setTimeout(() => setStatus(null), 2500);
            setCalibration({ active: false, stage: 'idle', anchor: null, point: null });
            return;
        }

        const boundsRes = await sendEvent('saveBounds', {
            map: {
                a: calibration.anchor.map,
                b: pointPayload
            },
            world: {
                a: calibration.anchor.world || res.coords,
                b: res.coords
            },
            mapSize: editorMapSize
        });

        if (boundsRes && boundsRes.ok) {
            setStatus('Calibration saved');
            setTimeout(() => setStatus(null), 1500);
        } else {
            const reason = boundsRes && boundsRes.error ? boundsRes.error : 'invalid_bounds';
            setStatus(`Calibration failed: ${reason}`);
            setTimeout(() => setStatus(null), 2500);
        }

        setCalibration({ active: false, stage: 'idle', anchor: null, point: null });
    }, [calibration.anchor, sendEvent]);


    const autoCalibrate = useCallback(async () => {
        setStatus('Auto-calibrating...');
        const res = await sendEvent('autoCalibrate', {});
        if (res && res.ok) {
            setStatus('Calibration complete');
            setTimeout(() => setStatus(null), 1500);
        } else {
            const reason = res && res.error ? res.error : 'unknown';
            setStatus(`Calibration failed: ${reason}`);
            setTimeout(() => setStatus(null), 2500);
        }
    }, [sendEvent]);


    useEffect(() => {
        if (!open) return;
        const onKeyDown = (event) => {
            if (event.key === 'Escape') {
                if (calibration.active) {
                    setCalibration({ active: false, stage: 'idle', anchor: null, point: null });
                    setStatus(null);
                    return;
                }
                if (drawMode) {
                    setDrawMode(false);
                    return;
                }
                closeEditor();
            }
        };
        window.addEventListener('keydown', onKeyDown);
        return () => window.removeEventListener('keydown', onKeyDown);
    }, [open, closeEditor, calibration.active, drawMode]);

    if (!open) return null;

    return React.createElement('div', {
        ref: editorRef,
        className: 'cortex-editor-root',
        role: 'dialog',
        'aria-modal': true,
        'aria-label': 'Cortex weather zone editor',
        tabIndex: -1
    },
        React.createElement(EditorToolbar, { onSave: saveZones, onClose: closeEditor, onCalibrate: autoCalibrate, onZoomIn: zoomIn, onZoomOut: zoomOut, status }),
        React.createElement('div', { className: 'cortex-editor-workspace' },
            React.createElement(EditorSidebar, {
                zones,
                selectedId,
                onSelect: selectZone,
                onUpdate: updateZone,
                onDelete: removeZone,
                onCenter: centerOnZone,
                onAdd: addZone,
                drawMode,
                setDrawMode,
                onUndo: undoLastPoint,
                onClearPoints: clearPoints,
                bounds,
                mapSize,
                view
            }),
            React.createElement(EditorMap, {
                zones,
                selectedId,
                onSelect: selectZone,
                onUpdate: updateZone,
                onAddPoint: addPointToZone,
                onRemovePoint: removePointFromZone,
                onCalibrateAnchor: setCalibrationAnchor,
                onCalibratePoint: finishCalibration,
                calibration,
                onCancelCalibration: () => {
                    setCalibration({ active: false, stage: 'idle', anchor: null, point: null });
                    setStatus(null);
                },
                view,
                setView,
                minScaleRef,
                bounds,
                mapUrl: boundedText(payload.mapUrl, '', 512) || undefined,
                mapSize,
                drawMode
            })

        )
    );
}

function normalizeZone(zone) {
    if (!isRecord(zone)) return null;
    const points = Array.isArray(zone.points) ? zone.points.slice(0, 1024).map((point) => {
        const source = isRecord(point) || Array.isArray(point) ? point : null;
        if (!source) return null;
        const x = typeof source.x === 'number' ? source.x : source[0];
        const y = typeof source.y === 'number' ? source.y : source[1];
        const z = typeof source.z === 'number' ? source.z : source[2];
        if (!Number.isFinite(x) || !Number.isFinite(y)) return null;
        return { x, y, z: Number.isFinite(z) ? z : 0 };
    }).filter(Boolean) : [];

    const id = boundedText(zone.id, '', 96);
    if (!id) return null;

    return {
        id,
        label: boundedText(zone.label, id || 'Zone', 160),
        mode: zone.mode === 'fixed' ? 'fixed' : 'dynamic',
        weather: boundedText(zone.weather, 'CLEAR', 64),
        weathers: Array.isArray(zone.weathers)
            ? zone.weathers.slice(0, 64).map(value => boundedText(value, '', 64)).filter(Boolean)
            : (zone.weather ? [boundedText(zone.weather, 'CLEAR', 64)] : []),
        intervalMinutes: zone.intervalMinutes || 10,
        thickness: zone.thickness || 200,
        points
    };
}

function EditorToolbar({ onSave, onClose, onCalibrate, onZoomIn, onZoomOut, status }) {
    return React.createElement('div', { className: 'cortex-editor-toolbar' },
        React.createElement('div', { className: 'cortex-editor-title' },
            React.createElement('span', { style: { color: 'var(--cortex-accent)' } }, 'CORTEX'),
            ' WEATHER'
        ),
        React.createElement('div', { className: 'cortex-editor-spacer' }),
        status ? React.createElement('div', { className: 'cortex-editor-status', role: 'status', 'aria-live': 'polite' }, status) : null,
        React.createElement('div', { className: 'cortex-editor-actions' },
            React.createElement('button', { className: 'cortex-editor-btn calibrate', onClick: onCalibrate }, 'Auto-Calibrate'),
            React.createElement('button', { className: 'cortex-editor-btn primary', onClick: onSave }, 'Save Changes'),
            React.createElement('div', { className: 'cortex-toolbar-divider' }),
            React.createElement('div', { className: 'cortex-editor-zoom-controls' },
                React.createElement('button', { className: 'cortex-editor-btn icon', onClick: onZoomOut, title: 'Zoom Out' }, '−'),
                React.createElement('button', { className: 'cortex-editor-btn icon', onClick: onZoomIn, title: 'Zoom In' }, '+')
            ),
            React.createElement('button', { className: 'cortex-editor-btn ghost icon', onClick: onClose, 'aria-label': 'Close weather editor' }, '✕')
        )
    );
}

function EditorSidebar({ zones, selectedId, onSelect, onUpdate, onDelete, onCenter, onAdd, drawMode, setDrawMode, onUndo, onClearPoints, bounds, mapSize, view }) {
    const selected = zones.find(zone => zone.id === selectedId);
    const [tab, setTab] = useState('config'); // 'config' | 'points' | 'debug'

    // Reset tab when selection changes
    useEffect(() => {
        setTab('config');
    }, [selectedId]);

    return React.createElement('div', { className: 'cortex-editor-sidebar' },
        React.createElement('div', { className: 'cortex-sidebar-header' },
            React.createElement('div', { className: 'cortex-sidebar-title' }, 'ZONES'),
            React.createElement('button', { className: 'cortex-editor-btn full-width primary', onClick: onAdd }, '+ NEW ZONE')
        ),
        React.createElement('div', { className: 'cortex-zone-list' },
            zones.map(zone => React.createElement('div', {
                key: zone.id,
                className: `cortex-zone-item${zone.id === selectedId ? ' active' : ''}`
            },
                React.createElement('button', {
                    type: 'button',
                    className: 'cortex-zone-info cortex-zone-select',
                    'aria-pressed': zone.id === selectedId,
                    onClick: () => onSelect(zone.id)
                },
                    React.createElement('span', { className: 'cortex-zone-name' }, zone.label || zone.id),
                    React.createElement('span', { className: 'cortex-zone-meta' }, zone.mode === 'fixed' ? zone.weather : `${zone.weathers.length} weathers`)
                ),
                React.createElement('button', {
                    className: 'cortex-zone-delete',
                    'aria-label': `Delete ${boundedText(zone.label, zone.id, 96)}`,
                    onClick: (e) => {
                        e.stopPropagation();
                        // eslint-disable-next-line no-restricted-globals
                        if (confirm('Delete zone?')) onDelete(zone.id);
                    }
                }, '×')
            ))
        ),
        selected ? React.createElement('div', { className: 'cortex-selected-panel' },
            React.createElement('div', { className: 'cortex-panel-header' },
                React.createElement('div', { className: 'cortex-panel-title' }, selected.label || 'Unnamed Zone'),
                React.createElement('button', { className: 'cortex-icon-btn', onClick: () => onCenter && onCenter(selected), title: 'Center Map' }, '⌖')
            ),
            React.createElement('div', { className: 'cortex-draw-actions' },
                React.createElement('button', {
                    className: `cortex-editor-btn small ${drawMode ? 'primary' : ''}`,
                    onClick: () => setDrawMode(!drawMode),
                    title: 'Toggle Draw Mode'
                }, drawMode ? 'FINISH DRAWING' : 'DRAW POINTS'),
                drawMode && React.createElement(React.Fragment, null,
                    React.createElement('button', {
                        className: 'cortex-editor-btn small ghost',
                        onClick: () => onUndo(selected.id),
                        disabled: selected.points.length === 0,
                        title: 'Undo last point'
                    }, 'UNDO'),
                    React.createElement('button', {
                        className: 'cortex-editor-btn small ghost',
                        onClick: () => onClearPoints(selected.id),
                        disabled: selected.points.length === 0,
                        title: 'Clear all points'
                    }, 'CLEAR')
                )
            ),
            React.createElement('div', { className: 'cortex-panel-tabs', role: 'tablist', 'aria-label': 'Zone editor sections' },
                ['config', 'points', 'debug'].map((tabId, index, tabIds) => React.createElement('button', {
                    key: tabId,
                    id: `cortex-zone-tab-${tabId}`,
                    className: `cortex-tab ${tab === tabId ? 'active' : ''}`,
                    role: 'tab',
                    'aria-selected': tab === tabId,
                    'aria-controls': 'cortex-zone-tabpanel',
                    tabIndex: tab === tabId ? 0 : -1,
                    onClick: () => setTab(tabId),
                    onKeyDown: event => {
                        const direction = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
                        if (!direction) return;
                        event.preventDefault();
                        const nextTab = tabIds[(index + direction + tabIds.length) % tabIds.length];
                        setTab(nextTab);
                        window.requestAnimationFrame(() => document.getElementById(`cortex-zone-tab-${nextTab}`)?.focus());
                    }
                }, tabId.toUpperCase()))
            ),
            React.createElement('div', {
                id: 'cortex-zone-tabpanel',
                className: 'cortex-panel-content',
                role: 'tabpanel',
                'aria-labelledby': `cortex-zone-tab-${tab}`
            },
                tab === 'config'
                    ? React.createElement(ZoneConfigForm, { selected, onUpdate })
                    : tab === 'points'
                        ? React.createElement(ZonePointsList, { selected })
                        : React.createElement(ZoneDebugView, { selected, bounds, mapSize, view })
            )
        ) : React.createElement('div', { className: 'cortex-empty-state' },
            React.createElement('span', null, 'Select a zone to edit'),
            React.createElement(EditorHelp, null)
        )
    );
}

function ZoneDebugView({ selected, bounds, mapSize, view }) {
    if (!selected) return null;

    const toMapCoords = (point) => {
        if (!bounds || !mapSize) return { x: 0, y: 0 };
        return {
            x: ((point.x - bounds.minX) / (bounds.maxX - bounds.minX)) * mapSize,
            y: (1 - (point.y - bounds.minY) / (bounds.maxY - bounds.minY)) * mapSize
        };
    };

    const modeText = String(selected.mode || 'unknown');
    const weatherText = modeText === 'fixed'
        ? String(selected.weather || '')
        : (Array.isArray(selected.weathers) ? selected.weathers.join(', ') : '');

    return React.createElement('div', { className: 'cortex-debug-view' },
        React.createElement('div', { className: 'cortex-debug-section' },
            React.createElement('div', { className: 'cortex-debug-section-title' }, 'ZONE'),
            React.createElement('div', { className: 'cortex-debug-grid' },
                React.createElement('span', { className: 'cortex-debug-key' }, 'ID:'),
                React.createElement('span', { className: 'cortex-debug-val' }, selected.id),
                React.createElement('span', { className: 'cortex-debug-key' }, 'Label:'),
                React.createElement('span', { className: 'cortex-debug-val' }, selected.label),
                React.createElement('span', { className: 'cortex-debug-key' }, 'Mode:'),
                React.createElement('span', { className: 'cortex-debug-val' }, modeText),
                React.createElement('span', { className: 'cortex-debug-key' }, modeText === 'fixed' ? 'Weather:' : 'Weathers:'),
                React.createElement('span', { className: 'cortex-debug-val' }, weatherText),
                modeText === 'dynamic' ? React.createElement(React.Fragment, null,
                    React.createElement('span', { className: 'cortex-debug-key' }, 'Interval:'),
                    React.createElement('span', { className: 'cortex-debug-val' }, `${Number(selected.intervalMinutes || 0)}m`)
                ) : null,
                React.createElement('span', { className: 'cortex-debug-key' }, 'Thickness:'),
                React.createElement('span', { className: 'cortex-debug-val' }, String(selected.thickness || 0)),
                React.createElement('span', { className: 'cortex-debug-key' }, 'Points:'),
                React.createElement('span', { className: 'cortex-debug-val' }, String(selected.points.length))
            )
        ),
        React.createElement('div', { className: 'cortex-debug-section' },
            React.createElement('div', { className: 'cortex-debug-section-title' }, 'MAP / VIEW'),
            React.createElement('div', { className: 'cortex-debug-grid' },
                React.createElement('span', { className: 'cortex-debug-key' }, 'Bounds X:'),
                React.createElement('span', { className: 'cortex-debug-val' }, bounds ? `${bounds.minX.toFixed(0)}..${bounds.maxX.toFixed(0)}` : 'n/a'),
                React.createElement('span', { className: 'cortex-debug-key' }, 'Bounds Y:'),
                React.createElement('span', { className: 'cortex-debug-val' }, bounds ? `${bounds.minY.toFixed(0)}..${bounds.maxY.toFixed(0)}` : 'n/a'),
                React.createElement('span', { className: 'cortex-debug-key' }, 'MapSize:'),
                React.createElement('span', { className: 'cortex-debug-val' }, String(mapSize)),
                React.createElement('span', { className: 'cortex-debug-key' }, 'Zoom:'),
                React.createElement('span', { className: 'cortex-debug-val' }, view.scale.toFixed(2)),
                React.createElement('span', { className: 'cortex-debug-key' }, 'Pan:'),
                React.createElement('span', { className: 'cortex-debug-val' }, `${view.x.toFixed(0)}, ${view.y.toFixed(0)}`)
            )
        ),
        React.createElement('div', { className: 'cortex-point-table-container' },
            React.createElement('table', { className: 'cortex-point-table' },
                React.createElement('thead', null,
                    React.createElement('tr', null,
                        React.createElement('th', null, '#'),
                        React.createElement('th', null, 'WX'),
                        React.createElement('th', null, 'WY'),
                        React.createElement('th', null, 'WZ'),
                        React.createElement('th', null, 'MX'),
                        React.createElement('th', null, 'MY')
                    )
                ),
                React.createElement('tbody', null,
                    selected.points.map((pt, i) => {
                        const mapPt = toMapCoords(pt);
                        const wz = typeof pt.z === 'number' ? pt.z : 0;
                        return React.createElement('tr', { key: i },
                            React.createElement('td', null, i + 1),
                            React.createElement('td', null, pt.x.toFixed(2)),
                            React.createElement('td', null, pt.y.toFixed(2)),
                            React.createElement('td', null, Number(wz).toFixed(2)),
                            React.createElement('td', { style: { color: 'var(--cortex-info)' } }, mapPt.x.toFixed(1)),
                            React.createElement('td', { style: { color: 'var(--cortex-info)' } }, mapPt.y.toFixed(1))
                        );
                    })
                )
            )
        )
    );
}

function ZoneConfigForm({ selected, onUpdate }) {
    return React.createElement(React.Fragment, null,
        React.createElement(EditorField, {
            label: 'Label',
            value: selected.label,
            onChange: (value) => onUpdate(selected.id, { label: value })
        }),
        React.createElement(EditorSelect, {
            label: 'Mode',
            value: selected.mode,
            options: ['fixed', 'dynamic'],
            onChange: (value) => onUpdate(selected.id, { mode: value })
        }),
        selected.mode === 'fixed' ? React.createElement(EditorField, {
            label: 'Weather',
            value: selected.weather,
            onChange: (value) => onUpdate(selected.id, { weather: value })
        }) : React.createElement(EditorField, {
            label: 'Weathers (comma)',
            value: selected.weathers.join(', '),
            onChange: (value) => onUpdate(selected.id, { weathers: value.split(',').map(s => s.trim()).filter(Boolean) })
        }),
        selected.mode === 'dynamic' ? React.createElement(EditorField, {
            label: 'Interval (mins)',
            value: String(selected.intervalMinutes),
            onChange: (value) => onUpdate(selected.id, { intervalMinutes: Number(value) || 1 })
        }) : null,
        React.createElement(EditorField, {
            label: 'Thickness',
            value: String(selected.thickness),
            onChange: (value) => onUpdate(selected.id, { thickness: Number(value) || 1 })
        }),
        React.createElement(EditorField, {
            label: 'ID',
            value: selected.id,
            readOnly: true
        })
    );
}

function ZonePointsList({ selected }) {
    return React.createElement('div', { className: 'cortex-points-list' },
        React.createElement('div', { className: 'cortex-points-header' },
            React.createElement('span', null, '#'),
            React.createElement('span', null, 'X'),
            React.createElement('span', null, 'Y')
        ),
        selected.points.map((pt, i) => React.createElement('div', { key: i, className: 'cortex-point-row' },
            React.createElement('span', { className: 'cortex-point-index' }, i + 1),
            React.createElement('span', { className: 'cortex-point-val' }, pt.x.toFixed(1)),
            React.createElement('span', { className: 'cortex-point-val' }, pt.y.toFixed(1))
        ))
    );
}

let editorFieldIdCounter = 0;

function EditorField({ label, value, onChange, readOnly }) {
    const inputIdRef = useRef(`cortex-editor-field-${++editorFieldIdCounter}`);
    return React.createElement('div', { className: 'cortex-editor-group' },
        React.createElement('label', { className: 'cortex-editor-label', htmlFor: inputIdRef.current }, label),
        React.createElement('input', {
            id: inputIdRef.current,
            className: 'cortex-editor-input',
            value: value,
            readOnly: !!readOnly,
            onChange: onChange ? (e) => onChange(e.target.value) : undefined
        })
    );
}

function EditorSelect({ label, value, options, onChange }) {
    const labelIdRef = useRef(`cortex-editor-select-${++editorFieldIdCounter}`);
    return React.createElement('div', { className: 'cortex-editor-group' },
        React.createElement('div', { id: labelIdRef.current, className: 'cortex-editor-label' }, label),
        React.createElement('div', { className: 'cortex-editor-select', role: 'group', 'aria-labelledby': labelIdRef.current },
            options.map(option => React.createElement('button', {
                key: option,
                className: `cortex-editor-pill${option === value ? ' active' : ''}`,
                'aria-pressed': option === value,
                onClick: () => onChange(option)
            }, option))
        )
    );
}

function EditorHelp() {
    return React.createElement('div', { className: 'cortex-editor-help' },
        React.createElement('div', { className: 'cortex-editor-label' }, 'MAP CONTROLS'),
        React.createElement('div', { className: 'cortex-editor-help-line' }, React.createElement('strong', null, 'Draw Mode:'), ' Click map to add points'),
        React.createElement('div', { className: 'cortex-editor-help-line' }, 'Right-click point: remove'),
        React.createElement('div', { className: 'cortex-editor-help-line' }, 'Drag points: move'),
        React.createElement('div', { className: 'cortex-editor-help-line' }, 'Scroll: zoom, drag map: pan'),
        React.createElement('div', { className: 'cortex-editor-help-line' }, React.createElement('strong', null, 'Calibrate:'), ' Links map to game world. Stand in-game, then click corresponding spot on map (2 points needed).')
    );
}

function CalibrationOverlay({ calibration, onCancel }) {
    if (!calibration || !calibration.active) return null;

    const isPickAnchor = calibration.stage === 'pickAnchor';
    const isPickPoint = calibration.stage === 'pickPoint';

    const title = isPickAnchor ? 'STEP 1: Place Anchor A' : 'STEP 2: Place Anchor B';
    const instruction = isPickAnchor
        ? 'Stand at your first reference point in-game, then CLICK that location on this map.'
        : 'Move to your second reference point in-game, then CLICK that location on this map.';

    return React.createElement('div', { className: 'cortex-calibration-overlay' },
        React.createElement('div', { className: 'cortex-calibration-box' },
            React.createElement('div', { className: 'cortex-calibration-title' }, title),
            React.createElement('div', { className: 'cortex-calibration-instruction' }, instruction),
            React.createElement('div', { className: 'cortex-calibration-hint' },
                isPickAnchor
                    ? 'Tip: Choose two points far apart for best accuracy (e.g., opposite corners of the map)'
                    : 'Anchor A is marked. Now place Anchor B at a different location.'
            ),
            React.createElement('button', {
                className: 'cortex-calibration-cancel',
                onClick: onCancel
            }, 'Cancel (ESC)')
        )
    );
}

function EditorMap({ zones, selectedId, onSelect, onUpdate, onAddPoint, onRemovePoint, onCalibrateAnchor, onCalibratePoint, calibration, onCancelCalibration, view, setView, minScaleRef, bounds, mapUrl, mapSize, drawMode }) {
    const mapRef = useRef(null);
    const containerRef = useRef(null);
    const draggingRef = useRef(null);

    const imageUrl = mapUrl || WEATHER_EDITOR_MAP_URL;

    const toMapCoords = useCallback((point) => {
        return {
            x: ((point.x - bounds.minX) / (bounds.maxX - bounds.minX)) * mapSize,
            y: (1 - (point.y - bounds.minY) / (bounds.maxY - bounds.minY)) * mapSize,
            z: point.z || 0
        };
    }, [bounds, mapSize]);

    const toWorldCoords = useCallback((x, y) => {
        const worldX = bounds.minX + (x / mapSize) * (bounds.maxX - bounds.minX);
        const worldY = bounds.minY + ((mapSize - y) / mapSize) * (bounds.maxY - bounds.minY);
        return { x: worldX, y: worldY };
    }, [bounds, mapSize]);

    const handleWheel = useCallback((event) => {
        event.preventDefault();
        const delta = event.deltaY * -0.001;
        const minScale = (minScaleRef && minScaleRef.current) || 0.1;
        const oldScale = view.scale;
        const nextScale = Math.max(minScale, Math.min(3, oldScale + delta));

        if (nextScale === oldScale) return;

        // Get cursor position relative to the map container
        const rect = event.currentTarget.getBoundingClientRect();
        const cursorX = event.clientX - rect.left;
        const cursorY = event.clientY - rect.top;

        // Calculate the point on the map that's under the cursor
        const mapPointX = (cursorX - view.x) / oldScale;
        const mapPointY = (cursorY - view.y) / oldScale;

        // Calculate new view position to keep the same map point under cursor
        const newX = cursorX - (mapPointX * nextScale);
        const newY = cursorY - (mapPointY * nextScale);

        setView({ x: newX, y: newY, scale: nextScale });
    }, [setView, view.scale, view.x, view.y, minScaleRef]);

    const handlePointerDown = useCallback((event, type, payload) => {
        event.preventDefault();
        event.stopPropagation();
        draggingRef.current = {
            type: type,
            payload: payload,
            startX: event.clientX,
            startY: event.clientY,
            baseX: view.x,
            baseY: view.y
        };
    }, [view.x, view.y]);

    const handleMapPointerDown = useCallback((event) => {
        if (event.button !== 0) return;
        if (event.target !== event.currentTarget) return;
        handlePointerDown(event, 'pan');
    }, [handlePointerDown]);

    const handlePointerMove = useCallback((event) => {
        if (!draggingRef.current) return;

        if (draggingRef.current.type === 'pan') {
            const dx = event.clientX - draggingRef.current.startX;
            const dy = event.clientY - draggingRef.current.startY;
            setView(prev => ({ ...prev, x: draggingRef.current.baseX + dx, y: draggingRef.current.baseY + dy }));
            return;
        }

        if (draggingRef.current.type === 'point') {
            if (!mapRef.current) return;
            const rect = mapRef.current.getBoundingClientRect();
            const localX = (event.clientX - rect.left - view.x) / view.scale;
            const localY = (event.clientY - rect.top - view.y) / view.scale;
            const clampedX = Math.max(0, Math.min(mapSize, localX));
            const clampedY = Math.max(0, Math.min(mapSize, localY));

            const world = toWorldCoords(clampedX, clampedY);
            const target = draggingRef.current.payload;
            const targetZone = zones.find(z => z.id === target.zoneId);
            if (!targetZone) return;

            onUpdate(target.zoneId, {
                points: targetZone.points.map((pt, idx) => {
                    if (idx !== target.index) return pt;
                    return { x: world.x, y: world.y, z: pt.z || 0 };
                })
            });
        }
    }, [mapSize, onUpdate, toWorldCoords, view.scale, view.x, view.y, zones]);

    const handlePointerUp = useCallback(() => {
        draggingRef.current = null;
    }, []);

    useEffect(() => {
        window.addEventListener('pointermove', handlePointerMove);
        window.addEventListener('pointerup', handlePointerUp);
        return () => {
            window.removeEventListener('pointermove', handlePointerMove);
            window.removeEventListener('pointerup', handlePointerUp);
        };
    }, [handlePointerMove, handlePointerUp]);

    // Attach wheel listener with passive: false to allow preventDefault
    useEffect(() => {
        const container = containerRef.current;
        if (!container) return;

        container.addEventListener('wheel', handleWheel, { passive: false });
        return () => {
            container.removeEventListener('wheel', handleWheel);
        };
    }, [handleWheel]);

    const handleMapKeyDown = useCallback((event) => {
        const panStep = event.shiftKey ? 80 : 24;
        if (event.key === 'ArrowLeft' || event.key === 'ArrowRight' || event.key === 'ArrowUp' || event.key === 'ArrowDown') {
            event.preventDefault();
            setView(prev => ({
                ...prev,
                x: prev.x + (event.key === 'ArrowLeft' ? panStep : event.key === 'ArrowRight' ? -panStep : 0),
                y: prev.y + (event.key === 'ArrowUp' ? panStep : event.key === 'ArrowDown' ? -panStep : 0)
            }));
            return;
        }

        if (event.key === '+' || event.key === '=' || event.key === '-') {
            event.preventDefault();
            const minScale = minScaleRef?.current || 0.1;
            const direction = event.key === '-' ? -0.1 : 0.1;
            setView(prev => ({ ...prev, scale: Math.max(minScale, Math.min(3, prev.scale + direction)) }));
            return;
        }

        if (event.key === 'Escape' && calibration?.active) {
            event.preventDefault();
            onCancelCalibration();
            return;
        }

        if (event.key !== 'Enter') return;
        const container = containerRef.current;
        if (!container) return;
        const rect = container.getBoundingClientRect();
        const mapX = Math.max(0, Math.min(mapSize, ((rect.width / 2) - view.x) / view.scale));
        const mapY = Math.max(0, Math.min(mapSize, ((rect.height / 2) - view.y) / view.scale));
        if (calibration?.active) {
            event.preventDefault();
            if (calibration.stage === 'pickAnchor') onCalibrateAnchor({ x: mapX, y: mapY });
            else if (calibration.stage === 'pickPoint') onCalibratePoint({ x: mapX, y: mapY });
        } else if (selectedId && drawMode) {
            event.preventDefault();
            const world = toWorldCoords(mapX, mapY);
            onAddPoint(selectedId, { x: world.x, y: world.y, z: 0 });
        }
    }, [calibration, drawMode, mapSize, minScaleRef, onAddPoint, onCalibrateAnchor, onCalibratePoint, onCancelCalibration, selectedId, setView, toWorldCoords, view.scale, view.x, view.y]);

    return React.createElement('div', {
        ref: containerRef,
        className: `cortex-editor-map${calibration && calibration.active ? ' calibrating' : ''}${drawMode ? ' drawing' : ''}`,
        role: 'application',
        tabIndex: 0,
        'aria-label': 'Weather zone map',
        'aria-describedby': 'cortex-editor-map-help',
        onKeyDown: handleMapKeyDown,
        onPointerDown: handleMapPointerDown,
        onContextMenu: (event) => event.preventDefault()
    },
        React.createElement('div', { id: 'cortex-editor-map-help', className: 'cortex-sr-only' }, 'Use arrow keys to pan, plus or minus to zoom, and Enter to place the current point at the map center.'),
        drawMode && React.createElement('div', { className: 'cortex-draw-indicator' }, 'DRAW MODE ACTIVE'),
        React.createElement('div', {
            className: 'cortex-map-transform-layer',
            ref: mapRef,
            style: {
                width: `${mapSize}px`,
                height: `${mapSize}px`,
                transform: `translate(${view.x}px, ${view.y}px) scale(${view.scale})`
            }
        },
            React.createElement('img', {
                src: imageUrl,
                className: 'cortex-map-image',
                alt: '',
                'aria-hidden': 'true',
                draggable: false,
                width: mapSize,
                height: mapSize
            }),
            React.createElement('svg', {
                className: 'cortex-map-svg',
                viewBox: `0 0 ${mapSize} ${mapSize}`,
                onPointerDown: (event) => {
                    if (event.button !== 0) return;
                    if (event.target !== event.currentTarget) return;

                    const rect = mapRef.current.getBoundingClientRect();
                    const localX = (event.clientX - rect.left - view.x) / view.scale;
                    const localY = (event.clientY - rect.top - view.y) / view.scale;
                    const clampedX = Math.max(0, Math.min(mapSize, localX));
                    const clampedY = Math.max(0, Math.min(mapSize, localY));

                    if (calibration && calibration.active) {
                        const mapPoint = { x: clampedX, y: clampedY };
                        if (calibration.stage === 'pickAnchor') {
                            onCalibrateAnchor(mapPoint);
                        } else if (calibration.stage === 'pickPoint') {
                            onCalibratePoint(mapPoint);
                        }
                        return;
                    }

                    if (!selectedId || !drawMode) return;
                    const world = toWorldCoords(clampedX, clampedY);
                    onAddPoint(selectedId, { x: world.x, y: world.y, z: 0 });
                }
            },
                zones.map(zone => {
                    const isSelected = zone.id === selectedId;
                    const points = zone.points.map(pt => toMapCoords(pt));
                    const polygonPoints = points.map(pt => `${pt.x},${pt.y}`).join(' ');
                    return React.createElement(React.Fragment, { key: zone.id },
                        React.createElement('polygon', {
                            className: `zone-poly${isSelected ? ' selected' : ''}`,
                            points: polygonPoints,
                            onPointerDown: (event) => {
                                event.stopPropagation();
                                onSelect(zone.id);
                            }
                        }),
                        isSelected && points.map((pt, idx) => React.createElement('circle', {
                            key: `${zone.id}:${idx}`,
                            className: 'zone-handle',
                            cx: pt.x,
                            cy: pt.y,
                            r: 5,
                            onPointerDown: (event) => handlePointerDown(event, 'point', { zoneId: zone.id, index: idx }),
                            onContextMenu: (event) => {
                                event.preventDefault();
                                onRemovePoint(zone.id, idx);
                            }
                        }))
                    );
                }),
                calibration && calibration.anchor && calibration.anchor.map
                    ? React.createElement(React.Fragment, null,
                        React.createElement('circle', {
                            className: 'calibration-anchor',
                            cx: calibration.anchor.map.x,
                            cy: calibration.anchor.map.y,
                            r: 10
                        }),
                        React.createElement('text', {
                            className: 'calibration-label',
                            x: calibration.anchor.map.x + 12,
                            y: calibration.anchor.map.y + 4
                        }, 'A')
                    )
                    : null
            ) // end svg
        ), // end transform-layer
        calibration && calibration.active
            ? React.createElement(CalibrationOverlay, { calibration, onCancel: onCancelCalibration })
            : null
    ); // end outer div
}

// ============================================================================
// RESOLUTION SCALING
// ============================================================================

function clamp(n, min, max) {
    return Math.max(min, Math.min(max, n));
}

function getUiScale() {
    // FiveM/NUI renders at actual screen pixel size.
    // Use 1080p height as baseline, clamped up to 4K.
    const h = window.innerHeight || 1080;
    const normalized = h / 1080;
    return clamp(normalized, 1, 2);
}

function getSettingsUiScale() {
    const h = window.innerHeight || 1080;
    // Keep the compact low-resolution floor, but grow with the viewport through 4K.
    return clamp(h / 1080, 0.86, 2);
}

function applyUiScale(value) {
    document.documentElement.style.setProperty('--cortex-ui-scale', value);
    document.documentElement.style.setProperty('--cortex-settings-scale', getSettingsUiScale());
}

applyUiScale(getUiScale());
window.addEventListener('resize', () => applyUiScale(getUiScale()));

// ============================================================================
// DEBUG UTILITIES
// ============================================================================

const debugParams = new URLSearchParams(window.location.search);
const uiDebugEnabled = debugParams.get('debug') === '1' || debugParams.get('debug') === 'true';

function uiDebugLog(...args) {
    if (!uiDebugEnabled) return;
    // eslint-disable-next-line no-console
    console.log('[cortex-lib/ui]', ...args);
}

function safeJson(value) {
    try {
        const seen = new WeakSet();
        let nodes = 0;
        const normalize = (current, depth) => {
            if (current === null) return null;
            if (typeof current === 'string') return current.slice(0, 2048);
            if (typeof current === 'number') return Number.isFinite(current) ? current : String(current);
            if (typeof current === 'boolean') return current;
            if (typeof current !== 'object') return boundedText(String(current), '', 256);
            if (depth >= 6 || nodes >= 512) return '[truncated]';
            if (seen.has(current)) return '[circular]';
            seen.add(current);
            nodes += 1;
            if (Array.isArray(current)) return current.slice(0, 64).map(item => normalize(item, depth + 1));
            const result = {};
            for (const key of Object.keys(current).slice(0, 64)) {
                if (!isSafeObjectKey(key)) continue;
                result[key] = normalize(current[key], depth + 1);
            }
            return result;
        };
        return JSON.stringify(normalize(value, 0)).slice(0, 16384);
    } catch (e) {
        return '[unserializable]';
    }
}

if (uiDebugEnabled) {
    window.__cortex = window.__cortex || {};
    window.__cortex.debug = {
        enabled: true,
        push(action, data) {
            window.postMessage({ action, data }, '*');
        },
        notify(data) {
            window.postMessage({ action: 'notify', data }, '*');
        },
        clear() {
            window.postMessage({ action: 'clearNotifications', data: { all: true } }, '*');
        },
        hide(id) {
            window.postMessage({ action: 'hideNotify', data: { id } }, '*');
        },
        progressStart(data) {
            window.postMessage({ action: 'progressStart', data }, '*');
        },
        progressEnd() {
            window.postMessage({ action: 'progressEnd' }, '*');
        },
        alertDialog(data) {
            window.postMessage({ action: 'alertDialog', data }, '*');
        },
        textUIShow(data) {
            window.postMessage({ action: 'textUIShow', data }, '*');
        },
        textUIHide() {
            window.postMessage({ action: 'textUIHide' }, '*');
        }
    };

    uiDebugLog('Debug enabled. Try in console:', 'window.__cortex.debug.menu()', 'window.__cortex.debug.notify({ description: "Hello" })');
}

// ============================================================================
// ICONS
// ============================================================================

const icons = {
    success: React.createElement('svg', { viewBox: '0 0 24 24', width: 16, height: 16, fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
        React.createElement('path', { d: 'M20 6L9 17l-5-5' })
    ),
    error: React.createElement('svg', { viewBox: '0 0 24 24', width: 16, height: 16, fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
        React.createElement('circle', { cx: 12, cy: 12, r: 10 }),
        React.createElement('path', { d: 'M15 9l-6 6M9 9l6 6' })
    ),
    warning: React.createElement('svg', { viewBox: '0 0 24 24', width: 16, height: 16, fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
        React.createElement('path', { d: 'M12 9v4M12 17h.01' }),
        React.createElement('path', { d: 'M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z' })
    ),
    info: React.createElement('svg', { viewBox: '0 0 24 24', width: 16, height: 16, fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
        React.createElement('circle', { cx: 12, cy: 12, r: 10 }),
        React.createElement('path', { d: 'M12 16v-4M12 8h.01' })
    )
};

icons.inform = icons.info;

// ============================================================================
// NOTIFICATION COMPONENT
// ============================================================================

function Notification({ id, type, title, description, duration, showDuration, persistent, plain, hideIcon, onRemove }) {
    const [exiting, setExiting] = useState(false);
    const timeoutRef = useRef(null);

    const handleRemove = useCallback(() => {
        setExiting(true);
        setTimeout(() => onRemove(id), 150);
    }, [id, onRemove]);

    useEffect(() => {
        if (duration > 0 && !persistent) {
            timeoutRef.current = setTimeout(handleRemove, duration);
        }
        return () => {
            if (timeoutRef.current) {
                clearTimeout(timeoutRef.current);
            }
        };
    }, [duration, persistent, handleRemove]);

    const notifyType = type || 'info';
    const icon = icons[notifyType] || icons.info;
    const showBar = showDuration !== false && duration > 0;
    const showIcon = hideIcon !== true;

    const className = `notify ${notifyType}${persistent ? ' persistent' : ''}${plain ? ' notify-plain' : ''}${exiting ? ' exiting' : ''}`;

    const urgent = notifyType === 'error' || notifyType === 'warning';

    return React.createElement('div', {
        className,
        'data-id': id,
        role: urgent ? 'alert' : 'status',
        'aria-live': urgent ? 'assertive' : 'polite',
        'aria-atomic': 'true'
    },
        showIcon && React.createElement('div', { className: 'notify-icon' }, icon),
        React.createElement('div', { className: 'notify-content' },
            title && React.createElement('div', { className: 'notify-title' }, title),
            description && React.createElement('div', { className: 'notify-description' }, description)
        ),
        persistent && React.createElement('button', {
            className: 'notify-close',
            'aria-label': 'Close',
            onClick: (e) => {
                e.stopPropagation();
                handleRemove();
            }
        }, '\u00D7'),
        showBar && React.createElement('div', {
            className: 'notify-duration',
            'aria-hidden': 'true',
            style: { animation: `shrink ${duration}ms linear forwards` }
        })
    );
}

// ============================================================================
// NOTIFICATION CONTAINER
// ============================================================================

function NotificationContainer({ notifications, position, onRemove }) {
    return React.createElement('div', { id: 'notify-container', className: position || 'top-right' },
        notifications.map(notif =>
            React.createElement(Notification, {
                key: `${notif.id}-${notif.refreshTick || 0}`,
                ...notif,
                onRemove
            })
        )
    );
}

// ============================================================================
// DEBUG PANEL
// ============================================================================

function DebugPanelLine({ line }) {
    if (typeof line === 'string') {
        return React.createElement('div', { className: 'cortex-debug-line' }, line);
    }

    const label = line?.label;
    let value = line?.value;

    if (value == null) value = '';
    if (typeof value === 'object') value = safeJson(value);

    return React.createElement('div', { className: 'cortex-debug-line' },
        React.createElement('span', { className: 'cortex-debug-label' }, label || ''),
        React.createElement('span', { className: 'cortex-debug-value', style: line?.color ? { color: line.color } : undefined }, String(value))
    );
}

function DebugPanel({ open, title, subtitle, position, lines, data }) {
    if (!open) return null;

    const rootClass = `cortex-debug-root ${position || 'top-right'}`;
    const hasData = data && typeof data === 'object';

    return React.createElement('div', { className: rootClass },
        React.createElement('div', { className: 'cortex-debug-panel' },
            React.createElement('div', { className: 'cortex-debug-header' },
                React.createElement('div', { className: 'cortex-debug-title' }, title || 'DEBUG'),
                subtitle ? React.createElement('div', { className: 'cortex-debug-subtitle' }, subtitle) : null
            ),
            React.createElement('div', { className: 'cortex-debug-body' },
                Array.isArray(lines)
                    ? lines.map((line, idx) => React.createElement(DebugPanelLine, { key: idx, line }))
                    : null,
                hasData ? React.createElement('pre', { className: 'cortex-debug-json' }, safeJson(data)) : null
            )
        )
    );
}

// ============================================================================
// PROGRESS BAR COMPONENT
// ============================================================================

function ProgressBar({ active, duration, label, position, style, canCancel }) {
    const [progressPct, setProgressPct] = useState(0);
    const rafRef = useRef(null);
    const activeRef = useRef(false);

    useEffect(() => {
        activeRef.current = Boolean(active);

        if (rafRef.current) {
            cancelAnimationFrame(rafRef.current);
            rafRef.current = null;
        }

        if (!active) {
            setProgressPct(0);
            return;
        }

        if (!duration || duration <= 0) {
            setProgressPct(100);
            return;
        }

        const start = performance.now();
        setProgressPct(0);

        const step = (now) => {
            if (!activeRef.current) return;
            const t = Math.min(1, (now - start) / duration);
            setProgressPct(t * 100);
            if (t < 1) {
                rafRef.current = requestAnimationFrame(step);
            }
        };

        rafRef.current = requestAnimationFrame(step);

        return () => {
            activeRef.current = false;
            if (rafRef.current) {
                cancelAnimationFrame(rafRef.current);
                rafRef.current = null;
            }
        };
    }, [active, duration]);

    const containerClass = `progress-container ${position || 'bottom'}${active ? ' active' : ''}`;
    const effectiveStyle = style || 'bar';

    const showCircle = effectiveStyle === 'circle';
    const showBar = !showCircle;

    const pctClamped = Math.max(0, Math.min(100, progressPct));
    const pctText = `${Math.round(pctClamped)}%`;
    const pctSmooth = `${pctClamped}%`;

    const barStyle = { width: pctSmooth };

    const circleR = 45;
    const circleC = 2 * Math.PI * circleR;
    const circleOffset = circleC * (1 - (pctClamped / 100));

    return React.createElement('div', { id: 'progress-container', className: containerClass, 'aria-hidden': !active },
        React.createElement('div', {
            className: 'progress-wrapper',
            role: 'progressbar',
            'aria-label': label || 'Progress',
            'aria-valuemin': 0,
            'aria-valuemax': 100,
            'aria-valuenow': Math.round(pctClamped)
        },
            showBar && React.createElement('div', { className: 'progress-track' },
                React.createElement('div', {
                    id: 'progress-bar',
                    className: 'progress-fill',
                    style: barStyle
                })
            ),
            showCircle && React.createElement('div', { className: 'progress-circle' },
                React.createElement('svg', {
                    className: 'progress-circle-svg',
                    viewBox: '0 0 100 100'
                },
                    React.createElement('circle', {
                        className: 'progress-circle-track',
                        cx: 50,
                        cy: 50,
                        r: circleR
                    }),
                    React.createElement('circle', {
                        className: 'progress-circle-fill',
                        cx: 50,
                        cy: 50,
                        r: circleR,
                        style: {
                            strokeDasharray: circleC,
                            strokeDashoffset: circleOffset
                        }
                    })
                ),
                React.createElement('div', { className: 'progress-circle-center' }),
                React.createElement('div', { className: 'progress-circle-text' }, pctText)
            ),
            React.createElement('div', { id: 'progress-label', className: 'progress-label', role: 'status', 'aria-live': 'polite' }, label || ''),
            React.createElement('div', {
                id: 'progress-cancel',
                className: 'progress-cancel',
                style: { display: canCancel ? 'block' : 'none' }
            }, 'Backspace to cancel')
        )
    );
}

// ============================================================================
// TEXT UI COMPONENT
// ============================================================================

const textUiIcons = {
    hand: React.createElement('svg', { viewBox: '0 0 24 24', width: 16, height: 16, fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
        React.createElement('path', { d: 'M7 11V7a2 2 0 114 0v4' }),
        React.createElement('path', { d: 'M11 11V5a2 2 0 114 0v6' }),
        React.createElement('path', { d: 'M15 11V6a2 2 0 114 0v8a6 6 0 01-6 6H9a6 6 0 01-6-6V9a2 2 0 114 0v2' })
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

function TextUI({ open, text, position, icon, style, backdrop }) {
    if (!open) return null;

    const iconEl = icon ? (textUiIcons[icon] || null) : null;
    const className = `textui ${position || 'bottom-center'}${iconEl ? ' has-icon' : ''}${backdrop ? ' textui-backdrop' : ''}`;
    const { outer: outerStyle } = partitionTextUiStyle(style, Boolean(backdrop));

    return React.createElement('div', {
        id: 'textui',
        className,
        style: outerStyle,
        role: 'status',
        'aria-live': 'polite',
        'aria-atomic': 'true'
    },
        iconEl && React.createElement('div', { className: 'textui-icon' }, iconEl),
        React.createElement('div', { className: 'textui-text' }, text)
    );
}

// ============================================================================
// MENU COMPONENT
// ============================================================================

const menuKeyMap = {
    up: ['ArrowUp'],
    down: ['ArrowDown'],
    left: ['ArrowLeft'],
    right: ['ArrowRight'],
    select: ['Enter'],
    toggle: [' '],
    back: ['Escape', 'Backspace']
};

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
        progress: Number.isFinite(option.progress) ? option.progress : null,
        values,
        hasValues,
        checked: hasCheck ? option.checked : null,
        hasCheck,
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

function Menu({ open, id, session, revision, title, subtitle, position, canClose, disableInput, options, selected, tooltip, setMenu }) {
    const bodyRef = useRef(null);
    const dialogRef = useRef(null);
    const optionsRef = useRef([]);
    const selectedRef = useRef(1);

    useModalFocus(open, dialogRef, null, session);

    useEffect(() => {
        optionsRef.current = options;
        selectedRef.current = selected;
    }, [options, selected]);


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
        if (!opt || !opt.hasValues) return;

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
        if (!opt || !opt.hasCheck) return;

        const nextChecked = !opt.checked;
        const nextOption = { ...opt, checked: nextChecked };
        opts[idx] = nextOption;

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
    }, [id, revision, session, setMenu]);

    const submit = useCallback(async (selectedOverride) => {
        const opts = optionsRef.current;
        const selectedIndex = Number.isInteger(selectedOverride) ? selectedOverride : selectedRef.current;
        const idx = selectedIndex - 1;
        const opt = opts[idx];
        if (!opt) return;

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
    }, [id, revision, session, setMenu]);

    useEffect(() => {
        const handleKeyDown = (e) => {
            if (!open) return;

            const key = e.key;

            if (menuKeyMap.up.includes(key)) {
                e.preventDefault();
                setSelectedIndex(selectedRef.current - 1);
                return;
            }

            if (menuKeyMap.down.includes(key)) {
                e.preventDefault();
                setSelectedIndex(selectedRef.current + 1);
                return;
            }

            if (menuKeyMap.left.includes(key)) {
                e.preventDefault();
                doSideScroll(-1);
                return;
            }

            if (menuKeyMap.right.includes(key)) {
                e.preventDefault();
                doSideScroll(1);
                return;
            }

            if (menuKeyMap.select.includes(key)) {
                e.preventDefault();
                submit();
                return;
            }

            if (menuKeyMap.toggle.includes(key)) {
                e.preventDefault();
                toggleCheck();
                return;
            }

            if (menuKeyMap.back.includes(key)) {
                e.preventDefault();
                closeMenu(key);
            }
        };

        window.addEventListener('keydown', handleKeyDown, { passive: false });
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [open, setSelectedIndex, doSideScroll, submit, toggleCheck, closeMenu]);

    // Best-effort controller support via key events synthesized by browser
    // (FiveM usually routes gamepad as keyboard for NUI focus).

    useEffect(() => {
        if (!open) return;
        if (!bodyRef.current) return;

        const body = bodyRef.current;
        const active = body.querySelector('.cortex-menu-option.active');
        if (!active) return;

        if (document.activeElement !== active) active.focus({ preventScroll: true });

        const bodyRect = body.getBoundingClientRect();
        const activeRect = active.getBoundingClientRect();

        const outTop = activeRect.top < bodyRect.top;
        const outBottom = activeRect.bottom > bodyRect.bottom;

        if (outTop || outBottom) {
            active.scrollIntoView({ block: 'nearest' });
        }
    }, [id, open, options.length, selected, session]);

    if (!open) return null;

    const rootClass = `cortex-menu-root ${position || 'top-left'}${disableInput ? ' input-disabled' : ''}`;
    const hasIcons = options.some(option => Boolean(option.icon));


    return React.createElement('div', {
        className: rootClass,
        onMouseDown: (e) => {
            if (e.target === e.currentTarget) {
                closeMenu('Escape');
            }
        }
    },
        React.createElement('div', {
            ref: dialogRef,
            className: 'cortex-menu',
            role: 'dialog',
            'aria-modal': true,
            'aria-labelledby': 'cortex-menu-title'
        },
            React.createElement('div', { className: 'cortex-menu-header' },
                React.createElement('div', { id: 'cortex-menu-title', className: 'cortex-menu-title' }, title || ''),
                subtitle ? React.createElement('div', { className: 'cortex-menu-subtitle' }, subtitle) : null
            ),
            React.createElement('div', { className: 'cortex-menu-body', ref: bodyRef, role: 'listbox', 'aria-label': title || 'Menu options' },
                options.map((opt, i) => {
                    const optionIndex = i + 1;
                    const active = optionIndex === selected;
                    const value = opt.hasValues ? opt.values[(opt.scrollIndex || 1) - 1] : null;
                    const valueLabel = value ? getValueLabel(value) : '';

                    const rightBadge = opt.hasCheck
                        ? (opt.checked ? 'ON' : 'OFF')
                        : (opt.hasValues ? valueLabel : '');

                    return React.createElement('button', {
                        key: `${id || 'menu'}:${optionIndex}:${opt.label}`,
                        type: 'button',
                        className: `cortex-menu-option${active ? ' active' : ''}`,
                        role: 'option',
                        'aria-selected': active,
                        'aria-label': rightBadge ? `${opt.label}, ${rightBadge}` : opt.label,
                        tabIndex: active ? 0 : -1,
                        onFocus: () => setSelectedIndex(optionIndex),
                        onMouseEnter: () => setSelectedIndex(optionIndex),
                        onMouseDown: (e) => { e.preventDefault(); e.stopPropagation(); },
                        onClick: (e) => {
                            e.preventDefault();
                            e.stopPropagation();
                            setSelectedIndex(optionIndex);
                            submit(optionIndex);
                        }
                    },
                        hasIcons ? React.createElement('span', {
                            className: 'cortex-menu-option-icon',
                            style: opt.iconColor ? { '--cortex-menu-icon-color': opt.iconColor } : undefined,
                            'aria-hidden': 'true'
                        }, opt.icon || '') : null,
                        React.createElement('div', { className: 'cortex-menu-option-main' },
                            React.createElement('div', { className: 'cortex-menu-option-label' }, opt.label),
                            opt.progress != null ? React.createElement('div', { className: 'cortex-menu-option-progress' },
                                React.createElement('div', {
                                    className: 'cortex-menu-option-progressFill',
                                    style: { width: `${Math.max(0, Math.min(100, opt.progress))}%` }
                                })
                            ) : null
                        ),
                        rightBadge ? React.createElement('div', { className: 'cortex-menu-option-badge' }, rightBadge) : null
                    );
                })
            ),
            React.createElement('div', { className: 'cortex-menu-footer' },
                React.createElement('div', { className: 'cortex-menu-tooltip' }, tooltip || ''),
                React.createElement('div', { className: 'cortex-menu-hints' },
                    React.createElement('span', null, 'Enter: Select'),
                    React.createElement('span', null, 'Arrows: Navigate'),
                    React.createElement('span', null, 'Esc/Back: Close')
                )
            )
        )
    );
}

// ============================================================================
// ALERT DIALOG COMPONENT
// ============================================================================

function AlertDialog({ open, session, header, content, centered, cancel, labels, style, onClose }) {
    const confirmLabel = labels?.confirm || 'CONFIRM';
    const cancelLabel = labels?.cancel || 'CANCEL';
    const dialogRef = useRef(null);
    const handleCancel = useCallback(() => {
        if (cancel) onClose('cancel', session);
    }, [cancel, onClose, session]);
    useModalFocus(open, dialogRef, cancel ? handleCancel : null, session);

    if (!open) return null;

    const dialogClass = `alert-dialog${centered ? ' centered' : ''}`;

    return React.createElement('div', {
        className: 'alert-overlay',
        onMouseDown: handleCancel
    },
        React.createElement('div', {
            ref: dialogRef,
            className: dialogClass,
            role: 'dialog',
            'aria-modal': true,
            'aria-labelledby': header ? 'cortex-alert-title' : undefined,
            'aria-label': header ? undefined : 'Confirmation',
            'aria-describedby': content ? 'cortex-alert-content' : undefined,
            tabIndex: -1,
            style: normalizeAlertStyle(style),
            onMouseDown: (e) => e.stopPropagation(),
            onClick: (e) => e.stopPropagation(),
            onContextMenu: (e) => e.preventDefault()
        },

            header && React.createElement('div', { id: 'cortex-alert-title', className: 'alert-header', role: 'heading', 'aria-level': 2 }, header),
            content && React.createElement('div', { id: 'cortex-alert-content', className: 'alert-content' }, content),
            React.createElement('div', { className: 'alert-actions' },
                cancel && React.createElement('button', {
                    type: 'button',
                    className: 'alert-btn cancel',
                    onClick: handleCancel
                }, cancelLabel),
                React.createElement('button', {
                    type: 'button',
                    className: 'alert-btn confirm',
                    'data-autofocus': 'true',
                    onClick: () => onClose('confirm', session)
                }, confirmLabel)
            )
        )
    );
}

function HelpBar({ open, items }) {
    if (!open || !items || !items.length) return null;

    return React.createElement('div', { className: 'cortex-help-bar', role: 'group', 'aria-label': 'Controls' },
        items.map((item, i) => React.createElement('div', { key: i, className: 'cortex-help-item' },
            React.createElement('div', { className: 'cortex-help-label' }, item.label),
            React.createElement('div', { className: 'cortex-help-values' },
                item.value.split(' ').map((key, j) =>
                    React.createElement('span', { key: j, className: 'cortex-help-key' }, key)
                )
            )
        ))
    );
}

// ============================================================================
// CONTEXT MENU COMPONENT (Settings-style dialog with form fields)
// ============================================================================

function ContextMenuCheckbox({ field, value, onChange, descriptionId }) {
    const handleClick = useCallback(() => {
        onChange(field.name, !value);
    }, [field.name, value, onChange]);

    return React.createElement('button', {
        type: 'button',
        className: 'cortex-context-checkbox',
        role: 'checkbox',
        'aria-checked': Boolean(value),
        'aria-required': field.required === true,
        'aria-describedby': field.description ? descriptionId : undefined,
        onClick: handleClick
    },
        React.createElement('div', { className: `cortex-context-checkbox-box${value ? ' checked' : ''}` },
            React.createElement('svg', { viewBox: '0 0 24 24' },
                React.createElement('path', { d: 'M20 6L9 17l-5-5' })
            )
        ),
        React.createElement('span', { className: 'cortex-context-checkbox-label' }, field.label)
    );
}

let contextSelectIdCounter = 0;

function ContextMenuSelect({ field, value, onChange, inputId, descriptionId }) {
    const [dropdownOpen, setDropdownOpen] = useState(false);
    const [activeIndex, setActiveIndex] = useState(-1);
    const selectRef = useRef(null);
    const menuIdRef = useRef(`cortex-context-select-${++contextSelectIdCounter}`);
    const options = Array.isArray(field.options) ? field.options : [];

    const selectedOption = options.find(opt =>
        (typeof opt === 'object' ? opt.value : opt) === value
    );
    const displayValue = selectedOption
        ? (typeof selectedOption === 'object' ? selectedOption.label : selectedOption)
        : (value || 'Select...');

    const handleSelect = useCallback((optValue) => {
        onChange(field.name, optValue);
        setDropdownOpen(false);
    }, [field.name, onChange]);

    const openDropdown = useCallback((preferredIndex) => {
        const selectedIndex = options.findIndex(opt => (typeof opt === 'object' ? opt.value : opt) === value);
        const nextIndex = Number.isInteger(preferredIndex)
            ? preferredIndex
            : Math.max(0, selectedIndex);
        setActiveIndex(Math.min(Math.max(nextIndex, 0), Math.max(options.length - 1, 0)));
        setDropdownOpen(options.length > 0);
    }, [options, value]);

    const handleTriggerKeyDown = useCallback((event) => {
        if (event.key === 'Escape') {
            if (dropdownOpen) {
                event.preventDefault();
                event.stopPropagation();
                setDropdownOpen(false);
            }
            return;
        }
        if (event.key === 'ArrowDown' || event.key === 'ArrowUp' || event.key === 'Home' || event.key === 'End') {
            event.preventDefault();
            if (!dropdownOpen) {
                openDropdown(event.key === 'End' ? options.length - 1 : undefined);
                return;
            }
            if (event.key === 'Home') setActiveIndex(0);
            else if (event.key === 'End') setActiveIndex(Math.max(options.length - 1, 0));
            else setActiveIndex(current => {
                const direction = event.key === 'ArrowDown' ? 1 : -1;
                return (Math.max(current, 0) + direction + options.length) % options.length;
            });
            return;
        }
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            if (!dropdownOpen) openDropdown();
            else if (options[activeIndex] !== undefined) {
                const option = options[activeIndex];
                handleSelect(typeof option === 'object' ? option.value : option);
            }
        }
    }, [activeIndex, dropdownOpen, handleSelect, openDropdown, options]);

    useEffect(() => {
        if (!dropdownOpen) return;
        const handleClickOutside = (e) => {
            if (selectRef.current && !selectRef.current.contains(e.target)) {
                setDropdownOpen(false);
            }
        };
        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, [dropdownOpen]);

    return React.createElement('div', { className: 'cortex-context-select', ref: selectRef },
        React.createElement('button', {
            type: 'button',
            id: inputId,
            className: 'cortex-context-select-trigger',
            role: 'combobox',
            'aria-label': field.label,
            'aria-haspopup': 'listbox',
            'aria-expanded': dropdownOpen,
            'aria-required': field.required === true,
            'aria-controls': menuIdRef.current,
            'aria-describedby': field.description ? descriptionId : undefined,
            'aria-activedescendant': dropdownOpen && activeIndex >= 0 ? `${menuIdRef.current}-option-${activeIndex}` : undefined,
            onClick: () => dropdownOpen ? setDropdownOpen(false) : openDropdown(),
            onKeyDown: handleTriggerKeyDown
        },
            field.icon && React.createElement('div', { className: 'cortex-context-select-icon' }, field.icon),
            React.createElement('span', { className: 'cortex-context-select-value' }, displayValue),
            React.createElement('svg', { className: 'cortex-context-select-arrow', viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
                React.createElement('path', { d: 'M6 9l6 6 6-6' })
            )
        ),
        dropdownOpen && React.createElement('div', { id: menuIdRef.current, className: 'cortex-context-select-dropdown', role: 'listbox' },
            options.map((opt, i) => {
                const optValue = typeof opt === 'object' ? opt.value : opt;
                const optLabel = typeof opt === 'object' ? opt.label : opt;
                const isSelected = optValue === value;
                return React.createElement('button', {
                    key: i,
                    id: `${menuIdRef.current}-option-${i}`,
                    type: 'button',
                    role: 'option',
                    'aria-selected': isSelected,
                    tabIndex: -1,
                    className: `cortex-context-select-option${isSelected ? ' selected' : ''}${i === activeIndex ? ' active' : ''}`,
                    onMouseMove: () => setActiveIndex(i),
                    onClick: () => handleSelect(optValue)
                }, optLabel);
            })
        )
    );
}

function ContextMenuInput({ field, value, onChange, inputId, descriptionId }) {
    const handleChange = useCallback((e) => {
        onChange(field.name, e.target.value);
    }, [field.name, onChange]);

    return React.createElement('input', {
        className: 'cortex-context-input',
        id: inputId,
        type: field.inputType || 'text',
        placeholder: field.placeholder || '',
        value: value ?? '',
        required: field.required === true,
        'aria-describedby': field.description ? descriptionId : undefined,
        onChange: handleChange
    });
}

function ContextMenu({ open, session, title, fields, values, labels, onClose }) {
    const [formValues, setFormValues] = useState({});
    const dialogRef = useRef(null);
    const confirmLabel = labels?.confirm || 'CONFIRM';
    const cancelLabel = labels?.cancel || 'CANCEL';

    useEffect(() => {
        if (open) {
            const nextValues = {};
            const sourceValues = isRecord(values) ? values : {};
            for (const field of fields || []) {
                if (!field || !isSafeObjectKey(field.name)) continue;
                if (Object.prototype.hasOwnProperty.call(sourceValues, field.name)) {
                    const sourceValue = sourceValues[field.name];
                    if (field.type === 'checkbox') {
                        nextValues[field.name] = sourceValue === true;
                    } else if (field.type === 'select') {
                        const matchedOption = field.options.find(option => {
                            const optionValue = isRecord(option) ? option.value : option;
                            return Object.is(optionValue, sourceValue);
                        });
                        nextValues[field.name] = matchedOption === undefined
                            ? ''
                            : (isRecord(matchedOption) ? matchedOption.value : matchedOption);
                    } else {
                        nextValues[field.name] = normalizeScalarValue(sourceValue);
                    }
                }
            }
            setFormValues(nextValues);
        }
    }, [fields, open, session, values]);

    const handleChange = useCallback((name, value) => {
        setFormValues(prev => ({ ...prev, [name]: value }));
    }, []);

    const handleConfirm = useCallback(() => {
        onClose('confirm', formValues, session);
    }, [formValues, onClose, session]);

    const handleCancel = useCallback(() => {
        onClose('cancel', null, session);
    }, [onClose, session]);

    useModalFocus(open, dialogRef, handleCancel, session);

    if (!open) return null;

    return React.createElement('div', {
        className: 'cortex-context-overlay',
        onMouseDown: handleCancel
    },
        React.createElement('div', {
            ref: dialogRef,
            className: 'cortex-context-dialog',
            role: 'dialog',
            'aria-modal': true,
            'aria-labelledby': title ? 'cortex-context-title' : undefined,
            'aria-label': title ? undefined : 'Context options',
            tabIndex: -1,
            onMouseDown: (e) => e.stopPropagation(),
            onClick: (e) => e.stopPropagation()
        },
            title && React.createElement('div', { id: 'cortex-context-title', className: 'cortex-context-header', role: 'heading', 'aria-level': 2 }, title),
            React.createElement('div', { className: 'cortex-context-body' },
                (fields || []).map((field, i) => {
                    if (!isRecord(field) || !field.name) return null;
                    const fieldValue = formValues[field.name];
                    const inputId = `cortex-context-field-${i}`;
                    const descriptionId = `${inputId}-description`;
                    
                    if (field.type === 'checkbox') {
                        return React.createElement('div', { key: i, className: 'cortex-context-field' },
                            React.createElement(ContextMenuCheckbox, {
                                field,
                                value: Boolean(fieldValue),
                                onChange: handleChange,
                                descriptionId
                            }),
                            field.description && React.createElement('div', { id: descriptionId, className: 'cortex-context-sublabel' }, field.description)
                        );
                    }

                    if (field.type === 'select') {
                        return React.createElement('div', { key: i, className: 'cortex-context-field' },
                            React.createElement('label', { className: 'cortex-context-label', htmlFor: inputId },
                                field.label,
                                field.required && React.createElement('span', { className: 'required' }, '*')
                            ),
                            field.description && React.createElement('div', { id: descriptionId, className: 'cortex-context-sublabel' }, field.description),
                            React.createElement(ContextMenuSelect, {
                                field,
                                value: fieldValue,
                                onChange: handleChange,
                                inputId,
                                descriptionId
                            })
                        );
                    }

                    if (field.type === 'input' || field.type === 'text') {
                        return React.createElement('div', { key: i, className: 'cortex-context-field' },
                            React.createElement('label', { className: 'cortex-context-label', htmlFor: inputId },
                                field.label,
                                field.required && React.createElement('span', { className: 'required' }, '*')
                            ),
                            field.description && React.createElement('div', { id: descriptionId, className: 'cortex-context-sublabel' }, field.description),
                            React.createElement(ContextMenuInput, {
                                field,
                                value: fieldValue,
                                onChange: handleChange,
                                inputId,
                                descriptionId
                            })
                        );
                    }

                    return null;
                })
            ),
            React.createElement('div', { className: 'cortex-context-actions' },
                React.createElement('button', {
                    type: 'button',
                    className: 'cortex-context-btn cancel',
                    onClick: handleCancel
                }, cancelLabel),
                React.createElement('button', {
                    type: 'button',
                    className: 'cortex-context-btn confirm',
                    'data-autofocus': 'true',
                    onClick: handleConfirm
                }, confirmLabel)
            )
        )
    );
}

// ============================================================================
// RADIAL MENU COMPONENT (SVG-based, ox_lib inspired)
// ============================================================================

const RADIAL_PAGE_ITEMS = 8;  // Max rendered sectors per page
const RADIAL_PAGE_ACTIONS = RADIAL_PAGE_ITEMS - 1;
const RADIAL_SIZE = 350;       // SVG viewBox size
const RADIAL_CENTER = RADIAL_SIZE / 2;
const RADIAL_OUTER_RADIUS = RADIAL_CENTER;
const RADIAL_INNER_RADIUS = 45;
const RADIAL_ICON_RADIUS = RADIAL_CENTER * 0.58;
const RADIAL_GAP = 3;

function degToRad(deg) {
    return deg * (Math.PI / 180);
}

function polarToCartesian(centerX, centerY, radius, angleInDegrees) {
    const angleInRadians = degToRad(angleInDegrees - 90);
    return {
        x: centerX + (radius * Math.cos(angleInRadians)),
        y: centerY + (radius * Math.sin(angleInRadians))
    };
}

function describeArc(x, y, radius, startAngle, endAngle) {
    const start = polarToCartesian(x, y, radius, endAngle);
    const end = polarToCartesian(x, y, radius, startAngle);
    const largeArcFlag = endAngle - startAngle <= 180 ? '0' : '1';
    return [
        'M', start.x, start.y,
        'A', radius, radius, 0, largeArcFlag, 0, end.x, end.y
    ].join(' ');
}

function describeSector(cx, cy, outerRadius, innerRadius, startAngle, endAngle, gap) {
    const outerStart = polarToCartesian(cx, cy, outerRadius - gap, startAngle + gap * 0.3);
    const outerEnd = polarToCartesian(cx, cy, outerRadius - gap, endAngle - gap * 0.3);
    const innerStart = polarToCartesian(cx, cy, innerRadius + gap, startAngle + gap * 0.3);
    const innerEnd = polarToCartesian(cx, cy, innerRadius + gap, endAngle - gap * 0.3);
    
    const largeArc = endAngle - startAngle > 180 ? 1 : 0;
    
    return [
        'M', outerStart.x, outerStart.y,
        'A', outerRadius - gap, outerRadius - gap, 0, largeArc, 1, outerEnd.x, outerEnd.y,
        'L', innerEnd.x, innerEnd.y,
        'A', innerRadius + gap, innerRadius + gap, 0, largeArc, 0, innerStart.x, innerStart.y,
        'Z'
    ].join(' ');
}

function getRadialPointer(clientX, clientY, element, itemCount, visibleItemCount) {
    if (!element || visibleItemCount === 0) return { type: 'outside', index: -1 };

    const rect = element.getBoundingClientRect();
    const svgScale = rect.width / RADIAL_SIZE;
    if (!Number.isFinite(svgScale) || svgScale <= 0) return { type: 'outside', index: -1 };

    const dx = clientX - (rect.left + rect.width / 2);
    const dy = clientY - (rect.top + rect.height / 2);
    const distance = Math.sqrt(dx * dx + dy * dy) / svgScale;

    if (distance < RADIAL_INNER_RADIUS) return { type: 'center', index: -1 };
    if (distance > RADIAL_OUTER_RADIUS) return { type: 'outside', index: -1 };

    let angle = Math.atan2(dx, -dy) * (180 / Math.PI);
    if (angle < 0) angle += 360;

    const angleStep = 360 / itemCount;
    const index = Math.floor(angle / angleStep) % itemCount;
    if (index >= visibleItemCount) return { type: 'outside', index: -1 };
    return { type: 'item', index };
}

function RadialMenu({ open, id, session, items, canGoBack, visible, appearance }) {
    const [hoverIndex, setHoverIndex] = useState(-1);
    const [page, setPage] = useState(1);
    const [isVisible, setIsVisible] = useState(false);
    const radialSvgRef = useRef(null);

    // Reset page when items change or menu opens
    useEffect(() => {
        if (open) {
            setPage(1);
            setHoverIndex(-1);
            setIsVisible(true);
        } else {
            setIsVisible(false);
        }
    }, [open, items]);

    // Handle visibility transitions
    useEffect(() => {
        if (visible === false) {
            setIsVisible(false);
        } else if (visible === true && open) {
            setIsVisible(true);
        }
    }, [visible, open]);

    useModalFocus(open && isVisible, radialSvgRef, null, `${session ?? 'none'}:${id ?? ''}`);

    // Calculate paginated items
    const allItems = items || [];
    const totalPages = allItems.length > RADIAL_PAGE_ITEMS
        ? Math.ceil(allItems.length / RADIAL_PAGE_ACTIONS)
        : 1;
    const needsPagination = allItems.length > RADIAL_PAGE_ITEMS;
    const pageStartIndex = needsPagination ? (page - 1) * RADIAL_PAGE_ACTIONS : 0;
    
    let displayItems = allItems;
    if (needsPagination) {
        displayItems = allItems.slice(pageStartIndex, pageStartIndex + RADIAL_PAGE_ACTIONS);
        // Add "more" item at the end
        displayItems = [...displayItems, { id: '__more__', label: 'More', icon: '...' }];
    }

    const itemCount = Math.max(displayItems.length, 3); // Minimum 3 sectors for visual balance
    const angleStep = 360 / itemCount;

    const activateItem = useCallback((index) => {
        if (!isVisible) return;
        const item = displayItems[index];
        if (!item) return;

        if (item.id === '__more__') {
            setPage(p => p < totalPages ? p + 1 : 1);
            return;
        }

        const sourceIndex = pageStartIndex + index;
        if (sourceIndex >= 0 && sourceIndex < allItems.length) {
            nuiPost('radialClick', { index: sourceIndex, itemId: item.id, menuId: id, session });
        }
    }, [allItems.length, displayItems, id, isVisible, pageStartIndex, session, totalPages]);

    // Handle mouse movement
    const handleMouseMove = useCallback((e) => {
        if (!isVisible) return;
        const hit = getRadialPointer(
            e.clientX,
            e.clientY,
            radialSvgRef.current,
            itemCount,
            displayItems.length
        );
        setHoverIndex(hit.type === 'item' ? hit.index : -1);
    }, [displayItems.length, isVisible, itemCount]);

    // Handle click
    const handleClick = useCallback((e) => {
        if (!isVisible) return;
        const hit = getRadialPointer(
            e.clientX,
            e.clientY,
            radialSvgRef.current,
            itemCount,
            displayItems.length
        );

        if (hit.type === 'center') {
            if (page > 1) {
                setPage(p => p - 1);
            } else if (canGoBack) {
                nuiPost('radialBack', { menuId: id, session });
            } else {
                nuiPost('radialClose', { menuId: id, session });
            }
            return;
        }

        if (hit.type === 'item') activateItem(hit.index);
    }, [activateItem, canGoBack, displayItems.length, id, isVisible, itemCount, page, session]);

    // Right-click = back/close
    const handleContextMenu = useCallback((e) => {
        e.preventDefault();
        if (!isVisible) return;
        if (page > 1) {
            setPage(p => p - 1);
        } else if (canGoBack) {
            nuiPost('radialBack', { menuId: id, session });
        } else {
            nuiPost('radialClose', { menuId: id, session });
        }
    }, [canGoBack, id, isVisible, page, session]);

    // Keyboard handling
    useEffect(() => {
        if (!open || !isVisible) return;

        const handleKeyDown = (e) => {
            if (e.key === 'Escape') {
                e.preventDefault();
                nuiPost('radialClose', { menuId: id, session });
            } else if (e.key === 'Backspace') {
                e.preventDefault();
                if (page > 1) {
                    setPage(p => p - 1);
                } else if (canGoBack) {
                    nuiPost('radialBack', { menuId: id, session });
                }
            } else if (displayItems.length > 0 && (e.key === 'ArrowRight' || e.key === 'ArrowDown')) {
                e.preventDefault();
                setHoverIndex(current => current < 0 ? 0 : (current + 1) % displayItems.length);
            } else if (displayItems.length > 0 && (e.key === 'ArrowLeft' || e.key === 'ArrowUp')) {
                e.preventDefault();
                setHoverIndex(current => current < 0 ? displayItems.length - 1
                    : (current - 1 + displayItems.length) % displayItems.length);
            } else if ((e.key === 'Enter' || e.key === ' ') && hoverIndex >= 0) {
                e.preventDefault();
                activateItem(hoverIndex);
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [activateItem, open, isVisible, canGoBack, displayItems.length, hoverIndex, id, page, session]);

    if (!open) return null;

    const hoveredItem = hoverIndex >= 0 ? displayItems[hoverIndex] : null;
    const centerIcon = hoveredItem?.icon || (page > 1 ? '←' : (canGoBack ? '←' : '✕'));
    const centerLabel = hoveredItem?.label || (page > 1 ? 'Back' : (canGoBack ? 'Back' : 'Close'));

    const compactControl = appearance === 'compact-control';

    return React.createElement('div', {
        className: `cortex-radial-overlay${isVisible ? ' visible' : ''}${compactControl ? ' cortex-radial-overlay--compact-control' : ''}`,
        onMouseMove: handleMouseMove,
        onClick: handleClick,
        onContextMenu: handleContextMenu,
        role: 'dialog',
        'aria-modal': true,
        'aria-label': 'Radial controls',
        'aria-busy': !isVisible,
        'aria-hidden': !isVisible
    },
        React.createElement('svg', {
            className: `cortex-radial-svg${compactControl ? ' cortex-radial-svg--compact-control' : ''}`,
            viewBox: `0 0 ${RADIAL_SIZE} ${RADIAL_SIZE}`,
            xmlns: 'http://www.w3.org/2000/svg',
            ref: radialSvgRef,
            role: 'menu',
            tabIndex: isVisible ? 0 : -1,
            'aria-label': id ? `${id.replaceAll('_', ' ')} menu` : 'Controls menu',
            'aria-activedescendant': hoverIndex >= 0 ? `cortex-radial-item-${pageStartIndex + hoverIndex}` : undefined
        },
            // Sectors
            displayItems.map((item, i) => {
                const startAngle = i * angleStep;
                const endAngle = startAngle + angleStep;
                const isHovered = i === hoverIndex;
                const midAngle = startAngle + angleStep / 2;
                
                // Icon position
                const iconPos = polarToCartesian(RADIAL_CENTER, RADIAL_CENTER, RADIAL_ICON_RADIUS, midAngle);

                return React.createElement('g', {
                    key: `${pageStartIndex + i}:${item.id || 'item'}`,
                    id: `cortex-radial-item-${pageStartIndex + i}`,
                    className: `cortex-radial-sector${isHovered ? ' hover' : ''}`,
                    role: 'menuitem',
                    'aria-label': item.label || item.id || `Item ${i + 1}`
                },
                    // Sector path
                    React.createElement('path', {
                        d: describeSector(
                            RADIAL_CENTER, RADIAL_CENTER,
                            RADIAL_OUTER_RADIUS, RADIAL_INNER_RADIUS,
                            startAngle, endAngle, RADIAL_GAP
                        ),
                        className: 'cortex-radial-sector-bg'
                    }),
                    // Icon
                    React.createElement('text', {
                        x: iconPos.x,
                        y: iconPos.y - 6,
                        className: 'cortex-radial-sector-icon',
                        style: item.iconColor ? { '--cortex-radial-icon-color': item.iconColor } : undefined,
                        textAnchor: 'middle',
                        dominantBaseline: 'middle'
                    }, item.icon || '•'),
                    // Label
                    React.createElement('text', {
                        x: iconPos.x,
                        y: iconPos.y + 14,
                        className: 'cortex-radial-sector-label',
                        textAnchor: 'middle',
                        dominantBaseline: 'middle'
                    }, item.label?.length > 12 ? item.label.substring(0, 11) + '...' : item.label)
                );
            }),

            // Center circle background
            React.createElement('circle', {
                cx: RADIAL_CENTER,
                cy: RADIAL_CENTER,
                r: RADIAL_INNER_RADIUS - 2,
                className: 'cortex-radial-center-bg'
            }),

            // Center icon
            React.createElement('text', {
                x: RADIAL_CENTER,
                y: RADIAL_CENTER - 6,
                className: 'cortex-radial-center-icon',
                textAnchor: 'middle',
                dominantBaseline: 'middle'
            }, centerIcon),

            // Center label  
            React.createElement('text', {
                x: RADIAL_CENTER,
                y: RADIAL_CENTER + 12,
                className: 'cortex-radial-center-label',
                textAnchor: 'middle',
                dominantBaseline: 'middle'
            }, centerLabel?.length > 10 ? centerLabel.substring(0, 9) + '...' : centerLabel),

            // Page indicator (if paginated)
            needsPagination && React.createElement('text', {
                x: RADIAL_CENTER,
                y: RADIAL_SIZE - 15,
                className: 'cortex-radial-page-indicator',
                textAnchor: 'middle'
            }, `${page}/${totalPages}`)
        )
    );
}

// ============================================================================
// SETTINGS PANEL
// ============================================================================

let settingsSelectIdCounter = 0;

function SettingsSelect({ field, value, onChange }) {
    const triggerRef = useRef(null);
    const menuRef = useRef(null);
    const optionRefs = useRef([]);
    const selectIdRef = useRef(null);
    const [open, setOpen] = useState(false);
    const [activeIndex, setActiveIndex] = useState(0);
    const [menuStyle, setMenuStyle] = useState({});

    if (selectIdRef.current === null) {
        settingsSelectIdCounter += 1;
        selectIdRef.current = `cortex-settings-select-${settingsSelectIdCounter}`;
    }

    const options = Array.isArray(field.options)
        ? field.options.filter((option) => option && option.value !== undefined)
        : [];
    const selectedIndex = options.findIndex((option) => Object.is(option.value, value));
    const resolvedSelectedIndex = selectedIndex >= 0 ? selectedIndex : 0;
    const selectedOption = options[selectedIndex] || null;
    const selectedLabel = selectedOption?.label ?? selectedOption?.value ?? value ?? 'Select';
    const menuId = `${selectIdRef.current}-menu`;

    const updateMenuPosition = useCallback(() => {
        const trigger = triggerRef.current;
        if (!trigger) return;

        const rect = trigger.getBoundingClientRect();
        const viewportWidth = window.innerWidth;
        const viewportHeight = window.innerHeight;
        const viewportPadding = 12;
        const gap = 6;
        const menuWidth = Math.min(
            Math.max(rect.width, 160),
            Math.max(160, viewportWidth - (viewportPadding * 2))
        );
        const availableBelow = viewportHeight - rect.bottom - viewportPadding;
        const availableAbove = rect.top - viewportPadding;
        const opensAbove = availableBelow < 150 && availableAbove > availableBelow;
        const availableHeight = opensAbove ? availableAbove : availableBelow;
        const left = Math.min(
            Math.max(viewportPadding, rect.left),
            Math.max(viewportPadding, viewportWidth - viewportPadding - menuWidth)
        );

        setMenuStyle(opensAbove ? {
            left: `${left}px`,
            bottom: `${Math.max(viewportPadding, viewportHeight - rect.top + gap)}px`,
            width: `${menuWidth}px`,
            maxHeight: `${Math.max(96, Math.min(260, availableHeight - gap))}px`
        } : {
            left: `${left}px`,
            top: `${Math.min(viewportHeight - viewportPadding, rect.bottom + gap)}px`,
            width: `${menuWidth}px`,
            maxHeight: `${Math.max(96, Math.min(260, availableHeight - gap))}px`
        });
    }, []);

    const closeMenu = useCallback((restoreFocus = false) => {
        setOpen(false);
        if (restoreFocus) {
            window.requestAnimationFrame(() => triggerRef.current?.focus());
        }
    }, []);

    const focusAdjacentControl = useCallback((reverse) => {
        const trigger = triggerRef.current;
        const panel = trigger?.closest('.cortex-settings-panel');
        if (!trigger || !panel) return;

        const controls = Array.from(panel.querySelectorAll(
            'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])'
        )).filter((element) => element.offsetParent !== null);
        const currentIndex = controls.indexOf(trigger);
        const nextIndex = currentIndex + (reverse ? -1 : 1);
        controls[nextIndex]?.focus();
    }, []);

    const chooseOption = useCallback((index) => {
        const option = options[index];
        if (!option) return;
        onChange(option.value);
        closeMenu(true);
    }, [options, onChange, closeMenu]);

    useEffect(() => {
        if (!open) return;

        updateMenuPosition();
        optionRefs.current = optionRefs.current.slice(0, options.length);
        window.requestAnimationFrame(() => optionRefs.current[activeIndex]?.focus());

        const handlePointerDown = (event) => {
            if (triggerRef.current?.contains(event.target) || menuRef.current?.contains(event.target)) return;
            closeMenu(false);
        };
        const handleViewportChange = () => updateMenuPosition();

        document.addEventListener('mousedown', handlePointerDown);
        window.addEventListener('resize', handleViewportChange);
        window.addEventListener('scroll', handleViewportChange, true);

        return () => {
            document.removeEventListener('mousedown', handlePointerDown);
            window.removeEventListener('resize', handleViewportChange);
            window.removeEventListener('scroll', handleViewportChange, true);
        };
    }, [open, activeIndex, options.length, updateMenuPosition, closeMenu]);

    const openMenu = (index = resolvedSelectedIndex) => {
        if (options.length === 0) return;
        setActiveIndex(Math.max(0, Math.min(options.length - 1, index)));
        setOpen(true);
    };

    const moveActiveOption = (nextIndex) => {
        const boundedIndex = Math.max(0, Math.min(options.length - 1, nextIndex));
        setActiveIndex(boundedIndex);
        window.requestAnimationFrame(() => optionRefs.current[boundedIndex]?.focus());
    };

    const handleTriggerKeyDown = (event) => {
        if (event.key === 'ArrowDown') {
            event.preventDefault();
            openMenu(Math.min(options.length - 1, resolvedSelectedIndex + 1));
        } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            openMenu(Math.max(0, resolvedSelectedIndex - 1));
        }
    };

    const handleMenuKeyDown = (event) => {
        if (event.key === 'ArrowDown') {
            event.preventDefault();
            moveActiveOption((activeIndex + 1) % options.length);
        } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            moveActiveOption((activeIndex - 1 + options.length) % options.length);
        } else if (event.key === 'Home') {
            event.preventDefault();
            moveActiveOption(0);
        } else if (event.key === 'End') {
            event.preventDefault();
            moveActiveOption(options.length - 1);
        } else if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            chooseOption(activeIndex);
        } else if (event.key === 'Escape') {
            event.preventDefault();
            event.stopPropagation();
            closeMenu(true);
        } else if (event.key === 'Tab') {
            event.preventDefault();
            closeMenu(false);
            window.requestAnimationFrame(() => focusAdjacentControl(event.shiftKey));
        }
    };

    const menu = open
        ? ReactDOM.createPortal(
            React.createElement('div', {
                ref: menuRef,
                id: menuId,
                className: 'cortex-settings-select-menu',
                style: menuStyle,
                role: 'listbox',
                'aria-label': field.label,
                onKeyDown: handleMenuKeyDown
            }, options.map((option, index) => {
                const selected = index === selectedIndex;
                const active = index === activeIndex;
                return React.createElement('button', {
                    ref: (element) => { optionRefs.current[index] = element; },
                    key: `${String(option.value)}-${index}`,
                    type: 'button',
                    role: 'option',
                    tabIndex: active ? 0 : -1,
                    'aria-selected': selected,
                    className: `cortex-settings-select-option${selected ? ' selected' : ''}${active ? ' active' : ''}`,
                    onMouseMove: () => setActiveIndex(index),
                    onClick: () => chooseOption(index)
                },
                    React.createElement('span', null, option.label ?? String(option.value)),
                    selected ? React.createElement('span', {
                        className: 'cortex-settings-select-check',
                        'aria-hidden': 'true'
                    }, '✓') : null
                );
            })),
            document.body
        )
        : null;

    return React.createElement('div', { className: 'cortex-settings-select-wrap' },
        React.createElement('button', {
            ref: triggerRef,
            type: 'button',
            className: `cortex-settings-select${open ? ' is-open' : ''}`,
            role: 'combobox',
            'aria-label': field.label,
            'aria-haspopup': 'listbox',
            'aria-expanded': open,
            'aria-controls': menuId,
            disabled: options.length === 0,
            onClick: () => open ? closeMenu(false) : openMenu(),
            onKeyDown: handleTriggerKeyDown
        },
            React.createElement('span', { className: 'cortex-settings-select-text' }, selectedLabel),
            React.createElement('span', {
                className: 'cortex-settings-select-arrow',
                'aria-hidden': 'true'
            }, '⌄')
        ),
        menu
    );
}

function SettingsField({ field, value, tabId, onChange, onAction, onPreviewSound }) {
    if (!field || typeof field !== 'object') return null;
    if (!field.type || !field.key) return null;

    const fieldId = `cortex-setting-${String(tabId).replace(/[^a-z0-9_-]/gi, '-')}-${String(field.key).replace(/[^a-z0-9_-]/gi, '-')}`;
    const labelId = `${fieldId}-label`;
    const descriptionId = `${fieldId}-description`;

    const renderControl = () => {
        switch (field.type) {
            case 'toggle':
                return React.createElement('button', {
                    className: `cortex-settings-toggle${value ? ' on' : ''}`,
                    onClick: () => onChange(tabId, field.key, !value),
                    type: 'button',
                    role: 'switch',
                    'aria-checked': Boolean(value),
                    'aria-label': field.label
                },
                    React.createElement('span', { className: 'cortex-settings-toggle-knob' })
                );

            case 'select':
            case 'color':
                return React.createElement(SettingsSelect, {
                    field,
                    value,
                    onChange: (nextValue) => onChange(tabId, field.key, nextValue)
                });

            case 'slider': {
                const sliderVal = value !== undefined && value !== null ? value : (field.min || 0);
                const suffix = field.suffix || '%';
                return React.createElement('div', { className: 'cortex-settings-slider-wrap' },
                    React.createElement('input', {
                        id: fieldId,
                        type: 'range',
                        className: 'cortex-settings-slider',
                        min: field.min !== undefined ? field.min : 0,
                        max: field.max !== undefined ? field.max : 100,
                        step: field.step !== undefined ? field.step : 1,
                        value: sliderVal,
                        'aria-labelledby': labelId,
                        'aria-describedby': field.description ? descriptionId : undefined,
                        onChange: (e) => onChange(tabId, field.key, Number(e.target.value))
                    }),
                    React.createElement('span', { className: 'cortex-settings-slider-val' }, `${sliderVal}${suffix}`)
                );
            }

            case 'buttons':
                return React.createElement('div', { className: 'cortex-settings-btns', role: 'group', 'aria-labelledby': labelId },
                    (field.buttons || []).map(btn =>
                        React.createElement('button', {
                            key: btn.value,
                            type: 'button',
                            className: 'cortex-settings-action-btn',
                            onClick: () => onAction(tabId, field.key, btn.value)
                        }, btn.label)
                    )
                );

            case 'text':
            case 'input':
                return React.createElement('input', {
                    id: fieldId,
                    type: field.inputType || 'text',
                    className: 'cortex-settings-input',
                    placeholder: field.placeholder || '',
                    maxLength: field.maxLength,
                    spellCheck: false,
                    autoCapitalize: 'off',
                    autoCorrect: 'off',
                    value: value !== undefined && value !== null ? value : '',
                    'aria-labelledby': labelId,
                    'aria-describedby': field.description ? descriptionId : undefined,
                    onChange: (e) => onChange(tabId, field.key, e.target.value)
                });

            case 'soundList':
                return React.createElement('div', { className: 'cortex-settings-soundlist', role: 'radiogroup', 'aria-labelledby': labelId },
                    (field.options || []).map((opt) =>
                        React.createElement('div', {
                            key: opt.value,
                            className: `cortex-settings-sound-item${value === opt.value ? ' selected' : ''}`
                        },
                            React.createElement('button', {
                                type: 'button',
                                className: 'cortex-settings-sound-select',
                                role: 'radio',
                                'aria-checked': value === opt.value,
                                onClick: () => onChange(tabId, field.key, opt.value)
                            },
                                React.createElement('span', { className: 'cortex-settings-sound-radio' }),
                                React.createElement('span', { className: 'cortex-settings-sound-label' }, opt.label)
                            ),
                            React.createElement('button', {
                                type: 'button',
                                className: 'cortex-settings-sound-preview',
                                title: 'Preview',
                                'aria-label': `Preview ${boundedText(opt.label, 'sound', 96)}`,
                                onClick: (e) => {
                                    e.stopPropagation();
                                    onPreviewSound(opt.name, opt.set);
                                }
                            }, '▶')
                        )
                    )
                );

            default:
                return null;
        }
    };

    const rowClass = field.type === 'soundList' ? 'cortex-settings-row cortex-settings-row--stack' : 'cortex-settings-row';

    return React.createElement('div', { className: rowClass },
        React.createElement('div', { className: 'cortex-settings-row-info' },
            React.createElement('div', { id: labelId, className: 'cortex-settings-row-label' }, field.label),
            field.description
                ? React.createElement('div', { id: descriptionId, className: 'cortex-settings-row-desc' }, field.description)
                : null
        ),
        React.createElement('div', { className: 'cortex-settings-row-ctrl' }, renderControl())
    );
}

function SettingsPanel({ open, session, tabs, onClose }) {
    const [activeTab, setActiveTab] = useState(0);
    const [values, setValues] = useState({});
    const [submitError, setSubmitError] = useState('');
    const [submitting, setSubmitting] = useState(false);
    const dialogRef = useRef(null);
    const sessionRef = useRef(normalizeSession(session));
    sessionRef.current = normalizeSession(session);

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
        setActiveTab(0);
        setSubmitError('');
        setSubmitting(false);
    }, [open, session, tabs]);

    useEffect(() => {
        if (!open || !tabs || tabs.length === 0) return;
        if (activeTab >= tabs.length) setActiveTab(0);
    }, [open, tabs, activeTab]);

    const handleChange = useCallback((tabId, key, value) => {
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

    const handleSave = useCallback(async () => {
        if (submitting) return;
        const capturedSession = normalizeSession(session);
        setSubmitting(true);
        const response = await nuiPost('settingsSave', { tabs: values, session });
        if (sessionRef.current !== capturedSession) return;
        if (response?.ok === true) {
            onClose(session);
            return;
        }
        setSubmitError('SAVE FAILED');
        setSubmitting(false);
    }, [onClose, session, submitting, values]);

    const handleCancel = useCallback(async () => {
        if (submitting) return;
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

    useModalFocus(open, dialogRef, handleCancel, session);

    if (!open || !tabs || tabs.length === 0) return null;

    const tab = tabs[activeTab] || tabs[0];
    const tabValues = values[tab.id] || {};
    const fields = tab.fields || [];

    // Build rows with optional section headers
    const rows = [];
    let lastSection = null;
    for (let fi = 0; fi < fields.length; fi++) {
        const field = fields[fi];
        if (!field || typeof field !== 'object') continue;
        const rowKey = field.key != null && field.key !== '' ? String(field.key) : `field-${fi}`;
        if (field.section && field.section !== lastSection) {
            lastSection = field.section;
            rows.push(
                React.createElement('div', { key: `sec-${field.section}`, className: 'cortex-settings-section' }, field.section)
            );
        }
        rows.push(
            React.createElement(SettingsField, {
                key: rowKey,
                field,
                value: tabValues[field.key],
                tabId: tab.id,
                onChange: handleChange,
                onAction: handleAction,
                onPreviewSound: handlePreviewSound
            })
        );
    }

    const handleTabKeyDown = (event, index) => {
        let nextIndex = index;
        if (event.key === 'ArrowRight' || event.key === 'ArrowDown') nextIndex = (index + 1) % tabs.length;
        else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') nextIndex = (index - 1 + tabs.length) % tabs.length;
        else if (event.key === 'Home') nextIndex = 0;
        else if (event.key === 'End') nextIndex = tabs.length - 1;
        else return;
        event.preventDefault();
        setActiveTab(nextIndex);
        window.requestAnimationFrame(() => dialogRef.current?.querySelector(`#cortex-settings-tab-${nextIndex}`)?.focus());
    };

    return React.createElement('div', { className: 'cortex-settings-overlay' },
        React.createElement('div', {
            ref: dialogRef,
            className: 'cortex-settings-panel',
            role: 'dialog',
            'aria-modal': true,
            'aria-labelledby': 'cortex-settings-title',
            tabIndex: -1
        },
            // Header
            React.createElement('div', { className: 'cortex-settings-header' },
                React.createElement('div', { id: 'cortex-settings-title', className: 'cortex-settings-title' },
                    React.createElement('span', { className: 'cortex-settings-accent' }, 'Cortex'),
                    ' Settings'
                ),
                React.createElement('button', {
                    type: 'button',
                    className: 'cortex-settings-close',
                    onClick: handleCancel,
                    disabled: submitting,
                    'aria-label': 'Close settings and discard changes'
                }, '✕')
            ),
            // Tabs
            React.createElement('div', { className: 'cortex-settings-tabs', role: 'tablist', 'aria-label': 'Cortex resources' },
                tabs.map((t, i) =>
                    React.createElement('button', {
                        key: t && t.id != null ? String(t.id) : `tab-${i}`,
                        type: 'button',
                        id: `cortex-settings-tab-${i}`,
                        role: 'tab',
                        'aria-selected': i === activeTab,
                        'aria-controls': 'cortex-settings-tabpanel',
                        tabIndex: i === activeTab ? 0 : -1,
                        'data-autofocus': i === activeTab ? 'true' : undefined,
                        className: `cortex-settings-tab${i === activeTab ? ' active' : ''}`,
                        onClick: () => setActiveTab(i),
                        onKeyDown: event => handleTabKeyDown(event, i)
                    }, t && t.label != null ? t.label : '')
                )
            ),
            // Content
            React.createElement('div', {
                id: 'cortex-settings-tabpanel',
                className: 'cortex-settings-content',
                role: 'tabpanel',
                'aria-labelledby': `cortex-settings-tab-${activeTab}`
            }, ...rows),
            // Footer
            React.createElement('div', { className: 'cortex-settings-footer' },
                React.createElement('div', { className: 'cortex-settings-footer-left' },
                    React.createElement('button', { type: 'button', className: 'cortex-settings-btn reset', onClick: handleReset, disabled: submitting }, 'RESET'),
                    React.createElement(
                        'span',
                        {
                            className: `cortex-settings-live-note${submitError ? ' error' : ''}`,
                            role: 'status',
                            'aria-live': 'polite'
                        },
                        submitError || 'LIVE · SAVE TO KEEP'
                    )
                ),
                React.createElement('div', { className: 'cortex-settings-footer-right' },
                    React.createElement('button', { type: 'button', className: 'cortex-settings-btn cancel', onClick: handleCancel, disabled: submitting }, 'CANCEL'),
                    React.createElement('button', { type: 'button', className: 'cortex-settings-btn save', onClick: handleSave, disabled: submitting }, 'SAVE')
                )
            )
        )
    );
}

// ============================================================================
// MAIN APP
// ============================================================================

let notifyIdCounter = 0;
const INTERACTION_UI_SCALE = 0.8;
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

function InteractionKey({ item, className, ariaLabel, decorative = false }) {
    const holdDuration = getInteractionHoldDuration(item.holdDuration);
    const isHolding = holdDuration !== null && item.holdActive === true;
    const classes = [
        className,
        item.key.length > 3 ? 'is-wide' : '',
        holdDuration !== null ? 'has-hold' : '',
        isHolding ? 'is-holding' : ''
    ].filter(Boolean).join(' ');
    const style = isHolding
        ? { '--cortex-interaction-hold-duration': `${holdDuration}ms` }
        : undefined;

    return React.createElement('span', {
        className: classes,
        style,
        role: decorative ? undefined : 'img',
        'aria-label': decorative ? undefined : ariaLabel,
        'aria-hidden': decorative ? 'true' : undefined
    },
        React.createElement('svg', {
            className: 'cortex-interaction-key-ring',
            viewBox: '0 0 48 48',
            focusable: 'false',
            'aria-hidden': 'true'
        },
            React.createElement('circle', {
                className: 'cortex-interaction-key-ring-track',
                cx: '24',
                cy: '24',
                r: '21.5',
                pathLength: '100'
            }),
            isHolding ? React.createElement('circle', {
                className: 'cortex-interaction-key-ring-progress',
                key: `hold-${item.holdRevision || 0}`,
                cx: '24',
                cy: '24',
                r: '21.5',
                pathLength: '100'
            }) : null
        ),
        React.createElement('span', {
            className: 'cortex-interaction-key-value',
            'aria-hidden': 'true'
        }, item.key)
    );
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

function formatInteractionKey(value) {
    const key = String(value || '').toUpperCase();
    if (key === 'DELETE') return { prefix: '', label: 'DEL' };
    const numpad = /^NUMPAD([0-9]|ENTER)$/.exec(key);
    if (numpad) return { prefix: 'NUM', label: numpad[1] === 'ENTER' ? '↵' : numpad[1] };
    return { prefix: '', label: key };
}

function TargetInteractionKeyLabel({ value }) {
    const { prefix, label } = formatInteractionKey(value);
    return React.createElement('span', {
        className: `cortex-target-key-label${prefix ? ' is-numpad' : ''}${label.length > 3 ? ' is-wide' : ''}`,
        'aria-hidden': 'true'
    },
        prefix ? React.createElement('span', { className: 'cortex-target-key-prefix' }, prefix) : null,
        React.createElement('span', { className: 'cortex-target-key-value' }, label)
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
            React.createElement('span', {
                className: 'cortex-target-action-dot',
                role: 'img',
                'aria-label': `Press ${item.key} to ${item.label.toLowerCase()}`,
                'data-key': item.key
            }, React.createElement(TargetInteractionKeyLabel, { value: item.key }))
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

function InteractionPrompts({ items, layout }) {
    if (!Array.isArray(items) || items.length === 0) return null;

    const screenWidth = Number(layout?.screenWidth) || 1920;
    const screenHeight = Number(layout?.screenHeight) || 1080;
    const scale = clampInteractionNumber(Math.min(screenWidth / 1920, screenHeight / 1080), 0.75, 1.5)
        * INTERACTION_UI_SCALE;
    const style = {
        '--cortex-interaction-safe-right': `${Math.max(0, Number(layout?.insetRight) || 0)}px`,
        '--cortex-interaction-safe-bottom': `${Math.max(0, Number(layout?.insetBottom) || 0)}px`,
        '--cortex-interaction-scale': scale
    };

    const blocks = buildInteractionBlocks(items);

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
        )));
}

function WorldInteractionPrompts({ items }) {
    if (!Array.isArray(items) || items.length === 0) return null;

    const vehicleAccessItems = items
        .filter((item) => getVehicleAccessPresentation(item))
        .sort((left, right) => (
            getVehicleAccessPresentation(left).order - getVehicleAccessPresentation(right).order
        ));
    const standardItems = items.filter((item) => !getVehicleAccessPresentation(item));
    const prompts = standardItems.map((item) => {
        const scale = clampInteractionNumber(1.035 - (item.distance * 0.025), 0.96, 1.02)
            * INTERACTION_UI_SCALE;
        const style = {
            '--cortex-world-x': `${clampInteractionNumber(item.x, 0, 1) * 100}vw`,
            '--cortex-world-y': `${clampInteractionNumber(item.y, 0, 1) * 100}vh`,
            '--cortex-world-scale': scale
        };

        return React.createElement('div', {
            className: 'cortex-world-interaction',
            key: `${item.owner}:${item.id}`,
            style,
            role: 'listitem'
        },
            React.createElement('span', { className: 'cortex-world-interaction-label' }, item.label),
            React.createElement(InteractionKey, {
                item,
                className: 'cortex-world-interaction-key',
                ariaLabel: item.holdDuration
                    ? `Hold ${item.key} to ${item.label.toLowerCase()}`
                    : `Press ${item.key} to ${item.label.toLowerCase()}`
            })
        );
    });

    if (vehicleAccessItems.length > 0) {
        const itemCount = vehicleAccessItems.length;
        const anchor = vehicleAccessItems.reduce((position, item) => ({
            x: position.x + clampInteractionNumber(item.x, 0, 1) / itemCount,
            y: position.y + clampInteractionNumber(item.y, 0, 1) / itemCount,
            distance: position.distance + Math.max(0, Number(item.distance) || 0) / itemCount
        }), { x: 0, y: 0, distance: 0 });
        const scale = clampInteractionNumber(1.035 - (anchor.distance * 0.025), 0.96, 1.02)
            * INTERACTION_UI_SCALE;
        const style = {
            '--cortex-world-x': `${anchor.x * 100}vw`,
            '--cortex-world-y': `${anchor.y * 100}vh`,
            '--cortex-world-scale': scale,
            '--cortex-access-shift-x': anchor.x < 0.22 ? '0%' : (anchor.x > 0.78 ? '-100%' : '-50%'),
            '--cortex-access-shift-y': anchor.y < 0.12 ? '0%' : (anchor.y > 0.88 ? '-100%' : '-50%')
        };

        prompts.push(React.createElement('div', {
            className: 'cortex-world-access',
            key: 'cortex-hud:vehicle-access',
            style,
            role: 'presentation'
        }, vehicleAccessItems.map((item) => {
            const presentation = getVehicleAccessPresentation(item);
            const actionName = String(item.label || '').toLowerCase();

            return React.createElement('div', {
                className: `cortex-world-access-row is-${presentation.icon}`,
                key: `${item.owner}:${item.id}`,
                role: 'listitem'
            },
                React.createElement(InteractionKey, {
                    item,
                    className: 'cortex-world-access-key',
                    ariaLabel: item.holdDuration
                        ? `Hold ${item.key} to ${actionName}`
                        : `Press ${item.key} to ${actionName}`
                }),
                React.createElement('span', {
                    className: 'cortex-world-access-icon',
                    'aria-hidden': 'true'
                }, React.createElement(VehicleAccessIcon, { type: presentation.icon })),
                React.createElement('span', { className: 'cortex-world-access-label' }, item.label)
            );
        })));
    }

    return React.createElement('div', {
        className: 'cortex-world-interactions',
        role: 'list',
        'aria-label': 'Nearby world actions'
    }, prompts);
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
    'distance'
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

    const limit = world ? 4 : 8;
    const normalized = [];

    for (let index = 0; index < items.length && normalized.length < limit; index += 1) {
        const item = items[index];
        if (!item || typeof item.label !== 'string' || typeof item.key !== 'string') continue;
        if (world && (!Number.isFinite(Number(item.x)) || !Number.isFinite(Number(item.y)))) continue;

        const normalizedIndex = normalized.length;
        const nextItem = {
            id: typeof item.id === 'string' ? item.id : `${world ? 'world' : 'screen'}-${normalizedIndex}`,
            owner: typeof item.owner === 'string' ? item.owner : 'unknown',
            label: item.label.trim().slice(0, 96),
            key: item.key.trim().slice(0, 16),
            holdDuration: world ? getInteractionHoldDuration(item.holdDuration) : null,
            holdActive: world && item.holdActive === true,
            holdRevision: world ? clampInteractionNumber(item.holdRevision, 0, 1000000000) : 0
        };
        const panel = normalizeInteractionPanel(item.panel);
        if (panel) Object.assign(nextItem, panel);

        if (world) {
            nextItem.x = clampInteractionNumber(item.x, 0, 1);
            nextItem.y = clampInteractionNumber(item.y, 0, 1);
            nextItem.distance = clampInteractionNumber(item.distance, 0, 25);
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
        React.createElement(InteractionPrompts, { items: interactionItems, layout: interactionLayout }),
        React.createElement(WorldInteractionPrompts, { items: latestWorldItemsRef.current })
    );
}

function App() {
    const [notifications, setNotifications] = useState([]);
    const [notifyPosition, setNotifyPosition] = useState('top-right');
    const [progress, setProgress] = useState({
        active: false,
        duration: 0,
        label: '',
        position: 'bottom',
        style: 'bar',
        canCancel: false
    });

    const [debugPanel, setDebugPanel] = useState({
        open: false,
        title: '',
        subtitle: '',
        position: 'top-right',
        accentColor: null,
        lines: [],
        data: null
    });

    const [alertDialog, setAlertDialog] = useState({
        open: false,
        session: null,
        header: '',
        content: '',
        centered: false,
        cancel: true,
        labels: { confirm: 'CONFIRM', cancel: 'CANCEL' },
        style: null
    });

    const [textUi, setTextUi] = useState({
        open: false,
        text: '',
        position: 'bottom-center',
        icon: null,
        style: null,
        backdrop: false
    });

    const [menu, setMenu] = useState({
        open: false,
        id: null,
        session: null,
        revision: null,
        title: '',
        subtitle: '',
        position: 'top-left',
        canClose: true,
        disableInput: false,
        options: [],
        selected: 1,
        tooltip: ''
    });

    const [help, setHelp] = useState({
        open: false,
        items: []
    });

    const [radial, setRadial] = useState({
        open: false,
        id: null,
        session: null,
        items: [],
        canGoBack: false,
        visible: true,
        appearance: null
    });

    const [contextMenu, setContextMenu] = useState({
        open: false,
        session: null,
        title: '',
        fields: [],
        values: {},
        labels: { confirm: 'CONFIRM', cancel: 'CANCEL' }
    });

    const [uiApps, setUiApps] = useState({});

    const [settingsPanel, setSettingsPanel] = useState({ open: false, session: null, tabs: [] });
    const diagnosticsRef = useRef({ notificationCount: 0, notifyPosition: 'top-right' });
    diagnosticsRef.current = { notificationCount: notifications.length, notifyPosition };

    const closeSettingsPanelLocal = useCallback((session) => {
        setSettingsPanel(prev => prev.session === normalizeSession(session)
            ? { ...prev, open: false }
            : prev);
    }, []);

    const removeNotification = useCallback((id) => {
        setNotifications(prev => prev.filter(n => n.id !== id));
    }, []);

    const addNotification = useCallback((data) => {
        const normalized = normalizeNotificationData(data);
        if (!normalized) return;
        if (normalized.position) {
            setNotifyPosition(normalized.position);
        }

        const generatedId = `notify-${++notifyIdCounter}`;
        setNotifications(prev => mergeNotificationState(prev, normalized, generatedId));
    }, []);

    const clearNotifications = useCallback((data) => {
        setNotifications(prev => filterNotificationsForClear(prev, data));
    }, []);

    const startProgress = useCallback((data) => {
        const normalized = normalizeProgressData(data);
        if (!normalized) return;
        setProgress({
            active: true,
            ...normalized
        });
    }, []);

    const endProgress = useCallback(() => {
        setProgress(prev => ({ ...prev, active: false }));
    }, []);

    const closeAlertDialog = useCallback(async (result, session) => {
        const normalizedSession = normalizeSession(session);
        const response = await nuiPost('alertDialogResult', { result, session });
        if (response?.ok !== true) return;
        setAlertDialog(prev => prev.session === normalizedSession
            ? { ...prev, open: false }
            : prev);
    }, []);

    const closeContextMenu = useCallback(async (result, values, session) => {
        const normalizedSession = normalizeSession(session);
        const response = await nuiPost('contextMenuResult', { result, values: isRecord(values) ? values : null, session });
        if (response?.ok !== true) return;
        setContextMenu(prev => prev.session === normalizedSession
            ? { ...prev, open: false }
            : prev);
    }, []);

    const openMenu = useCallback((data) => {
        const normalizedOptions = Array.isArray(data?.options)
            ? data.options.slice(0, NUI_MAX_MENU_OPTIONS).map(normalizeOption)
            : [];

        const initialSelected = normalizedOptions.length ? 1 : 0;
        const tooltip = normalizedOptions.length ? getOptionTooltip(normalizedOptions[0]) : '';

        setMenu({
            open: true,
            id: boundedText(data?.id, '', 96) || null,
            session: normalizeSession(data?.session),
            revision: normalizeRevision(data?.revision),
            title: boundedText(data?.title, '', 160),
            subtitle: boundedText(data?.subtitle, '', 256),
            position: ['top-left', 'top-right', 'bottom-left', 'bottom-right'].includes(data?.position) ? data.position : 'top-left',
            canClose: data?.canClose !== false,
            disableInput: Boolean(data?.disableInput),
            options: normalizedOptions,
            selected: initialSelected,
            tooltip
        });
    }, [setMenu]);

    const setMenuOptionsAll = useCallback((data) => {
        setMenu(prev => {
            if (!prev.open || prev.id !== data?.id) return prev;
            if (prev.session !== normalizeSession(data?.session)) return prev;
            if (!Array.isArray(data?.options)) return prev;
            const nextRevision = normalizeRevision(data?.revision);
            if (nextRevision === null || (prev.revision !== null && nextRevision <= prev.revision)) return prev;
            const normalizedOptions = Array.isArray(data?.options)
                ? data.options.slice(0, NUI_MAX_MENU_OPTIONS).map(normalizeOption)
                : [];
            const selectedIndex = normalizedOptions.length
                ? Math.max(1, Math.min(prev.selected || 1, normalizedOptions.length))
                : 0;
            const tooltip = normalizedOptions.length
                ? getOptionTooltip(normalizedOptions[selectedIndex - 1])
                : '';
            return { ...prev, revision: nextRevision, options: normalizedOptions, selected: selectedIndex, tooltip };
        });
    }, [setMenu]);

    const setMenuOptionSingle = useCallback((data) => {
        setMenu(prev => {
            if (!prev.open || prev.id !== data?.id) return prev;
            if (prev.session !== normalizeSession(data?.session)) return prev;
            if (!isRecord(data?.option)) return prev;
            const nextRevision = normalizeRevision(data?.revision);
            if (nextRevision === null || (prev.revision !== null && nextRevision <= prev.revision)) return prev;
            const index = data?.index;
            if (!Number.isInteger(index) || index < 1 || index > NUI_MAX_MENU_OPTIONS) return prev;

            const next = prev.options.slice(0);
            next[index - 1] = normalizeOption(data?.option || {});

            const tooltip = next.length
                ? getOptionTooltip(next[(prev.selected || 1) - 1])
                : '';

            return { ...prev, revision: nextRevision, options: next, tooltip };
        });
    }, [setMenu]);

    // NUI message handler
    useEffect(() => {
        const handleMessage = (event) => {
            const message = normalizeNuiMessage(event);
            if (!message) return;
            const { action, data } = message;

            if (uiDebugEnabled) {
                uiDebugLog('message', action, safeJson(data));
            }

            switch (action) {
                case 'debugPing':
                    addNotification({
                        type: 'info',
                        title: 'UI Debug',
                        description: `Ping OK: ${new Date().toLocaleTimeString()}`,
                        duration: 1500,
                        showDuration: true,
                        position: data?.position || 'top-right'
                    });
                    break;
                case 'debugState': {
                    const diagnostics = diagnosticsRef.current;
                    addNotification({
                        type: 'info',
                        title: 'UI Debug',
                        description: `notifications=${diagnostics.notificationCount} position=${diagnostics.notifyPosition}`,
                        duration: 2500,
                        showDuration: true,
                        position: diagnostics.notifyPosition
                    });
                    break;
                }
                case 'copyToClipboard':
                    void copyTextToClipboard(data.text).then((copied) => {
                        if (!copied) uiDebugLog('copyToClipboard failed');
                    }).catch(error => uiDebugLog('copyToClipboard failed', error));
                    break;
                case 'notify':
                    addNotification(data);
                    break;
                case 'menuOpen':
                    openMenu(data);
                    break;
                case 'menuClose':
                    setMenu(prev => prev.session === normalizeSession(data.session)
                        ? { ...prev, open: false, id: null }
                        : prev);
                    break;
                case 'menuSetOptions':
                    setMenuOptionsAll(data);
                    break;
                case 'menuSetOption':
                    setMenuOptionSingle(data);
                    break;
                case 'uiAppOpen':
                    if (isSafeObjectKey(boundedText(data.id, '', 96))) {
                        const appId = boundedText(data.id, '', 96);
                        setUiApps(prev => {
                            if (!prev[appId] && Object.keys(prev).length >= 32) return prev;
                            return {
                                ...prev,
                                [appId]: {
                                    open: true,
                                    session: normalizeSession(data.session),
                                    payload: isRecord(data.payload) ? data.payload : {}
                                }
                            };
                        });
                    }
                    break;
                case 'uiAppData':
                    if (isSafeObjectKey(boundedText(data.id, '', 96))) {
                        const appId = boundedText(data.id, '', 96);
                        setUiApps(prev => {
                            if (!prev[appId]) return prev;
                            if (prev[appId].session !== normalizeSession(data.session)) return prev;
                            return {
                                ...prev,
                                [appId]: {
                                    ...prev[appId],
                                    payload: { ...(isRecord(prev[appId]?.payload) ? prev[appId].payload : {}), ...(isRecord(data.payload) ? data.payload : {}) }
                                }
                            };
                        });
                    }
                    break;
                case 'uiAppClose':
                    if (isSafeObjectKey(boundedText(data.id, '', 96))) {
                        const appId = boundedText(data.id, '', 96);
                        setUiApps(prev => prev[appId] && prev[appId].session === normalizeSession(data.session)
                            ? { ...prev, [appId]: { ...prev[appId], open: false } }
                            : prev);
                    }
                    break;
                case 'debugPanelShow':
                    setDebugPanel({
                        open: true,
                        title: boundedText(data.title, 'DEBUG', 160),
                        subtitle: boundedText(data.subtitle, '', 256),
                        position: ['top-left', 'top-right', 'bottom-left', 'bottom-right'].includes(data.position) ? data.position : 'top-right',
                        accentColor: boundedText(data.accentColor, '', 96) || null,
                        lines: normalizeDebugLines(data.lines),
                        data: isRecord(data.data) ? data.data : null
                    });
                    break;
                case 'debugPanelUpdate':
                    setDebugPanel(prev => ({
                        ...prev,
                        title: data.title !== undefined ? boundedText(data.title, prev.title, 160) : prev.title,
                        subtitle: data.subtitle !== undefined ? boundedText(data.subtitle, prev.subtitle, 256) : prev.subtitle,
                        position: ['top-left', 'top-right', 'bottom-left', 'bottom-right'].includes(data.position) ? data.position : prev.position,
                        accentColor: data.accentColor !== undefined ? (boundedText(data.accentColor, '', 96) || null) : prev.accentColor,
                        lines: Array.isArray(data.lines) ? normalizeDebugLines(data.lines) : prev.lines,
                        data: data.data !== undefined ? (isRecord(data.data) ? data.data : null) : prev.data
                    }));
                    break;
                case 'debugPanelHide':
                    setDebugPanel(prev => ({ ...prev, open: false }));
                    break;
                case 'hideNotify':
                    if (boundedText(data.id, '', 128)) {
                        removeNotification(boundedText(data.id, '', 128));
                    }
                    break;
                case 'clearNotifications':
                    clearNotifications(data);
                    break;
                case 'progressStart':
                    startProgress(data);
                    break;
                case 'progressEnd':
                    endProgress();
                    break;
                case 'alertDialog': {
                    const content = Array.isArray(data.content)
                        ? data.content.slice(0, 64).map(value => boundedText(value, '', 512)).join('\n').slice(0, NUI_MAX_TEXT_LENGTH)
                        : boundedText(data.content, '', NUI_MAX_TEXT_LENGTH);
                    setAlertDialog({
                        open: true,
                        session: normalizeSession(data.session),
                        header: boundedText(data.header, '', 256),
                        content,
                        centered: Boolean(data.centered),
                        cancel: data.cancel !== false,
                        labels: {
                            confirm: boundedText(isRecord(data.labels) ? data.labels.confirm : null, 'CONFIRM', 64),
                            cancel: boundedText(isRecord(data.labels) ? data.labels.cancel : null, 'CANCEL', 64)
                        },
                        style: normalizeAlertStyle(data.style)
                    });
                    break;
                }
                case 'alertDialogClose':
                    setAlertDialog(prev => prev.session === normalizeSession(data.session)
                        ? { ...prev, open: false }
                        : prev);
                    break;
                case 'contextMenu': {
                    setContextMenu({
                        open: true,
                        session: normalizeSession(data.session),
                        title: boundedText(data.title, '', 256),
                        fields: Array.isArray(data.fields)
                            ? data.fields.slice(0, NUI_MAX_CONTEXT_FIELDS).map(normalizeContextField).filter(Boolean)
                            : [],
                        values: isRecord(data.values) ? data.values : {},
                        labels: {
                            confirm: boundedText(isRecord(data.labels) ? data.labels.confirm : null, 'CONFIRM', 64),
                            cancel: boundedText(isRecord(data.labels) ? data.labels.cancel : null, 'CANCEL', 64)
                        }
                    });
                    break;
                }
                case 'contextMenuClose':
                    setContextMenu(prev => prev.session === normalizeSession(data.session)
                        ? { ...prev, open: false }
                        : prev);
                    break;
                case 'textUIShow': {
                    setTextUi({
                        open: true,
                        text: boundedText(data.text, '', NUI_MAX_TEXT_LENGTH),
                        position: ['top-center', 'top-left', 'top-right', 'bottom-center', 'bottom-left', 'bottom-right'].includes(data.position) ? data.position : 'bottom-center',
                        icon: boundedText(data.icon, '', 32) || null,
                        style: normalizeAlertStyle(data.style),
                        backdrop: Boolean(data.backdrop)
                    });
                    break;
                }
                case 'textUIHide':
                    setTextUi(prev => ({ ...prev, open: false }));
                    break;
                case 'helpShow':
                    setHelp({ open: true, items: normalizeHelpItems(data.items) });
                    break;
                case 'helpHide':
                    setHelp(prev => ({ ...prev, open: false }));
                    break;
                case 'radialShow':
                    setRadial({
                        open: true,
                        id: boundedText(data.menuId, '', 96) || null,
                        session: normalizeSession(data.session),
                        items: normalizeRadialItems(data.items),
                        canGoBack: Boolean(data.canGoBack),
                        appearance: data.appearance === 'compact-control' ? 'compact-control' : null,
                        visible: true
                    });
                    break;
                case 'radialHide':
                    setRadial(prev => prev.session === normalizeSession(data.session)
                        ? { ...prev, open: false, visible: false }
                        : prev);
                    break;
                case 'radialRefresh':
                    setRadial(prev => prev.session === normalizeSession(data.session) ? ({
                        ...prev,
                        id: boundedText(data.menuId, '', 96) || prev.id,
                        items: Array.isArray(data.items) ? normalizeRadialItems(data.items) : prev.items,
                        canGoBack: data.canGoBack !== undefined ? Boolean(data.canGoBack) : prev.canGoBack,
                        appearance: data.appearance !== undefined ? (data.appearance === 'compact-control' ? 'compact-control' : null) : prev.appearance
                    }) : prev);
                    break;
                case 'radialTransitionOut':
                    setRadial(prev => prev.session === normalizeSession(data.session)
                        ? { ...prev, visible: false }
                        : prev);
                    break;
                case 'radialTransitionIn':
                    setRadial(prev => prev.session === normalizeSession(data.session) ? ({
                        ...prev,
                        id: boundedText(data.menuId, '', 96) || null,
                        items: normalizeRadialItems(data.items),
                        canGoBack: Boolean(data.canGoBack),
                        appearance: data.appearance === 'compact-control' ? 'compact-control' : null,
                        visible: true
                    }) : prev);
                    break;
                case 'settingsOpen':
                    setSettingsPanel({
                        open: true,
                        session: normalizeSession(data.session),
                        tabs: normalizeSettingsTabs(data.tabs)
                    });
                    break;
                case 'settingsClose':
                    setSettingsPanel(prev => prev.session === normalizeSession(data.session)
                        ? { ...prev, open: false }
                        : prev);
                    break;
                case 'notifySetPosition':
                    if (['top', 'top-right', 'top-left', 'bottom', 'bottom-right', 'bottom-left'].includes(data.position)) {
                        setNotifyPosition(data.position);
                    }
                    break;
            }
        };

        window.addEventListener('message', handleMessage);
        return () => window.removeEventListener('message', handleMessage);
    }, [addNotification, removeNotification, clearNotifications, startProgress, endProgress, openMenu, setMenuOptionsAll, setMenuOptionSingle]);

    return React.createElement(React.Fragment, null,
        React.createElement(NotificationContainer, {
            notifications,
            position: notifyPosition,
            onRemove: removeNotification
        }),
        React.createElement(ProgressBar, progress),
        React.createElement(TextUI, { ...textUi }),
        React.createElement(AlertDialog, { ...alertDialog, onClose: closeAlertDialog }),
        React.createElement(ContextMenu, { ...contextMenu, onClose: closeContextMenu }),
        React.createElement(DebugPanel, { ...debugPanel }),
        React.createElement(HelpBar, { ...help }),
        React.createElement(RadialMenu, { ...radial }),
        React.createElement(WeatherZoneEditorApp, { appState: uiApps[WEATHER_EDITOR_APP_ID], setUiApps }),
        React.createElement(Menu, { ...menu, setMenu }),
        React.createElement(SettingsPanel, { ...settingsPanel, onClose: closeSettingsPanelLocal }),
        React.createElement(InteractionSurface, { hidden: settingsPanel.open })
    );
}

// ============================================================================
// DYNAMIC STYLES
// ============================================================================

// Keep only truly dynamic keyframes here; all layout styles live in style.css
const style = document.createElement('style');
style.textContent = `@keyframes shrink { from { width: 100%; } to { width: 0%; } }`;
document.head.appendChild(style);

// ============================================================================
// RENDER APP
// ============================================================================

const rootEl = document.getElementById('root');

// React 18: ReactDOM.createRoot
// React 17/legacy: ReactDOM.render
if (ReactDOM.createRoot) {
    const root = ReactDOM.createRoot(rootEl);
    root.render(React.createElement(App));
} else {
    ReactDOM.render(React.createElement(App), rootEl);
}
