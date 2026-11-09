class_name ArtValidator
extends RefCounted
## Checks the whole art library against art_spec.json, the bibles and the manifest.
##
## Levels:
##   error    – broken data or a file that would show wrong in game. Fails the check.
##   warning  – worth fixing (fails only with strict=true).
##   missing  – planned asset with no file yet. Normal during production;
##              fails only with require_complete=true (release check).
##   info     – status notes (e.g. appearance not yet confirmed).

const TBD := "TBD"

var catalog: ArtCatalog
var strict := false
var require_complete := false
var issues: Array = []          ## [{level, code, message, path}]

var _registered_paths: Dictionary = {}   ## lowercased rel path -> asset id / "reference"
var _hashes: Dictionary = {}             ## md5 -> rel path


func run(cat: ArtCatalog) -> Dictionary:
	catalog = cat
	issues = []
	_registered_paths = {}
	_hashes = {}
	for e in cat.load_errors:
		_add("error", "E_LOAD", e)
	if cat.spec.is_empty():
		return report()
	_check_characters()
	_check_npc()
	_check_manifest()
	_check_required()
	_check_unregistered_files()
	return report()


func report() -> Dictionary:
	var counts := {"error": 0, "warning": 0, "missing": 0, "info": 0}
	for i in issues:
		counts[i["level"]] += 1
	var failed: bool = counts["error"] > 0 or (strict and counts["warning"] > 0) or (require_complete and counts["missing"] > 0)
	return {"ok": not failed, "counts": counts, "issues": issues, "progress": catalog.progress() if catalog else {}}


func _add(level: String, code: String, message: String, path := "") -> void:
	issues.append({"level": level, "code": code, "message": message, "path": path})


# ---------------------------------------------------------------- bibles

static func appearance_hash(bible: Dictionary) -> String:
	return JSON.stringify(bible.get("appearance", {}), "", true).md5_text()


static func contains_tbd(v) -> bool:
	match typeof(v):
		TYPE_STRING:
			return str(v).strip_edges().to_upper() == TBD or str(v).strip_edges() == ""
		TYPE_DICTIONARY:
			for k in v:
				if contains_tbd(v[k]):
					return true
		TYPE_ARRAY:
			if v.is_empty():
				return true
			for x in v:
				if contains_tbd(x):
					return true
	return false


