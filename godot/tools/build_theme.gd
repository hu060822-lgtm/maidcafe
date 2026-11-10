## Regenerates res://ui/maid_theme.tres (standard font size) from scripts/view/maid_theme.gd.
##   godot --headless --path godot -s tools/build_theme.gd
extends SceneTree

const MaidTheme = preload("res://scripts/view/maid_theme.gd")

func _init() -> void:
	var t := MaidTheme.build(1.0)
	var err := ResourceSaver.save(t, "res://ui/maid_theme.tres")
	print("maid_theme.tres -> ", error_string(err))
	quit(0 if err == OK else 1)
