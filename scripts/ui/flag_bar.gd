class_name FlagBar
extends HBoxContainer
## Notification flags: banners above the command card when something needs you (an idle research tree, Army
## Exhaustion, an open plot a free Mason could fill, something you can afford to upgrade, a quake, a truce running out,
## warscore at ±100, a war about to end in white peace, a spell ready, requests waiting, war news, being over the
## province limit). Left-click deals with it, right-click dismisses it until its reason goes away and comes back.
## web: flags.js with the v96, v98, v102, v105 and v106 wrappers of flagList and their click handlers.
## Views only: clicks go through the HUD and the Game's own actions.

const TRUCE_WARN := 30.0
const WAR_TIMER_SHOW := 30.0
const SPELL_FLAGS := [{"k": "graverob", "img": "sp_graverob", "school": "death", "mana": true},
	{"k": "trading", "img": "sp_trading", "school": "arcane", "mana": true}]   # (the Sacred Pyre's flag is the Swamplings')
const TREE_NAME := {"gov": "Government", "mil": "Military", "mag": "Magic"}
const TREE_IMG := {"gov": "government", "mil": "military", "mag": "magic"}

var game: Game
var hud
var ack := {}        # flag id -> true, or {instance key: true} for flags with several places (web: v102 flagAck)
var cycle := {}      # flag id -> index of the place the last click went to (web: v102 flagCycle)
var shown := []      # the flags on screen
var key := ""
var next_at := 0.0
var inst_cache := {}


