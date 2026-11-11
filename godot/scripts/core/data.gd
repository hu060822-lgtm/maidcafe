## Static game content. Everything here is original.
## Pure data: no scene access, safe to load in headless tests.
extends RefCounted

const SKILLS := ["reception", "cooking", "floor", "performance", "management"]
const SKILL_NAMES := {"reception": "接待", "cooking": "料理", "floor": "外場", "performance": "表演", "management": "管理"}
const ROLE_NAMES := {"reception": "接待", "kitchen": "廚房", "floor": "外場", "stage": "舞台", "support": "支援", "off": "休假"}

# ------------------------------------------------------------------ calendar
const SEASON_DAYS := 14
const YEAR_DAYS := 56
const SEASONS := ["spring", "summer", "autumn", "winter"]
const SEASON_NAMES := {"spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"}
const WEEKDAYS := ["一", "二", "三", "四", "五", "六", "日"]

static func weekday(day: int) -> int:
	return (day - 1) % 7

static func season(day: int) -> String:
	return SEASONS[int(((day - 1) % YEAR_DAYS) / SEASON_DAYS)]

static func season_day(day: int) -> int:
	return ((day - 1) % SEASON_DAYS) + 1

static func date_label(day: int) -> String:
	return "%s季第 %d 天（星期%s）" % [SEASON_NAMES[season(day)], season_day(day), WEEKDAYS[weekday(day)]]

# ------------------------------------------------------------------ traits & habits
const TRAITS := {
	"cheerful": {"name": "開朗", "desc": "附近同事的心情會慢慢變好。"},
	"careful": {"name": "細心", "desc": "送餐、點餐比較不容易出錯。"},
	"slow_warm": {"name": "慢熟", "desc": "對新客人好感成長慢，對熟客成長快。"},
	"perfectionist": {"name": "完美主義", "desc": "料理品質高，但做菜容易累。"},
	"shy": {"name": "怕生", "desc": "一開始接待很慢，接待越多次越順手。"},
	"lively": {"name": "愛熱鬧", "desc": "熱鬧的日子心情好，冷清時心情下滑。"},
	"bookish": {"name": "愛書", "desc": "空檔時喜歡到書架旁讀書，會和愛看書的客人聊起來。"},
	"impatient": {"name": "急性子", "desc": "動作快，但看不慣慢吞吞的同事。"},
	"caring": {"name": "愛照顧人", "desc": "看到同事忙不過來，會主動去幫忙。"},
	"laid_back": {"name": "慢步調", "desc": "動作慢一點，但不容易累，也不容易被忙碌影響心情。"},
}

## Habits form from repeated behaviour. Strength 0-100; behaviour choices add strength, days decay it.
const HABITS := {
	"tidy": {"name": "整理控", "desc": "營業前或空檔會主動整理桌面、照顧花瓶。"},
	"read": {"name": "閱讀時光", "desc": "休息時喜歡到書架旁看書。"},
	"help": {"name": "熱心補位", "desc": "同事忙不過來時，常常主動去幫忙。"},
	"stay_late": {"name": "留到最後", "desc": "打烊後常常一個人留在店裡。"},
	"chat": {"name": "聊天王", "desc": "空檔時很愛找人聊天。"},
	"regular_talk": {"name": "熟客的朋友", "desc": "會主動和熟客聊幾句。"},
	"window": {"name": "看窗外", "desc": "空檔時喜歡站在窗邊發呆。"},
}

