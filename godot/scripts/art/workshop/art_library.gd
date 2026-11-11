class_name ArtLibrary
extends RefCounted
## Write operations on the art library, used by the Creator Workshop and the
## Portrait Maker: import any image into a slot (resize, name and register it
## automatically), change status, edit bibles, add characters, store maker
## recipes. Works on files under the catalog root (development builds only).

var catalog: ArtCatalog


func _init(cat: ArtCatalog = null) -> void:
	catalog = cat if cat != null else ArtCatalog.shared()


# ---------------------------------------------------------------- slots

## Every image slot of a character: [{id, kind, pose, outfit, expression, path, status, has_file, label}]
func slots_for(character_id: String) -> Array:
	var owner := catalog.owner_of(character_id)
	var out: Array = []
	var seen := {}
	for e in catalog.required_assets():
		if _entry_owner(e) == owner:
			out.append(_slot(e))
			seen[e["id"]] = true
	for e in catalog.manifest_list:
		if _entry_owner(e) == owner and not seen.has(str(e.get("id", ""))):
			out.append(_slot(e))
	return out


func _entry_owner(e: Dictionary) -> String:
	if e.has("owner"):
		return str(e["owner"])
	if str(e.get("kind", "")) == "cg":
		# cg events are named "<owner>-story-01"
		var ev := str(e.get("event", ""))
		for cid in catalog.character_order:
			if ev.begins_with(catalog.owner_of(cid) + "-"):
				return catalog.owner_of(cid)
	return ""


func _slot(req: Dictionary) -> Dictionary:
	var e: Dictionary = catalog.assets.get(req["id"], req)
	var s: Dictionary = e.duplicate()
	s["has_file"] = FileAccess.file_exists(catalog.root + str(e.get("path", "")))
	if not s["has_file"]:
		s["status"] = "missing"
	s["label"] = slot_label(e)
	return s


func slot_label(e: Dictionary) -> String:
	var v: Dictionary = catalog.spec.get("vocab", {})
	var pose := str(v.get("poses", {}).get(e.get("pose", ""), {}).get("label", e.get("pose", "")))
	match str(e.get("kind", "")):
		"portrait_body":
			return "本體｜%s・%s" % [pose, _outfit_label(str(e.get("outfit", "")))]
		"portrait_face":
			return "表情｜%s・%s" % [pose, v.get("expressions", {}).get(e.get("expression", ""), {}).get("label", e.get("expression", ""))]
		"portrait_full":
			return "整張｜%s・%s・%s" % [pose, _outfit_label(str(e.get("outfit", ""))), v.get("expressions", {}).get(e.get("expression", ""), {}).get("label", e.get("expression", ""))]
		"cg":
			return "劇情 CG｜%s" % e.get("event", "")
		"background":
			return "背景｜%s・%s" % [e.get("location", ""), v.get("times", {}).get(e.get("time", ""), e.get("time", ""))]
	return str(e.get("id", ""))


func _outfit_label(o: String) -> String:
	return str(catalog.spec.get("vocab", {}).get("outfits", {}).get(o, {}).get("label", o))


## Asset id for a file name that follows the naming rules ("" otherwise).
func asset_id_for_filename(filename: String) -> String:
	var name := filename.get_file().get_basename().to_lower() + ".png"
	var parsed := catalog.parse_filename(name)
	if parsed.is_empty() or parsed["kind"] == "reference":
		return ""
	return name.get_basename()


# ---------------------------------------------------------------- manifest

func ensure_entry(asset_id: String) -> Dictionary:
	if catalog.assets.has(asset_id):
		return catalog.assets[asset_id]
	var parsed := catalog.parse_filename(asset_id + ".png")
	if parsed.is_empty():
		return {}
	var e := catalog.make_entry(parsed["kind"], parsed["fields"])
	catalog.manifest_list.append(e)
	catalog.assets[asset_id] = e
	return e


func save_manifest() -> bool:
	var path := catalog.root + "manifest.json"
	var manifest := ArtCatalog.read_json(path)
	if manifest.is_empty():
		manifest = {"_doc": "Asset manifest. One entry per image.", "assets": []}
	var list := catalog.manifest_list.duplicate()
	list.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	manifest["assets"] = list
	return write_json(path, manifest)


