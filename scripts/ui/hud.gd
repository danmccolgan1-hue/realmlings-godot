class_name Hud
extends CanvasLayer
## The interface: the top bar (resources with storage caps and income, the payday clock, buttons for research, the
## Armory, pause and the menu), the minimap, your units' roster, the selected province's panel, the selected unit's
## command card (the web game's 4×4 grid and keys), pop-ups, the Armory window and the game's messages.

const RES := ["gold", "wood", "food"]
const STAGE_NAME := ["Outpost", "Fort", "Capital"]

var game: Game
var paused_label: Label
var topbar: TopBar
var panel: PanelContainer
var panel_text: RichTextLabel
var prov := -1
var part := ""               # the selected building of `prov`: "settlement" or "<type>@<slot>" (web: S.selPart)
var parts_row: HFlowContainer   # the province panel's buildings, to select one (web: the province menu's .pm-b)
var parts_key := ""
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
var main            # the scene's entry node: saving, loading, the main menu
var map: MapView
var cam: Camera2D
var armory: ArmoryWindow
var diplomacy: DiplomacyWindow
var requests: RequestBox
var flags: FlagBar
var settings: SettingsWindow
var dialog: DialogBox
var minimap: Minimap
var roster: Roster
var menu_win: Dictionary
var ui_scale := 1.0


func _ready() -> void:
	# the Paused plaque first, so every window draws over it (web: #pausedBadge)
	paused_label = _label(34)
	paused_label.text = "Paused"
	paused_label.add_theme_color_override("font_color", Color("#1d1a22"))
	paused_label.add_theme_stylebox_override("normal", TopBar.paper(3, 2))
	paused_label.tooltip_text = "Space to play"
	paused_label.mouse_filter = Control.MOUSE_FILTER_STOP
	paused_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	paused_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	paused_label.position.y = 190
	add_child(paused_label)
	topbar = TopBar.new()
	topbar.hud = self
	add_child(topbar)
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
	parts_row = HFlowContainer.new()
	parts_row.add_theme_constant_override("h_separation", 6)
	pcol.add_child(parts_row)
	actions = VBoxContainer.new()
	pcol.add_child(actions)
	panel.add_child(pcol)
	_build_research()
	_build_tutorial()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -(16 + Minimap.SIZE.y + 56)   # above the minimap and its toggles (web: #prov)
	panel.offset_top = panel.offset_bottom
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
	card.tooltip_text = "Select a unit, building or province to see its actions here"
	flags = FlagBar.new()
	add_child(flags)
	flags.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)   # hung under the research strip (web: #nflags)
	flags.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts = VBoxContainer.new()
	toasts.custom_minimum_size = Vector2(560, 0)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toasts.alignment = BoxContainer.ALIGNMENT_END
	add_child(toasts)
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)   # bottom center (web: #toast)
	toasts.offset_bottom = -90
	toasts.offset_top = -90
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roster = Roster.new()
	add_child(roster)
	roster.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)   # under the map buttons (web: #roster)
	roster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	roster.offset_top = 70
	minimap = Minimap.new()
	add_child(minimap)
	# bottom left (web: #mini); placed each frame in _process
	armory = ArmoryWindow.new()
	add_child(armory)
	diplomacy = DiplomacyWindow.new()
	add_child(diplomacy)
	requests = RequestBox.new()
	requests.set_anchors_preset(Control.PRESET_CENTER_TOP)
	requests.position = Vector2(-260, 70)
	add_child(requests)
	dialog = DialogBox.new()
	add_child(dialog)
	_build_menu()
	settings = SettingsWindow.new()
	add_child(settings)
	# drawing order: the Paused plaque, the top bar, the flags and the toasts under every window and panel
	move_child(paused_label, 0)
	move_child(topbar, 1)
	move_child(flags, 2)
	move_child(toasts, 3)
	hide()


func set_game(g: Game) -> void:
	game = g
	g.on_toast = add_toast
	g.on_dialog = func(title: String, text: String, choices: Array, f: Callable):
		dialog.ask(title, text, choices, f if f.is_valid() else func(_id): pass)
	armory.setup(g, self)
	diplomacy.setup(g, self)
	requests.setup(g, self)
	flags.setup(g, self)
	g.on_game_over = func(_w):
		if main:
			main.save_recording()
		dialog.ask("Your realm has fallen", "Every province you held is gone. The other nations play on without you.",
		[{"id": "menu", "label": "Main menu", "why": null}, {"id": "watch", "label": "Watch", "why": null}],
		func(id): if id == "menu" and main: main.to_main_menu())
	roster.setup(g, self)
	if map and cam:
		minimap.setup(g, map, cam)
	topbar.setup(g)
	show()


func select_province(p: int, prt := "") -> void:
	prov = p
	part = prt if p >= 0 else ""
	if map:
		map.selected_part = part
	if game != null and game.tutorial != null and p == game.capital and unit == null:
		game.tutorial.selected.capital = true
	panel.visible = p >= 0


func select_unit(u) -> void:
	unit = u
	if game != null and game.tutorial != null and u != null and u.kind == game.WAYFINDER:
		game.tutorial.selected.wayfinder = true
	if u != null:
		part = ""
		if map:
			map.selected_part = ""


