class_name Lockstep
extends RefCounted
## Playing one game together (multiplayer step 8, docs: the multiplayer plan). Every copy runs the same rules from
## the same save, in the same fixed steps (Game.STEP), with the same orders at the same step, so only orders travel.
##
## The host keeps the clock: each step it sends every player the orders for that step ("go"), then runs it. A
## player's order goes to the host, which schedules it DELAY steps ahead (so it reaches everyone in time) and
## stamps it with that player's nation. Players run the steps as the host's messages arrive. Every SUM_EVERY steps
## each player sends a fingerprint of its game (Game.checksum); one that differs from the host's gets the host's
## save and carries on from there.
##
## Drop-outs (step 9): a player who goes quiet for DROP_AFTER seconds, or whose connection closes, pauses the game
## and everyone is told; the host chooses to wait (they may come back to their nation by joining with the same
## name) or to hand their nation to the computer. If the host leaves, every player keeps a save.
## Rules never draw: this only moves orders and saves; the game's views show the results.

signal note(text: String)                  # tell this player something (someone dropped, came back, a resync)
signal ask_drop(nation: int, name: String) # host: wait for this player, or hand their nation to the computer?
signal game_replaced(g: Game)              # a resync loaded the host's save: the views show the new game
signal ended(why: String)                  # the game is over for this player (the host left)
signal waiting(text: String)               # "" when the game is running; otherwise why it waits
signal resumed                             # host: everyone who dropped out is back, and the game goes on

const DELAY := 3              # an order runs 3 steps (150 ms) after the host receives it
const SUM_EVERY := 100        # fingerprints every 5 s of steps
const ACK_EVERY := 10         # players report their step twice a second
const LAG_MAX := 80           # the host waits for a player more than 4 s of steps behind
const DROP_AFTER := 15.0      # seconds without a word: the player has dropped out (0.19: was 5, which a busy computer or a
                              # wobbly connection could reach without anything being wrong)
const MAX_CATCHUP := 40       # steps a player runs in one frame to catch up
## Orders only the host may give. (Settings → Debug is for every player when the lobby allowed it: Game.debug_ok.)
const HOST_ONLY := ["hand_to_ai", "take_from_ai", "grant_tech", "rec_toggle"]

var net: NetSession
var game: Game
var is_host := false
var me := 0                    # this player's nation
var seat_of := {}              # host: peer id -> nation
var names := {}                # nation -> player name
var step := 0                  # the next step to run
var pending := {}              # host: step -> [command]
var inbox := {}                # players: step -> [command] (the host's "go" messages)
var sums := {}                 # host: step -> fingerprint
var heard := {}                # host: peer id -> last time (s) a message came from them
var acked := {}                # host: peer id -> the step they had reached
var ready := {}                # host: peer ids that loaded the game
var gone := {}                 # host: nation -> true while its player is away
var started := false           # host: everyone loaded, the clock runs
var resyncs := 0
var drop_paused := false       # host: the game was paused because someone dropped out (it goes on when they're all back)
var send_at := {}              # host: peer id -> [step, nation]: send them the game once that step has run (hot-join)
var host_pid := 1              # host: the player who may give HOST_ONLY orders (on a dedicated server, the one hosting)
var _acc := 0.0
var _clock := 0.0


func _init(session: NetSession, g: Game, host: bool, nation: int) -> void:
	net = session
	is_host = host
	me = nation
	if g != null:
		_set_game(g)
	net.message.connect(_on_message)
	net.closed.connect(_on_closed)
	if is_host:
		net.locked = true
		net.left.connect(_on_left)
		net.rejoined.connect(_on_rejoined)
		net.take_seat.connect(_on_take_seat)
		net.seat_choices = _seat_choices


## A player: the game from the host's "start" has loaded (main loads it in the background); run from step s.
func loaded(g: Game, s: int) -> void:
	_set_game(g)
	step = s
	for k in inbox.keys():
		if k < s:
			inbox.erase(k)
	net.send_to(1, {"t": "ready"})
	net.send_to(1, {"t": "ack", "s": step})


