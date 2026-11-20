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
var actions: VBoxContainer   # train and upgrade buttons of the selected province
var actions_key := ""
var confirm_key := ""
var aim = null               # {unit, spell}: the next click picks the spell's province
var research: PanelContainer
var research_box: VBoxContainer
var research_key := ""
var tut_panel: PanelContainer
var tut_text: RichTextLabel
var tut_objs: Label
var tut_next: Button
var tut_key := ""


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
	actions = VBoxContainer.new()
	pcol.add_child(actions)
	panel.add_child(pcol)
	_build_research()
	_build_tutorial()
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
	who.text = "Basic Tutorial" if g.tutorial != null else "%s — Practice island" % (L.full if L else "")
	show()


func select_province(p: int) -> void:
	prov = p
	if game != null and game.tutorial != null and p == game.capital and unit == null:
		game.tutorial.selected.capital = true
	panel.visible = p >= 0


func select_unit(u) -> void:
	unit = u
	if game != null and game.tutorial != null and u != null and u.kind == game.WAYFINDER:
		game.tutorial.selected.wayfinder = true
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
	if u.kind == "mage:A" or game.military.has(u.kind):
		list = []
	if game.is_caster(u):
		# the Realmlings' castable spells fill the card's middle rows (web: magic.js SPELL_CELLS)
		var cell := 4 if u.kind == "army" else 0
		for k in Game.SPELLS:
			if game.lvl(k) and cell < 15:
				var casting: bool = u.get("cast") != null and (u.cast.spell == k or u.cast.spell == "q:" + k)
				var mana = Game.SPELL_MANA.get(k, 0)
				var label: String = game.TECH_BY_ID[game.line_tech(k)].name
				out[cell] = {"id": "spell:" + k, "label": "%s\n%s" % [label, "stop" if casting else ("%s mana" % mana if mana is int else str(mana))], "why": game.cast_why(u, k)}
				cell += 1
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
		elif id == "road":
			var q := game.mason_border(u)
			var why = "Research Dirt Roads first" if not game.has_tech("roads") else "Walk up to an open border first" if q < 0 else game.link_why("road", u, q)
			cmd = {"id": id, "label": "Road\n25g 75w", "why": why}
		elif id == "dismiss":
			cmd = {"id": id, "label": "Dismiss", "why": null}
		elif id == "retreat":
			# web: game.js cmdInfo 'retreat'
			var why = null
			if u.get("battle") == null or u.get("retreating", false):
				why = "Not in battle"
			elif game.retreat_to(u) < 0:
				why = "No way out: every open border is blocked"
			elif game.retreat_lock_left(u) > 0:
				why = "Locked in battle for %d s" % ceili(game.retreat_lock_left(u))
			var label := "Retreat"
			if u.get("battle") != null:
				label += "\nlose ~%d of %d" % [game.retreat_loss(u), game.troop_count(u)]
			cmd = {"id": id, "label": label, "why": why}
		elif id == "split":
			cmd = {"id": id, "label": "Split", "why": null if game.troop_count(u) >= 2 else "Needs 2 soldiers"}
		elif id == "combine":
			var n := game.units.filter(func(v): return v.kind == "army" and v.owner == Game.ME and v.prov == u.prov and not v.moving).size()
			cmd = {"id": id, "label": "Combine", "why": null if n >= 2 else "No other army here"}
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
	elif id == "road":
		game.start_link(unit, game.mason_border(unit), "road")
	elif id == "dismiss":
		if confirm_key != "dismiss:%d" % unit.id:
			confirm_key = "dismiss:%d" % unit.id
			add_toast("Dismiss %s? Press Dismiss again to confirm." % unit.name, true)
			return
		confirm_key = ""
		game.dismiss([unit])
		select_unit(null)
	elif id.begins_with("spell:"):
		var k := id.substr(6)
		if k in ["rift"] or (k == "eyes" and game.see_nbrs(unit).size() > 1):
			aim = {"unit": unit, "spell": k}
			add_toast("Click the province to target. Right-click cancels.")
		else:
			game.cast_spell(unit, k)
	elif id == "retreat":
		game.retreat(unit)
	elif id == "split":
		game.split_army(unit)
	elif id == "combine":
		game.combine_armies(game.units.filter(func(v): return v.kind == "army" and v.owner == Game.ME and v.prov == unit.prov and not v.moving))


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
	_refresh_actions()
	_refresh_tutorial()
	if research.visible:
		_refresh_research()
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



