extends SceneTree
## Writes assets/ui/theme.tres (the project's default theme: tooltip look) from UiKit.tooltip_theme().
## godot --headless --path . --script res://tools/make_theme.gd
func _initialize():
	var err := ResourceSaver.save(UiKit.tooltip_theme(), "res://assets/ui/theme.tres")
	print("theme saved: ", error_string(err))
	quit()