func add_toast(msg: String, warn := false) -> void:
	# web: #toast, a paper note at the bottom center (pink when something went wrong)
	var l := _label(17)
	l.text = msg
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UiKit.INK)
	l.add_theme_constant_override("outline_size", 0)
	var st := TopBar.paper(3, 2)
	if warn:
		st.bg_color = Color("#ffe1e1")
	l.add_theme_stylebox_override("normal", st)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_child(l)
	toast_list.append({"label": l, "until": Time.get_ticks_msec() + 6000})
	while toast_list.size() > 3:
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
				var left := ""
				if casting and is_finite(u.cast.dur):
					left = " %d s left." % ceili(u.cast.dur - (game.t - u.cast.t0))
				var cd_tip := (" Cooldown: %d s." % ceili(game.cd_left(k))) if game.cd_left(k) > 0 else ""
				out[cell] = {"id": "spell:" + k, "label": "%s\n%s" % [label, "stop" if casting else ("%s mana" % mana if mana is int else str(mana))], "why": null if casting else game.cast_why(u, k),
					"name": label + (" (casting)" if casting else ""), "desc": str(game.TECH_BY_ID[game.line_tech(k)].get("blurb", "")) + left + cd_tip,
					"ok": "Click to stop casting" if casting else "Click to cast"}
				cell += 1
		# Shockwave (every Mage) and Earthquake (Tier III Magic): web gpc.js Z11 / Z12
		for k in (["shock", "quake"] if game.tech_of(Game.ME, "earthquake") else ["shock"]):
			if cell >= 15:
				break
			var on: bool = u.get("quake") and u.quake.kind == k
			var left := ""
			if on:
				left = "%d s left" % ceili(u.quake.T - (game.t - u.quake.t0))
			var why = null
			if not on:
				why = game.quake_why(u) if k == "quake" else (null if game.mages_in(u) > 0 else "No Mage")
			var d2: String = str(game.TECH_BY_ID["earthquake"].get("blurb", "")) if k == "quake" else "Click this, then a neighboring enemy province: after %d seconds of casting, the shockwave hits the walls on its border and the armies standing there." % Game.SHOCK_TIME
			out[cell] = {"id": "spell2:" + k, "label": "%s\n%s" % [game.spell2_name(k), left if on else "%d mana" % Game.SPELL2_MANA[k]], "why": why,
				"name": game.spell2_name(k), "desc": d2 + ((" " + left + ".") if on else ""), "ok": "Click to cancel" if on else "Click to cast"}
			cell += 1
	if u.kind == "army" and game.has_art(Game.ME, "slippers"):   # v95: Winged Slippers
		for cell in [9, 7, 6, 5, 4]:
			if out[cell] == null and not list.any(func(c): return c.get("cell", -1) == cell):
				out[cell] = {"id": "fly", "label": "Fly\n(Slippers)", "why": game.fly_why(u), "name": "Fly (Winged Slippers)",
					"desc": "Click this, then a province: the army flies there over walls, rivers and mountains. Then the Slippers rest for a minute.", "ok": "Click, then pick a province"}
				break
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
			cmd = {"id": id, "label": "%s\n%s" % [name, " ".join(short)], "why": game.build_check(u.prov, type), "name": name, "cost": cost, "desc": _build_desc(u, type)}
		elif id == "survey":
			var why = null
			if game.surveyed.has(u.prov):
				why = "Already surveyed"
			elif u.survey != null:
				why = "Surveying…"
			cmd = {"id": id, "label": "Survey", "why": why, "desc": "Walk a loop around this province to reveal its resources and any Hidden Gold Deposit."}
		elif id == "auto" and game.has_tech("autoscout"):
			var on: bool = u.get("auto", true) != false
			cmd = {"id": id, "label": "Auto: %s" % ("on" if on else "off"), "why": null, "name": "Auto-survey: %s" % ("On" if on else "Off"),
				"desc": "When idle, Wayfinders walk to the nearest explored province that hasn’t been surveyed and survey it. Click to turn it %s." % ("off" if on else "on")}
		elif id == "cancelbuild":
			var b = u.build
			var nm := ""
			if b != null:
				nm = "outpost" if b.type == "outpost" else "road" if b.type == "road" else "wall" if b.type in ["wall", "rewall"] else (game.BUILD_DEFS[b.type].name if game.BUILD_DEFS.has(b.type) else "building")
			cmd = {"id": id, "label": "Cancel build", "why": null if b != null else "He isn’t building anything", "name": ("Cancel the " + nm) if b != null else "Cancel construction",
				"desc": ("Stop building and get back everything paid (%s)." % Game.cost_text(b.get("paid", {}))) if b != null else "When the Mason is building, this stops it and refunds what was paid.", "ok": "Click to cancel and get a refund"}
		elif id == "road":
			var q := game.mason_road_border(u)
			var why = "Research Dirt Roads first" if not game.has_tech("roads") else "Walk up to an open border, or a wall between two of your provinces, first" if q < 0 else game.link_why("road", u, q)
			cmd = {"id": id, "label": "Road\n25g 75w", "why": why, "name": ("Build a road to " + game.prov_name(q)) if q >= 0 else "Build a road", "cost": {"gold": 25, "wood": 75},
				"desc": "The Mason paves the border he stands next to: an open one, or through the gate of a wall between two of your provinces. %d s. Units move faster along roads." % int(Game.ROAD_TIME)}
		elif id == "dismiss":
			cmd = {"id": id, "label": "Dismiss", "why": null if u.get("battle") == null else "Not during battle",
				"desc": "Send %s home for good. No refund; the upkeep stops. Click twice to confirm." % u.name}
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
			cmd = {"id": id, "label": label, "why": why, "desc": "Pull out of the battle to a safe neighboring province. Some soldiers are lost covering the escape; the bigger the enemy compared to you, the more you lose."}
		elif id == "split":
			cmd = {"id": id, "label": "Split", "why": null if game.troop_count(u) >= 2 else "Only one soldier", "name": "Split Army",
				"desc": "Divide the army into two, sharing out each kind of soldier."}
		elif id == "rest":
			# web: features.js extraCmdInfo 'rest'
			var why = null if u.get("battle") == null else "Not during battle"
			if why == null and not (u.get("wounds", 0.0) > 0.01):
				why = "The army isn’t hurt"
			cmd = {"id": id, "label": "Resting…" if u.get("rest") != null else "Rest at a\nBarracks", "why": why, "name": "Resting…" if u.get("rest") != null else "Rest at a Barracks",
				"desc": "A wounded army gets its health back while it stands still at one of your Barracks: %d s for every soldier in it (%d s for this one). Click to march to the nearest Barracks." % [int(Game.REST_TIME), int(Game.REST_TIME * game.troop_count(u))]}
		elif id == "retrofit":
			cmd = {"id": id, "label": "Retrofit…", "why": game.retrofit_why(u), "name": "Retrofit",
				"desc": "Re-equip this army’s soldiers with another Armory design of the same kind; you pay the difference in gear cost. It takes %d s per soldier at a Barracks; the army marches to the nearest one by itself." % int(Game.RETRO_TIME)}
		elif id == "inspect":
			cmd = {"id": id, "label": "Inspect", "why": null, "name": "Inspect army", "desc": "See what this army is made of: each kind of soldier, their gear, strength and upkeep."}
		elif id == "combine":
			var n := game.units.filter(func(v): return v.kind == "army" and v.owner == Game.ME and v.prov == u.prov and not v.moving).size()
			cmd = {"id": id, "label": "Combine", "why": null if n >= 2 else "No other army here", "name": "Combine Armies", "desc": "Merge the armies standing in this province into one."}
		if cmd != null:
			out[int(c.cell)] = cmd
	return out


