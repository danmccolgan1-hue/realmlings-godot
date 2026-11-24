class_name CommandCard
extends Control
## The command card, bottom right: a 4×4 grid of icon buttons with their hotkeys, tabs above it naming what is
## selected, and an empty dashed grid when nothing of yours is. Each cell is a command from the HUD:
## {id, label, why, icon (Texture2D), bg (Color), prog (0..1), q (a queue slot), n (its number), glow}.
## web: game_shell.html .cmd / .cmd-grid / .cmd-btn / .cmd-tab; game.js renderCmd

const INK := Color("#1d1a22")
const CHIP := Color("#efdcb3")
const CHIP_HI := Color("#faf1dc")
const SUN := Color("#ffc93c")
const MUTED := Color("#5a6475")
const CELL := 60.0
const GAP := 5.0
const PAD := 6.0
const TAB_H := 34.0
const KEYS := ["Q", "W", "E", "R", "A", "S", "D", "F", "Z", "X", "C", "V", "U", "I", "O", "P"]

var cells := []          # 16 entries: a command Dictionary or null
var tabs := []           # [{text, icon, on, id}]
var hover := -1
var hover_tab := -1
var down := -1
var on_press: Callable   # func(i)
var on_tab: Callable     # func(tab_id)
var tip_of: Callable     # func(cmd) -> String
var empty_text := ""


func _init() -> void:
	cells.resize(16)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(grid_w(), grid_w() + TAB_H)


static func grid_w() -> float:
	return PAD * 2 + CELL * 4 + GAP * 3


func set_cells(c: Array, t: Array, empty := "") -> void:
	cells = c
	tabs = t
	empty_text = empty
	queue_redraw()


func _cell_rect(i: int) -> Rect2:
	var x := PAD + (i % 4) * (CELL + GAP)
	var y := TAB_H + PAD + (i / 4) * (CELL + GAP)
	return Rect2(x, y, CELL, CELL)


