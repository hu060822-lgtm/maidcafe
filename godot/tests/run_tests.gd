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
const Life = preload("res://scripts/core/life.gd")
const LD = preload("res://scripts/core/life_data.gd")
const Main = preload("res://scripts/view/main.gd")

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
	test_life_content()
	test_directional_relations()
	test_promises_and_talks()
	test_life_in_the_cafe()
	test_arcs_and_pairs()
	test_customer_life()
	test_album_and_decor()
	test_recruit_more()
	test_migration()
	test_autonomy()
	test_long_life()
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

# ======================================================================== Living Hearts
func _ctx(s: Dictionary, served := 10) -> Dictionary:
	var working := []
	for m in St.active_maids(s):
		if m.role != "off":
			working.append(m.id)
	return Life.make_ctx(s, served, World.dominant_style(s).key, working)

func test_life_content() -> void:
	section("living hearts: content")
	check(Data.MAIDS.size() >= 9, "9 maids (%d)" % Data.MAIDS.size())
	check(Data.MAX_STAFF == 6, "staff cap 6")
	var recruitable := 0
	for mid in Data.MAIDS:
		var L: Dictionary = LD.MAID_LIFE.get(mid, {})
		check(not L.is_empty(), "%s has a personal life" % mid)
		if Data.MAIDS[mid].has("recruit"):
			recruitable += 1
			check(Data.LOCATIONS.has(Data.MAIDS[mid].recruit.location), "%s recruit location" % mid)
		for tag in L.get("likes", []) + L.get("dislikes", []):
			var p: PackedStringArray = tag.split(":")
			var ok: bool = tag in ["busy", "quiet", "decor"] or (p.size() == 2 and p[0] in ["music", "light", "weather", "act", "furn", "style", "dish"])
			if ok and p.size() == 2:
				match p[0]:
					"music":
						ok = Data.MUSIC.has(p[1])
					"light":
						ok = Data.LIGHTING.has(p[1])
					"act":
						ok = Data.ACTIVITIES.has(p[1])
					"furn":
						ok = Data.FURNITURE.has(p[1])
					"style":
						ok = Data.STYLE_NAMES.has(p[1])
					"dish":
						ok = Data.DISHES.has(p[1])
			check(ok, "%s tag %s is understood by the sim" % [mid, tag])
		for loc in L.get("offday", {}):
			check(Data.LOCATIONS.has(loc), "%s off-day location %s" % [mid, loc])
		for w in L.get("wants", []):
			match w.kind:
				"furniture":
					check(Data.FURNITURE.has(w.type), "%s wants known furniture" % mid)
				"upgrade":
					check(Data.UPGRADES.has(w.id), "%s wants known upgrade" % mid)
				"dish":
					check(Data.DISHES.has(w.dish), "%s wants known dish" % mid)
				"music":
					check(Data.MUSIC.has(w.key), "%s wants known music" % mid)
				"activity":
					check(Data.ACTIVITIES.has(w.act), "%s wants known activity" % mid)
		check(L.get("arc", []).size() >= 2, "%s has a 2-stage personal story" % mid)
	check(recruitable >= 6, "6 recruitable maids (%d)" % recruitable)
	for cid in LD.CUSTOMER_LIFE:
		check(Data.CUSTOMERS.has(cid), "customer life %s exists" % cid)
	for k in Data.SEASONS:
		check(LD.DECOR.has(k), "decor for %s" % k)

