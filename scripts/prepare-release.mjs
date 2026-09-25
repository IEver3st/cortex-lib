import { execFileSync } from 'node:child_process';
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const stable = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const compare = (a, b) => {
    const left = a.split('.').map(BigInt);
    const right = b.split('.').map(BigInt);
    for (let i = 0; i < 3; i++) {
        if (left[i] !== right[i]) return left[i] > right[i] ? 1 : -1;
    }
    return 0;
};

export function nextVersion(base, tags) {
    if (!stable.test(base)) throw new Error('Manifest version must be MAJOR.MINOR.PATCH');
    const versions = tags.filter(tag => tag.startsWith('v') && stable.test(tag.slice(1)))
        .map(tag => tag.slice(1)).sort(compare);
    const latest = versions.at(-1);
    if (!latest || compare(base, latest) > 0) return base;
    const [major, minor, patch] = latest.split('.');
    return `${major}.${minor}.${BigInt(patch) + 1n}`;
}

export function prepareRelease(cwd = process.cwd()) {
    const git = (...args) => execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();
    if (git('status', '--porcelain', '--untracked-files=no')) {
        throw new Error('Prepare releases only from a clean, committed checkout');
    }
    const source = git('rev-parse', 'HEAD');
    const tags = git('tag', '--list', 'v*').split('\n').filter(Boolean);
    for (const tag of tags.filter(tag => stable.test(tag.slice(1)))) {
        const commit = git('rev-parse', `${tag}^{commit}`);
        const parents = git('show', '-s', '--format=%P', commit);
        const message = git('show', '-s', '--format=%B', commit);
        if (commit === source || (parents === source && message.split('\n').includes(`Source-commit: ${source}`))) {
            return { version: tag.slice(1), tag, commit, source, reused: 'true' };
        }
    }
    const manifestPath = `${cwd}/fxmanifest.lua`;
    const readmePath = `${cwd}/README.md`;
    const manifest = readFileSync(manifestPath, 'utf8');
    const declaration = /^version\s+(['"])([^'"]+)\1\s*$/m;
    const base = manifest.match(declaration)?.[2];
    const version = nextVersion(base ?? '', tags);
    const tag = `v${version}`;
    writeFileSync(manifestPath, manifest.replace(declaration, `version '${version}'`));
    writeFileSync(readmePath, readFileSync(readmePath, 'utf8')
        .replace(/version-\d+\.\d+\.\d+-blue/g, `version-${version}-blue`)
        .replace(/alt="Version \d+\.\d+\.\d+"/g, `alt="Version ${version}"`));
    git('add', '--', 'fxmanifest.lua', 'README.md');
    const tree = git('write-tree');
    const date = git('show', '-s', '--format=%cI', source);
    const commit = execFileSync('git', ['commit-tree', tree, '-p', source], {
        cwd, encoding: 'utf8', input: `Release ${tag}\n\nSource-commit: ${source}\n`,
        env: { ...process.env,
            GIT_AUTHOR_NAME: 'github-actions[bot]', GIT_COMMITTER_NAME: 'github-actions[bot]',
            GIT_AUTHOR_EMAIL: '41898282+github-actions[bot]@users.noreply.github.com',
            GIT_COMMITTER_EMAIL: '41898282+github-actions[bot]@users.noreply.github.com',
            GIT_AUTHOR_DATE: date, GIT_COMMITTER_DATE: date,
        },
    }).trim();
    return { version, tag, commit, source, reused: 'false' };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    const result = prepareRelease();
    if (process.env.GITHUB_OUTPUT) {
        appendFileSync(process.env.GITHUB_OUTPUT,
            Object.entries(result).map(([key, value]) => `${key}=${value}\n`).join(''));
    }
    console.log(JSON.stringify(result));
}
