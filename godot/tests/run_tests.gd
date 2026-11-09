## Headless test runner:  godot --headless --path godot -s tests/run_tests.gd
## Exit code 0 = all passed.
extends SceneTree

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")
const Layout = preload("res://scripts/core/layout.gd")
const World = preload("res://scripts/core/world.gd")
const Biz = preload("res://scripts/core/business.gd")
const Settle = preload("res://scripts/core/settlement.gd")
const Social = preload("res://scripts/core/social.gd")
const Events = preload("res://scripts/core/events.gd")
const Auto = preload("res://tests/autoplay.gd")

var passed := 0
var failed := 0
var current := ""

func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  ✗ [%s] %s" % [current, msg])

func section(name: String) -> void:
	current = name
	print("— " + name)

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	test_content()
	test_layout()
	test_single_day()
	test_offhours()
	test_world()
	test_concerns()
	test_save_load()
	test_determinism()
	test_multi_day()
	test_stress()
	print("\n%d passed, %d failed  (%.1fs)" % [passed, failed, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failed > 0 else 0)

# ---------------------------------------------------------------- content
func test_content() -> void:
	section("content")
	check(Data.MAIDS.size() >= 5, "at least 5 maids")
	check(Data.CUSTOMERS.size() >= 18, "at least 18 customers")
	check(Data.RESIDENTS.size() >= 5, "at least 5 street residents")
	for id in Data.CUSTOMERS:
		var c: Dictionary = Data.CUSTOMERS[id]
		for d in c.likes:
			check(Data.DISHES.has(d), "%s likes unknown dish %s" % [id, d])
		if c.has("companion"):
			check(Data.CUSTOMERS.has(c.companion), "%s companion exists" % id)
	for id in Data.DISHES:
		for ing in Data.DISHES[id].ing:
			check(Data.INGREDIENTS.has(ing), "%s uses unknown ingredient %s" % [id, ing])
	var seasons := {}
	for id in Data.DISHES:
		if Data.DISHES[id].has("season"):
			seasons[Data.DISHES[id].season] = true
	check(seasons.size() == 4, "one seasonal dish per season")
	for r in Data.CUSTOMER_RELATIONS:
		check(Data.CUSTOMERS.has(r.a) and Data.CUSTOMERS.has(r.b), "relation members exist")
	for rid in Data.RESIDENTS:
		var sch: Dictionary = Data.RESIDENTS[rid].schedule
		for k in sch:
			for loc in sch[k]:
				check(loc == "" or Data.LOCATIONS.has(loc), "%s schedule location %s" % [rid, loc])

# ---------------------------------------------------------------- layout
func test_layout() -> void:
	section("layout")
	var s := St.new_game(1)
	var lay = Layout.new(s.furniture, s.upgrades)
	check(lay.all_reachable(), "default layout fully reachable")
	check(lay.tables.size() == 5, "5 default tables")
	check(lay.can_place("table", 9, 10) != "", "cannot block the entrance")
	check(lay.can_place("plant", 7, 6) != "", "cannot overlap furniture")
	check(lay.can_place("bookshelf", 3, 9) == "", "bookshelf fits at 3,9")
	var p = lay.find_path(Layout.DOOR_IN, lay.table_goals("f1"))
	check(p != null and p.size() > 0, "path from door to a table")
	# a wall of plants that would cut the room is rejected
	var s2 := St.new_game(2)
	var placed := 0
	for x in range(1, 17):
		if World.buy_furniture(s2, "plant", x, 5) == "":
			placed += 1
	var lay2 = Layout.new(s2.furniture, s2.upgrades)
	check(lay2.all_reachable(), "placement never breaks reachability (placed %d plants)" % placed)
	var fm: Dictionary = lay.flow_metrics()
	check(fm.kitchen_avg > 0 and fm.kitchen_avg < 99, "flow metrics computed")

# ---------------------------------------------------------------- one business day
func run_day(s: Dictionary, dt := 0.1) -> Object:
	var b = Biz.new(s, "business")
	var n := 0
	while not b.ended and n < 6000:
		b.update(dt)
		n += 1
		if n % 10 == 0:
			for h in b.health_check():
				check(false, "health: " + h)
	return b

func test_single_day() -> void:
	section("single day")
	var s := St.new_game(7)
	var b = run_day(s)
	check(b.ended, "business day ends")
	check(b.t <= Biz.HARD_END + 1, "ends before hard limit")
	check(b.results.size() > 0, "customers visited")
	check(b.revenue > 0, "revenue > 0")
	check(b.parties.is_empty(), "no party left inside")
	for w in b.workers:
		check(w.job == null or w.job.done or w.job.cancelled or b.ended, "worker job state sane")
	# every visited customer has a reason and causes are recorded
	var named := 0
	for r in b.results:
		if r.def != "":
			named += 1
			check(r.reasons.size() > 0, "%s arrival has reasons" % r.def)
	check(named > 0, "named customers visited")
	# debugging observability: candidates and failure reasons are recorded
	var had_cands := false
	for w in b.workers:
		if not w.candidates.is_empty():
			had_cands = true
	check(had_cands, "job candidates recorded for debug")
	var rep := Settle.settle(s, b)
	check(rep.reviews.size() > 0, "reviews written")
	check(s.phase == "night", "phase night after settle")
	Settle.next_day(s)
	check(int(s.day) == 2 and s.phase == "explore", "next day")

func test_offhours() -> void:
	section("offhours life")
	var s := St.new_game(11)
	World.buy_furniture(s, "bookshelf", 3, 9)
	s.staff.append("yukino")
	s.maids.yukino.hired_day = 1
	var b = Biz.new(s, "offhours")
	var acts := {}
	for i in 1200:
		b.update(0.25)
		for w in b.workers:
			if w.kind == "maid":
				acts[w.activity] = true
		if i % 40 == 0:
			for h in b.health_check():
				check(false, "health: " + h)
			# no two maids standing still on the same cell
			var cells := {}
			for w in b.workers:
				if w.path.is_empty():
					var k := Layout.key(w.cell)
					check(not cells.has(k), "two idle workers stacked at %s" % k)
					cells[k] = true
	check(acts.size() >= 4, "maids do varied things after hours (%s)" % ", ".join(acts.keys()))
	var read := false
	for a in acts:
		if "書" in a:
			read = true
	check(read, "a bookish maid reads at the bookshelf")

# ---------------------------------------------------------------- world
func test_world() -> void:
	section("world & street")
	var s := St.new_game(3)
	var wd := Data.weekday(1)
	check(World.resident_location(s, "yamada", 0) == "grocer", "yamada at grocer in the morning")
	var enc := World.visit_location(s, "park")
	check(s.customers.mayu.known, "meet mayu at the park")
	check(int(s.action_points) == Data.DAY_ACTION_POINTS - 1, "visit uses an action point")
	check(World.slot_index(s) == 1, "time advances")
	var e := World.buy_ingredient(s, "sakura", 1)
	check(e == "", "spring sakura available on day 1 (%s)" % e)
	check(World.buy_ingredient(s, "chestnut", 1) != "", "autumn chestnut not sold in spring")
	# collaborations unlock through repeated talks
	for i in 4:
		s.day = 1 + i
		World.talk_resident(s, "sunahara")
	var t := World.talk_resident(s, "sunahara")
	s.day = 1
	check(float(World.resident(s, "sunahara").aff) >= 16, "resident affinity grows over days")
	check(World.accept_offer(s, "sweets_collab") == "", "sign sweets collab")
	check("collab_cake" in s.unlocked_dishes, "collab dish unlocked")
	check(World.ingredient_price(s, "cream") < Data.INGREDIENTS.cream.price, "partner discount")
	# activities with requirements
	check(World.activity_requirement(s, "stage") != "", "stage needs a stage")
	check(World.activity_requirement(s, "street_music") != "", "street music needs collab")
	s.day = 10
	check(World.birthday_maid(s) == "koharu", "koharu's birthday on day 10")
	check(World.activity_requirement(s, "birthday") == "", "birthday party possible on the day")
	var brief := World.morning_briefing(s)
	check(brief.size() >= 2, "morning briefing has content")

# ---------------------------------------------------------------- concerns
func test_concerns() -> void:
	section("concerns")
	var s := St.new_game(5)
	St.rel_change(s, "koharu", "rin", "friction", 50, "test")
	var stats := {}
	var rng := RandomNumberGenerator.new()
	var got := false
	for i in 20:
		rng.seed = i
		Social.daily(s, stats, rng)
		for m in St.active_maids(s):
			if not m.concern.is_empty():
				got = true
		if got:
			break
	check(got, "friction creates a concern")
	var mid := ""
	for m in St.active_maids(s):
		if not m.concern.is_empty():
			mid = m.id
	if mid == "":
		return
	var c: Dictionary = s.maids[mid].concern
	check(c.has("sign") and c.has("confide"), "concern has visible sign and confide text")
	# it shows in the scene: the maid picks the concern leisure
	var b = Biz.new(s, "offhours")
	var seen := false
	for i in 800:
		b.update(0.25)
		var w = b.worker(mid)
		if w.activity == c.leisure:
			seen = true
			break
	check(seen, "concern visible as a behaviour (%s)" % c.leisure)
	# asking first (cafe chat) reveals it
	World.visit_location(s, "cafe", mid)
	check(s.maids[mid].concern.get("revealed", false), "chatting reveals the concern")
	var opts := Social.options(s, mid)
	check(opts.size() >= 3, "intervene / alternative / ignore options")
	if c.type == "quarrel":
		var before := float(St.rel(s, "koharu", "rin").friction)
		Social.resolve(s, mid, "mediate")
		check(float(St.rel(s, "koharu", "rin").friction) < before - 10, "mediation after asking lowers friction")
	else:
		Social.resolve(s, mid, opts[0].id)
	check(s.maids[mid].concern.is_empty(), "concern resolved")
	var reasons := 0
	for r in s.rel_log:
		if r.reason != "":
			reasons += 1
	check(reasons > 0, "relationship changes keep their reason")

# ---------------------------------------------------------------- save/load
func test_save_load() -> void:
	section("save/load")
	var a := Auto.new(21)
	a.play_days(3)
	var txt := St.serialize(a.s)
	var copy := St.deserialize(txt)
	check(not copy.is_empty(), "deserialize works")
	check(St.serialize(copy) == txt, "roundtrip is lossless")
	check(typeof(copy.day) == TYPE_INT, "ints stay ints")
	# continue both: identical results
	var b := Auto.new(0)
	b.s = copy
	a.play_day()
	b.play_day()
	check(St.serialize(a.s) == St.serialize(b.s), "loaded game continues identically")
	check(St.deserialize("garbage").is_empty(), "bad save rejected")

func test_determinism() -> void:
	section("determinism")
	var a := Auto.new(99)
	var b := Auto.new(99)
	a.play_days(2)
	b.play_days(2)
	check(St.serialize(a.s) == St.serialize(b.s), "same seed same game")

# ---------------------------------------------------------------- multi-day
func test_multi_day() -> void:
	section("multi-day (35 days)")
	var a := Auto.new(2024)
	a.play_days(35)
	for p in a.problems.slice(0, 10):
		print("    problem: " + p)
	check(a.problems.is_empty(), "no health problems over 35 days (%d)" % a.problems.size())
	check(a.max_party_t < 200, "no party stuck (max %.0fs)" % a.max_party_t)
	check(a.max_job_age < 150, "no job waits forever (max %.0fs)" % a.max_job_age)
	var s: Dictionary = a.s
	check(int(s.day) == 36, "35 days played")
	check(not is_nan(float(s.money)), "money is a number")
	# memory tiers stay bounded
	for cid in s.customers:
		var c: Dictionary = s.customers[cid]
		check(c.recent.size() <= St.CAP_RECENT_VISITS, "recent capped")
		check(c.log.size() <= St.CAP_CUSTOMER_LOG, "customer log capped")
	for k in s.maid_rel:
		check(s.maid_rel[k].shared.size() <= St.CAP_REL_SHARED, "shared memories capped")
	check(s.moments.size() <= St.CAP_MOMENT_LOG, "moments capped")
	# systems actually did something
	var regulars := 0
	for cid in s.customers:
		if s.customers[cid].is_regular:
			regulars += 1
	check(regulars >= 2, "regulars formed (%d)" % regulars)
	var changed := false
	for k in s.maid_rel:
		var r: Dictionary = s.maid_rel[k]
		if float(r.synergy) > 15 or float(r.trust) > 35:
			changed = true
	check(changed, "relationships grew from shared work")
	var habit_up := false
	for mid in s.staff:
		var m: Dictionary = s.maids[mid]
		for h in m.habits:
			if float(m.habits[h]) > float(Data.MAIDS[mid].get("seed_habits", {}).get(h, 0)) + 10:
				habit_up = true
	check(habit_up, "habits formed from behaviour")
	check(s.album.size() >= 5, "album has memories (%d)" % s.album.size())
	var ids := {}
	var dup := false
	for mo in s.moments:
		var k := "%d:%s" % [mo.day, mo.id]
		if ids.has(k):
			dup = true
		ids[k] = true
	check(not dup, "no duplicated moment on the same day")
	check(s.moments.size() >= 5, "daily moments happened (%d)" % s.moments.size())
	check(s.staff.size() >= 4, "recruited new maids (%s)" % ", ".join(s.staff))
	# visit habits: Shiraishi (Tue/Thu reader) mostly comes on her days
	var sh: Dictionary = s.customers.shiraishi
	if int(sh.visits) >= 3:
		var on := int(sh.weekday_counts[1]) + int(sh.weekday_counts[3])
		check(on * 2 >= int(sh.visits), "shiraishi comes mostly on Tue/Thu (%s)" % str(sh.weekday_counts))
	var pref_seats := 0
	for cid in s.customers:
		if s.customers[cid].fav_seat != "":
			pref_seats += 1
	check(pref_seats >= 2, "customers learned favourite seats")
	var acq: int = s.cust_rel.values().filter(func(r): return r.type == "acquaintance").size()
	check(acq >= 1 and acq <= 8, "a few customers became acquaintances in the cafe (%d)" % acq)
	var seasonal := false
	for id in s.unlocked_dishes:
		if Data.DISHES[id].get("season", "") == "summer":
			seasonal = true
	check(seasonal, "summer dish unlocked in season 2")
	print("    " + "\n    ".join(a.log.filter(func(l): return l.begins_with("D")).slice(0, 35)))
	print("    album: " + ", ".join(s.album.map(func(x): return x.title)))
	print("    staff: %s  album: %d  moments: %d  regulars: %d  acquaintances: %d" % [", ".join(s.staff), s.album.size(), s.moments.size(), regulars,
		s.cust_rel.values().filter(func(r): return r.type == "acquaintance").size()])

func test_stress() -> void:
	section("stress: crowded festival")
	var s := St.new_game(77)
	for p in [[7, 4], [11, 4], [15, 4], [15, 8], [3, 8]]:
		World.buy_furniture(s, "table", p[0], p[1])
	s.popularity = 90.0
	s.street.event = "festival"
	s.weather = "rain"
	s.money = 99999.0
	for k in s.inventory.keys():
		s.inventory[k] = 40
	for k in ["cream", "strawberry", "chocolate", "pasta", "cheese", "curry", "matcha", "cocoa"]:
		s.inventory[k] = 40
	var b = run_day(s, 0.2)
	check(b.ended, "crowded day ends")
	check(b.served_count >= 15, "served many (%d)" % b.served_count)
	print("    served %d lost %d congestion %.0fs incidents %s" % [b.served_count, b.lost, b.congestion, str(b.incidents)])
