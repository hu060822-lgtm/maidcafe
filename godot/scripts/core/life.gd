## Living Hearts: personal lives on top of the existing systems.
## - maids: likes/dislikes that react to what really happened, days off, coming to talk to the manager,
##   promises the manager makes (checked automatically, kept or broken), personal story arcs, memories
## - maid pairs: joint events that come out of the directional relationship values
## - customers: life changes that alter their routine, impressions of the cafe, shared memories
## Every change has a cause stored next to it (memory text, promise, rel_log reason, customer log).
## Pure logic over the state Dictionary (no scene access). Does not preload world/events (no cycles).
extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")
const LD = preload("res://scripts/core/life_data.gd")

const WANT_EXPIRE := 2          # days a maid waits to talk before giving up
const WANT_GAP := 3             # minimum days between two things she brings up
const BUSY_SERVED := 15
const QUIET_SERVED := 8

const TAG_NAMES := {
	"music:jazz": "爵士樂", "music:pop": "偶像流行歌", "music:classical": "古典樂", "music:none": "店裡沒有音樂",
	"light:dim": "昏暗的燈光", "light:warm": "暖黃的燈光", "light:bright": "明亮的燈光",
	"weather:rain": "下雨天", "weather:sunny": "晴天", "weather:snow": "下雪", "weather:hot": "大熱天", "weather:cloudy": "陰天",
	"busy": "忙碌熱鬧的晚上", "quiet": "安靜的晚上", "decor": "季節裝飾",
}

static func _n(id: String) -> String:
	if Data.MAIDS.has(id):
		return Data.MAIDS[id].name
	return Data.CUSTOMERS.get(id, {}).get("name", id)

static func _queue(s: Dictionary, id: String) -> void:
	if not id in s.pending_events:
		s.pending_events.append(id)

static func _active(s: Dictionary, id: String) -> bool:
	return id in s.staff and not s.maids[id].quit

static func tag_name(tag: String) -> String:
	if TAG_NAMES.has(tag):
		return TAG_NAMES[tag]
	var p := tag.split(":")
	match p[0]:
		"act":
			return Data.ACTIVITIES.get(p[1], {}).get("name", p[1])
		"furn":
			return Data.FURNITURE.get(p[1], {}).get("name", p[1])
		"dish":
			return Data.DISHES.get(p[1], {}).get("name", p[1])
		"style":
			return Data.STYLE_NAMES.get(p[1], p[1])
	return tag

## Trust in the manager grows slower the higher it already is (so it means something); losses are not softened.
static func bond_add(m: Dictionary, amount: float) -> void:
	if amount > 0:
		amount *= 1.0 - float(m.bond) / 125.0
	m.bond = St.clampf100(float(m.bond) + amount)

static func life_of(mid: String) -> Dictionary:
	return LD.MAID_LIFE.get(mid, {})

static func likes(mid: String, tag: String) -> bool:
	return tag in life_of(mid).get("likes", [])

static func dislikes(mid: String, tag: String) -> bool:
	return tag in life_of(mid).get("dislikes", [])

## Today's context, built once by the settlement from what really happened.
static func make_ctx(s: Dictionary, served: int, style: String, working_ids: Array) -> Dictionary:
	var furn := {}
	for f in s.furniture:
		furn[f.type] = int(furn.get(f.type, 0)) + 1
	var off := []
	for m in St.active_maids(s):
		if m.role == "off":
			off.append(m.id)
	return {"served": served, "music": s.music, "lighting": s.lighting, "weather": s.weather, "activity": s.activity,
		"furn": furn, "style": style, "decor": s.get("decor", "") != "", "menu": s.menu.duplicate(), "off_ids": off, "working_ids": working_ids}

static func tag_active(tag: String, ctx: Dictionary) -> bool:
	if tag == "busy":
		return int(ctx.served) >= BUSY_SERVED
	if tag == "quiet":
		return int(ctx.served) <= QUIET_SERVED
	if tag == "decor":
		return ctx.decor
	var p := tag.split(":")
	if p.size() != 2:
		return false
	match p[0]:
		"music":
			return ctx.music == p[1]
		"light":
			return ctx.lighting == p[1]
		"weather":
			return ctx.weather == p[1]
		"act":
			return ctx.activity == p[1]
		"furn":
			return ctx.furn.has(p[1])
		"style":
			return ctx.style == p[1]
		"dish":
			return p[1] in ctx.menu
	return false

# ======================================================================== maids: feelings about the day
## Mood reacts to the things she likes / dislikes that actually happened today. Returns short notes.
static func day_feelings(s: Dictionary, ctx: Dictionary) -> Array:
	var notes := []
	for mid in ctx.working_ids:
		var m: Dictionary = s.maids[mid]
		var L := life_of(mid)
		if L.is_empty():
			continue
		var up := 0.0
		var down := 0.0
		var felt := []
		for tag in L.get("likes", []):
			if tag_active(tag, ctx):
				up += 0.5 if tag.begins_with("furn:") else 1.5
				felt.append("喜歡" + tag_name(tag))
		for tag in L.get("dislikes", []):
			if tag_active(tag, ctx):
				var d := 0.5 if tag.begins_with("furn:") else 2.0
				if "laid_back" in Data.MAIDS[mid].traits:
					d *= 0.5
				down += d
				felt.append("不喜歡" + tag_name(tag))
		# who she worked with matters too (her own view of them)
		for o in ctx.working_ids:
			if o == mid:
				continue
			var r := St.rel(s, mid, o)
			if float(r.close) >= 65:
				up += 1.0
				felt.append("和%s一起上班" % _n(o))
			if float(r.friction) >= 40:
				down += 2.5
				felt.append("和%s處不來" % _n(o))
		var delta := minf(4.0, up) - minf(6.0, down)
		m.mood = St.clampf100(float(m.mood) + delta)
		m.flags["feel"] = felt.slice(0, 4)
		m.flags["feel_delta"] = snappedf(delta, 0.1)
		if absf(delta) >= 3.0:
			notes.append("%s：%s（心情 %+d）" % [_n(mid), "、".join(felt.slice(0, 3)), int(roundf(delta))])
		# the first time in a while something she loves happens, she remembers it
		for tag in L.get("likes", []):
			if tag.split(":")[0] in ["furn", "weather", "light"] or tag in ["busy", "quiet"] or not tag_active(tag, ctx):
				continue
			if int(s.day) - int(m.likes_seen.get(tag, -99)) >= 20:
				m.likes_seen[tag] = int(s.day)
				St.remember(s, mid, "第 %d 天，店裡有%s。那天心情特別好。" % [int(s.day), tag_name(tag)], "like", [], 0.8)
				break
	return notes

