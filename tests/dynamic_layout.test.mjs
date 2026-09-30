import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';
const { solve, overlaps } = createRequire(import.meta.url)('../ui/dynamic-layout.js');
const surface = (key, x, y, width, height, priority = 50, fixed = false) => ({ key, x, y, width, height, priority, fixed });
for (const [width, height] of [[1280, 720], [1920, 1080], [3440, 1440]]) {
    test(`chat, notifications, prompts and minimap remain disjoint at ${width}x${height}`, () => {
        const items = [surface('hud:minimap', 20, height - 220, 290, 200, 100, true),
            surface('chat:chat', 20, 20, 480, 350, 85, true),
            surface('lib:notifications', 20, 20, 328, 180, 50),
            surface('lib:prompts', width - 350, height - 150, 320, 120, 75)];
        const result = solve(items, { width, height, inset: 20 });
        const boxes = items.map(item => ({ ...item, ...result[item.key] }));
        for (let i = 0; i < boxes.length; i++) {
            assert.equal(boxes[i].crowded, false);
            assert.ok(boxes[i].x >= 20 && boxes[i].y >= 20);
            assert.ok(boxes[i].x + boxes[i].width <= width - 20);
            assert.ok(boxes[i].y + boxes[i].height <= height - 20);
            for (let j = i + 1; j < boxes.length; j++) assert.equal(overlaps(boxes[i], boxes[j]), false);
        }
        assert.deepEqual(solve([...items].reverse(), { width, height, inset: 20 }), result);
    });
}
test('fixed controls keep their position and movable surfaces return when reservations leave', () => {
    const viewport = { width: 1920, height: 1080, inset: 20 };
    const notice = surface('notice', 20, 20, 480, 350, 85);
    const camera = surface('camera', 20, 20, 500, 200, 100, true);
    const moved = solve([notice, camera], viewport);
    assert.deepEqual(moved.camera, { x: 20, y: 20, crowded: false });
    assert.notEqual(moved.notice.y, 20);
    assert.deepEqual(solve([notice], viewport).notice, { x: 20, y: 20, crowded: false });
});
test('an impossible fit is explicit and does not silently hide content', () => {
    const result = solve([surface('chat', -100, -100, 800, 800)], { width: 720, height: 480, inset: 20 });
    assert.deepEqual(result.chat, { x: 20, y: 20, crowded: true });
});
test('increasing content size moves the lower-priority surface without moving chat', () => {
    const viewport = { width: 1280, height: 720, inset: 20 };
    const chat = surface('chat', 20, 20, 480, 540, 85, true);
    const notify = surface('notify', 20, 20, 328, 180);
    const result = solve([notify, chat], viewport);
    assert.deepEqual(result.chat, { x: 20, y: 20, crowded: false });
    assert.equal(overlaps({ ...chat, ...result.chat }, { ...notify, ...result.notify }, 10), false);
});