func set_status(asset_id: String, status: String) -> String:
	var e := ensure_entry(asset_id)
	if e.is_empty():
		return "找不到素材 %s" % asset_id
	if status in ["draft", "approved"] and not FileAccess.file_exists(catalog.root + str(e["path"])):
		return "還沒有圖片，不能標為%s" % ("完成" if status == "approved" else "草稿")
	if status == "approved" and bool(e.get("placeholder", false)):
		return "佔位圖不能標為完成"
	e["status"] = status
	catalog.clear_cache()
	return "" if save_manifest() else "無法寫入 manifest.json"


## Delete the image file and mark the slot missing again.
func clear_slot(asset_id: String) -> String:
	var e := ensure_entry(asset_id)
	if e.is_empty():
		return "找不到素材 %s" % asset_id
	var full := catalog.root + str(e["path"])
	if FileAccess.file_exists(full):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(full))
		if FileAccess.file_exists(full + ".import"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(full + ".import"))
	e["status"] = "missing"
	e.erase("source")
	catalog.clear_cache()
	PortraitTextures.clear_cache()
	return "" if save_manifest() else "無法寫入 manifest.json"


# ---------------------------------------------------------------- import

## Import any image file into a slot. The image is converted to RGBA, fitted
## to the canvas of that asset kind, saved under the right name and
## registered as "draft".
## opts: remove_bg (bool), tolerance (0..1, default 0.08), save (default true)
## Returns {ok, error, path, asset}
func import_image(asset_id: String, source_path: String, opts: Dictionary = {}) -> Dictionary:
	var img := Image.new()
	if img.load(source_path) != OK or img.is_empty():
		return {"ok": false, "error": "無法讀取圖片：%s" % source_path.get_file()}
	return store_image(asset_id, img, "import: " + source_path.get_file(), opts)


## Store an Image (from import or from the Portrait Maker) into a slot.
func store_image(asset_id: String, img: Image, source: String, opts: Dictionary = {}) -> Dictionary:
	var e := ensure_entry(asset_id)
	if e.is_empty():
		return {"ok": false, "error": "「%s」不符合命名規則" % asset_id}
	var kind := str(e["kind"])
	var canvas_name := str(catalog.spec.get("naming", {}).get(kind, {}).get("canvas", ""))
	var c: Dictionary = catalog.spec.get("canvases", {}).get(canvas_name, {})
	var w := int(e.get("width", c.get("width", 0)))
	var h := int(e.get("height", c.get("height", 0)))
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var wants_alpha := bool(c.get("alpha", false))
	if wants_alpha and bool(opts.get("remove_bg", false)):
		remove_flat_background(img, float(opts.get("tolerance", 0.08)))
	if wants_alpha and img.detect_alpha() == Image.ALPHA_NONE:
		return {"ok": false, "error": "這張圖沒有透明背景。請勾選「去除純色背景」再匯入，或先用去背工具處理。"}
	if w > 0 and h > 0 and (img.get_width() != w or img.get_height() != h):
		if kind == "portrait_face" or not wants_alpha:
			img = _fit(img, w, h, not wants_alpha, false)
		else:
			img = _fit(img, w, h, false, true)
	if img.is_invisible():
		return {"ok": false, "error": "圖片是全透明的"}
	var full := catalog.root + str(e["path"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(full.get_base_dir()))
	if img.save_png(full) != OK:
		return {"ok": false, "error": "無法寫入 %s" % full}
	e["status"] = "draft"
	e["source"] = source
	catalog.clear_cache()
	PortraitTextures.clear_cache()
	if bool(opts.get("save", true)):
		save_manifest()
	return {"ok": true, "error": "", "path": full, "asset": asset_id}


## Scale to the canvas keeping aspect. cover=true fills the canvas (crop),
## otherwise the image is contained; bottom=true anchors it to the bottom
## centre (standing portraits), else centre.
static func _fit(src: Image, w: int, h: int, cover: bool, bottom: bool) -> Image:
	var sw := src.get_width()
	var sh := src.get_height()
	var k := maxf(float(w) / sw, float(h) / sh) if cover else minf(float(w) / sw, float(h) / sh)
	var nw := maxi(1, int(round(sw * k)))
	var nh := maxi(1, int(round(sh * k)))
	var scaled := src.duplicate()
	scaled.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var dst := Vector2i((w - nw) / 2, (h - nh) if bottom else (h - nh) / 2)
	out.blit_rect(scaled, Rect2i(0, 0, nw, nh), dst)
	return out


## Make the flat background transparent: flood-fills from the four corners
## over pixels close to the corner colour. For images on plain white / green
## etc. Real photos or busy backgrounds need a proper cut-out tool.
static func remove_flat_background(img: Image, tolerance := 0.08) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var tol := int(tolerance * 255.0 * 3.0)
	var visited := PackedByteArray()
	visited.resize(w * h)
	var stack := PackedInt32Array()
	for corner in [0, w - 1, (h - 1) * w, h * w - 1]:
		var ci: int = corner * 4
		if data[ci + 3] == 0:
			continue
		var r := data[ci]
		var g := data[ci + 1]
		var b := data[ci + 2]
		stack.append(corner)
		while not stack.is_empty():
			var p := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			if visited[p] == 1:
				continue
			visited[p] = 1
			var i := p * 4
			if absi(data[i] - r) + absi(data[i + 1] - g) + absi(data[i + 2] - b) > tol:
				continue
			data[i + 3] = 0
			var x := p % w
			if x > 0:
				stack.append(p - 1)
			if x < w - 1:
				stack.append(p + 1)
			if p >= w:
				stack.append(p - w)
			if p < (h - 1) * w:
				stack.append(p + w)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)


