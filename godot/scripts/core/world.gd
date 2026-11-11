## Daytime: exploring the shopping street, street residents, shops & collaborations,
## preparation helpers (stock, menu, furniture, ambience) and the cafe's style.
extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")
const Layout = preload("res://scripts/core/layout.gd")
const LD = preload("res://scripts/core/life_data.gd")
const Life = preload("res://scripts/core/life.gd")

# ---------------------------------------------------------------- style
static func style_scores(s: Dictionary) -> Dictionary:
	var sc := {"warm": 2.0, "elegant": 0.0, "cute": 0.0, "retro": 1.0, "fantasy": 0.0}
	for f in s.furniture:
		var st: Dictionary = Data.FURNITURE[f.type].style
		for k in st:
			sc[k] += float(st[k])
	# a wilted vase is not elegant
	for f in s.furniture:
		if f.type == "vase" and int(s.vase_water.get(f.id, 0)) >= 2:
			sc.elegant -= 3.0
	for id in s.menu:
		var d: Dictionary = Data.DISHES.get(id, {})
		if d.is_empty():
			continue
		if d.cat == "dessert":
			sc.cute += 0.7
		if id in ["d_coffee", "m_napolitan", "m_doria"]:
			sc.retro += 0.7
		if id in ["d_royaltea", "s_shortcake"]:
			sc.elegant += 0.7
		if d.get("signature", false):
			sc.warm += 2.0
	match s.music:
		"jazz":
			sc.retro += 1.5
		"classical":
			sc.elegant += 1.5
		"pop":
			sc.cute += 1.5
	match s.lighting:
		"warm":
			sc.warm += 1.0
		"dim":
			sc.elegant += 0.8
			sc.fantasy += 0.8
		"bright":
			sc.cute += 0.8
	sc.cute += minf(6.0, float(s.flags.get("costume_days", 0)) * 1.5 + float(s.flags.get("stage_days", 0)))
	# seasonal decoration
	if s.get("decor", "") != "" and LD.DECOR.has(s.decor):
		var ds: Dictionary = LD.DECOR[s.decor].style
		for k in ds:
			sc[k] += float(ds[k])
	if s.activity == "costume":
		sc.cute += 4.0
	return sc

static func dominant_style(s: Dictionary) -> Dictionary:
	var sc := style_scores(s)
	var best := "warm"
	for k in sc:
		if sc[k] > sc[best]:
			best = k
	return {"key": best, "name": Data.STYLE_NAMES[best], "strength": sc[best]}

# ---------------------------------------------------------------- inventory & shops
static func servings(inv: Dictionary, dish_id: String) -> int:
	var d: Dictionary = Data.DISHES[dish_id]
	var n := 9999
	for k in d.ing:
		n = mini(n, int(int(inv.get(k, 0)) / int(d.ing[k])))
	return n

static func shop_open(s: Dictionary, shop: String) -> bool:
	if s.street.get("event", "") == "closed_" + shop:
		return false
	if shop == "sweets":
		# Sunahara takes Tuesdays off unless the collaboration keeps her busy
		return Data.weekday(s.day) != 1 or "sweets_collab" in s.partners
	return true

static func ingredient_available(s: Dictionary, id: String) -> bool:
	var ing: Dictionary = Data.INGREDIENTS[id]
	if ing.has("season") and ing.season != Data.season(s.day):
		return false
	if ing.has("flag") and not s.flags.get(ing.flag, false):
		return false
	return shop_open(s, ing.shop)

static func ingredient_price(s: Dictionary, id: String) -> int:
	var ing: Dictionary = Data.INGREDIENTS[id]
	var p := float(ing.price)
	if ing.shop == "sweets" and "sweets_collab" in s.partners:
		p *= 0.8
	if s.street.get("event", "") == "sale" and ing.shop == "grocer":
		p *= 0.8
	return int(roundf(p))

static func buy_ingredient(s: Dictionary, id: String, qty: int) -> String:
	if not ingredient_available(s, id):
		return "現在買不到%s。" % Data.INGREDIENTS[id].name
	var cost := ingredient_price(s, id) * qty
	if float(s.money) < cost:
		return "錢不夠。"
	s.money = float(s.money) - cost
	s.today_spend.ingredients = float(s.today_spend.ingredients) + cost
	s.inventory[id] = int(s.inventory.get(id, 0)) + qty
	return ""

## Rough stock suggestion for one shift: what each menu item can still make.
static func stock_report(s: Dictionary) -> Array:
	var out := []
	for id in s.menu:
		out.append({"id": id, "name": Data.DISHES[id].name, "servings": servings(s.inventory, id)})
	return out

