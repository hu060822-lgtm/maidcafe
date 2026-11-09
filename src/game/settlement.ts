// After-hours: settlement, memory updates, character events, and the transition to the next day.
import type { DayReport, GameState, VisitCause } from './types';
import { BusinessSim, VisitResult } from './business';
import { ACTIVITIES, DAY_ACTION_POINTS, DISH_BY_ID, MAINTENANCE, UTILITIES, WAGE_PER_SHIFT } from './data/content';
import { CUSTOMER_BY_ID, REGULAR_LOYALTY, REGULAR_VISITS } from './data/customers';
import { MAID_BY_ID } from './data/maids';
import { activeMaids, addAlbum, clamp } from './state';
import { servingsPossible } from './world';

const CAUSE_TEXT: Partial<Record<VisitCause, string>> = {
  longWaitDoor: '在門口等了好久',
  longWaitOrder: '一直沒人來點餐',
  longWaitFood: '餐點等太久',
  greatFood: '餐點非常好吃',
  badFood: '餐點不太好吃',
  favDish: '吃到了喜歡的料理',
  favMaid: '見到了喜歡的女僕',
  favMaidAbsent: '喜歡的女僕不在',
  noisy: '太吵了',
  enjoyedShow: '舞台表演很精彩',
  spill: '有餐點被打翻',
  complaintHandled: '客訴被好好處理了',
  complaintIgnored: '客訴沒人理',
  outOfStock: '想吃的賣完了',
  styleMatch: '很喜歡店裡的風格',
  managerChat: '和店長聊得很開心',
  favSeat: '坐到了老位子',
  walkedOut: '受不了就走了',
};

function reviewText(r: VisitResult): string {
  const good = r.causes.filter((c) => ['greatFood', 'favDish', 'favMaid', 'enjoyedShow', 'complaintHandled', 'styleMatch', 'managerChat', 'favSeat'].includes(c));
  const bad = r.causes.filter((c) => !good.includes(c));
  const parts: string[] = [];
  if (good.length) parts.push(good.map((c) => CAUSE_TEXT[c]).join('、'));
  if (bad.length) parts.push(`可惜${bad.map((c) => CAUSE_TEXT[c]).join('、')}`);
  const head = r.sat >= 75 ? '★★★★★' : r.sat >= 60 ? '★★★★☆' : r.sat >= 45 ? '★★★☆☆' : r.sat >= 30 ? '★★☆☆☆' : '★☆☆☆☆';
  return `${head} ${parts.join('，') || '普通的一餐。'}`;
}

