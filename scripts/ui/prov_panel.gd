class_name ProvPanel
extends PanelContainer
## The province menu, bottom left over the minimap: name, terrain and owner; its resources with what buildings add;
## development and Develop Province (or Build Outpost on free land); the research it makes; tags (Hidden Gold
## Deposit, tree borders, coast, set piece, bandits); and its building plots: the settlement, each building (click to
## select it) and empty plots (click to build there). web: game.js provMenu, partInfo, openPlotMenu;
## v106.js provDevHTML; content.js provResearchRow, setpieceTag, setpieceNote, banditTag; v104.js partInfo (crops)

const INK := Color("#1d1a22")
const MUTED := Color("#5a6475")
const CHIP := Color("#efdcb3")
const CHIP_HI := Color("#faf1dc")
const W := 330.0
const TER := {"grassland": ["#9bd95f", "Grassland"], "forest": ["#3f9b4b", "Forest"], "desert": ["#e8c26a", "Desert"], "swamp": ["#7c9a6a", "Swamp"], "mountains": ["#9a9aa8", "Mountains"]}
const TREE_NAME := {"gov": "Government", "mil": "Military", "mag": "Magic"}

var hud
var game: Game
var col: VBoxContainer
var body: VBoxContainer
var actions: VBoxContainer   # the HUD's own rows (Mason links, Mage paths) at the bottom
var key := ""
var p := -1


func _init() -> void:
	add_theme_stylebox_override("panel", Roster._sb(CHIP, 2, 4, 8))
	custom_minimum_size = Vector2(W, 0)
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	add_child(col)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	col.add_child(body)
	actions = VBoxContainer.new()
	col.add_child(actions)
	mouse_filter = Control.MOUSE_FILTER_STOP


func refresh(h, g: Game, prov: int) -> void:
	hud = h
	game = g
	p = prov
	if p < 0:
		return
	var k := _key()
	if k == key:
		return
	key = k
	UiKit.clear(body)
	_build()
	reset_size()


func _key() -> String:
	var vis: bool = game.visible.has(p)
	var b = game.buildings.get(p) if vis else null
	var out := [p, game.prov_name(p), hud.part, vis, b.stage if b else -1, game.upgrades.has(p), game.surveyed.has(p), game.occ.get(p), b.owner if b else 0, game.income]
	if vis:
		for e in game.extras_in(p):
			out.append("%s%d%s%s" % [e.type, e.get("level", 1), e.get("crop", ""), e.get("cropNext", "")])
		for v in game.sites_in(p):
			out.append(v.build.type + str(v.build.get("slot")))
		for v in game.pending_in(p):
			out.append(v.pending.type + str(v.pending.get("slot")))
	var dr = game.dev_rec(p)
	out.append([dr.lv, int(dr.job.done) if dr.job != null else -1] if dr != null else null)
	out.append(game.dev_why(p) if b != null and b.owner == Game.ME else game.outpost_btn_why(p))
	out.append(game.prov_research(p) if game.owned(p) else null)
	out.append([game.sp_known(p), game.setpiece_why(p)])
	out.append(game.units.filter(func(v): return v.get("bandit", false) and v.get("seen", false) and v.prov == p).size())
	out.append(game.free_masons().size())
	return str(out)


static func _lbl(t: String, sz: int, c := INK) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _tex(t: Texture2D, sz: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.custom_minimum_size = Vector2(sz, sz)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _clickable(c: Control, f: Callable, tip := "") -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.tooltip_text = tip
	c.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			c.accept_event()
			f.call())