func setup(g: Game, h) -> void:
	game = g
	hud = h
	ack.clear()
	cycle.clear()
	key = ""
	add_theme_constant_override("separation", 4)
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The flags as the web game lists them, in its order. web: flagList and its wrappers
func flag_list() -> Array:
	var out := []
	var g := game
	# flags.js
	for tr in ["gov", "mil", "mag"]:
		var st: Dictionary = g.tech[tr]
		if st.tier and st.cur == null and not st.opts.is_empty():
			out.append({"id": "r-" + tr, "img": TREE_IMG[tr], "tip": "Research idle: pick a %s technology (left-click to open Research, right-click to dismiss)" % TREE_NAME[tr]})
	if g.exhaust > 0:
		out.append({"id": "exh", "img": "army_exhaustion", "warn": true, "n": g.exhaust, "tip": "Army Exhaustion %d/%d: you can’t feed your soldiers" % [g.exhaust, GameData.c("EXHAUST_MAX")]})
	if not _inst("plots").is_empty():
		out.append({"id": "plots", "img": "empty_plots", "tip": "A Mason is free and a building plot is open: left-click to go there, right-click to dismiss"})
	var ups := _inst("upg")
	if not ups.is_empty():
		out.append({"id": "upg", "img": "upgrade", "tip": "You can afford to upgrade %s in %s: left-click to go there, right-click to dismiss" % [_upg_what(ups[0]), g.prov_name(ups[0].p)]})
	for q in g.quakes:
		var nm: String = g.spell2_name(q.kind) if q.kind == "shock" else "Earthquake"
		out.append({"id": "quake:%d" % q.id, "img": "earthquake", "warn": true, "tip": "%s at %s: left-click to look, right-click to dismiss" % [nm, g.prov_name(q.from)], "label": "%s at %s" % [nm, g.prov_name(q.from)]})
	for o in g.nations:
		var left := g.truce_left(Game.ME, o)
		if left > 0 and left <= TRUCE_WARN and g.alive_nation(o):
			out.append({"id": "truce:%d" % o, "img": "truce", "warn": true, "tip": "Your truce with the %s is ending soon: left-click to look at their land, right-click to dismiss" % g.player_info(o).name, "label": "Truce ending soon"})
	# v96: warscore at ±100, the white-peace timer
	for w in g.wars_of(Game.ME):
		var o := Game.foe_of(w, Game.ME)
		var s := g.warscore(w, Game.ME)
		var left: float = Game.WAR_TIMER - (g.t - w.since)
		if absi(s) >= g.W("total"):
			out.append({"id": "peace100:%d" % w.id, "img": "peace", "label": "Call for peace", "tip": ("Warscore +100 against the %s: call for peace and take what you want. Left-click to open Diplomacy" if s > 0 else "Warscore −100 against the %s: call for peace (surrender) before they take more. Left-click to open Diplomacy") % g.player_info(o).name})
		if left <= WAR_TIMER_SHOW and left > 0 and w.get("parent") == null:
			out.append({"id": "wpt:%d" % w.id, "img": "wptimer", "warn": true, "n": ceili(left), "label": "White peace", "tip": "The war with the %s ends in white peace in %d s unless a peace deal is made. Left-click to open Diplomacy" % [g.player_info(o).name, ceili(left)]})
	# v98: economic spells ready (v102 #27: not while there is no room for what they bring in)
	var sc = g.current_school()
	if sc != null:
		for F in SPELL_FLAGS:
			if sc != F.school or not g.lvl(F.k) or g.cd_left(F.k) > 0:
				continue
			if g.units.any(func(v): return v.get("cast") != null and v.cast.spell == "q:" + F.k):
				continue
			var full := func(k): return g.stock[k] >= g.storage_cap(k)
			if (F.k == "graverob" and full.call("gold")) or (F.k == "trading" and Game.RES.all(full)):
				continue
			var c = g.ready_caster(F.k, F.mana)
			if c == null:
				continue
			var nm: String = g.TECH_BY_ID[g.line_tech(F.k)].name
			out.append({"id": "spell:" + F.k, "img": F.img, "label": nm, "tip": "%s is ready and %s can cast it. Left-click to select him, right-click to dismiss" % [nm, c.name]})
	# v102: right-clicked flags stay hidden until their reason goes away, or a new place for them turns up
	var ids := {}
	for f in out:
		ids[f.id] = true
	for id in ack.keys():
		if not ids.has(id) and id != "overlimit":   # (the province-limit flag comes later and keeps its own)
			ack.erase(id)
	out = out.filter(func(f):
		if not ack.has(f.id):
			return true
		var a = ack[f.id]
		if not (a is Dictionary):
			return false
		var cur := _inst(f.id).map(func(x): return x.key)
		if cur.any(func(k): return not a.has(k)):
			ack.erase(f.id)
			return true
		var still := {}
		for k in cur:
			still[k] = true
		ack[f.id] = still
		return false)
	# v105: requests waiting (all but the one on screen), news of other nations' wars
	if not g.dipl.is_empty():
		var D := g.dipl_state()
		var on_screen = null
		for r in D.reqs:
			if not r.min:
				on_screen = r
				break
		for r in D.reqs:
			if not is_same(r, on_screen):
				out.append({"id": "dxreq:%d" % r.id, "img": "dxreq", "warn": true, "label": Game.REQ_NAME[r.kind], "tip": "%s from the %s: left-click to answer (declined when the time runs out), right-click to decline" % [Game.REQ_NAME[r.kind], g.player_info(r.from).name]})
		for n in D.news:
			var war: bool = n.kind == "war"
			out.append({"id": "dxnews:%d" % n.id, "img": "dxwar" if war else "dxpeace", "label": "War" if war else "Peace",
				"tip": ("The %s declared war on the %s. Left-click for Diplomacy, right-click to dismiss" if war else "The %s and the %s made peace. Left-click for Diplomacy, right-click to dismiss") % [g.player_info(n.a).name, g.player_info(n.b).name]})
	# v106: over the province limit
	var over := g.over_limit()
	if over > 0 and not ack.has("overlimit"):
		var per: int = GameData.c("OVER_UPKEEP")
		out.append({"id": "overlimit", "img": "overlimit", "warn": true, "n": over, "label": "Over the limit",
			"tip": "Over your province limit: %d provinces, your forts hold %d. Each province over costs %d gold, %d wood and %d food upkeep (−%d of each now). Build or develop forts to hold more. Left-click for details, right-click to dismiss" % [g.provs_of(Game.ME).size(), g.prov_limit(), per, per, per, over * per]})
	elif over <= 0:
		ack.erase("overlimit")
	return out


func _upg_what(u: Dictionary) -> String:
	if u.part == "settlement":
		return "the outpost (to a Fort)"
	var e = _extra(u.p, u.part)
	var d: Dictionary = game.BUILD_DEFS[e.type]
	var lv: int = e.get("level", 1)
	return "the %s (to a %s)" % [d.levels[lv - 1], d.levels[lv]]


func _extra(p: int, part: String):
	var slot := int(part.split("@")[1])
	for e in game.extras_in(p):
		if e.slot == slot:
			return e
	return null


## The places a flag can take you, each with a key (web: v102 FLAG_INST, refreshed at most once a second)
func _inst(id: String, fresh := false) -> Array:
	if id != "plots" and id != "upg":
		return []
	var now := Time.get_ticks_msec() / 1000.0
	if not fresh and inst_cache.has(id) and now - inst_cache[id].t < 1.0:
		return inst_cache[id].list
	var list := []
	if id == "plots":
		for p in game.open_plots():
			list.append({"key": "%d@%d" % [p, game.free_plot(p)], "p": p})
	else:
		for u in game.all_upgradable():
			list.append({"key": "%d|%s" % [u.p, u.part], "p": u.p, "part": u.part})
	inst_cache[id] = {"t": now, "list": list}
	return list


