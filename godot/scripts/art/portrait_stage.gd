class_name PortraitStage
extends Control
## Reusable character-portrait layer for dialogue, events and menus.
##
## Add it as a full-rect child of any UI (CanvasLayer / Control) and drive it
## by character ID:
##
##   var stage := PortraitStage.new()
##   add_child(stage)
##   stage.show_character("koharu", {"expression": "smile", "position": "left"})
##   stage.set_expression("koharu", "surprised")
##   stage.set_speaker("koharu")
##   stage.hide_character("koharu")
##
## Every call is safe with unknown IDs or missing images: the character is
## drawn as a marked silhouette and a warning is logged, the game continues.

signal character_shown(id: String)
signal character_hidden(id: String)

## Named horizontal positions (fraction of stage width).
const POSITIONS := {
	"far_left": 0.12, "left": 0.25, "center_left": 0.375, "center": 0.5,
	"center_right": 0.625, "right": 0.75, "far_right": 0.88,
}

@export_range(0.3, 1.2) var height_ratio := 0.92
@export var default_duration := 0.25
@export var expression_crossfade := 0.12
@export var move_duration := 0.3
@export var show_missing_labels := true
@export var max_characters := 5

var catalog: ArtCatalog
var _slots: Dictionary = {}          ## id -> PortraitSlot
var _order: Array[String] = []       ## display order (left -> right for auto layout)
var _speaker := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	if catalog == null:
		catalog = ArtCatalog.shared()
	resized.connect(_relayout.bind(0.0))


func _cat() -> ArtCatalog:
	if catalog == null:
		catalog = ArtCatalog.shared()
	return catalog


# ---------------------------------------------------------------- public API

## opts: pose, outfit, expression, position ("left"/"center"/0.3/"auto"),
##       enter ("fade"/"slide_left"/"slide_right"/"rise"/"none"), duration,
##       key (stage key; defaults to the character id). Other calls take the key.
func show_character(character_id: String, opts: Dictionary = {}) -> PortraitSlot:
	var dur := float(opts.get("duration", default_duration))
	# "key" lets the same art (e.g. one NPC archetype) appear more than once.
	var id := str(opts.get("key", character_id))
	var slot: PortraitSlot = _slots.get(id)
	if slot != null and not slot.leaving:
		slot.apply_variant(str(opts.get("pose", "")), str(opts.get("outfit", "")), str(opts.get("expression", "")), expression_crossfade)
		if opts.has("position"):
			_place_slot(slot, opts["position"])
		_relayout(move_duration)
		return slot
	if slot != null:
		# It was leaving: drop it right away and enter fresh.
		_remove_slot(id)
	if _slots.size() >= max_characters:
		push_warning("PortraitStage: more than %d characters on screen" % max_characters)
	if not _cat().has_character(character_id) and not _cat().archetypes.has(character_id):
		push_warning("PortraitStage: unknown character id '%s' (showing silhouette)" % character_id)

	slot = PortraitSlot.new()
	slot.setup(character_id, _cat())
	slot.name = "Portrait_" + id.validate_node_name()
	slot.show_missing_label = show_missing_labels
	_place_slot(slot, opts.get("position", "auto"))
	_slots[id] = slot
	_order.append(id)
	add_child(slot)
	slot.apply_variant(str(opts.get("pose", "")), str(opts.get("outfit", "")), str(opts.get("expression", "")))
	_relayout(move_duration)
	slot.layout(size, height_ratio)  # new slot appears in place, others glide
	if _speaker != "":
		slot.set_focused(_speaker == id, 0.0)
	slot.play_enter(str(opts.get("enter", "fade")), dur)
	character_shown.emit(id)
	return slot


## opts: exit ("fade"/"slide_left"/"slide_right"/"rise"/"none"), duration
func hide_character(id: String, opts: Dictionary = {}) -> void:
	var slot: PortraitSlot = _slots.get(id)
	if slot == null or slot.leaving:
		return
	var dur := float(opts.get("duration", default_duration))
	slot.exited.connect(_on_slot_exited.bind(id, slot), CONNECT_ONE_SHOT)
	slot.play_exit(str(opts.get("exit", "fade")), dur)


func clear(duration := -1.0) -> void:
	for id in _slots.keys():
		hide_character(id, {"duration": default_duration if duration < 0.0 else duration})


func set_expression(id: String, expression: String) -> void:
	set_variant(id, {"expression": expression})


func set_pose(id: String, pose: String) -> void:
	set_variant(id, {"pose": pose})


func set_outfit(id: String, outfit: String) -> void:
	set_variant(id, {"outfit": outfit})


## variant: any of pose / outfit / expression.
func set_variant(id: String, variant: Dictionary) -> void:
	var slot: PortraitSlot = _slots.get(id)
	if slot == null:
		push_warning("PortraitStage: '%s' is not on stage" % id)
		return
	slot.apply_variant(str(variant.get("pose", "")), str(variant.get("outfit", "")), str(variant.get("expression", "")), expression_crossfade)
	slot.layout(size, height_ratio)


func move_character(id: String, position_value) -> void:
	var slot: PortraitSlot = _slots.get(id)
	if slot == null:
		return
	_place_slot(slot, position_value)
	_relayout(move_duration)


## Highlight the speaking character and dim the others. "" = nobody dimmed.
func set_speaker(id: String) -> void:
	_speaker = id
	for k in _slots:
		_slots[k].set_focused(id == "" or k == id)


func is_showing(id: String) -> bool:
	return _slots.has(id) and not _slots[id].leaving


func get_slot(id: String) -> PortraitSlot:
	return _slots.get(id)


func shown_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _order:
		if is_showing(id):
			out.append(id)
	return out


# ---------------------------------------------------------------- internals

func _place_slot(slot: PortraitSlot, value) -> void:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		slot.auto_position = false
		slot.x_anchor = clampf(float(value), 0.0, 1.0)
	elif POSITIONS.has(str(value)):
		slot.auto_position = false
		slot.x_anchor = POSITIONS[str(value)]
	else:
		slot.auto_position = true


func _relayout(duration := 0.0) -> void:
	var autos: Array = []
	for id in _order:
		var s: PortraitSlot = _slots[id]
		if s.auto_position and not s.leaving:
			autos.append(s)
	for i in autos.size():
		autos[i].x_anchor = float(i + 1) / float(autos.size() + 1)
	for id in _order:
		var s: PortraitSlot = _slots[id]
		if not s.leaving:
			s.layout(size, height_ratio, duration)


func _on_slot_exited(id: String, slot: PortraitSlot) -> void:
	if _slots.get(id) == slot:
		_remove_slot(id)


func _remove_slot(id: String) -> void:
	var slot: PortraitSlot = _slots.get(id)
	if slot == null:
		return
	_slots.erase(id)
	_order.erase(id)
	slot.queue_free()
	if _speaker == id:
		_speaker = ""
	_relayout(move_duration)
	character_hidden.emit(id)