func _check_characters() -> void:
	var vocab: Dictionary = catalog.spec.get("vocab", {})
	var tiers: Dictionary = catalog.spec.get("tiers", {})
	var id_rx := RegEx.create_from_string("^[a-z0-9]+([_-][a-z0-9]+)*$")
	for cid in catalog.character_order:
		var b: Dictionary = catalog.characters[cid]
		var where := "characters/%s/bible.json" % cid
		if id_rx.search(cid) == null:
			_add("error", "E_BIBLE_ID", "character id '%s' must be lowercase letters/digits" % cid, where)
		if str(b.get("id", "")) != cid:
			_add("error", "E_BIBLE_ID", "bible id '%s' does not match index id '%s'" % [b.get("id", ""), cid], where)
		var tier := str(b.get("tier", ""))
		if not tiers.has(tier):
			_add("error", "E_TIER", "%s: unknown tier '%s'" % [cid, tier], where)
			continue
		var t: Dictionary = tiers[tier]
		var art: Dictionary = b.get("art", {})
		var owner := str(art.get("owner", cid))
		if not catalog.is_valid_segment(owner):
			_add("error", "E_OWNER", "%s: art.owner '%s' is not a valid filename segment (use kebab-case)" % [cid, owner], where)
		var shared := catalog.archetypes.has(owner)
		if shared:
			var look := str(art.get("default", {}).get("outfit", ""))
			var found := false
			for l in catalog.archetypes[owner].get("looks", []):
				found = found or str(l.get("id", "")) == look
			if not found:
				_add("error", "E_OWNER", "%s: uses archetype '%s' but look '%s' does not exist" % [cid, owner, look], where)
		else:
			for pair in [["expressions", "expressions", "min_expressions"], ["poses", "poses", "min_poses"], ["outfits", "outfits", "min_outfits"]]:
				var lst: Array = art.get(pair[0], [])
				for v in lst:
					if not vocab.get(pair[1], {}).has(str(v)):
						_add("error", "E_VOCAB", "%s: %s '%s' is not in art_spec vocab" % [cid, pair[0], v], where)
					if not catalog.is_valid_segment(str(v)):
						_add("error", "E_VOCAB", "%s: '%s' is not a valid id" % [cid, v], where)
				if lst.size() < int(t.get(pair[2], 0)):
					_add("error", "E_TIER_MIN", "%s: tier %s needs at least %d %s (has %d)" % [cid, tier, int(t[pair[2]]), pair[0], lst.size()], where)
			var maxp = t.get("max_poses")
			if maxp != null and art.get("poses", []).size() > int(maxp):
				_add("warning", "E_TIER_MAX", "%s: tier %s allows at most %d poses" % [cid, tier, int(maxp)], where)
			if art.get("cg", []).size() < int(t.get("min_cg", 0)):
				_add("error", "E_TIER_MIN", "%s: tier %s needs at least %d CG" % [cid, tier, int(t["min_cg"])], where)
			var d: Dictionary = art.get("default", {})
			for k in [["pose", "poses"], ["outfit", "outfits"], ["expression", "expressions"]]:
				if d.has(k[0]) and not art.get(k[1], []).has(d[k[0]]):
					_add("error", "E_DEFAULT", "%s: default %s '%s' is not in its %s list" % [cid, k[0], d[k[0]], k[1]], where)
		# appearance lock
		var status := str(b.get("appearance_status", "unconfirmed"))
		if status == "confirmed":
			if contains_tbd(b.get("appearance", {})):
				_add("error", "E_LOCK_TBD", "%s: appearance is confirmed but still has TBD fields" % cid, where)
			if str(b.get("appearance_lock_hash", "")) != appearance_hash(b):
				_add("error", "E_LOCK_CHANGED", "%s: confirmed appearance was edited. Revert it, or get approval and re-lock (art_cli lock %s)" % [cid, cid], where)
		else:
			_add("info", "I_UNCONFIRMED", "%s: appearance not confirmed yet — AI generation for this character is draft-only" % cid, where)
		# references
		var refs: Array = b.get("references", [])
		if refs.is_empty() and tier != "B":
			_add("warning", "W_NO_REFERENCE", "%s: no visual reference image yet" % cid, where)
		for r in refs:
			_check_reference(cid, r, where)
		# npc tags
		var tags: Dictionary = art.get("npc_tags", {})
		var dims: Dictionary = catalog.taxonomy.get("dimensions", {})
		for dim in ["age_look", "customer_type"]:
			if tags.has(dim):
				var v := str(tags[dim])
				if v == TBD:
					_add("info", "I_NPC_TAG_TBD", "%s: npc_tags.%s is TBD" % [cid, dim], where)
				elif not dims.get(dim, {}).has(v):
					_add("error", "E_NPC_TAG", "%s: npc_tags.%s '%s' not in taxonomy" % [cid, dim, v], where)
		for p in tags.get("personality", []):
			if not dims.get("personality", {}).has(str(p)):
				_add("error", "E_NPC_TAG", "%s: personality '%s' not in taxonomy" % [cid, p], where)


func _check_reference(cid: String, r, where: String) -> void:
	var rel := str(r.get("path", "")) if typeof(r) == TYPE_DICTIONARY else str(r)
	var parsed := catalog.parse_filename(rel.get_file())
	if parsed.get("kind", "") != "reference":
		_add("error", "E_NAMING", "%s: reference '%s' must be named ref_{owner}_{name}.png" % [cid, rel], rel)
	_registered_paths[rel.to_lower()] = "reference:" + cid
	var full := catalog.root + rel
	if not FileAccess.file_exists(full):
		_add("error", "E_FILE_MISSING", "%s: reference image not found" % cid, rel)
		return
	var c: Dictionary = catalog.spec.get("canvases", {}).get("reference", {})
	var img := _load_image(full, rel)
	if img and (img.get_width() < int(c.get("min_width", 0)) or img.get_height() < int(c.get("min_height", 0))):
		_add("error", "E_SIZE", "%s: reference smaller than %dx%d" % [cid, int(c.get("min_width", 0)), int(c.get("min_height", 0))], rel)


# ---------------------------------------------------------------- npc

func _check_npc() -> void:
	var npc := NpcArtCatalog.new(catalog)
	for aid in catalog.archetypes:
		var a: Dictionary = catalog.archetypes[aid]
		var where := "npc/archetypes.json"
		if not catalog.is_valid_segment(aid):
			_add("error", "E_NPC_ID", "archetype id '%s' invalid" % aid, where)
		if catalog.characters.has(aid):
			_add("error", "E_NPC_ID", "archetype id '%s' collides with a character id" % aid, where)
		var seen := {}
		for look in a.get("looks", []):
			var lid := str(look.get("id", ""))
			if seen.has(lid):
				_add("error", "E_NPC_ID", "%s: duplicate look id '%s'" % [aid, lid], where)
			seen[lid] = true
			for p in npc.check_look(a, look):
				_add("error", "E_NPC_RULE", "%s/%s: %s" % [aid, lid, p], where)
		for pair in npc.similar_pairs(a):
			_add("warning", "W_NPC_SIMILAR", "%s: looks %s and %s are too similar" % [aid, pair[0], pair[1]], where)
		for e in a.get("expressions", []):
			if not catalog.spec.get("vocab", {}).get("expressions", {}).has(str(e)):
				_add("error", "E_VOCAB", "%s: expression '%s' not in vocab" % [aid, e], where)
		if str(a.get("status", "")) == "proposal":
			_add("info", "I_NPC_PROPOSAL", "%s: archetype is a proposal (not approved by the art director)" % aid, where)


