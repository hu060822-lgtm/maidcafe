import type { ActivityId, DishDef, FurnitureDef, FurnitureType, IngredientDef, StyleKey } from '../types';

export const INGREDIENTS: IngredientDef[] = [
  { id: 'milk', name: '牛奶', price: 20, shop: 'grocer' },
  { id: 'egg', name: '雞蛋', price: 15, shop: 'grocer' },
  { id: 'rice', name: '白米', price: 20, shop: 'grocer' },
  { id: 'tomato', name: '番茄', price: 15, shop: 'grocer' },
  { id: 'cheese', name: '起司', price: 30, shop: 'grocer' },
  { id: 'pasta', name: '義大利麵', price: 20, shop: 'grocer' },
  { id: 'curry', name: '咖哩塊', price: 25, shop: 'grocer' },
  { id: 'coffee', name: '咖啡豆', price: 25, shop: 'general' },
  { id: 'tea', name: '紅茶葉', price: 20, shop: 'general' },
  { id: 'matcha', name: '抹茶粉', price: 35, shop: 'general' },
  { id: 'cocoa', name: '可可粉', price: 25, shop: 'general' },
  { id: 'sugar', name: '砂糖', price: 10, shop: 'general' },
  { id: 'flour', name: '麵粉', price: 10, shop: 'general' },
  { id: 'cream', name: '鮮奶油', price: 30, shop: 'sweets' },
  { id: 'strawberry', name: '草莓', price: 35, shop: 'sweets' },
  { id: 'chocolate', name: '巧克力', price: 30, shop: 'sweets' },
];
export const INGREDIENT_BY_ID: Record<string, IngredientDef> = Object.fromEntries(INGREDIENTS.map((i) => [i.id, i]));

export const DISHES: DishDef[] = [
  // drinks
  { id: 'd_coffee', name: '手沖咖啡', category: 'drink', price: 380, time: 5, quality: 55, ingredients: { coffee: 1 }, station: 'coffee', color: 0x4a2c1a },
  { id: 'd_royaltea', name: '皇家奶茶', category: 'drink', price: 420, time: 6, quality: 55, ingredients: { tea: 1, milk: 1 }, station: 'coffee', color: 0xc89a6a },
  { id: 'd_matcha', name: '抹茶拿鐵', category: 'drink', price: 480, time: 6, quality: 55, ingredients: { matcha: 1, milk: 1 }, station: 'coffee', color: 0x8fbf5a },
  { id: 'd_strawmilk', name: '草莓牛奶', category: 'drink', price: 450, time: 5, quality: 55, ingredients: { strawberry: 1, milk: 1 }, station: 'coffee', color: 0xf5a0b5 },
  { id: 'd_cocoa', name: '熱可可', category: 'drink', price: 400, time: 5, quality: 55, ingredients: { cocoa: 1, milk: 1 }, station: 'coffee', color: 0x6a3a2a },
  // desserts
  { id: 's_pudding', name: '焦糖布丁', category: 'dessert', price: 450, time: 7, quality: 52, ingredients: { egg: 1, milk: 1, sugar: 1 }, station: 'stove', color: 0xf2c95a },
  { id: 's_shortcake', name: '草莓蛋糕', category: 'dessert', price: 580, time: 9, quality: 55, ingredients: { flour: 1, cream: 1, strawberry: 1 }, station: 'stove', color: 0xfff0f0 },
  { id: 's_pancake', name: '鬆餅', category: 'dessert', price: 520, time: 9, quality: 55, ingredients: { flour: 1, egg: 1, milk: 1 }, station: 'stove', color: 0xe0b070 },
  { id: 's_parfait', name: '奶油聖代', category: 'dessert', price: 620, time: 8, quality: 58, ingredients: { cream: 1, strawberry: 1, chocolate: 1 }, station: 'stove', color: 0xfadadd },
  { id: 's_choco', name: '巧克力蛋糕', category: 'dessert', price: 560, time: 9, quality: 55, ingredients: { flour: 1, chocolate: 1, egg: 1 }, station: 'stove', color: 0x4a2a1a },
  // mains
  { id: 'm_omurice', name: '蛋包飯', category: 'main', price: 980, time: 13, quality: 55, ingredients: { egg: 2, rice: 1, tomato: 1 }, station: 'stove', color: 0xf5d040 },
  { id: 'm_napolitan', name: '拿坡里義大利麵', category: 'main', price: 880, time: 12, quality: 55, ingredients: { pasta: 1, tomato: 1, cheese: 1 }, station: 'stove', color: 0xe05a3a },
  { id: 'm_curry', name: '咖哩飯', category: 'main', price: 900, time: 11, quality: 55, ingredients: { rice: 1, curry: 1 }, station: 'stove', color: 0xb5791a },
  { id: 'm_doria', name: '焗烤飯', category: 'main', price: 950, time: 14, quality: 55, ingredients: { rice: 1, cheese: 1, milk: 1 }, station: 'stove', color: 0xf0d8a0 },
  { id: 'm_sandwich', name: '雞蛋三明治', category: 'main', price: 680, time: 8, quality: 55, ingredients: { flour: 1, egg: 1 }, station: 'stove', color: 0xf8e8a0 },
  // signature (unlocked through the 千鶴 storyline)
  { id: 'sig_pudding', name: '千鶴的焦糖布丁', category: 'dessert', price: 680, time: 9, quality: 78, ingredients: { egg: 1, milk: 1, sugar: 1, cream: 1 }, station: 'stove', color: 0xe8a838, signature: true },
];
export const DISH_BY_ID: Record<string, DishDef> = Object.fromEntries(DISHES.map((d) => [d.id, d]));
export const BASE_DISHES = DISHES.filter((d) => !d.signature).map((d) => d.id);
export const MAX_MENU = 9;

