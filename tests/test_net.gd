extends RefCounted
## The multiplayer lobby over a real connection on this computer: a host and two players join, chat reaches
## everyone, a changed nation reaches everyone, a player with another game version is turned away, and a player
## who leaves is dropped from the list.

const TEST_PORT := 24599


func run() -> Array:
	var errs := []
	var h := NetSession.new("Host", {"race": "realm"})
	var w := h.host(TEST_PORT, false)
	if w != "":
		return ["hosting failed: " + w]
	var a := NetSession.new("Ann", {"race": "swamp"})
	var b := NetSession.new("Bo", {"race": "wood"})
	var heard := []
	b.chat.connect(func(n, tx): heard.append([n, tx]))
	a.join("127.0.0.1:%d" % TEST_PORT)
	b.join("127.0.0.1:%d" % TEST_PORT)
	_pump([h, a, b], func(): return h.players.size() == 3 and a.players.size() == 3 and b.players.size() == 3)
	if h.players.size() != 3 or a.players.size() != 3 or b.players.size() != 3:
		errs.append("three players in the lobby (host sees %d, Ann %d, Bo %d)" % [h.players.size(), a.players.size(), b.players.size()])
	a.send_chat("hello from the swamp")
	_pump([h, a, b], func(): return heard.any(func(x): return x[1] == "hello from the swamp"))
	if not heard.any(func(x): return x[0] == "Ann" and x[1] == "hello from the swamp"):
		errs.append("chat reaches the other players")
	a.set_nation({"race": "swamp", "emblem": "skull"})
	_pump([h, a, b], func(): return b.players.has(a.my_id) and b.players[a.my_id].nation.get("emblem") == "skull")
	if not (b.players.has(a.my_id) and b.players[a.my_id].nation.get("emblem") == "skull"):
		errs.append("a changed nation reaches the other players")
	var old := NetSession.new("Old", {})
	old.version = "0.0.1"
	var why := []
	old.closed.connect(func(x): why.append(x))
	old.join("127.0.0.1:%d" % TEST_PORT)
	_pump([h, a, b, old], func(): return not why.is_empty())
	if why.is_empty() or not str(why[0]).begins_with("Different game versions"):
		errs.append("another version is turned away (%s)" % str(why))
	b.leave()
	_pump([h, a], func(): return h.players.size() == 2 and a.players.size() == 2, 4.0)
	if h.players.size() != 2 or a.players.size() != 2:
		errs.append("a player who leaves is dropped (host sees %d, Ann %d)" % [h.players.size(), a.players.size()])
	for s in [h, a, old]:
		s.leave()
	return errs


func _pump(sessions: Array, done: Callable, secs := 3.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000:
		for s in sessions:
			s.poll(0.01)
		if done.call():
			for i in 5:
				for s in sessions:
					s.poll(0.01)
				OS.delay_msec(5)
			return
		OS.delay_msec(10)