func test_directional_relations() -> void:
	section("living hearts: directional relationships")
	var s := St.new_game(5)
	check(s.maid_rel.size() == Data.MAIDS.size() * (Data.MAIDS.size() - 1), "one relation per ordered pair")
	check(float(St.rel(s, "shizuku", "koharu").trust) > float(St.rel(s, "koharu", "shizuku").trust), "shizuku leans on koharu more than the reverse")
	var before := float(St.rel(s, "rin", "koharu").trust)
	St.rel_change(s, "koharu", "rin", "trust", 10.0, "test", false)
	check(float(St.rel(s, "koharu", "rin").trust) == 40.0, "one-way change applies to a's view")
	check(float(St.rel(s, "rin", "koharu").trust) == before, "the other direction is untouched")
	St.rel_change(s, "koharu", "rin", "close", 5.0, "test")
	check(float(St.rel(s, "rin", "koharu").close) == 35.0, "mutual change applies to both")
	# helping: the helped trusts the helper (asymmetric) — run through the settlement
	var b = Biz.new(s, "business")
	b.helps.append({"helper": "koharu", "helped": "shizuku", "type": "deliver"})
	b.helps.append({"helper": "koharu", "helped": "shizuku", "type": "deliver"})
	var t_ks := float(St.rel(s, "koharu", "shizuku").trust)
	var t_sk := float(St.rel(s, "shizuku", "koharu").trust)
	b.ended = true
	Settle.settle(s, b)
	check(float(St.rel(s, "shizuku", "koharu").trust) > t_sk + 3.0, "helped maid trusts the helper more")
	check(float(St.rel(s, "koharu", "shizuku").trust) == t_ks, "helper's trust is not changed by helping")
	# arguments: the outcome depends on how much the other one trusts her
	var s2 := St.new_game(6)
	St.rel(s2, "rin", "koharu").friction = 60.0
	St.rel(s2, "koharu", "rin").trust = 60.0
	var r1 := Life.argue(s2, "rin", "koharu")
	check(r1.ok and float(St.rel(s2, "rin", "koharu").friction) < 60.0, "argument with trust is talked out")
	var s3 := St.new_game(6)
	St.rel(s3, "rin", "koharu").friction = 60.0
	St.rel(s3, "koharu", "rin").trust = 10.0
	var r2 := Life.argue(s3, "rin", "koharu")
	check(not r2.ok and s3.flags.has("unresolved:" + St.pair_key("rin", "koharu")), "argument without trust stays unresolved")
	check(s3.maids.koharu.memories.size() > 0, "both remember the fight")
	# reconcile comes when one later helps the other
	Life.pair_events(s3, ["rin", "koharu"], [{"helper": "rin", "helped": "koharu", "type": "cook"}])
	check(("pair:reconcile|" + St.pair_key("rin", "koharu").replace("|", "|")) in s3.pending_events or s3.pending_events.any(func(e): return String(e).begins_with("pair:reconcile")), "reconcile event after helping")
	var ev := Events.next_event(s3)
	check(not ev.is_empty() and ev.title == "和好", "reconcile scene builds")
	var fr := float(St.rel(s3, "rin", "koharu").friction)
	Events.resolve(s3, ev.id, 0)
	check(float(St.rel(s3, "rin", "koharu").friction) < fr, "reconciling lowers friction")
	# argue happens by itself in the off-hours sim
	var s4 := St.new_game(8)
	St.rel(s4, "rin", "koharu").friction = 80.0
	var nb = Biz.new(s4, "offhours")
	for i in 600:
		nb.update(0.25)
	check(nb.argued.has(St.pair_key("rin", "koharu")), "maids with high friction argue after hours on their own")

