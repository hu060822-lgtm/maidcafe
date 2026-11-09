## Maid personal concerns ("心事"). A concern grows out of what actually happened
## (friction, mistakes, fatigue, curiosity about another job, a missing regular...).
## It shows up in the scene first (behaviour + bubbles), can be learned about by talking,
## and the manager decides: intervene / ask / leave it. Each path changes later behaviour.
extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")

const TYPE_NAMES := {"quarrel": "同事間的摩擦", "self_doubt": "對自己沒信心", "hidden_fatigue": "硬撐著的疲勞",
	"wants_role": "想嘗試別的工作", "homesick": "想家", "regular_worry": "擔心一位熟客"}

static func name_of(id: String) -> String:
	return Data.MAIDS[id].name if Data.MAIDS.has(id) else Data.CUSTOMERS.get(id, {}).get("name", id)

## Called every night after settlement. Creates at most one new concern, expires old ones.
static func daily(s: Dictionary, stats: Dictionary, rng: RandomNumberGenerator) -> Array:
	var notes := []
	for m in St.active_maids(s):
		if m.concern.is_empty():
			if int(m.concern_cooldown) > 0:
				m.concern_cooldown = int(m.concern_cooldown) - 1
			continue
		var c: Dictionary = m.concern
		c.age = int(c.get("age", 0)) + 1
		var t := _tick_ignored(s, m, c, rng)
		if t != "":
			notes.append(t)
	# new concern?
	var cands := []
	for m in St.active_maids(s):
		if not m.concern.is_empty() or int(m.concern_cooldown) > 0 or m.role == "off":
			continue
		var st: Dictionary = stats.get(m.id, {})
		var traits: Array = Data.MAIDS[m.id].traits
		for o in St.active_maids(s):
			if o.id == m.id or not o.concern.is_empty():
				continue
			var r := St.rel(s, m.id, o.id)
			if float(r.friction) >= 30:
				cands.append({"w": float(r.friction) / 30.0, "c": _make_quarrel(m.id, o.id, r)})
		if int(st.get("spills", 0)) + int(st.get("wrong", 0)) + int(st.get("complaints", 0)) >= 2 or ("complaint" in m.yesterday and "spill" in m.yesterday):
			cands.append({"w": 1.6, "c": _make_doubt(m.id)})
		if float(m.fatigue) >= 55 and int(m.flags.get("tired_nights", 0)) >= 2 and ("perfectionist" in traits or "caring" in traits):
			cands.append({"w": 1.4, "c": _make_fatigue(m.id)})
		var want := _wanted_role(m)
		if want != "" and int(m.days_worked) >= 4:
			cands.append({"w": 0.8, "c": _make_role(m.id, want)})
		for cid in s.customers:
			var cm: Dictionary = s.customers[cid]
			if cm.is_regular and int(cm.missed_habit_days) >= 2 and float(cm.affinity.get(m.id, 0.0)) >= 15:
				cands.append({"w": 1.0, "c": _make_regular(m.id, cid)})
				break
		if int(m.days_worked) >= 6 and rng.randf() < 0.04:
			cands.append({"w": 0.5, "c": _make_homesick(m.id)})
	if cands.is_empty() or rng.randf() > 0.7:
		return notes
	var total := 0.0
	for c in cands:
		total += float(c.w)
	var pick := rng.randf() * total
	for c in cands:
		pick -= float(c.w)
		if pick <= 0.0:
			var con: Dictionary = c.c
			con.day = int(s.day)
			con.age = 0
			con.revealed = false
			s.maids[con.maid].concern = con
			St.debug(s, "concern %s for %s (from %s)" % [con.type, con.maid, con.get("source", "")])
			break
	return notes

static func _wanted_role(m: Dictionary) -> String:
	var map := {"reception": "reception", "cooking": "kitchen", "floor": "floor", "performance": "stage"}
	var best := ""
	var bv := 25.0
	for k in map:
		if map[k] == m.role or map[k] == m.get("preferred_role", ""):
			continue
		if float(m.exp.get(k, 0.0)) > bv:
			bv = float(m.exp[k])
			best = map[k]
	if best == "stage":
		return ""
	return best

