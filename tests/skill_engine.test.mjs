import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const context = vm.createContext({});
vm.runInContext(readFileSync(new URL('../ui/skill-engine.js', import.meta.url), 'utf8'), context);
const E = context.CortexSkillEngine;
const options = (type, extra = {}) => ({ type, duration: 10000, speed: .5, targetStart: .5, targetSize: .15,
    key: 'E', keys: ['E', 'R', 'E'], direction: 'upper', tolerance: .23, ...extra });
test('radial scores the input timestamp, not a stale animation frame', () => {
    const good = E.create(options('radial'), 0);
    E.input(good, 'E', true, 1100);
    assert.equal(good.result.success, true);
    const bad = E.create(options('radial'), 0);
    E.input(bad, 'E', true, 200);
    assert.equal(bad.result.success, false);
});
test('hold requires release in the zone and ignores keyboard auto repeat', () => {
    const s = E.create(options('hold'), 0);
    E.input(s, 'E', true, 100);
    E.input(s, 'E', true, 700, true);
    E.input(s, 'E', false, 1200);
    assert.equal(s.result.success, true);
    const over = E.create(options('hold'), 0);
    E.input(over, 'E', true, 0);
    E.tick(over, 2100);
    assert.equal(over.result.success, false);
});
test('sequence rejects wrong keys, ignores repeats, and completes ordered edges', () => {
    const s = E.create(options('sequence'), 0);
    E.input(s, 'E', true, 100);
    E.input(s, 'E', true, 200, true);
    assert.equal(s.index, 1);
    E.input(s, 'R', true, 300);
    E.input(s, 'E', true, 400);
    assert.equal(s.result.success, true);
    const bad = E.create(options('sequence'), 0);
    E.input(bad, 'Q', true, 100);
    assert.equal(bad.result.success, false);
});
test('timeouts, Escape, and finalized results are deterministic', () => {
    const s = E.create(options('radial'), 0);
    E.input(s, 'E', true, 11000);
    assert.equal(s.result.reason, 'timeout');
    const escape = E.create(options('radial'), 0);
    E.input(escape, 'ESCAPE', true, 10);
    assert.equal(escape.result.reason, 'cancelled');
    E.input(escape, 'E', true, 1100);
    assert.equal(escape.result.success, false);
});
test('outcome scores are presentation only: centre hits score high, misses carry none', () => {
    const centre = E.create(options('radial'), 0);
    E.input(centre, 'E', true, 1150); // progress .575 = zone centre
    assert.equal(centre.result.success, true);
    assert.ok(centre.score >= 95);
    const edge = E.create(options('radial'), 0);
    E.input(edge, 'E', true, 1010);
    assert.ok(edge.result.success && edge.score < 20);
    const miss = E.create(options('radial'), 0);
    E.input(miss, 'E', true, 200);
    assert.equal(miss.score, null);
    assert.deepEqual(Object.keys(miss.result).sort(), ['reason', 'success'], 'the reported result stays success/reason only');
});