func test_promises_and_talks() -> void:
	section("living hearts: talking & promises")
	var s := St.new_game(12)
	var rng := RandomNumberGenerator.new()
	var m: Dictionary = s.maids.koharu
	m.flags["tired_nights"] = 2
	m.flags["want_next"] = 0
	Life.daily(s, rng, [])
	check(m.want_talk.get("topic", "") == "tired", "a tired maid wants to talk about it")
	var tv := Life.talk_view(s, "koharu")
	check(tv.options.size() == 2, "talk has options")
	Life.talk_resolve(s, "koharu", "rest")
	check(m.day_off_tomorrow and m.want_talk.is_empty(), "listening gives her a day off")
	# a request becomes a promise; kept by really buying the furniture
	m.want_talk = {"topic": "request", "short": "x", "line": "x", "day": int(s.day), "want": Life._pick_request(s, "koharu")}
	check(m.want_talk.want.get("kind", "") != "", "koharu has something to ask for")
	var bond0 := float(m.bond)
	Life.talk_resolve(s, "koharu", "promise")
	check(s.promises.size() == 1 and s.promises[0].status == "open", "promise recorded")
	var p: Dictionary = s.promises[0]
	if p.kind == "furniture":
		World.buy_furniture(s, p.data.type, 3, 9)
	elif p.kind == "activity":
		s.activity = p.data.act
	elif p.kind == "music":
		s.music = p.data.key.split(":")[-1]
	Life.check_promises(s, _ctx(s), [])
	check(p.status == "kept", "promise kept by what the manager did (%s)" % p.kind)
	check(float(m.bond) > bond0 + 5, "keeping a promise raises trust")
	check(Life.memory_line(s, "koharu", 0).find("謝謝妳記得") >= 0, "she mentions the kept promise when you talk")
	# broken promise
	var s2 := St.new_game(13)
	var r: Dictionary = s2.maids.rin
	Life.add_promise(s2, "rin", {"kind": "music", "key": "jazz", "days": 2}, "放爵士樂")
	var b0 := float(r.bond)
	for i in 3:
		s2.music = "pop"
		Life.check_promises(s2, _ctx(s2), [])
		s2.day = int(s2.day) + 1
	check(s2.promises[0].status == "broken", "unkept promise breaks after its days")
	check(float(r.bond) < b0 - 5, "breaking it lowers trust")
	check(r.memories.any(func(x): return x.tag == "promise_broken"), "she remembers the broken promise")
	check(Life.memory_line(s2, "rin", 0).find("沒關係") >= 0 or int(s2.day) - int(r.memories[-1].day) > 3, "she brings it up later")
	# promised day off on a specific day
	var s3 := St.new_game(14)
	var pr := Life.add_promise(s3, "rin", {"kind": "dayoff_on", "days": 2, "kept_flag": "rin_contest_went"}, "比賽那天放假")
	s3.day = int(pr.target)
	s3.maids.rin.role = "off"
	Life.check_promises(s3, _ctx(s3), [])
	check(pr.status == "kept" and s3.flags.get("rin_contest_went", false), "day-off promise kept on the day, story flag set")
	# ignored wish expires with a consequence
	var s4 := St.new_game(15)
	var y: Dictionary = s4.maids.shizuku
	y.want_talk = {"topic": "share", "short": "昨天被客人誇獎了", "line": "x", "day": int(s4.day)}
	var yb := float(y.bond)
	s4.day = int(s4.day) + Life.WANT_EXPIRE
	Life.daily(s4, rng, [])
	check(y.want_talk.is_empty() and float(y.bond) < yb, "ignored wish fades and costs trust")
	check(y.memories.any(func(x): return x.tag == "ignored"), "she remembers not being heard")
	# she walks to the manager after hours
	var s5 := St.new_game(16)
	s5.maids.koharu.want_talk = {"topic": "share", "short": "昨天被客人誇獎了", "line": "x", "day": int(s5.day)}
	var nb = Biz.new(s5, "offhours")
	var sought := false
	for i in 200:
		nb.update(0.25)
		if nb.sought.has("koharu"):
			sought = true
			break
	check(sought, "a maid with something to say comes to find the manager")
	var mg = nb.manager()
	check(Layout.manhattan(nb.worker("koharu").cell, mg.cell) <= 2, "she stands next to the manager")

