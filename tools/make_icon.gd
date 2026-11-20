extends SceneTree
## Renders icon.svg to the Windows icon's sizes (assets/icon/icon_<n>.png); tools/make_icon.py packs them into
## assets/icon/realmlings.ico. godot --headless --path . --script res://tools/make_icon.gd
func _initialize():
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	for n in [16, 24, 32, 48, 64, 128, 256]:
		var img := Image.new()
		img.load_svg_from_string(svg, n / 128.0)
		img.save_png("res://assets/icon/icon_%d.png" % n)
	print("icons rendered")
	quit()
