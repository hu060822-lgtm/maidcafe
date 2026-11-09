## After hours: settlement, memory tiers, habits & relationships, customer social network,
## word of mouth, concerns, night events, and the transition to the next day.
##
## Memory tiers:
##   short  = the business sim itself (thrown away after the shift)
##   medium = customer.recent (last CAP_RECENT_VISITS visits), maid.yesterday, rel.shared (last few)
##   long   = aggregates with fixed size (weekday_counts, dish_counts, seat_counts, habits, relation dims) + milestone logs (capped)
extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")
const World = preload("res://scripts/core/world.gd")
const Social = preload("res://scripts/core/social.gd")
const Events = preload("res://scripts/core/events.gd")
const Moments = preload("res://scripts/core/moments.gd")
const Layout = preload("res://scripts/core/layout.gd")
const Life = preload("res://scripts/core/life.gd")

const CAUSE_TEXT := {
	"longWaitDoor": "在門口等了好久", "longWaitOrder": "一直沒人來點餐", "longWaitFood": "餐點等太久",
	"greatFood": "餐點非常好吃", "badFood": "餐點不太好吃", "favDish": "吃到了喜歡的料理", "favMaid": "見到了喜歡的女僕",
	"favMaidAbsent": "喜歡的女僕不在", "noisy": "太吵了", "enjoyedShow": "表演很精彩", "spill": "有餐點被打翻",
	"complaintHandled": "客訴被好好處理了", "complaintIgnored": "客訴沒人理", "outOfStock": "想吃的賣完了",
	"styleMatch": "很喜歡店裡的風格", "managerChat": "和店長聊得很開心", "favSeat": "坐到了老位子", "walkedOut": "受不了就走了",
	"wrongOrder": "送錯了餐", "seatChanged": "幫忙換了座位", "seatTaken": "老位子被坐走了", "seatUnhappy": "不喜歡這個位子",
	"hot": "店裡好熱", "likedMusic": "喜歡店裡的音樂", "maidChat": "和女僕聊了幾句", "bookshelf": "坐在書架旁很自在",
	"boughtGoods": "買了展示櫃的商品", "posted": "拍了照上傳", "remembered": "店員記得他的習慣",
}
const GOOD := ["greatFood", "favDish", "favMaid", "enjoyedShow", "complaintHandled", "styleMatch", "managerChat", "favSeat",
	"seatChanged", "likedMusic", "maidChat", "bookshelf", "boughtGoods", "posted", "remembered"]

static func review_text(r: Dictionary) -> String:
	var good := []
	var bad := []
	for c in r.causes:
		if not CAUSE_TEXT.has(c):
			continue
		if c in GOOD:
			good.append(CAUSE_TEXT[c])
		else:
			bad.append(CAUSE_TEXT[c])
	var parts := []
	if not good.is_empty():
		parts.append("、".join(good))
	if not bad.is_empty():
		parts.append("可惜" + "、".join(bad))
	var sat := float(r.sat)
	var head := "★★★★★" if sat >= 75 else ("★★★★☆" if sat >= 60 else ("★★★☆☆" if sat >= 45 else ("★★☆☆☆" if sat >= 30 else "★☆☆☆☆")))
	return "%s %s" % [head, "，".join(parts) if not parts.is_empty() else "普通的一餐。"]

# ---------------------------------------------------------------- begin business
static func begin_business(s: Dictionary) -> String:
	var menu := []
	for id in s.menu:
		if id in s.unlocked_dishes:
			menu.append(id)
	if menu.is_empty():
		return "菜單上至少要有一道料理。"
	var working := 0
	for m in St.active_maids(s):
		if m.role != "off":
			working += 1
	if working == 0:
		return "至少要有一位女僕上班。"
	if s.activity != "none":
		var err := World.activity_requirement(s, s.activity)
		if err != "":
			return err
	if s.activity in ["stage", "street_music", "birthday"]:
		var has_perf := false
		for m in St.active_maids(s):
			if m.role == "stage":
				has_perf = true
		if not has_perf and s.activity == "stage":
			return "舞台表演日請指派一位女僕擔任「舞台」。"
	else:
		for m in St.active_maids(s):
			if m.role == "stage":
				m.role = Data.MAIDS[m.id].default_role
	if s.activity == "limited" and s.featured_dish == "":
		return "請選擇今天的限定料理。"
	var cost := float(Data.ACTIVITIES[s.activity].cost)
	s.money = float(s.money) - cost
	s.today_spend.activity = float(s.today_spend.activity) + cost
	if s.activity == "costume":
		for m in St.active_maids(s):
			var tr: Array = Data.MAIDS[m.id].traits
			m.mood = St.clampf100(float(m.mood) + (15 if "lively" in tr else (-3 if "shy" in tr else 6)))
	s.phase = "business"
	# maids given the day off this morning still go out and live their day
	Life.plan_offdays(s)
	return ""