func test_life_in_the_cafe() -> void:
	section("living hearts: likes, days off, furniture")
	var s := St.new_game(21)
	s.music = "pop"
	s.activity = "costume"
	var m0 := float(s.maids.koharu.mood)
	var r0 := float(s.maids.rin.mood)
	Life.day_feelings(s, _ctx(s, 20))
	check(float(s.maids.koharu.mood) > m0, "koharu enjoys pop music / costume day")
	check(float(s.maids.rin.mood) < r0, "rin dislikes costume day")
	check(not s.maids.koharu.flags.feel.is_empty(), "the reasons are kept for the notebook")
	# day off: planned at the street, met when visiting
	var s2 := St.new_game(22)
	s2.maids.koharu.role = "off"
	Life.plan_offdays(s2)
	var loc: String = s2.maids.koharu.offday.get("loc", "")
	check(loc != "", "day-off plan made")
	var enc := World.visit_location(s2, loc)
	check(enc.lines.any(func(l): return String(l).find("放假的小春") >= 0), "you can meet her on her day off")
	# two close friends who are off go together and it becomes a shared memory
	var s3 := St.new_game(23)
	s3.maids.koharu.role = "off"
	s3.maids.shizuku.role = "off"
	St.rel(s3, "koharu", "shizuku").close = 70.0
	St.rel(s3, "shizuku", "koharu").close = 70.0
	Life.plan_offdays(s3)
	check(s3.maids.koharu.offday.with == "shizuku" or s3.maids.shizuku.offday.with == "koharu", "friends spend the day off together")
	Life.offday_settle(s3, [])
	check(St.rel(s3, "koharu", "shizuku").shared.any(func(x): return String(x.text).find("一起放假") >= 0), "shared day-off memory")
	# furniture changes what they do after hours
	var s4 := St.new_game(24)
	s4.money = 99999.0
	World.buy_furniture(s4, "plush", 3, 9)
	World.buy_furniture(s4, "sofa_table", 15, 8)
	World.buy_furniture(s4, "plant", 14, 9)
	s4.staff.append("hiyori")
	s4.maids.koharu.fatigue = 5.0
	s4.maids.shizuku.fatigue = 75.0
	s4.maids.hiyori.fatigue = 70.0
	var acts := {}
	var nb = Biz.new(s4, "offhours")
	for i in 1600:
		nb.update(0.25)
		for w in nb.workers:
			if w.kind == "maid" and not w.leisure.is_empty() and w.leisure.get("started", false):
				acts[w.leisure.id] = true
		if i % 40 == 0:
			for h in nb.health_check():
				check(false, "health: " + h)
	check(acts.has("plush"), "someone hugs the bear (%s)" % ", ".join(acts.keys()))
	check(acts.has("nap"), "a tired maid naps on the sofa seat")
	check(acts.has("water"), "someone waters the plants")
	# without the furniture those things never happen
	var s5 := St.new_game(24)
	var acts2 := {}
	var nb2 = Biz.new(s5, "offhours")
	for i in 800:
		nb2.update(0.25)
		for w in nb2.workers:
			if w.kind == "maid" and not w.leisure.is_empty():
				acts2[w.leisure.id] = true
	check(not acts2.has("plush") and not acts2.has("nap"), "no bear / sofa, no hugging / napping")

func test_arcs_and_pairs() -> void:
	section("living hearts: personal stories & pair events")
	var s := St.new_game(31)
	var m: Dictionary = s.maids.koharu
	check(not Life.arc_ready(s, "koharu"), "arc waits for real conditions")
	m.bond = 50.0
	m.days_worked = 6
	check(Life.arc_ready(s, "koharu"), "arc ready once trust and time are there")
	Life.daily(s, RandomNumberGenerator.new(), [])
	check("arc:koharu" in s.pending_events, "arc scene queued")
	var ev := Events.build(s, "arc:koharu")
	check(ev.title == "小春的歌詞本" and ev.choices.size() == 2, "arc scene builds")
	Events.resolve(s, "arc:koharu", 0)
	check(int(m.arc_stage) == 1 and s.promises.size() == 1 and s.promises[0].data.type == "stage", "choice creates a promise (stage)")
	check(not Life.arc_ready(s, "koharu"), "stage 2 needs the stage and a performance")
	s.money = 99999.0
	World.buy_furniture(s, "stage", 3, 7)
	s.flags["stage_days"] = 1
	m.skills.performance = 65.0
	m.flags["arc_last"] = -99
	check(Life.arc_ready(s, "koharu"), "stage 2 ready when it really happened")
	Events.resolve(s, "arc:koharu", 0)
	check(s.album.any(func(a): return a.get("key", "") == "arc_koharu_1"), "story ending goes to the album")
	# the other branch: refusing has its own consequence
	var s2 := St.new_game(32)
	s2.maids.rin.bond = 50.0
	s2.maids.rin.skills.cooking = 75.0
	var b0 := float(s2.maids.rin.bond)
	Events.resolve(s2, "arc:rin", 1)
	check(float(s2.maids.rin.bond) < b0 and s2.maids.rin.memories.any(func(x): return x.text.find("比賽") >= 0), "refusing is remembered")
	# mentor: comes from skill gap + trust, once per pair
	var s3 := St.new_game(33)
	St.rel(s3, "shizuku", "rin").trust = 60.0
	Life.pair_events(s3, ["rin", "shizuku"], [])
	check(s3.pending_events.any(func(e): return String(e).begins_with("pair:mentor|rin|shizuku")), "mentor event from trust and skill gap")
	var q: int = s3.pending_events.size()
	Life.pair_events(s3, ["rin", "shizuku"], [])
	check(s3.pending_events.size() == q, "same pair event never queued twice")
	var e: String = s3.pending_events[0]
	var sk0 := float(s3.maids.shizuku.skills.cooking)
	Events.resolve(s3, e, 0)
	check(float(s3.maids.shizuku.skills.cooking) > sk0, "mentoring improves the skill")