# ------------------------------------------------------------------ maids
const MAIDS := {
	"koharu": {
		"name": "小春", "hair": "f2a65a", "intro": "從開店就在的元氣女僕。不太會做菜，但只要她在，店裡就會亮起來。",
		"traits": ["cheerful", "lively"], "growth": "idol", "default_role": "reception", "birthday": 10, "gift": "accessory",
		"skills": {"reception": 62, "cooking": 28, "floor": 50, "performance": 55, "management": 30},
		"caps": {"reception": 95, "cooking": 60, "floor": 80, "performance": 100, "management": 60},
		"seed_habits": {"chat": 30, "regular_talk": 20},
		"lines": {
			"greet": ["歡迎回來，主人！", "今天也辛苦了～請進！", "這邊請～位子準備好了！"],
			"idle": ["今天會有誰來呢～", "嗯～哼～♪", "要不要想個新的招呼方式？"],
			"tired": ["腳、腳好痠……", "再撐一下下就好……"],
			"happy": ["被誇獎了！嘿嘿～", "好開心！"],
			"sorry": ["對、對不起！我馬上處理！"],
		},
	},
	"rin": {
		"name": "凜", "hair": "2c2f4a", "intro": "前餐廳學徒，對料理有強烈的堅持。說話冷淡，熟了之後其實很照顧人。",
		"traits": ["perfectionist", "slow_warm"], "growth": "specialist", "default_role": "kitchen", "birthday": 19, "gift": "tool",
		"skills": {"reception": 30, "cooking": 68, "floor": 40, "performance": 20, "management": 52},
		"caps": {"reception": 70, "cooking": 100, "floor": 70, "performance": 50, "management": 85},
		"seed_habits": {"stay_late": 25},
		"lines": {
			"greet": ["……歡迎光臨。", "請坐。菜單在這裡。"],
			"idle": ["醬汁的比例……再調一次。", "刀該磨了。", "……"],
			"tired": ["……我還可以。", "手有點不穩了。"],
			"happy": ["……還不錯。", "嗯，這樣就對了。"],
			"sorry": ["……是我的失誤。重做。"],
		},
	},
	"shizuku": {
		"name": "雫", "hair": "b7c7e8", "intro": "剛來不久的新人，很怕和陌生人說話，但手腳仔細，總是把桌面擦得最乾淨。",
		"traits": ["shy", "careful"], "growth": "allround", "default_role": "floor", "birthday": 5, "gift": "sweets",
		"skills": {"reception": 26, "cooking": 45, "floor": 60, "performance": 38, "management": 35},
		"caps": {"reception": 85, "cooking": 80, "floor": 90, "performance": 90, "management": 70},
		"seed_habits": {"tidy": 30, "window": 15},
		"lines": {
			"greet": ["歡、歡迎……回來……", "那個……這邊請……"],
			"idle": ["桌子……還有一點水痕。", "（深呼吸）……"],
			"tired": ["有點……頭暈……", "我、我沒事……"],
			"happy": ["謝謝您……！", "被記住了……好開心。"],
			"sorry": ["對不起對不起！"],
		},
	},
	"yukino": {
		"name": "雪乃", "hair": "e8e4f0", "intro": "總是帶著一本書的安靜女生。冷靜可靠，擅長處理突發狀況，講話慢條斯理。",
		"traits": ["bookish", "careful"], "growth": "allround", "default_role": "reception", "birthday": 36, "gift": "book",
		"skills": {"reception": 48, "cooking": 40, "floor": 45, "performance": 25, "management": 62},
		"caps": {"reception": 85, "cooking": 70, "floor": 75, "performance": 55, "management": 95},
		"seed_habits": {"read": 40, "tidy": 15},
		"lines": {
			"greet": ["歡迎回來。今天想坐哪裡呢？", "外面冷吧？這邊請。"],
			"idle": ["這本書的結局……", "（翻頁的聲音）", "花瓶的水該換了。"],
			"tired": ["……稍微有點累了呢。", "我休息一下就好。"],
			"happy": ["謝謝。我會記住的。", "今天是好日子。"],
			"sorry": ["非常抱歉，我立刻處理。"],
		},
		"recruit": {"location": "general", "visits": 2, "popularity": 22},
	},
	"kaede": {
		"name": "楓", "hair": "c84a2a", "intro": "前田徑隊員，腳程全店最快。性子很急，看不慣拖拖拉拉，但對夥伴非常講義氣。",
		"traits": ["impatient", "caring"], "growth": "specialist", "default_role": "floor", "birthday": 45, "gift": "sports",
		"skills": {"reception": 40, "cooking": 30, "floor": 70, "performance": 45, "management": 35},
		"caps": {"reception": 75, "cooking": 55, "floor": 100, "performance": 80, "management": 65},
		"seed_habits": {"help": 35},
		"lines": {
			"greet": ["歡迎！這邊這邊！", "來啦！位子馬上好！"],
			"idle": ["好閒喔～有沒有事可以做？", "（原地小跑步）"],
			"tired": ["呼……呼……還沒完嗎……", "腿……有點抖。"],
			"happy": ["好耶！", "就是這個節奏！"],
			"sorry": ["抱歉！我太急了！"],
		},
		"recruit": {"location": "plaza", "visits": 2, "popularity": 30},
	},
	# ---- Living Hearts: more maids who can join
	"tsumugi": {
		"name": "紬", "hair": "a07858", "intro": "在月光雜貨幫忙做手作小物的女生。說話輕聲細語，手很巧，總是默默照顧身邊的人。",
		"traits": ["caring", "careful"], "growth": "allround", "default_role": "floor", "birthday": 27, "gift": "craft",
		"skills": {"reception": 42, "cooking": 44, "floor": 52, "performance": 30, "management": 40},
		"caps": {"reception": 85, "cooking": 80, "floor": 85, "performance": 60, "management": 75},
		"seed_habits": {"tidy": 30, "help": 20},
		"lines": {
			"greet": ["歡迎回來。外套可以交給我喔。", "這邊請，椅子已經擦好了。"],
			"idle": ["這個桌布的邊，有點脫線了呢。", "（從口袋拿出針線）……", "大家都還好嗎？"],
			"tired": ["我沒事……只是手有點痠。", "稍微坐一下就好。"],
			"happy": ["能幫上忙就好。", "嘿嘿，謝謝。"],
			"sorry": ["對不起，我馬上弄好。"],
		},
		"recruit": {"location": "general", "visits": 4, "popularity": 28, "requires": "tsukimi_collab"},
	},
	"chinatsu": {
		"name": "千夏", "hair": "4a7ac8", "intro": "奏的學妹，音樂系的學生。在人前會緊張到說不出話，一拿起吉他就像換了一個人。",
		"traits": ["shy", "lively"], "growth": "idol", "default_role": "floor", "birthday": 50, "gift": "music",
		"skills": {"reception": 32, "cooking": 30, "floor": 45, "performance": 60, "management": 28},
		"caps": {"reception": 80, "cooking": 55, "floor": 75, "performance": 100, "management": 55},
		"seed_habits": {"window": 20, "stay_late": 15},
		"lines": {
			"greet": ["歡、歡迎回來！", "這邊……請！"],
			"idle": ["（手指在托盤上敲著節奏）", "這段旋律……要記下來。", "啦～啦啦～"],
			"tired": ["腦袋裡的歌停了……", "有點撐不住了……"],
			"happy": ["好像聽到掌聲了！", "今天的心情是大調！"],
			"sorry": ["對不起！我又分心了！"],
		},
		"recruit": {"location": "plaza", "visits": 4, "popularity": 32, "requires": "kanade_collab"},
	},
	"aoi": {
		"name": "葵", "hair": "2a6a5a", "intro": "從廣場旁的連鎖咖啡店辭職的咖啡師。做事俐落、標準很高，想泡出讓人記住的咖啡。",
		"traits": ["perfectionist", "impatient"], "growth": "specialist", "default_role": "kitchen", "birthday": 14, "gift": "coffee",
		"skills": {"reception": 40, "cooking": 55, "floor": 48, "performance": 22, "management": 45},
		"caps": {"reception": 75, "cooking": 95, "floor": 75, "performance": 45, "management": 80},
		"seed_habits": {"stay_late": 20, "tidy": 15},
		"lines": {
			"greet": ["歡迎光臨。今天想喝什麼？", "請坐，我馬上來點餐。"],
			"idle": ["研磨度再細一點……", "（擦著咖啡杯）", "那家店的豆子，烘太深了。"],
			"tired": ["……手腕好重。", "還差一點。"],
			"happy": ["這杯，及格了。", "客人喝完了，一滴不剩。"],
			"sorry": ["是我的錯，重新做一杯。"],
		},
		"recruit": {"location": "plaza", "visits": 3, "popularity": 35, "requires": "new_shop_seen"},
	},
	"hiyori": {
		"name": "日和", "hair": "f0d878", "intro": "常在公園花圃午睡的女生。做什麼都慢半拍，但只要她在，連忙碌的晚上都會變得悠閒一點。",
		"traits": ["laid_back", "cheerful"], "growth": "allround", "default_role": "reception", "birthday": 31, "gift": "plant",
		"skills": {"reception": 50, "cooking": 36, "floor": 40, "performance": 35, "management": 30},
		"caps": {"reception": 90, "cooking": 70, "floor": 70, "performance": 75, "management": 60},
		"seed_habits": {"window": 30, "chat": 20},
		"lines": {
			"greet": ["歡迎回來～慢慢來沒關係喔。", "外面天氣很好吧～這邊請～"],
			"idle": ["呼啊……（打呵欠）", "窗外的雲，像一隻貓。", "花該澆水了～"],
			"tired": ["好想睡……", "可以……瞇一下下嗎……"],
			"happy": ["今天是好日子呢～", "嘿嘿～"],
			"sorry": ["啊、對不起～我馬上～"],
		},
		"recruit": {"location": "park", "visits": 3, "popularity": 30},
	},
}
const STARTING_MAIDS := ["koharu", "rin", "shizuku"]
const MAX_STAFF := 6
const MANAGER_SKILLS := {"reception": 55, "cooking": 40, "floor": 50, "performance": 20, "management": 70}

