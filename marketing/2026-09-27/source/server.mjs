import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const types = { '.html':'text/html', '.js':'text/javascript', '.mjs':'text/javascript', '.css':'text/css', '.png':'image/png', '.woff2':'font/woff2', '.svg':'image/svg+xml', '.json':'application/json', '.psd':'image/vnd.adobe.photoshop' };
const server = http.createServer(async (req,res) => {
  try {
    const url = new URL(req.url, 'http://127.0.0.1');
    let file = path.resolve(root, '.' + decodeURIComponent(url.pathname === '/' ? '/marketing/2026-09-27/source/index.html' : url.pathname));
    const relative = path.relative(root,file);
    if (relative.startsWith('..') || path.isAbsolute(relative) || !(/^(ui[\\/]|marketing[\\/]2026-09-27[\\/])/.test(relative))) { res.writeHead(403); res.end(); return; }
    let content = await fs.readFile(file);
    if (relative.replaceAll('\\','/') === 'ui/index.html') {
      content = Buffer.from(content.toString().replaceAll('https://cfx-nui-cortex-lib/ui/', '/ui/').replace('<script src="vendor/', '<script src="/marketing/2026-09-27/source/fixture.js"></script><script src="vendor/'));
    }
    res.writeHead(200, {'Content-Type':types[path.extname(file)] || 'application/octet-stream','Cache-Control':'no-store'});res.end(content);
  } catch {res.writeHead(404);res.end('Not found');}
});
server.listen(Number(process.env.PORT || 5196), '127.0.0.1', () => console.log('Cortex-Lib showcase: http://127.0.0.1:5196'));
