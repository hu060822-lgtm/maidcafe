extends Control
## Creator Workshop (創作者工作坊): manage, import and create character portraits
## without touching JSON or file names by hand.
##
## Open scenes: res://scripts/art/workshop/creator_workshop.tscn
## * 素材  – every image slot of a character; import by button or drag & drop
## * 產生器 – Portrait Maker: build a portrait from options and export all slots
## * 角色設定 – edit the Character Bible, confirm / lock the appearance
##
## Command line (after "--"): --art-root=<path>  --tab=<0..2>  --character=<id>  --screenshot=<png>

const PINK := Color("f58aa8")
const PINK_DARK := Color("d9567c")
const CREAM := Color("fff6ef")
const PANEL := Color("ffffff")
const INK := Color("5a3a48")
const STATUS_COLORS := {"missing": Color("c9bcc4"), "draft": Color("f5b84a"), "approved": Color("5cc48a"), "deprecated": Color("9a9a9a")}
const GAME_FONT := "res://ui/fonts/jf-openhuninn-2.1.ttf"
const STATUS_LABELS := {"missing": "缺少", "draft": "草稿", "approved": "完成", "deprecated": "停用"}

var catalog: ArtCatalog
var lib: ArtLibrary
var current := ""
var selected_slot := ""
var recipe: Dictionary = {}
var preview_state := {"pose": "", "outfit": "", "expression": ""}
var font_scale := 1.0

var _char_list: ItemList
var _tabs: TabContainer
var _slot_grid: HFlowContainer
var _slot_info: Label
var _remove_bg: CheckBox
var _stage: PortraitStage
var _pose_opt: OptionButton
var _outfit_opt: OptionButton
var _expr_opt: OptionButton
var _toast: Label
var _maker_box: VBoxContainer
var _maker_view: SubViewport
var _maker_painter: PortraitPainter
var _maker_progress: Label
var _bible_box: VBoxContainer
var _bible_fields: Dictionary = {}
var _bible_status: Label
var _file_dialog: FileDialog
var _exporter: PortraitExporter
var _busy := false
var _opts := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	catalog = ArtCatalog.new()
	catalog.load_from(str(_opts.get("art-root", ArtCatalog.DEFAULT_ROOT)))
	lib = ArtLibrary.new(catalog)
	theme = _make_theme()
	_build()
	_exporter = PortraitExporter.new()
	add_child(_exporter)
	_exporter.progress.connect(func(done, total, _id): _maker_progress.text = "匯出中 %d / %d" % [done, total])
	get_window().files_dropped.connect(_on_files_dropped)
	_refresh_characters()
	var start := str(_opts.get("character", catalog.character_order[0] if catalog.character_order.size() > 0 else ""))
	_select_character(start)
	_tabs.current_tab = int(_opts.get("tab", 0))
	if _opts.has("screenshot"):
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(_opts["screenshot"]))
		get_tree().quit()


# ================================================================ theme