# ======================================================================== maids: days off
## Plan where each maid spends her day off (deterministic from day, her favourite places and friendships).
static func plan_offdays(s: Dictionary) -> void:
	var off := []
	for m in St.active_maids(s):
		if m.role != "off" or int(m.offday.get("day", -1)) != int(s.day):
			m.offday = {}
		if m.role == "off":
			off.append(m.id)
	for mid in off:
		var m: Dictionary = s.maids[mid]
		if not m.offday.is_empty():
			continue
		var spots: Dictionary = life_of(mid).get("offday", {})
		if spots.is_empty():
			continue
		var keys: Array = spots.keys()
		var loc: String = keys[(int(s.day) + mid.length()) % keys.size()]
		if s.weather == "rain" and loc == "park" and keys.size() > 1:
			loc = keys[(keys.find(loc) + 1) % keys.size()]
		m.offday = {"loc": loc, "line": spots[loc], "with": "", "day": int(s.day)}
		# two close friends who are both off go out together (both have to want it)
		for o in off:
			if o == mid or not s.maids[o].offday.is_empty():
				continue
			if float(St.rel(s, mid, o).close) >= 55 and float(St.rel(s, o, mid).close) >= 55:
				m.offday.with = o
				s.maids[o].offday = {"loc": loc, "line": "她和%s一起逛著商店街。" % _n(mid), "with": mid, "day": int(s.day)}
				break

## Off-duty maids you can meet on the street. Called from World when visiting a location.
static func offday_meet(s: Dictionary, loc: String) -> Array:
	var out := []
	for mid in s.staff:
		var m: Dictionary = s.maids[mid]
		if m.quit or m.role != "off" or m.offday.is_empty() or m.offday.loc != loc or int(m.offday.day) != int(s.day):
			continue
		var w: String = m.offday.get("with", "")
		if w != "" and mid > w:
			continue
		var who := _n(mid) if w == "" else "%s和%s" % [_n(mid), _n(w)]
		var line: String = m.offday.line if w == "" else "兩個人提著同一家店的紙袋，笑得很開心。"
		out.append("☕ 放假的%s也在這裡。%s" % [who, line])
		for x in ([mid] if w == "" else [mid, w]):
			var xm: Dictionary = s.maids[x]
			if int(xm.flags.get("met_offday", -1)) != int(s.day):
				xm.flags["met_offday"] = int(s.day)
				xm.mood = St.clampf100(float(xm.mood) + 5)
				bond_add(xm, 2)
				St.remember(s, x, "休假的時候在%s遇到店長，聊了一下。" % Data.LOCATIONS[loc].name.split("「")[0], "offday", [], 0.8)
		out.append("（聊了幾句，她看起來很開心）")
	return out

## End of a day off: memories and shared experiences.
static func offday_settle(s: Dictionary, notes: Array) -> void:
	for m in St.active_maids(s):
		if m.role != "off" or m.offday.is_empty():
			continue
		var loc_name: String = Data.LOCATIONS[m.offday.loc].name.split("「")[0]
		var w: String = m.offday.get("with", "")
		if w == "":
			St.remember(s, m.id, "休假日去了%s。%s" % [loc_name, m.offday.line], "offday", [], 0.5)
			continue
		if m.id > w or not _active(s, w):
			continue
		St.rel_change(s, m.id, w, "close", 4.0, "一起放假出去玩")
		St.rel_share(s, m.id, w, "一起放假去了%s" % loc_name)
		St.remember(s, m.id, "和%s一起放假去了%s。" % [_n(w), loc_name], "pair", [w], 1.5)
		St.remember(s, w, "和%s一起放假去了%s。" % [_n(m.id), loc_name], "pair", [m.id], 1.5)
		var key := "pairdayoff_" + St.pair_key(m.id, w)
		if int(s.day) - int(s.flags.get(key, -99)) >= 14:
			s.flags[key] = int(s.day)
			_queue(s, "pair:dayoff|%s|%s|%s" % [m.id, w, m.offday.loc])
		notes.append("🛍 %s和%s一起放假去了%s。" % [_n(m.id), _n(w), loc_name])

# ======================================================================== maids: coming to talk, promises
static func open_promise_of(s: Dictionary, mid: String) -> Dictionary:
	for p in s.promises:
		if p.maid == mid and p.status == "open":
			return p
	return {}

static func _want_satisfied(s: Dictionary, w: Dictionary) -> bool:
	match w.kind:
		"furniture":
			var n := 0
			for f in s.furniture:
				if f.type == w.type:
					n += 1
			return n >= int(w.get("count", 1))
		"upgrade":
			return s.upgrades.get(w.id, false)
		"dish":
			return w.dish in s.menu
		"decor":
			return s.get("decor", "") != ""
	return false

static func _pick_request(s: Dictionary, mid: String) -> Dictionary:
	var asked: Dictionary = s.maids[mid].flags.get("asked", {})
	for w in life_of(mid).get("wants", []):
		var key: String = w.kind + ":" + str(w.get("type", w.get("key", w.get("dish", w.get("act", w.get("id", ""))))))
		if _want_satisfied(s, w):
			continue
		if w.kind == "dish" and not Data.DISHES.has(w.dish):
			continue
		if int(s.day) - int(asked.get(key, -99)) < 10:
			continue
		var out: Dictionary = w.duplicate()
		out["key"] = key
		return out
	return {}

