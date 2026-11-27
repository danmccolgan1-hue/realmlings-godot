class_name ObserverPanel
extends PanelContainer
## An observer's window over the game (0.19.3): every player, written in their nation's color, with their ping,
## resources, total army power and provinces. Drag it by its title; the − button folds it to its title bar (+ opens
## it again). It also says when the game waits for someone. Views only.

const INK := Color("#1d1a22")
const MUTED := Color("#5a6475")
const COLS := ["Player", "Ping", "Gold", "Wood", "Food", "Army", "Provinces"]

var lock: Lockstep
var grid: GridContainer
var body: VBoxContainer
var fold_btn: Button
var wait_label: Label
var folded := false
var _t := 0.0
var _sig := ""


func _init() -> void:
	add_theme_stylebox_override("panel", TopBar.paper(3, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	var title := Label.new()
	title.text = "Watching · Players"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	fold_btn = Button.new()
	fold_btn.text = "−"
	fold_btn.focus_mode = Control.FOCUS_NONE
	fold_btn.tooltip_text = "Minimize"
	fold_btn.custom_minimum_size = Vector2(30, 28)
	fold_btn.add_theme_font_size_override("font_size", 18)
	for st in ["normal", "hover", "pressed"]:
		var sb := TopBar.paper(3, 1)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		if st == "hover":
			sb.bg_color = Color("#fff6df")
		fold_btn.add_theme_stylebox_override(st, sb)
	fold_btn.add_theme_color_override("font_color", INK)
	fold_btn.add_theme_color_override("font_hover_color", INK)
	fold_btn.pressed.connect(toggle_fold)
	head.add_child(fold_btn)
	UiKit.draggable(self, title, "observer")
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	v.add_child(body)
	grid = GridContainer.new()
	grid.columns = COLS.size()
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	body.add_child(grid)
	wait_label = Label.new()
	wait_label.add_theme_font_size_override("font_size", 14)
	wait_label.add_theme_color_override("font_color", Color("#a0461e"))
	wait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wait_label.custom_minimum_size = Vector2(300, 0)
	wait_label.visible = false
	body.add_child(wait_label)
	hide()


func setup(lk: Lockstep) -> void:
	lock = lk
	lk.waiting.connect(func(t2):
		if is_instance_valid(wait_label):
			wait_label.text = t2
			wait_label.visible = t2 != "")
	_sig = ""
	_t = 0.0
	show()


func toggle_fold() -> void:
	folded = not folded
	body.visible = not folded
	fold_btn.text = "+" if folded else "−"
	fold_btn.tooltip_text = "Open" if folded else "Minimize"
	reset_size()


## One row per player nation: [nation id, player name, color, ping text, gold, wood, food, army power, provinces,
## state ("" or away / computer / fallen)].
static func rows_of(g: Game, net: NetSession, gone := {}) -> Array:
	var out := []
	var ids: Array = g.seat_names.keys()
	ids.sort()
	for o in ids:
		var nm := str(g.seat_names[o])
		var ping := "–"
		if net != null:
			for pid in net.players:
				if str(net.players[pid].name) == nm and not net.players[pid].get("watch", false):
					ping = "%d ms" % int(net.players[pid].get("ping", 0)) if pid != 1 or net.dedicated else "host"
		var st: Dictionary = {}
		var state := ""
		if g.seats.has(o):
			st = g.seats[o].stock
			state = "fallen" if g.seats[o].fallen else "away" if gone.has(o) else ""
		elif g.nations.has(o):
			st = g.nations[o].get("stock", {})
			state = "computer"
		else:
			state = "fallen"
		out.append([o, nm, Color(str(g.player_info(o).color)), ping, int(st.get("gold", 0)), int(st.get("wood", 0)), int(st.get("food", 0)),
			int(Ai.nation_power(g, o)), g.provs_of(o).size(), state])
	return out


func _process(dt: float) -> void:
	if lock == null or lock.game == null or not visible:
		return
	if not UiKit.is_placed("observer"):   # (top right, under the clock, until it is dragged elsewhere)
		position = Vector2(get_viewport_rect().size.x - size.x - 12, 76)
	if folded:
		return
	_t -= dt
	if _t > 0:
		return
	_t = 0.5
	var rows := rows_of(lock.game, lock.net, lock.gone)
	var sig := str(rows)
	if sig == _sig:
		return
	_sig = sig
	UiKit.clear(grid)
	for c in COLS:
		var h := Label.new()
		h.text = c.to_upper()
		h.add_theme_font_size_override("font_size", 12)
		h.add_theme_color_override("font_color", MUTED)
		grid.add_child(h)
	for r in rows:
		var name_l := Label.new()
		name_l.text = str(r[1]) + (("  (%s)" % r[9]) if r[9] != "" else "")
		name_l.tooltip_text = str(lock.game.player_info(int(r[0])).name)
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		name_l.add_theme_font_size_override("font_size", 16)
		name_l.add_theme_color_override("font_color", r[2])   # (the player's nation's color)
		name_l.add_theme_color_override("font_outline_color", Color(INK, 0.55))
		name_l.add_theme_constant_override("outline_size", 2)
		grid.add_child(name_l)
		for i in range(3, 9):
			var l := Label.new()
			l.text = str(r[i])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_color_override("font_color", INK if i != 3 else MUTED)
			grid.add_child(l)
	reset_size()