static func _make_quarrel(a: String, b: String, r: Dictionary) -> Dictionary:
	var na := name_of(a)
	var nb := name_of(b)
	return {"type": "quarrel", "maid": a, "with": b, "source": "摩擦 %d" % int(r.friction),
		"sign": "%s和%s今天幾乎沒說話，擦身而過時都別開了視線。" % [na, nb],
		"confide": "……%s總是把東西放得亂七八糟，還說是我太計較。我也知道自己講話很衝啦。" % nb,
		"leisure": "一個人待在角落", "line": "……哼。",
		"effect": "avoid"}

static func _make_doubt(a: String) -> Dictionary:
	return {"type": "self_doubt", "maid": a, "source": "連續失誤",
		"sign": "%s今天一直盯著托盤，動作也變得小心翼翼。" % name_of(a),
		"confide": "我是不是……拖累大家了？昨天又出錯了。",
		"leisure": "對著托盤練習", "line": "這次一定要拿穩……",
		"effect": "slow"}

static func _make_fatigue(a: String) -> Dictionary:
	return {"type": "hidden_fatigue", "maid": a, "source": "連續疲勞",
		"sign": "%s打烊後一直揉著肩膀，被問到時卻說「沒事」。" % name_of(a),
		"confide": "……其實這幾天腰很痛。但大家都很忙，我不想說。",
		"leisure": "偷偷揉肩膀", "line": "（輕輕嘆氣）",
		"effect": "slow"}

static func _make_role(a: String, role: String) -> Dictionary:
	return {"type": "wants_role", "maid": a, "role": role, "source": "累積了%s經驗" % Data.ROLE_NAMES[role],
		"sign": "%s空檔時一直往%s那邊看。" % [name_of(a), {"kitchen": "廚房", "reception": "門口", "floor": "外場"}[role]],
		"confide": "那個……我可以試試看%s的工作嗎？最近幫忙的時候，覺得好像很有趣。" % Data.ROLE_NAMES[role],
		"leisure": "偷看%s的工作" % Data.ROLE_NAMES[role], "line": "原來是這樣做的啊……",
		"effect": "watch"}

static func _make_regular(a: String, cid: String) -> Dictionary:
	var cn := name_of(cid)
	return {"type": "regular_worry", "maid": a, "cust": cid, "source": "%s連續沒來" % cn,
		"sign": "%s好幾次看向門口，像是在等誰。" % name_of(a),
		"confide": "%s已經好幾天沒來了……是不是我們哪裡做得不好？" % cn,
		"leisure": "望著門口", "line": "今天會來嗎……",
		"effect": "watch_door"}

static func _make_homesick(a: String) -> Dictionary:
	return {"type": "homesick", "maid": a, "source": "家裡的事",
		"sign": "%s休息時一直看著手機，好像在等誰的訊息。" % name_of(a),
		"confide": "老家的奶奶住院了……我應該回去看看，可是店裡這麼忙。",
		"leisure": "看著手機發呆", "line": "……",
		"effect": "slow"}

## Options the manager has for a concern. "ask" requires chatting at the cafe (uses an action point) first.
static func options(s: Dictionary, mid: String) -> Array:
	var c: Dictionary = s.maids[mid].concern
	if c.is_empty():
		return []
	var out := []
	match c.type:
		"quarrel":
			out.append({"id": "mediate", "label": "找兩人一起談談"})
			out.append({"id": "separate", "label": "暫時把兩人排在不同區域"})
		"self_doubt":
			out.append({"id": "encourage", "label": "鼓勵她"})
			out.append({"id": "mentor", "label": "請前輩帶她練習"})
		"hidden_fatigue":
			out.append({"id": "dayoff", "label": "讓她明天休假"})
			out.append({"id": "support", "label": "明天讓她做支援就好"})
		"wants_role":
			out.append({"id": "try_role", "label": "明天讓她試試看"})
			out.append({"id": "later", "label": "「等店裡穩定一點再說」"})
		"regular_worry":
			out.append({"id": "letter", "label": "請秋子阿姨幫忙傳話"})
			out.append({"id": "reassure", "label": "「他一定只是有事」"})
		"homesick":
			out.append({"id": "go_home", "label": "讓她休假回老家"})
			out.append({"id": "listen", "label": "陪她聊聊"})
	out.append({"id": "ignore", "label": "先觀察就好"})
	return out

