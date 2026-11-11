## Real-time cafe simulation. Two modes:
##   "business": the evening shift (customers, jobs, incidents).
##   "offhours": the cafe before opening / after closing — no customers, maids live their own lives.
## Pure logic: the 3D view only reads positions/labels from here.
extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")
const Layout = preload("res://scripts/core/layout.gd")
const World = preload("res://scripts/core/world.gd")
const Moments = preload("res://scripts/core/moments.gd")
const Life = preload("res://scripts/core/life.gd")

const DURATION := 240.0
const LAST_ARRIVAL := 200.0
const HARD_END := 300.0
const OPEN_HOUR := 17
const CLOSE_HOUR := 22
const MAX_CP := 5
const CP_REGEN := 40.0
const STEP := 0.1
const JOB_NAMES := {"greet": "帶位", "order": "點餐", "cook": "製作", "deliver": "送餐", "clean": "整理桌面", "mess": "清理地板",
	"complaint": "處理客訴", "repair": "修理設備", "seat_change": "換座位", "dispute": "調解糾紛", "tend": "照顧花瓶"}
const ROLE_WEIGHTS := {
	"reception": {"greet": 10, "order": 9, "complaint": 8, "dispute": 8, "seat_change": 7, "clean": 5, "deliver": 4, "mess": 4, "repair": 3, "cook": 0.5, "tend": 1},
	"kitchen": {"cook": 10, "repair": 5, "deliver": 3, "mess": 2, "clean": 1},
	"floor": {"deliver": 10, "mess": 9, "clean": 8, "seat_change": 6, "order": 6, "greet": 5, "complaint": 6, "dispute": 5, "repair": 3, "cook": 0.5, "tend": 2},
	"support": {},
}
## The "owner" role of each job type (used to detect when someone helps a colleague).
const JOB_ROLE := {"greet": "reception", "order": "reception", "cook": "kitchen", "deliver": "floor", "clean": "floor", "mess": "floor"}

# ======================================================================== agents
class Agent extends RefCounted:
	var id := ""
	var pos := Vector2.ZERO
	var cell := Vector2i.ZERO
	var path: Array = []
	var speed := 2.4
	var wait_t := 0.0
	var facing := 0.0
	var moving := false
	var inside := true
	var ghost := false
	var bubble := ""
	var bubble_until := 0.0

class Worker extends Agent:
	var kind := "maid"
	var maid_id := ""
	var name := ""
	var job = null
	var steps: Array = []
	var step_t := 0.0
	var step_dur := 0.0
	var activity := "待命"
	var paused := false
	var resting := false
	var rest_spot = null
	var carrying := ""
	var performing := false
	var leisure := {}
	var leisure_t := 0.0
	var decide_t := 0.0
	var job_t := 0.0
	var last_fail := ""
	var candidates: Array = []   # debug: last job evaluation

class Cust extends Agent:
	var party_id := ""
	var def_id := ""
	var name := ""
	var color := "888888"
	var hair := "2a2a2a"
	var sat := 60.0
	var causes := {}
	var seat = null
	var sitting := false
	var items: Array = []
	var pose := ""   # "photo", "read"

class Party extends RefCounted:
	var id := ""
	var members: Array = []
	var state := "arriving"
	var prev_state := ""
	var t := 0.0
	var table := ""
	var patience := 30.0
	var orders: Array = []
	var served_by := {}
	var handled := {}
	var complaint_done := false
	var paid := false
	var quality := -1.0
	var reasons: Array = []
	var waiting_for := ""      # companion def id still to arrive
	var stay_mul := 1.0
	var seat_checked := false
	var noise_t := 0.0
	var photo_done := false
	var preferred_maid := ""

# ======================================================================== state
var s: Dictionary
var mode := "business"
var layout
var rng: RandomNumberGenerator
var t := 0.0
var ended := false
var closed_flag := false
var workers: Array = []
var parties: Array = []
var orders: Array = []
var jobs: Array = []
var messes: Array = []
var notes: Array = []
var slots: Array = [null, null, null, null]
var station_busy := {}
var broken := {}
var dirty_tables := {}
var reserved_tables := {}
var arrivals: Array = []
var results: Array = []
var maid_stats := {}
var command_points := MAX_CP
var cp_timer := 0.0
var revenue := 0.0
var goods_revenue := 0.0
var served_count := 0
var lost := 0
var turned_away := 0
var complaints := 0
var complaints_handled := 0
var incidents := {}
var congestion := 0.0
var heat := {}
var stage_quality := 0.0
var door_closed := false
var boosts := {}           # name -> until time
var handoffs := {}         # pair key -> count
var helps: Array = []      # [{helper, helped, type}]
var moments_fired: Array = []
var co_present := {}       # pair key -> seconds both named customers present
var ac_broken := false
var moment_timer := 0.0
var _uid := 0
var _claims := {}
var sought := {}           # maid id -> already went to find the manager this session
var argued := {}           # pair key -> argued this session

func _init(p_state: Dictionary, p_mode := "business") -> void:
	s = p_state
	mode = p_mode
	layout = Layout.new(s.furniture, s.upgrades)
	rng = St.make_rng(s)
	if mode == "offhours":
		rng = RandomNumberGenerator.new()
		rng.seed = int(s.seed) + int(s.day) * 7919
	for st in layout.stations:
		station_busy[st.id] = ""
	var spawn := [Vector2i(11, 9), Vector2i(3, 2), Vector2i(5, 7), Vector2i(9, 4), Vector2i(7, 4)]
	var i := 0
	for m in St.active_maids(s):
		var role: String = m.role
		var c: Vector2i = spawn[i % spawn.size()]
		if role == "off":
			c = Layout.IDLE_SPOTS.off[0]
		elif Layout.IDLE_SPOTS.has(role):
			c = Layout.IDLE_SPOTS[role][0]
		if mode == "offhours":
			c = [Vector2i(8, 4), Vector2i(10, 7), Vector2i(4, 7), Vector2i(13, 8), Vector2i(9, 3), Vector2i(7, 9)][i % 6]
		c = _spawn_cell(c)
		workers.append(_make_worker("maid", m.id, Data.MAIDS[m.id].name, c))
		maid_stats[m.id] = {"tasks": 0.0, "greets": 0, "cooks": 0, "delivers": 0, "spills": 0, "wrong": 0, "complaints": 0,
			"happy": 0, "perform": 0.0, "solo": 0, "rest": 0.0, "idle": 0.0, "leisure": 0.0, "helped": 0, "regular_talks": 0}
		i += 1
	if mode == "business":
		workers.append(_make_worker("manager", "", "店長", Vector2i(8, 9)))
		_plan_arrivals()
		for w in workers:
			if w.kind != "maid":
				continue
			var m: Dictionary = s.maids[w.maid_id]
			if m.role == "off":
				continue
			var lines: Dictionary = Data.MAIDS[w.maid_id].lines
			if "overworked" in m.yesterday:
				say(w, lines.tired[0], 6)
			elif "complaint" in m.yesterday:
				say(w, "今天要更小心才行……", 6)
			elif "praised" in m.yesterday:
				say(w, lines.happy[0], 6)
		# wilted vases become work
		for f in s.furniture:
			if f.type == "vase" and int(s.vase_water.get(f.id, 0)) >= 1:
				_add_job("tend", {"furniture": f.id})
		note("開始營業！今天預計有 %d 組客人。" % arrivals.size())
	else:
		workers.append(_make_worker("manager", "", "店長", Vector2i(8, 9)))
		for f in s.furniture:
			if f.type == "vase" and int(s.vase_water.get(f.id, 0)) >= 1:
				_add_job("tend", {"furniture": f.id})

func _spawn_cell(c: Vector2i) -> Vector2i:
	var used := {}
	for w in workers:
		used[w.cell] = true
	if layout.walkable(c) and not used.has(c):
		return c
	var frontier := [c]
	var seen := {c: true}
	while not frontier.is_empty():
		var x: Vector2i = frontier.pop_front()
		for d in Layout.NEIGHBORS:
			var n: Vector2i = x + d
			if seen.has(n) or not layout.in_bounds(n):
				continue
			seen[n] = true
			if layout.walkable(n) and not used.has(n):
				return n
			frontier.append(n)
	return c

func _uid_next(p: String) -> String:
	_uid += 1
	return "%s%d" % [p, _uid]

func _make_worker(kind: String, maid_id: String, name: String, c: Vector2i) -> Worker:
	var w := Worker.new()
	w.id = maid_id if maid_id != "" else "manager"
	w.kind = kind
	w.maid_id = maid_id
	w.name = name
	w.cell = c
	w.pos = Vector2(c.x, c.y)
	w.decide_t = randf() * 1.5
	return w

func maid(id: String) -> Dictionary:
	return s.maids.get(id, {})

func manager() -> Worker:
	for w in workers:
		if w.kind == "manager":
			return w
	return null

func worker(id: String):
	for w in workers:
		if w.id == id:
			return w
	return null

func party(id: String):
	for p in parties:
		if p.id == id:
			return p
	return null

func order(id: String):
	for o in orders:
		if o.id == id:
			return o
	return null

func note(text: String, kind := "info") -> void:
	notes.append({"t": t, "text": text, "kind": kind})
	if notes.size() > 60:
		notes.pop_front()

func say(a, text: String, dur := 3.5) -> void:
	a.bubble = text
	a.bubble_until = t + dur

func clock() -> String:
	var mins := minf(t, DURATION) / DURATION * (CLOSE_HOUR - OPEN_HOUR) * 60.0
	return "%d:%02d" % [OPEN_HOUR + int(mins / 60.0), int(mins) % 60]

func skill(w: Worker, k: String) -> float:
	if w.kind == "manager":
		return float(Data.MANAGER_SKILLS[k])
	return float(maid(w.maid_id).skills[k])

static func speed_f(sk: float) -> float:
	return 1.4 - sk / 100.0 * 0.8

func has_trait(w: Worker, tr: String) -> bool:
	return w.kind == "maid" and tr in Data.MAIDS[w.maid_id].traits

func habit(w: Worker, h: String) -> float:
	return float(maid(w.maid_id).habits.get(h, 0.0)) if w.kind == "maid" else 0.0

func grow_habit(w: Worker, h: String, amount: float) -> void:
	if w.kind != "maid":
		return
	var m := maid(w.maid_id)
	m.habits[h] = St.clampf100(float(m.habits.get(h, 0.0)) + amount)

func boosted(name: String) -> bool:
	return float(boosts.get(name, -1.0)) > t