## Night: maids decide what they want to bring up tomorrow, ignored wishes expire, arcs come forward.
static func daily(s: Dictionary, rng: RandomNumberGenerator, notes: Array) -> void:
	var new_wants := 0
	var arc_q := 0
	for m in St.active_maids(s):
		var mid: String = m.id
		m.bond = float(m.bond) + (45.0 - float(m.bond)) * 0.01
		# a wish nobody listened to fades, and she remembers that
		if not m.want_talk.is_empty() and int(s.day) - int(m.want_talk.day) >= WANT_EXPIRE:
			bond_add(m, -4)
			m.mood = St.clampf100(float(m.mood) - 5)
			St.remember(s, mid, "想跟店長說「%s」，但店長一直很忙。" % m.want_talk.get("short", "一件事"), "ignored", [], 1.5)
			notes.append("💬 %s本來有話想說，等了兩天就不說了。（信賴 -4）" % _n(mid))
			m.want_talk = {}
		# personal story moves forward when its conditions are really met
		if arc_q < 1 and arc_ready(s, mid) and not ("arc:" + mid) in s.pending_events:
			_queue(s, "arc:" + mid)
			arc_q += 1
		if not m.want_talk.is_empty() or new_wants >= 2 or int(s.day) < int(m.flags.get("want_next", 3)):
			continue
		var want := {}
		if int(m.flags.get("tired_nights", 0)) >= 2:
			want = {"topic": "tired", "short": "最近很累", "line": Data.MAIDS[mid].lines.tired[0]}
		elif "praised" in m.yesterday and rng.randf() < 0.3:
			want = {"topic": "share", "short": "昨天被客人誇獎了", "line": Data.MAIDS[mid].lines.happy[0]}
		elif float(m.bond) >= 30 and open_promise_of(s, mid).is_empty():
			var req := _pick_request(s, mid)
			if not req.is_empty():
				want = {"topic": "request", "short": req.promise, "line": req.ask, "want": req}
		if want.is_empty():
			continue
		want["day"] = int(s.day) + 1
		m.want_talk = want
		m.flags["want_next"] = int(s.day) + WANT_GAP + (2 if float(m.bond) < 30 else 0)
		new_wants += 1

## What the talk looks like when the manager listens. Returns {title, lines, options:[{id,label}]}.
static func talk_view(s: Dictionary, mid: String) -> Dictionary:
	var m: Dictionary = s.maids[mid]
	var w: Dictionary = m.want_talk
	var n := _n(mid)
	if w.is_empty():
		return {}
	match w.topic:
		"request":
			return {"title": "%s有事想拜託" % n, "lines": ["%s：「%s」" % [n, w.line]],
				"options": [{"id": "promise", "label": "「好，我答應妳。」（%s）" % w.want.promise}, {"id": "later", "label": "「現在還沒辦法……」"}]}
		"tired":
			return {"title": "%s想說的話" % n, "lines": ["%s：「%s……店長，老實說，最近真的有點累。」" % [n, w.line]],
				"options": [{"id": "rest", "label": "「明天放假吧。」"}, {"id": "push", "label": "「再撐一下好嗎？」"}]}
		"share":
			return {"title": "%s想說的話" % n, "lines": ["%s：「店長店長！%s」" % [n, w.line], "她看起來很想把昨天的事說給妳聽。"],
				"options": [{"id": "listen", "label": "「說給我聽聽！」"}]}
	return {}

static func talk_resolve(s: Dictionary, mid: String, opt: String) -> String:
	var m: Dictionary = s.maids[mid]
	var w: Dictionary = m.want_talk
	var n := _n(mid)
	if w.is_empty():
		return ""
	m.want_talk = {}
	m.flags["listened"] = int(m.flags.get("listened", 0)) + 1
	match opt:
		"promise":
			var req: Dictionary = w.want
			var asked: Dictionary = m.flags.get("asked", {})
			asked[req.key] = int(s.day)
			m.flags["asked"] = asked
			var days := 5
			match req.kind:
				"music":
					days = 3
				"dish":
					days = 3
			add_promise(s, mid, {"kind": req.kind, "type": req.get("type", ""), "key": req.get("key", ""), "dish": req.get("dish", ""), "act": req.get("act", ""),
				"id": req.get("id", ""), "count": req.get("count", 1), "days": days}, req.promise)
			bond_add(m, 3)
			m.mood = St.clampf100(float(m.mood) + 6)
			return "%s的眼睛亮了起來：「真的嗎！？我會記住的喔！」\n（約定：%s，%d 天內）" % [n, req.promise, days]
		"later":
			var asked: Dictionary = m.flags.get("asked", {})
			asked[w.want.key] = int(s.day)
			m.flags["asked"] = asked
			bond_add(m, -1)
			m.mood = St.clampf100(float(m.mood) - 2)
			St.remember(s, mid, "跟店長說想要%s，店長說現在還沒辦法。" % w.want.promise.trim_prefix("在店裡"), "request", [], 0.8)
			return "%s：「……嗯，我知道了。等店裡再好一點吧。」" % n
		"rest":
			m.day_off_tomorrow = true
			bond_add(m, 5)
			m.mood = St.clampf100(float(m.mood) + 5)
			St.remember(s, mid, "說了很累之後，店長讓我放假。", "care", [], 1.5)
			return "%s鬆了一口氣：「謝謝店長……我會好好休息的。」（明天休假）" % n
		"push":
			bond_add(m, -3)
			m.mood = St.clampf100(float(m.mood) - 3)
			St.remember(s, mid, "說了很累，店長要我再撐一下。", "care", [], 1.5)
			return "%s：「……好，我會努力的。」她的笑容有點勉強。" % n
		"listen":
			bond_add(m, 3)
			m.mood = St.clampf100(float(m.mood) + 6)
			St.remember(s, mid, "把被誇獎的事說給店長聽，店長聽得很認真。", "share", [], 1.0)
			var tr: Array = Data.MAIDS[mid].traits
			if "slow_warm" in tr or "bookish" in tr or "perfectionist" in tr:
				return "%s說得很簡短，但說完以後，嘴角一直沒有放下來。" % n
			if "shy" in tr:
				return "%s小聲地、一點一點地說完了。最後她鼓起勇氣說：「……下次，也想說給店長聽。」" % n
			return "%s比手畫腳地說了好久。說完後，她笑著說：「下次也要說給店長聽！」" % n
	return ""

