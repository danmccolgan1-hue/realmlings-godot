class_name Hud
extends CanvasLayer
## Placeholder interface for play-testing the rules: resource bar, clock, leader, and a panel for the selected
## province. Reads the game; never changes it (the main scene handles input). The real interface is Phase 5.

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
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(20, -20)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
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
	hide()


func set_game(g: Game) -> void:
	game = g
	var L = g.leader_of()
	who.text = "%s — Practice island" % (L.full if L else "")
	show()


func select_province(p: int) -> void:
	prov = p
	panel.visible = p >= 0


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
