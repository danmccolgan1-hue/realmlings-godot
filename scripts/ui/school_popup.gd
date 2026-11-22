class_name SchoolPopup
extends Control
## "Choose a school of magic": offered when your first Mage Tower stands (and after abandoning a school). A card per
## school your race can learn (only the leader's own school for a school-locked leader), with its spells; picking
## one makes it your Magic research. web: magic.js openSchoolPopup + the #schoolPick clicks, v105.js lockOf.
## Views only: picking goes through game.pick_school.

var game: Game
var hud
var panel: PanelContainer
var col: VBoxContainer


func setup(g: Game, h) -> void:
	game = g
	hud = h
	if panel == null:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiKit.box(UiKit.PAPER, 14, 4))
		add_child(panel)
		col = VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		panel.add_child(col)
	hide()


func open() -> void:
	if game.current_school() != null:
		return
	UiKit.clear(col)
	var head := HBoxContainer.new()
	var t := UiKit.ink(26)
	t.text = "Choose a school of magic"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiKit.button("✕", 18, func(): hide()))
	col.add_child(head)
	var L = game.leader_of(Game.LOCAL)
	var lock = L.get("school") if L != null else null
	var sub := UiKit.ink(16)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(760, 0)
	sub.text = ("%s follows %s: it is the only school your nation can learn." % [L.full, GameData.c("SCHOOL_WORD")[lock]]) if lock != null else \
		"Your first Mage Tower stands. Your first Magic research will be the school you pick; you can switch before it finishes. Abandoning a school later is costly."
	col.add_child(sub)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(cards)
	var SC: Dictionary = GameData.c("SCHOOLS")
	var cur = game.tech.mag.cur
	for k in SC:
		var id: String = "school-" + k
		if not game.TECH_BY_ID.has(id) or not game.tech_for(game.TECH_BY_ID[id]) or not Races.race_is(SC[k].get("race"), game.race()) or (lock != null and k != lock):
			continue
		cards.add_child(_card(k, SC[k], cur == id))
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 10)
	col.add_child(btns)
	btns.add_child(_plain("Show me", func():   # the choice stays open
		for p in game.extras:
			if game.owned(p) and game.extras[p].any(func(e): return e.type == "magetower"):
				hud.look_at_prov(p, false)
				break))
	btns.add_child(_plain("Decide later (Research panel)", func(): hide()))
	show()
	panel.reset_size()
	UiKit.center.call_deferred(panel)


func _plain(t: String, f: Callable) -> Button:
	var b := UiKit.button(t, 16, f)
	for st in [["normal", Color.WHITE], ["hover", Color("#fff6d8")], ["pressed", Color("#efe6cf")], ["focus", Color.WHITE]]:
		var bx := UiKit.box(st[1], 4, 2, UiKit.INK)
		bx.content_margin_top = 4
		bx.content_margin_bottom = 4
		b.add_theme_stylebox_override(st[0], bx)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, UiKit.INK)
	return b


func _card(k: String, sc: Dictionary, on: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(270, 360)
	var col_c := Color(sc.color)
	var light := Color(sc.light)
	for st in [["normal", light], ["hover", light.lightened(0.3)], ["pressed", light.darkened(0.05)], ["focus", light]]:
		var bx := UiKit.box(st[1], 10, 4 if on else 3, UiKit.INK if not on else col_c.darkened(0.3))
		b.add_theme_stylebox_override(st[0], bx)
	b.pressed.connect(func():
		if game.do("pick_school", [k]) != false:
			hide())
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.offset_top = 10
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := TextureRect.new()
	ic.texture = Hud.icon("icons/realm/tech_school_%s.png" % k)
	ic.custom_minimum_size = Vector2(64, 64)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	var n := UiKit.ink(22)
	n.text = sc.name
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_color_override("font_color", col_c.darkened(0.35))
	v.add_child(n)
	var bl := UiKit.ink(14)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.text = sc.blurb
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bl)
	for s in sc.spells:
		var l := UiKit.ink(14)
		l.text = s
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	var ep := PanelContainer.new()   # the "Choose …" plate (the whole card is the button)
	ep.add_theme_stylebox_override("panel", UiKit.box(Color.WHITE, 4, 2, UiKit.INK))
	ep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var e := UiKit.ink(15)
	e.text = "Researching" if on else "Choose " + sc.name
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ep.add_child(e)
	v.add_child(ep)
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b
