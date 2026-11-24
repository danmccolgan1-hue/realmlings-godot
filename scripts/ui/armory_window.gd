class_name ArmoryWindow
extends Control
## The Armory (G), laid out as the web game's: the designs on the left (grouped Infantry, Cavalry, Mages, each with
## its portrait and stats), the edited design on the right (a spinning preview, name, stat bars, cost, note, buttons)
## and its gear as picture buttons under Weapons / Armor / Horses tabs. The second tab places Army Training Orders.
## web: equip.js renderArmory / renderMageEditor / drawArmPreview, v96.js armTabs, v106.js renderOrderView.
## Views only: every change goes through the game's own functions.

const LINE := Color("#cdbf9e")
const SEL := Color("#fff1b8")
const CARD := Color("#fbf6e8")
const MUTED := Color("#6b6257")
const BLUE := Color("#4a8fdc")
const GREEN := Color("#7ac74f")

var game: Game
var hud
var win: Dictionary
var sub: Label
var mode := 0                 # 0: Designs, 1: Army Training Order
var mode_btns := []
var content: Control
var draft := {}
var sel := ""                 # the design being edited ("mage" for the Mage gear, "" for a new one)
var gear_tab := "Weapons"
var name_edit: LineEdit
var key := ""
var order_draft := {}
var order_rally := -1
var order_key := ""


## The spinning preview on its green patch (web: equip.js drawArmPreview). The port has art for the starting
## designs only, so a design shows the starting soldier of its weapon family (see Art.design_art).
class Preview extends Control:
	var kind := "d-sword"
	var look := 0   # the armor it wears (Art.armored)
	var game

	func _process(_dt: float) -> void:
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var ctr := Vector2(size.x / 2, size.y * 0.8)
		var pts := PackedVector2Array()
		for i in 48:
			var a := TAU * i / 48.0
			pts.append(ctr + Vector2(cos(a) * size.x * 0.37, sin(a) * size.y * 0.11))
		draw_colored_polygon(pts, Color("#9bd95f"))
		pts.append(pts[0])
		draw_polyline(pts, UiKit.INK, 3.0, true)
		var dir := int(Time.get_ticks_msec() / 1000.0 * 0.6 / (PI / 4)) % 8
		var sp = Art.armored(Art.race_sprite("units", game.race(), Art.unit_file(Art.design_art(game, kind), "d%d" % dir)), look)
		if sp == null:
			return
		var tex: Texture2D = sp.tex
		var s := size.y * (0.78 if game.DSTATS.get(kind, {}).get("cav", false) else 0.66) / tex.get_height()
		draw_set_transform(ctr - Vector2(sp.ax, sp.ay) * s, 0.0, Vector2(s, s))
		draw_texture(tex, Vector2.ZERO)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A small padlock on locked gear (the bundled fonts have no 🔒).
class Lock extends Control:
	func _draw() -> void:
		draw_arc(Vector2(7, 7), 4.0, PI, TAU, 12, UiKit.INK, 2.0, true)
		draw_line(Vector2(3, 7), Vector2(3, 9), UiKit.INK, 2.0)
		draw_line(Vector2(11, 7), Vector2(11, 9), UiKit.INK, 2.0)
		draw_rect(Rect2(1, 8, 12, 8), Color("#e8c547"))
		draw_rect(Rect2(1, 8, 12, 8), UiKit.INK, false, 1.5)


func setup(g: Game, h) -> void:
	game = g
	hud = h
	draft = {}
	sel = ""
	order_draft = {}
	if not win.is_empty():   # (a new game reuses the window)
		hide()
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win = UiKit.window("Armory", 1060, func(): close())
	add_child(win.panel)
	UiKit.draggable(win.panel, win.title, "armory")   # 0.19
	var head: HBoxContainer = win.title.get_parent()
	win.title.size_flags_horizontal = 0
	sub = UiKit.ink(15)
	sub.add_theme_color_override("font_color", MUTED)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(sub)
	head.move_child(sub, 1)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	win.body.add_child(bar)
	for i in 2:
		var b := UiKit.button(["Designs", "Army Training Order"][i], 15, func(): _mode(i))
		bar.add_child(b)
		mode_btns.append(b)
	content = VBoxContainer.new()
	win.body.add_child(content)
	hide()


func open(tab := 0) -> void:
	show()
	mode = tab
	if draft.is_empty():
		edit(game.designs[0].id if not game.designs.is_empty() else "mage")
	if order_rally < 0 or not game.owned(order_rally):
		order_rally = game.capital if game.capital >= 0 and game.owned(game.capital) else -1
	_rebuild()
	_place.call_deferred()


