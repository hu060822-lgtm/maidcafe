## Sweet maid-style UI theme shared by the whole game (and by tools such as the creator workshop).
##
##   var theme := MaidTheme.build(1.0)        # scale = player font-size setting (see settings.gd)
##   control.theme = theme
##
## A pre-built copy at the standard size lives at res://ui/maid_theme.tres (regenerate with
## `godot --headless --path godot -s tools/build_theme.gd`). Code that respects the player's
## font-size choice should call build() with Settings.font_scale() instead of loading the .tres.
extends RefCounted

const FONT_PATH := "res://ui/fonts/jf-openhuninn-2.1.ttf"
const BASE_FONT_SIZE := 18

# ---- palette: strawberry milk, cream, cocoa
const CREAM := Color("fff8f3")
const CREAM_DEEP := Color("fdeef2")
const PINK := Color("ff8fb5")
const PINK_HOVER := Color("ffa6c4")
const PINK_PRESS := Color("ee6f9c")
const PINK_EDGE := Color("d9628c")
const PINK_LINE := Color("f6b6cb")
const RASPBERRY := Color("d94f82")
const COCOA := Color("5b3a46")
const COCOA_SOFT := Color("8f6a77")
const MINT := Color("6cc5a5")
const HONEY := Color("f7b84e")
const WHITE := Color("ffffff")

## Colours for BBCode / overrides, readable on cream panels.
const C := {
	"text": "#5b3a46", "soft": "#8f6a77", "faint": "#b597a2", "title": "#d94f82", "accent": "#e8790f",
	"good": "#2f9b72", "warn": "#d9622b", "bad": "#d23c4f", "love": "#e0518e", "gold": "#c9861a",
}

static var _font: Font = null

