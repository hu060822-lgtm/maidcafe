## Night events: short scenes after closing with a choice. Queued by settlement from real conditions.
extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")

static func _m(s: Dictionary, id: String) -> Dictionary:
	return s.maids[id]

static func _active(s: Dictionary, id: String) -> bool:
	return id in s.staff and not s.maids[id].quit

static func queue(s: Dictionary, id: String) -> void:
	if not id in s.pending_events:
		s.pending_events.append(id)

## Next playable event, or {} (skips events whose maid has left).
static func next_event(s: Dictionary) -> Dictionary:
	while not s.pending_events.is_empty():
		var id: String = s.pending_events[0]
		var ev := build(s, id)
		var who: String = ev.get("who", "")
		if not ev.is_empty() and not (Data.MAIDS.has(who) and not _active(s, who)):
			return ev
		s.pending_events.pop_front()
	return {}

static func _avg_close(s: Dictionary, mid: String) -> float:
	var tot := 0.0
	var n := 0
	for o in St.active_maids(s):
		if o.id != mid:
			tot += float(St.rel(s, mid, o.id).close)
			n += 1
	return tot / n if n > 0 else 30.0

## Build an event's text and choice labels from the current state.
static func build(s: Dictionary, id: String) -> Dictionary:
	var parts := id.split(":")
	var base: String = parts[0]
	var arg: String = parts[1] if parts.size() > 1 else ""
	match base:
		"koharu_fan":
			var n := "客人"
			for cid in s.customers:
				if s.customers[cid].fav_maid == "koharu":
					n = Data.CUSTOMERS[cid].name
			return _ev(id, "小春的第一位指名客人", "koharu", ["打烊後，小春抱著托盤在店裡轉圈圈。", "小春：「店長店長！%s說下次還要我幫他點餐！這是不是叫做『指名』！？」" % n],
				["「很厲害喔，這是妳努力的成果。」", "「別得意忘形，明天也要好好做。」"])
		"rin_overwork":
			return _ev(id, "廚房裡的凜", "rin", ["大家都下班了，廚房的燈還亮著。凜一個人在練習醬汁，手在發抖。", "凜：「……一台爐子要應付全部的單，我不能慢下來。」"],
				["讓她明天休假", "陪她一起練習"])
		"shizuku_solo":
			return _ev(id, "雫的第一次", "shizuku", ["雫：「店、店長……今天，我一個人從帶位、點餐到送餐，全部做完了……！」", "她的聲音很小，但眼睛閃閃發亮。"], ["摸摸頭稱讚她"])
		"shizuku_spill":
			return _ev(id, "打翻的杯子", "shizuku", ["休息室裡，雫抱著膝蓋坐在角落。", "雫：「我果然……不適合這份工作吧……」"],
				["「失誤沒關係，下次小心就好。」", "請小春陪陪她"])
		"shizuku_stage":
			return _ev(id, "舞台上的雫", "shizuku", ["表演結束後，雫的手還在發抖。", "雫：「好可怕……可是，大家在拍手……我好像，還想再站上去一次。」"], ["「下次也交給妳了。」"])
		"rin_teaches":
			return _ev(id, "凜的料理教室", "rin", ["打烊後，凜叫住了正要回家的小春。", "凜：「……妳的蛋包飯，蛋皮太厚了。過來，我教妳。」", "小春：「欸！？凜要教我！？」"], ["在旁邊默默看著"])
		"kaede_impatient":
			var o := arg
			return _ev(id, "楓的抱怨", "kaede", ["打烊後，楓用力地把抹布丟進水桶。", "楓：「店長！%s動作真的太慢了啦！我一個人跑三趟，她才走到一半！」" % Data.MAIDS[o].name, "休息室的門口，%s好像聽到了。" % Data.MAIDS[o].name],
				["「每個人的步調不一樣。」", "「那妳帶著她跑一次看看？」"])
		"yukino_reader":
			return _ev(id, "同一位作家", "yukino", ["白石小姐結帳時，看見雪乃圍裙口袋裡露出的書。", "白石：「……那本，妳也在看？」", "雪乃：「嗯。第三章的那一段，我讀了三次。」", "兩個人站在櫃台前，聊了整整十分鐘。"],
				["（笑著等她們聊完）"])
		"birthday":
			return _birthday(s, id, arg)
		"anniversary":
			var years := int(int(s.day) / Data.YEAR_DAYS)
			return _ev(id, "Maiden Parade %d 週年" % years, "", ["打烊後，大家把桌子拼在一起。", "小春：「店長！今天是妳接手這間店剛好 %d 年喔！」" % years, "相簿裡已經有 %d 張回憶了。" % s.album.size()],
				["「謝謝大家，明年也請多指教。」"])
		"acquaintance":
			var p := arg.split("|")
			return _ev(id, "店裡認識的朋友", p[0], ["%s和%s又坐在相鄰的位子上。" % [Data.CUSTOMERS[p[0]].name, Data.CUSTOMERS[p[1]].name], "今天，其中一個人終於開口：「……我們好像常常遇到呢。」", "兩人從那天起，會互相點頭打招呼了。"],
				["（悄悄幫他們換到同一桌）", "（就讓他們自然發展）"])
		"nanami_post":
			var dish: String = arg
			return _ev(id, "七海的貼文", "nanami", ["深夜，小春拿著手機衝進休息室。", "小春：「店長！七海發文了！『商店街裡的隱藏名店——%s』，按讚數一直跳！」" % Data.DISHES[dish].name],
				["「明天要多準備一點材料了。」"])
		"chizuru_recipe":
			return _ev(id, "千鶴奶奶的秘方", "chizuru", ["千鶴奶奶在結帳時遞來一張泛黃的紙條。", "千鶴：「布丁的味道很誠實。妳們的布丁……讓我想起以前的這間店。」", "「這是我年輕時的配方。焦糖要煮到快要苦的那一刻，再加一匙鮮奶油。」"],
				["交給凜研究", "大家一起學"])
		"chizuru_proud":
			return _ev(id, "招牌料理誕生", "chizuru", ["千鶴奶奶吃完最後一口布丁，安靜了很久。", "千鶴：「……就是這個味道。以後，這就是妳們店的布丁了。」"], ["「我們會好好守護它。」"])
		"amamiya_secret":
			return _ev(id, "角落座位的男人", "amamiya", ["雨宮先生收拾稿紙時，有一張掉在地上。上面寫著「女僕咖啡廳」與「店長」。", "雨宮：「啊……被看到了。其實，我在寫一部以這間店為舞台的小說。」", "「這裡很安靜，又有人情味。請不要改變太多。」"],
				["「請一定要讓我們讀。」", "幫他保留角落的座位"])
		"amamiya_book":
			return _ev(id, "一本書", "amamiya", ["雨宮先生把一本新書放在櫃台上。書名是《Maiden Parade 的晚上》。", "雨宮：「出版了。書裡的店長……是以妳為原型。」"], ["把書放在店裡的書架上"])
		"quit_warning":
			var n: String = Data.MAIDS[arg].name
			return _ev(id, "%s的辭職信" % n, arg, ["休息室的桌上放著一個信封。", "%s：「……對不起。最近真的好累，好像不管怎麼做都做不好。」" % n],
				["「明天放假吧，我們好好談談。」", "「再撐一下好嗎？店裡需要妳。」"])
	return {}