func test_customer_life() -> void:
	section("living hearts: customers' lives")
	var s := St.new_game(41)
	var k: Dictionary = s.customers.kenta
	k.visits = 4
	var res := [{"def": "kenta", "causes": ["greatFood", "remembered"], "table": "f1", "items": ["m_omurice"], "sat": 80.0}]
	Life.customers_daily(s, res, {}, [])
	check(k.life.state == "job_hunting", "kenta starts job hunting after enough visits")
	check(float(k.impressions.get("food", 0.0)) > 0, "impressions come from the visit")
	check(s.pending_events.has("carc:kenta|0"), "his scene is queued")
	var mod := Life.arrival_mod(s, "kenta")
	check(mod.has("arrival") and float(mod.chance) < 1.0, "job hunting changes when and how often he comes")
	check(Life.arrival_line(s, "kenta", []).find("面試") >= 0, "his arrival line comes from his life")
	for i in 8:
		s.day = int(s.day) + 1
		Life.customers_daily(s, [], {}, [])
	check(k.life.get("done", false), "the job hunt ends")
	Life.customers_daily(s, res, {}, [])
	check(k.life.state == "employed" and k.life.weekdays == [4], "employed: new weekly routine (Friday)")
	# a deadline keeps hayase away
	var s2 := St.new_game(42)
	var h: Dictionary = s2.customers.hayase
	h.visits = 4
	Life.customers_daily(s2, [{"def": "hayase", "causes": [], "table": "", "items": [], "sat": 60.0}], {}, [])
	check(Life.arrival_mod(s2, "hayase").skip, "deadline: he does not come")
	var b = Biz.new(s2, "business")
	check(not b.arrivals.any(func(a): return "hayase" in a.ids), "arrival plan respects it")
	# impressions decay and gossip spreads
	var s3 := St.new_game(43)
	s3.customers.akiko.impressions = {"service": 10.0}
	var tb := float(s3.customers.tachibana.impressions.get("gossip", 0.0))
	Life.customers_daily(s3, [{"def": "akiko", "causes": ["favMaid"], "table": "", "items": [], "sat": 70.0}], {}, [])
	check(float(s3.customers.tachibana.impressions.get("gossip", 0.0)) > tb, "akiko tells her friend about the cafe")
	var v := float(s3.customers.akiko.impressions.service)
	Life.customers_daily(s3, [], {}, [])
	check(float(s3.customers.akiko.impressions.service) < v, "impressions fade without visits")
	# related customers remember evenings together
	var s4 := St.new_game(44)
	var key := St.pair_key("sakura", "misaki")
	Life.customers_daily(s4, [{"def": "sakura", "causes": [], "table": "f1", "items": [], "sat": 60.0}, {"def": "misaki", "causes": [], "table": "f1", "items": [], "sat": 60.0}], {key: 60.0}, [])
	check(s4.cust_rel[key].memories.size() == 1, "friends remember the evening")
	check(Life.arrival_line(s4, "sakura", ["misaki"]).find("美咲") >= 0, "and mention it next time they meet")

func test_album_and_decor() -> void:
	section("living hearts: album & decoration")
	var s := St.new_game(51)
	check(St.add_album(s, "t", "x", ["koharu"], "", "k1"), "album add")
	check(not St.add_album(s, "t2", "y", ["koharu"], "", "k1"), "same key never recorded twice")
	check(s.album[-1].cat == "maid", "category guessed from who")
	St.add_album(s, "p", "x", ["koharu", "rin"], "", "k2")
	check(s.album[-1].cat == "pair", "pair category")
	check(not Main.album_has_photo({"image": ""}), "no image -> fallback")
	check(not Main.album_has_photo({"image": "pending"}), "pending -> fallback")
	check(not Main.album_has_photo({"image": "user://memories/does_not_exist.png"}), "missing file -> fallback")
	var m0 := float(s.money)
	var st0: Dictionary = World.style_scores(s)
	check(World.set_decor(s) == "", "decor bought")
	check(float(s.money) < m0 and s.decor == Data.season(int(s.day)), "decor costs money and is up")
	var st1: Dictionary = World.style_scores(s)
	var changed := false
	for k in st1:
		if float(st1[k]) > float(st0[k]):
			changed = true
	check(changed, "decor changes the style")
	check(World.set_decor(s) != "", "cannot buy twice")
	s.day = Data.SEASON_DAYS
	Settle.next_day(s)
	check(s.decor == "", "decor comes down when the season ends")