# ---------------------------------------------------------------- manifest

func _check_manifest() -> void:
	var seen_ids := {}
	var statuses: Dictionary = catalog.spec.get("asset_status", {})
	for e in catalog.manifest_list:
		var aid := str(e.get("id", ""))
		var rel := str(e.get("path", ""))
		var kind := str(e.get("kind", ""))
		var status := str(e.get("status", ""))
		if seen_ids.has(aid):
			_add("error", "E_DUP_ID", "duplicate asset id '%s'" % aid, rel)
		seen_ids[aid] = true
		var low := rel.to_lower()
		if _registered_paths.has(low):
			_add("error", "E_DUP_PATH", "path registered twice ('%s' and '%s')" % [_registered_paths[low], aid], rel)
		_registered_paths[low] = aid
		if not statuses.has(status) or status.begins_with("_"):
			_add("error", "E_STATUS", "%s: unknown status '%s'" % [aid, status], rel)
		if not catalog.naming_kinds().has(kind):
			_add("error", "E_KIND", "%s: unknown kind '%s'" % [aid, kind], rel)
			continue
		# naming: path must be exactly what the naming rule produces
		var fields := {}
		for k in e:
			if not ["id", "kind", "path", "status", "note", "placeholder", "width", "height", "source", "prompt"].has(k):
				fields[k] = str(e[k])
		for f in fields:
			if not catalog.is_valid_segment(fields[f]):
				_add("error", "E_NAMING", "%s: field %s='%s' is not a valid id segment" % [aid, f, fields[f]], rel)
		var expected := catalog.format_path(kind, fields)
		if expected != rel:
			_add("error", "E_NAMING", "%s: path should be '%s'" % [aid, expected], rel)
		if aid != rel.get_file().get_basename():
			_add("error", "E_NAMING", "asset id '%s' must equal the filename without extension" % aid, rel)
		if rel.contains("..") or rel.begins_with("/") or rel.contains("\\"):
			_add("error", "E_BAD_PATH", "%s: path must be relative, forward slashes, inside the art root" % aid, rel)
		_check_variant_declared(e, kind, rel)
		_check_file(e, kind, status, rel)


func _check_variant_declared(e: Dictionary, kind: String, rel: String) -> void:
	if not kind.begins_with("portrait_"):
		return
	var owner := str(e.get("owner", ""))
	var prof: Dictionary = {}
	for cid in catalog.character_order:
		if catalog.owner_of(cid) == owner and not catalog.archetypes.has(owner):
			prof = catalog.get_art_profile(cid)
	if prof.is_empty() and catalog.archetypes.has(owner):
		prof = catalog.get_art_profile(owner)
	if prof.is_empty():
		_add("error", "E_OWNER_UNKNOWN", "%s: owner '%s' is not a character or archetype" % [e.get("id", ""), owner], rel)
		return
	for pair in [["pose", "poses"], ["outfit", "outfits"], ["expression", "expressions"]]:
		if e.has(pair[0]) and not prof[pair[1]].has(str(e[pair[0]])):
			_add("warning", "W_UNDECLARED_VARIANT", "%s: %s '%s' is not listed in the bible, the game will never request it" % [e.get("id", ""), pair[0], e[pair[0]]], rel)


