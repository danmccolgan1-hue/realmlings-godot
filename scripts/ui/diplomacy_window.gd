class_name DiplomacyWindow
extends Control
## Diplomacy (Y), laid out as the web game's v105 screen: one large window with a header (your flag, leader and how
## many wars you may fight) and a collapsible section for every nation you have met. A section's summary shows its
## flag, leader, size, the agreements between you (as badges) and how you stand; opened, it shows the leader's card
## and what he likes, the facts you know, the war and its peace terms, and the diplomatic actions as picture buttons.
## Hover a nation for its opinion of you, part by part. web: v105.js dxPanelHTML / dxActions / dxFacts / dxLeaderCard /
## the opinion tooltip, v106.js (Proclaim Enemy, opinion of you), war.js (warscore and peace terms).
## Views only: every change goes through the game's own functions (dx_act, make_peace…).

const DIFF_NAME := {"easy": "Easy", "moderate": "Moderate", "difficult": "Difficult"}
const MUTED := Color("#6b6257")
const LINE := Color("#cdbf9e")
const UP := Color("#2c7a3a")
const DOWN := Color("#b2302a")

var game: Game
var hud
var win: Dictionary
var head_flag: TextureRect
var head_pt: TextureRect
var head_sub: Label
var scroll: ScrollContainer
var body: VBoxContainer
var key := ""
var tick := 0.0
var open_set := {}      # the nations whose sections are open (web: dxUI.open)
var bribe_o := 0        # the nation whose bribe targets are shown (web: dxUI.bribe)
var drafts := {}        # multiplayer: what you are writing or offering, kept while the window redraws


## A nation's summary row: a button whose tooltip is its opinion of you, part by part (web: the #dxTip tooltip).
class OpinionButton extends Button:
	var tip: Callable

	func _make_custom_tooltip(_t: String) -> Object:
		return tip.call()


func setup(g: Game, h) -> void:
	game = g
	hud = h
	open_set = {}
	bribe_o = 0
	if win.is_empty():
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		win = UiKit.window("Diplomacy", 1000, func(): close())
		add_child(win.panel)
		var head: HBoxContainer = win.title.get_parent()
		head.add_theme_constant_override("separation", 8)
		head_flag = _texrect(42, 28)
		head.add_child(head_flag)
		head.move_child(head_flag, 0)
		head_pt = _portrait(null, 34)
		head.add_child(head_pt)
		head.move_child(head_pt, 1)
		win.title.size_flags_horizontal = 0
		head_sub = UiKit.ink(14)
		head_sub.add_theme_color_override("font_color", MUTED)
		head_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(head_sub)
		head.move_child(head_sub, 3)
		scroll = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(960, 600)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		win.body.add_child(scroll)
		body = VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 6)
		scroll.add_child(body)
	win.panel.hide()
	key = ""


func toggle() -> void:
	if win.panel.visible:
		close()
	else:
		open()


## Open Diplomacy; with a nation, its section opens (web: openDip(o)).
func open(o := 0) -> void:
	if game == null or (game.nations.is_empty() and game.seats.size() < 2):
		if hud:
			hud.add_toast("There are no other nations on the Practice island.", true)
		return
	if o:
		open_set[o] = true
	key = ""
	_refresh()
	if is_inside_tree():
		scroll.custom_minimum_size.y = minf(620, get_viewport_rect().size.y - 220)
	win.panel.show()
	UiKit.center.call_deferred(win.panel)
	_fit.call_deferred()


func close() -> void:
	win.panel.hide()


func _process(dt: float) -> void:
	if game == null or win.is_empty() or not win.panel.visible:
		return
	tick += dt
	if tick < 0.5:
		return
	tick = 0.0
	_refresh()


func _state_key() -> String:
	var D := game.dipl_state()
	var parts := [game.fallen, game.wars.size(), game.allies.size(), D.news.size(), D.access.size(), D.trade.size(), D.crime.size(),
		D.spies.size(), D.mods.size(), int(game.stock.gold) / 100, D.intel.size(), open_set.keys(), bribe_o, game.enemy_of(Game.LOCAL)]
	for w in game.wars:
		parts.append([w.id, game.warscore(w, Game.LOCAL), game.exhaustion_of(w), int(game.t - w.since) / 30])
	for sp in D.spies.values():
		parts.append(int(sp.until - game.t) / 5)
	for o in game.seat_ids():
		if o != Game.LOCAL:
			parts.append([o, game.alive_nation(o), game.knows(o), game.provs_of(o).size(), game.enemy_of(o), game.allied(Game.LOCAL, o), game.access_given(o, Game.LOCAL),
				game.access_given(Game.LOCAL, o), game.declare_why(Game.LOCAL, o), game.proclaim_why(Game.LOCAL, o), int(game.truce_left(Game.LOCAL, o)) / 30,
				["growl", "flirt", "gift", "ask", "ally", "trade", "crime"].map(func(a): return game.player_act_why(a, o))])
	for o in game.ai_ids():
		parts.append([o, game.alive_nation(o), game.knows(o), game.opinion(o, Game.LOCAL), game.declare_why(Game.LOCAL, o), game.proclaim_why(Game.LOCAL, o),
			int(game.truce_left(Game.LOCAL, o)) / 30, game.provs_of(o).size(), game.enemy_of(o)])
	return str(parts)


