class_name Roster
extends PanelContainer
## The outliner, top right: three tabs. Workers (your Wayfinders and Masons), Provinces (yours, with their plots
## built), Armies (your armies, Mages, Barracks and Mage Towers). Sections fold away; a click selects, a double-click
## goes there. web: game.js renderRoster, myProvList, unitStatus; features.js armiesTabHTML, barracksSec, towersSec;
## v96.js roHead / roToggle

const INK := Color("#1d1a22")
const CHIP := Color("#efdcb3")
const CHIP_HI := Color("#faf1dc")
const SUN := Color("#ffc93c")
const MUTED := Color("#5a6475")
const TER_TEXT := {"grassland": "#4d7f12", "forest": "#16543a", "desert": "#b0600f", "swamp": "#6b4a8e"}
const W := 280.0

var game: Game
var hud
var box: VBoxContainer
var tabs_row: HBoxContainer
var scroll: ScrollContainer
var list: VBoxContainer
var key := ""


func setup(g: Game, h) -> void:
	game = g
	hud = h
	key = ""
	if box != null:   # (a new game reuses the list; a second one would be drawn over the first)
		return
	add_theme_stylebox_override("panel", _sb(CHIP, 2, 4, 6))
	custom_minimum_size = Vector2(W, 0)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	tabs_row = HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 4)
	box.add_child(tabs_row)
	var line := ColorRect.new()
	line.color = Color(INK, 0.15)
	line.custom_minimum_size = Vector2(0, 2)
	box.add_child(line)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)


static func _sb(bg: Color, border := 0, radius := 9, pad := 0, border_col := INK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border_col
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


func _workers() -> Array:
	return game.units.filter(func(u): return u.owner == Game.ME and (u.kind == game.WAYFINDER or u.kind == Game.MASON))


## web: game.js myProvList (forts and capitals first, then by name)
func _my_provs() -> Array:
	var out := []
	for p in game.buildings:
		if game.buildings[p].owner == Game.ME:
			out.append(p)
	out.sort_custom(func(a, b):
		var sa: int = game.buildings[a].stage
		var sb: int = game.buildings[b].stage
		return sa > sb if sa != sb else game.prov_name(a) < game.prov_name(b))
	return out


func _armies() -> Array:
	return game.units.filter(func(v): return v.kind == "army" and v.owner == Game.ME)


func status_of(u: Dictionary) -> String:
	return hud._status(u) if hud else "idle"


## web: features.js armyStatus
func army_status(a: Dictionary) -> String:
	if a.get("battle") != null and not a.get("retreating", false):
		return "in battle"
	if a.get("retreatHome"):
		return "retreating home"
	if a.get("retreating", false):
		return "retreating"
	if a.get("exiting"):
		return "marching home"
	if a.get("sieging") != null:
		return "battering a wall"
	if a.get("retro") != null:
		return "retrofitting"
	if a.get("rest") != null:
		return "resting"
	return "marching" if a.moving else "standing"


func _process(_dt: float) -> void:
	if game == null:
		return
	var tab: String = Settings.roster_tab
	var k := tab + "#" + str(Settings.roster_folded) + "#" + str(Settings.view.hideFull) + "#" + _sig(tab)
	if k != key:
		key = k
		_rebuild(tab)
	# fit the list between the map buttons and the command card
	var vh := get_viewport_rect().size.y
	var maxh := maxf(120.0, vh - offset_top - 300.0 - 70.0)
	scroll.custom_minimum_size = Vector2(W - 12, minf(list.get_combined_minimum_size().y, maxh))
	reset_size()


func _sig(tab: String) -> String:
	var sel = hud.unit if hud else null
	var out := "%d:%d:%d|" % [_workers().size(), _my_provs().size(), _armies().size()]
	if tab == "units":
		for u in _workers():
			out += "%d%s%s%d%s|" % [u.id, u.name, status_of(u), u.prov, "*" if is_same(u, sel) else ""]
	elif tab == "provs":
		for p in _my_provs():
			out += "%d%s:%d:%d|" % [p, game.prov_name(p), game.buildings[p].stage, game.extras_in(p).size()]
		out += str(hud.prov if hud else -1)
	else:
		for a in game.units:
			if a.owner == Game.ME and (a.kind == "army" or a.kind == game.MAGE):
				out += "%d%s:%d:%s:%s:%d%s|" % [a.id, a.name, game.troop_count(a) if a.kind == "army" else 0, army_status(a) if a.kind == "army" else status_of(a), a.prov,
					int(game.raw_strength([a]) * 10) if a.kind == "army" else 0, "*" if is_same(a, sel) else ""]
		for p in game.extras:
			if game.owned(p):
				for e in game.extras[p]:
					if e.type in ["barracks", "magetower"]:
						out += "%d%s%d:%d|" % [p, e.type, e.get("level", 1), game.queues.get("%s:%d" % [e.type, p], []).size()]
		out += (hud.part + str(hud.prov)) if hud else ""
	return out


func _rebuild(tab: String) -> void:
	UiKit.clear(tabs_row)
	for t in [["units", "Workers", _workers().size(), ""], ["provs", "Provinces", _my_provs().size(), "Your provinces: buildings built / building plots"], ["armies", "Armies", _armies().size(), "Your armies"]]:
		var b := Button.new()
		b.text = "%s %d" % [t[1], t[2]]
		b.tooltip_text = t[3]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, _sb(SUN if t[0] == tab else Color("#dcc493"), 2, 8, 3))
		for st in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(st, INK)
		var id: String = t[0]
		b.pressed.connect(func():
			Settings.roster_tab = id
			Settings.save_all())
		tabs_row.add_child(b)
	UiKit.clear(list)
	if tab == "provs":
		_provs_tab()
	elif tab == "armies":
		_armies_tab()
	else:
		for kind in [game.WAYFINDER, Game.MASON]:
			var us := _workers().filter(func(u): return u.kind == kind)
			var nm: String = str(game.unit_defs[kind].name) + "s"
			if _head("u:" + kind, nm, str(us.size())):
				if us.is_empty():
					_none("None yet")
				for u in us:
					var st := status_of(u)
					_row(hud.unit_icon(u.kind), u.name, st, st != "idle", "%s · %s" % [st, game.prov_name(u.prov) if game.explored.has(u.prov) else "fog"],
						is_same(u, hud.unit), _pick_unit.bind(u), _go_unit.bind(u), "Click to select, double-click to go to")


