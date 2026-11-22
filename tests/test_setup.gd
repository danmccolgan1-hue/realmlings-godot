extends RefCounted
## A full-size game is set up exactly as the web game sets it up: your capital, the computer nations (capitals,
## names, colors, leaders, designs), units, buildings, set pieces, ruins, travelers, bosses and yields.
## Fixtures: tools/gen_world_setup_fixtures.py (Math.random pinned to 0.5).

const DIR := "res://tests/fixtures/setup/"


func run() -> Array:
	var errs := []
	Game.test_random = 0.5
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".json"):
			continue
		var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		for n in fx.nations:   # the port gives each race its own flags (Races.EMBLEMS), so emblems no longer follow the web game
			n.erase("emblem")
		var g := Game.new_world(fx.seed, fx.leader, fx.slots, fx.start)
		var got := snapshot(g)
		for k in got:
			if not TestDecor._close(fx[k], got[k]):
				var w = fx[k]
				var gv = got[k]
				if w is Array and gv is Array:
					for i in maxi(w.size(), gv.size()):
						if i >= w.size() or i >= gv.size() or not TestDecor._close(w[i], gv[i]):
							w = w[i] if i < w.size() else "(none)"
							gv = gv[i] if i < gv.size() else "(none)"
							k += "[%d]" % i
							break
				errs.append("%s %s: got %s\n   want %s" % [fx.seed, k, JSON.stringify(gv).left(700), JSON.stringify(w).left(700)])
	Game.test_random = -1.0
	return errs


static func snapshot(g: Game) -> Dictionary:
	var r6 := func(v: float) -> float: return snappedf(v, 0.000001)
	var trees: Array = GameData.c("TREE_KEYS")
	var nats := []
	for id in g.nations:
		var N: Dictionary = g.nations[id]
		var td := {}
		for tr in trees:
			td[tr] = N.tech[tr].done
		nats.append({"id": N.id, "diff": N.diff, "name": N.name, "capital": N.capital, "family": N.family,
			"armorLine": N.armorLine, "wantSchool": N.wantSchool, "leader": N.leader, "design": N.design, "warCheck": r6.call(N.warCheck),
			"think": r6.call(N.think), "stock": N.stock, "techDone": td})
	var pl := {}
	for k in g.players:
		if int(k) == 1 or g.nations.has(int(k)):
			pl[k] = {"name": g.players[k].name, "color": g.players[k].color, "light": g.players[k].light}
	var us := g.units.map(func(u): return {"id": u.id, "owner": u.owner, "kind": u.kind, "prov": u.prov, "slot": u.slot,
		"troops": u.get("troops"), "boss": u.get("boss"), "bandit": u.get("bandit", false), "name": u.name if u.kind == "army" and u.owner != 1 else null})
	var bl := []
	for p in g.buildings:
		bl.append([p, g.buildings[p].stage, g.buildings[p].owner])
	var ex := []
	for p in g.extras:
		ex.append([p, g.extras[p].map(func(e): return [e.type, e.slot, e.get("freeFor", 0)])])
	var sp := []
	for p in TestPlay.sorted_keys(g.setpieces):
		sp.append([p, g.setpieces[p]])
	var fd := []
	for p in g.finds:
		fd.append([p, g.finds[p].id])
	var td := {}
	for tr in trees:
		td[tr] = g.tech[tr].done
	var ds := {}
	for k in g.DSTATS:
		if str(k).begins_with("ai") and str(k).substr(2, 1).is_valid_int():
			var d: Dictionary = g.DSTATS[k]
			ds[k] = [d.atk, d.hp, r6.call(d.red), d.speed]
	return {"capital": g.capital, "nations": nats, "players": pl, "units": us, "buildings": bl, "extras": ex, "setpieces": sp,
		"finds": fd, "travelers": g.travelers.map(func(T): return [T.prov, T.n]), "yields": g.yields.map(func(y): return [y.gold, y.wood, y.food]),
		"stock": g.stock, "techDone": td, "dstats": ds}