## A command's tooltip, like the web game's hover box: name, what it does, cost, and why it can't be used now
## (web: game.js showCmdTip)
func cmd_tip(c: Dictionary) -> String:
	var name: String = c.get("name", str(c.label).split("\n")[0])
	var out := name
	if c.get("desc", "") != "":
		out += "\n" + UiKit.wrap(c.desc)
	if c.get("cost") != null and not c.cost.is_empty():
		out += "\nCost: " + Game.cost_text(c.cost)
	out += "\n" + (("✗ " + str(c.why)) if c.why != null else ("✓ " + c.get("ok", "Ready")))
	return out


# web: game.js cmdInfo('build:<type>') desc
func _build_desc(u: Dictionary, type: String) -> String:
	if type == "outpost":
		return "Claims this province. It must be surveyed and border your land. Builds where the Mason stands in %d s." % int(game.build_time(type))
	var d: Dictionary = game.BUILD_DEFS[type]
	var desc := ""
	var gv := game.gives_of(type)
	if not gv.is_empty():
		desc = "Adds " + ", ".join(gv.keys().map(func(k): return "+%s %s" % [UiKit.num(gv[k]), k])) + " every 10 s."
		desc += " Up to 4 per province." if type == "farm" else " One per tree border." if type == "lumber" else ""
		if game.owned(u.prov) and game.build_cap(u.prov, type) > 1:
			desc += " %d/%d here." % [game.count_of(u.prov, type), game.build_cap(u.prov, type)]
	elif type == "barracks":
		desc = "Trains the infantry you design in the Armory. With a Stable in the same province, your cavalry designs too."
	elif type == "stable":
		desc = "Lets a Barracks in this province train Cavalry."
	if desc == "":
		desc = str(d.get("blurb", ""))
	var up: Dictionary = d.get("upkeep", {})
	if not up.is_empty():
		desc += " Upkeep every 10 s: " + ", ".join(up.keys().map(func(k): return "%s %s" % [UiKit.num(up[k]), k])) + "."
	return desc + " Builds where the Mason stands in %d s." % int(game.build_time(type))


func press(i: int) -> void:
	var c = card_cmds[i]
	if c == null:
		return
	if unit == null:
		_press_part(c)
		return
	if not game.units.any(func(v): return is_same(v, unit)):
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
		game.start_link(unit, game.mason_road_border(unit), "road")
	elif id == "dismiss":
		if confirm_key != "dismiss:%d" % unit.id:
			confirm_key = "dismiss:%d" % unit.id
			add_toast("Dismiss %s? Press Dismiss again to confirm." % unit.name, true)
			return
		confirm_key = ""
		game.dismiss([unit])
		select_unit(null)
	elif id == "fly":
		aim = {"unit": unit, "spell": "fly"}
		add_toast("Click a province next to the army. Right-click cancels.")
	elif id.begins_with("spell2:"):
		var k := id.substr(7)
		if unit.get("quake") and unit.quake.kind == k:
			game.end_quake(unit, "%s stopped." % game.spell2_name(k))
		elif k == "quake":
			game.start_spell2(unit, "quake")
		else:
			aim = {"unit": unit, "spell": "shock"}
			add_toast("Click a neighboring province behind an enemy wall. Right-click cancels.")
	elif id.begins_with("spell:"):
		var k := id.substr(6)
		if k in ["rift"] or (k == "eyes" and game.see_nbrs(unit).size() > 1):
			aim = {"unit": unit, "spell": k}
			add_toast("Click the province to target. Right-click cancels.")
		else:
			game.cast_spell(unit, k)
	elif id == "retreat":
		game.retreat(unit)
	elif id == "rest":
		game.send_to_rest(unit)
	elif id == "retrofit":
		_show_retrofit(unit)
	elif id == "inspect":
		_show_inspect(unit)
	elif id == "split":
		game.split_army(unit)
	elif id == "combine":
		game.combine_armies(game.units.filter(func(v): return v.kind == "army" and v.owner == Game.ME and v.prov == unit.prov and not v.moving))


## A command-card key (q w e r / a s d f / z x c v / u i o p). Returns true when it was used.
func key(k: String) -> bool:
	var i := GRID_KEYS.find(k)
	if i < 0 or (unit == null and part == ""):
		return false
	press(i)
	return true


func _process(_delta: float) -> void:
	if not game:
		return
	paused_label.visible = game.paused
	if prov >= 0:
		panel_text.text = _province_text(prov)
		_refresh_parts()
	upgrade_btn.visible = false   # Upgrade to Fort is on the command card now, with the settlement selected
	_refresh_actions()
	_refresh_tutorial()
	if research.visible:
		_refresh_research()
	if unit != null and not game.units.any(func(v): return is_same(v, unit)):
		select_unit(null)
	if part != "" and (prov < 0 or not game.owned(prov) or (part != "settlement" and part_extra() == null)):
		select_province(prov if prov >= 0 and game.explored.has(prov) else -1)   # the building is gone
	# the command card is always there; empty when nothing of yours is selected (web: game.js renderCmd)
	card_cmds = commands_of(unit) if unit != null and unit.owner == Game.ME else part_commands()
	for i in 16:
		var c = card_cmds[i]
		var b: Button = card_buttons[i]
		b.text = "" if c == null else "%s [%s]" % [c.label, GRID_KEYS[i].to_upper()]
		b.disabled = c == null or (c.why != null and not c.get("live", false))
		b.tooltip_text = "" if c == null else cmd_tip(c)
	minimap.position = Vector2(16, topbar.size.y - Minimap.SIZE.y - 16)
	# the flags hang from the research strip, centered (web: #nflags, top 100px)
	flags.offset_top = topbar.bottom() + 8.0
	flags.offset_bottom = flags.offset_top + flags.get_combined_minimum_size().y
	paused_label.position.y = flags.offset_bottom + (30.0 if flags.get_child_count() else 4.0)
	var now := Time.get_ticks_msec()
	while not toast_list.is_empty() and toast_list[0].until < now:
		toast_list.pop_front().label.queue_free()


