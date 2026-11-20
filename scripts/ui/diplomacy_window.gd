class_name DiplomacyWindow
extends Control
## Diplomacy (Y): the nations you have met, what they think of you, your wars and their warscore, declaring war,
## proclaiming an enemy, and the peace terms you can offer. web: war.js renderDip / v105.js dxPanelHTML / v106.js.
## Views only: every change goes through the game's own functions (declare_war, make_peace, proclaim_enemy…).

var game: Game
var hud
var win: Dictionary
var body: VBoxContainer
var key := ""
var tick := 0.0

const DIFF_NAME := {"easy": "Easy", "moderate": "Moderate", "difficult": "Difficult"}


func setup(g: Game, h) -> void:
	game = g
	hud = h
	if win.is_empty():
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		win = UiKit.window("Diplomacy", 900, func(): close())
		add_child(win.panel)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(860, 560)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		win.body.add_child(scroll)
		body = VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 10)
		scroll.add_child(body)
	win.panel.hide()
	key = ""


func toggle() -> void:
	if win.panel.visible:
		close()
	else:
		open()


func open() -> void:
	if game == null or game.nations.is_empty():
		if hud:
			hud.add_toast("There are no other nations on the Practice island.", true)
		return
	key = ""
	_refresh()
	win.panel.show()
	UiKit.center.call_deferred(win.panel)


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
	var parts := [game.fallen, game.wars.size(), game.allies.size(), game.artifacts.get(Game.ME, []).size(), D.news.size(), D.access.size(), D.trade.size(),
		D.spies.size(), D.mods.size(), int(game.stock.gold) / 100, D.intel.size()]
	for w in game.wars:
		parts.append([w.id, game.warscore(w, Game.ME), int(game.t - w.since) / 30])
	for o in game.live_nations():
		if o == Game.ME:
			continue
		parts.append([o, game.knows(o), game.opinion(o, Game.ME), game.declare_why(Game.ME, o), game.proclaim_why(Game.ME, o), int(game.truce_left(Game.ME, o)) / 30, game.provs_of(o).size(), game.enemy_of(o)])
	return str(parts)


func _refresh() -> void:
	var k := _state_key()
	if k == key:
		return
	key = k
	UiKit.clear(body)
	var arts: Array = game.artifacts.get(Game.ME, [])
	if not arts.is_empty():
		var al := UiKit.rich(18, 840)
		al.text = "[b]Your artifacts:[/b] " + "; ".join(arts.map(func(id): return "%s — %s" % [Game.ARTIFACTS[id].name, Game.ARTIFACTS[id].desc]))
		body.add_child(al)
	_news()
	_wars()
	_nations()


func _swatch(o: int) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(game.player_info(o).color)
	c.custom_minimum_size = Vector2(22, 22)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _heading(txt: String) -> void:
	var l := UiKit.ink(22)
	l.text = txt
	body.add_child(l)


# --- news of wars between the nations you know (web: v105.js newsAdd flags) ---
func _news() -> void:
	var D := game.dipl_state()
	if D.news.is_empty():
		return
	var l := UiKit.rich(17, 840)
	var lines := []
	for n in D.news:
		lines.append(("%s: the %s declared war on the %s" if n.kind == "war" else "%s: the %s and the %s made peace") % [Game.fmt_time(n.t), game.player_info(n.a).name, game.player_info(n.b).name])
	l.text = "[b]News:[/b] " + "; ".join(lines) + "."
	body.add_child(l)