## A promise the manager made. Checked every night by check_promises.
static func add_promise(s: Dictionary, mid: String, data: Dictionary, text: String) -> Dictionary:
	var from := int(s.day) + (1 if s.phase == "night" else 0)
	var p := {"id": "p%d_%s" % [int(s.day), mid], "maid": mid, "kind": data.kind, "data": data, "text": text, "day": int(s.day), "from": from, "status": "open"}
	if data.kind == "dayoff_on":
		var target := from
		if data.has("weekday"):
			target = from + 1
			while Data.weekday(target) != int(data.weekday):
				target += 1
		else:
			target = int(s.day) + int(data.get("days", 3))
		p["target"] = target
		p["due"] = target
	else:
		p["due"] = from + int(data.get("days", 5)) - 1
	if data.has("kept_flag"):
		p["kept_flag"] = data.kept_flag
	s.promises.append(p)
	# closed promises older than the cap are dropped (the maid's memory keeps the story)
	while s.promises.size() > St.CAP_PROMISES:
		var dropped := false
		for i in s.promises.size():
			if s.promises[i].status != "open":
				s.promises.remove_at(i)
				dropped = true
				break
		if not dropped:
			break
	return p

static func _promise_met(s: Dictionary, p: Dictionary, ctx: Dictionary) -> bool:
	var d: Dictionary = p.data
	match p.kind:
		"furniture":
			return int(ctx.furn.get(d.type, 0)) >= int(d.get("count", 1))
		"upgrade":
			return s.upgrades.get(d.id, false)
		"music":
			var key: String = String(d.get("key", "")).split(":")[-1]
			return ctx.music == key
		"dish":
			return d.dish in ctx.menu
		"activity":
			return ctx.activity == d.act
		"decor":
			return ctx.decor
		"dayoff_on":
			return int(s.day) == int(p.target) and p.maid in ctx.off_ids
	return false

## Every night: promises are kept or broken by what the manager actually did. Nothing is clicked.
static func check_promises(s: Dictionary, ctx: Dictionary, notes: Array) -> void:
	for p in s.promises:
		if p.status != "open" or int(s.day) < int(p.from):
			continue
		var mid: String = p.maid
		if not _active(s, mid):
			p.status = "void"
			continue
		var m: Dictionary = s.maids[mid]
		if _promise_met(s, p, ctx):
			p.status = "kept"
			p["closed"] = int(s.day)
			bond_add(m, 8)
			m.mood = St.clampf100(float(m.mood) + 10)
			St.remember(s, mid, "店長遵守了約定：%s。" % p.text, "promise_kept", [], 2.5)
			if p.has("kept_flag"):
				s.flags[p.kept_flag] = true
			notes.append("🤝 遵守了和%s的約定：%s（信賴 +8）" % [_n(mid), p.text])
			s.moments.append({"day": int(s.day), "id": "promise_" + p.id, "text": "%s發現店長真的記得約定（%s），偷偷笑了好久。" % [_n(mid), p.text], "who": [mid]})
		elif int(s.day) >= int(p.due):
			p.status = "broken"
			p["closed"] = int(s.day)
			bond_add(m, -10)
			m.mood = St.clampf100(float(m.mood) - 10)
			St.remember(s, mid, "店長說過要%s……結果沒有。" % p.text, "promise_broken", [], 2.5)
			notes.append("💔 沒有做到和%s的約定：%s（信賴 -10）" % [_n(mid), p.text])
	while s.moments.size() > St.CAP_MOMENT_LOG:
		s.moments.pop_front()

static func promises_due_today(s: Dictionary) -> Array:
	var out := []
	for p in s.promises:
		if p.status == "open" and int(s.day) >= int(p.from):
			if p.kind == "dayoff_on":
				if int(p.target) == int(s.day):
					out.append("📅 今天要讓%s放假（約定：%s）" % [_n(p.maid), p.text])
			elif int(p.due) - int(s.day) <= 1:
				out.append("🤝 和%s的約定快到期了：%s" % [_n(p.maid), p.text])
	return out

# ======================================================================== maids: personal arcs
static func _arc_stage_def(mid: String, stage: int) -> Dictionary:
	var arc: Array = life_of(mid).get("arc", [])
	return arc[stage] if stage < arc.size() else {}

static func arc_ready(s: Dictionary, mid: String) -> bool:
	var m: Dictionary = s.maids[mid]
	var st := _arc_stage_def(mid, int(m.arc_stage))
	if st.is_empty() or int(m.flags.get("arc_last", -99)) >= int(s.day) - 2:
		return false
	var need: Dictionary = st.need
	if float(m.bond) < float(need.get("bond", 0)):
		return false
	if int(m.days_worked) < int(need.get("days_worked", 0)):
		return false
	if int(m.greets_done) < int(need.get("greets_done", 0)):
		return false
	if need.has("skill") and float(m.skills[need.skill[0]]) < float(need.skill[1]):
		return false
	if need.has("flag") and not s.flags.get(need.flag, false):
		return false
	if need.has("upgrade") and not s.upgrades.get(need.upgrade, false):
		return false
	if need.has("furn"):
		var found := false
		for f in s.furniture:
			if f.type == need.furn:
				found = true
		if not found:
			return false
	if need.has("customer_visits") and int(s.customers[need.customer_visits[0]].visits) < int(need.customer_visits[1]):
		return false
	return true

static func arc_event(s: Dictionary, mid: String) -> Dictionary:
	if not s.maids.has(mid):
		return {}
	var st := _arc_stage_def(mid, int(s.maids[mid].arc_stage))
	if st.is_empty():
		return {}
	return {"id": "arc:" + mid, "title": st.title, "who": mid, "lines": st.lines, "choices": st.choices.map(func(c): return c.label)}

