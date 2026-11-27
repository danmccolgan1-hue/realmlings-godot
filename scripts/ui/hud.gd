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
var prov := -1
var part := ""               # the selected building of `prov`: "settlement" or "<type>@<slot>" (web: S.selPart)
var tip: PanelContainer      # the province under the mouse (web: #tip)
var tip_text: RichTextLabel
var bug: Control   # BugReport
var tip_key := ""
var renamer: RenameBox
var sel_rename: Button        # ✎ beside the selection line
var pick: PickMenu           # the build-on-a-plot and crop menus
var crop_arm := {}           # web: v104.js cropAllArm, {p, slot, t}: "Apply to all" waits 8 s for its confirm
var unit = null              # the command card's unit: the first selected unit of the card's tab (web: primary())
var mason_adv := false       # the Mason's card shows its second page, Advanced Buildings
var selection := []          # every selected unit (web: S.selected); several by box or Shift-click
var cmd_tab := ""            # with several kinds selected, the kind whose commands the card shows (web: cmdTab)
var card: CommandCard
var sel_line: Label          # what is selected, bottom left next to the minimap (web: #sel)
var card_cmds := []          # per cell: {id, label, why} or null
var toasts: VBoxContainer
var banners: VBoxContainer   # 0.19.1: notices about a province (a dig site found, a star fallen): click to look there
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
var tut_voice_id := ""
var main            # the scene's entry node: saving, loading, the main menu
var map: MapView
var cam: Camera2D
var armory: ArmoryWindow
var diplomacy: DiplomacyWindow
var school: SchoolPopup
var country: CountryWindow
var quests: QuestLogWindow    # the Quest Log (L)
var dialog_queue := []         # pop-ups waiting for the open one to close: [title, text, choices, f, pics]
var requests: RequestBox
var flags: FlagBar
var settings: SettingsWindow
var dialog: DialogBox
var minimap: Minimap
var msglog: MessageLog        # the messages box, beside the minimap
var roster: Roster
var menu_win: Dictionary
var ui_scale := 1.0
## 0.19.3: an observer's interface: the map, the minimap and its toggles, zoom and the menu, and the players'
## window (ObserverPanel); nothing to select, order, research or open (set before set_game).
var observer := false
var watch_panel: ObserverPanel


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
	panel = ProvPanel.new()
	add_child(panel)
	panel.hide()
	actions = panel.actions
	_build_research()
	_build_tutorial()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -(16 + Minimap.SIZE.y + 56)   # above the minimap and its toggles (web: #prov)
	panel.offset_top = panel.offset_bottom
	# the command card
	GRID_KEYS = GameData.c("GRID_KEYS")
	card = CommandCard.new()
	card.on_press = press
	card.on_tab = func(id):
		cmd_tab = str(id)
		_sync_unit()
	card.tip_of = cmd_tip
	add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.tooltip_text = " "   # (the card's own tooltip names each cell)
	card_cmds.resize(16)
	tip = PanelContainer.new()
	tip.add_theme_stylebox_override("panel", TopBar.paper(3, 2))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_text = RichTextLabel.new()
	tip_text.bbcode_enabled = true
	tip_text.fit_content = true
	tip_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_text.add_theme_color_override("default_color", UiKit.INK)
	tip_text.add_theme_font_size_override("normal_font_size", 15)
	tip_text.add_theme_font_size_override("bold_font_size", 18)
	tip.add_child(tip_text)
	add_child(tip)
	tip.hide()
	pick = PickMenu.new()
	pick.hud = self
	sel_line = Label.new()
	sel_line.add_theme_stylebox_override("normal", TopBar.paper(3, 2))
	sel_line.add_theme_color_override("font_color", UiKit.INK)
	sel_line.add_theme_font_size_override("font_size", 17)
	sel_line.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(sel_line)
	call_deferred("add_child", pick)   # (over every other panel)
	renamer = RenameBox.new()
	call_deferred("add_child", renamer)
	sel_rename = Button.new()
	sel_rename.text = "✎"
	sel_rename.focus_mode = Control.FOCUS_NONE
	sel_rename.tooltip_text = "Rename"
	sel_rename.add_theme_stylebox_override("normal", TopBar.paper(3, 2))
	sel_rename.add_theme_stylebox_override("hover", TopBar.paper(3, 2))
	sel_rename.add_theme_color_override("font_color", UiKit.INK)
	sel_rename.add_theme_color_override("font_hover_color", UiKit.INK)
	sel_rename.pressed.connect(func():
		if unit != null and unit.owner == Game.LOCAL:
			renamer.open(game, "unit:%d" % unit.id))
	add_child(sel_rename)
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
	banners = VBoxContainer.new()
	banners.add_theme_constant_override("separation", 6)
	banners.custom_minimum_size = Vector2(520, 0)
	banners.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(banners)
	banners.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	banners.offset_top = 118   # (under the top bar, the research strip and the flags)
	banners.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roster = Roster.new()
	add_child(roster)
	roster.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)   # under the map buttons (web: #roster)
	roster.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	roster.offset_top = 70
	minimap = Minimap.new()
	add_child(minimap)
	msglog = MessageLog.new()
	add_child(msglog)
	# bottom left (web: #mini); placed each frame in _process
	armory = ArmoryWindow.new()
	add_child(armory)
	diplomacy = DiplomacyWindow.new()
	add_child(diplomacy)
	school = SchoolPopup.new()
	add_child(school)
	country = CountryWindow.new()
	add_child(country)
	quests = QuestLogWindow.new()
	add_child(quests)
	requests = RequestBox.new()
	requests.set_anchors_preset(Control.PRESET_CENTER_TOP)
	requests.position = Vector2(-260, 70)
	add_child(requests)
	dialog = DialogBox.new()
	add_child(dialog)
	_build_menu()
	settings = SettingsWindow.new()
	add_child(settings)
	bug = preload("res://scripts/ui/bug_report.gd").new()   # 0.19: the bug report box (the bug button, top right)
	bug.hud = self
	add_child(bug)
	watch_panel = ObserverPanel.new()
	add_child(watch_panel)
	# drawing order: the Paused plaque, the top bar, the flags and the toasts under every window and panel
	move_child(paused_label, 0)
	move_child(topbar, 1)
	move_child(flags, 2)
	move_child(toasts, 3)
	hide()


func set_game(g: Game) -> void:
	if game != g and msglog != null and (game == null or game.world != g.world or g.t < game.t):   # (a new game starts a clean box)
		msglog.clear()
	if game != g:
		dialog_queue.clear()
	game = g
	g.on_toast = add_toast
	g.on_notice = add_banner
	g.on_dialog = func(title: String, text: String, choices: Array, f: Callable):
		var pics := []
		for it in g.dialog_items:   # (0.19.3: a new quest shows the relic that started it)
			var tx := QuestLogWindow.item_tex(str(it))
			if tx != null:
				pics.append(tx)
		if g.dialog_nation != 0:   # meeting a nation: its flag and its leader
			pics = [Art.nation_flag(g, g.dialog_nation)]
			var L = g.leader_of(g.dialog_nation)
			if L != null:
				pics.append(Hud.leader_icon(L.id))
				text = "%s leads them.\n%s" % [L.full, text]
		if dialog.visible:   # (one at a time: a new pop-up waits its turn instead of replacing an open one)
			dialog_queue.append([title, text, choices, f, pics])
			return
		dialog.ask(title, text, choices, f if f.is_valid() else func(_id): pass, pics)
	armory.setup(g, self)
	diplomacy.setup(g, self)
	school.setup(g, self)
	country.setup(g, self)
	quests.setup(g, self)
	requests.setup(g, self)
	flags.setup(g, self)
	g.on_game_over = func(w):   # web: war.js gameOver
		if main:
			main.save_recording()
		var who := ("The %s annexed every province you held." % game.player_info(w).name) if w != null and int(w) > 0 else "You hold no land."
		dialog.ask("Your realm has fallen", who,
		[{"id": "look", "label": "Show me", "why": null}, {"id": "ok", "label": "OK", "why": null}, {"id": "again", "label": "Start over", "why": null}],
		func(id):
			if id == "look" and game.capital >= 0:
				look_at_prov(game.capital)
			elif id == "again" and main:
				main.to_main_menu()
				main.menu.show_screen("setup"))
	roster.setup(g, self)
	if map and cam:
		minimap.setup(g, map, cam)
	topbar.setup(g)
	_apply_observer()
	show()


## An observer's interface (see `observer`), or a player's: what shows, and no pop-ups or messages from the game
## (an observer's copy plays no nation; the rules never wait on these).
func _apply_observer() -> void:
	topbar.set_observer(observer)
	for c in [card, sel_line, sel_rename, flags, roster, msglog, banners, requests]:
		c.visible = not observer
	if observer:
		game.on_toast = Callable()
		game.on_notice = Callable()
		game.on_dialog = Callable()
		game.on_game_over = Callable()
		select_unit(null)
		select_province(-1)
		for w in [armory, diplomacy, quests, country, school]:
			if w.visible:
				w.hide()
		research.hide()
	else:
		watch_panel.hide()


func select_province(p: int, prt := "") -> void:
	prov = p
	part = prt if p >= 0 else ""
	if map:
		map.selected_part = part
	if game != null and game.tutorial != null and p == game.capital and unit == null:
		game.tutorial.selected.capital = true
	panel.visible = p >= 0


func select_unit(u) -> void:
	set_selection([u] if u != null else [])


## Select these units (web: S.selected = …): the card shows the first kind's commands, with a tab per kind.
func set_selection(list: Array) -> void:
	selection = list.filter(func(v): return v != null)
	mason_adv = false   # (a Mason's card opens on its first page)
	if game != null and game.tutorial != null and selection.any(func(v): return v.kind == game.WAYFINDER):
		game.tutorial.selected.wayfinder = true
	if not selection.is_empty():
		part = ""
		if map:
			map.selected_part = ""
	_sync_unit()


