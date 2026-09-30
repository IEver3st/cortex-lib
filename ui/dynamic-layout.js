/* Pure, deterministic layout policy. Shared by every participating NUI. */
(function (root) {
    'use strict';
    const overlaps = (a, b, gap = 0) => a.x < b.x + b.width + gap
        && a.x + a.width + gap > b.x && a.y < b.y + b.height + gap
        && a.y + a.height + gap > b.y;
    function solve(items, viewport, gap = 10) {
        const result = {};
        const occupied = [];
        const inset = Math.max(8, viewport.inset || 0);
        const sorted = [...items].sort((a, b) => Number(b.fixed) - Number(a.fixed)
            || b.priority - a.priority || a.key.localeCompare(b.key));
        for (const item of sorted) {
            if (item.fixed) {
                occupied.push(item);
                result[item.key] = { x: item.x, y: item.y, crowded: false };
                continue;
            }
            const maxX = viewport.width - inset - item.width;
            const maxY = viewport.height - inset - item.height;
            const clamp = (n, max) => Math.max(inset, Math.min(max, n));
            const preferred = { ...item, x: clamp(item.x, maxX), y: clamp(item.y, maxY) };
            // Candidates follow edges and obstacles, never a grid or random jitter.
            const xs = new Set([preferred.x, inset, Math.max(inset, maxX)]);
            const ys = new Set([preferred.y, inset, Math.max(inset, maxY)]);
            for (const block of occupied) {
                xs.add(block.x - gap - item.width); xs.add(block.x + block.width + gap);
                ys.add(block.y - gap - item.height); ys.add(block.y + block.height + gap);
            }
            let best = null;
            let distance = Infinity;
            const nearby = (values, start) => [...values].sort((a, b) => Math.abs(a - start) - Math.abs(b - start)).slice(0, 24);
            for (const x of nearby(xs, preferred.x)) for (const y of nearby(ys, preferred.y)) {
                if (x < inset || y < inset || x > maxX || y > maxY) continue;
                const candidate = { ...item, x, y };
                if (occupied.some(block => overlaps(candidate, block, gap))) continue;
                // Prefer staying in the chosen column; protect the center playfield.
                const cost = Math.abs(x - preferred.x) * 2 + Math.abs(y - preferred.y);
                if (cost < distance) { best = candidate; distance = cost; }
            }
            const placement = best || preferred;
            result[item.key] = { x: placement.x, y: placement.y, crowded: !best };
            // Never silently hide actionable or time-sensitive content when saturated.
            occupied.push(placement);
        }
        return result;
    }
    root.CortexLayout = Object.freeze({ solve, overlaps });
    if (typeof module !== 'undefined') module.exports = root.CortexLayout;
})(typeof window === 'undefined' ? globalThis : window);