static func arc_resolve(s: Dictionary, mid: String, idx: int) -> String:
	var m: Dictionary = s.maids[mid]
	var st := _arc_stage_def(mid, int(m.arc_stage))
	if st.is_empty():
		return ""
	var ch: Dictionary = st.choices[clampi(idx, 0, st.choices.size() - 1)]
	var fx: Dictionary = ch.fx
	var out := []
	if fx.has("bond"):
		bond_add(m, float(fx.bond))
		out.append("信賴 %+d" % int(fx.bond))
	if fx.has("mood"):
		m.mood = St.clampf100(float(m.mood) + float(fx.mood))
		out.append("心情 %+d" % int(fx.mood))
	if fx.has("exp"):
		var k: String = fx.exp[0]
		m.skills[k] = minf(float(Data.MAIDS[mid].caps[k]), float(m.skills[k]) + float(fx.exp[1]) / 10.0)
		out.append("%s +%d" % [Data.SKILL_NAMES[k], int(float(fx.exp[1]) / 10.0)])
	if fx.has("flag"):
		s.flags[fx.flag] = true
	if fx.has("memory"):
		St.remember(s, mid, fx.memory[0], "arc", [], float(fx.memory[1]))
	if fx.has("promise"):
		var p := add_promise(s, mid, fx.promise, fx.promise.text)
		out.append("約定：%s（到第 %d 天）" % [p.text, int(p.due)])
	if fx.has("album"):
		St.add_album(s, fx.album[0], fx.album[1], [mid], "pending", "arc_%s_%d" % [mid, int(m.arc_stage)], "maid")
		out.append("📷 新的回憶：「%s」" % fx.album[0])
	m.arc_stage = 99 if fx.get("end_arc", false) else int(m.arc_stage) + 1
	m.flags["arc_last"] = int(s.day)
	return "（%s）" % "、".join(out) if not out.is_empty() else "……"

# ======================================================================== maid pairs: joint events
## Joint events come from the directional values: someone looks up to someone (mentor), two maids who work
## well but needle each other (rival), an unresolved argument that one of them finally reaches out about (reconcile).
static func pair_events(s: Dictionary, working_ids: Array, helps: Array) -> void:
	var queued := 0
	for a in working_ids:
		for b in working_ids:
			if a == b or queued >= 1:
				continue
			var ma: Dictionary = s.maids[a]
			var mb: Dictionary = s.maids[b]
			var ba := St.rel(s, b, a)   # how b sees a
			# mentor: a is much better at something b is working on, and b trusts a
			var best_k := ""
			for k in ["cooking", "reception", "floor", "performance"]:
				if float(ma.skills[k]) >= 60 and float(ma.skills[k]) - float(mb.skills[k]) >= 22:
					best_k = k
					break
			if best_k != "" and float(ba.trust) >= 50 and not s.flags.get("pair_mentor_%s>%s" % [a, b], false):
				s.flags["pair_mentor_%s>%s" % [a, b]] = true
				_queue(s, "pair:mentor|%s|%s|%s" % [a, b, best_k])
				queued += 1
				continue
			# rival: same role, real teamwork, but a keeps getting under b's skin
			if a < b and ma.role == mb.role and ma.role in ["floor", "reception", "kitchen"]:
				var ab := St.rel(s, a, b)
				if float(ab.synergy) >= 35 and (float(ab.friction) >= 12 or float(ba.friction) >= 12) and not s.flags.get("pair_rival_" + St.pair_key(a, b), false):
					s.flags["pair_rival_" + St.pair_key(a, b)] = true
					_queue(s, "pair:rival|%s|%s" % [a, b])
					queued += 1
					continue
	# reconcile: an argument that was left unresolved, and today one helped the other
	for k in s.flags.keys():
		if not String(k).begins_with("unresolved:"):
			continue
		var p: PackedStringArray = String(k).substr(11).split("|")
		if p.size() != 2 or not _active(s, p[0]) or not _active(s, p[1]):
			s.flags.erase(k)
			continue
		var helped := false
		for h in helps:
			if (h.helper == p[0] and h.helped == p[1]) or (h.helper == p[1] and h.helped == p[0]):
				helped = true
		if helped or int(s.day) - int(s.flags[k]) >= 6:
			s.flags.erase(k)
			_queue(s, "pair:reconcile|%s|%s" % [p[0], p[1]])
			break

static func pair_event(s: Dictionary, arg: String) -> Dictionary:
	var p := arg.split("|")
	if p.size() < 3 or not _active(s, p[1]) or not _active(s, p[2]):
		return {}
	var a := _n(p[1])
	var b := _n(p[2])
	var id := "pair:" + arg
	match p[0]:
		"mentor":
			var k: String = Data.SKILL_NAMES.get(p[3] if p.size() > 3 else "", "")
			return {"id": id, "title": "%s的小老師" % a, "who": p[1], "lines": ["打烊後，%s叫住了%s。" % [a, b], "%s：「剛剛那個%s的動作，我教妳一個訣竅。」" % [a, k], "%s學得很認真，連筆記本都拿出來了。" % b],
				"choices": ["（在旁邊看著）"]}
		"rival":
			return {"id": id, "title": "%s和%s的比賽" % [a, b], "who": p[1], "lines": ["%s：「今天誰做得比較多？」" % a, "%s：「當然是我。明天再比一次。」" % b, "兩個人嘴上不饒人，手上的動作卻越來越有默契。"],
				"choices": ["「明天我來當裁判。」", "「別比了，好好合作。」"]}
		"reconcile":
			return {"id": id, "title": "和好", "who": p[1], "lines": ["%s端著兩杯熱可可，走到%s旁邊。" % [a, b], "%s：「……那天，是我說得太過分了。」" % a, "%s接過杯子，小聲地說：「我也是。」" % b],
				"choices": ["（悄悄離開休息室）"]}
		"dayoff":
			var loc: String = Data.LOCATIONS.get(p[3] if p.size() > 3 else "", {}).get("name", "商店街").split("「")[0]
			return {"id": id, "title": "%s和%s的休假日" % [a, b], "who": p[1], "lines": ["%s和%s同一天放假，約好了一起去%s。" % [a, b, loc], "隔天，兩個人的手機桌布換成了同一張照片。"],
				"choices": ["「下次也帶我去吧。」"]}
	return {}

