import type { CustomerDef } from '../types';

// 12 fixed customers: 6 normal, 4 regulars-to-be, 2 with special storylines.
export const CUSTOMERS: CustomerDef[] = [
  // ---- 一般客人 ----
  {
    id: 'sakura', name: '佐倉同學', kind: 'normal', desc: '放學後會順路過來的高中生，喜歡甜甜的東西。',
    color: 0x6b7fd7, hair: 0x3a2a20, budget: 1000, likes: ['d_strawmilk', 's_pancake'], prefCategory: 'dessert',
    style: 'cute', prefersQuiet: false, lively: true, picky: false, arrival: [0, 70], baseChance: 0.55, patience: 32, metAt: 'start',
  },
  {
    id: 'otsuka', name: '大塚先生', kind: 'normal', desc: '下班趕時間的上班族。最討厭等待。',
    color: 0x4a4f5a, hair: 0x1a1a1a, budget: 1500, likes: ['m_curry', 'd_coffee'], prefCategory: 'main',
    style: null, prefersQuiet: false, lively: false, picky: true, arrival: [40, 130], baseChance: 0.5, patience: 22, metAt: 'start',
  },
  {
    id: 'misaki', name: '美咲小姐', kind: 'normal', desc: '大學生，喜歡拍照分享可愛的甜點。',
    color: 0xe58fb0, hair: 0x5a3a2a, budget: 1300, likes: ['d_matcha', 's_parfait'], prefCategory: 'dessert',
    style: 'cute', prefersQuiet: false, lively: true, picky: false, arrival: [30, 140], baseChance: 0.45, patience: 30, metAt: 'start',
  },
  {
    id: 'kenta', name: '健太', kind: 'normal', desc: '熬夜打電動的大學生，蛋包飯是他的能量來源。',
    color: 0x3f8f6b, hair: 0x2a2a2a, budget: 1300, likes: ['m_omurice', 'd_cocoa'], prefCategory: 'main',
    style: 'fantasy', prefersQuiet: false, lively: true, picky: false, arrival: [90, 190], baseChance: 0.45, patience: 34, metAt: 'start',
  },
  {
    id: 'tachibana', name: '橘太太', kind: 'normal', desc: '附近的主婦，喜歡安靜優雅地喝杯下午茶。',
    color: 0xb08a5a, hair: 0x6a4a3a, budget: 1200, likes: ['d_royaltea', 's_shortcake'], prefCategory: 'dessert',
    style: 'elegant', prefersQuiet: true, lively: false, picky: true, arrival: [0, 90], baseChance: 0.4, patience: 28, metAt: 'start',
  },
  {
    id: 'akiko', name: '秋子阿姨', kind: 'normal', desc: '商店街洗衣店的老闆娘，消息靈通。',
    color: 0x9a6ab0, hair: 0x8a8a8a, budget: 1100, likes: ['d_coffee', 'm_sandwich'], prefCategory: 'main',
    style: 'retro', prefersQuiet: false, lively: false, picky: false, arrival: [20, 120], baseChance: 0.4, patience: 36, metAt: 'start',
  },
  // ---- 可培養的熟客 ----
  {
    id: 'hayase', name: '早瀨先生', kind: 'regular', desc: '在家接案的工程師，總是帶著筆電。',
    color: 0x5a7a9a, hair: 0x2a2020, budget: 1600, likes: ['d_coffee', 'm_napolitan'], prefCategory: 'main',
    style: 'retro', prefersQuiet: true, lively: false, picky: false, arrival: [60, 170], baseChance: 0.6, patience: 34, metAt: 'start',
  },
  {
    id: 'takagi', name: '高木爺爺', kind: 'regular', desc: '退休的老鐘錶師傅，從這間店還很熱鬧時就常來。',
    color: 0x7a6040, hair: 0xdddddd, budget: 1400, likes: ['m_doria', 'd_coffee'], prefCategory: 'main',
    style: 'retro', prefersQuiet: true, lively: false, picky: false, arrival: [0, 60], baseChance: 0.65, patience: 45, metAt: 'start',
  },
  {
    id: 'mayu', name: '小林真由', kind: 'regular', desc: '在公園寫生的插畫家，喜歡可愛又有故事的店。',
    color: 0xd9a0c8, hair: 0x4a2a3a, budget: 1300, likes: ['s_choco', 'd_cocoa'], prefCategory: 'dessert',
    style: 'cute', prefersQuiet: false, lively: false, picky: false, arrival: [50, 160], baseChance: 0.6, patience: 36, metAt: 'park',
  },
  {
    id: 'endo', name: '遠藤', kind: 'regular', desc: '在廣場發傳單時認識的地下偶像粉絲，熱愛舞台。',
    color: 0xe0503a, hair: 0x202020, budget: 1500, likes: ['m_omurice', 'd_strawmilk'], prefCategory: 'main',
    style: 'cute', prefersQuiet: false, lively: true, picky: false, arrival: [80, 180], baseChance: 0.45, patience: 34, metAt: 'plaza',
  },
  // ---- 特殊客人 ----
  {
    id: 'chizuru', name: '千鶴奶奶', kind: 'special', desc: '在公園餵鴿子的老奶奶。年輕時似乎是很有名的甜點師。',
    color: 0x7a8a6a, hair: 0xeeeeee, budget: 1200, likes: ['s_pudding', 'd_royaltea'], prefCategory: 'dessert',
    style: 'warm', prefersQuiet: true, lively: false, picky: true, arrival: [10, 100], baseChance: 0.7, patience: 40, metAt: 'park', minDay: 2,
    story: 'pudding',
  },
  {
    id: 'amamiya', name: '雨宮先生', kind: 'special', desc: '總是坐在角落寫稿的男人。似乎在寫一部小說。',
    color: 0x3a4a3a, hair: 0x3a3a3a, budget: 1500, likes: ['d_coffee', 's_choco'], prefCategory: 'drink',
    style: 'retro', prefersQuiet: true, lively: false, picky: false, arrival: [70, 160], baseChance: 0.7, patience: 40, metAt: 'start', minDay: 2,
    story: 'novel',
  },
];

export const CUSTOMER_BY_ID: Record<string, CustomerDef> = Object.fromEntries(CUSTOMERS.map((c) => [c.id, c]));

// Visit thresholds (scaled down for MVP pacing; design doc uses 5 / 10).
export const REGULAR_VISITS = 4;
export const REGULAR_LOYALTY = 55;
export const FRIEND_VISITS = 6;
export const FRIEND_LOYALTY = 70;
