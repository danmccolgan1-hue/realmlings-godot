class_name UiKit
extends RefCounted
## Shared look for the interface: the web game's parchment panels with ink outlines, dark bars, and big readable
## type. Views only; nothing here changes the game.

const INK := Color("#1d1a22")
const PAPER := Color("#faf1dc")
const DARK := Color("#2a2433")
const GOLD := Color("#e8c547")
const BAD := Color("#b3261e")


static func box(c: Color, radius := 10, border := 0, border_col := INK) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = c
	b.set_corner_radius_all(radius)
	b.content_margin_left = 16
	b.content_margin_right = 16
	b.content_margin_top = 10
	b.content_margin_bottom = 10
	if border:
		b.set_border_width_all(border)
		b.border_color = border_col
	return b


static func label(size: int, col := Color.WHITE, outline := true) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
	return l


static func ink(size: int) -> Label:
	return label(size, INK, false)


static func rich(size: int, width := 0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	if width:
		r.custom_minimum_size = Vector2(width, 0)
	r.add_theme_color_override("default_color", INK)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size + 2)
	return r


static func button(text: String, size := 18, f = null) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if f is Callable:
		b.pressed.connect(f)
	return b


## A parchment window with a title and a close button; returns {panel, body: VBoxContainer, title: Label}.
static func window(title: String, width: int, on_close: Callable) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(PAPER.lerp(Color.WHITE, 0.0), 14, 4))
	panel.custom_minimum_size = Vector2(width, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var head := HBoxContainer.new()
	var t := ink(26)
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(button("✕", 18, on_close))
	col.add_child(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	col.add_child(body)
	return {"panel": panel, "body": body, "title": t}


static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


static func cost_line(c: Dictionary) -> String:
	var parts := []
	for k in ["gold", "wood", "food", "mana"]:
		if c.get(k, 0):
			parts.append("%d %s" % [c[k], k])
	return ", ".join(parts) if not parts.is_empty() else "free"


## Put a window in the middle of the screen (call when it opens: its size is known then).
static func center(panel: Control) -> void:
	panel.reset_size()
	var vs := panel.get_viewport_rect().size
	panel.position = ((vs - panel.size) / 2).floor()
