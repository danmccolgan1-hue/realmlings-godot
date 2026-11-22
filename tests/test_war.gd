extends RefCounted
## Wars on a full-size map against a frozen computer nation: declaring, a battle, occupying the capital, warscore,
## the time tick, and peace (gold; annexing a whole nation). Fixtures: tools/gen_war_fixtures.py.

const DIR := "res://tests/fixtures/war/"


func run() -> Array:
	var errs := []
	Game.test_random = 0.5
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".json"):
			continue
		var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		for m in play(fx).slice(0, 6):
			errs.append("%s: %s" % [fx.seed, m])
	Game.test_random = -1.0
	return errs


static func r6(v: float) -> float:
	return snappedf(v, 0.000001)


static func snap(g: Game, foe: int) -> Dictionary:
	var oc := []
	for p in TestPlay.sorted_keys(g.occ):
		oc.append([p, g.occ[p]])
	var pr := []
	for p in TestPlay.sorted_keys(g.occ_prog):
		pr.append([p, g.occ_prog[p].by, r6(g.occ_prog[p].f)])
	var bl := []
	for p in TestPlay.sorted_keys(g.buildings):
		var b: Dictionary = g.buildings[p]
		bl.append([p, b.stage, b.owner, b.get("cc", false)])
	var tr := []
	for k in g.truces:
		tr.append([k, r6(g.truces[k])])
	return {"t": r6(g.t), "stock": g.stock.duplicate(), "foeStock": g.nations[foe].stock.duplicate(),
		"wars": g.wars.map(func(w): return [w.id, w.a, w.b, r6(w.base), w.active, g.warscore(w, Game.HOST), r6(w.peak), r6(w.nextTick), w.parent if w.parent != null else 0]),
		"occ": oc, "prog": pr, "buildings": bl, "battles": g.battles.map(func(b): return [b.prov, TestPlay.str_keys(b.lost)]), "truces": tr,
		"units": g.units.filter(func(u): return u.kind == "army").map(func(u): return [u.id, u.owner, u.prov, u.moving, u.get("exiting", false), u.troops.duplicate()])}


static func play(fx: Dictionary) -> Array:
	var errs := []
	var g := Game.new_world(fx.seed, fx.leader, fx.slots, "center")
	g.battle_rand = func(): return 0.5
	g.ai_frozen = true   # the fixture freezes the brains (stepAI, aiEnemyThink)
	g.units = g.units.filter(func(u): return not u.get("bandit", false))
	g.travelers.clear()
	g.paused = false
	for o in g.nations:
		g.met[o] = true
	var foe := int(fx.foe)
	var acts: Array = fx.actions
	var k := 0
	var si := 0
	for i in int(fx.frames):
		while k < acts.size() and g.t >= float(acts[k].t):
			var A: Dictionary = acts[k]
			k += 1
			match A.a:
				"own":
					g.buildings[int(A.p)] = {"stage": 0, "born": 0, "owner": Game.HOST}
					g.surveyed[int(A.p)] = 0
					g.compute_income()
					g.compute_fog()
				"give":
					g.stock.gold += A.gold
					g.stock.food += A.food
				"declare":
					g.declare_war(Game.HOST, int(A.o))
				"army":
					var tr := {}
					for tk in A.troops:
						tr[tk] = int(A.troops[tk])
					g.new_army(int(A.p), tr)
				"order":
					var mine := g.units.filter(func(u): return u.kind == "army" and u.owner == Game.HOST)
					g.order(mine[-1], int(A.p))
				"peace":
					var w = g.war_between(Game.HOST, int(A.o))
					if w != null:
						var terms := {"kind": A.kind}
						if A.kind == "provs":
							terms.provs = g.provs_of(int(A.o))
						g.make_peace(w, Game.HOST, terms)
		g.update(1.0 + i * 0.1)
		if i % 10 == 0:
			var want: Dictionary = fx.snaps[si]
			si += 1
			var got := snap(g, foe)
			for key in got:
				if not TestDecor._close(want[key], got[key]):
					errs.append("t=%s %s: got %s, want %s" % [want.t, key, JSON.stringify(got[key]).left(600), JSON.stringify(want[key]).left(600)])
			if not errs.is_empty():
				return errs
	return errs
