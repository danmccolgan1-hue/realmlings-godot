extends RefCounted
## Game setup, leader starts and the economy must match the web game. Fixtures: tests/fixtures/econ, written by
## tools/gen_econ_fixtures.py (a Practice game per seed and Realmling leader, 200 s of game time in 0.1 s frames).

const DIR := "res://tests/fixtures/econ/"


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
		var g := Game.new_practice(fx.seed, fx.leader, maps[fx.seed].duplicate(true))
		var e := compare_start(fx.start, g)
		if e.is_empty():
			e = compare_run(fx, g)
		for m in e.slice(0, 6):
			errs.append("%s/%s: %s" % [fx.seed, fx.leader, m])
	return errs


static func eq(a, b) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not eq(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not eq(a[k], b[k]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		# positions may differ in the last bit (JSON round trip, summation order); counts and stock are whole numbers
		return absf(float(a) - float(b)) <= 1e-9 * maxf(1.0, absf(float(a)))
	return a == b


static func compare_start(w: Dictionary, g: Game) -> Array:
	var errs := []
	var chk := func(name: String, want, got) -> void:
		if not eq(want, got):
			errs.append("%s: got %s, want %s" % [name, JSON.stringify(got).left(300), JSON.stringify(want).left(300)])
	chk.call("leader", w.leader, g.leader)
	var terr := []
	var ic := []
	var coastal := []
	var lakeside := []
	for p in g.G.provs:
		terr.append(p.terrain)
		ic.append(p.ic)
		coastal.append(p.coastal)
		lakeside.append(p.lakeside)
	chk.call("terrain", w.terrain, terr)
	chk.call("ic", w.ic, ic)
	chk.call("coastal", w.coastal, coastal)
	chk.call("lakeside", w.lakeside, lakeside)
	chk.call("bounds", w.bounds, g.G.bounds)
	chk.call("capital", w.capital, g.capital)
	chk.call("yields", w.yields, g.yields)
	if w.leader == "weylyn":   # its woodlines are picked with Math.random: only the capital's count is certain
		chk.call("capTrees", w.capTrees, g.tree_border[g.capital])
	else:
		chk.call("treeBorder", w.treeBorder, g.tree_border)
	# unit ids are left out: the web game's Bandit Gangs (left out here) take ids before the leader's army is made
	var want_units := []
	for u in w.units:
		var c: Dictionary = u.duplicate()
		c.erase("id")
		want_units.append(c)
	var units := []
	for u in g.units:
		units.append({"owner": u.owner, "kind": u.kind, "prov": u.prov, "slot": u.slot, "x": u.x, "y": u.y, "troops": u.get("troops")})
	chk.call("units", want_units, units)
	var ex := []
	for p in g.extras:
		var l := []
		for e in g.extras[p]:
			l.append({"type": e.type, "slot": e.slot, "freeFor": e.get("freeFor")})
		ex.append([p, l])
	chk.call("extras", w.extras, ex)
	var bl := []
	for p in g.buildings:
		bl.append([p, g.buildings[p].stage, g.buildings[p].owner])
	chk.call("buildings", w.buildings, bl)
	chk.call("techDone", w.techDone, {"gov": g.tech.gov.done, "mil": g.tech.mil.done, "mag": g.tech.mag.done})
	chk.call("stock", w.stock, g.stock)
	chk.call("income", w.income, g.income)
	chk.call("gross", w.gross, g.income_parts.gross)
	chk.call("up", w.up, g.income_parts.up)
	chk.call("caps", w.caps, [g.storage_cap("gold"), g.storage_cap("wood"), g.storage_cap("food")])
	return errs


static func compare_run(fx: Dictionary, g: Game) -> Array:
	var got := []
	g.paused = false
	g.on_payday = func(t: float) -> void:
		got.append({"t": t, "stock": g.stock.duplicate(), "income": g.income.duplicate(), "exhaust": g.exhaust, "soldiers": g.soldier_count()})
	for i in int(fx.frames):
		g.update(1.0 + i * 0.1)
	g.on_payday = Callable()
	var errs := []
	if not eq(fx.end_t, g.t):
		errs.append("end time %s, want %s" % [g.t, fx.end_t])
	var want: Array = fx.paydays
	if want.size() != got.size():
		errs.append("%d paydays, want %d" % [got.size(), want.size()])
	for i in mini(want.size(), got.size()):
		if not eq(want[i], got[i]):
			errs.append("payday %d: got %s, want %s" % [i, JSON.stringify(got[i]), JSON.stringify(want[i])])
			break
	return errs
