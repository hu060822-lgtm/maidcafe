## "Maiden Parade" story content: the cafe's main chapters, each maid's heart episodes, profiles and
## training lines. Pure data (all original). Logic lives in story.gd.
##
## Goal kinds (checked by story.gd against the live state):
##   days_open n · served_total n · regulars n · popularity n · reputation n · money n · staff n
##   partners n · signature n (signature dishes unlocked) · resident_aff [count, aff]
##   arcs_done n (personal arcs finished) · avg_bond n · heart_rank [count, rank] · trained n
extends RefCounted

const CHAPTERS := [
	{
		"title": "序章．快要熄燈的招牌",
		"who": "koharu",
		"intro": ["商店街的盡頭，招牌上的燈泡少了兩顆。", "小春：「店長！妳真的願意接手嗎！？太好了……我還以為這裡要關門了。」", "凜：「……先撐過這個禮拜再說吧。」", "雫：「我、我會努力的……！」"],
		"goals": [{"kind": "days_open", "n": 3, "label": "營業 3 天"}, {"kind": "served_total", "n": 25, "label": "接待 25 位客人"}],
		"outro": ["第三天打烊後，小春把招牌擦得亮晶晶的。", "小春：「店長，妳看！今天門口有人停下來看了喔！」", "凜：「……明天的蛋，我多買了一些。」", "這間店，好像還能再走下去。"],
		"reward": {"money": 3000, "dish": "st_heart_omurice", "popularity": 3},
	},
	{
		"title": "第一章．歡迎回來，主人",
		"who": "shizuku",
		"intro": ["雫：「店長……我、我想問一件事。」", "雫：「『歡迎回來』這句話……要怎麼說，客人才會真的覺得回到家呢？」", "也許答案不在台詞裡，而是在一次又一次的相遇裡。"],
		"goals": [{"kind": "regulars", "n": 1, "label": "第一位常客"}, {"kind": "popularity", "n": 25, "label": "人氣 25"}, {"kind": "trained", "n": 3, "label": "陪女僕特訓 3 次"}],
		"outro": ["那位客人推開門，很自然地說了一句：「我回來了。」", "雫愣了一下，然後笑著回答：「……歡迎回來！」", "那天晚上，雫在筆記本上寫：「今天，有人回家了。」"],
		"reward": {"money": 4000, "dish": "st_rose_tea", "popularity": 4},
	},
	{
		"title": "第二章．商店街的朋友",
		"who": "rin",
		"intro": ["凜把一張舊照片放在櫃台上。照片裡，商店街擠滿了人。", "凜：「鶴見先生說，以前這條街很熱鬧。……店不能只靠自己。」", "去認識街坊們吧。一間店，是被一條街養大的。"],
		"goals": [{"kind": "resident_aff", "n": [2, 20], "label": "和 2 位街坊變熟（熟悉度 20）"}, {"kind": "partners", "n": 1, "label": "談成 1 項合作"}, {"kind": "staff", "n": 4, "label": "女僕增加到 4 人"}],
		"outro": ["新來的夥伴第一次穿上制服，大家在休息室裡拍手。", "山田大叔送來一箱蛋，砂原小姐附上一張卡片：「一起加油吧！」", "凜：「……店變吵了。」她的嘴角在笑。"],
		"reward": {"money": 6000, "dish": "st_lace_crepe", "popularity": 5},
	},
	{
		"title": "第三章．我們的招牌",
		"who": "rin",
		"intro": ["雜誌記者來過一次，只寫了一行：「一間普通的女僕咖啡廳。」", "凜把雜誌丟進回收箱。", "凜：「普通？……我們需要一道讓人記住名字的料理。還有，讓人想再回來的理由。」"],
		"goals": [{"kind": "reputation", "n": 60, "label": "口碑 60"}, {"kind": "signature", "n": 1, "label": "做出 1 道招牌料理"}, {"kind": "heart_rank", "n": [2, 3], "label": "和 2 位女僕達到羈絆 Lv3"}],
		"outro": ["同一位記者又來了。這次，他點了招牌料理，安靜地吃完。", "下個月的雜誌上，有半頁寫著：「商店街裡，值得特地走一趟的店。」", "大家擠在一起看雜誌，小春哭得比誰都大聲。"],
		"reward": {"money": 8000, "popularity": 8},
	},
	{
		"title": "第四章．每個人的夢想",
		"who": "koharu",
		"intro": ["打烊後，小春突然問：「欸，大家以後想做什麼？」", "休息室安靜了一下。", "凜說想開自己的店。雫說想讓媽媽來吃一次飯。每個人都有一個藏起來的夢想。", "店長能做的，是陪她們一起走到那裡。"],
		"goals": [{"kind": "arcs_done", "n": 2, "label": "完成 2 位女僕的個人故事"}, {"kind": "avg_bond", "n": 55, "label": "平均信賴 55"}, {"kind": "staff", "n": 5, "label": "女僕增加到 5 人"}, {"kind": "popularity", "n": 50, "label": "人氣 50"}],
		"outro": ["牆上的回憶照片越來越多了。", "小春：「店長，妳知道嗎？以前我覺得夢想是一個人的事。」", "小春：「可是在這裡，大家的夢想會互相幫忙耶。」"],
		"reward": {"money": 10000, "popularity": 8},
	},
	{
		"title": "終章．Maiden Parade",
		"who": "koharu",
		"intro": ["商店街公會決定，今年要重新舉辦停了十年的祭典。", "鶴見先生：「開場的遊行……就交給妳們店吧。」", "小春：「女僕的遊行！？就像店名一樣！」", "要讓整條街都看見——這間店，和店裡的每一個人。"],
		"goals": [{"kind": "popularity", "n": 70, "label": "人氣 70"}, {"kind": "staff", "n": 6, "label": "女僕 6 人到齊"}, {"kind": "money", "n": 150000, "label": "存款 ¥150,000"}, {"kind": "heart_rank", "n": [3, 4], "label": "和 3 位女僕達到羈絆 Lv4"}],
		"outro": ["祭典當天，女僕們穿著制服走在商店街的正中央。", "兩旁站滿了熟客、街坊，還有第一次來的人。", "小春在最前面揮手，凜偷偷在笑，雫沒有低頭。", "有人喊了一聲：「Maiden Parade！」", "那一天，招牌上的燈泡全部都亮著。"],
		"reward": {"money": 20000, "dish": "st_parade_parfait", "popularity": 10, "album": ["Maiden Parade", "停了十年的祭典，由我們的女僕遊行揭開序幕。整條商店街都在喊店的名字。"], "ending": true},
	},
]

