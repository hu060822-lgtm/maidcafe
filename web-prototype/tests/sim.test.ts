import { describe, expect, it } from 'vitest';
import { newGame } from '../src/game/state';
import { BusinessSim } from '../src/game/business';
import { beginBusiness, settleDay, startNextDay, nextEvent, resolveEvent } from '../src/game/settlement';
import { Layout } from '../src/game/layout';
import { findPath } from '../src/game/path';
import { buyIngredient, visitLocation } from '../src/game/world';
import { CUSTOMERS } from '../src/game/data/customers';
import { DISHES, LOCATIONS, ACTIVITIES } from '../src/game/data/content';
import { MAIDS } from '../src/game/data/maids';
import type { GameState } from '../src/game/types';

function stock(s: GameState) {
  for (const id of ['milk', 'egg', 'rice', 'tomato', 'coffee', 'tea', 'sugar', 'flour', 'curry', 'cheese', 'pasta']) buyIngredient(s, id, 10);
}

function runDay(s: GameState) {
  expect(beginBusiness(s)).toBeNull();
  const sim = new BusinessSim(s);
  let guard = 0;
  while (!sim.ended && guard++ < 10000) {
    sim.update(0.1);
    for (const p of sim.parties)
      if (['browsing', 'waitOrder', 'waitFood', 'eating'].includes(p.state)) expect(p.members.every((m) => m.sitting)).toBe(true);
  }
  expect(sim.ended).toBe(true);
  const report = settleDay(s, sim);
  let ev = nextEvent(s);
  while (ev) {
    resolveEvent(s, ev, 0);
    ev = nextEvent(s);
  }
  return { sim, report };
}

describe('content counts (MVP spec)', () => {
  it('has the required amounts of content', () => {
    expect(MAIDS.length).toBe(3);
    expect(CUSTOMERS.length).toBe(12);
    expect(CUSTOMERS.filter((c) => c.kind === 'normal').length).toBe(6);
    expect(CUSTOMERS.filter((c) => c.kind === 'regular').length).toBe(4);
    expect(CUSTOMERS.filter((c) => c.kind === 'special').length).toBe(2);
    expect(DISHES.filter((d) => !d.signature).length).toBe(15);
    expect(LOCATIONS.length).toBe(6);
    expect(Object.keys(ACTIVITIES).filter((a) => a !== 'none').length).toBe(3);
  });
});

describe('layout & pathfinding', () => {
  it('default layout is fully reachable', () => {
    const s = newGame(1);
    const l = new Layout(s.furniture, s.upgrades);
    expect(l.allReachable()).toBe(true);
    const p = findPath(l, { x: 9, z: 10 }, [{ x: 1, z: 2 }]);
    expect(p).not.toBeNull();
    expect(p!.length).toBeGreaterThan(5);
  });
  it('rejects furniture that blocks the aisle', () => {
    const s = newGame(1);
    const l = new Layout(s.furniture, s.upgrades);
    expect(l.canPlace('plant', 9, 10)).not.toBeNull(); // entrance
    expect(l.canPlace('plant', 3, 8)).toBeNull();
  });
});

describe('business day', () => {
  it('serves customers, earns money and updates memory', () => {
    const s = newGame(42);
    stock(s);
    const { sim, report } = runDay(s);
    expect(sim.results.length).toBeGreaterThan(0);
    expect(report.served).toBeGreaterThan(0);
    expect(report.revenue).toBeGreaterThan(0);
    const visited = Object.values(s.customers).filter((c) => c.visits > 0);
    expect(visited.length).toBeGreaterThan(0);
    expect(visited.every((c) => c.lastSatisfaction !== null)).toBe(true);
  });

  it('yesterday affects today: memory, affinity and loyalty carry over', () => {
    const s = newGame(7);
    let sawReaction = false;
    for (let d = 0; d < 5; d++) {
      stock(s);
      s.phase = 'prep';
      const { sim } = runDay(s);
      if (d > 0) {
        // any named customer with a previous visit should have a memory-based state
        for (const r of sim.results) if (r.defId && s.customers[r.defId].visits > 1) sawReaction = true;
      }
      startNextDay(s);
    }
    expect(sawReaction).toBe(true);
    const anyFav = Object.values(s.customers).some((c) => c.favoriteMaid);
    expect(anyFav).toBe(true);
    expect(s.day).toBe(6);
  });

  it('an unstaffed kitchen still gets orders cooked by others', () => {
    const s = newGame(3);
    stock(s);
    s.maids.find((m) => m.id === 'rin')!.role = 'off';
    const { report } = runDay(s);
    expect(report.served).toBeGreaterThan(0);
  });

  it('exploration unlocks customers', () => {
    const s = newGame(5);
    expect(s.customers.mayu.known).toBe(false);
    visitLocation(s, 'park');
    expect(s.customers.mayu.known).toBe(true);
    expect(s.actionPoints).toBe(3);
  });
});