# ======================================================================== arrivals
func _plan_arrivals() -> void:
	var style: String = World.dominant_style(s).key
	var wd := Data.weekday(s.day)
	var sig_on := false
	for d in s.menu:
		if Data.DISHES[d].get("signature", false):
			sig_on = true
	var coming := {}
	var plans := []
	for id in Data.CUSTOMERS:
		var def: Dictionary = Data.CUSTOMERS[id]
		var mem: Dictionary = s.customers[id]
		if not mem.known or s.day < int(def.get("min_day", 0)):
			continue
		# their own life comes first: a deadline, a new job, a birthday
		var lm := Life.arrival_mod(s, id)
		if lm.skip:
			continue
		var reasons: Array = lm.reasons.duplicate()
		var ch := float(def.chance) + float(mem.loyalty) * 0.004 + (float(s.popularity) - 20.0) * 0.004 + float(lm.bonus)
		if float(mem.last_sat) >= 0:
			ch += (float(mem.last_sat) - 60.0) * 0.006
		if "walkedOut" in mem.last_causes or "complaintIgnored" in mem.last_causes:
			ch -= 0.25
			reasons.append("上次不愉快（-）")
		if mem.is_regular:
			ch += 0.15
			reasons.append("熟客")
		if int(mem.visits) == 0:
			ch += 0.15
			reasons.append("好奇第一次來")
		var days: Array = lm.get("weekdays", def.weekdays)
		var wd_mul := float(lm.chance)
		if not days.is_empty():
			if wd in days:
				wd_mul *= 1.6
				reasons.append("習慣星期%s來" % Data.WEEKDAYS[wd])
			else:
				wd_mul *= 0.3
		elif int(mem.visits) >= 3:
			var total := 0
			for v in mem.weekday_counts:
				total += int(v)
			if total > 0 and float(mem.weekday_counts[wd]) / total >= 0.4:
				ch += 0.15
				reasons.append("最近常在星期%s來" % Data.WEEKDAYS[wd])
		if def.style != "" and def.style == style:
			ch += 0.1
			reasons.append("喜歡店裡的風格")
		if s.get("decor", "") != "" and ("seasonal" in def.events or "curious_new" in def.behaviors):
			ch += 0.08
			reasons.append("被季節裝飾吸引")
		if s.activity in def.events:
			ch += 0.3
			reasons.append("對今天的活動有興趣")
		if s.activity == "limited" and s.featured_dish in def.likes:
			ch += 0.35
			reasons.append("限定料理是他愛吃的")
		if s.activity == "stage" and def.quiet:
			ch -= 0.2
		if s.activity == "meetup" and (mem.is_regular or float(mem.loyalty) >= 40):
			ch += 0.45
			reasons.append("受邀參加交流會")
		if s.activity == "birthday":
			var bm := _birthday_maid()
			if bm != "" and float(mem.affinity.get(bm, 0.0)) >= 10:
				ch += 0.4
				reasons.append("來替%s慶生" % Data.MAIDS[bm].name)
		if sig_on and def.pref == "dessert":
			ch += 0.15
			reasons.append("聽說有招牌甜點")
		var buzz := 0.0
		for d in def.likes:
			buzz += float(s.dish_buzz.get(d, 0.0))
		if buzz > 10 and (d_on_menu(def.likes)):
			ch += minf(0.2, buzz / 100.0)
			reasons.append("看到網路上的貼文")
		if s.weather == "rain" and not mem.is_regular:
			ch -= 0.1
		if "curious_new" in def.behaviors and not s.new_dishes.is_empty():
			ch += 0.2
			reasons.append("想試新菜單")
		if s.flags.get("invite_" + id, false):
			ch += 0.5
			reasons.append("聽秋子阿姨說店裡的人在擔心他")
		if id == "chizuru" and int(mem.story_stage) >= 1 and int(mem.visits) == 0:
			ch = 0.95
		ch = clampf(clampf(ch, 0.03, 0.95) * wd_mul, 0.03, 0.95)
		if rng.randf() < ch:
			coming[id] = true
			plans.append({"id": id, "reasons": reasons})
	# social pull: friends coming together, companions
	for r in Data.CUSTOMER_RELATIONS + _emergent_relations():
		var a: String = r.a
		var b: String = r.b
		if not s.customers[a].known or not s.customers[b].known:
			continue
		var rel: Dictionary = s.cust_rel.get(St.pair_key(a, b), {})
		if rel.is_empty():
			continue
		if coming.has(a) != coming.has(b) and float(rel.strength) >= 50 and rng.randf() < 0.35:
			var other := b if coming.has(a) else a
			if s.day >= int(Data.CUSTOMERS[other].get("min_day", 0)):
				coming[other] = true
				plans.append({"id": other, "reasons": ["和%s約好了" % Data.CUSTOMERS[a if other == b else b].name]})
	# build parties (companions arrive together)
	var used := {}
	for p in plans:
		var id: String = p.id
		if used.has(id):
			continue
		var def: Dictionary = Data.CUSTOMERS[id]
		var group := [id]
		used[id] = true
		var comp: String = def.get("companion", "")
		if comp != "" and coming.has(comp) and not used.has(comp):
			group.append(comp)
			used[comp] = true
		elif comp != "" and not coming.has(comp):
			# companion-bound customers only come with their companion (e.g. the couple)
			if Data.CUSTOMERS[comp].get("companion", "") == id:
				continue
		# companions that rely on this customer (riku with takagi)
		for other in Data.CUSTOMERS:
			if used.has(other) or not coming.has(other):
				continue
			if Data.CUSTOMERS[other].get("companion", "") == id:
				group.append(other)
				used[other] = true
				break
		var reasons: Array = p.reasons
		var waits := ""
		if group.size() > 1 and "waits_friend" in Data.CUSTOMERS[group[1]].behaviors:
			# the friend arrives first and waits
			waits = group[0]
			group = [group[1]]
		var size := group.size()
		var mem: Dictionary = s.customers[group[0]]
		if size == 1 and int(mem.visits) >= Data.FRIEND_VISITS and float(mem.loyalty) >= Data.FRIEND_LOYALTY and rng.randf() < 0.45:
			size = 2
			reasons = reasons + ["帶朋友來"]
		var win: Array = Life.arrival_mod(s, id).get("arrival", def.arrival)
		var tt := rng.randf_range(float(win[0]), minf(float(win[1]), LAST_ARRIVAL))
		arrivals.append({"t": tt, "ids": group, "size": maxi(size, group.size()), "reasons": reasons, "done": false, "waits_for": waits})
		if waits != "":
			arrivals.append({"t": minf(LAST_ARRIVAL, tt + rng.randf_range(15, 45)), "ids": [waits], "size": 1, "reasons": ["約了朋友"], "done": false, "join": true})
	# referrals: loyal customers introduce someone new
	for rid in Data.REFERRALS:
		var ref: Dictionary = Data.REFERRALS[rid]
		var from_mem: Dictionary = s.customers[ref.from]
		if not s.customers[rid].known and coming.has(ref.from) and float(from_mem.loyalty) >= float(ref.loyalty):
			for a in arrivals:
				if ref.from in a.ids and not a.get("join", false):
					a.ids.append(rid)
					a.size = maxi(a.size, a.ids.size())
					a.reasons.append("帶%s來介紹給店裡" % Data.CUSTOMERS[rid].name)
					a["referral"] = rid
					break
	# walk-ins: popularity, reputation, buzz, weather, events
	var walk := int(1.0 + float(s.popularity) / 15.0)
	walk += int(maxf(0.0, (float(s.reputation) - 55.0) / 10.0))
	var buzz_total := 0.0
	for d in s.menu:
		buzz_total += float(s.dish_buzz.get(d, 0.0))
	walk += int(minf(3.0, buzz_total / 25.0))
	match s.activity:
		"stage", "street_music":
			walk += 3
		"costume":
			walk += 1
		"limited", "seasonal":
			walk += 2
		"craft_fair":
			walk += 2
	if s.weather == "rain":
		walk += 2
	if s.street.get("event", "") == "festival":
		walk += 3
	var fame_maid := ""
	var best_fame := 30.0
	for m in St.active_maids(s):
		if m.role != "off" and float(s.maid_fame.get(m.id, 0.0)) > best_fame:
			best_fame = float(s.maid_fame.get(m.id, 0.0))
			fame_maid = m.id
	for k in walk:
		var reasons := ["路過"]
		if s.weather == "rain" and k < 2:
			reasons = ["躲雨"]
		elif buzz_total > 20 and k % 3 == 0:
			reasons = ["看到網路貼文"]
		elif fame_maid != "" and k % 4 == 1:
			reasons = ["想見%s" % Data.MAIDS[fame_maid].name]
		arrivals.append({"t": rng.randf_range(5, LAST_ARRIVAL), "ids": [], "size": 2 if rng.randf() < 0.3 else 1, "reasons": reasons, "done": false,
			"fan_of": fame_maid if reasons[0].begins_with("想見") else ""})
	arrivals.sort_custom(func(a, b): return a.t < b.t)

func d_on_menu(ids: Array) -> bool:
	for d in ids:
		if d in s.menu:
			return true
	return false

func _emergent_relations() -> Array:
	var out := []
	for k in s.cust_rel:
		var r: Dictionary = s.cust_rel[k]
		if r.type == "acquaintance":
			var p: PackedStringArray = k.split("|")
			out.append({"a": p[0], "b": p[1], "type": "acquaintance"})
	return out

func _birthday_maid() -> String:
	var yd := ((int(s.day) - 1) % Data.YEAR_DAYS) + 1
	for m in St.active_maids(s):
		if int(Data.MAIDS[m.id].birthday) == yd:
			return m.id
	return ""

const ANON_NAMES := ["路過的上班族", "散步的學生", "觀光客", "附近的上班族", "好奇的路人", "情侶客人"]
const ANON_COLORS := ["8a7a6a", "6a8aa0", "a07a8a", "7aa07a", "9a9a6a", "6a6aa0"]

func _spawn(a: Dictionary) -> void:
	if a.get("join", false):
		# a late friend joining a waiting party
		for p in parties:
			if p.waiting_for == a.ids[0] and p.state in ["waitFriend", "browsing"]:
				var c := _make_cust(p.id, a.ids[0], 1)
				c.pos = Vector2(Layout.DOOR.x, 13.5)
				p.members.append(c)
				c.seat = null
				p.waiting_for = ""
				say(p.members[0], "啊，你終於來了！", 3)
				return
		# friend never found (the waiting one left): come alone
		a.erase("join")
	if door_closed:
		turned_away += maxi(1, a.size)
		return
	var p := Party.new()
	p.id = _uid_next("p")
	p.reasons = a.reasons
	p.waiting_for = a.get("waits_for", "")
	p.preferred_maid = a.get("fan_of", "")
	var anon_name: String = "表演觀眾" if s.activity in ["stage", "street_music"] and rng.randf() < 0.5 else ANON_NAMES[rng.randi() % ANON_NAMES.size()]
	if a.reasons.size() > 0 and a.reasons[0] == "躲雨":
		anon_name = "躲雨的客人"
	for i in a.size:
		var did: String = a.ids[i] if i < a.ids.size() else ""
		var c := _make_cust(p.id, did, i)
		if did == "":
			c.name = anon_name if i == 0 else ("%s的朋友" % Data.CUSTOMERS[a.ids[0]].name if a.ids.size() > 0 else "同行的人")
			c.color = ANON_COLORS[rng.randi() % ANON_COLORS.size()]
		p.members.append(c)
	var main: Cust = p.members[0]
	var def: Dictionary = Data.CUSTOMERS.get(main.def_id, {})
	var mem: Dictionary = s.customers.get(main.def_id, {})
	p.patience = float(def.get("patience", 30))
	if not mem.is_empty():
		if "longWaitDoor" in mem.last_causes or "longWaitFood" in mem.last_causes:
			p.patience *= 0.8
		p.patience *= 1.0 + float(mem.loyalty) / 250.0
	if s.weather == "rain":
		p.stay_mul *= 1.3
	if "reader" in def.get("behaviors", []):
		p.stay_mul *= 1.5
	parties.append(p)
	# memory-driven greeting line
	if not def.is_empty():
		var here := []
		for op in parties:
			for om in op.members:
				if om.def_id != "" and op != p:
					here.append(om.def_id)
		var line := Life.arrival_line(s, main.def_id, here)
		if line == "":
			line = _arrival_line(def, mem)
		if line != "":
			say(main, line, 6)
		var fav: String = mem.fav_maid
		if fav != "" and not _maid_working(fav):
			main.sat -= 4
			main.causes["favMaidAbsent"] = true
			say(main, "今天%s不在啊……" % Data.MAIDS[fav].name, 6)
		if "asks_maid" in def.behaviors and fav != "":
			say(main, "今天%s有上班嗎？" % Data.MAIDS[fav].name, 5)
		if a.has("referral"):
			note("🤝 %s帶了%s來店裡！" % [def.name, Data.CUSTOMERS[a.referral].name], "good")
		elif a.size > 1 and a.ids.size() == 1 and not mem.brought_friend:
			note("⭐ %s第一次帶朋友來了！" % def.name, "good")
	if p.waiting_for != "":
		say(main, "我在等%s……" % Data.CUSTOMERS[p.waiting_for].name, 5)

func _make_cust(pid: String, did: String, i: int) -> Cust:
	var c := Cust.new()
	c.id = _uid_next("c")
	c.party_id = pid
	c.def_id = did
	var def: Dictionary = Data.CUSTOMERS.get(did, {})
	c.name = def.get("name", "客人")
	c.color = def.get("color", "888888")
	c.hair = def.get("hair", "2a2a2a")
	c.sat = 65.0 if did != "" else 60.0
	c.pos = Vector2(9.0 + (0.6 if i else 0.0) + (-5.0 if rng.randf() < 0.5 else 5.0), 13.5)
	c.cell = Layout.DOOR
	c.inside = false
	c.moving = true
	c.speed = 2.0
	return c

func _arrival_line(def: Dictionary, mem: Dictionary) -> String:
	if int(mem.visits) == 0:
		return "……就是這間店啊。" if def.kind == "special" else "打擾了～"
	var c: Array = mem.last_causes
	if "complaintIgnored" in c or "walkedOut" in c:
		return "上次的事……再給一次機會吧。"
	if "longWaitFood" in c or "longWaitDoor" in c:
		return "上次等好久……今天希望快一點。"
	if "noisy" in c and def.quiet:
		return "今天應該比較安靜吧？"
	if mem.fav_maid != "" and _maid_working(mem.fav_maid):
		return "今天也想讓%s服務！" % Data.MAIDS[mem.fav_maid].name
	if mem.fav_dish != "" and int(mem.dish_counts.get(mem.fav_dish, 0)) >= 2:
		return "老樣子，%s。" % Data.DISHES[mem.fav_dish].name
	if mem.is_regular:
		return "我又來了。"
	return "又來了～"

func _maid_working(id: String) -> bool:
	var m := maid(id)
	return not m.is_empty() and id in s.staff and not m.quit and m.role != "off"

# ======================================================================== update
func update(dt: float) -> void:
	if ended:
		return
	while dt > 0.0:
		var d := minf(STEP, dt)
		_tick(d)
		dt -= d
		if ended:
			break

func _tick(dt: float) -> void:
	t += dt
	cp_timer += dt
	if cp_timer >= CP_REGEN:
		cp_timer = 0.0
		command_points = mini(MAX_CP, command_points + 1)
	if mode == "business":
		for a in arrivals:
			if not a.done and float(a.t) <= t:
				a.done = true
				_spawn(a)
	_rebuild_claims()
	for p in parties:
		_update_party(p, dt)
	parties = parties.filter(func(p): return p.state != "gone")
	_refresh_jobs()
	for w in workers:
		_update_worker(w, dt)
	_update_moods(dt)
	if mode == "business":
		_environment(dt)
		moment_timer += dt
		if moment_timer >= 8.0:
			moment_timer = 0.0
			_social_tick()
		if t >= DURATION and not closed_flag:
			closed_flag = true
			note("🔔 打烊時間到了，不再接新客人。")
			for p in parties:
				if p.state in ["queue", "arriving"]:
					_leave(p, false, true)
		if t >= DURATION and (parties.is_empty() or t >= HARD_END):
			for p in parties.duplicate():
				_finish_party(p, true)
			ended = true
			St.store_rng(s, rng)

# ---------------------------------------------------------------- movement
func _movers() -> Array:
	var out: Array = workers.duplicate()
	for p in parties:
		out.append_array(p.members)
	return out

func _rebuild_claims() -> void:
	_claims.clear()
	for m in _movers():
		if not m.inside or (m is Cust and m.sitting):
			continue
		if layout.walkable(m.cell):
			_claims[Layout.key(m.cell)] = m.id
		if m.moving and not m.path.is_empty():
			_claims[Layout.key(m.path[0])] = m.id

func set_path(m, goals: Array, allow_goal := false, avoid := false) -> bool:
	var av := {}
	if avoid:
		for k in _claims:
			if _claims[k] != m.id:
				av[k] = true
	var p = layout.find_path(m.cell, goals, allow_goal, av)
	if p == null:
		return false
	m.path = p
	m.moving = not p.is_empty()
	m.wait_t = 0.0
	return true

## Advance along the path. Returns true when the path is complete.
func move(m, dt: float, mul := 1.0) -> bool:
	if m.path.is_empty():
		m.moving = false
		return true
	var nxt: Vector2i = m.path[0]
	var nk := Layout.key(nxt)
	var owner = _claims.get(nk, "")
	var at_center := absf(m.pos.x - m.cell.x) < 0.01 and absf(m.pos.y - m.cell.y) < 0.01
	if at_center and owner != "" and owner != m.id and not m.ghost and layout.walkable(nxt):
		m.wait_t += dt
		congestion += dt
		heat[nk] = float(heat.get(nk, 0.0)) + dt
		# the destination itself is occupied by someone standing still: stop next to it instead of stacking
		if m.path.size() == 1 and m.wait_t > 1.4:
			var occ = _agent_by_id(owner)
			if occ != null and occ.path.is_empty():
				m.path.clear()
				m.moving = false
				m.wait_t = 0.0
				return true
		if m.wait_t > 1.4 and m.wait_t - dt <= 1.4:
			var goal: Vector2i = m.path[m.path.size() - 1]
			set_path(m, [goal], not layout.walkable(goal), true)
			m.wait_t = 1.41
		if m.wait_t > 3.0:
			m.ghost = true
		return false
	_claims[nk] = m.id
	var target := Vector2(nxt.x, nxt.y)
	var delta: Vector2 = target - m.pos
	var dist := delta.length()
	var step: float = m.speed * mul * dt
	if dist > 0.0001:
		m.facing = atan2(delta.x, delta.y)
	if dist <= step:
		m.pos = target
		if _claims.get(Layout.key(m.cell), "") == m.id:
			_claims.erase(Layout.key(m.cell))
		m.cell = nxt
		m.path.pop_front()
		m.ghost = false
		m.wait_t = 0.0
		if m is Cust:
			for ms in messes:
				if ms.cell == m.cell and not m.causes.has("spill"):
					m.sat -= 3
					m.causes["spill"] = true
	else:
		m.pos += delta / dist * step
	m.moving = not m.path.is_empty()
	return m.path.is_empty()