func _make_theme() -> Theme:
	var th := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Noto Sans CJK TC", "Noto Sans TC", "Microsoft JhengHei", "PingFang TC", "Heiti TC", "sans-serif"])
	th.default_font = f
	# Use the game's bundled UI font when it is present, so the workshop matches the game.
	if ResourceLoader.exists(GAME_FONT):
		var gf = load(GAME_FONT)
		if gf is Font:
			th.default_font = gf
	th.default_font_size = int(20 * font_scale)
	th.set_color("font_color", "Label", INK)
	th.set_stylebox("panel", "PanelContainer", _box(PANEL, 18, 14))
	th.set_stylebox("normal", "Button", _box(PINK, 14, 10))
	th.set_stylebox("hover", "Button", _box(PINK.lightened(0.15), 14, 10))
	th.set_stylebox("pressed", "Button", _box(PINK_DARK, 14, 10))
	th.set_stylebox("disabled", "Button", _box(Color("e6d8de"), 14, 10))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(c, "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color("a8949c"))
	for cls in ["OptionButton", "CheckBox", "LineEdit", "ItemList", "TabContainer", "TextEdit"]:
		th.set_color("font_color", cls, INK)
	th.set_color("font_hover_color", "CheckBox", PINK_DARK)
	th.set_color("font_pressed_color", "CheckBox", INK)
	th.set_stylebox("normal", "OptionButton", _box(Color("ffe9f0"), 12, 8, PINK))
	th.set_stylebox("hover", "OptionButton", _box(Color("ffdce8"), 12, 8, PINK))
	th.set_stylebox("pressed", "OptionButton", _box(Color("ffdce8"), 12, 8, PINK))
	th.set_color("font_hover_color", "OptionButton", INK)
	th.set_color("font_pressed_color", "OptionButton", INK)
	th.set_color("font_focus_color", "OptionButton", INK)
	th.set_stylebox("normal", "LineEdit", _box(Color("fffafc"), 10, 8, Color("f0c4d2")))
	th.set_stylebox("focus", "LineEdit", _box(Color("ffffff"), 10, 8, PINK))
	th.set_color("font_placeholder_color", "LineEdit", Color("c0a8b2"))
	th.set_stylebox("panel", "ItemList", _box(PANEL, 18, 8))
	th.set_stylebox("selected", "ItemList", _box(Color("ffd3e0"), 10, 4))
	th.set_stylebox("selected_focus", "ItemList", _box(Color("ffd3e0"), 10, 4))
	th.set_stylebox("hovered", "ItemList", _box(Color("fff0f5"), 10, 4))
	th.set_color("font_selected_color", "ItemList", PINK_DARK)
	th.set_color("font_hovered_color", "ItemList", INK)
	th.set_constant("v_separation", "ItemList", 8)
	th.set_stylebox("panel", "TabContainer", _box(PANEL, 18, 14))
	th.set_stylebox("tab_selected", "TabContainer", _box(PANEL, 14, 12))
	th.set_stylebox("tab_unselected", "TabContainer", _box(Color("ffdce8"), 14, 12))
	th.set_stylebox("tab_hovered", "TabContainer", _box(Color("ffe9f0"), 14, 12))
	th.set_color("font_selected_color", "TabContainer", PINK_DARK)
	th.set_color("font_unselected_color", "TabContainer", INK)
	th.set_color("font_hovered_color", "TabContainer", PINK_DARK)
	th.set_font_size("font_size", "TabContainer", int(22 * font_scale))
	return th


func _box(c: Color, radius: int, pad: int, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	if border.a > 0:
		sb.border_color = border
		sb.set_border_width_all(2)
	return sb


func _label(text: String, size := 20, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size * font_scale))
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


# ================================================================ layout

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = CREAM
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 14)
	margin.add_child(root_v)

	# top bar
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root_v.add_child(top)
	top.add_child(_label("♡ 創作者工作坊", 34, PINK_DARK))
	_toast = _label("把圖片拖進視窗就能匯入", 20, Color("a08090"))
	_toast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.clip_text = true
	top.add_child(_toast)
	top.add_child(_button("＋ 新增角色", _on_add_character))
	top.add_child(_button("檢查素材", _on_validate))
	top.add_child(_button("字 －", func(): _set_font_scale(font_scale - 0.1)))
	top.add_child(_button("字 ＋", func(): _set_font_scale(font_scale + 0.1)))
	top.add_child(_button("返回遊戲", _on_back))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root_v.add_child(body)

	# left: characters
	_char_list = ItemList.new()
	_char_list.custom_minimum_size = Vector2(230, 0)
	_char_list.item_selected.connect(func(i): _select_character(str(_char_list.get_item_metadata(i))))
	body.add_child(_char_list)

	# centre: tabs
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_tabs)
	_build_assets_tab()
	_build_maker_tab()
	_build_bible_tab()

	# right: in-game preview
	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	right.add_child(rv)
	rv.add_child(_label("遊戲中的樣子", 22, PINK_DARK))
	var stage_holder := Panel.new()
	stage_holder.add_theme_stylebox_override("panel", _box(Color("ffeef3"), 14, 0))
	stage_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_holder.clip_contents = true
	rv.add_child(stage_holder)
	_stage = PortraitStage.new()
	_stage.catalog = catalog
	_stage.height_ratio = 1.0
	_stage.default_duration = 0.15
	stage_holder.add_child(_stage)
	_pose_opt = OptionButton.new()
	_outfit_opt = OptionButton.new()
	_expr_opt = OptionButton.new()
	for pair in [["姿勢", _pose_opt, "pose"], ["服裝", _outfit_opt, "outfit"], ["表情", _expr_opt, "expression"]]:
		var row := HBoxContainer.new()
		var l := _label(pair[0])
		l.custom_minimum_size = Vector2(60, 0)
		row.add_child(l)
		var ob: OptionButton = pair[1]
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.item_selected.connect(_on_preview_changed.bind(pair[2], ob))
		row.add_child(ob)
		rv.add_child(row)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; 圖片"])
	_file_dialog.file_selected.connect(func(p): _import_files(PackedStringArray([p])))
	add_child(_file_dialog)


