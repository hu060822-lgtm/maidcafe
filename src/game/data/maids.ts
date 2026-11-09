import type { MaidDef, TraitKey } from '../types';

export const TRAIT_INFO: Record<TraitKey, { name: string; desc: string }> = {
  cheerful: { name: '開朗', desc: '在附近工作的同事心情會慢慢變好。' },
  careful: { name: '細心', desc: '送餐時比較不容易失誤。' },
  slowWarm: { name: '慢熟', desc: '第一次見面的客人好感成長慢，熟客則成長很快。' },
  perfectionist: { name: '完美主義', desc: '料理品質高，但做菜時比較容易累。' },
  shy: { name: '怕生', desc: '一開始接待很慢，接待越多次會越順手。' },
  lively: { name: '愛熱鬧', desc: '活動日心情大好，冷清的日子心情會下滑。' },
};

export const MAIDS: MaidDef[] = [
  {
    id: 'koharu',
    name: '小春',
    hair: 0xf2a65a,
    eye: 0x8a4b2a,
    intro: '從開店就在的元氣女僕。不太會做菜，但只要她在，店裡就會亮起來。',
    traits: ['cheerful', 'lively'],
    growth: 'idol',
    skills: { reception: 62, cooking: 28, floor: 50, performance: 55, management: 30 },
    caps: { reception: 95, cooking: 60, floor: 80, performance: 100, management: 60 },
    defaultRole: 'reception',
    lines: {
      greet: ['歡迎回來，主人！', '今天也辛苦了～請進！', '這邊請～位子已經準備好了！'],
      idle: ['今天會有誰來呢～', '嗯～哼～♪', '要不要來想新的招呼方式呀？'],
      tired: ['腳、腳好痠……', '再撐一下下就好……'],
      happy: ['被誇獎了！嘿嘿～', '好開心！'],
      sorry: ['對、對不起！我馬上處理！'],
    },
  },
  {
    id: 'rin',
    name: '凜',
    hair: 0x2c2f4a,
    eye: 0x4a6aa8,
    intro: '前餐廳學徒，對料理有強烈的堅持。說話冷淡，熟了之後其實很照顧人。',
    traits: ['perfectionist', 'slowWarm'],
    growth: 'specialist',
    skills: { reception: 30, cooking: 68, floor: 40, performance: 20, management: 52 },
    caps: { reception: 70, cooking: 100, floor: 70, performance: 50, management: 85 },
    defaultRole: 'kitchen',
    lines: {
      greet: ['……歡迎光臨。', '請坐。菜單在這裡。'],
      idle: ['醬汁的比例……再調一次。', '刀該磨了。', '……'],
      tired: ['……我還可以。', '手有點不穩了。'],
      happy: ['……還不錯。', '嗯，這樣就對了。'],
      sorry: ['……是我的失誤。重做。'],
    },
  },
  {
    id: 'shizuku',
    name: '雫',
    hair: 0xb7c7e8,
    eye: 0x5d7f9e,
    intro: '剛來不久的新人，很怕和陌生人說話，但手腳仔細，總是把桌面擦得最乾淨。',
    traits: ['shy', 'careful'],
    growth: 'allround',
    skills: { reception: 26, cooking: 45, floor: 60, performance: 38, management: 35 },
    caps: { reception: 85, cooking: 80, floor: 90, performance: 90, management: 70 },
    defaultRole: 'floor',
    lines: {
      greet: ['歡、歡迎……回來……', '那個……這邊請……'],
      idle: ['桌子……還有一點水痕。', '（深呼吸）……'],
      tired: ['有點……頭暈……', '我、我沒事……'],
      happy: ['謝謝您……！', '被記住了……好開心。'],
      sorry: ['對不起對不起！'],
    },
  },
];

export const MAID_BY_ID: Record<string, MaidDef> = Object.fromEntries(MAIDS.map((m) => [m.id, m]));

export const MANAGER = {
  id: 'manager',
  name: '店長',
  skills: { reception: 55, cooking: 40, floor: 50, performance: 20, management: 70 },
};