## Heart ranks come from trust (bond). Each new rank plays a short episode (ranks 2-4) and unlocks profile lines.
const RANK_BOND := [0, 40, 52, 66, 82]          # Lv1..Lv5 thresholds
const RANK_NAMES := ["初次見面", "漸漸熟悉", "值得信賴", "重要的夥伴", "心之所繫"]

## Profile fields: motto, food, good (good at), weak (bad at) are always shown; dream unlocks at Lv3, secret at Lv5,
## title (her nickname around the street) at Lv4. Appearance is intentionally not described here (see art bibles).
const PROFILES := {
	"koharu": {"motto": "笑容是免費的，但可以讓人回來！", "food": "草莓牛奶", "good": "記住每位客人的名字", "weak": "打蛋（常常打進蛋殼）", "dream": "站在舞台上，唱自己寫的歌", "secret": "其實開店第一天，她在後門哭過，因為怕店會倒。", "title": "商店街的小太陽"},
	"rin": {"motto": "料理不會說謊。", "food": "剛起鍋的白飯", "good": "醬汁、刀工、算成本", "weak": "被當面道謝", "dream": "有一天開一間只有八個座位的小餐館", "secret": "她把每一位客人的剩菜都記在本子裡，用來改食譜。", "title": "廚房的守門人"},
	"shizuku": {"motto": "慢慢來，也是一種前進。", "food": "媽媽做的蛋捲", "good": "把桌子擦得像鏡子一樣", "weak": "被很多人同時看著", "dream": "讓老家的媽媽來店裡，吃一次她端的布丁", "secret": "她的筆記本裡，寫滿了每天練習的「歡迎回來」。", "title": "安靜的小花"},
	"yukino": {"motto": "故事會在對的時候翻頁。", "food": "加了蜂蜜的紅茶", "good": "冷靜處理突發狀況", "weak": "選擇困難（點餐要想很久）", "dream": "寫一本讓人想在咖啡廳讀的書", "secret": "她偷偷在寫小說，主角是一間女僕咖啡廳的店長。", "title": "書頁間的月光"},
	"kaede": {"motto": "跑起來就對了！", "food": "大碗咖哩", "good": "同時端四個盤子", "weak": "等待、排隊、慢慢來", "dream": "再跑一次全國大賽——這次是為了自己", "secret": "她退出田徑隊的原因是受傷，到現在下雨天腳還會痛。", "title": "外場的疾風"},
	"tsumugi": {"motto": "小小的東西，也能裝很多心意。", "food": "糖霜餅乾", "good": "手作小物、修補制服", "weak": "拒絕別人的請託", "dream": "在商店街開一間手作教室", "secret": "店裡每個人的圍裙口袋裡，都被她偷偷縫了一個小刺繡。", "title": "針線盒裡的魔法"},
	"chinatsu": {"motto": "說不出口的話，就用唱的吧。", "food": "檸檬蘇打", "good": "吉他、即興編曲", "weak": "面對面說話", "dream": "在擠滿人的舞台上，唱完一整首歌不發抖", "secret": "她的第一首原創歌，是寫給學姊奏的。", "title": "吉他盒裡的星星"},
	"aoi": {"motto": "一杯咖啡，要讓人記住一整天。", "food": "淺焙單品咖啡", "good": "拉花、記住客人的口味", "weak": "看到流程被打亂", "dream": "沖出一杯有自己名字的咖啡", "secret": "她辭職那天，把連鎖店的制服摺得整整齊齊才離開。", "title": "吧台的指揮家"},
	"hiyori": {"motto": "今天也是好天氣喔～", "food": "曬過太陽的麵包", "good": "讓緊張的人放鬆下來", "weak": "早起", "dream": "在公園旁邊有一間可以午睡的店", "secret": "她其實記得每一盆花種下的日子。", "title": "午後的陽光"},
}