# --- the selected province's buildings: training and upgrades ---

func _refresh_actions() -> void:
	var key := ""
	var rows := []
	if prov >= 0 and game.owned(prov):
		var srcs := []
		if game.buildings[prov].stage == 2:
			srcs.append("capital")
		for e in game.extras_in(prov):
			if e.type in ["barracks", "magetower"] and not srcs.has(e.type):
				srcs.append(e.type)
		for src in srcs:
			var qkey := "%s:%d" % [src, prov]
			var Q: Array = game.queues.get(qkey, [])
			var names := []
			for q in Q:
				names.append(game.unit_defs[q.kind].name)
			var head: String = {"capital": "Capital", "barracks": "Barracks", "magetower": "Mage Tower"}[src]
			if not Q.is_empty():
				var f: float = 0.0 if Q[0].t0 == null else (game.t - Q[0].t0) / Game.train_time(Q[0].kind)
				head += " · training %s (%d%%)%s" % [names[0], int(f * 100), (", then " + ", ".join(names.slice(1))) if names.size() > 1 else ""]
			rows.append({"label": head})
			for kind in game.trainable(src, prov):
				var d: Dictionary = game.unit_defs[kind]
				var why = game.train_why(src, prov, kind)
				rows.append({"btn": "Train %s (%s)" % [d.name, Game.cost_text(d.cost)], "why": why, "do": game.train.bind(src, prov, kind)})
		var dr = game.dev_rec(prov)
		if dr != null and dr.job != null:
			rows.append({"label": "Developing to level %d: %d%%" % [dr.lv + 1, int(dr.job.done / GameData.c("DEV").time * 100)]})
		elif dr == null or dr.lv < GameData.c("DEV").max:
			var lv: int = dr.lv if dr != null else 0
			rows.append({"btn": "Develop to level %d (%s, 5 min)" % [lv + 1, Game.cost_text(game.dev_cost(lv))], "why": game.dev_why(prov), "do": game.start_develop.bind(prov)})
		for e in game.extras_in(prov):
			rows.append({"btn": "Tear down the %s (no refund)" % game.BUILD_DEFS[e.type].name, "why": null, "do": _confirm.bind("destroy:%d@%d" % [prov, e.slot], "Tear down the %s? Press again to confirm." % game.BUILD_DEFS[e.type].name, game.destroy_extra.bind(prov, e.slot))})
		for e in game.extras_in(prov):
			if e.type in ["forge", "magetower"]:
				var d: Dictionary = game.BUILD_DEFS[e.type]
				var lv: int = e.get("level", 1)
				var k := "%d@%d" % [prov, e.slot]
				if game.xup.has(k):
					var xu: Dictionary = game.xup[k]
					rows.append({"btn": "Upgrading to %s… (cancel)" % d.levels[lv], "why": null, "do": game.cancel_xup.bind(prov, e.slot)})
				elif lv < d.levels.size():
					rows.append({"btn": "Upgrade %s to %s (%s)" % [d.levels[lv - 1], d.levels[lv], Game.cost_text(d.ups[lv].cost)], "why": game.xup_why(prov, e), "do": game.start_xup.bind(prov, e.slot)})
	if unit != null and game.is_caster(unit) and unit.prov == prov:
		rows.append({"label": "%s: %d / %d mana%s" % [unit.name, int(Game.mana_of(unit)), game.mana_cap(), (" · casting " + str(unit.cast.spell).trim_prefix("q:")) if unit.get("cast") != null else ""]})
		for q in game.all_nbr[prov]:
			for kind in ["forest", "tunnel"]:
				if not game.lvl(kind):
					continue
				var why = game.path_why(unit, q, kind, false)
				if why == null or str(why).begins_with("Not enough mana"):
					rows.append({"btn": "Open a %s to province %d (200 mana)" % ["forest path" if kind == "forest" else "tunnel", q], "why": why, "do": game.start_path.bind(unit, q, kind, false)})
	if unit != null and unit.kind == Game.MASON and unit.prov == prov and not unit.moving:
		rows.append({"label": "Mason: roads and walls to a neighbour"})
		for q in game.all_nbr[prov]:
			for type in ["road", "wall"]:
				var why = game.link_why(type, unit, q)
				if why != null and not str(why).begins_with("Need"):
					continue   # only the links he could build now (or with more resources)
				var cost: Dictionary = GameData.c("ROAD_COST") if type == "road" else GameData.c("WALL_COST")
				rows.append({"btn": "%s to province %d (%s)" % [type.capitalize(), q, Game.cost_text(cost)], "why": why, "do": game.start_link.bind(unit, q, type)})
	for r in rows:
		key += str(r.get("label", "")) + str(r.get("btn", "")) + str(r.get("why", "")) + "|"
	if key == actions_key:
		return
	actions_key = key
	for c in actions.get_children():
		c.queue_free()
	for r in rows:
		if r.has("label"):
			var l := Label.new()
			l.text = r.label
			l.add_theme_color_override("font_color", Color("#1d1a22"))
			l.add_theme_font_size_override("font_size", 18)
			actions.add_child(l)
		else:
			var b := Button.new()
			b.text = r.btn
			b.add_theme_font_size_override("font_size", 17)
			b.disabled = r.why != null
			b.tooltip_text = "" if r.why == null else str(r.why)
			var f: Callable = r.do
			b.pressed.connect(func(): f.call())
			actions.add_child(b)


