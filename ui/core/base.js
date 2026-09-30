

/* Cortex library NUI core: shared React hooks, bounded normalizers, the NUI
 * bridge, focus management, scale and debug helpers. Classic script: its
 * top-level declarations are shared with the surface modules that follow. */

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

function normalizeIconColor(value) {
    const color = boundedText(value, '', 64).trim();
    return /^(?:var\(--[a-z0-9-]+\)|#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8}))$/i.test(color)
        ? color
        : null;
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
    )).filter(element => element.getAttribute('aria-hidden') !== 'true' && !element.closest?.('[inert], [hidden]'));
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
            if (event.defaultPrevented) return;
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
    const w = window.innerWidth || 1920;
    // Match pause.css: scale by the short viewport axis, including beyond 4K.
    return Math.max(Math.min(w, h) / 1080, 0.86);
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