func _build_assets_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "素材"
	v.add_theme_constant_override("separation", 10)
	_tabs.add_child(v)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_slot_grid = HFlowContainer.new()
	_slot_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_grid.add_theme_constant_override("h_separation", 10)
	_slot_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_slot_grid)
	_slot_info = _label("點一格選取，再匯入圖片", 20)
	_slot_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_slot_info)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	v.add_child(row)
	row.add_child(_button("匯入圖片…", _on_import_pressed, "選一張圖片放進目前選取的格子"))
	_remove_bg = CheckBox.new()
	_remove_bg.text = "去除純色背景"
	_remove_bg.tooltip_text = "圖片是白底或單色底時勾選，會自動變成透明背景"
	row.add_child(_remove_bg)
	row.add_child(_button("標為完成", func(): _set_status("approved")))
	row.add_child(_button("退回草稿", func(): _set_status("draft")))
	row.add_child(_button("刪除圖片", _on_clear_slot))
	row.add_child(_button("複製 AI 提示詞", _on_copy_prompt, "把這張圖的 AI 生成提示詞複製到剪貼簿"))


func _build_maker_tab() -> void:
	var h := HBoxContainer.new()
	h.name = "產生器"
	h.add_theme_constant_override("separation", 14)
	_tabs.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_maker_box = VBoxContainer.new()
	_maker_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_maker_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_maker_box)
	var pv := VBoxContainer.new()
	pv.custom_minimum_size = Vector2(300, 0)
	h.add_child(pv)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(300, 450)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(holder)
	_maker_view = SubViewport.new()
	_maker_view.transparent_bg = true
	_maker_view.disable_3d = true
	holder.add_child(_maker_view)
	_maker_painter = PortraitPainter.new()
	_maker_view.add_child(_maker_painter)
	holder.resized.connect(_fit_maker_preview.bind(holder))
	_maker_progress = _label("預覽會跟著右邊的姿勢、服裝、表情變化", 18, Color("a08090"))
	_maker_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(_maker_progress)
	pv.add_child(_button("儲存設定", _on_save_recipe))
	pv.add_child(_button("畫出全部立繪", _on_export_all, "依這個設定畫出這位角色所有姿勢、服裝、表情，存成草稿"))


func _fit_maker_preview(holder: Control) -> void:
	var s := minf(holder.size.x / PortraitPainter.W, holder.size.y / PortraitPainter.H)
	_maker_painter.supersample = maxf(s, 0.05)
	_maker_painter.position = Vector2((holder.size.x - PortraitPainter.W * s) * 0.5, holder.size.y - PortraitPainter.H * s)
	_maker_painter.queue_redraw()


func _build_bible_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "角色設定"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_bible_box = VBoxContainer.new()
	_bible_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bible_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_bible_box)


# ================================================================ characters

func _refresh_characters() -> void:
	_char_list.clear()
	var prog := catalog.progress()
	for cid in catalog.character_order:
		var b: Dictionary = catalog.characters[cid]
		var p: Dictionary = prog.get(catalog.owner_of(cid), {"required": 0, "approved": 0, "draft": 0})
		var i := _char_list.add_item("%s  %s　%d/%d" % [b.get("tier", ""), b.get("name", cid), p["approved"] + p["draft"], p["required"]])
		_char_list.set_item_tooltip(i, "完成 %d・草稿 %d・需要 %d" % [p["approved"], p["draft"], p["required"]])
		_char_list.set_item_metadata(i, cid)
		if cid == current:
			_char_list.select(i)