func _confirm(key: String, msg: String, f: Callable) -> void:
	if confirm_key != key:
		confirm_key = key
		add_toast(msg, true)
		return
	confirm_key = ""
	f.call()


# --- research (T) ---

func _build_research() -> void:
	research = PanelContainer.new()
	research.add_theme_stylebox_override("panel", _box(Color("#faf1dc", 0.97)))
	research.custom_minimum_size = Vector2(1100, 0)
	add_child(research)
	research.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 70)
	research.grow_horizontal = Control.GROW_DIRECTION_BOTH
	research_box = VBoxContainer.new()
	research.add_child(research_box)
	research.hide()


func toggle_research() -> void:
	research.visible = not research.visible
	research_key = ""


func _refresh_research() -> void:
	var key := ""
	for tr in Game.TREE_KEYS:
		var st: Dictionary = game.tech[tr]
		key += "%s|%s|%d|%d|%s|%s|%d;" % [tr, st.cur, int(st.prog), int(st.bank), ",".join(st.opts), st.tier, st.done.size()]
	if key == research_key:
		return
	research_key = key
	for c in research_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "Research  (T to close)"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#1d1a22"))
	research_box.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	research_box.add_child(cols)
	for tr in Game.TREE_KEYS:
		var st: Dictionary = game.tech[tr]
		var T: Dictionary = GameData.c("TECH_TREES")[tr]
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(350, 0)
		cols.add_child(col)
		var h := Label.new()
		h.text = "%s · Tier %s · +%d every 10 s" % [T.name, ["—", "I", "II", "III"][st.tier], game.tech_rate(tr)] if st.tier else "%s · %s" % [T.name, "locked: build a Forge" if tr == "mil" else "locked: build a Mage Tower"]
		h.add_theme_font_size_override("font_size", 20)
		h.add_theme_color_override("font_color", Color(T.color))
		col.add_child(h)
		var info := Label.new()
		info.add_theme_color_override("font_color", Color("#1d1a22"))
		info.add_theme_font_size_override("font_size", 17)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if st.cur != null:
			var x: Dictionary = game.TECH_BY_ID[st.cur]
			info.text = "Researching %s: %d / %d" % [x.name, int(st.prog), game.tech_cost(x)]
		else:
			info.text = "Nothing in progress%s" % (" · %d points banked" % int(st.bank) if st.bank else "")
		col.add_child(info)
		for id in st.opts:
			var x: Dictionary = game.TECH_BY_ID[id]
			var b := Button.new()
			b.text = "%s  (%d%s)" % [x.name, game.tech_cost(x), ", %d gold" % x.gold if x.get("gold", 0) else ""]
			b.tooltip_text = str(x.get("blurb", ""))
			b.add_theme_font_size_override("font_size", 17)
			b.pressed.connect(func(): game.pick_tech(id))
			col.add_child(b)
		var auto := CheckBox.new()
		auto.text = "Auto-pick the cheapest"
		auto.button_pressed = game.auto_tech[tr]
		auto.add_theme_color_override("font_color", Color("#1d1a22"))
		auto.toggled.connect(func(on): game.auto_tech[tr] = on)
		col.add_child(auto)
		if not st.done.is_empty():
			var done := Label.new()
			done.text = "Done: " + ", ".join(st.done.map(func(i): return game.TECH_BY_ID[i].name))
			done.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			done.add_theme_font_size_override("font_size", 15)
			done.add_theme_color_override("font_color", Color("#5a5560"))
			col.add_child(done)



