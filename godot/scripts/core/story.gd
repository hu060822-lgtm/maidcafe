## Character-raising story layer: the cafe's main chapters with goals, heart ranks and heart episodes for
## each maid, training before opening, and maid profiles that open up as trust grows.
## Pure static functions over the state dictionary (testable headless). Content: story_data.gd.
##
## State: s.story = {chapter, started, ended, served_total, days_open, trained_total,
##                   heart: {maid: highest rank already played}, trained_today: {maid: day}, train_day, train_used}
extends RefCounted

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")
const SD = preload("res://scripts/core/story_data.gd")
const LD = preload("res://scripts/core/life_data.gd")

static func new_story() -> Dictionary:
	return {"chapter": 0, "started": false, "ended": false, "served_total": 0, "days_open": 0, "trained_total": 0,
		"heart": {}, "trained_today": {}, "train_day": -1, "train_used": 0}

static func st(s: Dictionary) -> Dictionary:
	if not s.has("story") or typeof(s.story) != TYPE_DICTIONARY:
		s.story = new_story()
	var fresh := new_story()
	for k in fresh:
		if not s.story.has(k):
			s.story[k] = fresh[k]
	return s.story

# ======================================================================== heart ranks
static func heart_rank(s: Dictionary, mid: String) -> int:
	var b := float(s.maids[mid].bond)
	var r := 1
	for i in SD.RANK_BOND.size():
		if b >= float(SD.RANK_BOND[i]):
			r = i + 1
	return r

## Progress to the next rank, 0..1 (1 at max rank).
static func heart_progress(s: Dictionary, mid: String) -> float:
	var r := heart_rank(s, mid)
	if r >= SD.RANK_BOND.size():
		return 1.0
	var lo := float(SD.RANK_BOND[r - 1])
	var hi := float(SD.RANK_BOND[r])
	return clampf((float(s.maids[mid].bond) - lo) / (hi - lo), 0.0, 1.0)

static func rank_name(r: int) -> String:
	return SD.RANK_NAMES[clampi(r, 1, SD.RANK_NAMES.size()) - 1]

## Profile rows that are visible at her current rank: [[label, text, unlocked]]
static func profile(s: Dictionary, mid: String) -> Array:
	var p: Dictionary = SD.PROFILES.get(mid, {})
	var r := heart_rank(s, mid)
	var out := []
	out.append(["座右銘", p.get("motto", "？"), true])
	out.append(["喜歡的東西", p.get("food", "？"), true])
	out.append(["拿手", p.get("good", "？"), true])
	out.append(["不擅長", p.get("weak", "？"), true])
	out.append(["夢想", p.get("dream", "？"), r >= 3])
	out.append(["街坊的稱呼", p.get("title", "？"), r >= 4])
	out.append(["小秘密", p.get("secret", "？"), r >= 5])
	return out

static func unlock_hint(r: int) -> String:
	return "羈絆 Lv%d 解鎖" % r

# ======================================================================== chapter goals
static func chapter(s: Dictionary) -> Dictionary:
	var i := int(st(s).chapter)
	return SD.CHAPTERS[i] if i < SD.CHAPTERS.size() else {}

static func _count_regulars(s: Dictionary) -> int:
	var n := 0
	for cid in s.customers:
		if s.customers[cid].get("is_regular", false):
			n += 1
	return n

static func _arcs_done(s: Dictionary) -> int:
	var n := 0
	for mid in s.staff:
		var m: Dictionary = s.maids[mid]
		var arc: Array = _life_arc(mid)
		if not arc.is_empty() and int(m.get("arc_stage", 0)) >= arc.size():
			n += 1
	return n

static func _life_arc(mid: String) -> Array:
	return LD.MAID_LIFE.get(mid, {}).get("arc", [])

static func _avg_bond(s: Dictionary) -> float:
	var ms := St.active_maids(s)
	if ms.is_empty():
		return 0.0
	var t := 0.0
	for m in ms:
		t += float(m.bond)
	return t / ms.size()