func _select_character(cid: String) -> void:
	if not catalog.has_character(cid):
		return
	current = cid
	selected_slot = ""
	for i in _char_list.item_count:
		if str(_char_list.get_item_metadata(i)) == cid:
			_char_list.select(i)
	var prof := catalog.get_art_profile(cid)
	var vocab: Dictionary = catalog.spec.get("vocab", {})
	preview_state = prof["default"].duplicate()
	for trio in [[_pose_opt, "poses", "pose"], [_outfit_opt, "outfits", "outfit"], [_expr_opt, "expressions", "expression"]]:
		var ob: OptionButton = trio[0]
		ob.clear()
		for v in prof[trio[1]]:
			ob.add_item(str(vocab.get(trio[1], {}).get(v, {}).get("label", v)))
			ob.set_item_metadata(ob.item_count - 1, v)
			if v == preview_state[trio[2]]:
				ob.select(ob.item_count - 1)
	recipe = lib.load_recipe(cid)
	_refresh_slots()
	_refresh_preview()
	_rebuild_maker()
	_rebuild_bible()


func _on_preview_changed(index: int, key: String, ob: OptionButton) -> void:
	preview_state[key] = str(ob.get_item_metadata(index))
	_refresh_preview()
	if key == "outfit":
		_rebuild_maker()


func _refresh_preview() -> void:
	for id in _stage.shown_ids():
		if id != current:
			_stage.hide_character(id, {"duration": 0.0})
	if not _stage.is_showing(current):
		_stage.show_character(current, {"position": "center", "pose": preview_state["pose"], "outfit": preview_state["outfit"], "expression": preview_state["expression"]})
	else:
		_stage.set_variant(current, preview_state)
	_maker_painter.configure(recipe, str(preview_state["pose"]), str(preview_state["outfit"]), str(preview_state["expression"]))


func _reload_stage() -> void:
	PortraitTextures.clear_cache()
	catalog.clear_cache()
	_stage.hide_character(current, {"duration": 0.0})
	_refresh_preview()


# ================================================================ assets tab

func _refresh_slots() -> void:
	for c in _slot_grid.get_children():
		c.queue_free()
	for s in lib.slots_for(current):
		_slot_grid.add_child(_slot_card(s))
	_update_slot_info()


