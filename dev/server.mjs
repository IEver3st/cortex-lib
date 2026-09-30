import { readFile, realpath } from 'node:fs/promises';
import { watch } from 'node:fs';
import { resolve, relative, extname, sep, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const headers = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript',
    '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.png': 'image/png', '.jpg': 'image/jpeg' };

export function previewHtml(source) {
    return source.replaceAll('https://cfx-nui-cortex-lib/ui/', '/ui/')
        .replace('<head>', '<head><base href="/ui/"><script src="/dev/bridge.js"></script>');
}

export async function handleRequest(request, revision = 'test') {
    if (!['GET', 'HEAD'].includes(request.method)) return new Response('Method not allowed', { status: 405, headers });
    let path;
    try { path = decodeURIComponent(new URL(request.url).pathname); } catch { return new Response('Bad path', { status: 400 }); }
    if (path === '/__revision') return Response.json({ revision }, { headers });
    if (path === '/favicon.ico') return new Response(null, { status: 204 });
    if (path === '/preview') {
        const html = previewHtml(await readFile(resolve(root, 'ui/index.html'), 'utf8'));
        return new Response(request.method === 'HEAD' ? null : html, { headers: { ...headers, 'Content-Type': 'text/html' } });
    }
    if (path === '/') path = '/dev/index.html';
    // Never expose the repository, Lua, credentials, symlinks outside the lab, or arbitrary files.
    if (!/^\/(dev|ui)\/[a-zA-Z0-9_./-]+$/.test(path) || path.split('/').some(part => part.startsWith('.'))
        || !types[extname(path)] || path === '/dev/server.mjs') return new Response('Not found', { status: 404 });
    try {
        const directory = await realpath(resolve(root, path.split('/')[1]));
        const file = await realpath(resolve(root, path.slice(1)));
        const inside = relative(directory, file);
        if (inside.startsWith(`..${sep}`) || inside === '..' || isAbsolute(inside))
            return new Response('Not found', { status: 404 });
        const body = await readFile(file);
        return new Response(request.method === 'HEAD' ? null : body, { headers: { ...headers, 'Content-Type': types[extname(file)] } });
    } catch { return new Response('Not found', { status: 404, headers }); }
}

if (import.meta.main) {
    const flag = process.argv.indexOf('--port');
    const port = Number(flag >= 0 ? process.argv[flag + 1] : process.env.PORT || 5196);
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Use --port <1-65535>');
    let revision = Date.now().toString();
    for (const folder of ['ui', 'dev']) watch(resolve(root, folder), { recursive: true }, () => { revision = Date.now().toString(); });
    try {
        const server = Bun.serve({ hostname: '127.0.0.1', port, fetch: request => handleRequest(request, revision) });
        console.log(`\nCortex UI lab: ${server.url}\nReal UI, browser fixtures. Edits reload automatically. Ctrl+C stops.\n`);
    } catch (error) {
        console.error(`Cannot start on 127.0.0.1:${port}. Try bun run dev --port ${port + 1}.\n${error.message}`);
        process.exit(1);
    }
}