# ------------------------------------------------------------------ customers
# weekdays: 0=一 ... 6=日 (preferred days). seat: preferred seat kind.
# behaviors: reader, photographer, asks_maid, waits_friend, curious_new, observer
const CUSTOMERS := {
	"sakura": {"name": "佐倉同學", "kind": "normal", "desc": "放學後順路過來的高中生，喜歡甜甜的東西。", "color": "6b7fd7", "hair": "3a2a20",
		"budget": 1000, "likes": ["d_strawmilk", "s_pancake"], "pref": "dessert", "style": "cute", "quiet": false, "lively": true, "picky": false,
		"arrival": [0, 70], "chance": 0.5, "patience": 32, "met": "start", "weekdays": [0, 1, 2, 3, 4], "seat": "any",
		"behaviors": ["photographer", "curious_new"], "ambience": "pop", "events": ["costume", "stage"]},
	"otsuka": {"name": "大塚先生", "kind": "normal", "desc": "下班趕時間的上班族。最討厭等待。", "color": "4a4f5a", "hair": "1a1a1a",
		"budget": 1500, "likes": ["m_curry", "d_coffee"], "pref": "main", "style": "", "quiet": false, "lively": false, "picky": true,
		"arrival": [40, 130], "chance": 0.5, "patience": 22, "met": "start", "weekdays": [0, 1, 2, 3, 4], "seat": "any",
		"behaviors": [], "ambience": "", "events": []},
	"misaki": {"name": "美咲小姐", "kind": "normal", "desc": "大學生，喜歡拍照分享可愛的甜點。", "color": "e58fb0", "hair": "5a3a2a",
		"budget": 1300, "likes": ["d_matcha", "s_parfait"], "pref": "dessert", "style": "cute", "quiet": false, "lively": true, "picky": false,
		"arrival": [30, 140], "chance": 0.45, "patience": 30, "met": "start", "weekdays": [4, 5, 6], "seat": "window",
		"behaviors": ["photographer"], "ambience": "pop", "events": ["costume", "limited"]},
	"kenta": {"name": "健太", "kind": "normal", "desc": "熬夜打電動的大學生，蛋包飯是他的能量來源。", "color": "3f8f6b", "hair": "2a2a2a",
		"budget": 1300, "likes": ["m_omurice", "d_cocoa"], "pref": "main", "style": "fantasy", "quiet": false, "lively": true, "picky": false,
		"arrival": [90, 190], "chance": 0.45, "patience": 34, "met": "start", "weekdays": [], "seat": "any",
		"behaviors": ["curious_new"], "ambience": "", "events": ["stage"]},
	"tachibana": {"name": "橘太太", "kind": "normal", "desc": "附近的主婦，喜歡安靜優雅地喝杯下午茶。", "color": "b08a5a", "hair": "6a4a3a",
		"budget": 1200, "likes": ["d_royaltea", "s_shortcake"], "pref": "dessert", "style": "elegant", "quiet": true, "lively": false, "picky": true,
		"arrival": [0, 90], "chance": 0.4, "patience": 28, "met": "start", "weekdays": [1, 3], "seat": "quiet",
		"behaviors": ["observer"], "ambience": "classical", "events": []},
	"akiko": {"name": "秋子阿姨", "kind": "normal", "desc": "商店街洗衣店的老闆娘，消息靈通，什麼都想知道。", "color": "9a6ab0", "hair": "8a8a8a",
		"budget": 1100, "likes": ["d_coffee", "m_sandwich"], "pref": "main", "style": "retro", "quiet": false, "lively": false, "picky": false,
		"arrival": [20, 120], "chance": 0.4, "patience": 36, "met": "start", "weekdays": [], "seat": "any",
		"behaviors": ["observer", "asks_maid"], "ambience": "", "events": ["meetup"]},
	"hayase": {"name": "早瀨先生", "kind": "regular", "desc": "在家接案的工程師，總是帶著筆電坐窗邊。", "color": "5a7a9a", "hair": "2a2020",
		"budget": 1600, "likes": ["d_coffee", "m_napolitan"], "pref": "main", "style": "retro", "quiet": true, "lively": false, "picky": false,
		"arrival": [60, 170], "chance": 0.55, "patience": 34, "met": "start", "weekdays": [1, 3], "seat": "window",
		"behaviors": [], "ambience": "jazz", "events": []},
	"takagi": {"name": "高木爺爺", "kind": "regular", "desc": "退休的老鐘錶師傅，從這間店還很熱鬧時就常來。", "color": "7a6040", "hair": "dddddd",
		"budget": 1400, "likes": ["m_doria", "d_coffee"], "pref": "main", "style": "retro", "quiet": true, "lively": false, "picky": false,
		"arrival": [0, 60], "chance": 0.6, "patience": 45, "met": "start", "weekdays": [0, 2, 4], "seat": "quiet",
		"behaviors": ["reader", "observer"], "ambience": "jazz", "events": []},
	"mayu": {"name": "小林真由", "kind": "regular", "desc": "在公園寫生的插畫家，喜歡可愛又有故事的店。", "color": "d9a0c8", "hair": "4a2a3a",
		"budget": 1300, "likes": ["s_choco", "d_cocoa"], "pref": "dessert", "style": "cute", "quiet": false, "lively": false, "picky": false,
		"arrival": [50, 160], "chance": 0.55, "patience": 36, "met": "park", "weekdays": [2, 5], "seat": "window",
		"behaviors": ["observer", "photographer"], "ambience": "", "events": ["costume"]},
	"endo": {"name": "遠藤", "kind": "regular", "desc": "在廣場認識的地下偶像粉絲，熱愛舞台。", "color": "e0503a", "hair": "202020",
		"budget": 1500, "likes": ["m_omurice", "d_strawmilk"], "pref": "main", "style": "cute", "quiet": false, "lively": true, "picky": false,
		"arrival": [80, 180], "chance": 0.45, "patience": 34, "met": "plaza", "weekdays": [5, 6], "seat": "stage",
		"behaviors": ["asks_maid"], "ambience": "pop", "events": ["stage", "costume"]},
	"chizuru": {"name": "千鶴奶奶", "kind": "special", "desc": "在公園餵鴿子的老奶奶。年輕時似乎是很有名的甜點師。", "color": "7a8a6a", "hair": "eeeeee",
		"budget": 1200, "likes": ["s_pudding", "d_royaltea"], "pref": "dessert", "style": "warm", "quiet": true, "lively": false, "picky": true,
		"arrival": [10, 100], "chance": 0.65, "patience": 40, "met": "park", "min_day": 2, "story": "pudding", "weekdays": [], "seat": "quiet",
		"behaviors": ["observer"], "ambience": "classical", "events": []},
	"amamiya": {"name": "雨宮先生", "kind": "special", "desc": "總是坐在角落寫稿的男人。似乎在寫一部小說。", "color": "3a4a3a", "hair": "3a3a3a",
		"budget": 1500, "likes": ["d_coffee", "s_choco"], "pref": "drink", "style": "retro", "quiet": true, "lively": false, "picky": false,
		"arrival": [70, 160], "chance": 0.6, "patience": 40, "met": "start", "min_day": 2, "story": "novel", "weekdays": [], "seat": "quiet",
		"behaviors": ["reader"], "ambience": "jazz", "events": []},
	# ---- expansion customers ----
	"shiraishi": {"name": "白石小姐", "kind": "regular", "desc": "在月光雜貨認識的圖書館員，週二、週四下班後一定會來看書。", "color": "6a8a9a", "hair": "1a1a2a",
		"budget": 1100, "likes": ["d_royaltea", "s_pudding"], "pref": "drink", "style": "elegant", "quiet": true, "lively": false, "picky": false,
		"arrival": [40, 120], "chance": 0.5, "patience": 40, "met": "general", "weekdays": [1, 3], "seat": "bookshelf",
		"behaviors": ["reader"], "ambience": "classical", "events": []},
	"nanami": {"name": "七海", "kind": "normal", "desc": "在廣場拍照的美食攝影部落客。她的貼文能讓一道料理一夕爆紅。", "color": "f0b040", "hair": "6a3a1a",
		"budget": 1400, "likes": ["s_parfait", "s_shortcake"], "pref": "dessert", "style": "cute", "quiet": false, "lively": true, "picky": true,
		"arrival": [20, 150], "chance": 0.35, "patience": 30, "met": "plaza", "weekdays": [5, 6], "seat": "window",
		"behaviors": ["photographer", "curious_new"], "ambience": "pop", "events": ["limited", "seasonal"]},
	"morishita": {"name": "森下先生", "kind": "normal", "desc": "大塚先生的同事。週五會被拖來一起吃晚餐。", "color": "4a6a5a", "hair": "2a2a1a",
		"budget": 1400, "likes": ["m_napolitan", "d_coffee"], "pref": "main", "style": "", "quiet": false, "lively": false, "picky": false,
		"arrival": [60, 150], "chance": 0.3, "patience": 30, "met": "referral", "weekdays": [4], "seat": "any",
		"behaviors": ["waits_friend"], "ambience": "", "events": [], "companion": "otsuka"},
	"riku": {"name": "小陸", "kind": "normal", "desc": "高木爺爺的孫子，小學生。週末會被爺爺帶來吃布丁。", "color": "5ab0e0", "hair": "3a2a1a",
		"budget": 800, "likes": ["s_pudding", "d_strawmilk"], "pref": "dessert", "style": "fantasy", "quiet": false, "lively": true, "picky": false,
		"arrival": [0, 60], "chance": 0.6, "patience": 25, "met": "referral", "weekdays": [5, 6], "seat": "any",
		"behaviors": ["curious_new", "observer"], "ambience": "", "events": ["stage"], "companion": "takagi"},
	"kasuga_m": {"name": "春日先生", "kind": "normal", "desc": "在公園散步的夫妻中的先生。不太說話，總是幫太太拉椅子。", "color": "5a5a7a", "hair": "4a4a4a",
		"budget": 1500, "likes": ["d_coffee", "m_doria"], "pref": "main", "style": "warm", "quiet": true, "lively": false, "picky": false,
		"arrival": [30, 140], "chance": 0.45, "patience": 35, "met": "park", "min_day": 3, "weekdays": [6], "seat": "sofa",
		"behaviors": [], "ambience": "jazz", "events": [], "companion": "kasuga_f"},
	"kasuga_f": {"name": "春日太太", "kind": "normal", "desc": "春日先生的太太。結婚三十年，每週日的約會從不缺席。", "color": "c07a8a", "hair": "6a5a5a",
		"budget": 1300, "likes": ["d_royaltea", "s_shortcake"], "pref": "dessert", "style": "warm", "quiet": true, "lively": false, "picky": false,
		"arrival": [30, 140], "chance": 0.45, "patience": 35, "met": "park", "min_day": 3, "weekdays": [6], "seat": "sofa",
		"behaviors": ["photographer"], "ambience": "jazz", "events": [], "companion": "kasuga_m"},
}

