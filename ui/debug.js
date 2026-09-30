/* One shared React root. Lua owns the catalog, execution and modal session. */
(() => {
    const h = React.createElement;
    const { useState, useRef, useEffect, useCallback } = React;
    const bounded = (value, limit = 256) => typeof value === 'string' ? value.slice(0, limit) : '';
    function normalizeCatalog(value) {
        return Array.isArray(value) ? value.slice(0, 100).filter(item => item && /^[a-z_]{1,48}$/.test(item.id)
            && typeof item.title === 'string' && typeof item.group === 'string').map(item => ({
            id: item.id, title: bounded(item.title, 96), group: bounded(item.group, 64), description: bounded(item.description, 512)
        })) : [];
    }
    function normalizeHistory(value) {
        return Array.isArray(value) ? value.slice(0, 100).filter(item => item && typeof item.id === 'string').map(item => ({
            id: bounded(item.id, 48), status: ['running', 'result', 'error'].includes(item.status) ? item.status : 'result',
            detail: bounded(item.detail, 512)
        })) : [];
    }
    const normalizeRun = value => value && Number.isSafeInteger(value.index) && Number.isSafeInteger(value.total)
        && Number.isSafeInteger(value.completed) && value.completed >= 0 && value.completed <= value.total
        && value.index > 0 && value.index <= value.total && value.total <= 100
        ? { index: value.index, completed: value.completed, total: value.total, id: bounded(value.id, 48), title: bounded(value.title, 96) } : null;
    const placements = ['top-right', 'top-left', 'top', 'bottom-right', 'bottom-left', 'bottom'];
    const samples = ['Vehicle spawned.', 'Started cortex_mdtsv', 'Started cortex-subtleadditions', 'Equipment updated. Return to the depot to collect your replacement.'];
    function Workbench({ post, ProgressBar }) {
        const [walkthrough, setWalkthrough] = useState(null);
        const runRevision = useRef(0);
        const [state, setState] = useState(null);
        const [page, setPage] = useState('');
        const [selected, setSelected] = useState(0);
        const [duration, setDuration] = useState(5000);
        const [position, setPosition] = useState(0);
        const [sample, setSample] = useState(0);
        const [pending, setPending] = useState(false);
        const [error, setError] = useState('');
        const activeSession = useRef(null);
        const input = useRef(() => {});
        const inFlight = useRef(false);
        useEffect(() => {
            const listener = event => {
                const { action, data } = event.data || {};
                if (action === 'debug:walkthrough') {
                    if (data && Number.isSafeInteger(data.revision) && data.revision > runRevision.current) {
                        runRevision.current = data.revision;
                        setWalkthrough(normalizeRun(data.run));
                    }
                    return;
                }
                if (!data || !Number.isSafeInteger(data.session) || data.session <= 0) return;
                if (action === 'debug:open') {
                    activeSession.current = data.session;
                    inFlight.current = false; setPending(false); setError('');
                    setState({ session: data.session, catalog: normalizeCatalog(data.catalog), history: normalizeHistory(data.history) });
                } else if (data.session === activeSession.current) {
                    if (action === 'debug:close') {
                        activeSession.current = null; inFlight.current = false; setState(null); setPending(false);
                    } else if (action === 'debug:history') {
                        setState(current => current ? { ...current, history: normalizeHistory(data.history) } : null);
                    } else if (action === 'debug:input') input.current(data.input);
                }
            };
            window.addEventListener('message', listener);
            return () => window.removeEventListener('message', listener);
        }, []);
        useEffect(() => {
            if (!state || walkthrough) return;
            const session = state.session;
            post('debugReady', { session }).then(reply => {
                if (activeSession.current === session && reply?.ok !== true) setError(reply?.error || 'Input unavailable. Use /cortexdebug to close.');
            });
        }, [state?.session, Boolean(walkthrough), post]);
        if (walkthrough) {
            input.current = () => {};
            return h(ProgressBar, { active: true, id: 'debug-test-all', style: 'bar', position: 'middle',
                value: walkthrough.completed / walkthrough.total * 100,
                label: `Test All · ${walkthrough.completed} / ${walkthrough.total} · ${walkthrough.title}`,
                hint: '/cortexdebug to stop' });
        }
        if (!state) { input.current = () => {}; return null; }
        const request = async (endpoint, payload = {}) => {
            if (inFlight.current && !['debugClose', 'debugStop'].includes(endpoint)) return;
            const session = state.session;
            inFlight.current = true; setPending(true); setError('');
            const reply = await post(endpoint, { session, ...payload });
            if (activeSession.current !== session) return;
            inFlight.current = false; setPending(false);
            if (reply?.ok !== true) setError(reply?.error || 'Request failed.');
        };
        const navigate = next => { setPage(next); setSelected(0); setError(''); };
        const cycle = (value, delta, length) => (value + delta + length) % length;
        const options = { duration, position: placements[position], message: samples[sample] };
        const run = item => request('debugRun', { id: item.id, options });
        const groups = [...new Set(state.catalog.map(item => item.group))];
        let rows;
        if (page === 'Test options') rows = [
            { id: 'duration', title: 'Duration', value: `${duration / 1000}s`, description: 'Applies to notification and progress tests.', adjust: d => setDuration(v => (cycle(v / 1000 - 1, d, 15) + 1) * 1000) },
            { id: 'position', title: 'Notification position', value: placements[position], description: 'Cycle through all six placements.', adjust: d => setPosition(v => cycle(v, d, placements.length)) },
            { id: 'sample', title: 'Message sample', value: `${sample + 1} / ${samples.length}`, description: samples[sample], adjust: d => setSample(v => cycle(v, d, samples.length)) }
        ];
        else if (page) rows = state.catalog.filter(item => page === 'All tests' || item.group === page).map(item => ({ ...item, action: () => run(item) }));
        else rows = [
            ...groups.map(group => ({ id: group, title: group, value: state.catalog.filter(item => item.group === group).length, action: () => navigate(group) })),
            { id: 'test_all', title: 'Test All', description: 'Run every test in sequence. Close interactive tests to continue; /cortexdebug stops the walkthrough.', action: () => request('debugRunAll', { options }) },
            { id: 'all', title: 'All tests', value: state.catalog.length, action: () => navigate('All tests') },
            { id: 'options', title: 'Test options', value: '›', action: () => navigate('Test options') },
            { id: 'clear', title: 'Clear active tests', description: 'Remove temporary fixtures and reset results.', action: () => request('debugClear') },
            { id: 'close', title: 'Close menu', action: () => request('debugClose') }
        ];
        const index = Math.min(selected, Math.max(0, rows.length - 1));
        const row = rows[index];
        const enter = () => { if (!inFlight.current) row?.adjust ? row.adjust(1) : row?.action?.(); };
        input.current = command => {
            if (command === 'back') { if (page) navigate(''); else request('debugClose'); }
            else if (command === 'up' || command === 'down') setSelected(v => cycle(v, command === 'up' ? -1 : 1, rows.length || 1));
            else if (command === 'left' || command === 'right') row?.adjust?.(command === 'left' ? -1 : 1);
            else if (command === 'enter') enter();
        };
        const start = Math.max(0, index - 8);
        const visible = rows.slice(start, start + 9);
        const result = row && state.history.find(entry => entry.id === row.id);
        return h('section', { className: 'debug-menu', 'aria-labelledby': 'debug-title' },
            h('header', { className: 'debug-menu-header' }, h('h1', { id: 'debug-title' }, 'Cortex', h('span', null, ' Debug')), h('span', null, `${state.catalog.length} tests`)),
            h('div', { className: 'debug-menu-location' }, h('span', null, page || 'Library'), h('span', null, `${index + 1} / ${rows.length}`)),
            h('div', { className: 'debug-menu-list', role: 'menu', 'aria-label': page || 'Library tests', 'aria-activedescendant': `debug-row-${index}` },
                visible.map((entry, offset) => h('button', { key: entry.id, id: `debug-row-${start + offset}`, type: 'button', role: 'menuitem', tabIndex: -1,
                    className: `debug-menu-row${start + offset === index ? ' selected' : ''}`, onClick: () => { if (!inFlight.current) entry.adjust ? entry.adjust(1) : entry.action?.(); } },
                    h('span', null, entry.title), h('span', { className: 'debug-menu-value' }, entry.adjust ? `‹ ${entry.value} ›` : entry.value ?? '')))),
            h('div', { className: 'debug-menu-detail', role: error ? 'alert' : 'status' },
                h('p', null, error || (pending ? 'Starting…' : row?.description || 'Scroll to select. Left-click to open.')),
                result && h('p', { className: `debug-menu-result ${result.status}` }, result.detail)),
            h('footer', { className: 'debug-menu-hints' }, h('span', null, 'Scroll ↑↓'), h('span', null, 'LMB Enter'), h('span', null, 'RMB Back')));
    }
    window.CortexDebug = { Workbench, normalizeCatalog, normalizeHistory };
})();