func _slot_card(s: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(168, 236)
	b.toggle_mode = true
	b.button_pressed = str(s["id"]) == selected_slot
	b.set_meta("slot", str(s["id"]))
	var status := str(s.get("status", "missing"))
	b.add_theme_stylebox_override("normal", _box(Color("fff7fa"), 14, 6, STATUS_COLORS.get(status, Color.GRAY)))
	b.add_theme_stylebox_override("hover", _box(Color("ffeef4"), 14, 6, STATUS_COLORS.get(status, Color.GRAY)))
	b.add_theme_stylebox_override("pressed", _box(Color("ffd9e5"), 14, 6, PINK_DARK))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
	b.add_child(v)
	var thumb := TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if s["has_file"]:
		thumb.texture = _thumbnail(catalog.root + str(s["path"]))
	v.add_child(thumb)
	var parts := str(s["label"]).split("｜")
	var l := _label(parts[1] if parts.size() > 1 else parts[0], 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	var tag := _label("%s・%s" % [parts[0], STATUS_LABELS.get(status, status)], 16, STATUS_COLORS.get(status, Color.GRAY).darkened(0.3))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tag)
	b.pressed.connect(_on_slot_pressed.bind(str(s["id"])))
	return b


func _thumbnail(path: String) -> Texture2D:
	var tex := PortraitTextures.load_texture(path)
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	var used := img.get_used_rect()
	if used.size.x > 0 and used.size.y > 0 and used.size != img.get_size():
		img = img.get_region(used)
	var k := minf(160.0 / img.get_width(), 200.0 / img.get_height())
	if k < 1.0:
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


func _on_slot_pressed(id: String) -> void:
	selected_slot = id
	for c in _slot_grid.get_children():
		if c is Button:
			c.button_pressed = str(c.get_meta("slot", "")) == id
	_update_slot_info()
	# show the selected variant in the preview
	var e: Dictionary = lib.ensure_entry(id)
	for trio in [["pose", _pose_opt], ["outfit", _outfit_opt], ["expression", _expr_opt]]:
		if e.has(trio[0]):
			preview_state[trio[0]] = str(e[trio[0]])
			var ob: OptionButton = trio[1]
			for i in ob.item_count:
				if str(ob.get_item_metadata(i)) == preview_state[trio[0]]:
					ob.select(i)
	if str(e.get("kind", "")) == "portrait_body":
		preview_state["expression"] = str(catalog.get_art_profile(current)["default"]["expression"])
	_refresh_preview()


func _update_slot_info() -> void:
	if selected_slot == "":
		_slot_info.text = "點一格選取，再按「匯入圖片」，或直接把圖片拖進視窗。"
		return
	var e: Dictionary = lib.ensure_entry(selected_slot)
	_slot_info.text = "已選取：%s\n檔名：%s.png" % [lib.slot_label(e), selected_slot]


func _on_import_pressed() -> void:
	if selected_slot == "":
		_say("請先點選要放圖片的格子", true)
		return
	_file_dialog.popup_centered_ratio(0.7)


func _on_files_dropped(files: PackedStringArray) -> void:
	_import_files(files)


## Dropped / chosen files: a correctly named file goes to its own slot;
## a single other file goes to the selected slot.
func _import_files(files: PackedStringArray) -> void:
	var ok := 0
	var errors: Array = []
	var opts := {"remove_bg": _remove_bg.button_pressed, "save": false}
	for f in files:
		var target := lib.asset_id_for_filename(f)
		if target != "" and lib._entry_owner(lib.ensure_entry(target)) == "":
			target = ""
		if target == "":
			if files.size() == 1 and selected_slot != "":
				target = selected_slot
			else:
				errors.append("%s：請先選一個格子，或把檔名改成規定的名稱" % f.get_file())
				continue
		var r := lib.import_image(target, f, opts)
		if r["ok"]:
			ok += 1
		else:
			errors.append("%s：%s" % [f.get_file(), r["error"]])
	lib.save_manifest()
	_refresh_slots()
	_refresh_characters()
	_reload_stage()
	if errors.is_empty():
		_say("已匯入 %d 張圖片，狀態為草稿" % ok)
	else:
		_say("匯入 %d 張，%d 張失敗：%s" % [ok, errors.size(), errors[0]], true)


func _set_status(status: String) -> void:
	if selected_slot == "":
		_say("請先點選一個格子", true)
		return
	var err := lib.set_status(selected_slot, status)
	if err != "":
		_say(err, true)
		return
	_refresh_slots()
	_refresh_characters()
	_reload_stage()
	_say("已標為%s" % STATUS_LABELS.get(status, status))


func _on_clear_slot() -> void:
	if selected_slot == "":
		_say("請先點選一個格子", true)
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "要刪除這張圖片嗎？\n%s.png\n這個動作無法復原。" % selected_slot
	dlg.ok_button_text = "刪除圖片"
	dlg.cancel_button_text = "保留"
	add_child(dlg)
	dlg.confirmed.connect(_do_clear_slot)
	dlg.popup_centered()


func _do_clear_slot() -> void:
	var err := lib.clear_slot(selected_slot)
	_refresh_slots()
	_refresh_characters()
	_reload_stage()
	_say(err if err != "" else "已刪除圖片", err != "")


func _on_copy_prompt() -> void:
	if selected_slot == "":
		_say("請先點選一個格子", true)
		return
	var r := ArtPromptBuilder.new(catalog).build(selected_slot, true)
	if not r["ok"]:
		_say(str(r["blocked"]), true)
		return
	DisplayServer.clipboard_set("%s\n\nNegative: %s\n\nCanvas: %s" % [r["prompt"], r["negative"], r["canvas"]])
	var unconfirmed := str(catalog.get_character(current).get("appearance_status", "")) != "confirmed"
	_say("提示詞已複製" + ("（外觀尚未確認，內容含 TBD）" if unconfirmed else ""))


# ================================================================ maker tab

func _rebuild_maker() -> void:
	for c in _maker_box.get_children():
		c.queue_free()
	_maker_box.add_child(_label("外觀", 22, PINK_DARK))
	_maker_option("後髮", "hair_back", PortraitRecipe.HAIR_BACK)
	_maker_option("瀏海", "bangs", PortraitRecipe.BANGS)
	_maker_option("眼型", "eye_shape", PortraitRecipe.EYES)
	_maker_color("髮色", recipe, "hair_color")
	_maker_color("瞳色", recipe, "eye_color")
	_maker_color("膚色", recipe, "skin")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_maker_box.add_child(row)
	for pair in [["呆毛", "ahoge"], ["鬢髮", "side_locks"]]:
		var cb := CheckBox.new()
		cb.text = pair[0]
		cb.button_pressed = bool(recipe.get(pair[1], false))
		cb.toggled.connect(func(on): _maker_set(recipe, pair[1], on))
		row.add_child(cb)
	var srow := HBoxContainer.new()
	var sl := _label("身高")
	sl.custom_minimum_size = Vector2(90, 0)
	srow.add_child(sl)
	var slider := HSlider.new()
	slider.min_value = 0.9
	slider.max_value = 1.06
	slider.step = 0.01
	slider.value = float(recipe.get("scale", 1.0))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 32)
	slider.value_changed.connect(func(v): _maker_set(recipe, "scale", v))
	srow.add_child(slider)
	_maker_box.add_child(srow)
	_maker_box.add_child(_label("配件", 22, PINK_DARK))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 16)
	_maker_box.add_child(flow)
	for acc in PortraitRecipe.ACCESSORIES:
		var cb := CheckBox.new()
		cb.text = PortraitRecipe.ACCESSORIES[acc]
		cb.button_pressed = recipe.get("accessories", []).has(acc)
		cb.toggled.connect(_on_accessory_toggled.bind(acc))
		flow.add_child(cb)
	var o := str(preview_state["outfit"])
	var vocab_label := str(catalog.spec.get("vocab", {}).get("outfits", {}).get(o, {}).get("label", o))
	_maker_box.add_child(_label("服裝：%s" % vocab_label, 22, PINK_DARK))
	if not recipe["outfits"].has(o):
		recipe["outfits"][o] = PortraitRecipe.DEFAULT_OUTFIT.duplicate(true)
	var od: Dictionary = recipe["outfits"][o]
	_maker_option("款式", "style", PortraitRecipe.OUTFIT_STYLES, od)
	_maker_color("主色", od, "main")
	_maker_color("副色", od, "accent")
	_maker_color("緞帶", od, "ribbon")
	_maker_box.add_child(_label("要改另一套服裝，請在右邊切換「服裝」。", 17, Color("a08090")))