func _refresh() -> void:
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if fo != null and (fo is LineEdit or fo is SpinBox or fo.get_parent() is SpinBox) and body.is_ancestor_of(fo):
		return   # (not while you are typing)
	var k := _state_key()
	if k == key:
		return
	key = k
	var sv := scroll.scroll_vertical
	_header()
	UiKit.clear(body)
	var players: Array = game.seat_ids().filter(func(o): return o != Game.LOCAL and game.knows(o))
	if game.seats.size() > 1:
		body.add_child(_proclamation())
	for o in players:
		body.add_child(_player_section(o))
	var met := game.ai_ids().filter(func(o): return game.knows(o))
	var unmet := game.ai_ids().filter(func(o): return game.alive_nation(o) and not game.knows(o)).size() + game.seat_ids().filter(func(o): return o != Game.LOCAL and game.alive_nation(o) and not game.knows(o)).size()
	if met.is_empty() and players.is_empty():
		body.add_child(_note("You haven't met anyone yet. Explore with your %ss to find the other nations." % game.unit_defs[game.WAYFINDER].name, 15))
	for o in met:
		body.add_child(_section(o))
	if unmet:
		body.add_child(_note("%d nation%s you haven't met yet." % [unmet, "s" if unmet > 1 else ""], 14))
	_between()
	_news()
	scroll.set_deferred("scroll_vertical", sv)
	if win.panel.visible:   # (a window that grew while its sections were laid out shrinks back to fit)
		_fit.call_deferred()


func _fit() -> void:
	var h0: float = win.panel.size.y
	win.panel.reset_size()
	if absf(win.panel.size.y - h0) > 1:
		UiKit.center(win.panel)
	if win.panel.size.y > get_viewport_rect().size.y:   # (once more after the labels have their widths)
		get_tree().process_frame.connect(_fit, CONNECT_ONE_SHOT)


# web: v105.js dxPanelHTML's header (+ v106.js your proclaimed enemy)
func _header() -> void:
	head_flag.texture = Art.nation_flag(game, Game.LOCAL)
	var me = game.leader_of(Game.LOCAL)
	head_pt.texture = Hud.leader_icon(me.id) if me != null else null
	head_pt.get_parent().visible = me != null
	var e = game.enemy_of(Game.LOCAL)
	head_sub.text = "%s%s · at war with %d of at most %d nations%s · hover a nation to see its opinion of you" % [game.player_info(Game.LOCAL).name,
		(" · " + me.full) if me != null else "", game.enemies_of(Game.LOCAL).size(), int(game.W("maxVsPlayer")),
		(" · your proclaimed enemy: the " + game.player_info(e).name) if e != null and int(e) > 0 else ""]


# ------------------------------------------------------------------ a nation's section

func _section(o: int) -> PanelContainer:
	var N: Dictionary = game.nations[o]
	var alive: bool = game.alive_nation(o)
	var is_open: bool = open_set.has(o) and alive
	var rel := _relation(o)
	var bg: Color = {"war": Color("#f6ddd6"), "ally": Color("#e2f1da"), "truce": Color("#f3ecd6")}.get(rel.cls, Color("#fbf6e8"))
	var pc := PanelContainer.new()
	var bx := UiKit.box(bg, 6, 2 if is_open else 1, UiKit.INK if is_open else LINE)
	bx.set_content_margin_all(0)
	pc.add_theme_stylebox_override("panel", bx)
	if not alive:
		pc.modulate.a = 0.6
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	pc.add_child(col)
	# the summary
	var sum := OpinionButton.new()
	sum.tip = _opinion_tip.bind(o)
	sum.tooltip_text = "opinion" if alive else ""
	sum.custom_minimum_size = Vector2(0, 54)
	sum.flat = true
	sum.focus_mode = Control.FOCUS_NONE
	sum.pressed.connect(func():
		if open_set.has(o):
			open_set.erase(o)
		else:
			open_set[o] = true
		key = ""
		_refresh())
	col.add_child(sum)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -10
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sum.add_child(h)
	var chev := UiKit.ink(16)
	chev.text = "▾" if is_open else "▸"
	h.add_child(chev)
	var fl := _texrect(36, 24)
	fl.texture = Art.nation_flag(game, o)
	h.add_child(fl)
	var L = game.leader_of(o)
	if L != null:
		h.add_child(_portrait(L, 34))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -2)
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nv)
	var nm := UiKit.ink(17)
	nm.text = game.player_info(o).name
	nv.add_child(nm)
	var sm := UiKit.ink(13)
	sm.add_theme_color_override("font_color", MUTED)
	var np := game.provs_of(o).size()
	sm.text = ("%s%ss · %d province%s · %s" % [(L.full + " · ") if L != null else "", CountryWindow.RACE_WORD.get(N.get("race", "realm"), "Realmling"),
		np, "" if np == 1 else "s", DIFF_NAME.get(N.diff, str(N.diff))]) if alive else "Fallen"
	nv.add_child(sm)
	if alive:
		for b in _badges(o):
			var ic := _texrect(26, 26)
			ic.texture = Hud.icon("icons/common/dx_%s.png" % b[0])
			ic.tooltip_text = b[1]
			ic.mouse_filter = Control.MOUSE_FILTER_PASS
			h.add_child(ic)
		h.add_child(_chip(rel))
	for c in h.get_children():
		if c.mouse_filter != Control.MOUSE_FILTER_PASS:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_open:
		return pc
	# the details
	var det := HBoxContainer.new()
	det.add_theme_constant_override("separation", 14)
	var m := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	m.add_child(det)
	col.add_child(m)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 6)
	det.add_child(left)
	if L != null:
		left.add_child(_leader_card(L))
	left.add_child(_facts(o))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	det.add_child(right)
	var w = game.war_between(Game.LOCAL, o)
	if w != null:
		right.add_child(_war_block(o, w))
	right.add_child(_actions(o))
	return pc


