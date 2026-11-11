## Game entry: owns the state, drives the daily loop and builds the UI in code.
##   explore (daytime street) -> prepare -> business (evening shift) -> night (report, events, after-hours scene) -> next day
extends Node

const Data = preload("res://scripts/core/data.gd")
const St = preload("res://scripts/core/state.gd")
const Layout = preload("res://scripts/core/layout.gd")
const World = preload("res://scripts/core/world.gd")
const Biz = preload("res://scripts/core/business.gd")
const Settle = preload("res://scripts/core/settlement.gd")
const Events = preload("res://scripts/core/events.gd")
const Social = preload("res://scripts/core/social.gd")
const Life = preload("res://scripts/core/life.gd")
const LD = preload("res://scripts/core/life_data.gd")
const CafeView = preload("res://scripts/view/cafe_view.gd")
const MaidTheme = preload("res://scripts/view/maid_theme.gd")
const Settings = preload("res://scripts/core/settings.gd")
const Story = preload("res://scripts/core/story.gd")
const SD = preload("res://scripts/core/story_data.gd")
const WORKSHOP_SCENE := "res://scripts/art/workshop/creator_workshop.tscn"
const PORTRAIT_SCRIPT := "res://scripts/art/portrait_stage.gd"

var s: Dictionary = {}
var view
var sim = null
var speed := 1.0
var paused := false
var sel_kind := ""
var sel_id := ""
var placing := ""
var moving_fid := ""
var hover_cell := Vector2i(-1, -1)
var night_step := ""
var report: Dictionary = {}
var briefing_shown_day := -1
var notes_seen := 0
var prep_tab := 0
var capturing := false
var on_title := false
var autoshot := ""   # set by --shot to take screenshots for playtests

# UI
var ui: CanvasLayer
var theme: Theme
var ui_root: Control
var ui_k := 1.0       # player font scale (settings)
var top_bar: PanelContainer
const BASE_TOP_FONT := 17
var top_label: RichTextLabel
var top_buttons: HBoxContainer
var side: VBoxContainer
var side_panel: PanelContainer
var inspector: RichTextLabel
var inspector_panel: PanelContainer
var inspector_buttons: VBoxContainer
var log_label: RichTextLabel
var log_panel: PanelContainer
var debug_label: RichTextLabel
var debug_panel: PanelContainer
var modal: Control
var modal_box: VBoxContainer
var modal_title: Label
var modal_body: RichTextLabel
var modal_buttons: VBoxContainer
var modal_extra: Control
var toast_label: Label
var toast_t := 0.0
var refresh_t := 0.0

func _ready() -> void:
	_build_theme()
	view = CafeView.new()
	add_child(view)
	view.cell_clicked.connect(_on_cell_clicked)
	view.agent_clicked.connect(_on_agent_clicked)
	_build_ui()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			autoshot = a.substr(7)
	if autoshot != "":
		_run_playtest_shots()
		return
	_title()

# ======================================================================== theme & widgets
func _build_theme() -> void:
	ui_k = Settings.font_scale()
	theme = MaidTheme.build(ui_k)
	if ui_root != null:
		ui_root.theme = theme
		_layout_panels()

## Scaled font size for a design size (sizes were picked for the old 15px UI; everything is a bit bigger now).
func _fs(size: float) -> int:
	return MaidTheme.fs(maxf(15.0, size * 1.2), ui_k)

## Panel sizes follow the font size so bigger text still fits.
func _layout_panels() -> void:
	var vw := get_viewport().get_visible_rect().size.x
	var sw := clampf(420.0 * ui_k, 380.0, vw * 0.42)
	var top_h := 58.0 * ui_k
	top_bar.offset_bottom = top_h
	side_panel.offset_top = top_h + 10
	side_panel.offset_right = 10 + sw
	inspector_panel.offset_left = -clampf(400.0 * ui_k, 360.0, vw * 0.36)
	inspector_panel.offset_top = top_h + 10
	log_panel.offset_left = sw + 22
	log_panel.offset_right = -12
	log_panel.offset_top = -150.0 * ui_k
	toast_label.offset_top = top_h + 14
	# keep the top bar on one line at big font sizes: cap its text and drop the button words
	var tk := minf(ui_k, 1.1)
	top_label.add_theme_font_size_override("normal_font_size", MaidTheme.fs(BASE_TOP_FONT, tk))
	top_label.add_theme_font_size_override("bold_font_size", MaidTheme.fs(BASE_TOP_FONT, tk))
	for b in top_buttons.get_children():
		var full: String = b.get_meta("full", b.text)
		b.set_meta("full", full)
		b.text = full.split(" ")[0] if ui_k > 1.1 else full
		b.add_theme_font_size_override("font_size", MaidTheme.fs(17, tk))
	toast_label.add_theme_font_size_override("font_size", _fs(18))
	modal_title.add_theme_font_size_override("font_size", _fs(22))

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var root := Control.new()
	ui_root = root
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	# top bar
	var top := PanelContainer.new()
	top_bar = top
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 10
	top.offset_right = -10
	top.offset_top = 8
	top.offset_bottom = 58
	root.add_child(top)
	var th := HBoxContainer.new()
	top.add_child(th)
	top_label = RichTextLabel.new()
	top_label.bbcode_enabled = true
	top_label.fit_content = true
	top_label.scroll_active = false
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	th.add_child(top_label)
	top_buttons = HBoxContainer.new()
	th.add_child(top_buttons)
	top_buttons.add_theme_constant_override("separation", 6)
	for b in [["📖 故事", _open_story, "主線故事與本章目標"], ["🎀 女僕", _open_maids, "女僕檔案、羈絆與特訓"], ["📒", _open_notebook, "筆記本（N）"], ["📷", _open_album, "回憶相簿（M）"],
			["⚙", _open_settings, "設定：字體大小"], ["💾", _save, "存檔"]]:
		var tb := _btn(b[0], b[1])
		tb.tooltip_text = b[2]
		top_buttons.add_child(tb)
	# side panel
	side_panel = PanelContainer.new()
	side_panel.position = Vector2(8, 54)
	side_panel.size = Vector2(390, 600)
	side_panel.anchor_bottom = 1.0
	side_panel.offset_bottom = -8
	side_panel.offset_top = 54
	side_panel.offset_left = 8
	side_panel.offset_right = 398
	root.add_child(side_panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(sc)
	side = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 6)
	sc.add_child(side)
	# inspector (right)
	inspector_panel = PanelContainer.new()
	inspector_panel.anchor_left = 1.0
	inspector_panel.anchor_right = 1.0
	inspector_panel.offset_left = -380
	inspector_panel.offset_right = -8
	inspector_panel.offset_top = 54
	inspector_panel.offset_bottom = 470
	root.add_child(inspector_panel)
	var iv := VBoxContainer.new()
	inspector_panel.add_child(iv)
	inspector = RichTextLabel.new()
	inspector.bbcode_enabled = true
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	iv.add_child(inspector)
	inspector_buttons = VBoxContainer.new()
	iv.add_child(inspector_buttons)
	inspector_panel.visible = false
	# log (bottom)
	log_panel = PanelContainer.new()
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.anchor_right = 1.0
	log_panel.offset_left = 408
	log_panel.offset_right = -390
	log_panel.offset_top = -170
	log_panel.offset_bottom = -8
	root.add_child(log_panel)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_panel.add_child(log_label)
	# debug (right, below inspector)
	debug_panel = PanelContainer.new()
	debug_panel.anchor_left = 1.0
	debug_panel.anchor_right = 1.0
	debug_panel.anchor_bottom = 1.0
	debug_panel.offset_left = -520
	debug_panel.offset_right = -8
	debug_panel.offset_top = 478
	debug_panel.offset_bottom = -8
	root.add_child(debug_panel)
	debug_label = RichTextLabel.new()
	debug_label.bbcode_enabled = true
	debug_label.add_theme_font_size_override("normal_font_size", 13)
	debug_panel.add_child(debug_label)
	debug_panel.visible = false
	# toast
	toast_label = Label.new()
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.offset_left = -300
	toast_label.offset_right = 300
	toast_label.offset_top = 60
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_color", Color("ffffff"))
	toast_label.add_theme_color_override("font_outline_color", Color("d94f82"))
	toast_label.add_theme_constant_override("outline_size", 10)
	root.add_child(toast_label)
	# modal
	modal = ColorRect.new()
	modal.color = Color(0.36, 0.13, 0.24, 0.42)
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var mp := PanelContainer.new()
	mp.custom_minimum_size = Vector2(760, 200)
	center.add_child(mp)
	modal_box = VBoxContainer.new()
	modal_box.add_theme_constant_override("separation", 8)
	mp.add_child(modal_box)
	modal_title = Label.new()
	modal_title.theme_type_variation = "TitleLabel"
	modal_title.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	modal_box.add_child(modal_title)
	modal_body = RichTextLabel.new()
	modal_body.bbcode_enabled = true
	modal_body.custom_minimum_size = Vector2(740, 120)
	modal_body.fit_content = true
	modal_box.add_child(modal_body)
	modal_extra = VBoxContainer.new()
	modal_box.add_child(modal_extra)
	modal_buttons = VBoxContainer.new()
	modal_box.add_child(modal_buttons)
	modal.visible = false
	_layout_panels()

