extends SceneTree
## Art pipeline command line.  Run from the godot/ folder:
##
##   godot --headless -s res://scripts/art/tools/art_cli.gd -- <command> [options]
##
## Commands
##   validate [--strict] [--complete] [--show-missing] [--json=<file>]
##       Check images, formats, sizes, naming, duplicates, unregistered files,
##       bible rules and NPC rules. Exit code 1 on failure.
##   sync [--register-found]
##       Add every asset the bibles/spec require to manifest.json (status
##       "missing"). --register-found also registers correctly named image
##       files that are on disk but not in the manifest, as "draft".
##   status [--out=<file>]
##       Write a Markdown progress table (default ../docs/art/ASSET_STATUS.md).
##   prompt <asset-id> [--allow-unconfirmed]
##       Print the generation prompt for one asset, built from spec + bible.
##   new-character <id> <tier S|A|B> <name> [--role=<role>]
##       Create an empty bible (all appearance fields TBD) and index entry.
##   lock <character-id>
##       Mark a fully filled-in appearance as confirmed. After this, any edit
##       to the appearance block fails validation until it is re-locked.
##   --root=<res://path/>  use another art root (tests).

var catalog: ArtCatalog
var opts := {}
var args: Array = []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
		else:
			args.append(a)
	catalog = ArtCatalog.new()
	catalog.load_from(str(opts.get("root", ArtCatalog.DEFAULT_ROOT)))
	var cmd := str(args[0]) if args.size() > 0 else "validate"
	var code := 0
	match cmd:
		"validate":
			code = _validate()
		"sync":
			code = _sync()
		"status":
			code = _status()
		"prompt":
			code = _prompt()
		"new-character":
			code = _new_character()
		"lock":
			code = _lock()
		_:
			printerr("unknown command '%s'" % cmd)
			code = 2
	quit(code)


func _validate() -> int:
	var v := ArtValidator.new()
	v.strict = opts.has("strict")
	v.require_complete = opts.has("complete")
	var rep := v.run(catalog)
	print(v.format_text(rep, opts.has("show-missing")))
	if opts.has("json"):
		_write_text(str(opts["json"]), JSON.stringify(rep, "  "))
	return 0 if rep["ok"] else 1


func _sync() -> int:
	var path := catalog.root + "manifest.json"
	var manifest := ArtCatalog.read_json(path)
	if manifest.is_empty():
		manifest = {"_doc": "Asset manifest. One entry per image. Edit status by hand (missing -> draft -> approved); run 'art_cli sync' to add planned entries.", "assets": []}
	var list: Array = manifest.get("assets", [])
	var have := {}
	for e in list:
		have[str(e.get("id", ""))] = true
	var added := 0
	for r in catalog.required_assets():
		if not have.has(r["id"]):
			list.append(r)
			have[r["id"]] = true
			added += 1
	var registered := 0
	if opts.has("register-found"):
		var known := {}
		for e in list:
			known[str(e.get("path", "")).to_lower()] = true
		for cid in catalog.characters:
			for ref in catalog.characters[cid].get("references", []):
				known[str(ref.get("path", "") if typeof(ref) == TYPE_DICTIONARY else ref).to_lower()] = true
		for rel in ArtValidator.list_image_files(catalog.root):
			if known.has(rel.to_lower()):
				continue
			var parsed := catalog.parse_filename(rel.get_file())
			if parsed.is_empty() or parsed["kind"] == "reference":
				print("skip (bad name or reference): ", rel)
				continue
			var entry := catalog.make_entry(parsed["kind"], parsed["fields"], "draft")
			if entry["path"] != rel:
				print("skip (wrong folder, expected %s): %s" % [entry["path"], rel])
				continue
			if have.has(entry["id"]):
				continue
			list.append(entry)
			registered += 1
	list.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	manifest["assets"] = list
	_write_text(path, JSON.stringify(manifest, "  ", false) + "\n")
	print("manifest: %d entries (%d planned added, %d found files registered as draft)" % [list.size(), added, registered])
	return 0