func _set_game(g: Game) -> void:
	game = g
	game.view_seat = me
	game.use_seat(me)
	game.on_command = _order


# =================================================================================================================
# the host

## Start: send every player the game and their nation. `seats`: peer id -> nation (the host is 1 -> Game.HOST).
func begin(seats: Dictionary) -> void:
	seat_of = seats.duplicate()
	var text := game.save_text()
	for pid in seat_of:
		names[seat_of[pid]] = game.seat_names.get(seat_of[pid], str(net.players.get(pid, {}).get("name", "Player")))
		if pid != 1:
			net.reserved[names[seat_of[pid]]] = true
			net.send_to(pid, {"t": "start", "save": text, "seat": seat_of[pid], "s": step})
			heard[pid] = _clock
	ready = {1: true}
	waiting.emit("Waiting for everyone to load the island…")


## The game's clock, every frame (host) or the steps that have arrived (players).
func process(dt: float) -> void:
	_clock += dt
	if is_host:
		_host_tick(dt)
	else:
		_client_tick()


func _host_tick(dt: float) -> void:
	if not started:
		if seat_of.keys().all(func(pid): return ready.has(pid) or gone.has(seat_of[pid])):
			started = true
			waiting.emit("")
		elif _clock > 60.0:   # someone never loaded: go on without them, as if they dropped
			for pid in seat_of:
				if not ready.has(pid):
					_dropped(pid)
		return
	_check_quiet()
	_acc = minf(_acc + dt, 0.25)
	while _acc >= Game.STEP:
		var slow := _slowest()
		if slow != "":
			waiting.emit("Waiting for %s to catch up…" % slow)
			_acc = 0.0
			return
		_acc -= Game.STEP
		var cmds: Array = pending.get(step, [])
		pending.erase(step)
		net.send_all({"t": "go", "s": step, "c": cmds})
		_run(cmds)
		_send_waiting()
	waiting.emit("")


# host: a player joining a game in progress gets the game once the order giving them their nation has run
func _send_waiting() -> void:
	for pid in send_at.keys():
		if step > int(send_at[pid][0]):
			var o: int = send_at[pid][1]
			send_at.erase(pid)
			if not game.seats.has(o):
				continue
			seat_of[pid] = o
			heard[pid] = _clock
			acked[pid] = step
			net.send_to(pid, {"t": "start", "save": game.save_text(), "seat": o, "s": step})


## The name of a player too far behind to go on without, or "".
func _slowest() -> String:
	for pid in seat_of:
		if pid == 1 or gone.has(seat_of[pid]):
			continue
		if step - int(acked.get(pid, 0)) > LAG_MAX:
			return names.get(seat_of[pid], "a player")
	return ""


func _check_quiet() -> void:
	for pid in seat_of.keys():
		if pid != 1 and not gone.has(seat_of[pid]) and _clock - float(heard.get(pid, _clock)) > DROP_AFTER:
			_dropped(pid)


# a player stopped answering, or their connection closed
func _dropped(pid: int) -> void:
	var o: int = seat_of.get(pid, 0)
	if o == 0 or gone.has(o) or not game.seats.has(o):
		return
	gone[o] = true
	var nm: String = names.get(o, "A player")
	NetSession.log_line("%s dropped out (no word for %d s, or their connection closed)" % [nm, int(DROP_AFTER)])
	if not game.paused:
		drop_paused = true
	_queue({"player": Game.HOST, "type": "set_paused", "args": [true]})
	net.announce("%s has dropped out. The game is paused while the host decides." % nm)
	note.emit("%s has dropped out." % nm)
	ask_drop.emit(o, nm)


## The host's answer to ask_drop: hand the nation to the computer (or keep waiting: do nothing).
func hand_over(o: int) -> void:
	if not is_host or not game.seats.has(o) or o == Game.HOST:   # (the first nation can only wait for a player)
		return
	_queue({"player": Game.HOST, "type": "hand_to_ai", "args": [o]})
	gone.erase(o)   # (0.19: no longer waited for; a newcomer may still take it back from the computer)
	net.announce("%s is now played by the computer." % names.get(o, "The nation"))
	for pid in seat_of.keys():
		if seat_of[pid] == o:
			seat_of.erase(pid)
	net.reserved.erase(names.get(o, ""))
	_resume_if_all_back()


