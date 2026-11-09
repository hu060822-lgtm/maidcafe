// Real-time business simulation (the "evening" phase).
// Pure logic: no DOM / three.js. The renderer reads agents' positions and labels every frame.
import type { Cell, CustomerDef, GameState, MaidState, Role, VisitCause } from './types';
import { DISH_BY_ID } from './data/content';
import { CUSTOMER_BY_ID, CUSTOMERS, FRIEND_LOYALTY, FRIEND_VISITS } from './data/customers';
import { MAID_BY_ID, MANAGER } from './data/maids';
import { DOOR, DOOR_IN, GREET_SPOT, IDLE_SPOTS, Layout, PASS_SLOTS, REST_SPOTS, key, manhattan, sameCell } from './layout';
import { findPath } from './path';
import { Rng, activeMaids, clamp } from './state';
import { dominantStyle, servingsPossible } from './world';

export const DURATION = 240; // seconds of simulated business (17:00 → 22:00)
export const LAST_ARRIVAL = 200;
export const HARD_END = 300;
export const OPEN_HOUR = 17;
export const CLOSE_HOUR = 22;
const MAX_CP = 5;
const CP_REGEN = 40;

export interface Vec {
  x: number;
  z: number;
}

export interface Mover {
  id: string;
  pos: Vec;
  cell: Cell;
  path: Cell[];
  speed: number;
  waitT: number;
  facing: number;
  moving: boolean;
  inside: boolean;
  ghost: boolean;
}

export type JobType = 'greet' | 'order' | 'cook' | 'deliver' | 'clean' | 'mess' | 'complaint';
export const JOB_NAMES: Record<JobType, string> = {
  greet: '帶位',
  order: '點餐',
  cook: '製作',
  deliver: '送餐',
  clean: '整理桌面',
  mess: '清理地板',
  complaint: '處理客訴',
};

export interface Job {
  id: string;
  type: JobType;
  partyId?: string;
  orderId?: string;
  tableId?: string;
  messId?: string;
  created: number;
  claimedBy: string | null;
  preferred: string | null;
  done: boolean;
  cancelled: boolean;
}

type Step =
  | { kind: 'goto'; goals: () => Cell[]; label: string; allowGoal?: boolean }
  | { kind: 'work'; dur: number; label: string; done: (w: Worker) => void }
  | { kind: 'check'; ok: (w: Worker) => boolean };

export interface Worker extends Mover {
  kind: 'maid' | 'manager';
  maidId: string | null;
  name: string;
  job: Job | null;
  steps: Step[];
  stepT: number;
  stepDur: number;
  activity: string;
  paused: boolean;
  resting: boolean;
  restSpot: Cell | null;
  carrying: string | null;
  bubble: { text: string; until: number } | null;
  performing: boolean;
  idleChatT: number;
  manual: boolean;
}

export interface CustAgent extends Mover {
  partyId: string;
  defId: string | null;
  name: string;
  color: number;
  hair: number;
  sat: number;
  causes: Set<VisitCause>;
  bubble: { text: string; until: number } | null;
  seat: Cell | null;
  sitting: boolean;
  items: string[];
}

export type PartyState = 'arriving' | 'queue' | 'toSeat' | 'browsing' | 'waitOrder' | 'waitFood' | 'eating' | 'angry' | 'leaving' | 'gone';

export interface Party {
  id: string;
  members: CustAgent[];
  state: PartyState;
  prevState: PartyState | null;
  t: number;
  tableId: string | null;
  patience: number;
  orderId: string | null;
  servedBy: Set<string>;
  handledBy: Record<string, string>;
  complaintDone: boolean;
  paid: boolean;
  friend: boolean;
  quality: number | null;
}

export interface Order {
  id: string;
  partyId: string;
  items: string[];
  state: 'queued' | 'cooking' | 'ready' | 'carried' | 'served';
  slot: number;
  stationId: string | null;
  quality: number;
  cookedBy: string | null;
}

export interface Mess {
  id: string;
  cell: Cell;
}

export interface Note {
  t: number;
  text: string;
  kind: 'info' | 'warn' | 'good';
}

export interface VisitResult {
  defId: string | null;
  name: string;
  sat: number;
  causes: VisitCause[];
  items: string[];
  paid: number;
  servedBy: string[];
  tableId: string | null;
  friendOf: string | null;
  affinityGain: Record<string, number>;
  quality: number | null;
}

export interface MaidDayStats {
  tasks: number;
  greets: number;
  cooks: number;
  delivers: number;
  spills: number;
  complaintsCaused: number;
  happyServed: number;
  performSeconds: number;
  soloOrders: number;
  restSeconds: number;
}

interface Arrival {
  t: number;
  defId: string | null;
  size: number;
  done: boolean;
}

const ANON_NAMES = ['路過的上班族', '散步的學生', '觀光客', '附近的上班族', '好奇的路人', '情侶客人', '表演觀眾'];
const ANON_COLORS = [0x8a7a6a, 0x6a8aa0, 0xa07a8a, 0x7aa07a, 0x9a9a6a, 0x6a6aa0];

export class BusinessSim {
  t = 0;
  ended = false;
  layout: Layout;
  rng: Rng;
  workers: Worker[] = [];
  parties: Party[] = [];
  orders: Order[] = [];
  jobs: Job[] = [];
  messes: Mess[] = [];
  notes: Note[] = [];
  slots: (string | null)[] = PASS_SLOTS.map(() => null);
  stationBusy: Record<string, string | null> = {};
  dirtyTables = new Set<string>();
  reservedTables = new Set<string>();
  arrivals: Arrival[] = [];
  results: VisitResult[] = [];
  maidStats: Record<string, MaidDayStats> = {};
  affinityGain: Record<string, Record<string, number>> = {}; // partyId+member -> maid -> gain
  commandPoints = MAX_CP;
  cpTimer = 0;
  revenue = 0;
  servedCount = 0;
  lost = 0;
  complaints = 0;
  complaintsHandled = 0;
  spills = 0;
  congestion = 0;
  stageQuality = 0;
  private uid = 0;
  private claims = new Map<string, string>();

  constructor(public state: GameState) {
    this.layout = new Layout(state.furniture, state.upgrades);
    this.rng = new Rng(state.rngState);
    for (const st of this.layout.stations) this.stationBusy[st.id] = null;
    // workers
    const start: Cell[] = [
      { x: 11, z: 9 },
      { x: 3, z: 2 },
      { x: 5, z: 7 },
      { x: 9, z: 3 },
    ];
    activeMaids(state).forEach((m, i) => {
      const def = MAID_BY_ID[m.id];
      const c = m.role === 'off' ? IDLE_SPOTS.off[0] : (IDLE_SPOTS[m.role]?.[0] ?? start[i % start.length]);
      this.workers.push(this.makeWorker('maid', m.id, def.name, c));
      this.maidStats[m.id] = { tasks: 0, greets: 0, cooks: 0, delivers: 0, spills: 0, complaintsCaused: 0, happyServed: 0, performSeconds: 0, soloOrders: 0, restSeconds: 0 };
    });
    this.workers.push(this.makeWorker('manager', null, MANAGER.name, { x: 8, z: 9 }));
    this.planArrivals();
    // next-day reactions from maids
    for (const w of this.workers) {
      if (!w.maidId) continue;
      const m = this.maid(w.maidId)!;
      if (m.role === 'off') continue;
      const def = MAID_BY_ID[m.id];
      if (m.yesterday.includes('overworked')) this.say(w, def.lines.tired[0], 6);
      else if (m.yesterday.includes('complaint')) this.say(w, '今天要更小心才行……', 6);
      else if (m.yesterday.includes('praised')) this.say(w, def.lines.happy[0], 6);
    }
    this.note(`開始營業！今天預計有 ${this.arrivals.length} 組客人。`, 'info');
  }