func _check_file(e: Dictionary, kind: String, status: String, rel: String) -> void:
	var aid := str(e.get("id", ""))
	var full := catalog.root + rel
	var exists := FileAccess.file_exists(full)
	if status == "missing":
		if exists:
			_add("warning", "W_FILE_UNREVIEWED", "%s: file exists but status is 'missing' — set it to 'draft' for review" % aid, rel)
		else:
			_add("missing", "M_MISSING", "%s: not produced yet" % aid, rel)
			return
	elif status == "deprecated":
		if not exists:
			return
	elif not exists:
		_add("error", "E_FILE_MISSING", "%s: status '%s' but the file does not exist" % [aid, status], rel)
		return
	if bool(e.get("placeholder", false)) and status == "approved":
		_add("error", "E_PLACEHOLDER_APPROVED", "%s: placeholder images can never be 'approved'" % aid, rel)
	var img := _load_image(full, rel)
	if img == null:
		return
	var canvas_name := str(catalog.spec.get("naming", {}).get(kind, {}).get("canvas", ""))
	var c: Dictionary = catalog.spec.get("canvases", {}).get(canvas_name, {})
	var w := int(e.get("width", c.get("width", 0)))
	var h := int(e.get("height", c.get("height", 0)))
	if w > 0 and h > 0 and (img.get_width() != w or img.get_height() != h):
		_add("error", "E_SIZE", "%s: is %dx%d, spec requires %dx%d" % [aid, img.get_width(), img.get_height(), w, h], rel)
	if bool(c.get("alpha", false)) and img.detect_alpha() == Image.ALPHA_NONE:
		_add("error", "E_ALPHA", "%s: needs a transparent background (no transparent pixels found)" % aid, rel)
	if img.is_invisible():
		_add("error", "E_BLANK", "%s: image is fully transparent" % aid, rel)
	elif _is_solid(img):
		_add("error", "E_BLANK", "%s: image is a single flat colour (looks like a placeholder)" % aid, rel)
	var md5 := FileAccess.get_md5(full)
	if _hashes.has(md5):
		_add("error", "E_DUP_CONTENT", "%s: identical to '%s'" % [aid, _hashes[md5]], rel)
	else:
		_hashes[md5] = rel


func _load_image(full: String, rel: String) -> Image:
	var f := FileAccess.open(full, FileAccess.READ)
	if f == null:
		_add("error", "E_FILE_MISSING", "cannot open file", rel)
		return null
	var magic := f.get_buffer(8)
	f.close()
	if magic != PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		_add("error", "E_FORMAT", "not a real PNG file (wrong file signature)", rel)
		return null
	var img := Image.new()
	if img.load(full) != OK or img.is_empty():
		_add("error", "E_FORMAT", "PNG could not be decoded", rel)
		return null
	return img


func _is_solid(img: Image) -> bool:
	var first := img.get_pixel(0, 0)
	var steps := 12
	for yi in steps:
		for xi in steps:
			var px := img.get_pixel(int((xi + 0.5) * img.get_width() / steps), int((yi + 0.5) * img.get_height() / steps))
			if not px.is_equal_approx(first):
				return false
	return true


# ---------------------------------------------------------------- coverage

func _check_required() -> void:
	for r in catalog.required_assets():
		if not catalog.assets.has(r["id"]):
			_add("error", "E_REQUIRED_UNREGISTERED", "%s is required by the bible/spec but not in manifest.json (run: art_cli sync)" % r["id"], r["path"])


func _check_unregistered_files() -> void:
	for rel in list_image_files(catalog.root):
		var low: String = rel.to_lower()
		if _registered_paths.has(low):
			if rel.get_extension() != "png":
				_add("error", "E_FORMAT", "only .png is allowed", rel)
			continue
		var hint := ""
		var parsed := catalog.parse_filename(rel.get_file())
		if parsed.is_empty():
			hint = " (name does not follow any naming rule)"
		_add("error", "E_UNREGISTERED_FILE", "image is not registered in manifest.json%s" % hint, rel)


## All image files under root, as paths relative to root.
static func list_image_files(art_root: String) -> Array:
	var out: Array = []
	_walk(art_root, "", out)
	out.sort()
	return out


static func _walk(base: String, rel_dir: String, out: Array) -> void:
	var d := DirAccess.open(base + rel_dir)
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		if ArtCatalog.IMAGE_EXTENSIONS.has(f.get_extension().to_lower()):
			out.append(rel_dir + f)
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		_walk(base, rel_dir + sub + "/", out)


# ---------------------------------------------------------------- output

func format_text(rep: Dictionary, show_missing := false) -> String:
	var lines := PackedStringArray()
	for level in ["error", "warning", "missing", "info"]:
		if level == "missing" and not show_missing:
			continue
		for i in rep["issues"]:
			if i["level"] == level:
				lines.append("[%s] %s %s%s" % [level.to_upper(), i["code"], i["message"], ("  <" + i["path"] + ">") if i["path"] != "" else ""])
	var c: Dictionary = rep["counts"]
	lines.append("")
	lines.append("Summary: %d error(s), %d warning(s), %d missing asset(s), %d note(s) -> %s" % [c["error"], c["warning"], c["missing"], c["info"], "OK" if rep["ok"] else "FAILED"])
	return "\n".join(lines)
