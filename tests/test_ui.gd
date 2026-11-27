extends RefCounted
## The interface's rules that aren't drawing: which notification flags show and when they go away (web: flags.js and
## its wrappers), the Settings debug switches (web: swamp.js), remembered settings, and the patch notes' data.

func run() -> Array:
	var errs := []
	_flags_practice(errs)
	_flags_world(errs)
	_settings(errs)
	_debug(errs)
	_gate_road(errs)
	_fort_cmds(errs)
	_crops(errs)
	_new_game_choices(errs)
	_mage_gear(errs)
	_country(errs)
	_school(errs)
	_orders(errs)
	_arrows_and_sounds(errs)
	var pn: Array = GameData.c("PATCH_NOTES")
	if pn.is_empty() or pn[0].v != "v106":
		errs.append("patch notes: the web game's v106 notes are missing")
	return errs


static func ids(fb: FlagBar) -> Array:
	return fb.flag_list().map(func(f): return f.id)


func _flags_practice(errs: Array) -> void:
	var g := Game.new_practice("ember", "cormac")
	var fb := FlagBar.new()
	fb.game = g
	# an idle research tree
	g.tech.gov.cur = null
	if g.tech.gov.opts.is_empty():
		g.tech.gov.opts = ["x"]
	if not ids(fb).has("r-gov"):
		errs.append("flags: no idle Government research flag")
	fb.dismiss("r-gov")
	if ids(fb).has("r-gov"):
		errs.append("flags: the research flag stays after a right-click")
	var keep = g.tech.gov.opts.duplicate()
	g.tech.gov.opts = []           # the reason goes away...
	ids(fb)
	g.tech.gov.opts = keep         # ...and comes back: the flag with it
	if not ids(fb).has("r-gov"):
		errs.append("flags: the research flag doesn't come back with its reason")
	# Army Exhaustion, with its count
	g.exhaust = 3
	var ex = fb.flag_list().filter(func(f): return f.id == "exh")
	if ex.is_empty() or ex[0].n != 3:
		errs.append("flags: Army Exhaustion flag missing or without its count")
	g.exhaust = 0
	# an open plot and a free Mason, once there is enough to build
	for k in Game.RES:
		g.stock[k] += 3000
	g.debug_cap = 5000
	fb.inst_cache.clear()
	if not ids(fb).has("plots"):
		errs.append("flags: no open-plot flag with a free Mason and full stores")
	fb.dismiss("plots")
	fb.inst_cache.clear()
	if ids(fb).has("plots"):
		errs.append("flags: the open-plot flag stays after a right-click")
	# an outpost you can afford to make a fort
	var q: int = g.open_nbr[g.capital][0].q
	g.buildings[q] = {"stage": 0, "born": 0, "owner": Game.HOST}
	fb.inst_cache.clear()
	var up = fb.flag_list().filter(func(f): return f.id == "upg")
	if g.upgrade_why(q) == null and (up.is_empty() or not str(up[0].tip).contains("the outpost (to a Fort)")):
		errs.append("flags: no upgrade flag for an outpost you can make a fort (%s)" % [up])
	elif g.upgrade_why(q) != null:
		errs.append("flags: test setup: the outpost can't be upgraded: %s" % g.upgrade_why(q))
	# an earthquake: left as a flag until dismissed
	g.quakes.append({"id": 7, "from": g.capital, "to": g.capital, "by": 2, "kind": "quake"})
	if not ids(fb).has("quake:7"):
		errs.append("flags: no earthquake flag")
	fb.dismiss("quake:7")
	if not g.quakes.is_empty():
		errs.append("flags: dismissing the quake flag doesn't forget the quake")
	fb.free()