static func font() -> Font:
	if _font != null:
		return _font
	var main: Font = null
	if ResourceLoader.exists(FONT_PATH):
		main = load(FONT_PATH)
	if main == null and FileAccess.file_exists(FONT_PATH):
		var ff := FontFile.new()
		if ff.load_dynamic_font(FONT_PATH) == OK:
			main = ff
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Noto Sans CJK TC", "Noto Sans TC", "Microsoft JhengHei", "PingFang TC", "Heiti TC", "WenQuanYi Zen Hei", "Noto Sans CJK JP", "sans-serif"])
	var emoji := SystemFont.new()
	emoji.font_names = PackedStringArray(["Noto Color Emoji", "Segoe UI Emoji", "Apple Color Emoji", "Noto Emoji"])
	if main == null:
		sys.fallbacks = [emoji]
		_font = sys
	else:
		if main is FontFile:
			(main as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		main.fallbacks = [sys, emoji]
		_font = main
	return _font

static func fs(size: float, scale: float) -> int:
	return maxi(8, int(round(size * scale)))

static func panel_box(bg := CREAM, border := PINK_LINE, radius := 18, bw := 3, shadow := true) -> StyleBoxFlat:
	var p := StyleBoxFlat.new()
	p.bg_color = bg
	p.border_color = border
	p.set_border_width_all(bw)
	p.set_corner_radius_all(radius)
	p.set_content_margin_all(14)
	p.anti_aliasing = true
	if shadow:
		p.shadow_color = Color(0.85, 0.38, 0.55, 0.22)
		p.shadow_size = 10
		p.shadow_offset = Vector2(0, 4)
	return p

static func button_box(bg: Color, edge: Color, radius := 16, press := false) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = edge
	b.set_border_width_all(0)
	b.border_width_bottom = 1 if press else 4
	b.set_corner_radius_all(radius)
	b.content_margin_left = 16
	b.content_margin_right = 16
	b.content_margin_top = 9 + (3 if press else 0)
	b.content_margin_bottom = 9 - (3 if press else 0)
	b.anti_aliasing = true
	return b

## Build the theme. scale multiplies every font size (player setting: 0.9 – 1.5).
static func build(scale := 1.0) -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = fs(BASE_FONT_SIZE, scale)
	# panels
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_stylebox("panel", "TooltipPanel", panel_box(CREAM, PINK, 12, 2, false))
	t.set_color("font_color", "TooltipLabel", COCOA)
	t.set_font_size("font_size", "TooltipLabel", fs(16, scale))
	# type variations: a raspberry "card" for highlighted boxes and a header ribbon
	t.set_type_variation("CardPanel", "PanelContainer")
	var card := panel_box(CREAM_DEEP, PINK_LINE, 14, 2, false)
	card.set_content_margin_all(10)
	t.set_stylebox("panel", "CardPanel", card)
	t.set_type_variation("RibbonPanel", "PanelContainer")
	var rib := panel_box(PINK, PINK_EDGE, 22, 0, true)
	rib.border_width_bottom = 4
	rib.content_margin_top = 6
	rib.content_margin_bottom = 6
	t.set_stylebox("panel", "RibbonPanel", rib)
	# buttons: candy pink with a darker lip
	t.set_stylebox("normal", "Button", button_box(PINK, PINK_EDGE))
	t.set_stylebox("hover", "Button", button_box(PINK_HOVER, PINK_EDGE))
	t.set_stylebox("pressed", "Button", button_box(PINK_PRESS, PINK_EDGE, 16, true))
	t.set_stylebox("hover_pressed", "Button", button_box(PINK_PRESS, PINK_EDGE, 16, true))
	t.set_stylebox("disabled", "Button", button_box(Color("f1e4e8"), Color("e2d0d6")))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = HONEY
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(18)
	focus.set_expand_margin_all(2)
	t.set_stylebox("focus", "Button", focus)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "Button", WHITE)
	t.set_color("font_disabled_color", "Button", Color("b9a3ab"))
	t.set_color("font_outline_color", "Button", PINK_EDGE)
	t.set_constant("outline_size", "Button", 0)
	t.set_constant("h_separation", "Button", 8)
	# secondary (cream) buttons for list rows / options
	t.set_type_variation("SoftButton", "Button")
	t.set_stylebox("normal", "SoftButton", button_box(WHITE, PINK_LINE, 14))
	t.set_stylebox("hover", "SoftButton", button_box(Color("fff0f5"), PINK, 14))
	t.set_stylebox("pressed", "SoftButton", button_box(Color("ffe1ec"), PINK, 14, true))
	t.set_stylebox("hover_pressed", "SoftButton", button_box(Color("ffe1ec"), PINK, 14, true))
	t.set_stylebox("disabled", "SoftButton", button_box(Color("f7f0f2"), Color("eadde2"), 14))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "SoftButton", COCOA)
	t.set_color("font_disabled_color", "SoftButton", Color("c2adb5"))
	# selected tab / option
	t.set_type_variation("ActiveButton", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(st, "ActiveButton", button_box(RASPBERRY, Color("a8345f"), 16, st.begins_with("press")))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, "ActiveButton", WHITE)
	# labels
	t.set_color("font_color", "Label", COCOA)
	t.set_color("default_color", "RichTextLabel", COCOA)
	t.set_font_size("normal_font_size", "RichTextLabel", fs(BASE_FONT_SIZE, scale))
	t.set_font_size("bold_font_size", "RichTextLabel", fs(BASE_FONT_SIZE, scale))
	t.set_constant("line_separation", "RichTextLabel", 4)
	t.set_type_variation("TitleLabel", "Label")
	t.set_color("font_color", "TitleLabel", RASPBERRY)
	t.set_font_size("font_size", "TitleLabel", fs(26, scale))
	t.set_color("font_outline_color", "TitleLabel", WHITE)
	t.set_constant("outline_size", "TitleLabel", 6)
	t.set_type_variation("HintLabel", "Label")
	t.set_color("font_color", "HintLabel", COCOA_SOFT)
	t.set_font_size("font_size", "HintLabel", fs(15, scale))
	# separators: dotted lace line
	var sep := StyleBoxLine.new()
	sep.color = PINK_LINE
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)
	# progress bars (hearts / skills / goals)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color("fbe1ea")
	pb_bg.set_corner_radius_all(10)
	var pb_fg := StyleBoxFlat.new()
	pb_fg.bg_color = PINK
	pb_fg.set_corner_radius_all(10)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fg)
	t.set_color("font_color", "ProgressBar", COCOA)
	t.set_font_size("font_size", "ProgressBar", fs(13, scale))
	# scrollbars
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color("fbe8ee")
	sb_bg.set_corner_radius_all(6)
	sb_bg.content_margin_left = 4
	sb_bg.content_margin_right = 4
	var grab := StyleBoxFlat.new()
	grab.bg_color = PINK_LINE
	grab.set_corner_radius_all(6)
	var grab_h := grab.duplicate()
	grab_h.bg_color = PINK
	for sbt in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sbt, sb_bg)
		t.set_stylebox("grabber", sbt, grab)
		t.set_stylebox("grabber_highlight", sbt, grab_h)
		t.set_stylebox("grabber_pressed", sbt, grab_h)
	# line edits / option buttons / checkboxes (used by tools)
	var le := button_box(WHITE, PINK_LINE, 12)
	le.set_border_width_all(2)
	t.set_stylebox("normal", "LineEdit", le)
	var le_f := le.duplicate()
	le_f.border_color = PINK
	t.set_stylebox("focus", "LineEdit", le_f)
	t.set_color("font_color", "LineEdit", COCOA)
	t.set_color("font_placeholder_color", "LineEdit", Color("c2a8b2"))
	t.set_stylebox("normal", "TextEdit", le)
	t.set_stylebox("focus", "TextEdit", le_f)
	t.set_color("font_color", "TextEdit", COCOA)
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "OptionButton", t.get_stylebox(st, "SoftButton"))
	t.set_color("font_color", "OptionButton", COCOA)
	t.set_color("font_hover_color", "OptionButton", COCOA)
	t.set_stylebox("panel", "PopupMenu", panel_box(CREAM, PINK_LINE, 12, 2, false))
	t.set_color("font_color", "PopupMenu", COCOA)
	t.set_color("font_hover_color", "PopupMenu", RASPBERRY)
	t.set_color("font_color", "CheckBox", COCOA)
	t.set_color("font_color", "CheckButton", COCOA)
	t.set_stylebox("panel", "TabContainer", panel_box(CREAM, PINK_LINE, 14, 2, false))
	t.set_stylebox("tab_selected", "TabContainer", button_box(RASPBERRY, Color("a8345f"), 12))
	t.set_stylebox("tab_unselected", "TabContainer", button_box(PINK_LINE, PINK, 12))
	t.set_stylebox("tab_hovered", "TabContainer", button_box(PINK_HOVER, PINK_EDGE, 12))
	t.set_color("font_selected_color", "TabContainer", WHITE)
	t.set_color("font_unselected_color", "TabContainer", COCOA)
	return t
