extends RefCounted
## Recording a game and watching it back: the recording (Recorder) keeps the web game's stats log (events,
## milestones, a line per nation every 30 s) and map frames; a Replay rebuilt from the saved file shows the map exactly
## as it stood when each frame was taken. Recording never changes how the game plays.

func run() -> Array:
	var errs := []
	Game.test_random = 0.5
	var g := Game.new_world("river", "", ["easy", "moderate"])
	var plain := Game.load_text(g.save_text())   # the same game, not recorded
	g.paused = false
	plain.paused = false
	Recorder.start(g, "test")
	var want := {}
	var want_ex := {}
	var want_t := 0.0
	var real := 1.0
	var nf := 0
	while g.t < 420.0:
		real += 0.1
		g.update(real)
		plain.update(real)
		if g.rec.frames.size() != nf:
			nf = g.rec.frames.size()
			if nf == 40:   # the map as frame 40 saw it
				want_t = float(g.rec.frames[-1].t)
				for p in g.buildings:
					want[p] = [g.buildings[p].owner, g.buildings[p].stage]
				for p in g.extras:
					want_ex[p] = g.extras[p].size()
	Game.test_random = -1.0
	# recording doesn't change the game
	var sa := JSON.stringify(state(g))
	var sb := JSON.stringify(state(plain))
	if sa != sb:
		var i := 0
		while i < mini(sa.length(), sb.length()) and sa[i] == sb[i]:
			i += 1
		errs.append("recording changed the game: …%s… vs …%s…" % [sa.substr(maxi(0, i - 80), 160), sb.substr(maxi(0, i - 80), 160)])
	var R: Dictionary = g.rec
	if R.snap.size() < 3 * 14 or R.frames.size() < 75:
		errs.append("recording: %d snapshot lines, %d frames in 7 minutes" % [R.snap.size(), R.frames.size()])
	var kinds := {}
	for e in R.ev:
		kinds[e.e] = true
	for k in ["gained outpost", "built", "milestone"]:
		if not kinds.has(k):
			errs.append("recording: no '%s' event in 7 minutes of three nations (%s)" % [k, kinds.keys()])
	# the file, read back, plays the map as it stood
	var d = JSON.parse_string(JSON.stringify(Recorder.export(g)))
	var r = Replay.from_dict(d)
	if r == null:
		errs.append("replay: the recording can't be read back")
		return errs
	r.seek(want_t)
	var got := {}
	for p in r.g.buildings:
		got[p] = [r.g.buildings[p].owner, r.g.buildings[p].stage]
	if JSON.stringify(got) != JSON.stringify(want):
		errs.append("replay at %d s: provinces differ\n   got %s\n   want %s" % [want_t, JSON.stringify(got).left(300), JSON.stringify(want).left(300)])
	for p in want_ex:
		if r.g.extras.get(p, []).size() != want_ex[p]:
			errs.append("replay at %d s: province %d has %d buildings, want %d" % [want_t, p, r.g.extras.get(p, []).size(), want_ex[p]])
			break
	# scrubbing back and forth lands on the same map
	r.seek(r.t1)
	r.seek(want_t)
	var again := {}
	for p in r.g.buildings:
		again[p] = [r.g.buildings[p].owner, r.g.buildings[p].stage]
	if JSON.stringify(again) != JSON.stringify(want):
		errs.append("replay: seeking back to %d s doesn't give the same map" % want_t)
	if r.stats_at().size() != 3:
		errs.append("replay: %d nations' numbers at the playhead, want 3" % r.stats_at().size())
	return errs


## What the rules decided (names, picked by an unseeded generator, left out)
static func state(g: Game) -> Dictionary:
	var nats := {}
	for o in g.nations:
		var N: Dictionary = g.nations[o]
		nats[str(o)] = [N.stock, N.tech.gov.done, N.tech.mil.done, N.tech.mag.done]
	var us := []
	for u in g.units:
		us.append([u.owner, u.kind, u.prov, int(u.x), int(u.y), u.get("troops", {})])
	us.sort_custom(func(a, b): return str(a) < str(b))
	var ex := {}
	for p in g.extras:
		ex[str(p)] = g.extras[p].map(func(e): return [e.type, e.slot, e.get("level", 1)])
	var bs := {}
	for p in g.buildings:
		bs[str(p)] = [g.buildings[p].owner, g.buildings[p].stage]
	return {"t": snappedf(g.t, 0.01), "stock": g.stock, "b": bs, "ex": ex, "nations": nats, "units": us, "wars": g.wars.size()}
