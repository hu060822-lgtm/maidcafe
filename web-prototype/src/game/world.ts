// Exploration (daytime), preparation helpers and cafe style evaluation.
import type { DishDef, GameState, StyleKey } from './types';
import { DISH_BY_ID, FURNITURE, INGREDIENT_BY_ID, PARTNER_FEE, STYLE_NAMES } from './data/content';
import { CUSTOMER_BY_ID } from './data/customers';
import { MAID_BY_ID } from './data/maids';
import { activeMaids, addAlbum, clamp } from './state';

export interface Encounter {
  title: string;
  lines: string[];
}

// ---------------------------------------------------------------- style
export function styleScores(s: GameState): Record<StyleKey, number> {
  const sc: Record<StyleKey, number> = { warm: 2, elegant: 0, cute: 0, retro: 1, fantasy: 0 };
  for (const f of s.furniture) {
    const st = FURNITURE[f.type].style;
    for (const k in st) sc[k as StyleKey] += st[k as StyleKey]!;
  }
  for (const id of s.menu) {
    const d = DISH_BY_ID[id];
    if (!d) continue;
    if (d.category === 'dessert') sc.cute += 0.7;
    if (id === 'd_coffee' || id === 'm_napolitan' || id === 'm_doria') sc.retro += 0.7;
    if (id === 'd_royaltea' || id === 's_shortcake') sc.elegant += 0.7;
    if (d.signature) sc.warm += 2;
  }
  const costumeDays = Number(s.flags.costumeDays ?? 0);
  const stageDays = Number(s.flags.stageDays ?? 0);
  sc.cute += Math.min(6, costumeDays * 1.5 + stageDays);
  if (s.activity === 'costume') sc.cute += 4;
  return sc;
}

export function dominantStyle(s: GameState): { key: StyleKey; name: string; strength: number } {
  const sc = styleScores(s);
  let best: StyleKey = 'warm';
  for (const k in sc) if (sc[k as StyleKey] > sc[best]) best = k as StyleKey;
  return { key: best, name: STYLE_NAMES[best], strength: sc[best] };
}

// ---------------------------------------------------------------- inventory
export function ingredientPrice(s: GameState, id: string) {
  const base = INGREDIENT_BY_ID[id].price;
  return s.partners.includes('sweets') && INGREDIENT_BY_ID[id].shop === 'sweets' ? Math.round(base * 0.8) : base;
}

export function buyIngredient(s: GameState, id: string, qty: number): boolean {
  const cost = ingredientPrice(s, id) * qty;
  if (s.money < cost) return false;
  s.money -= cost;
  s.todaySpend.ingredients += cost;
  s.inventory[id] = (s.inventory[id] ?? 0) + qty;
  return true;
}

export function servingsPossible(inv: Record<string, number>, dish: DishDef) {
  let n = Infinity;
  for (const k in dish.ingredients) n = Math.min(n, Math.floor((inv[k] ?? 0) / dish.ingredients[k]));
  return n;
}

// ---------------------------------------------------------------- exploration
export function visitLocation(s: GameState, loc: string, opt?: string): Encounter {
  s.actionPoints = Math.max(0, s.actionPoints - 1);
  const visits = Number(s.flags[`visit_${loc}`] ?? 0) + 1;
  s.flags[`visit_${loc}`] = visits;
  const enc: Encounter = { title: '', lines: [] };
  switch (loc) {
    case 'cafe': {
      const m = activeMaids(s).find((x) => x.id === opt) ?? activeMaids(s)[0];
      const def = MAID_BY_ID[m.id];
      m.mood = clamp(m.mood + 10);
      m.fatigue = clamp(m.fatigue - 5);
      m.flags.talks = Number(m.flags.talks ?? 0) + 1;
      enc.title = `和${def.name}聊天`;
      enc.lines.push(chatLine(s, m.id));
      enc.lines.push(`${def.name}的心情變好了。`);
      break;
    }
    case 'grocer':
      enc.title = '山田生鮮';
      enc.lines.push(visits === 1 ? '山田大叔：「喔！妳就是新來的店長啊。蛋跟牛奶都很新鮮喔！」' : '山田大叔：「今天的番茄特別紅！」');
      break;
    case 'general':
      enc.title = '月光雜貨';
      enc.lines.push(visits === 1 ? '月光雜貨的老闆娘一邊打毛線一邊說：「家具和擺飾也可以在這裡訂喔。」' : '店裡飄著淡淡的焙煎咖啡香。');
      break;
    case 'sweets':
      enc.title = '糖霜屋';
      if (!s.partners.includes('sweets')) {
        enc.lines.push('糖霜屋的老闆嘆了口氣：「最近客人越來越少，可能撐不到年底了……」');
        enc.lines.push(`「如果妳的店願意簽約長期進貨，我可以給妳八折，而且是最新鮮的鮮奶油。」（簽約費 ¥${PARTNER_FEE}）`);
      } else enc.lines.push('老闆笑著說：「託妳的福，最近生意好多了！」');
      break;
    case 'park': {
      enc.title = '向日葵公園';
      const mayu = s.customers.mayu;
      const chizuru = s.customers.chizuru;
      if (!mayu.known) {
        mayu.known = true;
        enc.lines.push('長椅上有位女生在畫素描。她叫小林真由，是插畫家。');
        enc.lines.push('真由：「女僕咖啡廳？聽起來好可愛……我改天去看看！」');
        enc.lines.push('🆕 認識了新顧客：小林真由');
      } else if (!chizuru.known && s.day >= 2) {
        chizuru.known = true;
        chizuru.storyStage = 1;
        enc.lines.push('一位老奶奶正在餵鴿子。她看著妳的圍裙笑了。');
        enc.lines.push('千鶴奶奶：「女僕咖啡廳啊……那間店的布丁，以前可是很有名的喔。現在還有在做嗎？」');
        enc.lines.push('🆕 認識了特殊顧客：千鶴奶奶（她似乎很在意布丁）');
      } else {
        enc.lines.push('陽光很舒服。散步的人們聊著商店街的近況。');
        s.popularity = clamp(s.popularity + 1);
        enc.lines.push('（店鋪人氣 +1）');
      }
      break;
    }
    case 'plaza': {
      enc.title = '商店街廣場';
      const endo = s.customers.endo;
      const gain = Math.max(1, 5 - Math.floor(Number(s.flags.flyersToday ?? 0)) * 2);
      s.flags.flyersToday = Number(s.flags.flyersToday ?? 0) + 1;
      s.popularity = clamp(s.popularity + gain);
      enc.lines.push(`在廣場發了傳單。（店鋪人氣 +${gain}）`);
      if (!endo.known) {
        endo.known = true;
        enc.lines.push('一位穿著應援外套的男生接過傳單：「女僕咖啡廳……有舞台表演嗎！？」');
        enc.lines.push('🆕 認識了新顧客：遠藤（似乎很喜歡舞台表演）');
      }
      break;
    }
  }
  return enc;
}

