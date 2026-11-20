class_name Hud
extends CanvasLayer
## Placeholder interface for play-testing the rules: resource bar, clock, leader, a panel for the selected
## province, the command card of the selected unit (the web game's 4×4 grid and keys) and the game's messages.
## The real interface is Phase 5.

const RES := ["gold", "wood", "food"]
const STAGE_NAME := ["Outpost", "Fort", "Capital"]

var game: Game
var bar: HBoxContainer
var res_labels := {}
var clock: Label
var who: Label
var paused_label: Label
var panel: PanelContainer
var panel_text: RichTextLabel
var prov := -1
var unit = null
var card: GridContainer
var card_buttons := []
var card_cmds := []          # per cell: {id, label, why} or null
var upgrade_btn: Button
var toasts: VBoxContainer
var toast_list := []         # [{label, until}]
var GRID_KEYS: Array


func _ready() -> void:
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_stylebox_override("panel", _box(Color("#2a2433", 0.92)))
	add_child(top)
	bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 28)
	top.add_child(bar)
	for k in RES:
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		var sp = Art.get_sprite("icons", "common", "res_%s.png" % k)
		if sp:
			icon.texture = sp.tex
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var l := _label(24)
		row.add_child(l)
		res_labels[k] = l
		bar.add_child(row)
	clock = _label(24)
	bar.add_child(clock)
	who = _label(20)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(who)
	paused_label = _label(40)
	paused_label.text = "Paused — press Space to play"
	paused_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	paused_label.position.y = 90
	paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paused_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(paused_label)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("#faf1dc", 0.96)))
	panel.custom_minimum_size = Vector2(420, 0)
	panel_text = RichTextLabel.new()
	panel_text.bbcode_enabled = true
	panel_text.fit_content = true
	panel_text.custom_minimum_size = Vector2(400, 0)
	panel_text.add_theme_color_override("default_color", Color("#1d1a22"))
	panel_text.add_theme_font_size_override("normal_font_size", 20)
	panel_text.add_theme_font_size_override("bold_font_size", 22)
	panel.add_child(panel_text)
	add_child(panel)
	panel.hide()
	upgrade_btn = Button.new()
	upgrade_btn.add_theme_font_size_override("font_size", 20)
	upgrade_btn.pressed.connect(func(): game.start_upgrade(prov))
	panel_text.get_parent().remove_child(panel_text)
	var pcol := VBoxContainer.new()
	pcol.add_child(panel_text)
	pcol.add_child(upgrade_btn)
	panel.add_child(pcol)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# the command card
	GRID_KEYS = GameData.c("GRID_KEYS")
	var cpanel := PanelContainer.new()
	cpanel.add_theme_stylebox_override("panel", _box(Color("#2a2433", 0.92)))
	add_child(cpanel)
	cpanel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	cpanel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cpanel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card = GridContainer.new()
	card.columns = 4
	cpanel.add_child(card)
	for i in 16:
		var b := Button.new()
		b.custom_minimum_size = Vector2(124, 64)
		b.add_theme_font_size_override("font_size", 15)
		b.clip_text = true
		b.pressed.connect(press.bind(i))
		card.add_child(b)
		card_buttons.append(b)
		card_cmds.append(null)
	cpanel.hide()
	toasts = VBoxContainer.new()
	toasts.custom_minimum_size = Vector2(520, 0)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(toasts)
	toasts.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	toasts.offset_top = 70
	hide()


func set_game(g: Game) -> void:
	game = g
	g.on_toast = add_toast
	var L = g.leader_of()
	who.text = "%s — Practice island" % (L.full if L else "")
	show()


func select_province(p: int) -> void:
	prov = p
	panel.visible = p >= 0


func select_unit(u) -> void:
	unit = u
	card.get_parent().visible = u != null


func add_toast(msg: String, warn := false) -> void:
	var l := _label(19)
	l.text = msg
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if warn:
		l.add_theme_color_override("font_color", Color("#ffb3a6"))
	toasts.add_child(l)
	toast_list.append({"label": l, "until": Time.get_ticks_msec() + 6000})
	while toast_list.size() > 5:
		toast_list.pop_front().label.queue_free()


## The commands of the selected unit, by cell. web: game.js CMD (Mason: build:<type>, Wayfinder: survey, auto)
func commands_of(u) -> Array:
	var out := []
	out.resize(16)
	if u == null:
		return out
	var list: Array = GameData.c("CMD").get(u.kind, [])
	for c in list:
		var id: String = c.id
		var cmd = null
		if id.begins_with("build:"):
			var type := id.substr(6)
			if type != "outpost" and not game.BUILD_DEFS.has(type):
				continue
			var name: String = "Outpost" if type == "outpost" else game.BUILD_DEFS[type].name
			var cost: Dictionary = GameData.c("OUTPOST_COST") if type == "outpost" else game.BUILD_DEFS[type].cost
			var short := []
			for k in cost:
				short.append("%d%s" % [cost[k], k.left(1)])
			cmd = {"id": id, "label": "%s\n%s" % [name, " ".join(short)], "why": game.build_check(u.prov, type)}
		elif id == "survey":
			var why = null
			if game.surveyed.has(u.prov):
				why = "Already surveyed"
			elif u.survey != null:
				why = "Surveying…"
			cmd = {"id": id, "label": "Survey", "why": why}
		elif id == "auto" and game.has_tech("autoscout"):
			cmd = {"id": id, "label": "Auto: %s" % ("off" if u.get("auto", true) == false else "on"), "why": null}
		elif id == "cancelbuild":
			cmd = {"id": id, "label": "Cancel build", "why": null if u.build != null else "Not building"}
		if cmd != null:
			out[int(c.cell)] = cmd
	return out


