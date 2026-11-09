// Core shared types for Maiden Parade.
// Everything in GameState must stay JSON-serialisable (it is saved to localStorage).

export type Phase = 'explore' | 'prep' | 'business' | 'night';
export type SkillKey = 'reception' | 'cooking' | 'floor' | 'performance' | 'management';
export type Role = 'reception' | 'kitchen' | 'floor' | 'stage' | 'off';
export type TraitKey = 'cheerful' | 'careful' | 'slowWarm' | 'perfectionist' | 'shy' | 'lively';
export type StyleKey = 'warm' | 'elegant' | 'cute' | 'retro' | 'fantasy';
export type DishCategory = 'drink' | 'dessert' | 'main';
export type ActivityId = 'none' | 'costume' | 'limited' | 'stage';
export type GrowthType = 'specialist' | 'idol' | 'allround';

export type Skills = Record<SkillKey, number>;

export interface Cell {
  x: number;
  z: number;
}

export interface MaidDef {
  id: string;
  name: string;
  hair: number;
  eye: number;
  intro: string;
  traits: TraitKey[];
  growth: GrowthType;
  skills: Skills;
  caps: Skills;
  defaultRole: Role;
  /** Short lines used for in-scene speech bubbles. */
  lines: {
    greet: string[];
    idle: string[];
    tired: string[];
    happy: string[];
    sorry: string[];
  };
}

export interface MaidState {
  id: string;
  skills: Skills;
  exp: Skills;
  mood: number; // 0-100
  fatigue: number; // 0-100
  relationships: Record<string, number>; // other maid id -> 0-100
  role: Role;
  dayOffTomorrow: boolean;
  lowMoodNights: number;
  quit: boolean;
  greetsDone: number;
  ordersSolo: number;
  flags: Record<string, number | boolean | string>;
  /** Yesterday's notable experiences, used for next-day reactions. */
  yesterday: string[];
}

export interface CustomerDef {
  id: string;
  name: string;
  kind: 'normal' | 'regular' | 'special';
  desc: string;
  color: number;
  hair: number;
  budget: number;
  likes: string[];
  prefCategory: DishCategory;
  style: StyleKey | null;
  prefersQuiet: boolean;
  lively: boolean;
  picky: boolean;
  arrival: [number, number]; // business seconds window
  baseChance: number;
  patience: number; // seconds willing to wait at door
  /** Where the customer is first met. 'start' = known from day 1. */
  metAt: 'start' | string;
  minDay?: number;
  story?: string;
}

export type VisitCause =
  | 'longWaitDoor'
  | 'longWaitOrder'
  | 'longWaitFood'
  | 'greatFood'
  | 'badFood'
  | 'favDish'
  | 'favMaid'
  | 'favMaidAbsent'
  | 'noisy'
  | 'enjoyedShow'
  | 'spill'
  | 'complaintHandled'
  | 'complaintIgnored'
  | 'outOfStock'
  | 'styleMatch'
  | 'managerChat'
  | 'favSeat'
  | 'walkedOut';

export interface CustomerMemory {
  id: string;
  known: boolean;
  visits: number;
  loyalty: number; // 0-100
  maidAffinity: Record<string, number>;
  favoriteMaid: string | null;
  favoriteSeat: string | null; // table id
  favoriteDish: string | null;
  lastSatisfaction: number | null;
  lastVisitDay: number | null;
  lastCauses: VisitCause[];
  isRegular: boolean;
  broughtFriend: boolean;
  storyStage: number;
  log: { day: number; text: string }[];
}

export interface DishDef {
  id: string;
  name: string;
  category: DishCategory;
  price: number;
  time: number; // base cook seconds
  quality: number; // base quality
  ingredients: Record<string, number>;
  station: 'stove' | 'coffee';
  color: number;
  signature?: boolean;
}

export interface IngredientDef {
  id: string;
  name: string;
  price: number;
  shop: string;
}

export type FurnitureType =
  | 'table'
  | 'plant'
  | 'lamp'
  | 'gramophone'
  | 'plush'
  | 'vase'
  | 'crystal'
  | 'photo'
  | 'stage';

export interface FurnitureDef {
  type: FurnitureType;
  name: string;
  price: number;
  /** Footprint relative to anchor cell (anchor = 0,0). */
  footprint: Cell[];
  style: Partial<Record<StyleKey, number>>;
  desc: string;
}

export interface FurnitureItem {
  id: string;
  type: FurnitureType;
  x: number;
  z: number;
}

export interface CafeMemory {
  day: number;
  title: string;
  text: string;
}

export interface Upgrades {
  secondStove: boolean;
  coffeeMachine: boolean;
  sofa: boolean;
}

export interface DayReport {
  day: number;
  revenue: number;
  expenses: { ingredients: number; wages: number; maintenance: number; utilities: number; activity: number; promotion: number; furniture: number };
  served: number;
  lost: number;
  complaints: number;
  complaintsHandled: number;
  spills: number;
  avgSatisfaction: number;
  congestion: number;
  popularityDelta: number;
  reviews: { customer: string; sat: number; text: string }[];
  advice: string[];
  maidNotes: { id: string; text: string }[];
}

export interface GameState {
  version: number;
  seed: number;
  rngState: number;
  day: number;
  phase: Phase;
  money: number;
  popularity: number; // 0-100
  actionPoints: number; // exploration time slots left today
  inventory: Record<string, number>;
  unlockedDishes: string[];
  menu: string[]; // dishes on today's menu
  activity: ActivityId;
  featuredDish: string | null;
  maids: MaidState[];
  customers: Record<string, CustomerMemory>;
  furniture: FurnitureItem[];
  upgrades: Upgrades;
  partners: string[]; // supplier partnerships
  album: CafeMemory[];
  flags: Record<string, number | boolean | string>;
  /** Spend accumulators for the current day (reset after settlement). */
  todaySpend: { ingredients: number; activity: number; promotion: number; furniture: number };
  lastReport: DayReport | null;
  pendingEvents: string[];
  history: { day: number; revenue: number; net: number; sat: number; popularity: number }[];
  nextFurnitureId: number;
}