# --- your wars and the peace you can offer ---
func _wars() -> void:
	var mine := game.wars_of(Game.ME)
	_heading("Your wars" if not mine.is_empty() else "You are at peace")
	for w in mine:
		var foe := Game.foe_of(w, Game.ME)
		var s := game.warscore(w, Game.ME)
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", UiKit.box(Color("#f3dcd0"), 10, 2))
		var col := VBoxContainer.new()
		box.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_swatch(foe))
		var t := UiKit.rich(19, 760)
		var why_w := "attacked you" if w.a == foe else "you declared"
		t.text = "[b]At war with the %s[/b] (%s, %s ago). Warscore [b]%s%d[/b]. %s" % [game.player_info(foe).name, why_w,
			Game.fmt_time(game.t - w.since), "+" if s >= 0 else "", s, _score_hint(s)]
		row.add_child(t)
		col.add_child(row)
		var terms := HBoxContainer.new()
		terms.add_theme_constant_override("separation", 8)
		col.add_child(terms)
		var picks := _province_pick(w, s, foe)
		var opts := [["White peace", "white", []], ["Take gold", "gold", []]]
		if not picks.is_empty():
			var all: bool = picks.size() == game.provs_of(foe).size()
			opts.append([("Annex them (%d provinces)" if all else "Take %d province%s" % [picks.size(), "s" if picks.size() > 1 else ""]) % picks.size(), "provs", picks])
		else:
			opts.append(["Take provinces", "provs", []])
		opts.append(["Surrender", "surrender", []])
		for o in opts:
			var why := game.peace_check(w, o[1], o[2])
			var b := UiKit.button(o[0], 17, _peace.bind(w, o[1], o[2]))
			b.disabled = why != ""
			b.tooltip_text = why if why != "" else _terms_tip(o[1], o[2], foe)
			terms.add_child(b)
		body.add_child(box)
	# truces and the wars between other nations you know of
	var other := game.wars.filter(func(w): return w.a != Game.ME and w.b != Game.ME and (game.knows(w.a) or game.knows(w.b)))
	if not other.is_empty():
		var l := UiKit.rich(18, 840)
		l.text = "[b]Other wars:[/b] " + ", ".join(other.map(func(w): return "the %s against the %s" % [game.player_info(w.a).name, game.player_info(w.b).name]))
		body.add_child(l)


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
func _province_pick(w: Dictionary, s: int, foe: int) -> Array:
	if s < game.W("provs"):
		return []
	if s >= game.W("total") and game.annexable(Game.ME, foe):
		return game.provs_of(foe)
	return game.connected_pick(Game.ME, foe, game.demand_max(s))


func _terms_tip(kind: String, provs: Array, foe: int) -> String:
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
	if game.peace_check(w, kind, provs) != "":
		return
	var terms := {"kind": kind}
	if kind == "provs":
		terms.provs = provs
	var foe := Game.foe_of(w, Game.ME)
	game.make_peace(w, foe if kind == "surrender" else Game.ME, terms)
	key = ""


