class_name Replay
extends RefCounted
## Watching a recorded game back (Recorder): a stand-in Game that only the map reads, set to how the map stood at the
## playhead from the recording's frames (provinces, buildings, roads, walls and armies, which glide between frames).
## The real rules never run here.

var rec: Dictionary
var g: Game                 # the stand-in the map draws
var t := 0.0                # the playhead, in game seconds
var t0 := 0.0
var t1 := 0.0
var _at := -1               # the last frame folded into the state
var _own := {}
var _ex := {}
var _roads := []
var _walls := []


## Raise the recorded map (the same seed gives the same island) and the stand-in game. Slow: call off the main thread.
static func load_file(path: String):
	var txt := FileAccess.get_file_as_string(path)
	return from_dict(JSON.parse_string(txt) if txt != "" else null)


static func from_dict(d):
	if not (d is Dictionary) or d.get("frames", []).is_empty():
		return null
	var r := Replay.new()
	r.rec = d
	var g := Game.new()
	var md: String = str(d.header.get("mode", "normal"))
	g.world = RealmGen.scale_world(RealmGen.generate_world(str(d.header.seed), Game.map_opts_of(md) if md.begins_with("map:") else null, true))
	g.world.mode = md
	g.G = WorldPrep.prep(g.world)
	g.setup_game("center")
	g.players = d.header.players
	r.g = g
	r.t0 = float(d.frames[0].t)
	r.t1 = float(d.frames[-1].t)
	r.reset()
	return r


func reset() -> void:
	_at = -1
	_own = {}
	_ex = {}
	_roads = []
	_walls = []
	g.buildings = {}
	g.extras = {}
	g.units = []
	g.roads = {}
	g.walls = {}
	g.battles = []
	g.reveal_all = true
	g.explored = {}
	g.visible = {}
	for p in g.G.provs.size():
		g.explored[p] = true
		g.visible[p] = true
	t = t0
	seek(t0)


## Move the playhead (forward or back) and set the map to match.
func seek(to: float) -> void:
	t = clampf(to, t0, t1)
	var frames: Array = rec.frames
	var want := 0
	while want + 1 < frames.size() and float(frames[want + 1].t) <= t:
		want += 1
	if want < _at:
		_at = -1
		_own = {}
		_ex = {}
		_roads = []
		_walls = []
	var changed := false
	while _at < want:
		_at += 1
		var f: Dictionary = frames[_at]
		for k in f.get("own", {}):
			if f.own[k] == null:
				_own.erase(int(k))
			else:
				_own[int(k)] = f.own[k]
			changed = true
		for k in f.get("ex", {}):
			if f.ex[k] == null:
				_ex.erase(int(k))
			else:
				_ex[int(k)] = f.ex[k]
			changed = true
		if f.has("roads"):
			_roads = f.roads
			changed = true
		if f.has("walls"):
			_walls = f.walls
			changed = true
	if changed:
		g.buildings = {}
		for p in _own:
			g.buildings[p] = {"owner": int(_own[p][0]), "stage": int(_own[p][1]), "born": 0}
		g.extras = {}
		for p in _ex:
			g.extras[p] = _ex[p].map(func(e): return {"type": e[0], "slot": int(e[1]), "level": int(e[2])})
		g.roads = {}
		for k in _roads:
			g.roads[k] = true
		g.walls = {}
		for i in _walls:
			g.walls[int(i)] = true
	_armies(frames, want)
	g.t = t


# armies glide from one frame to the next (matched by unit id)
func _armies(frames: Array, i: int) -> void:
	var f: Dictionary = frames[i]
	var nxt = frames[i + 1] if i + 1 < frames.size() else null
	var k := 0.0
	var later := {}
	if nxt != null:
		k = clampf((t - float(f.t)) / maxf(0.001, float(nxt.t) - float(f.t)), 0.0, 1.0)
		for a in nxt.armies:
			if a.size() > 7:
				later[int(a[7])] = a
	var us := []
	var battles := {}
	for a in f.armies:
		var x := float(a[1])
		var y := float(a[2])
		if a.size() > 7 and later.has(int(a[7])):
			var b: Array = later[int(a[7])]
			x = lerpf(x, float(b[1]), k)
			y = lerpf(y, float(b[2]), k)
		var troops := {str(a[4]): int(a[3])}
		us.append({"id": a[7] if a.size() > 7 else us.size(), "kind": "army", "owner": int(a[0]), "x": x, "y": y, "th": 0.0, "prov": int(a[5]),
			"troops": troops, "name": "", "moving": false, "build": null, "survey": null, "scouting": null, "path": []})
		if int(a[6]):
			battles[int(a[5])] = true
	g.units = us
	var bl := []
	for p in f.get("battles", battles.keys()):
		bl.append({"prov": int(p)})
	g.battles = bl


## The latest snapshot line of each nation at the playhead (web: recSnap lines), by nation id.
func stats_at() -> Dictionary:
	var out := {}
	for s in rec.snap:
		if float(s.t) > t:
			break
		out[int(s.o)] = s
	return out


## The events up to the playhead, newest last.
func events_until(n := 8) -> Array:
	var out := []
	for e in rec.ev:
		if float(e.t) > t:
			break
		out.append(e)
	return out.slice(maxi(0, out.size() - n))


## One line of text for an event (web: the recording's event kinds).
func event_text(e: Dictionary) -> String:
	var who := _nat_name(int(e.get("o", 0)))
	match str(e.e):
		"built":
			return "%s built a %s in %s" % [who, _bname(e.type), e.at]
		"upgraded":
			return "%s raised a %s to level %d in %s" % [who, _bname(e.type), int(e.level), e.at]
		"lost building":
			return "%s lost a %s in %s" % [who, _bname(e.type), e.at]
		"researched":
			return "%s researched %s" % [who, e.name]
		"milestone":
			return "%s: %s" % [who, e.what]
		"war":
			return "War: %s declared war on %s" % [e.declaredBy, e.between[1] if e.between[0] == e.declaredBy else e.between[0]]
		"war over":
			return "A war ended"
		"peace":
			return "Peace: %s won against %s (%s)" % [e.winner, e.loser, e.terms]
		"fort":
			return "%s built a fort in %s" % [who, e.at]
	if str(e.e).begins_with("gained") or str(e.e).begins_with("lost") or str(e.e).begins_with("settlement"):
		return "%s: %s, %s" % [who, e.e, e.get("at", "")]
	return "%s: %s" % [who, e.e]


func _nat_name(o: int) -> String:
	for n in rec.header.nations:
		if int(n.id) == o:
			return n.name
	return "Nobody" if o == 0 else "?"


func _bname(ty) -> String:
	var d = g.BUILD_DEFS.get(str(ty))
	return d.name if d != null else str(ty)
