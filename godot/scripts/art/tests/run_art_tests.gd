extends SceneTree
## Headless tests for the art pipeline.
##   godot --headless -s res://scripts/art/tests/run_art_tests.gd
## Builds a throw-away fixture art root in user:// with generated test images
## (never in res://art, so test images can't be mistaken for real assets).

const FIX := "user://art_test_fixture/"

var failures := 0
var passes := 0


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		printerr("  FAIL: ", msg)


func _run() -> void:
	print("== art pipeline tests ==")
	_test_real_data()
	_build_fixture()
	_test_naming()
	_test_resolution()
	_test_textures()
	await _test_stage()
	_test_npc()
	_test_validator_detects_problems()
	_test_prompt_builder()
	_test_recipe()
	_test_library()
	await _test_maker_render()
	print("== %d passed, %d failed ==" % [passes, failures])
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------- real data

func _test_real_data() -> void:
	print("- real art data")
	var cat := ArtCatalog.new()
	check(cat.load_from(ArtCatalog.DEFAULT_ROOT), "real catalog loads without errors: %s" % str(cat.load_errors))
	check(cat.characters.size() >= 28, "all characters indexed (%d)" % cat.characters.size())
	for id in ["koharu", "rin", "shizuku", "yukino", "kaede", "kasuga_m", "yamada"]:
		check(cat.has_character(id), "has character " + id)
	check(cat.owner_of("kasuga_m") == "kasuga-m", "underscore ids map to kebab art owner")
	var v := ArtValidator.new()
	var rep := v.run(cat)
	check(rep["counts"]["error"] == 0, "real data has no validation errors:\n" + v.format_text(rep))
	check(rep["counts"]["missing"] > 0, "missing art is reported as missing, not hidden")
	# No real character may be marked confirmed while it still has TBD fields.
	for id in cat.characters:
		var b: Dictionary = cat.characters[id]
		if str(b.get("appearance_status", "")) == "confirmed":
			check(not ArtValidator.contains_tbd(b.get("appearance", {})), id + " confirmed without TBD")
	# Every tier S has at least 8 expressions / 3 poses / 2 outfits / 1 CG
	for id in cat.characters:
		var b: Dictionary = cat.characters[id]
		if b["tier"] == "S":
			check(b["art"]["expressions"].size() >= 8 and b["art"]["poses"].size() >= 3 and b["art"]["outfits"].size() >= 2 and b["art"]["cg"].size() >= 1, id + " meets tier S")
	# Characters without art resolve to silhouettes without crashing; the maids
	# have Portrait Maker drafts, which must be drafts made by the maker (never approved by a tool).
	var r := cat.resolve_portrait("kasuga_m", "", "", "smile")
	check(r["silhouette"] and r["known"], "kasuga_m without art -> silhouette, known character")
	r = cat.resolve_portrait("koharu", "", "", "smile")
	check(r["known"], "koharu resolves as known character")
	for e in cat.manifest_list:
		if str(e.get("source", "")) == "portrait-maker":
			check(e["status"] == "draft" or e["status"] == "approved", e["id"] + " maker image has a valid status")
			check(FileAccess.file_exists(cat.root + str(e["path"])), e["id"] + " maker image exists")
	# Maker recipes are proposals until luz confirms the appearance.
	var lib := ArtLibrary.new(cat)
	for id in cat.characters:
		if lib.has_recipe(id) and str(cat.characters[id].get("appearance_status", "")) != "confirmed":
			check(str(ArtCatalog.read_json(lib.recipe_path(id)).get("status", "")) == "proposal", id + " recipe is marked as a proposal")


# ------------------------------------------------------------- fixture

func _img(w: int, h: int, seed_color: Color, alpha := true) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0) if alpha else Color(0.9, 0.9, 0.9, 1))
	img.fill_rect(Rect2i(w / 4, h / 8, w / 2, h * 7 / 8), seed_color)
	img.fill_rect(Rect2i(w / 3, h / 6, w / 3, h / 8), seed_color.lightened(0.4))
	return img


