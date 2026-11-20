class_name TestSiege
extends RefCounted
## Sieges, Shockwave, Earthquake and a boss fight on a full-size map (the computer nations' brains frozen).
## Fixtures: tools/gen_siege_fixtures.py.

const DIR := "res://tests/fixtures/siege/"


func run() -> Array:
	var errs := []
	Game.test_random = 0.5
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".json"):
			continue
		var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		for m in play(fx).slice(0, 6):
			errs.append("%s: %s" % [fx.kase, m])
	Game.test_random = -1.0
	return errs


static func r6(v: float) -> float:
	return snappedf(v, 0.000001)


static func snap(g: Game, foe: int, fc: int) -> Dictionary:
	var oc := []
	for p in TestPlay.sorted_keys(g.occ):
		oc.append([p, g.occ[p]])
	var ws := []
	for i in TestPlay.sorted_keys(g.walls):
		var e: Dictionary = g.world.edges[i]
		var go = g.gate_own.get(g.link_key(e.a, e.b))
		ws.append([i, r6(g.wall_hp.get(i, -1.0)), go.owner if go != null else 0])
	var arts := {}
	for o in g.artifacts:
		arts[str(o)] = g.artifacts[o].duplicate()
	return {"t": r6(g.t), "stock": g.stock.duplicate(), "foeStock": g.nations[foe].stock.duplicate(),
		"wars": g.wars.map(func(w): return [w.a, w.b, g.warscore(w, Game.ME)]), "occ": oc, "walls": ws,
		"extras": g.extras_in(fc).map(func(e): return e.type), "artifacts": arts,
		"battles": g.battles.map(func(b): return [b.prov, TestPlay.str_keys(b.lost)]),
		"units": g.units.filter(func(u): return u.kind == "army").map(func(u): return [u.id, u.owner, u.prov, u.moving,
			u.sieging if u.get("sieging") != null else -1, u.quake.kind if u.get("quake") else "", r6(u.x), r6(u.y), u.troops.duplicate(),
			r6(u.get("mana", -1.0)) if u.has("mana") else -1.0])}


static func play(fx: Dictionary, verbose := false) -> Array:
	var errs := []
	var g := Game.new_world(fx.seed, fx.leader, fx.slots, "center")
	g.battle_rand = func(): return 0.5
	g.ai_frozen = true
	g.units = g.units.filter(func(u): return not u.get("bandit", false) or u.get("boss") != null)
	g.travelers.clear()
	g.paused = false
	for o in g.nations:
		g.met[o] = true
	var foe := int(fx.foe)
	var fc := int(fx.fc)
	var acts: Array = fx.actions
	var k := 0
	var si := 0
	var mine := func():
		var l := g.units.filter(func(u): return u.kind == "army" and u.owner == Game.ME)
		return l[-1]
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
				"give":
					g.stock.gold += A.gold
					g.stock.food += A.food
				"foetech":
					g.nations[foe].tech.gov.done.append(A.id)
				"tech":
					g.grant_tech(A.id)
				"declare":
					g.declare_war(Game.ME, int(A.o))
				"army":
					var tr := {}
					for tk in A.troops:
						tr[tk] = int(A.troops[tk])
					g.new_army(int(A.p), tr)
					if A.has("mana"):
						mine.call().mana = float(A.mana)
				"mana":
					mine.call().mana = float(A.n)
				"order":
					g.order(mine.call(), int(A.p))
				"shock":
					g.start_spell2(mine.call(), "shock", int(A.p))
				"quake":
					g.start_spell2(mine.call(), "quake")
		g.update(1.0 + i * 0.1)
		if i % 10 == 0:
			var want: Dictionary = fx.snaps[si]
			si += 1
			var got := snap(g, foe, fc)
			for key in got:
				if not TestDecor._close(want[key], got[key]):
					errs.append("t=%s %s: got %s, want %s" % [want.t, key, JSON.stringify(got[key]).left(700), JSON.stringify(want[key]).left(700)])
			if not errs.is_empty():
				return errs
	return errs