func _on_left(pid: int, _name: String) -> void:
	if seat_of.has(pid):
		_dropped(pid)


func _on_rejoined(pid: int, nm: String) -> void:
	var o := 0
	for n in names:
		if names[n] == nm and gone.has(n) and game.seats.has(n):
			o = n
	if o == 0:   # 0.19: back before their old connection was noticed as gone (it froze the newcomer): take it over now
		for n in names:
			if names[n] == nm and game.seats.has(n):
				o = n
	if o == 0:
		net.send_to(pid, {"t": "refused", "why": "Your nation is no longer in this game (it was handed to the computer, or has fallen)."})
		return
	_seat_player(pid, o, nm)


# host: player pid (peer) plays nation o from now on: send them the game
func _seat_player(pid: int, o: int, nm: String) -> void:
	for old in seat_of.keys():
		if seat_of[old] == o:
			seat_of.erase(old)
	seat_of[pid] = o
	gone.erase(o)
	names[o] = nm
	net.reserved[nm] = true
	heard[pid] = _clock
	acked[pid] = step
	ready[pid] = true
	net.send_to(pid, {"t": "start", "save": game.save_text(), "seat": o, "s": step})
	net.announce("%s is back." % nm)
	note.emit("%s is back." % nm)
	NetSession.log_line("%s took up nation %d at step %d" % [nm, o, step])
	_resume_if_all_back()


# host: everyone who dropped out is back: the game goes on by itself (it was paused for them)
func _resume_if_all_back() -> void:
	if drop_paused and gone.is_empty():
		drop_paused = false
		_queue({"player": Game.HOST, "type": "set_paused", "args": [false]})
		resumed.emit()


## host (hot-join, 0.19): the nations a player joining the game in progress may take: those whose player is away,
## and those a player had before they were handed to the computer.
func _seat_choices() -> Array:
	var out := []
	for o in game.seat_ids():
		if gone.has(o) and not game.seats[o].fallen:   # (on a server the first nation's player can be away too)
			out.append({"id": o, "nation": str(game.player_info(o).name), "player": str(names.get(o, "")), "state": "away", "race": game.race(o)})
	var coming := send_at.values().map(func(x): return int(x[1]))   # (already being handed to someone)
	for o in game.nations:
		if game.nations[o].get("fromHuman", false) and game.nations[o].get("alive", true) and not coming.has(int(o)):
			out.append({"id": int(o), "nation": str(game.player_info(int(o)).name), "player": str(names.get(int(o), "")), "state": "computer", "race": game.race(int(o))})
	return out


# host: a player joining the game in progress chose nation o
func _on_take_seat(pid: int, nm: String, o: int) -> void:
	var ok := _seat_choices().any(func(c): return int(c.id) == o)
	if not ok:
		var free_now := _seat_choices()
		if free_now.is_empty():
			net.send_to(pid, {"t": "refused", "why": "That nation was just taken, and no other is free."})
		else:
			net.picking[pid] = true
			net.send_to(pid, {"t": "pick_seat", "choices": free_now})
		return
	if game.seats.has(o):   # a player's nation that is waiting for them
		_seat_player(pid, o, nm)
		return
	# a nation the computer plays: every copy hands it back at the same step, then the newcomer gets the game
	names[o] = nm
	net.reserved[nm] = true
	_queue({"player": Game.HOST, "type": "take_from_ai", "args": [o, nm]})
	send_at[pid] = [step + DELAY, o]
	net.announce("%s joins the game as %s." % [nm, game.player_info(o).name])
	note.emit("%s joins the game as %s." % [nm, game.player_info(o).name])
	NetSession.log_line("%s takes nation %d back from the computer" % [nm, o])


# =================================================================================================================
# everyone

# an order from this player's interface (Game.do)
func _order(cmd: Dictionary) -> void:
	if is_host:
		_queue(cmd, 1)
	else:
		net.send_to(1, {"t": "cmd", "cmd": cmd})