func _agent_by_id(id: String):
	for m in _movers():
		if m.id == id:
			return m
	return null

## True when no other worker stands on, walks to, or rests at this cell.
func _cell_free_for(w: Worker, c: Vector2i) -> bool:
	for o in workers:
		if o == w:
			continue
		if o.cell == c:
			return false
		if not o.leisure.is_empty() and o.leisure.cell == c:
			return false
		if o.rest_spot != null and o.rest_spot == c:
			return false
		if not o.path.is_empty() and o.path[o.path.size() - 1] == c:
			return false
	return true

func _free_adjacent(w: Worker, cells: Array):
	for c in layout.adjacent_walkable(cells):
		if _cell_free_for(w, c):
			return c
	return null

func lerp_to(m, target: Vector2, dt: float) -> bool:
	var d: Vector2 = target - m.pos
	var len := d.length()
	var step: float = m.speed * dt
	if len > 0.001:
		m.facing = atan2(d.x, d.y)
	if len <= step:
		m.pos = target
		m.moving = false
		return true
	m.moving = true
	m.pos += d / len * step
	return false

# ---------------------------------------------------------------- parties
func queue_index(p: Party) -> int:
	var i := 0
	for x in parties:
		if x == p:
			return i
		if x.state in ["queue", "arriving"]:
			i += 1
	return 0

func _update_party(p: Party, dt: float) -> void:
	p.t += dt
	var main: Cust = p.members[0]
	var def: Dictionary = Data.CUSTOMERS.get(main.def_id, {})
	match p.state:
		"arriving", "queue":
			var qi := queue_index(p)
			for i in p.members.size():
				var m: Cust = p.members[i]
				var target := Vector2(Layout.DOOR.x + (0.55 if i else 0.0) - 0.25 * (p.members.size() - 1), Layout.DOOR.y + 1.2 + qi * 0.9)
				if lerp_to(m, target, dt) and p.state == "arriving":
					p.state = "queue"
					p.t = 0.0
				m.facing = PI
			if p.state == "queue" and p.t > p.patience * 0.5:
				for m in p.members:
					m.sat -= 0.4 * dt
			if p.state == "queue" and p.t > p.patience:
				for m in p.members:
					m.causes["longWaitDoor"] = true
				say(main, "等太久了，下次再來吧……", 4)
				note("%s在門口等太久，離開了。" % main.name, "warn")
				_leave(p, false)
		"toSeat", "moving":
			var all := true
			for m in p.members:
				if not m.inside:
					if lerp_to(m, Vector2(Layout.DOOR.x, Layout.DOOR.y), dt):
						m.inside = true
						m.cell = Layout.DOOR
						if m.seat != null:
							set_path(m, [m.seat], true)
					all = false
					continue
				if not m.sitting:
					if m.seat == null:
						_assign_seat(p, m)
					if move(m, dt) and m.seat != null and m.cell == m.seat:
						m.sitting = true
						var tb = layout.table_by_id(p.table)
						if tb != null:
							m.facing = atan2(tb.cell.x - m.seat.x, 0)
					elif m.path.is_empty() and m.seat != null and m.cell != m.seat:
						if not set_path(m, [m.seat], true):
							m.cell = m.seat
							m.pos = Vector2(m.seat.x, m.seat.y)
					all = false
			if all:
				if p.state == "moving":
					p.state = p.prev_state
				elif p.waiting_for != "":
					p.state = "waitFriend"
				else:
					p.state = "browsing"
				p.t = 0.0
		"waitFriend":
			if p.waiting_for == "":
				p.state = "toSeat"   # friend arrived: let them sit, then browse
				p.t = 0.0
			elif p.t > 60.0:
				say(main, "……他好像不來了。", 4)
				p.waiting_for = ""
				p.state = "browsing"
				_fire_moment("waits_friend_late", "%s等朋友等了好久。最後一個人點了餐。" % main.name, [main.def_id])
		"browsing":
			_check_seat_wish(p)
			if p.t > 3.0:
				p.state = "waitOrder"
				p.t = 0.0
				var pref := _pref_maid(p)
				var j := _add_job("order", {"party": p.id, "preferred": pref})
				if _is_regular(p) and boosted("regulars"):
					j.boost = 150.0
		"waitOrder", "waitFood":
			var grace := 12.0 if p.state == "waitOrder" else 32.0
			var drain := 0.8 if p.state == "waitOrder" else 0.55
			if p.t > grace * (p.patience / 30.0):
				for m in p.members:
					m.sat -= drain * dt * (1.3 if ac_broken else 1.0)
					m.causes["longWaitOrder" if p.state == "waitOrder" else "longWaitFood"] = true
			_noise_check(p, dt)
			if main.sat < 25 and not p.complaint_done:
				p.prev_state = p.state
				p.state = "angry"
				p.t = 0.0
				complaints += 1
				say(main, "💢 到底還要等多久！叫負責人來！", 8)
				note("💢 %s發脾氣了！請店長（或管理能力高的女僕）去處理。" % main.name, "warn")
				_add_job("complaint", {"party": p.id, "preferred": "manager"})
			elif main.sat < 8:
				say(main, "……算了。", 4)
				note("%s受不了等待，離開了。" % main.name, "warn")
				for m in p.members:
					m.causes["walkedOut"] = true
				_leave(p, false)
		"angry":
			if p.t > 25.0:
				for m in p.members:
					m.causes["complaintIgnored"] = true
				say(main, "這種店不會再來了！", 5)
				note("%s氣沖沖地離開了。口碑下降。" % main.name, "warn")
				s.popularity = St.clampf100(float(s.popularity) - 3)
				s.reputation = St.clampf100(float(s.reputation) - 3)
				_leave(p, false)
		"eating":
			var eat_dur := (16.0 + main.items.size() * 4.0) * p.stay_mul
			var tb = layout.table_by_id(p.table)
			if tb != null and tb.type == "sofa_table":
				eat_dur *= 1.25
				for m in p.members:
					m.sat += 0.04 * dt
			_apply_show(p, dt)
			_noise_check(p, dt)
			_eating_behaviors(p, dt)
			if p.t > eat_dur:
				_leave(p, true)
		"leaving":
			var all := true
			for m in p.members:
				if m.inside:
					if m.sitting:
						m.sitting = false
						var adj: Array = layout.adjacent_walkable([m.seat])
						if not adj.is_empty():
							m.cell = adj[0]
							m.pos = Vector2(adj[0].x, adj[0].y)
						set_path(m, [Layout.DOOR])
					if move(m, dt):
						if m.cell == Layout.DOOR:
							m.inside = false
						elif not set_path(m, [Layout.DOOR]):
							m.inside = false
					all = false
				else:
					var side := -7.0 if m.id.length() % 2 else 7.0
					if not lerp_to(m, Vector2(Layout.DOOR.x + side, 13.5), dt):
						all = false
			if all:
				_finish_party(p, false)

func _assign_seat(p: Party, m: Cust) -> void:
	var tb = layout.table_by_id(p.table)
	if tb == null:
		return
	var taken := {}
	for o in p.members:
		if o != m and o.seat != null:
			taken[Layout.key(o.seat)] = true
	for st in tb.seats:
		if not taken.has(Layout.key(st)):
			m.seat = st
			set_path(m, [st], true)
			return
	m.seat = tb.seats[0]
	set_path(m, [m.seat], true)

func _is_regular(p: Party) -> bool:
	var did: String = p.members[0].def_id
	return did != "" and s.customers[did].is_regular

func _pref_maid(p: Party) -> String:
	var did: String = p.members[0].def_id
	if did == "":
		return p.preferred_maid if _maid_working(p.preferred_maid) else ""
	var fav: String = s.customers[did].fav_maid
	return fav if fav != "" and _maid_working(fav) else ""

## Seat-change request: the customer wanted a different kind of seat and one is free now.
func _check_seat_wish(p: Party) -> void:
	if p.seat_checked:
		return
	p.seat_checked = true
	var def: Dictionary = Data.CUSTOMERS.get(p.members[0].def_id, {})
	var want: String = def.get("seat", "any")
	if want == "any":
		return
	var tb = layout.table_by_id(p.table)
	if tb == null or tb.tags.has(want):
		return
	for t2 in layout.tables:
		if t2.tags.has(want) and not reserved_tables.has(t2.id) and not dirty_tables.has(t2.id):
			say(p.members[0], "那個……可以換到那邊的位子嗎？", 4)
			_add_job("seat_change", {"party": p.id, "target": t2.id})
			incidents["seat_change"] = int(incidents.get("seat_change", 0)) + 1
			return
	p.members[0].sat -= 2
	p.members[0].causes["seatUnhappy"] = true

func _noise_level() -> float:
	var n := 0.0
	for p in parties:
		if p.state in ["eating", "waitFood", "waitOrder", "browsing"]:
			for m in p.members:
				var def: Dictionary = Data.CUSTOMERS.get(m.def_id, {})
				if def.get("lively", false) or m.def_id == "":
					n += 0.6
	if stage_quality > 0:
		n += 3.0
	if s.music == "pop":
		n += 1.5
	return n

## Quiet customers next to noisy ones get annoyed; may turn into a dispute that needs mediating.
func _noise_check(p: Party, dt: float) -> void:
	var main: Cust = p.members[0]
	var def: Dictionary = Data.CUSTOMERS.get(main.def_id, {})
	if not def.get("quiet", false):
		return
	var tb = layout.table_by_id(p.table)
	if tb == null or tb.tags.has("private"):
		return
	var noise := _noise_level()
	if noise < 4.0:
		return
	p.noise_t += dt
	main.sat -= 0.05 * dt
	main.causes["noisy"] = true
	if p.noise_t > 20.0 and not p.handled.has("dispute") and not _has_job("dispute", p.id):
		p.handled["dispute"] = "pending"
		say(main, "隔壁也太吵了吧……", 5)
		note("😤 %s覺得太吵，和隔壁起了口角。" % main.name, "warn")
		incidents["dispute"] = int(incidents.get("dispute", 0)) + 1
		_add_job("dispute", {"party": p.id, "preferred": "manager"})

func _has_job(type: String, pid: String) -> bool:
	for j in jobs:
		if j.type == type and j.get("party", "") == pid and not j.done and not j.cancelled:
			return true
	return false

func _apply_show(p: Party, dt: float) -> void:
	if stage_quality <= 0.0:
		return
	var tb = layout.table_by_id(p.table)
	for m in p.members:
		var def: Dictionary = Data.CUSTOMERS.get(m.def_id, {})
		if def.get("quiet", false):
			if tb == null or not tb.tags.has("private"):
				m.sat -= 0.18 * dt
				m.causes["noisy"] = true
		else:
			m.sat += stage_quality * (0.3 if def.get("lively", true) else 0.15) * dt
			m.causes["enjoyedShow"] = true

## Customer quirks while eating: photographers shoot food, readers read, observers watch.
func _eating_behaviors(p: Party, dt: float) -> void:
	for m in p.members:
		var def: Dictionary = Data.CUSTOMERS.get(m.def_id, {})
		var bh: Array = def.get("behaviors", [])
		if "photographer" in bh and not p.photo_done and p.t > 2.0:
			p.photo_done = true
			var dish: String = m.items[0] if not m.items.is_empty() else ""
			var good: bool = p.quality >= 62.0 or (dish != "" and (Data.DISHES[dish].get("signature", false) or Data.DISHES[dish].has("season") or Data.DISHES[dish].get("collab", false)))
			m.pose = "photo"
			if good and dish != "":
				say(m, "📸 好可愛！要上傳！", 4)
				var gain := 6.0 if m.def_id == "nanami" else 3.0
				if not layout.furniture_cells("photo").is_empty():
					gain += 2.0
				s.dish_buzz[dish] = float(s.dish_buzz.get(dish, 0.0)) + gain
				s.reputation = St.clampf100(float(s.reputation) + gain * 0.15)
				m.causes["posted"] = true
				if m.def_id == "nanami":
					note("📸 七海把%s拍下來上傳了！明天可能會有人看到貼文來。" % Data.DISHES[dish].name, "good")
			else:
				say(m, "📸 ……嗯，這張先不發好了。", 3)
		if "reader" in bh and p.t > 4.0 and m.pose == "":
			m.pose = "read"
			var tb = layout.table_by_id(p.table)
			if tb != null and tb.tags.has("bookshelf"):
				m.sat += 4
				m.causes["bookshelf"] = true
				say(m, "（從書架上拿了一本書）", 3)
			else:
				say(m, "（翻開帶來的書）", 3)
		if "observer" in bh and int(p.t * 10) % 120 == 60:
			var busy := ""
			for w in workers:
				if w.kind == "maid" and w.job != null:
					busy = w.name
					break
			if busy != "":
				say(m, "那位%s好認真呢。" % busy, 3)

func _leave(p: Party, served: bool, closing := false) -> void:
	if p.state in ["leaving", "gone"]:
		return
	for j in jobs:
		if j.get("party", "") == p.id and not j.done:
			j.cancelled = true
	for o in orders:
		if o.party == p.id and o.slot >= 0 and slots[o.slot] == o.id:
			slots[o.slot] = null
	if p.table != "":
		reserved_tables.erase(p.table)
		var sat_in := false
		for m in p.members:
			if m.inside:
				sat_in = true
		if sat_in:
			dirty_tables[p.table] = true
			_add_job("clean", {"table": p.table})
	if served and not p.paid:
		p.paid = true
		var total := 0.0
		for m in p.members:
			for it in m.items:
				var price := float(Data.DISHES[it].price)
				if it == s.featured_dish and s.activity == "limited":
					price *= 1.25
				total += roundf(price)
		revenue += total
		s.money = float(s.money) + total
		served_count += p.members.size()
		var main: Cust = p.members[0]
		var sat := main.sat
		say(main, "好開心！我還會再來的！" if sat >= 75 else ("謝謝招待～" if sat >= 50 else "嗯……"), 4)
		# display-case goods
		if not layout.furniture_cells("display").is_empty() and sat >= 65:
			var goods := 300.0
			if s.activity == "craft_fair":
				goods = 450.0
			if "sweets_collab" in s.partners or s.activity == "craft_fair" or sat >= 78:
				goods_revenue += goods
				revenue += goods
				s.money = float(s.money) + goods
				main.causes["boughtGoods"] = true
		for mid in p.served_by:
			if maid(mid).is_empty():
				continue
			if sat >= 75:
				maid(mid).mood = St.clampf100(float(maid(mid).mood) + 3)
				maid_stats[mid].happy += 1
				s.maid_fame[mid] = float(s.maid_fame.get(mid, 0.0)) + 0.8
			elif sat < 35:
				maid(mid).mood = St.clampf100(float(maid(mid).mood) - 2)
	elif not closing:
		lost += p.members.size()
	p.state = "leaving"
	p.t = 0.0
	for m in p.members:
		if not m.inside:
			m.moving = true

