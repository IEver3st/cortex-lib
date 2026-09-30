/* Dialogs: the alert (lib.alertDialog) and the input form (lib.contextMenu).
 * One 520u slip placed centre-low over a light ink scrim that exists only while
 * a dialog owns focus. Keyboard first: Enter confirms, Escape cancels, the
 * focused action flips to paper. Results always echo the session; app.js owns
 * the transport and the stale-session guards. */

const DIALOG_LEAVE_MS = 180;
const DIALOG_NUMBER_LIMIT = 1e9;
const DIALOG_NUMBER_PATTERN = /^[-+]?(?:\d+\.?\d*|\.\d+)(?:e[-+]?\d+)?$/i;
const DIALOG_MAX_PARAGRAPHS = 64;

function normalizeDialogNumber(value) {
    return typeof value === 'number' && Number.isFinite(value) && Math.abs(value) <= DIALOG_NUMBER_LIMIT ? value : undefined;
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

    // Optional number bounds: finite, bounded, min <= max, step > 0. Invalid bounds are dropped.
    let min = normalizeDialogNumber(field.min);
    let max = normalizeDialogNumber(field.max);
    if (min !== undefined && max !== undefined && min > max) {
        min = undefined;
        max = undefined;
    }
    const step = normalizeDialogNumber(field.step);

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
            : [],
        min,
        max,
        step: step !== undefined && step > 0 ? step : undefined
    };
}

// ============================================================================
// FORM VALUES: parsing, stepping, validation (pure; covered by contract tests)
// ============================================================================

function contextOptionValue(option) {
    return isRecord(option) ? option.value : option;
}

function parseDialogNumber(value) {
    const text = String(value ?? '').trim();
    if (!DIALOG_NUMBER_PATTERN.test(text)) return null;
    const number = Number(text);
    return Number.isFinite(number) ? number : null;
}

function formatDialogNumber(value) {
    return String(Number(Number(value).toFixed(6)));
}

function stepDialogNumber(field, text, direction, multiplier = 1) {
    const step = field.step !== undefined ? field.step : 1;
    const current = parseDialogNumber(text);
    let next;
    if (current === null) {
        next = field.min !== undefined ? field.min : (field.max !== undefined && field.max < 0 ? field.max : 0);
    } else {
        next = current + direction * step * multiplier;
    }
    if (field.min !== undefined) next = Math.max(field.min, next);
    if (field.max !== undefined) next = Math.min(field.max, next);
    return formatDialogNumber(next);
}

function describeDialogRange(field) {
    if (field.inputType !== 'number') return '';
    if (field.min !== undefined && field.max !== undefined) return `${formatDialogNumber(field.min)} – ${formatDialogNumber(field.max)}`;
    if (field.min !== undefined) return `Min ${formatDialogNumber(field.min)}`;
    if (field.max !== undefined) return `Max ${formatDialogNumber(field.max)}`;
    return '';
}

/** Returns { [fieldName]: message } for every field that blocks Confirm. */
function validateContextValues(fields, values) {
    const errors = {};
    const source = isRecord(values) ? values : {};
    for (const field of Array.isArray(fields) ? fields : []) {
        if (!isRecord(field) || !isSafeObjectKey(field.name) || field.type === 'checkbox') continue;
        const value = Object.prototype.hasOwnProperty.call(source, field.name) ? source[field.name] : undefined;

        if (field.type === 'select') {
            const options = Array.isArray(field.options) ? field.options : [];
            const chosen = value !== undefined && options.some(option => Object.is(contextOptionValue(option), value));
            if (field.required && !chosen) errors[field.name] = 'Choose an option to continue.';
            continue;
        }

        const text = value === undefined || value === null ? '' : String(value);
        if (!text.trim()) {
            if (field.required) errors[field.name] = 'Enter a value to continue.';
            continue;
        }
        if (field.inputType !== 'number') continue;
        const number = parseDialogNumber(text);
        if (number === null) errors[field.name] = 'Enter a number.';
        else if (field.min !== undefined && number < field.min) errors[field.name] = `Minimum is ${formatDialogNumber(field.min)}.`;
        else if (field.max !== undefined && number > field.max) errors[field.name] = `Maximum is ${formatDialogNumber(field.max)}.`;
    }
    return errors;
}