# ------------------------------------------------------------------ multiplayer: another player's nation (step 11)

## Issue Proclamation: a message to every player you have met (100 gold).
func _proclamation() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.box(Color("#fbf6e8"), 6, 1, LINE))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	pc.add_child(h)
	var ic := _texrect(28, 28)
	ic.texture = Hud.icon("icons/common/dx_enemy.png")
	h.add_child(ic)
	var e := _line("procl", "A proclamation to every player you have met (80 letters)")
	h.add_child(e)
	var why := game.proclamation_why()
	var b := _plain_btn("Issue Proclamation (%d gold)" % Game.PROCLAIM_COST.gold, func():
		game.do("issue_proclamation", [str(drafts.get("procl", ""))])
		drafts.erase("procl")
		key = "")
	b.disabled = why != ""
	b.tooltip_text = why if why != "" else "Every player you have met reads it in their flags"
	h.add_child(b)
	return pc


func _line(k: String, hint: String) -> LineEdit:
	var e := LineEdit.new()
	e.max_length = Game.MSG_LEN
	e.placeholder_text = hint
	e.text = str(drafts.get(k, ""))
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 14)
	e.text_changed.connect(func(t2): drafts[k] = t2)
	return e


func _player_section(o: int) -> PanelContainer:
	var alive: bool = game.alive_nation(o)
	var is_open: bool = open_set.has(o) and alive
	var rel := _relation(o)
	var bg: Color = {"war": Color("#f6ddd6"), "ally": Color("#e2f1da"), "truce": Color("#f3ecd6")}.get(rel.cls, Color("#fbf6e8"))
	var pc := PanelContainer.new()
	var bx := UiKit.box(bg, 6, 2 if is_open else 1, UiKit.INK if is_open else LINE)
	bx.set_content_margin_all(0)
	pc.add_theme_stylebox_override("panel", bx)
	var col := VBoxContainer.new()
	pc.add_child(col)
	var sum := Button.new()
	sum.flat = true
	sum.focus_mode = Control.FOCUS_NONE
	sum.custom_minimum_size = Vector2(0, 54)
	sum.pressed.connect(func():
		if open_set.has(o):
			open_set.erase(o)
		else:
			open_set[o] = true
		key = ""
		_refresh())
	col.add_child(sum)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.offset_right = -10
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sum.add_child(h)
	var chev := UiKit.ink(16)
	chev.text = "▾" if is_open else "▸"
	h.add_child(chev)
	var fl := _texrect(36, 24)
	fl.texture = Art.nation_flag(game, o)
	h.add_child(fl)
	var L = game.leader_of(o)
	if L != null:
		h.add_child(_portrait(L, 34))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -2)
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nv)
	var nm := UiKit.ink(17)
	nm.text = game.player_info(o).name
	nv.add_child(nm)
	var sm := UiKit.ink(13)
	sm.add_theme_color_override("font_color", MUTED)
	var np := game.provs_of(o).size()
	sm.text = ("Player: %s · %s%ss · %d province%s" % [game.seat_names.get(o, "?"), (L.full + " · ") if L != null else "", CountryWindow.RACE_WORD.get(game.race(o), "Realmling"),
		np, "" if np == 1 else "s"]) if alive else "Fallen"
	nv.add_child(sm)
	if alive:
		for b in _badges(o):
			var ic := _texrect(26, 26)
			ic.texture = Hud.icon("icons/common/dx_%s.png" % b[0])
			ic.tooltip_text = b[1]
			ic.mouse_filter = Control.MOUSE_FILTER_PASS
			h.add_child(ic)
		h.add_child(_chip(rel))
	for c in h.get_children():
		if c.mouse_filter != Control.MOUSE_FILTER_PASS:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_open:
		return pc
	var m := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	col.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var e = game.enemy_of(o)
	var facts := []
	facts.append("Proclaimed enemy: %s" % (("you" if e == Game.LOCAL else "the " + game.player_info(e).name) if e != null and int(e) > 0 else "none"))
	var al := game.allies_of(o).filter(func(x): return x != Game.LOCAL)
	if not al.is_empty():
		facts.append("Allied with " + ", ".join(al.map(func(x): return game.player_info(x).name)))
	var wr := game.enemies_of(o).filter(func(x): return x != Game.LOCAL)
	if not wr.is_empty():
		facts.append("At war with " + ", ".join(wr.map(func(x): return game.player_info(x).name)))
	v.add_child(_note(" · ".join(facts), 14))
	var w = game.war_between(Game.LOCAL, o)
	if w != null:
		v.add_child(_war_block(o, w))
	# the actions: no opinion between players, so each is your choice, or theirs to accept
	v.add_child(_sec("Actions"))
	var gd := GridContainer.new()
	gd.columns = 3
	gd.add_theme_constant_override("h_separation", 6)
	gd.add_theme_constant_override("v_separation", 6)
	v.add_child(gd)
	var D := game.dipl_state()
	var DL: Dictionary = Game.DIPL
	if game.enemy_of(Game.LOCAL) == o:
		gd.add_child(_act(o, "proclaim", "enemy", "Renounce enemy", "", "Lift your proclamation"))
	else:
		gd.add_child(_act(o, "proclaim", "enemy", "Proclaim Enemy", game.proclaim_why(Game.LOCAL, o), "Every player who has met you hears of it", true))
	if game.race() == "swamp":   # (Swamplings growl, the others flirt; once in 10 minutes)
		gd.add_child(_act(o, "growl", "growl", "Growl", game.player_act_why("growl", o), "They’ll hear it; players have no opinion to sway"))
	else:
		gd.add_child(_act(o, "flirt", "flirt", "Flirt", game.player_act_why("flirt", o), "They’ll know; players have no opinion to sway"))
	gd.add_child(_act(o, "gift", "gift", "Gift", game.player_act_why("gift", o), "%d gold, straight to their treasury" % DL.gift.gold))
	if game.access_given(Game.LOCAL, o):
		gd.add_child(_act(o, "grant", "revoke", "Revoke access", "", "Their armies may no longer march through your land"))
	else:
		gd.add_child(_act(o, "grant", "access", "Offer access", game.player_act_why("grant", o), "Their armies may march through your land"))
	if game.access_given(o, Game.LOCAL):
		gd.add_child(_act(o, "giveback", "revoke", "Give back access", "", "You may march through their land; give it back"))
	else:
		gd.add_child(_act(o, "ask", "access", "Ask for access", game.player_act_why("ask", o), "They choose: 30 s to answer"))
	if game.allied(Game.LOCAL, o):
		gd.add_child(_act(o, "ally", "ally", "End alliance", "", "%d-minute truce afterwards" % (int(game.W("allyTruce")) / 60)))
	else:
		gd.add_child(_act(o, "ally", "ally", "Alliance", game.player_act_why("ally", o), "Any race; they choose: 30 s to answer"))
	if not game.is_sw():
		if game.pair_has(D.trade, Game.LOCAL, o) != null:
			gd.add_child(_act(o, "trade", "trade", "End Trade Network", "", "Stop trading"))
		else:
			gd.add_child(_act(o, "trade", "trade", "Trade Network", game.player_act_why("trade", o), "A shared border: +10% Community / Trade Routes. They choose"))
	else:
		if game.pair_has(D.crime, Game.LOCAL, o) != null:
			gd.add_child(_act(o, "crime", "crime", "End Organized Crime", "", "Extra Thugs leave their dens 10 s later"))
		else:
			gd.add_child(_act(o, "crime", "crime", "Organized Crime", game.player_act_why("crime", o), "+1 Thug in every Thug Den. They choose"))
	if not game.at_war(Game.LOCAL, o) and not game.allied(Game.LOCAL, o):
		var dc: Dictionary = game.W("declareCost")
		gd.add_child(_act(o, "declare", "war", "Declare war", game.declare_why(Game.LOCAL, o), "−%s" % UiKit.cost_line(dc), true))
	# Send Message
	v.add_child(_sec("Send a message (%d gold)" % Game.MSG_COST.gold))
	var mr := HBoxContainer.new()
	mr.add_theme_constant_override("separation", 8)
	mr.add_child(_line("msg:%d" % o, "Up to 80 letters, for their eyes only"))
	var mwhy := game.message_why(o)
	var mb := _plain_btn("Send", func():
		game.do("send_message", [o, str(drafts.get("msg:%d" % o, ""))])
		drafts.erase("msg:%d" % o)
		key = "")
	mb.disabled = mwhy != ""
	mb.tooltip_text = mwhy
	mr.add_child(mb)
	v.add_child(mr)
	# Barter
	v.add_child(_sec("Barter: they have 30 s to accept"))
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 6)
	var bd: Dictionary = drafts.get("barter:%d" % o, {"give": {"gold": 0, "wood": 0, "food": 0}, "want": {"gold": 0, "wood": 0, "food": 0}})
	drafts["barter:%d" % o] = bd
	for side in ["give", "want"]:
		br.add_child(_ink("You give" if side == "give" else "for", 14))
		for k in Game.RES:
			var sp := SpinBox.new()
			sp.min_value = 0
			sp.max_value = 99999
			sp.step = 10
			sp.value = int(bd[side][k])
			sp.suffix = k
			sp.custom_minimum_size = Vector2(110, 0)
			var sd: String = side
			var kk: String = k
			sp.value_changed.connect(func(x): bd[sd][kk] = int(x))
			br.add_child(sp)
	var ob := _plain_btn("Offer", func():
		game.do("offer_barter", [o, bd.give.duplicate(), bd.want.duplicate()])
		key = "")
	br.add_child(ob)
	v.add_child(br)
	return pc


