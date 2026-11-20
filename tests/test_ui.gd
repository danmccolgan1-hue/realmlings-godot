extends RefCounted
## The interface's rules that aren't drawing: which notification flags show and when they go away (web: flags.js and
## its wrappers), the Settings debug switches (web: swamp.js), remembered settings, and the patch notes' data.

func run() -> Array:
	var errs := []
	_flags_practice(errs)
	_flags_world(errs)
	_settings(errs)
	_debug(errs)
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