## Heart episodes: HEART[maid][rank] = {title, lines, choices: [{label, fx}]}
## fx: bond, mood, skill [key, points], memory [text, weight], album [title, text]
const HEART := {
	"koharu": {
		2: {"title": "小春的練習時間", "lines": ["開店前，小春對著窗戶的倒影練習鞠躬。", "小春：「歡迎回來，主人！……不對，要再有精神一點。歡迎回來～！」", "她發現妳在看，臉一下子紅了。"],
			"choices": [{"label": "「剛剛那個很好喔。」", "fx": {"bond": 4, "mood": 8, "skill": ["reception", 2]}}, {"label": "一起練習", "fx": {"bond": 5, "mood": 5, "skill": ["reception", 3]}}]},
		3: {"title": "有點累的小太陽", "lines": ["打烊後，小春趴在桌上，難得沒有說話。", "小春：「……店長，我是不是很吵？」", "小春：「我怕如果我不笑，店裡就會變得好安靜。」"],
			"choices": [{"label": "「不笑的小春，我也想認識。」", "fx": {"bond": 7, "mood": 10, "memory": ["店長說，不笑的我也沒關係。", 3.0]}}, {"label": "「店裡需要妳的笑容。」", "fx": {"bond": 2, "mood": 4}}]},
		4: {"title": "寫給店長的歌", "lines": ["小春把一張摺得小小的紙塞給妳。", "上面是一段歌詞：「推開門的那個人，說了一聲我回來了——」", "小春：「這、這是寫給這間店的！……也有一點點是寫給店長的！」"],
			"choices": [{"label": "把歌詞收進筆記本", "fx": {"bond": 6, "mood": 12, "skill": ["performance", 4], "album": ["寫給店的歌", "小春寫了一首關於這間店的歌。第一句是「推開門的那個人，說了一聲我回來了」。"]}}]},
	},
	"rin": {
		2: {"title": "試吃", "lines": ["凜把一小碟醬汁推到妳面前。", "凜：「……試吃。不要客氣，直接說。」"],
			"choices": [{"label": "「再酸一點會更好。」", "fx": {"bond": 5, "mood": 6, "skill": ["cooking", 3]}}, {"label": "「好吃！」", "fx": {"bond": 2, "mood": 3, "memory": ["店長說好吃。……沒有參考價值，但不討厭。", 1.5]}}]},
		3: {"title": "凜的師父", "lines": ["凜在整理刀具時，拿出一把很舊的菜刀。", "凜：「這是師父給我的。他的店……三年前收了。」", "凜：「所以我不想再看到一間店關門。」"],
			"choices": [{"label": "「這間店不會關。我保證。」", "fx": {"bond": 8, "mood": 8, "memory": ["店長說這間店不會關。我信了。", 3.0]}}, {"label": "安靜地陪她擦刀", "fx": {"bond": 6, "mood": 6}}]},
		4: {"title": "員工餐", "lines": ["打烊後，桌上擺著一份熱騰騰的料理。", "凜：「……員工餐。今天大家都很累。」", "那是她第一次，為『大家』做菜，而不是為客人。"],
			"choices": [{"label": "「我們一起吃吧。」", "fx": {"bond": 6, "mood": 12, "skill": ["management", 3], "album": ["凜的員工餐", "某天打烊後，凜默默做了員工餐。大家擠在一張桌子吃，凜說「太吵了」，但盤子被添了第二次。"]}}]},
	},
	"shizuku": {
		2: {"title": "小小的進步", "lines": ["雫：「店、店長……今天，有一位客人跟我說謝謝。」", "雫：「我……我也有好好地看著他的眼睛說不客氣。」"],
			"choices": [{"label": "「好棒！要記下來喔。」", "fx": {"bond": 5, "mood": 10, "skill": ["reception", 3]}}, {"label": "摸摸她的頭", "fx": {"bond": 6, "mood": 8}}]},
		3: {"title": "雨天的休息室", "lines": ["外面下著雨，雫在休息室裡替盆栽澆水。", "雫：「植物不會催我……所以待在它們旁邊，我比較能呼吸。」", "雫：「店長在旁邊的時候……也是。」"],
			"choices": [{"label": "「那我常常過來。」", "fx": {"bond": 8, "mood": 8, "memory": ["雨天的休息室，店長說會常常過來。", 3.0]}}, {"label": "一起照顧盆栽", "fx": {"bond": 5, "mood": 6, "skill": ["floor", 2]}}]},
		4: {"title": "第一次大聲說", "lines": ["客滿的晚上，門口又進來一組客人。", "雫深吸一口氣：「歡迎回來！請稍等一下，馬上幫您準備位子！」", "全店的人都轉過頭來。她自己好像也嚇了一跳。"],
			"choices": [{"label": "對她比一個讚", "fx": {"bond": 6, "mood": 14, "skill": ["reception", 4], "album": ["雫的聲音", "客滿的晚上，雫第一次用整間店都聽得到的聲音說「歡迎回來」。"]}}]},
	},
	"yukino": {
		2: {"title": "推薦的一本書", "lines": ["雪乃把一本書放在妳的桌上，書籤夾在中間。", "雪乃：「這一章，我覺得店長會喜歡。」"],
			"choices": [{"label": "當天晚上讀完", "fx": {"bond": 6, "mood": 8}}, {"label": "「可以跟我說說妳喜歡哪裡嗎？」", "fx": {"bond": 5, "mood": 6, "skill": ["reception", 2]}}]},
		3: {"title": "雪乃的筆記", "lines": ["雪乃的筆記本掉在地上，翻開的那頁寫著：「店長今天說了『沒關係』，三次。」", "雪乃：「……那是觀察日記。人物設定用的。」", "她把筆記本抱得很緊。"],
			"choices": [{"label": "「那我會努力當個好角色。」", "fx": {"bond": 8, "mood": 8, "memory": ["被店長看到筆記了。她說要當個好角色。", 3.0]}}, {"label": "假裝沒看到", "fx": {"bond": 4, "mood": 4}}]},
		4: {"title": "第一章", "lines": ["雪乃遞來幾張稿紙。標題是〈推開門的時候〉。", "雪乃：「第一章寫完了。第一個讀者……想請店長來當。」"],
			"choices": [{"label": "認真讀完，寫下感想", "fx": {"bond": 7, "mood": 12, "skill": ["management", 3], "album": ["〈推開門的時候〉", "雪乃寫完了小說的第一章，第一個讀者是店長。稿紙的角落寫著：「獻給 Maiden Parade」。"]}}]},
	},
	"kaede": {
		2: {"title": "比賽！", "lines": ["楓：「店長！來比賽！從門口跑到廚房，輸的人請喝飲料！」", "其他女僕在旁邊起鬨。"],
			"choices": [{"label": "認真跑", "fx": {"bond": 6, "mood": 10, "skill": ["floor", 2]}}, {"label": "「店裡不准跑步！」", "fx": {"bond": 2, "mood": -2, "skill": ["floor", 1]}}]},
		3: {"title": "下雨天的腳", "lines": ["下雨的晚上，楓走路有一點不自然。", "楓：「……沒事啦！舊傷而已，下雨就會這樣。」", "楓：「別跟其他人說喔。我不想被當成需要照顧的人。」"],
			"choices": [{"label": "「那今天的外場我來幫妳。」", "fx": {"bond": 8, "mood": 8, "memory": ["下雨天，店長默默幫我跑了外場。", 3.0]}}, {"label": "「我會保密，但不准逞強。」", "fx": {"bond": 7, "mood": 6}}]},
		4: {"title": "接力棒", "lines": ["楓教新人怎麼端盤子，比平常有耐心得多。", "楓：「以前在田徑隊，最喜歡的是接力。把棒子交出去的那一瞬間……很像現在。」"],
			"choices": [{"label": "「妳是很棒的隊長。」", "fx": {"bond": 6, "mood": 12, "skill": ["management", 4], "album": ["楓的接力棒", "楓帶著新人跑了一整晚的外場。她說，這間店就像一場接力賽。"]}}]},
	},
	"tsumugi": {
		2: {"title": "鈕扣", "lines": ["紬：「店長，制服的鈕扣鬆了……要不要我幫妳縫？」", "她已經拿出針線盒了。"],
			"choices": [{"label": "「麻煩妳了。」", "fx": {"bond": 6, "mood": 8}}, {"label": "「教我怎麼縫吧。」", "fx": {"bond": 5, "mood": 6, "skill": ["management", 2]}}]},
		3: {"title": "說不出口的「不」", "lines": ["紬的桌上堆滿了別人拜託她做的小東西。", "紬：「大家都說『只要一個就好』……我不知道怎麼拒絕。」", "她的手指上貼著好幾個 OK 繃。"],
			"choices": [{"label": "「我陪妳一起去說。」", "fx": {"bond": 8, "mood": 8, "memory": ["店長陪我去說了『這次沒辦法』。原來說出口也沒關係。", 3.0]}}, {"label": "「先休息一天吧。」", "fx": {"bond": 6, "mood": 10}}]},
		4: {"title": "大家的刺繡", "lines": ["妳在圍裙口袋裡發現了一個小小的刺繡：一個咖啡杯，旁邊有一顆愛心。", "紬：「被、被發現了……每個人都有一個喔。店長的是第一個。」"],
			"choices": [{"label": "「謝謝妳，我會好好珍惜。」", "fx": {"bond": 7, "mood": 12, "skill": ["floor", 3], "album": ["口袋裡的刺繡", "紬在每個人的圍裙口袋裡，偷偷縫了小小的刺繡。店長的是一個咖啡杯和一顆愛心。"]}}]},
	},
	"chinatsu": {
		2: {"title": "休息室的吉他聲", "lines": ["休息室傳來很輕的吉他聲。妳一推開門，聲音就停了。", "千夏：「啊……對、對不起，我馬上收起來……」"],
			"choices": [{"label": "「再彈一次給我聽好嗎？」", "fx": {"bond": 6, "mood": 10, "skill": ["performance", 2]}}, {"label": "在門外安靜地聽", "fx": {"bond": 5, "mood": 6}}]},
		3: {"title": "學姊的影子", "lines": ["千夏：「奏學姊……在廣場唱歌的時候，好像什麼都不怕。」", "千夏：「我一直在追她的背影。可是追上了，我要唱什麼呢？」"],
			"choices": [{"label": "「唱妳自己的歌。」", "fx": {"bond": 8, "mood": 8, "memory": ["店長說，唱我自己的歌就好。", 3.0]}}, {"label": "「先從一首開始吧。」", "fx": {"bond": 6, "mood": 6, "skill": ["performance", 2]}}]},
		4: {"title": "不發抖的一首歌", "lines": ["舞台的燈亮起，千夏抱著吉他，看了妳一眼。", "她唱完了一整首歌。最後一個和弦結束時，她才發現自己沒有發抖。"],
			"choices": [{"label": "第一個站起來鼓掌", "fx": {"bond": 7, "mood": 14, "skill": ["performance", 4], "album": ["千夏的一首歌", "千夏在店裡的舞台上，唱完了一整首自己的歌，一次都沒有停下來。"]}}]},
	},
	"aoi": {
		2: {"title": "一杯試作", "lines": ["葵遞來一杯咖啡，拉花是一隻小兔子。", "葵：「新的豆子。告訴我，第一口是什麼味道。」"],
			"choices": [{"label": "「像早晨的水果。」", "fx": {"bond": 6, "mood": 8, "skill": ["cooking", 2]}}, {"label": "「兔子好可愛！」", "fx": {"bond": 3, "mood": 4}}]},
		3: {"title": "被打亂的流程", "lines": ["忙亂的晚上過後，葵一個人重新排列吧台上的杯子。", "葵：「我討厭事情不照順序來。……可是今天，大家互相補位的樣子，其實不難看。」"],
			"choices": [{"label": "「流程可以一起重新設計。」", "fx": {"bond": 8, "mood": 8, "skill": ["management", 3], "memory": ["和店長一起重新畫了吧台的流程圖。", 3.0]}}, {"label": "幫她把杯子排好", "fx": {"bond": 6, "mood": 6}}]},
		4: {"title": "有名字的咖啡", "lines": ["葵把一杯咖啡放在妳面前，旁邊是一張手寫的卡片：「Parade Blend」。", "葵：「這是這間店的味道。……我想讓它有名字。」"],
			"choices": [{"label": "「就叫它 Parade Blend。」", "fx": {"bond": 7, "mood": 12, "skill": ["cooking", 4], "album": ["Parade Blend", "葵調出了屬於這間店的綜合咖啡，取名叫 Parade Blend。"]}}]},
	},
	"hiyori": {
		2: {"title": "午睡的位置", "lines": ["日和在窗邊的陽光裡打瞌睡。", "日和：「啊……店長～這裡下午三點的陽光最舒服喔。要一起嗎～？」"],
			"choices": [{"label": "坐下來曬五分鐘", "fx": {"bond": 6, "mood": 10}}, {"label": "「開店前要醒來喔。」", "fx": {"bond": 3, "mood": 3, "skill": ["reception", 2]}}]},
		3: {"title": "花圃的日子", "lines": ["日和指著公園的花圃：「那一株是去年春天第三個禮拜二種的喔。」", "日和：「大家都說我慢……可是我記得的東西，好像比別人多一點點。」"],
			"choices": [{"label": "「慢慢來的人才看得到。」", "fx": {"bond": 8, "mood": 8, "memory": ["店長說，慢慢來的人才看得到。", 3.0]}}, {"label": "「那店裡的盆栽也交給妳。」", "fx": {"bond": 6, "mood": 6, "skill": ["floor", 2]}}]},
		4: {"title": "最忙的晚上", "lines": ["客滿的晚上，每個人都快要喘不過氣。", "日和走到大家中間，慢慢地說：「深呼吸～一桌一桌來就好～」", "奇怪的是，大家真的冷靜下來了。"],
			"choices": [{"label": "「今天多虧了日和。」", "fx": {"bond": 7, "mood": 12, "skill": ["management", 4], "album": ["日和的深呼吸", "最忙的晚上，日和一句「深呼吸～」讓整間店冷靜了下來。"]}}]},
	},
}