  // ------------------------------------------------------------ helpers
  private id(p: string) {
    return `${p}${++this.uid}`;
  }
  maid(id: string): MaidState | undefined {
    return this.state.maids.find((m) => m.id === id);
  }
  maidOf(w: Worker) {
    return w.maidId ? this.maid(w.maidId) : undefined;
  }
  manager() {
    return this.workers.find((w) => w.kind === 'manager')!;
  }
  party(id: string | undefined | null) {
    return this.parties.find((p) => p.id === id);
  }
  order(id: string | undefined | null) {
    return this.orders.find((o) => o.id === id);
  }
  note(text: string, kind: Note['kind'] = 'info') {
    this.notes.push({ t: this.t, text, kind });
    if (this.notes.length > 60) this.notes.shift();
  }
  say(a: { bubble: { text: string; until: number } | null }, text: string, dur = 3.5) {
    a.bubble = { text, until: this.t + dur };
  }
  clock(): string {
    const mins = Math.min(this.t, DURATION) / DURATION * (CLOSE_HOUR - OPEN_HOUR) * 60;
    const h = OPEN_HOUR + Math.floor(mins / 60);
    const m = Math.floor(mins % 60);
    return `${h}:${String(m).padStart(2, '0')}`;
  }
  skill(w: Worker, k: keyof typeof MANAGER.skills): number {
    const m = this.maidOf(w);
    return m ? m.skills[k] : MANAGER.skills[k];
  }
  /** Time multiplier from a skill: 50 → 1.0, 100 → 0.6, 0 → 1.4 */
  speedF(s: number) {
    return 1.4 - (s / 100) * 0.8;
  }

  private makeWorker(kind: 'maid' | 'manager', maidId: string | null, name: string, c: Cell): Worker {
    return {
      id: maidId ?? 'manager', kind, maidId, name, pos: { x: c.x, z: c.z }, cell: { ...c }, path: [], speed: 2.4, waitT: 0, facing: 0, moving: false,
      inside: true, ghost: false, job: null, steps: [], stepT: 0, stepDur: 0, activity: '待命', paused: false, resting: false, restSpot: null,
      carrying: null, bubble: null, performing: false, idleChatT: 4 + Math.random() * 4, manual: false,
    };
  }

  // ------------------------------------------------------------ arrivals
  private planArrivals() {
    const s = this.state;
    const style = dominantStyle(s).key;
    const sigOnMenu = s.menu.some((d) => DISH_BY_ID[d]?.signature);
    for (const def of CUSTOMERS) {
      const mem = s.customers[def.id];
      if (!mem.known) continue;
      if (def.minDay && s.day < def.minDay) continue;
      let ch = def.baseChance + mem.loyalty * 0.004 + (s.popularity - 20) * 0.004;
      if (mem.lastSatisfaction != null) ch += (mem.lastSatisfaction - 60) * 0.006;
      if (mem.lastCauses.includes('walkedOut') || mem.lastCauses.includes('complaintIgnored')) ch -= 0.25;
      if (mem.isRegular) ch += 0.15;
      if (mem.visits === 0) ch += 0.15;
      if (def.style && def.style === style) ch += 0.1;
      if (s.activity === 'costume' && def.style === 'cute') ch += 0.25;
      if (s.activity === 'limited' && s.featuredDish && def.likes.includes(s.featuredDish)) ch += 0.35;
      if (s.activity === 'stage' && def.lively) ch += 0.3;
      if (s.activity === 'stage' && def.prefersQuiet) ch -= 0.2;
      if (sigOnMenu && def.prefCategory === 'dessert') ch += 0.15;
      if (def.id === 'chizuru' && mem.storyStage >= 1 && mem.visits === 0) ch = 0.95;
      ch = clamp(ch, 0.05, 0.95);
      if (this.rng.next() < ch) {
        const friend = mem.visits >= FRIEND_VISITS && mem.loyalty >= FRIEND_LOYALTY && (!mem.broughtFriend || this.rng.next() < 0.4);
        this.arrivals.push({ t: this.rng.range(def.arrival[0], Math.min(def.arrival[1], LAST_ARRIVAL)), defId: def.id, size: friend ? 2 : 1, done: false });
      }
    }
    let walkIns = Math.floor(1 + s.popularity / 15);
    if (s.activity === 'stage') walkIns += 3;
    if (s.activity === 'costume') walkIns += 1;
    if (s.activity === 'limited') walkIns += 2;
    for (let i = 0; i < walkIns; i++) {
      this.arrivals.push({ t: this.rng.range(5, LAST_ARRIVAL), defId: null, size: this.rng.next() < 0.3 ? 2 : 1, done: false });
    }
    this.arrivals.sort((a, b) => a.t - b.t);
  }

  private spawnParty(a: Arrival) {
    const def = a.defId ? CUSTOMER_BY_ID[a.defId] : null;
    const mem = a.defId ? this.state.customers[a.defId] : null;
    const pid = this.id('p');
    const members: CustAgent[] = [];
    const anonName = this.state.activity === 'stage' && this.rng.next() < 0.5 ? '表演觀眾' : this.rng.pick(ANON_NAMES.slice(0, 6));
    for (let i = 0; i < a.size; i++) {
      const isMain = i === 0;
      const name = def ? (isMain ? def.name : `${def.name}的朋友`) : isMain ? anonName : '同行的人';
      const color = def && isMain ? def.color : this.rng.pick(ANON_COLORS);
      const start = { x: 9 + (i ? 0.6 : 0) + (this.rng.next() < 0.5 ? -5 : 5), z: 13.5 };
      members.push({
        id: this.id('c'), partyId: pid, defId: isMain && def ? def.id : null, name, color, hair: def && isMain ? def.hair : 0x2a2a2a,
        pos: start, cell: { x: DOOR.x, z: DOOR.z }, path: [], speed: 2.0, waitT: 0, facing: 0, moving: true, inside: false, ghost: false,
        sat: def ? 65 : 60, causes: new Set(), bubble: null, seat: null, sitting: false, items: [],
      });
    }
    let patience = def ? def.patience : 30;
    if (mem) {
      if (mem.lastCauses.includes('longWaitDoor') || mem.lastCauses.includes('longWaitFood')) patience *= 0.8;
      patience *= 1 + mem.loyalty / 250;
    }
    const party: Party = {
      id: pid, members, state: 'arriving', prevState: null, t: 0, tableId: null, patience, orderId: null, servedBy: new Set(), handledBy: {},
      complaintDone: false, paid: false, friend: a.size > 1 && !!def, quality: null,
    };
    this.parties.push(party);
    // memory-driven greeting line
    const main = members[0];
    if (def && mem) {
      const line = this.arrivalLine(def, mem);
      if (line) this.say(main, line, 6);
      const fav = mem.favoriteMaid;
      if (fav) {
        const fm = this.maid(fav);
        if (!fm || fm.role === 'off' || fm.quit) {
          main.sat -= 4;
          main.causes.add('favMaidAbsent');
          this.say(main, `今天${MAID_BY_ID[fav].name}不在啊……`, 6);
        }
      }
      if (a.size > 1 && !mem.broughtFriend) this.note(`⭐ ${def.name}第一次帶朋友來了！`, 'good');
    }
  }

  private arrivalLine(def: CustomerDef, mem: GameState['customers'][string]): string | null {
    if (mem.visits === 0) return def.kind === 'special' ? '……就是這間店啊。' : '打擾了～';
    const c = mem.lastCauses;
    if (c.includes('complaintIgnored') || c.includes('walkedOut')) return '上次的事……再給一次機會吧。';
    if (c.includes('longWaitFood') || c.includes('longWaitDoor')) return '上次等好久……今天希望快一點。';
    if (c.includes('noisy') && def.prefersQuiet) return '今天應該比較安靜吧？';
    if (mem.favoriteMaid && this.maid(mem.favoriteMaid)?.role !== 'off') return `今天也想讓${MAID_BY_ID[mem.favoriteMaid].name}服務！`;
    if (c.includes('greatFood') && mem.favoriteDish) return `上次的${DISH_BY_ID[mem.favoriteDish].name}好好吃，今天也要點！`;
    if (mem.isRegular) return '老樣子，麻煩了。';
    return '又來了～';
  }

  // ------------------------------------------------------------ main update
  update(dt: number) {
    if (this.ended) return;
    const step = 0.1;
    while (dt > 0) {
      const d = Math.min(step, dt);
      this.tick(d);
      dt -= d;
      if (this.ended) break;
    }
  }

  private tick(dt: number) {
    this.t += dt;
    // command points
    this.cpTimer += dt;
    if (this.cpTimer >= CP_REGEN) {
      this.cpTimer = 0;
      this.commandPoints = Math.min(MAX_CP, this.commandPoints + 1);
    }
    for (const a of this.arrivals) {
      if (!a.done && a.t <= this.t) {
        a.done = true;
        this.spawnParty(a);
      }
    }
    this.rebuildClaims();
    for (const p of this.parties) this.updateParty(p, dt);
    this.parties = this.parties.filter((p) => p.state !== 'gone');
    this.refreshJobs();
    for (const w of this.workers) this.updateWorker(w, dt);
    this.updateMoods(dt);
    if (this.t >= DURATION && !this.flags.closed) {
      this.flags.closed = true;
      this.note('🔔 打烊時間到了，不再接新客人。', 'info');
      for (const p of this.parties) if (p.state === 'queue' || p.state === 'arriving') this.leave(p, false, true);
    }
    if (this.t >= DURATION && (this.parties.length === 0 || this.t >= HARD_END)) {
      for (const p of [...this.parties]) this.finishParty(p, true);
      this.ended = true;
      this.state.rngState = this.rng.s;
    }
  }
  private flags: Record<string, boolean> = {};