func is_selected(u) -> bool:
	return selection.any(func(v): return is_same(v, u))


## The kinds selected, in the order they were picked (web: game.js renderCmd kinds).
func sel_kinds() -> Array:
	var out := []
	for v in selection:
		if not out.has(v.kind):
			out.append(v.kind)
	return out


## The selected units of the card's kind (commands such as Retreat and Auto-survey apply to all of them).
func tab_units() -> Array:
	return selection.filter(func(v): return v.kind == cmd_tab)


func _sync_unit() -> void:
	var kinds := sel_kinds()
	if not kinds.has(cmd_tab):
		cmd_tab = kinds[0] if not kinds.is_empty() else ""
	unit = null
	for v in selection:
		if v.kind == cmd_tab:
			unit = v
			break
	if map:
		map.selected_unit = unit
		map.selection = selection


## A banner under the top bar about province p (it also goes to the messages box). Clicking it looks at p; it goes
## by itself after 12 seconds, and only the newest 3 stay.
func add_banner(msg: String, p: int) -> void:
	add_toast(msg)
	if banners == null:
		return
	var b := Button.new()
	b.text = msg + "\n▸ Show me"
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(520, 0)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", UiKit.INK)
	b.add_theme_color_override("font_hover_color", UiKit.INK)
	b.add_theme_color_override("font_pressed_color", UiKit.INK)
	var st := TopBar.paper(4, 2)
	st.bg_color = Color("#fff2c9")
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	st.border_color = Color("#c98a12")
	b.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate()
	hv.bg_color = Color("#ffe59a")
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.tooltip_text = "Look at %s" % game.prov_name(p) if game != null else ""
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func():
		if game != null and p >= 0:
			look_at_prov(p)
		b.queue_free())
	banners.add_child(b)
	get_tree().create_timer(12.0).timeout.connect(func(): if is_instance_valid(b): b.queue_free())
	while banners.get_child_count() > 3:
		var old := banners.get_child(0)
		banners.remove_child(old)
		old.queue_free()


func add_toast(msg: String, warn := false) -> void:
	if Sound.inst:
		Sound.inst.on_toast(warn)
	# every message goes to the messages box beside the minimap (0.17; the web game's #toast note at the bottom center
	# is kept only for the menus, when no game is shown)
	if game != null and msglog != null:
		msglog.add(msg, warn, Game.fmt_time(game.t))
		return
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
	var list: Array = game.CMD.get(u.kind + Races.ADV if u.kind == Game.MASON and mason_adv else u.kind, [])
	if u.kind == "mage:A" or game.military.has(u.kind):
		list = []
	if u.kind == game.MAGE and u.owner == Game.LOCAL:   # web: magic.js CMD[MAGE] 'join' (cell 12)
		var jw := game.join_why(u)
		out[12] = {"id": "join", "label": "Join army", "why": null if jw == "" else jw, "name": "Join army",
			"desc": "The %s joins the army in this province: he fights with it, and its battle spells fire when a battle starts. An army can have one." % game.unit_defs[game.MAGE].name}
	elif u.kind == "army" and u.owner == Game.LOCAL and u.troops.get(game.MAGE, 0) > 0:   # web: magic.js CMD.army 'detach' (cell 2)
		out[2] = {"id": "detach", "label": "Detach\n" + game.unit_defs[game.MAGE].name, "why": null if u.get("battle") == null else "Not during battle",
			"name": "Detach " + game.unit_defs[game.MAGE].name, "desc": "The %s leaves the army and stands on his own." % game.unit_defs[game.MAGE].name}
	if game.is_caster(u):
		# the Realmlings' castable spells fill the card's middle rows (web: magic.js SPELL_CELLS)
		var cell := 4 if u.kind == "army" else 0
		for k in Game.SPELLS:
			if game.lvl(k) and cell < 15:
				var casting: bool = u.get("cast") != null and (u.cast.spell == k or u.cast.spell == "q:" + k)
				var mana = Game.SPELL_MANA.get(k, 0)
				var label: String = game.spell_name(k)
				var left := ""
				if casting and is_finite(u.cast.dur):
					left = " %d s left." % ceili(u.cast.dur - (game.t - u.cast.t0))
				var cd_tip := (" Cooldown: %d s." % ceili(game.cd_left(k))) if game.cd_left(k) > 0 else ""
				out[cell] = {"id": "spell:" + k, "label": "%s\n%s" % [label, "stop" if casting else ("%s mana" % mana if mana is int else str(mana))], "why": null if casting else game.cast_why(u, k),
					"name": label + (" (casting)" if casting else ""), "desc": str(game.TECH_BY_ID[game.line_tech(k)].get("blurb", "")) + left + cd_tip,
					"ok": "Click to stop casting" if casting else "Click to cast"}
				cell += 1
		# Shockwave (every Mage) and Earthquake (Tier III Magic): web gpc.js Z11 / Z12
		for k in (["shock", "quake"] if game.tech_of(Game.LOCAL, "earthquake") else ["shock"]):
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
	if game.quests_on and game.is_caster(u):   # quests: the Spell Books' spells, once their quest is done (Godot only)
		for k in Quests.SPELLS:
			if not game.quest_unlocks.has(Quests.SPELLS[k].unlock):
				continue
			var cell := -1
			for i in range(4 if u.kind == "army" else 0, 15):
				if out[i] == null and not list.any(func(c): return int(c.get("cell", -1)) == i):
					cell = i
					break
			if cell < 0:
				break
			var sw := Quests.spell_why(game, u, k)
			out[cell] = {"id": "qspell:" + k, "label": "%s\n%d mana" % [Quests.SPELLS[k].name, Quests.SPELL_MANA], "why": null if sw == "" else sw,
				"name": Quests.SPELLS[k].name, "icon_path": "icons/common/cmd_%s.png" % k, "ok": "Click, then pick a neighboring province" if k == "flamewall" else "Click, then pick a building here",
				"desc": "A wall of fire on the border with a neighboring province for %d s: only your units pass, and nothing can break it. One at a time." % int(Quests.FLAME_TIME) if k == "flamewall"
					else "One building in this province works twice as fast: twice its gold, wood or food, twice its research, soldiers in half the time. Until you warp another."}
	if u.kind == "army" and game.has_art(Game.LOCAL, "slippers"):   # v95: Winged Slippers
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
			var cost: Dictionary = game.bog_cost(u.prov, game.ME, GameData.c("OUTPOST_COST") if type == "outpost" else game.BUILD_DEFS[type].cost)
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
			var planning: bool = u.get("roadPlan") != null or (aim != null and aim.spell == "road" and is_same(aim.unit, u))
			if b == null and planning:   # 0.19: a road being picked, or one he is walking off to pave
				nm = "road"
			cmd = {"id": id, "label": "Cancel build", "why": null if b != null or planning else "He isn’t building anything", "name": ("Cancel the " + nm) if b != null else "Cancel construction",
				"desc": ("Stop building and get back everything paid (%s)." % Game.cost_text(b.get("paid", {}))) if b != null else "When the Mason is building, this stops it and refunds what was paid.", "ok": "Click to cancel and get a refund"}
		elif id == "road":   # 0.19: pick where the road starts and where it ends
			var why = "Research Dirt Roads first" if not game.has_tech("roads") else null
			var picking: bool = aim != null and aim.spell == "road" and is_same(aim.unit, u)
			cmd = {"id": id, "label": "Road\n25g 75w", "why": why, "name": "Build a road" + (" (picking…)" if picking else ""), "cost": GameData.c("ROAD_COST"),
				"desc": "Click the province where the road starts, then the one where it ends: both your own, joined by your own land. The Mason paves every border along the way (%d s and %s each). Units move %d%% faster on roads. Esc, right-click or Cancel stops it before it begins." % [int(Game.ROAD_TIME), Game.cost_text(GameData.c("ROAD_COST")), roundi(game.road_bonus() * 100)]}
		elif id == "advanced":
			var advl: Array = game.CMD.get(Game.MASON + Races.ADV, []).filter(func(x): return str(x.id).begins_with("build:") and game.BUILD_DEFS.has(str(x.id).substr(6)))
			var names: Array = advl.map(func(x): return str(game.BUILD_DEFS[str(x.id).substr(6)].name))
			var ready: int = advl.filter(func(x): return game.build_check(u.prov, str(x.id).substr(6)) == null).size()
			cmd = {"id": id, "label": "Advanced\nbuildings", "why": null, "name": "Advanced Buildings",
				"desc": "The buildings research unlocks: %s.%s" % [", ".join(names), (" %d can be built here now." % ready) if ready else ""], "ok": "Click to open"}
		elif id == "basic":
			cmd = {"id": id, "label": "Back", "why": null, "name": "Back to Buildings", "desc": "The outpost and the buildings that need no research.", "ok": "Click to go back"}
		elif id == "thugin":
			cmd = {"id": id, "label": "Enter den", "why": null if game.extras.keys().any(func(p): return game.den_room_in(p) != null) else "No Thug Den with room",
				"name": "Enter a Thug Den", "desc": "The Thug goes into the Thug Den here, or walks to the nearest one with room. Inside, he makes 1 gold every 10 s."}
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
			var n := game.units.filter(func(v): return v.kind == "army" and v.owner == Game.LOCAL and v.prov == u.prov and not v.moving).size()
			cmd = {"id": id, "label": "Combine", "why": null if n >= 2 else "No other army here", "name": "Combine Armies", "desc": "Merge the armies standing in this province into one."}
		if cmd != null:
			out[int(c.cell)] = cmd
	# quests: Dig (cell 5), and what a scouting unit carries in the bottom row's slot (Godot only)
	if game.quests_on and u.kind == game.WAYFINDER and u.owner == Game.LOCAL and out[5] == null:
		if u.get("dig") != null:
			out[5] = {"id": "stopdig", "label": "Digging…\nstop", "why": null, "name": "Digging", "icon_path": "icons/common/cmd_dig.png", "glow": true,
				"desc": "%s is digging. Every 10 s there is a chance to unearth what lies here; rarer relics take longer." % u.name, "ok": "Click to stop digging"}
		else:
			var dw := Quests.dig_why(game, u)
			out[5] = {"id": "dig", "label": "Dig", "why": null if dw == "" else dw, "name": "Dig", "icon_path": "icons/common/cmd_dig.png",
				"desc": "Dig at the dig site where %s stands (a red X; a silver X for a Fallen Star). He keeps digging until the relic is found or he is moved." % u.name, "ok": "Click to dig"}
	if game.quests_on and u.kind == game.WAYFINDER and u.owner == Game.LOCAL:
		var b: Array = Quests.bag_of(u)
		for i in Quests.carry():
			var cell: int = 12 + i
			if cell <= 14 and out[cell] == null:
				out[cell] = _relic_cell(str(b[i]) if i < b.size() else "", "Carries a relic when no Reliquary has room; it goes into one as soon as one has.")
	return out