# ---------------------------------------------------------------- settlement
static func settle(s: Dictionary, biz) -> Dictionary:
	var working := []
	for m in St.active_maids(s):
		if m.role != "off":
			working.append(m)
	var wages := working.size() * Data.WAGE_PER_SHIFT
	s.money = float(s.money) - wages - Data.MAINTENANCE - Data.UTILITIES - Data.RENT
	var results: Array = biz.results
	var avg_sat := 0.0
	for r in results:
		avg_sat += float(r.sat)
	avg_sat = avg_sat / results.size() if not results.is_empty() else 0.0
	var reviews := []
	var advice := []
	var maid_notes := []
	var new_fans := []
	var social_notes := []
	var wd := Data.weekday(int(s.day))
	var came := {}

	# ---------------- customers: memory & habits
	for r in results:
		var cid: String = r.def
		if cid == "" or not s.customers.has(cid):
			continue
		came[cid] = true
		var def: Dictionary = Data.CUSTOMERS[cid]
		var mem: Dictionary = s.customers[cid]
		var first: bool = int(mem.visits) == 0
		mem.visits = int(mem.visits) + 1
		if first:
			mem.first_day = int(s.day)
		mem.last_day = int(s.day)
		mem.last_sat = roundf(float(r.sat))
		mem.last_causes = r.causes
		mem.missed_habit_days = 0
		s.flags.erase("invite_" + cid)
		# medium-term: recent visits
		var main_dish: String = r.items[0] if not r.items.is_empty() else ""
		mem.recent.append({"day": int(s.day), "sat": roundf(float(r.sat)), "maid": r.served_by[0] if not r.served_by.is_empty() else "", "dish": main_dish, "seat": r.table, "weekday": wd})
		while mem.recent.size() > St.CAP_RECENT_VISITS:
			mem.recent.pop_front()
		# long-term aggregates (learned habits)
		mem.weekday_counts[wd] = int(mem.weekday_counts[wd]) + 1
		for it in r.items:
			mem.dish_counts[it] = int(mem.dish_counts.get(it, 0)) + 1
		if r.table != "":
			mem.seat_counts[r.table] = int(mem.seat_counts.get(r.table, 0)) + (2 if float(r.sat) >= 65 else 1)
		var dl := (float(r.sat) - 50.0) * 0.4 + 3.0
		if "walkedOut" in r.causes or "complaintIgnored" in r.causes:
			dl -= 10.0
		if "complaintHandled" in r.causes:
			dl += 2.0
		mem.loyalty = St.clampf100(float(mem.loyalty) + dl)
		for mid in r.affinity:
			var g := float(r.affinity[mid])
			if Data.MAIDS.has(mid) and "slow_warm" in Data.MAIDS[mid].traits:
				g *= 0.6 if int(mem.visits) < 4 else 1.4
			mem.affinity[mid] = float(mem.affinity.get(mid, 0.0)) + g
		# favourites derived from the aggregates
		var fav := ""
		var fv := 12.0
		for mid in mem.affinity:
			if float(mem.affinity[mid]) > fv:
				fv = float(mem.affinity[mid])
				fav = mid
		if fav != "" and fav != mem.fav_maid:
			mem.fav_maid = fav
			St.cust_log(mem, int(s.day), "開始指名%s" % Data.MAIDS[fav].name)
			new_fans.append({"maid": fav, "cust": cid})
			s.maid_fame[fav] = float(s.maid_fame.get(fav, 0.0)) + 3.0
		var best_seat := ""
		var bs := 2
		for k in mem.seat_counts:
			if int(mem.seat_counts[k]) > bs:
				bs = int(mem.seat_counts[k])
				best_seat = k
		if best_seat != "" and best_seat != mem.fav_seat and s.flags.get("reserved_seat_" + cid, "") == "":
			mem.fav_seat = best_seat
			if int(mem.visits) >= 3:
				St.cust_log(mem, int(s.day), "習慣坐同一個位子")
		var best_dish := ""
		var bd := 1
		for k in mem.dish_counts:
			if int(mem.dish_counts[k]) > bd and (k in def.likes or int(mem.dish_counts[k]) >= 3):
				bd = int(mem.dish_counts[k])
				best_dish = k
		if best_dish != "":
			mem.fav_dish = best_dish
		if first:
			St.cust_log(mem, int(s.day), "第一次來店（滿意度 %d）" % int(r.sat))
		if "complaintIgnored" in r.causes:
			St.cust_log(mem, int(s.day), "客訴沒有被處理，生氣地離開")
		if "walkedOut" in r.causes:
			St.cust_log(mem, int(s.day), "等太久而離開")
		if not mem.is_regular and int(mem.visits) >= Data.REGULAR_VISITS and float(mem.loyalty) >= Data.REGULAR_LOYALTY:
			mem.is_regular = true
			St.cust_log(mem, int(s.day), "成為熟客")
			s.flags["regular_count"] = int(s.flags.get("regular_count", 0)) + 1
			# the album keeps the first regulars and the special guests; everyone else lives in the notebook
			if int(s.flags.regular_count) <= 3 or def.kind == "special":
				St.add_album(s, "%s成為熟客" % def.name, "第 %d 次來店時，%s說：「這裡已經是我的老地方了。」" % [int(mem.visits), def.name], [cid])
		reviews.append({"customer": def.name, "id": cid, "sat": int(roundf(float(r.sat))), "text": review_text(r), "reasons": r.reasons})
		# word of mouth: a photo post
		if "posted" in r.causes and cid == "nanami" and main_dish != "" and not s.flags.get("nanami_post_" + main_dish, false):
			s.flags["nanami_post_" + main_dish] = true
			Events.queue(s, "nanami_post:" + main_dish)
		match def.get("story", ""):
			"pudding":
				_story_pudding(s, r)
			"novel":
				_story_novel(s, r)
		# a referral became a known customer
		if not mem.known:
			mem.known = true
	for r in results:
		var fo: String = r.get("friend_of", "")
		if fo != "" and s.customers.has(fo):
			var mem: Dictionary = s.customers[fo]
			if not mem.brought_friend:
				mem.brought_friend = true
				St.cust_log(mem, int(s.day), "第一次帶朋友來")
				var def: Dictionary = Data.CUSTOMERS[fo]
				if not s.flags.get("first_friend", false):
					s.flags["first_friend"] = true
					St.add_album(s, "%s帶朋友來了" % def.name, "%s帶著朋友推開店門：「就是這裡，我跟你說過的那間店！」" % def.name, [fo])
	# missed routines (visit habits)
	for cid in s.customers:
		var mem: Dictionary = s.customers[cid]
		if not mem.known or came.has(cid) or not mem.is_regular:
			continue
		var days: Array = Data.CUSTOMERS[cid].weekdays
		if wd in days:
			mem.missed_habit_days = int(mem.missed_habit_days) + 1
			if int(mem.missed_habit_days) >= 3:
				mem.loyalty = St.clampf100(float(mem.loyalty) - 3)
	var anon := []
	for r in results:
		if r.def == "" and r.get("friend_of", "") == "":
			anon.append(r)
	if not anon.is_empty():
		var a := 0.0
		for r in anon:
			a += float(r.sat)
		a /= anon.size()
		reviews.append({"customer": "其他客人（%d 位）" % anon.size(), "id": "", "sat": int(roundf(a)), "text": "網路上出現了幾則好評。" if a >= 60 else "網路評價普普通通。", "reasons": []})

	# ---------------- customer social network
	var new_acq := 0
	for k in biz.co_present:
		var secs := float(biz.co_present[k])
		# only a real shared evening counts: long co-presence, or a meetup where people mingle
		if secs < (32.0 if s.activity == "meetup" else 56.0):
			continue
		var p: PackedStringArray = k.split("|")
		if not s.cust_rel.has(k):
			s.cust_rel[k] = {"type": "", "strength": 0.0, "co_visits": 0}
		var rel: Dictionary = s.cust_rel[k]
		rel.co_visits = int(rel.co_visits) + 1
		rel.strength = minf(100.0, float(rel.strength) + 6.0)
		var new_ok: bool = new_acq < 1 and (s.customers[p[0]].is_regular or s.customers[p[1]].is_regular) \
			and _acq_count(s, p[0]) == 0 and _acq_count(s, p[1]) == 0
		if rel.type == "" and new_ok and int(rel.co_visits) >= 4 and _compatible(p[0], p[1]):
			new_acq += 1
			rel.type = "acquaintance"
			rel.strength = maxf(float(rel.strength), 50.0)
			St.cust_log(s.customers[p[0]], int(s.day), "在店裡認識了%s" % Data.CUSTOMERS[p[1]].name)
			St.cust_log(s.customers[p[1]], int(s.day), "在店裡認識了%s" % Data.CUSTOMERS[p[0]].name)
			Events.queue(s, "acquaintance:" + k)
			social_notes.append("👋 %s和%s在店裡變熟了。" % [Data.CUSTOMERS[p[0]].name, Data.CUSTOMERS[p[1]].name])
	for k in s.cust_rel:
		var rel: Dictionary = s.cust_rel[k]
		if rel.type != "" and not biz.co_present.has(k):
			rel.strength = maxf(20.0, float(rel.strength) - 0.5)

	# ---------------- popularity & word of mouth
	var served := 0
	for r in results:
		if float(r.paid) > 0:
			served += 1
	var pop: float = (avg_sat - 55.0) / 6.0 + served / 12.0 - minf(6.0, biz.lost * 0.5)
	if s.activity != "none":
		pop += 1.0
	var stage_perf := 0.0
	for mid in biz.maid_stats:
		stage_perf += float(biz.maid_stats[mid].perform)
	if s.activity in ["stage", "street_music"] and stage_perf > 60:
		pop += 3.0
	if s.street.get("event", "") == "new_shop":
		pop -= 2.0
	var pop_i := int(roundf(pop))
	# popularity fades unless the cafe keeps giving people a reason to talk about it
	s.popularity = St.clampf100(float(s.popularity) * 0.95 + pop_i)
	if not results.is_empty():
		s.reputation = St.clampf100(float(s.reputation) + (avg_sat - 60.0) * 0.12)
	s.reputation = float(s.reputation) + (50.0 - float(s.reputation)) * 0.03
	for d in s.dish_buzz.keys():
		s.dish_buzz[d] = float(s.dish_buzz[d]) * 0.8
		if float(s.dish_buzz[d]) < 0.5:
			s.dish_buzz.erase(d)
	for mid in s.maid_fame.keys():
		s.maid_fame[mid] = float(s.maid_fame[mid]) * 0.96

	# ---------------- maids: condition, habits, relationships
	var working_ids := []
	for m in working:
		working_ids.append(m.id)
	for m in St.active_maids(s):
		var def: Dictionary = Data.MAIDS[m.id]
		var st: Dictionary = biz.maid_stats.get(m.id, {})
		m.yesterday = []
		m.flags.erase("off_today")
		if m.role == "off":
			m.fatigue = St.clampf100(float(m.fatigue) - 50)
			m.mood = St.clampf100(float(m.mood) + 10)
			m.yesterday.append("dayoff")
			m.flags["tired_nights"] = 0
		else:
			m.days_worked = int(m.days_worked) + 1
			if float(m.fatigue) >= 75:
				m.yesterday.append("overworked")
				m.mood = St.clampf100(float(m.mood) - 5)
			if float(m.fatigue) >= 55:
				m.flags["tired_nights"] = int(m.flags.get("tired_nights", 0)) + 1
			else:
				m.flags["tired_nights"] = 0
			if int(st.get("happy", 0)) >= 2:
				m.yesterday.append("praised")
			if int(st.get("spills", 0)) >= 1:
				m.yesterday.append("spill")
			if int(st.get("complaints", 0)) >= 1:
				m.yesterday.append("complaint")
			m.fatigue = St.clampf100(float(m.fatigue) - (40 if s.upgrades.sofa else 30))
		# mood settles toward a baseline that depends on how much she trusts the manager (bond)
		m.mood = St.clampf100(float(m.mood) + (52.0 + float(m.bond) * 0.16 - float(m.mood)) * 0.15)
		# habits fade slowly toward their seed when not practised; reinforced ones stay
		for h in m.habits:
			var seed := float(def.get("seed_habits", {}).get(h, 0))
			var v := float(m.habits[h])
			if v > seed:
				m.habits[h] = maxf(seed, v - 0.8)
			if v >= 50 and not m.flags.get("habit_" + h, false):
				m.flags["habit_" + h] = true
				Moments.record(s, "habit_%s_%s" % [m.id, h], "%s好像養成了「%s」的習慣。%s" % [def.name, Data.HABITS[h].name, Data.HABITS[h].desc], [m.id])
				social_notes.append("🔁 %s養成了習慣：%s" % [def.name, Data.HABITS[h].name])
		if int(m.flags.get("separate_days", 0)) > 0:
			m.flags.separate_days = int(m.flags.separate_days) - 1
			if int(m.flags.separate_days) <= 0:
				m.flags.erase("separate_from")
		if float(m.mood) < 25:
			m.low_mood_nights = int(m.low_mood_nights) + 1
		else:
			m.low_mood_nights = 0
		# a maid who trusts the manager holds on one night longer
		if int(m.low_mood_nights) >= (4 if float(m.bond) >= 65 else 3):
			m.quit = true
			s.staff.erase(m.id)
			St.add_album(s, "%s離開了" % def.name, "%s留下一封信：「對不起，我已經撐不下去了。」也許我太在意營業額了。" % def.name, [m.id])
			maid_notes.append({"id": m.id, "text": "%s辭職了……" % def.name})
			continue
		if int(m.low_mood_nights) == 2:
			Events.queue(s, "quit_warning:" + m.id)
			maid_notes.append({"id": m.id, "text": "⚠ %s的心情連續兩天很差，再這樣下去她可能會辭職。" % def.name})
		if not st.is_empty() and m.role != "off":
			var bits := []
			if int(st.greets) > 0:
				bits.append("帶位 %d" % int(st.greets))
			if int(st.cooks) > 0:
				bits.append("製作 %d" % int(st.cooks))
			if int(st.delivers) > 0:
				bits.append("送餐 %d" % int(st.delivers))
			if int(st.helped) > 0:
				bits.append("補位 %d" % int(st.helped))
			if int(st.spills) + int(st.wrong) > 0:
				bits.append("失誤 %d" % (int(st.spills) + int(st.wrong)))
			if float(st.perform) > 0:
				bits.append("表演 %d 秒" % int(st.perform))
			if int(st.regular_talks) > 0:
				bits.append("和熟客聊天 %d" % int(st.regular_talks))
			maid_notes.append({"id": m.id, "text": "%s：%s。心情 %d／疲勞 %d" % [def.name, "、".join(bits) if not bits.is_empty() else "今天沒什麼工作", int(m.mood), int(m.fatigue)]})
		# personal story events from what happened today
		if m.id == "koharu" and not m.flags.get("fan_event", false):
			for f in new_fans:
				if f.maid == "koharu":
					Events.queue(s, "koharu_fan")
		if m.id == "rin" and "overworked" in m.yesterday and not m.flags.get("overwork_event", false):
			Events.queue(s, "rin_overwork")
		if m.id == "shizuku" and int(st.get("solo", 0)) > 0 and not m.flags.get("solo_event", false):
			Events.queue(s, "shizuku_solo")
		if m.id == "shizuku" and float(st.get("perform", 0.0)) > 40 and not m.flags.get("stage_event", false):
			Events.queue(s, "shizuku_stage")
		if m.id == "shizuku" and int(st.get("spills", 0)) > 0 and not m.flags.get("spill_event", false) and not "shizuku_solo" in s.pending_events:
			Events.queue(s, "shizuku_spill")
	_relationships(s, biz, working_ids, social_notes)
	# ---------------- Living Hearts: personal lives (likes, days off, promises, pair events, customers' lives)
	var lctx := Life.make_ctx(s, served, World.dominant_style(s).key, working_ids)
	for t in Life.day_feelings(s, lctx):
		social_notes.append("💗 " + t)
	Life.offday_settle(s, social_notes)
	Life.check_promises(s, lctx, social_notes)
	Life.pair_events(s, working_ids, biz.helps)
	Life.customer_visit_events(s, results)
	Life.customers_daily(s, results, biz.co_present, social_notes)
	if _active(s, "koharu") and _active(s, "rin") and float(St.rel(s, "koharu", "rin").close) >= 50 and not s.flags.get("rin_teaches", false) and int(s.day) >= 3:
		Events.queue(s, "rin_teaches")
	if _active(s, "yukino") and came.has("shiraishi") and not s.flags.get("yukino_reader", false):
		Events.queue(s, "yukino_reader")
	# special days
	var bm := World.birthday_maid(s)
	if bm != "" and not s.flags.get("birthday_done_%s_%d" % [bm, int((int(s.day) - 1) / Data.YEAR_DAYS)], false):
		Events.queue(s, "birthday:" + bm)
	if int(s.day) % Data.YEAR_DAYS == 0:
		Events.queue(s, "anniversary")

	# ---------------- concerns, moments
	var crng := RandomNumberGenerator.new()
	crng.seed = int(s.seed) * 31 + int(s.day) * 101
	for t in Social.daily(s, biz.maid_stats, crng):
		social_notes.append("💭 " + t)
	Life.daily(s, crng, social_notes)
	var closing_moments: Array = Moments.closing(s, biz)

	# ---------------- advice (staff suggestions & flow analysis)
	var lay = Layout.new(s.furniture, s.upgrades)
	var flow: Dictionary = lay.flow_metrics()
	var hot := _hot_cells(biz.heat)
	if biz.congestion > 25:
		var where := ""
		if not hot.is_empty():
			where = "（最常卡住的地方：%s）" % "、".join(hot.slice(0, 2).map(func(h): return "(%d,%d)" % [h.x, h.z]))
		advice.append("雫：「走道有點擠……大家常常互相卡住。」今天塞住 %d 秒%s。" % [int(biz.congestion), where])
	if biz.lost >= 2:
		advice.append("小春：「有 %d 位客人沒吃到東西就走了……要不要多擺幾張桌子，或多一個人負責接待？」" % biz.lost)
	if biz.turned_away > 0:
		advice.append("暫停接客時，有 %d 位客人在門口折返。" % biz.turned_away)
	if biz.complaints > biz.complaints_handled:
		advice.append("凜：「客訴要快點處理。店長或管理能力高的人才能安撫客人。」")
	var low := []
	for id in s.menu:
		if World.servings(s.inventory, id) < 2:
			low.append(Data.DISHES[id].name)
	if not low.is_empty():
		advice.append("凜：「%s的材料快用完了，明天記得去採購。」" % "、".join(low.slice(0, 4)))
	var has_green := false
	for f in s.furniture:
		if f.type in ["plant", "vase"]:
			has_green = true
	if not has_green:
		advice.append("雫：「店裡……好像少了點綠色。」")
	var cooks := 0
	for mid in biz.maid_stats:
		cooks += int(biz.maid_stats[mid].cooks)
	if not s.upgrades.second_stove and cooks >= 8:
		advice.append("凜：「一台爐子根本不夠用。第二台爐具可以讓出餐快很多。」")
	if float(flow.kitchen_max) >= 16:
		advice.append("📐 動線：最遠的桌子離出餐口要走 %d 步，送餐會比較慢。" % int(flow.kitchen_max))
	for m in working:
		if float(m.fatigue) >= 60:
			advice.append("%s的疲勞偏高，明天容易失誤，考慮讓她休假吧。" % Data.MAIDS[m.id].name)
			break
	if biz.incidents.has("aircon"):
		advice.append("夏天的老冷氣很容易壞，考慮換一台新冷氣。")
	if advice.is_empty():
		advice.append("今天運作得很順利！")

	# ---------------- activity counters & albums
	if s.activity == "costume":
		s.flags["costume_days"] = int(s.flags.get("costume_days", 0)) + 1
	if s.activity == "stage":
		s.flags["stage_days"] = int(s.flags.get("stage_days", 0)) + 1
	if s.activity == "stage" and stage_perf > 60:
		St.add_album(s, "第一次舞台表演", "小小的舞台上響起了歌聲，客人們跟著打拍子。那天的人氣上升了 %d。" % pop_i, [], "pending")
	if s.activity == "street_music":
		St.add_album(s, "街頭音樂之夜", "奏的吉他聲從店裡傳到了街上。路過的人停下腳步，有人跟著哼了起來。", [], "pending")
	if s.activity == "craft_fair":
		St.add_album(s, "手作小市集", "月見小姐的手作雜貨擺滿了展示櫃。小春買了一個兔子吊飾。", [], "pending")
	if biz.revenue >= 15000:
		St.add_album(s, "大豐收的一天", "第 %d 天的營業額突破 ¥15,000！大家累得說不出話，卻都在笑。" % int(s.day))

	var exp := {
		"ingredients": float(s.today_spend.ingredients), "wages": wages, "maintenance": Data.MAINTENANCE, "utilities": Data.UTILITIES, "rent": Data.RENT,
		"activity": float(s.today_spend.activity), "promotion": float(s.today_spend.promotion), "furniture": float(s.today_spend.furniture),
	}
	var total_exp := 0.0
	for k in exp:
		total_exp += float(exp[k])
	var report := {
		"day": int(s.day), "date": Data.date_label(int(s.day)), "revenue": biz.revenue, "goods": biz.goods_revenue, "expenses": exp, "total_expenses": total_exp,
		"served": served, "lost": biz.lost, "complaints": biz.complaints, "complaints_handled": biz.complaints_handled,
		"avg_sat": int(roundf(avg_sat)), "congestion": int(biz.congestion), "pop_delta": pop_i, "reputation": int(s.reputation),
		"reviews": reviews, "advice": advice, "maid_notes": maid_notes, "social": social_notes,
		"moments": closing_moments.map(func(x): return x.text), "incidents": biz.incidents.duplicate(), "flow": flow, "hot": hot.slice(0, 5), "heat_map": biz.heat.duplicate(),
		"style": World.dominant_style(s).name,
	}
	s.last_report = report
	s.history.append({"day": int(s.day), "revenue": biz.revenue, "net": biz.revenue - total_exp, "sat": int(roundf(avg_sat)), "popularity": float(s.popularity), "reputation": float(s.reputation)})
	while s.history.size() > St.CAP_HISTORY:
		s.history.pop_front()
	s.phase = "night"
	return report