## Static social relations between customers. Emergent ones are added at runtime.
const CUSTOMER_RELATIONS := [
	{"a": "otsuka", "b": "morishita", "type": "coworker"},
	{"a": "takagi", "b": "riku", "type": "family"},
	{"a": "kasuga_m", "b": "kasuga_f", "type": "couple"},
	{"a": "sakura", "b": "misaki", "type": "interest"},
	{"a": "mayu", "b": "nanami", "type": "interest"},
	{"a": "akiko", "b": "tachibana", "type": "friend"},
]
const RELATION_NAMES := {"friend": "朋友", "couple": "夫妻", "coworker": "同事", "family": "家人", "interest": "同好", "acquaintance": "店裡認識的熟客"}

## Who can introduce whom (referral unlocks): when `from` is loyal enough, they bring `to`.
const REFERRALS := {"morishita": {"from": "otsuka", "loyalty": 45}, "riku": {"from": "takagi", "loyalty": 45}}

const REGULAR_VISITS := 5
const REGULAR_LOYALTY := 55
const FRIEND_VISITS := 6
const FRIEND_LOYALTY := 70

# ------------------------------------------------------------------ food
const INGREDIENTS := {
	"milk": {"name": "牛奶", "price": 20, "shop": "grocer"},
	"egg": {"name": "雞蛋", "price": 15, "shop": "grocer"},
	"rice": {"name": "白米", "price": 20, "shop": "grocer"},
	"tomato": {"name": "番茄", "price": 15, "shop": "grocer"},
	"cheese": {"name": "起司", "price": 30, "shop": "grocer"},
	"pasta": {"name": "義大利麵", "price": 20, "shop": "grocer"},
	"curry": {"name": "咖哩塊", "price": 25, "shop": "grocer"},
	"coffee": {"name": "咖啡豆", "price": 25, "shop": "general"},
	"tea": {"name": "紅茶葉", "price": 20, "shop": "general"},
	"matcha": {"name": "抹茶粉", "price": 35, "shop": "general"},
	"cocoa": {"name": "可可粉", "price": 25, "shop": "general"},
	"sugar": {"name": "砂糖", "price": 10, "shop": "general"},
	"flour": {"name": "麵粉", "price": 10, "shop": "general"},
	"cream": {"name": "鮮奶油", "price": 30, "shop": "sweets"},
	"strawberry": {"name": "草莓", "price": 35, "shop": "sweets"},
	"chocolate": {"name": "巧克力", "price": 30, "shop": "sweets"},
	# seasonal / special (sold only when the condition holds)
	"sakura": {"name": "鹽漬櫻花", "price": 40, "shop": "grocer", "season": "spring"},
	"icecream": {"name": "香草冰淇淋", "price": 35, "shop": "sweets", "season": "summer"},
	"chestnut": {"name": "栗子", "price": 45, "shop": "grocer", "season": "autumn"},
	"apple": {"name": "蘋果", "price": 25, "shop": "grocer", "season": "winter"},
	"farm_egg": {"name": "山田家的放牧蛋", "price": 30, "shop": "grocer", "flag": "yamada_eggs"},
}