# --- the tutorial's lines and objectives (web: tutorial.js tutRender) ---

func _build_tutorial() -> void:
	tut_panel = PanelContainer.new()
	tut_panel.add_theme_stylebox_override("panel", _box(Color("#fff8e6", 0.97)))
	tut_panel.custom_minimum_size = Vector2(760, 0)
	add_child(tut_panel)
	tut_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 20)
	tut_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tut_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var col := VBoxContainer.new()
	tut_panel.add_child(col)
	tut_text = RichTextLabel.new()
	tut_text.bbcode_enabled = true
	tut_text.fit_content = true
	tut_text.custom_minimum_size = Vector2(740, 0)
	tut_text.add_theme_color_override("default_color", Color("#1d1a22"))
	tut_text.add_theme_font_size_override("normal_font_size", 20)
	col.add_child(tut_text)
	var row := HBoxContainer.new()
	col.add_child(row)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): game.tutorial.back_line())
	row.add_child(back)
	tut_next = Button.new()
	tut_next.text = "Next"
	tut_next.pressed.connect(func(): game.tutorial.next_line())
	row.add_child(tut_next)
	tut_objs = Label.new()
	tut_objs.add_theme_color_override("font_color", Color("#1d1a22"))
	tut_objs.add_theme_font_size_override("font_size", 18)
	tut_objs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut_objs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(tut_objs)
	tut_panel.hide()


func _refresh_tutorial() -> void:
	if tut_panel == null:
		return
	var T = game.tutorial
	if T == null:
		tut_panel.hide()
		return
	var L = T.shown()
	var objs := []
	for o in T.objs:
		objs.append(("✔ " if T.done.has(o.key) else "☐ ") + o.text)
	var key := "%s|%s|%s" % [L.id + str(L.k) if L != null else "", ",".join(objs), T.ended]
	if key == tut_key:
		return
	tut_key = key
	tut_objs.text = "   ".join(objs.slice(-3))
	if L != null:
		tut_text.text = T.line_text(L.lines[L.k])
		tut_next.text = "Next" if L.k < L.lines.size() - 1 else "Got it"
		tut_next.show()
		tut_panel.show()
	elif not objs.is_empty() and not T.ended:
		tut_text.text = "[i]Objective:[/i] " + T.objs[T.objs.size() - 1].text
		tut_next.hide()
		tut_panel.show()
	else:
		tut_panel.hide()