  // ------------------------------------------------------------ movement
  private movers(): Mover[] {
    const out: Mover[] = [...this.workers];
    for (const p of this.parties) for (const m of p.members) out.push(m);
    return out;
  }
  private rebuildClaims() {
    this.claims.clear();
    for (const m of this.movers()) {
      if (!m.inside || (m as CustAgent).sitting) continue;
      if (this.layout.walkable(m.cell)) this.claims.set(key(m.cell), m.id);
      if (m.moving && m.path.length) this.claims.set(key(m.path[0]), m.id);
    }
  }
  private setPath(m: Mover, goals: Cell[], allowGoal = false, avoid = false): boolean {
    const p = findPath(this.layout, m.cell, goals, {
      allowGoal,
      extraCost: avoid ? (c) => (this.claims.has(key(c)) && this.claims.get(key(c)) !== m.id ? 8 : 0) : undefined,
    });
    if (!p) return false;
    m.path = p;
    m.moving = p.length > 0;
    m.waitT = 0;
    return true;
  }
  /** Advance along path. Returns true when the path is complete. */
  private move(m: Mover, dt: number, speedMul = 1): boolean {
    if (!m.path.length) {
      m.moving = false;
      return true;
    }
    const next = m.path[0];
    const nk = key(next);
    const owner = this.claims.get(nk);
    const atCenter = Math.abs(m.pos.x - m.cell.x) < 0.01 && Math.abs(m.pos.z - m.cell.z) < 0.01;
    if (atCenter && owner && owner !== m.id && !m.ghost && this.layout.walkable(next)) {
      m.waitT += dt;
      this.congestion += dt;
      if (m.waitT > 1.4 && m.waitT - dt <= 1.4) {
        const goal = m.path[m.path.length - 1];
        const allow = !this.layout.walkable(goal);
        this.setPath(m, [goal], allow, true);
        m.waitT = 1.41;
      }
      if (m.waitT > 3) m.ghost = true;
      return false;
    }
    this.claims.set(nk, m.id);
    const dx = next.x - m.pos.x;
    const dz = next.z - m.pos.z;
    const dist = Math.hypot(dx, dz);
    const stepLen = m.speed * speedMul * dt;
    if (dist > 0.0001) m.facing = Math.atan2(dx, dz);
    if (dist <= stepLen) {
      m.pos = { x: next.x, z: next.z };
      if (this.claims.get(key(m.cell)) === m.id) this.claims.delete(key(m.cell));
      m.cell = { ...next };
      m.path.shift();
      m.ghost = false;
      m.waitT = 0;
      // stepping through a mess
      if ((m as CustAgent).partyId && this.messes.some((x) => sameCell(x.cell, m.cell))) {
        const c = m as CustAgent;
        if (!c.causes.has('spill')) {
          c.sat -= 3;
          c.causes.add('spill');
        }
      }
    } else {
      m.pos = { x: m.pos.x + (dx / dist) * stepLen, z: m.pos.z + (dz / dist) * stepLen };
    }
    m.moving = m.path.length > 0;
    return m.path.length === 0;
  }
  /** Straight-line move for the outside-the-door street. */
  private lerpTo(m: Mover, target: Vec, dt: number): boolean {
    const dx = target.x - m.pos.x;
    const dz = target.z - m.pos.z;
    const d = Math.hypot(dx, dz);
    const s = m.speed * dt;
    if (d > 0.001) m.facing = Math.atan2(dx, dz);
    if (d <= s) {
      m.pos = { ...target };
      m.moving = false;
      return true;
    }
    m.moving = true;
    m.pos = { x: m.pos.x + (dx / d) * s, z: m.pos.z + (dz / d) * s };
    return false;
  }

  // ------------------------------------------------------------ parties
  queueIndex(p: Party) {
    return this.parties.filter((x) => x.state === 'queue' || x.state === 'arriving').indexOf(p);
  }

  private updateParty(p: Party, dt: number) {
    p.t += dt;
    const main = p.members[0];
    const def = main.defId ? CUSTOMER_BY_ID[main.defId] : null;
    switch (p.state) {
      case 'arriving':
      case 'queue': {
        const qi = Math.max(0, this.queueIndex(p));
        p.members.forEach((m, i) => {
          const target = { x: DOOR.x + (i ? 0.55 : 0) - 0.25 * (p.members.length - 1), z: DOOR.z + 1.2 + qi * 0.9 };
          const arrived = this.lerpTo(m, target, dt);
          if (arrived && p.state === 'arriving') {
            p.state = 'queue';
            p.t = 0;
          }
          m.facing = Math.PI;
        });
        if (p.state === 'queue' && p.t > p.patience * 0.5) for (const m of p.members) m.sat -= 0.4 * dt;
        if (p.state === 'queue' && p.t > p.patience) {
          for (const m of p.members) m.causes.add('longWaitDoor');
          this.say(main, '等太久了，下次再來吧……', 4);
          this.note(`${main.name}在門口等太久，離開了。`, 'warn');
          this.leave(p, false);
        }
        break;
      }
      case 'toSeat': {
        let all = true;
        for (const m of p.members) {
          if (!m.inside) {
            if (this.lerpTo(m, { x: DOOR.x, z: DOOR.z }, dt)) {
              m.inside = true;
              m.cell = { ...DOOR };
              if (m.seat) this.setPath(m, [m.seat], true);
            }
            all = false;
            continue;
          }
          if (!m.sitting) {
            if (this.move(m, dt) && m.seat && sameCell(m.cell, m.seat)) {
              m.sitting = true;
              const t = this.layout.tableById(p.tableId!);
              if (t) m.facing = Math.atan2(t.cell.x - m.seat.x, 0);
            } else all = false;
          }
        }
        if (all) {
          p.state = 'browsing';
          p.t = 0;
        }
        break;
      }
      case 'browsing':
        if (p.t > 3) {
          p.state = 'waitOrder';
          p.t = 0;
          this.addJob('order', { partyId: p.id, preferred: this.prefMaid(p) });
        }
        break;
      case 'waitOrder':
      case 'waitFood': {
        const grace = p.state === 'waitOrder' ? 12 : 32;
        const drain = p.state === 'waitOrder' ? 0.8 : 0.55;
        if (p.t > grace * (p.patience / 30)) {
          for (const m of p.members) {
            m.sat -= drain * dt;
            m.causes.add(p.state === 'waitOrder' ? 'longWaitOrder' : 'longWaitFood');
          }
        }
        if (main.sat < 25 && !p.complaintDone) {
          p.prevState = p.state;
          p.state = 'angry';
          p.t = 0;
          this.complaints++;
          this.say(main, '💢 到底還要等多久！叫負責人來！', 8);
          this.note(`💢 ${main.name}發脾氣了！請店長（或管理能力高的女僕）去處理。`, 'warn');
          this.addJob('complaint', { partyId: p.id, preferred: 'manager' });
          // blame whoever let it happen
          const blame = p.state === 'angry' && p.orderId ? this.order(p.orderId)?.cookedBy : null;
          if (blame && this.maidStats[blame]) this.maidStats[blame].complaintsCaused++;
        } else if (main.sat < 8) {
          this.say(main, '……算了。', 4);
          this.note(`${main.name}受不了等待，離開了。`, 'warn');
          for (const m of p.members) m.causes.add('walkedOut');
          this.leave(p, false);
        }
        break;
      }
      case 'angry':
        if (p.t > 25) {
          for (const m of p.members) m.causes.add('complaintIgnored');
          this.say(main, '這種店不會再來了！', 5);
          this.note(`${main.name}氣沖沖地離開了。人氣下降。`, 'warn');
          this.state.popularity = clamp(this.state.popularity - 3);
          this.leave(p, false);
        }
        break;
      case 'eating': {
        const eatDur = 16 + main.items.length * 4;
        this.applyShow(p, dt);
        if (p.t > eatDur) this.leave(p, true);
        break;
      }
      case 'leaving': {
        let all = true;
        for (const m of p.members) {
          if (m.inside) {
            if (m.sitting) {
              m.sitting = false;
              // stand up onto a free neighbouring cell
              const n = this.layout.adjacentWalkable([m.seat!])[0];
              if (n) {
                m.cell = { ...n };
                m.pos = { x: n.x, z: n.z };
              }
              this.setPath(m, [DOOR]);
            }
            if (this.move(m, dt)) {
              if (sameCell(m.cell, DOOR)) m.inside = false;
              else if (!this.setPath(m, [DOOR])) m.inside = false;
            }
            all = false;
          } else {
            if (!this.lerpTo(m, { x: DOOR.x + (m.id.length % 2 ? -7 : 7), z: 13.5 }, dt)) all = false;
          }
        }
        if (all) this.finishParty(p, false);
        break;
      }
    }
    void def;
  }

