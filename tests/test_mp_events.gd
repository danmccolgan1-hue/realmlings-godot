extends RefCounted
## Multiplayer copies stay in step through a question to a player (0.19.1): a lost band of travelers asks the
## player's nation; the host (like the dedicated server) has no window to ask in, the player's copy shows the question
## and answers a moment later. Every copy must wait for that answer: the server used to send the band away by itself,
## and from then on its game and its players' differed (they fell out of step every few seconds). The question also
## survives saving and loading (a copy sent the game again keeps waiting for the same answer).

const PORT := 24640

var h: NetSession
var a: NetSession
var L := {}
var asked := []


func run() -> Array:
	var errs := []
	h = NetSession.new("Host", {"race": "realm"})
	if h.host(PORT, false) != "":
		return ["events: hosting failed"]
	a = NetSession.new("Ann", {"race": "swamp"})
	a.join("127.0.0.1:%d" % PORT)
	_pump(func(): return h.players.size() == 2 and a.joined, 4.0)
	a.message.connect(_on_start)
	var g := Game.new_world("ember", "cormac", ["human", "moderate"], "center", {}, {}, {"name": "Hosts"}, "realm", [],
		{0: {"nation": {"name": "Ann's Bog"}, "race": "swamp"}})
	var ids := g.seat_ids()
	var ann: int = ids[1]
	g.seat_names = {Game.HOST: "Host", ann: "Ann"}
	# a band of travelers right where Ann's first unit stands: they ask her at once
	var u: Dictionary = g.units.filter(func(v): return v.owner == ann)[0]
	var B: Dictionary = g.travelers[0]
	B.prov = u.prov
	B.x = g.G.provs[u.prov].ic[0]
	B.y = g.G.provs[u.prov].ic[1]
	g.paused = false
	var hl := Lockstep.new(h, g, true, Game.HOST)
	L[h] = hl
	hl.begin({1: Game.HOST, a.my_id: ann})
	_run(func(): return L.has(a) and L[a].game != null and hl.started, 10.0)
	if not hl.started:
		return ["events: the player never loaded the game"]
	_run(func(): return not asked.is_empty(), 10.0)
	if asked.is_empty():
		return ["events: the travelers never asked Ann"]
	if hl.game.trav_asking == null:
		errs.append("events: the host (no window) didn't wait for Ann's answer")
	# a copy loaded from the host's save is still waiting for the same answer
	var copy := Game.load_text(hl.game.save_text(), hl.game.world)
	if copy == null or copy.trav_asking == null or int(copy.trav_asking.prov) != int(B.prov):
		errs.append("events: a loaded copy forgot the question")
	_run(func(): return hl.step >= L[a].step and hl.step > 200, 10.0)
	L[a].game.do("travelers_choose", ["leave"])   # (Ann answers a few seconds later)
	_run(func(): return hl.game.trav_asking == null, 5.0)
	if hl.game.trav_asking != null:
		errs.append("events: Ann's answer never arrived")
	_run(func(): return hl.step >= 500, 15.0)
	_settle()
	if L[a].step == hl.step and L[a].game.checksum() != hl.game.checksum():
		errs.append("events: Ann's copy differs from the host's after the question")
	if L[a].resyncs > 0:
		errs.append("events: Ann fell out of step (%d resyncs)" % L[a].resyncs)
	a.leave()
	h.leave()
	return errs


func _on_start(_from: int, m: Dictionary) -> void:
	if m.get("t") != "start" or (L.has(a) and L[a].game != null):
		return
	var lk := Lockstep.new(a, null, false, int(m.seat))
	L[a] = lk
	var g := Game.load_text(str(m.save), L[h].game.world)
	g.on_dialog = func(title, _text, _choices, _f): asked.append(title)   # (Ann's window: the question shows)
	lk.loaded(g, int(m.s))


func _settle() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		h.poll(0.01)
		a.poll(0.01)
		L[a].process(0.0)
		if L[a].step == L[h].step:
			return
		OS.delay_msec(2)


func _run(done: Callable, secs := 30.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000:
		for s in [h, a]:
			if s.peer != null:
				s.poll(0.01)
		for s in L.keys():
			L[s].process(0.05)
		if done.call():
			return
		OS.delay_msec(1)


func _pump(done: Callable, secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000:
		h.poll(0.01)
		a.poll(0.01)
		if done.call():
			return
		OS.delay_msec(5)