func _build() -> void:
	var P: Dictionary = game.G.provs[p]
	var T: Array = TER.get(P.terrain, ["#cccccc", str(P.terrain).capitalize()])
	var vis: bool = game.visible.has(p)
	var b = game.buildings.get(p) if vis else null
	var y: Dictionary = game.yields[p]
	var surveyed: bool = game.surveyed.has(p)
	# the head: swatch, name, terrain, owner, close
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var sw := ColorRect.new()
	sw.color = Color(T[0])
	sw.custom_minimum_size = Vector2(16, 16)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sw)
	head.add_child(_lbl(game.prov_name(p), 22))
	var rn := Button.new()
	rn.text = "✎"
	rn.focus_mode = Control.FOCUS_NONE
	rn.tooltip_text = "Rename this province"
	rn.custom_minimum_size = Vector2(26, 26)
	rn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for st in ["normal", "hover", "pressed"]:
		rn.add_theme_stylebox_override(st, Roster._sb(CHIP_HI, 1, 4, 0))
	rn.add_theme_color_override("font_color", INK)
	rn.add_theme_color_override("font_hover_color", INK)
	rn.pressed.connect(func(): hud.renamer.open(game, "prov:%d" % p))
	head.add_child(rn)
	var tl := _lbl(T[1], 13, MUTED)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var x := Button.new()
	x.text = "×"
	x.focus_mode = Control.FOCUS_NONE
	x.custom_minimum_size = Vector2(26, 26)
	x.tooltip_text = "Close province menu"
	for st in ["normal", "hover", "pressed"]:
		x.add_theme_stylebox_override(st, Roster._sb(CHIP_HI, 2, 6, 0))
	x.add_theme_color_override("font_color", INK)
	x.add_theme_color_override("font_hover_color", INK)
	x.pressed.connect(func():
		if hud.map:
			hud.map.selected_prov = -1
		hud.select_province(-1))
	head.add_child(x)
	body.add_child(head)
	var own := HBoxContainer.new()
	own.add_theme_constant_override("separation", 5)
	if b != null:
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var oc := Color(game.player_info(b.owner).color)
		dot.draw.connect(func(): dot.draw_circle(Vector2(6, 6), 5.5, oc))
		own.add_child(dot)
		own.add_child(_lbl("%s%s" % [game.player_info(b.owner).name, " (you)" if b.owner == Game.ME else ""], 14, MUTED))
	else:
		own.add_child(_lbl("Unclaimed" if vis else "Owner unknown", 14, MUTED))
	body.add_child(own)
	# occupied
	var occ_by = game.occ.get(p)
	if occ_by != null:
		var ol := _lbl("Occupied by %s · %s" % ["you" if occ_by == Game.ME else "the " + str(game.player_info(occ_by).name), "pays you nothing" if b != null and b.owner == Game.ME else "pays its owner nothing"], 13, Color("#b3261e"))
		ol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ol.custom_minimum_size = Vector2(W - 20, 0)
		body.add_child(ol)
	# resources: what the land gives, + what buildings (and a capital) add
	if not surveyed:
		var nl := _lbl("Resources unknown", 14, MUTED)
		nl.tooltip_text = "Survey it with a Wayfinder to learn its resources"
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		body.add_child(nl)
	else:
		var xb: Dictionary = game.extras_bonus(p) if b != null else {"gold": 0, "wood": 0, "food": 0}
		var cap: bool = b != null and (b.stage == 2 or b.get("cc", false))
		var res := HBoxContainer.new()
		res.add_theme_constant_override("separation", 12)
		for k in CostRow.ORDER:
			var add: int = int(xb[k] + (game.CAPITAL_BONUS[k] if cap else 0))
			var c := HBoxContainer.new()
			c.add_theme_constant_override("separation", 2)
			c.add_child(_tex(CostRow.icon(k), 22))
			c.add_child(_lbl(str(int(y[k])), 18, Color("#1f7a2e") if y.get("bonus", {}).get(k, 0) else INK))
			if add:
				c.add_child(_lbl("+%d" % add, 13, Color("#1f7a2e")))
			c.tooltip_text = "%s: %d from the land%s" % [k.capitalize(), y[k], (", +%d from buildings" % add) if add else ""]
			c.mouse_filter = Control.MOUSE_FILTER_PASS
			res.add_child(c)
		body.add_child(res)
	_dev_section(b, vis)
	# research made here
	if game.owned(p) and vis:
		var r: Dictionary = game.prov_research(p)
		var rr := HBoxContainer.new()
		rr.add_theme_constant_override("separation", 8)
		rr.tooltip_text = "Research points this province makes every 10 s"
		rr.mouse_filter = Control.MOUSE_FILTER_PASS
		rr.add_child(_lbl("RESEARCH", 12, MUTED))
		for t in ["gov", "mil", "mag"]:
			var g := Glyph.make("tree_" + t, 18, Glyph.TREE_COL["tree_" + t])
			g.set_value(1.0 if r.get(t, 0) else 0.0)
			rr.add_child(g)
			rr.add_child(_lbl(str(r.get(t, 0)), 15, INK if r.get(t, 0) else MUTED))
		body.add_child(rr)
	# tags
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 5)
	tags.add_theme_constant_override("v_separation", 4)
	if y.get("deposit", false) and surveyed:
		tags.add_child(_tag("Hidden Gold Deposit", Color("#ffe7a3")))
	var tb: int = game.tree_border[p]
	if tb:
		tags.add_child(_tag("%d tree border%s" % [tb, "s" if tb > 1 else ""]))
	if P.get("coastal", false):
		tags.add_child(_tag("Coastal"))
	if P.get("lakeside", false):
		tags.add_child(_tag("Lakeside"))
	if game.setpieces.has(p) and game.explored.has(p) and game.sp_known(p):
		var D: Dictionary = game.SETPIECES[game.setpieces[p]]
		var why = game.setpiece_why(p)
		var st := _tag("%s +%d" % [D.name, D.pts], Color("#e6e9ef") if why != null else Color("#e9f6d9"))
		st.tooltip_text = "%s: +%d %s research every 10 s%s" % [D.name, D.pts, TREE_NAME[D.tree], (" (%s)" % why) if why != null else ""]
		tags.add_child(st)
	var bt = _bandit_tag()
	if bt != null:
		tags.add_child(bt)
	if tags.get_child_count():
		body.add_child(tags)
	if game.setpieces.has(p) and game.explored.has(p) and game.sp_known(p):
		var D: Dictionary = game.SETPIECES[game.setpieces[p]]
		var why = game.setpiece_why(p)
		var note := _lbl("%s. %s Gives +%d %s research every 10 s while you hold it%s. %s" % [D.name, D.get("blurb", ""), D.pts, TREE_NAME[D.tree], (" and own " + str(D.need) + " (or its upgrades)") if D.get("need") else "", ("Inactive: %s." % why) if why != null else "Active."], 13, MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(W - 20, 0)
		body.add_child(note)
	# buildings
	var ex := game.extras_in(p) if vis else []
	body.add_child(_lbl("BUILDINGS" + ("  %d/%d" % [ex.size(), game.plot_cap(p)] if b != null else ""), 12, MUTED))
	if not vis:
		var hl := _lbl("Hidden", 14, MUTED)
		hl.tooltip_text = "Send a unit here to see what is built"
		hl.mouse_filter = Control.MOUSE_FILTER_PASS
		body.add_child(hl)
	elif b == null:
		var nl := _lbl("No settlement", 14, MUTED)
		nl.tooltip_text = "A Mason can build an outpost here once it is surveyed and borders your land"
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		body.add_child(nl)
	else:
		var si := part_info("settlement", null)
		body.add_child(_slot("settlement", si, "trains units" if b.stage == 2 else "", true))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 5)
		grid.add_theme_constant_override("v_separation", 5)
		var sites := game.sites_in(p)
		var pend := game.pending_in(p)
		for i in game.plot_cap(p):
			var e = null
			for v in ex:
				if v.slot == i:
					e = v
			var s2 = null
			for v in sites:
				if v.build.get("slot") == i:
					s2 = v
			var pd = null
			for v in pend:
				if v.pending.get("slot") == i:
					pd = v
			if e != null:
				grid.add_child(_slot("%s@%d" % [e.type, e.slot], part_info(e.type, e), ""))
			elif s2 != null:
				grid.add_child(_busy(s2.build.type, "building…"))
			elif pd != null:
				grid.add_child(_busy(pd.pending.type, "%s on the way" % game.unit_defs[Game.MASON].name))
			elif b.owner == Game.ME:
				grid.add_child(_empty(i, true))
			else:
				grid.add_child(_empty(i, false))
		body.add_child(grid)
		if hud.part != "" and vis:
			var info := part_info(hud.part.split("@")[0] if hud.part != "settlement" else "settlement", hud.part_extra())
			var sl := _lbl("%s · %s" % [info.name, info.desc], 13, INK)
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sl.custom_minimum_size = Vector2(W - 20, 0)
			body.add_child(sl)