export function signPartnership(s: GameState): boolean {
  if (s.partners.includes('sweets') || s.money < PARTNER_FEE) return false;
  s.money -= PARTNER_FEE;
  s.todaySpend.promotion += PARTNER_FEE;
  s.partners.push('sweets');
  addAlbum(s, '與糖霜屋簽約', '快要倒閉的糖霜屋成了我們的甜點供應商。從今天起，甜點用的鮮奶油都是當天早上打發的。');
  return true;
}

export function buyPoster(s: GameState): boolean {
  if (s.money < 500 || s.flags.posterToday) return false;
  s.money -= 500;
  s.todaySpend.promotion += 500;
  s.flags.posterToday = true;
  s.popularity = clamp(s.popularity + 6);
  return true;
}

function chatLine(s: GameState, maidId: string): string {
  const m = s.maids.find((x) => x.id === maidId)!;
  const name = MAID_BY_ID[maidId].name;
  if (m.fatigue > 60) return `${name}：「老實說……最近有點累。可以讓我稍微休息一下嗎？」`;
  if (m.yesterday.includes('complaint')) return `${name}：「昨天的客訴……我會更注意的。」`;
  if (m.yesterday.includes('praised')) return `${name}：「昨天有客人說想再見到我！好開心～」`;
  const talks = Number(m.flags.talks ?? 0);
  const lines: Record<string, string[]> = {
    koharu: ['小春：「店長！我想到新的歡迎口號了，要聽嗎？」', '小春：「如果有舞台的話，我想試著唱歌看看！」', '小春：「雫最近比較敢說話了喔，要多誇誇她！」'],
    rin: ['凜：「……蛋包飯的火候，我又改良了一點。」', '凜：「廚房只有一台爐子，忙的時候根本來不及。」', '凜：「……謝謝妳每次都來聽我說。」'],
    shizuku: ['雫：「我……我想變得能好好跟客人說話。」', '雫：「擦桌子的時候，客人跟我說了謝謝……」', '雫：「小春前輩教我笑的方法……像這樣？」'],
  };
  return lines[maidId][talks % lines[maidId].length];
}

// ---------------------------------------------------------------- morning briefing (next-day reactions)
export function morningBriefing(s: GameState): string[] {
  const out: string[] = [];
  for (const m of activeMaids(s)) {
    const n = MAID_BY_ID[m.id].name;
    if (m.yesterday.includes('overworked')) out.push(`${n}看起來還很疲倦，動作比平常慢。`);
    if (m.yesterday.includes('complaint')) out.push(`${n}因為昨天的客訴有點沮喪。`);
    if (m.yesterday.includes('praised')) out.push(`${n}因為昨天被客人稱讚，今天特別有幹勁。`);
    if (m.yesterday.includes('dayoff')) out.push(`${n}休假回來，精神飽滿。`);
    if (m.lowMoodNights >= 2) out.push(`⚠ ${n}最近似乎在考慮要不要繼續做下去……`);
  }
  for (const id in s.customers) {
    const c = s.customers[id];
    if (!c.known || c.lastVisitDay !== s.day - 1) continue;
    const name = CUSTOMER_BY_ID[id].name;
    if (c.lastCauses.includes('complaintIgnored') || c.lastCauses.includes('walkedOut'))
      out.push(`聽說${name}在商店街抱怨昨天的服務……`);
    else if ((c.lastSatisfaction ?? 0) >= 75) out.push(`${name}昨天很開心，似乎會再來。`);
  }
  if (out.length === 0) out.push('平靜的早晨。');
  return out;
}