func _finish_party(p: Party, forced: bool) -> void:
	if p.state == "gone":
		return
	if forced and not p.paid and p.state == "eating":
		_leave(p, true)
	p.state = "gone"
	if p.table != "":
		reserved_tables.erase(p.table)
	var anchor: String = p.members[0].def_id
	for m in p.members:
		var paid := 0.0
		if p.paid:
			for it in m.items:
				paid += float(Data.DISHES[it].price)
		results.append({
			"def": m.def_id, "name": m.name, "sat": clampf(m.sat, 0, 100), "causes": m.causes.keys(), "items": m.items,
			"paid": paid, "served_by": p.served_by.keys(), "table": p.table,
			"friend_of": anchor if m.def_id == "" and anchor != "" else "",
			"affinity": m.get_meta("aff", {}), "quality": p.quality, "reasons": p.reasons,
			"party_defs": p.members.map(func(x): return x.def_id).filter(func(x): return x != ""),
		})

# ---------------------------------------------------------------- jobs
func _add_job(type: String, o := {}) -> Dictionary:
	var j := {"id": _uid_next("j"), "type": type, "created": t, "claimed": "", "preferred": "", "done": false, "cancelled": false, "boost": 0.0, "fails": 0}
	j.merge(o, true)
	jobs.append(j)
	return j

func _refresh_jobs() -> void:
	jobs = jobs.filter(func(j): return not j.done and not j.cancelled)
	for p in parties:
		if p.state == "queue" and not _has_job("greet", p.id):
			var j := _add_job("greet", {"party": p.id, "preferred": _pref_maid(p)})
			if _is_regular(p) and boosted("regulars"):
				j.boost = 150.0

func job_available(j: Dictionary, w: Worker) -> String:
	## "" when the worker can start the job now, otherwise the reason (shown in the debug panel).
	if j.done or j.cancelled:
		return "已完成"
	match j.type:
		"greet":
			var p = party(j.get("party", ""))
			if p == null or p.state != "queue":
				return "客人不在門口"
			if _free_table(p) == "":
				return "沒有空桌"
		"cook":
			var o = order(j.get("order", ""))
			if o == null:
				return "訂單消失"
			if _free_station(o) == "":
				return "爐具忙碌或故障"
			if not slots.has(null):
				return "出餐台滿了"
		"complaint", "dispute":
			if w.kind != "manager" and skill(w, "management") < 50:
				return "管理能力不足 50"
		"repair":
			if w.kind != "manager" and skill(w, "management") < 55:
				return "管理能力不足 55"
		"seat_change":
			var tid: String = j.get("target", "")
			if reserved_tables.has(tid) or dirty_tables.has(tid):
				return "目標座位被占用"
	return ""

func _job_anchor(j: Dictionary):
	match j.type:
		"greet":
			return Layout.GREET_SPOT
		"order", "complaint", "dispute", "seat_change":
			var p = party(j.get("party", ""))
			if p != null and p.table != "":
				return layout.table_by_id(p.table).cell
			return null
		"cook":
			return layout.stations[0].stand
		"deliver":
			var o = order(j.get("order", ""))
			return PASS(o.slot) if o != null and o.slot >= 0 else null
		"clean":
			var tb = layout.table_by_id(j.get("table", ""))
			return tb.cell if tb != null else null
		"mess":
			for ms in messes:
				if ms.id == j.get("mess", ""):
					return ms.cell
			return null
		"repair":
			return _repair_cell(j.get("target", ""))
		"tend":
			for f in s.furniture:
				if f.id == j.get("furniture", ""):
					return Vector2i(int(f.x), int(f.z))
			return null
	return null

static func PASS(i: int) -> Vector2i:
	return Layout.PASS_SLOTS[i]

func _repair_cell(target: String) -> Vector2i:
	if target == "aircon":
		return Vector2i(9, 1)
	for st in layout.stations:
		if st.id == target:
			return st.stand
	return Vector2i(9, 1)

func _role_of(w: Worker) -> String:
	return "manager" if w.kind == "manager" else String(maid(w.maid_id).role)

func _backlog(type: String) -> int:
	var n := 0
	for j in jobs:
		if j.type == type and j.claimed == "" and not j.done and not j.cancelled:
			n += 1
	return n

## Worker currently "responsible" for a job type's role (to credit help).
func _owner_of(type: String, exclude: Worker):
	var role: String = JOB_ROLE.get(type, "")
	for w in workers:
		if w != exclude and w.kind == "maid" and maid(w.maid_id).role == role:
			return w
	return null

## Job selection with explainable scores. Fills w.candidates for the debug panel.
func pick_job(w: Worker):
	var m := maid(w.maid_id)
	var role: String = m.role
	var weights: Dictionary = ROLE_WEIGHTS.get(role, {})
	var kitchen_staffed := false
	for x in workers:
		if x.kind == "maid" and maid(x.maid_id).role == "kitchen" and not x.paused and not x.resting:
			kitchen_staffed = true
	var best = null
	var best_score := -INF
	var cands := []
	var avoid_id := _avoided_colleague(w)
	for j in jobs:
		if j.claimed != "" or j.done or j.cancelled:
			continue
		var why := []
		var wgt := float(weights.get(j.type, 0.0))
		if role == "support":
			# support follows the biggest backlog, but leaves the stove to the kitchen when someone is there
			wgt = 4.0 + _backlog(j.type) * 2.0
			if j.type == "cook" and kitchen_staffed:
				wgt = 1.0 + _backlog(j.type) * 0.5
			why.append("支援：積壓 %d" % _backlog(j.type))
		if j.type == "cook" and not kitchen_staffed and wgt < 1:
			wgt = 6.0
			why.append("廚房沒人")
		# helping colleagues: backlog in someone else's area
		var owner_role: String = JOB_ROLE.get(j.type, "")
		if owner_role != "" and owner_role != role and role != "support" and _backlog(j.type) >= 2:
			var helpf := 1.0 + habit(w, "help") / 40.0 + (1.5 if has_trait(w, "caring") else 0.0)
			var ow = _owner_of(j.type, w)
			if ow != null:
				helpf += float(St.rel(s, w.maid_id, ow.maid_id).trust) / 50.0
			wgt = maxf(wgt, 2.0 * helpf)
			why.append("補位 x%.1f" % helpf)
		if boosted("floor") and j.type in ["deliver", "clean", "mess"]:
			wgt += 3.0
			why.append("外場優先")
		if boosted("job_" + j.type):
			wgt += 4.0
			why.append("指定優先")
		if wgt <= 0.0:
			continue
		var reason := job_available(j, w)
		if reason != "":
			cands.append({"job": j.id, "type": j.type, "score": -1, "why": reason})
			continue
		var anchor = _job_anchor(j)
		var dist := Layout.manhattan(w.cell, anchor) if anchor != null else 0
		var score := wgt * 100.0 - dist * 3.0 + minf(60.0, (t - float(j.created)) * 2.0) + float(j.get("boost", 0.0))
		if j.preferred != "" and j.preferred == w.maid_id:
			score += 120.0
			why.append("被指名")
		elif j.preferred != "" and j.preferred != "manager":
			score -= 40.0
		if avoid_id != "" and anchor != null:
			var aw = worker(avoid_id)
			if aw != null and Layout.manhattan(aw.cell, anchor) <= 3:
				score -= 70.0
				why.append("避開%s" % aw.name)
		if role != "" and m.get("preferred_role", "") != "" and JOB_ROLE.get(j.type, "") == m.preferred_role:
			score += 15.0
		why.push_front("距離 %d" % dist)
		cands.append({"job": j.id, "type": j.type, "score": int(score), "why": ", ".join(why)})
		if score > best_score:
			best_score = score
			best = j
	cands.sort_custom(func(a, b): return a.score > b.score)
	w.candidates = cands.slice(0, 6)
	# low mood maids sometimes slack off when the work isn't urgent
	if best != null and float(m.mood) < 30 and best_score < 700 and rng.randf() < 0.3:
		w.last_fail = "心情差，偷懶了一下"
		return null
	return best

func _avoided_colleague(w: Worker) -> String:
	if w.kind != "maid":
		return ""
	var m := maid(w.maid_id)
	if m.concern.get("type", "") == "quarrel":
		return m.concern.with
	if m.flags.get("separate_from", "") != "":
		return m.flags.separate_from
	var worst := ""
	var wf := 40.0
	for x in workers:
		if x == w or x.kind != "maid":
			continue
		var f := float(St.rel(s, w.maid_id, x.maid_id).friction)
		if f >= wf:
			wf = f
			worst = x.maid_id
	return worst

func _free_table(p: Party) -> String:
	var free := []
	for tb in layout.tables:
		if not reserved_tables.has(tb.id) and not dirty_tables.has(tb.id):
			free.append(tb)
	if free.is_empty():
		return ""
	var did: String = p.members[0].def_id
	var def: Dictionary = Data.CUSTOMERS.get(did, {})
	var mem: Dictionary = s.customers.get(did, {})
	var want: String = def.get("seat", "any")
	var best = free[0]
	var best_s := -INF
	for tb in free:
		var sc := -float(Layout.manhattan(tb.cell, Layout.DOOR_IN))
		if def.get("quiet", false):
			sc = float(Layout.manhattan(tb.cell, Layout.DOOR_IN))
			if tb.tags.has("private"):
				sc += 20
		if want != "any" and tb.tags.has(want):
			sc += 60
		if not mem.is_empty() and mem.fav_seat == tb.id:
			sc += 100
		if def.get("lively", false) and tb.tags.has("stage"):
			sc += 15
		if sc > best_s:
			best_s = sc
			best = tb
	return best.id

func _free_station(o: Dictionary) -> String:
	var need_stove := false
	for it in o.items:
		if Data.DISHES[it].station == "stove":
			need_stove = true
	var coffee_free := false
	for st in layout.stations:
		if st.kind == "coffee" and station_busy[st.id] == "" and not broken.has(st.id):
			coffee_free = true
	for st in layout.stations:
		if station_busy[st.id] != "" or broken.has(st.id):
			continue
		if need_stove and st.kind != "stove":
			continue
		if not need_stove and st.kind != "coffee" and coffee_free:
			continue
		return st.id
	return ""

# ---------------------------------------------------------------- job → steps
func _assign(w: Worker, j: Dictionary) -> void:
	j.claimed = w.id
	w.job = j
	w.step_t = 0.0
	w.job_t = 0.0
	w.leisure = {}
	w.steps = _build_steps(w, j)
	w.activity = JOB_NAMES[j.type]
	# helping a colleague is noticed
	if w.kind == "maid":
		var owner_role: String = JOB_ROLE.get(j.type, "")
		var role: String = maid(w.maid_id).role
		if owner_role != "" and owner_role != role and role != "support":
			var ow = _owner_of(j.type, w)
			if ow != null and (ow.job != null or ow.resting):
				helps.append({"helper": w.maid_id, "helped": ow.maid_id, "type": j.type})
				maid_stats[w.maid_id].helped += 1
				grow_habit(w, "help", 1.5)
				if rng.randf() < 0.35:
					say(w, "%s，這個我來！" % ow.name, 2.5)

func release(w: Worker, reason := "") -> void:
	var j = w.job
	if j != null and not j.done:
		j.claimed = ""
		if reason != "":
			j.fails = int(j.get("fails", 0)) + 1
			j["fail_reason"] = reason
			w.last_fail = "%s：%s" % [JOB_NAMES.get(j.type, j.type), reason]
		if j.type == "cook":
			var o = order(j.get("order", ""))
			if o != null and o.state == "cooking":
				if o.station != "":
					station_busy[o.station] = ""
				o.state = "queued"
				o.station = ""
				if o.slot >= 0 and String(slots[o.slot]) == "reserved:" + o.id:
					slots[o.slot] = null
				o.slot = -1
		if j.type == "greet":
			var p = party(j.get("party", ""))
			if p != null and p.table != "" and p.state == "queue":
				reserved_tables.erase(p.table)
				p.table = ""
	w.job = null
	w.steps = []
	w.path = []
	w.moving = false
	w.carrying = ""
	w.activity = "待命"

func _goals_table(tid: String) -> Array:
	return layout.table_goals(tid)

func _goals_party_table(pid: String) -> Array:
	var p = party(pid)
	return layout.table_goals(p.table) if p != null and p.table != "" else []

func _goals_cells(cells: Array) -> Array:
	return cells

func _goals_adj(c: Vector2i) -> Array:
	return layout.adjacent_walkable([c])

func _goals_mess(mid: String) -> Array:
	for ms in messes:
		if ms.id == mid:
			return [ms.cell] + layout.adjacent_walkable([ms.cell])
	return []

func _check_party_queue(_w, pid: String) -> bool:
	var p = party(pid)
	return p != null and p.state == "queue"