## Apply the manager's decision. Returns a description of what happened.
static func resolve(s: Dictionary, mid: String, opt: String) -> String:
	var m: Dictionary = s.maids[mid]
	var c: Dictionary = m.concern
	if c.is_empty():
		return ""
	var n := name_of(mid)
	var knows: bool = c.get("revealed", false)
	var out := ""
	if opt == "ignore":
		c.ignored = true
		return "妳決定先不插手，看看%s會怎麼做。" % n
	match c.type:
		"quarrel":
			var o: String = c.with
			var on := name_of(o)
			if opt == "mediate":
				if knows or float(St.rel(s, mid, o).friction) < 55:
					St.rel_change(s, mid, o, "friction", -22, "店長居中調解")
					St.rel_change(s, mid, o, "trust", 6, "把話說開了")
					St.rel_share(s, mid, o, "被店長叫去一起談，最後兩個人都笑了")
					m.mood = St.clampf100(float(m.mood) + 6)
					out = "%s和%s把話說開了。「……抱歉，我也有不對。」（摩擦大幅下降）" % [n, on]
				else:
					St.rel_change(s, mid, o, "friction", -6, "店長調解（不了解原因）")
					m.mood = St.clampf100(float(m.mood) - 4)
					out = "談話有點尷尬。妳還不知道問題出在哪……（摩擦小幅下降，也許該先私下聽聽她的想法）"
			else:
				m.flags["separate_from"] = o
				m.flags["separate_days"] = 3
				St.rel_change(s, mid, o, "friction", -4, "暫時分開工作")
				out = "接下來三天，%s和%s會盡量待在不同區域。問題沒有解決，但比較不會起衝突。" % [n, on]
		"self_doubt":
			if opt == "encourage":
				m.mood = St.clampf100(float(m.mood) + (14 if knows else 8))
				m.flags["manager_trust"] = float(m.flags.get("manager_trust", 30.0)) + 5
				out = "%s小聲地說：「……我會再努力看看。」" % n
			else:
				var mentor := _best_at(s, mid, "floor")
				if mentor != "":
					St.rel_change(s, mid, mentor, "trust", 10, "前輩帶著練習")
					St.rel_change(s, mid, mentor, "close", 6, "一起練習到很晚")
					St.rel_share(s, mid, mentor, "打烊後一起練習端托盤")
					m.skills.floor = minf(float(Data.MAIDS[mid].caps.floor), float(m.skills.floor) + 3)
					m.mood = St.clampf100(float(m.mood) + 6)
					m.habits["help"] = minf(100.0, float(m.habits.get("help", 0)) + 6)
					out = "%s陪%s練到很晚。（外場 +3，兩人的信任提升）" % [name_of(mentor), n]
				else:
					m.mood = St.clampf100(float(m.mood) + 6)
					out = "妳陪她練習了一會兒。"
		"hidden_fatigue":
			if opt == "dayoff":
				m.day_off_tomorrow = true
				out = "%s愣了一下：「……被發現了啊。謝謝。」明天她會休假。" % n
			else:
				m.flags["support_tomorrow"] = true
				m.fatigue = St.clampf100(float(m.fatigue) - 10)
				out = "明天%s會在支援位置，不用一直跑來跑去。" % n
		"wants_role":
			if opt == "try_role":
				m.preferred_role = c.role
				m.flags["role_tomorrow"] = c.role
				m.mood = St.clampf100(float(m.mood) + 10)
				out = "%s眼睛一亮：「真的嗎！」明天她會試著擔任%s。" % [n, Data.ROLE_NAMES[c.role]]
			else:
				m.mood = St.clampf100(float(m.mood) - 3)
				m.preferred_role = c.role
				out = "%s點點頭，但看起來有點失落。她還是會偷偷學。" % n
		"regular_worry":
			var cid: String = c.cust
			if opt == "letter":
				s.flags["invite_" + cid] = true
				out = "秋子阿姨說會幫忙問問%s。說不定明天就會出現。" % name_of(cid)
			else:
				m.mood = St.clampf100(float(m.mood) + 3)
				out = "%s勉強笑了笑。" % n
		"homesick":
			if opt == "go_home":
				m.day_off_tomorrow = true
				m.flags["homesick_trip"] = true
				m.flags["manager_trust"] = float(m.flags.get("manager_trust", 30.0)) + 10
				out = "%s深深鞠了一躬。明天她會回老家一趟。" % n
			else:
				m.mood = St.clampf100(float(m.mood) + (10 if knows else 5))
				out = "妳陪%s聊了很久。她說心裡輕鬆多了。" % n
	m.concern = {}
	m.concern_cooldown = 3
	return out