# --- the nations ---
func _nations() -> void:
	var known := game.ai_ids().filter(func(o): return game.alive_nation(o) and game.knows(o))
	var unknown := game.ai_ids().filter(func(o): return game.alive_nation(o) and not game.knows(o)).size()
	_heading("Nations you have met" if not known.is_empty() else "You haven’t met another nation yet")
	if unknown:
		var u := UiKit.ink(18)
		u.text = "%d nation%s you haven’t met yet. Send Wayfinders out to find them." % [unknown, "s" if unknown > 1 else ""]
		body.add_child(u)
	for o in known:
		var N: Dictionary = game.nations[o]
		var box := PanelContainer.new()
		var war := game.at_war(Game.ME, o)
		box.add_theme_stylebox_override("panel", UiKit.box(Color("#f3dcd0") if war else UiKit.PAPER.darkened(0.05), 10, 2))
		var col := VBoxContainer.new()
		box.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_swatch(o))
		var t := UiKit.rich(19, 520)
		var L = game.leader_of(o)
		var op := game.opinion(o, Game.ME)
		t.text = "[b]%s[/b] — %s%s. %d provinces, army power %d. Opinion of you: [b]%s%d[/b]. %s" % [game.player_info(o).name,
			L.full if L != null else "no leader", " (%s)" % DIFF_NAME.get(N.diff, N.diff), game.provs_of(o).size(),
			int(Ai.nation_power(game, o)), "+" if op >= 0 else "", op, _relation(o)]
		t.tooltip_text = _opinion_tip(o)
		row.add_child(t)
		col.add_child(row)
		var intel = game.dipl_state().intel.get(o)
		if intel != null and intel.has("power"):
			var il := UiKit.ink(16)
			il.text = "Spies counted their armies %s ago: power %d." % [Game.fmt_time(game.t - intel.powerT), int(intel.power)]
			col.add_child(il)
		var acts := HFlowContainer.new()
		acts.add_theme_constant_override("h_separation", 6)
		acts.add_theme_constant_override("v_separation", 6)
		col.add_child(acts)
		var D := game.dipl_state()
		var act := func(label: String, why: String, tip: String, a: String, arg := -1):
			var b := UiKit.button(label, 16, func():
				game.dx_act(a, o, arg)
				key = "")
			b.disabled = why != ""
			b.tooltip_text = why if why != "" else tip
			acts.add_child(b)
		if not war:
			act.call("Declare war (%d gold)" % game.W("declareCost").gold, game.declare_why(Game.ME, o), "Their allies join them; yours join you.", "declare")
		act.call("Flirt", game.flirt_why(o), "+%d opinion for 10 minutes." % Game.DIPL.flirt.v, "flirt")
		act.call("Gift (%d gold)" % Game.DIPL.gift.gold, game.gift_why(o), "+%d opinion for 10 minutes." % Game.DIPL.gift.v, "gift")
		if game.allied(Game.ME, o):
			act.call("End the alliance", "", "They no longer join your wars, nor you theirs.", "ally")
		else:
			act.call("Propose an alliance", game.ally_why(Game.ME, o), "If anyone declares war on one of you, the other joins (a Proxy War).", "ally")
		if game.access_given(Game.ME, o):
			act.call("Revoke their access", "", "Their armies may no longer march through your land.", "grant")
		elif not game.allied(Game.ME, o):
			act.call("Offer military access", game.grant_why(o), "Their armies may march through your land; +%d opinion while it stands." % Game.DIPL_ACCESS_OP, "grant")
		if game.access_given(o, Game.ME):
			act.call("Give back their access", "", "Your armies leave their land.", "giveback")
		elif not game.allied(Game.ME, o):
			act.call("Ask for military access", game.ask_why(o), "Your armies may march through their land.", "ask")
		if game.pair_has(D.trade, Game.ME, o) != null:
			act.call("End the Trade Network", "", "", "trade")
		else:
			act.call("Trade Network", game.trade_why(Game.ME, o), "Community and Trade Routes give both nations 10% more gold; +25 opinion.", "trade")
		act.call("Send spies (%d gold)" % Game.DIPL.spy.gold, game.spy_why(o), "3 minutes; 10% they are caught (−50 opinion), else they map provinces or count their armies.", "spy")
		if game.enemy_of(Game.ME) == o:
			act.call("Renounce enemy", "", "", "proclaim")
		else:
			act.call("Proclaim enemy", game.proclaim_why(Game.ME, o), "%d opinion with them while it stands; +%d with nations who share the enemy. One every 10 minutes." % [Game.DIPL_ENEMY, Game.DIPL_SHARED], "proclaim")
		var bw := game.bribe_why(o)
		if bw == "":
			for y in game.bribe_targets(o):
				act.call("Bribe to attack the %s (%d gold)" % [game.player_info(y).name, Game.DIPL.bribe.gold], "", "They declare war on the %s; you pay their war fee too." % game.player_info(y).name, "bribe", y)
		else:
			act.call("Bribe (%d gold)" % Game.DIPL.bribe.gold, bw, "", "bribe")
		body.add_child(box)


func _relation(o: int) -> String:
	if game.at_war(Game.ME, o):
		return "[color=#b3261e]At war.[/color]"
	if game.allied(Game.ME, o):
		return "[color=#2e7d32]Your ally.[/color]"
	if game.truce_left(Game.ME, o) > 0:
		return "Truce: %s left." % Game.fmt_time(game.truce_left(Game.ME, o))
	var parts := []
	if game.enemy_of(o) == Game.ME:
		parts.append("[color=#b3261e]They proclaim you their enemy.[/color]")
	if game.enemy_of(Game.ME) == o:
		parts.append("You proclaim them your enemy.")
	var at := game.enemies_of(o)
	if not at.is_empty():
		parts.append("At war with " + ", ".join(at.map(func(x): return "you" if x == Game.ME else "the " + game.player_info(x).name)) + ".")
	var al := game.allies_of(o)
	if not al.is_empty():
		parts.append("Allied with " + ", ".join(al.map(func(x): return "you" if x == Game.ME else "the " + game.player_info(x).name)) + ".")
	return " ".join(parts) if not parts.is_empty() else "At peace."


func _opinion_tip(o: int) -> String:
	var lines := []
	for part in game.opinion_parts(o, Game.ME):
		lines.append("%s%d  %s" % ["+" if part[1] >= 0 else "", part[1], part[0]])
	return "What they think of you:\n" + ("\n".join(lines) if not lines.is_empty() else "nothing either way")