func _build_steps(w: Worker, j: Dictionary) -> Array:
	var recv := skill(w, "reception")
	match j.type:
		"greet":
			var dur := 2.4 * speed_f(recv)
			if has_trait(w, "shy"):
				dur *= 1.5 - minf(0.5, float(maid(w.maid_id).greets_done) * 0.02)
			return [
				{"kind": "goto", "goals": _goals_cells.bind([Layout.GREET_SPOT, Layout.DOOR_IN]), "label": "前往門口"},
				{"kind": "check", "ok": _check_party_queue.bind(j.party)},
				{"kind": "work", "dur": dur, "label": "迎賓", "done": _done_greet.bind(j)},
			]
		"order":
			return [
				{"kind": "goto", "goals": _goals_party_table.bind(j.party), "label": "前往桌邊"},
				{"kind": "work", "dur": 3.0 * speed_f(recv), "label": "點餐中", "done": _done_order.bind(j)},
			]
		"cook":
			var o = order(j.order)
			var st_id := _free_station(o)
			var st: Dictionary = {}
			for x in layout.stations:
				if x.id == st_id:
					st = x
			station_busy[st_id] = o.id
			o.station = st_id
			o.state = "cooking"
			o.slot = slots.find(null)
			slots[o.slot] = "reserved:" + o.id
			var base := 0.0
			for it in o.items:
				var d: Dictionary = Data.DISHES[it]
				base += float(d.time) * (0.7 if d.cat == "drink" and s.upgrades.coffee_machine else 1.0)
			var dur := base * speed_f(skill(w, "cooking"))
			if has_trait(w, "perfectionist"):
				dur *= 1.1
			if float(s.equipment_wear.get(st_id, 0.0)) > 70:
				dur *= 1.25
			var names := []
			for it in o.items:
				names.append(Data.DISHES[it].name)
			return [
				{"kind": "goto", "goals": _goals_cells.bind([st.stand]), "label": "前往廚房"},
				{"kind": "work", "dur": dur, "label": "製作" + "＋".join(names), "done": _done_cook.bind(j)},
			]
		"deliver":
			var o = order(j.order)
			var pick := 0.5
			var cook_w = worker(o.cooked_by) if o.cooked_by != "" else null
			if cook_w != null and w.kind == "maid" and cook_w.kind == "maid" and cook_w != w:
				var syn := float(St.rel(s, w.maid_id, cook_w.maid_id).synergy)
				var fr := float(St.rel(s, w.maid_id, cook_w.maid_id).friction)
				pick = clampf(0.6 - syn / 200.0 + fr / 100.0, 0.15, 1.2)
			return [
				{"kind": "goto", "goals": _goals_adj.bind(PASS(o.slot)), "label": "取餐"},
				{"kind": "work", "dur": pick, "label": "取餐", "done": _done_pickup.bind(j)},
				{"kind": "goto", "goals": _goals_party_table.bind(o.party), "label": "送餐中"},
				{"kind": "work", "dur": 0.9 * speed_f(skill(w, "floor")), "label": "上菜", "done": _done_serve.bind(j)},
			]
		"clean":
			return [
				{"kind": "goto", "goals": _goals_table.bind(j.table), "label": "前往桌邊"},
				{"kind": "work", "dur": 2.6 * speed_f(skill(w, "floor")), "label": "整理桌面", "done": _done_clean.bind(j)},
			]
		"mess":
			return [
				{"kind": "goto", "goals": _goals_mess.bind(j.mess), "label": "拿拖把"},
				{"kind": "work", "dur": 2.5 * speed_f(skill(w, "floor")), "label": "清理地板", "done": _done_mess.bind(j)},
			]
		"complaint", "dispute":
			return [
				{"kind": "goto", "goals": _goals_party_table.bind(j.party), "label": "趕去處理"},
				{"kind": "work", "dur": 4.0 * speed_f(skill(w, "management")), "label": "道歉中" if j.type == "complaint" else "調解中", "done": _done_complaint.bind(j)},
			]
		"repair":
			return [
				{"kind": "goto", "goals": _goals_adj_or_self.bind(_repair_cell(j.target)), "label": "拿工具"},
				{"kind": "work", "dur": 6.0 * speed_f(skill(w, "management")), "label": "修理中", "done": _done_repair.bind(j)},
			]
		"seat_change":
			return [
				{"kind": "goto", "goals": _goals_party_table.bind(j.party), "label": "前往桌邊"},
				{"kind": "work", "dur": 1.6, "label": "帶客人換位", "done": _done_seat_change.bind(j)},
			]
		"tend":
			var c = _job_anchor(j)
			return [
				{"kind": "goto", "goals": _goals_adj.bind(c), "label": "去換花瓶的水"},
				{"kind": "work", "dur": 3.0, "label": "照顧花瓶", "done": _done_tend.bind(j)},
			]
	return []

func _goals_adj_or_self(c: Vector2i) -> Array:
	return [c] if layout.walkable(c) else layout.adjacent_walkable([c])

func _done_greet(w: Worker, j: Dictionary) -> void:
	var p = party(j.party)
	if p == null or p.state != "queue":
		return
	var tid := _free_table(p)
	if tid == "":
		say(w, "請稍等一下，馬上幫您安排～", 3)
		j.claimed = ""
		return
	p.table = tid
	reserved_tables[tid] = true
	for c in p.members:
		c.seat = null
	_assign_seats_initial(p)
	p.state = "toSeat"
	p.t = 0.0
	p.handled["greet"] = w.id
	if w.kind == "maid":
		var m := maid(w.maid_id)
		p.served_by[w.maid_id] = true
		m.greets_done = int(m.greets_done) + 1
		maid_stats[w.maid_id].greets += 1
		_gain_exp(m, "reception", 3)
	var lines: Dictionary = Data.MAIDS[w.maid_id].lines if w.kind == "maid" else {"greet": ["歡迎光臨！"]}
	say(w, lines.greet[rng.randi() % lines.greet.size()], 3)
	_interact(w, p, 1.0)
	var main: Cust = p.members[0]
	var mem: Dictionary = s.customers.get(main.def_id, {})
	if not mem.is_empty() and mem.fav_seat == tid:
		main.sat += 3
		main.causes["favSeat"] = true
	elif not mem.is_empty() and mem.fav_seat != "" and reserved_tables.has(mem.fav_seat) and mem.fav_seat != tid:
		main.causes["seatTaken"] = true
		_fire_moment("seat_taken_" + main.def_id, "%s發現自己的老位子被別人坐走了，只好坐在別桌。" % main.name, [main.def_id])
	var cdef: Dictionary = Data.CUSTOMERS.get(main.def_id, {})
	if cdef.get("style", "") != "" and cdef.style == World.dominant_style(s).key:
		main.sat += 4
		main.causes["styleMatch"] = true
	# ambience preferences
	var amb: String = cdef.get("ambience", "")
	if amb != "" and amb == s.music:
		main.sat += 4
		main.causes["likedMusic"] = true
	elif amb != "" and s.music != "none" and s.music != amb:
		main.sat -= 2
	if s.lighting == "dim" and cdef.get("quiet", false):
		main.sat += 2
	if s.lighting == "bright" and "photographer" in cdef.get("behaviors", []):
		main.sat += 2
	if cdef.get("style", "") == "cute" and not layout.furniture_cells("photo").is_empty():
		main.sat += 3
	j.done = true

func _assign_seats_initial(p: Party) -> void:
	var tb = layout.table_by_id(p.table)
	for i in p.members.size():
		p.members[i].seat = tb.seats[i % tb.seats.size()]

func _done_order(w: Worker, j: Dictionary) -> void:
	var p = party(j.party)
	if p == null:
		return
	var angry: bool = p.state == "angry" and p.prev_state == "waitOrder"
	if p.state != "waitOrder" and not angry:
		return
	_take_order(p, w)
	if angry and p.state == "waitFood":
		p.state = "angry"
		p.prev_state = "waitFood"
	p.handled["order"] = w.id
	if w.kind == "maid":
		p.served_by[w.maid_id] = true
		_gain_exp(maid(w.maid_id), "reception", 3)
	_interact(w, p, 1.0)
	j.done = true

func _take_order(p: Party, w: Worker) -> void:
	var items_all := []
	for c in p.members:
		var def: Dictionary = Data.CUSTOMERS.get(c.def_id, {})
		var mem: Dictionary = s.customers.get(c.def_id, {})
		var budget := float(def.get("budget", 1100))
		var likes: Array = def.get("likes", [s.menu[rng.randi() % s.menu.size()], s.menu[rng.randi() % s.menu.size()]])
		var missing := 0
		for l in likes:
			if not (l in s.menu and World.servings(s.inventory, l) >= 1):
				missing += 1
		if not def.is_empty() and missing == likes.size():
			c.sat -= 6
			c.causes["outOfStock"] = true
			say(c, "沒有%s啊……" % Data.DISHES[likes[0]].name, 4)
		var curious: bool = "curious_new" in def.get("behaviors", []) or def.is_empty()
		var pref: String = def.get("pref", ["main", "dessert"][rng.randi() % 2])
		var first = _choose(c, likes, mem, def, ["drink"] if pref == "drink" else [pref, "dessert" if pref == "main" else "main"], budget, curious)
		var mine := []
		if first != "":
			mine.append(first)
		var left := budget - (float(Data.DISHES[first].price) if first != "" else 0.0)
		var second = _choose(c, likes, mem, def, ["dessert", "main"] if pref == "drink" else ["drink"], left, curious)
		if second != "" and (pref == "drink" or rng.randf() < 0.75):
			mine.append(second)
		for id in mine:
			for k in Data.DISHES[id].ing:
				s.inventory[k] = int(s.inventory.get(k, 0)) - int(Data.DISHES[id].ing[k])
		c.items = mine
		if curious and not s.new_dishes.is_empty() and mine.size() > 0 and mine[0] in s.new_dishes and c.def_id != "":
			say(c, "這是新菜單嗎？我要這個！", 3)
		elif mem.size() > 0 and mem.fav_dish != "" and mem.fav_dish in mine and int(mem.dish_counts.get(mem.fav_dish, 0)) >= 2 and w.kind == "maid" and float(mem.affinity.get(w.maid_id, 0.0)) >= 15:
			say(w, "老樣子，%s對吧？" % Data.DISHES[mem.fav_dish].name, 3)
			c.sat += 5
			c.causes["remembered"] = true
		items_all.append_array(mine)
	if items_all.is_empty():
		for c in p.members:
			c.causes["outOfStock"] = true
		say(p.members[0], "想吃的都賣完了……", 4)
		note("%s想點的都賣完了，只好離開。記得多採購食材！" % p.members[0].name, "warn")
		_leave(p, false)
		return
	# wrong order: tired / unhappy order-takers mishear (careful maids rarely do)
	var wrong := false
	if w.kind == "maid":
		var m := maid(w.maid_id)
		var ch := 0.02
		if float(m.fatigue) > 70:
			ch += 0.06
		if float(m.mood) < 35:
			ch += 0.04
		if has_trait(w, "careful"):
			ch -= 0.02
		if p.members.size() > 1:
			ch *= 1.5
		wrong = rng.randf() < ch
	# split large orders into two trays so two people can carry them
	var chunks := [items_all]
	if items_all.size() > 2:
		chunks = [items_all.slice(0, 2), items_all.slice(2)]
	for ch_items in chunks:
		var o := {"id": _uid_next("o"), "party": p.id, "items": ch_items, "state": "queued", "slot": -1, "station": "", "quality": 0.0,
			"cooked_by": "", "wrong": wrong, "taker": w.maid_id}
		wrong = false
		orders.append(o)
		p.orders.append(o.id)
		_add_job("cook", {"order": o.id, "party": p.id})
	p.state = "waitFood"
	p.t = 0.0

func _choose(c: Cust, likes: Array, mem: Dictionary, def: Dictionary, cats: Array, left: float, curious: bool) -> String:
	var best := ""
	var bs := -INF
	for id in s.menu:
		var d: Dictionary = Data.DISHES[id]
		if not d.cat in cats or World.servings(s.inventory, id) < 1 or float(d.price) > left:
			continue
		var sc := rng.randf()
		if id in likes:
			sc += 5.0
		if not mem.is_empty() and mem.fav_dish == id:
			sc += 4.0
		if not def.is_empty() and d.cat == def.pref:
			sc += 2.0
		if s.activity == "limited" and s.featured_dish == id:
			sc += 3.0
		if d.get("signature", false) and def.get("pref", "") == "dessert":
			sc += 3.0
		if curious and id in s.new_dishes:
			sc += 3.5
		sc += minf(3.0, float(s.dish_buzz.get(id, 0.0)) / 10.0)
		if s.weather == "hot" and d.cat == "drink":
			sc += 1.0
		if sc > bs:
			bs = sc
			best = id
	return best

func _done_cook(w: Worker, j: Dictionary) -> void:
	var o = order(j.order)
	if o == null:
		return
	station_busy[o.station] = ""
	o.quality = _cook_quality(w, o)
	o.state = "ready"
	o.cooked_by = w.id
	slots[o.slot] = o.id
	var p = party(o.party)
	if p != null:
		p.handled["cook"] = w.id
	if w.kind == "maid":
		var m := maid(w.maid_id)
		maid_stats[w.maid_id].cooks += 1
		_gain_exp(m, "cooking", 4)
		m.fatigue = St.clampf100(float(m.fatigue) + (5.0 if has_trait(w, "perfectionist") else 3.0))
		if o.quality >= 75:
			say(w, Data.MAIDS[w.maid_id].lines.happy[-1], 2.5)
	# equipment wear and breakdowns (conditions: wear builds per cook; repairs reset)
	var wear := float(s.equipment_wear.get(o.station, 0.0)) + 1.5
	s.equipment_wear[o.station] = wear
	if wear > 60.0 and rng.randf() < (wear - 60.0) / 200.0 and not broken.has(o.station):
		broken[o.station] = true
		incidents["breakdown"] = int(incidents.get("breakdown", 0)) + 1
		note("🔧 %s故障了！需要店長（或管理 55 以上的女僕）修理。" % ("咖啡機" if o.station == "coffee" else "爐具"), "warn")
		_add_job("repair", {"target": o.station, "preferred": "manager"})
	j.done = true
	if p != null:
		# hand-off: call the floor partner the cook works best with
		var pref := _pref_maid(p)
		if pref == "" and w.kind == "maid":
			var best := ""
			var bsyn := 35.0
			for x in workers:
				if x.kind == "maid" and x != w and maid(x.maid_id).role == "floor":
					var syn := float(St.rel(s, w.maid_id, x.maid_id).synergy)
					if syn >= bsyn:
						bsyn = syn
						best = x.maid_id
			if best != "":
				pref = best
				say(w, "%s，%s號桌的好了！" % [Data.MAIDS[best].name, p.table.trim_prefix("f")], 2.5)
		_add_job("deliver", {"order": o.id, "party": p.id, "preferred": pref})
	else:
		slots[o.slot] = null

func _cook_quality(w: Worker, o: Dictionary) -> float:
	var total := 0.0
	for it in o.items:
		var d: Dictionary = Data.DISHES[it]
		var q := float(d.q) + (skill(w, "cooking") - 50.0) * 0.5
		if w.kind == "maid":
			var m := maid(w.maid_id)
			q += (float(m.mood) - 50.0) * 0.1
			if float(m.fatigue) > 70:
				q -= 8
		if has_trait(w, "perfectionist"):
			q += 8
		if d.cat == "drink" and s.upgrades.coffee_machine:
			q += 10
		if d.cat == "dessert" and "sweets" in s.partners and (d.ing.has("cream") or d.ing.has("strawberry") or d.ing.has("chocolate")):
			q += 8
		total += q
	return St.clampf100(total / o.items.size())

func _done_pickup(w: Worker, j: Dictionary) -> void:
	var o = order(j.order)
	if o == null:
		return
	slots[o.slot] = null
	o.slot = -1
	o.state = "carried"
	w.carrying = o.id
	if w.kind == "maid" and o.cooked_by != "" and o.cooked_by != w.id:
		var k := St.pair_key(w.maid_id, o.cooked_by)
		handoffs[k] = int(handoffs.get(k, 0)) + 1

