class_name ArtCatalog
extends RefCounted
## Data-driven registry of every art asset in the game.
##
## Loads art_spec.json, the character index + bibles, the asset manifest and the
## NPC archetypes from an art root (default res://art/). It never loads
## textures itself; it only answers "which file should be shown for
## character X with pose P / outfit O / expression E", applying the fallback
## rules from the spec. All game content lives in JSON, so adding characters
## needs no code changes.

const DEFAULT_ROOT := "res://art/"
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg"]

var root: String = DEFAULT_ROOT
var spec: Dictionary = {}
var characters: Dictionary = {}      ## character id -> bible
var character_order: Array[String] = []
var archetypes: Dictionary = {}      ## archetype id -> archetype dict
var taxonomy: Dictionary = {}
var manifest_list: Array = []        ## raw manifest entries, in file order
var assets: Dictionary = {}          ## asset id -> entry (first wins)
var load_errors: PackedStringArray = []
## When true, assets with status "draft" are shown. Release builds can turn it off.
var allow_draft := true

var _naming_regex: Dictionary = {}   ## kind -> RegEx
var _exists_cache: Dictionary = {}

static var _shared: ArtCatalog = null


## The game-wide catalog, loaded lazily from res://art/.
static func shared() -> ArtCatalog:
	if _shared == null:
		_shared = ArtCatalog.new()
		_shared.load_from(DEFAULT_ROOT)
	return _shared


## Replace the shared catalog (tests, mods, or after hot-reloading data).
static func set_shared(catalog: ArtCatalog) -> void:
	_shared = catalog


# ---------------------------------------------------------------- loading

func load_from(art_root: String) -> bool:
	root = art_root if art_root.ends_with("/") else art_root + "/"
	spec = {}
	characters = {}
	character_order = []
	archetypes = {}
	taxonomy = {}
	manifest_list = []
	assets = {}
	load_errors = PackedStringArray()
	_naming_regex = {}
	_exists_cache = {}

	spec = read_json(root + "art_spec.json")
	if spec.is_empty():
		load_errors.append("art_spec.json missing or invalid")
		return false
	_build_naming_regex()

	var index := read_json(root + "characters/index.json")
	for entry in index.get("characters", []):
		var cid := str(entry.get("id", ""))
		var bible := read_json(root + str(entry.get("bible", "")))
		if bible.is_empty():
			load_errors.append("bible missing for character '%s'" % cid)
			continue
		if characters.has(cid):
			load_errors.append("duplicate character id '%s' in index" % cid)
			continue
		characters[cid] = bible
		character_order.append(cid)

	taxonomy = read_json(root + "npc/taxonomy.json")
	var arch := read_json(root + "npc/archetypes.json")
	for a in arch.get("archetypes", []):
		archetypes[str(a.get("id", ""))] = a

	var manifest := read_json(root + "manifest.json")
	manifest_list = manifest.get("assets", [])
	for e in manifest_list:
		var aid := str(e.get("id", ""))
		if not assets.has(aid):
			assets[aid] = e
	return load_errors.is_empty()


static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("ArtCatalog: invalid JSON in %s" % path)
		return {}
	return data


# ---------------------------------------------------------------- naming

func _build_naming_regex() -> void:
	var seg := "[a-z0-9]+(?:-[a-z0-9]+)*"
	var naming: Dictionary = spec.get("naming", {})
	for kind in naming:
		if str(kind).begins_with("_"):
			continue
		var pattern := str(naming[kind].get("pattern", ""))
		var rx_src := "^" + pattern.replace(".", "\\.")
		var field_rx := RegEx.create_from_string("\\{([a-z_]+)\\}")
		for m in field_rx.search_all(pattern):
			rx_src = rx_src.replace(m.get_string(0), "(?<%s>%s)" % [m.get_string(1), seg])
		rx_src += "$"
		_naming_regex[kind] = RegEx.create_from_string(rx_src)


func is_valid_segment(s: String) -> bool:
	var rx := RegEx.create_from_string(str(spec.get("id_rules", {}).get("segment_pattern", "^[a-z0-9]+(-[a-z0-9]+)*$")))
	return rx.search(s) != null


func naming_kinds() -> Array:
	return _naming_regex.keys()


## Filename (no dir) for an asset kind, e.g. ("portrait_body", {owner, pose, outfit}).
func format_filename(kind: String, fields: Dictionary) -> String:
	var rule: Dictionary = spec.get("naming", {}).get(kind, {})
	return _fill(str(rule.get("pattern", "")), fields)


func format_dir(kind: String, fields: Dictionary) -> String:
	var rule: Dictionary = spec.get("naming", {}).get(kind, {})
	return _fill(str(rule.get("dir", "")), fields)


## Path relative to the art root.
func format_path(kind: String, fields: Dictionary) -> String:
	return format_dir(kind, fields) + "/" + format_filename(kind, fields)


func _fill(pattern: String, fields: Dictionary) -> String:
	var out := pattern
	for k in fields:
		out = out.replace("{%s}" % k, str(fields[k]))
	return out