func _save(rel: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute((FIX + rel).get_base_dir())
	img.save_png(FIX + rel)


func _write(rel: String, data) -> void:
	DirAccess.make_dir_recursive_absolute((FIX + rel).get_base_dir())
	var f := FileAccess.open(FIX + rel, FileAccess.WRITE)
	f.store_string(data if typeof(data) == TYPE_STRING else JSON.stringify(data, "  "))
	f.close()


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
		d.remove(sub)


func _build_fixture() -> void:
	_rm_tree(FIX)
	DirAccess.make_dir_recursive_absolute(FIX)
	var spec := ArtCatalog.read_json("res://art/art_spec.json")
	spec["canvases"]["portrait"]["width"] = 128
	spec["canvases"]["portrait"]["height"] = 192
	spec["canvases"]["cg"] = {"width": 160, "height": 90, "format": "png", "alpha": false}
	spec["canvases"]["background"] = {"width": 160, "height": 90, "format": "png", "alpha": false}
	spec["backgrounds_required"] = [{"location": "cafe", "times": ["day"]}]
	_write("art_spec.json", spec)
	var s: Dictionary = spec["tiers"]["S"]
	var alpha := {
		"id": "alpha", "name": "測試甲", "tier": "S", "appearance_status": "unconfirmed",
		"appearance": {"summary": "TBD"},
		"art": {"owner": "alpha", "expressions": s["default_expressions"], "poses": s["default_poses"], "outfits": s["default_outfits"],
			"default": {"pose": "stand", "outfit": "maid", "expression": "neutral"}, "cg": ["alpha-story-01"],
			"display": {"scale": 1.0, "y_offset": 0.0}},
		"references": [],
	}
	var beta := {
		"id": "beta_two", "name": "測試乙", "tier": "B", "appearance_status": "unconfirmed", "appearance": {"summary": "TBD"},
		"art": {"owner": "beta-two", "expressions": ["neutral", "smile"], "poses": ["stand"], "outfits": ["default"],
			"default": {"pose": "stand", "outfit": "default", "expression": "neutral"}, "cg": [], "display": {"scale": 0.9, "y_offset": 0.02}},
		"references": [],
	}
	_write("characters/alpha/bible.json", alpha)
	_write("characters/beta_two/bible.json", beta)
	_write("characters/index.json", {"characters": [
		{"id": "alpha", "bible": "characters/alpha/bible.json"},
		{"id": "beta_two", "bible": "characters/beta_two/bible.json"}]})
	_write("npc/taxonomy.json", FileAccess.get_file_as_string("res://art/npc/taxonomy.json"))
	_write("npc/archetypes.json", FileAccess.get_file_as_string("res://art/npc/archetypes.json"))

	var cat := ArtCatalog.new()
	cat.load_from(FIX)
	var list: Array = cat.required_assets()
	var have := {
		"chr_alpha_body_stand_maid": Color(0.9, 0.5, 0.3),
		"chr_alpha_body_stand_casual": Color(0.3, 0.5, 0.9),
		"chr_alpha_body_greet_maid": Color(0.8, 0.4, 0.6),
		"chr_alpha_face_stand_smile": Color(1, 0.8, 0.7),
		"chr_alpha_face_greet_smile": Color(1, 0.7, 0.8),
		"chr_beta-two_body_stand_default": Color(0.4, 0.7, 0.4),
		"chr_npc-student-f_body_stand_look-01": Color(0.2, 0.2, 0.5),
		"chr_npc-student-f_body_stand_look-02": Color(0.5, 0.2, 0.2),
	}
	for e in list:
		if have.has(e["id"]):
			_save(e["path"], _img(128, 192, have[e["id"]]))
			e["status"] = "draft" if e["id"] == "chr_alpha_body_stand_casual" else "approved"
	# an extra full image (optional kind) for serve/maid/laugh
	var full := cat.make_entry("portrait_full", {"owner": "alpha", "pose": "serve", "outfit": "maid", "expression": "laugh"}, "approved")
	_save(full["path"], _img(128, 192, Color(0.95, 0.6, 0.2)))
	list.append(full)
	# registered as approved but the file is corrupt (text with .png name)
	var bad := cat.make_entry("portrait_face", {"owner": "alpha", "pose": "stand", "expression": "angry"}, "approved")
	for e in list:
		if e["id"] == bad["id"]:
			e["status"] = "approved"
	_write(bad["path"], "this is not a png")
	_write("manifest.json", {"assets": list})


# ------------------------------------------------------------- tests

func _fixture_catalog() -> ArtCatalog:
	var cat := ArtCatalog.new()
	cat.load_from(FIX)
	return cat


func _test_naming() -> void:
	print("- naming")
	var cat := _fixture_catalog()
	check(cat.format_filename("portrait_face", {"owner": "alpha", "pose": "stand", "expression": "smile"}) == "chr_alpha_face_stand_smile.png", "face filename")
	var p := cat.parse_filename("chr_npc-student-f_body_stand_look-01.png")
	check(p.get("kind", "") == "portrait_body" and p["fields"]["owner"] == "npc-student-f" and p["fields"]["outfit"] == "look-01", "parse kebab segments: %s" % str(p))
	check(cat.parse_filename("chr_alpha_full_serve_maid_laugh.png").get("kind", "") == "portrait_full", "parse full")
	check(cat.parse_filename("Koharu Smile.png").is_empty(), "bad names do not parse")
	check(cat.parse_filename("chr_kasuga_m_body_stand_default.png").get("kind", "") != "portrait_body" or cat.parse_filename("chr_kasuga_m_body_stand_default.png")["fields"]["owner"] != "kasuga_m", "underscore owner is never parsed as one segment")
	check(not cat.is_valid_segment("kasuga_m") and cat.is_valid_segment("kasuga-m"), "segment rule")


func _test_resolution() -> void:
	print("- portrait resolution & fallbacks")
	var cat := _fixture_catalog()
	var r := cat.resolve_portrait("alpha")
	check(r["layers"].size() == 1 and r["layers"][0].ends_with("chr_alpha_body_stand_maid.png"), "default -> body only: %s" % str(r["layers"]))
	r = cat.resolve_portrait("alpha", "", "", "smile")
	check(r["layers"].size() == 2 and r["layers"][1].ends_with("chr_alpha_face_stand_smile.png"), "expression -> body + face")
	r = cat.resolve_portrait("alpha", "", "casual", "smile")
	check(r["layers"][0].ends_with("chr_alpha_body_stand_casual.png") and r["layers"][1].ends_with("chr_alpha_face_stand_smile.png"), "outfit switch keeps face patch")
	r = cat.resolve_portrait("alpha", "greet", "", "smile")
	check(r["layers"][0].ends_with("chr_alpha_body_greet_maid.png") and r["layers"][1].ends_with("chr_alpha_face_greet_smile.png"), "pose switch uses that pose's face")
	r = cat.resolve_portrait("alpha", "serve", "maid", "laugh")
	check(r["layers"].size() == 1 and r["layers"][0].ends_with("chr_alpha_full_serve_maid_laugh.png"), "full image wins")
	r = cat.resolve_portrait("alpha", "serve", "", "smile")
	check(r["pose"] == "stand" and r["expression"] == "smile" and r["fallbacks"].size() > 0, "missing pose falls back to default pose: %s" % str(r))
	r = cat.resolve_portrait("alpha", "greet", "casual", "")
	check(r["pose"] == "greet" and r["outfit"] == "maid", "missing outfit falls back to default outfit")
	r = cat.resolve_portrait("alpha", "", "", "tired")
	check(r["layers"].size() == 1 and r["expression"] == "neutral", "missing expression falls back to neutral body")
	r = cat.resolve_portrait("alpha", "", "", "no-such-expression")
	check(not r["silhouette"], "unknown expression id still shows the character")
	r = cat.resolve_portrait("beta_two", "", "", "smile")
	check(r["layers"].size() == 1 and r["display"]["scale"] == 0.9, "tier B, display scale from bible")
	r = cat.resolve_portrait("ghost")
	check(r["silhouette"] and not r["known"], "unknown character -> silhouette")
	r = cat.resolve_portrait("npc-student-f", "", "look-02", "smile")
	check(r["layers"][0].ends_with("chr_npc-student-f_body_stand_look-02.png"), "archetype look as outfit")
	cat.allow_draft = false
	r = cat.resolve_portrait("alpha", "", "casual", "")
	check(r["outfit"] == "maid", "draft assets hidden when allow_draft=false")
	var prog := cat.progress()
	check(prog["alpha"]["approved"] >= 4 and prog["alpha"]["draft"] == 1, "progress counts: %s" % str(prog["alpha"]))


func _test_textures() -> void:
	print("- texture loading")
	PortraitTextures.clear_cache()
	var t := PortraitTextures.load_texture(FIX + "portraits/alpha/chr_alpha_body_stand_maid.png")
	check(t != null and t.get_width() == 128, "loads un-imported PNG from disk")
	check(PortraitTextures.load_texture(FIX + "portraits/alpha/chr_alpha_face_stand_angry.png") == null, "corrupt PNG returns null (no crash)")
	check(PortraitTextures.load_texture(FIX + "nope.png") == null, "missing file returns null")
	check(PortraitTextures.silhouette() != null, "silhouette texture")


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _test_stage() -> void:
	print("- portrait stage")
	var cat := _fixture_catalog()
	var stage := PortraitStage.new()
	stage.catalog = cat
	stage.default_duration = 0.1
	stage.move_duration = 0.05
	stage.expression_crossfade = 0.05
	root.add_child(stage)
	stage.size = Vector2(1920, 1080)
	stage.show_character("alpha", {"position": "left", "expression": "smile"})
	stage.show_character("beta_two", {"position": "right", "enter": "slide_right"})
	stage.show_character("ghost", {"position": "center"})
	await _wait(0.3)
	check(stage.shown_ids().size() == 3, "three characters on screen")
	var a := stage.get_slot("alpha")
	check(a.modulate.a > 0.99, "fade-in finished")
	check(a.layer_names() == ["chr_alpha_body_stand_maid", "chr_alpha_face_stand_smile"], "alpha layers %s" % str(a.layer_names()))
	check(absf(a.size.y - 1080 * stage.height_ratio) < 1.0 and absf(a.size.x - a.size.y * 128.0 / 192.0) < 1.0, "auto size from canvas aspect")
	check(absf(a.position.y + a.size.y - 1080) < 1.0, "bottom anchored")
	check(absf(a.position.x + a.size.x * 0.5 - 1920 * 0.25) < 1.0, "left position")
	var b := stage.get_slot("beta_two")
	check(b.size.y < a.size.y, "bible display.scale applied")
	check(stage.get_slot("ghost").is_silhouette(), "unknown id shows silhouette")
	stage.set_expression("alpha", "angry")   # registered but corrupt file
	await _wait(0.15)
	check(not a.is_silhouette() and a.layer_names() == ["chr_alpha_body_stand_maid"], "corrupt face layer skipped, body kept: %s" % str(a.layer_names()))
	stage.set_variant("alpha", {"pose": "greet", "expression": "smile"})
	await _wait(0.15)
	check(a.layer_names() == ["chr_alpha_body_greet_maid", "chr_alpha_face_greet_smile"], "pose switch")
	stage.set_outfit("alpha", "casual")
	await _wait(0.15)
	check(a.resolved["outfit"] == "maid", "greet/casual missing -> default outfit")
	stage.set_speaker("alpha")
	await _wait(0.2)
	check(b.get_child(0).modulate.r < 0.9, "non-speaker dimmed")
	stage.hide_character("beta_two", {"exit": "slide_left"})
	await _wait(0.35)
	check(not stage.is_showing("beta_two") and stage.get_slot("beta_two") == null, "exit removes slot")
	# auto layout with several crowd NPCs using the same archetype art
	stage.clear(0.0)
	await _wait(0.1)
	for i in 3:
		stage.show_character("npc-student-f", {"key": "crowd%d" % i, "outfit": "look-0%d" % (i % 2 + 1)})
	await _wait(0.2)
	var xs: Array = []
	for i in 3:
		xs.append(stage.get_slot("crowd%d" % i).x_anchor)
	check(xs == [0.25, 0.5, 0.75], "auto layout spreads evenly: %s" % str(xs))
	stage.set_expression("not-on-stage", "smile")  # must only warn
	stage.size = Vector2(1280, 720)
	await _wait(0.1)
	check(absf(stage.get_slot("crowd0").size.y - 720 * stage.height_ratio) < 1.0, "re-layout on resize")
	stage.queue_free()


func _test_npc() -> void:
	print("- npc art catalog")
	var cat := ArtCatalog.new()
	cat.load_from(ArtCatalog.DEFAULT_ROOT)
	var npc := NpcArtCatalog.new(cat)
	for aid in cat.archetypes:
		for look in cat.archetypes[aid]["looks"]:
			check(npc.check_look(cat.archetypes[aid], look).is_empty(), "%s/%s valid" % [aid, look["id"]])
	var senior := {"age_look": "senior", "body_type": "average"}
	check(not npc.check_look(senior, {"hair_style": "short", "hair_color": "gray", "outfit": "school-uniform", "accessories": []}).is_empty(), "uniform on senior rejected")
	check(not npc.check_look({"age_look": "teen", "body_type": "slim"}, {"hair_style": "short", "hair_color": "black", "outfit": "casual", "accessories": ["cane"]}).is_empty(), "cane on teen rejected")
	check(not npc.check_look(senior, {"hair_style": "short", "hair_color": "purple", "outfit": "casual", "accessories": []}).is_empty(), "unknown taxonomy value rejected")
	var twin := {"looks": [{"id": "a", "hair_style": "bob", "hair_color": "black", "outfit": "casual", "accessories": ["none"]},
		{"id": "b", "hair_style": "bob", "hair_color": "black", "outfit": "casual", "accessories": ["glasses"]}]}
	check(npc.similar_pairs(twin).size() == 1, "too-similar looks detected")
	check(npc.available_looks(true).is_empty(), "real data: no approved NPC art yet -> nothing shown as finished")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var on_screen: Array = []
	for i in 8:
		var pick := npc.pick_look({}, on_screen, rng, false)
		if pick.is_empty():
			break
		check(not on_screen.has(pick["key"]), "no duplicate look on screen")
		on_screen.append(pick["key"])
	check(on_screen.size() == 8, "8 distinct looks picked")
	var stu := npc.pick_look({"customer_type": "office-worker"}, [], rng, false)
	check(stu.get("archetype", "") == "npc-office-m", "filter by customer type")
	# with fixture art only the two baked looks are available
	var fx := NpcArtCatalog.new(_fixture_catalog())
	var keys := {}
	for i in 6:
		var p := fx.pick_look({}, [], rng, true)
		keys[p.get("key", "")] = true
	check(keys.size() == 2 and keys.has("npc-student-f/look-01") and keys.has("npc-student-f/look-02"), "only looks with art are used: %s" % str(keys.keys()))


func _test_validator_detects_problems() -> void:
	print("- validator detects problems")
	var cat := _fixture_catalog()
	var v := ArtValidator.new()
	var rep := v.run(cat)
	var codes := _codes(rep)
	check(codes.has("E_FORMAT"), "corrupt png flagged")
	check(not codes.has("E_SIZE"), "fixture sizes fine")
	# now break things on purpose
	var list: Array = ArtCatalog.read_json(FIX + "manifest.json")["assets"]
	_save("portraits/alpha/chr_alpha_face_stand_sad.png", _img(100, 100, Color.RED))           # wrong size
	_save("portraits/alpha/chr_alpha_face_stand_surprised.png", Image.create(128, 192, false, Image.FORMAT_RGBA8))  # blank
	var dup := Image.load_from_file(FIX + "portraits/alpha/chr_alpha_body_stand_maid.png")
	dup.save_png(FIX + "portraits/alpha/chr_alpha_face_stand_laugh.png")                       # duplicate content
	var opaque := Image.create(128, 192, false, Image.FORMAT_RGBA8)
	opaque.fill(Color(0.8, 0.8, 0.8, 1))
	opaque.fill_rect(Rect2i(10, 10, 50, 50), Color.BLUE)
	opaque.save_png(FIX + "portraits/alpha/chr_alpha_face_stand_embarrassed.png")              # no transparency
	var jpg := _img(128, 192, Color.GREEN)
	jpg.convert(Image.FORMAT_RGB8)
	jpg.save_jpg(FIX + "portraits/alpha/chr_alpha_face_greet_sad.png")                          # jpeg named .png
	_save("portraits/alpha/random_upload.png", _img(128, 192, Color.PURPLE))                    # unregistered + bad name
	_save("backgrounds/bg_park_day.png", _img(160, 90, Color.YELLOW, false))                   # unregistered, good name
	for e in list:
		if e["id"] in ["chr_alpha_face_stand_sad", "chr_alpha_face_stand_surprised", "chr_alpha_face_stand_laugh", "chr_alpha_face_stand_embarrassed", "chr_alpha_face_greet_sad"]:
			e["status"] = "draft"
		if e["id"] == "chr_alpha_face_greet_laugh":
			e["status"] = "approved"        # approved but no file
		if e["id"] == "chr_alpha_face_greet_tired":
			e["path"] = "portraits/alpha/Alpha Tired.png"  # naming
		if e["id"] == "chr_alpha_face_serve_sad":
			e["status"] = "approved"
			e["placeholder"] = true
	list.append(list[0].duplicate())                                                            # duplicate id + path
	var removed := ""
	for i in list.size():
		if list[i]["id"] == "chr_alpha_face_serve_tired":
			removed = list[i]["id"]
			list.remove_at(i)
			break
	_save("portraits/alpha/chr_alpha_face_serve_sad.png", _img(128, 192, Color(0.1, 0.9, 0.9)))
	_write("manifest.json", {"assets": list})
	# confirmed bible whose appearance was edited afterwards
	var b := ArtCatalog.read_json(FIX + "characters/beta_two/bible.json")
	b["appearance"] = {"summary": "test person", "hair": {"style": "bob", "color": "black"}}
	b["appearance_status"] = "confirmed"
	b["appearance_lock_hash"] = ArtValidator.appearance_hash(b)
	b["appearance"]["hair"]["color"] = "red"
	b["art"]["expressions"] = ["neutral", "smile", "wink"]
	_write("characters/beta_two/bible.json", b)

	cat = _fixture_catalog()
	rep = v.run(cat)
	codes = _codes(rep)
	for c in ["E_SIZE", "E_BLANK", "E_DUP_CONTENT", "E_ALPHA", "E_FORMAT", "E_UNREGISTERED_FILE", "E_FILE_MISSING",
			"E_NAMING", "E_DUP_ID", "E_DUP_PATH", "E_PLACEHOLDER_APPROVED", "E_REQUIRED_UNREGISTERED", "E_LOCK_CHANGED", "E_VOCAB"]:
		check(codes.has(c), "validator reports " + c)
	check(not rep["ok"], "report fails")
	var unreg: Array = rep["issues"].filter(func(i): return i["code"] == "E_UNREGISTERED_FILE").map(func(i): return i["path"])
	check(unreg.has("backgrounds/bg_park_day.png") and unreg.has("portraits/alpha/random_upload.png"), "unregistered files listed: %s" % str(unreg))
	check(removed != "", "removed one required entry")
	# the game still runs on this broken data
	var r := cat.resolve_portrait("alpha", "", "", "sad")
	check(r["layers"].size() >= 1, "broken data still resolves")


func _codes(rep: Dictionary) -> Dictionary:
	var out := {}
	for i in rep["issues"]:
		out[i["code"]] = true
	return out


func _test_prompt_builder() -> void:
	print("- prompt builder")
	var cat := ArtCatalog.new()
	cat.load_from(ArtCatalog.DEFAULT_ROOT)
	var pb := ArtPromptBuilder.new(cat)
	var r := pb.build("chr_koharu_face_stand_smile")
	check(not r["ok"] and r["blocked"].contains("not confirmed"), "unconfirmed character blocked")
	r = pb.build("chr_koharu_face_stand_smile", true)
	check(r["ok"] and r["warnings"].size() > 0 and r["prompt"].contains("gentle smile"), "exploration prompt with warning")
	r = pb.build("chr_npc-office-m_body_stand_look-02")
	check(r["ok"] and r["prompt"].contains("slicked") and r["canvas"].begins_with("1024x1536"), "archetype prompt: %s" % r["prompt"])
	r = pb.build("bg_park_day")
	check(r["ok"] and r["negative"].contains("people"), "background prompt")


# ------------------------------------------------------------- workshop / maker

func _test_recipe() -> void:
	print("- portrait recipe")
	var r := PortraitRecipe.normalized({"hair_color": "#112233", "scale": 5.0, "outfits": {"maid": {"main": "#000000"}, "swim": {"style": "sailor"}}})
	check(r["hair_color"] == "#112233" and r["bangs"] == PortraitRecipe.DEFAULT["bangs"], "recipe keeps given values and fills defaults")
	check(is_equal_approx(r["scale"], 1.1), "recipe scale is clamped")
	check(r["outfits"]["maid"]["main"] == "#000000" and r["outfits"]["maid"]["style"] == "classic", "outfit overrides merge with defaults")
	check(r["outfits"]["swim"]["style"] == "sailor" and r["outfits"]["swim"].has("ribbon"), "unknown outfit gets default fields")
	check(PortraitRecipe.DEFAULT["outfits"]["maid"]["main"] == "#2e2a3a", "normalizing never mutates the defaults")
	var spec := ArtCatalog.read_json("res://art/art_spec.json")
	for ex in spec["vocab"]["expressions"]:
		check(PortraitRecipe.EXPRESSIONS.has(ex), "maker can draw expression " + str(ex))
	var fr := PortraitRecipe.face_rect({})
	check(Rect2i(0, 0, 1024, 1536).encloses(fr) and fr.size.x > 100, "face patch rect lies inside the canvas")


func _test_library() -> void:
	print("- art library (workshop backend)")
	var cat := _fixture_catalog()
	var lib := ArtLibrary.new(cat)
	var slots := lib.slots_for("alpha")
	check(slots.size() > 10, "alpha has slots (%d)" % slots.size())
	check(lib.asset_id_for_filename("chr_alpha_face_stand_sad.png") == "chr_alpha_face_stand_sad", "file name -> asset id")
	check(lib.asset_id_for_filename("holiday.png") == "", "free file name is not matched to a slot")

	# import: opaque image is refused, then accepted with background removal, and resized to the canvas
	var src := "user://art_test_fixture/_import_src.png"
	var img := Image.create(300, 600, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	img.fill_rect(Rect2i(100, 100, 100, 500), Color(0.8, 0.2, 0.3, 1))
	img.save_png(src)
	var id := "chr_alpha_body_serve_maid"
	var res := lib.import_image(id, src)
	check(not res["ok"] and str(res["error"]) != "", "opaque portrait refused without background removal")
	check(not FileAccess.file_exists(FIX + "portraits/alpha/%s.png" % id), "refused import writes nothing")
	res = lib.import_image(id, src, {"remove_bg": true})
	check(res["ok"], "import with background removal ok: " + str(res["error"]))
	var out := Image.load_from_file(FIX + "portraits/alpha/%s.png" % id)
	check(out != null and out.get_width() == 128 and out.get_height() == 192, "imported image fitted to the canvas")
	if out != null:
		check(out.get_pixel(2, 2).a < 0.05, "background became transparent")
		check(out.get_pixel(64, 150).a > 0.9 and out.get_pixel(64, 150).r > 0.6, "subject kept, anchored to the bottom")
	cat = _fixture_catalog()
	lib = ArtLibrary.new(cat)
	var e: Dictionary = cat.assets.get(id, {})
	check(e.get("status", "") == "draft", "import is registered as draft, never approved")
	var v := ArtValidator.new()
	var rep := v.run(cat)
	var bad := false
	for it in rep["issues"]:
		if str(it["path"]).contains(id) and it["level"] == "error":
			bad = true
	check(not bad, "imported asset passes the validator")
	check(not cat.resolve_portrait("alpha", "serve", "maid", "neutral")["silhouette"], "imported body is used by the portrait system")

	# status changes
	check(lib.set_status(id, "approved") == "", "draft -> approved")
	check(lib.set_status("chr_alpha_face_serve_sad", "approved") != "", "cannot approve a slot without an image")
	check(lib.clear_slot(id) == "", "clear slot")
	check(not FileAccess.file_exists(FIX + "portraits/alpha/%s.png" % id), "clear removes the file")
	check(_fixture_catalog().assets[id]["status"] == "missing", "cleared slot is missing again")
	check(lib.import_image("not a valid name", src)["ok"] == false, "bad asset id refused")
	check(lib.import_image(id, "user://nope.png")["ok"] == false, "unreadable file refused")

	# add character
	check(lib.add_character("Bad Id", "x", "S") != "", "invalid id refused")
	check(lib.add_character("alpha", "x", "S") != "", "duplicate id refused")
	check(lib.add_character("gamma_new", "測試丙", "A") == "", "add character")
	cat = _fixture_catalog()
	lib = ArtLibrary.new(cat)
	check(cat.has_character("gamma_new") and cat.owner_of("gamma_new") == "gamma-new", "new character is indexed")
	check(lib.slots_for("gamma_new").size() >= 4, "new character has slots")
	check(cat.resolve_portrait("gamma_new", "", "", "")["silhouette"], "new character shows the missing-art silhouette")
	check(str(cat.characters["gamma_new"]["appearance"]["summary"]) == "TBD", "new character appearance is left TBD")

	# lock / unlock
	check(lib.lock_appearance("gamma_new") != "", "cannot lock while fields are TBD")
	var b: Dictionary = cat.characters["gamma_new"].duplicate(true)
	b["appearance"] = {"summary": "短髮", "hair": {"style": "短髮", "color": "黑"}}
	check(lib.save_bible("gamma_new", b) == "", "save bible")
	check(lib.lock_appearance("gamma_new") == "", "lock filled appearance")
	check(str(cat.characters["gamma_new"]["appearance_status"]) == "confirmed", "locked -> confirmed")
	var changed: Dictionary = cat.characters["gamma_new"].duplicate(true)
	changed["appearance"]["summary"] = "長髮"
	check(lib.save_bible("gamma_new", changed) != "", "locked appearance cannot be changed")
	rep = ArtValidator.new().run(_fixture_catalog())
	var lock_ok := true
	for it in rep["issues"]:
		if it["code"] in ["E_LOCK_CHANGED", "E_LOCK_TBD"] and str(it["message"]).begins_with("gamma_new"):
			lock_ok = false
	check(lock_ok, "lock hash written by the library validates")
	check(lib.unlock_appearance("gamma_new") == "", "unlock")
	changed["appearance_status"] = "unconfirmed"
	changed["appearance_lock_hash"] = ""
	check(lib.save_bible("gamma_new", changed) == "", "edit after unlock")

	# recipes
	check(not lib.has_recipe("alpha"), "no recipe yet")
	var rec := lib.load_recipe("alpha")
	check(rec["outfits"].has("maid") and rec["outfits"].has("casual"), "default recipe covers the bible's outfits")
	rec["hair_back"] = "bob"
	check(lib.save_recipe("alpha", rec) and lib.has_recipe("alpha"), "save recipe")
	check(lib.load_recipe("alpha")["hair_back"] == "bob", "recipe round-trips")


func _test_maker_render() -> void:
	print("- portrait maker render")
	if DisplayServer.get_name() == "headless":
		print("  (skipped: needs a renderer; run without --headless)")
		return
	var cat := _fixture_catalog()
	var lib := ArtLibrary.new(cat)
	var ex := PortraitExporter.new()
	root.add_child(ex)
	var rec := PortraitRecipe.normalized({})
	var img: Image = await ex.render(rec, "stand", "maid", "smile")
	check(img.get_width() == 1024 and img.get_height() == 1536, "render is on the spec canvas")
	check(img.get_pixel(4, 4).a < 0.02, "render background is transparent")
	check(img.get_pixel(512, 420).a > 0.95, "face is opaque")
	var other: Image = await ex.render(rec, "stand", "maid", "angry")
	check(img.get_pixel(512, 440) != other.get_pixel(512, 440) or img.get_data() != other.get_data(), "expressions differ")
	var face: Image = await ex.render_face(rec, "stand", "maid", "smile")
	var fr := PortraitRecipe.face_rect(rec)
	check(face.get_pixel(512, 1400).a == 0.0 and face.get_pixelv(fr.get_center()).a > 0.9, "face patch only covers the face")
	var out: Dictionary = await ex.export_character(lib, "alpha", rec)
	check(out["ok"] > 0 and out["failed"].is_empty(), "export alpha: %s" % str(out))
	var c2 := _fixture_catalog()
	var res := c2.resolve_portrait("alpha", "point", "casual", "sad")
	check(not res["silhouette"], "exported character resolves to real images")
	for e in c2.manifest_list:
		if str(e.get("source", "")) == "portrait-maker":
			check(e["status"] == "draft", e["id"] + " exported as draft")
	ex.queue_free()
