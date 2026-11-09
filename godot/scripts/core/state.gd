## Game state creation, save/load and small shared helpers.
## The whole state is a plain Dictionary (only Variant-native types), saved with var_to_bytes.
extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const SAVE_PATH := "user://maiden_parade_save.txt"
const VERSION := 3

## Memory caps (short/medium/long separation, see docs).
const CAP_RECENT_VISITS := 8
const CAP_CUSTOMER_LOG := 12
const CAP_REL_SHARED := 5
const CAP_REL_LOG := 12
const CAP_MOMENT_LOG := 40
const CAP_HISTORY := 120
const CAP_MAID_MEMORY := 14
const CAP_CREL_MEMORY := 4
const CAP_PROMISES := 30

static func clampf100(v: float) -> float:
	return clampf(v, 0.0, 100.0)

static func new_maid(id: String) -> Dictionary:
	var def: Dictionary = Data.MAIDS[id]
	var habits := {}
	for h in Data.HABITS:
		habits[h] = float(def.get("seed_habits", {}).get(h, 0))
	return {
		"id": id,
		"skills": def.skills.duplicate(),
		"exp": {"reception": 0.0, "cooking": 0.0, "floor": 0.0, "performance": 0.0, "management": 0.0},
		"mood": 65.0,
		"fatigue": 10.0,
		"role": def.default_role,
		"preferred_role": "",
		"day_off_tomorrow": false,
		"low_mood_nights": 0,
		"quit": false,
		"greets_done": 0,
		"flags": {},
		"yesterday": [],
		"habits": habits,
		"rest_spot": "",          # favourite rest cell key (habit "always the same seat")
		"concern": {},            # active personal concern (see social.gd)
		"concern_cooldown": 0,
		"days_worked": 0,
		"hired_day": 1,
		# ---- Living Hearts: personal life
		"bond": 35.0,             # trust in the manager (promises, listening, birthdays)
		"memories": [],           # personal memories [{day, text, tag, with, weight}] (capped, weighted)
		"want_talk": {},          # {topic, reason, day, data} -> she comes looking for the manager
		"arc_stage": 0,           # personal story progress
		"offday": {},             # today's day-off plan {spots: [loc per slot], with: maid id}
		"likes_seen": {},         # tag -> last day she reacted to it (cooldown)
	}

static func new_relation() -> Dictionary:
	return {"close": 30.0, "trust": 30.0, "synergy": 10.0, "friction": 0.0, "shared": []}

static func new_customer(id: String) -> Dictionary:
	var def: Dictionary = Data.CUSTOMERS[id]
	return {
		"id": id,
		"known": def.met == "start",
		"visits": 0,
		"loyalty": 20.0 if def.kind == "regular" else 10.0,
		"affinity": {},
		"fav_maid": "",
		"fav_seat": "",
		"fav_dish": "",
		"last_sat": -1.0,
		"last_day": -1,
		"first_day": -1,
		"last_causes": [],
		"is_regular": false,
		"brought_friend": false,
		"story_stage": 0,
		# medium-term memory
		"recent": [],               # [{day, sat, maid, dish, seat, weekday}]
		# learned habits (long-term aggregates, small fixed size)
		"weekday_counts": [0, 0, 0, 0, 0, 0, 0],
		"dish_counts": {},
		"seat_counts": {},
		"missed_habit_days": 0,
		"log": [],                  # long-term milestones only
		# ---- Living Hearts: customer life
		"life": {"state": "", "until": -1, "note": ""},   # what is going on in their life right now
		"arc_stage": 0,
		"impressions": {},          # tag -> weight: what they think of the cafe (decays)
	}

