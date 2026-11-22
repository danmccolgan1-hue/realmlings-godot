class_name Recorder
extends RefCounted
## Recording a game (Settings → Record games): the web game's stats log (v102.js recStart / stepRecord / recSnap /
## recMilestones: events, milestones and a line per nation every 30 s) plus, for watching it back, a frame of the map
## every 5 s (who holds each province, its buildings, roads, walls and every nation's armies).
## Reads the game only: it never changes the rules' state or draws on their randomness. Lives in Game.rec (saved with
## the game); main.gd writes it to user://recordings/ as it goes.

const REC_SNAP := 30.0          # web: REC_SNAP
const FRAME_EVERY := 5.0
const MS_PROV := [10, 20, 30, 40]
const MS_POW := [1000, 5000, 10000, 20000]
const DIR := "user://recordings/"


# web: v102.js recOn
static func on(g: Game) -> bool:
	return g.rec.get("on", false) and g.started and not g.nations.is_empty() and g.tutorial == null


# web: v102.js recNations
static func nations_of(g: Game) -> Array:
	var out := g.seat_ids()
	for o in g.nations:
		if g.alive_nation(o):
			out.append(o)
	return out


static func name_of(g: Game, o: int) -> String:
	if o == Game.LOCAL:
		return "You"
	if g.is_human(o):
		return g.player_info(o).name
	var N = g.nations.get(o)
	return "%s (%s)" % [g.player_info(o).name, GameData.c("DIFF_NAME").get(N.diff, "?") if N != null else "?"]


# web: v102.js recStart
static func start(g: Game, why: String) -> void:
	var nats := []
	for o in nations_of(g):
		var N = g.nations.get(o)
		var L = g.leader_of(o)
		nats.append({"id": o, "name": g.player_info(o).name, "label": name_of(g, o), "race": "realm",
			"diff": "player" if g.is_human(o) else N.diff, "color": g.player_info(o).color, "leader": L.full if L != null else "",
			"school": null if g.is_human(o) else N.get("wantSchool")})
	var players := {}
	for o in nations_of(g):
		players[str(o)] = g.player_info(o).duplicate()
	g.rec = {"v": 1, "on": true, "game": "Godot %s (web %s)" % [ProjectSettings.get_setting("application/config/version", "?"), GameData.c("GAME_VERSION")],
		"id": Time.get_datetime_string_from_system().replace(":", "-") + "_" + str(g.world.seed), "made": Time.get_datetime_string_from_system(),
		"began": JS.round_js(g.t), "why": why,
		"header": {"seed": str(g.world.seed), "mode": g.world.get("mode", "normal"), "provinces": g.G.provs.size(), "nations": nats, "players": players},
		"ev": [], "snap": [], "ms": {}, "frames": []}
	g.rec_prev = {}
	g.rec_t = -9.0


static func rt(g: Game) -> int:
	return int(JS.round_js(g.t))


static func ev(g: Game, o: int, e: String, data := {}) -> void:
	var x := {"t": rt(g), "o": o, "e": e}
	x.merge(data)
	g.rec.ev.append(x)


# web: v102.js nationBuildings / nationSettle
static func buildings_of(g: Game, o: int) -> Dictionary:
	var m := {}
	for p in g.buildings:
		if g.buildings[p].owner == o:
			for e in g.extras_in(p):
				m["%d@%d" % [p, e.slot]] = "%s:%d" % [e.type, e.get("level", 1)]
	return m


static func settle_of(g: Game, o: int) -> Dictionary:
	var m := {}
	for p in g.buildings:
		if g.buildings[p].owner == o:
			m[p] = "cc" if g.buildings[p].get("cc") else g.buildings[p].stage
	return m


static func tech_of(g: Game, o: int) -> Dictionary:
	return g.seats[o].tech if g.is_human(o) else g.nations[o].tech


static func word(s) -> String:
	return "conquered capital" if str(s) == "cc" else GameData.c("STAGE_WORD")[int(s)]