export function settleDay(s: GameState, sim: BusinessSim): DayReport {
  const working = activeMaids(s).filter((m) => m.role !== 'off');
  const wages = working.length * WAGE_PER_SHIFT;
  s.money -= wages + MAINTENANCE + UTILITIES;
  const results = sim.results;
  const named = results.filter((r) => r.defId);
  const avgSat = results.length ? results.reduce((a, r) => a + r.sat, 0) / results.length : 0;
  const reviews: DayReport['reviews'] = [];
  const advice: string[] = [];
  const maidNotes: DayReport['maidNotes'] = [];
  const newFans: { maid: string; cust: string }[] = [];

  // ---------------- customers & memory
  for (const r of named) {
    const def = CUSTOMER_BY_ID[r.defId!];
    const mem = s.customers[def.id];
    const firstVisit = mem.visits === 0;
    mem.visits++;
    mem.lastVisitDay = s.day;
    mem.lastSatisfaction = Math.round(r.sat);
    mem.lastCauses = r.causes;
    let dl = (r.sat - 50) * 0.4 + 3;
    if (r.causes.includes('walkedOut') || r.causes.includes('complaintIgnored')) dl -= 10;
    if (r.causes.includes('complaintHandled')) dl += 2;
    mem.loyalty = clamp(mem.loyalty + dl);
    for (const mid in r.affinityGain) mem.maidAffinity[mid] = (mem.maidAffinity[mid] ?? 0) + r.affinityGain[mid];
    let fav: string | null = null;
    let favV = 12;
    for (const mid in mem.maidAffinity) if (mem.maidAffinity[mid] > favV) {
      favV = mem.maidAffinity[mid];
      fav = mid;
    }
    if (fav && fav !== mem.favoriteMaid) {
      mem.favoriteMaid = fav;
      mem.log.push({ day: s.day, text: `開始指名${MAID_BY_ID[fav].name}` });
      newFans.push({ maid: fav, cust: def.id });
    }
    if (r.sat >= 70 && r.tableId) mem.favoriteSeat = r.tableId;
    if ((r.causes.includes('greatFood') || r.causes.includes('favDish')) && r.items.length) mem.favoriteDish = r.items.find((i) => def.likes.includes(i)) ?? r.items[0];
    if (firstVisit) mem.log.push({ day: s.day, text: `第一次來店（滿意度 ${Math.round(r.sat)}）` });
    if (r.causes.includes('complaintIgnored')) mem.log.push({ day: s.day, text: '客訴沒有被處理，生氣地離開' });
    if (r.causes.includes('walkedOut')) mem.log.push({ day: s.day, text: '等太久而離開' });
    if (!mem.isRegular && mem.visits >= REGULAR_VISITS && mem.loyalty >= REGULAR_LOYALTY) {
      mem.isRegular = true;
      mem.log.push({ day: s.day, text: '成為熟客' });
      addAlbum(s, `${def.name}成為熟客`, `第 ${mem.visits} 次來店時，${def.name}說：「這裡已經是我的老地方了。」`);
    }
    reviews.push({ customer: def.name, sat: Math.round(r.sat), text: reviewText(r) });
    // ---------- storylines
    if (def.story === 'pudding') storyPudding(s, r);
    if (def.story === 'novel') storyNovel(s, r);
  }
  for (const r of results) {
    if (r.friendOf) {
      const mem = s.customers[r.friendOf];
      if (!mem.broughtFriend) {
        mem.broughtFriend = true;
        mem.log.push({ day: s.day, text: '第一次帶朋友來' });
        const def = CUSTOMER_BY_ID[r.friendOf];
        addAlbum(s, `${def.name}帶朋友來了`, `${def.name}帶著朋友推開店門：「就是這裡，我跟你說過的那間店！」`);
      }
    }
  }
  const anon = results.filter((r) => !r.defId && !r.friendOf);
  if (anon.length) {
    const a = anon.reduce((x, r) => x + r.sat, 0) / anon.length;
    reviews.push({ customer: `其他客人（${anon.length} 位）`, sat: Math.round(a), text: a >= 60 ? '網路上出現了幾則好評。' : '網路評價普普通通。' });
  }

  // ---------------- popularity
  const served = results.filter((r) => r.paid > 0).length;
  let pop = (avgSat - 55) / 6 + served / 6 - sim.lost * 0.8;
  if (s.activity !== 'none') pop += 1;
  const stagePerf = Object.values(sim.maidStats).reduce((a, m) => a + m.performSeconds, 0);
  if (s.activity === 'stage' && stagePerf > 60) pop += 3;
  pop = Math.round(pop);
  s.popularity = clamp(s.popularity + pop);

  // ---------------- maids
  const workingIds = working.map((m) => m.id);
  for (const m of activeMaids(s)) {
    const def = MAID_BY_ID[m.id];
    const st = sim.maidStats[m.id];
    m.yesterday = [];
    if (m.role === 'off') {
      m.fatigue = clamp(m.fatigue - 50);
      m.mood = clamp(m.mood + 10);
      m.yesterday.push('dayoff');
    } else {
      if (m.fatigue >= 75) {
        m.yesterday.push('overworked');
        m.mood = clamp(m.mood - 5);
      }
      if (st && st.happyServed >= 2) m.yesterday.push('praised');
      if (st && st.spills >= 1) m.yesterday.push('spill');
      if (st && st.complaintsCaused >= 1) m.yesterday.push('complaint');
      m.fatigue = clamp(m.fatigue - (s.upgrades.sofa ? 40 : 30));
      for (const o of workingIds) if (o !== m.id) m.relationships[o] = clamp((m.relationships[o] ?? 40) + 2);
    }
    m.mood = clamp(m.mood + (60 - m.mood) * 0.15);
    if (m.mood < 25) m.lowMoodNights++;
    else m.lowMoodNights = 0;
    if (m.lowMoodNights >= 3) {
      m.quit = true;
      addAlbum(s, `${def.name}離開了`, `${def.name}留下一封信：「對不起，我已經撐不下去了。」也許我太在意營業額了。`);
      maidNotes.push({ id: m.id, text: `${def.name}辭職了……` });
      continue;
    }
    if (m.lowMoodNights === 2) maidNotes.push({ id: m.id, text: `⚠ ${def.name}的心情連續兩天很差，再這樣下去她可能會辭職。` });
    if (st) {
      const bits: string[] = [];
      if (st.greets) bits.push(`帶位 ${st.greets}`);
      if (st.cooks) bits.push(`製作 ${st.cooks}`);
      if (st.delivers) bits.push(`送餐 ${st.delivers}`);
      if (st.spills) bits.push(`失誤 ${st.spills}`);
      if (st.performSeconds > 0) bits.push(`表演 ${Math.round(st.performSeconds)} 秒`);
      if (m.role !== 'off') maidNotes.push({ id: m.id, text: `${def.name}：${bits.join('、') || '今天沒什麼工作'}。心情 ${Math.round(m.mood)}／疲勞 ${Math.round(m.fatigue)}` });
    }
    // ---------- personal events
    if (m.id === 'koharu' && newFans.some((f) => f.maid === 'koharu') && !m.flags.fanEvent) queue(s, 'koharu_fan');
    if (m.id === 'rin' && m.yesterday.includes('overworked') && !m.flags.overworkEvent) queue(s, 'rin_overwork');
    if (m.id === 'shizuku' && st && st.soloOrders > 0 && !m.flags.soloEvent) queue(s, 'shizuku_solo');
    if (m.id === 'shizuku' && st && st.performSeconds > 40 && !m.flags.stageEvent) queue(s, 'shizuku_stage');
    if (m.id === 'shizuku' && st && st.spills > 0 && !m.flags.spillEvent && !s.pendingEvents.includes('shizuku_solo')) queue(s, 'shizuku_spill');
  }
  // staff relationship events
  const ko = s.maids.find((m) => m.id === 'koharu');
  if (ko && !ko.quit && (ko.relationships.rin ?? 0) >= 50 && !s.flags.rinTeaches && s.day >= 3) queue(s, 'rin_teaches');
  if (s.day === 5 && !s.flags.birthday && !s.maids.find((m) => m.id === 'shizuku')?.quit) queue(s, 'shizuku_birthday');

  // ---------------- advice (staff suggestions)
  if (sim.congestion > 25) advice.push(`雫：「走道有點擠……大家常常互相卡住。」（今天塞住 ${Math.round(sim.congestion)} 秒，試著讓走道寬一點）`);
  if (sim.lost >= 2) advice.push(`小春：「有 ${sim.lost} 位客人沒吃到東西就走了……要不要多擺幾張桌子，或多一個人負責接待？」`);
  if (sim.complaints > sim.complaintsHandled) advice.push('凜：「客訴要快點處理。店長或管理能力高的人才能安撫客人。」');
  const low = s.menu.filter((id) => servingsPossible(s.inventory, DISH_BY_ID[id]) < 2).map((id) => DISH_BY_ID[id].name);
  if (low.length) advice.push(`凜：「${low.slice(0, 4).join('、')}的材料快用完了，明天記得去採購。」`);
  if (!s.furniture.some((f) => f.type === 'plant' || f.type === 'vase')) advice.push('雫：「店裡……好像少了點綠色。」');
  if (!s.upgrades.secondStove && Object.values(sim.maidStats).reduce((a, m) => a + m.cooks, 0) >= 8) advice.push('凜：「一台爐子根本不夠用。第二台爐具可以讓出餐快很多。」');
  if (working.some((m) => m.fatigue >= 60)) advice.push('疲勞高的女僕明天容易失誤，考慮讓她休假吧。');
  if (advice.length === 0) advice.push('今天運作得很順利！');

  // ---------------- activity counters
  if (s.activity === 'costume') s.flags.costumeDays = Number(s.flags.costumeDays ?? 0) + 1;
  if (s.activity === 'stage') s.flags.stageDays = Number(s.flags.stageDays ?? 0) + 1;
  if (s.activity === 'stage' && stagePerf > 60) addAlbum(s, '第一次舞台表演', `小小的舞台上響起了歌聲，客人們跟著打拍子。那天的人氣上升了 ${pop}。`);
  if (sim.revenue >= 15000) addAlbum(s, '大豐收的一天', `第 ${s.day} 天的營業額突破 ¥15,000！大家累得說不出話，卻都在笑。`);

  const exp = {
    ingredients: s.todaySpend.ingredients,
    wages,
    maintenance: MAINTENANCE,
    utilities: UTILITIES,
    activity: s.todaySpend.activity,
    promotion: s.todaySpend.promotion,
    furniture: s.todaySpend.furniture,
  };
  const totalExp = Object.values(exp).reduce((a, b) => a + b, 0);
  const report: DayReport = {
    day: s.day,
    revenue: sim.revenue,
    expenses: exp,
    served,
    lost: sim.lost,
    complaints: sim.complaints,
    complaintsHandled: sim.complaintsHandled,
    spills: sim.spills,
    avgSatisfaction: Math.round(avgSat),
    congestion: Math.round(sim.congestion),
    popularityDelta: pop,
    reviews,
    advice,
    maidNotes,
  };
  s.lastReport = report;
  s.history.push({ day: s.day, revenue: sim.revenue, net: sim.revenue - totalExp, sat: Math.round(avgSat), popularity: s.popularity });
  s.phase = 'night';
  return report;
}