## A section's head with its fold button; returns whether it is open. web: v96.js roHead
func _head(k: String, title: String, count: String, tip := "", full := false) -> bool:
	var open := not Settings.roster_folded.has(k)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = tip
	var fb := Button.new()
	fb.text = "−" if open else "+"
	fb.focus_mode = Control.FOCUS_NONE
	fb.custom_minimum_size = Vector2(20, 20)
	fb.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed"]:
		fb.add_theme_stylebox_override(st, _sb(CHIP_HI, 1, 3, 0))
	fb.add_theme_color_override("font_color", INK)
	fb.add_theme_color_override("font_hover_color", INK)
	fb.tooltip_text = ("Hide " if open else "Show ") + title.to_lower()
	fb.pressed.connect(func():
		if Settings.roster_folded.has(k):
			Settings.roster_folded.erase(k)
		else:
			Settings.roster_folded.append(k)
		Settings.save_all())
	row.add_child(fb)
	var l := Label.new()
	l.text = title.to_upper() + "  " + count
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#b8321f") if full else MUTED)
	row.add_child(l)
	list.add_child(row)
	return open


func _none(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", MUTED)
	list.add_child(l)


## A row: portrait, name, a status dot and line, an optional power chip. web: .ro-u
func _row(tex: Texture2D, name: String, _st: String, busy: bool, small: String, on: bool, click: Callable, dbl: Callable, tip: String, dot := Color.TRANSPARENT, pow := "") -> void:
	var p := PanelContainer.new()
	var normal := _sb(SUN if on else CHIP_HI, 2, 9, 2, INK if on else Color(0, 0, 0, 0))
	var hov := _sb(SUN if on else Color("#fff7d9"), 2, 9, 2)
	p.add_theme_stylebox_override("panel", normal)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.tooltip_text = tip
	p.mouse_entered.connect(func(): p.add_theme_stylebox_override("panel", hov))
	p.mouse_exited.connect(func(): p.add_theme_stylebox_override("panel", normal))
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.double_click:
				dbl.call()
			else:
				click.call()
			p.accept_event())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var ic := TextureRect.new()
	ic.texture = tex
	ic.custom_minimum_size = Vector2(40, 40)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var nl := Label.new()
	nl.text = name
	nl.add_theme_font_override("font", Fonts.names)   # web: .ro-u b (Grenze Gotisch; Alegreya SemiBold here)
	nl.add_theme_font_size_override("font_size", 18)
	nl.add_theme_color_override("font_color", INK)
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 4)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sh)
	var d := Control.new()
	d.custom_minimum_size = Vector2(8, 14)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dc := dot if dot.a > 0 else (Color("#3e9b4f") if busy else Color("#e8a817"))
	d.draw.connect(func(): d.draw_circle(Vector2(4, 8), 3.5, dc))
	sh.add_child(d)
	var sl := Label.new()
	sl.text = small
	sl.clip_text = true
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sl.custom_minimum_size = Vector2(W - 120 if pow != "" else W - 80, 0)
	sl.add_theme_font_size_override("font_size", 13)
	sl.add_theme_color_override("font_color", INK if on else MUTED)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(sl)
	if pow != "":
		var pl := Label.new()
		pl.text = pow
		pl.tooltip_text = "Army power"
		pl.add_theme_font_size_override("font_size", 13)
		pl.add_theme_color_override("font_color", INK)
		pl.add_theme_stylebox_override("normal", _sb(Color("#f3e4c4"), 1, 0, 3))
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(pl)
	list.add_child(p)