static func dish_available(s: Dictionary, id: String) -> bool:
	var d: Dictionary = Data.DISHES[id]
	if d.has("season") and d.season != Data.season(s.day):
		return false
	return id in s.unlocked_dishes

static func set_menu(s: Dictionary, menu: Array) -> String:
	if menu.size() > Data.MAX_MENU:
		return "菜單最多 %d 道。" % Data.MAX_MENU
	var old: Array = s.menu
	var fresh := []
	for id in menu:
		if not dish_available(s, id):
			return "%s現在不能上菜單。" % Data.DISHES[id].name
		if not id in old:
			fresh.append(id)
	s.menu = menu.duplicate()
	for id in fresh:
		if not id in s.new_dishes:
			s.new_dishes.append(id)
	return ""

static func toggle_menu(s: Dictionary, id: String) -> String:
	var m: Array = s.menu.duplicate()
	if id in m:
		m.erase(id)
	else:
		m.append(id)
	return set_menu(s, m)

# ---------------------------------------------------------------- furniture
static func buy_furniture(s: Dictionary, type: String, x: int, z: int) -> String:
	var def: Dictionary = Data.FURNITURE[type]
	if float(s.money) < float(def.price):
		return "錢不夠。"
	var lay = Layout.new(s.furniture, s.upgrades)
	var err: String = lay.can_place(type, x, z)
	if err != "":
		return err
	s.money = float(s.money) - float(def.price)
	s.today_spend.furniture = float(s.today_spend.furniture) + float(def.price)
	var id := "f%d" % int(s.next_furniture_id)
	s.next_furniture_id = int(s.next_furniture_id) + 1
	s.furniture.append({"id": id, "type": type, "x": x, "z": z})
	if type == "vase":
		s.vase_water[id] = 0
	return ""

static func move_furniture(s: Dictionary, fid: String, x: int, z: int) -> String:
	var idx := -1
	for i in s.furniture.size():
		if s.furniture[i].id == fid:
			idx = i
	if idx < 0:
		return "找不到家具。"
	var f: Dictionary = s.furniture[idx]
	var rest: Array = s.furniture.duplicate()
	rest.remove_at(idx)
	var lay = Layout.new(rest, s.upgrades)
	var err: String = lay.can_place(f.type, x, z)
	if err != "":
		return err
	f.x = x
	f.z = z
	return ""

static func sell_furniture(s: Dictionary, fid: String) -> String:
	var seats := 0
	var target = null
	for f in s.furniture:
		if f.type in Layout.SEATING:
			seats += 1
		if f.id == fid:
			target = f
	if target == null:
		return "找不到家具。"
	if target.type in Layout.SEATING and seats <= 2:
		return "店裡至少要留兩組座位。"
	s.furniture.erase(target)
	s.vase_water.erase(fid)
	s.money = float(s.money) + roundf(float(Data.FURNITURE[target.type].price) * 0.5)
	return ""

static func buy_upgrade(s: Dictionary, id: String) -> String:
	if s.upgrades.get(id, false):
		return "已經有了。"
	var price := float(Data.UPGRADES[id].price)
	if float(s.money) < price:
		return "錢不夠。"
	s.money = float(s.money) - price
	s.today_spend.furniture = float(s.today_spend.furniture) + price
	s.upgrades[id] = true
	if id == "second_stove":
		s.equipment_wear["stove2"] = 0.0
	return ""

# ---------------------------------------------------------------- activities
static func activity_requirement(s: Dictionary, id: String) -> String:
	var a: Dictionary = Data.ACTIVITIES[id]
	if id in ["stage", "street_music"]:
		var has_stage := false
		for f in s.furniture:
			if f.type == "stage":
				has_stage = true
		if not has_stage:
			return "需要小舞台。"
	match a.get("requires", ""):
		"kanade_collab", "tsukimi_collab":
			if not s.flags.get(a.requires, false):
				return "還沒有談好合作。"
		"birthday_today":
			if birthday_maid(s) == "":
				return "今天沒有人生日。"
		"seasonal_dish":
			var found := false
			for d in s.menu:
				if Data.DISHES[d].get("season", "") == Data.season(s.day):
					found = true
			if not found:
				return "菜單上需要一道當季限定料理。"
	if float(s.money) < float(a.cost):
		return "錢不夠。"
	return ""

static func set_activity(s: Dictionary, id: String, featured := "") -> String:
	if id != "none":
		var err := activity_requirement(s, id)
		if err != "":
			return err
	s.activity = id
	s.featured_dish = featured if id == "limited" else ""
	return ""