func _maker_row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _label(title)
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	_maker_box.add_child(row)
	return row


func _maker_option(title: String, key: String, options: Dictionary, target: Dictionary = {}) -> void:
	var dict := target if not target.is_empty() else recipe
	var row := _maker_row(title)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in options:
		ob.add_item(str(options[id]))
		ob.set_item_metadata(ob.item_count - 1, id)
		if str(dict.get(key, "")) == id:
			ob.select(ob.item_count - 1)
	ob.item_selected.connect(func(i): _maker_set(dict, key, str(ob.get_item_metadata(i))))
	row.add_child(ob)


func _maker_color(title: String, dict: Dictionary, key: String) -> void:
	var row := _maker_row(title)
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(120, 40)
	cp.color = Color(str(dict.get(key, "#ffffff")))
	cp.edit_alpha = false
	cp.color_changed.connect(func(c): _maker_set(dict, key, "#" + c.to_html(false)))
	row.add_child(cp)


func _maker_set(dict: Dictionary, key: String, value) -> void:
	dict[key] = value
	_maker_painter.configure(recipe, str(preview_state["pose"]), str(preview_state["outfit"]), str(preview_state["expression"]))


func _on_accessory_toggled(on: bool, acc: String) -> void:
	var list: Array = recipe.get("accessories", []).duplicate()
	list.erase(acc)
	if on:
		list.append(acc)
	_maker_set(recipe, "accessories", list)