const DISHES := {
	"d_coffee": {"name": "手沖咖啡", "cat": "drink", "price": 380, "time": 5, "q": 55, "ing": {"coffee": 1}, "station": "coffee", "color": "4a2c1a"},
	"d_royaltea": {"name": "皇家奶茶", "cat": "drink", "price": 420, "time": 6, "q": 55, "ing": {"tea": 1, "milk": 1}, "station": "coffee", "color": "c89a6a"},
	"d_matcha": {"name": "抹茶拿鐵", "cat": "drink", "price": 480, "time": 6, "q": 55, "ing": {"matcha": 1, "milk": 1}, "station": "coffee", "color": "8fbf5a"},
	"d_strawmilk": {"name": "草莓牛奶", "cat": "drink", "price": 450, "time": 5, "q": 55, "ing": {"strawberry": 1, "milk": 1}, "station": "coffee", "color": "f5a0b5"},
	"d_cocoa": {"name": "熱可可", "cat": "drink", "price": 400, "time": 5, "q": 55, "ing": {"cocoa": 1, "milk": 1}, "station": "coffee", "color": "6a3a2a"},
	"s_pudding": {"name": "焦糖布丁", "cat": "dessert", "price": 450, "time": 7, "q": 52, "ing": {"egg": 1, "milk": 1, "sugar": 1}, "station": "stove", "color": "f2c95a"},
	"s_shortcake": {"name": "草莓蛋糕", "cat": "dessert", "price": 580, "time": 9, "q": 55, "ing": {"flour": 1, "cream": 1, "strawberry": 1}, "station": "stove", "color": "fff0f0"},
	"s_pancake": {"name": "鬆餅", "cat": "dessert", "price": 520, "time": 9, "q": 55, "ing": {"flour": 1, "egg": 1, "milk": 1}, "station": "stove", "color": "e0b070"},
	"s_parfait": {"name": "奶油聖代", "cat": "dessert", "price": 620, "time": 8, "q": 58, "ing": {"cream": 1, "strawberry": 1, "chocolate": 1}, "station": "stove", "color": "fadadd"},
	"s_choco": {"name": "巧克力蛋糕", "cat": "dessert", "price": 560, "time": 9, "q": 55, "ing": {"flour": 1, "chocolate": 1, "egg": 1}, "station": "stove", "color": "4a2a1a"},
	"m_omurice": {"name": "蛋包飯", "cat": "main", "price": 980, "time": 13, "q": 55, "ing": {"egg": 2, "rice": 1, "tomato": 1}, "station": "stove", "color": "f5d040"},
	"m_napolitan": {"name": "拿坡里義大利麵", "cat": "main", "price": 880, "time": 12, "q": 55, "ing": {"pasta": 1, "tomato": 1, "cheese": 1}, "station": "stove", "color": "e05a3a"},
	"m_curry": {"name": "咖哩飯", "cat": "main", "price": 900, "time": 11, "q": 55, "ing": {"rice": 1, "curry": 1}, "station": "stove", "color": "b5791a"},
	"m_doria": {"name": "焗烤飯", "cat": "main", "price": 950, "time": 14, "q": 55, "ing": {"rice": 1, "cheese": 1, "milk": 1}, "station": "stove", "color": "f0d8a0"},
	"m_sandwich": {"name": "雞蛋三明治", "cat": "main", "price": 680, "time": 8, "q": 55, "ing": {"flour": 1, "egg": 1}, "station": "stove", "color": "f8e8a0"},
	# unlockable
	"sig_pudding": {"name": "千鶴的焦糖布丁", "cat": "dessert", "price": 680, "time": 9, "q": 78, "ing": {"egg": 1, "milk": 1, "sugar": 1, "cream": 1}, "station": "stove", "color": "e8a838", "signature": true},
	"sp_omurice": {"name": "放牧蛋特製蛋包飯", "cat": "main", "price": 1280, "time": 14, "q": 74, "ing": {"farm_egg": 2, "rice": 1, "tomato": 1}, "station": "stove", "color": "f8c020", "signature": true},
	"collab_cake": {"name": "糖霜屋聯名蛋糕", "cat": "dessert", "price": 720, "time": 8, "q": 70, "ing": {"flour": 1, "cream": 1, "strawberry": 1, "sugar": 1}, "station": "stove", "color": "ffd0e0", "collab": true},
	"sea_sakura": {"name": "櫻花拿鐵", "cat": "drink", "price": 520, "time": 6, "q": 62, "ing": {"sakura": 1, "milk": 1}, "station": "coffee", "color": "f8c8d8", "season": "spring"},
	"sea_soda": {"name": "冰淇淋蘇打", "cat": "drink", "price": 550, "time": 5, "q": 62, "ing": {"icecream": 1, "sugar": 1}, "station": "coffee", "color": "60d0a0", "season": "summer"},
	"sea_montblanc": {"name": "栗子蒙布朗", "cat": "dessert", "price": 680, "time": 10, "q": 64, "ing": {"chestnut": 1, "cream": 1, "flour": 1}, "station": "stove", "color": "c8a070", "season": "autumn"},
	# story rewards (story_data.gd STORY_DISHES)
	"st_heart_omurice": {"name": "愛心蛋包飯", "cat": "main", "price": 1080, "time": 13, "q": 66, "ing": {"egg": 2, "rice": 1, "tomato": 1}, "station": "stove", "color": "ff8a7a", "story": true},
	"st_rose_tea": {"name": "玫瑰蜜奶茶", "cat": "drink", "price": 520, "time": 6, "q": 64, "ing": {"tea": 1, "milk": 1, "sugar": 1}, "station": "coffee", "color": "f2a7bb", "story": true},
	"st_lace_crepe": {"name": "蕾絲可麗餅", "cat": "dessert", "price": 640, "time": 8, "q": 66, "ing": {"flour": 1, "egg": 1, "cream": 1, "strawberry": 1}, "station": "stove", "color": "fbe3c8", "story": true},
	"st_parade_parfait": {"name": "遊行聖代", "cat": "dessert", "price": 820, "time": 9, "q": 76, "ing": {"cream": 1, "strawberry": 1, "chocolate": 1, "sugar": 1}, "station": "stove", "color": "ffb3cf", "story": true},
	"sea_appletea": {"name": "熱蘋果茶", "cat": "drink", "price": 480, "time": 6, "q": 62, "ing": {"apple": 1, "tea": 1}, "station": "coffee", "color": "d08040", "season": "winter"},
}
const BASE_DISHES := ["d_coffee", "d_royaltea", "d_matcha", "d_strawmilk", "d_cocoa", "s_pudding", "s_shortcake", "s_pancake", "s_parfait", "s_choco",
	"m_omurice", "m_napolitan", "m_curry", "m_doria", "m_sandwich"]