## Two customers can become acquaintances only if they would plausibly talk (shared taste or temperament).
static func _compatible(a: String, b: String) -> bool:
	var da: Dictionary = Data.CUSTOMERS[a]
	var db: Dictionary = Data.CUSTOMERS[b]
	if da.get("companion", "") == b:
		return false
	for d in da.likes:
		if d in db.likes:
			return true
	return da.pref == db.pref or (da.quiet and db.quiet) or (da.style != "" and da.style == db.style)

static func _acq_count(s: Dictionary, cid: String) -> int:
	var n := 0
	for k in s.cust_rel:
		if s.cust_rel[k].type == "acquaintance" and cid in String(k).split("|"):
			n += 1
	return n

static func _active(s: Dictionary, id: String) -> bool:
	return id in s.staff and not s.maids[id].quit

static func _hot_cells(heat: Dictionary) -> Array:
	var arr := []
	for k in heat:
		var p: PackedStringArray = String(k).split(",")
		arr.append({"x": int(p[0]), "z": int(p[1]), "v": float(heat[k])})
	arr.sort_custom(func(a, b): return a.v > b.v)
	return arr

## Relationship changes come from shared work, not from a timer.
static func _relationships(s: Dictionary, biz, working_ids: Array, notes: Array) -> void:
	# handoffs (cook -> deliver, greet -> order ...) build synergy
	for k in biz.handoffs:
		var p: PackedStringArray = k.split("|")
		if not _active(s, p[0]) or not _active(s, p[1]):
			continue
		var n := int(biz.handoffs[k])
		St.rel_change(s, p[0], p[1], "synergy", minf(6.0, n * 0.6), "今天交接了 %d 次" % n)
		if n >= 5:
			St.rel_share(s, p[0], p[1], "一起撐過了忙碌的晚上（交接 %d 次）" % n)
	# helping builds trust (and closeness)
	var counted := {}
	for h in biz.helps:
		if not _active(s, h.helper) or not _active(s, h.helped):
			continue
		var k: String = h.helper + ">" + h.helped
		counted[k] = int(counted.get(k, 0)) + 1
	for k in counted:
		var p: PackedStringArray = k.split(">")
		# the one who was helped trusts the helper more; the helper only grows a little closer
		St.rel_change(s, p[1], p[0], "trust", minf(8.0, 2.5 * counted[k]), "忙不過來時%s來幫忙" % Data.MAIDS[p[0]].name, false)
		St.rel_change(s, p[0], p[1], "close", 1.0, "去幫%s的忙" % Data.MAIDS[p[1]].name, false)
		St.rel_change(s, p[1], p[0], "close", 2.0, "被%s幫忙" % Data.MAIDS[p[0]].name, false)
		s.maids[p[0]].habits["help"] = minf(100.0, float(s.maids[p[0]].habits.help) + 1.5 * counted[k])
		if counted[k] >= 2:
			St.rel_share(s, p[0], p[1], "忙到不行的時候，%s過來幫忙" % Data.MAIDS[p[0]].name)
	# an impatient maid gets annoyed by a much slower colleague; overloaded maids resent idle ones
	for a in working_ids:
		for b in working_ids:
			if a >= b:
				continue
			var sa: Dictionary = biz.maid_stats.get(a, {})
			var sb: Dictionary = biz.maid_stats.get(b, {})
			if sa.is_empty() or sb.is_empty():
				continue
			var ta := float(sa.tasks)
			var tb := float(sb.tasks)
			for pair in [[a, b, ta, tb], [b, a, tb, ta]]:
				var x: String = pair[0]
				var y: String = pair[1]
				if pair[2] > 6.0 and pair[2] > pair[3] * 2.2:
					var amt := 4.0 if "impatient" in Data.MAIDS[x].traits else 2.0
					# only the overloaded one resents it; the other may not even notice
					St.rel_change(s, x, y, "friction", amt, "%s覺得工作都落在自己身上" % Data.MAIDS[x].name, false)
					if "impatient" in Data.MAIDS[x].traits and x == "kaede" and float(St.rel(s, x, y).friction) >= 25 and not s.flags.get("kaede_impatient", false):
						Events.queue(s, "kaede_impatient:" + y)
			St.rel_change(s, a, b, "close", 0.6, "同一天上班")
	# mistakes on handoffs (wrong orders) strain trust a bit; friction fades with time
	# friction fades with time (faster when she trusts the other one); closeness needs upkeep
	for k in s.maid_rel:
		var r: Dictionary = s.maid_rel[k]
		r.friction = maxf(0.0, float(r.friction) - (2.5 if float(r.trust) >= 55 else 1.5))
		r.close = maxf(0.0, float(r.close) - 0.2)