static func pair_resolve(s: Dictionary, arg: String, idx: int) -> String:
	var p := arg.split("|")
	if p.size() < 3:
		return ""
	var a := p[1]
	var b := p[2]
	match p[0]:
		"mentor":
			var k: String = p[3]
			s.maids[b].skills[k] = minf(float(Data.MAIDS[b].caps[k]), float(s.maids[b].skills[k]) + 3.0)
			St.rel_change(s, b, a, "trust", 5.0, "%s教了%s訣竅" % [_n(a), _n(b)], false)
			St.rel_change(s, a, b, "close", 3.0, "教%s做事" % _n(b), false)
			St.rel_share(s, a, b, "%s教%s%s的訣竅" % [_n(a), _n(b), Data.SKILL_NAMES[k]])
			St.remember(s, b, "%s教了我%s的訣竅。" % [_n(a), Data.SKILL_NAMES[k]], "pair", [a], 1.5)
			return "%s的%s +3。%s更信任%s了。" % [_n(b), Data.SKILL_NAMES[k], _n(b), _n(a)]
		"rival":
			var role: String = s.maids[a].role
			var k: String = {"kitchen": "cooking", "reception": "reception"}.get(role, "floor")
			for x in [a, b]:
				s.maids[x].skills[k] = minf(float(Data.MAIDS[x].caps[k]), float(s.maids[x].skills[k]) + 2.0)
			St.rel_change(s, a, b, "friction", -8.0, "較勁變成了良性競爭")
			St.rel_change(s, a, b, "synergy", 5.0 if idx == 0 else 2.0, "互相較勁")
			if idx == 1:
				St.rel_change(s, a, b, "close", 3.0, "店長要她們好好合作")
			St.rel_share(s, a, b, "比賽誰做得多，結果不分勝負")
			return "兩人的%s各 +2，默契上升了。" % Data.SKILL_NAMES[k]
		"reconcile":
			St.rel_change(s, a, b, "friction", -20.0, "和好了")
			St.rel_change(s, a, b, "close", 6.0, "和好了")
			St.rel_change(s, b, a, "trust", 4.0, "%s先來道歉" % _n(a), false)
			St.rel_share(s, a, b, "吵架之後，一起喝了熱可可")
			St.remember(s, a, "和%s和好了。" % _n(b), "pair", [b], 2.0)
			St.remember(s, b, "%s先來跟我道歉了。" % _n(a), "pair", [a], 2.0)
			St.add_album(s, "%s和%s和好了" % [_n(a), _n(b)], "吵架之後的第一杯熱可可。%s先開口道歉，%s說「我也是」。" % [_n(a), _n(b)], [a, b], "pending", "reconcile_" + St.pair_key(a, b), "pair")
			return "兩人之間的摩擦大幅下降。"
		"dayoff":
			var loc: String = Data.LOCATIONS.get(p[3] if p.size() > 3 else "", {}).get("name", "商店街").split("「")[0]
			St.add_album(s, "%s和%s的休假日" % [_n(a), _n(b)], "%s和%s一起放假去了%s。回來的時候，兩個人提著同一家店的紙袋。" % [_n(a), _n(b), loc], [a, b], "", "dayoff_" + St.pair_key(a, b), "pair")
			return "📷 新的回憶。"
	return ""

## The outcome of an argument during off-hours depends on how much the other one trusts her.
static func argue(s: Dictionary, a: String, b: String) -> Dictionary:
	var trust_b := float(St.rel(s, b, a).trust)
	if trust_b >= 45:
		St.rel_change(s, a, b, "friction", -12.0, "吵了一架，但把話說開了")
		St.rel_change(s, a, b, "trust", 3.0, "把話說開了")
		St.rel_share(s, a, b, "吵了一架，但把話說開了")
		return {"ok": true, "a_line": "……我覺得工作都落在我身上。", "b_line": "……對不起，我沒注意到。下次我會多看一下。",
			"text": "%s和%s在打烊後吵了起來。說到最後，兩個人都笑了出來。" % [_n(a), _n(b)]}
	St.rel_change(s, a, b, "friction", 5.0, "吵架")
	s.maids[a].mood = St.clampf100(float(s.maids[a].mood) - 6)
	s.maids[b].mood = St.clampf100(float(s.maids[b].mood) - 6)
	s.flags["unresolved:" + St.pair_key(a, b)] = int(s.day)
	St.remember(s, a, "和%s吵架了。" % _n(b), "fight", [b], 1.5)
	St.remember(s, b, "%s突然對我發脾氣。" % _n(a), "fight", [a], 1.5)
	return {"ok": false, "a_line": "妳每次都這樣！", "b_line": "……我又不是故意的。",
		"text": "%s和%s在打烊後吵了起來。%s甩上了休息室的門。" % [_n(a), _n(b), _n(b)]}

# ======================================================================== customers: life, impressions, shared memories
const IMPRESSION := {
	"greatFood": ["food", 3.0], "favDish": ["food", 2.0], "badFood": ["food", -3.0], "outOfStock": ["food", -2.0],
	"favMaid": ["service", 2.0], "maidChat": ["service", 2.0], "managerChat": ["service", 2.0], "complaintHandled": ["service", 2.0],
	"seatChanged": ["service", 1.0], "longWaitDoor": ["service", -2.0], "longWaitOrder": ["service", -2.0], "longWaitFood": ["service", -2.0],
	"wrongOrder": ["service", -2.0], "spill": ["service", -1.0], "complaintIgnored": ["service", -5.0], "walkedOut": ["service", -5.0],
	"remembered": ["remembered", 3.0], "styleMatch": ["cozy", 2.0], "favSeat": ["cozy", 2.0], "likedMusic": ["cozy", 2.0], "bookshelf": ["cozy", 2.0],
	"enjoyedShow": ["cozy", 2.0], "noisy": ["cozy", -3.0], "hot": ["cozy", -2.0], "seatTaken": ["cozy", -2.0], "seatUnhappy": ["cozy", -1.0],
}
const IMPRESSION_NAMES := {"food": ["覺得料理好吃", "對料理不太滿意"], "service": ["覺得店員很用心", "覺得服務有待加強"],
	"remembered": ["很高興被記住", ""], "cozy": ["覺得店裡很自在", "覺得店裡待起來不太舒服"]}

