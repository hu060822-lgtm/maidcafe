import type { FurnitureType, GameState, Role, SkillKey } from '../game/types';
import { BusinessSim, CLOSE_HOUR, DURATION, JOB_NAMES, Job, OPEN_HOUR } from '../game/business';
import { ACTIVITIES, DISH_BY_ID, FURNITURE, INGREDIENTS, LOCATIONS, MAX_MENU, PARTNER_FEE, STYLE_NAMES, UPGRADE_INFO } from '../game/data/content';
import { CUSTOMER_BY_ID, CUSTOMERS } from '../game/data/customers';
import { MAID_BY_ID, TRAIT_INFO } from '../game/data/maids';
import { Layout, key } from '../game/layout';
import { activeMaids, clamp, loadGame, newGame, saveGame } from '../game/state';
import { beginBusiness, nextEvent, resolveEvent, settleDay, startNextDay } from '../game/settlement';
import { buyIngredient, buyPoster, dominantStyle, ingredientPrice, morningBriefing, servingsPossible, signPartnership, styleScores, visitLocation, Encounter } from '../game/world';
import { Pick, World3D } from '../render/world3d';

const ROLE_NAMES: Record<Role, string> = { reception: '接待', kitchen: '廚房', floor: '外場', stage: '舞台', off: '休假' };
const SKILL_NAMES: Record<SkillKey, string> = { reception: '接待', cooking: '料理', floor: '外場', performance: '表演', management: '管理' };
const PHASE_NAMES = { explore: '☀ 白天・街區探索', prep: '🌤 下午・營業準備', business: '🌙 晚上・正式營業', night: '🌌 深夜・結算' };
const CAT_NAMES = { drink: '飲品', dessert: '甜點', main: '主餐' };
const PARTY_STATE: Record<string, string> = {
  arriving: '走向店門', queue: '在門口等待帶位', toSeat: '前往座位', browsing: '看菜單中', waitOrder: '等待點餐', waitFood: '等待上菜',
  eating: '用餐中', angry: '生氣中！', leaving: '離開中',
};

const $ = (id: string) => document.getElementById(id)!;
const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);
const yen = (n: number) => `¥${Math.round(n).toLocaleString()}`;
const bar = (v: number, cls = '') => `<span class="bar ${cls}"><i style="width:${clamp(v)}%"></i></span>`;

export class App {
  state: GameState;
  world: World3D;
  sim: BusinessSim | null = null;
  preview: BusinessSim;
  speed = 1;
  paused = false;
  showLabels = true;
  prepTab: 'menu' | 'staff' | 'activity' | 'decor' = 'menu';
  placing: FurnitureType | null = null;
  removing = false;
  encounter: { loc: string; enc: Encounter } | null = null;
  eventResult: string | null = null;
  briefing: string[] = [];
  private lastHtml: Record<string, string> = {};
  private down: { x: number; y: number } | null = null;
  private toastT = 0;

