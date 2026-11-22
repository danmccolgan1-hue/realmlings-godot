class_name TestAi
extends RefCounted
## Computer nations playing on their own on a full-size map: expanding, building, researching, training, diplomacy.
## Fixtures: tools/gen_ai_fixtures.py (Math.random pinned to 0.5; a snapshot of every nation every 5 s).

const DIR := "res://tests/fixtures/ai/"


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


static func snap(g: Game) -> Dictionary:
	var ns := []
	for id in g.nations:
		var N: Dictionary = g.nations[id]
		var tech := []
		for tr in Game.TREE_KEYS:
			var st: Dictionary = N.tech[tr]
			tech.append([st.cur if st.cur != null else "", ",".join(st.done), int(JS.round_js(st.prog)), ",".join(st.opts)])
		var ups: Array = N.ups.keys()
		ups.sort()
		ns.append({"id": N.id, "alive": N.alive, "stock": N.stock.duplicate(), "income": N.income.duplicate(), "stage": Ai.stage_text(g, N),
			"stance": N.get("stance", "normal"), "rival": N.rival if N.get("rival") != null else 0, "school": N.school if N.school != null else "",
			"exhaust": N.exhaust, "tech": tech, "rep": N.rep.duplicate(), "queue": N.queue.map(func(q): return [q.kind, q.prov]), "ups": ups,
			"surveyed": N.surveyed.size()})
	var bl := []
	for p in TestPlay.sorted_keys(g.buildings):
		bl.append([p, g.buildings[p].stage, g.buildings[p].owner])
	var ex := []
	for p in TestPlay.sorted_keys(g.extras):
		var l: Array = g.extras[p]
		if l.is_empty() or g.nation_of(p) == Game.HOST:
			continue
		ex.append([p, ",".join(l.map(func(e): return e.type + (str(e.level) if e.get("level", 1) > 1 else "") + ((":" + e.crop) if e.get("crop", "staple") != "staple" else "")))])
	var us := []
	for u in g.units:
		if u.owner == Game.HOST or not g.is_nation(u.owner):
			continue
		var what = u.troops.duplicate() if u.kind == "army" else (("%s@%d" % [u.build.type, u.build.prov]) if u.build != null else ("job:%s@%d" % [u.aiJob.type, u.aiJob.prov]) if u.get("aiJob") != null else "")
		us.append([u.id, u.owner, u.kind, u.prov, u.moving, what])
	return {"t": snappedf(g.t, 0.000001), "nations": ns, "buildings": bl, "extras": ex, "units": us,
		"wars": g.wars.map(func(w): return [w.a, w.b]), "allies": g.allies.map(func(A): return [A.a, A.b])}


## the differing entries of two lists (or the whole values)
static func diff(got, want) -> String:
	if not (got is Array and want is Array):
		return "got %s, want %s" % [JSON.stringify(got).left(700), JSON.stringify(want).left(700)]
	var out := []
	var wi := {}
	for w in want:
		wi[JSON.stringify(w[0]).replace(".0", "")] = w
	var gi := {}
	for x in got:
		gi[JSON.stringify(x[0]).replace(".0", "")] = x
	for k in gi:
		if not wi.has(k):
			out.append("extra " + JSON.stringify(gi[k]))
		elif not TestDecor._close(wi[k], gi[k]):
			out.append("got " + JSON.stringify(gi[k]) + " want " + JSON.stringify(wi[k]))
	for k in wi:
		if not gi.has(k):
			out.append("missing " + JSON.stringify(wi[k]))
	return "; ".join(out.slice(0, 6)).left(1400)


static func play(fx: Dictionary, frames := -1) -> Array:
	var errs := []
	var g := Game.new_world(fx.seed, fx.leader, fx.slots, "center")
	g.battle_rand = func(): return 0.5
	g.units = g.units.filter(func(u): return not u.get("bandit", false))
	g.travelers.clear()
	g.paused = false
	for o in g.nations:
		g.met[o] = true
	var si := 0
	var n: int = int(fx.frames) if frames < 0 else frames
	for i in n:
		g.update(1.0 + i * 0.1)
		if i % 100 == 0:
			var want: Dictionary = fx.snaps[si]
			si += 1
			var got := snap(g)
			for key in got:
				if key == "nations":
					for j in got.nations.size():
						for k2 in got.nations[j]:
							if not TestDecor._close(want.nations[j][k2], got.nations[j][k2]):
								errs.append("t=%s nation %d %s: got %s, want %s" % [want.t, got.nations[j].id, k2, JSON.stringify(got.nations[j][k2]).left(500), JSON.stringify(want.nations[j][k2]).left(500)])
				elif not TestDecor._close(want[key], got[key]):
					errs.append("t=%s %s: %s" % [want.t, key, diff(got[key], want[key])])
			if not errs.is_empty():
				return errs
	return errs