static func impression_score(mem: Dictionary) -> float:
	var t := 0.0
	for k in mem.impressions:
		t += float(mem.impressions[k])
	return t

static func impression_text(mem: Dictionary) -> String:
	var parts := []
	for k in mem.impressions:
		var v := float(mem.impressions[k])
		if absf(v) < 2.0 or not IMPRESSION_NAMES.has(k):
			continue
		var t: String = IMPRESSION_NAMES[k][0 if v > 0 else 1]
		if t != "":
			parts.append(t)
	return "、".join(parts)

## Customer life: impressions from today's visit, life stages, akiko's gossip, shared memories of related customers.
static func customers_daily(s: Dictionary, results: Array, co_present: Dictionary, notes: Array) -> void:
	var came := {}
	for r in results:
		if r.def != "" and s.customers.has(r.def):
			came[r.def] = r
	# impressions fade a little every day; today's visit adds to them
	for cid in s.customers:
		var mem: Dictionary = s.customers[cid]
		for k in mem.impressions.keys():
			mem.impressions[k] = float(mem.impressions[k]) * 0.92
			if absf(float(mem.impressions[k])) < 0.3:
				mem.impressions.erase(k)
	for cid in came:
		var mem: Dictionary = s.customers[cid]
		for c in came[cid].causes:
			if IMPRESSION.has(c):
				var e: Array = IMPRESSION[c]
				mem.impressions[e[0]] = clampf(float(mem.impressions.get(e[0], 0.0)) + float(e[1]), -20.0, 20.0)
	# akiko tells her friends what she thinks of the place
	if came.has("akiko"):
		var ak: Dictionary = s.customers.akiko
		var sc := impression_score(ak)
		if absf(sc) >= 4.0:
			for k in s.cust_rel:
				var cr: Dictionary = s.cust_rel[k]
				var p: PackedStringArray = String(k).split("|")
				if cr.type == "" or not "akiko" in p:
					continue
				var other: String = p[1] if p[0] == "akiko" else p[0]
				var om: Dictionary = s.customers[other]
				om.impressions["gossip"] = clampf(float(om.impressions.get("gossip", 0.0)) + sc * 0.3, -10.0, 10.0)
				if int(s.flags.get("gossip_" + other, -99)) < int(s.day) - 6:
					s.flags["gossip_" + other] = int(s.day)
					St.cust_log(om, int(s.day), "聽秋子阿姨說這間店%s" % ("很不錯" if sc > 0 else "最近不太行"))
					notes.append("🗣 秋子阿姨把店裡的事說給%s聽了（%s）。" % [_n(other), "好話" if sc > 0 else "抱怨"])
	# related customers who spent the evening together remember it
	for k in s.cust_rel:
		var cr: Dictionary = s.cust_rel[k]
		var p: PackedStringArray = String(k).split("|")
		if cr.type == "" or not came.has(p[0]) or not came.has(p[1]) or float(co_present.get(k, 0.0)) < 30.0:
			continue
		var same_table: bool = came[p[0]].table != "" and came[p[0]].table == came[p[1]].table
		var txt := "第 %d 天%s" % [int(s.day), "坐在同一桌聊了很久" if same_table else "在店裡碰面，隔著桌子聊了幾句"]
		if not cr.has("memories"):
			cr["memories"] = []
		cr.memories.append({"day": int(s.day), "text": txt})
		while cr.memories.size() > St.CAP_CREL_MEMORY:
			cr.memories.pop_front()
	# life stages
	for cid in LD.CUSTOMER_LIFE:
		_customer_stage(s, cid, came, notes)

static func _customer_stage(s: Dictionary, cid: String, came: Dictionary, notes: Array) -> void:
	var mem: Dictionary = s.customers[cid]
	if not mem.known:
		return
	var stages: Array = LD.CUSTOMER_LIFE[cid]
	var life: Dictionary = mem.life
	# a life state runs out
	if life.state != "" and int(life.until) >= 0 and int(s.day) >= int(life.until):
		St.cust_log(mem, int(s.day), "「%s」告一段落" % life.note.split("。")[0])
		mem.life = {"state": "", "until": -1, "note": "", "done": true}
		life = mem.life
	var stage := int(mem.arc_stage)
	# yearly stages (a birthday) repeat; others advance once
	if stage >= stages.size():
		if stages[0].get("repeat_yearly", false) and int(s.flags.get("carc_year_" + cid, -1)) != int((int(s.day)) / Data.YEAR_DAYS):
			stage = 0
		else:
			return
	var st: Dictionary = stages[stage]
	var need: Dictionary = st.need
	if int(mem.visits) < int(need.get("visits", 0)):
		return
	if need.has("furn"):
		var found := false
		for f in s.furniture:
			if f.type == need.furn:
				found = true
		if not found:
			return
	if need.get("life_done", false) and not life.get("done", false):
		return
	if need.has("year_day"):
		# set up the day before (so the routine changes tomorrow), the scene happens when they come
		var tomorrow := ((int(s.day)) % Data.YEAR_DAYS) + 1
		if tomorrow != int(need.year_day) or life.state == st.life.state:
			return
		s.flags["carc_year_" + cid] = int(int(s.day) / Data.YEAR_DAYS)
		_set_life(s, mem, st.life)
		mem.arc_stage = stage + 1
		St.cust_log(mem, int(s.day), st.life.note)
		return
	# other stages begin on a day the customer actually came (the scene needs them there)
	if not came.has(cid):
		return
	_set_life(s, mem, st.life)
	mem.arc_stage = stage + 1
	var good: bool = impression_score(mem) >= float(st.get("album_if", 0))
	mem.life["good"] = good
	St.cust_log(mem, int(s.day), st.title)
	_queue(s, "carc:%s|%d" % [cid, stage])
	notes.append("📖 %s：%s" % [_n(cid), st.title])

static func _set_life(s: Dictionary, mem: Dictionary, life: Dictionary) -> void:
	var days := int(life.get("days", -1))
	mem.life = {"state": life.state, "until": (int(s.day) + days) if days > 0 else -1, "note": life.get("note", ""), "done": false, "since": int(s.day)}
	for k in ["arrival", "weekdays", "chance", "absent"]:
		if life.has(k):
			mem.life[k] = life[k]

