/* Cortex library NUI: root composition and the message router. Surfaces live
 * in ui/surfaces, shared helpers in ui/core. */

let notifyIdCounter = 0;

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
        gameControls: false,
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
        appearance: null,
        trail: [],
        focusIndex: null,
        view: 0
    });

    const [contextMenu, setContextMenu] = useState({
        open: false,
        session: null,
        title: '',
        fields: [],
        values: {},
        labels: { confirm: 'CONFIRM', cancel: 'CANCEL' }
    });

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
        // token restarts the timer when a new action replaces a running one.
        setProgress(prev => ({
            active: true,
            ...normalized,
            outcome: null,
            token: (prev.token || 0) + 1
        }));
    }, []);

    const endProgress = useCallback((data) => {
        setProgress(prev => ({ ...prev, active: false, outcome: normalizeProgressOutcome(data) }));
    }, []);

    const closeAlertDialog = useCallback(async (result, session) => {
        const normalizedSession = normalizeSession(session);
        const response = await nuiPost('alertDialogResult', { result, session });
        if (response?.ok !== true) return response;
        setAlertDialog(prev => prev.session === normalizedSession
            ? { ...prev, open: false }
            : prev);
        return response;
    }, []);

    const closeContextMenu = useCallback(async (result, values, session) => {
        const normalizedSession = normalizeSession(session);
        const response = await nuiPost('contextMenuResult', { result, values: isRecord(values) ? values : null, session });
        if (response?.ok !== true) return response;
        setContextMenu(prev => prev.session === normalizedSession
            ? { ...prev, open: false }
            : prev);
        return response;
    }, []);

    const openMenu = useCallback((data) => {
        const normalizedOptions = Array.isArray(data?.options)
            ? data.options.slice(0, NUI_MAX_MENU_OPTIONS).map(normalizeOption)
            : [];

        const requestedStart = Number.isInteger(data?.startIndex) ? data.startIndex : 1;
        const initialSelected = normalizedOptions.length
            ? Math.max(1, Math.min(requestedStart, normalizedOptions.length))
            : 0;
        const tooltip = normalizedOptions.length ? getOptionTooltip(normalizedOptions[initialSelected - 1]) : '';

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
            gameControls: data?.gameControls === true,
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
                case 'menuNav':
                    // Game-control menus have no NUI focus; Lua forwards their input here.
                    window.dispatchEvent(new CustomEvent('cortex-menu-nav', { detail: data }));
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
                    endProgress(data);
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
                    setHelp({ open: true, items: normalizeHelpItems(data.items), compact: data.compact === true });
                    break;
                case 'helpHide':
                    setHelp(prev => ({ ...prev, open: false }));
                    break;
                case 'radialShow':
                    setRadial(prev => ({
                        open: true,
                        id: boundedText(data.menuId, '', 96) || null,
                        session: normalizeSession(data.session),
                        items: normalizeRadialItems(data.items),
                        canGoBack: Boolean(data.canGoBack),
                        appearance: data.appearance === 'compact-control' ? 'compact-control' : null,
                        visible: true,
                        trail: normalizeRadialTrail(data.trail),
                        focusIndex: null,
                        view: prev.view + 1
                    }));
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
                        appearance: data.appearance !== undefined ? (data.appearance === 'compact-control' ? 'compact-control' : null) : prev.appearance,
                        trail: Array.isArray(data.trail) ? normalizeRadialTrail(data.trail) : prev.trail
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
                        visible: true,
                        trail: normalizeRadialTrail(data.trail),
                        focusIndex: normalizeRadialFocusIndex(data.focusIndex),
                        view: prev.view + 1
                    }) : prev);
                    break;
                case 'settingsOpen':
                    setSettingsPanel({
                        open: true,
                        session: normalizeSession(data.session),
                        tabs: normalizeSettingsTabs(data.tabs),
                        page: data.page === 'home' ? 'home' : 'settings',
                        pause: window.CortexPause.normalize(data.pause)
                    });
                    break;
                case 'pauseUpdate':
                    setSettingsPanel(prev => prev.open && prev.session === normalizeSession(data.session)
                        ? { ...prev, pause: window.CortexPause.normalize(data.pause) } : prev);
                    break;
                case 'pauseInput':
                    window.dispatchEvent(new CustomEvent('cortex-pause-input', { detail: data }));
                    break;
                case 'settingsClose':
                    setSettingsPanel(prev => prev.session === normalizeSession(data.session)
                        ? { ...prev, open: false }
                        : prev);
                    break;
                case 'cortex:prefs':
                    window.CortexKit.setPrefs(data.prefs);
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
        React.createElement(Menu, { ...menu, setMenu }),
        React.createElement(MemoizedSettingsPanel, { ...settingsPanel, onClose: closeSettingsPanelLocal }),
        React.createElement(InteractionSurface, { hidden: settingsPanel.open }),
        React.createElement(window.CortexSkillChecks.Surface),
        React.createElement(window.CortexDebug.Workbench, { post: nuiPost, ProgressBar })
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
