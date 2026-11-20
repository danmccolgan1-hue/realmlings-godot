extends RefCounted
class_name TestPlay
## Orders, walking, exploring, surveys, building, upgrades and fog must match the web game. Fixtures:
## tests/fixtures/play, written by tools/gen_play_fixtures.py (scripted Practice games, a snapshot every second).

const DIR := "res://tests/fixtures/play/"


func run() -> Array:
	var errs := []
	var maps := {}
	var files := DirAccess.get_files_at(DIR)
	if files.is_empty():
		return ["no fixtures in " + DIR]
	for f in files:
		if not f.ends_with(".json") or (OS.get_environment("PLAY_ONLY") != "" and not OS.get_environment("PLAY_ONLY") in f):
			continue
		var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		if not maps.has(fx.seed):
			maps[fx.seed] = RealmGen.scale_world(RealmGen.generate_practice(fx.seed))
		if OS.get_environment("PLAY_ONLY") != "":
			printerr("ran ", f)
		for m in play(fx, maps[fx.seed].duplicate(true)).slice(0, 6):
			errs.append("%s/%s: %s" % [fx.seed, fx.scenario, m])
	return errs


## after_frame (optional): func(g, i) -> Game, called after every frame; it may hand back another game to go on with
## (tests/test_save.gd swaps in a saved and loaded copy).
static func play(fx: Dictionary, map: Dictionary, after_frame := Callable()) -> Array:
	var g := Game.new_practice(fx.seed, fx.leader, map)
	var errs := []
	var ruins := []
	for p in g.finds:
		if g.finds[p].id == "ruins":
			ruins.append(p)
	if not TestEconomy.eq(fx.plan.ruins, ruins):
		errs.append("ruins at %s, want %s" % [ruins, fx.plan.ruins])
	g.finds.clear()
	if fx.plan.has("travelers"):
		var tv := g.travelers.map(func(B): return [B.prov, B.n, B.x, B.y, B.wait])
		if not TestEconomy.eq(fx.plan.travelers, tv):
			errs.append("travelers %s, want %s" % [tv, fx.plan.travelers])
		var sp := []
		for p in sorted_keys(g.setpieces):
			sp.append([p, g.setpieces[p]])
		if not TestEconomy.eq(fx.plan.setpieces, sp):
			errs.append("set pieces %s, want %s" % [sp, fx.plan.setpieces])
	g.travelers.clear()   # as in the fixture: they would stop the game to ask
	g.units = g.units.filter(func(u): return u.owner == Game.ME)   # as in the fixture: no Bandit Gangs or monsters
	if str(fx.scenario).begins_with("battle"):
		g.battle_rand = func(): return 0.5   # as in the fixture: Math.random pinned to 0.5
	var E0 := g.explored.duplicate()
	var q1: int = g.open_nbr[g.capital][0].q
	var q2 := -1
	for n in g.open_nbr[q1]:
		if n.q != g.capital and not E0.has(n.q):
			q2 = n.q
			break
	if not TestEconomy.eq([fx.plan.cap, fx.plan.q1, fx.plan.q2], [g.capital, q1, q2]):
		return errs + ["plan %s, want %s" % [[g.capital, q1, q2], fx.plan]]
	g.paused = false
	if fx.scenario == "develop":
		g.dev_rand = func(): return 0.99   # as in the fixture: no lucky finds
	var acts: Array = fx.actions
	var k := 0
	var snaps: Array = fx.snaps
	var si := 0
	for i in int(fx.frames):
		while k < acts.size() and g.t >= acts[k].t:
			var A: Dictionary = acts[k]
			k += 1
			var u = unit(g, A.get("u", ""))
			match A.a:
				"survey": g.queue_survey(u, int(A.p))
				"order":
					if int(A.p) >= 0:
						g.order(u, int(A.p))
				"build": g.order_build(u, int(A.p), A.type)
				"upgrade": g.start_upgrade(int(A.p))
				"give":
					for r in Game.RES:
						g.stock[r] += int(A[r])
				"train": g.train(A.src, int(A.p), A.kind)
				"pick":
					if A.id != null:
						if not g.tech[A.tree].opts.has(A.id):
							g.tech[A.tree].opts.append(A.id)
						g.pick_tech(A.id)
				"points": g.add_research(A.tree, int(A.n))
				"grant": g.grant_tech(A.id)
				"spawn":
					var gang := g.spawn_bandit(int(A.p))
					gang.troops = {}
					for tk in A.troops:
						gang.troops[tk] = int(A.troops[tk])
				"retreat":
					for a in g.units:
						if a.kind == "army" and a.owner == Game.ME and a.get("battle") != null:
							g.retreat(a)
							break
				"mana": unit(g, "army").mana = float(A.n)
				"cast": g.cast_spell(unit(g, "army"), A.k)
				"aim":
					if int(A.p) >= 0:
						g.cast_spell(unit(g, "army"), A.k, int(A.p))
				"path":
					if int(A.p) >= 0:
						g.start_path(unit(g, "army"), int(A.p), A.kind)
				"link":
					if int(A.p) >= 0:
						g.start_link(u, int(A.p), A.type)
				"develop": g.start_develop(int(A.p))
				"design": g.add_design(A.spec)
				"tord":
					var mix := {}
					for mk in A.mix:
						mix[mk] = int(A.mix[mk])
					g.purchase_order(mix, g.capital if str(A.p) == "cap" else int(A.p))
				"retrofit": g.retrofit_armies([unit(g, "army")], A.to)
				"wounds": unit(g, "army").wounds = float(A.n)
				"split": g.split_army(unit(g, "army"))
				"combine":
					var a0 = unit(g, "army")
					g.combine_armies(g.units.filter(func(v): return v.kind == "army" and v.owner == Game.ME and v.prov == a0.prov))
				"destroy":
					for e in g.extras_in(int(A.p)):
						if e.type == A.type:
							g.destroy_extra(int(A.p), e.slot)
							break
				"xup":
					for e in g.extras_in(int(A.p)):
						if e.type == A.type:
							g.start_xup(int(A.p), e.slot)
							break
		g.update(1.0 + i * 0.1)
		if after_frame.is_valid():
			g = after_frame.call(g, i)
		if i % 10 == 0:
			var e := compare(snaps[si], snapshot(g))
			si += 1
			if not e.is_empty():
				return errs + ["t=%.1f: %s" % [g.t, ", ".join(e)]]
	return errs