# host: schedule an order, stamped with its player's nation
func _queue(cmd: Dictionary, pid := 0) -> void:
	var c := cmd.duplicate()
	if pid != 0:
		if not seat_of.has(pid):
			return
		c.player = seat_of[pid]
		if c.get("type") in HOST_ONLY and pid != host_pid:
			return
	var at := step + DELAY
	if not pending.has(at):
		pending[at] = []
	pending[at].append(c)


func _run(cmds: Array) -> void:
	for c in cmds:
		game.apply(c)
	game.step_fixed()
	step += 1
	if step % SUM_EVERY == 0:
		var h := game.checksum()
		if is_host:
			sums[step] = h
			sums.erase(step - SUM_EVERY * 6)
		else:
			net.send_to(1, {"t": "sum", "s": step, "h": h})
	if not is_host and step % ACK_EVERY == 0:
		net.send_to(1, {"t": "ack", "s": step})


func _client_tick() -> void:
	if game == null:
		waiting.emit("Loading the island…")
		return
	var n := 0
	while inbox.has(step) and n < MAX_CATCHUP:
		var cmds: Array = inbox[step]
		inbox.erase(step)
		_run(cmds)
		n += 1
	waiting.emit("" if inbox.has(step) or n > 0 or _clock - float(heard.get(1, _clock)) < 1.0 else "Waiting for the host…")


func _on_message(from: int, m: Dictionary) -> void:
	heard[from] = _clock
	if is_host and gone.has(seat_of.get(from, 0)) and game.seats.has(seat_of[from]):   # only quiet for a while
		var o: int = seat_of[from]
		gone.erase(o)
		acked[from] = int(m.get("s", acked.get(from, step))) if m.get("t") == "ack" else acked.get(from, step)
		net.announce("%s is back." % names.get(o, "A player"))
		note.emit("%s is back." % names.get(o, "A player"))
		NetSession.log_line("%s is back after a quiet spell" % names.get(o, "A player"))
		_resume_if_all_back()
	match str(m.get("t", "")):
		"go":
			if not is_host and int(m.s) >= step:
				inbox[int(m.s)] = m.get("c", [])
		"cmd":
			if is_host and m.get("cmd") is Dictionary:
				_queue(m.cmd, from)
		"ack":
			if is_host:
				acked[from] = int(m.get("s", 0))
		"ready":
			if is_host:
				ready[from] = true
				acked[from] = step
		"sum":
			if is_host and sums.has(int(m.s)) and sums[int(m.s)] != int(m.h):
				resyncs += 1
				NetSession.log_line("%s fell out of step at step %d and was sent the game again (resync %d)" % [names.get(seat_of.get(from, 0), "A player"), int(m.s), resyncs])
				net.send_to(from, {"t": "resync", "save": game.save_text(), "s": step})
				note.emit("%s fell out of step and was sent the game again." % names.get(seat_of.get(from, 0), "A player"))
		"resync", "start":
			if not is_host and game != null:
				_load(str(m.save), int(m.s), int(m.get("seat", me)))
		"end":   # the host (or the server) ended the game
			if not is_host:
				ended.emit(str(m.get("why", "The game is over")))


# a player: the host's save at step s (a resync, or coming back after dropping out)
func _load(text: String, s: int, seat: int) -> void:
	var g := Game.load_text(text, game.world)
	if g == null:
		ended.emit("The host's game could not be loaded.")
		return
	g.on_toast = game.on_toast
	g.on_sfx = game.on_sfx
	g.on_dialog = game.on_dialog
	g.on_game_over = game.on_game_over
	me = seat
	_set_game(g)
	step = s
	for k in inbox.keys():
		if k < s:
			inbox.erase(k)
	resyncs += 1
	game_replaced.emit(g)
	net.send_to(1, {"t": "ack", "s": step})


func _on_closed(why: String) -> void:
	ended.emit(why)


## The host: end the game for everyone (they are told why); then stop().
func end_game(why: String) -> void:
	if is_host:
		net.send_all({"t": "end", "why": why})


## Leave the game (this player's choice, or the game ended).
func stop() -> void:
	if game != null:
		game.on_command = Callable()
	if net != null:
		net.leave()
