class_name NpcArtCatalog
extends RefCounted
## Picks portraits for unnamed / crowd customers from pre-approved archetype looks.
##
## Rules (see godot/art/npc/taxonomy.json):
## * A look is a pre-baked body image. Heads and bodies are never assembled at
##   runtime; the only layering is the archetype's own face patches, which are
##   drawn and checked to fit all of that archetype's looks.
## * Looks that break a compatibility rule are rejected (also by the validator).
## * The same look is never on screen twice, and recently used looks are avoided.

var catalog: ArtCatalog
var _recent: Array[String] = []   ## "archetype/look" keys, newest last


func _init(cat: ArtCatalog = null) -> void:
	catalog = cat if cat != null else ArtCatalog.shared()


func taxonomy() -> Dictionary:
	return catalog.taxonomy


static func look_key(archetype_id: String, look_id: String) -> String:
	return archetype_id + "/" + look_id


## Attributes of a look merged with its archetype (age_look, body_type, ...).
func look_attributes(archetype: Dictionary, look: Dictionary) -> Dictionary:
	return {
		"age_look": str(archetype.get("age_look", "")),
		"body_type": str(archetype.get("body_type", "")),
		"hair_style": str(look.get("hair_style", "")),
		"hair_color": str(look.get("hair_color", "")),
		"outfit": str(look.get("outfit", "")),
		"accessory": look.get("accessories", []),
	}


## Returns a list of human-readable problems; empty = compatible.
func check_look(archetype: Dictionary, look: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var dims: Dictionary = taxonomy().get("dimensions", {})
	var attrs := look_attributes(archetype, look)
	for dim in ["age_look", "body_type", "hair_style", "hair_color", "outfit"]:
		if not dims.get(dim, {}).has(attrs[dim]):
			problems.append("%s '%s' is not in the taxonomy" % [dim, attrs[dim]])
	for acc in attrs["accessory"]:
		if not dims.get("accessory", {}).has(str(acc)):
			problems.append("accessory '%s' is not in the taxonomy" % acc)
	for rule in taxonomy().get("compatibility", {}).get("rules", []):
		if not _matches(attrs, rule.get("if", {})):
			continue
		var req: Dictionary = rule.get("require", {})
		for dim in req:
			if not _has_any(attrs, dim, req[dim]):
				problems.append("rule %s: requires %s in %s" % [rule.get("id", "?"), dim, req[dim]])
		var forb: Dictionary = rule.get("forbid", {})
		for dim in forb:
			if _has_any(attrs, dim, forb[dim]):
				problems.append("rule %s: forbids %s %s" % [rule.get("id", "?"), dim, forb[dim]])
	return problems


func _matches(attrs: Dictionary, cond: Dictionary) -> bool:
	for dim in cond:
		if not _has_any(attrs, dim, cond[dim]):
			return false
	return true


func _has_any(attrs: Dictionary, dim: String, values: Array) -> bool:
	var v = attrs.get(dim, "")
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			if values.has(str(x)):
				return true
		return false
	return values.has(str(v))


## Number of visible attributes in which two looks differ.
func difference(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	for attr in taxonomy().get("distinctiveness", {}).get("visible_attributes", ["hair_style", "hair_color", "outfit", "accessories"]):
		var va = a.get(attr, "")
		var vb = b.get(attr, "")
		if typeof(va) == TYPE_ARRAY:
			va = ",".join(PackedStringArray(va.map(func(x): return str(x))))
			vb = ",".join(PackedStringArray((vb if typeof(vb) == TYPE_ARRAY else []).map(func(x): return str(x))))
		if str(va) != str(vb):
			n += 1
	return n


## Pairs of looks in one archetype that are too similar.
func similar_pairs(archetype: Dictionary) -> Array:
	var min_diff := int(taxonomy().get("distinctiveness", {}).get("min_differences", 2))
	var looks: Array = archetype.get("looks", [])
	var out: Array = []
	for i in looks.size():
		for j in range(i + 1, looks.size()):
			if difference(looks[i], looks[j]) < min_diff:
				out.append([str(looks[i].get("id", "")), str(looks[j].get("id", ""))])
	return out


## All looks that may be shown: compatible, and (unless require_art=false)
## with a usable body image registered in the manifest.
func available_looks(require_art := true) -> Array:
	var out: Array = []
	for aid in catalog.archetypes:
		var a: Dictionary = catalog.archetypes[aid]
		for look in a.get("looks", []):
			if not check_look(a, look).is_empty():
				continue
			if require_art:
				var body_id := catalog.format_filename("portrait_body", {"owner": aid, "pose": str(a.get("pose", "stand")), "outfit": str(look.get("id", ""))}).get_basename()
				if catalog.asset_path(body_id) == "":
					continue
			out.append({"archetype": aid, "look": str(look.get("id", "")), "data": look, "archetype_data": a})
	return out


## Choose a look for a crowd customer.
## criteria: {customer_type, personality, age_look} (all optional)
## on_screen: look keys ("archetype/look") already visible.
## Returns {} if nothing fits (the caller then shows a silhouette).
func pick_look(criteria: Dictionary, on_screen: Array, rng: RandomNumberGenerator, require_art := true) -> Dictionary:
	var pool: Array = []
	for c in available_looks(require_art):
		var a: Dictionary = c["archetype_data"]
		if criteria.has("customer_type") and not a.get("customer_types", []).has(criteria["customer_type"]):
			continue
		if criteria.has("personality") and not a.get("personalities", []).has(criteria["personality"]):
			continue
		if criteria.has("age_look") and str(a.get("age_look", "")) != str(criteria["age_look"]):
			continue
		var key := look_key(c["archetype"], c["look"])
		if on_screen.has(key):
			continue
		pool.append(c)
	if pool.is_empty():
		return {}
	var fresh := pool.filter(func(c): return not _recent.has(look_key(c["archetype"], c["look"])))
	var choose_from := fresh if not fresh.is_empty() else pool
	var pick: Dictionary = choose_from[rng.randi_range(0, choose_from.size() - 1)]
	var k := look_key(pick["archetype"], pick["look"])
	_recent.erase(k)
	_recent.append(k)
	var hist := int(taxonomy().get("distinctiveness", {}).get("recent_history", 4))
	while _recent.size() > hist:
		_recent.pop_front()
	return {"archetype": pick["archetype"], "look": pick["look"], "key": k}