static func unit(g: Game, which: String):
	for u in g.units:
		if (which == "wf" and u.kind == g.WAYFINDER) or (which == "mason" and u.kind == Game.MASON) or (which == "army" and u.kind == "army" and u.owner == Game.ME):
			return u
	return null


static func sorted_keys(d: Dictionary) -> Array:
	var a := d.keys()
	a.sort()
	return a


static func snapshot(g: Game) -> Dictionary:
	var us := []
	for u in g.units:
		us.append({"owner": u.owner, "kind": u.kind, "prov": u.prov, "x": u.x, "y": u.y, "moving": u.moving, "slot": u.slot, "scouting": u.scouting,
			"survey": u.survey != null, "build": u.build.type if u.build != null else null, "pending": u.pending.type if u.pending != null else null,
			"queue": u.surveyQueue.size(), "troops": u.get("troops")})
	var bl := []
	for p in sorted_keys(g.buildings):
		bl.append([p, g.buildings[p].stage])
	var ex := []
	for p in sorted_keys(g.extras):
		var l := []
		for e in g.extras[p]:
			l.append([e.type, e.slot])
		ex.append([p, l])
	var fd := []
	for p in g.finds:
		fd.append([p, g.finds[p].id, g.finds[p].done])
	var techs := 0
	for tr in g.tech:
		techs += g.tech[tr].done.size()
	var qs := []
	for key in sorted_keys(g.queues):
		var l := []
		for q in g.queues[key]:
			l.append([q.kind, q.t0])
		qs.append([key, l])
	var tch := {}
	for tr in Game.TREE_KEYS:
		var st: Dictionary = g.tech[tr]
		tch[tr] = {"cur": st.cur, "prog": st.prog, "bank": st.bank, "done": st.done, "tier": st.tier}
	var lv := []
	for p in sorted_keys(g.extras):
		lv.append([p, g.extras[p].map(func(e): return e.get("level", 1))])
	var dv := []
	for p in g.devel:
		var r: Dictionary = g.devel[p]
		dv.append([p, r.lv, snapped(r.job.done, 0.001) if r.job != null else null])
	var ys := []
	for y in g.yields:
		ys.append([y.gold, y.wood, y.food, y.deposit])
	var rd := g.roads.keys()
	rd.sort()
	var cds := []
	for k in sorted_keys(g.cd):
		cds.append([k, g.cd[k]])
	var pth := []
	for k in sorted_keys(g.paths):
		pth.append([k, g.paths[k]])
	var bt := []
	for b in g.battles:
		var lost := {}
		for o in b.lost:
			lost[str(o)] = b.lost[o]   # JSON object keys are strings
		bt.append([b.prov, b.defender, lost])
	var wd := []
	for u in g.units:
		wd.append(snapped(u.wounds, 0.000001) if u.has("wounds") else null)
	return {"t": g.t, "battles": bt, "wounds": wd, "mana": g.units.map(func(u): return u.get("mana")), "casts": g.units.map(func(u): return u.cast.spell if u.get("cast") != null else null),
		"cd": cds, "paths": pth, "eyes": g.eyes.map(func(r): return [r.a, r.b, r.until]), "haunts": g.haunts.map(func(h): return [h.prov, h.until]),
		"reveals": g.reveals.size(), "harvest": g.harvest_by != null, "queues": qs, "roads": rd, "walls": sorted_keys(g.walls), "devel": dv, "yields": ys, "tech": tch, "rep": g.rep, "xup": g.xup.keys(), "levels": lv, "stock": g.stock, "income": g.income, "units": us, "explored": sorted_keys(g.explored), "visible": sorted_keys(g.visible),
		"surveyed": sorted_keys(g.surveyed), "wf": sorted_keys(g.wf), "buildings": bl, "extras": ex, "upgrades": g.upgrades.keys(), "techs": techs, "finds": fd,
		"orders": g.train_orders.map(func(O): return [O.id, O.done, O.total, O.rally.prov]),
		"retro": g.units.map(func(u): return [u.retro.kind, u.retro.t0, u.retro.dur] if u.get("retro") != null else (["want", u.retroWant.to, u.retroWant.prov] if u.get("retroWant") != null else null)),
		"rest": g.units.map(func(u): return [u.rest.t0, u.rest.dur] if u.get("rest") != null else null),
		"designs": g.designs.map(func(d): return [d.id, d.name, g.DSTATS[d.id].atk, g.DSTATS[d.id].hp, snapped(g.DSTATS[d.id].red, 1e-9), g.DSTATS[d.id].speed])}


static func compare(want: Dictionary, got: Dictionary) -> Array:
	var out := []
	for k in want:
		if k == "units":
			if want.units.size() != got.units.size():
				out.append("%d units, want %d" % [got.units.size(), want.units.size()])
				continue
			for i in want.units.size():
				for f in want.units[i]:
					if not TestEconomy.eq(want.units[i][f], got.units[i][f]):
						out.append("unit %d (%s) %s: got %s, want %s" % [i, want.units[i].kind, f, got.units[i][f], want.units[i][f]])
		elif not TestEconomy.eq(want[k], got[k]):
			out.append("%s: got %s, want %s" % [k, JSON.stringify(got[k]).left(200), JSON.stringify(want[k]).left(200)])
	return out
