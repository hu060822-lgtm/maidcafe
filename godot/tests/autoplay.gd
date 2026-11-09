## A simple scripted "player" used by the multi-day tests. It plays the whole daily loop:
## explore -> prepare -> (morning offhours) -> business -> night (settle, events, concerns) -> next day.
extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")
const World = preload("res://scripts/core/world.gd")
const Biz = preload("res://scripts/core/business.gd")
const Settle = preload("res://scripts/core/settlement.gd")
const Events = preload("res://scripts/core/events.gd")
const Social = preload("res://scripts/core/social.gd")
const Life = preload("res://scripts/core/life.gd")

var s: Dictionary
var log: Array = []
var problems: Array = []
var day_reports: Array = []
var max_job_age := 0.0
var max_party_t := 0.0
var commands := true
var listen := true          # false = a player who never answers maids (autonomy test)
var keep_promises := true
var talks := 0

func _init(seed_value: int) -> void:
	s = St.new_game(seed_value)

func play_days(n: int) -> void:
	for i in n:
		play_day()

func play_day() -> void:
	var d := int(s.day)
	_explore()
	_prepare()
	_morning()
	var err := Settle.begin_business(s)
	if err != "":
		problems.append("D%d begin_business: %s" % [d, err])
		s.activity = "none"
		err = Settle.begin_business(s)
		if err != "":
			problems.append("D%d still cannot open: %s" % [d, err])
			return
	var biz = Biz.new(s, "business")
	var steps := 0
	var cmd_used := false
	while not biz.ended and steps < 4000:
		biz.update(0.25)
		steps += 1
		if steps % 4 == 0:
			for h in biz.health_check():
				problems.append("D%d t=%d %s" % [d, int(biz.t), h])
			for j in biz.jobs:
				if not j.done and not j.cancelled:
					max_job_age = maxf(max_job_age, biz.t - float(j.created))
			for p in biz.parties:
				max_party_t = maxf(max_party_t, p.t)
		# use a few management commands like a player would
		if commands and not cmd_used and biz.t > 90.0:
			cmd_used = true
			biz.order_boost("floor", 30.0)
			if biz.pending_counts().get("cook", 0) >= 3:
				for m in St.active_maids(s):
					if m.role == "floor":
						biz.set_role(m.id, "support")
						break
	if not biz.ended:
		problems.append("D%d business never ended" % d)
	var rep := Settle.settle(s, biz)
	day_reports.append(rep)
	log.append("D%d %s rev=%d served=%d lost=%d sat=%d pop=%d rep=%d money=%d moments=%d" % [d, s.weather, int(rep.revenue), rep.served, rep.lost, rep.avg_sat, int(s.popularity), int(s.reputation), int(s.money), rep.moments.size()])
	# night: events and concerns
	var guard := 0
	while guard < 10:
		guard += 1
		var ev := Events.next_event(s)
		if ev.is_empty():
			break
		var res := Events.resolve(s, ev.id, (d + guard) % ev.choices.size())
		log.append("  event %s -> %s" % [ev.title, res])
	if listen:
		_listen()
	for m in St.active_maids(s):
		if listen and not m.concern.is_empty() and int(m.concern.get("age", 0)) >= 1:
			var opts := Social.options(s, m.id)
			var pick: Dictionary = opts[d % opts.size()]
			log.append("  concern %s %s -> %s: %s" % [m.id, m.concern.type, pick.id, Social.resolve(s, m.id, pick.id)])
	# after-hours scene
	var night = Biz.new(s, "offhours")
	for i in 240:
		night.update(0.25)
		if i % 20 == 0:
			for h in night.health_check():
				problems.append("D%d night %s" % [d, h])
	Settle.next_day(s)

func _explore() -> void:
	var d := int(s.day)
	var plan: Array = [["cafe", "grocer", "park", "plaza"], ["general", "sweets", "plaza", "cafe"], ["park", "general", "grocer", "plaza"]][d % 3]
	for loc in plan:
		if int(s.action_points) <= 0:
			break
		var opt := ""
		if loc == "cafe":
			var ms := St.active_maids(s)
			opt = ms[d % ms.size()].id
			for m in ms:
				if not m.concern.is_empty() and not m.concern.get("revealed", false):
					opt = m.id
		var enc := World.visit_location(s, loc, opt)
		for rid in enc.residents:
			var t := World.talk_resident(s, rid)
			if t.offer != "":
				var e := World.accept_offer(s, t.offer)
				log.append("  offer %s -> %s" % [t.offer, e if e != "" else "accepted"])
	if listen:
		_listen()
	for mid in Data.MAIDS:
		if s.flags.get("recruit_" + mid, false):
			if World.hire_maid(s, mid) == "":
				log.append("  hired %s" % mid)

