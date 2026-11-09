class_name PortraitSlot
extends Control
## One character on a PortraitStage.
##
## Node layout:  PortraitSlot (placed by the stage)
##                 └ Motion (enter/exit offsets, speaker dimming)
##                     └ Layers (one per variant; cross-faded on change)
##                         ├ TextureRect body / full
##                         └ TextureRect face patch
## All layers share one canvas size, so they are simply stacked full-rect.

signal entered
signal exited

var character_id := ""
var catalog: ArtCatalog
var resolved: Dictionary = {}
var x_anchor := 0.5          ## centre of the portrait, as a fraction of stage width
var auto_position := true    ## laid out automatically by the stage
var leaving := false
var show_missing_label := true

var _motion: Control
var _current: Control
var _fade_tween: Tween
var _move_tween: Tween
var _swap_tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motion = Control.new()
	_motion.name = "Motion"
	_motion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motion.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_motion)


func setup(id: String, cat: ArtCatalog) -> void:
	character_id = id
	catalog = cat
	name = "Portrait_" + id.validate_node_name()


## Pick and show images for the given variants. Empty string = keep current
## (or the character's default the first time).
func apply_variant(pose := "", outfit := "", expression := "", crossfade := 0.0) -> Dictionary:
	var cur: Dictionary = resolved.get("requested", {})
	var p := pose if pose != "" else str(cur.get("pose", ""))
	var o := outfit if outfit != "" else str(cur.get("outfit", ""))
	var e := expression if expression != "" else str(cur.get("expression", ""))
	var r := catalog.resolve_portrait(character_id, p, o, e)
	if not resolved.is_empty() and r.get("layers", []) == resolved.get("layers", []) \
			and r.get("silhouette", false) == resolved.get("silhouette", false) and _current != null:
		resolved = r
		return r
	resolved = r
	_swap_layers(_build_layers(r), crossfade)
	return r


func _build_layers(r: Dictionary) -> Control:
	var box := Control.new()
	box.name = "Layers"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	var drew := false
	for path in r.get("layers", []):
		var tex := PortraitTextures.load_texture(str(path))
		if tex == null:
			continue  # a broken file degrades to whatever layers did load
		box.add_child(_rect(tex, str(path).get_file().get_basename()))
		drew = true
	if not drew:
		r["silhouette"] = true
		box.add_child(_rect(PortraitTextures.silhouette(), "Silhouette"))
		if show_missing_label:
			var lbl := Label.new()
			lbl.name = "MissingLabel"
			var nm := catalog.display_name(character_id) if catalog else character_id
			lbl.text = "%s\n[MISSING ART]\n%s / %s / %s" % [nm, r["requested"].get("pose", ""), r["requested"].get("outfit", ""), r["requested"].get("expression", "")]
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
			lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			lbl.add_theme_constant_override("outline_size", 6)
			lbl.add_theme_font_size_override("font_size", 22)
			lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(lbl)
	return box


func _rect(tex: Texture2D, n: String) -> TextureRect:
	var t := TextureRect.new()
	t.name = n
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	return t


func _swap_layers(next: Control, crossfade: float) -> void:
	var old := _current
	_current = next
	_motion.add_child(next)
	if _swap_tween:
		_swap_tween.kill()
	if old == null or crossfade <= 0.0 or not is_inside_tree():
		if old:
			old.queue_free()
		return
	next.modulate.a = 0.0
	_swap_tween = create_tween()
	_swap_tween.tween_property(next, "modulate:a", 1.0, crossfade)
	_swap_tween.tween_callback(old.queue_free)


## Canvas aspect from the spec so every character uses the same framing.
func canvas_aspect() -> float:
	var c: Dictionary = catalog.spec.get("canvases", {}).get("portrait", {}) if catalog else {}
	var w := float(c.get("width", 1024))
	var h := float(c.get("height", 1536))
	return w / h if h > 0 else 2.0 / 3.0


## Size and place the portrait inside a stage of `stage_size`.
func layout(stage_size: Vector2, height_ratio: float, duration := 0.0) -> void:
	var disp: Dictionary = resolved.get("display", {})
	var scale_f := float(disp.get("scale", 1.0))
	var y_off := float(disp.get("y_offset", 0.0))
	var h := stage_size.y * height_ratio * scale_f
	var w := h * canvas_aspect()
	size = Vector2(w, h)
	var target := Vector2(stage_size.x * x_anchor - w * 0.5, stage_size.y - h + y_off * stage_size.y)
	if _move_tween:
		_move_tween.kill()
	if duration <= 0.0 or not is_inside_tree():
		position = target
	else:
		_move_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_move_tween.tween_property(self, "position", target, duration)


## Enter animation: "fade", "slide_left", "slide_right", "rise", "none".
func play_enter(style := "fade", duration := 0.25) -> void:
	leaving = false
	if style == "none" or duration <= 0.0 or not is_inside_tree():
		modulate.a = 1.0
		_motion.position = Vector2.ZERO
		entered.emit()
		return
	modulate.a = 0.0
	_motion.position = _offset_for(style)
	_kill_fade()
	_fade_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(self, "modulate:a", 1.0, duration)
	_fade_tween.tween_property(_motion, "position", Vector2.ZERO, duration)
	_fade_tween.chain().tween_callback(func(): entered.emit())


## Exit animation; emits `exited` when done (the stage then frees the slot).
func play_exit(style := "fade", duration := 0.25) -> void:
	leaving = true
	_kill_fade()
	if style == "none" or duration <= 0.0 or not is_inside_tree():
		modulate.a = 0.0
		exited.emit()
		return
	_fade_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_fade_tween.tween_property(self, "modulate:a", 0.0, duration)
	_fade_tween.tween_property(_motion, "position", _offset_for(style), duration)
	_fade_tween.chain().tween_callback(func(): exited.emit())


func _kill_fade() -> void:
	if _fade_tween:
		_fade_tween.kill()


func _offset_for(style: String) -> Vector2:
	match style:
		"slide_left":
			return Vector2(-size.x * 0.35, 0)
		"slide_right":
			return Vector2(size.x * 0.35, 0)
		"rise":
			return Vector2(0, size.y * 0.06)
	return Vector2.ZERO


## Dim non-speaking characters.
func set_focused(focused: bool, duration := 0.15) -> void:
	var target := Color.WHITE if focused else Color(0.62, 0.62, 0.68)
	if duration <= 0.0 or not is_inside_tree():
		_motion.modulate = target
		return
	create_tween().tween_property(_motion, "modulate", target, duration)


func is_silhouette() -> bool:
	return bool(resolved.get("silhouette", false))


func layer_names() -> Array:
	var out: Array = []
	if _current:
		for c in _current.get_children():
			out.append(str(c.name))
	return out