## Time Warp: which building in the caster's province (Godot only).
func _open_warp_menu(c: Dictionary) -> void:
	var items := []
	var tw = game.time_warp
	for e in Quests.warp_targets(game, c):
		var slot: int = e.slot
		var on: bool = tw != null and int(tw.p) == int(c.prov) and int(tw.slot) == slot
		items.append({"icon": icon("icons/realm/build_%s.png" % e.type), "name": str(game.BUILD_DEFS[e.type].name) + (" · warped now" if on else ""),
			"small": "Plot %d" % (slot + 1), "why": "Already warped" if on else null, "do": func(): game.do("cast_timewarp", [c, slot])})
	if items.is_empty():
		add_toast("No building here that Time Warp can speed up.", true)
		return
	pick.open("Time Warp", game.prov_name(c.prov), items, card.global_position - Vector2(400, 40))


## A relic slot on the command card: a Reliquary's or what a scouting unit carries. id "" is an empty slot.
func _relic_cell(id: String, empty_desc: String) -> Dictionary:
	if id == "":
		return {"id": "slot", "slot": true, "label": "", "why": null, "name": "Empty slot", "desc": empty_desc, "ok": "Empty"}
	return {"id": "slot", "slot": true, "label": Quests.item_name(id), "why": null, "name": Quests.item_name(id),
		"desc": "A relic from the old world.", "icon_path": "icons/common/item_%s.png" % id, "ok": "Kept safe"}


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
		if game.is_sw():
			desc = "Trains the Berserkers you design at the Armory."
		elif game.is_wd():
			desc = "Trains the Protectors you design at the Armory. With a Hall of Champions in the same province, your Champions too."
		else:
			desc = "Trains the infantry you design in the Armory. With a Stable in the same province, your cavalry designs too."
	elif type == "stable":
		if game.is_sw():
			desc = "Trains Ogres you design at the Armory."
		elif game.is_wd():
			desc = "Lets a Barracks in this province train Champions."
		else:
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
		game.do("order_build", [unit, unit.prov, id.substr(6)])
	elif id == "survey":
		game.do("queue_survey", [unit, unit.prov])
	elif id == "auto":
		var on: bool = tab_units().any(func(w): return w.get("auto", true) != false)
		for w in tab_units():
			w.auto = not on
	elif id == "advanced" or id == "basic":
		mason_adv = id == "advanced"
	elif id == "qspell:flamewall":
		aim = {"unit": unit, "spell": "flamewall"}
		add_toast("Click a province next to the caster: the Wall of Flame rises on that border. Right-click cancels.")
	elif id == "qspell:timewarp":
		_open_warp_menu(unit)
	elif id == "dig":
		game.do("start_dig", [unit])
	elif id == "stopdig":
		game.do("stop_dig", [unit])
	elif id == "cancelbuild":
		if aim != null and aim.spell == "road" and is_same(aim.unit, unit):
			aim = null
			add_toast("Road cancelled.")
			return
		game.do("cancel_build", [unit])
		add_toast("Construction cancelled. Resources refunded.")
	elif id == "road":   # 0.19: the next clicks pick where the road starts and ends
		aim = {"unit": unit, "spell": "road", "start": -1}
		add_toast("Road: click the province where it starts (one of yours). Esc or right-click cancels.")
	elif id == "thugin":
		game.do("thugs_enter", [tab_units().filter(func(w): return w.kind == Game.THUG)])
		set_selection(selection.filter(func(w): return game.units.has(w)))
	elif id == "dismiss":
		if confirm_key != "dismiss:%d" % unit.id:
			confirm_key = "dismiss:%d" % unit.id
			add_toast("Dismiss %s? Press Dismiss again to confirm." % unit.name, true)
			return
		confirm_key = ""
		game.do("dismiss", [[unit]])
		select_unit(null)
	elif id == "fly":
		aim = {"unit": unit, "spell": "fly"}
		add_toast("Click a province next to the army. Right-click cancels.")
	elif id.begins_with("spell2:"):
		var k := id.substr(7)
		if unit.get("quake") and unit.quake.kind == k:
			game.do("end_quake", [unit, "%s stopped." % game.spell2_name(k)])
		elif k == "quake":
			game.do("start_spell2", [unit, "quake"])
		else:
			aim = {"unit": unit, "spell": "shock"}
			add_toast("Click a neighboring province behind an enemy wall. Right-click cancels.")
	elif id.begins_with("spell:"):
		var k := id.substr(6)
		if k in ["rift"] or (k == "eyes" and game.see_nbrs(unit).size() > 1) or (k == "wrocks" and game.see_nbrs(unit, "mountains").size() > 1):
			aim = {"unit": unit, "spell": k}
			add_toast("Click the province to target. Right-click cancels.")
		else:
			game.do("cast_spell", [unit, k])
	elif id == "retreat":
		for a in tab_units().filter(func(v): return v.get("battle") != null and not v.get("retreating", false)):
			game.do("retreat", [a])
	elif id == "rest":
		game.do("send_to_rest", [unit])
	elif id == "retrofit":
		_show_retrofit(unit)
	elif id == "inspect":
		_show_inspect(unit)
	elif id == "split":
		game.do("split_army", [unit])
	elif id == "combine":
		game.do("combine_armies", [game.units.filter(func(v): return v.kind == "army" and v.owner == Game.LOCAL and v.prov == unit.prov and not v.moving)])
	elif id == "join":
		var mages: Array = selection.filter(func(v): return v.kind == game.MAGE and v.owner == Game.LOCAL)
		var a = game.do("mage_join", [mages if not mages.is_empty() else [unit]])
		if a is Dictionary:
			set_selection([a])
	elif id == "detach":
		var m = game.do("mage_detach", [unit])
		if m is Dictionary:
			set_selection([m])


## 0.19: a click while a road is being planned: first its start, then its end (both the player's own provinces).
## A start that isn't yours is refused (nothing more to pick); an end that isn't yours, or with no way there through
## your land, is refused but the start stays.
func road_click(p: int) -> void:
	if aim == null or aim.spell != "road":
		return
	var m = aim.unit
	if not game.units.any(func(v): return is_same(v, m)):
		aim = null
		return
	if int(aim.start) < 0:
		if p < 0 or not game.owned(p):
			Sound.play("ui_deny")
			add_toast("A road has to start in one of your own provinces.", true)
			return
		aim.start = p
		if map:
			map.selected_prov = p
			map.selected_part = ""
		Sound.play("ui_confirm")
		add_toast("Road from %s: now click the province where it ends." % game.prov_name(p))
		return
	if p < 0 or not game.owned(p):
		Sound.play("ui_deny")
		add_toast("A road has to end in one of your own provinces. Pick another end (Esc cancels).", true)
		return
	if p == int(aim.start):
		return
	var path := game.road_path(int(aim.start), p)
	var why := game.road_plan_why(m, path) if not path.is_empty() else "There is no way for a road from %s to %s through your own provinces" % [game.prov_name(int(aim.start)), game.prov_name(p)]
	if why != "":
		Sound.play("ui_deny")
		add_toast(why + ".", true)
		return
	aim = null
	game.do("plan_road", [m, path])


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
	if observer:   # (the map, the minimap, the tooltip and the toasts; nothing of a nation's)
		paused_label.text = "Paused by %s" % game.seat_names.get(game.paused_by, "a player") if game.paused and game.paused_by != 0 else "Paused"
		_hover_tip()
		minimap.position = Vector2(16, topbar.size.y - Minimap.SIZE.y - 16)
		paused_label.position.y = topbar.bottom() + 8.0
		var now0 := Time.get_ticks_msec()
		while not toast_list.is_empty() and toast_list[0].until < now0:
			toast_list.pop_front().label.queue_free()
		return
	if not dialog.visible and not dialog_queue.is_empty():
		var dq: Array = dialog_queue.pop_front()
		dialog.ask(dq[0], dq[1], dq[2], dq[3] if dq[3].is_valid() else func(_id): pass, dq[4])
	paused_label.text = "Paused by %s" % game.seat_names.get(game.paused_by, "a player") if game.paused and game.paused_by != 0 and game.seats.size() > 1 else "Paused"
	if game.school_popup:
		game.do("close_school_popup")
		school.open()
	if prov >= 0:
		panel.refresh(self, game, prov)
	_refresh_actions()
	_refresh_tutorial()
	if research.visible:
		_refresh_research()
	if selection.any(func(v): return not game.units.any(func(w): return is_same(w, v))):
		set_selection(selection.filter(func(v): return game.units.any(func(w): return is_same(w, v))))
	if part != "" and (prov < 0 or not game.owned(prov) or (part != "settlement" and part_extra() == null)):
		select_province(prov if prov >= 0 and game.explored.has(prov) else -1)   # the building is gone
	# the command card is always there; empty when nothing of yours is selected (web: game.js renderCmd)
	card_cmds = commands_of(unit) if unit != null and unit.owner == Game.LOCAL else part_commands()
	for c in card_cmds:
		if c != null and not c.is_empty():
			_decorate(c)
	card.set_cells(card_cmds, _card_tabs())
	_refresh_sel_line()
	_hover_tip()
	_race_tooltip()
	minimap.position = Vector2(16, topbar.size.y - Minimap.SIZE.y - 16)
	msglog.place(Vector2(16 + Minimap.SIZE.x + 12, minimap.position.y), Vector2(Minimap.SIZE.x * 1.6, Minimap.SIZE.y))   # (twice the minimap's width, less a fifth)
	sel_line.position = Vector2(msglog.position.x, msglog.position.y - sel_line.size.y - 6)
	sel_rename.visible = sel_line.visible and unit != null and unit.owner == Game.LOCAL
	sel_rename.position = sel_line.position + Vector2(sel_line.size.x + 4, 0)
	sel_rename.size = Vector2(sel_line.size.y, sel_line.size.y)
	if panel.visible:   # the province menu stands on the minimap's toggles, growing upward (web: #prov)
		panel.reset_size()
		panel.position = Vector2(16, topbar.size.y - 16 - Minimap.SIZE.y - 56 - panel.size.y)
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
				game.do("retrofit_armies", [[a], id]))


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

