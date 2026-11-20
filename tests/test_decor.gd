class_name TestDecor
extends RefCounted
## The map's decoration lands exactly where the web game puts it (tests/fixtures/decor, tools/gen_decor_fixtures.py).

const DIR := "res://tests/fixtures/decor/"


func run() -> Array:
	var errs := []
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".json"):
			continue
		var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		var w := RealmGen.scale_world(RealmGen.generate_practice(fx.seed))
		var D := MapDecor.build(w, WorldPrep.prep(w))
		var r6 := func(v: float) -> float: return snappedf(v, 0.000001)
		var got := {
			"items": D.items.map(func(l): return l.map(func(it): return [r6.call(it.x), r6.call(it.y), it.s])),
			"sway": D.sway.map(func(it): return [r6.call(it.x), r6.call(it.y), it.s, r6.call(it.ph)]),
			"still": D.still.map(func(it): return [r6.call(it.x), r6.call(it.y), it.s]),
			"lakeMarks": D.lake_marks.map(func(m): return [r6.call(m.x), r6.call(m.y)]),
			"waves": D.waves.map(func(v): return [r6.call(v.x), r6.call(v.y), r6.call(v.ph), r6.call(v.s)]),
			"clouds": D.clouds.map(func(c): return [r6.call(c.x), r6.call(c.y), r6.call(c.v), r6.call(c.s)]),
			"bounds": D.bounds}
		for k in got:
			if not _close(fx[k], got[k]):
				errs.append("%s %s: got %s, want %s" % [fx.seed, k, JSON.stringify(got[k]).left(300), JSON.stringify(fx[k]).left(300)])
	return errs


static func _close(a, b) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _close(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _close(a[k], b[k]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= 2e-6 * maxf(1.0, absf(float(a)))
	return a == b