func _process(_dt: float) -> void:
	if game == null or not is_visible_in_tree():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < next_at:
		return
	next_at = now + 0.25
	var list := flag_list()
	var k := "|".join(list.map(func(f): return f.id + str(f.get("n", ""))))
	if k == key:
		return
	key = k
	shown = list
	for c in get_children():
		c.queue_free()
	for f in list:
		add_child(_flag_button(f))


func _flag_button(f: Dictionary) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = UiKit.wrap(f.tip)
	b.custom_minimum_size = Vector2(72, 96)
	var sp = Art.get_sprite("flags", "common", "flag_%s.png" % f.img)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(col)
	var pic := TextureRect.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.custom_minimum_size = Vector2(64, 80)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if sp:
		pic.texture = sp.tex
	col.add_child(pic)
	if f.get("label"):
		var l := UiKit.label(13, Color("#ffd2c9") if f.get("warn") else Color.WHITE)
		l.text = f.label
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.custom_minimum_size = Vector2(72, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(l)
		b.custom_minimum_size.y = 118
	if f.has("n"):
		var badge := UiKit.label(18, Color("#ffc93c"))
		badge.text = str(f.n)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(46, 2)
		b.add_child(badge)
	if f.get("warn"):
		var tw := b.create_tween().set_loops()
		tw.tween_property(pic, "modulate", Color(1, 0.8, 0.8), 0.6)
		tw.tween_property(pic, "modulate", Color.WHITE, 0.6)
	var id: String = f.id
	b.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				click(id)
				b.accept_event()
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				dismiss(id)
				b.accept_event())
	return b


## Right-click: every flag of the same kind goes away until its reason does (web: flags.js / v102 / v105 contextmenu)
func dismiss(id: String) -> void:
	var type := id.split(":")[0]
	if id.begins_with("dxreq:"):
		for r in game.dipl_state().reqs:
			if "dxreq:%d" % r.id == id:
				game.answer_request(r, false)
				break
	elif id.begins_with("dxnews:"):
		game.dismiss_news(int(id.split(":")[1]))
	elif id.begins_with("quake:"):
		game.dismiss_quake(int(id.split(":")[1]))
	else:
		for f in shown + [{"id": id}]:
			if f.id.split(":")[0] != type:
				continue
			if f.id == "plots" or f.id == "upg":
				var keys := {}
				for x in _inst(f.id, true):
					keys[x.key] = true
				ack[f.id] = keys
			else:
				ack[f.id] = true
	key = ""
	next_at = 0.0


## Left-click (web: the flags' click handlers)
func click(id: String) -> void:
	var g := game
	key = ""
	next_at = 0.0
	if id.begins_with("r-"):
		if not hud.research.visible:
			hud.toggle_research()
	elif id == "exh":
		hud.add_toast("Army Exhaustion %d/%d: keep food income above zero so you can feed your army. At %d the whole army deserts." % [g.exhaust, GameData.c("EXHAUST_MAX"), GameData.c("EXHAUST_MAX")], true)
	elif id == "plots" or id == "upg":
		var list := _inst(id, true)
		if list.is_empty():
			return
		var i: int = (cycle.get(id, -1) + 1) % list.size()
		cycle[id] = i
		hud.look_at_prov(list[i].p, true)
		if list.size() > 1:
			hud.add_toast("%d of %d: click the flag again for the next one." % [i + 1, list.size()])
	elif id.begins_with("quake:"):
		for q in g.quakes:
			if "quake:%d" % q.id == id:
				hud.look_at_prov(q.from, false)
	elif id.begins_with("truce:"):
		hud.focus_nation(int(id.split(":")[1]))
	elif id.begins_with("peace100:") or id.begins_with("wpt:"):
		hud.diplomacy.open()
	elif id.begins_with("spell:"):
		var k := id.split(":")[1]
		for F in SPELL_FLAGS:
			if F.k == k:
				var c = g.ready_caster(k, F.mana)
				if c != null:
					hud.focus_unit(c)
	elif id.begins_with("dxreq:"):
		var D := g.dipl_state()
		var pick = null
		for r in D.reqs:
			if "dxreq:%d" % r.id == id:
				pick = r
		if pick == null:
			return
		for r in D.reqs:
			r.min = not is_same(r, pick)
		D.reqs = [pick] + D.reqs.filter(func(r): return not is_same(r, pick))
	elif id.begins_with("dxnews:"):
		g.dismiss_news(int(id.split(":")[1]))
		hud.diplomacy.open()
	elif id == "overlimit":
		var n := g.over_limit()
		var per: int = GameData.c("OVER_UPKEEP")
		hud.add_toast("You hold %d provinces and your forts hold %d: %d over the limit, −%d gold, wood and food every 10 s. Build forts, research administration or develop your forts to hold more." % [g.provs_of(Game.ME).size(), g.prov_limit(), n, n * per], true)
