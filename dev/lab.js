import { scenarios } from './scenarios.mjs';

const $ = id => document.getElementById(id);
const frame = $('preview');
let current = scenarios.find(item => item.id === location.hash.slice(1)) || scenarios[0];
let ready = false, run = 0, tour = null, tourQueue = [], logs = [], failNext = false;
let size = '1920x1080', backdrop = 'dark', customImage = '', zoom = 1;
const visited = new Set();
const send = (kind, data) => { if (ready) frame.contentWindow.postMessage({ lab: true, kind, data }, location.origin); };
const status = text => { $('status').textContent = text; };
function log(kind, data) {
    logs.push(`${new Date().toLocaleTimeString()}  ${kind}\n${typeof data === 'string' ? data : JSON.stringify(data, null, 2)}`);
    logs = logs.slice(-120);
    $('log').textContent = logs.join('\n\n');
    $('log').scrollTop = $('log').scrollHeight;
}
function renderCatalog() {
    const query = $('search').value.trim().toLowerCase();
    const filtered = scenarios.filter(item => `${item.group} ${item.title} ${item.description}`.toLowerCase().includes(query));
    $('count').textContent = `${filtered.length} scenarios · ${visited.size} visited`;
    const fragment = document.createDocumentFragment();
    for (const group of [...new Set(filtered.map(item => item.group))]) {
        const heading = document.createElement('h3'); heading.textContent = group; fragment.append(heading);
        for (const item of filtered.filter(item => item.group === group)) {
            const button = document.createElement('button'); button.textContent = item.title;
            button.setAttribute('aria-current', String(item.id === current.id)); button.dataset.scenario = item.id;
            button.addEventListener('click', () => { stopTour(); select(item); });
            if (visited.has(item.id)) { const marker = document.createElement('small'); marker.textContent = 'Seen'; button.append(marker); }
            fragment.append(button);
        }
    }
    if (!filtered.length) { const empty = document.createElement('p'); empty.textContent = 'No matching scenarios.'; fragment.append(empty); }
    $('scenarios').replaceChildren(fragment);
}
function select(item) {
    current = item;
    history.replaceState(null, '', `#${item.id}`);
    $('group').textContent = item.group; $('title').textContent = item.title; $('description').textContent = item.description;
    $('payload').value = JSON.stringify(item.messages, null, 2);
    failNext = Boolean(item.failNext); $('fail').setAttribute('aria-pressed', String(failNext));
    ready = false; run++; status('Loading real UI…');
    frame.src = `/preview?run=${run}`;
    renderCatalog();
}
function stopTour() {
    clearTimeout(tour); tour = null; tourQueue = [];
    $('tour').textContent = 'Tour all'; $('tour').setAttribute('aria-pressed', 'false');
}
function advanceTour() {
    if (!tourQueue.length) { stopTour(); status('Tour finished. Visited means displayed, not tested or passed.'); return; }
    select(tourQueue.shift());
}
function startTour() {
    stopTour(); tourQueue = [...scenarios];
    $('tour').textContent = 'Stop tour'; $('tour').setAttribute('aria-pressed', 'true'); advanceTour();
}
function fitStage() {
    const area = $('stage-scroll');
    // Leave a pixel for rounded client dimensions so Fit cannot toggle scrollbars
    // and feed a resize back into its own iframe on fractional/DPI layouts.
    const availableWidth = Math.max(1, area.clientWidth - 1), availableHeight = Math.max(1, area.clientHeight - 1);
    const [width, height] = size === 'fit' ? [Math.max(320, availableWidth), Math.max(300, availableHeight)] : size.split('x').map(Number);
    const scale = Math.min(availableWidth / width, availableHeight / height) * zoom;
    Object.assign($('stage').style, { width: `${width}px`, height: `${height}px`, transform: `scale(${scale})` });
    Object.assign($('stage-space').style, { width: `${Math.floor(width * scale)}px`, height: `${Math.floor(height * scale)}px` });
    $('dimensions').textContent = `${width} × ${height} · ${Math.round(scale * 100)}% display`;
}
function setBackground(value) {
    backdrop = value; $('stage').dataset.background = value;
    $('stage').style.backgroundImage = value === 'image' ? `url("${customImage}")` : '';
    for (const button of $('backgrounds').querySelectorAll('button')) button.setAttribute('aria-pressed', String(button.dataset.background === value));
}
window.addEventListener('message', event => {
    if (event.origin !== location.origin || event.source !== frame.contentWindow || !event.data?.lab || String(event.data.run) !== String(run)) return;
    const { kind, data } = event.data;
    if (kind === 'ready') {
        ready = true; visited.add(current.id); renderCatalog();
        send('configure', { behavior: current.behavior, failNext }); send('messages', current.messages);
        status('Ready · click the stage to interact');
        log('Scenario', current.id);
        if ($('tour').getAttribute('aria-pressed') === 'true') tour = setTimeout(advanceTour, Math.max(5000, ...current.messages.map(item => (item.after || 0) + 1500)));
    } else if (kind === 'navigate') {
        const item = scenarios.find(entry => entry.id === data); if (item) select(item);
    } else if (kind === 'tour') startTour();
    else if (kind === 'failNext') { failNext = data; $('fail').setAttribute('aria-pressed', String(data)); }
    else { log(kind, data); if (kind === 'error') status(`UI error · ${data}`); }
});
$('search').addEventListener('input', renderCatalog);
$('replay').addEventListener('click', () => { stopTour(); select(current); });
$('reset').addEventListener('click', () => { stopTour(); select(scenarios.find(item => item.id === 'empty')); });
for (const [id, delta] of [['previous', -1], ['next', 1]]) $(id).addEventListener('click', () => { stopTour(); select(scenarios[(scenarios.indexOf(current) + delta + scenarios.length) % scenarios.length]); });
$('tour').addEventListener('click', () => $('tour').getAttribute('aria-pressed') === 'true' ? stopTour() : startTour());
$('viewports').addEventListener('click', event => {
    if (!event.target.dataset.size) return; size = event.target.dataset.size;
    for (const button of $('viewports').children) button.setAttribute('aria-pressed', String(button.dataset.size === size));
    fitStage();
});
$('backgrounds').addEventListener('click', event => { if (event.target.dataset.background) setBackground(event.target.dataset.background); });
$('zoom').addEventListener('input', event => { zoom = Number(event.target.value); $('zoom-value').textContent = `${zoom}×`; fitStage(); });
$('image').addEventListener('change', event => {
    const file = event.target.files[0]; if (!file) return;
    if (!file.type.startsWith('image/')) { status('Choose an image file.'); return; }
    if (customImage) URL.revokeObjectURL(customImage); customImage = URL.createObjectURL(file); setBackground('image');
});
$('send').addEventListener('click', () => {
    try {
        const data = JSON.parse($('payload').value);
        if (!Array.isArray(data) || data.length > 256 || data.some(item => !item || typeof item.action !== 'string' || (item.after !== undefined && (!Number.isFinite(item.after) || item.after < 0)))) throw new Error('Use up to 256 messages with action, data, and optional non-negative after.');
        if (!ready) throw new Error('Wait for the UI to load.');
        send('messages', data); status(`Sent ${data.length} messages`);
    } catch (error) { status(error.message); }
});
$('copy').addEventListener('click', async () => { try { await navigator.clipboard.writeText($('payload').value); status('Scenario JSON copied'); } catch { $('payload').focus(); $('payload').select(); status('Press Ctrl+C to copy the selected JSON'); } });
$('fail').addEventListener('click', () => { failNext = !failNext; $('fail').setAttribute('aria-pressed', String(failNext)); send('failNext', failNext); });
$('clear-log').addEventListener('click', () => { logs = []; $('log').textContent = ''; });
$('clear-settings').addEventListener('click', () => send('clearSettings'));
window.addEventListener('hashchange', () => { const item = scenarios.find(entry => entry.id === location.hash.slice(1)); if (item) { stopTour(); select(item); } });
let resizeFrame = 0;
new ResizeObserver(() => { cancelAnimationFrame(resizeFrame); resizeFrame = requestAnimationFrame(fitStage); }).observe($('stage-scroll'));
document.addEventListener('visibilitychange', () => { if (document.hidden) stopTour(); });
let revision = null, polling = false;
setInterval(async () => {
    if (document.hidden || polling) return;
    polling = true;
    try {
        const response = await fetch('/__revision'); if (!response.ok) throw new Error('Server unavailable');
        const next = (await response.json()).revision;
        if (revision && next !== revision) location.reload();
        revision = next;
    } catch { status('Dev server disconnected · restart bun run dev'); }
    finally { polling = false; }
}, 1000);
select(current); fitStage();