var menu_btns := {}   # the menu's buttons that depend on the game (save, load, import, end)


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
	menu_btns.save = UiKit.button("Save game (F5)", 20, func():
		if main and main.lock != null:
			main.save_mp()
		elif main and game.tutorial == null:
			main.save_to(main.QUICKSAVE))
	b.add_child(menu_btns.save)
	menu_btns.load = UiKit.button("Load saved game (F9)", 20, func():
		if main:
			toggle_menu()
			main.load_from(main.QUICKSAVE))
	b.add_child(menu_btns.load)
	b.add_child(UiKit.button("Export a save file", 20, func():
		if main and game.tutorial == null:
			main.export_save()))
	menu_btns.import = UiKit.button("Import a save file", 20, func():
		if main:
			toggle_menu()
			main.import_save())
	b.add_child(menu_btns.import)
	b.add_child(UiKit.button("Settings", 20, func(): settings.open(game)))
	b.add_child(UiKit.button("How to Play", 20, func():
		if main:
			main.how_to.open()))
	b.add_child(UiKit.button("Return to main menu", 20, func():
		if main:
			toggle_menu()
			main.to_main_menu()))
	b.add_child(UiKit.button("Quit", 20, func(): get_tree().quit()))
	menu_win.panel.hide()


func toggle_menu() -> void:
	var p: Control = menu_win.panel
	p.visible = not p.visible
	if p.visible:
		# multiplayer: only the host saves (on a server, the server keeps it); nobody loads a single-player game
		var lk = main.lock if main else null
		var lead: bool = lk != null and (lk.is_host or (lk.net != null and lk.net.is_leader()))
		menu_btns.save.visible = (lk == null or lead) and not observer
		menu_btns.save.text = "Save game (F5)" if lk == null else "Save the game on the server" if not lk.is_host else "Save the multiplayer game"
		menu_btns.load.visible = lk == null
		menu_btns.import.visible = lk == null
		UiKit.center.call_deferred(p)
		if game and not observer:
			game.do("set_paused", [true])


func set_ui_scale(v: float) -> void:
	Settings.ui_scale = clampf(v, 0.7, 1.6)
	ui_scale = Settings.ui_scale
	Settings.save_all()
	Settings.apply(get_tree())


func _province_text(p: int) -> String:
	var P: Dictionary = game.G.provs[p]
	var s := "[b]%s[/b] · %s\n" % [game.prov_name(p), game.terrain_name(p).capitalize()]
	if game.variant_of(p) != "":
		s += Game.VARIANT_TEXT[game.variant_of(p)] + "\n"
	if game.setpieces.has(p) and game.sp_known(p):
		var why = game.setpiece_why(p)
		var D: Dictionary = game.SETPIECES[game.setpieces[p]]
		s += "%s: +%d %s research%s\n" % [D.name, D.pts, {"gov": "Government", "mil": "Military", "mag": "Magic"}[D.tree], "" if why == null else " (%s)" % why]
	if game.buildings.has(p):
		var b: Dictionary = game.buildings[p]
		var o: int = b.owner
		var stage_name: String = "Conquered Capital" if b.get("cc", false) else STAGE_NAME[b.stage]
		s += "%s (%s)\n" % [stage_name, "yours" if o == Game.LOCAL else "the " + game.player_info(o).name]
		if game.occ.has(p):
			s += "[color=#b3261e]Occupied by %s[/color]\n" % ("you" if game.occ[p] == Game.LOCAL else "the " + game.player_info(game.occ[p]).name)
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
		if u.prov == p and (u.owner == Game.LOCAL or game.visible.has(p)):
			var whose := "" if u.owner == Game.LOCAL or u.owner == Game.RAIDERS else " (%s)" % game.player_info(u.owner).name
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
	if unit != null and game.is_caster(unit) and unit.prov == prov:
		rows.append({"label": "%s: %d / %d mana%s" % [unit.name, int(Game.mana_of(unit)), game.mana_cap(), (" · casting " + str(unit.cast.spell).trim_prefix("q:")) if unit.get("cast") != null else ""]})
		for q in game.all_nbr[prov]:
			for kind in ["forest", "tunnel"]:
				if not game.lvl(kind):
					continue
				var why = game.path_why(unit, q, kind, false)
				if why == null or str(why).begins_with("Not enough mana"):
					rows.append({"btn": "Open a %s to province %d (200 mana)" % ["forest path" if kind == "forest" else "tunnel", q], "why": why, "do": func(): game.do("start_path", [unit, q, kind, false])})
	if unit != null and unit.kind == Game.MASON and unit.prov == prov and not unit.moving:
		rows.append({"label": ("%s: roads and walls to a neighbour" % game.unit_defs[game.MASON].name) if game.race() == "realm" else ("%s: walls to a neighbour" % game.unit_defs[game.MASON].name)})
		for q in game.all_nbr[prov]:
			for type in ["road", "wall"]:
				var why = game.link_why(type, unit, q)
				if why != null and not str(why).begins_with("Need"):
					continue   # only the links he could build now (or with more resources)
				var cost: Dictionary = GameData.c("ROAD_COST") if type == "road" else GameData.c("WALL_COST")
				rows.append({"btn": "%s to province %d (%s)" % [type.capitalize(), q, Game.cost_text(cost)], "why": why, "do": func(): game.do("start_link", [unit, q, type])})
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
			l.add_theme_color_override("font_color", Color("#5a6475"))
			l.add_theme_font_size_override("font_size", 13)
			actions.add_child(l)
		else:
			var b := Button.new()
			b.text = r.btn
			b.add_theme_font_size_override("font_size", 14)
			b.disabled = r.why != null
			var tip := UiKit.wrap(str(r.get("tip", ""))) if r.get("tip", "") != "" else ""
			if r.why != null:
				tip += ("\n" if tip != "" else "") + "✗ " + str(r.why)
			b.tooltip_text = tip
			var f: Callable = r.do
			b.pressed.connect(func(): f.call())
			actions.add_child(b)


# --- the command card's look: icons, colors and progress (web: game.js cmdInfo(...).icon, v78.js cmdBg) ---

const BUILD_BG := {"outpost": "#a3a9b3", "farm": "#2aa198", "lumber": "#2e6b34", "goldmine": "#f0a62e", "barracks": "#ef2b2b", "stable": "#8c1c3a", "market": "#d9bf8f",
	"granary": "#36d6e8", "storehouse": "#b58a58", "bank": "#ffe62e", "forge": "#e8552a", "magetower": "#3f6fe0", "temple": "#9a5fd6"}
static var _tex := {}


## A leader's portrait, whatever his race (they live in their race's own folder).
static func leader_icon(id) -> Texture2D:
	if id == null:
		return null
	for rc in ["realm", "swamp", "wood"]:
		var p := "icons/%s/leader_%s.png" % [rc, id]
		if not _tex.has(p):
			_tex[p] = load("res://assets/art/" + p) if ResourceLoader.exists("res://assets/art/" + p) else null
		if _tex[p] != null:
			return _tex[p]
	return null


static func icon(path: String) -> Texture2D:
	if Art.player_race != "realm":   # the player's race's own icons first (Swampling buildings, Woodling units...)
		var rp := ""
		if path.begins_with("icons/realm/"):
			rp = "icons/%s/%s" % [Art.player_race, path.substr(12)]
		elif path.begins_with("icons/common/cmd_"):
			rp = "icons/%s/%s" % [Art.player_race, path.substr(13)]
		if rp != "":
			if not _tex.has(rp):
				_tex[rp] = load("res://assets/art/" + rp) if ResourceLoader.exists("res://assets/art/" + rp) else null
			if _tex[rp] != null:
				return _tex[rp]
	if not _tex.has(path):
		var full := "res://assets/art/" + path
		_tex[path] = load(full) if ResourceLoader.exists(full) else null
	return _tex[path]