func _provs_tab() -> void:
	var provs := _my_provs()
	var full := func(p): return game.extras_in(p).size() >= game.plot_cap(p)
	var n_full := provs.filter(full).size()
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	var hb := Button.new()
	hb.text = ("☑" if Settings.view.hideFull else "☐") + " Hide full" + ((" %d" % n_full) if n_full else "")
	hb.tooltip_text = "Hide provinces whose building plots are all built"
	hb.focus_mode = Control.FOCUS_NONE
	hb.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed"]:
		hb.add_theme_stylebox_override(st, _sb(SUN if Settings.view.hideFull else CHIP_HI, 1, 0, 3))
	hb.add_theme_color_override("font_color", INK)
	hb.add_theme_color_override("font_hover_color", INK)
	hb.pressed.connect(func():
		Settings.view.hideFull = not Settings.view.hideFull
		Settings.save_all())
	bar.add_child(hb)
	list.add_child(bar)
	if not _head("provs", "Provinces", str(provs.size())):
		return
	var shown := provs.filter(func(p): return not full.call(p)) if Settings.view.hideFull else provs
	if shown.is_empty():
		_none("Every province is full" if not provs.is_empty() else "No provinces yet")
	for p in shown:
		var n := game.extras_in(p).size()
		var cap := game.plot_cap(p)
		var t: String = game.G.provs[p].terrain
		var st: int = game.buildings[p].stage
		var on: bool = hud.prov == p and hud.unit == null
		var r := PanelContainer.new()
		var normal := _sb(CHIP_HI, 2, 8, 4, INK if on else Color(0, 0, 0, 0))
		var hov := _sb(Color("#fff7d9"), 2, 8, 4)
		r.add_theme_stylebox_override("panel", normal)
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		r.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		r.tooltip_text = "%s · %s %s · %d of %d plots built%s. Click to open, double-click to go there." % [game.prov_name(p), t.capitalize(), hud.STAGE_NAME[st].to_lower(), n, cap, (" (%d empty)" % (cap - n)) if n < cap else ""]
		r.mouse_entered.connect(func(): r.add_theme_stylebox_override("panel", hov))
		r.mouse_exited.connect(func(): r.add_theme_stylebox_override("panel", normal))
		r.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.double_click:
					hud.look_at_prov(p)
				else:
					_pick_prov(p)
				r.accept_event())
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(h)
		var nl := Label.new()
		nl.text = game.prov_name(p)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		nl.add_theme_font_override("font", Fonts.names)
		nl.add_theme_font_size_override("font_size", 18)
		nl.add_theme_color_override("font_color", Color(TER_TEXT.get(t, "#1d1a22")))
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(nl)
		if st > 0:
			var sl := Label.new()
			sl.text = str(hud.STAGE_NAME[st]).to_upper()
			sl.add_theme_font_size_override("font_size", 11)
			sl.add_theme_color_override("font_color", MUTED)
			sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(sl)
		var el := Label.new()
		el.text = " %d/%d" % [n, cap]
		el.add_theme_font_size_override("font_size", 17)
		el.add_theme_color_override("font_color", Color("#1f7a2e") if n >= cap else Color("#b3261e"))
		el.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(el)
		list.add_child(r)