func _flags_world(errs: Array) -> void:
	var g := Game.new_world("ember", "cormac", ["easy", "easy", "easy"])
	var fb := FlagBar.new()
	fb.game = g
	var ns: Array = g.nations.keys()
	for o in ns:
		g.met[o] = true
	g.news_add("war", ns[0], ns[1])
	var nid := "dxnews:%d" % g.dipl_state().news[-1].id
	if not ids(fb).has(nid):
		errs.append("flags: no war news flag")
	fb.dismiss(nid)
	if ids(fb).has(nid) or not g.dipl_state().news.is_empty():
		errs.append("flags: war news stays after a right-click")
	# two requests: the first is in the request box, the second waits as a flag; right-click declines it
	var r1 = g.dip_request(ns[0], "alliance", {"vs": ns[2]})
	var r2 = g.dip_request(ns[1], "alliance", {"vs": ns[2]})
	var got := ids(fb)
	if got.has("dxreq:%d" % r1.id) or not got.has("dxreq:%d" % r2.id):
		errs.append("flags: requests: want only the second as a flag, got %s" % [got])
	fb.dismiss("dxreq:%d" % r2.id)
	if g.dipl_state().reqs.size() != 1:
		errs.append("flags: right-clicking a request flag doesn't decline it")
	# over the province limit
	var lim := g.prov_limit()
	var free := []
	for p in g.G.provs.size():
		if not g.buildings.has(p) and free.size() < lim + 2:
			free.append(p)
	for p in free:
		g.buildings[p] = {"stage": 0, "born": 0, "owner": Game.HOST}
	var ol = fb.flag_list().filter(func(f): return f.id == "overlimit")
	if ol.is_empty() or ol[0].n != g.over_limit():
		errs.append("flags: no province-limit flag (over by %d)" % g.over_limit())
	fb.dismiss("overlimit")
	if ids(fb).has("overlimit"):
		errs.append("flags: the province-limit flag stays after a right-click")
	fb.free()


func _settings(errs: Array) -> void:
	var keep := [Settings.PATH, Settings.ui_scale, Settings.calm_map, Settings.fullscreen, Settings.record_games]
	Settings.PATH = "user://test_settings.json"
	Settings.ui_scale = 1.3
	Settings.calm_map = true
	Settings.record_games = true
	Settings.save_all()
	Settings.ui_scale = 1.0
	Settings.calm_map = false
	Settings.record_games = false
	Settings._loaded = false
	Settings.load_all()
	if not (is_equal_approx(Settings.ui_scale, 1.3) and Settings.calm_map and Settings.record_games):
		errs.append("settings: not remembered (%s, %s, %s)" % [Settings.ui_scale, Settings.calm_map, Settings.record_games])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	Settings.PATH = keep[0]
	Settings.ui_scale = keep[1]
	Settings.calm_map = keep[2]
	Settings.fullscreen = keep[3]
	Settings.record_games = keep[4]


func _debug(errs: Array) -> void:
	var g := Game.new_practice("river", "cormac")
	var cap := g.storage_cap("wood")
	var wood: int = g.stock.wood
	g.debug_resources()
	if g.storage_cap("wood") != cap + 2000 or g.stock.wood != wood + 2000:
		errs.append("debug: +2000 resources: cap %d→%d, wood %d→%d" % [cap, g.storage_cap("wood"), wood, g.stock.wood])
	var n: int = g.tech.gov.done.size()
	g.debug_all_tech()
	if g.tech.gov.done.size() <= n or g.current_school() == null or not g.debug_tech:
		errs.append("debug: every technology didn't research them (gov %d→%d, school %s)" % [n, g.tech.gov.done.size(), g.current_school()])
	g.debug_reveal(true)
	if g.visible.size() < g.G.provs.size():
		errs.append("debug: reveal leaves %d of %d provinces hidden" % [g.G.provs.size() - g.visible.size(), g.G.provs.size()])