## What happens to a concern nobody addresses. Most resolve or escalate by themselves.
static func _tick_ignored(s: Dictionary, m: Dictionary, c: Dictionary, rng: RandomNumberGenerator) -> String:
	var n := name_of(m.id)
	var age := int(c.age)
	match c.type:
		"quarrel":
			var o: String = c.with
			var r := St.rel(s, m.id, o)
			if float(r.synergy) >= 30 and rng.randf() < 0.5:
				St.rel_change(s, m.id, o, "friction", -15, "一起撐過忙碌後自己和好")
				St.rel_share(s, m.id, o, "吵完架隔天，一起撐過了最忙的時段")
				_clear(m)
				return "💞 %s和%s自己和好了。一起撐過忙碌的時段，好像就說開了。" % [n, name_of(o)]
			if age >= 3:
				St.rel_change(s, m.id, o, "friction", 8, "摩擦沒有人處理")
				m.mood = St.clampf100(float(m.mood) - 5)
				_clear(m)
				return "%s和%s之間的氣氛更僵了。" % [n, name_of(o)]
		"self_doubt":
			if float(m.habits.get("stay_late", 0)) >= 25:
				m.skills.floor = minf(float(Data.MAIDS[m.id].caps.floor), float(m.skills.floor) + 1)
				m.fatigue = St.clampf100(float(m.fatigue) + 8)
				if age >= 2:
					_clear(m)
					return "%s每天都一個人留下來練習。她靠自己找回了一點信心。" % n
			elif age >= 2:
				m.mood = St.clampf100(float(m.mood) - 8)
				_clear(m)
				return "%s越來越沒精神了……" % n
		"hidden_fatigue":
			m.fatigue = St.clampf100(float(m.fatigue) + 6)
			if age >= 2:
				_clear(m)
				return "%s還是硬撐著。（疲勞上升）" % n
		"wants_role":
			if age >= 3:
				m.preferred_role = c.role
				m.mood = St.clampf100(float(m.mood) - 4)
				_clear(m)
				return "%s沒再提起想換工作的事，但空檔時還是常往那邊看。" % n
		"regular_worry":
			var cid: String = c.cust
			if int(s.customers[cid].missed_habit_days) == 0:
				_clear(m)
				return "%s回來了，%s鬆了一口氣。" % [name_of(cid), n]
			if age >= 3:
				_clear(m)
		"homesick":
			m.mood = St.clampf100(float(m.mood) - 4)
			if age >= 3:
				_clear(m)
				return "%s接到老家的電話，奶奶出院了。她一整天都在笑。" % n
	return ""

static func _clear(m: Dictionary) -> void:
	m.concern = {}
	m.concern_cooldown = 4

static func _best_at(s: Dictionary, exclude: String, skill: String) -> String:
	var best := ""
	var bv := -1.0
	for o in St.active_maids(s):
		if o.id == exclude:
			continue
		if float(o.skills[skill]) > bv:
			bv = float(o.skills[skill])
			best = o.id
	return best
