import type { Cell, FurnitureItem, FurnitureType, Upgrades } from './types';
import { FURNITURE } from './data/content';

// Cafe grid. x: 0..W-1 (left→right), z: 0..H-1 (back wall → front door).
export const W = 18;
export const H = 12;

export const DOOR: Cell = { x: 9, z: 11 };
export const DOOR_IN: Cell = { x: 9, z: 10 };
export const GREET_SPOT: Cell = { x: 10, z: 10 };
export const RECEPTION_DESK: Cell = { x: 12, z: 10 };
export const STOVE1: Cell = { x: 1, z: 1 };
export const STOVE2: Cell = { x: 2, z: 1 };
export const COFFEE: Cell = { x: 4, z: 1 };
export const PASS_SLOTS: Cell[] = [
  { x: 1, z: 4 },
  { x: 2, z: 4 },
  { x: 3, z: 4 },
  { x: 4, z: 4 },
];
export const KITCHEN_WALL: Cell[] = [
  { x: 6, z: 1 },
  { x: 6, z: 2 },
  { x: 6, z: 3 },
];
export const STAFF_WALL: Cell[] = [
  { x: 12, z: 1 },
  { x: 12, z: 2 },
];
export const SOFA: Cell[] = [
  { x: 15, z: 1 },
  { x: 16, z: 1 },
];
export const REST_SPOTS: Cell[] = [
  { x: 14, z: 2 },
  { x: 15, z: 2 },
  { x: 16, z: 2 },
  { x: 13, z: 2 },
];
export const IDLE_SPOTS: Record<string, Cell[]> = {
  reception: [{ x: 11, z: 10 }, { x: 11, z: 9 }],
  kitchen: [{ x: 3, z: 2 }, { x: 5, z: 2 }],
  floor: [{ x: 5, z: 6 }, { x: 5, z: 7 }],
  stage: [{ x: 9, z: 3 }],
  off: [{ x: 14, z: 3 }],
};
/** Cells that must stay free so staff can work. */
const RESERVED: Cell[] = [
  DOOR_IN,
  GREET_SPOT,
  { x: 8, z: 10 },
  { x: 11, z: 10 },
  { x: 1, z: 5 },
  { x: 2, z: 5 },
  { x: 3, z: 5 },
  { x: 4, z: 5 },
  { x: 5, z: 5 },
  { x: 5, z: 4 },
  { x: 12, z: 3 },
  { x: 9, z: 9 },
];

export const key = (c: Cell) => `${c.x},${c.z}`;
export const sameCell = (a: Cell, b: Cell) => a.x === b.x && a.z === b.z;
export const manhattan = (a: Cell, b: Cell) => Math.abs(a.x - b.x) + Math.abs(a.z - b.z);
export const NEIGHBORS: Cell[] = [
  { x: 1, z: 0 },
  { x: -1, z: 0 },
  { x: 0, z: 1 },
  { x: 0, z: -1 },
];

export type CellKind = 'floor' | 'wall' | 'kitchen' | 'counter' | 'desk' | 'staffFloor' | 'sofa' | 'furniture' | 'seat' | 'door';

export interface TableInfo {
  id: string;
  cell: Cell;
  seats: Cell[];
}

export interface StationInfo {
  id: string;
  kind: 'stove' | 'coffee';
  cell: Cell;
  stand: Cell;
}

/** Derived, non-serialised view of the cafe grid. Rebuilt whenever furniture changes. */
export class Layout {
  kinds: CellKind[][] = [];
  furnitureAt = new Map<string, FurnitureItem>();
  tables: TableInfo[] = [];
  stations: StationInfo[] = [];
  stageCells: Cell[] = [];

  constructor(public furniture: FurnitureItem[], public upgrades: Upgrades) {
    this.rebuild();
  }