func _status() -> int:
	var out := str(opts.get("out", ProjectSettings.globalize_path("res://").path_join("../docs/art/ASSET_STATUS.md").simplify_path()))
	var prog := catalog.progress()
	var lines := PackedStringArray()
	lines.append("# 美術素材進度")
	lines.append("")
	lines.append("由 `art_cli status` 自動產生，請勿手動編輯。")
	lines.append("")
	lines.append("| 擁有者 | 名稱 | Tier | 外觀 | 需求 | 完成 | 草稿 | 缺少 |")
	lines.append("|---|---|---|---|---:|---:|---:|---:|")
	var tot := {"required": 0, "approved": 0, "draft": 0, "missing": 0}
	var keys := prog.keys()
	keys.sort()
	for k in keys:
		var p: Dictionary = prog[k]
		var name := str(k)
		var tier := "-"
		var look := "-"
		for cid in catalog.character_order:
			if catalog.owner_of(cid) == k:
				var b: Dictionary = catalog.characters[cid]
				name = str(b.get("name", cid))
				tier = str(b.get("tier", "-"))
				look = "已確認" if str(b.get("appearance_status", "")) == "confirmed" else "待確認"
		if catalog.archetypes.has(k):
			name = "NPC 原型"
			look = "提案" if str(catalog.archetypes[k].get("status", "")) == "proposal" else "已核准"
		lines.append("| `%s` | %s | %s | %s | %d | %d | %d | %d |" % [k, name, tier, look, p["required"], p["approved"], p["draft"], p["missing"]])
		for t in tot:
			tot[t] += int(p[t])
	lines.append("| **合計** | | | | **%d** | **%d** | **%d** | **%d** |" % [tot["required"], tot["approved"], tot["draft"], tot["missing"]])
	_write_text(out, "\n".join(lines) + "\n")
	print("wrote ", out)
	return 0


func _prompt() -> int:
	if args.size() < 2:
		printerr("usage: prompt <asset-id>")
		return 2
	var r := ArtPromptBuilder.new(catalog).build(str(args[1]), opts.has("allow-unconfirmed"))
	if not r["ok"]:
		printerr("BLOCKED: ", r["blocked"])
		return 1
	print("ASSET:    ", r["asset"])
	print("CANVAS:   ", r["canvas"])
	print("PROMPT:   ", r["prompt"])
	print("NEGATIVE: ", r["negative"])
	for s in r["steps"]:
		print("STEP:     ", s)
	for w in r["warnings"]:
		print("WARNING:  ", w)
	return 0


func _new_character() -> int:
	if args.size() < 4:
		printerr("usage: new-character <id> <tier> <name>")
		return 2
	var id := str(args[1])
	var tier := str(args[2])
	var tiers: Dictionary = catalog.spec.get("tiers", {})
	if not tiers.has(tier):
		printerr("tier must be one of ", tiers.keys())
		return 2
	if catalog.has_character(id):
		printerr("character '%s' already exists" % id)
		return 1
	var t: Dictionary = tiers[tier]
	var outfits := {}
	for o in t["default_outfits"]:
		outfits[o] = {"design": "TBD"}
	var owner := id.replace("_", "-")
	var bible := {
		"id": id, "name": str(args[3]), "role": str(opts.get("role", "TBD")), "tier": tier, "tier_confirmed": false,
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
		"references": [],
		"open_questions": ["外貌尚未確認"],
		"changelog": [{"revision": 0, "date": Time.get_date_string_from_system(), "note": "建立空白設定"}],
	}
	_write_text(catalog.root + "characters/%s/bible.json" % id, JSON.stringify(bible, "  ", false) + "\n")
	var index := ArtCatalog.read_json(catalog.root + "characters/index.json")
	var chars: Array = index.get("characters", [])
	chars.append({"id": id, "bible": "characters/%s/bible.json" % id})
	index["characters"] = chars
	_write_text(catalog.root + "characters/index.json", JSON.stringify(index, "  ", false) + "\n")
	print("created characters/%s/bible.json — fill in the appearance, then run 'sync'" % id)
	return 0


func _lock() -> int:
	if args.size() < 2:
		printerr("usage: lock <character-id>")
		return 2
	var id := str(args[1])
	if not catalog.has_character(id):
		printerr("unknown character ", id)
		return 1
	var path := catalog.root + "characters/%s/bible.json" % id
	var b := ArtCatalog.read_json(path)
	if ArtValidator.contains_tbd(b.get("appearance", {})):
		printerr("appearance still has TBD fields; fill them in before locking")
		return 1
	var rev := int(b.get("bible_revision", 0)) + 1
	b["bible_revision"] = rev
	b["appearance_status"] = "confirmed"
	b["appearance_lock_hash"] = ArtValidator.appearance_hash(b)
	var log: Array = b.get("changelog", [])
	log.append({"revision": rev, "date": Time.get_date_string_from_system(), "note": str(opts.get("note", "外觀確認並鎖定"))})
	b["changelog"] = log
	_write_text(path, JSON.stringify(b, "  ", false) + "\n")
	print("locked %s at revision %d" % [id, rev])
	return 0


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write ", path)
		return
	f.store_string(text)
	f.close()