## Put up this season's decoration (taken down automatically when the season changes).
static func set_decor(s: Dictionary) -> String:
	var season := Data.season(int(s.day))
	if s.get("decor", "") == season:
		return "這一季的裝飾已經掛上了。"
	var d: Dictionary = LD.DECOR[season]
	if float(s.money) < float(d.price):
		return "錢不夠。"
	s.money = float(s.money) - float(d.price)
	s.today_spend.furniture = float(s.today_spend.furniture) + float(d.price)
	s.decor = season
	St.add_album(s, "店裡的%s" % d.name, "%s大家一起動手佈置，小春說這樣客人一進門就會知道季節換了。" % d.desc, [], "pending",
		"decor_%s_%d" % [season, int((int(s.day) - 1) / Data.YEAR_DAYS)], "cafe")
	return ""

static func birthday_maid(s: Dictionary) -> String:
	var yd := ((int(s.day) - 1) % Data.YEAR_DAYS) + 1
	for m in St.active_maids(s):
		if int(Data.MAIDS[m.id].birthday) == yd:
			return m.id
	return ""

## Days until the next birthday / anniversary (for preparation reminders).
static func upcoming_special_days(s: Dictionary, within := 3) -> Array:
	var out := []
	for k in range(1, within + 1):
		var d := int(s.day) + k
		var yd := ((d - 1) % Data.YEAR_DAYS) + 1
		for m in St.active_maids(s):
			if int(Data.MAIDS[m.id].birthday) == yd:
				out.append({"kind": "birthday", "who": m.id, "in": k, "day": d, "title": "%s的生日" % Data.MAIDS[m.id].name})
		if (d - 1) % Data.YEAR_DAYS == 0 and d > 1:
			out.append({"kind": "anniversary", "who": "", "in": k, "day": d, "title": "接手店鋪 %d 週年" % int((d - 1) / Data.YEAR_DAYS)})
		for m in St.active_maids(s):
			var worked := d - int(m.hired_day)
			if worked > 0 and worked % 28 == 0 and not m.id in Data.STARTING_MAIDS:
				out.append({"kind": "join", "who": m.id, "in": k, "day": d, "title": "%s來店裡滿 %d 天" % [Data.MAIDS[m.id].name, worked]})
	return out

## Preparation for tomorrow's special day (done in the evening/day before): gift, decoration, cake.
static func prepare_special(s: Dictionary, key: String, kind: String) -> String:
	var costs := {"gift": 400, "decor": 300, "cake": 250, "letter": 0}
	if not costs.has(kind):
		return "不明的準備。"
	if float(s.money) < float(costs[kind]):
		return "錢不夠。"
	var prep: Dictionary = s.special_prep.get(key, {})
	if prep.has(kind):
		return "已經準備好了。"
	s.money = float(s.money) - float(costs[kind])
	s.today_spend.promotion = float(s.today_spend.promotion) + float(costs[kind])
	prep[kind] = true
	s.special_prep[key] = prep
	return ""

# ---------------------------------------------------------------- street & residents
static func slot_index(s: Dictionary) -> int:
	return clampi(Data.DAY_ACTION_POINTS - int(s.action_points), 0, Data.SLOTS.size() - 1)

static func resident_location(s: Dictionary, rid: String, slot: int) -> String:
	var sch: Dictionary = Data.RESIDENTS[rid].schedule
	var wd := Data.weekday(s.day)
	var row: Array = sch.get(wd, sch["default"])
	var loc: String = row[clampi(slot, 0, row.size() - 1)]
	# street events move people around
	if s.street.get("event", "") == "festival" and loc != "":
		if rid in ["kanade", "tsukimi", "tsurumi"]:
			loc = "plaza"
	if s.weather == "rain" and loc == "park":
		loc = ""
	if s.street.get("event", "") == "closed_" + loc:
		loc = ""
	return loc

static func residents_at(s: Dictionary, loc: String, slot := -1) -> Array:
	if slot < 0:
		slot = slot_index(s)
	var out := []
	for rid in Data.RESIDENTS:
		if resident_location(s, rid, slot) == loc:
			out.append(rid)
	return out

static func resident(s: Dictionary, rid: String) -> Dictionary:
	if not s.street.residents.has(rid):
		s.street.residents[rid] = {"aff": 0.0, "talks": 0, "met": false, "last_day": -1}
	return s.street.residents[rid]