# web: features.js showRetrofit
func _show_retrofit(a: Dictionary) -> void:
	var choices := []
	for d in game.designs:
		var plan := game.retro_plan(a, d.id)
		if not plan.n:
			continue
		var lack = game.lack_text(plan.cost)
		choices.append({"id": d.id, "label": "%s\n%d soldier%s · %s" % [d.name, plan.n, "s" if plan.n > 1 else "", UiKit.cost_line(plan.cost)], "why": lack})
	if choices.is_empty():
		add_toast("No other design of the same kind to retrofit to. Make one in the Armory (G).", true)
		return
	dialog.ask("Retrofit %s" % a.name, "Re-equip the soldiers with another design of the same kind; you pay the difference in gear cost. It takes %d s per soldier at a Barracks (cavalry: with a Stable); the army marches to the nearest one by itself." % int(Game.RETRO_TIME),
		choices, func(id):
			if id != "leave":
				game.retrofit_armies([a], id))


func _show_inspect(a: Dictionary) -> void:
	var lines := []
	for k in a.troops:
		var st: Dictionary = game.stats_of(k, a.owner)
		var d = game.unit_defs.get(k)
		lines.append("[b]%s × %d[/b]  attack %s · health %s · blocks %d%% · speed %s" % [d.name if d else k, a.troops[k], st.atk, st.hp, roundi(st.get("red", 0) * 100), game.UNIT_SPEED.get(k, "?")])
	var w: float = a.get("wounds", 0.0)
	if w > 0.01:
		lines.append("Wounds: %d health lost%s" % [roundi(w), " (resting)" if a.get("rest") != null else ""])
	dialog.ask(a.name, "\n".join(lines), [{"id": "ok", "label": "OK"}], func(_id): pass)


## Select a unit and look at it (the roster's buttons).
## Look at a nation: the camera goes to its capital (or any province of it).
func focus_nation(o: int) -> void:
	var c := game.capital_of(o)
	if c < 0:
		var pl := game.provs_of(o)
		if pl.is_empty():
			return
		c = pl[0]
	if cam:
		cam.position = Vector2(game.G.provs[c].ic[0], game.G.provs[c].ic[1])
	select_province(c)


## Look at a province (web: lookAtProv / flyTo), and select it when asked to.
func look_at_prov(p: int, sel := true) -> void:
	if cam:
		cam.position = Vector2(game.G.provs[p].ic[0], game.G.provs[p].ic[1])
		cam.zoom = cam.zoom.max(Vector2(0.55, 0.55))
	if sel:
		select_unit(null)
		if map:
			map.selected_unit = null
			map.selected_prov = p
		select_province(p)


func toggle_fullscreen() -> void:
	Settings.fullscreen = not Settings.fullscreen
	Settings.save_all()
	Settings.apply(get_tree())


func focus_unit(u: Dictionary) -> void:
	select_unit(u)
	if map:
		map.selected_unit = u
		map.selected_prov = u.prov
	select_province(u.prov)
	if cam:
		cam.position = Vector2(u.x, u.y)


# --- the menu (Esc) ---

func _build_menu() -> void:
	var shade := Control.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	menu_win = UiKit.window("Menu", 420, func(): toggle_menu())
	shade.add_child(menu_win.panel)
	menu_win.panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	var b: VBoxContainer = menu_win.body
	b.add_child(UiKit.button("Resume", 20, func(): toggle_menu()))
	b.add_child(UiKit.button("Save game (F5)", 20, func():
		if main and game.tutorial == null:
			main.save_to(main.QUICKSAVE)))
	b.add_child(UiKit.button("Load saved game (F9)", 20, func():
		if main:
			toggle_menu()
			main.load_from(main.QUICKSAVE)))
	b.add_child(UiKit.button("Settings", 20, func(): settings.open(game)))
	b.add_child(UiKit.button("Main menu", 20, func():
		if main:
			toggle_menu()
			main.to_main_menu()))
	b.add_child(UiKit.button("Quit", 20, func(): get_tree().quit()))
	menu_win.panel.hide()


func toggle_menu() -> void:
	var p: Control = menu_win.panel
	p.visible = not p.visible
	if p.visible:
		UiKit.center.call_deferred(p)
		if game:
			game.paused = true


func set_ui_scale(v: float) -> void:
	Settings.ui_scale = clampf(v, 0.7, 1.6)
	ui_scale = Settings.ui_scale
	Settings.save_all()
	Settings.apply(get_tree())


