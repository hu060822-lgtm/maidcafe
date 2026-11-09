class_name ArtPromptBuilder
extends RefCounted
## Builds AI-generation prompts for a manifest asset from art_spec + the
## character bible, so every image starts from the same confirmed data.
## Characters whose appearance is not confirmed are blocked unless the caller
## explicitly asks for a draft/exploration prompt.

var catalog: ArtCatalog


func _init(cat: ArtCatalog) -> void:
	catalog = cat


func build(asset_id: String, allow_unconfirmed := false) -> Dictionary:
	var out := {"ok": false, "asset": asset_id, "prompt": "", "negative": "", "canvas": "", "steps": [], "warnings": [], "blocked": ""}
	var e: Dictionary = catalog.assets.get(asset_id, {})
	if e.is_empty():
		var parsed := catalog.parse_filename(asset_id + ".png")
		if parsed.is_empty():
			out["blocked"] = "unknown asset id '%s'" % asset_id
			return out
		e = catalog.make_entry(parsed["kind"], parsed["fields"])
	var kind := str(e["kind"])
	var style: Dictionary = catalog.spec.get("style_guide", {})
	var vocab: Dictionary = catalog.spec.get("vocab", {})
	var canvas_name := str(catalog.spec.get("naming", {}).get(kind, {}).get("canvas", ""))
	var c: Dictionary = catalog.spec.get("canvases", {}).get(canvas_name, {})
	out["canvas"] = "%sx%s %s%s" % [c.get("width", "?"), c.get("height", "?"), c.get("format", "png"), ", transparent background" if c.get("alpha", false) else ""]
	out["negative"] = str(style.get("negative_prompt", ""))
	var parts := PackedStringArray([str(style.get("positive_prompt", ""))])

	if kind.begins_with("portrait_"):
		var owner := str(e.get("owner", ""))
		var cid := ""
		for id in catalog.character_order:
			if catalog.owner_of(id) == owner:
				cid = id
		if cid != "":
			var b: Dictionary = catalog.characters[cid]
			var confirmed := str(b.get("appearance_status", "")) == "confirmed"
			if not confirmed:
				if not allow_unconfirmed:
					out["blocked"] = "%s's appearance is not confirmed in the bible. Fill in and confirm the bible first (or pass --allow-unconfirmed for exploration sketches that will never be approved)." % cid
					return out
				out["warnings"].append("UNCONFIRMED appearance: output may only be used as exploration, never as an approved asset")
			var outfit := str(e.get("outfit", catalog.get_art_profile(cid).get("default", {}).get("outfit", "")))
			parts.append(_character_block(b, outfit))
			if b.get("references", []).size() > 0:
				out["steps"].append("Use the bible reference images as image prompt / IP-Adapter / character LoRA input: %s" % str(b["references"]))
			else:
				out["warnings"].append("no reference image in the bible: consistency between images will be weak")
		elif catalog.archetypes.has(owner):
			parts.append(_archetype_block(catalog.archetypes[owner], str(e.get("outfit", ""))))
		else:
			out["blocked"] = "owner '%s' not found" % owner
			return out
		if e.has("pose"):
			parts.append(str(vocab.get("poses", {}).get(e["pose"], {}).get("prompt", e["pose"])))
		var ex := str(e.get("expression", "neutral"))
		parts.append(str(vocab.get("expressions", {}).get(ex, {}).get("prompt", ex)))
		match kind:
			"portrait_body":
				out["steps"].append("Generate the full half-body portrait with a neutral face; this is the base layer.")
			"portrait_face":
				out["steps"].append("img2img / inpaint ONLY the face region of the approved body layer for this pose; keep hair, outline and colours identical.")
				out["steps"].append("Export the face patch on the full canvas (everything outside the face region transparent).")
			"portrait_full":
				out["steps"].append("Generate from the approved body layer with img2img so the outfit and proportions stay identical.")
		out["steps"].append("Align to the portrait guides in art_spec.json (head top / eye line / centre), remove background, export RGBA PNG.")
	elif kind == "background":
		var loc := str(e.get("location", ""))
		parts.append("background art, no people, %s, %s" % [loc, str(vocab.get("times", {}).get(e.get("time", ""), e.get("time", "")))])
		out["negative"] += ", people, characters"
	elif kind == "cg":
		out["warnings"].append("CG composition must come from the event script; list the characters and use each one's confirmed bible block")
		parts.append("event illustration '%s'" % e.get("event", ""))
	elif kind == "ui":
		parts = PackedStringArray(["game UI element '%s/%s', flat, clean edges, matching the cafe theme" % [e.get("group", ""), e.get("name", "")]])
	out["prompt"] = ", ".join(parts)
	out["ok"] = true
	return out


func _character_block(b: Dictionary, outfit: String) -> String:
	var a: Dictionary = b.get("appearance", {})
	var bits := PackedStringArray()
	bits.append("1 character: %s" % str(a.get("summary", "TBD")))
	bits.append("age look %s" % str(a.get("age_look", "TBD")))
	bits.append("%s %s hair" % [a.get("hair", {}).get("color", "TBD"), a.get("hair", {}).get("style", "TBD")])
	bits.append("%s eyes" % str(a.get("eyes", {}).get("color", "TBD")))
	bits.append("build: %s" % str(a.get("body", {}).get("build", "TBD")))
	var od := str(a.get("outfits", {}).get(outfit, {}).get("design", "TBD"))
	bits.append("wearing %s" % od)
	bits.append("accessories: %s" % str(a.get("accessories", "TBD")))
	bits.append("colour palette: %s" % str(a.get("signature_colors", "TBD")))
	return ", ".join(bits)


func _archetype_block(a: Dictionary, look_id: String) -> String:
	var look: Dictionary = {}
	for l in a.get("looks", []):
		if str(l.get("id", "")) == look_id:
			look = l
	var acc: Array = look.get("accessories", [])
	return "1 %s %s person, %s %s hair, %s outfit, accessories: %s" % [
		str(a.get("age_look", "")).replace("_", " "), a.get("body_type", ""),
		look.get("hair_color", ""), look.get("hair_style", ""), look.get("outfit", ""),
		", ".join(PackedStringArray(acc.map(func(x): return str(x))))]
