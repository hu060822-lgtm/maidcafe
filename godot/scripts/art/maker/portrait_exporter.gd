class_name PortraitExporter
extends PortraitRenderer
## Renders every portrait slot of a character from its maker recipe and
## stores the images in the art library as "draft".

signal progress(done: int, total: int, asset_id: String)


## Returns {ok: int, failed: [messages]}
func export_character(lib: ArtLibrary, character_id: String, recipe: Dictionary) -> Dictionary:
	var prof := lib.catalog.get_art_profile(character_id)
	var result := {"ok": 0, "failed": []}
	if prof.is_empty():
		result["failed"].append("unknown character " + character_id)
		return result
	var slots: Array = []
	for s in lib.slots_for(character_id):
		if str(s.get("kind", "")) in ["portrait_body", "portrait_face"]:
			slots.append(s)
	var default_outfit := str(prof["default"]["outfit"])
	var default_expr := str(prof["default"]["expression"])
	var done := 0
	for s in slots:
		var img: Image
		if s["kind"] == "portrait_body":
			img = await render(recipe, str(s["pose"]), str(s["outfit"]), default_expr)
		else:
			img = await render_face(recipe, str(s["pose"]), default_outfit, str(s["expression"]))
		var r := lib.store_image(str(s["id"]), img, "portrait-maker", {"save": false})
		if r["ok"]:
			result["ok"] += 1
		else:
			result["failed"].append("%s: %s" % [s["id"], r["error"]])
		done += 1
		progress.emit(done, slots.size(), str(s["id"]))
	lib.save_manifest()
	return result