  private applyShow(p: Party, dt: number) {
    if (this.stageQuality <= 0) return;
    for (const m of p.members) {
      const def = m.defId ? CUSTOMER_BY_ID[m.defId] : null;
      if (def?.prefersQuiet) {
        m.sat -= 0.18 * dt;
        m.causes.add('noisy');
      } else {
        m.sat += this.stageQuality * (def?.lively || !def ? 0.3 : 0.15) * dt;
        m.causes.add('enjoyedShow');
      }
    }
  }

  private prefMaid(p: Party): string | null {
    const main = p.members[0];
    if (!main.defId) return null;
    const fav = this.state.customers[main.defId].favoriteMaid;
    if (!fav) return null;
    const m = this.maid(fav);
    return m && m.role !== 'off' && !m.quit ? fav : null;
  }

  private leave(p: Party, served: boolean, closing = false) {
    if (p.state === 'leaving' || p.state === 'gone') return;
    // cancel any pending jobs for this party
    for (const j of this.jobs) if (j.partyId === p.id && !j.done) j.cancelled = true;
    for (const o of this.orders) {
      if (o.partyId !== p.id) continue;
      if (o.slot >= 0 && this.slots[o.slot] === o.id) this.slots[o.slot] = null;
    }
    if (p.tableId) {
      this.reservedTables.delete(p.tableId);
      if (p.members.some((m) => m.inside)) {
        this.dirtyTables.add(p.tableId);
        this.addJob('clean', { tableId: p.tableId });
      }
    }
    if (served && !p.paid) {
      p.paid = true;
      let total = 0;
      for (const m of p.members)
        for (const it of m.items) {
          const d = DISH_BY_ID[it];
          total += Math.round(d.price * (it === this.state.featuredDish && this.state.activity === 'limited' ? 1.25 : 1));
        }
      this.revenue += total;
      this.servedCount += p.members.length;
      this.state.money += total;
      const main = p.members[0];
      const sat = main.sat;
      this.say(main, sat >= 75 ? '好開心！我還會再來的！' : sat >= 50 ? '謝謝招待～' : '嗯……', 4);
      for (const mid of p.servedBy) {
        const ms = this.maid(mid);
        if (!ms) continue;
        if (sat >= 75) {
          ms.mood = clamp(ms.mood + 3);
          this.maidStats[mid].happyServed++;
        } else if (sat < 35) ms.mood = clamp(ms.mood - 2);
      }
    } else if (!closing) {
      this.lost += p.members.length;
    }
    p.state = 'leaving';
    p.t = 0;
    for (const m of p.members) if (!m.inside) m.moving = true;
  }

  private finishParty(p: Party, forced: boolean) {
    if (p.state === 'gone') return;
    if (forced && !p.paid && p.members.some((m) => m.items.length)) {
      // closing time: settle the bill of anyone already served
      if (p.state === 'eating') this.leave(p, true);
    }
    p.state = 'gone';
    if (p.tableId) this.reservedTables.delete(p.tableId);
    for (const m of p.members) {
      if (!m.defId && !p.friend) {
        // anonymous customers still count for satisfaction stats
      }
      this.results.push({
        defId: m.defId,
        name: m.name,
        sat: clamp(m.sat),
        causes: [...m.causes],
        items: m.items,
        paid: p.paid ? m.items.reduce((a, it) => a + DISH_BY_ID[it].price, 0) : 0,
        servedBy: [...p.servedBy],
        tableId: p.tableId,
        friendOf: m.defId ? null : p.friend ? p.members[0].defId : null,
        affinityGain: this.affinityGain[m.id] ?? {},
        quality: p.quality,
      });
    }
  }

  // ------------------------------------------------------------ jobs
  private addJob(type: JobType, o: Partial<Job> = {}): Job {
    const j: Job = { id: this.id('j'), type, created: this.t, claimedBy: null, preferred: null, done: false, cancelled: false, ...o };
    this.jobs.push(j);
    return j;
  }
  private refreshJobs() {
    this.jobs = this.jobs.filter((j) => !j.done && !j.cancelled);
    // greet jobs for queued parties
    for (const p of this.parties) {
      if (p.state === 'queue' && !this.jobs.some((j) => j.type === 'greet' && j.partyId === p.id)) {
        this.addJob('greet', { partyId: p.id, preferred: this.prefMaid(p) });
      }
    }
  }

  /** Whether a job can currently be started by worker w. */
  jobAvailable(j: Job, w: Worker): boolean {
    if (j.done || j.cancelled) return false;
    switch (j.type) {
      case 'greet': {
        const p = this.party(j.partyId);
        return !!p && p.state === 'queue' && this.freeTable(p) !== null;
      }
      case 'cook':
        return this.freeStation(this.order(j.orderId)!) !== null && this.slots.some((s) => s === null);
      case 'complaint':
        return w.kind === 'manager' || this.skill(w, 'management') >= 50;
      case 'clean':
        return true;
      default:
        return true;
    }
  }

  private roleWeights(role: Role): Partial<Record<JobType, number>> {
    switch (role) {
      case 'reception':
        return { greet: 10, order: 9, complaint: 8, clean: 5, deliver: 4, mess: 4, cook: 0.5 };
      case 'kitchen':
        return { cook: 10, deliver: 3, mess: 2, clean: 1 };
      case 'floor':
        return { deliver: 10, mess: 9, clean: 8, order: 6, greet: 5, complaint: 6, cook: 0.5 };
      default:
        return {};
    }
  }

  private pickJob(w: Worker): Job | null {
    const m = this.maidOf(w);
    if (!m) return null;
    const weights = this.roleWeights(m.role);
    const kitchenStaffed = this.workers.some((x) => x.maidId && this.maid(x.maidId)?.role === 'kitchen' && !x.paused && !x.resting);
    let best: Job | null = null;
    let bestScore = -Infinity;
    for (const j of this.jobs) {
      if (j.claimedBy || j.done || j.cancelled) continue;
      let wgt = weights[j.type] ?? 0;
      if (j.type === 'cook' && !kitchenStaffed && wgt < 1) wgt = 6; // someone has to cook
      if (wgt <= 0) continue;
      if (!this.jobAvailable(j, w)) continue;
      const tgt = this.jobAnchor(j);
      const dist = tgt ? manhattan(w.cell, tgt) : 0;
      let score = wgt * 100 - dist * 3 + Math.min(60, (this.t - j.created) * 2);
      if (j.preferred && j.preferred === w.maidId) score += 120;
      if (j.preferred && j.preferred !== w.maidId && j.preferred !== 'manager') score -= 40;
      if (score > bestScore) {
        bestScore = score;
        best = j;
      }
    }
    return best;
  }

  private jobAnchor(j: Job): Cell | null {
    switch (j.type) {
      case 'greet':
        return GREET_SPOT;
      case 'order':
      case 'complaint': {
        const p = this.party(j.partyId);
        return p?.tableId ? this.layout.tableById(p.tableId)!.cell : null;
      }
      case 'cook':
        return this.layout.stations[0].stand;
      case 'deliver': {
        const o = this.order(j.orderId);
        return o && o.slot >= 0 ? PASS_SLOTS[o.slot] : null;
      }
      case 'clean':
        return this.layout.tableById(j.tableId!)?.cell ?? null;
      case 'mess':
        return this.messes.find((m) => m.id === j.messId)?.cell ?? null;
    }
  }