function queue(s: GameState, id: string) {
  if (!s.pendingEvents.includes(id)) s.pendingEvents.push(id);
}

function storyPudding(s: GameState, r: VisitResult) {
  const mem = s.customers.chizuru;
  const hadPudding = r.items.includes('s_pudding');
  const hadSig = r.items.includes('sig_pudding');
  if (mem.storyStage === 1 && hadPudding) {
    if ((r.quality ?? 0) >= 58) {
      mem.storyStage = 2;
      queue(s, 'chizuru_recipe');
    } else {
      mem.log.push({ day: s.day, text: '覺得布丁「火候還差一點」' });
    }
  } else if (mem.storyStage === 1 && !hadPudding) {
    mem.log.push({ day: s.day, text: '沒吃到布丁，有點失望' });
  }
  if (mem.storyStage === 3 && hadSig && r.sat >= 65) {
    mem.storyStage = 4;
    queue(s, 'chizuru_proud');
  }
}

function storyNovel(s: GameState, r: VisitResult) {
  const mem = s.customers.amamiya;
  if (r.causes.includes('noisy')) {
    mem.storyStage = Math.max(0, mem.storyStage - 1);
    mem.log.push({ day: s.day, text: '舞台太吵，沒辦法寫稿' });
    return;
  }
  if (r.sat >= 62) {
    mem.storyStage++;
    if (mem.storyStage === 2) queue(s, 'amamiya_secret');
    if (mem.storyStage === 4) queue(s, 'amamiya_book');
  }
}