# ---------------------------------------------------------------- bibles

func bible_path(character_id: String) -> String:
	return catalog.root + "characters/%s/bible.json" % character_id


func save_bible(character_id: String, bible: Dictionary) -> String:
	var old := catalog.get_character(character_id)
	if str(old.get("appearance_status", "")) == "confirmed" and str(bible.get("appearance_status", "")) == "confirmed" \
			and ArtValidator.appearance_hash(old) != ArtValidator.appearance_hash(bible):
		return "外觀已確認並鎖定，不能直接修改。請先解除鎖定。"
	if not write_json(bible_path(character_id), bible):
		return "無法寫入角色設定"
	catalog.characters[character_id] = bible
	return ""


## Confirm + lock the appearance. Fails while any field is still TBD.
func lock_appearance(character_id: String, note := "外觀確認並鎖定") -> String:
	var b: Dictionary = catalog.get_character(character_id).duplicate(true)
	if b.is_empty():
		return "找不到角色"
	if ArtValidator.contains_tbd(b.get("appearance", {})):
		return "外觀還有未填寫（TBD）的欄位"
	var rev := int(b.get("bible_revision", 0)) + 1
	b["bible_revision"] = rev
	b["appearance_status"] = "confirmed"
	b["appearance_lock_hash"] = ArtValidator.appearance_hash(b)
	var log: Array = b.get("changelog", [])
	log.append({"revision": rev, "date": Time.get_date_string_from_system(), "note": note})
	b["changelog"] = log
	if not write_json(bible_path(character_id), b):
		return "無法寫入角色設定"
	catalog.characters[character_id] = b
	return ""


func unlock_appearance(character_id: String) -> String:
	var b: Dictionary = catalog.get_character(character_id).duplicate(true)
	if b.is_empty():
		return "找不到角色"
	b["appearance_status"] = "unconfirmed"
	b["appearance_lock_hash"] = ""
	var log: Array = b.get("changelog", [])
	log.append({"revision": int(b.get("bible_revision", 0)), "date": Time.get_date_string_from_system(), "note": "解除外觀鎖定以便修改"})
	b["changelog"] = log
	if not write_json(bible_path(character_id), b):
		return "無法寫入角色設定"
	catalog.characters[character_id] = b
	return ""