  private freeTable(p: Party): string | null {
    const free = this.layout.tables.filter((t) => !this.reservedTables.has(t.id) && !this.dirtyTables.has(t.id));
    if (!free.length) return null;
    const def = p.members[0].defId ? CUSTOMER_BY_ID[p.members[0].defId] : null;
    const mem = def ? this.state.customers[def.id] : null;
    const stage = this.layout.stageCells[0];
    let best = free[0];
    let bestS = -Infinity;
    for (const t of free) {
      let s = -manhattan(t.cell, DOOR_IN);
      if (def?.prefersQuiet) s = manhattan(t.cell, DOOR_IN) + (stage ? manhattan(t.cell, stage) : 0);
      if (def?.lively && stage) s = -manhattan(t.cell, stage) * 2;
      if (mem?.favoriteSeat === t.id) s += 100;
      if (s > bestS) {
        bestS = s;
        best = t;
      }
    }
    return best.id;
  }

  private freeStation(o: Order): string | null {
    const needStove = o.items.some((i) => DISH_BY_ID[i].station === 'stove');
    for (const st of this.layout.stations) {
      if (this.stationBusy[st.id]) continue;
      if (needStove && st.kind !== 'stove') continue;
      if (!needStove && st.kind !== 'coffee' && this.layout.stations.some((x) => x.kind === 'coffee' && !this.stationBusy[x.id])) continue;
      return st.id;
    }
    return null;
  }

  // ------------------------------------------------------------ job → steps
  private assign(w: Worker, j: Job) {
    j.claimedBy = w.id;
    w.job = j;
    w.stepT = 0;
    w.steps = this.buildSteps(w, j);
    w.activity = JOB_NAMES[j.type];
  }

  private release(w: Worker) {
    const j = w.job;
    if (j && !j.done) {
      j.claimedBy = null;
      if (j.type === 'cook') {
        const o = this.order(j.orderId);
        if (o && o.state === 'cooking') {
          if (o.stationId) this.stationBusy[o.stationId] = null;
          o.state = 'queued';
          o.stationId = null;
          if (o.slot >= 0 && this.slots[o.slot] === o.id) this.slots[o.slot] = null;
          o.slot = -1;
        }
      }
      if (j.type === 'greet') {
        const p = this.party(j.partyId);
        if (p?.tableId && p.state === 'queue') {
          this.reservedTables.delete(p.tableId);
          p.tableId = null;
        }
      }
    }
    w.job = null;
    w.steps = [];
    w.path = [];
    w.moving = false;
    w.manual = false;
    w.carrying = null;
    w.activity = '待命';
  }

  private tableGoals(tableId: string | null | undefined): () => Cell[] {
    return () => {
      const t = tableId ? this.layout.tableById(tableId) : null;
      return t ? this.layout.adjacentWalkable([t.cell, ...t.seats]) : [];
    };
  }

  private buildSteps(w: Worker, j: Job): Step[] {
    const recv = this.skill(w, 'reception');
    const m = this.maidOf(w);
    const def = m ? MAID_BY_ID[m.id] : null;
    switch (j.type) {
      case 'greet': {
        let dur = 2.4 * this.speedF(recv);
        if (def?.traits.includes('shy')) dur *= 1.5 - Math.min(0.5, (m!.greetsDone || 0) * 0.02);
        return [
          { kind: 'goto', goals: () => [GREET_SPOT, DOOR_IN], label: '前往門口' },
          { kind: 'check', ok: () => !!this.party(j.partyId) && this.party(j.partyId)!.state === 'queue' },
          {
            kind: 'work', dur, label: '迎賓', done: (wk) => {
              const p = this.party(j.partyId);
              if (!p || p.state !== 'queue') return;
              const tid = this.freeTable(p);
              if (!tid) {
                this.say(wk, '請稍等一下，馬上幫您安排～', 3);
                j.claimedBy = null;
                return;
              }
              const t = this.layout.tableById(tid)!;
              p.tableId = tid;
              this.reservedTables.add(tid);
              p.members.forEach((c, i) => (c.seat = t.seats[i % t.seats.length]));
              p.state = 'toSeat';
              p.t = 0;
              p.handledBy.greet = wk.id;
              if (wk.maidId) {
                p.servedBy.add(wk.maidId);
                m!.greetsDone++;
                this.maidStats[wk.maidId].greets++;
                this.gainExp(m!, 'reception', 3);
              }
              this.say(wk, def ? this.rng.pick(def.lines.greet) : '歡迎光臨！', 3);
              this.interact(wk, p, 1);
              const main = p.members[0];
              if (main.defId && this.state.customers[main.defId].favoriteSeat === tid) {
                main.sat += 3;
                main.causes.add('favSeat');
              }
              const ds = dominantStyle(this.state);
              const cdef = main.defId ? CUSTOMER_BY_ID[main.defId] : null;
              if (cdef?.style && cdef.style === ds.key) {
                main.sat += 4;
                main.causes.add('styleMatch');
              }
              if (cdef?.style === 'cute' && this.state.furniture.some((f) => f.type === 'photo')) main.sat += 3;
              j.done = true;
            },
          },
        ];
      }
      case 'order':
        return [
          { kind: 'goto', goals: this.tableGoals(this.party(j.partyId)?.tableId), label: '前往桌邊' },
          {
            kind: 'work', dur: 3 * this.speedF(recv), label: '點餐中', done: (wk) => {
              const p = this.party(j.partyId);
              if (!p) return;
              const angry = p.state === 'angry' && p.prevState === 'waitOrder';
              if (p.state !== 'waitOrder' && !angry) return;
              this.takeOrder(p);
              if (angry && p.state === 'waitFood') {
                p.state = 'angry';
                p.prevState = 'waitFood';
              }
              p.handledBy.order = wk.id;
              if (wk.maidId) {
                p.servedBy.add(wk.maidId);
                this.gainExp(m!, 'reception', 3);
              }
              this.interact(wk, p, 1);
              j.done = true;
            },
          },
        ];
      case 'cook': {
        const o = this.order(j.orderId)!;
        const stId = this.freeStation(o)!;
        const st = this.layout.stations.find((s) => s.id === stId)!;
        this.stationBusy[stId] = o.id;
        o.stationId = stId;
        o.state = 'cooking';
        o.slot = this.slots.findIndex((s) => s === null);
        this.slots[o.slot] = `reserved:${o.id}`;
        let base = 0;
        for (const it of o.items) {
          const d = DISH_BY_ID[it];
          base += d.time * (d.category === 'drink' && this.state.upgrades.coffeeMachine ? 0.7 : 1);
        }
        let dur = base * this.speedF(this.skill(w, 'cooking'));
        if (def?.traits.includes('perfectionist')) dur *= 1.1;
        return [
          { kind: 'goto', goals: () => [st.stand], label: '前往廚房' },
          {
            kind: 'work', dur, label: `製作${o.items.map((i) => DISH_BY_ID[i].name).join('＋')}`, done: (wk) => {
              this.stationBusy[stId] = null;
              o.quality = this.cookQuality(wk, o);
              o.state = 'ready';
              o.cookedBy = wk.maidId;
              this.slots[o.slot] = o.id;
              const p = this.party(o.partyId);
              if (p) p.handledBy.cook = wk.id;
              if (wk.maidId) {
                this.maidStats[wk.maidId].cooks++;
                this.gainExp(m!, 'cooking', 4);
                const ms = m!;
                ms.fatigue = clamp(ms.fatigue + (def?.traits.includes('perfectionist') ? 5 : 3));
                if (o.quality >= 75) this.say(wk, def!.lines.happy[1] ?? def!.lines.happy[0], 2.5);
              }
              j.done = true;
              if (p) this.addJob('deliver', { orderId: o.id, partyId: p.id, preferred: this.prefMaid(p) });
              else {
                this.slots[o.slot] = null;
              }
            },
          },
        ];
      }
      case 'deliver': {
        const o = this.order(j.orderId)!;
        return [
          { kind: 'goto', goals: () => this.layout.adjacentWalkable([PASS_SLOTS[o.slot]]), label: '取餐' },
          {
            kind: 'work', dur: 0.5, label: '取餐', done: (wk) => {
              this.slots[o.slot] = null;
              o.slot = -1;
              o.state = 'carried';
              wk.carrying = o.id;
            },
          },
          { kind: 'goto', goals: this.tableGoals(this.party(o.partyId)?.tableId), label: '送餐中' },
          {
            kind: 'work', dur: 0.9 * this.speedF(this.skill(w, 'floor')), label: '上菜', done: (wk) => {
              wk.carrying = null;
              const p = this.party(o.partyId);
              if (!p || (p.state !== 'waitFood' && p.state !== 'angry')) {
                o.state = 'served';
                j.done = true;
                return;
              }
              if (this.trySpill(wk, o, p)) {
                j.done = true;
                return;
              }
              this.serve(wk, o, p);
              j.done = true;
            },
          },
        ];
      }
      case 'clean':
        return [
          { kind: 'goto', goals: this.tableGoals(j.tableId), label: '前往桌邊' },
          {
            kind: 'work', dur: 2.6 * this.speedF(this.skill(w, 'floor')), label: '整理桌面', done: (wk) => {
              this.dirtyTables.delete(j.tableId!);
              if (wk.maidId) this.gainExp(m!, 'floor', 2);
              j.done = true;
            },
          },
        ];
      case 'mess': {
        const mess = this.messes.find((x) => x.id === j.messId)!;
        return [
          { kind: 'goto', goals: () => (mess ? [mess.cell, ...this.layout.adjacentWalkable([mess.cell])] : []), label: '拿拖把' },
          {
            kind: 'work', dur: 2.5 * this.speedF(this.skill(w, 'floor')), label: '清理地板', done: (wk) => {
              this.messes = this.messes.filter((x) => x.id !== j.messId);
              if (wk.maidId) this.gainExp(m!, 'floor', 2);
              j.done = true;
            },
          },
        ];
      }
      case 'complaint':
        return [
          { kind: 'goto', goals: this.tableGoals(this.party(j.partyId)?.tableId), label: '趕去處理客訴' },
          {
            kind: 'work', dur: 4 * this.speedF(this.skill(w, 'management')), label: '道歉中', done: (wk) => {
              const p = this.party(j.partyId);
              if (!p || p.state !== 'angry') return;
              p.state = p.prevState ?? 'waitFood';
              p.t = 0;
              p.complaintDone = true;
              this.complaintsHandled++;
              for (const c of p.members) {
                c.sat = Math.max(c.sat, wk.kind === 'manager' ? 52 : 45);
                c.causes.add('complaintHandled');
              }
              this.say(wk, '真的非常抱歉，我們馬上為您處理！', 3);
              this.say(p.members[0], '……好吧，這次就算了。', 4);
              this.note(`✅ ${wk.name}安撫了${p.members[0].name}。`, 'good');
              if (wk.maidId) this.gainExp(m!, 'management', 6);
              j.done = true;
            },
          },
        ];
    }
  }

