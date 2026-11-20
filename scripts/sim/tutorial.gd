class_name Tutorial
extends RefCounted
## The Basic Tutorial (web: tutorial.js): its own five-province island, the Swamp Bandits, and 20 steps of
## lines with objectives. The text comes from the web game's data (TUT_TRIGGERS, TUT_FINAL); each step's condition,
## start and objective test are written out here by id.
## Differences: no leader is assigned (the web game picks one and keeps only its buildings), no voice lines yet.

const TP := {"capital": 0, "forest": 1, "swamp": 2, "desert": 3, "bandits": 4}

var g: Game
var trig: Array              # TUT_TRIGGERS
var next := 0
var cur = null               # {id, lines, k, glow}
var replay = null
var finished := []
var objs := []               # [{key, text, trig}]
var done := []
var allow := []
var ended := false
var final_shown := false
var bandits_placed := false
## what the player has selected (the interface reports it): "capital", "wayfinder"
var selected := {}


# web: tutorial.js tutorialWorld(): the island from the tutorial's diagram
static func tutorial_world() -> Dictionary:
	var K := 3.2
	var V0 := [[200, 125], [222, 205], [140, 100], [138, 45], [185, 12], [238, 40], [245, 100], [298, 120], [305, 185],
		[345, 225], [320, 282], [245, 285], [205, 330], [148, 300], [140, 222], [100, 165]]
	var V := []
	for v in V0:
		V.append([v[0] * K, v[1] * K])
	var polys := [{"terrain": "grassland", "verts": [1, 8, 9, 10, 11]}, {"terrain": "forest", "verts": [14, 1, 11, 12, 13]},
		{"terrain": "swamp", "verts": [15, 2, 0, 1, 14]}, {"terrain": "desert", "verts": [2, 3, 4, 5, 6, 0]},
		{"terrain": "swamp", "verts": [0, 6, 7, 8, 1]}]
	var E := [{"a": 0, "b": 1, "v": [11, 1], "open": true, "style": null}, {"a": 1, "b": 2, "v": [1, 14], "open": true, "style": null},
		{"a": 2, "b": 3, "v": [2, 0], "open": true, "style": null}, {"a": 3, "b": 4, "v": [6, 0], "open": true, "style": null},
		{"a": 2, "b": 4, "v": [0, 1], "open": false, "style": "ruins"}, {"a": 4, "b": 0, "v": [8, 1], "open": false, "style": "mountains"}]
	for i in E.size():
		E[i].id = i
	var ek := func(a: int, b: int) -> String: return "%d_%d" % [mini(a, b), maxi(a, b)]
	var inner := {}
	for e in E:
		inner[ek.call(e.v[0], e.v[1])] = true
	var provinces := []
	for i in polys.size():
		var P: Dictionary = polys[i]
		var coast := []
		for k in P.verts.size():
			var a: int = P.verts[k]
			var b: int = P.verts[(k + 1) % P.verts.size()]
			if not inner.has(ek.call(a, b)):
				coast.append([a, b, 0])
		var nbr := []
		var pe := []
		for e in E:
			if e.a == i or e.b == i:
				nbr.append(e.b if e.a == i else e.a)
				pe.append(e.id)
		var sx := 0.0
		var sy := 0.0
		for v in P.verts:
			sx += V[v][0]
			sy += V[v][1]
		provinces.append({"id": i, "site": [sx / P.verts.size(), sy / P.verts.size()], "verts": P.verts.duplicate(), "terrain": P.terrain,
			"adj": nbr.duplicate(), "nbr": nbr, "edges": pe, "coast": coast})
	var xs := V.map(func(v): return v[0])
	var ys := V.map(func(v): return v[1])
	return {"W": xs.max() + 400, "H": ys.max() + 400, "center": [(xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2],
		"provinces": provinces, "vertices": V, "edges": E, "rivers": [], "junctions": [{"v": 1, "kind": "mountains"}],
		"features": {"peninsulas": [], "coves": []}, "lakes": [], "lakesInland": true, "touchesEdgeOfWorld": false,
		"seed": "realmlings-tutorial", "tutorial": true, "attempts": 1, "report": [],
		"shoreTrees": [[1, 11, 12], [1, 12, 13], [2, 14, 15], [4, 6, 7], [4, 7, 8]]}


## A new tutorial game. web: tutorial.js startTutorial()
static func start() -> Game:
	var g := Game.new()
	g.world = RealmGen.scale_world(tutorial_world())
	g.G = WorldPrep.prep(g.world)
	_shore(g)
	var T := Tutorial.new()
	T.g = g
	T.trig = GameData.c("TUT_TRIGGERS")
	g.tutorial = T
	g.setup_game()
	for p in g.world.shoreTrees:   # web: the rollYields wrapper: shore trees count as tree borders
		g.tree_border[p[0]] += 1
	g.units = g.units.filter(func(u): return not (u.owner == Game.ME and u.kind == "army"))   # no starting army
	g.leader = ""
	var gang := g.spawn_bandit(TP.bandits)
	gang.name = "Swamp Bandits"
	T.bandits_placed = true
	for k in Game.RES:
		g.stock[k] += 500
	for p in g.world.provinces.size():
		g.treasure_rolled[p] = true
	g.compute_income()
	g.compute_fog()
	g.started = true
	g.last = 0.0
	g.next_tick = 0.0
	return g


# web: tutorial.js tutorialShore() (rules half): the open ground keeps clear of the shore trees
static func _shore(g: Game) -> void:
	var w: Dictionary = g.world
	var ek := func(a: int, b: int) -> String: return "%d_%d" % [mini(a, b), maxi(a, b)]
	var trees := {}
	for s in w.shoreTrees:
		trees[ek.call(s[1], s[2])] = true
	var edge_by := {}
	for e in w.edges:
		edge_by[ek.call(e.v[0], e.v[1])] = e
	for i in w.provinces.size():
		if not w.shoreTrees.any(func(s): return s[0] == i):
			continue
		var P: Dictionary = g.G.provs[i]
		var vs: Array = w.provinces[i].verts
		var d := []
		for k in vs.size():
			var key: String = ek.call(vs[k], vs[(k + 1) % vs.size()])
			var e = edge_by.get(key)
			d.append(WorldPrep.BAND_IN + 40 if trees.has(key) else (6.0 if e.open else WorldPrep.BAND_IN) if e != null else 18.0)
		P.inner = WorldPrep.inset_poly(P.pts, d, P.c)
		P.ic = WorldPrep.centroid(P.inner)


func trig_by_id(id: String) -> Dictionary:
	for x in trig:
		if x.id == id:
			return x
	return {}


func is_done(key: String) -> bool:
	return done.has(key)


func soldiers() -> int:
	var n := 0
	for a in g.units:
		if a.owner == Game.ME and a.kind == "army":
			n += g.troop_count(a) - a.troops.get(GameData.c("MAGE"), 0)
	return n


func bandits() -> Array:
	return g.units.filter(func(v): return v.get("bandit", false) and g.troop_count(v) > 0)


# each step's condition (web: TUT_TRIGGERS[i].cond)
func cond(id: String) -> bool:
	match id:
		"2": return is_done("capital")
		"3": return is_done("research")
		"4": return is_done("wayfinder")
		"5": return is_done("survey")
		"6": return is_done("explore")
		"9": return is_done("outpost")
		"14": return not g.upgrades.is_empty() or is_done("fort")
		"15": return g.wf.has(TP.desert) or g.explored.has(TP.desert)
		"16": return bandits().any(func(v): return v.get("seen", false))
		"17": return is_done("barracks")
	return true


# each objective's test (web: TUT_TRIGGERS[i].obj.done)
func obj_done(key: String) -> bool:
	match key:
		"capital": return selected.get("capital", false)
		"research":
			for k in Game.TREE_KEYS:
				if g.tech[k].cur != null or not g.tech[k].done.is_empty():
					return true
			return false
		"wayfinder": return selected.get("wayfinder", false)
		"survey": return g.surveyed.has(TP.forest)
		"explore": return g.wf.has(TP.swamp) or g.explored.has(TP.swamp)
		"outpost": return g.owned(TP.forest)
		"fort": return g.buildings.values().any(func(b): return b.owner == Game.ME and b.stage == 1)
		"barracks":
			for p in g.extras:
				if g.owned(p) and g.extras[p].any(func(e): return e.type == "barracks"):
					return true
			return false
		"swords": return soldiers() >= 3
	return false


# each step's start (web: TUT_TRIGGERS[i].start)
func on_start(id: String) -> void:
	match id:
		"10":
			allow.append("lumber")
		"13":
			top_up(GameData.c("FORT_UPGRADE").cost, "the Fort")
		"16":
			allow.append("barracks")
			top_up(g.BUILD_DEFS.barracks.cost, "a Barracks")
		"17":
			var c: Dictionary = g.unit_defs[g.footman_of()].cost
			var need := {}
			for k in c:
				need[k] = c[k] * 3
			top_up(need, "three Footmen")


func top_up(cost: Dictionary, why: String) -> void:
	var add := {}
	for k in cost:
		if g.stock[k] < cost[k]:
			add[k] = cost[k] - g.stock[k]
			g.stock[k] = cost[k]
	if not add.is_empty():
		g.toast("Tutorial: you’ve been given %s for %s." % [Game.cost_text(add), why])


## What the Mason may build in the tutorial (web: the buildCheck wrapper)
func build_why(type: String):
	if type != "outpost" and not allow.has(type):
		return "Not available in the tutorial yet"
	return null


func play(x: Dictionary) -> void:
	cur = {"id": x.id, "lines": x.get("lines", []).duplicate(), "k": 0, "glow": x.get("glow", [])}
	on_start(x.id)
	if x.has("obj"):
		objs.append({"key": x.obj.key, "text": x.obj.text, "trig": x.id})
	if cur.lines.is_empty():
		end_step()


func end_step() -> void:
	if cur == null:
		return
	finished.append(cur.id)
	cur = null


## The lines on screen now: {lines, k} or null.
func shown():
	return replay if replay != null else cur


func line_text(l) -> String:
	return l if l is String else str(l.get("t", ""))


func next_line() -> void:
	var L = shown()
	if L == null:
		return
	L.k += 1
	if L.k < L.lines.size():
		return
	if L == replay:
		replay = null
	else:
		end_step()


func back_line() -> void:
	var L = shown()
	if L != null and L.k > 0:
		L.k -= 1


## Show an objective's lines again.
func show_again(key: String) -> void:
	var o = null
	for x in objs:
		if x.key == key:
			o = x
	if o == null:
		return
	var i := -1
	for j in trig.size():
		if trig[j].id == o.trig:
			i = j
	while i > 0 and trig[i].get("lines", []).is_empty():
		i -= 1
	if i < 0 or trig[i].get("lines", []).is_empty():
		return
	replay = {"id": trig[i].id, "lines": trig[i].lines.duplicate(), "k": 0}


# web: tutorial.js stepTutorial(), every frame
func step() -> void:
	for x in trig:
		if x.has("obj") and not done.has(x.obj.key) and objs.any(func(o): return o.key == x.obj.key) and obj_done(x.obj.key):
			done.append(x.obj.key)
	if not ended and bandits_placed and bandits().is_empty():
		ended = true
		replay = null
		cur = null
		for o in objs:
			if not done.has(o.key):
				done.append(o.key)
		play(GameData.c("TUT_FINAL"))
		next = trig.size()
		return
	if cur != null or replay != null:
		return
	if ended:
		final_shown = true
		return
	if next < trig.size():
		var nx: Dictionary = trig[next]
		if cond(nx.id):
			next += 1
			play(nx)