/** Declared fields only; number text is trimmed so Lua parses what the player saw. */
function contextResultValues(fields, values) {
    const result = {};
    const source = isRecord(values) ? values : {};
    for (const field of Array.isArray(fields) ? fields : []) {
        if (!isRecord(field) || !isSafeObjectKey(field.name)) continue;
        if (!Object.prototype.hasOwnProperty.call(source, field.name)) continue;
        const value = source[field.name];
        result[field.name] = field.type !== 'select' && field.type !== 'checkbox' && field.inputType === 'number' && typeof value === 'string'
            ? value.trim()
            : value;
    }
    return result;
}

// ============================================================================
// SHARED DIALOG PIECES
// ============================================================================

/** Keeps a closing dialog mounted long enough to play its exit. */
function useDialogPresence(open) {
    const [present, setPresent] = useState(open);
    useEffect(() => {
        if (open) {
            setPresent(true);
            return undefined;
        }
        const timer = window.setTimeout(() => setPresent(false), DIALOG_LEAVE_MS);
        return () => window.clearTimeout(timer);
    }, [open]);
    return open || present;
}

/** Tracks whether a scroll region has content above/below, for the fading edges. */
function useDialogScrollEdges(scrollRef, watchKey) {
    const [edges, setEdges] = useState('');
    useEffect(() => {
        const element = scrollRef.current;
        if (!element) {
            setEdges('');
            return undefined;
        }
        let frame = 0;
        const measure = () => {
            frame = 0;
            const top = element.scrollTop > 2;
            const bottom = element.scrollTop + element.clientHeight < element.scrollHeight - 2;
            const next = `${top ? ' fade-top' : ''}${bottom ? ' fade-bottom' : ''}`;
            setEdges(previous => previous === next ? previous : next);
        };
        const schedule = () => {
            if (!frame) frame = window.requestAnimationFrame(measure);
        };
        measure();
        element.addEventListener('scroll', schedule, { passive: true });
        window.addEventListener('resize', schedule);
        const observer = typeof ResizeObserver === 'function' ? new ResizeObserver(schedule) : null;
        if (observer) {
            observer.observe(element);
            Array.from(element.children).forEach(child => observer.observe(child));
        }
        return () => {
            if (frame) window.cancelAnimationFrame(frame);
            element.removeEventListener('scroll', schedule);
            window.removeEventListener('resize', schedule);
            observer?.disconnect();
        };
    }, [scrollRef, watchKey]);
    return edges;
}

function stopDialogEvent(event) {
    event.stopPropagation();
}

/** Body copy: blank lines split paragraphs, single newlines stay line breaks. */
function DialogCopy({ id, text }) {
    const paragraphs = String(text || '')
        .split(/\n[ \t]*\n+/)
        .map(paragraph => paragraph.replace(/^\n+|\n+$/g, ''))
        .filter(paragraph => paragraph.trim())
        .slice(0, DIALOG_MAX_PARAGRAPHS);
    return React.createElement('div', { id, className: 'cx-dialog-copy' },
        paragraphs.map((paragraph, index) => React.createElement('p', { key: index }, paragraph)));
}

/**
 * Keycap buttons. The primary action wears the paper face (it is what Enter
 * does); when the secondary takes keyboard focus the paper face moves to it.
 */