func _done_serve(w: Worker, j: Dictionary) -> void:
	var o = order(j.order)
	w.carrying = ""
	j.done = true
	if o == null:
		return
	var p = party(o.party)
	if p == null or not p.state in ["waitFood", "angry", "eating"]:
		o.state = "served"
		return
	if _try_spill(w, o, p):
		return
	if o.wrong:
		o.wrong = false
		o.state = "queued"
		incidents["wrong_order"] = int(incidents.get("wrong_order", 0)) + 1
		for c in p.members:
			c.sat -= 6
			c.causes["wrongOrder"] = true
		say(p.members[0], "咦？這不是我點的……", 4)
		note("🔄 %s的餐點送錯了，要重做。（點餐的人太累或心情不好時容易出錯）" % p.members[0].name, "warn")
		var taker: String = o.get("taker", "")
		if taker != "" and not maid(taker).is_empty():
			maid(taker).mood = St.clampf100(float(maid(taker).mood) - 4)
			maid_stats[taker].wrong += 1
		_consume(o.items)
		_add_job("cook", {"order": o.id, "party": p.id})
		return
	_serve(w, o, p)

func _consume(items: Array) -> void:
	for it in items:
		for k in Data.DISHES[it].ing:
			s.inventory[k] = maxi(0, int(s.inventory.get(k, 0)) - int(Data.DISHES[it].ing[k]))

func _try_spill(w: Worker, o: Dictionary, p: Party) -> bool:
	if w.kind != "maid":
		return false
	var m := maid(w.maid_id)
	var ch := 0.03
	if float(m.fatigue) > 70:
		ch += 0.08
	if float(m.mood) < 30:
		ch += 0.06
	if has_trait(w, "careful"):
		ch -= 0.025
	if has_trait(w, "impatient"):
		ch += 0.015
	ch -= float(m.skills.floor) / 2000.0
	if rng.randf() >= maxf(0.005, ch):
		return false
	maid_stats[w.maid_id].spills += 1
	m.mood = St.clampf100(float(m.mood) - 6)
	var ms := {"id": _uid_next("m"), "cell": w.cell}
	messes.append(ms)
	_add_job("mess", {"mess": ms.id})
	var sorry: Array = Data.MAIDS[w.maid_id].lines.sorry
	say(w, sorry[0], 3)
	note("💦 %s打翻了餐點！需要清理地板並重新製作。" % w.name, "warn")
	incidents["spill"] = int(incidents.get("spill", 0)) + 1
	for c in p.members:
		c.sat -= 8
		c.causes["spill"] = true
	o.state = "queued"
	o.slot = -1
	_consume(o.items)
	_add_job("cook", {"order": o.id, "party": p.id})
	# a close colleague nearby comes to cheer her up
	for x in workers:
		if x != w and x.kind == "maid" and x.job == null and Layout.manhattan(x.cell, w.cell) <= 5:
			if float(St.rel(s, w.maid_id, x.maid_id).close) >= 50:
				say(x, "%s，沒事的！我來幫忙！" % w.name, 3)
				St.rel_change(s, w.maid_id, x.maid_id, "trust", 2.0, "%s打翻餐點時%s來幫忙" % [w.name, x.name])
				break
	return true

func _serve(w: Worker, o: Dictionary, p: Party) -> void:
	o.state = "served"
	var all_served := true
	for oid in p.orders:
		var oo = order(oid)
		if oo != null and oo.state != "served":
			all_served = false
	p.quality = maxf(p.quality, o.quality)
	p.handled["deliver"] = w.id
	if w.kind == "maid":
		p.served_by[w.maid_id] = true
		maid_stats[w.maid_id].delivers += 1
		_gain_exp(maid(w.maid_id), "floor", 3)
		if p.handled.get("greet", "") == w.id and p.handled.get("order", "") == w.id:
			maid_stats[w.maid_id].solo += 1
	for c in p.members:
		var def: Dictionary = Data.CUSTOMERS.get(c.def_id, {})
		c.sat += (o.quality - 55.0) * 0.4 / maxf(1.0, p.orders.size())
		if o.quality >= 75:
			c.causes["greatFood"] = true
		if o.quality < 40:
			c.causes["badFood"] = true
		for it in c.items:
			if it in def.get("likes", []) and it in o.items:
				c.sat += 6
				c.causes["favDish"] = true
	_interact(w, p, 0.8)
	say(w, "讓您久等了，請慢用～", 2.5)
	if not all_served:
		return
	if p.state == "angry":
		p.complaint_done = true
		for j in jobs:
			if j.get("party", "") == p.id and j.type == "complaint":
				j.cancelled = true
	p.state = "eating"
	p.t = 0.0

func _done_clean(w: Worker, j: Dictionary) -> void:
	dirty_tables.erase(j.table)
	if w.kind == "maid":
		_gain_exp(maid(w.maid_id), "floor", 2)
	j.done = true

func _done_mess(w: Worker, j: Dictionary) -> void:
	messes = messes.filter(func(x): return x.id != j.mess)
	if w.kind == "maid":
		_gain_exp(maid(w.maid_id), "floor", 2)
	j.done = true

func _done_complaint(w: Worker, j: Dictionary) -> void:
	var p = party(j.party)
	j.done = true
	if p == null:
		return
	if j.type == "dispute":
		p.handled["dispute"] = w.id
		p.noise_t = -999.0
		for c in p.members:
			c.sat = maxf(c.sat, 50.0)
			c.causes["complaintHandled"] = true
		say(w, "非常抱歉，我們幫您調整一下。", 3)
		note("✅ %s調解了%s的抱怨。" % [w.name, p.members[0].name], "good")
		complaints_handled += 1
		if w.kind == "maid":
			_gain_exp(maid(w.maid_id), "management", 5)
		return
	if p.state != "angry":
		return
	p.state = p.prev_state if p.prev_state != "" else "waitFood"
	p.t = 0.0
	p.complaint_done = true
	complaints_handled += 1
	for c in p.members:
		c.sat = maxf(c.sat, 52.0 if w.kind == "manager" else 45.0)
		c.causes["complaintHandled"] = true
	say(w, "真的非常抱歉，我們馬上為您處理！", 3)
	say(p.members[0], "……好吧，這次就算了。", 4)
	note("✅ %s安撫了%s。" % [w.name, p.members[0].name], "good")
	if w.kind == "maid":
		_gain_exp(maid(w.maid_id), "management", 6)

func _done_repair(w: Worker, j: Dictionary) -> void:
	var target: String = j.target
	j.done = true
	if target == "aircon":
		ac_broken = false
		note("❄ 冷氣修好了。", "good")
	else:
		broken.erase(target)
		s.equipment_wear[target] = 20.0
		note("🔧 %s修好了。" % ("咖啡機" if target == "coffee" else "爐具"), "good")
	if w.kind == "maid":
		_gain_exp(maid(w.maid_id), "management", 6)

func _done_seat_change(w: Worker, j: Dictionary) -> void:
	var p = party(j.party)
	j.done = true
	var target: String = j.target
	if p == null or reserved_tables.has(target) or dirty_tables.has(target) or not p.state in ["browsing", "waitOrder", "waitFood", "eating"]:
		return
	reserved_tables.erase(p.table)
	p.prev_state = p.state
	p.table = target
	reserved_tables[target] = true
	var tb = layout.table_by_id(target)
	for i in p.members.size():
		var c: Cust = p.members[i]
		c.sitting = false
		var adj: Array = layout.adjacent_walkable([c.seat])
		if not adj.is_empty():
			c.cell = adj[0]
			c.pos = Vector2(adj[0].x, adj[0].y)
		c.seat = tb.seats[i % tb.seats.size()]
		set_path(c, [c.seat], true)
		c.sat += 5
		c.causes["seatChanged"] = true
	p.state = "moving"
	say(w, "這邊請～", 2)

func _done_tend(w: Worker, j: Dictionary) -> void:
	s.vase_water[j.furniture] = 0
	j.done = true
	grow_habit(w, "tidy", 2.0)
	say(w, "花喝飽水了。", 2)

func _interact(w: Worker, p: Party, weight: float) -> void:
	if w.kind != "maid":
		return
	var m := maid(w.maid_id)
	for c in p.members:
		var gain := (3.0 + (float(m.skills.reception) - 50.0) / 20.0 + (float(m.mood) - 50.0) / 25.0) * weight
		var visits: int = int(s.customers[c.def_id].visits) if c.def_id != "" else 0
		if has_trait(w, "slow_warm"):
			gain *= 0.5 if visits < 2 else 1.6
		if has_trait(w, "shy"):
			gain *= 0.6 + minf(0.6, float(m.greets_done) / 40.0)
		if has_trait(w, "cheerful"):
			gain += 1.0
		gain = maxf(0.5, gain)
		var rec: Dictionary = c.get_meta("aff", {})
		rec[w.maid_id] = float(rec.get(w.maid_id, 0.0)) + gain
		c.set_meta("aff", rec)
		if c.def_id != "":
			var mem: Dictionary = s.customers[c.def_id]
			if mem.fav_maid == w.maid_id and not c.causes.has("favMaid"):
				c.sat += 8
				c.causes["favMaid"] = true
				say(c, "是%s！" % w.name, 3)

func _gain_exp(m: Dictionary, k: String, n: float) -> void:
	m.exp[k] = float(m.exp[k]) + n
	var cap := int(Data.MAIDS[m.id].caps[k])
	while float(m.exp[k]) >= 12.0:
		m.exp[k] = float(m.exp[k]) - 12.0
		if int(m.skills[k]) < cap:
			m.skills[k] = int(m.skills[k]) + 1

# ---------------------------------------------------------------- workers
func _update_worker(w: Worker, dt: float) -> void:
	if w.bubble != "" and w.bubble_until < t:
		w.bubble = ""
	var m := maid(w.maid_id) if w.kind == "maid" else {}
	var mul := 1.05
	if not m.is_empty():
		mul = (0.85 + float(m.skills.floor) / 100.0 * 0.3) * (0.82 if float(m.fatigue) > 70 else 1.0)
		if has_trait(w, "impatient"):
			mul *= 1.08
		if has_trait(w, "laid_back"):
			mul *= 0.93
		if m.concern.get("effect", "") == "slow":
			mul *= 0.9
	if not m.is_empty() and m.role == "off" and mode == "business":
		w.activity = "休假中"
		_go_to(w, dt, Layout.IDLE_SPOTS.off, mul)
		return
	if w.paused:
		w.activity = "暫停中"
		return
	if not m.is_empty() and not w.resting and w.job == null and float(m.fatigue) >= 90:
		_start_rest(w)
	if w.resting and not m.is_empty():
		_do_rest(w, m, dt, mul)
		return
	if not m.is_empty() and m.role == "stage" and mode == "business":
		_update_performer(w, m, dt, mul)
		return
	if w.job != null and (w.job.cancelled or (w.job.done and w.steps.is_empty())):
		release(w)
	# watchdog: a job that makes no progress is handed back instead of hanging forever
	if w.job != null:
		w.job_t += dt
		if w.job_t > 30.0 and w.steps.size() > 0 and w.steps[0].kind == "goto":
			note("⚠ %s卡住了，把「%s」交還給其他人。" % [w.name, JOB_NAMES[w.job.type]], "warn")
			release(w, "30 秒沒有進展")
	if w.job == null and w.kind == "maid":
		w.decide_t -= dt
		if w.decide_t <= 0.0 or w.leisure.is_empty():
			w.decide_t = 0.6
			var j = pick_job(w)
			if j != null:
				_assign(w, j)
	if w.job == null:
		if w.kind == "manager":
			w.activity = "移動中" if not w.path.is_empty() else "巡視中"
			move(w, dt, mul)
		else:
			_leisure(w, m, dt, mul)
		return
	_run_steps(w, dt, mul)
	if not m.is_empty():
		var rate := 0.14 if has_trait(w, "perfectionist") else (0.08 if has_trait(w, "laid_back") else 0.11)
		if ac_broken:
			rate *= 1.4
		m.fatigue = St.clampf100(float(m.fatigue) + rate * dt)
		maid_stats[w.maid_id].tasks += dt / 10.0

func _run_steps(w: Worker, dt: float, mul: float) -> void:
	if w.steps.is_empty():
		if w.job != null:
			w.job.done = true
		release(w)
		return
	var step: Dictionary = w.steps[0]
	match step.kind:
		"check":
			if not step.ok.call(w):
				if w.job != null:
					w.job.cancelled = true
				release(w)
				return
			w.steps.pop_front()
		"goto":
			w.activity = step.label
			var goals: Array = step.goals.call()
			if goals.is_empty():
				if w.job != null:
					w.job.cancelled = true
				release(w)
				return
			if w.path.is_empty() and w.cell in goals:
				w.steps.pop_front()
				return
			if w.path.is_empty() or not w.path[w.path.size() - 1] in goals:
				if not set_path(w, goals, step.get("allow_goal", false)):
					release(w, "找不到路")
					return
			if move(w, dt, mul):
				w.steps.pop_front()
		"work":
			w.activity = step.label
			w.step_dur = step.dur
			w.step_t += dt
			w.job_t = 0.0
			if w.step_t >= float(step.dur):
				w.step_t = 0.0
				w.steps.pop_front()
				step.done.call(w)
				if w.job != null and not w.job.done and w.job.claimed == "":
					var j = w.job
					w.job = null
					w.steps = []
					j.claimed = ""
				if w.job != null and w.job.done and w.steps.is_empty():
					release(w)

func _go_to(w: Worker, dt: float, spots: Array, mul: float) -> bool:
	var target: Vector2i = spots[0]
	for sp in spots:
		var taken := false
		for o in workers:
			if o != w and o.cell == sp:
				taken = true
		if not taken:
			target = sp
			break
	if w.cell != target and w.path.is_empty():
		set_path(w, [target], not layout.walkable(target))
	return move(w, dt, mul)

func _start_rest(w: Worker) -> void:
	release(w)
	w.resting = true
	w.rest_spot = null
	say(w, "對不起……我先去休息一下。", 3)
	note("😮‍💨 %s太累了，去休息室休息。" % w.name, "warn")
	incidents["overwork"] = int(incidents.get("overwork", 0)) + 1

func _do_rest(w: Worker, m: Dictionary, dt: float, mul: float) -> void:
	if w.rest_spot == null:
		# habit: always the same rest seat if possible
		var fav: String = m.get("rest_spot", "")
		for r in Layout.REST_SPOTS:
			if Layout.key(r) == fav and not _spot_taken(w, r):
				w.rest_spot = r
		if w.rest_spot == null:
			for r in Layout.REST_SPOTS:
				if not _spot_taken(w, r):
					w.rest_spot = r
					break
		if w.rest_spot == null:
			w.rest_spot = Layout.REST_SPOTS[0]
		m.rest_spot = Layout.key(w.rest_spot)
	if w.cell != w.rest_spot and w.path.is_empty():
		set_path(w, [w.rest_spot])
	if move(w, dt, mul):
		w.activity = "休息中"
		m.fatigue = St.clampf100(float(m.fatigue) - (2.2 if s.upgrades.sofa else 1.3) * dt)
		maid_stats[w.maid_id].rest += dt
		if float(m.fatigue) <= 35:
			w.resting = false
			w.rest_spot = null
			say(w, "好，回去工作！", 2)

func _spot_taken(w: Worker, c: Vector2i) -> bool:
	for o in workers:
		if o != w and o.rest_spot != null and o.rest_spot == c:
			return true
	return false

