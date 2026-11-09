import type { CustomerMemory, GameState, MaidState } from './types';
import { MAIDS } from './data/maids';
import { CUSTOMERS } from './data/customers';
import { BASE_DISHES, DAY_ACTION_POINTS } from './data/content';
import { defaultFurniture } from './layout';

export const SAVE_KEY = 'maiden-parade-save-v1';

/** Small deterministic RNG (mulberry32). State lives in GameState so runs are reproducible. */
export class Rng {
  constructor(public s: number) {}
  next() {
    let t = (this.s = (this.s + 0x6d2b79f5) | 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  range(a: number, b: number) {
    return a + (b - a) * this.next();
  }
  int(a: number, b: number) {
    return Math.floor(this.range(a, b + 1));
  }
  pick<T>(arr: T[]): T {
    return arr[Math.floor(this.next() * arr.length)];
  }
}

export const clamp = (v: number, a = 0, b = 100) => Math.max(a, Math.min(b, v));

export function newMaidState(id: string): MaidState {
  const def = MAIDS.find((m) => m.id === id)!;
  const rel: Record<string, number> = {};
  for (const m of MAIDS) if (m.id !== id) rel[m.id] = 40;
  // starting relationships: 小春 and 雫 already get along
  if (id === 'koharu') rel.shizuku = 55;
  if (id === 'shizuku') rel.koharu = 55;
  return {
    id,
    skills: { ...def.skills },
    exp: { reception: 0, cooking: 0, floor: 0, performance: 0, management: 0 },
    mood: 65,
    fatigue: 10,
    relationships: rel,
    role: def.defaultRole,
    dayOffTomorrow: false,
    lowMoodNights: 0,
    quit: false,
    greetsDone: 0,
    ordersSolo: 0,
    flags: {},
    yesterday: [],
  };
}

export function newCustomerMemory(id: string): CustomerMemory {
  const def = CUSTOMERS.find((c) => c.id === id)!;
  return {
    id,
    known: def.metAt === 'start',
    visits: 0,
    loyalty: def.kind === 'regular' ? 20 : 10,
    maidAffinity: {},
    favoriteMaid: null,
    favoriteSeat: null,
    favoriteDish: null,
    lastSatisfaction: null,
    lastVisitDay: null,
    lastCauses: [],
    isRegular: false,
    broughtFriend: false,
    storyStage: 0,
    log: [],
  };
}

export function newGame(seed = Date.now() % 100000): GameState {
  const customers: Record<string, CustomerMemory> = {};
  for (const c of CUSTOMERS) customers[c.id] = newCustomerMemory(c.id);
  return {
    version: 1,
    seed,
    rngState: seed,
    day: 1,
    phase: 'explore',
    money: 8000,
    popularity: 15,
    actionPoints: DAY_ACTION_POINTS,
    inventory: { coffee: 6, milk: 6, egg: 6, rice: 3, tea: 3, sugar: 4, flour: 4, tomato: 2 },
    unlockedDishes: [...BASE_DISHES],
    menu: ['d_coffee', 'd_royaltea', 's_pudding', 's_pancake', 'm_omurice', 'm_curry', 'm_sandwich'],
    activity: 'none',
    featuredDish: null,
    maids: MAIDS.map((m) => newMaidState(m.id)),
    customers,
    furniture: defaultFurniture(),
    upgrades: { secondStove: false, coffeeMachine: false, sofa: false },
    partners: [],
    album: [
      { day: 1, title: '接手 Maiden Parade', text: '在老商店街的一角，我接下了這間快撐不下去的女僕咖啡廳。小春、凜、雫決定留下來。' },
    ],
    flags: {},
    todaySpend: { ingredients: 0, activity: 0, promotion: 0, furniture: 0 },
    lastReport: null,
    pendingEvents: [],
    history: [],
    nextFurnitureId: 100,
  };
}

export function saveGame(s: GameState) {
  try {
    localStorage.setItem(SAVE_KEY, JSON.stringify(s));
  } catch {
    /* storage unavailable */
  }
}

export function loadGame(): GameState | null {
  try {
    const raw = localStorage.getItem(SAVE_KEY);
    if (!raw) return null;
    const s = JSON.parse(raw) as GameState;
    return s.version === 1 ? s : null;
  } catch {
    return null;
  }
}

export function activeMaids(s: GameState) {
  return s.maids.filter((m) => !m.quit);
}

export function addAlbum(s: GameState, title: string, text: string) {
  if (s.album.some((a) => a.title === title)) return;
  s.album.push({ day: s.day, title, text });
}