# web: war.js relation + v105.js dxRelation
func _relation(o: int) -> Dictionary:
	var w = game.war_between(Game.LOCAL, o)
	if w != null and w.get("proxy") != null:
		return {"cls": "war", "text": "Proxy war %d%%" % game.exhaustion_of(w), "col": DOWN}
	if w != null:
		var s := game.warscore(w, Game.LOCAL)
		return {"cls": "war", "text": "⚔ War %s" % _sgn(s), "col": DOWN}
	if game.allied(Game.LOCAL, o):
		return {"cls": "ally", "text": "Allied", "col": UP}
	var tl := game.truce_left(Game.LOCAL, o)
	if tl > 0:
		return {"cls": "truce", "text": "Truce " + Game.fmt_time(tl), "col": MUTED}
	return {"cls": "", "text": "Peace", "col": MUTED}


func _chip(rel: Dictionary) -> PanelContainer:
	var pc := PanelContainer.new()
	var bx := UiKit.box(Color.WHITE, 12, 2, rel.col)
	bx.content_margin_top = 2
	bx.content_margin_bottom = 2
	bx.content_margin_left = 10
	bx.content_margin_right = 10
	pc.add_theme_stylebox_override("panel", bx)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := UiKit.ink(14)
	l.text = rel.text
	l.add_theme_color_override("font_color", rel.col)
	pc.add_child(l)
	return pc