static func _story_pudding(s: Dictionary, r: Dictionary) -> void:
	var mem: Dictionary = s.customers.chizuru
	var had: bool = "s_pudding" in r.items
	var had_sig: bool = "sig_pudding" in r.items
	if int(mem.story_stage) == 1 and had:
		if float(r.quality) >= 58:
			mem.story_stage = 2
			Events.queue(s, "chizuru_recipe")
		else:
			St.cust_log(mem, int(s.day), "覺得布丁「火候還差一點」")
	elif int(mem.story_stage) == 1:
		St.cust_log(mem, int(s.day), "沒吃到布丁，有點失望")
	if int(mem.story_stage) == 3 and had_sig and float(r.sat) >= 65:
		mem.story_stage = 4
		Events.queue(s, "chizuru_proud")

static func _story_novel(s: Dictionary, r: Dictionary) -> void:
	var mem: Dictionary = s.customers.amamiya
	if "noisy" in r.causes:
		mem.story_stage = maxi(0, int(mem.story_stage) - 1)
		St.cust_log(mem, int(s.day), "太吵了，沒辦法寫稿")
		return
	if float(r.sat) >= 62:
		mem.story_stage = int(mem.story_stage) + 1
		if int(mem.story_stage) == 2:
			Events.queue(s, "amamiya_secret")
		if int(mem.story_stage) == 4:
			Events.queue(s, "amamiya_book")