## v106: a Mason can build a road through a wall between two of your own provinces (web: v106.js), and the
## command card's Road button finds that wall when no open border is near (game.gd mason_road_border).
func _gate_road(errs: Array) -> void:
	var g := Game.new_practice("ember", "cormac")
	var m = null
	for u in g.units:
		if u.kind == Game.MASON and u.owner == Game.HOST:
			m = u
	if m == null:
		errs.append("gate road: the practice game has no Mason")
		return
	var p: int = m.prov
	g.tech[g.TECH_BY_ID["roads"].tree].done.append("roads")
	g.stock = {"gold": 999, "wood": 999, "food": 999}
	# wall every border of the Mason's province, and make each neighbor yours
	var near_q := -1
	var near_d := INF
	for i in g.world.edges.size():
		var e: Dictionary = g.world.edges[i]
		if e.a != p and e.b != p:
			continue
		var q: int = e.b if e.a == p else e.a
		if not g.open_between(p, q):
			continue
		g.walls[i] = true
		g.open_nbr[p] = g.open_nbr[p].filter(func(n): return n.q != q)
		g.open_nbr[q] = g.open_nbr[q].filter(func(n): return n.q != p)
		var b: Dictionary = g.buildings[p].duplicate(true)
		b.stage = 0
		g.buildings[q] = b
		var va: Array = g.world.vertices[e.v[0]]
		var vb: Array = g.world.vertices[e.v[1]]
		var mid := Vector2((va[0] + vb[0]) / 2.0, (va[1] + vb[1]) / 2.0)
		if near_q < 0:
			near_q = q
			near_d = 0
			m.x = mid.x
			m.y = mid.y
	if near_q < 0:
		errs.append("gate road: the Mason's province has no land border")
		return
	if g.mason_border(m) >= 0:
		errs.append("gate road: an open border is still in reach")
	if g.mason_road_border(m) != near_q:
		errs.append("gate road: the Road button doesn't find the wall to your own province (got %d, want %d)" % [g.mason_road_border(m), near_q])
	var why = g.link_why("road", m, near_q)
	if why != null:
		errs.append("gate road: a road through your own gate is refused: %s" % why)


## The settlement card's Upgrade can be cancelled for a refund (web: game.js cancelUpgrade), and a fort can be
## dismantled back to an outpost, losing its buildings (web: v96.js dismantleFort).
func _fort_cmds(errs: Array) -> void:
	var g := Game.new_practice("ember", "cormac")
	var q := -1
	for n in g.all_nbr[g.capital]:
		if not g.buildings.has(n):
			q = n
			break
	var b: Dictionary = g.buildings[g.capital].duplicate(true)
	b.stage = 0
	g.buildings[q] = b
	g.stock = {"gold": 5000, "wood": 5000, "food": 5000}
	var before: Dictionary = g.stock.duplicate()
	if not g.start_upgrade(q):
		errs.append("fort: the upgrade doesn't start: %s" % g.upgrade_why(q))
		return
	g.cancel_upgrade(q)
	if g.upgrades.has(q) or ["gold", "wood", "food"].any(func(k): return int(g.stock[k]) != int(before[k])):
		errs.append("fort: cancelling the upgrade doesn't refund it (%s vs %s)" % [g.stock, before])
	g.buildings[q].stage = 1
	g.extras[q] = [{"type": "farm", "slot": 0}]
	if g.dismantle_why(q) != null:
		errs.append("fort: can't dismantle: %s" % g.dismantle_why(q))
	g.dismantle_fort(q)
	if g.buildings[q].stage != 0 or not g.extras_in(q).is_empty():
		errs.append("fort: dismantling leaves stage %d with %d buildings" % [g.buildings[q].stage, g.extras_in(q).size()])