const MAX_MENU := 10
const CAT_NAMES := {"drink": "飲品", "dessert": "甜點", "main": "主餐"}

# ------------------------------------------------------------------ furniture
# style: ambience contributions. effects are interpreted by the simulation (not flat bonuses).
const FURNITURE := {
	"table": {"name": "雙人桌", "price": 600, "fp": [[-1, 0], [0, 0], [1, 0]], "style": {"warm": 1}, "desc": "一張桌子＋兩張椅子。"},
	"sofa_table": {"name": "沙發座", "price": 1100, "fp": [[-1, 0], [0, 0], [1, 0]], "style": {"warm": 3, "elegant": 1}, "desc": "坐得很舒服，客人會待得更久、更放鬆。喜歡沙發的客人會指定這裡。"},
	"plant": {"name": "盆栽", "price": 180, "fp": [[0, 0]], "style": {"warm": 2, "elegant": 1}, "desc": "讓店裡多一點綠意。"},
	"lamp": {"name": "暖色立燈", "price": 220, "fp": [[0, 0]], "style": {"warm": 2, "retro": 1}, "desc": "柔和的燈光。"},
	"gramophone": {"name": "古董留聲機", "price": 420, "fp": [[0, 0]], "style": {"retro": 4}, "desc": "播放爵士時氣氛更好。"},
	"plush": {"name": "大型絨毛熊", "price": 300, "fp": [[0, 0]], "style": {"cute": 4}, "desc": "可愛風格的代表。"},
	"vase": {"name": "白瓷花瓶", "price": 380, "fp": [[0, 0]], "style": {"elegant": 4}, "desc": "需要每天有人換水，否則花會枯萎。愛整理的女僕會主動照顧。"},
	"crystal": {"name": "魔法水晶燈", "price": 450, "fp": [[0, 0]], "style": {"fantasy": 4}, "desc": "閃閃發光，像故事書裡的道具。"},
	"photo": {"name": "拍照區", "price": 500, "fp": [[0, 0]], "style": {"cute": 3}, "desc": "愛拍照的客人會去拍照並分享，帶來口碑。"},
	"stage": {"name": "小舞台", "price": 900, "fp": [[0, 0], [1, 0], [0, 1], [1, 1]], "style": {"cute": 2, "fantasy": 1}, "desc": "舉辦舞台表演日的必要設備。"},
	"bookshelf": {"name": "書架", "price": 650, "fp": [[0, 0]], "style": {"retro": 2, "elegant": 1}, "desc": "愛看書的客人會選旁邊的座位、待得更久；愛書的女僕休息時會來這裡讀書。"},
	"display": {"name": "展示櫃", "price": 800, "fp": [[0, 0]], "style": {"elegant": 2, "cute": 1}, "desc": "展示合作商品。客人離開前可能會順手買一份。"},
	"partition": {"name": "隔間屏風", "price": 350, "fp": [[0, 0]], "style": {"elegant": 1, "retro": 1}, "desc": "緊鄰屏風的桌子變成半包廂，喜歡安靜的客人會優先選擇，也不容易被舞台吵到。"},
	"ribbon_arch": {"name": "緞帶拱門", "price": 480, "fp": [[0, 0]], "style": {"cute": 3, "warm": 1}, "desc": "綁滿粉色緞帶的小拱門。愛拍照的客人很喜歡在這裡停下來。"},
	"tea_cart": {"name": "下午茶推車", "price": 520, "fp": [[0, 0]], "style": {"elegant": 3, "warm": 1}, "desc": "擺著茶壺與點心架的推車，讓店裡多一點午茶時光的氣氛。"},
}
const STYLE_NAMES := {"warm": "溫馨家庭風", "elegant": "高級優雅風", "cute": "可愛偶像風", "retro": "復古懷舊風", "fantasy": "奇幻主題風"}