# web: v105.js dxBadges
func _badges(o: int) -> Array:
	var D := game.dipl_state()
	var out := []
	if game.allied(Game.LOCAL, o):
		out.append(["ally", "Allies"])
	if game.access_given(Game.LOCAL, o):
		out.append(["access", "They may march through your land"])
	if game.access_given(o, Game.LOCAL):
		out.append(["access", "You may march through their land"])
	if game.pair_has(D.trade, Game.LOCAL, o) != null:
		out.append(["trade", "Trade Network"])
	if game.pair_has(D.crime, Game.LOCAL, o) != null:
		out.append(["crime", "Organized Crime Agreement"])
	if D.spies.has(o):
		out.append(["spy", "Spies at work: " + game.fmt_left(D.spies[o].until - game.t)])
	return out


# web: v105.js dxLeaderCard
func _leader_card(L: Dictionary) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	h.add_child(_portrait(L, 72))
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nv)
	var n := UiKit.ink(16)
	n.text = L.full
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(n)
	var r := UiKit.ink(13)
	r.text = "%s · %s" % [CountryWindow.RACE_WORD.get(L.race, "Realmling"), "Woman" if L.get("sex") == "f" else "Man"]
	r.add_theme_color_override("font_color", MUTED)
	nv.add_child(r)
	var b := UiKit.ink(13)
	b.text = L.bonus
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(b)
	v.add_child(_sec("%s likes nations with" % L.name))
	for lk in StartScreen.leader_like_text(L):
		var row := UiKit.rich(13, 290)
		row.text = "[color=#%s][b]%s[/b][/color] %s" % [(UP if str(lk[0]).begins_with("+") else DOWN).to_html(false), lk[0], lk[1]]
		v.add_child(row)
	return v


# web: v105.js dxFacts + v106.js (opinion of you, proclaimed enemy)
func _facts(o: int) -> GridContainer:
	var N: Dictionary = game.nations[o]
	var I: Dictionary = game.dipl_state().intel.get(o, {})
	var gd := GridContainer.new()
	gd.columns = 2
	gd.add_theme_constant_override("h_separation", 12)
	gd.add_theme_constant_override("v_separation", 1)
	var e = game.enemy_of(o)
	var op := game.opinion(o, Game.LOCAL)
	var rows := [["Opinion of you", _sgn(op), UP if op > 0 else (DOWN if op < 0 else UiKit.INK)],
		["Proclaimed enemy", ("You" if e == Game.LOCAL else game.player_info(e).name) if e != null and int(e) > 0 else "None", DOWN if e != null and int(e) > 0 else MUTED],
		["Provinces", str(game.provs_of(o).size()), UiKit.INK], ["Difficulty", DIFF_NAME.get(N.diff, str(N.diff)), UiKit.INK],
		["Military power", ("%d (spied %s ago)" % [int(I.power), game.fmt_left(game.t - I.powerT)]) if I.has("power") else "Hidden: send spies", UiKit.INK if I.has("power") else MUTED]]
	var al := game.allies_of(o).filter(func(x): return x != Game.LOCAL)
	if not al.is_empty():
		rows.append(["Allied with", ", ".join(al.map(func(x): return game.player_info(x).name)), UiKit.INK])
	var wr := game.enemies_of(o).filter(func(x): return x != Game.LOCAL)
	if not wr.is_empty():
		rows.append(["At war with", ", ".join(wr.map(func(x): return game.player_info(x).name)), UiKit.INK])
	for r in rows:
		var k := UiKit.ink(13)
		k.text = r[0]
		k.add_theme_color_override("font_color", MUTED)
		gd.add_child(k)
		var v := UiKit.ink(14)
		v.text = r[1]
		v.add_theme_color_override("font_color", r[2])
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size = Vector2(160, 0)
		gd.add_child(v)
	return gd


# ------------------------------------------------------------------ the war and its peace terms

func _war_block(o: int, w: Dictionary) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	if w.get("proxy") != null:   # web: v105.js dxWarBlock (Proxy War)
		var e := game.exhaustion_of(w)
		var mine: bool = w.proxy == Game.LOCAL
		var P = game.parent_war(w)
		var def: int = int(P.b) if P != null else 0
		v.add_child(_sec("Proxy War"))
		v.add_child(_note(("You joined to defend your ally, the %s. You can't win this war, only help them win: your provinces can't be occupied, and your victories count for them." % (game.player_info(def).name if def else "")) if mine
			else "They joined to defend their ally%s. Their provinces can't be occupied; they leave the war at 100 exhaustion." % ((", the " + game.player_info(def).name) if def else ""), 14))
		v.add_child(_bar(e / 100.0, DOWN, "%s exhaustion %d / 100" % ["Your" if mine else "Their", e]))
		v.add_child(_note("+%d for every 1%% of the army's value lost; +%d if a third nation declares war on %s. At 100: white peace." % [Game.DIPL.exhPer, Game.DIPL.exhDeclare, "you" if mine else "them"], 12))
		return v
	var s := game.warscore(w, Game.LOCAL)
	v.add_child(_sec("War"))
	var why_w := "they attacked you" if w.a == o else "you declared"
	v.add_child(_note("At war for %s (%s). Warscore %s. %s" % [Game.fmt_time(game.t - w.since), why_w, _sgn(s), _score_hint(s)], 14))
	v.add_child(_ws_bar(s))
	var terms := HFlowContainer.new()
	terms.add_theme_constant_override("h_separation", 6)
	terms.add_theme_constant_override("v_separation", 6)
	v.add_child(terms)
	var picks := _province_pick(s, o)
	var opts := [["White peace", "white", []], ["Take gold", "gold", []]]
	if not picks.is_empty():
		var all: bool = picks.size() == game.provs_of(o).size()
		opts.append([("Annex them (%d provinces)" % picks.size()) if all else ("Take %d province%s" % [picks.size(), "s" if picks.size() > 1 else ""]), "provs", picks])
	else:
		opts.append(["Take provinces", "provs", []])
	opts.append(["Surrender", "surrender", []])
	for op in opts:
		var why := game.peace_check(w, op[1], op[2])
		var b := _plain_btn(op[0], func(): _peace(w, op[1], op[2]))
		if why != "":
			b.modulate.a = 0.55
		b.tooltip_text = UiKit.wrap(why if why != "" else _terms_tip(op[1], op[2]))
		terms.add_child(b)
	return v