func _tab_rects() -> Array:
	var out := []
	var x := 12.0
	var font := get_theme_default_font()
	var room := (size.x - 12.0 - 4.0 * tabs.size()) / maxf(1, tabs.size())   # several kinds selected: the tabs share the width
	for t in tabs:
		var w: float = minf(room, font.get_string_size(str(t.text), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + (40.0 if t.get("icon") else 16.0))
		var h := TAB_H if t.get("on", true) else TAB_H - 4
		out.append(Rect2(x, TAB_H - h + 3, w, h))
		x += w + 4
	return out


func _cell_at(p: Vector2) -> int:
	for i in 16:
		if _cell_rect(i).has_point(p):
			return i
	return -1


func _tab_at(p: Vector2) -> int:
	var rs := _tab_rects()
	for i in rs.size():
		if rs[i].has_point(p):
			return i
	return -1


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := _cell_at(ev.position)
		var ht := _tab_at(ev.position)
		if h != hover or ht != hover_tab:
			hover = h
			hover_tab = ht
			queue_redraw()
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var i := _cell_at(ev.position)
		if ev.pressed:
			down = i
			var t := _tab_at(ev.position)
			if t >= 0 and on_tab.is_valid() and tabs[t].has("id"):
				on_tab.call(tabs[t].id)
		else:
			if i >= 0 and i == down and cells[i] != null and on_press.is_valid():
				on_press.call(i)
			down = -1
		queue_redraw()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover = -1
		hover_tab = -1
		down = -1
		queue_redraw()


## The action buttons' tips show after 1 s of the mouse resting on one (the rest of the interface waits 5 s), in a
## note of their own beside the card.
const TIP_DELAY := 1.0
var _tip: PanelContainer
var _tip_label: RichTextLabel   # (0.19: BBCode, so costs show the resources' icons)
var _tip_rest := 0.0
var _tip_at := Vector2(-1, -1)
var _tip_for := ""


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		_hide_tip()
		return
	var mp := get_local_mouse_position()
	var inside := Rect2(Vector2.ZERO, size).has_point(mp)
	if not inside:
		_hide_tip()
		return
	if mp.distance_to(_tip_at) > 2.0:
		_tip_at = mp
		_tip_rest = 0.0
		_hide_tip()
		return
	_tip_rest += dt
	if _tip_rest < TIP_DELAY:
		return
	var text := _tip_text(mp)
	if text == "":
		_hide_tip()
		return
	if _tip == null:
		_tip = PanelContainer.new()
		_tip.add_theme_stylebox_override("panel", _sb(Color("#faf1dc"), 2, 6))
		_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip.top_level = true
		_tip.z_index = 100
		_tip_label = RichTextLabel.new()
		_tip_label.bbcode_enabled = true
		_tip_label.fit_content = true
		_tip_label.scroll_active = false
		_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip_label.custom_minimum_size = Vector2(320, 0)
		_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_label.add_theme_color_override("default_color", INK)
		_tip_label.add_theme_font_size_override("normal_font_size", 15)
		_tip.add_child(_tip_label)
		add_child(_tip)
	if text != _tip_for:
		_tip_for = text
		_tip_label.text = UiKit.res_icons(text)
		_tip.reset_size()
	_tip.show()
	var g := get_global_mouse_position()
	var vp := get_viewport_rect().size
	_tip.global_position = Vector2(clampf(g.x - _tip.size.x - 12, 8, vp.x - _tip.size.x - 8), clampf(g.y - _tip.size.y - 12, 8, vp.y - _tip.size.y - 8))


func _hide_tip() -> void:
	if _tip != null and _tip.visible:
		_tip.hide()


# (the built-in tooltip would wait the interface's 5 s: the card shows its own)
func _get_tooltip(_at: Vector2) -> String:
	return ""


func _tip_text(at: Vector2) -> String:
	var i := _cell_at(at)
	if i < 0 or cells[i] == null:
		return "" if i >= 0 or _tab_at(at) >= 0 else "Select a unit, building or province to see its actions here"
	return Races.words(UiKit.wrap(tip_of.call(cells[i])) if tip_of.is_valid() else str(cells[i].get("label", "")), Art.player_race)


static func _sb(bg: Color, border: float, radius := 8, col := INK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = col
	s.set_border_width_all(int(border))
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


func _draw() -> void:
	var font := get_theme_default_font()
	# tabs, then the card
	var trs := _tab_rects()
	for i in tabs.size():
		var t: Dictionary = tabs[i]
		var r: Rect2 = trs[i]
		var sb := _sb(CHIP if t.get("on", true) else Color("#dcc493"), 3, 10)
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.border_width_bottom = 0
		draw_style_box(sb, r)
		var x := r.position.x + 6
		if t.get("icon"):
			draw_texture_rect(t.icon, Rect2(x - 2, r.position.y + 3, 26, 26), false)
			x += 26
		draw_string(font, Vector2(x + 2, r.position.y + r.size.y / 2 + 6), str(t.text), HORIZONTAL_ALIGNMENT_LEFT, r.end.x - x - 6, 14, INK, TextServer.JUSTIFICATION_NONE)
	draw_style_box(_sb(CHIP, 3, 12), Rect2(0, TAB_H, size.x, size.y - TAB_H))
	var any := false
	for i in 16:
		var r := _cell_rect(i)
		var c = cells[i]
		if c == null:
			draw_style_box(_sb(Color("#eef2f7"), 0, 8), r)
			_dashed_rect(r, Color(INK, 0.18))
			continue
		any = true
		var off: bool = c.get("why") != null and not c.get("q", false)
		var pressed := i == down and i == hover
		var rr := r if not pressed else Rect2(r.position + Vector2(0, 2.5), r.size)
		if not pressed:
			draw_style_box(_sb(INK, 0, 8), Rect2(r.position + Vector2(0, 2.5 if not off else 1.0), r.size))
		var bg: Color = c.get("bg", CHIP_HI) if c.get("bg") != null else CHIP_HI
		if c.get("q", false):
			bg = Color("#eef7fd")
		if i == hover and not off:
			bg = Color("#fff7d9") if c.get("bg") == null else bg.lightened(0.15)
		var sb := _sb(bg, 2.5, 8)
		if off:
			sb.bg_color = Color("#d9dee6") if c.get("bg") == null else bg.lerp(Color("#d6dbe3"), 0.72)
		draw_style_box(sb, rr)
		if off:
			_stripes(rr.grow(-3))
		if c.get("glow", false):
			var a := 0.55 + 0.35 * sin(Time.get_ticks_msec() / 1000.0 * TAU / 1.6)
			draw_rect(rr.grow(3), Color("#ffd34d", a), false, 3.0)
		var tex = c.get("icon")
		var isz := 40.0 if c.get("q", false) else 48.0
		if tex != null:
			var ir := Rect2(rr.position + Vector2((CELL - isz) / 2, (CELL - isz) / 2 - 4), Vector2(isz, isz))
			draw_texture_rect(tex, ir, false, Color(1, 1, 1, 0.4) if off else Color.WHITE)
		else:
			var lines: PackedStringArray = str(c.get("label", "")).split("\n")
			for li in mini(lines.size(), 2):
				draw_string(font, rr.position + Vector2(3, 24 + li * 15), lines[li], HORIZONTAL_ALIGNMENT_CENTER, CELL - 6, 12, Color(INK, 0.5 if off else 1.0))
		# the hotkey, the queue number, a progress bar
		if not c.get("q", false):
			var kr := Rect2(rr.position + Vector2(2, 2), Vector2(14, 14))
			draw_style_box(_sb(Color("#e3e6ec") if off else SUN, 1.5, 4), kr)
			draw_string(font, kr.position + Vector2(0, 11), KEYS[i], HORIZONTAL_ALIGNMENT_CENTER, 14, 10, INK)
		else:
			draw_string(font, rr.position + Vector2(CELL - 16, 13), str(c.get("n", "")), HORIZONTAL_ALIGNMENT_CENTER, 12, 11, MUTED)
		if c.get("prog") != null:
			var pr := Rect2(rr.position + Vector2(4, CELL - 11), Vector2(CELL - 8, 8))
			draw_style_box(_sb(CHIP_HI, 1.5, 4), pr)
			if float(c.prog) > 0:
				draw_style_box(_sb(Color("#7fb0ff"), 0, 3), Rect2(pr.position + Vector2(1.5, 1.5), Vector2((pr.size.x - 3) * clampf(c.prog, 0, 1), pr.size.y - 3)))
		if c.get("cd") != null:   # a spell's cooldown drains
			var cr := Rect2(rr.position + Vector2(4, CELL - 11), Vector2(CELL - 8, 8))
			draw_style_box(_sb(CHIP_HI, 1.5, 4), cr)
			draw_style_box(_sb(Color("#ff9a3c"), 0, 3), Rect2(cr.position + Vector2(1.5, 1.5), Vector2((cr.size.x - 3) * clampf(c.cd, 0, 1), cr.size.y - 3)))
	if not any and empty_text != "":
		draw_string(font, Vector2(PAD, TAB_H + size.y / 2 - 10), empty_text, HORIZONTAL_ALIGNMENT_CENTER, size.x - PAD * 2, 12, MUTED)


func _dashed_rect(r: Rect2, col: Color) -> void:
	var segs := [[r.position + Vector2(8, 1), r.position + Vector2(r.size.x - 8, 1)], [r.position + Vector2(r.size.x - 1, 8), r.end - Vector2(1, 8)],
		[r.end - Vector2(8, 1), r.position + Vector2(8, r.size.y - 1)], [r.position + Vector2(1, r.size.y - 8), r.position + Vector2(1, 8)]]
	for s in segs:
		draw_dashed_line(s[0], s[1], col, 2.0, 5.0)


func _stripes(r: Rect2) -> void:
	var x := -r.size.y
	while x < r.size.x:
		var p0 := Vector2(x, 0)
		var p1 := Vector2(x + r.size.y, r.size.y)
		# clip the 45° stripe to the box
		if p0.x < 0:
			p0 = Vector2(0, -x)
		if p1.x > r.size.x:
			p1 = Vector2(r.size.x, r.size.x - x)
		if p0.y < r.size.y and p1.y > 0:
			draw_line(r.position + p0, r.position + p1, Color("#cdd3dc"), 4.0)
		x += 12
