import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const testDir = path.dirname(fileURLToPath(import.meta.url));
const read = (...segments) => readFileSync(path.join(testDir, '..', ...segments), 'utf8')
    .replace(/\r\n/g, '\n');

const externalLoader = read('init.lua');
const internalLoader = read('resource', 'init.lua');
const registry = read('imports', 'interaction', 'client.lua');
const renderer = read('client', 'interaction_renderer.lua');
const points = read('imports', 'points', 'client.lua');
const uiSource = read('ui', 'app.js');

for (const loader of [externalLoader, internalLoader]) {
    assert.match(loader, /GetVehicleMaxNumberOfPassengers/);
    assert.match(loader, /vehicleChanged or type\(seat\) ~= 'number' or GetPedInVehicleSeat/);
    assert.doesNotMatch(loader, /for i = -1, 16 do/);
    assert.match(loader, /if playerId ~= cache\.playerId then[\s\S]*?cache\.serverId = GetPlayerServerId\(playerId\)/);
}

const activeLookup = registry.match(/local function isInteractionActive\([\s\S]*?\nend\n\nlocal function isInteractionVisible/);
assert.ok(activeLookup, 'active lookup must remain independently inspectable');
assert.match(activeLookup[0], /getOwnedEntry/);
assert.doesNotMatch(activeLookup[0], /buildSnapshot|table\.sort/);
assert.match(registry, /local ownerCounts = \{\}/);
assert.match(registry, /local totalCount = 0/);
assert.match(registry, /rawDefinitionMatches/);
assert.match(registry, /publish\(false\)/, 'hold-only changes should not repeat key arbitration');

assert.match(renderer, /descriptor\.entityModel ~= entityModel/);
assert.match(renderer, /local boneIndex = GetEntityBoneIndexByName/);
assert.match(renderer, /descriptor\.boneIndex = boneIndex ~= -1 and boneIndex or nil/);
assert.match(renderer, /descriptor\.lastSentX ~= screenX/);
assert.match(renderer, /presentationItemsEqual\(screenItems, lastScreenItems\)/);
assert.match(renderer, /Wait\(frameCount > 0 and 0 or 50\)/);

assert.match(points, /local nearbyThreadActive = false/);
assert.match(points, /if nearbyThreadActive or #nearbyPoints == 0 then return end/);
assert.doesNotMatch(
    points,
    /CreateThread\(function\(\)\n\s+while true do\n\s+for i = 1, #nearbyPoints/,
    'points must not retain a per-frame thread while no point is nearby'
);

const appSource = uiSource.match(/function App\(\)[\s\S]*?\/\/ DYNAMIC STYLES/);
assert.ok(appSource, 'root app must remain independently inspectable');
assert.match(uiSource, /function InteractionSurface\(\{ hidden \}\)/);
assert.match(uiSource, /window\.requestAnimationFrame\(commitWorldItems\)/);
assert.match(uiSource, /interactionItemsEqual\(currentItems, nextItems, true\)/);
assert.match(uiSource, /if \(hiddenRef\.current\) break;/, 'hidden interaction UI must not schedule frame renders');
assert.doesNotMatch(appSource[0], /case 'interaction:(update|world|layout)'/);
assert.match(appSource[0], /React\.createElement\(InteractionSurface, \{ hidden: settingsPanel\.open \}\)/);

console.log('runtime performance contract: PASS');