  constructor() {
    this.state = loadGame() ?? newGame();
    this.world = new World3D($('view'));
    this.preview = this.makePreview();
    this.world.rebuildFurniture(this.state);
    this.bindInput();
    this.titleScreen();
    this.renderAll();
    let last = performance.now();
    let uiT = 0;
    const loop = (now: number) => {
      const dt = Math.min(0.1, (now - last) / 1000);
      last = now;
      if (this.sim && this.state.phase === 'business') {
        if (!this.paused && !this.modalOpen()) this.sim.update(dt * this.speed);
        this.world.sync(this.sim, { showLabels: this.showLabels, costume: this.state.activity === 'costume' });
        if (this.sim.ended) this.endBusiness();
      } else {
        this.world.sync(this.preview, { showLabels: this.showLabels, costume: false });
      }
      uiT += dt;
      if (uiT > 0.2) {
        uiT = 0;
        this.renderLive();
      }
      this.world.render();
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }

  private makePreview() {
    const p = new BusinessSim(this.state);
    for (const w of p.workers) w.bubble = null;
    return p;
  }
  private refreshPreview() {
    this.preview = this.makePreview();
  }
  private modalOpen() {
    return !$('modal').classList.contains('hidden');
  }

  // ================================================================ input
  private bindInput() {
    document.addEventListener('click', (e) => {
      const el = (e.target as HTMLElement).closest('[data-act]') as HTMLElement | null;
      if (el && !el.hasAttribute('disabled')) this.act(el.dataset.act!);
    });
    document.addEventListener('change', (e) => {
      const el = e.target as HTMLSelectElement;
      if (el.dataset.change) this.act(`${el.dataset.change}:${el.value}`);
    });
    const canvas = this.world.renderer.domElement;
    const view = $('view');
    view.addEventListener('pointerdown', (e) => (this.down = { x: e.clientX, y: e.clientY }));
    view.addEventListener('pointerup', (e) => {
      if (!this.down || e.button !== 0) return;
      const moved = Math.hypot(e.clientX - this.down.x, e.clientY - this.down.y);
      this.down = null;
      if (moved < 6) this.onSceneClick(e.clientX, e.clientY);
    });
    view.addEventListener('pointermove', (e) => {
      if (!this.placing) return;
      const c = this.world.cellAt(e.clientX, e.clientY);
      const lay = new Layout(this.state.furniture, this.state.upgrades);
      const ok = !!c && lay.canPlace(this.placing, c.x, c.z) === null;
      this.world.setGhost(this.placing, c, ok);
    });
    view.addEventListener('contextmenu', (e) => e.preventDefault());
    void canvas;
    window.addEventListener('keydown', (e) => {
      if ((e.target as HTMLElement).tagName === 'INPUT') return;
      if (e.key === 'Escape') {
        if (this.placing || this.removing) this.act('cancel-place');
        else if (this.modalOpen() && this.state.phase !== 'night') this.closeModal();
        else {
          this.world.selected = null;
          this.world.followId = null;
        }
      }
      if (this.state.phase !== 'business') return;
      if (e.key === ' ') {
        e.preventDefault();
        this.act('pause');
      }
      if (e.key === '1' || e.key === '2' || e.key === '3') this.act(`speed:${e.key}`);
      if (e.key === 'f' || e.key === 'F') this.act('follow');
    });
  }

  private onSceneClick(x: number, y: number) {
    const s = this.state;
    if (s.phase === 'prep' || s.phase === 'explore') {
      const c = this.world.cellAt(x, y);
      if (!c || s.phase !== 'prep') return;
      if (this.placing) this.placeFurniture(this.placing, c.x, c.z);
      else if (this.removing) this.removeFurniture(c.x, c.z);
      return;
    }
    if (s.phase !== 'business' || !this.sim) return;
    const pick = this.world.pick(x, y);
    if (!pick) return;
    const sim = this.sim;
    if (pick.kind === 'worker' || pick.kind === 'customer') {
      this.world.selected = pick;
    } else {
      const c = pick.cell;
      const job = sim.jobAtCell(c);
      if (job) {
        this.world.selected = pick;
      } else {
        // seated party at this table?
        const f = sim.layout.furnitureAt.get(key(c));
        const p = f ? sim.parties.find((pp) => pp.tableId === f.id && pp.state !== 'leaving') : undefined;
        if (p) this.world.selected = { kind: 'customer', partyId: p.id };
        else if (sim.layout.walkable(c)) {
          sim.managerMove(c);
          this.world.selected = { kind: 'worker', id: 'manager' };
          this.toast('店長移動中');
        }
      }
    }
    this.renderLive(true);
  }

  // ================================================================ actions
  private act(a: string) {
    const s = this.state;
    const [cmd, ...args] = a.split(':');
    switch (cmd) {
      case 'new-game':
        if (loadGame() && !confirm('開始新遊戲會覆蓋目前的存檔，確定嗎？')) return;
        this.state = newGame();
        saveGame(this.state);
        this.world.rebuildFurniture(this.state);
        this.refreshPreview();
        this.sim = null;
        this.closeModal();
        this.openIntro();
        break;
      case 'continue':
        this.closeModal();
        if (s.phase === 'business') {
          // a business day cannot be resumed mid-way: restart the evening
          s.phase = 'prep';
        }
        if (s.phase === 'night') this.maybeEvent();
        break;
      case 'close-modal':
        this.closeModal();
        break;
      case 'desel':
        this.world.selected = null;
        this.world.followId = null;
        break;
      case 'help':
        this.openHelp();
        break;
      case 'album':
        this.openAlbum();
        break;
      case 'notebook':
        this.openNotebook();
        break;
      case 'reset-cam':
        this.world.resetCamera();
        break;
      case 'toggle-labels':
        this.showLabels = !this.showLabels;
        break;
      // ---------- explore
      case 'visit': {
        if (s.actionPoints <= 0) return this.toast('今天白天的時間用完了，回店裡準備營業吧。');
        if (args[0] === 'cafe') return this.openChatChooser();
        const enc = visitLocation(s, args[0]);
        this.encounter = { loc: args[0], enc };
        this.openEncounter();
        break;
      }
      case 'chat': {
        const enc = visitLocation(s, 'cafe', args[0]);
        this.encounter = { loc: 'cafe', enc };
        this.openEncounter();
        break;
      }
      case 'buy': {
        if (!buyIngredient(s, args[0], Number(args[1]))) this.toast('資金不足。');
        this.openEncounter();
        break;
      }
      case 'partner':
        if (!signPartnership(s)) this.toast('資金不足。');
        else this.toast('與糖霜屋簽約了！甜點材料八折、甜點品質提升。');
        this.openEncounter();
        break;
      case 'poster':
        if (!buyPoster(s)) this.toast('今天已經貼過海報，或資金不足。');
        else this.toast('貼了宣傳海報！人氣 +6');
        this.openEncounter();
        break;
      case 'to-prep':
        s.phase = 'prep';
        this.closeModal();
        saveGame(s);
        break;
      // ---------- prep
      case 'tab':
        this.prepTab = args[0] as App['prepTab'];
        this.act('cancel-place');
        break;
      case 'menu-toggle': {
        const id = args[0];
        if (s.menu.includes(id)) s.menu = s.menu.filter((x) => x !== id);
        else if (s.menu.length >= MAX_MENU) this.toast(`菜單最多 ${MAX_MENU} 道。`);
        else s.menu.push(id);
        if (s.featuredDish && !s.menu.includes(s.featuredDish)) s.featuredDish = null;
        break;
      }
      case 'role': {
        const m = s.maids.find((x) => x.id === args[0])!;
        const r = args[1] as Role;
        if (r === 'stage' && s.activity !== 'stage') return this.toast('只有舞台表演日才能指派舞台。');
        if (r === 'stage') for (const o of s.maids) if (o.role === 'stage') o.role = MAID_BY_ID[o.id].defaultRole;
        m.role = r;
        this.refreshPreview();
        break;
      }
      case 'activity':
        s.activity = args[0] as GameState['activity'];
        if (s.activity !== 'stage') for (const o of s.maids) if (o.role === 'stage') o.role = MAID_BY_ID[o.id].defaultRole;
        if (s.activity === 'limited' && !s.featuredDish) s.featuredDish = s.menu[0] ?? null;
        this.refreshPreview();
        break;
      case 'featured':
        s.featuredDish = args[0] || null;
        break;
      case 'place':
        this.placing = args[0] as FurnitureType;
        this.removing = false;
        this.toast(`點擊地板放置「${FURNITURE[this.placing].name}」（Esc 取消）`);
        break;
      case 'remove-mode':
        this.removing = true;
        this.placing = null;
        this.world.setGhost(null, null, false);
        this.toast('點擊要移除的家具（退回一半費用，Esc 取消）');
        break;
      case 'cancel-place':
        this.placing = null;
        this.removing = false;
        this.world.setGhost(null, null, false);
        break;
      case 'start-business': {
        this.act('cancel-place');
        const err = beginBusiness(s);
        if (err) return this.toast(err);
        this.sim = new BusinessSim(s);
        this.world.selected = null;
        this.speed = 1;
        this.paused = false;
        break;
      }
      // ---------- business
      case 'speed':
        this.speed = Number(args[0]);
        this.paused = false;
        break;
      case 'pause':
        this.paused = !this.paused;
        break;
      case 'follow': {
        const sel = this.world.selected;
        if (this.world.followId) this.world.followId = null;
        else if (sel?.kind === 'worker') this.world.followId = sel.id;
        else if (sel?.kind === 'customer') this.world.followId = this.sim?.party(sel.partyId)?.members[0].id ?? null;
        if (this.world.followId) {
          // zoom in for a closer look
          const dir = this.world.camera.position.clone().sub(this.world.controls.target).normalize();
          this.world.camera.position.copy(this.world.controls.target.clone().add(dir.multiplyScalar(7)));
        }
        break;
      }
      case 'select-maid':
        if (s.phase === 'business') this.world.selected = { kind: 'worker', id: args[0] };
        break;
      case 'mg-do':
        this.cmdResult(this.sim?.managerDo(args[0]) ?? null, '店長出動！');
        break;
      case 'mg-chat':
        this.cmdResult(this.sim?.managerChat(args[0]) ?? null, '店長前去寒暄。');
        break;
      case 'assign':
        this.cmdResult(this.sim?.assignJob(args[0], args[1]) ?? null, `已指派${MAID_BY_ID[args[0]].name}。`);
        break;
      case 'b-role':
        this.cmdResult(this.sim?.setRole(args[0], args[1] as Role) ?? null, `${MAID_BY_ID[args[0]].name}改為${ROLE_NAMES[args[1] as Role]}。`);
        break;
      case 'b-rest':
        this.cmdResult(this.sim?.sendRest(args[0]) ?? null, `${MAID_BY_ID[args[0]].name}去休息了。`);
        break;
      case 'b-pause':
        this.cmdResult(this.sim?.togglePause(args[0]) ?? null, '已切換。');
        break;
      // ---------- night
      case 'event-choice': {
        const ev = nextEvent(s);
        if (!ev) return;
        this.eventResult = resolveEvent(s, ev, Number(args[0]));
        saveGame(s);
        this.openEventResult(ev.title);
        break;
      }
      case 'next-event':
        this.eventResult = null;
        this.closeModal();
        this.maybeEvent();
        break;
      case 'upgrade': {
        const k = args[0] as keyof typeof UPGRADE_INFO;
        const info = UPGRADE_INFO[k];
        if (s.upgrades[k]) return;
        if (s.money < info.price) return this.toast('資金不足。');
        s.money -= info.price;
        s.upgrades[k] = true;
        this.world.rebuildFurniture(s);
        this.refreshPreview();
        this.toast(`購入「${info.name}」！`);
        saveGame(s);
        break;
      }
      case 'dayoff': {
        const m = s.maids.find((x) => x.id === args[0])!;
        m.dayOffTomorrow = !m.dayOffTomorrow;
        break;
      }
      case 'sleep':
        if (nextEvent(s)) return this.maybeEvent();
        startNextDay(s);
        this.sim = null;
        this.refreshPreview();
        this.briefing = morningBriefing(s);
        saveGame(s);
        this.openMorning();
        break;
    }
    this.renderAll();
  }

  private cmdResult(err: string | null, ok: string) {
    this.toast(err ?? ok, !!err);
  }

  // ================================================================ furniture
  private placeFurniture(type: FurnitureType, x: number, z: number) {
    const s = this.state;
    const lay = new Layout(s.furniture, s.upgrades);
    const err = lay.canPlace(type, x, z);
    if (err) return this.toast(err, true);
    const price = FURNITURE[type].price;
    if (s.money < price) return this.toast('資金不足。', true);
    s.money -= price;
    s.todaySpend.furniture += price;
    s.furniture.push({ id: `f${s.nextFurnitureId++}`, type, x, z });
    this.world.rebuildFurniture(s);
    this.refreshPreview();
    this.toast(`放置了${FURNITURE[type].name}（${yen(price)}）`);
    this.renderAll();
  }
  private removeFurniture(x: number, z: number) {
    const s = this.state;
    const lay = new Layout(s.furniture, s.upgrades);
    const f = lay.furnitureAt.get(`${x},${z}`);
    if (!f) return;
    if (f.type === 'table' && s.furniture.filter((o) => o.type === 'table').length <= 1) return this.toast('至少要留一張桌子。', true);
    s.furniture = s.furniture.filter((o) => o.id !== f.id);
    const refund = Math.floor(FURNITURE[f.type].price / 2);
    s.money += refund;
    s.todaySpend.furniture -= refund;
    for (const c of Object.values(s.customers)) if (c.favoriteSeat === f.id) c.favoriteSeat = null;
    this.world.rebuildFurniture(s);
    this.refreshPreview();
    this.toast(`移除了${FURNITURE[f.type].name}（退回 ${yen(refund)}）`);
    this.renderAll();
  }

  // ================================================================ phase transitions
  private endBusiness() {
    if (!this.sim) return;
    const sim = this.sim;
    settleDay(this.state, sim);
    this.sim = null;
    this.world.selected = null;
    this.world.followId = null;
    for (const m of this.state.maids) if (m.role === 'stage') m.role = MAID_BY_ID[m.id].defaultRole;
    this.refreshPreview();
    saveGame(this.state);
    this.renderAll();
    this.maybeEvent();
  }

  private maybeEvent() {
    const ev = nextEvent(this.state);
    if (!ev) return;
    const who = MAID_BY_ID[ev.who]?.name ?? CUSTOMER_BY_ID[ev.who]?.name ?? '';
    this.modal(`
      <div class="event">
        <div class="event-tag">深夜事件 · ${esc(who)}</div>
        <h2>${esc(ev.title)}</h2>
        ${ev.lines(this.state).map((l) => `<p>${esc(l)}</p>`).join('')}
        <div class="choices">${ev.choices.map((c, i) => `<button class="btn primary" data-act="event-choice:${i}">${esc(c.label)}</button>`).join('')}</div>
      </div>`);
  }
  private openEventResult(title: string) {
    this.modal(`<div class="event"><h2>${esc(title)}</h2><p class="result">${esc(this.eventResult ?? '')}</p>
      <div class="choices"><button class="btn primary" data-act="next-event">繼續</button></div></div>`);
  }

  // ================================================================ modals
  private modal(html: string, wide = false) {
    const m = $('modal');
    m.classList.remove('hidden');
    m.innerHTML = `<div class="modal-card ${wide ? 'wide' : ''}">${html}</div>`;
  }
  closeModal() {
    $('modal').classList.add('hidden');
    $('modal').innerHTML = '';
  }

  private titleScreen() {
    const has = !!loadGame();
    this.modal(`
      <div class="title">
        <div class="logo">MAIDEN PARADE</div>
        <div class="sub">女僕咖啡廳物語 · 第一版可玩原型</div>
        <p>在老商店街的角落，接手一間快撐不下去的女僕咖啡廳。<br>員工會成長、客人會記得你、今天的選擇會改變明天。</p>
        <div class="choices">
          ${has ? `<button class="btn primary" data-act="continue">繼續遊戲（第 ${this.state.day} 天）</button>` : ''}
          <button class="btn ${has ? '' : 'primary'}" data-act="new-game">開始新遊戲</button>
          <button class="btn ghost" data-act="help">操作說明</button>
        </div>
      </div>`);
  }

  private openIntro() {
    this.modal(`
      <div class="event">
        <div class="event-tag">序章</div>
        <h2>Maiden Parade</h2>
        <p>「這間店，就拜託妳了。」前任店長留下鑰匙和一本記滿客人喜好的筆記，就離開了商店街。</p>
        <p>店裡只剩三位願意留下的女僕：元氣的<b>小春</b>、對料理很固執的<b>凜</b>、還有怕生的新人<b>雫</b>。</p>
        <p>白天去商店街採購、認識人；下午安排菜單和班表；晚上看著她們工作，必要時親自出手。</p>
        <div class="choices"><button class="btn primary" data-act="close-modal">開始第一天</button></div>
      </div>`);
    this.briefing = morningBriefing(this.state);
  }

  private openMorning() {
    const s = this.state;
    this.modal(`
      <div class="event">
        <div class="event-tag">第 ${s.day} 天 · 早晨</div>
        <h2>今日晨報</h2>
        ${this.briefing.map((l) => `<p>${esc(l)}</p>`).join('')}
        <div class="choices"><button class="btn primary" data-act="close-modal">出門</button></div>
      </div>`);
  }

  private openHelp() {
    this.modal(`
      <h2>操作說明</h2>
      <div class="help">
        <h3>鏡頭</h3>
        <p>左鍵拖曳：旋轉 · 右鍵拖曳：平移 · 滾輪：縮放 · 選取角色後按 <kbd>F</kbd>：跟隨並拉近觀察</p>
        <h3>一天的流程</h3>
        <p><b>白天</b>：到商店街的 6 個地點行動（每天 4 次）。採購食材、認識客人、發傳單、和女僕聊天。</p>
        <p><b>下午</b>：決定菜單、班表（接待／廚房／外場）、活動與裝潢。沒有時間限制。</p>
        <p><b>晚上</b>：女僕會自己工作。點擊客人、女僕或地上的狀況（打翻的餐點、待收的桌子、出餐台的料理）可以介入。</p>
        <p><b>深夜</b>：查看結算、客人評價與員工狀況，觸發角色事件，購買設備、安排明天休假。</p>
        <h3>介入營業</h3>
        <p>店長可以<b>親自</b>帶位、點餐、送餐、清理、處理客訴、和客人寒暄（免費，但要走過去）。點地板可以讓店長移動。</p>
        <p>對女僕下指令（改崗位、指派任務、休息、暫停）會消耗<b>指揮點數</b>，每 40 秒恢復 1 點，最多 5 點。</p>
        <p>快捷鍵：<kbd>空白鍵</kbd> 暫停 · <kbd>1</kbd><kbd>2</kbd><kbd>3</kbd> 速度 · <kbd>Esc</kbd> 取消選取</p>
        <h3>記憶</h3>
        <p>每位客人都會記得上次的體驗：誰服務他、等了多久、吃到什麼。滿意的客人會指名喜歡的女僕、坐老位子、帶朋友來；被冷落的客人會變少上門。</p>
      </div>
      <div class="choices"><button class="btn primary" data-act="close-modal">了解</button></div>`, true);
  }

  private openAlbum() {
    const a = this.state.album;
    this.modal(`<h2>📔 咖啡廳回憶相簿</h2>
      <div class="album">${a.map((e) => `<div class="memory"><div class="day">第 ${e.day} 天</div><h3>${esc(e.title)}</h3><p>${esc(e.text)}</p></div>`).join('')}</div>
      <div class="choices"><button class="btn primary" data-act="close-modal">關閉</button></div>`, true);
  }

  private openNotebook() {
    const s = this.state;
    const rows = CUSTOMERS.filter((c) => s.customers[c.id].known).map((c) => {
      const m = s.customers[c.id];
      const kind = m.isRegular ? '<span class="tag gold">熟客</span>' : c.kind === 'special' ? '<span class="tag pink">特別</span>' : '';
      const likes = c.likes.map((l) => DISH_BY_ID[l].name).join('、');
      return `<div class="cust">
        <div class="cust-head"><span class="dot" style="background:#${c.color.toString(16).padStart(6, '0')}"></span><b>${esc(c.name)}</b> ${kind}</div>
        <div class="muted">${esc(c.desc)}</div>
        <div class="kv"><span>來店</span><b>${m.visits} 次</b><span>忠誠</span>${bar(m.loyalty, 'pink')}
        <span>喜歡</span><b>${likes}${c.prefersQuiet ? '・喜歡安靜' : ''}${c.lively ? '・愛熱鬧' : ''}</b>
        <span>指名</span><b>${m.favoriteMaid ? MAID_BY_ID[m.favoriteMaid].name : '—'}</b>
        <span>上次</span><b>${m.lastSatisfaction != null ? `滿意度 ${m.lastSatisfaction}` : '還沒來過'}</b></div>
        ${m.log.length ? `<ul class="log">${m.log.slice(-4).map((l) => `<li>第 ${l.day} 天：${esc(l.text)}</li>`).join('')}</ul>` : ''}
      </div>`;
    });
    const unknown = CUSTOMERS.filter((c) => !s.customers[c.id].known).length;
    this.modal(`<h2>📒 顧客筆記</h2><div class="notebook">${rows.join('')}</div>
      ${unknown ? `<p class="muted">還有 ${unknown} 位客人尚未認識。去街區探索看看吧。</p>` : ''}
      <div class="choices"><button class="btn primary" data-act="close-modal">關閉</button></div>`, true);
  }

  private openChatChooser() {
    this.modal(`<h2>☕ 回店裡和誰聊聊？</h2><p class="muted">花費 1 次行動。聊天可以讓她的心情變好，並稍微恢復疲勞。</p>
      <div class="choices">${activeMaids(this.state).map((m) => `<button class="btn" data-act="chat:${m.id}">${MAID_BY_ID[m.id].name}（心情 ${Math.round(m.mood)}）</button>`).join('')}
      <button class="btn ghost" data-act="close-modal">取消</button></div>`);
  }

  private openEncounter() {
    if (!this.encounter) return;
    const s = this.state;
    const { loc, enc } = this.encounter;
    let shop = '';
    const ings = INGREDIENTS.filter((i) => i.shop === loc);
    if (ings.length) {
      shop = `<table class="shop"><tr><th>食材</th><th>單價</th><th>庫存</th><th></th></tr>
        ${ings.map((i) => `<tr><td>${i.name}</td><td>${yen(ingredientPrice(s, i.id))}</td><td>${s.inventory[i.id] ?? 0}</td>
        <td><button class="btn sm" data-act="buy:${i.id}:1">+1</button><button class="btn sm" data-act="buy:${i.id}:5">+5</button></td></tr>`).join('')}</table>`;
    }
    if (loc === 'sweets' && !s.partners.includes('sweets')) shop += `<button class="btn primary" data-act="partner">簽訂供應合約（${yen(PARTNER_FEE)}）</button>`;
    if (loc === 'plaza') shop += `<button class="btn" data-act="poster" ${s.flags.posterToday ? 'disabled' : ''}>張貼宣傳海報（¥500，人氣 +6）</button>`;
    if (loc === 'general') shop += `<p class="muted">家具與擺飾可以在下午「營業準備 → 裝潢」直接訂購擺放。</p>`;
    this.modal(`<h2>${LOCATIONS.find((l) => l.id === loc)?.icon ?? ''} ${esc(enc.title)}</h2>
      ${enc.lines.map((l) => `<p>${esc(l)}</p>`).join('')}
      ${shop}
      <div class="money-line">資金 ${yen(s.money)}</div>
      <div class="choices"><button class="btn primary" data-act="close-modal">離開</button></div>`);
  }

  toast(text: string, warn = false) {
    const t = $('toast');
    t.textContent = text;
    t.className = `show ${warn ? 'warn' : ''}`;
    clearTimeout(this.toastT);
    this.toastT = window.setTimeout(() => (t.className = ''), 2600);
  }

  // ================================================================ rendering
  private setHtml(id: string, html: string) {
    if (this.lastHtml[id] === html) return;
    this.lastHtml[id] = html;
    $(id).innerHTML = html;
  }

  renderAll() {
    this.renderTop();
    this.renderSide();
    this.renderStaff();
    this.renderInspector();
    this.renderFeed();
    document.body.dataset.phase = this.state.phase;
  }
  private renderLive(force = false) {
    if (force) this.lastHtml = {};
    this.renderTop();
    this.renderStaff();
    this.renderInspector();
    this.renderFeed();
    if (this.state.phase === 'business') this.renderSide();
  }

  private renderTop() {
    const s = this.state;
    const st = dominantStyle(s);
    let mid = '';
    if (s.phase === 'business' && this.sim) {
      const sim = this.sim;
      const pct = Math.min(100, (sim.t / DURATION) * 100);
      mid = `<div class="clock">🕰 ${sim.clock()} <span class="bar thin"><i style="width:${pct}%"></i></span><small>${OPEN_HOUR}:00–${CLOSE_HOUR}:00</small></div>
        <div class="cp" title="指揮點數：對女僕下指令需要消耗">📣 ${'●'.repeat(sim.commandPoints)}${'○'.repeat(5 - sim.commandPoints)}</div>
        <div class="speed">
          <button class="btn sm ${this.paused ? 'on' : ''}" data-act="pause">${this.paused ? '▶' : '❚❚'}</button>
          ${[1, 2, 3].map((n) => `<button class="btn sm ${!this.paused && this.speed === n ? 'on' : ''}" data-act="speed:${n}">${n}x</button>`).join('')}
        </div>
        <div class="stat">👥 ${sim.parties.filter((p) => p.state !== 'arriving' && p.state !== 'leaving').reduce((a, p) => a + p.members.length, 0)}</div>
        <div class="stat">💴 今日 ${yen(sim.revenue)}</div>`;
    }
    this.setHtml('topbar', `
      <div class="brand">MAIDEN PARADE</div>
      <div class="phase">第 ${s.day} 天 · ${PHASE_NAMES[s.phase]}</div>
      ${mid}
      <div class="stat" title="資金">💰 ${yen(s.money)}</div>
      <div class="stat" title="店鋪人氣">⭐ ${Math.round(s.popularity)}</div>
      <div class="stat" title="店鋪風格（由裝潢、菜單、活動形成）">🎀 ${st.name}</div>
      <div class="tools">
        <button class="btn sm ghost" data-act="notebook" title="顧客筆記">📒</button>
        <button class="btn sm ghost" data-act="album" title="回憶相簿">📔</button>
        <button class="btn sm ghost" data-act="toggle-labels" title="顯示/隱藏名牌">🏷</button>
        <button class="btn sm ghost" data-act="reset-cam" title="重置鏡頭">🎥</button>
        <button class="btn sm ghost" data-act="help" title="說明">？</button>
      </div>`);
  }

  private renderSide() {
    const s = this.state;
    let html = '';
    if (s.phase === 'explore') html = this.sideExplore();
    else if (s.phase === 'prep') html = this.sidePrep();
    else if (s.phase === 'business') html = this.sideBusiness();
    else html = this.sideNight();
    this.setHtml('side', html);
  }

  private sideExplore() {
    const s = this.state;
    const slots = ['09:00', '11:00', '13:00', '15:00'];
    const used = 4 - s.actionPoints;
    return `<h2>商店街</h2>
      <div class="ap">${slots.map((t, i) => `<span class="${i < used ? 'used' : ''}">${t}</span>`).join('')}</div>
      <p class="muted">剩下 ${s.actionPoints} 次行動。每個地點都有自己的用途。</p>
      <div class="brief">${(this.briefing.length ? this.briefing : morningBriefing(s)).map((l) => `<div>${esc(l)}</div>`).join('')}</div>
      <div class="locs">${LOCATIONS.map((l) => `<button class="loc" data-act="visit:${l.id}" ${s.actionPoints <= 0 ? 'disabled' : ''}>
        <span class="icon">${l.icon}</span><span><b>${esc(l.name)}</b><small>${esc(l.desc)}</small></span></button>`).join('')}</div>
      <h3>庫存</h3>${this.inventoryHtml()}
      <button class="btn primary wide" data-act="to-prep">回店裡準備營業 →</button>`;
  }

  private inventoryHtml() {
    const s = this.state;
    return `<div class="inv">${INGREDIENTS.map((i) => `<span class="${(s.inventory[i.id] ?? 0) <= 1 ? 'low' : ''}">${i.name} <b>${s.inventory[i.id] ?? 0}</b></span>`).join('')}</div>`;
  }

  private sidePrep() {
    const s = this.state;
    const tabs = (['menu', 'staff', 'activity', 'decor'] as const).map((t) => `<button class="tab ${this.prepTab === t ? 'on' : ''}" data-act="tab:${t}">${{ menu: '菜單', staff: '排班', activity: '活動', decor: '裝潢' }[t]}</button>`).join('');
    let body = '';
    if (this.prepTab === 'menu') {
      body = `<p class="muted">選擇今天供應的料理（最多 ${MAX_MENU} 道）。份數依目前庫存計算。</p>
        ${(['drink', 'dessert', 'main'] as const).map((cat) => `<h3>${CAT_NAMES[cat]}</h3>
        ${s.unlockedDishes.map((id) => DISH_BY_ID[id]).filter((d) => d.category === cat).map((d) => {
          const n = servingsPossible(s.inventory, d);
          const cost = Object.entries(d.ingredients).reduce((a, [k, v]) => a + ingredientPrice(s, k) * v, 0);
          const on = s.menu.includes(d.id);
          return `<label class="dish ${on ? 'on' : ''} ${d.signature ? 'sig' : ''}" data-act="menu-toggle:${d.id}">
            <span class="chk">${on ? '✔' : ''}</span><span class="nm">${d.signature ? '👑 ' : ''}${d.name}</span>
            <span class="pr">${yen(d.price)}</span><span class="muted">成本 ${yen(cost)}</span><span class="${n === 0 ? 'low' : ''}">可做 ${n === Infinity ? '∞' : n}</span></label>`;
        }).join('')}`).join('')}`;
    } else if (this.prepTab === 'staff') {
      body = activeMaids(s).map((m) => {
        const d = MAID_BY_ID[m.id];
        const roles: Role[] = ['reception', 'kitchen', 'floor', 'stage', 'off'];
        return `<div class="maid-card">
          <div class="mh"><span class="dot" style="background:#${d.hair.toString(16).padStart(6, '0')}"></span><b>${d.name}</b>
          ${d.traits.map((t) => `<span class="tag" title="${TRAIT_INFO[t].desc}">${TRAIT_INFO[t].name}</span>`).join('')}</div>
          <div class="muted">${esc(d.intro)}</div>
          <div class="skills">${(Object.keys(SKILL_NAMES) as SkillKey[]).map((k) => `<span>${SKILL_NAMES[k]}</span>${bar(m.skills[k], 'blue')}<b>${m.skills[k]}</b>`).join('')}</div>
          <div class="skills"><span>心情</span>${bar(m.mood, 'pink')}<b>${Math.round(m.mood)}</b><span>疲勞</span>${bar(m.fatigue, 'red')}<b>${Math.round(m.fatigue)}</b></div>
          ${m.fatigue >= 60 ? '<div class="warn">⚠ 很累了，今天容易失誤。考慮讓她休假。</div>' : ''}
          <div class="roles">${roles.map((r) => `<button class="btn sm ${m.role === r ? 'on' : ''}" data-act="role:${m.id}:${r}" ${r === 'stage' && s.activity !== 'stage' ? 'disabled' : ''}>${ROLE_NAMES[r]}</button>`).join('')}</div>
        </div>`;
      }).join('') + `<p class="muted">每位上班的女僕日薪 ¥900。廚房沒人時，其他人會勉強幫忙做菜。</p>`;
    } else if (this.prepTab === 'activity') {
      const hasStage = s.furniture.some((f) => f.type === 'stage');
      body = (Object.values(ACTIVITIES)).map((a) => `<label class="act-opt ${s.activity === a.id ? 'on' : ''}" data-act="activity:${a.id}">
          <b>${a.name}</b> ${a.cost ? `<span class="pr">${yen(a.cost)}</span>` : ''}<div class="muted">${a.desc}</div>
          ${a.id === 'stage' && !hasStage ? '<div class="warn">需要先在「裝潢」擺放小舞台。</div>' : ''}</label>`).join('');
      if (s.activity === 'limited') {
        body += `<h3>今日限定料理</h3><select data-change="featured">${s.menu.map((id) => `<option value="${id}" ${s.featuredDish === id ? 'selected' : ''}>${DISH_BY_ID[id].name}</option>`).join('')}</select>`;
      }
      if (s.activity === 'stage') body += `<p class="muted">到「排班」把一位女僕設為「舞台」。表演能力越高效果越好。</p>`;
    } else {
      const sc = styleScores(s);
      const max = Math.max(...Object.values(sc), 1);
      body = `<p class="muted">點選家具後在地板上點擊放置。走道被擋住、或要走很遠的位置，都會影響營業。</p>
        <div class="furn">${(Object.keys(FURNITURE) as FurnitureType[]).map((t) => {
          const f = FURNITURE[t];
          return `<button class="fbtn ${this.placing === t ? 'on' : ''}" data-act="place:${t}" title="${esc(f.desc)}"><b>${f.name}</b><small>${yen(f.price)}</small></button>`;
        }).join('')}</div>
        <div class="row"><button class="btn sm ${this.removing ? 'on' : ''}" data-act="remove-mode">🗑 移除模式</button>
        ${this.placing || this.removing ? '<button class="btn sm" data-act="cancel-place">取消</button>' : ''}</div>
        <h3>店鋪風格</h3>
        <div class="skills">${(Object.keys(sc) as (keyof typeof sc)[]).map((k) => `<span>${STYLE_NAMES[k].slice(0, 2)}</span>${bar((sc[k] / max) * 100, 'gold')}<b>${sc[k].toFixed(0)}</b>`).join('')}</div>
        <p class="muted">風格會吸引對應喜好的客人，並在他們入座時加分。</p>`;
    }
    const working = activeMaids(s).filter((m) => m.role !== 'off').length;
    return `<h2>營業準備</h2><div class="tabs">${tabs}</div><div class="tab-body">${body}</div>
      <div class="summary">上班 ${working} 人 · 活動：${ACTIVITIES[s.activity].name} · 菜單 ${s.menu.length} 道</div>
      <button class="btn primary wide" data-act="start-business">開店營業 🌙</button>`;
  }

  private sideBusiness() {
    const sim = this.sim!;
    const pc = sim.pendingCounts();
    const queue = sim.parties.filter((p) => p.state === 'queue').length;
    const tbl = sim.layout.tables.length;
    const busy = sim.reservedTables.size;
    return `<h2>營業中</h2>
      <div class="kv"><span>門口排隊</span><b>${queue} 組</b><span>座位</span><b>${busy}/${tbl} 桌${sim.dirtyTables.size ? `（待整理 ${sim.dirtyTables.size}）` : ''}</b>
      <span>服務完成</span><b>${sim.servedCount} 人</b><span>流失</span><b class="${sim.lost ? 'low' : ''}">${sim.lost} 人</b></div>
      <h3>待辦工作</h3>
      <div class="jobs">${(Object.keys(pc) as (keyof typeof pc)[]).filter((k) => pc[k]).map((k) => `<span class="${k === 'complaint' || k === 'mess' ? 'low' : ''}">${JOB_NAMES[k]} ${pc[k]}</span>`).join('') || '<span>（沒有）</span>'}</div>
      <p class="muted">點擊客人、女僕或地上的狀況來介入。點地板讓店長移動。<br>店長親自做事不需要點數，但要花時間走過去。</p>`;
  }

  private sideNight() {
    const s = this.state;
    const r = s.lastReport;
    if (!r) return '<h2>深夜</h2>';
    const totalExp = Object.values(r.expenses).reduce((a, b) => a + b, 0);
    const net = r.revenue - totalExp;
    const expRows: [string, number][] = [['食材', r.expenses.ingredients], ['薪資', r.expenses.wages], ['設備維護', r.expenses.maintenance], ['水電雜費', r.expenses.utilities], ['活動', r.expenses.activity], ['宣傳／合約', r.expenses.promotion], ['家具', r.expenses.furniture]];
    const pending = !!nextEvent(s);
    const regulars = Object.values(s.customers).filter((c) => c.isRegular).length;
    const known = Object.values(s.customers).filter((c) => c.known && c.visits > 0).length;
    const happy = activeMaids(s).reduce((a, m) => a + (m.mood - m.fatigue * 0.3), 0) / Math.max(1, activeMaids(s).length);
    return `<h2>第 ${r.day} 天 結算</h2>
      <div class="report">
        <div class="big"><span>營業額</span><b>${yen(r.revenue)}</b></div>
        <div class="big"><span>淨利潤</span><b class="${net < 0 ? 'low' : 'good'}">${yen(net)}</b></div>
        <details><summary>支出明細 ${yen(totalExp)}</summary>${expRows.filter((e) => e[1]).map(([k, v]) => `<div class="kv2"><span>${k}</span><b>${yen(v)}</b></div>`).join('')}</details>
        <div class="kv"><span>顧客滿意度</span>${bar(r.avgSatisfaction, 'pink')}<span>員工幸福度</span>${bar(happy, 'blue')}
        <span>服務／流失</span><b>${r.served} / ${r.lost}</b><span>客訴（處理）</span><b>${r.complaints}（${r.complaintsHandled}）</b>
        <span>失誤</span><b>${r.spills}</b><span>人氣</span><b>${Math.round(s.popularity)}（${r.popularityDelta >= 0 ? '+' : ''}${r.popularityDelta}）</b>
        <span>熟客比例</span><b>${known ? Math.round((regulars / known) * 100) : 0}%（${regulars} 人）</b></div>
      </div>
      <h3>客人評價</h3>
      <div class="reviews">${r.reviews.map((v) => `<div><b>${esc(v.customer)}</b> <small>${v.sat}</small><div>${esc(v.text)}</div></div>`).join('') || '<div class="muted">今天沒有客人……</div>'}</div>
      <h3>員工狀況</h3>
      <div class="reviews">${r.maidNotes.map((n) => `<div>${esc(n.text)}</div>`).join('')}</div>
      <h3>經營建議</h3>
      <div class="reviews">${r.advice.map((a) => `<div>💡 ${esc(a)}</div>`).join('')}</div>
      <h3>設備升級</h3>
      ${(Object.keys(UPGRADE_INFO) as (keyof typeof UPGRADE_INFO)[]).map((k) => `<div class="upg"><span><b>${UPGRADE_INFO[k].name}</b><small>${UPGRADE_INFO[k].desc}</small></span>
        ${s.upgrades[k] ? '<span class="tag">已購入</span>' : `<button class="btn sm" data-act="upgrade:${k}">${yen(UPGRADE_INFO[k].price)}</button>`}</div>`).join('')}
      <h3>明天的休假</h3>
      <div class="roles">${activeMaids(s).map((m) => `<button class="btn sm ${m.dayOffTomorrow ? 'on' : ''}" data-act="dayoff:${m.id}">${MAID_BY_ID[m.id].name}${m.dayOffTomorrow ? '休假' : '上班'}（疲勞 ${Math.round(m.fatigue)}）</button>`).join('')}</div>
      <button class="btn primary wide" data-act="sleep">${pending ? '還有事件……' : '就寢，迎接明天 →'}</button>`;
  }

  private renderStaff() {
    const s = this.state;
    const sim = this.sim;
    const sel = this.world.selected?.kind === 'worker' ? this.world.selected.id : null;
    this.setHtml('staff', activeMaids(s).map((m) => {
      const d = MAID_BY_ID[m.id];
      const w = sim?.workers.find((x) => x.maidId === m.id);
      const act = s.phase === 'business' && w ? w.activity : ROLE_NAMES[m.role];
      return `<div class="staff-card ${sel === m.id ? 'sel' : ''}" data-act="select-maid:${m.id}">
        <div><span class="dot" style="background:#${d.hair.toString(16).padStart(6, '0')}"></span><b>${d.name}</b> <span class="tag">${ROLE_NAMES[m.role]}</span></div>
        <div class="act">${esc(act)}</div>
        <div class="mini-row"><span>心情</span>${bar(m.mood, 'pink')}</div>
        <div class="mini-row"><span>疲勞</span>${bar(m.fatigue, 'red')}</div>
      </div>`;
    }).join(''));
  }

  private renderFeed() {
    if (this.state.phase !== 'business' || !this.sim) return this.setHtml('feed', '');
    const notes = this.sim.notes.slice(-6).reverse();
    this.setHtml('feed', notes.map((n) => `<div class="note ${n.kind}">${esc(n.text)}</div>`).join(''));
  }

  private renderInspector() {
    const sim = this.sim;
    const sel = this.world.selected;
    if (!sim || this.state.phase !== 'business' || !sel) return this.setHtml('inspector', '');
    let html = '';
    if (sel.kind === 'worker') html = this.inspectWorker(sel.id);
    else if (sel.kind === 'customer') html = this.inspectParty(sel.partyId);
    else html = this.inspectCell(sel);
    this.setHtml('inspector', html ? `<button class="x" data-act="desel">×</button>${html}` : '');
  }

  private assignButtons(j: Job) {
    const sim = this.sim!;
    const mg = `<button class="btn sm primary" data-act="mg-do:${j.id}">店長親自${JOB_NAMES[j.type]}</button>`;
    const maids = sim.workers.filter((w) => w.maidId && sim.maid(w.maidId)?.role !== 'off').map((w) => `<button class="btn sm" data-act="assign:${w.maidId}:${j.id}" ${sim.commandPoints < 1 ? 'disabled' : ''}>指派${w.name} 📣1</button>`).join('');
    const who = j.claimedBy ? sim.workers.find((w) => w.id === j.claimedBy)?.name : null;
    return `<div class="job"><b>${JOB_NAMES[j.type]}</b> ${who ? `<small>（${who}處理中）</small>` : '<small class="low">（還沒有人處理）</small>'}<div class="row">${mg}${maids}</div></div>`;
  }

  private inspectWorker(id: string) {
    const sim = this.sim!;
    const w = sim.workers.find((x) => x.id === id);
    if (!w) return '';
    if (w.kind === 'manager') {
      return `<h3>店長（你）</h3><div class="muted">目前：${esc(w.activity)}</div>
        <p class="muted">點地板移動。點客人或狀況，可以親自處理（不消耗點數）。</p>
        <button class="btn sm" data-act="follow">${this.world.followId ? '停止跟隨' : '🎥 跟隨（F）'}</button>`;
    }
    const m = sim.maid(w.maidId!)!;
    const d = MAID_BY_ID[m.id];
    const roles: Role[] = ['reception', 'kitchen', 'floor', 'stage'];
    return `<h3>${d.name} <span class="tag">${ROLE_NAMES[m.role]}</span></h3>
      <div class="muted">${d.traits.map((t) => TRAIT_INFO[t].name).join('・')} · 目前：${esc(w.activity)}${w.carrying ? '（端著餐點）' : ''}</div>
      <div class="skills"><span>心情</span>${bar(m.mood, 'pink')}<b>${Math.round(m.mood)}</b><span>疲勞</span>${bar(m.fatigue, 'red')}<b>${Math.round(m.fatigue)}</b>
      ${(Object.keys(SKILL_NAMES) as SkillKey[]).map((k) => `<span>${SKILL_NAMES[k]}</span>${bar(m.skills[k], 'blue')}<b>${m.skills[k]}</b>`).join('')}</div>
      <div class="sub">改變崗位 📣1</div>
      <div class="roles">${roles.map((r) => `<button class="btn sm ${m.role === r ? 'on' : ''}" data-act="b-role:${m.id}:${r}" ${m.role === r || sim.commandPoints < 1 || (r === 'stage' && this.state.activity !== 'stage') ? 'disabled' : ''}>${ROLE_NAMES[r]}</button>`).join('')}</div>
      <div class="row">
        <button class="btn sm" data-act="b-rest:${m.id}" ${w.resting || sim.commandPoints < 1 ? 'disabled' : ''}>去休息 📣1</button>
        <button class="btn sm" data-act="b-pause:${m.id}">${w.paused ? '恢復工作' : '暫停 📣1'}</button>
        <button class="btn sm" data-act="follow">${this.world.followId ? '停止跟隨' : '🎥 跟隨'}</button>
      </div>`;
  }

  private inspectParty(pid: string) {
    const sim = this.sim!;
    const p = sim.party(pid);
    if (!p) {
      this.world.selected = null;
      return '';
    }
    const main = p.members[0];
    const def = main.defId ? CUSTOMER_BY_ID[main.defId] : null;
    const mem = def ? this.state.customers[def.id] : null;
    const jobs = sim.jobsForParty(pid);
    const canChat = ['browsing', 'waitOrder', 'waitFood', 'eating'].includes(p.state) && !main.causes.has('managerChat');
    const memHtml = mem && def
      ? `<div class="kv"><span>來店</span><b>${mem.visits === 0 ? '第一次' : `第 ${mem.visits + 1} 次`}${mem.isRegular ? ' · 熟客' : ''}</b>
         <span>指名</span><b>${mem.favoriteMaid ? MAID_BY_ID[mem.favoriteMaid].name : '—'}</b>
         <span>喜歡</span><b>${def.likes.map((l) => DISH_BY_ID[l].name).join('、')}</b>
         <span>上次</span><b>${mem.lastSatisfaction != null ? `滿意度 ${mem.lastSatisfaction}` : '—'}</b></div>
         ${mem.lastCauses.length ? `<div class="muted">記得：${mem.lastCauses.slice(0, 3).map((c) => causeName(c)).join('、')}</div>` : ''}`
      : '<div class="muted">第一次見到的客人。</div>';
    const items = p.members.flatMap((m) => m.items);
    return `<h3>${esc(main.name)}${p.members.length > 1 ? ` 一行 ${p.members.length} 人` : ''}</h3>
      <div class="muted">${PARTY_STATE[p.state] ?? ''}</div>
      <div class="skills"><span>滿意度</span>${bar(main.sat, main.sat >= 70 ? 'green' : main.sat >= 45 ? 'gold' : 'red')}<b>${Math.round(main.sat)}</b></div>
      ${items.length ? `<div class="muted">點了：${items.map((i) => DISH_BY_ID[i].name).join('、')}</div>` : ''}
      ${memHtml}
      ${jobs.map((j) => this.assignButtons(j)).join('')}
      ${canChat ? `<button class="btn sm" data-act="mg-chat:${pid}">店長上前寒暄</button>` : ''}
      <button class="btn sm" data-act="follow">${this.world.followId ? '停止跟隨' : '🎥 跟隨'}</button>`;
  }

  private inspectCell(sel: Extract<Pick, { kind: 'cell' }>) {
    const sim = this.sim!;
    const j = sim.jobAtCell(sel.cell);
    if (!j) {
      this.world.selected = null;
      return '';
    }
    const o = j.orderId ? sim.order(j.orderId) : null;
    const desc = j.type === 'mess' ? '地上有打翻的餐點，客人踩到會不開心。' : j.type === 'clean' ? '客人離開後的桌子，整理好才能帶下一組客人入座。' : j.type === 'deliver' ? `出餐台上的${o?.items.map((i) => DISH_BY_ID[i].name).join('＋')}，等著送到客人桌上。` : j.type === 'cook' ? `還有 ${sim.pendingCounts().cook} 份訂單等待製作。店長也可以下廚（料理 40）。` : '';
    return `<h3>${JOB_NAMES[j.type]}</h3><p class="muted">${desc}</p>${this.assignButtons(j)}`;
  }
}

function causeName(c: string) {
  const map: Record<string, string> = {
    longWaitDoor: '門口等很久', longWaitOrder: '點餐等很久', longWaitFood: '上菜很慢', greatFood: '很好吃', badFood: '不好吃', favDish: '喜歡的料理',
    favMaid: '喜歡的女僕', favMaidAbsent: '指名的女僕不在', noisy: '太吵', enjoyedShow: '表演很棒', spill: '餐點打翻', complaintHandled: '客訴有被處理',
    complaintIgnored: '客訴被無視', outOfStock: '賣完了', styleMatch: '喜歡店裡風格', managerChat: '店長來聊天', favSeat: '老位子', walkedOut: '等不下去',
  };
  return map[c] ?? c;
}
