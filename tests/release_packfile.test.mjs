import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const validator = fileURLToPath(new URL('../scripts/validate-resource.ps1', import.meta.url));

test('release validation checks fonts, CSS assets and same-resource NUI URLs', () => {
    const root = mkdtempSync(path.join(tmpdir(), 'cortex-packfile-'));
    try {
        mkdirSync(path.join(root, 'ui'));
        mkdirSync(path.join(root, 'imports'));
        const write = (name, text) => writeFileSync(path.join(root, name), text);
        const manifest = (extra = '') => write('fxmanifest.lua', `
fx_version 'cerulean'
game 'gta5'
name 'cortex-lib'
ui_page 'ui/index.html'
files { 'ui/index.html', 'ui/style.css', ${extra} }
`);
        const validate = () => {
            const result = spawnSync('pwsh', ['-NoProfile', '-File', validator, '-Path', root], { encoding: 'utf8' });
            assert.ifError(result.error);
            assert.ok(result.stdout.trim().startsWith('{'), result.stderr || result.stdout);
            const data = JSON.parse(result.stdout);
            assert.equal(result.status, data.passed ? 0 : 1, result.stderr);
            return data;
        };
        write('ui/index.html', '<link href="style.css?v=1#theme" rel="stylesheet">');
        write('ui/style.css', '@font-face { src: url("display.woff2?v=1"); }');
        manifest("'ui/display.woff2'");
        let result = validate();
        assert.equal(result.passed, false, 'a declared font missing from disk must block release');
        assert.ok(result.errors.some(error => error.includes('ui/display.woff2')));

        write('ui/display.woff2', 'fixture');
        assert.equal(validate().passed, true, 'relative assets and cache-busting URLs resolve');

        write('ui/style.css', 'body { background-image: url(grain.svg); }');
        write('ui/grain.svg', '<svg xmlns="http://www.w3.org/2000/svg"/>');
        result = validate();
        assert.equal(result.passed, false, 'CSS assets existing on disk still require a files entry');
        assert.ok(result.errors.some(error => error.includes('ui/grain.svg')));

        write('ui/style.css', 'body { background: transparent; }');
        write('ui/index.html', '<script src="https://cfx-nui-cortex-lib/ui/shared.js?v=1"></script>');
        write('ui/shared.js', 'void 0;');
        result = validate();
        assert.equal(result.passed, false, 'same-resource HTTPS references must be in the packfile');
        assert.ok(result.errors.some(error => error.includes('ui/shared.js')));

        manifest("'ui/shared.js'");
        assert.equal(validate().passed, true, 'packaged same-resource HTTPS references resolve');
    } finally {
        assert.equal(path.dirname(root), path.resolve(tmpdir()));
        assert.ok(path.basename(root).startsWith('cortex-packfile-'));
        rmSync(root, { recursive: true, force: true });
    }
});