## Training (特訓): the manager spends time with one maid before opening.
const TRAIN_PER_DAY := 2
const TRAIN_FATIGUE := 10.0
const TRAIN_POINTS := 2          # skill points per lesson (more if it matches her growth)
const TRAINING := {
	"reception": {"name": "接待練習", "icon": "🎀", "lines": ["在門口練習了二十次「歡迎回來」。", "練習了帶位時的笑容和手勢。", "扮演難搞的客人，讓她練習應對。"]},
	"cooking": {"name": "料理特訓", "icon": "🍳", "lines": ["一起練習蛋包飯的蛋皮。", "把醬汁的比例重新算了一次。", "練習同時顧兩個鍋子。"]},
	"floor": {"name": "外場訓練", "icon": "🍰", "lines": ["端著托盤在桌子之間繞圈。", "練習一次記住三桌的點單。", "練習收桌和擦桌的順序。"]},
	"performance": {"name": "舞台練習", "icon": "🎤", "lines": ["在空蕩蕩的店裡練唱。", "對著鏡子練習舞步。", "練習在舞台上自我介紹。"]},
	"management": {"name": "店務學習", "icon": "📋", "lines": ["一起看了這週的帳本。", "練習排班和安排休假。", "討論了客訴的處理方式。"]},
}
const GROWTH_FOCUS := {"idol": ["performance", "reception"], "specialist": ["cooking", "management"], "allround": ["floor", "reception"]}

## Dishes unlocked by the story (registered in data.gd DISHES as story dishes).
const STORY_DISHES := ["st_heart_omurice", "st_rose_tea", "st_lace_crepe", "st_parade_parfait"]