function DialogActions({ confirmLabel, cancelLabel, showCancel, onConfirm, onCancel, pending, autofocusConfirm }) {
    const kit = window.CortexKit;
    const [focused, setFocused] = useState(null);
    const cancelHasFace = showCancel && focused === 'cancel';

    const action = (kind, key, label, onClick, paper, extra = {}) => React.createElement('button', {
        type: 'button',
        className: `cx-dialog-action cx-dialog-action--${kind}${paper ? ' is-paper' : ''}${kind === 'confirm' && pending ? ' is-pending' : ''}`,
        onClick,
        onFocus: () => setFocused(kind),
        onBlur: () => setFocused(current => current === kind ? null : current),
        ...extra
    },
        React.createElement(kit.Keycap, { value: key, size: 'sm' }),
        React.createElement('span', { className: 'cx-dialog-action-label' }, label)
    );

    return React.createElement('div', { className: 'cx-dialog-actions' },
        showCancel ? action('cancel', 'ESC', cancelLabel, onCancel, cancelHasFace) : null,
        action('confirm', 'ENTER', confirmLabel, onConfirm, !cancelHasFace, {
            'data-autofocus': autofocusConfirm ? 'true' : undefined,
            'aria-busy': pending ? 'true' : undefined
        })
    );
}

function DialogFailure({ message }) {
    if (!message) return null;
    return React.createElement('p', { className: 'cx-dialog-failure', role: 'alert' }, message);
}

function contextFailureMessage(response) {
    if (response?.error === 'invalid_values') return 'Some values were not accepted. Check the fields and try again.';
    return 'Could not submit. Try again.';
}

// ============================================================================
// ALERT DIALOG COMPONENT
// ============================================================================

function AlertDialog({ open, session, header, content, centered, cancel, labels, style, onClose }) {
    const confirmLabel = labels?.confirm || 'CONFIRM';
    const cancelLabel = labels?.cancel || 'CANCEL';
    const dialogRef = useRef(null);
    const scrollRef = useRef(null);
    const pendingRef = useRef(false);
    const [pending, setPending] = useState(false);
    const [failure, setFailure] = useState('');
    const present = useDialogPresence(open);
    const edges = useDialogScrollEdges(scrollRef, `${present}:${session}:${content}`);

    useEffect(() => {
        pendingRef.current = false;
        setPending(false);
        setFailure('');
    }, [open, session]);

    const handleCancel = useCallback(() => {
        if (pendingRef.current) return;
        if (cancel) onClose('cancel', session);
    }, [cancel, onClose, session]);

    const handleConfirm = useCallback(async () => {
        if (pendingRef.current) return;
        pendingRef.current = true;
        setPending(true);
        setFailure('');
        const response = await onClose('confirm', session);
        pendingRef.current = false;
        setPending(false);
        if (response && response.ok !== true && response.error !== 'aborted') setFailure('Could not confirm. Try again.');
    }, [onClose, session]);

    useModalFocus(open, dialogRef, cancel ? handleCancel : null, session);

    if (!present) return null;
    const kit = window.CortexKit;

    const handleKeyDown = (event) => {
        if (event.defaultPrevented) return;
        const scroller = scrollRef.current;
        if (event.key === 'Enter' && event.target === event.currentTarget) {
            event.preventDefault();
            void handleConfirm();
        } else if (scroller && ['ArrowDown', 'ArrowUp', 'PageDown', 'PageUp'].includes(event.key) && event.target !== scroller) {
            // Long copy stays readable from the keyboard while focus rests on an action.
            event.preventDefault();
            const page = Math.max(40, scroller.clientHeight - 48);
            const delta = { ArrowDown: 48, ArrowUp: -48, PageDown: page, PageUp: -page }[event.key];
            scroller.scrollBy({ top: delta, behavior: 'smooth' });
        }
    };

    return React.createElement('div', {
        className: `cx-dialog-layer${open ? '' : ' is-leaving'}`,
        onMouseDown: handleCancel
    },
        React.createElement('div', {
            ref: dialogRef,
            className: `cx-dialog cx-dialog--alert${centered ? ' is-centered' : ''}`,
            role: 'dialog',
            'aria-modal': true,
            'aria-labelledby': header ? 'cortex-alert-title' : undefined,
            'aria-label': header ? undefined : 'Confirmation',
            'aria-describedby': content ? 'cortex-alert-content' : undefined,
            tabIndex: -1,
            style: normalizeAlertStyle(style),
            onMouseDown: stopDialogEvent,
            onClick: stopDialogEvent,
            onContextMenu: (event) => event.preventDefault(),
            onKeyDown: handleKeyDown
        },
            header ? React.createElement('div', { className: 'cx-dialog-head' },
                React.createElement(kit.SlipHeader, { id: 'cortex-alert-title', title: header })
            ) : null,
            content ? React.createElement('div', {
                ref: scrollRef,
                className: `cx-dialog-scroll cx-scroll${edges}`
            }, React.createElement(DialogCopy, { id: 'cortex-alert-content', text: content })) : null,
            React.createElement(DialogFailure, { message: failure }),
            React.createElement(DialogActions, {
                confirmLabel,
                cancelLabel,
                showCancel: cancel,
                onConfirm: () => void handleConfirm(),
                onCancel: handleCancel,
                pending,
                autofocusConfirm: true
            })
        )
    );
}