## Visiting during a birthday: the scene is queued from the settlement when they came (see customer_visit_events).
static func customer_visit_events(s: Dictionary, results: Array) -> void:
	for r in results:
		var cid: String = r.def
		if cid == "" or not LD.CUSTOMER_LIFE.has(cid):
			continue
		var mem: Dictionary = s.customers[cid]
		if mem.life.state == "birthday":
			var st: Dictionary = LD.CUSTOMER_LIFE[cid][0]
			mem.life["good"] = st.get("needs_dish", "") in r.items
			_queue(s, "carc:%s|0" % cid)

static func carc_event(s: Dictionary, arg: String) -> Dictionary:
	var p := arg.split("|")
	if p.size() != 2 or not LD.CUSTOMER_LIFE.has(p[0]):
		return {}
	var cid := p[0]
	var st: Dictionary = LD.CUSTOMER_LIFE[cid][int(p[1])]
	var mem: Dictionary = s.customers[cid]
	var lines: Array = st.lines.duplicate()
	if st.has("low_lines") and not mem.life.get("good", true):
		lines = st.low_lines
	if st.has("needs_dish"):
		lines.append("小陸吃到布丁的那一刻，整張臉都亮了起來。" if mem.life.get("good", false) else "可是今天的菜單上沒有布丁。小陸低著頭，爺爺摸了摸他的頭。")
	return {"id": "carc:" + arg, "title": st.title, "who": cid, "lines": lines, "choices": ["（繼續）"]}

static func carc_resolve(s: Dictionary, arg: String, _idx: int) -> String:
	var p := arg.split("|")
	var cid := p[0]
	var st: Dictionary = LD.CUSTOMER_LIFE[cid][int(p[1])]
	var mem: Dictionary = s.customers[cid]
	var good: bool = mem.life.get("good", true)
	if st.has("needs_dish"):
		mem.life.state = ""
		if good:
			mem.loyalty = St.clampf100(float(mem.loyalty) + 8)
			s.customers.takagi.loyalty = St.clampf100(float(s.customers.takagi.loyalty) + 5)
			St.add_album(s, st.album, "小陸生日那天，高木爺爺帶他來吃布丁。紙做的王冠一直戴到回家。", [cid, "takagi"], "pending", "%s_%d" % [st.album, int(int(s.day) / Data.YEAR_DAYS)], "customer")
			return "📷 新的回憶：「%s」" % st.album
		mem.impressions["food"] = float(mem.impressions.get("food", 0.0)) - 3.0
		return "小陸的生日沒能吃到布丁。明年……要記得準備。"
	if st.has("album") and good:
		St.add_album(s, st.album, st.lines[st.lines.size() - 1], [cid], "pending", "carc_%s_%s" % [cid, p[1]], "customer")
		mem.loyalty = St.clampf100(float(mem.loyalty) + 6)
		return "📷 新的回憶：「%s」" % st.album
	if mem.life.state != "":
		return "（%s）" % mem.life.note
	return "……"

## How a customer's current life changes today's visit plan.
static func arrival_mod(s: Dictionary, cid: String) -> Dictionary:
	var mem: Dictionary = s.customers[cid]
	var life: Dictionary = mem.life
	var out := {"skip": false, "chance": 1.0, "reasons": []}
	if life.state != "":
		if life.get("absent", false):
			out.skip = true
			return out
		out.chance = float(life.get("chance", 1.0))
		if life.has("arrival"):
			out["arrival"] = life.arrival
		if life.has("weekdays"):
			out["weekdays"] = life.weekdays
		if life.note != "":
			out.reasons.append(life.note.split("。")[0])
	var sc := impression_score(mem)
	out["bonus"] = clampf(sc / 120.0, -0.15, 0.15)
	if sc >= 8.0:
		out.reasons.append("對店裡印象很好")
	elif sc <= -8.0:
		out.reasons.append("對店裡印象不太好（-）")
	return out

## Extra arrival line that comes from their life or a shared memory with someone else who is here today.
static func arrival_line(s: Dictionary, cid: String, here: Array) -> String:
	var mem: Dictionary = s.customers[cid]
	match mem.life.state:
		"job_hunting":
			return "（鬆了鬆領帶）……今天的面試好累。"
		"employed":
			return "下班了～老樣子！"
		"contest":
			return "今天也借一下拍照區喔！"
		"birthday":
			return "今天是我的生日！"
	for k in s.cust_rel:
		var cr: Dictionary = s.cust_rel[k]
		var p: PackedStringArray = String(k).split("|")
		if not cid in p or cr.get("memories", []).is_empty():
			continue
		var other: String = p[1] if p[0] == cid else p[0]
		if other in here:
			return "啊，%s也在！上次%s呢。" % [_n(other), cr.memories[cr.memories.size() - 1].text.split("天")[-1]]
	return ""

# ======================================================================== memory in dialogue
## A line where she brings up something she remembers (used by World.chat_line). "" when nothing fits.
static func memory_line(s: Dictionary, mid: String, talks: int) -> String:
	var m: Dictionary = s.maids[mid]
	var n := _n(mid)
	# a promise kept or broken recently is on her mind first
	for i in range(m.memories.size() - 1, -1, -1):
		var mm: Dictionary = m.memories[i]
		if int(s.day) - int(mm.day) > 3:
			break
		if mm.tag == "promise_kept":
			return "%s：「%s我真的好開心。謝謝妳記得。」" % [n, mm.text.trim_prefix("店長遵守了約定：").trim_suffix("。") + "……"]
		if mm.tag == "promise_broken":
			return "%s：「……沒關係啦。我知道店長很忙。」（她想起了那個約定）" % n
	var strong := []
	for mm in m.memories:
		if float(mm.weight) >= 1.5 and int(s.day) - int(mm.day) >= 3:
			strong.append(mm)
	if strong.is_empty() or talks % 4 != 3:
		return ""
	var mm: Dictionary = strong[(talks / 4) % strong.size()]
	return "%s：「店長，還記得嗎？第 %d 天……%s」" % [n, int(mm.day), mm.text]