func press(i: int) -> void:
	var c = card_cmds[i]
	if c == null or unit == null or not game.units.any(func(v): return is_same(v, unit)):
		return
	if c.why != null:
		add_toast(str(c.why), true)
		return
	var id: String = c.id
	if id.begins_with("build:"):
		game.order_build(unit, unit.prov, id.substr(6))
	elif id == "survey":
		game.queue_survey(unit, unit.prov)
	elif id == "auto":
		unit.auto = unit.get("auto", true) == false
	elif id == "cancelbuild":
		game.cancel_build(unit)
		add_toast("Construction cancelled. Resources refunded.")


## A command-card key (q w e r / a s d f / z x c v / u i o p). Returns true when it was used.
func key(k: String) -> bool:
	var i := GRID_KEYS.find(k)
	if i < 0 or unit == null:
		return false
	press(i)
	return true


func _process(_delta: float) -> void:
	if not game:
		return
	for k in RES:
		var inc: int = game.income[k]
		res_labels[k].text = "%d %s  (%s%d)" % [game.stock[k], k.capitalize(), "+" if inc >= 0 else "−", absi(inc)]
		res_labels[k].add_theme_color_override("font_color", Color("#ff8a7a") if inc < 0 else Color.WHITE)
	var secs := int(game.t)
	var next := maxf(0.0, game.next_tick - game.t) if game.next_tick > 0 else game.TICK
	clock.text = "%d:%02d   next payday %ds" % [secs / 60, secs % 60, ceili(next)]
	if game.exhaust > 0:
		clock.text += "   Army Exhaustion %d/%d" % [game.exhaust, GameData.c("EXHAUST_MAX")]
	paused_label.visible = game.paused
	if prov >= 0:
		panel_text.text = _province_text(prov)
		var show_up: bool = game.owned(prov) and game.buildings[prov].stage == 0
		upgrade_btn.visible = show_up
		if show_up:
			var why = game.upgrade_why(prov)
			upgrade_btn.text = "Upgrade to Fort (%s, %d s)" % [Game.cost_text(GameData.c("FORT_UPGRADE").cost), GameData.c("FORT_UPGRADE").time] if why == null else str(why)
			upgrade_btn.disabled = why != null
	if unit != null and not game.units.any(func(v): return is_same(v, unit)):
		select_unit(null)
	if unit != null:
		card_cmds = commands_of(unit)
		for i in 16:
			var c = card_cmds[i]
			var b: Button = card_buttons[i]
			b.text = "" if c == null else "%s [%s]" % [c.label, GRID_KEYS[i].to_upper()]
			b.disabled = c == null or c.why != null
			b.tooltip_text = "" if c == null or c.why == null else str(c.why)
	var now := Time.get_ticks_msec()
	while not toast_list.is_empty() and toast_list[0].until < now:
		toast_list.pop_front().label.queue_free()


func _province_text(p: int) -> String:
	var P: Dictionary = game.G.provs[p]
	var s := "[b]Province %d[/b] · %s\n" % [p, P.terrain.capitalize()]
	if game.buildings.has(p):
		var b: Dictionary = game.buildings[p]
		s += "%s (yours)\n" % STAGE_NAME[b.stage]
	if game.surveyed.has(p):
		var y: Dictionary = game.yields[p]
		s += "Yields every 10 s: %d gold, %d wood, %d food\n" % [y.gold, y.wood, y.food]
		if game.owned(p):
			var inc := game.province_income(p, game.buildings[p])
			s += "Pays now: %d gold, %d wood, %d food\n" % [inc.gold, inc.wood, inc.food]
	else:
		s += "Not surveyed: send a Wayfinder to learn what it yields\n"
	var ex := game.extras_in(p)
	if not ex.is_empty():
		var names := []
		for e in ex:
			names.append(game.BUILD_DEFS[e.type].name + (" (no upkeep)" if e.has("freeFor") else ""))
		s += "Buildings: %s\n" % ", ".join(names)
	if game.owned(p):
		s += "Plots: %d of %d used\n" % [ex.size(), game.plot_cap(p)]
	var here := []
	for u in game.units:
		if u.prov == p:
			if u.kind == "army":
				var parts := []
				for k in u.troops:
					var d = game.unit_defs.get(k)
					parts.append("%s × %d" % [d.name if d else k, u.troops[k]])
				here.append("%s: %s" % [u.name, ", ".join(parts)])
			else:
				here.append("%s the %s" % [u.name, game.unit_defs[u.kind].name])
	if not here.is_empty():
		s += "\n" + "\n".join(here)
	return s.strip_edges()


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


static func _box(c: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = c
	b.set_corner_radius_all(10)
	b.content_margin_left = 16
	b.content_margin_right = 16
	b.content_margin_top = 10
	b.content_margin_bottom = 10
	return b