func _tag(t: String, bg := Color("#eef2f7")) -> Label:
	var l := _lbl(t, 12)
	l.add_theme_stylebox_override("normal", Roster._sb(bg, 1, 0, 3))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## web: content.js banditTag
func _bandit_tag():
	var list := game.units.filter(func(v): return v.get("bandit", false) and v.get("seen", false) and v.prov == p and game.troop_count(v) > 0)
	if list.is_empty():
		return null
	var n := 0
	for v in list:
		n += game.troop_count(v)
	var mon = null
	for v in list:
		if v.get("monster") != null:
			mon = v
	var t := "Bandit Gang · %d soldier%s · %d gold bounty" % [n, "s" if n > 1 else "", GameData.c("BANDIT").bounty]
	var tip := "Hostile to everyone. Wayfinders can’t enter until they are beaten."
	if mon != null and mon.get("boss"):
		var B: Dictionary = GameData.c("BOSSES")[mon.boss]
		t = "%s · power %s" % [B.get("short", mon.boss), B.get("power", "?")]
		tip = "A boss. Wayfinders can’t enter until it is beaten."
	elif mon != null:
		var parts := []
		for k in mon.troops:
			parts.append("%d %s" % [mon.troops[k], game.unit_defs[k].name if game.unit_defs.has(k) else k])
		t = ", ".join(parts)
	var l := _tag(t, Color("#f6d4d4"))
	l.tooltip_text = tip
	return l


