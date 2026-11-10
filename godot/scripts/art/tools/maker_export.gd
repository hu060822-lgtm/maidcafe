extends SceneTree
## Batch-render Portrait Maker recipes into the art library (status "draft").
## Needs a renderer, so run WITHOUT --headless:
##   godot --path godot -s res://scripts/art/tools/maker_export.gd -- [character-id ...]
## With no ids, every character that has characters/<id>/maker.json is exported.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = []
	var art_root := ArtCatalog.DEFAULT_ROOT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--root="):
			art_root = a.substr(7)
		elif not a.begins_with("--"):
			ids.append(a)
	var cat := ArtCatalog.new()
	cat.load_from(art_root)
	var lib := ArtLibrary.new(cat)
	if ids.is_empty():
		for id in cat.character_order:
			if lib.has_recipe(id):
				ids.append(id)
	var ex := PortraitExporter.new()
	root.add_child(ex)
	var failed := 0
	for id in ids:
		var r: Dictionary = await ex.export_character(lib, id, lib.load_recipe(id))
		print("%s: %d images" % [id, r["ok"]])
		for f in r["failed"]:
			printerr("  ", f)
			failed += 1
	quit(1 if failed > 0 else 0)