static func _ev(id: String, title: String, who: String, lines: Array, choices: Array) -> Dictionary:
	return {"id": id, "title": title, "who": who, "lines": lines, "choices": choices}

static func _birthday(s: Dictionary, id: String, mid: String) -> Dictionary:
	var n: String = Data.MAIDS[mid].name
	var prep: Dictionary = s.special_prep.get("birthday_" + mid, {})
	var close := _avg_close(s, mid)
	var lines := []
	if prep.is_empty() and close < 50:
		lines = ["今天是%s的生日，但好像沒有人記得。" % n, "%s一個人默默收拾好店面，說了聲「辛苦了」就回家了。" % n]
	else:
		lines.append("打烊後，燈突然暗了下來。")
		if prep.has("cake"):
			lines.append("插著蠟燭的蛋糕被端了出來。")
		elif close >= 50:
			lines.append("同事們偷偷做了一個有點歪的蛋糕。")
		if prep.has("decor"):
			lines.append("店裡掛滿了大家前一天晚上偷偷做的紙花。")
		if prep.has("letter"):
			lines.append("每個人都寫了一張小卡片。")
		if prep.has("gift"):
			lines.append("妳把準備好的禮物遞給她。")
		lines.append("%s：「欸……？大家……怎麼知道……」" % n)
		if s.activity == "birthday":
			lines.append("營業時來祝賀的熟客們留下的卡片，也被貼在了牆上。")
	return _ev(id, "%s的生日" % n, mid, lines, ["（繼續）"])

