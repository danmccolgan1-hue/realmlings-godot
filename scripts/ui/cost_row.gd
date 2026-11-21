class_name CostRow
extends RefCounted
## A cost or yield as resource icons with numbers (web: game.js costHTML, .cst).

const ORDER := ["gold", "wood", "food"]


static func icon(k: String) -> Texture2D:
	var sp = Art.get_sprite("icons", "common", "res_%s.png" % k)
	return sp.tex if sp else null


## icons above numbers (vertical = true, the web's develop card) or side by side
static func make(cost: Dictionary, size := 14, vertical := false, prefix := "", col := Color("#1d1a22")) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10 if vertical else 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in ORDER:
		if not cost.has(k) or cost[k] == 0:
			continue
		var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
		box.add_theme_constant_override("separation", 0 if vertical else 2)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := TextureRect.new()
		ic.texture = icon(k)
		ic.custom_minimum_size = Vector2(size + 4, size + 4)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ic)
		var l := Label.new()
		l.text = prefix + UiKit.num(cost[k])
		l.add_theme_font_size_override("font_size", size)
		l.add_theme_color_override("font_color", col)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
		h.add_child(box)
	return h