// ---------------------------------------------------------------- events
export interface EventChoice {
  label: string;
  apply: (s: GameState) => string;
}
export interface NightEvent {
  id: string;
  title: string;
  who: string;
  lines: (s: GameState) => string[];
  choices: EventChoice[];
}

const maid = (s: GameState, id: string) => s.maids.find((m) => m.id === id)!;

export const EVENTS: Record<string, NightEvent> = {
  koharu_fan: {
    id: 'koharu_fan', title: '小春的第一位指名客人', who: 'koharu',
    lines: (s) => {
      const c = Object.values(s.customers).find((m) => m.favoriteMaid === 'koharu');
      const n = c ? CUSTOMER_BY_ID[c.id].name : '客人';
      return [`打烊後，小春抱著托盤在店裡轉圈圈。`, `小春：「店長店長！${n}說下次還要我幫他點餐！這是不是叫做『指名』！？」`];
    },
    choices: [
      { label: '「很厲害喔，這是妳努力的成果。」', apply: (s) => { const m = maid(s, 'koharu'); m.flags.fanEvent = true; m.mood = clamp(m.mood + 12); addAlbum(s, '小春的第一位指名', '小春第一次被客人指名。她說要把那天的日期寫在手帳上。'); return '小春的心情大幅提升。'; } },
      { label: '「別得意忘形，明天也要好好做。」', apply: (s) => { const m = maid(s, 'koharu'); m.flags.fanEvent = true; m.mood = clamp(m.mood + 3); m.skills.reception = Math.min(95, m.skills.reception + 2); return '小春鼓起臉頰，但默默練習了招呼。（接待 +2）'; } },
    ],
  },
  rin_overwork: {
    id: 'rin_overwork', title: '廚房裡的凜', who: 'rin',
    lines: () => ['大家都下班了，廚房的燈還亮著。凜一個人在練習醬汁，手在發抖。', '凜：「……一台爐子要應付全部的單，我不能慢下來。」'],
    choices: [
      { label: '讓她明天休假', apply: (s) => { const m = maid(s, 'rin'); m.flags.overworkEvent = true; m.dayOffTomorrow = true; m.mood = clamp(m.mood + 8); m.relationships.koharu = clamp((m.relationships.koharu ?? 40) + 3); return '凜愣了一下：「……謝謝。」明天她會休假。'; } },
      { label: '陪她一起練習', apply: (s) => { const m = maid(s, 'rin'); m.flags.overworkEvent = true; m.skills.cooking = Math.min(100, m.skills.cooking + 3); m.fatigue = clamp(m.fatigue + 10); return '兩人一直練到深夜。（凜 料理 +3，但更累了）'; } },
    ],
  },
  shizuku_solo: {
    id: 'shizuku_solo', title: '雫的第一次', who: 'shizuku',
    lines: () => ['雫：「店、店長……今天，我一個人從帶位、點餐到送餐，全部做完了……！」', '她的聲音很小，但眼睛閃閃發亮。'],
    choices: [
      { label: '摸摸頭稱讚她', apply: (s) => { const m = maid(s, 'shizuku'); m.flags.soloEvent = true; m.mood = clamp(m.mood + 12); m.greetsDone += 8; addAlbum(s, '雫第一次獨立完成訂單', '從帶位到送餐，雫一個人完成了。她說那位客人笑著跟她說了謝謝。'); return '雫的怕生程度降低了。（接待成長更快）'; } },
    ],
  },
  shizuku_spill: {
    id: 'shizuku_spill', title: '打翻的杯子', who: 'shizuku',
    lines: () => ['休息室裡，雫抱著膝蓋坐在角落。', '雫：「我果然……不適合這份工作吧……」'],
    choices: [
      { label: '「失誤沒關係，下次小心就好。」', apply: (s) => { const m = maid(s, 'shizuku'); m.flags.spillEvent = true; m.mood = clamp(m.mood + 10); return '雫點點頭，擦掉眼淚。'; } },
      { label: '請小春陪陪她', apply: (s) => { const m = maid(s, 'shizuku'); m.flags.spillEvent = true; m.mood = clamp(m.mood + 6); m.relationships.koharu = clamp((m.relationships.koharu ?? 40) + 10); maid(s, 'koharu').relationships.shizuku = clamp((maid(s, 'koharu').relationships.shizuku ?? 40) + 10); return '小春拉著雫去吃了宵夜。兩人的關係變好了。'; } },
    ],
  },
  shizuku_stage: {
    id: 'shizuku_stage', title: '舞台上的雫', who: 'shizuku',
    lines: () => ['表演結束後，雫的手還在發抖。', '雫：「好可怕……可是，大家在拍手……我好像，還想再站上去一次。」'],
    choices: [
      { label: '「下次也交給妳了。」', apply: (s) => { const m = maid(s, 'shizuku'); m.flags.stageEvent = true; m.skills.performance = Math.min(90, m.skills.performance + 6); m.mood = clamp(m.mood + 8); addAlbum(s, '雫站上了舞台', '那個連「歡迎光臨」都說不好的雫，在舞台上唱完了一整首歌。'); return '雫的表演能力大幅提升。（表演 +6）'; } },
    ],
  },
  rin_teaches: {
    id: 'rin_teaches', title: '凜的料理教室', who: 'rin',
    lines: () => ['打烊後，凜叫住了正要回家的小春。', '凜：「……妳的蛋包飯，蛋皮太厚了。過來，我教妳。」', '小春：「欸！？凜要教我！？」'],
    choices: [
      { label: '在旁邊默默看著', apply: (s) => { s.flags.rinTeaches = true; const k = maid(s, 'koharu'); k.skills.cooking = Math.min(60, k.skills.cooking + 5); k.relationships.rin = clamp(k.relationships.rin + 8); maid(s, 'rin').relationships.koharu = clamp((maid(s, 'rin').relationships.koharu ?? 40) + 8); return '小春的料理 +5，兩人的關係變好了。'; } },
    ],
  },
  shizuku_birthday: {
    id: 'shizuku_birthday', title: '雫的生日', who: 'shizuku',
    lines: (s) => {
      const avg = (maid(s, 'koharu').relationships.shizuku + (maid(s, 'rin').relationships.shizuku ?? 40)) / 2;
      return avg >= 50
        ? ['打烊後，燈突然暗了下來。', '小春端著插著蠟燭的蛋糕出來，凜在後面別過頭：「……蛋糕是我烤的。」', '雫：「欸……？大家……怎麼知道……」']
        : ['今天是雫的生日，但似乎沒有人知道。', '雫一個人默默地收拾好店面，說了聲「辛苦了」就回家了。'];
    },
    choices: [
      { label: '（繼續）', apply: (s) => { s.flags.birthday = true; const m = maid(s, 'shizuku'); const avg = (maid(s, 'koharu').relationships.shizuku + (maid(s, 'rin').relationships.shizuku ?? 40)) / 2; if (avg >= 50) { m.mood = clamp(m.mood + 20); addAlbum(s, '雫的生日派對', '店裡第一次為員工慶生。雫哭著吃完了整塊蛋糕。'); return '雫度過了最棒的生日。'; } m.mood = clamp(m.mood - 5); return '也許應該多關心員工之間的關係……'; } },
    ],
  },
  chizuru_recipe: {
    id: 'chizuru_recipe', title: '千鶴奶奶的秘方', who: 'chizuru',
    lines: () => ['千鶴奶奶在結帳時遞來一張泛黃的紙條。', '千鶴：「布丁的味道很誠實。妳們的布丁……讓我想起以前的這間店。」', '「這是我年輕時的配方。焦糖要煮到快要苦的那一刻，再加一匙鮮奶油。」'],
    choices: [
      { label: '交給凜研究', apply: (s) => { s.customers.chizuru.storyStage = 3; if (!s.unlockedDishes.includes('sig_pudding')) s.unlockedDishes.push('sig_pudding'); const r = maid(s, 'rin'); if (!r.quit) r.skills.cooking = Math.min(100, r.skills.cooking + 3); addAlbum(s, '千鶴的秘方', '千鶴奶奶把年輕時的布丁配方交給了我們。'); return '解鎖招牌料理「千鶴的焦糖布丁」！把它放進菜單，讓千鶴奶奶嚐嚐吧。'; } },
      { label: '大家一起學', apply: (s) => { s.customers.chizuru.storyStage = 3; if (!s.unlockedDishes.includes('sig_pudding')) s.unlockedDishes.push('sig_pudding'); for (const m of activeMaids(s)) m.skills.cooking = Math.min(MAID_BY_ID[m.id].caps.cooking, m.skills.cooking + 1); addAlbum(s, '千鶴的秘方', '千鶴奶奶把年輕時的布丁配方交給了我們，大家一起練習到深夜。'); return '解鎖招牌料理「千鶴的焦糖布丁」！全員料理 +1。'; } },
    ],
  },
  chizuru_proud: {
    id: 'chizuru_proud', title: '招牌料理誕生', who: 'chizuru',
    lines: () => ['千鶴奶奶吃完最後一口布丁，安靜了很久。', '千鶴：「……就是這個味道。以後，這就是妳們店的布丁了。」'],
    choices: [
      { label: '「我們會好好守護它。」', apply: (s) => { s.popularity = clamp(s.popularity + 8); addAlbum(s, '招牌料理誕生', '「千鶴的焦糖布丁」正式成為 Maiden Parade 的招牌。喜歡甜點的客人開始專程前來。'); return '人氣 +8。喜歡甜點的客人更容易上門。'; } },
    ],
  },
  amamiya_secret: {
    id: 'amamiya_secret', title: '角落座位的男人', who: 'amamiya',
    lines: () => ['雨宮先生收拾稿紙時，有一張掉在地上。上面寫著「女僕咖啡廳」與「店長」。', '雨宮：「啊……被看到了。其實，我在寫一部以這間店為舞台的小說。」', '「這裡很安靜，又有人情味。請不要改變太多。」'],
    choices: [
      { label: '「請一定要讓我們讀。」', apply: (s) => { s.customers.amamiya.loyalty = clamp(s.customers.amamiya.loyalty + 10); return '雨宮先生害羞地點了點頭。（記得：他討厭吵鬧）'; } },
      { label: '幫他保留角落的座位', apply: (s) => { const c = s.customers.amamiya; c.loyalty = clamp(c.loyalty + 6); c.favoriteSeat = c.favoriteSeat ?? 'f3'; return '從此角落那張桌子成了雨宮先生的老位子。'; } },
    ],
  },
  amamiya_book: {
    id: 'amamiya_book', title: '一本書', who: 'amamiya',
    lines: () => ['雨宮先生把一本新書放在櫃台上。書名是《Maiden Parade 的晚上》。', '雨宮：「出版了。書裡的店長……是以妳為原型。」'],
    choices: [
      { label: '把書放在店裡的書架上', apply: (s) => { s.popularity = clamp(s.popularity + 12); addAlbum(s, '《Maiden Parade 的晚上》', '雨宮先生的小說出版了。讀者們開始來店裡「聖地巡禮」。'); return '人氣 +12！'; } },
    ],
  },
};