## Visit a location in the current slot. Returns an encounter {title, lines, residents, options}.
static func visit_location(s: Dictionary, loc: String, opt := "") -> Dictionary:
	var slot := slot_index(s)
	s.action_points = maxi(0, int(s.action_points) - 1)
	var key := "visit_" + loc
	var visits := int(s.flags.get(key, 0)) + 1
	s.flags[key] = visits
	var enc := {"title": Data.LOCATIONS[loc].name, "lines": [], "residents": residents_at(s, loc, slot), "loc": loc}
	var L: Array = enc.lines
	match loc:
		"cafe":
			_visit_cafe(s, opt, enc)
		"grocer":
			if not shop_open(s, "grocer"):
				L.append("山田生鮮今天拉下了鐵門。")
			elif s.street.get("event", "") == "sale":
				L.append("商店街特賣日！生鮮全面八折。")
			var season_ing := []
			for id in Data.INGREDIENTS:
				var ing: Dictionary = Data.INGREDIENTS[id]
				if ing.shop == "grocer" and ing.has("season") and ing.season == Data.season(s.day):
					season_ing.append(ing.name)
			if not season_ing.is_empty():
				L.append("店頭擺著當季的%s。" % "、".join(season_ing))
		"general":
			L.append("月光雜貨飄著淡淡的焙煎咖啡香。家具和擺飾也可以在這裡訂。")
			var shi: Dictionary = s.customers.shiraishi
			if not shi.known and visits >= 1:
				shi.known = true
				L.append("一位戴眼鏡的女生正在挑書籤。她是附近圖書館的白石小姐。")
				L.append("白石：「女僕咖啡廳……那裡可以安靜看書嗎？如果可以，我下班想去坐坐。」")
				L.append("🆕 認識了新顧客：白石小姐（喜歡安靜看書）")
		"sweets":
			if not shop_open(s, "sweets"):
				L.append("糖霜屋的門口掛著「本日公休」的牌子。")
			elif not "sweets_collab" in s.partners:
				L.append("糖霜屋的櫃子空了一半。最近客人越來越少了……")
			else:
				L.append("糖霜屋的櫃子擺得滿滿的。託合作的福，生意好多了。")
		"park":
			if s.weather == "rain":
				L.append("下著雨，公園裡幾乎沒有人。")
			else:
				_visit_park(s, enc)
		"plaza":
			var gain := maxi(1, 5 - int(s.flags.get("flyers_today", 0)) * 2)
			if s.street.get("event", "") == "festival":
				gain += 3
				L.append("廣場正在辦祭典，人潮洶湧！")
			s.flags["flyers_today"] = int(s.flags.get("flyers_today", 0)) + 1
			s.popularity = St.clampf100(float(s.popularity) + gain)
			L.append("在廣場發了傳單。（店鋪人氣 +%d）" % gain)
			if not s.customers.endo.known:
				s.customers.endo.known = true
				L.append("一位穿著應援外套的男生接過傳單：「女僕咖啡廳……有舞台表演嗎！？」")
				L.append("🆕 認識了新顧客：遠藤（似乎很喜歡舞台表演）")
			elif not s.customers.nanami.known and visits >= 2:
				s.customers.nanami.known = true
				L.append("一個女生正對著可麗餅拍個不停。「我是美食部落客七海！妳的店有什麼招牌嗎？」")
				L.append("🆕 認識了新顧客：七海（她的貼文能讓料理爆紅）")
	# recruitable maids appear where they hang around
	for mid in Data.MAIDS:
		var r: Dictionary = Data.MAIDS[mid].get("recruit", {})
		if r.is_empty() or mid in s.staff or r.location != loc:
			continue
		if r.has("requires") and not s.flags.get(r.requires, false):
			continue
		if visits >= int(r.visits) and float(s.popularity) >= float(r.popularity):
			s.flags["recruit_" + mid] = true
			L.append("✨ %s：%s" % [Data.MAIDS[mid].name, _recruit_line(mid)])
	if not enc.residents.is_empty():
		var names := []
		for rid in enc.residents:
			names.append(Data.RESIDENTS[rid].name)
		L.append("（%s在這裡）" % "、".join(names))
	_chance_encounter(s, loc, enc)
	return enc