# web: war.js wsBar: your share grows right of the middle, theirs left; marks at ±20 and ±50
func _ws_bar(s: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 14)
	c.draw.connect(func():
		var W := c.size.x
		var H := c.size.y
		c.draw_rect(Rect2(0, 0, W, H), Color("#eef0f4"))
		if s > 0:
			c.draw_rect(Rect2(W / 2, 0, W * s / 200.0, H), Color("#5aa557"))
		elif s < 0:
			c.draw_rect(Rect2(W / 2 + W * s / 200.0, 0, -W * s / 200.0, H), Color("#d0574b"))
		for f in [0.25, 0.4, 0.6, 0.75]:
			c.draw_line(Vector2(W * f, 0), Vector2(W * f, H), Color(0, 0, 0, 0.25), 1.0)
		c.draw_line(Vector2(W * (s + 100) / 200.0, -2), Vector2(W * (s + 100) / 200.0, H + 2), UiKit.INK, 3.0)
		c.draw_rect(Rect2(0, 0, W, H), UiKit.INK, false, 1.5))
	return c


func _bar(f: float, col: Color, txt: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 20)
	c.draw.connect(func():
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("#eef0f4"))
		c.draw_rect(Rect2(0, 0, c.size.x * clampf(f, 0, 1), c.size.y), col)
		c.draw_rect(Rect2(Vector2.ZERO, c.size), UiKit.INK, false, 1.5)
		c.draw_string(get_theme_default_font(), Vector2(8, 15), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.INK))
	return c


func _score_hint(s: int) -> String:
	if s >= game.W("total"):
		return "You can annex them."
	if s >= game.W("provs"):
		return "You can take provinces."
	if s >= game.W("gold"):
		return "You can take gold."
	if s < 0:
		return "You are losing."
	return ""


## The provinces this warscore can take: connected ones next to your land, or the whole nation at 100.
func _province_pick(s: int, foe: int) -> Array:
	if s < game.W("provs"):
		return []
	if s >= game.W("total") and game.annexable(Game.LOCAL, foe):
		return game.provs_of(foe)
	return game.connected_pick(Game.LOCAL, foe, game.demand_max(s))


func _terms_tip(kind: String, provs: Array) -> String:
	match kind:
		"white":
			return "Peace with nothing given or taken, and a truce."
		"gold":
			return "They pay you up to %d gold, and a truce." % game.W("goldTerm")
		"provs":
			return "You take: " + ", ".join(provs.map(func(p): return game.prov_name(p)))
		"surrender":
			return "You give in: they take what their warscore allows."
	return ""


func _peace(w: Dictionary, kind: String, provs: Array) -> void:
	var why := game.peace_check(w, kind, provs)
	if why != "":
		game.toast(why, true)
		return
	var terms := {"kind": kind}
	if kind == "provs":
		terms.provs = provs
	var foe := Game.foe_of(w, Game.LOCAL)
	game.do("make_peace", [w, foe if kind == "surrender" else Game.LOCAL, terms])
	key = ""


# ------------------------------------------------------------------ the diplomatic actions (web: v105.js dxActions, v106.js)

