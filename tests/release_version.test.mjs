import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { nextVersion, prepareRelease } from '../scripts/prepare-release.mjs';

test('automatic patch versions, explicit larger versions, and numeric sorting', () => {
    assert.equal(nextVersion('2.2.1', ['v2.2.0']), '2.2.1');
    assert.equal(nextVersion('2.2.1', ['v2.2.9', 'v2.2.10', 'v3.0.0-beta.1']), '2.2.11');
    assert.equal(nextVersion('3.0.0', ['v2.2.10']), '3.0.0');
    assert.equal(nextVersion('1.0.0', []), '1.0.0');
    assert.throws(() => nextVersion('2.2.1\nevil', []));
});

test('tagged tree matches the version, preserves main, and retries reuse the same release', () => {
    const root = mkdtempSync(path.join(tmpdir(), 'cortex-release-'));
    const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
    try {
        git('init', '-q');
        git('config', 'user.name', 'Release fixture');
        git('config', 'user.email', 'fixture@example.invalid');
        writeFileSync(path.join(root, 'fxmanifest.lua'), "version '2.2.1'\n");
        writeFileSync(path.join(root, 'README.md'), 'version-2.2.1-blue alt="Version 2.2.1"\n');
        git('add', '.');
        git('commit', '-qm', 'previous source');
        git('tag', 'v2.2.1');
        writeFileSync(path.join(root, 'runtime.lua'), 'return true\n');
        git('add', '.');
        git('commit', '-qm', 'new source');
        const source = git('rev-parse', 'HEAD');
        const first = prepareRelease(root);
        assert.equal(first.tag, 'v2.2.2');
        assert.equal(git('rev-parse', 'HEAD'), source, 'main must not receive bot commits');
        assert.match(git('show', `${first.commit}:fxmanifest.lua`), /version '2.2.2'/);
        assert.match(git('show', `${first.commit}:README.md`), /version-2.2.2-blue/);
        assert.equal(git('show', `${first.commit}:runtime.lua`), 'return true');
        assert.throws(() => prepareRelease(root), /clean/);
        git('restore', '--source=HEAD', '--staged', '--worktree', 'fxmanifest.lua', 'README.md');
        assert.equal(prepareRelease(root).commit, first.commit, 'pre-publication retry must be deterministic');
        git('restore', '--source=HEAD', '--staged', '--worktree', 'fxmanifest.lua', 'README.md');
        git('tag', first.tag, first.commit);
        const retry = prepareRelease(root);
        assert.equal(retry.commit, first.commit);
        assert.equal(retry.reused, 'true');
        assert.match(readFileSync(path.join(root, 'fxmanifest.lua'), 'utf8'), /2.2.1/);
    } finally {
        assert.equal(path.dirname(root), path.resolve(tmpdir()));
        assert.ok(path.basename(root).startsWith('cortex-release-'));
        rmSync(root, { recursive: true, force: true });
    }
});