static func _recruit_line(mid: String) -> String:
	match mid:
		"yukino":
			return "「……妳是那間女僕咖啡廳的店長？我在找打工。我不太會笑，但我很會整理東西。」（可以招募）"
		"kaede":
			return "「欸！那間店在招人嗎？我跑得超快，送餐交給我！」（可以招募）"
		"tsumugi":
			return "（月見小姐身邊那個在縫布偶的女生抬起頭）「……那個，月見姐說妳的店需要人手。我會做一點針線活，也會照顧人。」（可以招募）"
		"chinatsu":
			return "（奏旁邊抱著吉他的女生）「學、學姊說妳的店願意聽完整首歌……我可以在那裡打工嗎？」（可以招募）"
		"aoi":
			return "（連鎖咖啡店門口，一個穿著制服的女生正在解開圍裙）「我辭職了。……妳是那間女僕咖啡廳的店長？我想泡讓人記得的咖啡。」（可以招募）"
		"hiyori":
			return "（花圃旁的長椅上，一個女生睡醒揉了揉眼睛）「嗯……咖啡廳啊～那裡可以慢慢來嗎？可以的話，我想去～」（可以招募）"
	return "（可以招募）"

static func hire_maid(s: Dictionary, mid: String) -> String:
	if mid in s.staff:
		return "已經是店裡的一員了。"
	if not s.flags.get("recruit_" + mid, false):
		return "還沒有機會邀請她。"
	if s.staff.size() >= Data.MAX_STAFF:
		return "店裡已經沒辦法再排更多人了。"
	s.staff.append(mid)
	var m: Dictionary = s.maids[mid]
	m.hired_day = int(s.day)
	m.quit = false
	m.role = Data.MAIDS[mid].default_role
	m.flags["want_next"] = int(s.day) + 3
	s.flags.erase("recruit_" + mid)
	St.add_album(s, "%s加入了" % Data.MAIDS[mid].name, Data.MAIDS[mid].intro, [mid])
	return ""

static func _visit_cafe(s: Dictionary, opt: String, enc: Dictionary) -> void:
	var maids := St.active_maids(s)
	var m: Dictionary = maids[0]
	for x in maids:
		if x.id == opt:
			m = x
	var def: Dictionary = Data.MAIDS[m.id]
	m.mood = St.clampf100(float(m.mood) + 10)
	m.fatigue = St.clampf100(float(m.fatigue) - 5)
	m.flags["talks"] = int(m.flags.get("talks", 0)) + 1
	m.flags["manager_trust"] = float(m.flags.get("manager_trust", 30.0)) + 2.0
	enc.title = "和%s聊天" % def.name
	enc.maid = m.id
	if not m.want_talk.is_empty():
		var tv := Life.talk_view(s, m.id)
		enc.lines.append_array(tv.lines)
		enc["talk"] = m.id
	elif not m.concern.is_empty() and not m.concern.get("revealed", false):
		m.concern.revealed = true
		enc.lines.append("%s：「%s」" % [def.name, m.concern.confide])
		enc["concern"] = m.id
	else:
		enc.lines.append(chat_line(s, m.id))
	enc.lines.append("%s的心情變好了。" % def.name)