## Leisure: what a maid does when nobody needs her. Driven by habits, traits, relationships and the room.
func _leisure(w: Worker, m: Dictionary, dt: float, mul: float) -> void:
	maid_stats[w.maid_id].idle += dt
	m.fatigue = St.clampf100(float(m.fatigue) - 0.04 * dt)
	if not w.leisure.is_empty():
		w.leisure_t -= dt
		var l: Dictionary = w.leisure
		var arrived := true
		if w.cell != l.cell:
			if w.path.is_empty():
				if not set_path(w, [l.cell], not layout.walkable(l.cell)):
					w.leisure = {}
					return
			arrived = move(w, dt, mul)
		w.activity = l.label if arrived else "走向" + l.label
		if arrived:
			maid_stats[w.maid_id].leisure += dt
			if not l.get("started", false):
				l.started = true
				_leisure_start(w, m, l)
		if w.leisure_t <= 0.0:
			w.leisure = {}
		return
	var opts := _leisure_options(w, m).filter(func(o): return o.id == "wait" or _cell_free_for(w, o.cell))
	if opts.is_empty():
		w.activity = "待命"
		_go_to(w, dt, Layout.IDLE_SPOTS.get(m.role, Layout.IDLE_SPOTS.floor) if mode == "business" else [w.cell], mul)
		return
	var best: Dictionary = opts[0]
	var bs := -INF
	for o in opts:
		var sc: float = o.score + rng.randf() * 0.8
		if sc > bs:
			bs = sc
			best = o
	w.leisure = best
	w.leisure_t = best.get("dur", 8.0)
	w.path = []
	if best.has("habit"):
		grow_habit(w, best.habit, 1.2)

func _leisure_options(w: Worker, m: Dictionary) -> Array:
	var out := []
	var role_spots: Array = Layout.IDLE_SPOTS.get(m.role, Layout.IDLE_SPOTS.floor)
	var wait_cell: Vector2i = role_spots[0]
	for sp in role_spots:
		if _cell_free_for(w, sp):
			wait_cell = sp
			break
	out.append({"id": "wait", "label": "待命", "cell": wait_cell, "score": 1.2 if mode == "business" else 0.3, "dur": 5.0})
	# chat with a colleague
	for x in workers:
		if x == w or x.kind != "maid" or x.job != null or x.resting:
			continue
		var r := St.rel(s, w.maid_id, x.maid_id)
		if float(r.friction) >= 45:
			continue
		if not x.path.is_empty() or (not x.leisure.is_empty() and x.leisure.get("with", "") == w.maid_id):
			continue
		var sc := 0.6 + habit(w, "chat") / 40.0 + float(r.close) / 80.0
		var cc = _free_adjacent(w, [x.cell])
		if cc != null:
			out.append({"id": "chat", "label": "和%s聊天" % x.name, "cell": cc, "score": sc, "dur": 6.0, "habit": "chat", "with": x.maid_id})
	# read at the bookshelf
	for c in layout.furniture_cells("bookshelf"):
		var adj: Array = layout.adjacent_walkable([c])
		if adj.is_empty():
			continue
		var sc := 0.2 + habit(w, "read") / 35.0 + (1.0 if has_trait(w, "bookish") else 0.0)
		if mode == "business":
			sc -= 0.4
		out.append({"id": "read", "label": "在書架旁看書", "cell": adj[0], "score": sc, "dur": 12.0, "habit": "read"})
	# tidy tables (mostly before opening)
	if mode == "offhours" or habit(w, "tidy") > 40:
		for tb in layout.tables:
			var adj: Array = layout.table_goals(tb.id)
			if adj.is_empty():
				continue
			out.append({"id": "tidy", "label": "擦桌子", "cell": adj[0], "score": 0.3 + habit(w, "tidy") / 35.0, "dur": 6.0, "habit": "tidy"})
			break
	# talk with a regular she knows
	if mode == "business":
		for p in parties:
			if p.state != "eating":
				continue
			var did: String = p.members[0].def_id
			if did == "" or p.members[0].causes.has("maidChat"):
				continue
			var aff := float(s.customers[did].affinity.get(w.maid_id, 0.0))
			if aff < 10:
				continue
			var goals: Array = layout.table_goals(p.table)
			if goals.is_empty():
				continue
			out.append({"id": "regular", "label": "和%s聊兩句" % p.members[0].name, "cell": goals[0], "score": 0.5 + habit(w, "regular_talk") / 35.0 + aff / 60.0,
				"dur": 5.0, "habit": "regular_talk", "party": p.id})
	# look out the window
	var wspot: Vector2i = Layout.WINDOW_SPOTS[hash(w.maid_id) % Layout.WINDOW_SPOTS.size()]
	if layout.walkable(wspot):
		out.append({"id": "window", "label": "看窗外", "cell": wspot, "score": 0.2 + habit(w, "window") / 35.0 + (0.6 if s.weather == "rain" else 0.0), "dur": 8.0, "habit": "window"})
	# a personal concern shows in what she does when nobody is looking
	if not m.concern.is_empty():
		var cc: Vector2i = wspot
		match m.concern.get("effect", ""):
			"watch":
				cc = Vector2i(5, 4) if m.concern.get("role", "") == "kitchen" else (Vector2i(11, 9) if m.concern.get("role", "") == "reception" else Vector2i(9, 6))
			"watch_door":
				cc = Vector2i(10, 9)
			"avoid":
				cc = Layout.REST_SPOTS[5]
		if layout.walkable(cc):
			out.append({"id": "concern", "label": m.concern.leisure, "cell": cc, "score": 1.9, "dur": 9.0})
	# take a breather when tired
	if float(m.fatigue) > 45:
		out.append({"id": "rest", "label": "坐著喘口氣", "cell": Layout.REST_SPOTS[3], "score": float(m.fatigue) / 40.0, "dur": 10.0})
	# after-hours: practice / stay
	if mode == "offhours" and habit(w, "stay_late") > 20:
		var c: Vector2i = layout.stations[0].stand if m.role == "kitchen" else Vector2i(10, 4)
		out.append({"id": "stay", "label": "一個人留下來練習", "cell": c, "score": habit(w, "stay_late") / 30.0, "dur": 14.0, "habit": "stay_late"})
	_life_options(w, m, out)
	return out

## Living Hearts leisure: coming to find the manager, arguing it out, and using the furniture she likes.
## Every target is a walkable cell next to the furniture, so pathfinding / collision / stations are untouched.
func _life_options(w: Worker, m: Dictionary, out: Array) -> void:
	var mid := w.maid_id
	var after := mode == "offhours"
	# she has something to say: walk over to the manager (only when the cafe is closed)
	if after and not m.want_talk.is_empty() and not sought.has(mid):
		var mg := manager()
		var cc = _free_adjacent(w, [mg.cell])
		if cc != null:
			out.append({"id": "seek", "label": "去找店長", "cell": cc, "score": 3.0, "dur": 7.0})
	# an argument that has been building up (never in front of customers)
	if after:
		for x in workers:
			if x == w or x.kind != "maid" or x.job != null or Layout.manhattan(x.cell, w.cell) > 6:
				continue
			var fr := float(St.rel(s, mid, x.maid_id).friction)
			var pk := St.pair_key(mid, x.maid_id)
			if fr >= 45 and not argued.has(pk):
				var cc = _free_adjacent(w, [x.cell])
				if cc != null:
					out.append({"id": "argue", "label": "找%s說清楚" % x.name, "cell": cc, "score": 1.2 + fr / 50.0, "dur": 6.0, "with": x.maid_id})
	var fav := func(type: String) -> float:
		return (0.9 if Life.likes(mid, "furn:" + type) else 0.0) - (0.6 if Life.dislikes(mid, "furn:" + type) else 0.0)
	var spot := func(type: String):
		for c in layout.furniture_cells(type):
			for a in layout.adjacent_walkable([c]):
				if _cell_free_for(w, a):
					return a
		return null
	var c
	c = spot.call("plush")
	if c != null:
		out.append({"id": "plush", "label": "抱一下大熊", "cell": c, "score": 0.1 + fav.call("plush") - (0.5 if not after else 0.0), "dur": 5.0})
	c = spot.call("plant")
	if c != null and (after or habit(w, "tidy") > 45):
		out.append({"id": "water", "label": "替盆栽澆水", "cell": c, "score": 0.2 + habit(w, "tidy") / 60.0 + fav.call("plant"), "dur": 5.0, "habit": "tidy"})
	c = spot.call("gramophone")
	if c != null and after:
		var mus := 0.6 if (Life.likes(mid, "music:jazz") or Life.likes(mid, "music:classical")) else 0.0
		out.append({"id": "record", "label": "放一張黑膠唱片", "cell": c, "score": 0.1 + mus + fav.call("gramophone"), "dur": 8.0})
	c = spot.call("display")
	if c != null and habit(w, "tidy") > 30:
		out.append({"id": "display", "label": "整理展示櫃", "cell": c, "score": 0.1 + habit(w, "tidy") / 50.0 + fav.call("display") - (0.4 if not after else 0.0), "dur": 6.0, "habit": "tidy"})
	if after and not layout.stage_cells.is_empty():
		var st: Vector2i = layout.stage_cells[0]
		if _cell_free_for(w, st):
			var perf := 0.6 if (Life.likes(mid, "act:stage") or Data.MAIDS[mid].growth == "idol") else 0.0
			out.append({"id": "practice", "label": "在舞台上偷偷練習", "cell": st, "score": perf + float(m.skills.performance) / 150.0 - 0.3, "dur": 10.0})
	if after:
		for tb in layout.tables:
			if tb.type != "sofa_table":
				continue
			var goals: Array = layout.table_goals(tb.id)
			for g in goals:
				if _cell_free_for(w, g):
					var sl: float = (0.8 if has_trait(w, "laid_back") else 0.0) + float(m.fatigue) / 60.0 + fav.call("sofa_table")
					out.append({"id": "nap", "label": "在沙發座打個盹", "cell": g, "score": sl - 0.3, "dur": 10.0})
					break
			break
	# photo spot: two friends take a picture together
	c = spot.call("photo")
	if c != null and after:
		for x in workers:
			if x == w or x.kind != "maid" or x.job != null or not x.leisure.is_empty():
				continue
			if float(St.rel(s, mid, x.maid_id).close) >= 60 and float(St.rel(s, x.maid_id, mid).close) >= 55:
				out.append({"id": "photo", "label": "和%s在拍照區合照" % x.name, "cell": c, "score": 0.8 + fav.call("photo"), "dur": 6.0, "with": x.maid_id})
				break

func _leisure_start(w: Worker, m: Dictionary, l: Dictionary) -> void:
	_leisure_say(w, m, l)
	var extra := {"with": l.get("with", "")}
	if l.has("party"):
		var p = party(l.party)
		if p != null:
			extra["cust"] = p.members[0].def_id
	var mo: Dictionary = Moments.from_leisure(s, w.maid_id, l.id, mode, extra)
	if not mo.is_empty():
		_fire_moment(mo.id, mo.text, mo.who, mo.get("album", ""))

func _leisure_say(w: Worker, m: Dictionary, l: Dictionary) -> void:
	var lines: Dictionary = Data.MAIDS[w.maid_id].lines
	match l.id:
		"chat":
			var other: String = l.with
			var r := St.rel(s, w.maid_id, other)
			var topics_close := ["剛剛那位客人好可愛～", "等等一起吃宵夜？", "今天配合得不錯呢！", "妳的髮夾好好看。"]
			var topics_cold := ["……今天客人多嗎？", "那個，盤子放這邊就好。", "嗯……"]
			var sh: Array = r.shared
			var xo = worker(other)
			if not sh.is_empty() and float(r.close) >= 50 and rng.randf() < 0.4:
				# reminiscing about something they went through together
				say(w, "還記得嗎？%s……" % sh[rng.randi() % sh.size()].text, 4)
				if xo != null:
					say(xo, "當然記得！", 3)
				St.rel_change(s, w.maid_id, other, "close", 1.0, "聊起以前的事")
			else:
				say(w, (topics_close if float(r.close) >= 55 else topics_cold)[rng.randi() % 3], 3)
				St.rel_change(s, w.maid_id, other, "close", 0.8, "空檔聊天")
		"read":
			say(w, "（翻頁）……", 3)
		"regular":
			var p = party(l.party)
			if p != null:
				var c: Cust = p.members[0]
				c.causes["maidChat"] = true
				c.sat += 4
				var rec: Dictionary = c.get_meta("aff", {})
				rec[w.maid_id] = float(rec.get(w.maid_id, 0.0)) + 2.0
				c.set_meta("aff", rec)
				say(w, "%s，今天也是老位子呢～" % c.name, 3)
				say(c, "妳還記得啊！", 3)
				maid_stats[w.maid_id].regular_talks += 1
		"window":
			say(w, "下雨了呢……" if s.weather == "rain" else lines.idle[rng.randi() % lines.idle.size()], 3)
		"stay":
			say(w, "……再練一次。", 3)
		"concern":
			say(w, m.concern.get("line", "……"), 4)
			maid_stats[w.maid_id]["concern_seen"] = int(maid_stats[w.maid_id].get("concern_seen", 0)) + 1
		"tidy":
			say(w, "擦乾淨了～", 2)
		"seek":
			sought[w.maid_id] = true
			var mg := manager()
			say(w, "店長，有空嗎？……" + String(m.want_talk.get("short", "")), 5)
			say(mg, "（%s好像有話想說）" % w.name, 3)
			note("💬 %s走過來找店長：「%s」（點她就可以聽她說）" % [w.name, m.want_talk.get("short", "")], "moment")
		"argue":
			var other: String = l.with
			argued[St.pair_key(w.maid_id, other)] = true
			var res := Life.argue(s, w.maid_id, other)
			say(w, res.a_line, 4)
			var xo = worker(other)
			if xo != null:
				say(xo, res.b_line, 4)
			note(("🌙 " if res.ok else "⚡ ") + res.text, "moment" if res.ok else "warn")
			s.moments.append({"day": int(s.day), "id": "argue_" + St.pair_key(w.maid_id, other), "text": res.text, "who": [w.maid_id, other]})
		"plush":
			m.mood = St.clampf100(float(m.mood) + 2)
			say(w, "（抱住大熊）軟軟的～", 3)
		"water":
			say(w, "多喝一點水喔～", 3)
		"record":
			say(w, "（把唱針輕輕放下）", 3)
			for x in workers:
				if x.kind == "maid" and Layout.manhattan(x.cell, w.cell) <= 6:
					var xm := maid(x.maid_id)
					if Life.likes(x.maid_id, "music:jazz") or Life.likes(x.maid_id, "music:classical"):
						xm.mood = St.clampf100(float(xm.mood) + 2)
						if x != w:
							say(x, "……這首歌，好好聽。", 3)
		"display":
			say(w, "排整齊了～", 2)
		"practice":
			_gain_exp(m, "performance", 2)
			say(w, "（小聲地練習唱歌）♪", 4)
		"nap":
			m.fatigue = St.clampf100(float(m.fatigue) - 8)
			say(w, "呼……（睡著了）", 4)
		"photo":
			var xo = worker(l.with)
			say(w, "%s，過來一起拍！" % Data.MAIDS[l.with].name, 3)
			if xo != null:
				say(xo, "等等，我的頭髮……！", 3)
			St.rel_change(s, w.maid_id, l.with, "close", 1.5, "一起拍照")
		_:
			if rng.randf() < 0.4:
				say(w, lines.idle[rng.randi() % lines.idle.size()], 3)