func _on_save_recipe() -> void:
	_say("產生器設定已儲存" if lib.save_recipe(current, recipe) else "無法儲存設定", false)


func _on_export_all() -> void:
	if _busy:
		return
	_busy = true
	lib.save_recipe(current, recipe)
	_say("正在畫出 %s 的全部立繪，請稍候…" % catalog.display_name(current))
	var r: Dictionary = await _exporter.export_character(lib, current, recipe)
	_busy = false
	_maker_progress.text = "完成：%d 張已存成草稿" % r["ok"]
	_refresh_slots()
	_refresh_characters()
	_reload_stage()
	if r["failed"].is_empty():
		_say("已畫出 %d 張立繪（草稿）。到「素材」分頁檢查後標為完成。" % r["ok"])
	else:
		_say("有 %d 張失敗：%s" % [r["failed"].size(), r["failed"][0]], true)


# ================================================================ bible tab

const BIBLE_FIELDS := [
	["name", "姓名"], ["appearance/summary", "外貌概要"], ["appearance/age_look", "年齡感"],
	["appearance/hair/style", "髮型"], ["appearance/hair/color", "髮色"], ["appearance/eyes/color", "瞳色"],
	["appearance/body/height_cm", "身高（公分）"], ["appearance/body/build", "體型"], ["appearance/body/proportion_note", "身形比例備註"],
	["appearance/accessories", "配件"], ["appearance/signature_colors", "代表色"], ["appearance/expression_traits", "表情特徵"],
]


func _rebuild_bible() -> void:
	for c in _bible_box.get_children():
		c.queue_free()
	_bible_fields = {}
	var b := catalog.get_character(current)
	var locked := str(b.get("appearance_status", "")) == "confirmed"
	_bible_status = _label("", 20)
	_bible_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bible_status.text = "外觀已確認並鎖定（第 %d 版）。要修改請先解除鎖定。" % int(b.get("bible_revision", 0)) if locked \
		else "外觀尚未確認。填完所有欄位後按「確認並鎖定外觀」。「TBD」代表還沒決定。"
	_bible_status.add_theme_color_override("font_color", Color("3a9a6a") if locked else Color("c07a20"))
	_bible_box.add_child(_bible_status)
	var fields: Array = BIBLE_FIELDS.duplicate()
	for o in b.get("appearance", {}).get("outfits", {}):
		fields.append(["appearance/outfits/%s/design" % o, "服裝設計：%s" % catalog.spec.get("vocab", {}).get("outfits", {}).get(o, {}).get("label", o)])
	for f in fields:
		var row := HBoxContainer.new()
		var l := _label(f[1])
		l.custom_minimum_size = Vector2(190, 0)
		row.add_child(l)
		var le := LineEdit.new()
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val = _get_path(b, f[0])
		le.text = "" if str(val) == "TBD" else str(val)
		le.placeholder_text = "尚未決定"
		le.editable = not locked or f[0] == "name"
		row.add_child(le)
		_bible_box.add_child(row)
		_bible_fields[f[0]] = le
	var p: Dictionary = b.get("personality", {})
	var pers := _label("個性：%s" % p.get("summary", ""), 18, Color("806878"))
	pers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bible_box.add_child(pers)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_bible_box.add_child(row)
	row.add_child(_button("儲存", _on_save_bible))
	if locked:
		row.add_child(_button("解除鎖定", _on_unlock))
	else:
		row.add_child(_button("確認並鎖定外觀", _on_lock))


func _get_path(d: Dictionary, path: String):
	var cur = d
	for k in path.split("/"):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(k):
			return "TBD"
		cur = cur[k]
	if typeof(cur) == TYPE_ARRAY:
		return "、".join(PackedStringArray(cur.map(func(x): return str(x))))
	return cur