## A unit's portrait (web: game.js portrait)
func unit_icon(kind: String) -> Texture2D:
	var t := icon("icons/realm/unit_%s.png" % kind.replace(":", "_").replace("-", "_").to_lower())
	if t == null:   # an Armory design: the portrait of the starting design of its weapon family
		t = icon("icons/realm/unit_%s.png" % Art.design_art(game, kind).replace("-", "_"))
	if t == null:
		t = icon("icons/realm/unit_mage_a.png") if kind == game.MAGE else icon("icons/realm/unit_d_sword.png")
	return t


func _decorate(c: Dictionary) -> void:
	var id: String = c.get("id", "")
	var tex: Texture2D = null
	if id.begins_with("queue:"):
		tex = unit_icon(c.kind)
	elif c.has("icon_path"):
		tex = icon(c.icon_path)
	elif id.begins_with("build:"):
		var type := id.substr(6)
		tex = icon("icons/common/cmd_build_%s.png" % type)
		var d: Dictionary = game.BUILD_DEFS.get(type, {})
		if BUILD_BG.has(type) and (d.get("tech") == null or game.has_tech(d.tech)):
			c.bg = Color(BUILD_BG[type])
	elif id.begins_with("train:"):
		tex = unit_icon(id.substr(6))
	elif id.begins_with("spell:"):
		tex = icon("icons/realm/tech_%s.png" % game.line_tech(id.substr(6)))
	elif id.begins_with("spell2:"):
		tex = icon("icons/common/cmd_%s.png" % id.substr(7))
	elif id == "fly":
		tex = icon("icons/common/ui_slippers.png")
	elif id in ["upgrade", "cancelup"]:
		tex = icon("icons/realm/settle_1.png")
	elif id in ["destroy", "dismantle"]:
		tex = icon("icons/common/cmd_destroy.png")
	elif id == "develop":
		tex = icon("icons/common/ui_dev.png")
	elif id == "xpath":
		tex = icon("icons/common/cmd_path.png")
	else:
		tex = icon("icons/common/cmd_%s.png" % id)
	c.icon = tex


## The tabs over the card: what is selected (web: game.js #cmdTabs)
func _card_tabs() -> Array:
	var kinds := sel_kinds()
	if kinds.size() > 1:   # several kinds: a tab for each, with how many (web: renderCmd .cmd-tab)
		var out := []
		for k in kinds:
			var n := selection.filter(func(v): return v.kind == k).size()
			var nm: String = ("Armies" if n > 1 else "Army") if k == "army" else str(game.unit_defs[k].name) + ("s" if n > 1 else "") if game.unit_defs.has(k) else k
			var pk: String = k
			if k == "army":
				var a = selection.filter(func(v): return v.kind == k)[0]
				for tk in a.troops:
					pk = tk
					break
			out.append({"text": ("%d " % n if n > 1 else "") + nm, "icon": unit_icon(pk), "on": k == cmd_tab, "id": k})
		return out
	if unit != null and unit.owner == Game.LOCAL:
		var nm: String = "Army" if unit.kind == "army" else str(game.unit_defs[unit.kind].name) if game.unit_defs.has(unit.kind) else unit.kind
		var pk: String = unit.kind
		if unit.kind == "army":
			for k in unit.troops:
				if unit.troops[k] > 0:
					pk = k
					break
		return [{"text": nm, "icon": unit_icon(pk), "on": true}]
	if prov >= 0 and part != "" and game.owned(prov):
		if part == "settlement":
			var b: Dictionary = game.buildings[prov]
			return [{"text": "Conquered Capital" if b.get("cc", false) else STAGE_NAME[b.stage], "icon": icon("icons/realm/settle_%d.png" % (2 if b.get("cc", false) else b.stage)), "on": true}]
		var e = part_extra()
		if e != null:
			var d: Dictionary = game.BUILD_DEFS[e.type]
			var lv: int = e.get("level", 1)
			var nm2: String = str(d.levels[lv - 1]) if d.has("levels") else ("Farm: " + Ai.crop_name(Ai.crop_of(e))) if e.type == "farm" else str(d.name)
			var ic := icon("icons/realm/build_%s_l%d.png" % [e.type, lv]) if d.has("levels") else icon("icons/realm/build_%s.png" % e.type)
			return [{"text": nm2, "icon": ic, "on": true}]
	return []


## web: game.js selUI, unitStatus
func _refresh_sel_line() -> void:
	var txt := ""
	if selection.size() > 1:   # web: selUI "<b>N units</b> · name (status) · …"
		txt = "%d units · %s" % [selection.size(), " · ".join(selection.map(func(v): return "%s (%s)" % [v.name, _status(v)]))]
		if txt.length() > 150:
			txt = txt.left(147) + "…"
		sel_line.tooltip_text = "Right-click a province to move them together. Hold Shift to queue moves. Ctrl+right-click opens the survey and build menu."
	elif unit != null and unit.owner == Game.LOCAL:
		if unit.kind == "army":
			var st := "in battle" if unit.get("battle") != null and not unit.get("retreating", false) else "retreating" if unit.get("retreating", false) else _status(unit)
			var parts := []
			for k in unit.troops:
				if unit.troops[k] > 0:
					parts.append("%d %s" % [unit.troops[k], game.unit_defs[k].name if game.unit_defs.has(k) else k])
			txt = "%s · %s · %s · power %s" % [unit.name, st, ", ".join(parts), UiKit.num(maxf(1, roundf(game.raw_strength([unit]) * 10)))]
			sel_line.tooltip_text = "Right-click a province to move. R retreats from a battle. Hold Shift to queue moves."
		else:
			var role := (" the " + str(game.unit_defs[unit.kind].name)) if unit.kind in [game.WAYFINDER, Game.MASON] else ""
			txt = "%s%s · %s" % [unit.name, role, _status(unit)]
			sel_line.tooltip_text = "Can enter unexplored land. Right-click to move. Q surveys the province he is in." if unit.kind == game.WAYFINDER \
				else "Walks on explored land only. Right-click to move. Q builds an outpost." if unit.kind == Game.MASON else "Walks on explored land only. Right-click a province to move."
	elif prov >= 0 and part_src() != "":
		var n: int = game.queues.get("%s:%d" % [part_src(), prov], []).size()
		txt = "%s · %s" % [{"capital": "Capital", "barracks": "Barracks", "magetower": "Mage Tower"}[part_src()], ("%d in training" % n) if n else "ready to train"]
		sel_line.tooltip_text = "Train units from the command card. Hover a button for its cost."
	sel_line.visible = txt != ""
	if sel_line.text != txt:
		sel_line.text = txt
		sel_line.reset_size()


## The province under the mouse, in a card by the pointer. web: game.js hoverAt
## Tooltips wait until the mouse has rested this long (the interface's own use the same delay: project.godot).
const TIP_DELAY := 5.0
var _tip_mouse := Vector2(-1, -1)
var _tip_rest := 0.0

func _hover_tip() -> void:
	var mp0 := get_viewport().get_mouse_position()
	if mp0.distance_to(_tip_mouse) > 2.0:   # the mouse moved: start waiting again
		_tip_mouse = mp0
		_tip_rest = 0.0
	else:
		_tip_rest += get_process_delta_time()
	var over_ui := get_viewport().gui_get_hovered_control() != null
	var p := -1
	if not over_ui and map != null and not dragging_map() and _tip_rest >= TIP_DELAY:
		p = map.province_at(map.get_global_mouse_position())
	if p < 0:
		tip.hide()
		tip_key = ""
		return
	var st := game.fog_state(p)
	var P: Dictionary = game.G.provs[p]
	var b = game.buildings.get(p) if game.visible.has(p) else null
	var y: Dictionary = game.yields[p]
	var k := "%d|%s|%s|%s|%s" % [p, st, b, game.surveyed.has(p), game.extras_in(p).size() if game.visible.has(p) else -1]
	if k != tip_key:
		tip_key = k
		var t := ""
		if st == "unexplored":
			t = "[b]Unexplored[/b]\nOnly a Wayfinder can go here."
		else:
			t = "[b]%s[/b]\n%s%s" % [game.terrain_name(p).capitalize(), "Visible" if st == "visible" else "Explored · contents unknown", (" · " + ("Conquered Capital" if b.get("cc", false) else STAGE_NAME[b.stage])) if b != null else ""]
			if not game.owned(p):
				t += "\n" + ("Outpost allowed here" if game.borders_owned(p) else "Too far from your land for an outpost")
			else:
				var ex := game.extras_in(p)
				t += "\nYours · %d/%d buildings%s" % [ex.size(), game.plot_cap(p), (": " + ", ".join(ex.map(func(e): return game.BUILD_DEFS[e.type].name))) if not ex.is_empty() else ""]
			if game.surveyed.has(p):
				t += "\nEvery 10 s: " + ", ".join(["gold", "wood", "food"].map(func(r): return "%d %s%s" % [y[r], r, (" (bonus +%d)" % y.bonus[r]) if y.get("bonus", {}).get(r, 0) else ""]))
				if y.get("deposit", false):
					t += "\n[color=#a67c00]Hidden Gold Deposit · a Gold Mine can be built[/color]"
			else:
				t += "\nResources unknown · survey it with a Wayfinder"
			if game.visible.has(p) and game.owned(p) and game.extras_in(p).any(func(e): return game.BUILD_DEFS[e.type].get("gives") != null):
				var x := game.extras_bonus(p)
				t += "\n[color=#1f7a2e]Buildings add %s[/color]" % ", ".join(["gold", "wood", "food"].filter(func(r): return x[r]).map(func(r): return "+%d %s" % [x[r], r]))
			var tb: int = game.tree_border[p]
			if tb:
				t += "\n%d tree border%s · room for %d Lumber Mill%s" % [tb, "s" if tb > 1 else "", tb, "s" if tb > 1 else ""]
		tip_text.text = UiKit.res_icons(t, true)   # 0.19: the resources as icons
		tip.reset_size()
	tip.show()
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport().get_visible_rect().size
	tip.position = Vector2(minf(mp.x + 18, vs.x - tip.size.x - 30), minf(mp.y + 18, vs.y - tip.size.y - 30))