## Apply choice `idx` of event `id`. Returns the result text.
static func resolve(s: Dictionary, id: String, idx: int) -> String:
	s.pending_events.erase(id)
	var parts := id.split(":")
	var base: String = parts[0]
	var arg: String = parts[1] if parts.size() > 1 else ""
	match base:
		"koharu_fan":
			var m := _m(s, "koharu")
			m.flags["fan_event"] = true
			if idx == 0:
				m.mood = St.clampf100(float(m.mood) + 12)
				St.add_album(s, "小春的第一位指名", "小春第一次被客人指名。她說要把那天的日期寫在手帳上。", ["koharu"])
				return "小春的心情大幅提升。"
			m.mood = St.clampf100(float(m.mood) + 3)
			m.skills.reception = minf(95, float(m.skills.reception) + 2)
			return "小春鼓起臉頰，但默默練習了招呼。（接待 +2）"
		"rin_overwork":
			var m := _m(s, "rin")
			m.flags["overwork_event"] = true
			if idx == 0:
				m.day_off_tomorrow = true
				m.mood = St.clampf100(float(m.mood) + 8)
				m.flags["manager_trust"] = float(m.flags.get("manager_trust", 30.0)) + 8
				return "凜愣了一下：「……謝謝。」明天她會休假。"
			m.skills.cooking = minf(100, float(m.skills.cooking) + 3)
			m.fatigue = St.clampf100(float(m.fatigue) + 10)
			m.habits["stay_late"] = minf(100.0, float(m.habits.stay_late) + 15)
			return "兩人一直練到深夜。（凜 料理 +3，但更累了；她更習慣留下來練習了）"
		"shizuku_solo":
			var m := _m(s, "shizuku")
			m.flags["solo_event"] = true
			m.mood = St.clampf100(float(m.mood) + 12)
			m.greets_done = int(m.greets_done) + 8
			St.add_album(s, "雫第一次獨立完成訂單", "從帶位到送餐，雫一個人完成了。她說那位客人笑著跟她說了謝謝。", ["shizuku"])
			return "雫的怕生程度降低了。（接待成長更快）"
		"shizuku_spill":
			var m := _m(s, "shizuku")
			m.flags["spill_event"] = true
			if idx == 0 or not _active(s, "koharu"):
				m.mood = St.clampf100(float(m.mood) + 10)
				return "雫點點頭，擦掉眼淚。"
			m.mood = St.clampf100(float(m.mood) + 6)
			St.rel_change(s, "shizuku", "koharu", "close", 10, "小春陪她吃宵夜")
			St.rel_change(s, "shizuku", "koharu", "trust", 5, "失誤時被安慰")
			St.rel_share(s, "shizuku", "koharu", "打翻杯子那天，一起去吃了宵夜")
			return "小春拉著雫去吃了宵夜。兩人的關係變好了。"
		"shizuku_stage":
			var m := _m(s, "shizuku")
			m.flags["stage_event"] = true
			m.skills.performance = minf(90, float(m.skills.performance) + 6)
			m.mood = St.clampf100(float(m.mood) + 8)
			St.add_album(s, "雫站上了舞台", "那個連「歡迎光臨」都說不好的雫，在舞台上唱完了一整首歌。", ["shizuku"], "pending")
			return "雫的表演能力大幅提升。（表演 +6）"
		"rin_teaches":
			s.flags["rin_teaches"] = true
			var k := _m(s, "koharu")
			k.skills.cooking = minf(60, float(k.skills.cooking) + 5)
			St.rel_change(s, "koharu", "rin", "close", 8, "凜教小春做蛋包飯")
			St.rel_change(s, "koharu", "rin", "trust", 6, "凜教小春做蛋包飯")
			St.rel_share(s, "koharu", "rin", "打烊後的蛋包飯特訓")
			return "小春的料理 +5，兩人的關係變好了。"
		"kaede_impatient":
			var o := arg
			s.flags["kaede_impatient"] = true
			if idx == 0:
				St.rel_change(s, "kaede", o, "friction", -10, "店長勸楓體諒步調")
				_m(s, "kaede").habits["help"] = minf(100.0, float(_m(s, "kaede").habits.help) + 10)
				return "楓嘟著嘴：「……知道了啦。」之後她開始會順手幫%s分擔。" % Data.MAIDS[o].name
			St.rel_change(s, "kaede", o, "synergy", 12, "楓帶著一起練跑動線")
			St.rel_change(s, "kaede", o, "friction", -4, "一起練習")
			St.rel_share(s, "kaede", o, "被楓拉著在店裡練跑動線")
			_m(s, o).skills.floor = minf(float(Data.MAIDS[o].caps.floor), float(_m(s, o).skills.floor) + 2)
			return "隔天開店前，楓拉著%s在店裡跑了好幾圈。（兩人的默契提升，%s外場 +2）" % [Data.MAIDS[o].name, Data.MAIDS[o].name]
		"yukino_reader":
			s.flags["yukino_reader"] = true
			s.customers.shiraishi.affinity["yukino"] = float(s.customers.shiraishi.affinity.get("yukino", 0.0)) + 15
			s.customers.shiraishi.loyalty = St.clampf100(float(s.customers.shiraishi.loyalty) + 10)
			St.add_album(s, "同一位作家", "白石小姐和雪乃發現她們在讀同一本書。從那天起，白石小姐每次都指名雪乃。", ["yukino", "shiraishi"])
			return "白石小姐對雪乃的好感大增。"
		"birthday":
			return _apply_birthday(s, arg)
		"anniversary":
			for m in St.active_maids(s):
				m.mood = St.clampf100(float(m.mood) + 10)
			St.add_album(s, "Maiden Parade %d 週年" % int(int(s.day) / Data.YEAR_DAYS), "大家拼起桌子，一起吃了一頓很晚的晚餐。", s.staff.duplicate(), "pending")
			return "全員心情 +10。"
		"acquaintance":
			var p := arg.split("|")
			var k := St.pair_key(p[0], p[1])
			if s.cust_rel.has(k):
				s.cust_rel[k].strength = float(s.cust_rel[k].strength) + (15 if idx == 0 else 5)
			St.add_album(s, "店裡認識的朋友", "%s和%s是在 Maiden Parade 認識的。" % [Data.CUSTOMERS[p[0]].name, Data.CUSTOMERS[p[1]].name], [p[0], p[1]])
			return "兩位客人之後可能會約好一起來。"
		"nanami_post":
			s.dish_buzz[arg] = float(s.dish_buzz.get(arg, 0.0)) + 25
			s.reputation = St.clampf100(float(s.reputation) + 6)
			St.add_album(s, "七海的貼文", "七海的一篇貼文，讓「%s」在一夜之間爆紅。" % Data.DISHES[arg].name, ["nanami"])
			return "這道料理的話題度大增，明天會有更多慕名而來的客人。"
		"chizuru_recipe":
			s.customers.chizuru.story_stage = 3
			if not "sig_pudding" in s.unlocked_dishes:
				s.unlocked_dishes.append("sig_pudding")
			if idx == 0:
				if _active(s, "rin"):
					_m(s, "rin").skills.cooking = minf(100, float(_m(s, "rin").skills.cooking) + 3)
				St.add_album(s, "千鶴的秘方", "千鶴奶奶把年輕時的布丁配方交給了我們。", ["chizuru", "rin"])
				return "解鎖招牌料理「千鶴的焦糖布丁」！把它放進菜單，讓千鶴奶奶嚐嚐吧。"
			for m in St.active_maids(s):
				m.skills.cooking = minf(float(Data.MAIDS[m.id].caps.cooking), float(m.skills.cooking) + 1)
			St.add_album(s, "千鶴的秘方", "千鶴奶奶把年輕時的布丁配方交給了我們，大家一起練習到深夜。", ["chizuru"])
			return "解鎖招牌料理「千鶴的焦糖布丁」！全員料理 +1。"
		"chizuru_proud":
			s.popularity = St.clampf100(float(s.popularity) + 8)
			s.dish_buzz["sig_pudding"] = float(s.dish_buzz.get("sig_pudding", 0.0)) + 15
			St.add_album(s, "招牌料理誕生", "「千鶴的焦糖布丁」正式成為 Maiden Parade 的招牌。喜歡甜點的客人開始專程前來。", ["chizuru"])
			return "人氣 +8。喜歡甜點的客人更容易上門。"
		"amamiya_secret":
			var c: Dictionary = s.customers.amamiya
			if idx == 0:
				c.loyalty = St.clampf100(float(c.loyalty) + 10)
				return "雨宮先生害羞地點了點頭。（記得：他討厭吵鬧）"
			c.loyalty = St.clampf100(float(c.loyalty) + 6)
			if c.fav_seat == "":
				c.fav_seat = "f3"
			s.flags["reserved_seat_amamiya"] = c.fav_seat
			return "從此角落那張桌子成了雨宮先生的老位子。"
		"amamiya_book":
			s.popularity = St.clampf100(float(s.popularity) + 12)
			s.reputation = St.clampf100(float(s.reputation) + 8)
			St.add_album(s, "《Maiden Parade 的晚上》", "雨宮先生的小說出版了。讀者們開始來店裡「聖地巡禮」。", ["amamiya"])
			return "人氣 +12！"
		"quit_warning":
			var m := _m(s, arg)
			if idx == 0:
				m.day_off_tomorrow = true
				m.mood = St.clampf100(float(m.mood) + 18)
				m.low_mood_nights = 0
				return "%s收回了信。「……謝謝妳願意聽。」" % Data.MAIDS[arg].name
			m.mood = St.clampf100(float(m.mood) + 5)
			return "%s點了點頭，但表情還是很沉重。" % Data.MAIDS[arg].name
	return ""