# ---------------------------------------------------------------- next day
static func next_day(s: Dictionary) -> void:
	s.day = int(s.day) + 1
	s.phase = "explore"
	s.action_points = Data.DAY_ACTION_POINTS
	s.activity = "none"
	s.featured_dish = ""
	s.today_spend = {"ingredients": 0.0, "activity": 0.0, "promotion": 0.0, "furniture": 0.0}
	s.flags["flyers_today"] = 0
	s.flags["poster_today"] = false
	s.new_dishes = []
	var rng := St.make_rng(s)
	s.weather = World.roll_weather(s, rng)
	# the street event was decided last night (so residents could hint at it)
	s.street["event"] = s.street.get("next_event", "")
	s.day = int(s.day) + 1
	s.street["next_event"] = World.roll_street_event(s, rng)
	s.day = int(s.day) - 1
	St.store_rng(s, rng)
	# seasonal dishes leave the menu when their season ends; new season unlocks
	var season := Data.season(int(s.day))
	for id in Data.DISHES:
		var d: Dictionary = Data.DISHES[id]
		if d.has("season"):
			if d.season == season and not id in s.unlocked_dishes:
				s.unlocked_dishes.append(id)
			elif d.season != season:
				s.menu.erase(id)
	for id in s.menu.duplicate():
		if not World.dish_available(s, id):
			s.menu.erase(id)
	# vases wilt unless tended
	for f in s.furniture:
		if f.type == "vase":
			s.vase_water[f.id] = int(s.vase_water.get(f.id, 0)) + 1
	for m in St.active_maids(s):
		if m.day_off_tomorrow:
			m.role = "off"
			m.day_off_tomorrow = false
			m.flags["off_today"] = true
		elif m.flags.get("role_tomorrow", "") != "":
			m.role = m.flags.role_tomorrow
			m.flags.erase("role_tomorrow")
		elif m.flags.get("support_tomorrow", false):
			m.role = "support"
			m.flags.erase("support_tomorrow")
			m.flags["support_once"] = true
		elif m.role in ["off", "stage"] or (m.role == "support" and m.flags.get("support_once", false)):
			m.flags.erase("support_once")
			m.role = Data.MAIDS[m.id].default_role if m.get("preferred_role", "") in ["", "stage"] else m.preferred_role
	Life.plan_offdays(s)
	# seasonal decoration comes down when the season ends
	if s.get("decor", "") != "" and s.decor != season:
		s.decor = ""
	if s.street.get("event", "") == "new_shop":
		s.flags["new_shop_seen"] = true
	# street residents remember being visited
	for rid in s.street.residents:
		var r: Dictionary = s.street.residents[rid]
		r.aff = maxf(0.0, float(r.aff) - 0.3)