func _set_path(d: Dictionary, path: String, value: String) -> void:
	var keys := path.split("/")
	var cur := d
	for i in keys.size() - 1:
		if typeof(cur.get(keys[i])) != TYPE_DICTIONARY:
			cur[keys[i]] = {}
		cur = cur[keys[i]]
	cur[keys[keys.size() - 1]] = value


func _collect_bible() -> Dictionary:
	var b: Dictionary = catalog.get_character(current).duplicate(true)
	for path in _bible_fields:
		var le: LineEdit = _bible_fields[path]
		if not le.editable:
			continue
		var t := le.text.strip_edges()
		_set_path(b, path, t if t != "" else "TBD")
	return b


func _on_save_bible() -> bool:
	var err := lib.save_bible(current, _collect_bible())
	_say(err if err != "" else "角色設定已儲存", err != "")
	_refresh_characters()
	return err == ""


func _on_lock() -> void:
	if not _on_save_bible():
		return
	var err := lib.lock_appearance(current)
	_say(err if err != "" else "外觀已確認並鎖定", err != "")
	_rebuild_bible()


func _on_unlock() -> void:
	var err := lib.unlock_appearance(current)
	_say(err if err != "" else "已解除鎖定，可以修改外觀", err != "")
	_rebuild_bible()


# ================================================================ top bar actions

func _on_add_character() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "新增角色"
	dlg.ok_button_text = "建立角色"
	dlg.cancel_button_text = "取消"
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	var id_edit := LineEdit.new()
	id_edit.placeholder_text = "角色 ID（小寫英文，例如 mizuki）"
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "名字（例如 美月）"
	var tier := OptionButton.new()
	for t in ["S", "A", "B"]:
		tier.add_item("%s　%s" % [t, catalog.spec.get("tiers", {}).get(t, {}).get("label", "")])
	v.add_child(id_edit)
	v.add_child(name_edit)
	v.add_child(tier)
	dlg.add_child(v)
	add_child(dlg)
	dlg.confirmed.connect(_do_add_character.bind(id_edit, name_edit, tier))
	dlg.popup_centered()


func _do_add_character(id_edit: LineEdit, name_edit: LineEdit, tier: OptionButton) -> void:
	var id := id_edit.text.strip_edges()
	var err := lib.add_character(id, name_edit.text.strip_edges(), ["S", "A", "B"][tier.selected], "TBD")
	if err != "":
		_say(err, true)
		return
	_refresh_characters()
	_select_character(id)
	_say("已建立角色，接著可以用產生器或匯入圖片")


func _on_validate() -> void:
	catalog.load_from(catalog.root)
	var v := ArtValidator.new()
	var rep := v.run(catalog)
	var dlg := AcceptDialog.new()
	dlg.title = "素材檢查"
	dlg.ok_button_text = "關閉"
	var te := TextEdit.new()
	te.editable = false
	te.custom_minimum_size = Vector2(900, 520)
	var c: Dictionary = rep["counts"]
	var lines := PackedStringArray(["錯誤 %d　警告 %d　缺少素材 %d" % [c["error"], c["warning"], c["missing"]], ""])
	for level in ["error", "warning"]:
		for i in rep["issues"]:
			if i["level"] == level:
				lines.append("[%s] %s  %s" % ["錯誤" if level == "error" else "警告", i["message"], i["path"]])
	if c["error"] == 0:
		lines.append("沒有錯誤。")
	te.text = "\n".join(lines)
	dlg.add_child(te)
	add_child(dlg)
	dlg.popup_centered()
	_refresh_characters()
	_refresh_slots()


func _on_back() -> void:
	var main := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main != "" and main != scene_file_path and ResourceLoader.exists(main):
		get_tree().change_scene_to_file(main)
	else:
		get_tree().quit()


func _set_font_scale(s: float) -> void:
	font_scale = clampf(s, 0.8, 1.6)
	theme = _make_theme()
	for c in get_children():
		if c != _exporter:
			c.queue_free()
	_build()
	_refresh_characters()
	_select_character(current)
	_say("字體大小 %d%%" % int(round(font_scale * 100)))


func _say(text: String, is_error := false) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", Color("d04a4a") if is_error else Color("3a9a6a"))
