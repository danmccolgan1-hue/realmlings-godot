class_name Roster
extends PanelContainer
## Your armies and workers in a list: what each is doing, a click selects it and looks there.
## web: game.js #roster

var game: Game
var hud
var box: VBoxContainer
var key := ""


func setup(g: Game, h) -> void:
	game = g
	hud = h
	add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.DARK, 0.88)))
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)


func _doing(u: Dictionary) -> String:
	if u.get("battle") != null:
		return "in battle"
	if u.get("retro") != null:
		return "retrofitting"
	if u.get("rest") != null:
		return "resting"
	if u.get("build") != null:
		return "building"
	if u.get("survey") != null:
		return "surveying"
	if u.get("cast") != null:
		return "casting"
	if u.moving:
		return "marching" if u.kind == "army" else "walking"
	return game.prov_name(u.prov)


func _process(_dt: float) -> void:
	if game == null:
		return
	var mine := game.units.filter(func(u): return u.owner == Game.ME)
	var rows := []
	for u in mine:
		var name: String = u.name
		if u.kind == "army":
			name += " (%d)" % game.troop_count(u)
		rows.append([u, "%s · %s" % [name, _doing(u)]])
	var k := str(rows.map(func(r): return r[1]))
	if k == key:
		return
	key = k
	UiKit.clear(box)
	var head := UiKit.label(18, UiKit.GOLD)
	head.text = "Your units"
	box.add_child(head)
	for r in rows:
		var b := UiKit.button(r[1], 15, func():
			hud.focus_unit(r[0]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.add_theme_color_override("font_color", Color.WHITE)
		box.add_child(b)