  private interact(w: Worker, p: Party, weight: number) {
    if (!w.maidId) return;
    const m = this.maidOf(w)!;
    const def = MAID_BY_ID[m.id];
    for (const c of p.members) {
      let gain = (3 + (m.skills.reception - 50) / 20 + (m.mood - 50) / 25) * weight;
      const visits = c.defId ? this.state.customers[c.defId].visits : 0;
      if (def.traits.includes('slowWarm')) gain *= visits < 2 ? 0.5 : 1.6;
      if (def.traits.includes('shy')) gain *= 0.6 + Math.min(0.6, m.greetsDone / 40);
      if (def.traits.includes('cheerful')) gain += 1;
      gain = Math.max(0.5, gain);
      const rec = (this.affinityGain[c.id] ??= {});
      rec[m.id] = (rec[m.id] ?? 0) + gain;
      if (c.defId) {
        const mem = this.state.customers[c.defId];
        if (mem.favoriteMaid === m.id && !c.causes.has('favMaid')) {
          c.sat += 8;
          c.causes.add('favMaid');
          this.say(c, `是${def.name}！`, 3);
        }
      }
    }
  }

  private takeOrder(p: Party) {
    const s = this.state;
    const items: string[] = [];
    const avail = (id: string) => {
      const d = DISH_BY_ID[id];
      return d && servingsPossible(s.inventory, d) >= 1;
    };
    for (const c of p.members) {
      const def = c.defId ? CUSTOMER_BY_ID[c.defId] : null;
      const mem = c.defId ? s.customers[c.defId] : null;
      const budget = def ? def.budget : 1100;
      const likes = def ? def.likes : [this.rng.pick(s.menu), this.rng.pick(s.menu)];
      const missing = likes.filter((l) => !s.menu.includes(l) || !avail(l));
      if (def && missing.length === likes.length) {
        c.sat -= 6;
        c.causes.add('outOfStock');
        this.say(c, `沒有${DISH_BY_ID[likes[0]].name}啊……`, 4);
      }
      const choose = (cats: string[], left: number) => {
        let best: string | null = null;
        let bs = -Infinity;
        for (const id of s.menu) {
          const d = DISH_BY_ID[id];
          if (!d || !cats.includes(d.category) || !avail(id) || d.price > left) continue;
          let sc = this.rng.next();
          if (likes.includes(id)) sc += 5;
          if (mem?.favoriteDish === id) sc += 4;
          if (def && d.category === def.prefCategory) sc += 2;
          if (s.activity === 'limited' && s.featuredDish === id) sc += 3;
          if (d.signature && def?.prefCategory === 'dessert') sc += 3;
          if (sc > bs) {
            bs = sc;
            best = id;
          }
        }
        return best;
      };
      const pref = def?.prefCategory ?? this.rng.pick(['main', 'dessert'] as const);
      const first = choose(pref === 'drink' ? ['drink'] : [pref, pref === 'main' ? 'dessert' : 'main'], budget);
      const mine: string[] = [];
      if (first) mine.push(first);
      const left = budget - (first ? DISH_BY_ID[first].price : 0);
      const second = pref === 'drink' ? choose(['dessert', 'main'], left) : choose(['drink'], left);
      if (second && (pref === 'drink' || this.rng.next() < 0.75)) mine.push(second);
      for (const id of mine) {
        const d = DISH_BY_ID[id];
        for (const k in d.ingredients) s.inventory[k] -= d.ingredients[k];
      }
      c.items = mine;
      items.push(...mine);
    }
    if (!items.length) {
      for (const c of p.members) c.causes.add('outOfStock');
      this.say(p.members[0], '想吃的都賣完了……', 4);
      this.note(`${p.members[0].name}想點的都賣完了，只好離開。記得多採購食材！`, 'warn');
      this.leave(p, false);
      return;
    }
    const o: Order = { id: this.id('o'), partyId: p.id, items, state: 'queued', slot: -1, stationId: null, quality: 0, cookedBy: null };
    this.orders.push(o);
    p.orderId = o.id;
    p.state = 'waitFood';
    p.t = 0;
    this.addJob('cook', { orderId: o.id, partyId: p.id });
  }

  private cookQuality(w: Worker, o: Order): number {
    const m = this.maidOf(w);
    const def = m ? MAID_BY_ID[m.id] : null;
    let total = 0;
    for (const it of o.items) {
      const d = DISH_BY_ID[it];
      let q = d.quality + (this.skill(w, 'cooking') - 50) * 0.5;
      if (m) {
        q += (m.mood - 50) * 0.1;
        if (m.fatigue > 70) q -= 8;
      }
      if (def?.traits.includes('perfectionist')) q += 8;
      if (d.category === 'drink' && this.state.upgrades.coffeeMachine) q += 10;
      if (d.category === 'dessert' && this.state.partners.includes('sweets') && (d.ingredients.cream || d.ingredients.strawberry || d.ingredients.chocolate)) q += 8;
      total += q;
    }
    return clamp(total / o.items.length);
  }

  private trySpill(w: Worker, o: Order, p: Party): boolean {
    const m = this.maidOf(w);
    if (!m) return false;
    const def = MAID_BY_ID[m.id];
    let chance = 0.03;
    if (m.fatigue > 70) chance += 0.08;
    if (m.mood < 30) chance += 0.06;
    if (def.traits.includes('careful')) chance -= 0.025;
    chance -= m.skills.floor / 2000;
    if (this.rng.next() >= Math.max(0.005, chance)) return false;
    this.spills++;
    this.maidStats[m.id].spills++;
    m.mood = clamp(m.mood - 6);
    m.yesterday.push('spill');
    const mess: Mess = { id: this.id('m'), cell: { ...w.cell } };
    this.messes.push(mess);
    this.addJob('mess', { messId: mess.id });
    this.say(w, this.rng.pick(def.lines.sorry), 3);
    this.note(`💦 ${def.name}打翻了餐點！需要清理地板並重新製作。`, 'warn');
    for (const c of p.members) {
      c.sat -= 8;
      c.causes.add('spill');
    }
    o.state = 'queued';
    o.slot = -1;
    const s = this.state;
    for (const it of o.items) {
      const d = DISH_BY_ID[it];
      for (const k in d.ingredients) s.inventory[k] = Math.max(0, (s.inventory[k] ?? 0) - d.ingredients[k]);
    }
    this.addJob('cook', { orderId: o.id, partyId: p.id });
    return true;
  }