## Current value and target for one goal: {value, target, done, label}
static func goal_status(s: Dictionary, g: Dictionary) -> Dictionary:
	var stt := st(s)
	var v := 0.0
	var target := 0.0
	match g.kind:
		"days_open":
			v = stt.days_open
			target = g.n
		"served_total":
			v = stt.served_total
			target = g.n
		"regulars":
			v = _count_regulars(s)
			target = g.n
		"popularity":
			v = s.popularity
			target = g.n
		"reputation":
			v = s.reputation
			target = g.n
		"money":
			v = s.money
			target = g.n
		"staff":
			v = St.active_maids(s).size()
			target = g.n
		"partners":
			v = s.partners.size()
			target = g.n
		"signature":
			for id in s.unlocked_dishes:
				if Data.DISHES.has(id) and Data.DISHES[id].get("signature", false):
					v += 1
			target = g.n
		"resident_aff":
			for rid in s.street.residents:
				if float(s.street.residents[rid].aff) >= float(g.n[1]):
					v += 1
			target = g.n[0]
		"arcs_done":
			v = _arcs_done(s)
			target = g.n
		"avg_bond":
			v = _avg_bond(s)
			target = g.n
		"heart_rank":
			for m in St.active_maids(s):
				if heart_rank(s, m.id) >= int(g.n[1]):
					v += 1
			target = g.n[0]
		"trained":
			v = stt.trained_total
			target = g.n
	return {"value": float(v), "target": float(target), "done": float(v) >= float(target), "label": g.label}

static func goals(s: Dictionary) -> Array:
	var ch := chapter(s)
	var out := []
	for g in ch.get("goals", []):
		out.append(goal_status(s, g))
	return out

static func chapter_complete(s: Dictionary) -> bool:
	var gs := goals(s)
	if gs.is_empty():
		return false
	for g in gs:
		if not g.done:
			return false
	return true

## The chapter intro has to be shown (start of game, or the morning after a chapter ended).
static func needs_intro(s: Dictionary) -> bool:
	var stt := st(s)
	return not stt.started and not stt.ended and int(stt.chapter) < SD.CHAPTERS.size()

static func intro_scene(s: Dictionary) -> Dictionary:
	var ch := chapter(s)
	if ch.is_empty():
		return {}
	var lines: Array = ch.intro.duplicate()
	lines.append("")
	lines.append("[b]本章目標[/b]")
	for g in ch.goals:
		lines.append("🎀 " + g.label)
	return {"id": "story_intro", "title": ch.title, "who": ch.get("who", ""), "lines": lines, "choices": ["開始吧！"]}

static func begin_chapter(s: Dictionary) -> void:
	st(s).started = true
	St.debug(s, "story: chapter %d started" % int(s.story.chapter))

# ======================================================================== night hook
## Called after settlement every night: count progress, queue chapter completion and heart episodes.
static func after_settle(s: Dictionary, served: int, opened: bool) -> void:
	var stt := st(s)
	if opened:
		stt.days_open = int(stt.days_open) + 1
		stt.served_total = int(stt.served_total) + served
	if stt.started and not stt.ended and chapter_complete(s):
		_queue(s, "story:done|%d" % int(stt.chapter))
	# at most one heart episode per night, lowest rank first
	var best := ""
	var best_rank := 99
	for m in St.active_maids(s):
		var r := heart_rank(s, m.id)
		var seen := int(stt.heart.get(m.id, 1))
		if r > seen:
			var nxt := seen + 1
			if not SD.HEART.get(m.id, {}).has(nxt):
				stt.heart[m.id] = r      # no episode for this rank (e.g. Lv5): just record it
				continue
			if nxt < best_rank:
				best_rank = nxt
				best = m.id
	if best != "":
		_queue(s, "heart:%s|%d" % [best, best_rank])

static func _queue(s: Dictionary, id: String) -> void:
	if not id in s.pending_events:
		s.pending_events.append(id)

