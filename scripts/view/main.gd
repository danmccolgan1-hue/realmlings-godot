extends Node2D
## Entry point. For now: shows the title. The Practice island view is added in Phase 3a.

func _ready() -> void:
	var label := Label.new()
	label.text = "Realmlings"
	label.add_theme_font_size_override("font_size", 64)
	label.position = Vector2(80, 80)
	add_child(label)