// ============================================================================
// CONTEXT MENU COMPONENT (input form: checkbox / select / input / text fields)
// ============================================================================

function ContextMenuCheckbox({ field, value, onChange, inputId, describedBy, descriptionId }) {
    const kit = window.CortexKit;
    const checked = value === true;
    return React.createElement('button', {
        type: 'button',
        id: inputId,
        className: `cx-dialog-check${checked ? ' is-checked' : ''}`,
        role: 'checkbox',
        'aria-checked': checked,
        'aria-describedby': describedBy,
        onClick: () => onChange(field.name, !checked)
    },
        React.createElement(kit.CheckMark, { checked }),
        React.createElement('span', { className: 'cx-dialog-check-text' },
            React.createElement('span', { className: 'cx-dialog-check-label' }, field.label),
            field.description
                ? React.createElement('span', { id: descriptionId, className: 'cx-dialog-hint' }, field.description)
                : null
        )
    );
}

function ContextMenuInput({ field, value, onChange, inputId, describedBy, invalid, autoFocus }) {
    const [revealed, setRevealed] = useState(false);
    const isPassword = field.inputType === 'password';
    const isNumber = field.inputType === 'number';
    const text = value === undefined || value === null ? '' : String(value);
    const current = isNumber ? parseDialogNumber(text) : null;
    const atMin = current !== null && field.min !== undefined && current <= field.min;
    const atMax = current !== null && field.max !== undefined && current >= field.max;

    const step = (direction, multiplier = 1) => onChange(field.name, stepDialogNumber(field, text, direction, multiplier));

    const stepButton = (direction, disabled) => React.createElement('button', {
        type: 'button',
        className: `cx-dialog-step cx-dialog-step--${direction > 0 ? 'up' : 'down'}`,
        tabIndex: -1,
        disabled,
        'aria-label': `${direction > 0 ? 'Increase' : 'Decrease'} ${field.label}`,
        onMouseDown: (event) => event.preventDefault(),
        onClick: () => step(direction)
    });

    let inputType = field.inputType || 'text';
    if (isNumber || (isPassword && revealed)) inputType = 'text';

    return React.createElement('span', {
        className: `cx-dialog-well${invalid ? ' is-invalid' : ''}${isNumber ? ' is-number' : ''}`
    },
        React.createElement('input', {
            className: 'cx-dialog-input',
            id: inputId,
            type: inputType,
            inputMode: isNumber ? 'decimal' : undefined,
            placeholder: field.placeholder || '',
            value: text,
            maxLength: 512,
            autoComplete: 'off',
            spellCheck: false,
            required: field.required === true,
            'aria-required': field.required === true,
            'aria-invalid': invalid ? 'true' : undefined,
            'aria-describedby': describedBy,
            'data-autofocus': autoFocus ? 'true' : undefined,
            onChange: (event) => onChange(field.name, event.target.value),
            onKeyDown: isNumber ? (event) => {
                if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
                event.preventDefault();
                step(event.key === 'ArrowUp' ? 1 : -1, event.shiftKey ? 10 : 1);
            } : undefined
        }),
        isPassword ? React.createElement('button', {
            type: 'button',
            className: 'cx-dialog-reveal',
            'aria-pressed': revealed,
            'aria-label': revealed ? `Hide ${field.label}` : `Show ${field.label}`,
            onMouseDown: (event) => event.preventDefault(),
            onClick: () => setRevealed(shown => !shown)
        }, revealed ? 'Hide' : 'Show') : null,
        isNumber ? React.createElement('span', { className: 'cx-dialog-stepper' },
            stepButton(-1, atMin),
            stepButton(1, atMax)
        ) : null
    );
}

