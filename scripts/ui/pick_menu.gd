class_name PickMenu
extends PanelContainer
## A small menu that opens beside the panel or card that asked for it: a heading and a list of choices, each with
## an icon, a name, a line under it and a cost. Greyed choices say why when clicked. Esc or a click elsewhere closes it.
## web: game.js #buildMenu (.bm-head, .bm-item), openPlotMenu, v104.js popNearCard

const INK := Color("#1d1a22")
const MUTED := Color("#5a6475")

var hud
var col: VBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", Roster._sb(Color("#efdcb3"), 2, 6, 8))
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP


## items: [{icon: Texture2D, name, small, cost: Dictionary, why, do: Callable, bg: Color}]
func open(title: String, sub: String, items: Array, at: Vector2, note := "") -> void:
	UiKit.clear(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 19)
	t.add_theme_color_override("font_color", INK)
	head.add_child(t)
	var s := Label.new()
	s.text = sub
	s.add_theme_font_size_override("font_size", 13)
	s.add_theme_color_override("font_color", MUTED)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(s)
	col.add_child(head)
	for it in items:
		col.add_child(_item(it))
	if note != "":
		var n := Label.new()
		n.text = note
		n.add_theme_font_size_override("font_size", 13)
		n.add_theme_color_override("font_color", MUTED)
		col.add_child(n)
	show()
	reset_size()
	var vs := get_viewport_rect().size
	position = Vector2(clampf(at.x, 8, vs.x - size.x - 8), clampf(at.y, 8, vs.y - size.y - 8))


func _item(it: Dictionary) -> Control:
	if it.has("sec"):   # a section heading (web: .bm-sec)
		var s := Label.new()
		s.text = str(it.sec).to_upper()
		s.add_theme_font_size_override("font_size", 12)
		s.add_theme_color_override("font_color", MUTED)
		return s
	if it.has("note"):   # a line of advice (web: .bm-note)
		var nl := Label.new()
		nl.text = str(it.note)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size = Vector2(380, 0)
		nl.add_theme_font_size_override("font_size", 13)
		nl.add_theme_color_override("font_color", MUTED)
		return nl
	var off: bool = it.get("why") != null and str(it.why) != ""
	var p := PanelContainer.new()
	var normal := Roster._sb(Color("#f6f1e4") if not off else Color("#e3e1dc"), 1, 0, 4)
	var hov := Roster._sb(Color("#fff7dd") if not off else Color("#e3e1dc"), 1, 0, 4)
	p.add_theme_stylebox_override("panel", normal)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.custom_minimum_size = Vector2(380, 0)
	p.mouse_entered.connect(func(): p.add_theme_stylebox_override("panel", hov))
	p.mouse_exited.connect(func(): p.add_theme_stylebox_override("panel", normal))
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			p.accept_event()
			if off:
				if hud:
					hud.add_toast(str(it.why), true)
				return
			hide()
			it.do.call())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	if it.get("glyph") != null:
		var gl := Label.new()
		gl.text = str(it.glyph)
		gl.custom_minimum_size = Vector2(44, 44)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		gl.add_theme_font_size_override("font_size", 26)
		gl.add_theme_color_override("font_color", INK)
		gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(gl)
	elif it.get("icon") != null:
		var ib := PanelContainer.new()
		var bgc: Color = it.get("bg", Color(0, 0, 0, 0))
		ib.add_theme_stylebox_override("panel", Roster._sb(bgc.lerp(Color("#d6dbe3"), 0.72) if off and bgc.a > 0 else bgc, 0, 6, 0))
		ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := TextureRect.new()
		ic.texture = it.icon
		ic.custom_minimum_size = Vector2(44, 44)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = Color(1, 1, 1, 0.45) if off else Color.WHITE
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ib.add_child(ic)
		h.add_child(ib)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var n := Label.new()
	n.text = str(it.name)
	n.add_theme_font_size_override("font_size", 17)
	n.add_theme_color_override("font_color", Color(INK, 0.55) if off else INK)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var sm := Label.new()
	sm.text = str(it.why) if off else str(it.get("small", ""))
	sm.add_theme_font_size_override("font_size", 13)
	sm.add_theme_color_override("font_color", Color("#b3261e") if off else MUTED)
	sm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sm.custom_minimum_size = Vector2(250, 0)
	sm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sm)
	var cost: Dictionary = it.get("cost", {})
	if not cost.is_empty():
		h.add_child(CostRow.make(cost, 14))
	return p


func _input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseButton and ev.pressed and not get_global_rect().has_point(ev.position):
		hide()