func _update_performer(w: Worker, m: Dictionary, dt: float, mul: float) -> void:
	if not s.activity in ["stage", "street_music", "birthday"] or layout.stage_cells.is_empty():
		m.role = "floor"
		return
	var st: Vector2i = layout.stage_cells[0]
	w.performing = false
	if w.cell != st:
		if w.path.is_empty():
			set_path(w, [st], true)
		w.activity = "前往舞台"
		stage_quality = 0.0
		move(w, dt, mul)
		return
	w.performing = true
	w.activity = "舞台表演中 ♪"
	stage_quality = float(m.skills.performance) / 100.0 * (0.5 + float(m.mood) / 200.0) * (0.6 if float(m.fatigue) > 70 else 1.0)
	if s.activity == "street_music":
		stage_quality += 0.25
	m.fatigue = St.clampf100(float(m.fatigue) + 0.12 * dt)
	maid_stats[w.maid_id].perform += dt
	if int(t * 10) % 40 == 0:
		_gain_exp(m, "performance", 1)
	if float(m.fatigue) >= 90:
		stage_quality = 0.0
		w.performing = false
		_start_rest(w)

func _update_moods(dt: float) -> void:
	var present := 0
	for p in parties:
		if p.state != "arriving":
			present += 1
	for w in workers:
		if w.kind != "maid":
			continue
		var m := maid(w.maid_id)
		if m.role == "off" and mode == "business":
			continue
		if has_trait(w, "cheerful"):
			for o in workers:
				if o != w and o.kind == "maid" and Layout.manhattan(o.cell, w.cell) <= 4:
					var om := maid(o.maid_id)
					om.mood = St.clampf100(float(om.mood) + 0.03 * dt)
		if has_trait(w, "lively") and mode == "business":
			m.mood = St.clampf100(float(m.mood) + (0.05 if s.activity != "none" else (-0.03 if present < 2 else 0.0)) * dt)
		if has_trait(w, "shy") and m.role == "reception" and int(m.greets_done) < 30:
			m.mood = St.clampf100(float(m.mood) - 0.03 * dt)
		if float(m.fatigue) > 75:
			m.mood = St.clampf100(float(m.mood) - 0.03 * dt)
		if m.get("preferred_role", "") != "" and m.role == m.preferred_role and mode == "business":
			m.mood = St.clampf100(float(m.mood) + 0.02 * dt)

# ---------------------------------------------------------------- environment & social
func _environment(dt: float) -> void:
	# summer heat: old air conditioner breaks mid-shift unless upgraded
	if s.weather == "hot" and not s.upgrades.aircon and not ac_broken and not incidents.has("aircon") and t > 60.0:
		ac_broken = true
		incidents["aircon"] = 1
		note("🥵 冷氣壞了！客人和女僕都會越來越不舒服，快請店長修理。", "warn")
		_add_job("repair", {"target": "aircon", "preferred": "manager"})
	if ac_broken:
		for p in parties:
			for m in p.members:
				m.sat -= 0.1 * dt
				m.causes["hot"] = true
	# rain: umbrellas drip at the entrance
	if s.weather == "rain" and int(t * 10) % 700 == 350:
		var c := Vector2i(8, 10)
		var exists := false
		for ms in messes:
			if ms.cell == c:
				exists = true
		if not exists:
			var ms := {"id": _uid_next("m"), "cell": c, "rain": true}
			messes.append(ms)
			_add_job("mess", {"mess": ms.id})
			note("☔ 門口被雨傘滴濕了。", "info")
	# crowding: too many people in one 3x3 area
	if int(t * 10) % 50 == 0:
		var counts := {}
		for m in _movers():
			if not m.inside:
				continue
			var k := "%d,%d" % [int(m.cell.x / 3), int(m.cell.y / 3)]
			counts[k] = int(counts.get(k, 0)) + 1
		for k in counts:
			if int(counts[k]) >= 6:
				incidents["crowding"] = int(incidents.get("crowding", 0)) + 1
				if int(incidents.crowding) == 1:
					note("🚶 店內某一區太擠了，大家走得很慢。可以看看深夜的動線分析。", "warn")
				for p in parties:
					for m in p.members:
						if "%d,%d" % [int(m.cell.x / 3), int(m.cell.y / 3)] == k:
							m.sat -= 0.5

## Periodic social checks: co-presence of customers, daily moments during service.
func _social_tick() -> void:
	var present := []
	for p in parties:
		if p.state in ["browsing", "waitOrder", "waitFood", "eating", "waitFriend"]:
			for m in p.members:
				if m.def_id != "":
					present.append(m.def_id)
	for i in present.size():
		for k in range(i + 1, present.size()):
			var key := St.pair_key(present[i], present[k])
			co_present[key] = float(co_present.get(key, 0.0)) + 8.0
	# a maid mentions a regular who usually comes today but hasn't
	if t > 150.0 and not moments_fired.has("missing_regular"):
		var wd := Data.weekday(s.day)
		for id in Data.CUSTOMERS:
			var def: Dictionary = Data.CUSTOMERS[id]
			var mem: Dictionary = s.customers[id]
			if not mem.is_regular or not wd in def.weekdays or id in present:
				continue
			var came := false
			for r in results:
				if r.def == id:
					came = true
			for p in parties:
				for m in p.members:
					if m.def_id == id:
						came = true
			if came:
				continue
			var fav: String = mem.fav_maid
			var w = worker(fav) if fav != "" and _maid_working(fav) else null
			if w == null:
				for x in workers:
					if x.kind == "maid" and _maid_working(x.maid_id):
						w = x
						break
			if w != null:
				say(w, "今天是星期%s……%s怎麼還沒來呢？" % [Data.WEEKDAYS[wd], def.name], 5)
				_fire_moment("missing_regular", "%s提起今天沒出現的%s。平常的星期%s，他一定會來的。" % [w.name, def.name, Data.WEEKDAYS[wd]], [w.maid_id, id])
			break

func _fire_moment(id: String, text: String, who: Array, album := "") -> void:
	if moments_fired.has(id) or not Moments.can_fire(s, id):
		return
	moments_fired.append(id)
	var mo: Dictionary = Moments.record(s, id, text, who, album)
	note("🌸 " + text, "moment")
	if mo.has("album"):
		note("📷 新的回憶：「%s」" % mo.album, "album")

# ---------------------------------------------------------------- player commands
func manager_move(c: Vector2i) -> bool:
	var mg := manager()
	if mg.carrying != "":
		return false
	release(mg)
	return set_path(mg, [c])

func manager_do(job_id: String) -> String:
	var mg := manager()
	var j = _job_by_id(job_id)
	if j == null or j.done or j.cancelled:
		return "這件事已經處理好了。"
	if mg.carrying != "":
		return "店長正在送餐中。"
	var why := job_available(j, mg)
	if why != "":
		return why
	if j.claimed != "" and j.claimed != mg.id:
		var other = worker(j.claimed)
		if other != null:
			if other.carrying != "" or (not other.steps.is_empty() and other.steps[0].kind == "work"):
				return "%s已經在處理了。" % other.name
			release(other)
	release(mg)
	_assign(mg, j)
	return ""

func manager_chat(pid: String) -> String:
	var mg := manager()
	var p = party(pid)
	if p == null or p.table == "" or not p.state in ["browsing", "waitOrder", "waitFood", "eating"]:
		return "現在不方便打擾。"
	if p.members[0].causes.has("managerChat"):
		return "剛剛已經聊過了。"
	if mg.carrying != "":
		return "店長正在送餐中。"
	release(mg)
	var fake := {"id": _uid_next("j"), "type": "order", "party": pid, "created": t, "claimed": mg.id, "preferred": "", "done": false, "cancelled": false}
	mg.job = fake
	mg.activity = "寒暄"
	mg.steps = [
		{"kind": "goto", "goals": _goals_party_table.bind(pid), "label": "前往寒暄"},
		{"kind": "work", "dur": 2.5, "label": "和客人聊天", "done": _done_chat.bind(fake)},
	]
	return ""

func _done_chat(w: Worker, j: Dictionary) -> void:
	j.done = true
	var p = party(j.party)
	if p == null:
		return
	var main: Cust = p.members[0]
	main.sat += 6
	main.causes["managerChat"] = true
	var line := "這間店氣氛不錯呢。"
	if main.def_id == "chizuru":
		line = "那孩子做的布丁越來越像樣了。" if int(s.customers.chizuru.story_stage) >= 2 else "布丁啊……火候和耐心最重要。"
	elif main.def_id == "amamiya":
		line = "小說的舞台……其實就是這間店。" if int(s.customers.amamiya.story_stage) >= 2 else "這裡很適合寫東西。只要安靜的話。"
	elif main.def_id != "" and s.customers[main.def_id].is_regular:
		line = "這裡已經是我的第二個家了。"
	say(main, line, 5)
	say(w, "謝謝您常來！", 2.5)

func _job_by_id(id: String):
	for j in jobs:
		if j.id == id:
			return j
	return null

func spend_cp(n := 1) -> bool:
	if command_points < n:
		return false
	command_points -= n
	return true

func set_role(maid_id: String, role: String) -> String:
	var w = worker(maid_id)
	var m := maid(maid_id)
	if w == null or m.is_empty():
		return "找不到女僕。"
	if m.role == "off":
		return "她今天休假。"
	if role == "stage" and (not s.activity in ["stage", "street_music", "birthday"] or layout.stage_cells.is_empty()):
		return "今天沒有舞台活動。"
	if w.carrying != "":
		return "她正在送餐，等一下再說。"
	if not spend_cp():
		return "指揮點數不足。"
	release(w)
	m.role = role
	say(w, "好的，交給我！", 2)
	return ""

func send_rest(maid_id: String) -> String:
	var w = worker(maid_id)
	if w == null or w.resting:
		return "她已經在休息了。"
	if w.carrying != "":
		return "她正在送餐，等一下再說。"
	if not spend_cp():
		return "指揮點數不足。"
	_start_rest(w)
	return ""

func toggle_pause(maid_id: String) -> String:
	var w = worker(maid_id)
	if w == null:
		return "找不到女僕。"
	if w.carrying != "":
		return "她正在送餐，等一下再說。"
	if not w.paused and not spend_cp():
		return "指揮點數不足。"
	w.paused = not w.paused
	if w.paused:
		release(w)
	return ""

func assign_job(maid_id: String, job_id: String) -> String:
	var w = worker(maid_id)
	var j = _job_by_id(job_id)
	if w == null or j == null or j.done or j.cancelled:
		return "這件事已經處理好了。"
	if maid(maid_id).role == "off":
		return "她今天休假。"
	if w.resting:
		return "她在休息中。"
	if w.carrying != "":
		return "她正在送餐，等一下再說。"
	var why := job_available(j, w)
	if why != "":
		return why
	if j.claimed == w.id:
		return "她已經在做這件事了。"
	if j.claimed != "":
		var other = worker(j.claimed)
		if other != null and (other.carrying != "" or (not other.steps.is_empty() and other.steps[0].kind == "work")):
			return "%s已經在處理了。" % other.name
		if other != null:
			release(other)
	if not spend_cp():
		return "指揮點數不足。"
	w.paused = false
	release(w)
	_assign(w, j)
	say(w, "收到！", 1.5)
	return ""

## Management orders (cost command points): floor priority, regulars first, boost a job type, close the door.
func order_boost(name: String, secs: float) -> String:
	if boosted(name):
		return "這個指令已經在生效中。"
	if not spend_cp():
		return "指揮點數不足。"
	boosts[name] = t + secs
	return ""

func toggle_door() -> String:
	if not door_closed and not spend_cp():
		return "指揮點數不足。"
	door_closed = not door_closed
	note("🚪 暫停接待新客人。" if door_closed else "🚪 恢復接待新客人。")
	return ""

func jobs_for_party(pid: String) -> Array:
	return jobs.filter(func(j): return j.get("party", "") == pid and not j.done and not j.cancelled and (j.type != "cook" or j.claimed == ""))

func job_at_cell(c: Vector2i):
	for j in jobs:
		if j.done or j.cancelled:
			continue
		match j.type:
			"mess":
				for ms in messes:
					if ms.id == j.mess and ms.cell == c:
						return j
			"clean":
				var tb = layout.table_by_id(j.table)
				if tb != null and (tb.cell == c or c in tb.seats):
					return j
			"deliver":
				var o = order(j.order)
				if o != null and o.slot >= 0 and PASS(o.slot) == c:
					return j
			"repair":
				if Layout.manhattan(_repair_cell(j.target), c) <= 1:
					return j
			"tend":
				var a = _job_anchor(j)
				if a != null and a == c:
					return j
	for st in layout.stations:
		if st.cell == c or st.stand == c:
			for j in jobs:
				if j.type == "cook" and j.claimed == "" and not j.done and not j.cancelled:
					return j
	return null

func pending_counts() -> Dictionary:
	var c := {}
	for j in jobs:
		if not j.done and not j.cancelled:
			c[j.type] = int(c.get(j.type, 0)) + 1
	return c

## Invariant check used by the automated tests: returns a list of problems (empty = healthy).
func health_check() -> Array:
	var bad := []
	var claimed := {}
	for j in jobs:
		if j.claimed != "" and not j.done and not j.cancelled:
			if claimed.has(j.id):
				bad.append("job %s double-claimed" % j.id)
			claimed[j.id] = true
			var w = worker(j.claimed)
			if w == null:
				bad.append("job %s claimed by missing worker" % j.id)
			elif w.job == null or w.job.id != j.id:
				bad.append("job %s claimed by %s who is not doing it" % [j.type, j.claimed])
	for p in parties:
		if p.state in ["browsing", "waitOrder", "waitFood", "eating"]:
			for m in p.members:
				if not m.sitting:
					bad.append("party %s %s not seated" % [p.id, p.state])
		if p.t > 200.0 and p.state != "eating":
			bad.append("party %s stuck in %s" % [p.id, p.state])
	for w in workers:
		if is_nan(w.pos.x) or is_nan(w.pos.y):
			bad.append("worker %s NaN" % w.id)
	return bad