## Parse a filename back into {kind, fields}. Empty dict if it matches no rule.
func parse_filename(filename: String) -> Dictionary:
	for kind in _naming_regex:
		var m: RegExMatch = _naming_regex[kind].search(filename)
		if m != null:
			var fields := {}
			for name in m.names:
				fields[name] = m.get_string(name)
			return {"kind": kind, "fields": fields}
	return {}


## Builds a manifest entry for an asset. Entry id = filename without extension.
func make_entry(kind: String, fields: Dictionary, status := "missing") -> Dictionary:
	var fname := format_filename(kind, fields)
	var e := {"id": fname.get_basename(), "kind": kind}
	for k in fields:
		e[k] = fields[k]
	e["path"] = format_path(kind, fields)
	e["status"] = status
	return e


# ---------------------------------------------------------------- characters

func has_character(id: String) -> bool:
	return characters.has(id)


func get_character(id: String) -> Dictionary:
	return characters.get(id, {})


func display_name(id: String) -> String:
	var b := get_character(id)
	if b.is_empty():
		return id
	return str(b.get("name", id))


## Art owner id used in filenames for a character (or the archetype id itself).
func owner_of(id: String) -> String:
	if characters.has(id):
		return str(characters[id].get("art", {}).get("owner", id))
	if archetypes.has(id):
		return id
	return ""


## The variant lists a character (or archetype) can show:
## {owner, expressions, poses, outfits, default:{pose,outfit,expression}, display}
func get_art_profile(id: String) -> Dictionary:
	if characters.has(id):
		var art: Dictionary = characters[id].get("art", {})
		var owner := str(art.get("owner", id))
		if archetypes.has(owner):
			# Character drawn with a shared archetype look.
			var p := _archetype_profile(archetypes[owner])
			var d: Dictionary = art.get("default", {})
			if d.has("outfit"):
				p["default"]["outfit"] = str(d["outfit"])
			p["display"] = art.get("display", p["display"])
			return p
		return {
			"owner": owner,
			"expressions": art.get("expressions", []),
			"poses": art.get("poses", []),
			"outfits": art.get("outfits", []),
			"default": _default_triplet(art.get("default", {}), art),
			"display": art.get("display", {"scale": 1.0, "y_offset": 0.0}),
		}
	if archetypes.has(id):
		return _archetype_profile(archetypes[id])
	return {}


func _archetype_profile(a: Dictionary) -> Dictionary:
	var looks: Array = []
	for l in a.get("looks", []):
		looks.append(str(l.get("id", "")))
	var pose := str(a.get("pose", "stand"))
	var exprs: Array = a.get("expressions", [])
	return {
		"owner": str(a.get("id", "")),
		"expressions": exprs,
		"poses": [pose],
		"outfits": looks,
		"default": {
			"pose": pose,
			"outfit": looks[0] if looks.size() > 0 else "default",
			"expression": str(spec.get("fallback", {}).get("expression", "neutral")),
		},
		"display": {"scale": 1.0, "y_offset": 0.0},
	}


func _default_triplet(d: Dictionary, art: Dictionary) -> Dictionary:
	var poses: Array = art.get("poses", [])
	var outfits: Array = art.get("outfits", [])
	return {
		"pose": str(d.get("pose", poses[0] if poses.size() > 0 else "stand")),
		"outfit": str(d.get("outfit", outfits[0] if outfits.size() > 0 else "default")),
		"expression": str(d.get("expression", spec.get("fallback", {}).get("expression", "neutral"))),
	}


# ---------------------------------------------------------------- assets

func usable_statuses() -> Array:
	return ["approved", "draft"] if allow_draft else ["approved"]


## Full resource path of an asset if it is registered, usable and on disk; else "".
func asset_path(asset_id: String) -> String:
	if not assets.has(asset_id):
		return ""
	var e: Dictionary = assets[asset_id]
	if not usable_statuses().has(str(e.get("status", ""))):
		return ""
	var full := root + str(e.get("path", ""))
	if not _file_exists(full):
		return ""
	return full


func _file_exists(path: String) -> bool:
	if not _exists_cache.has(path):
		_exists_cache[path] = FileAccess.file_exists(path)
	return _exists_cache[path]


func clear_cache() -> void:
	_exists_cache = {}


func _id(kind: String, fields: Dictionary) -> String:
	return format_filename(kind, fields).get_basename()