func test_recruit_more() -> void:
	section("living hearts: more recruitable maids")
	var s := St.new_game(61)
	s.popularity = 60.0
	for i in 5:
		World.visit_location(s, "general")
	check(not s.flags.get("recruit_tsumugi", false), "tsumugi needs the craft collaboration first")
	s.flags["tsukimi_collab"] = true
	World.visit_location(s, "general")
	check(s.flags.get("recruit_tsumugi", false), "tsumugi can be recruited after it")
	for mid in ["yukino", "kaede", "tsumugi"]:
		s.flags["recruit_" + mid] = true
		check(World.hire_maid(s, mid) == "", "hire %s" % mid)
	check(s.staff.size() == 6, "six maids")
	s.flags["recruit_hiyori"] = true
	check(World.hire_maid(s, "hiyori") != "", "seventh is refused")
	var b = run_day(s)
	check(b.ended and b.results.size() > 0, "a day with six maids runs")
	var nb = Biz.new(s, "offhours")
	var cells := {}
	for w in nb.workers:
		check(not cells.has(w.cell), "no two maids spawn on one cell")
		cells[w.cell] = true

func test_migration() -> void:
	section("living hearts: v2 save migration")
	var s := St.new_game(71)
	var old := {}
	for a in ["koharu", "rin", "shizuku", "yukino", "kaede"]:
		for b2 in ["koharu", "rin", "shizuku", "yukino", "kaede"]:
			if a < b2:
				old[a + "|" + b2] = St.new_relation()
	old["koharu|rin"].close = 77.0
	s.maid_rel = old
	s.version = 2
	for mid in ["tsumugi", "chinatsu", "aoi", "hiyori"]:
		s.maids.erase(mid)
	for mid in s.maids:
		for k in ["bond", "memories", "want_talk", "arc_stage", "offday", "likes_seen"]:
			s.maids[mid].erase(k)
	for cid in s.customers:
		for k in ["life", "arc_stage", "impressions"]:
			s.customers[cid].erase(k)
	s.erase("promises")
	s.erase("decor")
	for a in s.album:
		a.erase("key")
		a.erase("cat")
	var txt := "MP2:" + Marshalls.raw_to_base64(var_to_bytes(s))
	var v := St.deserialize(txt)
	check(not v.is_empty() and int(v.version) == St.VERSION, "v2 save loads")
	check(float(St.rel(v, "rin", "koharu").close) == 77.0 and float(St.rel(v, "koharu", "rin").close) == 77.0, "old pair becomes two directions")
	check(v.maids.has("hiyori") and v.maids.koharu.has("bond"), "missing maids and fields filled")
	check(v.has("promises") and v.album[0].has("key"), "new keys filled")
	var a2 := Auto.new(0)
	a2.s = v
	a2.play_day()
	check(a2.problems.is_empty(), "migrated save plays a day")

