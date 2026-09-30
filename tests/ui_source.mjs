// The NUI is a set of classic scripts and stylesheets loaded by ui/index.html.
// Contract tests read them in document order as one source, so moving a
// component between modules never hides it from a contract.
import { readFileSync } from 'node:fs';

const uiRoot = new URL('../ui/', import.meta.url);
const html = readFileSync(new URL('index.html', uiRoot), 'utf8');
const local = pattern => [...html.matchAll(pattern)].map(match => match[1])
    .filter(path => !/^(https?:|vendor\/)/.test(path));

export const scriptFiles = local(/<script src="([^"?#]+)[^"]*"><\/script>/g);
export const styleFiles = local(/<link rel="stylesheet" href="([^"?#]+)[^"]*">/g);
const read = files => files.map(file => readFileSync(new URL(file, uiRoot), 'utf8').replace(/\r\n/g, '\n')).join('\n');
export const uiSource = read(scriptFiles);
export const uiStyles = read(styleFiles);
