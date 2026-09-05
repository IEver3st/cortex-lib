import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...segments) => readFileSync(path.join(testDir, '..', ...segments), 'utf8')
    .replace(/\r\n/g, '\n');

const workflow = read('.github', 'workflows', 'release.yml');
const validator = read('scripts', 'validate-resource.ps1');
const manifest = read('fxmanifest.lua');
const readme = read('README.md');

const manifestVersion = manifest.match(/^version\s+['"]([^'"]+)['"]$/m)?.[1];
assert.ok(manifestVersion, 'fxmanifest must declare a release version');
assert.ok(readme.includes(`version-${manifestVersion}-blue`), 'README version badge must match fxmanifest');

assert.match(workflow, /^permissions:\n  contents: read$/m, 'workflow permissions must default to read-only');
assert.doesNotMatch(workflow, /runs-on:\s+ubuntu-latest/, 'release jobs must use an explicit runner image');
assert.equal((workflow.match(/runs-on:\s+ubuntu-24\.04/g) || []).length, 2, 'both jobs must use the pinned runner image');
assert.match(
    workflow,
    /release:\n    needs: validate[\s\S]*?permissions:\n      contents: write/,
    'only the release job may request content write access after validation'
);

const actionUses = [...workflow.matchAll(/^\s*uses:\s*([^\s#]+).*$/gm)].map((match) => match[1]);
assert.ok(actionUses.length > 0, 'workflow must declare its checkout action');
for (const action of actionUses) {
    assert.match(action, /@[0-9a-f]{40}$/, `${action} must be pinned to an immutable commit SHA`);
}

for (const requiredGate of [
    './scripts/validate-resource.ps1 -Path .',
    'node --check ui/app.js',
    'node --test tests/*.test.mjs',
    'for spec in tests/*_spec.lua',
    'git show --check --format= "$GITHUB_SHA"'
]) {
    assert.ok(workflow.includes(requiredGate), `release validation must include: ${requiredGate}`);
}

assert.match(workflow, /git ls-files -z/, 'release contents must come only from tracked files');
assert.match(
    workflow,
    /:\(exclude\)tests\/release_workflow_contract\.test\.mjs/,
    'the repository-only workflow contract must not be copied into the runtime archive'
);
assert.match(workflow, /git archive[\s\S]*?--prefix="\$\{RELEASE_NAME\}\/"/, 'archive must contain one top-level resource folder');
assert.match(workflow, /sha256sum "\$\{RELEASE_ASSET\}"/, 'release must publish an archive checksum');
assert.match(
    workflow,
    /Validate exact release archive[\s\S]*?unzip -q[\s\S]*?validate-resource\.ps1[\s\S]*?node --test[\s\S]*?lua5\.4/,
    'the exact extracted archive must pass manifest, Node, and Lua validation before publication'
);
assert.doesNotMatch(workflow, /actions\/github-script|softprops\/action-gh-release|oven-sh\/setup-bun/);

assert.match(validator, /Manifest reference missing/);
assert.match(validator, /Lazy-loadable import is not listed in files/);
assert.match(validator, /NUI asset is not listed in files/);
assert.match(validator, /Production manifest points ui_page at localhost/);
assert.match(validator, /Potential secret in shipped source/);

console.log('release workflow contract: PASS');