# ======================================================================== scenes (played as night events)
static func build(s: Dictionary, id: String) -> Dictionary:
	var parts := id.split(":")
	var arg: String = parts[1] if parts.size() > 1 else ""
	if parts[0] == "story":
		var p := arg.split("|")
		var i := int(p[1])
		if i >= SD.CHAPTERS.size() or i != int(st(s).chapter):
			return {}
		var ch: Dictionary = SD.CHAPTERS[i]
		var lines: Array = ch.outro.duplicate()
		lines.append("")
		lines.append("[b]🎉 %s 完成！[/b]" % ch.title)
		return {"id": id, "title": ch.title, "who": ch.get("who", ""), "lines": lines, "choices": ["（繼續）"]}
	if parts[0] == "heart":
		var p := arg.split("|")
		var mid: String = p[0]
		var r := int(p[1])
		var ep: Dictionary = SD.HEART.get(mid, {}).get(r, {})
		if ep.is_empty() or not mid in s.staff:
			return {}
		var lines: Array = ep.lines.duplicate()
		return {"id": id, "title": "💗 %s．%s" % [Data.MAIDS[mid].name, ep.title], "who": mid, "lines": lines,
			"choices": ep.choices.map(func(c): return c.label), "heart": r}
	return {}

static func resolve(s: Dictionary, id: String, idx: int) -> String:
	s.pending_events.erase(id)
	var parts := id.split(":")
	var arg: String = parts[1] if parts.size() > 1 else ""
	if parts[0] == "story":
		return _finish_chapter(s, int(arg.split("|")[1]))
	if parts[0] == "heart":
		var p := arg.split("|")
		return _resolve_heart(s, p[0], int(p[1]), idx)
	return ""

static func _finish_chapter(s: Dictionary, i: int) -> String:
	var stt := st(s)
	if i != int(stt.chapter) or i >= SD.CHAPTERS.size():
		return ""
	var ch: Dictionary = SD.CHAPTERS[i]
	var rw: Dictionary = ch.get("reward", {})
	var out := []
	if rw.has("money"):
		s.money = float(s.money) + float(rw.money)
		out.append("💰 商店街公會的獎勵 ¥%d" % int(rw.money))
	if rw.has("popularity"):
		s.popularity = minf(100.0, float(s.popularity) + float(rw.popularity))
		out.append("⭐ 人氣 +%d" % int(rw.popularity))
	if rw.has("dish") and not rw.dish in s.unlocked_dishes:
		s.unlocked_dishes.append(rw.dish)
		out.append("🍽 新料理「%s」解鎖！" % Data.DISHES[rw.dish].name)
	if rw.has("album"):
		St.add_album(s, rw.album[0], rw.album[1], s.staff.duplicate(), "pending", "story_%d" % i, "cafe")
		out.append("📷 回憶相簿多了一張照片")
	else:
		St.add_album(s, ch.title, ch.outro[ch.outro.size() - 1], s.staff.duplicate(), "", "story_%d" % i, "cafe")
	for m in St.active_maids(s):
		m.mood = St.clampf100(float(m.mood) + 6.0)
	stt.chapter = i + 1
	stt.started = false
	if rw.get("ending", false) or int(stt.chapter) >= SD.CHAPTERS.size():
		stt.ended = true
		s.flags["story_ending"] = int(s.day)
		out.append("\n[b]感謝遊玩主線故事！[/b] 店的日子還會繼續下去——女僕們的故事也是。")
	else:
		out.append("\n明天早上，新的一章開始。")
	return "\n".join(out)