# web: v102.js stepRecord (once a game second) and the map frames
static func step(g: Game) -> void:
	if not on(g):
		return
	if g.t - g.rec_t < 1.0 and g.t >= g.rec_t:
		return
	g.rec_t = g.t
	var nats := nations_of(g)
	var now := {"b": {}, "s": {}, "techs": {}, "wars": {}}
	for w in g.wars:
		now.wars[w.id] = true
	for o in nats:
		now.b[o] = buildings_of(g, o)
		now.s[o] = settle_of(g, o)
		var T := tech_of(g, o)
		var ids := {}
		for tr in T:
			for id in T[tr].done:
				ids[id] = true
		now.techs[o] = ids
	var prev: Dictionary = g.rec_prev
	if not prev.is_empty():
		for o in nats:
			var was: Dictionary = prev.b.get(o, {})
			var is_now: Dictionary = now.b[o]
			var n := g.provs_of(o).size()
			var st: Dictionary = g.seats[o].stock if g.is_human(o) else g.nations[o].stock
			for k in is_now:
				var before = was.get(k)
				var v: String = is_now[k]
				if before == v:
					continue
				var ty := v.split(":")[0]
				var p := int(k.split("@")[0])
				if before != null and str(before).split(":")[0] == ty:
					ev(g, o, "upgraded", {"type": ty, "level": int(v.split(":")[1]), "at": g.prov_name(p)})
				else:
					ev(g, o, "built", {"type": ty, "at": g.prov_name(p), "provs": n, "gold": int(JS.round_js(st.gold)), "key": "%d:%s" % [o, k]})
			for k in was:
				if is_now.has(k):
					continue
				var j := -1
				for i in g.rec.ev.size():
					var x: Dictionary = g.rec.ev[i]
					if x.e == "built" and x.get("key") == "%d:%s" % [o, k] and g.t - x.t < 60:
						j = i
				if j >= 0:
					g.rec.ev.remove_at(j)   # torn down (or lost) within a minute of going up: neither counts
				else:
					ev(g, o, "lost building", {"type": str(was[k]).split(":")[0], "at": g.prov_name(int(k.split("@")[0]))})
			var sw: Dictionary = prev.s.get(o, {})
			var si: Dictionary = now.s[o]
			for p in si:
				var b4 = sw.get(p)
				if b4 != null and str(b4) == str(si[p]):
					continue
				var e := ("gained " + word(si[p])) if b4 == null else "fort" if str(si[p]) == "1" and str(b4) == "0" else "settlement now " + word(si[p])
				ev(g, o, e, {"at": g.prov_name(p), "provs": n})
			for p in sw:
				if not si.has(p):
					var to := g.nation_of(p)
					ev(g, o, "lost " + word(sw[p]), {"at": g.prov_name(p), "to": name_of(g, to) if to else null})
			var tw: Dictionary = prev.techs.get(o, {})
			for id in now.techs[o]:
				if not tw.has(id):
					var x = g.TECH_BY_ID.get(id)
					ev(g, o, "researched", {"id": id, "name": x.name if x != null else id, "tree": x.tree if x != null else ""})
			milestones(g, o)
		for w in g.wars:
			if not prev.wars.has(w.id):
				var by: int = w.get("by", w.a)
				ev(g, by, "war", {"between": [name_of(g, w.a), name_of(g, w.b)], "declaredBy": name_of(g, by), "viaAlliance": w.get("parent") != null})
		for id in prev.wars:
			if not now.wars.has(id):
				ev(g, 0, "war over", {"war": id})
	else:
		for o in nats:
			milestones(g, o)
	g.rec_prev = now
	if g.rec.snap.is_empty() or g.t - g.rec.snap[-1].t >= REC_SNAP:
		snap(g)
	if g.rec.frames.is_empty() or g.t - g.rec.frames[-1].t >= FRAME_EVERY:
		frame(g)


# web: v102.js recSnap: a line per nation
static func snap(g: Game) -> void:
	for o in nations_of(g):
		var T := tech_of(g, o)
		var inc: Dictionary = g.seats[o].income if g.is_human(o) else g.nations[o].income
		var st: Dictionary = g.seats[o].stock if g.is_human(o) else g.nations[o].stock
		var bld := {}
		for v in buildings_of(g, o).values():
			var ty: String = v.split(":")[0]
			bld[ty] = bld.get(ty, 0) + 1
		var forts := 0
		for p in g.buildings:
			if g.buildings[p].owner == o and g.buildings[p].stage >= 1:
				forts += 1
		var mages := 0
		for v in g.units:
			if v.owner == o:
				mages += g.mages_in(v)
		var rate := {}
		for tr in ["gov", "mil", "mag"]:
			rate[tr] = g.in_seat(o, func(): return g.tech_rate(tr)) if g.is_human(o) else Ai.tech_rate(g, g.nations[o], tr)
		g.rec.snap.append({"t": rt(g), "o": o, "provs": g.provs_of(o).size(), "forts": forts,
			"inc": {"g": int(JS.round_js(inc.get("gold", 0))), "w": int(JS.round_js(inc.get("wood", 0))), "f": int(JS.round_js(inc.get("food", 0)))},
			"stock": {"g": int(JS.round_js(st.gold)), "w": int(JS.round_js(st.wood)), "f": int(JS.round_js(st.food))},
			"rate": rate, "techs": {"gov": T.gov.done.size(), "mil": T.mil.done.size(), "mag": T.mag.done.size()},
			"bld": bld, "soldiers": g.soldier_count(o), "power": int(Ai.nation_power(g, o)), "mages": mages,
			"school": g.in_seat(o, g.current_school) if g.is_human(o) else g.nations[o].get("school"), "wars": g.wars_of(o).size()})


