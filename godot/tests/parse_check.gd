extends SceneTree
func _init():
	for p in ["res://scripts/view/cafe_view.gd","res://scripts/view/main.gd","res://scripts/core/social.gd","res://scripts/core/moments.gd","res://scripts/core/events.gd","res://scripts/core/settlement.gd","res://scripts/core/data.gd","res://scripts/core/state.gd","res://scripts/core/layout.gd","res://scripts/core/world.gd","res://scripts/core/business.gd","res://scripts/core/life.gd","res://scripts/core/life_data.gd","res://scripts/core/story.gd","res://scripts/core/story_data.gd","res://scripts/core/settings.gd","res://scripts/view/maid_theme.gd"]:
		var sc = load(p)
		print(p, " -> ", sc != null and sc.can_instantiate())
	quit()