func _province_text(p: int) -> String:
	var P: Dictionary = game.G.provs[p]
	var s := "[b]%s[/b] · %s\n" % [game.prov_name(p), P.terrain.capitalize()]
	if game.setpieces.has(p) and game.sp_known(p):
		var why = game.setpiece_why(p)
		var D: Dictionary = game.SETPIECES[game.setpieces[p]]
		s += "%s: +%d %s research%s\n" % [D.name, D.pts, {"gov": "Government", "mil": "Military", "mag": "Magic"}[D.tree], "" if why == null else " (%s)" % why]
	if game.buildings.has(p):
		var b: Dictionary = game.buildings[p]
		var o: int = b.owner
		var stage_name: String = "Conquered Capital" if b.get("cc", false) else STAGE_NAME[b.stage]
		s += "%s (%s)\n" % [stage_name, "yours" if o == Game.ME else "the " + game.player_info(o).name]
		if game.occ.has(p):
			s += "[color=#b3261e]Occupied by %s[/color]\n" % ("you" if game.occ[p] == Game.ME else "the " + game.player_info(game.occ[p]).name)
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
		if u.prov == p and (u.owner == Game.ME or game.visible.has(p)):
			var whose := "" if u.owner == Game.ME or u.owner == Game.RAIDERS else " (%s)" % game.player_info(u.owner).name
			if u.kind == "army":
				var parts := []
				for k in u.troops:
					var d = game.unit_defs.get(k)
					parts.append("%s × %d" % [d.name if d else k, u.troops[k]])
				here.append("%s%s: %s" % [u.name, whose, ", ".join(parts)])
			else:
				here.append("%s the %s%s" % [u.name, game.unit_defs[u.kind].name, whose])
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
		# the province menu keeps the development level and Develop (web: v106.js the province menu); training,
		# upgrades, walls and tearing down are on the command card with the building selected
		var dr = game.dev_rec(prov)
		if dr != null and dr.job != null:
			rows.append({"label": "Developing to level %d: %d%%" % [dr.lv + 1, int(dr.job.done / GameData.c("DEV").time * 100)]})
		elif dr == null or dr.lv < GameData.c("DEV").max:
			var lv: int = dr.lv if dr != null else 0
			rows.append({"btn": "Develop to level %d (%s, 5 min)" % [lv + 1, Game.cost_text(game.dev_cost(lv))], "why": game.dev_why(prov), "do": game.start_develop.bind(prov), "tip": _dev_desc(lv)})
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
			var tip := UiKit.wrap(str(r.get("tip", ""))) if r.get("tip", "") != "" else ""
			if r.why != null:
				tip += ("\n" if tip != "" else "") + "✗ " + str(r.why)
			b.tooltip_text = tip
			var f: Callable = r.do
			b.pressed.connect(func(): f.call())
			actions.add_child(b)


func _dev_desc(lv: int) -> String:
	var DV: Dictionary = GameData.c("DEV")
	return "Level %d/%d. Develop to level %d: +1 gold, wood and food from the land, three new houses, and a %d%% chance of one more resource. %d%% chance of a Deep Gold Deposit (a Gold Mine there gives %d more gold). In a fort or capital each level holds one more province. %d minutes; hostile soldiers stall it, and an occupation resets the province to level 0." % [lv, DV.max, lv + 1, int(DV.luck * 100), int(DV.deep * 100), DV.deepGold, int(DV.time / 60)]


# --- the selected building's command card (web: game.js renderCmd, renderTrainCard, renderSettleCard, renderLevelCard;
# features.js renderBuildingCard, addDestroyCell; v96.js dismantle; v106.js settleCardCells) ---

## The selected extra building, or null.
func part_extra():
	if prov < 0 or part == "" or not part.contains("@"):
		return null
	var pp := part.split("@")
	for e in game.extras_in(prov):
		if e.type == pp[0] and e.slot == int(pp[1]):
			return e
	return null


## Where the selected building trains units: "capital", "barracks", "magetower" or "".
func part_src() -> String:
	if prov < 0 or part == "" or not game.owned(prov):
		return ""
	if part == "settlement":
		return "capital" if game.buildings[prov].stage == 2 else ""
	var e = part_extra()
	return e.type if e != null and e.type in ["barracks", "magetower"] else ""


func part_commands() -> Array:
	var out := []
	out.resize(16)
	if prov < 0 or part == "" or not game.owned(prov):
		return out
	var src := part_src()
	if src != "":
		# top rows train, the bottom row is the queue (click to cancel)
		var qkey := "%s:%d" % [src, prov]
		var kinds: Array = game.trainable(src, prov)
		for i in mini(kinds.size(), 12):
			var k: String = kinds[i]
			var d: Dictionary = game.unit_defs[k]
			out[i] = {"id": "train:" + k, "label": "%s\n%s" % [d.name, _short_cost(d.cost)], "why": game.train_why(src, prov, k), "name": "Train " + d.name,
				"cost": d.cost, "desc": _train_tip(k, qkey), "ok": "Click to train"}
		var Q: Array = game.queues.get(qkey, [])
		for i in mini(Q.size(), 4):
			var q: Dictionary = Q[i]
			var nm: String = game.unit_defs[q.kind].name
			var f := 0.0 if q.t0 == null else clampf((game.t - q.t0) / Game.train_time(q.kind, q), 0, 1)
			out[12 + i] = {"id": "queue:%d" % i, "label": "%d. %s%s" % [i + 1, nm, ("\n%d%%" % int(f * 100)) if i == 0 else ""], "why": null,
				"name": "%s%s in %s" % ["Retrofit to " if q.get("retro", false) else "", nm, "training" if i == 0 else "the queue"], "desc": "Click to cancel and get back what was paid.", "ok": "Click to cancel"}
		if Q.size() > 4:
			out[15] = {"id": "noop", "label": "+%d more" % (Q.size() - 3), "why": "", "name": "%d more in the queue" % (Q.size() - 3)}
		if src == "magetower":
			out[3] = _xup_cmd(part_extra())
		return out
	if part == "settlement":
		var b: Dictionary = game.buildings[prov]
		var up = game.upgrades.get(prov)
		var FU: Dictionary = GameData.c("FORT_UPGRADE")
		if b.stage == 0:
			if up != null:
				var left := ceili(FU.time - (game.t - up.t0))
				out[0] = {"id": "cancelup", "label": "Upgrading\n%d s · cancel" % left, "why": null, "name": "Upgrading to Fort", "cost": up.paid,
					"desc": "Ready in %d s. Click to cancel and get the resources back." % left, "ok": "Click to cancel"}
			else:
				out[0] = {"id": "upgrade", "label": "Upgrade to Fort\n%s" % _short_cost(FU.cost), "why": game.upgrade_why(prov), "name": "Upgrade to Fort", "cost": FU.cost,
					"desc": "Rebuild the outpost as a stone fort, opening 4 building plots instead of 2. Takes %d s; no Mason needed. Forts: %d/%d." % [FU.time, game.fort_count(), game.fort_limit()]}
		if b.stage >= 1:
			var rj = game.rewall_jobs.get(prov)
			var nw := game.rewalls_at(prov).size()
			out[0] = {"id": "rewalls", "label": ("Rebuilding walls\n%d s" % ceili(Game.REWALL_TIME - (game.t - rj.t0))) if rj != null else "Rebuild walls\n%dw each" % Game.REWALL_COST.wood,
				"why": "Already rebuilding" if rj != null else game.rewalls_why(prov), "name": "Rebuild walls" + (" (%d broken)" % nw if nw else ""),
				"desc": "Put back the walls broken in a siege or torn down on this province’s borders: %d wood each, %d s, no Mason needed. Only at peace with the nation on the other side." % [Game.REWALL_COST.wood, int(Game.REWALL_TIME)]}
		if b.stage == 1:
			out[3] = {"id": "dismantle", "label": "Dismantle\nfort", "why": game.dismantle_why(prov), "name": "Dismantle fort",
				"desc": "Turn this fort back into an outpost. Every building in the province is destroyed, with no refund, and the fort no longer counts toward your fort limit (or allows more provinces). Click twice to confirm."}
		var dr = game.dev_rec(prov)
		var lv: int = dr.lv if dr != null else 0
		if dr != null and dr.job != null:
			out[1] = {"id": "develop", "label": "Developing\n%d%%" % int(dr.job.done / GameData.c("DEV").time * 100), "why": "Already developing", "name": "Developing to level %d…" % (lv + 1),
				"desc": "%d s left%s." % [ceili(GameData.c("DEV").time - dr.job.done), " (stalled: hostile soldiers in the province)" if dr.job.get("stall", false) else ""]}
		elif lv >= GameData.c("DEV").max:
			out[1] = {"id": "develop", "label": "Fully\ndeveloped", "why": "Fully developed", "name": "Fully developed"}
		else:
			out[1] = {"id": "develop", "label": "Develop\n%s" % _short_cost(game.dev_cost(lv)), "why": game.dev_why(prov), "name": "Develop further", "cost": game.dev_cost(lv), "desc": _dev_desc(lv)}
		return out
	var e = part_extra()
	if e == null:
		return out
	if game.BUILD_DEFS[e.type].has("levels"):   # a Forge: its next upgrade
		out[0] = _xup_cmd(e)
	var nm2: String = game.BUILD_DEFS[e.type].name
	out[15] = {"id": "destroy", "label": "Tear down", "why": null, "name": "Tear down the " + nm2,
		"desc": "Tear down this %s to free its plot. No refund; its upkeep stops. Click twice to confirm." % nm2}
	return out


