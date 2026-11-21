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
	g.buildings[q] = {"stage": 0, "born": 0, "owner": Game.ME}
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
		g.buildings[p] = {"stage": 0, "born": 0, "owner": Game.ME}
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
		if u.kind == Game.MASON and u.owner == Game.ME:
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