## Name, picture and what a part does. web: game.js partInfo (+ v104.js the Farm's crop)
func part_info(part: String, e) -> Dictionary:
	if part == "settlement":
		var b: Dictionary = game.buildings[p]
		var st: int = b.stage
		if b.get("cc", false):
			return {"name": "Conquered Capital", "img": hud.icon("icons/realm/settle_2.png"), "desc": "A capital taken in war. +%d of each resource. 6 building plots." % game.CAPITAL_BONUS.gold}
		var desc: String = ("Trains %ss and %ss. +%d of each resource. 6 building plots." % [game.unit_defs[game.WAYFINDER].name, game.unit_defs[Game.MASON].name, game.CAPITAL_BONUS.gold]) if st == 2 \
			else "A stone fort. 4 building plots." if st == 1 else "Claims the province. 2 building plots; upgrade to a Fort for 4."
		return {"name": hud.STAGE_NAME[st], "img": hud.icon("icons/realm/settle_%d.png" % st), "desc": desc}
	var d: Dictionary = game.BUILD_DEFS[part]
	if d.has("levels"):
		var lv: int = e.get("level", 1) if e != null else 1
		return {"name": d.levels[lv - 1], "img": hud.icon("icons/realm/build_%s_l%d.png" % [part, lv]),
			"desc": "%s research Tier %s · +%d points every 10 s%s" % ["Military" if part == "forge" else "Magic", ["", "I", "II", "III"][lv], [0, 2, 4, 6][lv], " · select to upgrade" if lv < 3 else ""]}
	if part == "farm" and e != null:
		var c := Ai.crop_of(e)
		var g := Ai.crop_gives(c, game.gives_of("farm"))
		var up := Ai.crop_up(game, c)
		var line := ", ".join(g.keys().map(func(k): return "+%d %s" % [g[k], k])) + ((", %d wood upkeep" % up) if up else ", no upkeep")
		return {"name": "Farm: " + Ai.crop_name(c), "img": hud.icon("icons/common/ui_crop_%s.png" % c),
			"desc": "%s: %s every 10 s%s" % [Ai.CROP_KIND[c], line, (" · switching to %s in %d s" % [Ai.crop_name(e.cropNext), maxi(0, ceili(e.cropAt - game.t))]) if e.has("cropNext") else ""]}
	var desc2 := ""
	if d.get("store") != null:
		desc2 = str(d.get("note", ""))
	elif d.get("gives") != null:
		var gv := game.gives_of(part)
		desc2 = ", ".join(gv.keys().map(func(k): return "+%d %s" % [gv[k], k])) + " every 10 s"
	elif part == "barracks":
		desc2 = "Trains infantry and cavalry" if game.extras_in(p).any(func(x): return x.type == "stable") else "Trains infantry"
	elif part == "stable":
		desc2 = "Lets this province’s Barracks train cavalry"
	return {"name": d.name, "img": hud.icon("icons/realm/build_%s.png" % part), "desc": desc2}


