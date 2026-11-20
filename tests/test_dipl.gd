class_name TestDipl
extends RefCounted
## The player's diplomatic actions on a full-size map: flirting, a gift, military access both ways, a Trade Network,
## an alliance, spies, bribes. Fixtures: tools/gen_dipl_fixtures.py (brains frozen, Math.random pinned to 0.5).

const DIR := "res://tests/fixtures/dipl/"


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


static func snap(g: Game, ids: Array) -> Dictionary:
	var D := g.dipl_state()
	var intel := []
	for o in D.intel:
		intel.append([o, D.intel[o].get("power", 0), D.intel[o].get("provs", []).size()])
	return {"t": r6(g.t), "stock": g.stock.duplicate(), "income": g.income.duplicate(),
		"nations": ids.map(func(o): return [o, g.nations[o].stock.duplicate(), g.opinion(o, Game.ME) if g.alive_nation(o) else 0, g.nations[o].get("giftVault", 0)]),
		"mods": D.mods.map(func(m): return [m.o, m.t, m.kind, m.v, r6(m.until)]), "access": D.access.map(func(x): return [x.from, x.to]),
		"trade": D.trade.map(func(P): return [P.a, P.b]), "allies": g.allies.map(func(A): return [A.a, A.b]), "wars": g.wars.map(func(w): return [w.a, w.b]),
		"news": D.news.map(func(n): return [n.kind, n.a, n.b]), "reqs": D.reqs.map(func(r): return [r.from, r.kind]), "spies": D.spies.keys(),
		"intel": intel}


static func play(fx: Dictionary) -> Array:
	var errs := []
	var g := Game.new_world(fx.seed, fx.leader, fx.slots, "center")
	g.battle_rand = func(): return 0.5
	g.ai_frozen = true
	g.units = g.units.filter(func(u): return not u.get("bandit", false))
	g.travelers.clear()
	g.paused = false
	for o in g.nations:
		g.met[o] = true
	var ids: Array = fx.ids.map(func(x): return int(x))
	var acts: Array = fx.actions
	var k := 0
	var si := 0
	for i in int(fx.frames):
		while k < acts.size() and g.t >= float(acts[k].t):
			var A: Dictionary = acts[k]
			k += 1
			match A.a:
				"own":
					g.buildings[int(A.p)] = {"stage": 0, "born": 0, "owner": Game.ME}
					g.surveyed[int(A.p)] = 0
					g.compute_income()
					g.compute_fog()
				"gold":
					g.stock.gold = int(A.n)
				"claimfor":
					if A.has("p") and A.p != null:
						g.buildings[int(A.p)] = {"stage": 0, "born": g.t, "owner": int(A.o)}
				"dx":
					g.dx_act(A.act, int(A.o))
				"bribe":
					if int(A.y) >= 0:
						g.dx_act("bribe", int(A.o), int(A.y))
		g.update(1.0 + i * 0.1)
		if i % 10 == 0:
			var want: Dictionary = fx.snaps[si]
			si += 1
			var got := snap(g, ids)
			for key in got:
				if not TestDecor._close(want[key], got[key]):
					errs.append("t=%s %s: got %s, want %s" % [want.t, key, JSON.stringify(got[key]).left(700), JSON.stringify(want[key]).left(700)])
			if not errs.is_empty():
				return errs
	return errs