## Every tooltip speaks the player's race (Swampwright, not Mason; Ogres, not cavalry): the one under the mouse is
## put into the race's words before it shows (and again if its text changes).
func _race_tooltip() -> void:
	if Art.player_race == "realm":
		return
	var c := get_viewport().gui_get_hovered_control()
	while c != null:
		if c.tooltip_text != "":
			if c.get_meta("_rt", "") != c.tooltip_text:
				c.tooltip_text = Races.words(c.tooltip_text, Art.player_race)
				c.set_meta("_rt", c.tooltip_text)
			return
		c = c.get_parent() as Control


func dragging_map() -> bool:
	return main != null and main.get("dragging") == true and main.get("drag_moved") > 6.0


## What a worker is doing. web: game.js unitStatus
func _status(u: Dictionary) -> String:
	if u.get("scouting") != null:
		return "exploring (takes orders once done)"
	var nsv: int = u.surveyQueue.filter(func(e): return e is int).size() + (1 if u.pendingSurvey >= 0 else 0) if u.has("surveyQueue") else 0
	var nmv: int = u.surveyQueue.filter(func(e): return not (e is int)).size() if u.has("surveyQueue") else 0
	if nsv and u.get("survey") == null:
		return "heading to survey (%d queued)" % nsv
	if nmv:
		return "on the move (%d more queued)" % nmv
	if u.get("survey") != null:
		return "surveying"
	if u.get("build") != null:
		var bt: String = u.build.type
		return "building " + ("an outpost" if bt == "outpost" else "a wall back up" if bt == "rewall" else ("a " + bt) if bt in ["road", "wall", "bridge"] else str(game.BUILD_DEFS[bt].name) if game.BUILD_DEFS.has(bt) else bt)
	if u.get("dig") != null:
		return "digging"
	if u.get("pending") != null:
		return "going to build"
	if u.get("cast") != null:
		return "casting"
	if u.moving:
		return "marching" if u.kind == "army" else "walking"
	return "idle"


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
	if e != null and game.is_sw() and e.type in ["market", "stable"]:   # web: swamp.js (Thug Den, Ogre Cave)
		return e.type
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
			out[12 + i] = {"id": "queue:%d" % i, "label": "%d. %s%s" % [i + 1, nm, ("\n%d%%" % int(f * 100)) if i == 0 else ""], "why": null, "q": true, "n": i + 1,
				"icon_path": "", "prog": f if i == 0 else null, "kind": q.kind,
				"name": "%s%s in %s" % ["Retrofit to " if q.get("retro", false) else "", nm, "training" if i == 0 else "the queue"], "desc": "Click to cancel and get back what was paid.", "ok": "Click to cancel"}
		if Q.size() > 4:
			out[15] = {"id": "noop", "label": "+%d more" % (Q.size() - 3), "why": "", "name": "%d more in the queue" % (Q.size() - 3)}
		if src == "magetower":
			out[3] = _xup_cmd(part_extra())
		if src == "market":   # web: swamp.js extraCmdInfo 'thugout'
			var de = part_extra()
			var nt: int = int(de.get("thugs", 0))
			out[3] = {"id": "thugout", "label": "Thugs %d/%d\nstep out" % [nt, game.den_cap()], "why": null if nt > 0 else "No Thug inside", "name": "A Thug steps out",
				"desc": "Each Thug inside makes 1 gold every 10 s (twice that with Highwaymen if the den borders another nation). Click to let one out.", "ok": "Click to let one out"}
		return out
	if part == "settlement":
		var b: Dictionary = game.buildings[prov]
		var up = game.upgrades.get(prov)
		var FU: Dictionary = GameData.c("FORT_UPGRADE")
		if b.stage == 0:
			if up != null:
				var left := ceili(FU.time - (game.t - up.t0))
				out[0] = {"id": "cancelup", "label": "Upgrading\n%d s · cancel" % left, "why": null, "name": "Upgrading to Fort", "cost": up.paid, "prog": clampf((game.t - up.t0) / FU.time, 0, 1),
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
			out[1] = {"id": "develop", "label": "Developing\n%d%%" % int(dr.job.done / GameData.c("DEV").time * 100), "why": "Already developing", "q": true, "prog": dr.job.done / GameData.c("DEV").time, "name": "Developing to level %d…" % (lv + 1),
				"desc": "%d s left%s." % [ceili(GameData.c("DEV").time - dr.job.done), " (stalled: hostile soldiers in the province)" if dr.job.get("stall", false) else ""]}
		elif lv >= GameData.c("DEV").max:
			out[1] = {"id": "develop", "label": "Fully\ndeveloped", "why": "Fully developed", "name": "Fully developed"}
		else:
			out[1] = {"id": "develop", "label": "Develop\n%s" % _short_cost(game.dev_cost(lv)), "why": game.dev_why(prov), "name": "Develop further", "cost": game.dev_cost(lv), "desc": _dev_desc(lv)}
		return out
	var e = part_extra()
	if e == null:
		return out
	if e.type == "farm":   # web: v104.js the Farm's card: its crop, and "Apply to all" with a confirm
		out[0] = _crop_cmd(e, "crop")
		out[4] = _crop_cmd(e, "cropall")
		if _crop_armed():
			out[5] = _crop_cmd(e, "cropok")
	if game.BUILD_DEFS[e.type].has("levels"):   # a Forge: its next upgrade
		out[0] = _xup_cmd(e)
	if e.type == Dungeons.DUNGEON:   # its 3 cells: each prisoner's silhouette (Godot only)
		var held: Array = Dungeons.held_in(e)
		for i in Dungeons.SLOTS:
			if i < held.size():
				var pr: Dictionary = held[i]
				out[i] = {"id": "slot", "slot": true, "label": str(pr.name), "why": null, "name": "%s (%s)" % [pr.name, game.player_info(int(pr.from)).name if int(pr.from) else "outlaw"],
					"desc": "A prisoner in your Dungeon.", "icon_path": "icons/common/prisoner_%s.png" % pr.kind, "ok": "Locked up"}
			else:
				out[i] = {"id": "slot", "slot": true, "label": "", "why": null, "name": "Empty cell", "desc": "An empty cell for a prisoner.", "ok": "Empty"}
	if e.type == Quests.RELIQUARY:   # its slots, the top-left 3×3 of the card
		var its: Array = Quests.items_in(e)
		var cells := [0, 1, 2, 4, 5, 6, 8, 9, 10]
		for i in cells.size():
			out[cells[i]] = _relic_cell(str(its[i]) if i < its.size() else "", "An empty slot: the next relic your nation finds goes here.")
	var nm2: String = game.BUILD_DEFS[e.type].name
	out[15] = {"id": "destroy", "label": "Tear down", "why": null, "name": "Tear down the " + nm2,
		"desc": "Tear down this %s to free its plot. No refund; its upkeep stops. Click twice to confirm." % nm2}
	return out


func _crop_armed() -> bool:
	return not crop_arm.is_empty() and crop_arm.p == prov and part.ends_with("@%d" % crop_arm.slot) and Time.get_ticks_msec() - crop_arm.t < 8000


static func _crop_line(g: Game, c: String) -> String:
	var gv := Ai.crop_gives(c, g.gives_of("farm"))
	var up := Ai.crop_up(g, c)
	return ", ".join(gv.keys().map(func(k): return "+%d %s" % [gv[k], k])) + ((", %d wood upkeep" % up) if up else ", no upkeep")


## web: v104.js cmdInfo('crop' | 'cropall' | 'cropok')
func _crop_cmd(e: Dictionary, id: String) -> Dictionary:
	var t := Ai.crop_target(e)
	var nm := Ai.crop_name(t)
	if id == "crop":
		var desc := ""
		for c in ["staple", "cash", "fiber"]:
			desc += "\n%s (%s): %s%s" % [Ai.crop_name(c), Ai.CROP_KIND[c].to_lower(), _crop_line(game, c), ". One per province" if c == "fiber" else ". Farm research adds to it" if c == "staple" else ""]
		desc += "\nA new crop takes %d s and counts from the payout after that." % int(Ai.CROP_DELAY)
		return {"id": "crop", "label": "Crop\n" + nm, "why": null, "name": "Crop: %s%s" % [Ai.crop_name(Ai.crop_of(e)), (" → %s in %d s" % [nm, maxi(0, ceili(e.cropAt - game.t))]) if e.has("cropNext") else ""],
			"desc": desc.strip_edges(), "ok": "Click to choose a crop", "icon_path": "icons/common/ui_crop_%s.png" % t,
			"prog": clampf(1 - (e.cropAt - game.t) / Ai.CROP_DELAY, 0, 1) if e.has("cropNext") else null}
	var plan: Dictionary = Ai.crop_all_plan(game, t)
	var n: int = plan.plan.size()
	var why = null if n else (("Every province with a Farm already grows " + nm) if t == "fiber" else ("Every Farm already grows " + nm))
	var dtxt := ", ".join(["gold", "wood", "food"].filter(func(k): return plan.d[k] != 0).map(func(k): return "%s%d %s" % ["+" if plan.d[k] > 0 else "−", absi(plan.d[k]), k]))
	if dtxt == "":
		dtxt = "no change"
	if id == "cropall":
		return {"id": "cropall", "label": "Apply\nto all", "why": why, "name": "Apply to all: " + nm, "icon_path": "icons/common/ui_crop_all.png", "glow": _crop_armed(),
			"desc": "Plant %s in every Farm you own%s. %d Farm%s would change: %s every 10 s." % [nm, " (one per province, the Farm that loses the least food)" if t == "fiber" else "", n, "" if n == 1 else "s", dtxt],
			"ok": "Click the green button next to it to confirm" if _crop_armed() else "Click, then confirm"}
	return {"id": "cropok", "label": "Confirm", "why": why, "name": "Confirm: %d Farm%s to %s" % [n, "" if n == 1 else "s", nm], "icon_path": "icons/common/ui_crop_ok.png", "glow": true,
		"desc": "Every 10 s: %s%s. Takes %d s." % [dtxt, ". Your food income would be negative." if game.income.food + plan.d.food < 0 else "", int(Ai.CROP_DELAY)], "ok": "Click to apply"}


## The crop choice beside the card. web: v104.js cmdUse('crop'), popNearCard
func _open_crop_menu(e: Dictionary) -> void:
	var p0 := prov
	var items := []
	for c in ["staple", "cash", "fiber"]:
		var no := ("%s already grows %s" % [game.prov_name(p0), Ai.crop_name("fiber")]) if c == "fiber" and Ai.crop_target(e) != "fiber" and Ai.fiber_taken(game, p0, e) else ""
		var cur := " · grows now" if Ai.crop_of(e) == c else " · on its way" if e.get("cropNext") == c else ""
		items.append({"icon": icon("icons/common/ui_crop_%s.png" % c), "name": Ai.crop_name(c) + cur, "small": "%s: %s%s" % [Ai.CROP_KIND[c], _crop_line(game, c), " · one per province" if c == "fiber" else ""],
			"why": no if no != "" else null, "do": func():
				game.do("set_crop", [p0, e.slot, c])
				add_toast(("The Farm keeps growing %s." % Ai.crop_name(c)) if Ai.crop_of(e) == c and not e.has("cropNext") else ("The Farm will grow %s in %d s." % [Ai.crop_name(c), int(Ai.CROP_DELAY)]))})
	pick.open("Crop for this Farm", "%s · changes in %d s" % [game.prov_name(p0), int(Ai.CROP_DELAY)], items, card.global_position - Vector2(400, 40))


## Build on an empty plot: the nearest free Mason walks over. web: game.js openPlotMenu
func open_plot_menu(p0: int, slot: int, anchor: Control) -> void:
	var m = game.nearest_mason(p0)
	var T: String = game.terrain_name(p0).capitalize()
	var order: Array = game.BUILD_ORDER.filter(func(t): return game.BUILD_DEFS.has(t))
	order.sort_custom(func(a, b): return int(game.build_check(p0, a) == null) > int(game.build_check(p0, b) == null))
	var items := []
	for type in order:
		var d: Dictionary = game.BUILD_DEFS[type]
		var why = "No free Mason" if m == null else game.build_check(p0, type)
		var cap_note := (" · %d/%d here" % [game.count_of(p0, type), game.build_cap(p0, type)]) if game.build_cap(p0, type) > 1 else ""
		var gv := game.gives_of(type)
		var extra := (" · " + ", ".join(gv.keys().map(func(k): return "+%d %s" % [gv[k], k]))) if not gv.is_empty() else (" · " + str(d.note)) if d.get("note") else ""
		var small := "" if m == null else ("%s · %d s%s%s" % ["Build now" if m.prov == p0 else "Send " + m.name, int(game.build_time(type)), cap_note, extra])
		var tt: String = type
		items.append({"icon": icon("icons/realm/build_%s.png" % type), "bg": Color(BUILD_BG[type]) if BUILD_BG.has(type) and (d.get("tech") == null or game.has_tech(d.tech)) else Color(0, 0, 0, 0),
			"name": d.name, "small": small, "cost": d.cost, "why": why, "do": func():
				var mm = game.nearest_mason(p0)
				if mm == null:
					add_toast("Every Mason is busy.", true)
					return
				game.do("order_build", [mm, p0, tt, slot])})
	var at := Vector2(panel.global_position.x + panel.size.x + 10, anchor.global_position.y - 40)
	pick.open("Build on plot %d" % (slot + 1), "%s · %s" % [T, ((m.name + " is here") if m.prov == p0 else (m.name + " will walk over")) if m != null else "every Mason is busy"], items, at,
		"" if m != null else "Train a Mason at your capital, or wait for one to finish.")


## The survey / build menu (Ctrl+right-click a province with a Wayfinder, Mason or caster selected; a plain
## right-click with Quick queue on): move here, survey, what the Mason can build there, a road or wall on the
## border he stands by, and a caster's forest paths and tunnels. Shift (held when opening or picking) queues.
## web: game.js openBuildMenu, linkRows, the #bmenu clicks; magic.js magicRows
func open_build_menu(p: int, at: Vector2, shift: bool, pt: Vector2) -> void:
	var sel := selection.filter(func(v): return v.owner == Game.LOCAL)
	var m = null
	var w = null
	var c = null
	for v in sel:
		if v.kind == Game.MASON and m == null:
			m = v
		if v.kind == game.WAYFINDER and w == null:
			w = v
		if game.is_caster(v) and c == null:
			c = v
	var types: Array = [] if m == null or not game.explored.has(p) else (game.BUILD_ORDER.filter(func(ty): return game.BUILD_DEFS.has(ty)) if game.owned(p) else ["outpost"])
	var ws := sel.filter(func(v): return v.kind == game.WAYFINDER)
	var items := []
	var all_w := sel.all(func(v): return v.kind == game.WAYFINDER)
	var sh := func(): return shift or Input.is_key_pressed(KEY_SHIFT)
	items.append({"glyph": "➜", "name": ("Queue explore" if shift else "Explore") if all_w else ("Queue move here" if shift else "Move here"),
		"small": "Add to the end of the order list" if shift else "Shift to queue", "do": func():
			var mine := selection.filter(func(v): return v.owner == Game.LOCAL)
			var mr = game.do("order_group", [mine, p, sh.call(), [pt.x, pt.y] if map.province_at(pt) == p else null])
			var moved: Array = mr if mr is Array else mine
			if not moved.is_empty() and main:
				main.mark_move(pt)
				Sound.move(moved)})
	if w != null:
		var why = game.survey_why(p, ws)
		var qn := 0
		for v in ws:
			qn += v.surveyQueue.size() + (1 if v.pendingSurvey >= 0 else 0) + (1 if v.survey != null else 0)
		items.append({"icon": icon("icons/common/cmd_survey.png"), "name": "Queue survey" if shift else "Survey", "why": why,
			"small": ("Add to the list (%d already)" % qn) if shift else ("Survey this province" if w.prov == p else "Walk there and survey") + " · Shift to queue",
			"do": func(): game.do("queue_survey_on", [selection.filter(func(v): return v.kind == game.WAYFINDER and v.owner == Game.LOCAL), p, sh.call()])})
	if not types.is_empty():
		items.append({"sec": "Build"})
	for type in types:
		var d: Dictionary = {"name": "Outpost", "cost": GameData.c("OUTPOST_COST")} if type == "outpost" else game.BUILD_DEFS[type]
		var why = game.build_check(p, type)
		var cap_note := (" · %d/%d here" % [game.count_of(p, type), game.build_cap(p, type)]) if type != "outpost" and game.build_cap(p, type) > 1 else ""
		var gv := {} if type == "outpost" else game.gives_of(type)
		var extra := (" · " + ", ".join(gv.keys().map(func(k): return "+%s %s" % [UiKit.num(gv[k]), k]))) if not gv.is_empty() else (" · " + str(d.note)) if d.get("note") else ""
		var tt: String = type
		items.append({"icon": icon("icons/common/cmd_build_%s.png" % type), "bg": Color(BUILD_BG[type]) if BUILD_BG.has(type) and (d.get("tech") == null or game.has_tech(d.tech)) else Color(0, 0, 0, 0),
			"name": d.name, "small": "Build here · %d s%s%s" % [int(game.build_time(type)), cap_note, extra], "cost": d.cost, "why": why,
			"do": func():
				var mm = selection.filter(func(v): return v.kind == Game.MASON and v.owner == Game.LOCAL)
				if not mm.is_empty():
					game.do("order_build", [mm[0], p, tt])})
	# a road or wall on the border between where the Mason stands and the clicked province (web: linkRows)
	if m != null and (game.has_tech("roads") or game.has_tech("walls")) and m.prov != p:
		var rows := []
		for type in ["road", "wall"]:
			if not game.has_tech("roads" if type == "road" else "walls") or not game.open_between(m.prov, p):
				continue
			var why = game.link_why(type, m, p)
			var stone: bool = game.wall_kind() == "stone"
			var label: String = ("Road to %s" % game.prov_name(p)) if type == "road" else ("%s to %s" % ["Stone wall" if stone else "Palisade", game.prov_name(p)])
			var ok: String = ("From %s · %d s · units move faster on roads" % [game.prov_name(m.prov), int(Game.ROAD_TIME)]) if type == "road" else ("Closes the border with %s; its gate lets your units through · %d s" % [game.prov_name(m.prov), int(Game.WALL_TIME)])
			var ty2: String = type
			var mm2 = m
			rows.append({"icon": icon("icons/common/cmd_%s.png" % type), "name": label, "small": ok, "why": why, "cost": GameData.c("ROAD_COST") if type == "road" else GameData.c("WALL_COST"),
				"do": func(): game.do("start_link", [mm2, p, ty2])})
		if not rows.is_empty():
			items.append({"sec": "Border with " + game.prov_name(m.prov)})
			items.append_array(rows)
		elif not game.all_nbr[m.prov].has(p):
			items.append({"note": "Stand the Mason in a neighboring province to build a road or wall on this border."})
	# a caster's forest paths and tunnels (web: magic.js magicRows)
	if c != null and c.prov != p and game.all_nbr[c.prov].has(p):
		var rows := []
		var has_path := func(kind: String) -> bool:
			for i in game.paths:
				var e: Dictionary = game.world.edges[int(i)]
				if game.paths[i] == kind and [e.a, e.b].has(p) and [e.a, e.b].has(c.prov):
					return true
			return false
		for spec in [["forest", false, "Open a forest path to %s", "trees"], ["forest", true, "Close the forest path to %s", ""], ["tunnel", false, "Open a tunnel to %s", "mountains"], ["tunnel", true, "Seal the tunnel to %s", ""]]:
			var kind: String = spec[0]
			var close: bool = spec[1]
			if close and (game.lvl(kind) < 3 or not has_path.call(kind)):
				continue
			if not close and (not game.lvl(kind) or game._edge_between(c.prov, p, spec[3], false) < 0):
				continue
			var why = game.path_why(c, p, kind, close)
			var cc = c
			rows.append({"icon": icon("icons/realm/tech_%s.png" % (("arboreal" if kind == "forest" else "sealed") if close else game.line_tech(kind))), "name": spec[2] % game.prov_name(p),
				"small": "%d s of casting" % (Game.PATH_CLOSE if close else Game.PATH_OPEN[game.lvl(kind)]), "why": why, "do": func(): game.do("start_path", [cc, p, kind, close])})
		if not rows.is_empty():
			items.append({"sec": "Magic"})
			items.append_array(rows)
	var n := game.extras_in(p).size()
	var head_sub := ("%d/%d buildings" % [n, game.plot_cap(p)]) if game.owned(p) and m != null else ""
	if m != null and m.prov != p and not types.is_empty():
		head_sub += " · Mason will walk there"
	pick.open(game.terrain_name(p).capitalize() if game.explored.has(p) else "Unexplored", head_sub, items, at,
		"Build an outpost first to unlock farms, mills, mines and more." if m != null and not types.is_empty() and not game.owned(p) else "")


func _xup_cmd(e) -> Dictionary:
	if e == null:
		return {}
	var d: Dictionary = game.BUILD_DEFS[e.type]
	var lv: int = e.get("level", 1)
	var k := "%d@%d" % [prov, e.slot]
	if game.xup.has(k):
		var xu: Dictionary = game.xup[k]
		var left := ceili(d.ups[xu.to - 1].time - (game.t - xu.t0))
		return {"id": "xcancel", "label": "Upgrading\n%d s · cancel" % left, "why": null, "name": "Upgrading to " + str(d.levels[lv]), "cost": xu.get("paid"), "prog": clampf((game.t - xu.t0) / d.ups[xu.to - 1].time, 0, 1),
			"icon_path": "icons/realm/build_%s_l%d.png" % [e.type, lv + 1],
			"desc": "Ready in %d s. Click to cancel and get the resources back." % left, "ok": "Click to cancel"}
	if lv >= d.levels.size():
		return {"id": "xup", "label": "Fully\nupgraded", "why": "Fully upgraded", "name": str(d.levels[lv - 1])}
	return {"id": "xup", "label": "Upgrade\n%s" % _short_cost(d.ups[lv].cost), "why": game.xup_why(prov, e), "icon_path": "icons/realm/build_%s_l%d.png" % [e.type, lv + 1], "name": "Upgrade to " + str(d.levels[lv]), "cost": d.ups[lv].cost,
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
	if id in ["crop", "cropall", "cropok"]:
		var fe = part_extra()
		if fe == null:
			return
		if id == "crop":
			_open_crop_menu(fe)
		elif id == "cropall":
			crop_arm = {} if _crop_armed() else {"p": prov, "slot": fe.slot, "t": Time.get_ticks_msec()}
		else:
			var t := Ai.crop_target(fe)
			var plan: Array = Ai.crop_all_plan(game, t).plan
			for pf in plan:
				game.do("set_crop", [pf[0], pf[1].slot, t])
			crop_arm = {}
			if not plan.is_empty():
				add_toast("%d Farm%s will grow %s in %d s." % [plan.size(), "" if plan.size() == 1 else "s", Ai.crop_name(t), int(Ai.CROP_DELAY)])
		return
	if id == "thugout":
		game.do("thug_out", [prov, part_extra()])
	elif id.begins_with("train:"):
		game.do("train", [src, prov, id.substr(6)])
	elif id.begins_with("queue:"):
		game.do("cancel_training", ["%s:%d" % [src, prov], int(id.substr(6))])
	elif id == "upgrade":
		game.do("start_upgrade", [prov])
	elif id == "cancelup":
		game.do("cancel_upgrade", [prov])
	elif id == "rewalls":
		game.do("rebuild_walls", [prov])
	elif id == "develop":
		game.do("start_develop", [prov])
	elif id == "dismantle":
		var lost := game.extras_in(prov).size()
		_confirm("dismantle:%d" % prov, "Dismantle the fort at %s? It goes back to an outpost and all %d building%s in the province are destroyed. Press again to confirm." % [game.prov_name(prov), lost, "" if lost == 1 else "s"], game.dismantle_fort.bind(prov))
	elif id == "xup":
		var e = part_extra()
		if e != null:
			game.do("start_xup", [prov, e.slot])
	elif id == "xcancel":
		var e = part_extra()
		if e != null:
			game.do("cancel_xup", [prov, e.slot])
	elif id == "destroy":
		var e = part_extra()
		if e != null:
			var nm: String = game.BUILD_DEFS[e.type].name
			_confirm("destroy:%d@%d" % [prov, e.slot], "Tear down the %s? Press again to confirm." % nm, game.destroy_extra.bind(prov, e.slot))


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
		var ds := game.stats_of(kind, Game.LOCAL)
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
var research_open_opts := {}   # tree -> its options are unfolded while it researches something


## web: v101.js researchSettled: every tree with something on offer has an active research. except: a tree just
## picked (its research begins when the order is applied, which in multiplayer is a moment later)
func research_settled(except := "") -> bool:
	for tr in Game.TREE_KEYS:
		if tr == except:
			continue
		var st: Dictionary = game.tech[tr]
		if st.tier and st.cur == null and not st.opts.is_empty():
			return false
	return true


func _research_pick(id: String) -> void:
	var x = game.TECH_BY_ID.get(id)
	if x == null:
		return
	var tr := str(x.tree)
	# (0.19: judged before the order is applied, so it closes in multiplayer too, where the answer comes later)
	var ok: bool = game.tech[tr].opts.has(id) and (not x.get("gold", 0) or game.stock.gold >= x.gold)
	game.do("pick_tech", [id])
	research_open_opts.erase(tr)
	# web: v101.js: the window closes once every tree with something on offer is researching
	if ok and research.visible and research_settled(tr):
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
	if not UiKit.is_placed("research"):   # (0.19: unless the player has dragged it somewhere)
		research.position.y = topbar.bottom() + 8
	var key := ""
	for tr in Game.TREE_KEYS:
		var st: Dictionary = game.tech[tr]
		key += "%s|%s|%d|%d|%s|%s|%d|%s|%s|%s;" % [tr, st.cur, int(st.prog), int(st.bank), ",".join(st.opts), st.tier, st.done.size(), game.auto_tech[tr], research_open_done.get(tr, false), research_open_opts.get(tr, false)]
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
	UiKit.draggable(research, ttl, "research")   # 0.19
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
	var T: Dictionary = game.TECH_TREES[tr]
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
			game.do("set_auto_tech", [tr, on])
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
		# 0.19: the technology's icon beside what is being researched
		var nrow := HBoxContainer.new()
		nrow.add_theme_constant_override("separation", 8)
		now.add_child(nrow)
		var nic := TextureRect.new()
		nic.custom_minimum_size = Vector2(44, 44)
		nic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		nic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		nic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nsp = _tech_sprite(x)
		if nsp:
			nic.texture = nsp.tex
		nrow.add_child(nic)
		var nb := VBoxContainer.new()
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nrow.add_child(nb)
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
	for x in game.TECHS:
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
	# the options as cards: icon, name, what it does, tier and cost. While a technology is being researched they fold
	# away (click to see them, to switch)
	if not st.opts.is_empty():
		var show_opts: bool = st.cur == null or research_open_opts.get(tr, false)
		if st.cur == null:
			col.add_child(_ink("OPTIONS", 12, Color("#6b5a44")))
		else:
			var of := Button.new()
			of.text = "%s Other options (%d)" % ["−" if show_opts else "+", st.opts.size()]
			of.alignment = HORIZONTAL_ALIGNMENT_LEFT
			of.focus_mode = Control.FOCUS_NONE
			of.add_theme_font_size_override("font_size", 14)
			of.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			of.tooltip_text = "Show or hide the other options (picking one switches the research)"
			of.pressed.connect(func():
				research_open_opts[tr] = not research_open_opts.get(tr, false)
				research_key = "")
			col.add_child(of)
		if show_opts:
			for id in st.opts:
				col.add_child(_tech_card(game.TECH_BY_ID[id], col_c))
	if st.tier < 3:
		col.add_child(_ink("Tier %s: %s" % [["", "I", "II", "III"][st.tier + 1], str(T.tiers[st.tier]).to_lower()], 13, Color("#6b5a44")))
	return pan


## A technology's icon (null if it has none).
func _tech_sprite(x: Dictionary):
	return Art.race_sprite("icons", Art.player_race, "tech_%s.png" % str(x.id).replace("-", "_").to_lower())


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
	var sp = _tech_sprite(x)
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
	var cid: String = str(T.cur.id) if T.cur != null else ""
	if cid != tut_voice_id:   # a new step: its voice line, if one was recorded (web: tutorial.js TUT_AUDIO)
		tut_voice_id = cid
		if cid != "":
			Sound.tutorial_voice(cid)
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
