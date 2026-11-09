import type { Cell } from './types';
import { Layout, NEIGHBORS, key, manhattan } from './layout';

/**
 * A* on the cafe grid (4-neighbour). Finds the shortest path from `start` to any cell in `goals`.
 * `extraCost` lets callers make cells (e.g. ones blocked by other agents) more expensive.
 * `allowGoal` lets the final step enter a non-walkable cell (a chair).
 * Returns the path excluding the start cell, or null if unreachable.
 */
export function findPath(
  layout: Layout,
  start: Cell,
  goals: Cell[],
  opts: { extraCost?: (c: Cell) => number; allowGoal?: boolean } = {},
): Cell[] | null {
  if (goals.length === 0) return null;
  const goalSet = new Set(goals.map(key));
  if (goalSet.has(key(start))) return [];
  const h = (c: Cell) => Math.min(...goals.map((g) => manhattan(c, g)));
  const open: { c: Cell; f: number; g: number }[] = [{ c: start, f: h(start), g: 0 }];
  const came = new Map<string, Cell>();
  const gScore = new Map<string, number>([[key(start), 0]]);
  const closed = new Set<string>();
  let guard = 0;
  while (open.length && guard++ < 5000) {
    let bi = 0;
    for (let i = 1; i < open.length; i++) if (open[i].f < open[bi].f) bi = i;
    const cur = open.splice(bi, 1)[0];
    const ck = key(cur.c);
    if (goalSet.has(ck)) {
      const path: Cell[] = [cur.c];
      let k = ck;
      while (came.has(k)) {
        const p = came.get(k)!;
        k = key(p);
        if (k === key(start)) break;
        path.unshift(p);
      }
      return path;
    }
    if (closed.has(ck)) continue;
    closed.add(ck);
    for (const n of NEIGHBORS) {
      const nc = { x: cur.c.x + n.x, z: cur.c.z + n.z };
      const nk = key(nc);
      if (closed.has(nk)) continue;
      const isGoal = goalSet.has(nk);
      if (!layout.walkable(nc) && !(isGoal && opts.allowGoal && layout.inBounds(nc))) continue;
      const g = cur.g + 1 + (opts.extraCost ? opts.extraCost(nc) : 0);
      if (g < (gScore.get(nk) ?? Infinity)) {
        gScore.set(nk, g);
        came.set(nk, cur.c);
        open.push({ c: nc, g, f: g + h(nc) });
      }
    }
  }
  return null;
}