func _xup_cmd(e) -> Dictionary:
	if e == null:
		return {}
	var d: Dictionary = game.BUILD_DEFS[e.type]
	var lv: int = e.get("level", 1)
	var k := "%d@%d" % [prov, e.slot]
	if game.xup.has(k):
		var xu: Dictionary = game.xup[k]
		var left := ceili(d.ups[xu.to - 1].time - (game.t - xu.t0))
		return {"id": "xcancel", "label": "Upgrading\n%d s · cancel" % left, "why": null, "name": "Upgrading to " + str(d.levels[lv]), "cost": xu.get("paid"),
			"desc": "Ready in %d s. Click to cancel and get the resources back." % left, "ok": "Click to cancel"}
	if lv >= d.levels.size():
		return {"id": "xup", "label": "Fully\nupgraded", "why": "Fully upgraded", "name": str(d.levels[lv - 1])}
	return {"id": "xup", "label": "Upgrade\n%s" % _short_cost(d.ups[lv].cost), "why": game.xup_why(prov, e), "name": "Upgrade to " + str(d.levels[lv]), "cost": d.ups[lv].cost,
		"desc": "Raises %s research to Tier %s and to %d points every 10 s. Takes %d s; no Mason needed." % ["Military" if e.type == "forge" else "Magic", ["", "I", "II", "III"][mini(lv + 1, 3)], [0, 2, 4, 6][mini(lv + 1, 3)], d.ups[lv].time]}


static func _short_cost(cost: Dictionary) -> String:
	var short := []
	for k in cost:
		short.append("%d%s" % [cost[k], k.left(1)])
	return " ".join(short)


func _press_part(c: Dictionary) -> void:
	if prov < 0 or part == "":
		return
	var id: String = c.id
	if c.why != null and not id.begins_with("queue:") and not id in ["cancelup", "xcancel", "destroy"]:
		if str(c.why) != "":
			add_toast(str(c.why), true)
		return
	var src := part_src()
	if id.begins_with("train:"):
		game.train(src, prov, id.substr(6))
	elif id.begins_with("queue:"):
		game.cancel_training("%s:%d" % [src, prov], int(id.substr(6)))
	elif id == "upgrade":
		game.start_upgrade(prov)
	elif id == "cancelup":
		game.cancel_upgrade(prov)
	elif id == "rewalls":
		game.rebuild_walls(prov)
	elif id == "develop":
		game.start_develop(prov)
	elif id == "dismantle":
		var lost := game.extras_in(prov).size()
		_confirm("dismantle:%d" % prov, "Dismantle the fort at %s? It goes back to an outpost and all %d building%s in the province are destroyed. Press again to confirm." % [game.prov_name(prov), lost, "" if lost == 1 else "s"], game.dismantle_fort.bind(prov))
	elif id == "xup":
		var e = part_extra()
		if e != null:
			game.start_xup(prov, e.slot)
	elif id == "xcancel":
		var e = part_extra()
		if e != null:
			game.cancel_xup(prov, e.slot)
	elif id == "destroy":
		var e = part_extra()
		if e != null:
			var nm: String = game.BUILD_DEFS[e.type].name
			_confirm("destroy:%d@%d" % [prov, e.slot], "Tear down the %s? Press again to confirm." % nm, game.destroy_extra.bind(prov, e.slot))


## The province panel's row of buildings: click one to select it (web: game.js the province menu's .pm-b buttons).
func _refresh_parts() -> void:
	var list := []
	if prov >= 0 and game.owned(prov):
		var b: Dictionary = game.buildings[prov]
		list.append(["settlement", "Conquered Capital" if b.get("cc", false) else STAGE_NAME[b.stage]])
		for e in game.extras_in(prov):
			list.append(["%s@%d" % [e.type, e.slot], game.BUILD_DEFS[e.type].name])
	var k := str(prov) + "|" + part + "|" + str(list)
	if k == parts_key:
		return
	parts_key = k
	for c in parts_row.get_children():
		c.queue_free()
	for it in list:
		var bt := Button.new()
		bt.text = it[1]
		bt.toggle_mode = true
		bt.button_pressed = it[0] == part
		bt.add_theme_font_size_override("font_size", 16)
		bt.tooltip_text = "Select the %s: its actions are on the command card" % it[1]
		var prt: String = it[0]
		bt.pressed.connect(func():
			select_unit(null)
			if map:
				map.selected_unit = null
				map.selected_prov = prov
			select_province(prov, prt))
		parts_row.add_child(bt)