func _armies_tab() -> void:
	var armies := _armies()
	var MN: String = game.unit_defs[game.MAGE].name
	if _head("armies", "Armies", str(armies.size())):
		if armies.is_empty():
			_none("No armies yet")
		for a in armies:
			var m: int = a.troops.get(game.MAGE, 0)
			var pk: String = game.MAGE if m else "army"
			for k in a.troops:
				if a.troops[k] > 0 and k != game.MAGE:
					pk = k
					break
			var inb: bool = a.get("battle") != null
			var small := "%d%s · %s · %s" % [game.troop_count(a) - m, (" + %d %s" % [m, MN + ("s" if m > 1 else "")]) if m else "", army_status(a), game.prov_name(a.prov) if game.explored.has(a.prov) else "fog"]
			_row(hud.unit_icon(pk), a.name, "", not inb, small, is_same(a, hud.unit), _pick_unit.bind(a), _go_unit.bind(a), "Click to select, double-click to go to",
				Color("#c7362b") if inb else Color.TRANSPARENT, "⚔ " + UiKit.num(maxf(1, roundf(game.raw_strength([a]) * 10))))
	var mages := game.units.filter(func(v): return v.kind == game.MAGE and v.owner == Game.ME)
	var in_armies := 0
	for a in armies:
		in_armies += a.troops.get(game.MAGE, 0)
	var total := game.unit_total(game.MAGE)
	var cap := game.unit_limit(game.MAGE)
	if _head("mages", MN + "s", "%d/%d" % [total, cap], "%ss you have, counting those in armies and in training, out of the %s limit." % [MN, MN], total >= cap):
		for u in mages:
			var st := "casting" if u.get("cast") != null else "walking" if u.moving else "idle"
			_row(hud.unit_icon(game.MAGE), u.name, st, st != "idle", "%s · %s" % [st, game.prov_name(u.prov) if game.explored.has(u.prov) else "fog"], is_same(u, hud.unit), _pick_unit.bind(u), _go_unit.bind(u), "Click to select, double-click to go to")
		if in_armies:
			_none("%d in armies" % in_armies)
		if mages.is_empty() and in_armies == 0:
			_none("None yet")
	for kind in ["barracks", "magetower"]:
		var rows := []
		for p in game.extras:
			if game.owned(p):
				for e in game.extras[p]:
					if e.type == kind:
						rows.append([p, e])
		var D: Dictionary = game.BUILD_DEFS[kind]
		if not _head(kind, str(D.name) + ("" if kind == "barracks" else "s"), str(rows.size())):
			continue
		if rows.is_empty():
			_none("None yet")
		for r in rows:
			var p: int = r[0]
			var e: Dictionary = r[1]
			var Q: Array = game.queues.get("%s:%d" % [kind, p], [])
			var lv: int = e.get("level", 1)
			var what: String = ("infantry and cavalry" if game.extras_in(p).any(func(x): return x.type == "stable") else "infantry") if kind == "barracks" else str(D.levels[lv - 1])
			var tex: Texture2D = hud.icon("icons/realm/build_%s.png" % kind) if kind == "barracks" else hud.icon("icons/realm/build_magetower_l%d.png" % lv)
			var on: bool = hud.prov == p and hud.part == "%s@%d" % [kind, e.slot] and hud.unit == null
			_row(tex, game.prov_name(p), "", not Q.is_empty(), "%s · %s" % [("training %d" % Q.size()) if not Q.is_empty() else "idle", what], on,
				_pick_part.bind(p, "%s@%d" % [kind, e.slot]), hud.look_at_prov.bind(p, false), "Click to select and train, double-click to go to")


func _pick_unit(u: Dictionary) -> void:
	hud.select_unit(u)
	if hud.map:
		hud.map.selected_unit = u
		hud.map.selected_prov = u.prov
	hud.select_province(u.prov)


func _go_unit(u: Dictionary) -> void:
	hud.focus_unit(u)


func _pick_prov(p: int) -> void:
	var off: bool = hud.prov == p and hud.unit == null and hud.part == ""
	hud.select_unit(null)
	if hud.map:
		hud.map.selected_unit = null
		hud.map.selected_prov = -1 if off else p
	hud.select_province(-1 if off else p)


func _pick_part(p: int, part: String) -> void:
	hud.select_unit(null)
	if hud.map:
		hud.map.selected_unit = null
		hud.map.selected_prov = p
	hud.select_province(p, part)
