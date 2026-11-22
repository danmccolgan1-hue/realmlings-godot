extends RefCounted
## Multiplayer play over a real connection on this computer (steps 8 and 9): a host and two players start a game from
## the lobby, give orders from their own copies, and stay in step; a copy knocked out of step is sent the game again;
## a player's pause follows the rule; a player who drops out pauses the game, comes back to their own nation, and
## is finally handed to the computer; when the host leaves, the others are told.

const TEST_PORT := 24602

var h: NetSession
var a: NetSession
var b: NetSession
var L := {}          # session -> Lockstep
var asked := []      # [nation, name] from ask_drop
var ended := []


func run() -> Array:
	var errs := []
	h = NetSession.new("Host", {"race": "realm"})
	if h.host(TEST_PORT, false) != "":
		return ["hosting failed"]
	a = NetSession.new("Ann", {"race": "swamp"})
	b = NetSession.new("Bo", {"race": "wood"})
	a.join("127.0.0.1:%d" % TEST_PORT)
	b.join("127.0.0.1:%d" % TEST_PORT)
	_pump(func(): return h.players.size() == 3 and a.joined and b.joined, 4.0)
	if h.players.size() != 3:
		return ["the lobby didn't fill (%d)" % h.players.size()]
	for s in [a, b]:
		s.message.connect(_on_start.bind(s))
	# the host starts: each player takes a slot as a human nation
	var g := Game.new_world("ember", "cormac", ["human", "human", "moderate"], "center", {}, {}, {"name": "Hosts"}, "realm", [],
		{0: {"nation": {"name": "Ann's Bog"}, "race": "swamp"}, 1: {"nation": {"name": "Bo's Wood"}, "race": "wood"}})
	var ids := g.seat_ids()
	var seats := {1: Game.HOST, a.my_id: ids[1], b.my_id: ids[2]}
	g.seat_names = {Game.HOST: "Host", ids[1]: "Ann", ids[2]: "Bo"}
	g.paused = false
	var hl := Lockstep.new(h, g, true, Game.HOST)
	hl.ask_drop.connect(func(o, nm): asked.append([o, nm]))
	L[h] = hl
	hl.begin(seats)
	_run(func(): return L.has(a) and L.has(b) and L[a].game != null and L[b].game != null and hl.started, 10.0)
	if not hl.started:
		return errs + ["the players never loaded the game"]
	if L[a].me != ids[1] or L[b].me != ids[2] or L[a].game.view_seat != ids[1]:
		errs.append("the players were not given their own nations")
	# orders from every copy, through the host
	var n0: Dictionary = {}
	for o in ids:
		n0[o] = hl.game.units.filter(func(u): return u.owner == o).size()
	_run(func(): return hl.step >= 40)
	for s in [h, a, b]:
		var G0: Game = L[s].game
		G0.do("train", ["capital", G0.capital, G0.trainable("capital", G0.capital)[0]])
	_run(func(): return hl.step >= 400)
	_settle()
	for o in ids:
		if hl.game.seats[o].queues.values().all(func(q): return q.is_empty()) and hl.game.units.filter(func(u): return u.owner == o).size() <= n0[o]:
			errs.append("nation %d's order never arrived" % o)
	errs.append_array(_same("after the first orders"))
	if L[a].resyncs > 0 or L[b].resyncs > 0:
		errs.append("a copy fell out of step on its own")
	# a copy knocked out of step gets the game again
	var bu: Dictionary = L[b].game.units[0]
	bu.x += 0.001
	_run(func(): return L[b].resyncs > 0, 15.0)
	if L[b].resyncs == 0:
		errs.append("a copy out of step was not caught")
	_run(func(): return hl.step >= L[b].step + 60)
	_settle()
	errs.append_array(_same("after the resync"))
	# the pause rule, over the network
	L[a].game.do("set_paused", [true])
	_run(func(): return hl.game.paused, 3.0)
	L[b].game.do("set_paused", [false])
	_run(func(): return hl.step >= L[b].step + 20, 3.0)
	if not hl.game.paused or hl.game.paused_by != ids[1]:
		errs.append("Ann's pause was lifted by Bo")
	L[a].game.do("set_paused", [false])
	_run(func(): return not hl.game.paused, 3.0)
	if hl.game.paused:
		errs.append("Ann could not lift her own pause")
	_settle()
	errs.append_array(_same("after pausing"))
	# Bo drops out: the game pauses and the host is asked
	var b_old := b
	b.leave()
	L.erase(b_old)
	_run(func(): return not asked.is_empty(), 8.0)
	if asked.is_empty() or asked[0][0] != ids[2]:
		errs.append("Bo's drop-out was not noticed")
	_run(func(): return hl.game.paused, 2.0)
	if not hl.game.paused:
		errs.append("the game did not pause when Bo dropped out")
	# Bo comes back to his nation
	var b2 := NetSession.new("Bo", {"race": "wood"})
	b2.message.connect(_on_start.bind(b2))
	b2.join("127.0.0.1:%d" % TEST_PORT)
	b = b2
	_run(func(): return L.has(b2) and L[b2].game != null, 8.0)
	if not L.has(b2) or L[b2].me != ids[2]:
		errs.append("Bo could not come back to his nation")
	else:
		hl.game.do("set_paused", [false])
		_run(func(): return hl.step >= 1000, 20.0)
		_settle()
		errs.append_array(_same("after Bo came back"))
	# Bo drops again and the host hands his nation to the computer
	b2.leave()
	L.erase(b2)
	asked.clear()
	_run(func(): return not asked.is_empty(), 8.0)
	hl.hand_over(ids[2])
	hl.game.do("set_paused", [false])
	_run(func(): return hl.game.nations.has(ids[2]) and hl.step >= 1200, 15.0)
	_settle()
	if not hl.game.nations.has(ids[2]) or not L[a].game.nations.has(ids[2]):
		errs.append("Bo's nation was not handed to the computer in every copy")
	_settle()
	errs.append_array(_same("after the hand-over"))
	# the host leaves: Ann is told
	L[a].ended.connect(func(why): ended.append(why))
	h.leave()
	_run(func(): return not ended.is_empty(), 4.0)
	if ended.is_empty():
		errs.append("Ann was not told the host left")
	a.leave()
	return errs