  private serve(w: Worker, o: Order, p: Party) {
    o.state = 'served';
    p.quality = o.quality;
    p.handledBy.deliver = w.id;
    if (w.maidId) {
      p.servedBy.add(w.maidId);
      this.maidStats[w.maidId].delivers++;
      this.gainExp(this.maidOf(w)!, 'floor', 3);
      // solo order: same maid greeted, took the order and delivered
      if (p.handledBy.greet === w.id && p.handledBy.order === w.id) this.maidStats[w.maidId].soloOrders++;
    }
    for (const c of p.members) {
      const def = c.defId ? CUSTOMER_BY_ID[c.defId] : null;
      c.sat += (o.quality - 55) * 0.4;
      if (o.quality >= 75) c.causes.add('greatFood');
      if (o.quality < 40) c.causes.add('badFood');
      if (def && c.items.some((i) => def.likes.includes(i))) {
        c.sat += 6;
        c.causes.add('favDish');
      }
    }
    this.interact(w, p, 0.8);
    this.say(w, '讓您久等了，請慢用～', 2.5);
    if (p.state === 'angry') {
      p.complaintDone = true;
      for (const j of this.jobs) if (j.partyId === p.id && j.type === 'complaint') j.cancelled = true;
    }
    p.state = 'eating';
    p.t = 0;
  }

  private gainExp(m: MaidState, k: keyof MaidState['skills'], n: number) {
    m.exp[k] += n;
    const cap = MAID_BY_ID[m.id].caps[k];
    while (m.exp[k] >= 12) {
      m.exp[k] -= 12;
      if (m.skills[k] < cap) {
        m.skills[k] += 1;
      }
    }
  }

  // ------------------------------------------------------------ workers
  private updateWorker(w: Worker, dt: number) {
    if (w.bubble && w.bubble.until < this.t) w.bubble = null;
    const m = this.maidOf(w);
    const speedMul = m ? (0.85 + m.skills.floor / 100 * 0.3) * (m.fatigue > 70 ? 0.82 : 1) : 1.05;

    if (m && m.role === 'off') {
      w.activity = '休假中';
      this.goIdle(w, dt, IDLE_SPOTS.off, speedMul);
      return;
    }
    if (w.paused) {
      w.activity = '暫停中';
      return;
    }
    // resting
    if (m && !w.resting && !w.job && m.fatigue >= 90) this.startRest(w);
    if (w.resting && m) {
      if (!w.restSpot) w.restSpot = REST_SPOTS.find((r) => !this.workers.some((o) => o !== w && o.restSpot && sameCell(o.restSpot, r))) ?? REST_SPOTS[0];
      if (!sameCell(w.cell, w.restSpot) && !w.path.length) this.setPath(w, [w.restSpot]);
      if (this.move(w, dt, speedMul)) {
        w.activity = '休息中';
        m.fatigue = clamp(m.fatigue - (this.state.upgrades.sofa ? 2.2 : 1.3) * dt);
        this.maidStats[m.id].restSeconds += dt;
        if (m.fatigue <= 35) {
          w.resting = false;
          w.restSpot = null;
          this.say(w, '好，回去工作！', 2);
        }
      }
      return;
    }
    // stage performer
    if (m && m.role === 'stage') {
      this.updatePerformer(w, m, dt, speedMul);
      return;
    }
    if (w.job && (w.job.cancelled || (w.job.done && !w.steps.length))) this.release(w);
    if (!w.job && w.kind === 'maid') {
      const j = this.pickJob(w);
      if (j) this.assign(w, j);
    }
    if (!w.job) {
      if (w.kind === 'manager') {
        w.activity = w.path.length ? '移動中' : '巡視中';
        this.move(w, dt, speedMul);
      } else {
        w.activity = '待命';
        this.goIdle(w, dt, IDLE_SPOTS[m!.role] ?? IDLE_SPOTS.floor, speedMul);
      }
      return;
    }
    this.runSteps(w, dt, speedMul);
    if (m) m.fatigue = clamp(m.fatigue + (MAID_BY_ID[m.id].traits.includes("perfectionist") ? 0.14 : 0.11) * dt);
  }

  private runSteps(w: Worker, dt: number, speedMul: number) {
    const step = w.steps[0];
    if (!step) {
      if (w.job) w.job.done = true;
      this.release(w);
      return;
    }
    if (step.kind === 'check') {
      if (!step.ok(w)) {
        if (w.job) w.job.cancelled = true;
        this.release(w);
        return;
      }
      w.steps.shift();
      return;
    }
    if (step.kind === 'goto') {
      w.activity = step.label;
      const goals = step.goals();
      if (!goals.length) {
        if (w.job) w.job.cancelled = true;
        this.release(w);
        return;
      }
      if (goals.some((g) => sameCell(g, w.cell)) && !w.path.length) {
        w.steps.shift();
        return;
      }
      if (!w.path.length || !goals.some((g) => sameCell(g, w.path[w.path.length - 1]))) {
        if (!this.setPath(w, goals, step.allowGoal)) {
          if (w.job) w.job.claimedBy = null;
          this.release(w);
          return;
        }
      }
      if (this.move(w, dt, speedMul)) w.steps.shift();
      return;
    }
    // work
    w.activity = step.label;
    w.stepDur = step.dur;
    w.stepT += dt;
    if (w.stepT >= step.dur) {
      w.stepT = 0;
      w.steps.shift();
      const m = this.maidOf(w);
      if (m) this.maidStats[m.id].tasks += 0.5;
      step.done(w);
      if (w.job && !w.job.done && w.job.claimedBy === null) {
        // job handed back (e.g. no table free)
        const j = w.job;
        w.job = null;
        w.steps = [];
        j.claimedBy = null;
      }
      if (w.job?.done && !w.steps.length) this.release(w);
    }
  }

  private goIdle(w: Worker, dt: number, spots: Cell[], speedMul: number) {
    const target = spots.find((s) => !this.workers.some((o) => o !== w && sameCell(o.cell, s))) ?? spots[0];
    if (!sameCell(w.cell, target) && !w.path.length) this.setPath(w, [target]);
    this.move(w, dt, speedMul);
    const m = this.maidOf(w);
    if (!m) return;
    m.fatigue = clamp(m.fatigue - 0.04 * dt);
    // autonomous life: idle chats with nearby colleagues
    w.idleChatT -= dt;
    if (w.idleChatT <= 0) {
      w.idleChatT = 9 + this.rng.next() * 6;
      const buddy = this.workers.find((o) => o !== w && o.maidId && !o.job && !o.resting && manhattan(o.cell, w.cell) <= 4);
      const def = MAID_BY_ID[m.id];
      if (buddy?.maidId) {
        const bm = this.maid(buddy.maidId)!;
        const rel = m.relationships[bm.id] ?? 40;
        const lines = rel >= 60 ? [`${MAID_BY_ID[bm.id].name}，等等一起吃宵夜？`, '剛剛那位客人好可愛～', '今天配合得不錯呢！'] : ['……今天客人多嗎？', '那個，盤子放這邊就好。', '嗯……'];
        this.say(w, this.rng.pick(lines), 3);
        m.relationships[bm.id] = clamp(rel + 0.8);
        bm.relationships[m.id] = clamp((bm.relationships[m.id] ?? 40) + 0.8);
      } else if (this.rng.next() < 0.5) {
        this.say(w, this.rng.pick(def.lines.idle), 3);
      }
    }
  }

  private updatePerformer(w: Worker, m: MaidState, dt: number, speedMul: number) {
    if (this.state.activity !== 'stage' || !this.layout.stageCells.length) {
      m.role = 'floor';
      return;
    }
    const st = this.layout.stageCells[0];
    w.performing = false;
    if (!sameCell(w.cell, st)) {
      if (!w.path.length) this.setPath(w, [st], true);
      w.activity = '前往舞台';
      this.stageQuality = 0;
      this.move(w, dt, speedMul);
      return;
    }
    w.performing = true;
    w.activity = '舞台表演中 ♪';
    this.stageQuality = (m.skills.performance / 100) * (0.5 + m.mood / 200) * (m.fatigue > 70 ? 0.6 : 1);
    m.fatigue = clamp(m.fatigue + 0.12 * dt);
    this.maidStats[m.id].performSeconds += dt;
    if (Math.floor(this.t * 10) % 40 === 0) this.gainExp(m, 'performance', 1);
    if (m.fatigue >= 90) {
      this.stageQuality = 0;
      w.performing = false;
      this.startRest(w);
    }
  }