export const FURNITURE: Record<FurnitureType, FurnitureDef> = {
  table: { type: 'table', name: '雙人桌', price: 600, footprint: [{ x: -1, z: 0 }, { x: 0, z: 0 }, { x: 1, z: 0 }], style: { warm: 1 }, desc: '一張桌子＋兩張椅子。座位越多，能同時接待的客人越多。' },
  plant: { type: 'plant', name: '盆栽', price: 180, footprint: [{ x: 0, z: 0 }], style: { warm: 2, elegant: 1 }, desc: '讓店裡多一點綠意。' },
  lamp: { type: 'lamp', name: '暖色立燈', price: 220, footprint: [{ x: 0, z: 0 }], style: { warm: 2, retro: 1 }, desc: '柔和的燈光。' },
  gramophone: { type: 'gramophone', name: '古董留聲機', price: 420, footprint: [{ x: 0, z: 0 }], style: { retro: 4 }, desc: '高木爺爺似乎會很喜歡。' },
  plush: { type: 'plush', name: '大型絨毛熊', price: 300, footprint: [{ x: 0, z: 0 }], style: { cute: 4 }, desc: '可愛風格的代表。' },
  vase: { type: 'vase', name: '白瓷花瓶', price: 380, footprint: [{ x: 0, z: 0 }], style: { elegant: 4 }, desc: '高雅的擺飾。' },
  crystal: { type: 'crystal', name: '魔法水晶燈', price: 450, footprint: [{ x: 0, z: 0 }], style: { fantasy: 4 }, desc: '閃閃發光，像故事書裡的道具。' },
  photo: { type: 'photo', name: '拍照區', price: 500, footprint: [{ x: 0, z: 0 }], style: { cute: 3 }, desc: '喜歡拍照的客人會更滿意。' },
  stage: { type: 'stage', name: '小舞台', price: 900, footprint: [{ x: 0, z: 0 }, { x: 1, z: 0 }, { x: 0, z: 1 }, { x: 1, z: 1 }], style: { cute: 2, fantasy: 1 }, desc: '舉辦舞台表演日的必要設備。' },
};

export const STYLE_NAMES: Record<StyleKey, string> = {
  warm: '溫馨家庭風',
  elegant: '高級優雅風',
  cute: '可愛偶像風',
  retro: '復古懷舊風',
  fantasy: '奇幻主題風',
};

export interface ActivityDef {
  id: ActivityId;
  name: string;
  cost: number;
  desc: string;
}
export const ACTIVITIES: Record<ActivityId, ActivityDef> = {
  none: { id: 'none', name: '一般營業', cost: 0, desc: '平常的一天。' },
  costume: { id: 'costume', name: '主題服裝日', cost: 400, desc: '全員換上特別服裝。吸引喜歡可愛風的客人，愛熱鬧的女僕心情大好。' },
  limited: { id: 'limited', name: '限定菜單日', cost: 200, desc: '選一道料理作為限定商品（售價 +25%），喜歡它的客人更容易上門。' },
  stage: { id: 'stage', name: '小型舞台表演日', cost: 300, desc: '需要小舞台。指派一位女僕上台表演，吸引表演觀眾，但喜歡安靜的客人會不太開心。' },
};

export interface ShopItem {
  kind: 'ingredient' | 'furniture';
  id: string;
}
export interface LocationDef {
  id: string;
  name: string;
  desc: string;
  icon: string;
}
export const LOCATIONS: LocationDef[] = [
  { id: 'cafe', name: '女僕咖啡廳「Maiden Parade」', desc: '我們的店。可以先回店裡和女僕們聊聊天。', icon: '☕' },
  { id: 'grocer', name: '山田生鮮', desc: '牛奶、雞蛋、米、番茄、起司、麵條、咖哩塊。', icon: '🥚' },
  { id: 'general', name: '月光雜貨', desc: '咖啡豆、茶葉、粉類，還有各種擺飾與家具。', icon: '🏮' },
  { id: 'sweets', name: '糖霜屋', desc: '鮮奶油、草莓、巧克力。老闆最近好像生意不太好……', icon: '🍰' },
  { id: 'park', name: '向日葵公園', desc: '散步的人很多，常常能遇到新面孔。', icon: '🌳' },
  { id: 'plaza', name: '商店街廣場', desc: '可以發傳單宣傳，提高店鋪人氣。', icon: '📣' },
];

export const DAY_ACTION_POINTS = 4;
export const WAGE_PER_SHIFT = 900;
export const MAINTENANCE = 300;
export const UTILITIES = 400;
export const PARTNER_FEE = 1200;

export const UPGRADE_INFO = {
  secondStove: { name: '第二台爐具', price: 2500, desc: '廚房可以同時做兩道菜。' },
  coffeeMachine: { name: '義式咖啡機', price: 1800, desc: '飲品品質 +10，製作時間縮短。' },
  sofa: { name: '休息室沙發', price: 1500, desc: '女僕休息時恢復疲勞更快，打烊後疲勞恢復更多。' },
} as const;