## v104 crops for the player: a Cash crop gives 3 food and 1 gold, a Fiber crop 2 wood and no wood upkeep, one Fiber
## crop per province, a change takes 10 s, and "Apply to all" plans every Farm (web: v104.js).
func _crops(errs: Array) -> void:
	var g := Game.new_practice("ember", "cormac")
	var p := g.capital
	g.extras[p] = g.extras_in(p) + [{"type": "farm", "slot": 4}, {"type": "farm", "slot": 5}]
	g.compute_income()
	var st := g.gives_of("farm")
	var base := g.extras_bonus(p)
	var up0 := g.upkeep()
	var f1: Dictionary = g.extras_in(p).filter(func(e): return e.type == "farm")[0]
	var f2: Dictionary = g.extras_in(p).filter(func(e): return e.type == "farm")[1]
	Ai.set_crop(g, f1, "cash")
	if f1.get("cropNext") != "cash" or absf(f1.cropAt - (g.t + Ai.CROP_DELAY)) > 0.01:
		errs.append("crops: a new crop doesn't wait %d s" % int(Ai.CROP_DELAY))
	g.t += Ai.CROP_DELAY + 1
	g.crop_scan_at = 0
	Ai.step_crops(g)
	if Ai.crop_of(f1) != "cash":
		errs.append("crops: the Cash crop never grows")
	var cash := g.extras_bonus(p)
	if cash.food != base.food - st.get("food", 0) + 3 or cash.gold != base.gold + 1:
		errs.append("crops: a Cash crop gives %s (was %s, staple %s)" % [cash, base, st])
	f2.crop = "fiber"
	var fib := g.extras_bonus(p)
	if fib.wood != base.wood + 2:
		errs.append("crops: a Fiber crop gives %s" % fib)
	if g.upkeep().wood != up0.wood - Ai.crop_up(g, "staple"):
		errs.append("crops: a Fiber crop still pays wood upkeep (%d vs %d)" % [g.upkeep().wood, up0.wood])
	if not Ai.fiber_taken(g, p, f1):
		errs.append("crops: a second Fiber crop is allowed in one province")
	var plan: Dictionary = Ai.crop_all_plan(g, "staple")
	if plan.plan.size() != 2:
		errs.append("crops: Apply to all (Corn) would change %d Farms, not 2" % plan.plan.size())


## The New Game page's choices reach the game: your nation's name, color and flag, the island's shape (a "map:" mode),
## and computer nations never take your color or flag; a save keeps them all (web: menu.js startGame, mapMode;
## features.js applyNation).
func _new_game_choices(errs: Array) -> void:
	var opts := {"shape": "ring", "pens": 1, "coves": 3, "trees": 2}
	if Game.map_mode(opts) != "map:ring:1:3:2" or Game.map_mode({"shape": "classic", "pens": 2, "coves": 2, "trees": 0}) != "normal":
		errs.append("new game: map modes are %s / %s" % [Game.map_mode(opts), Game.map_mode({"shape": "classic", "pens": 2, "coves": 2, "trees": 0})])
	if Game.map_opts_of("map:ring:1:3:2") != opts.merged({"lakes": -1}):   # (0.19.3: lakes, -1 when not chosen)
		errs.append("new game: map_opts_of doesn't read the mode back")
	var nat := {"name": "The Thistle Crown", "color": 3, "emblem": "fleur"}
	var g := Game.new_world("lantern-fable-63", "cormac", ["easy", "moderate"], "center", {}, opts, nat)
	var NC: Array = GameData.c("NATION_COLORS")
	if g.world.mode != "map:ring:1:3:2":
		errs.append("new game: the world's mode is %s" % g.world.mode)
	if g.player_info(Game.HOST).name != "The Thistle Crown" or g.player_info(Game.HOST).color != NC[3][0] or g.my_nation.emblem != "fleur":
		errs.append("new game: your nation is %s / %s" % [g.player_info(Game.HOST), g.my_nation])
	for o in g.nations:
		if g.player_info(o).color == NC[3][0] or g.nations[o].get("emblem") == "fleur":
			errs.append("new game: nation %d took your color or flag" % o)
	var back := Game.from_save(JSON.parse_string(JSON.stringify(g.to_save())))
	if back == null or back.world.mode != g.world.mode or back.my_nation != g.my_nation or back.G.provs.size() != g.G.provs.size():
		errs.append("new game: a save loses the island or your nation")
	var pr := Game.new_practice("ember", "", {}, nat)
	if pr.player_info(Game.HOST).name != "The Thistle Crown":
		errs.append("new game: the practice island ignores your nation's name")