## Resolve which image layers to draw. Never fails: the worst case is
## {"silhouette": true}, which the view draws as a clearly marked placeholder.
##
## Returns {character, owner, known, pose, outfit, expression, layers:[paths],
##          silhouette, fallbacks:[strings], requested:{pose,outfit,expression}, display}
func resolve_portrait(character_id: String, pose := "", outfit := "", expression := "") -> Dictionary:
	var prof := get_art_profile(character_id)
	var res := {
		"character": character_id,
		"owner": "",
		"known": not prof.is_empty(),
		"pose": pose, "outfit": outfit, "expression": expression,
		"layers": [],
		"silhouette": false,
		"fallbacks": [],
		"requested": {"pose": pose, "outfit": outfit, "expression": expression},
		"display": {"scale": 1.0, "y_offset": 0.0},
	}
	if prof.is_empty():
		res["silhouette"] = true
		res["fallbacks"].append("unknown character '%s'" % character_id)
		return res

	var owner := str(prof["owner"])
	var d: Dictionary = prof["default"]
	var p := pose if pose != "" else str(d["pose"])
	var o := outfit if outfit != "" else str(d["outfit"])
	var e := expression if expression != "" else str(d["expression"])
	var de := str(d["expression"])
	res["owner"] = owner
	res["display"] = prof.get("display", res["display"])
	res["requested"] = {"pose": p, "outfit": o, "expression": e}

	var candidates: Array = []
	for c in [[p, o], [p, str(d["outfit"])], [str(d["pose"]), o], [str(d["pose"]), str(d["outfit"])]]:
		if not candidates.has(c):
			candidates.append(c)

	var layers: Array = []
	var got_e := e
	var got_p := p
	var got_o := o
	for c in candidates:
		var bp: String = c[0]
		var bo: String = c[1]
		var full := asset_path(_id("portrait_full", {"owner": owner, "pose": bp, "outfit": bo, "expression": e}))
		if full != "":
			layers = [full]
			got_p = bp; got_o = bo; got_e = e
			break
		var body := asset_path(_id("portrait_body", {"owner": owner, "pose": bp, "outfit": bo}))
		if body != "":
			layers = [body]
			got_p = bp; got_o = bo; got_e = e
			# The body layer carries the default (neutral) face; other
			# expressions are face patches drawn on top.
			var face := asset_path(_id("portrait_face", {"owner": owner, "pose": bp, "expression": e}))
			if face != "":
				layers.append(face)
			elif e != de:
				got_e = de
			break
		if e != de:
			var full_d := asset_path(_id("portrait_full", {"owner": owner, "pose": bp, "outfit": bo, "expression": de}))
			if full_d != "":
				layers = [full_d]
				got_p = bp; got_o = bo; got_e = de
				break

	if layers.is_empty():
		res["pose"] = p
		res["outfit"] = o
		res["expression"] = e
		res["silhouette"] = true
		res["fallbacks"].append("no image for %s (%s/%s/%s)" % [character_id, p, o, e])
		return res

	res["layers"] = layers
	res["pose"] = got_p
	res["outfit"] = got_o
	res["expression"] = got_e
	if got_p != p:
		res["fallbacks"].append("pose %s -> %s" % [p, got_p])
	if got_o != o:
		res["fallbacks"].append("outfit %s -> %s" % [o, got_o])
	if got_e != e:
		res["fallbacks"].append("expression %s -> %s" % [e, got_e])
	return res


# ---------------------------------------------------------------- requirements

## Every asset the bibles + spec say must exist, as manifest entries (status "missing").
func required_assets() -> Array:
	var out: Array = []
	for cid in character_order:
		var b: Dictionary = characters[cid]
		var art: Dictionary = b.get("art", {})
		var owner := str(art.get("owner", cid))
		if archetypes.has(owner):
			continue  # drawn with shared archetype art
		var de := str(_default_triplet(art.get("default", {}), art)["expression"])
		for pose in art.get("poses", []):
			for outfit in art.get("outfits", []):
				out.append(make_entry("portrait_body", {"owner": owner, "pose": pose, "outfit": outfit}))
			for ex in art.get("expressions", []):
				if ex == de:
					continue
				out.append(make_entry("portrait_face", {"owner": owner, "pose": pose, "expression": ex}))
		for ev in art.get("cg", []):
			out.append(make_entry("cg", {"event": ev, "variant": "main"}))
	for aid in archetypes:
		var a: Dictionary = archetypes[aid]
		var prof := _archetype_profile(a)
		var pose: String = prof["poses"][0]
		for look in prof["outfits"]:
			out.append(make_entry("portrait_body", {"owner": aid, "pose": pose, "outfit": look}))
		for ex in prof["expressions"]:
			if ex == prof["default"]["expression"]:
				continue
			out.append(make_entry("portrait_face", {"owner": aid, "pose": pose, "expression": ex}))
	for bg in spec.get("backgrounds_required", []):
		for t in bg.get("times", []):
			out.append(make_entry("background", {"location": bg["location"], "time": t}))
	return out


## Per-owner progress: {owner: {required, approved, draft, missing}}
func progress() -> Dictionary:
	var out := {}
	for e in required_assets():
		var key := str(e.get("owner", e.get("kind", "")))
		if not out.has(key):
			out[key] = {"required": 0, "approved": 0, "draft": 0, "missing": 0}
		out[key]["required"] += 1
		var m: Dictionary = assets.get(e["id"], {})
		var st := str(m.get("status", "missing"))
		if st != "missing" and not _file_exists(root + str(m.get("path", ""))):
			st = "missing"
		if out[key].has(st):
			out[key][st] += 1
		else:
			out[key]["missing"] += 1
	return out