# a player's lobby hears "start": make their lockstep and load the host's game (main does this in the background)
func _on_start(from: int, m: Dictionary, s: NetSession) -> void:
	if m.get("t") != "start" or (L.has(s) and L[s].game != null):
		return
	var lk := Lockstep.new(s, null, false, int(m.seat))
	L[s] = lk
	var g := Game.load_text(str(m.save), L[h].game.world)
	lk.loaded(g, int(m.s))


# every copy at the same step has the same fingerprint
func _same(when: String) -> Array:
	var errs := []
	var k: int = L[h].game.checksum()
	for s in L:
		if s != h and L[s].game != null and L[s].step == L[h].step and L[s].game.checksum() != k:
			errs.append("%s's copy differs from the host's %s" % [s.my_name, when])
	return errs


# let the players catch up with the host and stop the host's clock meanwhile
func _settle() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		for s in [h, a, b]:
			if s.peer != null:
				s.poll(0.01)
		for s in L:
			if s != h:
				L[s].process(0.0)
		if L.keys().all(func(s): return s == h or L[s].game == null or L[s].step == L[h].step):
			return
		OS.delay_msec(2)


func _run(done: Callable, secs := 30.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000:
		for s in [h, a, b]:
			if s != null and s.peer != null:
				s.poll(0.01)
		for s in L.keys():
			if L.has(s):
				L[s].process(0.05)
		if done.call():
			return
		OS.delay_msec(1)


func _pump(done: Callable, secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000:
		for s in [h, a, b]:
			s.poll(0.01)
		if done.call():
			return
		OS.delay_msec(5)