# web: game.js the resource bar's title: what you hold, what comes in and what goes out
func _res_tip(k: String) -> String:
	var inc: int = game.income[k]
	var out := "%s: %d of %d you can store (Storehouses and Granaries hold more).\n%s%d every payday" % [k.capitalize(), game.stock[k], game.storage_cap(k), "+" if inc >= 0 else "−", absi(inc)]
	var gross = game.income_parts.get("gross", {}).get(k)
	var up = game.income_parts.get("up", {}).get(k)
	if gross != null and up != null and up:
		out += " (+%d coming in, −%d upkeep)" % [gross, up]
	return out


# web: game.js cmdInfo('train:<kind>') desc
func _train_tip(kind: String, qkey: String) -> String:
	var d: Dictionary = game.unit_defs[kind]
	var out := str(d.get("blurb", ""))
	if game.DSTATS.has(kind):
		var ds := game.stats_of(kind, Game.ME)
		out += " Attack %s, health %s, armor %d%%." % [snappedf(ds.atk, 0.1), snappedf(ds.hp, 0.1), int(round(ds.get("red", 0) * 100))]
	if game.military.has(kind):
		out += " Joins the army standing in this province."
	out += " Takes %d s." % int(Game.train_time(kind))
	var up: Dictionary = d.get("upkeep", {})
	if not up.is_empty():
		out += " Upkeep every 10 s: " + ", ".join(up.keys().map(func(k): return "%s %s" % [UiKit.num(up[k]), k])) + "."
	var n: int = game.queues.get(qkey, []).size()
	if n:
		out += " %d already queued." % n
	return out.strip_edges()


func _confirm(key: String, msg: String, f: Callable) -> void:
	if confirm_key != key:
		confirm_key = key
		add_toast(msg, true)
		return
	confirm_key = ""
	f.call()


# --- research (T) ---

func _build_research() -> void:
	# web: tech.js renderTech: a window under the research strip, a column per tree
	research = PanelContainer.new()
	var st := TopBar.paper(3, 2)
	st.bg_color = Color("#f4ead2")
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 12
	research.add_theme_stylebox_override("panel", st)
	research.custom_minimum_size = Vector2(1180, 0)
	add_child(research)
	research.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 70)
	research.grow_horizontal = Control.GROW_DIRECTION_BOTH
	research_box = VBoxContainer.new()
	research_box.add_theme_constant_override("separation", 8)
	research.add_child(research_box)
	research.hide()


func toggle_research() -> void:
	research.visible = not research.visible
	research_key = ""


var research_open_done := {}   # tree -> the Researched list is unfolded


## web: v101.js researchSettled: every tree with something on offer has an active research
func research_settled() -> bool:
	for tr in Game.TREE_KEYS:
		var st: Dictionary = game.tech[tr]
		if st.tier and st.cur == null and not st.opts.is_empty():
			return false
	return true


func _research_pick(id: String) -> void:
	var before := str(Game.TREE_KEYS.map(func(t): return game.tech[t].cur))
	game.pick_tech(id)
	# web: v101.js: the window closes once every tree with something on offer is researching
	if research.visible and before != str(Game.TREE_KEYS.map(func(t): return game.tech[t].cur)) and research_settled():
		research.hide()
	research_key = ""