## A building's button: picture and name; click to select it. web: .pm-b
func _slot(part: String, info: Dictionary, small: String, wide := false) -> Control:
	var on: bool = hud.part == part
	var c := PanelContainer.new()
	var normal := Roster._sb(Color("#ffc93c") if on else CHIP_HI, 2, 8, 2)
	var hov := Roster._sb(Color("#ffc93c") if on else Color("#fff7d9"), 2, 8, 2)
	c.add_theme_stylebox_override("panel", normal)
	c.mouse_entered.connect(func(): c.add_theme_stylebox_override("panel", hov))
	c.mouse_exited.connect(func(): c.add_theme_stylebox_override("panel", normal))
	c.custom_minimum_size = Vector2(W - 20 if wide else (W - 25) / 2, 42)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(h)
	h.add_child(_tex(info.img, 38))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nl := _lbl(info.name, 14)
	nl.clip_text = true
	nl.custom_minimum_size = Vector2((W - 20 if wide else (W - 25) / 2) - 50, 0)
	v.add_child(nl)
	if small != "":
		v.add_child(_lbl(small, 11, MUTED))
	h.add_child(v)
	_clickable(c, func():
		hud.select_unit(null)
		if hud.map:
			hud.map.selected_unit = null
			hud.map.selected_prov = p
		hud.select_province(p, part), "%s: %s" % [info.name, info.desc])
	return c


func _busy(type: String, small: String) -> Control:
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", Roster._sb(Color("#eef2f7"), 2, 8, 2, Color(INK, 0.4)))
	c.custom_minimum_size = Vector2((W - 25) / 2, 42)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	c.add_child(h)
	var t := _tex(hud.icon("icons/realm/build_%s.png" % type), 38)
	t.modulate = Color(1, 1, 1, 0.6)
	h.add_child(t)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -3)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(_lbl(str(game.BUILD_DEFS[type].name) if game.BUILD_DEFS.has(type) else type, 13))
	v.add_child(_lbl(small, 11, MUTED))
	h.add_child(v)
	return c


