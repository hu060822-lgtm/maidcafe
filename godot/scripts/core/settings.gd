## Player preferences (font size, how much explanatory text to show). Stored apart from the save game
## so they apply to every save. Pure static helpers; the file is a ConfigFile at user://settings.cfg.
extends RefCounted

const PATH := "user://settings.cfg"
const FONT_SIZES := [
	{"key": "small", "name": "小", "scale": 0.9},
	{"key": "normal", "name": "標準", "scale": 1.0},
	{"key": "large", "name": "大", "scale": 1.2},
	{"key": "xlarge", "name": "特大", "scale": 1.4},
]
const DEFAULTS := {"font_size": "normal", "hints": false, "text_speed": 1.0}

static var _data: Dictionary = {}
static var _loaded := false

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_data = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in DEFAULTS:
			_data[k] = cf.get_value("ui", k, DEFAULTS[k])
	if font_index(String(_data.font_size)) < 0:
		_data.font_size = DEFAULTS.font_size

static func get_value(k: String):
	_ensure()
	return _data.get(k, DEFAULTS.get(k))

static func set_value(k: String, v) -> void:
	_ensure()
	_data[k] = v
	save()

static func save() -> void:
	var cf := ConfigFile.new()
	for k in _data:
		cf.set_value("ui", k, _data[k])
	cf.save(PATH)

## For tests: forget the cached values (and optionally use defaults without touching disk).
static func reset(defaults_only := false) -> void:
	_loaded = defaults_only
	_data = DEFAULTS.duplicate()

static func font_index(key: String) -> int:
	for i in FONT_SIZES.size():
		if FONT_SIZES[i].key == key:
			return i
	return -1

static func font_scale() -> float:
	var i := font_index(String(get_value("font_size")))
	return float(FONT_SIZES[i].scale) if i >= 0 else 1.0

## Show the longer explanations (tutorial-style hints) in side panels?
static func hints() -> bool:
	return bool(get_value("hints"))