static func new_game(seed_value: int = -1) -> Dictionary:
	if seed_value < 0:
		seed_value = int(Time.get_unix_time_from_system()) % 100000
	var maids := {}
	for id in Data.MAIDS:
		maids[id] = new_maid(id)
	var rel := {}
	for a in Data.MAIDS:
		for b in Data.MAIDS:
			if a != b:
				rel[dir_key(a, b)] = new_relation()
	# Koharu has looked after Shizuku since she joined; Shizuku leans on her even more.
	rel[dir_key("koharu", "shizuku")].close = 50.0
	rel[dir_key("koharu", "shizuku")].trust = 40.0
	rel[dir_key("shizuku", "koharu")].close = 55.0
	rel[dir_key("shizuku", "koharu")].trust = 50.0
	var customers := {}
	for id in Data.CUSTOMERS:
		customers[id] = new_customer(id)
	var crel := {}
	for r in Data.CUSTOMER_RELATIONS:
		crel[pair_key(r.a, r.b)] = {"type": r.type, "strength": 50.0, "co_visits": 0, "memories": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {
		"version": VERSION,
		"seed": seed_value,
		"rng_state": str(rng.state),
		"day": 1,
		"phase": "explore",
		"money": 8000.0,
		"popularity": 15.0,
		"reputation": 50.0,          # word of mouth (0-100)
		"dish_buzz": {},             # dish id -> hype
		"maid_fame": {},             # maid id -> fame
		"action_points": Data.DAY_ACTION_POINTS,
		"inventory": {"coffee": 6, "milk": 6, "egg": 6, "rice": 3, "tea": 3, "sugar": 4, "flour": 4, "tomato": 2},
		"unlocked_dishes": Data.BASE_DISHES.duplicate(),
		"menu": ["d_coffee", "d_royaltea", "s_pudding", "s_pancake", "m_omurice", "m_curry", "m_sandwich"],
		"new_dishes": [],            # dishes added to the menu today (curious customers notice)
		"activity": "none",
		"featured_dish": "",
		"music": "none",
		"lighting": "warm",
		"staff": Data.STARTING_MAIDS.duplicate(),
		"maids": maids,
		"maid_rel": rel,
		"rel_log": [],
		"customers": customers,
		"cust_rel": crel,
		"furniture": default_furniture(),
		"vase_water": {},            # furniture id -> days since tended
		"upgrades": {"second_stove": false, "coffee_machine": false, "sofa": false, "aircon": false},
		"equipment_wear": {"stove1": 0.0, "stove2": 0.0, "coffee": 0.0},
		"partners": [],
		"album": [{"day": 1, "date": Data.date_label(1), "title": "接手 Maiden Parade", "text": "在老商店街的一角，我接下了這間快撐不下去的女僕咖啡廳。小春、凜、雫決定留下來。", "who": ["koharu", "rin", "shizuku"], "image": "", "key": "start", "cat": "cafe"}],
		"flags": {},
		"today_spend": {"ingredients": 0.0, "activity": 0.0, "promotion": 0.0, "furniture": 0.0},
		"last_report": {},
		"pending_events": [],
		"moments": [],               # recent daily moments (capped)
		"moment_seen": {},           # moment id -> last day (cooldowns)
		"history": [],
		"next_furniture_id": 100,
		"weather": "sunny",
		"street": {"residents": {}, "event": "", "new_shop": "", "street_popularity": 20.0},
		"special_prep": {},          # preparations for tomorrow's special day
		"promises": [],              # things the manager agreed to [{id, maid, kind, text, day, due, data, status}]
		"decor": "",                 # seasonal decoration currently up ("" or a season key)
		"debug_log": [],
	}

static func pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

static func default_furniture() -> Array:
	return [
		{"id": "f1", "type": "table", "x": 7, "z": 6},
		{"id": "f2", "type": "table", "x": 11, "z": 6},
		{"id": "f3", "type": "table", "x": 15, "z": 6},
		{"id": "f4", "type": "table", "x": 7, "z": 8},
		{"id": "f5", "type": "table", "x": 11, "z": 8},
		{"id": "f6", "type": "plant", "x": 1, "z": 10},
		{"id": "f7", "type": "lamp", "x": 16, "z": 10},
	]

static func active_maids(s: Dictionary) -> Array:
	var out := []
	for id in s.staff:
		var m: Dictionary = s.maids[id]
		if not m.quit:
			out.append(m)
	return out

## Directional relationship key: how `a` feels about `b`.
static func dir_key(a: String, b: String) -> String:
	return a + ">" + b

## a's relationship toward b (each maid has her own view of every other maid).
static func rel(s: Dictionary, a: String, b: String) -> Dictionary:
	var k := dir_key(a, b)
	if not s.maid_rel.has(k):
		s.maid_rel[k] = new_relation()
	return s.maid_rel[k]

## Change a relationship dimension and keep the reason (observability).
## mutual=true changes both directions (a shared experience); false only changes how `a` sees `b`.
static func rel_change(s: Dictionary, a: String, b: String, dim: String, amount: float, reason: String, mutual := true) -> void:
	var r := rel(s, a, b)
	r[dim] = clampf100(float(r[dim]) + amount)
	if mutual:
		var r2 := rel(s, b, a)
		r2[dim] = clampf100(float(r2[dim]) + amount)
	if absf(amount) >= 1.0:
		s.rel_log.append({"day": s.day, "a": a, "b": b, "dim": dim, "amount": snappedf(amount, 0.1), "reason": reason, "mutual": mutual})
		while s.rel_log.size() > CAP_REL_LOG * 4:
			s.rel_log.pop_front()

## A shared experience is remembered by both.
static func rel_share(s: Dictionary, a: String, b: String, text: String) -> void:
	for r in [rel(s, a, b), rel(s, b, a)]:
		var dup := false
		for old in r.shared:
			if old.text == text:
				dup = true
		if dup:
			continue
		r.shared.append({"day": s.day, "text": text})
		while r.shared.size() > CAP_REL_SHARED:
			r.shared.pop_front()

## Personal memory of a maid. Low-weight memories are forgotten first when full.
static func remember(s: Dictionary, mid: String, text: String, tag: String, with: Array = [], weight := 1.0) -> void:
	var m: Dictionary = s.maids[mid]
	for old in m.memories:
		if old.text == text:
			return
	m.memories.append({"day": int(s.day), "text": text, "tag": tag, "with": with, "weight": weight})
	while m.memories.size() > CAP_MAID_MEMORY:
		var low := 0
		for i in m.memories.size():
			if float(m.memories[i].weight) < float(m.memories[low].weight):
				low = i
		m.memories.remove_at(low)

## Album entries are deduplicated by `key` (defaults to the title).
## cat: maid / pair / customer / street / cafe (guessed from `who` when empty).
static func add_album(s: Dictionary, title: String, text: String, who: Array = [], image: String = "", key := "", cat := "") -> bool:
	var k := key if key != "" else title
	for a in s.album:
		if a.get("key", a.title) == k:
			return false
	if cat == "":
		cat = "cafe"
		if who.size() == 1 and Data.MAIDS.has(who[0]):
			cat = "maid"
		elif who.size() == 2 and Data.MAIDS.has(who[0]) and Data.MAIDS.has(who[1]):
			cat = "pair"
		elif not who.is_empty() and Data.CUSTOMERS.has(who[0]):
			cat = "customer"
	s.album.append({"day": s.day, "date": Data.date_label(s.day), "title": title, "text": text, "who": who, "image": image, "key": k, "cat": cat})
	s.flags["album_new"] = true
	return true

static func cust_log(c: Dictionary, day: int, text: String) -> void:
	c.log.append({"day": day, "text": text})
	while c.log.size() > CAP_CUSTOMER_LOG:
		c.log.pop_front()

static func debug(s: Dictionary, text: String) -> void:
	s.debug_log.append("D%d %s" % [s.day, text])
	while s.debug_log.size() > 200:
		s.debug_log.pop_front()

static func make_rng(s: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(s.seed)
	r.state = int(s.rng_state)
	return r

static func store_rng(s: Dictionary, r: RandomNumberGenerator) -> void:
	s.rng_state = str(r.state)

## Binary Variant encoding (exact floats, int/float types kept), stored as base64 text.
## var_to_str would round floats to ~6 digits, which makes a loaded game drift from the original.
static func serialize(s: Dictionary) -> String:
	return "MP%d:" % VERSION + Marshalls.raw_to_base64(var_to_bytes(s))

static func deserialize(text: String) -> Dictionary:
	var head := "MP%d:" % VERSION
	if text.begins_with("MP2:"):
		head = "MP2:"
	if not text.begins_with(head):
		return {}
	var raw := Marshalls.base64_to_raw(text.substr(head.length()))
	if raw.is_empty():
		return {}
	var v = bytes_to_var(raw)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	if int(v.get("version", 0)) == 2:
		migrate_v2(v)
	if int(v.get("version", 0)) != VERSION:
		return {}
	fill_defaults(v)
	return v

## Content added after a save was made (new maids, customers, fields) gets default values.
static func fill_defaults(v: Dictionary) -> void:
	for id in Data.MAIDS:
		var fresh := new_maid(id)
		if not v.maids.has(id):
			v.maids[id] = fresh
			continue
		for k in fresh:
			if not v.maids[id].has(k):
				v.maids[id][k] = fresh[k]
	for a in Data.MAIDS:
		for b in Data.MAIDS:
			if a != b and not v.maid_rel.has(dir_key(a, b)):
				v.maid_rel[dir_key(a, b)] = new_relation()
	for id in Data.CUSTOMERS:
		var fresh := new_customer(id)
		if not v.customers.has(id):
			v.customers[id] = fresh
			continue
		for k in fresh:
			if not v.customers[id].has(k):
				v.customers[id][k] = fresh[k]
	for k in ["promises", "decor"]:
		if not v.has(k):
			v[k] = [] if k == "promises" else ""

## v2 -> v3: symmetric maid relations become two directional ones; new life fields get defaults.
static func migrate_v2(v: Dictionary) -> void:
	var rel := {}
	for k in v.maid_rel:
		var p: PackedStringArray = String(k).split("|")
		if p.size() != 2:
			continue
		rel[dir_key(p[0], p[1])] = v.maid_rel[k].duplicate(true)
		rel[dir_key(p[1], p[0])] = v.maid_rel[k].duplicate(true)
	for a in Data.MAIDS:
		for b in Data.MAIDS:
			if a != b and not rel.has(dir_key(a, b)):
				rel[dir_key(a, b)] = new_relation()
	v.maid_rel = rel
	for id in Data.MAIDS:
		var fresh := new_maid(id)
		if not v.maids.has(id):
			v.maids[id] = fresh
			continue
		for k in fresh:
			if not v.maids[id].has(k):
				v.maids[id][k] = fresh[k]
	for id in Data.CUSTOMERS:
		var fresh := new_customer(id)
		if not v.customers.has(id):
			v.customers[id] = fresh
			continue
		for k in fresh:
			if not v.customers[id].has(k):
				v.customers[id][k] = fresh[k]
	for k in v.cust_rel:
		if not v.cust_rel[k].has("memories"):
			v.cust_rel[k]["memories"] = []
	for a in v.album:
		if not a.has("key"):
			a["key"] = a.title
			a["cat"] = "cafe"
	if not v.has("promises"):
		v["promises"] = []
	if not v.has("decor"):
		v["decor"] = ""
	v.version = 3

static func save_game(s: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(serialize(s))

static func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	return deserialize(f.get_as_text()) if f else {}

static func has_save() -> bool:
	return not load_game().is_empty()