function ContextMenuField({ field, index, value, error, onChange, autoFocus }) {
    const kit = window.CortexKit;
    const inputId = `cortex-context-field-${index}`;
    const labelId = `${inputId}-label`;
    const descriptionId = `${inputId}-description`;
    const errorId = `${inputId}-error`;
    const describedBy = [field.description ? descriptionId : null, error ? errorId : null].filter(Boolean).join(' ') || undefined;
    const invalid = Boolean(error);
    const errorNode = error ? React.createElement('p', { id: errorId, className: 'cx-dialog-error' }, error) : null;

    if (field.type === 'checkbox') {
        return React.createElement('div', { className: 'cx-dialog-field cx-dialog-field--check' },
            React.createElement(ContextMenuCheckbox, { field, value, onChange, inputId, describedBy, descriptionId }),
            errorNode
        );
    }

    const range = describeDialogRange(field);
    let control = null;
    if (field.type === 'select') {
        control = React.createElement(kit.Dropdown, {
            id: inputId,
            options: field.options,
            value,
            label: field.label,
            labelledBy: labelId,
            describedBy,
            placeholder: field.placeholder || 'Select',
            scope: 'cx-dialog-menu',
            onChange: (next) => onChange(field.name, next)
        });
    } else {
        control = React.createElement(ContextMenuInput, { field, value, onChange, inputId, describedBy, invalid, autoFocus });
    }

    const unset = field.type === 'select'
        && !(Array.isArray(field.options) ? field.options : []).some(option => Object.is(contextOptionValue(option), value));
    return React.createElement('div', { className: `cx-dialog-field${invalid ? ' is-invalid' : ''}${unset ? ' is-unset' : ''}` },
        React.createElement('div', { className: 'cx-dialog-field-head' },
            React.createElement('label', { id: labelId, className: 'cx-dialog-label', htmlFor: inputId },
                React.createElement('span', { className: 'cx-dialog-label-text' }, field.label),
                field.required ? React.createElement('span', { className: 'cx-dialog-required', 'aria-hidden': 'true' }) : null,
                field.required ? React.createElement('span', { className: 'cortex-sr-only' }, ' (required)') : null
            ),
            range ? React.createElement('span', { className: 'cx-dialog-range', 'aria-hidden': 'true' }, range) : null
        ),
        field.description ? React.createElement('p', { id: descriptionId, className: 'cx-dialog-hint' }, field.description) : null,
        control,
        errorNode
    );
}

function focusContextField(dialog, index) {
    const element = dialog?.querySelector(`#cortex-context-field-${index}`);
    if (!element) return;
    focusElement(element);
    element.scrollIntoView?.({ block: 'nearest' });
}

