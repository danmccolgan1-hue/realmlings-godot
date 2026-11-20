extends RefCounted
## The Practice island must match the web generator for the same seed. Fixtures come from tools/gen_fixtures.js.

const DIR := "res://tests/fixtures/"


func run() -> Array:
	var errs := []
	var files := DirAccess.get_files_at(DIR)
	if files.is_empty():
		return ["no fixtures in " + DIR]
	var total_ms := 0
	for f in files:
		if not f.ends_with(".json"):
			continue
		var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		var t0 := Time.get_ticks_msec()
		var got := RealmGen.generate_practice(want.seed)
		total_ms += Time.get_ticks_msec() - t0
		var e := compare(want, got)
		for m in e.slice(0, 5):
			errs.append("%s: %s" % [want.seed, m])
	print("    generated %d islands in %d ms" % [files.size(), total_ms])
	return errs


static func num_eq(a, b, tol := 0.0) -> bool:
	return absf(float(a) - float(b)) <= tol


static func compare(want: Dictionary, got: Dictionary) -> Array:
	var errs := []
	if got.is_empty():
		return ["generation failed"]
	if int(want.attempts) != int(got.attempts):
		errs.append("attempts %s != %s" % [got.attempts, want.attempts])
	if not (num_eq(want.center[0], got.center[0], 1e-6) and num_eq(want.center[1], got.center[1], 1e-6)):
		errs.append("center %s != %s" % [got.center, want.center])
	var wp: Array = want.provinces
	var gp: Array = got.provinces
	if wp.size() != gp.size():
		return errs + ["province count %d != %d" % [gp.size(), wp.size()]]
	for i in wp.size():
		var a: Dictionary = wp[i]
		var b: Dictionary = gp[i]
		for k in ["site", "verts", "nbr", "edges", "coast"]:
			if not _arr_eq(a[k], b[k]):
				errs.append("province %d %s: %s != %s" % [i, k, b[k], a[k]])
		if a.terrain != b.terrain:
			errs.append("province %d terrain %s != %s" % [i, b.terrain, a.terrain])
	var we: Array = want.edges
	var ge: Array = got.edges
	if we.size() != ge.size():
		errs.append("edge count %d != %d" % [ge.size(), we.size()])
	else:
		for i in we.size():
			var a: Dictionary = we[i]
			var b: Dictionary = ge[i]
			if int(a.a) != b.a or int(a.b) != b.b or not _arr_eq(a.v, b.v) or a.open != b.open or a.style != b.style:
				errs.append("edge %d: %s != %s" % [i, b, a])
	var wj: Array = want.junctions
	var gj: Array = got.junctions
	if wj.size() != gj.size():
		errs.append("junction count %d != %d" % [gj.size(), wj.size()])
	else:
		for i in wj.size():
			if int(wj[i].v) != gj[i].v or wj[i].kind != gj[i].kind:
				errs.append("junction %d: %s != %s" % [i, gj[i], wj[i]])
	for pair in want.vertices:
		var vi := int(pair[0])
		if vi >= got.vertices.size():
			errs.append("vertex %d missing" % vi)
			continue
		var g: Array = got.vertices[vi]
		if not (num_eq(pair[1][0], g[0]) and num_eq(pair[1][1], g[1])):
			errs.append("vertex %d: %s != %s" % [vi, g, pair[1]])
	return errs


static func _arr_eq(a, b) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _arr_eq(a[i], b[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return float(a) == float(b)
	return a == b