func _btn(text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.pressed.connect(cb)
	return b

## Full-width button whose text wraps inside the side panel.
func _wbtn(text: String, cb: Callable, disabled := false) -> Button:
	var b := _btn(text, cb, disabled)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.theme_type_variation = "SoftButton"
	return b

## Big pink call-to-action button.
func _pbtn(text: String, cb: Callable, disabled := false) -> Button:
	var b := _btn(text, cb, disabled)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	b.add_theme_font_size_override("font_size", _fs(17))
	return b

## Tab / option button; the chosen one is raspberry.
func _tbtn(text: String, cb: Callable, active: bool) -> Button:
	var b := _btn(text, cb)
	b.theme_type_variation = "ActiveButton" if active else "SoftButton"
	return b

## Explanations only shown when the player turned on "詳細說明" in the settings.
func _hint(text: String) -> void:
	if Settings.hints():
		side.add_child(_label(text, 13, MaidTheme.C.soft))

func _section(text: String) -> Control:
	var pc := PanelContainer.new()
	pc.theme_type_variation = "RibbonPanel"
	var l := _label(text, 20, "#ffffff")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	return pc

func _bar(value: float, max_v: float, col := "", h := 14.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = max_v
	pb.value = value
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(60, h * ui_k)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if col != "":
		var fill := (theme.get_stylebox("fill", "ProgressBar") as StyleBoxFlat).duplicate()
		fill.bg_color = Color(col)
		pb.add_theme_stylebox_override("fill", fill)
	return pb

func _label(text: String, size := 15, color := "") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.add_theme_font_size_override("font_size", _fs(size))
	if color != "":
		l.add_theme_color_override("font_color", Color(color))
	return l

func _rich(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	return r

func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

func toast(text: String) -> void:
	if text == "":
		return
	toast_label.text = text
	toast_t = 3.0

## Show a modal dialog. buttons: [[label, callable], ...]
func show_modal(title: String, body: String, buttons: Array, extra: Control = null, width := 760) -> void:
	modal.visible = true
	modal_title.add_theme_font_size_override("font_size", _fs(22))
	modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	width = int(minf(width * (0.85 + 0.25 * ui_k), get_viewport().get_visible_rect().size.x - 40))
	modal_title.text = title
	modal_body.text = body
	modal_body.visible = body != ""
	modal_body.custom_minimum_size.x = width - 20
	(modal_box.get_parent() as PanelContainer).custom_minimum_size.x = width
	_clear(modal_extra)
	if extra != null:
		# tall content scrolls instead of pushing the buttons off screen
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(extra)
		modal_extra.add_child(sc)
		_fit_scroll(sc, extra)
		_fit_scroll.call_deferred(sc, extra)
	_clear(modal_buttons)
	for i in buttons.size():
		var b: Array = buttons[i]
		var bt := _wbtn(b[0], b[1], b.size() > 2 and b[2])
		bt.alignment = HORIZONTAL_ALIGNMENT_CENTER
		bt.theme_type_variation = "Button"
		modal_buttons.add_child(bt)

func _fit_scroll(sc: ScrollContainer, content: Control) -> void:
	if not is_instance_valid(sc) or not is_instance_valid(content):
		return
	var need := content.get_combined_minimum_size().y
	var vh := get_viewport().get_visible_rect().size.y
	sc.custom_minimum_size.y = minf(need, vh - 230.0 * ui_k)

func close_modal() -> void:
	modal.visible = false
	_clear(modal_extra)

# ======================================================================== title & save
func _title() -> void:
	on_title = true
	s = St.new_game()
	view.set_state(s)
	sim = Biz.new(s, "offhours")
	view.set_sim(sim)
	var buttons := [["🌸 開始新的營業", _new_game]]
	if St.has_save():
		buttons.push_front(["☕ 繼續上次的進度", _continue])
	buttons.append(["🎨 創作者工坊（立繪）", _open_workshop])
	buttons.append(["⚙ 設定．字體大小", _open_settings])
	buttons.append(["❔ 操作說明", _show_controls])
	_set_hud(false)
	show_modal("Maiden Parade", "[center][color=#8f6a77]商店街盡頭，一間快要熄燈的女僕咖啡廳。\n和女僕們一起，把它變成大家回得去的地方。[/color][/center]", buttons, null, 640)
	modal_title.text = "♡ Maiden Parade ♡"
	modal_title.add_theme_font_size_override("font_size", _fs(40))
	modal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _set_hud(on: bool) -> void:
	side_panel.visible = on
	log_panel.visible = on
	top_bar.visible = on

func _show_controls() -> void:
	show_modal("❔ 操作說明", "🖱 [b]左鍵[/b]　點角色或家具\n🖱 [b]右鍵[/b]　店長移動／親自處理\n🖱 [b]中鍵拖曳[/b]　旋轉鏡頭（Shift＋中鍵：平移）\n🖱 [b]滾輪[/b]　縮放\n⌨ [b]Q／E[/b] 旋轉　[b]空白鍵[/b] 暫停　[b]N[/b] 筆記本　[b]M[/b] 相簿　[b]F3[/b] 除錯",
		[["← 回到標題", _title]], null, 640)

## The creator workshop (portrait import / creation) is built by the art pipeline; open it when it exists.
func _open_workshop() -> void:
	if not ResourceLoader.exists(WORKSHOP_SCENE):
		toast("創作者工坊還在準備中。")
		return
	get_tree().change_scene_to_file(WORKSHOP_SCENE)

func _new_game() -> void:
	s = St.new_game()
	_start_loaded()

func _continue() -> void:
	var l := St.load_game()
	if l.is_empty():
		toast("讀檔失敗，開始新遊戲。")
		l = St.new_game()
	s = l
	_start_loaded()

func _start_loaded() -> void:
	on_title = false
	_set_hud(true)
	close_modal()
	view.set_state(s)
	match s.phase:
		"explore":
			enter_explore()
		"prepare":
			enter_prepare()
		_:
			s.phase = "explore"
			enter_explore()

func _save() -> void:
	if s.phase in ["business"]:
		toast("營業中不能存檔。")
		return
	St.save_game(s)
	toast("已存檔。")

# ======================================================================== frame loop
func _process(dt: float) -> void:
	if toast_t > 0:
		toast_t -= dt
		if toast_t <= 0:
			toast_label.text = ""
	if s.is_empty():
		return
	if sim != null and not paused and not capturing:
		var mul := speed if s.phase == "business" else 1.0
		sim.update(dt * mul)
		if s.phase == "business" and sim.ended:
			_end_business()
	refresh_t -= dt
	if refresh_t <= 0:
		refresh_t = 0.25
		_refresh_top()
		_refresh_log()
		if inspector_panel.visible:
			_refresh_inspector()
		if debug_panel.visible:
			_refresh_debug()
		if s.phase == "business":
			_refresh_business_side_live()
	_check_pending_screenshots()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_F3:
				_toggle_debug()
			KEY_N:
				if not modal.visible:
					_open_notebook()
			KEY_M:
				if not modal.visible:
					_open_album()
			KEY_SPACE:
				if s.phase == "business":
					paused = not paused
					toast("暫停" if paused else "繼續")
			KEY_ESCAPE:
				if placing != "" or moving_fid != "":
					placing = ""
					moving_fid = ""
					view.set_ghost("", Vector2i.ZERO, false)
				elif modal.visible and s.phase != "night":
					close_modal()
	elif ev is InputEventMouseMotion and (placing != "" or moving_fid != ""):
		var c: Vector2i = view.screen_to_cell(ev.position)
		if c != hover_cell:
			hover_cell = c
			var type := placing
			var lay = Layout.new(s.furniture, s.upgrades)
			if moving_fid != "":
				var rest: Array = s.furniture.filter(func(f): return f.id != moving_fid)
				for f in s.furniture:
					if f.id == moving_fid:
						type = f.type
				lay = Layout.new(rest, s.upgrades)
			view.set_ghost(type, c, lay.can_place(type, c.x, c.y) == "")

func _refresh_top() -> void:
	var phase_name: String = {"explore": "☀ 白天", "prepare": "🧹 準備", "business": "🍰 營業中", "night": "🌙 打烊後"}.get(s.phase, s.phase)
	var sep := "  [color=#f6b6cb]♥[/color]  "
	var wicon: String = {"sunny": "☀️", "cloudy": "☁️", "rain": "🌧", "hot": "🔥", "snow": "❄️"}.get(s.weather, "")
	var t := "[b]%s[/b]  %s%s  %s" % [Data.date_label(int(s.day)), wicon, World.WEATHER_NAMES.get(s.weather, s.weather), phase_name]
	t += sep + "[color=#c9861a][b]¥%s[/b][/color]" % _money(float(s.money))
	t += sep + "⭐ %d　💬 %d" % [int(s.popularity), int(s.reputation)]
	if s.phase == "explore":
		t += sep + "👣 %d／%d" % [int(s.action_points), Data.DAY_ACTION_POINTS]
	if s.phase == "business" and sim != null:
		t += sep + "🕐 %s　📣 %d／%d　%s" % [sim.clock(), sim.command_points, Biz.MAX_CP, ("⏸" if paused else "▶ x%d" % int(speed))]
	var ev: String = s.street.get("event", "")
	if ev != "":
		t += sep + "🏮 " + World.STREET_EVENT_NAMES.get(ev, ev)
	var ch := Story.chapter(s)
	if not ch.is_empty():
		var gs := Story.goals(s)
		var done := gs.filter(func(g): return g.done).size()
		t += sep + "[color=#d94f82]📖 %s %d／%d[/color]" % [String(ch.title).split("．")[0], done, gs.size()]
	top_label.text = t

static func _money(v: float) -> String:
	var n := int(v)
	var neg := n < 0
	var a := str(absi(n))
	var out := ""
	while a.length() > 3:
		out = "," + a.substr(a.length() - 3) + out
		a = a.substr(0, a.length() - 3)
	return ("-" if neg else "") + a + out

func _refresh_log() -> void:
	if sim == null:
		return
	if sim.notes.size() == notes_seen:
		return
	for i in range(notes_seen, sim.notes.size()):
		var n: Dictionary = sim.notes[i]
		var col: String = {"warn": "#d9622b", "good": "#2f9b72", "moment": "#e0518e", "album": "#c9861a"}.get(n.kind, "#5b3a46")
		log_label.append_text("[color=#b597a2]%s[/color] [color=%s]%s[/color]\n" % [sim.clock() if s.phase == "business" else "", col, n.text])
	notes_seen = sim.notes.size()

func _set_sim(p_sim) -> void:
	sim = p_sim
	notes_seen = 0
	log_label.clear()
	view.set_sim(sim)
	sel_id = ""
	inspector_panel.visible = false

# ======================================================================== explore
func enter_explore() -> void:
	s.phase = "explore"
	close_modal()
	_set_sim(Biz.new(s, "offhours"))
	log_label.append_text("[color=#8f6a77]早上的咖啡廳。女僕們在店裡做著自己的事。[/color]\n")
	_build_explore_side()
	if Story.needs_intro(s):
		_show_story_intro()
		return
	_morning_briefing()

func _morning_briefing() -> void:
	_hide_portrait()
	if briefing_shown_day != int(s.day):
		briefing_shown_day = int(s.day)
		show_modal("☀ 早安！%s" % Data.date_label(int(s.day)), "\n".join(World.morning_briefing(s)), [["出門吧", close_modal]])
	else:
		close_modal()

func _show_story_intro() -> void:
	var sc := Story.intro_scene(s)
	_show_portrait(sc.get("who", ""))
	show_modal("📖 " + sc.title, "\n".join(sc.lines), [[sc.choices[0], _begin_chapter]])

func _begin_chapter() -> void:
	Story.begin_chapter(s)
	_refresh_top()
	_morning_briefing()

func _build_explore_side() -> void:
	_clear(side)
	side.add_child(_section("☀ 白天：商店街"))
	if int(s.action_points) > 0:
		side.add_child(_label("🕘 %s．還能出門 %d 次" % [Data.SLOTS[World.slot_index(s)], int(s.action_points)], 15, "#8f6a77"))
		_hint("每去一個地方會花掉一段時間。街坊們會依照作息出現在不同地方。")
	else:
		side.add_child(_label("🌇 傍晚了，回店裡準備開店吧", 15, "#8f6a77"))
	for loc in Data.LOCATION_ORDER:
		var here := World.residents_at(s, loc)
		var names := []
		for rid in here:
			names.append(Data.RESIDENTS[rid].name)
		var txt := "📍 %s" % Data.LOCATIONS[loc].name
		if not names.is_empty():
			txt += "\n　　👤 " + "、".join(names)
		if loc == "cafe":
			var con := []
			for m in St.active_maids(s):
				if not m.concern.is_empty():
					con.append(Data.MAIDS[m.id].name)
			if not con.is_empty():
				txt += "\n　　💭 %s好像有心事" % "、".join(con)
			var talk := []
			for m in St.active_maids(s):
				if not m.want_talk.is_empty():
					talk.append(Data.MAIDS[m.id].name)
			if not talk.is_empty():
				txt += "\n　　💬 %s有話想說" % "、".join(talk)
		else:
			var off := []
			for m in St.active_maids(s):
				if m.role == "off" and not m.offday.is_empty() and m.offday.loc == loc:
					off.append(Data.MAIDS[m.id].name)
			if not off.is_empty():
				txt += "\n　　☕ 休假的%s可能在這裡" % "、".join(off)
		var b := _wbtn(txt, _on_visit.bind(loc), int(s.action_points) <= 0)
		b.tooltip_text = Data.LOCATIONS[loc].desc
		side.add_child(b)
	side.add_child(HSeparator.new())
	var recruits := []
	for mid in Data.MAIDS:
		if s.flags.get("recruit_" + mid, false):
			recruits.append(mid)
	for mid in recruits:
		side.add_child(_wbtn("✨ 邀請%s加入（店裡最多 %d 人，現在 %d 人）" % [Data.MAIDS[mid].name, Data.MAX_STAFF, s.staff.size()], _on_hire.bind(mid)))
	side.add_child(_pbtn("🏠 回店裡準備開店 →", enter_prepare))

func _on_visit(loc: String) -> void:
	if loc == "cafe":
		var ms := St.active_maids(s)
		var btns := []
		for m in ms:
			var t: String = Data.MAIDS[m.id].name
			if not m.want_talk.is_empty():
				t += "（💬 有話想說）"
			elif not m.concern.is_empty():
				t += "（💭 好像有心事）"
			btns.append([t, _visit_cafe.bind(m.id)])
		btns.append(["算了", close_modal])
		show_modal("回店裡", "要找誰聊聊？", btns)
		return
	var enc := World.visit_location(s, loc)
	_show_encounter(enc)

func _visit_cafe(mid: String) -> void:
	var enc := World.visit_location(s, "cafe", mid)
	_show_encounter(enc)

func _show_encounter(enc: Dictionary) -> void:
	var btns := []
	for rid in enc.residents:
		btns.append(["和%s聊聊" % Data.RESIDENTS[rid].name, _on_talk.bind(rid)])
	if enc.has("concern"):
		for o in Social.options(s, enc.concern):
			btns.append(["💭 " + o.label, _on_concern.bind(enc.concern, o.id)])
	if enc.has("talk"):
		var tv := Life.talk_view(s, enc.talk)
		for o in tv.get("options", []):
			btns.append(["💬 " + o.label, _on_talk_opt.bind(enc.talk, o.id)])
	btns.append(["離開", _close_and_refresh_explore])
	show_modal(enc.title, "\n".join(enc.lines), btns)
	_build_explore_side()

func _close_and_refresh_explore() -> void:
	close_modal()
	_build_explore_side()

func _on_talk(rid: String) -> void:
	var t := World.talk_resident(s, rid)
	var btns := []
	if t.offer != "":
		btns.append(["答應", _on_offer.bind(t.offer)])
	btns.append(["道別", _close_and_refresh_explore])
	var r := World.resident(s, rid)
	show_modal("%s（%s）" % [Data.RESIDENTS[rid].name, Data.RESIDENTS[rid].role], "\n".join(t.lines) + "\n\n[color=#8f6a77]熟悉度 %d[/color]" % int(r.aff), btns)

func _on_offer(offer: String) -> void:
	var e := World.accept_offer(s, offer)
	if e != "":
		toast(e)
		return
	show_modal("合作成立！", {"yamada_eggs": "山田家的放牧蛋可以在山田生鮮買到了。新料理「放牧蛋特製蛋包飯」解鎖！",
		"sweets_collab": "糖霜屋的食材八折，「糖霜屋聯名蛋糕」解鎖！展示櫃的商品也更好賣了。",
		"tsukimi_collab": "新活動「手作小市集」可以舉辦了。", "kanade_collab": "新活動「街頭音樂之夜」可以舉辦了（需要小舞台）。"}.get(offer, ""),
		[["太好了", _close_and_refresh_explore]])

func _on_hire(mid: String) -> void:
	var e := World.hire_maid(s, mid)
	if e != "":
		toast(e)
		return
	show_modal("%s加入了 Maiden Parade！" % Data.MAIDS[mid].name, Data.MAIDS[mid].intro + "\n\n特質：" + "、".join(Data.MAIDS[mid].traits.map(func(x): return Data.TRAITS[x].name)), [["歡迎！", _close_and_refresh_explore]])
	view.set_sim(sim)
	_set_sim(Biz.new(s, "offhours"))

## She came to talk: what the manager answers becomes a promise, a memory, a day off...
func _open_talk(mid: String) -> void:
	var tv := Life.talk_view(s, mid)
	if tv.is_empty():
		return
	var btns := []
	for o in tv.options:
		btns.append([o.label, _on_talk_opt.bind(mid, o.id)])
	_show_portrait(mid)
	show_modal("💬 " + tv.title, "\n".join(tv.lines), btns)

func _on_talk_opt(mid: String, opt: String) -> void:
	var r := Life.talk_resolve(s, mid, opt)
	_hide_portrait()
	show_modal("💬 %s" % Data.MAIDS[mid].name, r, [["好", _after_talk]])

func _after_talk() -> void:
	close_modal()
	if s.phase == "explore":
		_build_explore_side()
	elif s.phase == "night":
		_enter_night_scene()

func _on_concern(mid: String, opt: String) -> void:
	var r := Social.resolve(s, mid, opt)
	show_modal("💭 %s" % Data.MAIDS[mid].name, r, [["好", _close_and_refresh_explore]])

# ======================================================================== prepare
func enter_prepare() -> void:
	s.phase = "prepare"
	close_modal()
	if sim == null or sim.mode != "offhours":
		_set_sim(Biz.new(s, "offhours"))
	_build_prepare_side()

func _build_prepare_side() -> void:
	_clear(side)
	side.add_child(_section("🧹 開店準備"))
	var tabs := HFlowContainer.new()
	var names := ["菜單", "採購", "人員", "家具", "活動．氛圍", "特別日"]
	for i in names.size():
		var b := _btn(names[i], _set_prep_tab.bind(i))
		if i == prep_tab:
			b.theme_type_variation = "ActiveButton"
		tabs.add_child(b)
	side.add_child(tabs)
	side.add_child(HSeparator.new())
	match prep_tab:
		0:
			_prep_menu()
		1:
			_prep_shop()
		2:
			_prep_staff()
		3:
			_prep_furniture()
		4:
			_prep_activity()
		5:
			_prep_special()
	side.add_child(HSeparator.new())
	var open := _pbtn("🔔 開始營業（17:00）", _start_business)
	side.add_child(open)
	side.add_child(_wbtn("← 回到商店街", enter_explore, int(s.action_points) <= 0))

func _set_prep_tab(i: int) -> void:
	prep_tab = i
	placing = ""
	moving_fid = ""
	view.set_ghost("", Vector2i.ZERO, false)
	_build_prepare_side()

func _prep_menu() -> void:
	side.add_child(_label("菜單 %d／%d" % [s.menu.size(), Data.MAX_MENU], 15, "#8f6a77"))
	_hint("括號是材料夠做幾份。")
	for cat in ["drink", "dessert", "main"]:
		side.add_child(_label(Data.CAT_NAMES[cat], 15, "#d94f82"))
		for id in s.unlocked_dishes:
			var d: Dictionary = Data.DISHES[id]
			if d.cat != cat:
				continue
			var avail := World.dish_available(s, id)
			var on: bool = id in s.menu
			var tag := ""
			if d.get("signature", false):
				tag = "★招牌 "
			elif d.get("story", false):
				tag = "📖 "
			elif d.get("collab", false):
				tag = "🤝聯名 "
			elif d.has("season"):
				tag = "🍃季節 "
			var buzz := float(s.dish_buzz.get(id, 0.0))
			var t := "%s %s%s ¥%d（%d）%s" % ["☑" if on else "☐", tag, d.name, int(d.price), World.servings(s.inventory, id), "  📣%d" % int(buzz) if buzz >= 3 else ""]
			side.add_child(_wbtn(t, _toggle_dish.bind(id), not avail))

func _toggle_dish(id: String) -> void:
	toast(World.toggle_menu(s, id))
	_build_prepare_side()

func _prep_shop() -> void:
	var by_shop := {}
	for id in Data.INGREDIENTS:
		var ing: Dictionary = Data.INGREDIENTS[id]
		if not World.ingredient_available(s, id) and int(s.inventory.get(id, 0)) == 0:
			continue
		if not by_shop.has(ing.shop):
			by_shop[ing.shop] = []
		by_shop[ing.shop].append(id)
	var need := {}
	for id in s.menu:
		for ing in Data.DISHES[id].ing:
			need[ing] = true
	_hint("★ = 今天菜單會用到的材料。")
	for shop in ["grocer", "general", "sweets"]:
		side.add_child(_label(Data.LOCATIONS[shop].name + ("" if World.shop_open(s, shop) else "（今天公休）"), 15, "#d94f82"))
		for id in by_shop.get(shop, []):
			var h := HBoxContainer.new()
			var l := _label("%s%s ¥%d　庫存 %d" % ["★" if need.has(id) else "　", Data.INGREDIENTS[id].name, World.ingredient_price(s, id), int(s.inventory.get(id, 0))], 14)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(l)
			var ok := World.ingredient_available(s, id)
			h.add_child(_btn("+1", _buy.bind(id, 1), not ok))
			h.add_child(_btn("+5", _buy.bind(id, 5), not ok))
			side.add_child(h)
	side.add_child(_wbtn("🛒 自動補到每道菜 5 份", _auto_stock))

func _buy(id: String, n: int) -> void:
	toast(World.buy_ingredient(s, id, n))
	_build_prepare_side()

func _auto_stock() -> void:
	var want := {}
	for id in s.menu:
		for ing in Data.DISHES[id].ing:
			want[ing] = int(want.get(ing, 0)) + 5 * int(Data.DISHES[id].ing[ing])
	var spent := 0
	for ing in want:
		var n := int(want[ing]) - int(s.inventory.get(ing, 0))
		if n > 0 and World.ingredient_available(s, ing) and World.buy_ingredient(s, ing, n) == "":
			spent += n * World.ingredient_price(s, ing)
	toast("花了 ¥%d 補貨。" % spent)
	_build_prepare_side()

func _prep_staff() -> void:
	for m in St.active_maids(s):
		var def: Dictionary = Data.MAIDS[m.id]
		var box := VBoxContainer.new()
		var info := "[b]%s[/b]　%s\n心情 %d　疲勞 %d　%s" % [def.name, "、".join(def.traits.map(func(x): return Data.TRAITS[x].name)), int(m.mood), int(m.fatigue),
			("💭 " + m.concern.sign) if not m.concern.is_empty() else ""]
		if m.get("preferred_role", "") != "":
			info += "\n（想做：%s）" % Data.ROLE_NAMES[m.preferred_role]
		box.add_child(_rich(info))
		var roles := HFlowContainer.new()
		for r in ["reception", "kitchen", "floor", "support", "stage", "off"]:
			var b := _tbtn(Data.ROLE_NAMES[r], _set_role.bind(m.id, r), m.role == r)
			roles.add_child(b)
		box.add_child(roles)
		var why := Story.can_train(s, m.id)
		var tb := _wbtn("✨ 特訓．檔案（羈絆 Lv%d）" % Story.heart_rank(s, m.id), _open_maid.bind(m.id))
		tb.tooltip_text = why if why != "" else "陪她練習，提升能力與羈絆"
		box.add_child(tb)
		side.add_child(box)
		side.add_child(HSeparator.new())
	var rest := 5 - St.active_maids(s).size()
	if rest > 0:
		_hint("還可以再招募 %d 人。在商店街可能會遇到想打工的人。" % rest)

func _set_role(mid: String, r: String) -> void:
	s.maids[mid].role = r
	_build_prepare_side()

func _prep_furniture() -> void:
	var style := World.dominant_style(s)
	side.add_child(_label("風格：%s" % style.name, 15, "#8f6a77"))
	_hint("左鍵放置，Esc 取消。")
	if placing != "" or moving_fid != "":
		side.add_child(_label("👉 在店內點選位置放置……", 15, "#e8790f"))
	for type in Data.FURNITURE:
		var d: Dictionary = Data.FURNITURE[type]
		var b := _wbtn("%s　¥%d%s" % [d.name, int(d.price), ("\n　" + d.desc) if Settings.hints() else ""], _start_place.bind(type), float(s.money) < float(d.price))
		b.tooltip_text = d.desc
		side.add_child(b)
	side.add_child(_label("設備升級", 15, "#d94f82"))
	for id in Data.UPGRADES:
		var u: Dictionary = Data.UPGRADES[id]
		side.add_child(_wbtn("%s %s ¥%d\n　%s" % ["✔" if s.upgrades[id] else "", u.name, int(u.price), u.desc], _buy_upgrade.bind(id), s.upgrades[id]))
	_hint("點選店內的家具可以移動或賣掉。")
	var fm: Dictionary = Layout.new(s.furniture, s.upgrades).flow_metrics()
	side.add_child(_label("📐 動線：出餐口→桌子平均 %.1f 步（最遠 %d），門口→桌子平均 %.1f 步，窄道 %d 格" % [fm.kitchen_avg, int(fm.kitchen_max), fm.door_avg, int(fm.narrow)], 13, "#3f9a86"))

func _start_place(type: String) -> void:
	placing = type
	moving_fid = ""
	_build_prepare_side()

func _buy_upgrade(id: String) -> void:
	toast(World.buy_upgrade(s, id))
	view.rebuild_room()
	_set_sim(Biz.new(s, "offhours"))
	_build_prepare_side()

func _prep_activity() -> void:
	side.add_child(_label("今天的活動", 15, "#d94f82"))
	for id in Data.ACTIVITIES:
		var a: Dictionary = Data.ACTIVITIES[id]
		var req := World.activity_requirement(s, id) if id != "none" else ""
		var b := _wbtn("%s　¥%d%s%s" % [a.name, int(a.cost), ("\n　" + a.desc) if Settings.hints() else "", ("\n　⚠ " + req) if req != "" else ""], _set_activity.bind(id), req != "")
		b.tooltip_text = a.desc
		if s.activity == id:
			b.theme_type_variation = "ActiveButton"
		side.add_child(b)
	if s.activity == "limited":
		side.add_child(_label("限定料理：", 14))
		var fl := HFlowContainer.new()
		for id in s.menu:
			fl.add_child(_tbtn(Data.DISHES[id].name, _set_featured.bind(id), s.featured_dish == id))
		side.add_child(fl)
	side.add_child(_label("音樂", 15, "#d94f82"))
	var mf := HFlowContainer.new()
	for k in Data.MUSIC:
		mf.add_child(_tbtn(Data.MUSIC[k], _set_music.bind(k), s.music == k))
	side.add_child(mf)
	side.add_child(_label("燈光", 15, "#d94f82"))
	var lf := HFlowContainer.new()
	for k in Data.LIGHTING:
		lf.add_child(_tbtn(Data.LIGHTING[k], _set_lighting.bind(k), s.lighting == k))
	side.add_child(lf)
	_hint("音樂和燈光會影響店的風格，以及喜歡不同氣氛的客人。")
	var season := Data.season(int(s.day))
	var dc: Dictionary = LD.DECOR[season]
	side.add_child(_label("季節裝飾", 15, "#d94f82"))
	if s.get("decor", "") == season:
		side.add_child(_label("✔ 已經掛上了「%s」" % dc.name, 15, MaidTheme.C.good))
	else:
		var db := _wbtn("🎐 掛上「%s」　¥%d" % [dc.name, int(dc.price)], _set_decor)
		db.tooltip_text = dc.desc + "喜歡新奇的客人更容易上門，喜歡季節裝飾的女僕心情會變好。"
		side.add_child(db)

func _set_decor() -> void:
	var e := World.set_decor(s)
	toast(e if e != "" else "掛上了季節裝飾！")
	view.rebuild_room()
	_build_prepare_side()

func _set_activity(id: String) -> void:
	toast(World.set_activity(s, id, s.menu[0] if id == "limited" and not s.menu.is_empty() else ""))
	_build_prepare_side()

func _set_featured(id: String) -> void:
	s.featured_dish = id
	_build_prepare_side()

func _set_music(k: String) -> void:
	s.music = k
	_build_prepare_side()

func _set_lighting(k: String) -> void:
	s.lighting = k
	_build_prepare_side()

func _prep_special() -> void:
	var ups := World.upcoming_special_days(s, 3)
	var bm := World.birthday_maid(s)
	if bm != "":
		side.add_child(_label("🎂 今天是%s的生日！可以舉辦「女僕生日會」。" % Data.MAIDS[bm].name, 15, "#e8790f"))
		ups.push_front({"kind": "birthday", "who": bm, "in": 0, "title": "%s的生日（今天）" % Data.MAIDS[bm].name})
	if ups.is_empty():
		side.add_child(_label("最近三天沒有特別的日子。", 14, "#8f6a77"))
	for u in ups:
		side.add_child(_label("📅 %s%s" % [u.title, "" if u.in == 0 else "（%d 天後）" % u.in], 15, "#d94f82"))
		if u.kind == "birthday":
			var key: String = "birthday_" + u.who
			var prep: Dictionary = s.special_prep.get(key, {})
			for k in [["cake", "訂蛋糕 ¥250"], ["decor", "做裝飾 ¥300"], ["gift", "準備禮物 ¥400"], ["letter", "請大家寫卡片"]]:
				side.add_child(_wbtn(("✔ " if prep.has(k[0]) else "") + k[1], _prep.bind(key, k[0]), prep.has(k[0])))
			_hint("準備得越用心，壽星越開心；同事感情好的話，她們也會自己準備。")

func _prep(key: String, kind: String) -> void:
	toast(World.prepare_special(s, key, kind))
	_build_prepare_side()

# ======================================================================== business
func _start_business() -> void:
	var e := Settle.begin_business(s)
	if e != "":
		show_modal("還不能開店", e, [["好", close_modal]])
		return
	placing = ""
	moving_fid = ""
	view.set_ghost("", Vector2i.ZERO, false)
	_set_sim(Biz.new(s, "business"))
	paused = false
	_build_business_side()

var _biz_live: RichTextLabel

func _build_business_side() -> void:
	_clear(side)
	side.add_child(_section("🍰 營業中"))
	var sp := HBoxContainer.new()
	for v in [[1.0, "x1"], [2.0, "x2"], [4.0, "x4"]]:
		sp.add_child(_btn(v[1], _set_speed.bind(v[0])))
	sp.add_child(_btn("⏸／▶", _toggle_pause))
	side.add_child(sp)
	_biz_live = _rich("")
	side.add_child(_biz_live)
	_hint("指揮（消耗指揮點數，每 40 秒回復 1 點）")
	side.add_child(_wbtn("🏃 外場優先（送餐、整理優先 30 秒）", _cmd_boost.bind("floor", 30.0)))
	side.add_child(_wbtn("⭐ 熟客優先（熟客先帶位、先上菜 40 秒）", _cmd_boost.bind("regulars", 40.0)))
	var jf := HFlowContainer.new()
	for jt in [["cook", "優先製作"], ["clean", "優先整理桌面"], ["greet", "優先帶位"], ["mess", "優先清地板"]]:
		jf.add_child(_btn(jt[1], _cmd_boost.bind("job_" + jt[0], 30.0)))
	side.add_child(jf)
	side.add_child(_wbtn("🚪 暫停／恢復接待新客人", _cmd_door))
	side.add_child(HSeparator.new())
	_hint("女僕（點選角色可以看詳情、指派工作）")
	for m in St.active_maids(s):
		var box := VBoxContainer.new()
		box.add_child(_label(Data.MAIDS[m.id].name, 15, "#d94f82"))
		var fl := HFlowContainer.new()
		for r in ["reception", "kitchen", "floor", "support"]:
			fl.add_child(_btn(Data.ROLE_NAMES[r], _cmd_role.bind(m.id, r)))
		fl.add_child(_btn("休息", _cmd_rest.bind(m.id)))
		fl.add_child(_btn("暫停", _cmd_pause.bind(m.id)))
		box.add_child(fl)
		side.add_child(box)
	_hint("右鍵地板：店長移動．右鍵髒桌子／出餐口／壞掉的設備：店長親自處理．點客人可以讓店長去寒暄。")

func _refresh_business_side_live() -> void:
	if _biz_live == null or not is_instance_valid(_biz_live) or sim == null:
		return
	var pc: Dictionary = sim.pending_counts()
	var parts := []
	for k in pc:
		parts.append("%s %d" % [Biz.JOB_NAMES.get(k, k), int(pc[k])])
	var t := "營收 ¥%s　接待 %d　流失 %d\n待辦：%s" % [_money(sim.revenue), sim.served_count, sim.lost, "、".join(parts) if not parts.is_empty() else "（無）"]
	var lines := []
	for w in sim.workers:
		if w.kind == "maid":
			var m: Dictionary = s.maids[w.maid_id]
			lines.append("%s［%s］%s　😊%d 😮‍💨%d" % [w.name, Data.ROLE_NAMES.get(m.role, m.role), w.activity, int(m.mood), int(m.fatigue)])
	t += "\n" + "\n".join(lines)
	if sim.door_closed:
		t += "\n[color=#d9622b]🚪 暫停接待中[/color]"
	_biz_live.text = t

func _set_speed(v: float) -> void:
	speed = v
	paused = false

func _toggle_pause() -> void:
	paused = not paused

func _cmd_boost(n: String, secs: float) -> void:
	toast(sim.order_boost(n, secs))

func _cmd_door() -> void:
	toast(sim.toggle_door())

func _cmd_role(mid: String, r: String) -> void:
	toast(sim.set_role(mid, r))

func _cmd_rest(mid: String) -> void:
	toast(sim.send_rest(mid))

func _cmd_pause(mid: String) -> void:
	toast(sim.toggle_pause(mid))

func _end_business() -> void:
	report = Settle.settle(s, sim)
	_set_sim(Biz.new(s, "offhours"))
	log_label.append_text("[color=#8f6a77]打烊了。大家開始收拾，各自做著自己的事。[/color]\n")
	night_step = "report"
	_clear(side)
	side.add_child(_section("🌙 打烊了"))
	_hint("看看今天的報告吧。")
	_show_report(0)

# ======================================================================== night
func _show_report(page: int) -> void:
	var r := report
	var body := ""
	var btns := []
	match page:
		0:
			var exp: Dictionary = r.expenses
			body = "[b]營收[/b] ¥%s（含展示櫃商品 ¥%s）\n[b]支出[/b] ¥%s　（食材 %d、薪水 %d、房租 %d、水電 %d、維護 %d、活動 %d、宣傳 %d、家具 %d）\n[b]淨利[/b] ¥%s\n\n接待 %d 位．流失 %d 位．客訴 %d（處理 %d）．平均滿意度 %d\n人氣 %+d → %d．口碑 %d．店的風格：%s" % [
				_money(r.revenue), _money(r.goods), _money(r.total_expenses), int(exp.ingredients), int(exp.wages), int(exp.get("rent", 0)), int(exp.utilities), int(exp.maintenance),
				int(exp.activity), int(exp.promotion), int(exp.furniture), _money(float(r.revenue) - float(r.total_expenses)), r.served, r.lost, r.complaints, r.complaints_handled,
				r.avg_sat, r.pop_delta, int(s.popularity), r.reputation, r.style]
			if not r.incidents.is_empty():
				var inc := []
				var names := {"aircon": "冷氣故障", "breakdown": "設備故障", "crowding": "擁擠", "dispute": "客人糾紛", "overwork": "過勞", "seat_change": "換座位", "spill": "打翻", "wrong_order": "送錯餐"}
				for k in r.incidents:
					inc.append("%s ×%d" % [names.get(k, k), int(r.incidents[k])])
				body += "\n今天發生的事：" + "、".join(inc)
		1:
			var lines := []
			for rv in r.reviews:
				var why := ""
				if not rv.reasons.is_empty():
					why = "　[color=#a07d8a]（來店原因：%s）[/color]" % "、".join(rv.reasons)
				lines.append("[b]%s[/b]　%s%s" % [rv.customer, rv.text, why])
			body = "\n".join(lines) if not lines.is_empty() else "今天沒有客人……"
		2:
			body = "\n".join(r.maid_notes.map(func(x): return x.text))
			if not r.social.is_empty():
				body += "\n\n" + "\n".join(r.social)
			if not r.moments.is_empty():
				body += "\n\n[color=#e0518e]🌸 " + "\n🌸 ".join(r.moments) + "[/color]"
		3:
			var fl: Dictionary = r.flow
			body = "\n".join(r.advice)
			body += "\n\n[b]📐 動線分析[/b]\n出餐口到桌子：平均 %.1f 步，最遠 %d 步\n門口到桌子：平均 %.1f 步\n窄道：%d 格．今天塞住 %d 秒" % [fl.kitchen_avg, int(fl.kitchen_max), fl.door_avg, int(fl.narrow), r.congestion]
			if not r.hot.is_empty():
				body += "\n最常卡住的位置：" + "、".join(r.hot.map(func(h): return "(%d,%d) %.0f秒" % [h.x, h.z, h.v]))
			btns.append(["🔥 在店內顯示擁擠熱點", _toggle_heat])
	var titles := ["今日營業報告", "客人的評價", "女僕們與店裡的關係", "建議與動線"]
	if page > 0:
		btns.append(["← 上一頁", _show_report.bind(page - 1)])
	if page < 3:
		btns.append(["下一頁 →", _show_report.bind(page + 1)])
	else:
		btns.append(["結束報告", _night_events])
	show_modal("%s（%d/4）— %s" % [titles[page], page + 1, r.date], body, btns, null, 860)

func _toggle_heat() -> void:
	view.set_heat(not view.show_heat, report.get("heat_map", {}))

var _portrait = null

func _night_events() -> void:
	var ev := Events.next_event(s)
	if ev.is_empty():
		_hide_portrait()
		close_modal()
		_enter_night_scene()
		return
	var btns := []
	for i in ev.choices.size():
		btns.append([ev.choices[i], _choose_event.bind(ev.id, i)])
	_show_portrait(ev.who)
	show_modal("🌙 " + ev.title, "\n\n".join(ev.lines), btns)

func _choose_event(id: String, idx: int) -> void:
	var res := Events.resolve(s, id, idx)
	show_modal("🌙", res, [["繼續", _night_events]])

func _show_portrait(who: String) -> void:
	if not ResourceLoader.exists(PORTRAIT_SCRIPT) or who == "":
		return
	if _portrait == null:
		var scr = load(PORTRAIT_SCRIPT)
		if scr == null:
			return
		_portrait = scr.new()
		ui.add_child(_portrait)
		ui.move_child(_portrait, 0)
	if _portrait.has_method("show_character"):
		_portrait.show_character(who, {"expression": "smile", "position": "left"})
	if _portrait.has_method("set_speaker"):
		_portrait.set_speaker(who)

func _hide_portrait() -> void:
	if _portrait != null and is_instance_valid(_portrait):
		# let the portrait play its exit animation before freeing it
		var p = _portrait
		if p.has_method("clear"):
			p.clear()
		get_tree().create_timer(0.35).timeout.connect(func(): if is_instance_valid(p): p.queue_free())
	_portrait = null

func _enter_night_scene() -> void:
	s.phase = "night"
	night_step = "scene"
	_clear(side)
	side.add_child(_section("🌙 打烊後"))
	_hint("店裡只剩下女僕們。她們會依照自己的習慣和關係，做些營業時看不到的事。")
	var con := []
	for m in St.active_maids(s):
		if not m.concern.is_empty():
			con.append(m)
	for m in con:
		var n: String = Data.MAIDS[m.id].name
		side.add_child(_rich("[color=#e0518e]💭 %s[/color]%s" % [m.concern.sign, ("\n　%s：「%s」" % [n, m.concern.confide]) if m.concern.get("revealed", false) else "\n　[color=#8f6a77]（白天回店裡找她聊聊，可能會知道原因）[/color]"]))
		var fl := HFlowContainer.new()
		for o in Social.options(s, m.id):
			fl.add_child(_btn(o.label, _night_concern.bind(m.id, o.id)))
		side.add_child(fl)
	for m in St.active_maids(s):
		if not m.want_talk.is_empty():
			side.add_child(_wbtn("💬 %s好像有話想說：「%s」" % [Data.MAIDS[m.id].name, m.want_talk.get("short", "")], _open_talk.bind(m.id)))
	side.add_child(HSeparator.new())
	side.add_child(_wbtn("📒 打開筆記本", _open_notebook))
	side.add_child(_wbtn("📷 回憶相簿", _open_album))
	side.add_child(_wbtn("🔥 顯示／隱藏今天的擁擠熱點", _toggle_heat))
	var b := _pbtn("☀ 迎接明天（自動存檔）", _next_day)
	side.add_child(b)

func _night_concern(mid: String, opt: String) -> void:
	toast(Social.resolve(s, mid, opt))
	_enter_night_scene()

func _next_day() -> void:
	view.set_heat(false, {})
	Settle.next_day(s)
	St.save_game(s)
	view.rebuild_room()
	enter_explore()

# ======================================================================== picking
func _on_agent_clicked(kind: String, id: String) -> void:
	if placing != "" or moving_fid != "":
		return
	sel_kind = kind
	sel_id = id
	view.selected_id = id
	inspector_panel.visible = true
	_refresh_inspector()

func _on_cell_clicked(c: Vector2i, button: int) -> void:
	if modal.visible:
		return
	if s.phase == "prepare" and button == MOUSE_BUTTON_LEFT:
		if placing != "":
			var e := World.buy_furniture(s, placing, c.x, c.y)
			toast(e if e != "" else "放好了：%s" % Data.FURNITURE[placing].name)
			if e == "":
				placing = ""
				view.set_ghost("", Vector2i.ZERO, false)
				_set_sim(Biz.new(s, "offhours"))
			_build_prepare_side()
			return
		if moving_fid != "":
			var e := World.move_furniture(s, moving_fid, c.x, c.y)
			toast(e if e != "" else "移動好了。")
			if e == "":
				moving_fid = ""
				view.set_ghost("", Vector2i.ZERO, false)
				_set_sim(Biz.new(s, "offhours"))
			_build_prepare_side()
			return
		var lay = Layout.new(s.furniture, s.upgrades)
		var f = lay.furniture_at.get(Layout.key(c), null)
		if f != null:
			show_modal(Data.FURNITURE[f.type].name, Data.FURNITURE[f.type].desc, [["移動", _start_move.bind(f.id)], ["賣掉（半價）", _sell.bind(f.id)], ["取消", close_modal]])
		return
	if s.phase == "business" and sim != null and button == MOUSE_BUTTON_RIGHT:
		var j = sim.job_at_cell(c)
		if j != null:
			toast(sim.manager_do(j.id))
		elif not sim.manager_move(c):
			toast("店長走不到那裡。")
	if button == MOUSE_BUTTON_LEFT:
		sel_id = ""
		view.selected_id = ""
		inspector_panel.visible = false

func _start_move(fid: String) -> void:
	close_modal()
	moving_fid = fid
	_build_prepare_side()

func _sell(fid: String) -> void:
	toast(World.sell_furniture(s, fid))
	close_modal()
	_set_sim(Biz.new(s, "offhours"))
	_build_prepare_side()

func _refresh_inspector() -> void:
	if sim == null:
		return
	_clear(inspector_buttons)
	var t := ""
	var w = sim.worker(sel_id)
	if w == null:
		for x in sim.workers:
			if x.id == sel_id:
				w = x
	if w != null:
		t = _inspect_worker(w)
	else:
		var found = null
		var fp = null
		for p in sim.parties:
			for m in p.members:
				if m.id == sel_id:
					found = m
					fp = p
		if found == null:
			inspector_panel.visible = false
			return
		t = _inspect_customer(found, fp)
	inspector.text = t

func _inspect_worker(w) -> String:
	if w.kind == "manager":
		return "[b]店長（妳）[/b]\n%s\n\n右鍵地板移動，右鍵工作地點親自處理。管理能力高，適合處理客訴與糾紛。" % w.activity
	var m: Dictionary = s.maids[w.maid_id]
	var def: Dictionary = Data.MAIDS[w.maid_id]
	var t := "[b]%s[/b]　［%s］\n%s\n" % [def.name, Data.ROLE_NAMES.get(m.role, m.role), def.intro]
	t += "特質：%s\n" % "、".join(def.traits.map(func(x): return Data.TRAITS[x].name))
	t += "心情 %d　疲勞 %d\n" % [int(m.mood), int(m.fatigue)]
	t += "[color=#e8790f]現在：%s[/color]\n" % w.activity
	if w.job != null:
		t += "工作：%s（%d 步驟剩餘）\n" % [Biz.JOB_NAMES.get(w.job.type, w.job.type), w.steps.size()]
	if w.last_fail != "":
		t += "[color=#d9622b]上次放棄：%s[/color]\n" % w.last_fail
	if not m.concern.is_empty():
		t += "[color=#e0518e]💭 %s[/color]\n" % m.concern.sign
	t += "對店長的信賴 %d\n" % int(m.bond)
	if not m.want_talk.is_empty():
		t += "[color=#c9861a]💬 有話想說：%s[/color]\n" % m.want_talk.get("short", "")
		if s.phase != "business":
			inspector_buttons.add_child(_btn("💬 聽她說", _open_talk.bind(w.maid_id)))
	var habits := []
	for h in m.habits:
		if float(m.habits[h]) >= 20:
			habits.append("%s %d" % [Data.HABITS[h].name, int(m.habits[h])])
	if not habits.is_empty():
		t += "習慣：%s\n" % "、".join(habits)
	if s.phase == "business" and not w.candidates.is_empty():
		t += "\n[b]工作候選（分數／原因）[/b]\n"
		for c in w.candidates.slice(0, 4):
			t += "・%s %s　[color=#8f6a77]%s[/color]\n" % [Biz.JOB_NAMES.get(c.type, c.type), str(c.score) if c.score >= 0 else "✕", c.why]
		for c in w.candidates.slice(0, 4):
			if c.score >= 0:
				inspector_buttons.add_child(_btn("指派：%s" % Biz.JOB_NAMES.get(c.type, c.type), _assign.bind(w.maid_id, c.job)))
	return t

func _assign(mid: String, jid: String) -> void:
	toast(sim.assign_job(mid, jid))

func _inspect_customer(c, p) -> String:
	var t := "[b]%s[/b]\n" % c.name
	t += "狀態：%s　滿意度 %d\n" % [p.state, int(c.sat)]
	if not p.reasons.is_empty():
		t += "來店原因：%s\n" % "、".join(p.reasons)
	if not c.causes.is_empty():
		t += "感受：%s\n" % "、".join(c.causes.keys().map(func(k): return Settle.CAUSE_TEXT.get(k, k)))
	if c.def_id != "":
		var def: Dictionary = Data.CUSTOMERS[c.def_id]
		var mem: Dictionary = s.customers[c.def_id]
		t += "\n%s\n來店 %d 次．忠誠 %d%s\n" % [def.desc, int(mem.visits), int(mem.loyalty), "．熟客" if mem.is_regular else ""]
		if mem.fav_maid != "":
			t += "喜歡的女僕：%s\n" % Data.MAIDS[mem.fav_maid].name
		if mem.fav_dish != "":
			t += "常點：%s\n" % Data.DISHES[mem.fav_dish].name
	if s.phase == "business":
		inspector_buttons.add_child(_btn("店長去寒暄", _chat.bind(p.id)))
	return t

func _chat(pid: String) -> void:
	toast(sim.manager_chat(pid))

# ======================================================================== debug
func _toggle_debug() -> void:
	debug_panel.visible = not debug_panel.visible
	view.show_debug = debug_panel.visible

func _refresh_debug() -> void:
	if sim == null:
		return
	var t := "[b]DEBUG[/b] mode=%s t=%.1f claims=%d congestion=%.0f\n" % [sim.mode, sim.t, sim._claims.size(), sim.congestion]
	var hc: Array = sim.health_check()
	t += ("[color=#2f9b72]health OK[/color]\n" if hc.is_empty() else "[color=#d23c4f]" + "; ".join(hc) + "[/color]\n")
	for w in sim.workers:
		var step := "-"
		if not w.steps.is_empty():
			step = "%s:%s" % [w.steps[0].kind, w.steps[0].get("label", "")]
		t += "[color=#e8790f]%s[/color] %s job=%s step=%s cell=%s path=%d%s%s\n" % [w.name, w.activity, (w.job.type + "#" + w.job.id) if w.job != null else "-", step, str(w.cell), w.path.size(),
			" GHOST" if w.ghost else "", (" fail=" + w.last_fail) if w.last_fail != "" else ""]
		for c in w.candidates.slice(0, 3):
			t += "   %s %s (%s)\n" % [c.type, str(c.score), c.why]
	t += "[b]jobs[/b] "
	for j in sim.jobs:
		if not j.done and not j.cancelled:
			t += "%s#%s[%s %ds] " % [j.type, j.id, j.claimed if j.claimed != "" else "-", int(sim.t - float(j.created))]
	t += "\n[b]arrivals[/b] "
	for a in sim.arrivals:
		if not a.done:
			t += "%ds:%s(%s) " % [int(a.t), ",".join(a.ids) if not a.ids.is_empty() else "walk-in", "/".join(a.reasons)]
	t += "\n[b]relation log[/b]\n"
	for r in s.rel_log.slice(maxi(0, s.rel_log.size() - 6)):
		t += "D%d %s-%s %s %+.1f %s\n" % [r.day, r.a, r.b, r.dim, r.amount, r.reason]
	t += "[b]memory triggers[/b]\n"
	for d in s.debug_log.slice(maxi(0, s.debug_log.size() - 4)):
		t += d + "\n"
	debug_label.text = t

# ======================================================================== notebook
func _open_notebook() -> void:
	_notebook_page("maids")

func _notebook_page(page: String) -> void:
	var tabs := HFlowContainer.new()
	for p in [["maids", "女僕"], ["rel", "關係"], ["promise", "約定"], ["cust", "顧客"], ["street", "商店街"], ["moments", "每日瞬間"]]:
		tabs.add_child(_tbtn(p[1], _notebook_page.bind(p[0]), p[0] == page))
	var body := ""
	match page:
		"maids":
			for m in St.active_maids(s):
				var def: Dictionary = Data.MAIDS[m.id]
				var sk := []
				for k in Data.SKILLS:
					sk.append("%s %d" % [Data.SKILL_NAMES[k], int(m.skills[k])])
				var hb := []
				for h in m.habits:
					if float(m.habits[h]) >= 10:
						hb.append("%s %d" % [Data.HABITS[h].name, int(m.habits[h])])
				body += "[b][color=#d94f82]%s[/color][/b]　%s　生日：%s\n%s\n習慣：%s\n心情 %d　疲勞 %d　工作 %d 天%s\n\n" % [def.name, "、".join(def.traits.map(func(x): return Data.TRAITS[x].name)),
					Data.date_label(int(def.birthday)).split("（")[0], "、".join(sk), "、".join(hb) if not hb.is_empty() else "（還沒有明顯的習慣）", int(m.mood), int(m.fatigue), int(m.days_worked),
					("\n💭 " + m.concern.sign) if not m.concern.is_empty() else ""]
				body = body.trim_suffix("\n\n") + "\n" + _maid_life_text(m) + "\n\n"
		"rel":
			body += "[color=#8f6a77]每個人對別人的感覺不一定一樣：「A → B」是 A 怎麼看 B。[/color]\n\n"
			var ms := St.active_maids(s)
			for i in ms.size():
				for k in range(i + 1, ms.size()):
					var a: String = ms[i].id
					var b: String = ms[k].id
					var r := St.rel(s, a, b)
					var r2 := St.rel(s, b, a)
					body += "[b]%s → %s[/b]　親近 %d．信任 %d．默契 %d．摩擦 %d\n" % [Data.MAIDS[a].name, Data.MAIDS[b].name, int(r.close), int(r.trust), int(r.synergy), int(r.friction)]
					body += "[b]%s → %s[/b]　親近 %d．信任 %d．默契 %d．摩擦 %d\n" % [Data.MAIDS[b].name, Data.MAIDS[a].name, int(r2.close), int(r2.trust), int(r2.synergy), int(r2.friction)]
					for sh in r.shared:
						body += "　[color=#e0518e]・D%d %s[/color]\n" % [sh.day, sh.text]
			body += "\n[b]最近的變化與原因[/b]\n"
			for r in s.rel_log.slice(maxi(0, s.rel_log.size() - 12)):
				body += "D%d %s%s%s %s %+.1f：%s\n" % [r.day, Data.MAIDS[r.a].name, "↔" if r.get("mutual", true) else "→", Data.MAIDS[r.b].name, {"close": "親近", "trust": "信任", "synergy": "默契", "friction": "摩擦"}.get(r.dim, r.dim), r.amount, r.reason]
		"promise":
			var open := []
			var closed := []
			for pr in s.promises:
				(open if pr.status == "open" else closed).append(pr)
			body += "[b]還沒完成的約定[/b]\n"
			for pr in open:
				body += "・%s：%s　[color=#8f6a77]（%s）[/color]\n" % [Data.MAIDS[pr.maid].name, pr.text, ("第 %d 天" % int(pr.target)) if pr.kind == "dayoff_on" else ("到第 %d 天前" % int(pr.due))]
			if open.is_empty():
				body += "[color=#8f6a77]（目前沒有）[/color]\n"
			body += "\n[b]過去的約定[/b]\n"
			closed.reverse()
			for pr in closed.slice(0, 15):
				body += "%s D%d %s：%s\n" % [{"kept": "🤝", "broken": "💔", "void": "・"}.get(pr.status, "・"), int(pr.get("closed", pr.day)), Data.MAIDS[pr.maid].name, pr.text]
			body += "\n[color=#8f6a77]約定不需要另外回報：只要真的做到（擺了家具、放了那種音樂、讓她放假……），當天晚上她就會發現。[/color]"
		"cust":
			for cid in Data.CUSTOMERS:
				var mem: Dictionary = s.customers[cid]
				if not mem.known:
					continue
				var def: Dictionary = Data.CUSTOMERS[cid]
				body += "[b][color=#d94f82]%s[/color][/b]%s　來店 %d 次．忠誠 %d\n%s\n" % [def.name, "（熟客）" if mem.is_regular else "", int(mem.visits), int(mem.loyalty), def.desc]
				var habit := []
				var total := 0
				for v in mem.weekday_counts:
					total += int(v)
				if total >= 3:
					for d in 7:
						if float(mem.weekday_counts[d]) / total >= 0.3:
							habit.append("星期" + Data.WEEKDAYS[d])
				var favs := []
				if not habit.is_empty():
					favs.append("常在%s來" % "、".join(habit))
				if mem.fav_maid != "":
					favs.append("指名%s" % Data.MAIDS[mem.fav_maid].name)
				if mem.fav_dish != "":
					favs.append("常點%s" % Data.DISHES[mem.fav_dish].name)
				if mem.fav_seat != "":
					favs.append("老位子 %s" % mem.fav_seat)
				if not favs.is_empty():
					body += "　" + "．".join(favs) + "\n"
				for k in s.cust_rel:
					var cr: Dictionary = s.cust_rel[k]
					if cr.type != "" and cid in String(k).split("|"):
						var other: String = String(k).replace(cid, "").replace("|", "")
						body += "　🤝 和%s：%s\n" % [Data.CUSTOMERS[other].name, Data.RELATION_NAMES.get(cr.type, cr.type)]
				if mem.life.state != "" and mem.life.note != "":
					body += "　📖 最近：%s\n" % mem.life.note
				var imp := Life.impression_text(mem)
				if imp != "":
					body += "　💭 對店的印象：%s\n" % imp
				for k in s.cust_rel:
					var cr: Dictionary = s.cust_rel[k]
					if cid in String(k).split("|") and not cr.get("memories", []).is_empty():
						var other: String = String(k).replace(cid, "").replace("|", "")
						body += "　🫖 和%s：%s\n" % [Data.CUSTOMERS[other].name, cr.memories[cr.memories.size() - 1].text]
				for l in mem.log.slice(maxi(0, mem.log.size() - 3)):
					body += "　[color=#8f6a77]D%d %s[/color]\n" % [l.day, l.text]
				body += "\n"
		"street":
			for rid in Data.RESIDENTS:
				var def: Dictionary = Data.RESIDENTS[rid]
				var r := World.resident(s, rid)
				var where := []
				for i in Data.SLOTS.size():
					var loc := World.resident_location(s, rid, i)
					where.append("%s %s" % [Data.SLOTS[i], Data.LOCATIONS[loc].name.split("「")[0] if loc != "" else "—"])
				body += "[b]%s[/b]（%s）熟悉度 %d\n　今天：%s\n\n" % [def.name, def.role, int(r.aff), "．".join(where)]
			var nxt: String = s.street.get("next_event", "")
			if nxt != "":
				body += "聽說明天：%s\n" % World.STREET_EVENT_NAMES.get(nxt, nxt)
		"moments":
			var ms: Array = s.moments.duplicate()
			ms.reverse()
			for mo in ms:
				body += "[color=#e0518e]D%d[/color] %s\n" % [mo.day, mo.text]
			if ms.is_empty():
				body = "還沒有特別的瞬間。多看看店裡的人們吧。"
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(880, 560)
	var r := _rich(body)
	r.custom_minimum_size.x = 860
	sc.add_child(r)
	var box := VBoxContainer.new()
	box.add_child(tabs)
	box.add_child(sc)
	show_modal("📒 店長的筆記本", "", [["關閉", _close_notebook]], box, 900)

func _maid_life_text(m: Dictionary) -> String:
	var L := Life.life_of(m.id)
	var t := "對店長的信賴 %d" % int(m.bond)
	if not L.is_empty():
		t += "\n喜歡：%s\n不喜歡：%s\n興趣：%s" % ["、".join(L.likes.map(func(x): return Life.tag_name(x))), "、".join(L.dislikes.map(func(x): return Life.tag_name(x))), L.hobby]
	var feel: Array = m.flags.get("feel", [])
	if not feel.is_empty():
		t += "\n最近一天的心情：%s（%+.0f）" % ["、".join(feel), float(m.flags.get("feel_delta", 0.0))]
	if not m.want_talk.is_empty():
		t += "\n[color=#c9861a]💬 有話想說：%s[/color]" % m.want_talk.get("short", "")
	if m.role == "off" and not m.offday.is_empty():
		t += "\n☕ 今天休假：%s" % Data.LOCATIONS[m.offday.loc].name.split("「")[0]
	var mems: Array = m.memories.duplicate()
	mems.reverse()
	for mm in mems.slice(0, 3):
		t += "\n　[color=#e0518e]・D%d %s[/color]" % [int(mm.day), mm.text]
	return t

func _close_notebook() -> void:
	close_modal()
	if on_title:
		_title()
	elif s.phase == "night":
		if night_step == "report":
			_show_report(0)
		else:
			_enter_night_scene()

# ======================================================================== album & screenshots
var album_filter := ""

## The album: every important event once (deduplicated by key), filterable by kind or by person.
## When a photo is missing (not taken yet, or the file is gone) a drawn card stands in for it.
func _open_album(filter := "") -> void:
	album_filter = filter
	var tabs := HFlowContainer.new()
	for f in [["", "全部"], ["maid", "女僕"], ["pair", "兩個人"], ["customer", "客人"], ["cafe", "店裡"]]:
		tabs.add_child(_tbtn(f[1], _open_album.bind(f[0]), filter == f[0]))
	var people := {}
	for a in s.album:
		for id in a.get("who", []):
			people[id] = true
	for id in people:
		if Data.MAIDS.has(id) or Data.CUSTOMERS.has(id):
			tabs.add_child(_tbtn(_who_name(id), _open_album.bind("who:" + id), filter == "who:" + id))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var items: Array = []
	for a in s.album:
		if filter == "" or a.get("cat", "cafe") == filter or (filter.begins_with("who:") and filter.substr(4) in a.get("who", [])):
			items.append(a)
	items.reverse()
	for a in items:
		var card := VBoxContainer.new()
		card.custom_minimum_size = Vector2(280, 0)
		card.add_child(_album_picture(a))
		var who := []
		for id in a.get("who", []):
			who.append(_who_name(id))
		var info := _rich("")
		info.custom_minimum_size.x = 280
		card.add_child(info)
		info.text = ("[b][color=#d94f82]%s[/color][/b]\n[color=#8f6a77]%s%s[/color]\n%s" % [a.title, a.date, ("．" + "、".join(who)) if not who.is_empty() else "", a.text])
		grid.add_child(card)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(900, 540)
	sc.add_child(grid)
	var box := VBoxContainer.new()
	box.add_child(tabs)
	if items.is_empty():
		box.add_child(_label("這個分類還沒有回憶。", 14, "#8f6a77"))
	box.add_child(sc)
	show_modal("📷 Cafe Memories（%d）" % s.album.size(), "", [["關閉", _close_notebook]], box, 920)

func _who_name(id: String) -> String:
	return Data.MAIDS[id].name if Data.MAIDS.has(id) else Data.CUSTOMERS.get(id, {}).get("name", id)

static func album_has_photo(a: Dictionary) -> bool:
	var img: String = a.get("image", "")
	return img != "" and img != "pending" and FileAccess.file_exists(img)

func _album_picture(a: Dictionary) -> Control:
	if album_has_photo(a):
		var im := Image.load_from_file(a.image)
		if im != null:
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(im)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.custom_minimum_size = Vector2(280, 160)
			return tr
	# fallback card: the people in it (hair colours), the date and a note on why there is no photo
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(280, 160)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("fdeef2")
	sb.set_corner_radius_all(8)
	sb.border_color = Color("f6b6cb")
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	pc.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	for id in a.get("who", []).slice(0, 4):
		var hex: String = Data.MAIDS[id].hair if Data.MAIDS.has(id) else Data.CUSTOMERS.get(id, {}).get("color", "b597a2")
		var cr := ColorRect.new()
		cr.color = Color(hex)
		cr.custom_minimum_size = Vector2(34, 34)
		dots.add_child(cr)
	if a.get("who", []).is_empty():
		dots.add_child(_label({"cafe": "☕", "customer": "🫖", "pair": "🤝", "maid": "🎀"}.get(a.get("cat", "cafe"), "☕"), 30))
	v.add_child(dots)
	var why: String = "照片沖洗中……" if a.get("image", "") == "pending" else ("這天沒有留下照片" if a.get("image", "") == "" else "照片找不到了")
	var l1 := _label(a.title, 15, "#d94f82")
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l1)
	var l2 := _label("%s．%s" % [a.date.split("（")[0], why], 12, "#8f6a77")
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l2)
	pc.add_child(v)
	return pc

func _check_pending_screenshots() -> void:
	if capturing or s.is_empty():
		return
	for a in s.album:
		if a.get("image", "") == "pending":
			_capture(a)
			return

func _capture(entry: Dictionary) -> void:
	capturing = true
	ui.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	ui.visible = true
	DirAccess.make_dir_recursive_absolute("user://memories")
	var path := "user://memories/d%d_%d.png" % [int(entry.day), s.album.find(entry)]
	img.resize(640, int(640.0 * img.get_height() / img.get_width()))
	img.save_png(path)
	entry.image = path
	capturing = false

# ======================================================================== scripted playtest screenshots
## godot --path godot -- --shot=DIR : plays through the loop with UI and saves screenshots (used for automated playtests).
func _run_playtest_shots() -> void:
	var dir := autoshot
	DirAccess.make_dir_recursive_absolute(dir)
	Settings.reset(true)
	_build_theme()
	_title()
	await _wait(1.0)
	await _shot(dir + "/00_title.png")
	_open_settings()
	await _shot(dir + "/00_settings.png")
	s = St.new_game(7)
	on_title = false
	_set_hud(true)
	view.set_state(s)
	enter_explore()
	await _wait(0.5)
	await _shot(dir + "/00_story_intro.png")
	_begin_chapter()
	await _shot(dir + "/01_morning_briefing.png")
	close_modal()
	_on_visit("park")
	await _shot(dir + "/02_encounter.png")
	close_modal()
	World.visit_location(s, "general")
	World.visit_location(s, "plaza")
	_build_explore_side()
	await _wait(1.0)
	await _shot(dir + "/03_explore.png")
	World.buy_furniture(s, "bookshelf", 3, 9)
	World.buy_furniture(s, "vase", 14, 9)
	enter_prepare()
	prep_tab = 0
	_build_prepare_side()
	await _shot(dir + "/04_prepare_menu.png")
	_set_prep_tab(3)
	placing = "sofa_table"
	view.set_ghost("sofa_table", Vector2i(15, 8), true)
	await _shot(dir + "/05_prepare_furniture.png")
	placing = ""
	view.set_ghost("", Vector2i.ZERO, false)
	_auto_stock()
	_start_business()
	speed = 4.0
	await _wait(14.0)
	_toggle_debug()
	for w in sim.workers:
		if w.kind == "maid":
			_on_agent_clicked("maid", w.id)
			break
	await _wait(0.6)
	await _shot(dir + "/06_business_debug.png")
	_toggle_debug()
	while not sim.ended and s.phase == "business":
		await _wait(0.5)
	await _wait(0.5)
	await _shot(dir + "/07_report.png")
	_show_report(3)
	await _shot(dir + "/08_flow.png")
	_night_events()
	await _wait(0.3)
	await _shot(dir + "/09_night_event.png")
	var guard := 0
	while modal.visible and guard < 12:
		guard += 1
		var bs := modal_buttons.get_children()
		if bs.is_empty():
			break
		(bs[0] as Button).pressed.emit()
		await _wait(0.2)
	await _wait(6.0)
	await _shot(dir + "/10_after_hours.png")
	St.add_album(s, "打烊後的店裡", "（自動測試：確認回憶相簿會自動截圖）", s.staff.duplicate(), "pending")
	await _wait(1.0)
	print("ALBUM_IMAGE=", s.album[s.album.size() - 1].image, " exists=", FileAccess.file_exists(s.album[s.album.size() - 1].image))
	_open_notebook()
	_notebook_page("rel")
	await _shot(dir + "/11_notebook.png")
	_open_album()
	await _wait(0.5)
	await _shot(dir + "/12_album.png")
	# ---- Living Hearts screens
	_notebook_page("maids")
	await _shot(dir + "/13_notebook_maid_life.png")
	close_modal()
	s.maids.koharu.want_talk = {"topic": "request", "short": "在店裡擺一隻大型絨毛熊", "line": LD.MAID_LIFE.koharu.wants[0].ask, "day": int(s.day), "want": Life._pick_request(s, "koharu")}
	_enter_night_scene()
	_set_sim(Biz.new(s, "offhours"))
	await _wait(5.0)
	await _shot(dir + "/14_maid_seeks_manager.png")
	_open_talk("koharu")
	await _wait(0.4)
	await _shot(dir + "/15_talk.png")
	_on_talk_opt("koharu", "promise")
	close_modal()
	_notebook_page("promise")
	await _shot(dir + "/16_promises.png")
	close_modal()
	s.money = 99999.0
	World.buy_furniture(s, "plush", 3, 7)
	World.set_decor(s)
	view.rebuild_room()
	_set_sim(Biz.new(s, "offhours"))
	await _wait(8.0)
	await _shot(dir + "/17_decor_and_furniture.png")
	St.add_album(s, "沒有照片的一天", "（自動測試：照片遺失時的替代卡片）", ["koharu", "rin"], "user://memories/missing.png", "test_missing", "pair")
	_open_album("pair")
	await _wait(0.5)
	await _shot(dir + "/18_album_filter_fallback.png")
	# ---- story / raising screens
	close_modal()
	s.phase = "prepare"
	s.maids.koharu.bond = 58.0
	s.story.served_total = 31
	_build_prepare_side()
	_open_story()
	await _shot(dir + "/19_story_goals.png")
	_open_maids()
	await _wait(0.3)
	await _shot(dir + "/20_maids.png")
	_open_maid("koharu")
	await _wait(0.6)
	await _shot(dir + "/21_maid_profile.png")
	_do_train("koharu", "performance")
	await _wait(0.3)
	await _shot(dir + "/22_training.png")
	_close_maid()
	Story.after_settle(s, 0, false)
	_night_events()
	await _wait(0.6)
	await _shot(dir + "/23_heart_episode.png")
	close_modal()
	_hide_portrait()
	Settings.set_value("font_size", "xlarge")
	_build_theme()
	prep_tab = 2
	_build_prepare_side()
	await _wait(0.3)
	await _shot(dir + "/24_font_xlarge.png")
	Settings.set_value("font_size", "normal")
	get_tree().quit()

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


# ======================================================================== settings
func _open_settings() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.add_child(_label("🔠 字體大小", 18, MaidTheme.C.title))
	var fl := HBoxContainer.new()
	fl.add_theme_constant_override("separation", 8)
	var cur := String(Settings.get_value("font_size"))
	for f in Settings.FONT_SIZES:
		var b := _tbtn(f.name, _set_font_size.bind(f.key), cur == f.key)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", MaidTheme.fs(18, float(f.scale)))
		fl.add_child(b)
	box.add_child(fl)
	box.add_child(_label("預覽：歡迎回來，主人！今天也辛苦了～", 18, MaidTheme.C.soft))
	box.add_child(HSeparator.new())
	box.add_child(_label("💡 說明文字", 18, MaidTheme.C.title))
	var hl := HBoxContainer.new()
	hl.add_theme_constant_override("separation", 8)
	for o in [[false, "簡潔（推薦）"], [true, "詳細說明"]]:
		var b := _tbtn(o[1], _set_hints.bind(o[0]), Settings.hints() == o[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hl.add_child(b)
	box.add_child(hl)
	show_modal("⚙ 設定", "", [["完成", _close_settings]], box, 620)

func _set_font_size(key: String) -> void:
	Settings.set_value("font_size", key)
	_apply_settings()

func _set_hints(on: bool) -> void:
	Settings.set_value("hints", on)
	_apply_settings()

func _apply_settings() -> void:
	_build_theme()
	_rebuild_side()
	_open_settings()

func _close_settings() -> void:
	if on_title:
		_title()
	elif s.phase == "night" and night_step == "report":
		_show_report(0)
	else:
		close_modal()

## Rebuild the side panel of the current phase (after a settings change).
func _rebuild_side() -> void:
	if s.is_empty() or side.get_child_count() == 0:
		return
	match s.phase:
		"explore":
			_build_explore_side()
		"prepare":
			_build_prepare_side()
		"business":
			_build_business_side()
		"night":
			if night_step == "report":
				_clear(side)
				side.add_child(_section("🌙 打烊了"))
			else:
				_enter_night_scene()

# ======================================================================== story
func _open_story() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var stt := Story.st(s)
	var ch := Story.chapter(s)
	if ch.is_empty():
		box.add_child(_label("🎉 主線故事完結了！店的日子，和女僕們的故事，還會繼續。", 18, MaidTheme.C.title))
	else:
		var card := PanelContainer.new()
		card.theme_type_variation = "CardPanel"
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		cv.add_child(_label("📖 " + ch.title, 22, MaidTheme.C.title))
		if not stt.started:
			cv.add_child(_label("（明天早上開始）", 15, MaidTheme.C.soft))
		for g in Story.goals(s):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var l := _label(("✅ " if g.done else "🎀 ") + g.label, 17, MaidTheme.C.good if g.done else MaidTheme.C.text)
			l.custom_minimum_size.x = 300 * ui_k
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var bar := _bar(minf(g.value, g.target), maxf(1.0, g.target), "6cc5a5" if g.done else "")
			bar.custom_minimum_size.x = 160 * ui_k
			row.add_child(bar)
			var vl := _label("%s／%s" % [_short_num(g.value), _short_num(g.target)], 15, MaidTheme.C.soft)
			vl.autowrap_mode = TextServer.AUTOWRAP_OFF
			row.add_child(vl)
			cv.add_child(row)
		card.add_child(cv)
		box.add_child(card)
	box.add_child(_label("章節", 18, MaidTheme.C.title))
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 8)
	fl.add_theme_constant_override("v_separation", 8)
	for i in SD.CHAPTERS.size():
		var done: bool = i < int(stt.chapter)
		var now: bool = i == int(stt.chapter)
		var b := _tbtn(("✔ " if done else ("▶ " if now else "🔒 ")) + (SD.CHAPTERS[i].title if done or now else "？？？"), func(): pass, now)
		b.disabled = not (done or now)
		fl.add_child(b)
	box.add_child(fl)
	box.add_child(_label("💗 和女僕的羈絆越深，越能看見她們的故事。點上方的「🎀 女僕」看看每個人。", 15, MaidTheme.C.soft))
	show_modal("📖 Maiden Parade 的故事", "", [["🎀 女僕們", _open_maids], ["關閉", _close_notebook]], box, 820)

static func _short_num(v: float) -> String:
	if absf(v) >= 10000:
		return "%.1f萬" % (v / 10000.0)
	return str(int(v))

# ======================================================================== maids: profiles, hearts, training
func _hearts(r: int) -> String:
	return "[color=#e0518e]" + "♥".repeat(r) + "[/color][color=#f6b6cb]" + "♡".repeat(5 - r) + "[/color]"

func _open_maids() -> void:
	var grid := GridContainer.new()
	grid.columns = 3 if ui_k <= 1.05 else 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for m in St.active_maids(s):
		var def: Dictionary = Data.MAIDS[m.id]
		var r := Story.heart_rank(s, m.id)
		var card := PanelContainer.new()
		card.theme_type_variation = "CardPanel"
		card.custom_minimum_size = Vector2(270 * ui_k, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		var head := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.color = Color(def.hair)
		dot.custom_minimum_size = Vector2(22, 22) * ui_k
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(dot)
		var nm := _label(" " + def.name, 22, MaidTheme.C.title)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.add_child(nm)
		v.add_child(head)
		v.add_child(_rich("%s  Lv%d %s" % [_hearts(r), r, Story.rank_name(r)]))
		v.add_child(_bar(Story.heart_progress(s, m.id), 1.0, "ff8fb5", 10))
		var st_row := HBoxContainer.new()
		st_row.add_child(_label("😊", 15))
		st_row.add_child(_bar(m.mood, 100, "f7b84e", 10))
		st_row.add_child(_label(" 💤", 15))
		st_row.add_child(_bar(m.fatigue, 100, "9aa7d8", 10))
		v.add_child(st_row)
		var b := _btn("查看檔案", _open_maid.bind(m.id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(b)
		card.add_child(v)
		grid.add_child(card)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(880 * minf(ui_k, 1.1), minf(560 * ui_k, get_viewport().get_visible_rect().size.y - 260))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.add_child(grid)
	var box := VBoxContainer.new()
	var tl := Story.train_left(s)
	if s.phase in ["explore", "prepare"]:
		box.add_child(_label("✨ 今天還能陪 %d 位女僕特訓" % tl, 16, MaidTheme.C.accent if tl > 0 else MaidTheme.C.soft))
	box.add_child(sc)
	show_modal("🎀 女僕們", "", [["關閉", _close_notebook]], box, 920)

func _open_maid(mid: String) -> void:
	var m: Dictionary = s.maids[mid]
	var def: Dictionary = Data.MAIDS[mid]
	var r := Story.heart_rank(s, mid)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	# left: profile
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_rich("%s  [b]Lv%d %s[/b]" % [_hearts(r), r, Story.rank_name(r)]))
	left.add_child(_bar(Story.heart_progress(s, mid), 1.0, "ff8fb5", 12))
	left.add_child(_label(def.intro, 16, MaidTheme.C.soft))
	left.add_child(_label("特質：" + "、".join(def.traits.map(func(x): return Data.TRAITS[x].name)) + "　🎂 " + Data.date_label(int(def.birthday)).split("（")[0], 16))
	left.add_child(HSeparator.new())
	for row in Story.profile(s, mid):
		var h := HBoxContainer.new()
		var lab := _label(row[0], 15, MaidTheme.C.title)
		lab.custom_minimum_size.x = 96 * ui_k
		lab.autowrap_mode = TextServer.AUTOWRAP_OFF
		h.add_child(lab)
		var val := _label(row[1] if row[2] else "🔒 " + Story.unlock_hint({"夢想": 3, "街坊的稱呼": 4, "小秘密": 5}.get(row[0], 3)), 16, MaidTheme.C.text if row[2] else MaidTheme.C.faint)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(val)
		left.add_child(h)
	cols.add_child(left)
	# right: skills + training
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size.x = 330 * ui_k
	right.add_child(_label("能力", 18, MaidTheme.C.title))
	for sk in Data.SKILLS:
		var h := HBoxContainer.new()
		var lab := _label(SD.TRAINING[sk].icon + " " + Data.SKILL_NAMES[sk], 15)
		lab.custom_minimum_size.x = 90 * ui_k
		lab.autowrap_mode = TextServer.AUTOWRAP_OFF
		h.add_child(lab)
		var cap := float(def.caps[sk])
		h.add_child(_bar(float(m.skills[sk]), 100.0, "ff8fb5"))
		var vl := _label("%d／%d" % [int(m.skills[sk]), int(cap)], 14, MaidTheme.C.soft)
		vl.autowrap_mode = TextServer.AUTOWRAP_OFF
		h.add_child(vl)
		right.add_child(h)
	right.add_child(HSeparator.new())
	var why := Story.can_train(s, mid)
	right.add_child(_label("✨ 特訓" + ("" if why == "" else "：" + why), 18, MaidTheme.C.title if why == "" else MaidTheme.C.soft))
	if why == "":
		var focus: Array = SD.GROWTH_FOCUS.get(def.get("growth", ""), [])
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 6)
		fl.add_theme_constant_override("v_separation", 6)
		for sk in Data.SKILLS:
			var b := _btn(SD.TRAINING[sk].icon + SD.TRAINING[sk].name + (" ★" if sk in focus else ""), _do_train.bind(mid, sk))
			b.theme_type_variation = "Button" if sk in focus else "SoftButton"
			b.tooltip_text = "★ 她擅長成長的方向，效果更好" if sk in focus else ""
			fl.add_child(b)
		right.add_child(fl)
	cols.add_child(right)
	_show_portrait(mid)
	show_modal("🎀 " + def.name, "", [["← 所有女僕", _back_to_maids], ["關閉", _close_maid]], cols, 980)

func _do_train(mid: String, sk: String) -> void:
	var r := Story.train(s, mid, sk)
	toast(r.text.split("\n")[0] if r.ok else r.text)
	if r.ok:
		show_modal("✨ 特訓", r.text, [["回到檔案", _open_maid.bind(mid)], ["關閉", _close_maid]], null, 640)
		if s.phase == "prepare":
			_build_prepare_side()

func _back_to_maids() -> void:
	_hide_portrait()
	_open_maids()

func _close_maid() -> void:
	_hide_portrait()
	_close_notebook()