func _empty(slot: int, open: bool) -> Control:
	var c := PanelContainer.new()
	var normal := Roster._sb(CHIP_HI if open else Color(0, 0, 0, 0.05), 0, 8, 2)
	c.add_theme_stylebox_override("panel", normal)
	c.custom_minimum_size = Vector2((W - 25) / 2, 42)
	var l := _lbl("＋ Empty plot" if open else "Empty plot", 13, INK if open else MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(l)
	c.draw.connect(func():
		var r := Rect2(Vector2(1, 1), c.size - Vector2(2, 2))
		for s in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end], [r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
			c.draw_dashed_line(s[0], s[1], Color(INK, 0.45), 1.5, 5.0))
	if open:
		var hov := Roster._sb(Color("#fff7d9"), 0, 8, 2)
		c.mouse_entered.connect(func(): c.add_theme_stylebox_override("panel", hov))
		c.mouse_exited.connect(func(): c.add_theme_stylebox_override("panel", normal))
		_clickable(c, func(): hud.open_plot_menu(p, slot, c), "Click to build something on this plot")
	return c


## Development level and Develop Province, or Build Outpost on free land. web: v106.js provDevHTML
func _dev_section(b, vis: bool) -> void:
	if b == null:
		if not vis and not game.explored.has(p):
			return
		var why := game.outpost_btn_why(p)
		var m = game.nearest_mason(p)
		var small: String = why if why != "" else ((m.name + " is here") if m != null and m.prov == p else ("Sends " + m.name + ", the closest") if m != null else "")
		body.add_child(_dev_btn(hud.icon("icons/common/cmd_build_outpost.png"), "Build Outpost", small, GameData.c("OUTPOST_COST"), why, func():
			var mm = game.nearest_mason(p)
			if mm != null and game.outpost_btn_why(p) == "":
				mm.surveyQueue = []
				game.order_build(mm, p, "outpost")))
		return
	var r = game.dev_rec(p)
	var lv: int = r.lv if r != null else 0
	var DV: Dictionary = GameData.c("DEV")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_lbl("Development", 13, MUTED))
	row.add_child(_lbl("Level %d/%d" % [lv, DV.max], 13))
	for i in DV.max:
		var pip := Control.new()
		pip.custom_minimum_size = Vector2(14, 14)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var filled: bool = i < lv
		pip.draw.connect(func():
			var c := Vector2(7, 7)
			var dia := PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)])
			pip.draw_colored_polygon(dia, Color("#7ac74f") if filled else Color("#eef2f7"))
			dia.append(dia[0])
			pip.draw_polyline(dia, INK, 1.2, true))
		row.add_child(pip)
	if r != null and r.get("deep", false):
		row.add_child(_tag("Deep Gold", Color("#ffe7a3")))
	row.tooltip_text = ("From development: +%d gold, +%d wood, +%d food" % [r.add.gold, r.add.wood, r.add.food]) if r != null and lv else "Not developed yet"
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(row)
	if b.owner != Game.ME:
		return
	if r != null and r.job != null:
		var small := "Stalled: hostile soldiers here" if r.job.get("stall", false) else "%d s left" % ceili(DV.time - r.job.done)
		var c := _dev_btn(hud.icon("icons/common/ui_dev.png"), "Developing to level %d" % (lv + 1), small, {}, "", Callable())
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.value = r.job.done / DV.time * 100
		c.get_child(0).get_child(1).add_child(bar)
		body.add_child(c)
	elif lv < DV.max:
		var why = game.dev_why(p)
		body.add_child(_dev_btn(hud.icon("icons/common/ui_dev.png"), "Develop Province", str(why) if why != null else "To level %d: +1 of each resource · %d min" % [lv + 1, int(DV.time / 60)],
			game.dev_cost(lv), "" if why == null else str(why), game.start_develop.bind(p), hud._dev_desc(lv)))


func _dev_btn(tex: Texture2D, title: String, small: String, cost: Dictionary, why: String, f: Callable, tip := "") -> Control:
	var c := PanelContainer.new()
	var off := why != ""
	var normal := Roster._sb(Color("#f6f1e4") if not off else Color("#e6e4df"), 1, 0, 5)
	c.add_theme_stylebox_override("panel", normal)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(h)
	var t := _tex(tex, 40)
	if off:
		t.modulate = Color(1, 1, 1, 0.5)
	h.add_child(t)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	v.add_child(_lbl(title, 15, Color(INK, 0.6) if off else INK))
	var sl := _lbl(small, 12, Color("#b3261e") if off else MUTED)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size = Vector2(W - 90, 0)
	v.add_child(sl)
	if not cost.is_empty():
		var cr := CostRow.make(cost, 13, true)
		cr.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(cr)
	if f.is_valid():
		var hov := Roster._sb(Color("#fff7dd") if not off else Color("#e6e4df"), 1, 0, 5)
		c.mouse_entered.connect(func(): c.add_theme_stylebox_override("panel", hov))
		c.mouse_exited.connect(func(): c.add_theme_stylebox_override("panel", normal))
		_clickable(c, func():
			if off:
				hud.add_toast(why, true)
			else:
				f.call(), UiKit.wrap(why if off else tip))
	return c