export function nextEvent(s: GameState): NightEvent | null {
  while (s.pendingEvents.length) {
    const id = s.pendingEvents[0];
    const ev = EVENTS[id];
    if (ev && !(MAID_BY_ID[ev.who] && maid(s, ev.who).quit)) return ev;
    s.pendingEvents.shift();
  }
  return null;
}

export function resolveEvent(s: GameState, ev: NightEvent, choice: number): string {
  s.pendingEvents = s.pendingEvents.filter((x) => x !== ev.id);
  return ev.choices[choice].apply(s);
}

/** Start of a new day. */
export function startNextDay(s: GameState) {
  s.day++;
  s.phase = 'explore';
  s.actionPoints = DAY_ACTION_POINTS;
  s.activity = 'none';
  s.featuredDish = null;
  s.todaySpend = { ingredients: 0, activity: 0, promotion: 0, furniture: 0 };
  s.flags.flyersToday = 0;
  s.flags.posterToday = false;
  for (const m of activeMaids(s)) {
    if (m.dayOffTomorrow) {
      m.role = 'off';
      m.dayOffTomorrow = false;
    } else if (m.role === 'off' || m.role === 'stage') m.role = MAID_BY_ID[m.id].defaultRole;
  }
}

/** Validate & begin business. Returns an error string or null. */
export function beginBusiness(s: GameState): string | null {
  const menu = s.menu.filter((id) => s.unlockedDishes.includes(id));
  if (!menu.length) return '菜單上至少要有一道料理。';
  if (!activeMaids(s).some((m) => m.role !== 'off')) return '至少要有一位女僕上班。';
  if (s.activity === 'stage' && !s.furniture.some((f) => f.type === 'stage')) return '舞台表演日需要先擺放小舞台。';
  if (s.activity === 'stage' && !activeMaids(s).some((m) => m.role === 'stage')) return '舞台表演日請指派一位女僕擔任「舞台」。';
  if (s.activity === 'limited' && !s.featuredDish) return '請選擇今天的限定料理。';
  if (s.activity !== 'stage') for (const m of s.maids) if (m.role === 'stage') m.role = MAID_BY_ID[m.id].defaultRole;
  const cost = ACTIVITIES[s.activity].cost;
  if (s.money < cost) return '資金不足以舉辦這個活動。';
  s.money -= cost;
  s.todaySpend.activity += cost;
  if (s.activity === 'costume') for (const m of activeMaids(s)) {
    const t = MAID_BY_ID[m.id].traits;
    m.mood = clamp(m.mood + (t.includes('lively') ? 15 : t.includes('shy') ? -3 : 6));
  }
  s.phase = 'business';
  return null;
}