static func chat_line(s: Dictionary, mid: String) -> String:
	var m: Dictionary = s.maids[mid]
	var name: String = Data.MAIDS[mid].name
	if float(m.fatigue) > 60:
		return "%s：「老實說……最近有點累。可以讓我稍微休息一下嗎？」" % name
	if "complaint" in m.yesterday:
		return "%s：「昨天的客訴……我會更注意的。」" % name
	if "praised" in m.yesterday:
		return "%s：「昨天有客人說想再見到我！好開心～」" % name
	# talk about a colleague she is close to / has friction with
	var best := ""
	var worst := ""
	for o in St.active_maids(s):
		if o.id == mid:
			continue
		var r := St.rel(s, mid, o.id)
		if best == "" or float(r.close) > float(St.rel(s, mid, best).close):
			best = o.id
		if float(r.friction) >= 35 and (worst == "" or float(r.friction) > float(St.rel(s, mid, worst).friction)):
			worst = o.id
	var talks := int(m.flags.get("talks", 0))
	var ml := Life.memory_line(s, mid, talks)
	if ml != "":
		return ml
	if worst != "" and talks % 3 == 1:
		return "%s：「……%s那邊，最近有點難配合。」" % [name, Data.MAIDS[worst].name]
	if best != "" and talks % 3 == 2:
		var sh: Array = St.rel(s, mid, best).shared
		if not sh.is_empty():
			return "%s：「還記得嗎？%s那次，%s」" % [name, Data.MAIDS[best].name, sh[sh.size() - 1].text]
	var lines := {
		"koharu": ["小春：「店長！我想到新的歡迎口號了，要聽嗎？」", "小春：「如果有舞台的話，我想試著唱歌看看！」", "小春：「雫最近比較敢說話了喔，要多誇誇她！」"],
		"rin": ["凜：「……蛋包飯的火候，我又改良了一點。」", "凜：「廚房只有一台爐子，忙的時候根本來不及。」", "凜：「……謝謝妳每次都來聽我說。」"],
		"shizuku": ["雫：「我……我想變得能好好跟客人說話。」", "雫：「擦桌子的時候，客人跟我說了謝謝……」", "雫：「小春前輩教我笑的方法……像這樣？」"],
		"yukino": ["雪乃：「書架的書，我按作者重新排過了。」", "雪乃：「花瓶的水，每天換比較好。」", "雪乃：「常來看書的那位客人……好像也喜歡同一個作家。」"],
		"kaede": ["楓：「店長！今天我送了幾趟餐，妳猜？」", "楓：「慢吞吞的我真的受不了啦……不過我會忍耐的。」", "楓：「下次比賽誰先擦完桌子！」"],
		"tsumugi": ["紬：「桌布的邊脫線了，我晚上帶回去補。」", "紬：「大家今天都有喝水嗎？」", "紬：「月見姐說，下次市集想放我做的小熊。」"],
		"chinatsu": ["千夏：「客人點餐的聲音，其實有節奏喔。」", "千夏：「學姊今天在廣場唱了新歌……好想聽完整首。」", "千夏：「我、我今天有好好說『歡迎回來』了！」"],
		"aoi": ["葵：「今天的豆子，烘得剛好。」", "葵：「這裡的客人會說『謝謝』。以前那間店，很少人這樣說。」", "葵：「咖啡要趁熱喝。……我是說妳，店長。」"],
		"hiyori": ["日和：「今天的雲很好看喔～」", "日和：「忙的時候，深呼吸三次就好了～」", "日和：「沙發的位置，下午會曬到太陽～」"],
	}
	var arr: Array = lines.get(mid, ["%s：「今天也辛苦了。」" % name])
	return arr[talks % arr.size()]

static func _visit_park(s: Dictionary, enc: Dictionary) -> void:
	var L: Array = enc.lines
	var mayu: Dictionary = s.customers.mayu
	var chizuru: Dictionary = s.customers.chizuru
	var km: Dictionary = s.customers.kasuga_m
	if not mayu.known:
		mayu.known = true
		L.append("長椅上有位女生在畫素描。她叫小林真由，是插畫家。")
		L.append("真由：「女僕咖啡廳？聽起來好可愛……我改天去看看！」")
		L.append("🆕 認識了新顧客：小林真由")
	elif not chizuru.known and int(s.day) >= 2:
		chizuru.known = true
		chizuru.story_stage = 1
		L.append("一位老奶奶正在餵鴿子。她看著妳的圍裙笑了。")
		L.append("千鶴奶奶：「女僕咖啡廳啊……那間店的布丁，以前可是很有名的喔。現在還有在做嗎？」")
		L.append("🆕 認識了特殊顧客：千鶴奶奶（她似乎很在意布丁）")
	elif not km.known and int(s.day) >= 3:
		km.known = true
		s.customers.kasuga_f.known = true
		L.append("一對老夫妻手牽手散步。先生默默地幫太太撐著陽傘。")
		L.append("春日太太：「我們每個星期天都會出來約會喔。要是有能坐著聊天的地方就好了。」")
		L.append("🆕 認識了新顧客：春日夫妻（喜歡沙發座）")
	else:
		L.append("陽光很舒服。散步的人們聊著商店街的近況。")
		s.popularity = St.clampf100(float(s.popularity) + 1)
		L.append("（店鋪人氣 +1）")

## Small daytime encounters that depend on who is around (street life).
static func _chance_encounter(s: Dictionary, loc: String, enc: Dictionary) -> void:
	var L: Array = enc.lines
	var ev: String = s.street.get("event", "")
	if ev == "new_shop" and loc == "plaza":
		L.append("廣場旁開了一間連鎖咖啡店，門口排著長長的隊伍……")
	# maids on their day off are out living their own day
	if loc in ["grocer", "general", "sweets", "plaza", "park"]:
		L.append_array(Life.offday_meet(s, loc))