static func _apply_birthday(s: Dictionary, mid: String) -> String:
	var m := _m(s, mid)
	var n: String = Data.MAIDS[mid].name
	var prep: Dictionary = s.special_prep.get("birthday_" + mid, {})
	var close := _avg_close(s, mid)
	s.flags["birthday_done_%s_%d" % [mid, int((int(s.day) - 1) / Data.YEAR_DAYS)]] = true
	s.special_prep.erase("birthday_" + mid)
	if prep.is_empty() and close < 50:
		m.mood = St.clampf100(float(m.mood) - 6)
		return "也許應該多關心員工之間的關係……（%s心情 -6）" % n
	var gain := 10.0 + prep.size() * 5.0 + (5.0 if close >= 60 else 0.0) + (8.0 if s.activity == "birthday" else 0.0)
	m.mood = St.clampf100(float(m.mood) + gain)
	m.flags["manager_trust"] = float(m.flags.get("manager_trust", 30.0)) + 5 * prep.size()
	for o in St.active_maids(s):
		if o.id != mid:
			St.rel_change(s, mid, o.id, "close", 5, "一起慶生")
	var reaction := {"koharu": "小春哭著笑，說這是她最棒的一天。", "rin": "凜別過頭：「……蛋糕的奶油打發過頭了。」但她吃完了一整塊。",
		"shizuku": "雫哭著吃完了整塊蛋糕。", "yukino": "雪乃把卡片夾進了她最喜歡的那本書裡。", "kaede": "楓大喊：「明年換我幫大家辦！」"}
	St.add_album(s, "%s的生日" % n, reaction.get(mid, "%s度過了很棒的生日。" % n), s.staff.duplicate(), "pending")
	return "%s度過了很棒的生日。（心情 +%d）" % [n, int(gain)]