## Create a new character with an empty bible and register its slots.
func add_character(id: String, display_name: String, tier: String, role := "TBD") -> String:
	var rx := RegEx.create_from_string("^[a-z0-9]+(_[a-z0-9]+)*$")
	if rx.search(id) == null:
		return "角色 ID 只能用小寫英文、數字與底線"
	if catalog.has_character(id) or catalog.archetypes.has(id):
		return "角色 ID「%s」已存在" % id
	var tiers: Dictionary = catalog.spec.get("tiers", {})
	if not tiers.has(tier):
		return "分級必須是 S、A 或 B"
	var t: Dictionary = tiers[tier]
	var outfits := {}
	for o in t["default_outfits"]:
		outfits[o] = {"design": "TBD"}
	var owner := id.replace("_", "-")
	var bible := {
		"id": id, "name": display_name, "role": role, "tier": tier, "tier_confirmed": false,
		"bible_revision": 0, "appearance_status": "unconfirmed", "appearance_lock_hash": "",
		"appearance": {
			"summary": "TBD", "age_look": "TBD", "hair": {"style": "TBD", "color": "TBD"}, "eyes": {"color": "TBD"},
			"body": {"height_cm": "TBD", "build": "TBD", "proportion_note": "TBD"}, "outfits": outfits,
			"accessories": "TBD", "signature_colors": "TBD", "expression_traits": "TBD",
		},
		"personality": {"source": "TBD", "summary": "TBD", "traits": []},
		"art": {
			"owner": owner, "expressions": t["default_expressions"], "poses": t["default_poses"], "outfits": t["default_outfits"],
			"default": {"pose": t["default_poses"][0], "outfit": t["default_outfits"][0], "expression": "neutral"},
			"cg": ["%s-story-01" % owner] if int(t.get("min_cg", 0)) > 0 else [], "display": {"scale": 1.0, "y_offset": 0.0},
		},
		"references": [], "open_questions": ["外貌尚未確認"],
		"changelog": [{"revision": 0, "date": Time.get_date_string_from_system(), "note": "建立空白設定"}],
	}
	if not write_json(bible_path(id), bible):
		return "無法寫入角色設定"
	var index_path := catalog.root + "characters/index.json"
	var index := ArtCatalog.read_json(index_path)
	var chars: Array = index.get("characters", [])
	chars.append({"id": id, "bible": "characters/%s/bible.json" % id})
	index["characters"] = chars
	write_json(index_path, index)
	catalog.characters[id] = bible
	catalog.character_order.append(id)
	for r in catalog.required_assets():
		ensure_entry(r["id"])
	save_manifest()
	return ""


# ---------------------------------------------------------------- maker recipes

func recipe_path(character_id: String) -> String:
	return catalog.root + "characters/%s/maker.json" % character_id


func has_recipe(character_id: String) -> bool:
	return FileAccess.file_exists(recipe_path(character_id))


func load_recipe(character_id: String) -> Dictionary:
	var r := ArtCatalog.read_json(recipe_path(character_id))
	var b := catalog.get_character(character_id)
	if r.is_empty():
		# start from the prototype colours if the bible has them
		var hints: Dictionary = b.get("prototype_hints", {})
		if hints.has("hair_hex"):
			r["hair_color"] = hints["hair_hex"]
		if hints.has("eye_hex"):
			r["eye_color"] = hints["eye_hex"]
	var out := PortraitRecipe.normalized(r)
	# make sure every outfit the bible lists has an entry
	for o in b.get("art", {}).get("outfits", []):
		if not out["outfits"].has(o):
			out["outfits"][o] = PortraitRecipe.DEFAULT_OUTFIT.duplicate(true)
	return out


func save_recipe(character_id: String, recipe: Dictionary) -> bool:
	return write_json(recipe_path(character_id), recipe)


# ---------------------------------------------------------------- json

static func write_json(path: String, data) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_tidy(data), "  ", false) + "\n")
	f.close()
	return true


## JSON.parse turns every number into a float; write whole numbers back as ints.
static func _tidy(v):
	match typeof(v):
		TYPE_FLOAT:
			if v == floorf(v) and absf(v) < 1e15:
				return int(v)
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _tidy(v[k])
			return d
		TYPE_ARRAY:
			var a: Array = []
			for x in v:
				a.append(_tidy(x))
			return a
	return v