## Nobody answers the maids: they still live, wishes expire with consequences, nothing piles up.
func test_autonomy() -> void:
	section("living hearts: autonomy (no player input)")
	var a := Auto.new(808)
	a.listen = false
	a.keep_promises = false
	a.commands = false
	a.play_days(20)
	var s: Dictionary = a.s
	check(a.problems.is_empty(), "no health problems (%d)" % a.problems.size())
	var mems := 0
	var ignored := 0
	for mid in s.staff:
		mems += s.maids[mid].memories.size()
		ignored += s.maids[mid].memories.filter(func(x): return x.tag == "ignored").size()
	check(mems >= 6, "maids collected memories on their own (%d)" % mems)
	check(ignored >= 1, "unanswered wishes are remembered (%d)" % ignored)
	var imp := 0
	for cid in s.customers:
		if not s.customers[cid].impressions.is_empty():
			imp += 1
	check(imp >= 5, "customers formed impressions (%d)" % imp)
	check(s.pending_events.size() <= 6, "events don't pile up (%d)" % s.pending_events.size())
	# the attentive player's maids trust them more than the passive one's
	var b := Auto.new(808)
	b.play_days(20)
	var ta := 0.0
	var tb := 0.0
	for mid in Data.STARTING_MAIDS:
		ta += float(a.s.maids[mid].bond)
		tb += float(b.s.maids[mid].bond)
	check(tb > ta + 30, "listening and keeping promises builds trust (%.0f vs %.0f)" % [tb, ta])
	check(b.talks > 0, "the attentive player talked with maids (%d)" % b.talks)

func test_long_life() -> void:
	section("living hearts: 60-day life simulation")
	var a := Auto.new(4242)
	a.play_days(60)
	var s: Dictionary = a.s
	for p in a.problems.slice(0, 8):
		print("    problem: " + p)
	check(a.problems.is_empty(), "no stuck NPCs / health problems over 60 days (%d)" % a.problems.size())
	check(a.max_party_t < 200, "no party stuck (%.0f)" % a.max_party_t)
	check(not is_nan(float(s.money)), "money is a number")
	var keys := {}
	var dup := false
	for e in s.album:
		var ek: String = e.get("key", e.title)
		if keys.has(ek):
			dup = true
		keys[ek] = true
	check(not dup, "no album entry recorded twice")
	check(s.album.size() <= 90, "album stays reasonable (%d)" % s.album.size())
	check(s.promises.size() <= St.CAP_PROMISES, "promises capped")
	var kept: int = s.promises.filter(func(p): return p.status == "kept").size()
	check(kept >= 3, "promises were made and kept (%d)" % kept)
	var arcs := 0
	for mid in s.staff:
		var m: Dictionary = s.maids[mid]
		check(m.memories.size() <= St.CAP_MAID_MEMORY, "%s memories capped" % mid)
		check(float(m.bond) >= 0 and float(m.bond) <= 100 and float(m.mood) >= 0 and float(m.mood) <= 100, "%s values in range" % mid)
		arcs += int(m.arc_stage)
	check(arcs >= 4, "personal stories advanced (%d stages)" % arcs)
	for k in s.maid_rel:
		var r: Dictionary = s.maid_rel[k]
		for dim in ["close", "trust", "synergy", "friction"]:
			check(float(r[dim]) >= 0 and float(r[dim]) <= 100, "rel %s %s in range" % [k, dim])
	var asym := false
	for k in s.maid_rel:
		var p: PackedStringArray = String(k).split(">")
		if s.maid_rel.has(p[1] + ">" + p[0]) and absf(float(s.maid_rel[k].trust) - float(s.maid_rel[p[1] + ">" + p[0]].trust)) >= 5:
			asym = true
	check(asym, "relationships became asymmetric from what happened")
	var lives := 0
	for cid in LD.CUSTOMER_LIFE:
		if int(s.customers[cid].arc_stage) > 0:
			lives += 1
	check(lives >= 2, "customers' lives moved on (%d)" % lives)
	var crm := 0
	for k in s.cust_rel:
		crm += s.cust_rel[k].get("memories", []).size()
		check(s.cust_rel[k].get("memories", []).size() <= St.CAP_CREL_MEMORY, "customer shared memories capped")
	check(crm >= 1, "customers remember evenings together (%d)" % crm)
	check(s.pending_events.size() <= 6, "no runaway events (%d)" % s.pending_events.size())
	var ids := {}
	var mdup := false
	for mo in s.moments:
		var k2 := "%d:%s" % [mo.day, mo.id]
		if ids.has(k2):
			mdup = true
		ids[k2] = true
	check(not mdup, "no moment twice on the same day")
	var txt := St.serialize(s)
	check(St.serialize(St.deserialize(txt)) == txt, "60-day save round-trips")
	print("    staff %s | album %d | promises kept %d | arc stages %d | customer lives %d | talks %d" % [", ".join(s.staff), s.album.size(), kept, arcs, lives, a.talks])