  rebuild() {
    this.kinds = [];
    for (let x = 0; x < W; x++) {
      this.kinds[x] = [];
      for (let z = 0; z < H; z++) {
        const edge = x === 0 || z === 0 || x === W - 1 || z === H - 1;
        this.kinds[x][z] = edge ? 'wall' : 'floor';
        if (x >= 13 && x <= 16 && z >= 1 && z <= 3) this.kinds[x][z] = 'staffFloor';
      }
    }
    this.kinds[DOOR.x][DOOR.z] = 'door';
    for (const c of [STOVE1, STOVE2, COFFEE, { x: 3, z: 1 }, { x: 5, z: 1 }]) this.kinds[c.x][c.z] = 'kitchen';
    for (const c of PASS_SLOTS) this.kinds[c.x][c.z] = 'counter';
    for (const c of [...KITCHEN_WALL, ...STAFF_WALL]) this.kinds[c.x][c.z] = 'wall';
    this.kinds[RECEPTION_DESK.x][RECEPTION_DESK.z] = 'desk';
    if (this.upgrades.sofa) for (const c of SOFA) this.kinds[c.x][c.z] = 'sofa';

    this.stations = [{ id: 'stove1', kind: 'stove', cell: STOVE1, stand: { x: 1, z: 2 } }];
    if (this.upgrades.secondStove) this.stations.push({ id: 'stove2', kind: 'stove', cell: STOVE2, stand: { x: 2, z: 2 } });
    this.stations.push({ id: 'coffee', kind: 'coffee', cell: COFFEE, stand: { x: 4, z: 2 } });

    this.furnitureAt.clear();
    this.tables = [];
    this.stageCells = [];
    for (const f of this.furniture) {
      const def = FURNITURE[f.type];
      for (const off of def.footprint) {
        const c = { x: f.x + off.x, z: f.z + off.z };
        this.furnitureAt.set(key(c), f);
        this.kinds[c.x][c.z] = 'furniture';
        if (f.type === 'stage') this.stageCells.push(c);
      }
      if (f.type === 'table') {
        const seats = [
          { x: f.x - 1, z: f.z },
          { x: f.x + 1, z: f.z },
        ];
        for (const s of seats) this.kinds[s.x][s.z] = 'seat';
        this.tables.push({ id: f.id, cell: { x: f.x, z: f.z }, seats });
      }
    }
  }

  inBounds(c: Cell) {
    return c.x >= 0 && c.z >= 0 && c.x < W && c.z < H;
  }

  walkable(c: Cell) {
    if (!this.inBounds(c)) return false;
    const k = this.kinds[c.x][c.z];
    return k === 'floor' || k === 'staffFloor' || k === 'door';
  }

  /** Walkable cells next to any of the given cells. */
  adjacentWalkable(cells: Cell[]): Cell[] {
    const out: Cell[] = [];
    const seen = new Set<string>();
    for (const c of cells) {
      for (const n of NEIGHBORS) {
        const nc = { x: c.x + n.x, z: c.z + n.z };
        const k = key(nc);
        if (!seen.has(k) && this.walkable(nc)) {
          seen.add(k);
          out.push(nc);
        }
      }
    }
    return out;
  }

  tableById(id: string) {
    return this.tables.find((t) => t.id === id);
  }

  /** Cells where furniture may be placed (dining area / back hall, never kitchen or staff room). */
  placeable(c: Cell) {
    if (!this.inBounds(c)) return false;
    if (this.kinds[c.x][c.z] !== 'floor') return false;
    if (RESERVED.some((r) => sameCell(r, c))) return false;
    if (c.x <= 6 && c.z <= 4) return false; // kitchen block
    return true;
  }

  /** Returns an error message, or null when the placement is valid. */
  canPlace(type: FurnitureType, x: number, z: number): string | null {
    const def = FURNITURE[type];
    const cells = def.footprint.map((o) => ({ x: x + o.x, z: z + o.z }));
    for (const c of cells) if (!this.placeable(c)) return '這裡不能擺放。';
    if (type === 'stage' && this.furniture.some((f) => f.type === 'stage')) return '店裡只放得下一座舞台。';
    const test = new Layout([...this.furniture, { id: '__test', type, x, z }], this.upgrades);
    if (!test.allReachable()) return '這樣會擋住走道，有地方走不到了。';
    return null;
  }

  /** Every important spot must be reachable from the entrance. */
  allReachable(): boolean {
    const reach = this.reachableFrom(DOOR_IN);
    const need: Cell[][] = [
      [GREET_SPOT],
      ...this.stations.map((s) => [s.stand]),
      ...PASS_SLOTS.map((p) => this.adjacentWalkable([p])),
      [REST_SPOTS[0]],
    ];
    for (const t of this.tables) {
      need.push(this.adjacentWalkable([t.cell, ...t.seats]));
      for (const s of t.seats) need.push(this.adjacentWalkable([s]));
    }
    for (const group of need) {
      if (group.length === 0) return false;
      if (!group.some((c) => reach.has(key(c)))) return false;
    }
    return true;
  }

  reachableFrom(start: Cell): Set<string> {
    const seen = new Set<string>([key(start)]);
    const q = [start];
    while (q.length) {
      const c = q.shift()!;
      for (const n of NEIGHBORS) {
        const nc = { x: c.x + n.x, z: c.z + n.z };
        const k = key(nc);
        if (!seen.has(k) && this.walkable(nc)) {
          seen.add(k);
          q.push(nc);
        }
      }
    }
    return seen;
  }
}

export function defaultFurniture(): FurnitureItem[] {
  return [
    { id: 'f1', type: 'table', x: 7, z: 6 },
    { id: 'f2', type: 'table', x: 11, z: 6 },
    { id: 'f3', type: 'table', x: 15, z: 6 },
    { id: 'f4', type: 'table', x: 7, z: 8 },
    { id: 'f5', type: 'table', x: 11, z: 8 },
    { id: 'f6', type: 'plant', x: 1, z: 10 },
    { id: 'f7', type: 'lamp', x: 16, z: 10 },
  ];
}