## Talk with a street resident. Affinity grows; collaborations and info unlock.
static func talk_resident(s: Dictionary, rid: String) -> Dictionary:
	var r := resident(s, rid)
	var def: Dictionary = Data.RESIDENTS[rid]
	var out := {"title": def.name, "lines": [], "offer": ""}
	var L: Array = out.lines
	var first: bool = not r.met
	r.met = true
	if int(r.last_day) != int(s.day):
		r.aff = minf(100.0, float(r.aff) + 8.0)
		r.talks = int(r.talks) + 1
		r.last_day = int(s.day)
	var talks := int(r.talks)
	if first:
		L.append("%s（%s）：「%s」" % [def.name, def.role, _first_line(rid)])
	else:
		L.append("%s：「%s」" % [def.name, def.lines[talks % def.lines.size()]])
	match rid:
		"yamada":
			if not s.flags.get("yamada_eggs", false) and float(r.aff) >= 24:
				out.offer = "yamada_eggs"
				L.append("山田大叔：「妳很常來嘛。我家放牧雞下的蛋，要不要固定進一些？做蛋包飯可是絕品。」")
		"sunahara":
			if not "sweets_collab" in s.partners and float(r.aff) >= 16:
				out.offer = "sweets_collab"
				L.append("砂原：「如果妳的店願意長期進貨，我可以給妳八折，還能一起做聯名蛋糕。」（簽約費 ¥%d）" % Data.PARTNER_FEE)
		"tsukimi":
			if not s.flags.get("tsukimi_collab", false) and float(r.aff) >= 24:
				out.offer = "tsukimi_collab"
				L.append("月見：「我想在妳們店裡擺手作小市集……可以嗎？展示櫃也能借我放作品的話就更好了。」")
		"kanade":
			if not s.flags.get("kanade_collab", false) and float(r.aff) >= 24:
				out.offer = "kanade_collab"
				L.append("奏：「聽說妳們店有舞台？……讓我在那裡唱一晚，好不好？」（需要小舞台）")
		"tsurumi":
			var hint := street_hint(s)
			if hint != "":
				L.append("鶴見先生：「%s」" % hint)
	return out

static func _first_line(rid: String) -> String:
	match rid:
		"yamada":
			return "喔！妳就是新來的店長啊。蛋跟牛奶都很新鮮喔！"
		"sunahara":
			return "歡迎光臨……啊，是隔壁街的咖啡廳？請多指教。"
		"tsukimi":
			return "妳好～我在這裡打工，順便做些手作小物。"
		"kanade":
			return "（停下吉他）……妳是第一個停下來聽完的人。"
		"tsurumi":
			return "來下一盤嗎？……不會？那陪我聊聊商店街的往事吧。"
	return "妳好。"

static func accept_offer(s: Dictionary, offer: String) -> String:
	match offer:
		"yamada_eggs":
			s.flags["yamada_eggs"] = true
			if not "sp_omurice" in s.unlocked_dishes:
				s.unlocked_dishes.append("sp_omurice")
			St.add_album(s, "山田家的放牧蛋", "山田大叔說，這是他養的雞下的蛋，只給熟人。凜拿在手上看了好久，說要做最好的蛋包飯。", ["rin"])
		"sweets_collab":
			if float(s.money) < Data.PARTNER_FEE:
				return "錢不夠。"
			s.money = float(s.money) - Data.PARTNER_FEE
			s.today_spend.promotion = float(s.today_spend.promotion) + Data.PARTNER_FEE
			s.partners.append("sweets_collab")
			if not "collab_cake" in s.unlocked_dishes:
				s.unlocked_dishes.append("collab_cake")
			St.add_album(s, "與糖霜屋簽約", "快要撐不下去的糖霜屋成了我們的甜點夥伴。聯名蛋糕的試作品，大家一起吃掉了。")
		"tsukimi_collab":
			s.flags["tsukimi_collab"] = true
			St.add_album(s, "月見的手作小市集", "月光雜貨的月見小姐想在店裡擺攤。小小的雜貨，讓店裡多了不一樣的顏色。")
		"kanade_collab":
			s.flags["kanade_collab"] = true
			St.add_album(s, "廣場的吉他手", "奏說，她一直在找一個願意聽完整首歌的地方。")
		_:
			return "不明的提案。"
	return ""

## What the old chess player knows about upcoming street happenings.
static func street_hint(s: Dictionary) -> String:
	var nxt: String = s.street.get("next_event", "")
	match nxt:
		"festival":
			return "明天廣場有祭典喔，人會很多。"
		"sale":
			return "明天山田那邊好像要特賣。"
		"new_shop":
			return "聽說廣場邊要開一間新的咖啡店……"
	if Data.season_day(int(s.day) + 1) == 1:
		return "季節要換了。山田那邊會進新的食材吧。"
	return ""