  private startRest(w: Worker) {
    this.release(w);
    w.resting = true;
    w.restSpot = null;
    this.say(w, '對不起……我先去休息一下。', 3);
    this.note(`😮‍💨 ${w.name}太累了，去休息室休息。`, 'warn');
  }

  private updateMoods(dt: number) {
    const present = this.parties.filter((p) => p.state !== 'arriving').length;
    for (const w of this.workers) {
      const m = this.maidOf(w);
      if (!m || m.role === 'off') continue;
      const def = MAID_BY_ID[m.id];
      if (def.traits.includes('cheerful')) {
        for (const o of this.workers) {
          if (o === w || !o.maidId || manhattan(o.cell, w.cell) > 4) continue;
          const om = this.maid(o.maidId)!;
          om.mood = clamp(om.mood + 0.03 * dt);
        }
      }
      if (def.traits.includes('lively')) m.mood = clamp(m.mood + (this.state.activity !== 'none' ? 0.05 : present < 2 ? -0.03 : 0) * dt);
      if (def.traits.includes('shy') && m.role === 'reception' && m.greetsDone < 30) m.mood = clamp(m.mood - 0.03 * dt);
      if (m.fatigue > 75) m.mood = clamp(m.mood - 0.03 * dt);
    }
  }

  // ------------------------------------------------------------ player commands
  /** Manager walks to a floor cell. */
  managerMove(c: Cell) {
    const mg = this.manager();
    if (mg.carrying) return false;
    this.release(mg);
    return this.setPath(mg, [c]);
  }

  /** Manager personally performs a job. Free, but limited by walking time. */
  managerDo(jobId: string): string | null {
    const mg = this.manager();
    const j = this.jobs.find((x) => x.id === jobId);
    if (!j || j.done || j.cancelled) return '這件事已經處理好了。';
    if (mg.carrying) return '店長正在送餐中。';
    if (!this.jobAvailable(j, mg)) return j.type === 'cook' ? '爐子或出餐台已滿。' : j.type === 'greet' ? '目前沒有空桌。' : '現在無法執行。';
    if (j.claimedBy && j.claimedBy !== mg.id) {
      const other = this.workers.find((w) => w.id === j.claimedBy);
      if (other) {
        if (other.carrying) return `${other.name}已經在處理了。`;
        if (other.steps[0]?.kind === 'work') return `${other.name}已經在處理了。`;
        this.release(other);
      }
    }
    this.release(mg);
    this.assign(mg, j);
    mg.manual = true;
    return null;
  }

  /** Manager goes over to chat with a seated customer. */
  managerChat(partyId: string): string | null {
    const mg = this.manager();
    const p = this.party(partyId);
    if (!p || !p.tableId || !['browsing', 'waitOrder', 'waitFood', 'eating'].includes(p.state)) return '現在不方便打擾。';
    if (p.members[0].causes.has('managerChat')) return '剛剛已經聊過了。';
    if (mg.carrying) return '店長正在送餐中。';
    this.release(mg);
    const fake: Job = { id: this.id('j'), type: 'order', partyId, created: this.t, claimedBy: mg.id, preferred: null, done: false, cancelled: false };
    mg.job = fake;
    mg.manual = true;
    mg.activity = '寒暄';
    mg.steps = [
      { kind: 'goto', goals: this.tableGoals(p.tableId), label: '前往寒暄' },
      {
        kind: 'work', dur: 2.5, label: '和客人聊天', done: (wk) => {
          const pp = this.party(partyId);
          fake.done = true;
          if (!pp) return;
          const main = pp.members[0];
          main.sat += 6;
          main.causes.add('managerChat');
          const line = main.defId ? this.chatLine(main.defId) : '這間店氣氛不錯呢。';
          this.say(main, line, 5);
          this.say(wk, '謝謝您常來！', 2.5);
        },
      },
    ];
    return null;
  }

  private chatLine(defId: string): string {
    const mem = this.state.customers[defId];
    if (defId === 'chizuru') return mem.storyStage >= 2 ? '那孩子做的布丁越來越像樣了。' : '布丁啊……火候和耐心最重要。';
    if (defId === 'amamiya') return mem.storyStage >= 2 ? '小說的舞台……其實就是這間店。' : '這裡很適合寫東西。只要安靜的話。';
    if (mem.isRegular) return '這裡已經是我的第二個家了。';
    return '店長親自來打招呼啊，真開心。';
  }

  spendCP(): boolean {
    if (this.commandPoints < 1) return false;
    this.commandPoints--;
    return true;
  }

  setRole(maidId: string, role: Role): string | null {
    const w = this.workers.find((x) => x.maidId === maidId);
    const m = this.maid(maidId);
    if (!w || !m) return '找不到女僕。';
    if (m.role === 'off') return '她今天休假。';
    if (role === 'stage' && (this.state.activity !== 'stage' || !this.layout.stageCells.length)) return '今天不是舞台表演日。';
    if (w.carrying) return '她正在送餐，等一下再說。';
    if (!this.spendCP()) return '指揮點數不足。';
    this.release(w);
    m.role = role;
    if (role !== 'stage') this.stageQuality = this.workers.some((o) => o.performing && o !== w) ? this.stageQuality : 0;
    this.say(w, '好的，交給我！', 2);
    return null;
  }

  sendRest(maidId: string): string | null {
    const w = this.workers.find((x) => x.maidId === maidId);
    if (!w || w.resting) return '她已經在休息了。';
    if (w.carrying) return '她正在送餐，等一下再說。';
    if (!this.spendCP()) return '指揮點數不足。';
    this.startRest(w);
    return null;
  }

  togglePause(maidId: string): string | null {
    const w = this.workers.find((x) => x.maidId === maidId);
    if (!w) return '找不到女僕。';
    if (w.carrying) return '她正在送餐，等一下再說。';
    if (!w.paused && !this.spendCP()) return '指揮點數不足。';
    w.paused = !w.paused;
    if (w.paused) this.release(w);
    return null;
  }

  assignJob(maidId: string, jobId: string): string | null {
    const w = this.workers.find((x) => x.maidId === maidId);
    const j = this.jobs.find((x) => x.id === jobId);
    if (!w || !j || j.done || j.cancelled) return '這件事已經處理好了。';
    const m = this.maid(maidId)!;
    if (m.role === 'off') return '她今天休假。';
    if (w.resting) return '她在休息中。';
    if (w.carrying) return '她正在送餐，等一下再說。';
    if (!this.jobAvailable(j, w)) return j.type === 'complaint' ? '她的管理能力不足以處理客訴（需 50）。' : '現在無法執行。';
    if (j.claimedBy === w.id) return '她已經在做這件事了。';
    if (j.claimedBy) {
      const other = this.workers.find((x) => x.id === j.claimedBy);
      if (other && (other.carrying || other.steps[0]?.kind === 'work')) return `${other.name}已經在處理了。`;
      if (other) this.release(other);
    }
    if (!this.spendCP()) return '指揮點數不足。';
    w.paused = false;
    this.release(w);
    this.assign(w, j);
    this.say(w, '收到！', 1.5);
    return null;
  }

  /** Jobs targeting a given party / table / slot / mess, for click-to-interact UI. */
  jobsForParty(partyId: string) {
    return this.jobs.filter((j) => j.partyId === partyId && !j.done && !j.cancelled && (j.type !== 'cook' || !j.claimedBy));
  }
  jobAtCell(c: Cell): Job | null {
    for (const j of this.jobs) {
      if (j.done || j.cancelled) continue;
      if (j.type === 'mess') {
        const m = this.messes.find((x) => x.id === j.messId);
        if (m && sameCell(m.cell, c)) return j;
      }
      if (j.type === 'clean') {
        const t = this.layout.tableById(j.tableId!);
        if (t && [t.cell, ...t.seats].some((x) => sameCell(x, c))) return j;
      }
      if (j.type === 'deliver') {
        const o = this.order(j.orderId);
        if (o && o.slot >= 0 && sameCell(PASS_SLOTS[o.slot], c)) return j;
      }
    }
    // stations → first queued cook job
    if (this.layout.stations.some((s) => sameCell(s.cell, c) || sameCell(s.stand, c))) {
      return this.jobs.find((j) => j.type === 'cook' && !j.claimedBy && !j.done && !j.cancelled) ?? null;
    }
    return null;
  }

  pendingCounts() {
    const c: Record<JobType, number> = { greet: 0, order: 0, cook: 0, deliver: 0, clean: 0, mess: 0, complaint: 0 };
    for (const j of this.jobs) if (!j.done && !j.cancelled) c[j.type]++;
    return c;
  }
}
