## Daily Moments: small scenes that come out of what characters actually did
## (a leisure choice, a habit, a relationship, a customer's routine), not random popups.
## Every moment is logged (capped) with a cooldown; special ones go to the memories album.
extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")

const COOLDOWN := 4

static func can_fire(s: Dictionary, id: String, once := false) -> bool:
	if not s.moment_seen.has(id):
		return true
	if once:
		return false
	return int(s.day) - int(s.moment_seen[id]) >= COOLDOWN

static func record(s: Dictionary, id: String, text: String, who: Array, album_title := "") -> Dictionary:
	s.moment_seen[id] = int(s.day)
	var mo := {"day": int(s.day), "id": id, "text": text, "who": who}
	s.moments.append(mo)
	while s.moments.size() > St.CAP_MOMENT_LOG:
		s.moments.pop_front()
	if album_title != "":
		# "pending": the view takes a screenshot of the scene at this moment and fills the path in
		if St.add_album(s, album_title, text, who, "pending"):
			mo["album"] = album_title
	return mo

static func _n(id: String) -> String:
	if Data.MAIDS.has(id):
		return Data.MAIDS[id].name
	return Data.CUSTOMERS.get(id, {}).get("name", id)

## Called by the simulation when a maid starts a leisure activity. Returns {} or {id, text, who, album}.
static func from_leisure(s: Dictionary, mid: String, lid: String, mode: String, extra: Dictionary) -> Dictionary:
	var m: Dictionary = s.maids[mid]
	var n := _n(mid)
	var after := mode == "offhours"
	match lid:
		"read":
			if mid == "yukino" and after and can_fire(s, "yukino_books", true):
				return _mk("yukino_books", "打烊後，雪乃把書架上的書一本本按作者重新排好，最後抽出一本，坐在窗邊讀了起來。", [mid], "雪乃的書架")
			if can_fire(s, "read_" + mid) and float(m.habits.read) >= 35:
				return _mk("read_" + mid, "%s坐在書架旁看書，翻頁的聲音在安靜的店裡特別清楚。" % n, [mid])
		"stay":
			if after and can_fire(s, "stay_" + mid):
				var txt := "大家都下班了，%s一個人留在店裡，" % n
				txt += "反覆練習著同一道菜。" if m.role == "kitchen" else "對著鏡子練習招呼的笑容。"
				return _mk("stay_" + mid, txt, [mid], "留到最後的%s" % n if float(m.habits.stay_late) >= 50 else "")
		"tidy":
			if after and can_fire(s, "tidy_" + mid) and float(m.habits.tidy) >= 30:
				return _mk("tidy_" + mid, "開店前，%s把每張桌子都擦了一遍，連椅腳都沒放過。" % n, [mid])
		"window":
			if s.weather == "rain" and can_fire(s, "rain_" + mid):
				return _mk("rain_" + mid, "%s站在窗邊看雨，玻璃上映著店裡暖黃的燈。" % n, [mid])
			if s.weather == "snow" and can_fire(s, "snow_window", true):
				return _mk("snow_window", "外面下雪了。%s把手貼在玻璃上，小聲地說：「好漂亮……」" % n, [mid], "第一場雪")
		"chat":
			var o: String = extra.get("with", "")
			if o == "":
				return {}
			var r := St.rel(s, mid, o)
			var key := "chat_" + St.pair_key(mid, o)
			if float(r.close) >= 85 and can_fire(s, key + "_album", true):
				return _mk(key + "_album", "%s和%s聊到忘了時間，連打烊的鐵門都忘了拉下來。" % [n, _n(o)], [mid, o], "%s和%s" % [n, _n(o)])
			if float(r.close) >= 55 and after and can_fire(s, key):
				return _mk(key, "%s和%s在打烊後的店裡聊個不停，笑聲一直傳到休息室。" % [n, _n(o)], [mid, o])
		"regular":
			var cid: String = extra.get("cust", "")
			if cid != "" and can_fire(s, "remember_" + cid, true):
				return _mk("remember_" + cid, "%s不用問就知道%s要坐哪裡、點什麼。%s愣了一下，然後笑了。" % [n, _n(cid), _n(cid)], [mid, cid], "記得你的老位子")
		"photo":
			var o: String = extra.get("with", "")
			if o != "" and after and can_fire(s, "photo_" + St.pair_key(mid, o), true):
				return _mk("photo_" + St.pair_key(mid, o), "打烊後，%s拉著%s在拍照區自拍。拍了十幾張，最後選了一張兩個人都在笑的。" % [n, _n(o)], [mid, o], "合照：%s和%s" % [n, _n(o)])
		"practice":
			if after and can_fire(s, "practice_" + mid):
				var first := can_fire(s, "practice_album_" + mid, true) and float(m.skills.performance) >= 60
				return _mk("practice_album_" + mid if first else "practice_" + mid, "大家都回去了，%s一個人站在小舞台上，對著空蕩蕩的座位小聲地唱歌。" % n, [mid], "沒有觀眾的舞台" if first else "")
		"record":
			if after and can_fire(s, "record_" + mid):
				return _mk("record_" + mid, "%s放了一張黑膠唱片。沙沙的雜音裡，店裡的燈好像變得更暖了。" % n, [mid])
		"nap":
			if after and can_fire(s, "nap_" + mid):
				return _mk("nap_" + mid, "%s在沙發座上睡著了。有人悄悄替她蓋上了一件外套。" % n, [mid])
		"water":
			if after and can_fire(s, "water_" + mid) and (mid == "hiyori" or float(m.habits.tidy) >= 40):
				return _mk("water_" + mid, "%s一盆一盆地替植物澆水，還跟它們說話。" % n, [mid])
		"concern":
			if can_fire(s, "concern_" + mid):
				return _mk("concern_" + mid, "%s%s。" % [n, m.concern.get("leisure", "一個人發呆")], [mid])
	return {}