# ---------------------------------------------------------------- weather & street events
static func roll_weather(s: Dictionary, rng: RandomNumberGenerator) -> String:
	var season := Data.season(int(s.day))
	var r := rng.randf()
	match season:
		"spring":
			return "rain" if r < 0.25 else ("cloudy" if r < 0.45 else "sunny")
		"summer":
			return "hot" if r < 0.35 else ("rain" if r < 0.55 else "sunny")
		"autumn":
			return "rain" if r < 0.2 else ("cloudy" if r < 0.5 else "sunny")
		_:
			return "snow" if r < 0.2 else ("cloudy" if r < 0.55 else "sunny")

const WEATHER_NAMES := {"sunny": "晴天", "cloudy": "陰天", "rain": "雨天", "hot": "大熱天", "snow": "下雪"}

static func roll_street_event(s: Dictionary, rng: RandomNumberGenerator) -> String:
	var sd := Data.season_day(int(s.day))
	if sd == 7:
		return "festival"
	if int(s.day) >= 9 and not s.flags.get("new_shop_done", false) and rng.randf() < 0.2:
		s.flags["new_shop_done"] = true
		return "new_shop"
	if Data.weekday(int(s.day)) == 2 and rng.randf() < 0.5:
		return "sale"
	if rng.randf() < 0.06:
		return "closed_grocer"
	return ""

const STREET_EVENT_NAMES := {"": "", "festival": "商店街祭典", "sale": "生鮮特賣日", "new_shop": "新咖啡店開幕", "closed_grocer": "山田生鮮臨時公休"}

# ---------------------------------------------------------------- morning briefing
static func morning_briefing(s: Dictionary) -> Array:
	var out := []
	out.append("🌤 今天是%s，%s。" % [Data.date_label(int(s.day)), WEATHER_NAMES.get(s.weather, s.weather)])
	var ev: String = s.street.get("event", "")
	if ev != "":
		out.append("🏮 " + STREET_EVENT_NAMES.get(ev, ev) + "。")
	if Data.season_day(int(s.day)) == 1 and int(s.day) > 1:
		out.append("🍃 進入%s季了，當季食材與限定菜單上市。" % Data.SEASON_NAMES[Data.season(int(s.day))])
	for m in St.active_maids(s):
		var n: String = Data.MAIDS[m.id].name
		if "overworked" in m.yesterday:
			out.append("%s看起來還很疲倦，動作比平常慢。" % n)
		if "complaint" in m.yesterday:
			out.append("%s因為昨天的客訴有點沮喪。" % n)
		if "praised" in m.yesterday:
			out.append("%s因為昨天被客人稱讚，今天特別有幹勁。" % n)
		if "dayoff" in m.yesterday:
			out.append("%s休假回來，精神飽滿。" % n)
		if int(m.low_mood_nights) >= 2:
			out.append("⚠ %s最近似乎在考慮要不要繼續做下去……" % n)
		if not m.concern.is_empty():
			out.append("💭 " + String(m.concern.get("sign", "%s好像有心事。" % n)))
		if not m.want_talk.is_empty():
			out.append("💬 %s好像有話想跟店長說。（回店裡找她，或在店裡點她）" % n)
		if m.role == "off" and not m.offday.is_empty():
			out.append("☕ %s今天休假，好像會去%s。" % [n, Data.LOCATIONS[m.offday.loc].name.split("「")[0]])
	out.append_array(Life.promises_due_today(s))
	for cid in s.customers:
		var c: Dictionary = s.customers[cid]
		if c.known and c.life.state != "" and c.life.note != "" and int(s.day) - int(c.life.get("since", -99)) <= 2:
			out.append("📖 %s：%s。" % [Data.CUSTOMERS[cid].name, c.life.note.split("。")[0]])
	var bm := birthday_maid(s)
	if bm != "":
		out.append("🎂 今天是%s的生日！" % Data.MAIDS[bm].name)
	for u in upcoming_special_days(s, 2):
		out.append("📅 %d 天後是%s，可以先準備。" % [u.in, u.title])
	for id in s.customers:
		var c: Dictionary = s.customers[id]
		if not c.known or int(c.last_day) != int(s.day) - 1:
			continue
		var name: String = Data.CUSTOMERS[id].name
		if "complaintIgnored" in c.last_causes or "walkedOut" in c.last_causes:
			out.append("聽說%s在商店街抱怨昨天的服務……" % name)
		elif float(c.last_sat) >= 75:
			out.append("%s昨天很開心，似乎會再來。" % name)
	if float(s.reputation) >= 70:
		out.append("📣 商店街上都在說我們店的好話。")
	elif float(s.reputation) <= 30:
		out.append("📉 最近的口碑不太好……")
	return out