func _prepare() -> void:
	var d := int(s.day)
	# menu: keep seasonal/signature dishes on when unlocked
	for id in s.unlocked_dishes:
		var dd: Dictionary = Data.DISHES[id]
		if (dd.get("signature", false) or dd.get("collab", false) or dd.get("season", "") == Data.season(d)) and not id in s.menu and World.dish_available(s, id):
			if s.menu.size() >= Data.MAX_MENU:
				s.menu.remove_at(0)
			World.toggle_menu(s, id)
	# stock: ~5 servings of every dish, summed over shared ingredients
	var want := {}
	for id in s.menu:
		for ing in Data.DISHES[id].ing:
			want[ing] = int(want.get(ing, 0)) + 5 * int(Data.DISHES[id].ing[ing])
	for ing in want:
		var need := int(want[ing]) - int(s.inventory.get(ing, 0))
		if need > 0 and World.ingredient_available(s, ing) and float(s.money) > 2000:
			World.buy_ingredient(s, ing, need)
	# furniture over time
	var wishlist := {3: ["bookshelf", 3, 9], 5: ["vase", 14, 9], 7: ["sofa_table", 15, 8], 9: ["stage", 3, 7], 11: ["display", 13, 9], 13: ["partition", 5, 8]}
	if wishlist.has(d):
		var w: Array = wishlist[d]
		var e := World.buy_furniture(s, w[0], w[1], w[2])
		log.append("  furniture %s -> %s" % [w[0], e if e != "" else "placed"])
	if d == 8 and float(s.money) > 4000:
		World.buy_upgrade(s, "second_stove")
	# activities
	s.music = ["none", "jazz", "classical", "pop"][d % 4]
	var bm := World.birthday_maid(s)
	for u in World.upcoming_special_days(s, 1):
		if u.kind == "birthday":
			World.prepare_special(s, "birthday_" + u.who, "cake")
			World.prepare_special(s, "birthday_" + u.who, "letter")
	if bm != "" and World.activity_requirement(s, "birthday") == "":
		World.set_activity(s, "birthday")
	elif d % 5 == 4 and World.activity_requirement(s, "limited") == "":
		World.set_activity(s, "limited", s.menu[0])
	elif d % 7 == 6 and World.activity_requirement(s, "meetup") == "":
		World.set_activity(s, "meetup")
	elif d % 6 == 3 and World.activity_requirement(s, "stage") == "":
		World.set_activity(s, "stage")
		for m in St.active_maids(s):
			if m.id == "koharu" and m.role != "off":
				m.role = "stage"
	elif World.activity_requirement(s, "seasonal") == "" and d % 4 == 1:
		World.set_activity(s, "seasonal")
	if keep_promises:
		_keep_promises()
	# give the most tired maid a day off now and then
	var tired = null
	for m in St.active_maids(s):
		if float(m.fatigue) >= 50 and (tired == null or float(m.fatigue) > float(tired.fatigue)):
			tired = m
	var working := 0
	for m in St.active_maids(s):
		if m.role != "off":
			working += 1
	if tired != null and working > 2 and tired.role != "stage":
		tired.role = "off"
	# a promised day off (checked after the tired one so the promise wins)
	for p in s.promises:
		if keep_promises and p.status == "open" and p.kind == "dayoff_on" and int(p.target) == d and _active(p.maid):
			s.maids[p.maid].role = "off"

func _morning() -> void:
	var mo = Biz.new(s, "offhours")
	for i in 120:
		mo.update(0.25)

func _active(mid: String) -> bool:
	return mid in s.staff and not s.maids[mid].quit

## A player who listens: promises when it is affordable, otherwise says "not yet".
func _listen() -> void:
	for m in St.active_maids(s):
		var tv := Life.talk_view(s, m.id)
		if tv.is_empty():
			continue
		var ids: Array = tv.options.map(func(o): return o.id)
		var pick: String = ids[0]
		if "promise" in ids:
			var req: Dictionary = m.want_talk.want
			var cost := 0.0
			if req.kind == "furniture":
				cost = float(Data.FURNITURE[req.type].price)
			elif req.kind == "upgrade":
				cost = float(Data.UPGRADES[req.id].price)
			pick = "promise" if float(s.money) - cost > 3000 else "later"
		talks += 1
		log.append("  talk %s %s -> %s: %s" % [m.id, m.want_talk.topic, pick, Life.talk_resolve(s, m.id, pick)])

## Do what was promised (buy, set music, menu, activity) when possible.
func _keep_promises() -> void:
	for p in s.promises:
		if p.status != "open" or int(s.day) < int(p.from):
			continue
		var dd: Dictionary = p.data
		match p.kind:
			"furniture":
				var have := 0
				for f in s.furniture:
					if f.type == dd.type:
						have += 1
				while have < int(dd.get("count", 1)) and _place(dd.type):
					have += 1
			"upgrade":
				World.buy_upgrade(s, dd.id)
			"music":
				s.music = String(dd.get("key", "")).split(":")[-1]
			"dish":
				if not dd.dish in s.menu and World.dish_available(s, dd.dish):
					if s.menu.size() >= Data.MAX_MENU:
						s.menu.remove_at(0)
					World.toggle_menu(s, dd.dish)
			"activity":
				if s.activity == "none" and World.activity_requirement(s, dd.act) == "":
					World.set_activity(s, dd.act)
			"decor":
				World.set_decor(s)

func _place(type: String) -> bool:
	for c in [[3, 9], [14, 9], [13, 9], [1, 8], [16, 6], [1, 6], [16, 4], [13, 5], [3, 7], [1, 3], [8, 2]]:
		if World.buy_furniture(s, type, c[0], c[1]) == "":
			log.append("  promise furniture %s placed at %d,%d" % [type, c[0], c[1]])
			return true
	return false
