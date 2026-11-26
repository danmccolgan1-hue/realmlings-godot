class_name MpServer
extends Node
## The dedicated server: a copy of the game with no window and no nation of its own, which runs the lobby and the
## game's clock for everyone (docs/SERVER.md). Start it with
##   Realmlings.x86_64 --headless -- --server [--port=24565] [--password=secret] [--saves=/path/to/folder] [--name=Name]
## The first player to join hosts the game: they choose the island and the computer nations (or a saved game to
## carry on), may set a password, start the game, save it, and decide about players who drop out. If they leave,
## the next player to have joined takes over. The game is saved every minute of play; after a crash or a restart
## the server offers it again in the lobby. When the game ends (the host ends it, or no player's nation is left
## standing), the server saves it and stops.

const AUTOSAVE_EVERY := 60.0   # seconds of play between saves

var net: NetSession
var lock: Lockstep
var dir := "user://server_saves"
var port := NetSession.PORT
var done := false              # the game is over: the server is stopping
var quit_t := -1.0
var next_save := AUTOSAVE_EVERY
var asks := {}                 # nation -> name: players who dropped out, waiting for the host's decision
var asked_to := {}             # nation -> peer id the question went to
var on_quit: Callable          # (tests: called instead of quitting)
var _check_t := 0.0


func _ready() -> void:
	var w := start(Array(OS.get_cmdline_user_args()))
	if w != "":
		_quit(1)


## Start listening. args: the command line's own arguments (--port=, --password=, --saves=, --name=). Returns why it
## couldn't, or "".
func start(args: Array) -> String:
	var nm := "Realmlings server"
	var pw := ""
	for a in args:
		a = str(a)
		if a.begins_with("--port="):
			port = int(a.substr(7))
		elif a.begins_with("--password="):
			pw = a.substr(11)
		elif a.begins_with("--saves="):
			dir = a.substr(8)
		elif a.begins_with("--name="):
			nm = a.substr(7)
	DirAccess.make_dir_recursive_absolute(dir)
	net = NetSession.new(nm, {})
	var w := net.host(port, false, true)
	if w != "":
		say(w)
		net = null
		return w
	net.password = pw
	net.message.connect(_on_message)
	net.leader_changed.connect(_resend_asks)
	net.chat.connect(func(who, text): print(("%s: %s" % [who, text]) if who != "" else text))   # (joins, departures, the lobby's chat)
	if MpSetup.read_save(dir, MpSetup.AUTOSAVE) != "":   # a game that was cut short (a crash, a restart): offer it again
		_choose_save(MpSetup.AUTOSAVE)
		say("Found an interrupted game: the lobby offers to carry it on.")
	say("Realmlings server %s: listening on UDP port %d%s. Saves in %s" % [net.version, port, " (password set)" if pw != "" else "", ProjectSettings.globalize_path(dir)])
	return ""


func _process(dt: float) -> void:
	tick(dt)


## Everything the server does in a frame (tests call it in a loop).
func tick(dt: float) -> void:
	if net == null:
		return
	net.poll(dt)
	if net == null:
		return
	if lock != null:
		lock.host_pid = net.leader
		lock.process(dt)
		if lock.started and lock.game.t >= next_save and not done:
			next_save = (floor(lock.game.t / AUTOSAVE_EVERY) + 1) * AUTOSAVE_EVERY
			MpSetup.write_save(dir, lock.game, MpSetup.AUTOSAVE)
		_check_t -= dt
		if _check_t <= 0.0:
			_check_t = 1.0
			_check_asks()
			_check_end()
	if quit_t >= 0.0:
		quit_t -= dt
		if quit_t < 0.0:
			_quit(0)


## A line in the server's output and its log.
func say(text: String) -> void:
	print(text)
	NetSession.log_line(text)


func _on_message(from: int, m: Dictionary) -> void:
	if from != net.leader or done:
		return
	match str(m.get("t", "")):
		"lsaves":   # the host wants the list of saved games
			net.send_to(from, {"t": "saves", "list": MpSetup.list_saves(dir)})
		"lload":    # the host chose a saved game to carry on ("" for a new island)
			if lock == null:
				_choose_save(str(m.get("name", "")))
		"lupload":  # the host sent a saved game from their own computer
			if lock == null:
				var text := str(m.get("save", ""))
				var why := Game.save_why(text)
				var g := Game.load_text(text) if why == "" else null
				if g == null:
					net.send_to(from, {"t": "lnote", "text": why if why != "" else "That save can't be read."})
					return
				var nm := MpSetup.write_save(dir, g, "uploaded-" + Time.get_datetime_string_from_system(false, false).replace("-", "").replace(":", "").replace("T", "-"))
				say("%s uploaded a saved game (%s)" % [net.players[from].name, nm])
				_choose_save(nm)
		"lstart":
			_start(m.get("o", {}))
		"save_now":
			if lock != null and lock.started:
				var nm := MpSetup.write_save(dir, lock.game)
				net.send_to(from, {"t": "lnote", "text": "Saved on the server. Choose it under Load a saved game in the lobby to carry on." if nm != "" else "The game could not be saved on the server."})
				say("Saved the game as %s" % nm)
		"end_game":
			if lock != null:
				finish("%s ended the game." % str(net.players[from].name), true)
		"hand_over":
			var o := int(m.get("o", 0))
			if lock != null and asks.has(o):
				asks.erase(o)
				asked_to.erase(o)
				lock.hand_over(o)
		"wait":
			var o := int(m.get("o", 0))
			asks.erase(o)
			asked_to.erase(o)