# the Armory's Mage gear (web: magic.js mageStats, values from the web game) and that it survives a save
func _mage_gear(errs: Array) -> void:
	var g := Game.new_practice("ember", "cormac")
	var want := {"stave|": [4, 0.0769, 0.8, "Stave."], "grandstave|": [6, 0.0769, 0.8, "Grand Stave. Spells cast 10% faster."],
		"wand|round": [2, 0.25, 0.8, "Wand and Round Shield."], "crypticwand|tower": [3, 0.4783, 0.736, "Cryptic Wand and Tower Shield. Spells cost 10% less mana."]}
	for k in want:
		var p: PackedStringArray = k.split("|")
		var st := g.mage_stats({"weapon": p[0], "shield": p[1] if p[1] != "" else null})
		var w: Array = want[k]
		if st.atk != w[0] or absf(st.red - w[1]) > 0.001 or absf(st.speed - w[2]) > 0.001 or st.blurb != w[3] or st.hp != 25:
			errs.append("Mage gear %s: got atk %s red %.4f speed %.3f %s" % [k, st.atk, st.red, st.speed, st.blurb])
	if g.mage_gear_why("weapon", "grandstave") == null:
		errs.append("Mage gear: the Grand Stave isn't locked behind its research")
	g.set_mage_gear({"weapon": "crypticwand", "shield": "tower"})
	if absf(g.DSTATS[g.MAGE].speed - 0.736) > 0.001 or g.UNIT_SPEED[g.MAGE] != g.DSTATS[g.MAGE].speed:
		errs.append("Mage gear: equipping doesn't change every Mage's stats")
	g.set_mage_gear({"weapon": "stave", "shield": "tower"})
	if g.mage_gear.shield != null:
		errs.append("Mage gear: a two-handed stave keeps its shield")
	g.set_mage_gear({"weapon": "wand", "shield": "round"})
	var g2 := Game.from_save(JSON.parse_string(JSON.stringify(g.to_save())))
	if g2.mage_gear.weapon != "wand" or absf(g2.DSTATS[g2.MAGE].red - 0.25) > 0.001:
		errs.append("Mage gear: not kept by a save")
	# a design made in the Armory is drawn as the starting soldier of its weapon family
	var d := g.add_design({"name": "Maceman", "type": "inf", "weapon": "mace", "armor": "chain2"})
	var c := g.add_design({"name": "Lancer", "type": "cav", "weapon": "spear", "armor": "leather1", "horse": "riding"})
	if Art.design_art(g, d.id) != "d-club" or Art.design_art(g, c.id) != "d-rider" or Art.design_art(g, "d-spear") != "d-spear":
		errs.append("Armory: a design's art isn't its family's starting soldier")


# the Country Breakdown: gross income less building and unit upkeep is the net income (web: v78.js upkeepSplit)
func _country(errs: Array) -> void:
	var g := Game.new_world("ember", "cormac", ["moderate"], "center")
	g.compute_income()
	var sp := g.upkeep_split()
	var gross: Dictionary = g.income_parts.gross
	for k in Game.RES:
		if absf(gross[k] - sp.units[k] - sp.blds[k] - g.income[k]) > 0.01:
			errs.append("country: %s gross %s − units %s − buildings %s ≠ net %s" % [k, gross[k], sp.units[k], sp.blds[k], g.income[k]])
	if CountryWindow.clock(65) != "1:05" or CountryWindow.clock(3725) != "1:02:05":
		errs.append("country: the game clock reads %s / %s" % [CountryWindow.clock(65), CountryWindow.clock(3725)])


# the school of magic: offered when Magic research unlocks, picked as the research, forgotten when abandoned
func _school(errs: Array) -> void:
	var g := Game.new_practice("ember", "cormac")
	g.tech.mag.tier = 0
	g.extras[g.capital] = g.extras_in(g.capital) + [{"type": "magetower", "slot": 4}]
	g.tech_payday()
	if not g.school_popup:
		errs.append("school: no school choice when the first Mage Tower stands")
	if not g.pick_school("arcane") or g.tech.mag.cur != "school-arcane":
		errs.append("school: picking Arcane doesn't make it the Magic research (cur %s)" % g.tech.mag.cur)
	g.tech.mag.prog = 99999.0
	g.finish_tech("mag")
	if g.current_school() != "arcane":
		errs.append("school: Arcane not learned")
	g.tech.mag.done.append("arcscouts")
	g.tech.mag.cur = "abandon"
	g.finish_tech("mag")
	if g.current_school() != null or g.tech.mag.done.has("arcscouts") or g.tech.mag.done.has("abandon") or not g.school_popup:
		errs.append("school: abandoning keeps the school or its spells (done %s)" % [g.tech.mag.done])