static func _mk(id: String, text: String, who: Array, album := "") -> Dictionary:
	return {"id": id, "text": text, "who": who, "album": album}

## End of day: moments that come from the shift's statistics (helping, teamwork, routines).
static func closing(s: Dictionary, biz) -> Array:
	var out := []
	# someone covered for a colleague
	var seen_pairs := {}
	for h in biz.helps:
		var k := St.pair_key(h.helper, h.helped)
		if seen_pairs.has(k):
			continue
		seen_pairs[k] = true
		var id: String = "help_" + h.helper + "_" + h.helped
		if can_fire(s, id):
			out.append(record(s, id, "%s那邊忙不過來時，%s一句話也沒說就過去幫忙了。" % [_n(h.helped), _n(h.helper)], [h.helper, h.helped]))
			break
	# smooth handoffs
	var best := ""
	var bc := 0
	for k in biz.handoffs:
		if int(biz.handoffs[k]) > bc:
			bc = int(biz.handoffs[k])
			best = k
	if bc >= 4:
		var p: PackedStringArray = best.split("|")
		var id := "team_" + best
		var r := St.rel(s, p[0], p[1])
		if can_fire(s, id):
			var album := ""
			if float(r.synergy) >= 60 and can_fire(s, "team_album_" + best, true):
				album = "最佳搭檔"
				s.moment_seen["team_album_" + best] = int(s.day)
			out.append(record(s, id, "今天%s做好的餐，%s總是在最好的時機端出去。兩人幾乎不用說話。" % [_n(p[0]), _n(p[1])], [p[0], p[1]], album))
	# a regular kept their weekly habit
	var wd := Data.weekday(int(s.day))
	for r in biz.results:
		var cid: String = r.def
		if cid == "" or not s.customers.has(cid):
			continue
		var c: Dictionary = s.customers[cid]
		if c.is_regular and wd in Data.CUSTOMERS[cid].weekdays and int(c.visits) >= 6 and can_fire(s, "routine_" + cid, true):
			var album := "%s的星期%s" % [_n(cid), Data.WEEKDAYS[wd]] if Data.CUSTOMERS[cid].kind != "normal" and int(c.visits) >= 8 else ""
			out.append(record(s, "routine_" + cid, "星期%s，%s又準時推開了店門。這已經是第 %d 次了。" % [Data.WEEKDAYS[wd], _n(cid), int(c.visits)], [cid], album))
			break
	# rain shelter
	if s.weather == "rain" and biz.served_count >= 4 and can_fire(s, "rain_day"):
		out.append(record(s, "rain_day", "下雨的晚上，躲雨的客人一個接一個推門進來，店裡反而熱鬧了起來。", []))
	return out