func _ink(text: String, sz: int, col := UiKit.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _refresh_research() -> void:
	research.position.y = topbar.bottom() + 8
	var key := ""
	for tr in Game.TREE_KEYS:
		var st: Dictionary = game.tech[tr]
		key += "%s|%s|%d|%d|%s|%s|%d|%s|%s;" % [tr, st.cur, int(st.prog), int(st.bank), ",".join(st.opts), st.tier, st.done.size(), game.auto_tech[tr], research_open_done.get(tr, false)]
	if key == research_key:
		return
	research_key = key
	UiKit.clear(research_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	research_box.add_child(head)
	var ttl := _ink("Research", 26)
	ttl.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(ttl)
	var sub := _ink("Points arrive every payday (10 s). An idle tree saves at most 30 s of points. Magic follows the school you choose.", 15, Color("#6b5a44"))
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(sub)
	var xb := TopBar.paper_button("", "close", "Close [T]", func(): research.hide(), 34.0)
	xb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(xb)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	research_box.add_child(cols)
	for tr in Game.TREE_KEYS:
		cols.add_child(_tree_column(tr))


func _tree_column(tr: String) -> Control:
	var st: Dictionary = game.tech[tr]
	var T: Dictionary = GameData.c("TECH_TREES")[tr]
	var col_c := Color(T.color)
	var pan := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(T.light)
	ps.border_color = UiKit.INK
	ps.set_border_width_all(1)
	ps.content_margin_left = 10
	ps.content_margin_right = 10
	ps.content_margin_top = 8
	ps.content_margin_bottom = 10
	pan.add_theme_stylebox_override("panel", ps)
	pan.custom_minimum_size = Vector2(378, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(356, 0)
	pan.add_child(col)
	# the header: name, the tiers, Auto
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	col.add_child(h)
	var name_l := _ink(T.name, 22, col_c)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(name_l)
	for i in [1, 2, 3]:
		var tb := _ink(["", "I", "II", "III"][i], 13, Color.WHITE if st.tier >= i else UiKit.INK)
		tb.autowrap_mode = TextServer.AUTOWRAP_OFF
		var tbs := StyleBoxFlat.new()
		tbs.bg_color = col_c if st.tier >= i else Color("#fffaf0")
		tbs.border_color = UiKit.INK
		tbs.set_border_width_all(1)
		tbs.content_margin_left = 5
		tbs.content_margin_right = 5
		tb.add_theme_stylebox_override("normal", tbs)
		tb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tb.tooltip_text = "Tier %s: %s" % [["", "I", "II", "III"][i], T.tiers[i - 1]]
		tb.mouse_filter = Control.MOUSE_FILTER_STOP
		h.add_child(tb)
	if st.tier:
		var auto := Button.new()
		auto.text = "Auto: on" if game.auto_tech[tr] else "Auto: off"
		auto.toggle_mode = true
		auto.button_pressed = game.auto_tech[tr]
		auto.focus_mode = Control.FOCUS_NONE
		auto.tooltip_text = "When nothing is being researched, pick the cheapest option by itself"
		auto.add_theme_font_size_override("font_size", 13)
		auto.toggled.connect(func(on):
			game.auto_tech[tr] = on
			research_key = "")
		h.add_child(auto)
	var rule := ColorRect.new()
	rule.color = col_c
	rule.custom_minimum_size = Vector2(0, 3)
	col.add_child(rule)
	if not st.tier:   # locked
		col.add_child(_ink("Locked", 17))
		col.add_child(_ink(str(T.rate), 13, Color("#6b5a44")))
		var lk := PanelContainer.new()
		var ls := StyleBoxFlat.new()
		ls.bg_color = Color("#fffaf0", 0.6)
		ls.border_color = UiKit.INK
		ls.set_border_width_all(2)
		ls.content_margin_left = 12
		ls.content_margin_right = 12
		ls.content_margin_top = 10
		ls.content_margin_bottom = 10
		lk.add_theme_stylebox_override("panel", ls)
		var ll := _ink(str(T.locked), 16)
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lk.add_child(ll)
		col.add_child(lk)
		return pan
	col.add_child(_ink("+%d points per payday" % game.tech_rate(tr), 17))
	col.add_child(_ink(str(T.rate), 13, Color("#6b5a44")))
	# what is being researched, with its progress
	var now := PanelContainer.new()
	var ns := StyleBoxFlat.new()
	ns.bg_color = Color("#fffaf0")
	ns.border_color = UiKit.INK
	ns.set_border_width_all(1)
	ns.content_margin_left = 8
	ns.content_margin_right = 8
	ns.content_margin_top = 5
	ns.content_margin_bottom = 5
	now.add_theme_stylebox_override("panel", ns)
	col.add_child(now)
	if st.cur != null:
		var x: Dictionary = game.TECH_BY_ID[st.cur]
		var nb := VBoxContainer.new()
		now.add_child(nb)
		nb.add_child(_ink("Researching %s" % x.name, 16))
		var bar := ProgressBar.new()
		bar.max_value = game.tech_cost(x)
		bar.value = st.prog
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
		var fill := StyleBoxFlat.new()
		fill.bg_color = col_c
		var back := StyleBoxFlat.new()
		back.bg_color = Color("#e6dcc4")
		back.border_color = UiKit.INK
		back.set_border_width_all(1)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", back)
		nb.add_child(bar)
		nb.add_child(_ink("%d / %d points" % [int(st.prog), game.tech_cost(x)], 13, Color("#6b5a44")))
	else:
		now.add_child(_ink("Nothing being researched.%s%s" % [(" %d points saved." % int(st.bank)) if st.bank else "", " Pick one:" if not st.opts.is_empty() else ""], 15))
	# the researched list, folded by default
	var all := 0
	for x in GameData.c("TECHS"):
		if x.tree == tr and game.tech_for(x) and not x.get("rep") and not str(x.id).begins_with("school-"):
			all += 1
	var open: bool = research_open_done.get(tr, false)
	var fold := Button.new()
	fold.text = "%s Researched (%d/%d)" % ["−" if open else "+", st.done.size(), all]
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fold.focus_mode = Control.FOCUS_NONE
	fold.add_theme_font_size_override("font_size", 14)
	fold.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fold.tooltip_text = "Show or hide what this tree has researched"
	fold.pressed.connect(func():
		research_open_done[tr] = not research_open_done.get(tr, false)
		research_key = "")
	col.add_child(fold)
	if open:
		col.add_child(_ink(", ".join(st.done.map(func(i): return game.TECH_BY_ID[i].name)) if not st.done.is_empty() else "Nothing yet.", 14, Color("#5a5560")))
	# the options as cards: icon, name, what it does, tier and cost
	if not st.opts.is_empty():
		col.add_child(_ink("OPTIONS", 12, Color("#6b5a44")))
	for id in st.opts:
		col.add_child(_tech_card(game.TECH_BY_ID[id], col_c))
	if st.tier < 3:
		col.add_child(_ink("Tier %s: %s" % [["", "I", "II", "III"][st.tier + 1], str(T.tiers[st.tier]).to_lower()], 13, Color("#6b5a44")))
	return pan


func _tech_card(x: Dictionary, col_c: Color) -> Control:
	# web: tech.js an option card: icon, name, what it does, tier and cost; click to research it
	var card := PanelContainer.new()
	var styles := {}
	for stn in ["normal", "hover"]:
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color("#fffaf0") if stn == "normal" else Color("#fff1c9")
		bs.border_color = UiKit.INK
		bs.set_border_width_all(1)
		bs.content_margin_left = 6
		bs.content_margin_right = 6
		bs.content_margin_top = 5
		bs.content_margin_bottom = 5
		styles[stn] = bs
	card.add_theme_stylebox_override("panel", styles.normal)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = UiKit.wrap("%s\n%s\nClick to research it." % [x.name, x.get("blurb", "")])
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", styles.hover))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", styles.normal))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sp = Art.get_sprite("icons", "realm", "tech_%s.png" % str(x.id).replace("-", "_").to_lower())
	if sp:
		icon.texture = sp.tex
	row.add_child(icon)
	var mid := VBoxContainer.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	row.add_child(mid)
	var nm := _ink(x.name, 15)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(nm)
	var bl := _ink(str(x.get("blurb", "")), 12, Color("#5a5560"))
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bl.custom_minimum_size = Vector2(250, 0)
	mid.add_child(bl)
	var cost := _ink("T %s\n%d%s" % [["", "I", "II", "III"][int(x.get("tier", 1))], game.tech_cost(x), ("\n%dg" % x.gold) if x.get("gold", 0) else ""], 13, col_c)
	cost.autowrap_mode = TextServer.AUTOWRAP_OFF
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.custom_minimum_size = Vector2(34, 0)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cost)
	var id: String = x.id
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_research_pick(id))
	return card


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