## Designs: centered. The Army Training Order: narrower, just under the Paused sign.
func _place() -> void:
	win.panel.custom_minimum_size.x = 1060 if mode == 0 else 0
	win.panel.reset_size()
	UiKit.center(win.panel)
	if mode == 1 and hud != null and hud.paused_label != null and not UiKit.is_placed("armory"):
		win.panel.position.y = hud.paused_label.position.y + hud.paused_label.size.y + 8


func close() -> void:
	hide()


func toggle() -> void:
	if visible:
		close()
	else:
		open(mode)


func _mode(i: int) -> void:
	mode = i
	_rebuild()
	_place.call_deferred()


# web: equip.js editDesign
func edit(id: String) -> void:
	if id == "mage":
		sel = "mage"
		draft = {"id": "mage", "type": "mage", "name": game.unit_defs[game.MAGE].name, "weapon": game.mage_gear.weapon, "shield": game.mage_gear.shield, "skull": game.mage_gear.get("skull")}
	else:
		var d = game.design_by_id(id)
		if d == null:
			return
		sel = id
		draft = d.duplicate()
	key = ""
	if visible:
		_rebuild()


# web: equip.js newDesign (Realmlings)
func new_design(type: String) -> void:
	var rc: String = game.race()
	var n := 1 + game.designs.filter(func(d): return d.type == type and d.get("race", "realm") == rc).size()
	var champ: bool = rc == "wood" and type == "cav"
	draft = {"id": null, "name": (game.UNIT_BASE[type].name.trim_suffix("s") + " " if rc != "realm" else ("Cavalry " if type == "cav" else "Infantry ")) + str(n), "type": type,
		"weapon": "champsword" if champ else "spear", "shield": null, "off": null, "armor": "ornate1" if champ else Races.HOME_ARMOR[rc],
		"horse": "riding" if type == "cav" and rc != "wood" else null, "race": rc}
	sel = ""
	_rebuild()


func _rebuild() -> void:
	key = _key()
	order_key = ""
	for i in mode_btns.size():
		_tab_style(mode_btns[i], i == mode)
	UiKit.clear(content)
	content.custom_minimum_size = Vector2.ZERO
	if mode == 1:
		sub.text = "Order a whole army: every Barracks trains its share, and they gather in one province."
		_build_orders()
	else:
		sub.text = "Design the soldiers your Barracks train. Better gear costs more."
		_build_designs()
	win.panel.reset_size()


# the redraw key (web: armKey): research done and the designs' names; the draft changes rebuild the window directly
func _key() -> String:
	var n := 0
	for t in game.tech:
		n += game.tech[t].done.size()
	return "%d|%d|%s" % [n, game.designs.size(), ",".join(game.designs.map(func(d): return d.name))]


# ---------------------------------------------------------------- Designs

func _build_designs() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	row.add_child(_design_list())
	var ed := VBoxContainer.new()
	ed.add_theme_constant_override("separation", 6)
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ed)
	if draft.type == "mage":
		_mage_editor(ed)
	else:
		_design_editor(ed)


func _design_list() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(232, 0)
	col.add_theme_constant_override("separation", 5)
	for type in ["inf", "cav"]:
		col.add_child(_group_head(game.UNIT_BASE[type].name))
		for d in game.designs:
			if d.type != type or d.get("race", "realm") != game.race():
				continue
			var s: Dictionary = game.DSTATS[d.id]
			col.add_child(_card(hud.unit_icon(d.id), d.name, s, sel == d.id, edit.bind(d.id)))
		var nb := UiKit.button("＋ New %s design" % ("cavalry" if type == "cav" else "infantry"), 14, new_design.bind(type))
		_style(nb, Color(1, 1, 1, 0.25), 2, UiKit.INK)
		nb.add_theme_color_override("font_color", UiKit.INK)
		nb.add_theme_color_override("font_hover_color", UiKit.INK)
		nb.custom_minimum_size = Vector2(0, 34)
		col.add_child(nb)
	col.add_child(_group_head(game.unit_defs[game.MAGE].name + "s"))
	col.add_child(_card(hud.unit_icon(game.MAGE), game.unit_defs[game.MAGE].name + " gear", game.DSTATS[game.MAGE], sel == "mage", edit.bind("mage")))
	return col


func _group_head(t: String) -> Label:
	var l := UiKit.ink(13)
	l.text = t.to_upper()
	l.add_theme_color_override("font_color", MUTED)
	return l