static func _resolve_heart(s: Dictionary, mid: String, r: int, idx: int) -> String:
	var stt := st(s)
	var ep: Dictionary = SD.HEART.get(mid, {}).get(r, {})
	stt.heart[mid] = maxi(int(stt.heart.get(mid, 1)), r)
	if ep.is_empty():
		return ""
	var ch: Dictionary = ep.choices[clampi(idx, 0, ep.choices.size() - 1)]
	var fx: Dictionary = ch.fx
	var m: Dictionary = s.maids[mid]
	var out := ["💗 和%s的羈絆來到 Lv%d「%s」" % [Data.MAIDS[mid].name, r, rank_name(r)]]
	if fx.has("bond"):
		m.bond = St.clampf100(float(m.bond) + float(fx.bond))
	if fx.has("mood"):
		m.mood = St.clampf100(float(m.mood) + float(fx.mood))
		if float(fx.mood) > 0:
			out.append("心情變好了")
	if fx.has("skill"):
		out.append(_add_skill(m, fx.skill[0], int(fx.skill[1])))
	if fx.has("memory"):
		St.remember(s, mid, fx.memory[0], "heart", [], float(fx.memory[1]))
	if fx.has("album"):
		St.add_album(s, fx.album[0], fx.album[1], [mid], "pending", "heart_%s_%d" % [mid, r], "maid")
		out.append("📷 回憶相簿多了一張照片")
	var unlocked := []
	if r == 3:
		unlocked.append("夢想")
	if r == 4:
		unlocked.append("街坊的稱呼")
	if not unlocked.is_empty():
		out.append("📒 女僕檔案解鎖：" + "、".join(unlocked))
	return "\n".join(out)

static func _add_skill(m: Dictionary, k: String, pts: int) -> String:
	var cap := int(Data.MAIDS[m.id].caps[k])
	var before := int(m.skills[k])
	m.skills[k] = mini(cap, before + pts)
	var gain := int(m.skills[k]) - before
	return "%s %+d" % [Data.SKILL_NAMES[k], gain] if gain > 0 else "%s 已經到極限了" % Data.SKILL_NAMES[k]

# ======================================================================== training
static func _train_reset(s: Dictionary) -> void:
	var stt := st(s)
	if int(stt.train_day) != int(s.day):
		stt.train_day = int(s.day)
		stt.train_used = 0

static func train_left(s: Dictionary) -> int:
	_train_reset(s)
	return SD.TRAIN_PER_DAY - int(s.story.train_used)

## "" if she can train now, otherwise the reason.
static func can_train(s: Dictionary, mid: String) -> String:
	if not mid in s.staff or s.maids[mid].quit:
		return "她不在店裡。"
	if not s.phase in ["explore", "prepare"]:
		return "開店前才能特訓。"
	if train_left(s) <= 0:
		return "今天店長已經沒有時間了。"
	if int(st(s).trained_today.get(mid, -1)) == int(s.day):
		return "她今天已經練習過了。"
	if float(s.maids[mid].fatigue) >= 75.0:
		return "她太累了，讓她休息吧。"
	return ""

## Train one skill with her. Returns {ok, text}.
static func train(s: Dictionary, mid: String, skill: String) -> Dictionary:
	var why := can_train(s, mid)
	if why != "":
		return {"ok": false, "text": why}
	var stt := st(s)
	var m: Dictionary = s.maids[mid]
	var def: Dictionary = Data.MAIDS[mid]
	var pts := SD.TRAIN_POINTS
	var focus: Array = SD.GROWTH_FOCUS.get(def.get("growth", ""), [])
	var liked := skill in focus
	if liked:
		pts += 1
	var line: String = SD.TRAINING[skill].lines[(int(s.day) + mid.length()) % SD.TRAINING[skill].lines.size()]
	var out := ["%s %s和%s%s" % [SD.TRAINING[skill].icon, SD.TRAINING[skill].name, def.name, "：" + line]]
	out.append(_add_skill(m, skill, pts))
	m.fatigue = St.clampf100(float(m.fatigue) + SD.TRAIN_FATIGUE)
	m.bond = St.clampf100(float(m.bond) + 1.5)
	m.mood = St.clampf100(float(m.mood) + (3.0 if liked else -1.0))
	out.append("她看起來很投入！" if liked else "有點辛苦，但她很努力。")
	stt.train_used = int(stt.train_used) + 1
	stt.trained_today[mid] = int(s.day)
	stt.trained_total = int(stt.trained_total) + 1
	return {"ok": true, "text": "\n".join(out)}