func _actions(o: int) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_sec("Actions"))
	var D := game.dipl_state()
	var DL: Dictionary = Game.DIPL
	var gd := GridContainer.new()
	gd.columns = 3
	gd.add_theme_constant_override("h_separation", 6)
	gd.add_theme_constant_override("v_separation", 6)
	v.add_child(gd)
	var mine_en: bool = game.enemy_of(Game.LOCAL) == o
	if mine_en:
		gd.add_child(_act(o, "proclaim", "enemy", "Renounce enemy", "", "Lift your proclamation: their %d opinion goes away" % Game.DIPL_ENEMY))
	else:
		gd.add_child(_act(o, "proclaim", "enemy", "Proclaim Enemy", game.proclaim_why(Game.LOCAL, o), "%d opinion with them while it stands; +%d with nations who share the enemy. One at a time, one every 10 min" % [Game.DIPL_ENEMY, Game.DIPL_SHARED], true))
	if not game.is_sw(o):   # web: v106.js (no Flirt with Swamplings)
		gd.add_child(_act(o, "flirt", "flirt", "Flirt", game.flirt_why(o), "+%d opinion for %d min" % [DL.flirt.v, DL.flirt.dur / 60]))
	if game.is_sw():   # web: v105.js / v106.js Growl
		gd.add_child(_act(o, "growl", "growl", "Growl", game.growl_why(o), ("50%%: +%d or −%d opinion for %d min" % [DL.growl.v, DL.growl.v, DL.growl.dur / 60]) if game.is_sw(o) else ("They aren’t Swamplings: always −%d opinion for %d min" % [DL.growl.v, DL.growl.dur / 60])))
	gd.add_child(_act(o, "gift", "gift", "Gift", game.gift_why(o), "%d gold: +%d opinion for %d min" % [DL.gift.gold, DL.gift.v, DL.gift.dur / 60]))
	gd.add_child(_act(o, "bribe", "bribe", "Bribe", game.bribe_why(o), "%d gold: they attack a smaller nation" % DL.bribe.gold, false, bribe_o == o))
	if game.access_given(Game.LOCAL, o):
		gd.add_child(_act(o, "grant", "revoke", "Revoke access", "", "Their armies may no longer march through your land"))
	else:
		gd.add_child(_act(o, "grant", "access", "Offer access", game.grant_why(o), "Their armies may march through your land (they accept at %d or better)" % DL.offer))
	if game.access_given(o, Game.LOCAL):
		gd.add_child(_act(o, "giveback", "revoke", "Give back access", "", "You may march through their land; give it back"))
	else:
		gd.add_child(_act(o, "ask", "access", "Ask for access", game.ask_why(o), "Your armies march through their land"))
	if game.allied(Game.LOCAL, o):
		gd.add_child(_act(o, "ally", "ally", "End alliance", "", "%d-minute truce afterwards" % (int(game.W("allyTruce")) / 60)))
	else:
		gd.add_child(_act(o, "ally", "ally", "Alliance", game.ally_why(Game.LOCAL, o), "Needs +%d: vision, access, they defend each other" % DL.ally))
	if not game.is_sw():   # web: v105.js (Trade Networks for Realmlings and Woodlings)
		if game.pair_has(D.trade, Game.LOCAL, o) != null:
			gd.add_child(_act(o, "trade", "trade", "End Trade Network", "", "Stop trading"))
		else:
			gd.add_child(_act(o, "trade", "trade", "Trade Network", game.trade_why(Game.LOCAL, o), "Needs +%d and a shared border: +10%% Community / Trade Routes" % DL.trade))
	else:   # Organized Crime for Swamplings
		if game.pair_has(D.crime, Game.LOCAL, o) != null:
			gd.add_child(_act(o, "crime", "crime", "End Organized Crime", "", "Extra Thugs leave their dens 10 s later"))
		else:
			gd.add_child(_act(o, "crime", "crime", "Organized Crime", game.crime_why(Game.LOCAL, o), "Needs +%d: +1 Thug in every Thug Den, theirs and yours" % DL.crime))
	if D.spies.has(o):
		var sp: Dictionary = D.spies[o]
		var b := _act(o, "", "spy", "Spying…", "", "%s left" % game.fmt_left(sp.until - game.t))
		b.modulate.a = 0.8
		gd.add_child(b)
	else:
		gd.add_child(_act(o, "spy", "spy", "Spy", game.spy_why(o), "%d gold, %d min: maybe provinces or their army's power. 10%% caught" % [DL.spy.gold, DL.spy.dur / 60]))
	if not game.at_war(Game.LOCAL, o) and not game.allied(Game.LOCAL, o):
		var dc: Dictionary = game.W("declareCost")
		gd.add_child(_act(o, "declare", "war", "Declare war", game.declare_why(Game.LOCAL, o), "−%s. −200 opinion with them, for good" % UiKit.cost_line(dc), true))
	if bribe_o == o:
		v.add_child(_sec("Bribe the %s (%d gold) to attack…" % [game.player_info(o).name, DL.bribe.gold]))
		var ts := game.bribe_targets(o)
		if ts.is_empty():
			v.add_child(_note("No smaller nation they can attack.", 13))
		for y in ts:
			var al := game.allies_of(y)
			var b := _plain_btn("%s  ·  %d provinces%s" % [game.player_info(y).name, game.provs_of(y).size(),
				(", allied with " + ", ".join(al.map(func(x): return "you" if x == Game.LOCAL else game.player_info(x).name))) if not al.is_empty() else ""], func():
				game.do("dx_act", ["bribe", o, y])
				bribe_o = 0
				key = "")
			b.icon = Art.nation_flag(game, y)
			b.expand_icon = false
			v.add_child(b)
	return v


# a diplomatic action: its picture, name, and why it can't be done or what it does (web: v105.js dxActBtn)
func _act(o: int, act: String, icon: String, name: String, why: String, ok: String, war := false, on := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(196, 58)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = UiKit.wrap(why if why != "" else ok, 48)
	var bg := Color("#fff1b8") if on else (Color("#fbe3de") if war else Color.WHITE)
	for st in [["normal", bg], ["hover", bg.darkened(0.04)], ["pressed", bg.darkened(0.1)], ["focus", bg]]:
		var bx := UiKit.box(st[1], 5, 2 if on else 1, UiKit.INK if why == "" else LINE)
		bx.set_content_margin_all(4)
		b.add_theme_stylebox_override(st[0], bx)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6
	h.offset_right = -6
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var ic := _texrect(32, 32)
	ic.texture = Hud.icon("icons/common/dx_%s.png" % icon)
	if why != "":
		ic.modulate.a = 0.45
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -3)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var n := UiKit.ink(15)
	n.text = name
	if why != "":
		n.add_theme_color_override("font_color", MUTED)
	v.add_child(n)
	var s := UiKit.ink(11)
	s.text = why if why != "" else ok
	s.add_theme_color_override("font_color", DOWN if why != "" else MUTED)
	s.clip_text = true
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.custom_minimum_size = Vector2(140, 0)
	v.add_child(s)
	for c in [n, s]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if act != "":
		b.pressed.connect(func():
			if why != "":
				game.toast(why, true)
				return
			if act == "bribe":
				bribe_o = 0 if bribe_o == o else o
			else:
				game.do("dx_act", [act, o])
			key = "")
	return b