# the lobby carries on saved game `name` ("" for a new island)
func _choose_save(name: String) -> void:
	if name == "":
		net.set_lobby_save({})
		net.lobby_terms = ""   # (the host's next summary of the island goes out again)
		return
	var text := MpSetup.read_save(dir, name)
	var g := Game.load_text(text) if text != "" and Game.save_why(text) == "" else null
	if g == null:
		if net.leader != 0:
			net.send_to(net.leader, {"t": "lnote", "text": "That saved game can't be read."})
		return
	var info: Dictionary = MpSetup.list_saves(dir).filter(func(s): return s.name == name)[0]
	net.set_lobby_save({"name": name, "desc": MpSetup.save_label(info), "seats": MpSetup.save_seats(g)})
	net.set_lobby_info("Carrying on a saved game: %s. Pick your nation from it." % MpSetup.save_label(info), "save:%s:%d" % [name, int(info.when)])


# the host pressed Start
func _start(o: Dictionary) -> void:
	if lock != null or net.players.is_empty():
		return
	var tell := func(t2: String): net.send_to(net.leader, {"t": "lnote", "text": t2})
	if not net.all_ready():
		tell.call("Not everyone is ready yet.")
		return
	var players := net.players.duplicate(true)
	var made: Array
	if net.lobby_save.is_empty():
		var why := MpSetup.clash(players)
		if why != "":
			tell.call(why)
			return
		if str(o.get("seed", "")).strip_edges() == "":
			o.seed = str(randi() % 100000)
		say("Raising a new island (seed %s) for %d player%s" % [o.seed, players.size(), "" if players.size() == 1 else "s"])
		net.send_all({"t": "lnote", "text": "Raising the world and its nations…"})
		made = MpSetup.new_game(o, players, net.leader)
	else:
		var picks := {}
		for pid in players:
			picks[pid] = int(players[pid].get("pick", 0))
		var why := MpSetup.picks_why(net.lobby_save.get("seats", []), picks, players)
		if why != "":
			tell.call(why)
			return
		say("Carrying on saved game %s" % net.lobby_save.name)
		made = MpSetup.load_game(MpSetup.read_save(dir, str(net.lobby_save.name)), picks, players)
		if made.is_empty():
			tell.call("That saved game can't be read.")
			return
	var g: Game = made[0]
	g.debug_ok = net.debug_ok   # (the lobby's Allows Debug)
	lock = Lockstep.new(net, g, true, Game.HOST)
	lock.host_pid = net.leader
	lock.ask_drop.connect(func(o2, nm): asks[o2] = nm)
	lock.resumed.connect(func():
		asks.clear()
		asked_to.clear()
		net.send_all({"t": "drop_done"}))
	lock.note.connect(say)
	lock.begin(made[1])
	MpSetup.write_save(dir, g, MpSetup.AUTOSAVE)
	next_save = (floor(g.t / AUTOSAVE_EVERY) + 1) * AUTOSAVE_EVERY
	say("The game has started.")


# who decides about a player who dropped out: the host, unless their own nation is the one away (then the next player)
func _decider() -> int:
	var ids := net.players.keys()
	ids.sort()
	if net.leader != 0:
		ids.erase(net.leader)
		ids.push_front(net.leader)
	for pid in ids:
		if lock.seat_of.has(pid) and not lock.gone.has(lock.seat_of[pid]) and not net.picking.has(pid):
			return pid
	return 0


# put the questions about dropped players to whoever decides (again, if that changed); drop those settled
func _check_asks() -> void:
	for o in asks.keys():
		if not lock.gone.has(o):   # (they came back, or someone took the nation)
			asks.erase(o)
			if asked_to.has(o):
				net.send_to(asked_to[o], {"t": "drop_done", "o": o})
			asked_to.erase(o)
	var d := _decider()
	if d == 0:
		return
	for o in asks:
		if asked_to.get(o, 0) != d:
			asked_to[o] = d
			net.send_to(d, {"t": "ask_drop", "o": o, "nm": asks[o], "can_ai": o != Game.HOST})


func _resend_asks() -> void:
	asked_to.clear()


# the game is over when no player's nation is left standing
func _check_end() -> void:
	if done or lock == null or not lock.started:
		return
	var standing := lock.game.seat_ids().filter(func(o): return not lock.game.seats[o].get("fallen", false))
	if standing.is_empty():
		finish("No player's nation is left standing: the game is over.")


## End the game: keep a last save (and forget the autosave, so a restart starts a new lobby), tell everyone, stop.
func finish(why: String, keep := true) -> void:
	if done:
		return
	done = true
	if keep and lock != null and lock.game != null:
		var nm := MpSetup.write_save(dir, lock.game)
		say("Kept the finished game as %s" % nm)
	MpSetup.delete_save(dir, MpSetup.AUTOSAVE)
	say(why + " The server is stopping.")
	if lock != null:
		lock.end_game(why + " The server has stopped.")
	quit_t = 3.0   # (time for the message to reach everyone)


func _quit(code: int) -> void:
	if net != null:
		net.leave()
	net = null
	if on_quit.is_valid():
		on_quit.call(code)
	elif is_inside_tree():
		get_tree().quit(code)
