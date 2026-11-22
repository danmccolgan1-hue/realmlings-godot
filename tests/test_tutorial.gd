extends RefCounted
## The Basic Tutorial can be played to the end: every step comes up in order, every objective can be met, and
## breaking the Swamp Bandits ends it. Played through the game's own commands, as a player would.

var g: Game
var T: Tutorial
var real := 1.0
var errs := []
var verbose := false


func run() -> Array:
	g = Tutorial.start()
	T = g.tutorial
	g.paused = false
	g.battle_rand = func(): return 0.5
	var wf: Variant = _unit(g.WAYFINDER)
	var mason: Variant = _unit(Game.MASON)
	var TP := Tutorial.TP
	_expect(g.capital == TP.capital, "the capital is the grassland province")
	_expect(_unit("army") == null, "no starting army")
	_expect(g.bandits_in(TP.bandits), "the Swamp Bandits are in their swamp")
	_until(func(): return T.objs.any(func(o): return o.key == "capital"), "step 1")
	T.selected.capital = true
	_until(func(): return T.objs.any(func(o): return o.key == "research"), "step 2 (research)")
	var id: String = g.tech.gov.opts[0]
	g.pick_tech(id)
	_until(func(): return T.objs.any(func(o): return o.key == "wayfinder"), "step 3.1 (Wayfinder)")
	T.selected.wayfinder = true
	_until(func(): return T.objs.any(func(o): return o.key == "survey"), "step 4 (survey)")
	g.queue_survey(wf, TP.forest)
	_until(func(): return T.objs.any(func(o): return o.key == "explore"), "step 5 (explore)")
	g.order(wf, TP.swamp)
	_until(func(): return T.objs.any(func(o): return o.key == "outpost"), "step 8 (outpost)")
	g.order_build(mason, TP.forest, "outpost")
	_until(func(): return T.objs.any(func(o): return o.key == "fort"), "step 13 (fort)")
	_until(func(): return g.upgrade_why(TP.forest) == null, "the outpost can be upgraded")
	g.start_upgrade(TP.forest)
	_until(func(): return T.next > 13 and T.cur == null, "step 14")
	g.order(wf, TP.desert)
	_until(func(): return g.explored.has(TP.desert), "the desert explored")
	g.order(wf, TP.bandits)
	_until(func(): return T.objs.any(func(o): return o.key == "barracks"), "step 16 (bandits seen, barracks)")
	_expect(g.build_check(g.capital, "barracks") == null, "a Barracks may be built now: %s" % g.build_check(g.capital, "barracks"))
	g.order_build(mason, g.capital, "barracks")
	_until(func(): return T.objs.any(func(o): return o.key == "swords"), "step 17 (Footmen)")
	for i in 3:
		g.train("barracks", g.capital, g.footman_of())
	_until(func(): return T.done.has("swords"), "three Footmen trained")
	g.order(_unit("army"), TP.bandits)
	_until(func(): return T.ended and T.final_shown, "the bandits broken and the tutorial finished")
	_expect(T.done.size() == T.objs.size(), "every objective ticked")
	return errs


func _unit(kind: String):
	for u in g.units:
		if u.owner == Game.HOST and u.kind == kind:
			return u
	return null


func _expect(ok: bool, what: String) -> void:
	if not ok:
		errs.append(what)


## Play on (reading every line as it comes) until `cond` holds, at most 10 minutes of game time.
func _until(cond: Callable, what: String) -> void:
	if not errs.is_empty():
		return
	var t0 := g.t
	if verbose:
		printerr("  until: ", what, " t=", g.t, " step=", T.next)
	while g.t - t0 < 600:
		while T.shown() != null:
			T.next_line()
		if cond.call():
			return
		real += 0.1
		g.update(real)
	errs.append("never reached: %s (at step %s)" % [what, T.next])