const MUSIC := {"none": "不放音樂", "jazz": "爵士", "pop": "偶像流行", "classical": "古典"}
const LIGHTING := {"warm": "暖黃燈光", "bright": "明亮", "dim": "昏暗氣氛"}

# ------------------------------------------------------------------ activities
const ACTIVITIES := {
	"none": {"name": "一般營業", "cost": 0, "desc": "平常的一天。"},
	"costume": {"name": "主題服裝日", "cost": 400, "desc": "全員換上特別服裝。吸引喜歡可愛風的客人，愛熱鬧的女僕心情大好。"},
	"limited": {"name": "限定菜單日", "cost": 200, "desc": "選一道料理作為限定商品（售價 +25%），喜歡它的客人更容易上門。"},
	"stage": {"name": "小型舞台表演日", "cost": 300, "desc": "需要小舞台。指派一位女僕上台表演，吸引表演觀眾，但喜歡安靜的客人會不開心。"},
	"meetup": {"name": "熟客交流會", "cost": 250, "desc": "邀請熟客們來店。客人之間更容易互相認識，熟客幾乎都會到場。"},
	"street_music": {"name": "街頭音樂之夜", "cost": 350, "desc": "和廣場的吉他手奏合作。需要小舞台。客人會被音樂吸引、待得更久。", "requires": "kanade_collab"},
	"craft_fair": {"name": "手作小市集", "cost": 300, "desc": "和月光雜貨合作，店裡擺攤賣手作雜貨。展示櫃的銷量大增。", "requires": "tsukimi_collab"},
	"birthday": {"name": "女僕生日會", "cost": 300, "desc": "只能在女僕生日當天舉辦。熟客會來祝賀，壽星心情大好。", "requires": "birthday_today"},
	"seasonal": {"name": "季節限定祭", "cost": 300, "desc": "推出當季限定料理並裝飾店面。喜歡新奇事物的客人會蜂擁而至。", "requires": "seasonal_dish"},
}