# a design in the list: portrait, name, and "⚔atk ♥hp 🛡red% ➜speed"
func _card(tex: Texture2D, title: String, s: Dictionary, on: bool, f: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 50)
	_style(b, SEL if on else CARD, 2 if on else 1, UiKit.INK if on else LINE)
	b.pressed.connect(f)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 6)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	h.add_child(_tex(tex, 38))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var n := UiKit.ink(16)
	n.text = title
	v.add_child(n)
	v.add_child(_stat_line(s, 13))
	return b


func _stat_line(s: Dictionary, size: int) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := UiKit.ink(size)
	a.text = "⚔%s ♥%s " % [UiKit.num(s.atk), UiKit.num(s.hp)]
	h.add_child(a)
	h.add_child(_tex(Hud.icon("icons/common/gear_shield_round.png"), size))
	var r := UiKit.ink(size)
	r.text = "%d%% ➜%s" % [roundi(s.red * 100), ("%.2f" % s.speed) if s.get("fam") == "magic" else UiKit.num(snappedf(s.speed, 0.01))]
	h.add_child(r)
	return h


func _tex(tex: Texture2D, px: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


# the top of the editor: preview, then name / kind / stat bars / cost / note / buttons beside it
func _top(ed: VBoxContainer, st: Dictionary, kind_text: String, named: bool) -> VBoxContainer:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	ed.add_child(top)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box(Color("#eef6e0"), 2, UiKit.INK, 0))
	top.add_child(frame)
	var pv := Preview.new()
	pv.game = game
	pv.kind = game.MAGE if draft.type == "mage" else _draft_art()
	if draft.type != "mage":   # 0.19: the preview wears the chosen armor
		var A = GameData.c("ARMORS").get(str(draft.get("armor", "")))
		pv.look = {"chain": 1, "wyvern": 1, "mithril": 1, "plate": 2, "dragon": 2, "ornate": 2}.get(str(A.type), 0) if A is Dictionary else 0
	pv.custom_minimum_size = Vector2(176, 176)
	frame.add_child(pv)
	var sm := VBoxContainer.new()
	sm.add_theme_constant_override("separation", 3)
	sm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sm)
	if named:
		var nr := HBoxContainer.new()
		var nl := UiKit.ink(13)
		nl.text = "NAME"
		nl.add_theme_color_override("font_color", MUTED)
		nl.custom_minimum_size = Vector2(50, 0)
		nr.add_child(nl)
		name_edit = LineEdit.new()
		name_edit.text = draft.name
		name_edit.max_length = 24
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.add_theme_font_size_override("font_size", 17)
		name_edit.add_theme_color_override("font_color", UiKit.INK)
		name_edit.add_theme_stylebox_override("normal", _box(Color.WHITE, 1, UiKit.INK, 4))
		name_edit.add_theme_stylebox_override("focus", _box(Color.WHITE, 2, UiKit.INK, 4))
		name_edit.text_changed.connect(func(t): draft.name = t)
		nr.add_child(name_edit)
		sm.add_child(nr)
	var kl := UiKit.ink(14 if named else 16)
	kl.text = kind_text
	kl.add_theme_color_override("font_color", MUTED if named else UiKit.INK)
	sm.add_child(kl)
	sm.add_child(_bar("Attack", st.atk, 18, UiKit.num(st.atk)))
	sm.add_child(_bar("Health", st.hp, 75, UiKit.num(st.hp)))
	sm.add_child(_bar("Armor", st.red, 0.65, "%d%%" % roundi(st.red * 100)))
	sm.add_child(_bar("Speed", st.speed, 2, ("%.2f" % st.speed) if draft.type == "mage" else UiKit.num(snappedf(st.speed, 0.01))))
	return sm


