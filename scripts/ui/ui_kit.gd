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
	Fonts.title(t)
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


## Put a window in the middle of the screen (call when it opens: its size is known then). A window the player has
## dragged somewhere (0.19) goes back where they left it instead.
static func center(panel: Control) -> void:
	panel.reset_size()
	var vs := panel.get_viewport_rect().size
	var key := str(panel.get_meta("drag_key", ""))
	if key != "" and placed.has(key):
		panel.position = on_screen(panel, placed[key])
		return
	panel.position = ((vs - panel.size) / 2).floor()


# --- windows the player can drag about by their title (0.19) ---

## window key -> where the player last dragged it (kept while the game runs)
static var placed := {}


## Let the player drag `panel` about by `handle` (its title). key: remembers where it was left, so it opens there
## again. Call again with a new handle when the title is rebuilt.
static func draggable(panel: Control, handle: Control, key: String) -> void:
	panel.set_meta("drag_key", key)
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	if handle.tooltip_text == "":
		handle.tooltip_text = "Drag to move this window"
	handle.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			panel.set_meta("drag_on", ev.pressed)
			handle.accept_event()
		elif ev is InputEventMouseMotion and panel.get_meta("drag_on", false):
			if not (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
				panel.set_meta("drag_on", false)
				return
			panel.position = on_screen(panel, panel.position + ev.relative)
			placed[key] = panel.position
			handle.accept_event())


## p kept so that at least the window's top edge (its title) stays on the screen.
static func on_screen(panel: Control, p: Vector2) -> Vector2:
	var vs := panel.get_viewport_rect().size
	return Vector2(clampf(p.x, 80.0 - panel.size.x, vs.x - 80.0), clampf(p.y, 0.0, maxf(0.0, vs.y - 40.0))).floor()


## Has the player moved the window kept under key?
static func is_placed(key: String) -> bool:
	return placed.has(key)


## Break a long tooltip into lines of about `width` characters (Godot's plain tooltips don't wrap by themselves).
static func wrap(text: String, width := 64) -> String:
	var out := []
	for para in text.split("\n"):
		var line := ""
		for w in para.split(" "):
			if line != "" and line.length() + 1 + w.length() > width:
				out.append(line)
				line = w
			else:
				line = w if line == "" else line + " " + w
		out.append(line)
	return "\n".join(out)


## A tooltip's "50 gold, 20 wood" as numbers with the resources' icons, in BBCode for a RichTextLabel (0.19).
## Square brackets already in plain text are kept as they are; bbcode: the text is BBCode already (left alone).
static func res_icons(text: String, bbcode := false, px := 18) -> String:
	var out := text if bbcode else text.replace("[", "[lb]")
	for r in ["gold", "wood", "food"]:
		var rx := RegEx.create_from_string("([+−-]?\\d+)\\s+%s\\b" % r)
		out = rx.sub(out, "$1 [img=%dx%d]res://assets/art/icons/common/res_%s.png[/img]" % [px, px, r], true)
	return out


## A number as the web game prints it: 5, not 5.0; 0.5 stays 0.5.
static func num(v) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(snappedf(f, 0.01))


## The game's tooltip look: dark ink boxes with a gold rim and readable type (set on the root window, so every
## tooltip uses it).
static func tooltip_theme() -> Theme:
	var th := Theme.new()
	var b := box(Color(INK, 0.97), 8, 2, GOLD)
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 8
	b.content_margin_bottom = 8
	th.set_stylebox("panel", "TooltipPanel", b)
	th.set_font_size("font_size", "TooltipLabel", 17)
	th.set_color("font_color", "TooltipLabel", Color("#faf1dc"))
	return th


## The start screen's buttons: gold for the main action, dark ink for the rest.
static func style_button(b: Button, main := false) -> void:
	var base := GOLD if main else DARK
	for st in [["normal", base], ["hover", base.lightened(0.12)], ["pressed", base.darkened(0.15)], ["focus", base], ["disabled", base.lerp(Color.GRAY, 0.5)]]:
		var bx := box(st[1], 10, 3, INK)
		bx.content_margin_top = 8
		bx.content_margin_bottom = 8
		b.add_theme_stylebox_override(st[0], bx)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, INK if main else Color("#faf1dc"))