# ------------------------------------------------------------------ street
const LOCATIONS := {
	"cafe": {"name": "女僕咖啡廳「Maiden Parade」", "desc": "我們的店。可以先回店裡和女僕們聊聊天。"},
	"grocer": {"name": "山田生鮮", "desc": "牛奶、雞蛋、米、番茄、起司、麵條、咖哩塊，也有當季食材。"},
	"general": {"name": "月光雜貨", "desc": "咖啡豆、茶葉、粉類，還有各種擺飾與家具。"},
	"sweets": {"name": "糖霜屋", "desc": "鮮奶油、草莓、巧克力。老闆最近好像生意不太好……"},
	"park": {"name": "向日葵公園", "desc": "散步的人很多，常常能遇到新面孔。"},
	"plaza": {"name": "商店街廣場", "desc": "可以發傳單宣傳，提高店鋪人氣。"},
}
const LOCATION_ORDER := ["cafe", "grocer", "general", "sweets", "park", "plaza"]
const SLOTS := ["09:00", "11:00", "13:00", "15:00"]
const DAY_ACTION_POINTS := 4

## Street residents with weekly schedules: schedule[weekday] = [loc for slot0..3] ("" = not around).
const RESIDENTS := {
	"yamada": {"name": "山田大叔", "role": "山田生鮮老闆", "color": "8a5a3a",
		"schedule": {"default": ["grocer", "grocer", "grocer", "grocer"], 6: ["park", "park", "", ""]},
		"lines": ["今天的番茄特別紅！", "年輕人，好好吃飯啊。", "我家養的雞下的蛋，可是全商店街最好的。"]},
	"sunahara": {"name": "砂原小姐", "role": "糖霜屋老闆", "color": "e0a0b0",
		"schedule": {"default": ["sweets", "sweets", "sweets", "sweets"], 1: ["", "", "", ""]},
		"lines": ["今天的鮮奶油打得特別漂亮。", "嗯……要是能有更多人知道我們的蛋糕就好了。"]},
	"tsukimi": {"name": "月見小姐", "role": "月光雜貨店員", "color": "6a5a9a",
		"schedule": {"default": ["general", "general", "general", "plaza"], 3: ["", "general", "general", "general"]},
		"lines": ["這個毛線的顏色很適合妳們店喔。", "我在做手作小物，想找地方擺攤……"]},
	"kanade": {"name": "奏", "role": "廣場的街頭吉他手", "color": "3a6a8a",
		"schedule": {"default": ["", "", "plaza", "plaza"], 5: ["", "plaza", "plaza", "plaza"], 6: ["", "plaza", "plaza", "plaza"], 2: ["park", "park", "", ""]},
		"lines": ["（彈著吉他）……要點歌嗎？", "在廣場唱歌，聽眾都是路過的人。", "要是有一個願意聽完整首歌的地方就好了。"]},
	"tsurumi": {"name": "鶴見先生", "role": "公園的象棋老人", "color": "5a6a5a",
		"schedule": {"default": ["park", "park", "park", ""], 6: ["", "", "", ""]},
		"lines": ["將軍！……啊，被妳看到了。", "商店街以前可熱鬧了，有祭典、有夜市。", "最近好像有新店要開呢。"]},
}

const PARTNER_FEE := 1200
const WAGE_PER_SHIFT := 1200
const MAINTENANCE := 300
const UTILITIES := 400
const RENT := 1800
const UPGRADES := {
	"second_stove": {"name": "第二台爐具", "price": 2500, "desc": "廚房可以同時做兩道菜。"},
	"coffee_machine": {"name": "義式咖啡機", "price": 1800, "desc": "飲品品質 +10，製作時間縮短。"},
	"sofa": {"name": "休息室沙發", "price": 1500, "desc": "女僕休息時恢復疲勞更快，打烊後疲勞恢復更多。"},
	"aircon": {"name": "新冷氣", "price": 2000, "desc": "夏天不會再故障。"},
}