function ContextMenu({ open, session, title, fields, values, labels, onClose }) {
    const [formValues, setFormValues] = useState({});
    const [attempted, setAttempted] = useState(false);
    const [pending, setPending] = useState(false);
    const [failure, setFailure] = useState('');
    const pendingRef = useRef(false);
    const dialogRef = useRef(null);
    const scrollRef = useRef(null);
    const confirmLabel = labels?.confirm || 'CONFIRM';
    const cancelLabel = labels?.cancel || 'CANCEL';
    const present = useDialogPresence(open);
    const list = React.useMemo(
        () => (Array.isArray(fields) ? fields : []).filter(field => isRecord(field) && isSafeObjectKey(field.name)),
        [fields]
    );

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
                        // Text fields travel as strings (the Lua result contract).
                        nextValues[field.name] = String(normalizeScalarValue(sourceValue));
                    }
                }
            }
            setFormValues(nextValues);
            setAttempted(false);
            setFailure('');
            pendingRef.current = false;
            setPending(false);
        }
    }, [fields, open, session, values]);

    const errors = React.useMemo(
        () => (attempted ? validateContextValues(list, formValues) : {}),
        [attempted, list, formValues]
    );
    const edges = useDialogScrollEdges(scrollRef, `${present}:${session}:${list.length}`);

    const handleChange = useCallback((name, value) => {
        setFormValues(prev => ({ ...prev, [name]: value }));
        setFailure('');
    }, []);

    const handleConfirm = useCallback(async () => {
        if (pendingRef.current) return;
        const found = validateContextValues(list, formValues);
        const firstInvalid = list.findIndex(field => Object.prototype.hasOwnProperty.call(found, field.name));
        if (firstInvalid >= 0) {
            setAttempted(true);
            focusContextField(dialogRef.current, firstInvalid);
            return;
        }
        pendingRef.current = true;
        setPending(true);
        setFailure('');
        const response = await onClose('confirm', contextResultValues(list, formValues), session);
        pendingRef.current = false;
        setPending(false);
        if (response && response.ok !== true && response.error !== 'aborted') setFailure(contextFailureMessage(response));
    }, [formValues, list, onClose, session]);

    const handleCancel = useCallback(() => {
        if (pendingRef.current) return;
        onClose('cancel', null, session);
    }, [onClose, session]);

    useModalFocus(open, dialogRef, handleCancel, session);

    if (!present) return null;
    const kit = window.CortexKit;
    const firstTextIndex = list.findIndex(field => field.type === 'input' || field.type === 'text');
    const hasRequired = list.some(field => field.required && field.type !== 'checkbox');

    const handleKeyDown = (event) => {
        if (event.key !== 'Enter' || event.defaultPrevented || event.altKey || event.shiftKey) return;
        const target = event.target;
        const fromEntry = target === event.currentTarget
            || target?.tagName === 'INPUT'
            || target?.getAttribute?.('role') === 'checkbox';
        if (!fromEntry && !event.ctrlKey) return;
        event.preventDefault();
        void handleConfirm();
    };

    const legend = hasRequired
        ? React.createElement('span', { className: 'cx-dialog-legend' },
            React.createElement('span', { className: 'cx-dialog-required', 'aria-hidden': 'true' }),
            'Required')
        : null;

    return React.createElement('div', {
        className: `cx-dialog-layer${open ? '' : ' is-leaving'}`,
        onMouseDown: handleCancel
    },
        React.createElement('div', {
            ref: dialogRef,
            className: 'cx-dialog cx-dialog--form',
            role: 'dialog',
            'aria-modal': true,
            'aria-labelledby': title ? 'cortex-context-title' : undefined,
            'aria-label': title ? undefined : 'Context options',
            tabIndex: -1,
            onMouseDown: stopDialogEvent,
            onClick: stopDialogEvent,
            onKeyDown: handleKeyDown
        },
            title ? React.createElement('div', { className: 'cx-dialog-head' },
                React.createElement(kit.SlipHeader, { id: 'cortex-context-title', title, meta: legend })
            ) : null,
            list.length ? React.createElement('div', {
                ref: scrollRef,
                className: `cx-dialog-scroll cx-scroll${edges}`
            },
                React.createElement('div', { className: 'cx-dialog-form' },
                    list.map((field, index) => React.createElement(ContextMenuField, {
                        key: `${field.name}-${index}`,
                        field,
                        index,
                        value: formValues[field.name],
                        error: errors[field.name] || '',
                        onChange: handleChange,
                        autoFocus: index === firstTextIndex
                    }))
                )
            ) : null,
            React.createElement(DialogFailure, { message: failure }),
            React.createElement(DialogActions, {
                confirmLabel,
                cancelLabel,
                showCancel: true,
                onConfirm: () => void handleConfirm(),
                onCancel: handleCancel,
                pending,
                autofocusConfirm: firstTextIndex < 0
            })
        )
    );
}