# web: equip.js statBar
func _bar(label: String, v: float, mx: float, txt: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := UiKit.ink(14)
	l.text = label
	l.custom_minimum_size = Vector2(60, 0)
	h.add_child(l)
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.step = 0.0
	pb.value = clampf(v / mx, 0, 1)
	pb.custom_minimum_size = Vector2(0, 14)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_theme_stylebox_override("background", _box(Color("#f4f6fa"), 1, Color("#8a8f99"), 0))
	pb.add_theme_stylebox_override("fill", _box(BLUE, 0, BLUE, 0))
	h.add_child(pb)
	var t := UiKit.ink(14)
	t.text = txt
	t.custom_minimum_size = Vector2(48, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(t)
	return h


func _cost_line(sm: VBoxContainer, l1: String, c1: Dictionary, l2: String, c2: Dictionary) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for p in [[l1, c1], [l2, c2]]:
		var l := UiKit.ink(13)
		l.text = p[0].to_upper()
		l.add_theme_color_override("font_color", MUTED)
		h.add_child(l)
		h.add_child(CostRow.make(p[1], 15))
	sm.add_child(h)


func _note(sm: VBoxContainer, t: String) -> void:
	var l := UiKit.ink(14)
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	sm.add_child(l)


# the art kind a new (unsaved) design shows: the starting design of its weapon family
func _draft_art() -> String:
	var A: Dictionary = Art.DESIGN_ART[game.race()]
	if draft.type == "cav":
		return A.cav
	var base: String = A.get(GameData.c("WEAPONS")[draft.weapon].fam, A.other)
	return base + "-dw" if game.is_sw() and draft.get("off") != null else base


# web: equip.js renderArmory (Realmlings: no Ogres, Champions or off-hands)
func _design_editor(ed: VBoxContainer) -> void:
	var st := game.design_stats(draft)
	var W: Dictionary = GameData.c("WEAPONS")[draft.weapon]
	var cur = game.design_by_id(draft.id) if draft.get("id") != null else null
	var in_use: bool = cur != null and game.design_in_use(cur.id)
	var kt: String = game.UNIT_BASE[draft.type].name + (" · starting design" if cur != null and cur.builtin else (" · in use" if in_use else ""))
	var sm := _top(ed, st, kt, true)
	_cost_line(sm, "Cost", st.cost, "Upkeep", st.upkeep)
	var rc: String = game.race()
	var MT: Dictionary = GameData.c("OGRES") if rc == "swamp" else GameData.c("HORSES")
	var H = MT[draft.get("horse") if draft.get("horse") != null else "riding"]
	var where := " Trained at an %s." % game.BUILD_DEFS.stable.name if rc == "swamp" else " Needs a Barracks and a %s." % game.BUILD_DEFS.stable.name
	_note(sm, GameData.c("FAMILY")[W.fam].note + "." + ((" " + (H.note if rc != "wood" else "A Champion fights alone and needs no mount.") + where) if st.cav else "") + ("" if st.blurb == "" else " " + st.blurb))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	sm.add_child(btns)
	btns.add_child(_btn("Save changes" if cur != null and not cur.builtin and not in_use else "Save as new design", UiKit.GOLD, _save))
	if cur != null:
		var rb := _btn("Retrofit armies", Color("#dff0d0"), _retrofit)
		rb.tooltip_text = UiKit.wrap("Re-equip every %s soldier standing in your own provinces with this design; you pay the difference in gear cost" % ("cavalry" if cur.type == "cav" else "infantry"))
		btns.add_child(rb)
	if cur != null and not cur.builtin:
		btns.add_child(_btn("Delete", Color("#f3d6d2"), _delete))
	# the gear, under tabs (web: v96.js armTabs)
	var tabs := ["Weapons", "Armor"] + ([("Ogres" if rc == "swamp" else "Horses")] if draft.type == "cav" and rc != "wood" else [])
	if not tabs.has(gear_tab):
		gear_tab = "Weapons"
	ed.add_child(_gear_tabs(tabs))
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	ed.add_child(grid)
	if gear_tab == "Weapons" and rc == "wood" and draft.type == "cav":   # web: equip.js renderChampEditor
		grid.add_child(_gear_row("Champion weapons", "Each trades toughness, speed and cost", GameData.c("CHAMP_WEAPONS").map(func(w): return _eq("weapon", w, GameData.c("WEAPONS")[w], draft.weapon == w, game.gear_why("weapon", w)))))
		grid.add_child(_gear_row("Grip", "Champions may always fight two-handed", [_eq_flag("two", "Two-handed", draft.get("two", false), null), _eq_flag("two", "One-handed", not draft.get("two", false), null, false)]))
	elif gear_tab == "Weapons":
		for f in GameData.c("FAMILY"):
			var F: Dictionary = GameData.c("FAMILY")[f]
			if not _mine(F.get("race")):
				continue
			grid.add_child(_gear_row(F.name, F.note, F.order.map(func(w): return _eq("weapon", w, GameData.c("WEAPONS")[w], draft.weapon == w, game.gear_why("weapon", w)))))
		if rc == "realm":
			var sh := [_eq_none(draft.get("shield") == null or W.twoH)]
			var SD: Dictionary = GameData.c("SHIELD_DEFS")
			for k in SD:
				sh.append(_eq("shield", k, SD[k], draft.get("shield") == k and not W.twoH, "Two-handed weapon" if W.twoH else game.gear_why("shield", k)))
			grid.add_child(_gear_row("Shield", W.name + " needs both hands" if W.twoH else "One-handed weapons only", sh))
		elif rc == "swamp":   # web: swamp.js offhandRow (Dual Wielding)
			var off := [_eq_none(draft.get("off") == null or W.twoH, "off")]
			for f in ["axe", "blunt", "pole"]:
				for w in GameData.c("FAMILY")[f].order:
					if not GameData.c("WEAPONS")[w].twoH:
						off.append(_eq("off", w, GameData.c("WEAPONS")[w], draft.get("off") == w and not W.twoH, "Two-handed weapon" if W.twoH else game.gear_why("off", w)))
			grid.add_child(_gear_row("Off hand", "A second one-handed weapon hits for half its attack (Dual Wielding)", off))
		else:   # Woodlings: two-handing (Two-Handed Grip)
			var why = null if game.has_tech("twohand") else "Research " + game.TECH_BY_ID.twohand.name
			grid.add_child(_gear_row("Grip", "Two-handed: heavy blows every other round (125% damage over time)", [_eq_flag("two", "Two-handed", draft.get("two", false), why), _eq_flag("two", "One-handed", not draft.get("two", false), null, false)]))
	elif gear_tab == "Armor":
		var AT: Dictionary = GameData.c("ARMOR_TYPES")
		for t in AT:
			if not _mine(AT[t].get("race")) or (rc == "wood" and (t == "ornate") != (draft.type == "cav")):
				continue
			var row := []
			for lv in [1, 2, 3, 4]:
				var k := "%s%d" % [t, lv]
				row.append(_eq("armor", k, GameData.c("ARMORS")[k], draft.armor == k, game.gear_why("armor", k)))
			grid.add_child(_gear_row(AT[t].name, AT[t].note, row))
	else:
		var HS: Dictionary = MT
		var row := []
		for k in HS:
			row.append(_eq("horse", k, HS[k], draft.get("horse") == k, game.gear_why("horse", k)))
		grid.add_child(_gear_row("Mount", "Each breed trades speed, toughness, charge and cost", row))


# web: equip.js renderMageEditor (Realmling Mages: staves and wands, and a shield with a wand)
func _mage_editor(ed: VBoxContainer) -> void:
	var st := game.mage_stats(draft)
	var MW: Dictionary = GameData.c("MAGE_WEAPONS")
	var W: Dictionary = MW[draft.weapon]
	var M: String = game.unit_defs[game.MAGE].name
	var sm := _top(ed, st, "%s gear · every %s" % [M, M], false)
	_cost_line(sm, "Train", game.unit_defs[game.MAGE].cost, "Upkeep", game.unit_defs[game.MAGE].upkeep)
	_note(sm, "%ss are trained at a %s. Their gear is shared: changing it re-equips every %s. %s" % [M, game.BUILD_DEFS.magetower.name if game.BUILD_DEFS.has("magetower") else "Mage Tower", M, st.blurb])
	var btns := HBoxContainer.new()
	sm.add_child(btns)
	btns.add_child(_btn("Equip all %ss" % M, UiKit.GOLD, func():
		game.do("set_mage_gear", [{"weapon": draft.weapon, "shield": draft.get("shield"), "skull": draft.get("skull")}])
		edit("mage")))
	gear_tab = "Weapons"
	ed.add_child(_gear_tabs(["Weapons"]))
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	ed.add_child(grid)
	var rc: String = game.race()
	for ln in [["stave", "Staves", "Two-handed, the stronger attack"], ["wand", "Wands", "One-handed: leaves room for a skull" if rc == "swamp" else "One-handed: leaves room for a shield"]]:
		var row := []
		for k in MW:
			if MW[k].line == ln[0] and _mine(MW[k].get("race")) and (MW[k].get("tech") == null or not game.TECH_BY_ID.has(MW[k].tech) or game.tech_for(game.TECH_BY_ID[MW[k].tech])):
				row.append(_eq("weapon", k, MW[k], draft.weapon == k, game.mage_gear_why("weapon", k)))
		grid.add_child(_gear_row(ln[1], ln[2], row))
	if rc == "swamp":   # web: v95.js — the Shield row becomes an Off-hand skull row
		var sk := [_eq_none(draft.get("skull") == null or W.twoH, "skull")]
		var SKD: Dictionary = GameData.c("SKULLS")
		for k in SKD:
			sk.append(_eq("skull", k, SKD[k], draft.get("skull") == k and not W.twoH, "Staves need both hands" if W.twoH else game.mage_gear_why("skull", k)))
		grid.add_child(_gear_row("Off-hand skull", "Staves need both hands" if W.twoH else "Adds to the wand’s attack and speeds the Fireball", sk))
	elif rc == "realm":
		var sh := [_eq_none(draft.get("shield") == null or W.twoH)]
		var SD: Dictionary = GameData.c("SHIELD_DEFS")
		for k in SD:
			sh.append(_eq("shield", k, SD[k], draft.get("shield") == k and not W.twoH, "Two-handed stave" if W.twoH else game.mage_gear_why("shield", k)))
		grid.add_child(_gear_row("Shield", "Staves need both hands" if W.twoH else "Wands only", sh))


func _gear_tabs(names: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	for n in names:
		var b := UiKit.button(n.to_upper(), 14, func():
			gear_tab = n
			_rebuild())
		_tab_style(b, n == gear_tab)
		h.add_child(b)
	return h


func _gear_row(title: String, note: String, buttons: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(190, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	var t := UiKit.ink(16)
	t.text = title
	v.add_child(t)
	var n := UiKit.ink(12)
	n.text = note
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size = Vector2(190, 0)
	n.add_theme_color_override("font_color", MUTED)
	v.add_child(n)
	h.add_child(v)
	for b in buttons:
		h.add_child(b)
	return h


# a gear button: its picture and name; locked gear is faded with a padlock and says why when pressed
# (web: equip.js equipButton)
func _eq(kind: String, k: String, item: Dictionary, on: bool, why) -> Button:
	var b := _eq_frame(on, item.name + ("" if why == null else " · " + why))
	var v: VBoxContainer = b.get_child(0)
	var gk := "weapon" if kind == "off" else ("ogre" if kind == "horse" and game.is_sw() else kind)
	var ic := _tex(Hud.icon("icons/realm/tech_%s.png" % str(item.get("tech", "")).replace("-", "_")) if kind == "skull" else Hud.icon("icons/common/gear_%s_%s.png" % [gk, k]), 40)
	v.add_child(ic)
	var l := _eq_label(item.name)
	v.add_child(l)
	if why != null:
		ic.modulate.a = 0.4
		l.add_theme_color_override("font_color", MUTED)
		var lk := Lock.new()
		lk.position = Vector2(64, 3)
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lk)
	b.pressed.connect(func():
		if why != null:
			game.toast(item.name + " · " + why, true)
			return
		_pick(kind, k))
	return b


func _eq_none(on: bool, kind := "shield") -> Button:
	var b := _eq_frame(on, "None")
	var v: VBoxContainer = b.get_child(0)
	var d := UiKit.ink(22)
	d.text = "—"
	d.custom_minimum_size = Vector2(40, 40)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(d)
	v.add_child(_eq_label("None"))
	b.pressed.connect(func(): _pick(kind, ""))
	return b


# a two-way choice with no gear icon (the Woodlings' grip)
func _eq_flag(kind: String, label: String, on: bool, why, val := true) -> Button:
	var b := _eq_frame(on, label + ("" if why == null else " · " + str(why)))
	var v: VBoxContainer = b.get_child(0)
	var d := UiKit.ink(20)
	d.text = "✊✊" if val else "✊"
	d.custom_minimum_size = Vector2(40, 40)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(d)
	v.add_child(_eq_label(label))
	b.pressed.connect(func():
		if why != null:
			game.toast(label + " · " + str(why), true)
			return
		_pick(kind, "1" if val else ""))
	return b


func _eq_frame(on: bool, tip: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(82, 66)
	b.tooltip_text = tip
	_style(b, Color.WHITE if on else Color("#f3ead4"), 2 if on else 1, UiKit.INK if on else LINE)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 3
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	return b


func _eq_label(t: String) -> Label:
	var l := UiKit.ink(12)
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.custom_minimum_size = Vector2(80, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# web: equip.js the [data-eq] click
func _pick(kind: String, k: String) -> void:
	if kind == "weapon":
		draft.weapon = k
		var W: Dictionary = GameData.c("MAGE_WEAPONS")[k] if draft.type == "mage" else GameData.c("WEAPONS")[k]
		if W.twoH:
			draft.shield = null
	elif kind == "shield":
		draft.shield = null if k == "" else k
	elif kind == "skull":
		draft.skull = null if k == "" else k
	elif kind == "off":
		draft.off = null if k == "" else k
	elif kind == "two":
		draft.two = k == "1"
	else:
		draft[kind] = k
	_rebuild()


func _save() -> void:
	var d = game.do("save_design", [draft])
	if d is Dictionary:   # (multiplayer: the design arrives with the next steps)
		edit(d.id)


func _delete() -> void:
	if draft.get("id") != null and game.do("delete_design", [draft.id]) != false:
		edit(game.designs[0].id)


# web: features.js armoryRetroArmies + retrofitArmies
func _retrofit() -> void:
	if draft.get("id") == null or game.design_by_id(draft.id) == null:
		return
	game.do("retrofit_armies", [game.units.filter(func(v): return v.kind == "army" and v.owner == Game.LOCAL and v.get("battle") == null and not v.get("exiting", false)), draft.id])


# ---------------------------------------------------------------- Army Training Order (web: v106.js renderOrderView)

func _build_orders() -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	content.add_child(cols)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(340, 0)
	left.add_theme_constant_override("separation", 5)
	cols.add_child(left)
	left.add_child(_group_head("Soldiers"))
	var kinds := game.to_kinds()
	if kinds.is_empty():
		var l := UiKit.ink(14)
		l.text = "Nothing to train yet." if not game.to_buildings().is_empty() else "Build a Barracks first."
		l.add_theme_color_override("font_color", MUTED)
		left.add_child(l)
	for k in kinds:
		left.add_child(_order_unit(k))
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(320, 0)
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	right.add_child(_group_head("The order"))
	var rr := HBoxContainer.new()
	var rl := UiKit.ink(15)
	rl.text = "Gather in"
	rr.add_child(rl)
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", 15)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var provs := []
	for p in game.world.provinces.size():
		if game.owned(p):
			provs.append(p)
			opt.add_item(game.prov_name(p) + (" (capital)" if game.buildings.has(p) and game.buildings[p].stage == 2 else ""))
	if order_rally < 0 and not provs.is_empty():
		order_rally = provs[0]
	opt.select(provs.find(order_rally))
	opt.item_selected.connect(func(i):
		order_rally = provs[i]
		_rebuild())
	rr.add_child(opt)
	right.add_child(rr)
	var n := 0
	for k in order_draft:
		n += order_draft[k]
	var sum := HBoxContainer.new()
	var sl := UiKit.ink(15)
	sl.text = "%d soldier%s from %d building%s" % [n, "" if n == 1 else "s", game.to_buildings().size(), "" if game.to_buildings().size() == 1 else "s"]
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sum.add_child(sl)
	var cl := UiKit.ink(15)
	cl.text = "Cost " + ("—" if not n else "")
	sum.add_child(cl)
	if n:
		sum.add_child(CostRow.make(game.to_cost(order_draft), 15))
	right.add_child(sum)
	var note := UiKit.ink(13)
	note.text = "This rally point is the order's own: it doesn't change the rally points of your buildings."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", MUTED)
	right.add_child(note)
	var why = game.to_why(order_draft, order_rally)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	var buy := _btn("Purchase order", UiKit.GOLD, func():
		var r = game.do("purchase_order", [order_draft, order_rally])
		if r == null or int(r) >= 0:   # (multiplayer: on its way)
			order_draft = {}
		_rebuild())
	if why != null:
		buy.modulate.a = 0.6
		buy.tooltip_text = why
	btns.add_child(buy)
	btns.add_child(_btn("Clear", Color("#f3d6d2"), func():
		order_draft = {}
		_rebuild()))
	right.add_child(btns)
	if why != null and n:
		var w := UiKit.ink(13)
		w.text = why
		w.add_theme_color_override("font_color", UiKit.BAD)
		right.add_child(w)
	var active := game.train_orders.filter(func(O): return not O.done or game.t - O.get("doneT", game.t) < 60)
	if not active.is_empty():
		right.add_child(_group_head("Orders"))
	for O in active:
		right.add_child(_order_row(O))
	order_key = _order_key()


func _order_unit(k: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(CARD, 1, LINE, 3))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	pc.add_child(h)
	h.add_child(_tex(hud.unit_icon(k), 34))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var nl := UiKit.ink(15)
	nl.text = game.unit_defs[k].name
	v.add_child(nl)
	var st: Dictionary = game.DSTATS.get(k, {})
	var sr := HBoxContainer.new()
	var tl := UiKit.ink(13)
	tl.add_theme_color_override("font_color", MUTED)
	tl.text = ("Ranged" if st.get("ranged", false) else ("Cavalry" if st.get("cav", false) else "Infantry")) + " ·" if not st.is_empty() else "·"
	sr.add_child(tl)
	sr.add_child(CostRow.make(game.unit_defs[k].cost, 13))
	v.add_child(sr)
	var q := HBoxContainer.new()
	q.add_theme_constant_override("separation", 4)
	h.add_child(q)
	q.add_child(_qbtn("−", func(): _order_add(k, -1)))
	var nb := UiKit.ink(16)
	nb.text = str(order_draft.get(k, 0))
	nb.custom_minimum_size = Vector2(28, 0)
	nb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.add_child(nb)
	q.add_child(_qbtn("+", func(): _order_add(k, 1)))
	q.add_child(_qbtn("+5", func(): _order_add(k, 5)))
	return pc


func _qbtn(t: String, f: Callable) -> Button:
	var b := _btn(t, Color.WHITE, f)
	b.custom_minimum_size = Vector2(34, 28)
	return b


func _order_add(k: String, d: int) -> void:
	order_draft[k] = maxi(0, order_draft.get(k, 0) + d)
	if not order_draft[k]:
		order_draft.erase(k)
	_rebuild()


func _order_row(O: Dictionary) -> PanelContainer:
	var g := game.order_progress(O)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(CARD, 1, LINE, 3))
	if O.done:
		pc.modulate.a = 0.7
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	pc.add_child(v)
	var mix := []
	for k in O.mix:
		var x: int = int(O.mix[k])
		if x:
			mix.append("%d %s" % [x, _plural(game.unit_defs[k].name) if x > 1 else game.unit_defs[k].name])
	var l := UiKit.rich(14)
	l.text = "[b]Order %d[/b]  %s → %s" % [O.id, ", ".join(mix), game.prov_name(O.rally.prov)]
	v.add_child(l)
	var s := UiKit.ink(12)
	s.add_theme_color_override("font_color", MUTED)
	s.text = "Complete" if O.done else "%d/%d trained · %d gathered" % [g.made, O.total, g.there]
	v.add_child(s)
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.step = 0.0
	pb.value = float(g.made) / maxf(1, O.total)
	pb.custom_minimum_size = Vector2(0, 6)
	pb.add_theme_stylebox_override("background", _box(Color("#e3e7ee"), 0, LINE, 0))
	pb.add_theme_stylebox_override("fill", _box(GREEN, 0, GREEN, 0))
	v.add_child(pb)
	return pc


# web: equip.js raceIs (for the Realmlings)
static func _realm(r) -> bool:
	return r == null or r == "realm" or (r is Array and r.has("realm"))


func _mine(r) -> bool:
	return Races.race_is(r, game.race())


# web: equip.js PLURAL_OF
static func _plural(n: String) -> String:
	if n.ends_with("man"):
		return n.left(-3) + "men"
	if n.ends_with("s"):
		return n
	if n.ends_with("Thief"):
		return n.left(-1) + "ves"
	return n + "s"


func _order_key() -> String:
	var st := []
	for r in ["gold", "wood", "food"]:
		st.append(floori(game.stock.get(r, 0) / 10.0))
	return "%s|%s|%s|%d|%s" % [game.to_kinds(), game.to_buildings().size(), st,
		range(game.world.provinces.size()).filter(func(p): return game.owned(p)).size(), game.train_orders.map(func(O): return [O.id, O.done, game.order_progress(O)])]


# ---------------------------------------------------------------- look

func _box(bg: Color, border: int, bc: Color, pad := 6) -> StyleBoxFlat:
	var b := UiKit.box(bg, 4, border, bc)
	b.content_margin_left = pad
	b.content_margin_right = pad
	b.content_margin_top = pad
	b.content_margin_bottom = pad
	return b


func _style(b: Button, bg: Color, border: int, bc: Color) -> void:
	for st in [["normal", bg], ["hover", bg.lightened(0.25)], ["pressed", bg.darkened(0.08)], ["focus", bg], ["disabled", bg]]:
		b.add_theme_stylebox_override(st[0], _box(st[1], border, bc, 4))


func _btn(t: String, bg: Color, f: Callable) -> Button:
	var b := UiKit.button(t, 15, f)
	_style(b, bg, 2, UiKit.INK)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, UiKit.INK)
	b.custom_minimum_size = Vector2(0, 32)
	return b


func _tab_style(b: Button, on: bool) -> void:
	_style(b, UiKit.GOLD if on else Color("#eef2f7"), 1, UiKit.INK)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, UiKit.INK if on else MUTED)
	b.custom_minimum_size = Vector2(0, 30)


func _ready() -> void:
	if game == null:
		hide()


func _process(_dt: float) -> void:
	if game == null or not visible:
		return
	if mode == 0 and _key() != key:
		_rebuild()
	elif mode == 1 and _order_key() != order_key:
		_rebuild()
