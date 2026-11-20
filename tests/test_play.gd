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
		if not f.ends_with(".json"):
			continue
		var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		if not maps.has(fx.seed):
			maps[fx.seed] = RealmGen.scale_world(RealmGen.generate_practice(fx.seed))
		for m in play(fx, maps[fx.seed].duplicate(true)).slice(0, 6):
			errs.append("%s/%s: %s" % [fx.seed, fx.scenario, m])
	return errs


static func play(fx: Dictionary, map: Dictionary) -> Array:
	var g := Game.new_practice(fx.seed, fx.leader, map)
	var errs := []
	var ruins := []
	for p in g.finds:
		if g.finds[p].id == "ruins":
			ruins.append(p)
	if not TestEconomy.eq(fx.plan.ruins, ruins):
		errs.append("ruins at %s, want %s" % [ruins, fx.plan.ruins])
	g.finds.clear()
	var E0 := g.explored.duplicate()
	var q1: int = g.open_nbr[g.capital][0].q
	var q2 := -1
	for n in g.open_nbr[q1]:
		if n.q != g.capital and not E0.has(n.q):
			q2 = n.q
			break
	if not TestEconomy.eq(fx.plan, {"cap": g.capital, "q1": q1, "q2": q2, "ruins": fx.plan.ruins}):
		return errs + ["plan %s, want %s" % [[g.capital, q1, q2], fx.plan]]
	g.paused = false
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
				"order": g.order(u, int(A.p))
				"build": g.order_build(u, int(A.p), A.type)
				"upgrade": g.start_upgrade(int(A.p))
				"give":
					for r in Game.RES:
						g.stock[r] += int(A[r])
		g.update(1.0 + i * 0.1)
		if i % 10 == 0:
			var e := compare(snaps[si], snapshot(g))
			si += 1
			if not e.is_empty():
				return errs + ["t=%.1f: %s" % [g.t, ", ".join(e)]]
	return errs


static func unit(g: Game, which: String):
	for u in g.units:
		if (which == "wf" and u.kind == g.WAYFINDER) or (which == "mason" and u.kind == Game.MASON) or (which == "army" and u.kind == "army"):
			return u
	return null


static func sorted_keys(d: Dictionary) -> Array:
	var a := d.keys()
	a.sort()
	return a


static func snapshot(g: Game) -> Dictionary:
	var us := []
	for u in g.units:
		us.append({"kind": u.kind, "prov": u.prov, "x": u.x, "y": u.y, "moving": u.moving, "slot": u.slot, "scouting": u.scouting,
			"survey": u.survey != null, "build": u.build.type if u.build != null else null, "pending": u.pending.type if u.pending != null else null,
			"queue": u.surveyQueue.size()})
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
	return {"t": g.t, "stock": g.stock, "income": g.income, "units": us, "explored": sorted_keys(g.explored), "visible": sorted_keys(g.visible),
		"surveyed": sorted_keys(g.surveyed), "wf": sorted_keys(g.wf), "buildings": bl, "extras": ex, "upgrades": g.upgrades.keys(), "techs": techs, "finds": fd}


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