# ------------------------------------------------------------------ between other nations, news, the opinion tooltip

func _between() -> void:
	var D := game.dipl_state()
	var rows := []
	for w in game.wars:
		if w.get("parent") == null and w.a != Game.LOCAL and w.b != Game.LOCAL and (game.knows(w.a) or game.knows(w.b)):
			var kids := game.wars.filter(func(c): return c.get("parent") == w.id and c.get("proxy") != null and c.proxy != Game.LOCAL)
			rows.append([w.a, "⚔", w.b, _sgn(game.warscore(w, w.a)) + "".join(kids.map(func(c): return " · %s defends (exhaustion %d%%)" % [game.player_info(c.proxy).name, game.exhaustion_of(c)]))])
	for A in game.allies:
		if A.a != Game.LOCAL and A.b != Game.LOCAL and (game.knows(A.a) or game.knows(A.b)):
			rows.append([A.a, "allied with", A.b, ""])
	for k in ["trade", "crime"]:
		for P in D[k]:
			if P.a != Game.LOCAL and P.b != Game.LOCAL and (game.knows(P.a) or game.knows(P.b)):
				rows.append([P.a, "trades with" if k == "trade" else "deals with", P.b, ""])
	if rows.is_empty():
		return
	body.add_child(_sec("Between other nations"))
	for r in rows:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		for part in [_dot(r[0]), _ink(game.player_info(r[0]).name, 14), _ink(r[1], 14, MUTED), _dot(r[2]), _ink(game.player_info(r[2]).name, 14), _ink(r[3], 14, MUTED)]:
			h.add_child(part)
		body.add_child(h)


# news of wars and peace between the nations you know (web: v105.js newsAdd, shown as flags there)
func _news() -> void:
	var D := game.dipl_state()
	if D.news.is_empty():
		return
	body.add_child(_sec("News"))
	for n in D.news:
		if n.has("text"):   # a message, proclamation or answer from another player
			body.add_child(_note("%s: %s" % [Game.fmt_time(n.t), n.text], 13))
			continue
		body.add_child(_note(("%s: the %s declared war on the %s" if n.kind == "war" else "%s: the %s and the %s made peace") % [Game.fmt_time(n.t), game.player_info(n.a).name, game.player_info(n.b).name], 13))


# web: v105.js the #dxTip tooltip
func _opinion_tip(o: int) -> Control:
	var parts := game.opinion_parts(o, Game.LOCAL)
	var tot := 0
	for p in parts:
		tot += int(p[1])
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.custom_minimum_size = Vector2(320, 0)
	var row := func(t: String, n, bold := false):
		var h := HBoxContainer.new()
		var l := UiKit.label(15 if bold else 14, Color("#faf1dc"), false)
		l.text = t
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		if n != null:
			var r := UiKit.label(15 if bold else 14, Color("#8fd18a") if n > 0 else (Color("#ff8f80") if n < 0 else Color("#faf1dc")), false)
			r.text = _sgn(n)
			h.add_child(r)
		v.add_child(h)
	row.call("The %s's opinion of you" % game.player_info(o).name, tot, true)
	if parts.is_empty():
		row.call("Nothing for or against you", null)
	for p in parts:
		row.call(str(p[0]), int(p[1]))
	var nt := UiKit.label(12, Color("#c9bfa8"), false)
	nt.text = "Alliance +%d · Trade / Crime +%d · Access above 0" % [Game.DIPL.ally, Game.DIPL.trade]
	v.add_child(nt)
	return v


# ------------------------------------------------------------------ small parts

static func _sgn(n) -> String:   # web: war.js sgn
	var r := roundi(float(n))
	return ("+" if r > 0 else ("−" if r < 0 else "")) + str(absi(r))


func _texrect(w: int, h: int) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(w, h)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


# a leader's portrait in an ink frame (web: .pt)
func _portrait(L, px: int) -> TextureRect:
	var t := _texrect(px, px)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.texture = Hud.leader_icon(L.id) if L != null else null
	t.draw.connect(func(): t.draw_rect(Rect2(Vector2.ZERO, t.size), UiKit.INK, false, 2.0))
	return t


func _dot(o: int) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(str(game.player_info(o).color))
	c.custom_minimum_size = Vector2(12, 12)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _ink(t: String, size: int, col := UiKit.INK) -> Label:
	var l := UiKit.ink(size)
	l.text = t
	l.add_theme_color_override("font_color", col)
	return l


func _sec(t: String) -> Label:
	return _ink(t.to_upper(), 13, MUTED)


func _note(t: String, size: int) -> Label:
	var l := _ink(t, size, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l


func _plain_btn(t: String, f: Callable) -> Button:
	var b := UiKit.button(t, 15, f)
	b.focus_mode = Control.FOCUS_NONE
	for st in [["normal", Color.WHITE], ["hover", Color("#fff6d8")], ["pressed", Color("#efe6cf")], ["focus", Color.WHITE]]:
		var bx := UiKit.box(st[1], 4, 1, UiKit.INK)
		bx.content_margin_top = 4
		bx.content_margin_bottom = 4
		bx.content_margin_left = 10
		bx.content_margin_right = 10
		b.add_theme_stylebox_override(st[0], bx)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, UiKit.INK)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b