# orders for a group (web: game.js formation / orderGroup / queueSurvey): spots around the click, Shift queues
# behind what a busy unit is doing, a survey goes to the Wayfinder with the fewest to do
func _orders(errs: Array) -> void:
	var f := Game.formation(7)
	if f.size() != 7 or f[0] != [0.0, 0.0] or absf(Vector2(f[1][0], f[1][1] / 0.8).length() - 30.0) > 0.01:
		errs.append("orders: formation spots %s" % [f])
	var g := Game.new_practice("ember", "cormac")
	var ws: Array = g.units.filter(func(v): return v.owner == Game.HOST and v.kind != "army")
	var nb: Array = g.open_nbr[g.capital].map(func(n): return n.q)
	for q in nb:
		g.explored[q] = true
	var ic: Array = g.G.provs[nb[0]].ic
	var moved := g.order_group(ws, nb[0], false, [ic[0], ic[1]])
	if moved.size() != ws.size():
		errs.append("orders: %d of %d units set off together" % [moved.size(), ws.size()])
	var ends := {}
	for u in moved:
		var last = u.path[-1] if not u.path.is_empty() else null
		if last != null:
			ends["%d,%d" % [roundi(last.x), roundi(last.y)]] = true
	if ends.size() < moved.size():
		errs.append("orders: the group stacks on one spot instead of spreading out")
	g.order_group(ws, nb[1], true, null)   # Shift: queued behind the walk
	if ws.any(func(u): return u.surveyQueue.is_empty() or u.surveyQueue[-1].get("move") != nb[1]):
		errs.append("orders: a Shift order isn't queued behind the walk")
	var wf: Array = ws.filter(func(v): return v.kind == g.WAYFINDER)
	g.queue_survey_on(wf, nb[2], true)
	if not g.survey_queued(nb[2]) or g.survey_why(nb[2], wf) != "Already on a survey list":
		errs.append("orders: a queued survey isn't on the list")
	if g.queue_len(wf[0]) < 2:
		errs.append("orders: the survey replaced the queued move (Shift keeps it)")


# web: govtech.js stepArrows: a fort with Arrowslits shoots the hostile army in its province every 10 s;
# the rules name their sounds for the view (Game.sfx) and record the effects it shows (Game.fx)
func _arrows_and_sounds(errs: Array) -> void:
	var g := Game.new_practice("ember", "cormac")
	var heard := []
	g.on_sfx = func(n, _p, _v): heard.append(n)
	g.buildings[g.capital].stage = 1
	g.tech.gov.done.append("arrowslits")
	var q: int = g.open_nbr[g.capital][0].q
	var gang := g.spawn_bandit(q)
	gang.troops = {"d-sword": 3}
	gang.prov = g.capital
	gang.moving = false
	g.step_arrows(100.0)
	if not g.arrow_at.has(g.capital):
		errs.append("arrows: the fort doesn't take aim at the bandits")
	g.step_arrows(110.0)
	if g.troop_count(gang) >= 3 or not g.fx.any(func(x): return x.kind == "arrow") or not g.fx.any(func(x): return x.kind == "num"):
		errs.append("arrows: no arrows loosed after 10 s (troops %d, fx %s)" % [g.troop_count(gang), g.fx.map(func(x): return x.kind)])
	var m = g.units.filter(func(v): return v.kind == Game.MASON)[0]
	g.stock.gold += 1000
	g.stock.wood += 1000
	g.order_build(m, m.prov, "farm")
	if not heard.has("bld_work"):
		errs.append("sounds: building gives no work sound (heard %s)" % [heard])
	for k in ["bld_work", "ui_click", "war_declare", "mg_school", "bat_win"]:
		if not ResourceLoader.exists("res://assets/audio/sfx/%s.mp3" % k):
			errs.append("sounds: %s.mp3 missing" % k)
	if not ResourceLoader.exists("res://assets/audio/music/tavern.mp3"):
		errs.append("music: tavern.mp3 missing")
