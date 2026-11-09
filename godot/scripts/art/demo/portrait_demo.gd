extends Control
## Portrait system demo / manual test bench.  Open scenes/art/portrait_demo.tscn.
##
## Keys:  1-8 expression   P pose   O outfit   Tab next speaker
##        A add next character   X remove speaker   C clear
##
## Command line (after "--"):  --art-root=<res:// or user:// path>  --screenshot=<png path>

var stage: PortraitStage
var catalog: ArtCatalog
var info: Label
var ids: Array = []
var speaker_i := 0
var next_i := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	catalog = ArtCatalog.new()
	catalog.load_from(str(opts.get("art-root", ArtCatalog.DEFAULT_ROOT)))

	var bg := ColorRect.new()
	bg.color = Color(0.93, 0.88, 0.84)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	stage = PortraitStage.new()
	stage.catalog = catalog
	add_child(stage)

	var box := PanelContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -170
	box.offset_left = 120
	box.offset_right = -120
	box.offset_bottom = -24
	add_child(box)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 24)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)

	ids = catalog.character_order.duplicate()
	for i in mini(3, ids.size()):
		_add_next()
	speaker_i = 0
	_focus()
	if opts.has("screenshot"):
		_shoot(str(opts["screenshot"]), opts)


func _add_next() -> void:
	if ids.is_empty():
		return
	var id: String = ids[next_i % ids.size()]
	next_i += 1
	stage.show_character(id, {"enter": "slide_left" if next_i % 2 == 0 else "fade"})


func _current() -> String:
	var shown := stage.shown_ids()
	if shown.is_empty():
		return ""
	return shown[speaker_i % shown.size()]


func _focus() -> void:
	var id := _current()
	stage.set_speaker(id)
	var slot := stage.get_slot(id)
	if slot == null:
		info.text = "（沒有角色）  A 新增角色"
		return
	var r := slot.resolved
	info.text = "%s　pose:%s outfit:%s expression:%s%s\n%s\n1-8 表情  P 姿勢  O 服裝  Tab 換人  A 新增  X 退場  C 清空" % [
		catalog.display_name(id), r.get("pose", ""), r.get("outfit", ""), r.get("expression", ""),
		"　[缺素材，顯示預設剪影]" if slot.is_silhouette() else "",
		("備援：" + ", ".join(PackedStringArray(r.get("fallbacks", [])))) if not r.get("fallbacks", []).is_empty() else ""]


func _cycle(id: String, key: String, list_key: String) -> void:
	var prof := catalog.get_art_profile(id)
	var lst: Array = prof.get(list_key, [])
	if lst.is_empty():
		return
	var cur := str(stage.get_slot(id).resolved.get("requested", {}).get(key, ""))
	var nxt: String = lst[(lst.find(cur) + 1) % lst.size()]
	stage.set_variant(id, {key: nxt})


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var id := _current()
	var k: int = event.keycode
	if k >= KEY_1 and k <= KEY_8 and id != "":
		var ex: Array = catalog.get_art_profile(id).get("expressions", [])
		var n := k - KEY_1
		if n < ex.size():
			stage.set_expression(id, ex[n])
	elif k == KEY_P and id != "":
		_cycle(id, "pose", "poses")
	elif k == KEY_O and id != "":
		_cycle(id, "outfit", "outfits")
	elif k == KEY_TAB:
		speaker_i += 1
	elif k == KEY_A:
		_add_next()
	elif k == KEY_X and id != "":
		stage.hide_character(id)
	elif k == KEY_C:
		stage.clear()
	await get_tree().create_timer(0.35).timeout
	_focus()


func _shoot(path: String, opts: Dictionary) -> void:
	await get_tree().create_timer(0.6).timeout
	if opts.has("smile"):
		stage.set_expression(_current(), str(opts["smile"]))
		await get_tree().create_timer(0.4).timeout
		_focus()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