# web: v102.js recMilestones
static func milestones(g: Game, o: int) -> void:
	var key := str(o)
	if not g.rec.ms.has(key):
		g.rec.ms[key] = {}
	var M: Dictionary = g.rec.ms[key]
	var mark := func(k: String, extra := {}):
		if not M.has(k):
			M[k] = rt(g)
			var x := {"what": k}
			x.merge(extra)
			ev(g, o, "milestone", x)
	var types := {}
	var bs := buildings_of(g, o)
	for v in bs.values():
		types[v.split(":")[0]] = true
	for ty in ["barracks", "forge", "magetower", "temple", "stable", "market"]:
		if types.has(ty):
			mark.call("first " + (g.BUILD_DEFS[ty].name if g.BUILD_DEFS.has(ty) else ty))
	for v in bs.values():
		var parts: PackedStringArray = v.split(":")
		if parts[0] == "forge" and int(parts[1]) >= 2:
			mark.call("Forge level " + parts[1])
	for p in g.buildings:
		if g.buildings[p].owner == o and g.buildings[p].stage == 1:
			mark.call("first fort")
			break
	var T := tech_of(g, o)
	if not T.mil.done.is_empty():
		mark.call("first military research")
	for id in T.mil.done:
		var x = g.TECH_BY_ID.get(id)
		if x == null:
			continue
		if id.begins_with("w-") and x.get("tier", 0) >= 2:
			mark.call("weapon tier %d" % x.tier, {"tech": x.name})
		if id.begins_with("a-") and x.get("tier", 0) >= 2:
			mark.call("armor tier %d" % x.tier, {"tech": x.name})
	if T.mag.done.any(func(id): return id.begins_with("school-")):
		mark.call("school of magic", {"school": g.in_seat(o, g.current_school) if g.is_human(o) else g.nations[o].get("school")})
	var n := g.provs_of(o).size()
	for k in MS_PROV:
		if n >= k:
			mark.call("%d provinces" % k)
	var pw := Ai.nation_power(g, o)
	for k in MS_POW:
		if pw >= k:
			mark.call("army power %s" % (str(k / 1000) + "k" if k >= 2000 else str(k)))


## web: v102.js makePeace wrapper: the peace and its terms
static func peace(g: Game, w: Dictionary, winner: int, terms: Dictionary) -> void:
	if not on(g):
		return
	var loser := Game.foe_of(w, winner)
	var provs = null
	if terms.get("provs") != null:
		provs = terms.provs.map(func(p): return g.prov_name(p))
	ev(g, winner, "peace", {"winner": name_of(g, winner), "loser": name_of(g, loser), "terms": terms.get("kind", ""), "provinces": provs, "warscore": g.warscore(w, winner)})


## The map as it stands, for watching it back: changes since the last frame (provinces, buildings, roads, walls)
## and every nation's armies.
static func frame(g: Game) -> void:
	var f := {"t": rt(g)}
	var last: Dictionary = g.rec_map
	var own := {}
	var cur_own := {}
	for p in g.buildings:
		var b: Dictionary = g.buildings[p]
		var v := [b.owner, b.stage]
		cur_own[p] = v
		if last.get("own", {}).get(p) != v:
			own[str(p)] = v
	for p in last.get("own", {}):
		if not cur_own.has(p):
			own[str(p)] = null
	if not own.is_empty():
		f["own"] = own
	var ex := {}
	var cur_ex := {}
	for p in g.extras:
		var types: Array = g.extras[p].map(func(e): return [e.type, e.slot, e.get("level", 1)])
		cur_ex[p] = types
		if last.get("ex", {}).get(p) != types:
			ex[str(p)] = types
	for p in last.get("ex", {}):
		if not cur_ex.has(p):
			ex[str(p)] = null
	if not ex.is_empty():
		f["ex"] = ex
	var roads: Array = g.roads.keys()
	roads.sort()
	if roads != last.get("roads", []):
		f["roads"] = roads
	var walls: Array = g.walls.keys()
	walls.sort()
	if walls != last.get("walls", []):
		f["walls"] = walls
	var armies := []
	for u in g.units:
		if u.kind != "army" or not (g.is_human(u.owner) or g.nations.has(u.owner)):
			continue
		var n := 0
		var top := ""
		var best := 0
		for k in u.troops:
			n += u.troops[k]
			if u.troops[k] > best:
				best = u.troops[k]
				top = k
		if n > 0:
			armies.append([u.owner, int(u.x), int(u.y), n, top, u.prov, 1 if u.get("battle") != null else 0, u.id])
	f["armies"] = armies
	var battles := []
	for b in g.battles:
		battles.append(b.prov)
	if not battles.is_empty():
		f["battles"] = battles
	g.rec.frames.append(f)
	g.rec_map = {"own": cur_own, "ex": cur_ex, "roads": roads, "walls": walls}


## The recording as it goes into its file (web: v102.js exportRecording, minus the working parts).
static func export(g: Game) -> Dictionary:
	var out: Dictionary = g.rec.duplicate()
	out["endedAt"] = rt(g)
	out["exported"] = Time.get_datetime_string_from_system()
	return out


## Where this game's recording is written.
static func path_of(g: Game) -> String:
	return DIR + str(g.rec.id).validate_filename() + ".json"
