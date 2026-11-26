extends RefCounted
## The dedicated server (MpServer, docs/SERVER.md) over a real connection on this computer: the first player to join
## hosts the game; an optional password keeps others out; the host starts the game on the server and every copy
## stays in step; the host saves it on the server; a player who drops out is put to the host (wait, or the computer);
## when the host leaves, the next player hosts; the host ends the game and the server stops. Then a second server
## finds the interrupted game's autosave, offers it in the lobby, and the players pick their nations from it.
## Also the shared setup (MpSetup) a player hosting from their own copy uses: saving and loading with picks.

const PORT := 24611
const DIR := "user://test_server_saves"

var srv: MpServer
var clients := []          # NetSession
var L := {}                # session -> Lockstep (once the game reached them)
var got := {}              # session -> [message] (what the server told them, beyond the lockstep's own)
var quit_code := -99


func run() -> Array:
	var errs := []
	_wipe()
	errs.append_array(_setup_saves())
	errs.append_array(_server_game())
	errs.append_array(_resume())
	_wipe()
	return errs


# --- MpSetup: a host's own saves, picks and loading -----------------------------------------------------------
func _setup_saves() -> Array:
	var errs := []
	var g := Game.new_world("moss", "cormac", ["human", "moderate"], "center", {}, {}, {"name": "Hosts"}, "realm", [], {0: {"nation": {"name": "Ann's Bog"}, "race": "swamp"}})
	var ids := g.seat_ids()
	g.seat_names = {ids[0]: "Host", ids[1]: "Ann"}
	var nm := MpSetup.write_save(DIR, g)
	if nm == "" or MpSetup.read_save(DIR, nm) == "":
		return ["setup: a save was not written"]
	if MpSetup.read_save(DIR, "../" + nm) != "":
		errs.append("setup: a save name could reach outside the folder")
	var list := MpSetup.list_saves(DIR)
	if list.size() != 1 or not str(list[0].desc).contains("Ann's Bog"):
		errs.append("setup: the saves list is wrong: %s" % [list])
	var seats := MpSetup.save_seats(g)
	if seats.size() != 2 or int(seats[0].id) != Game.HOST:
		errs.append("setup: the save's nations are wrong: %s" % [seats])
	var players := {1: {"name": "Ann"}, 5: {"name": "Cy"}}
	var guess := MpSetup.guess_picks(seats, players)
	if guess.get(1) != ids[1] or guess.has(5):
		errs.append("setup: picks weren't guessed by name: %s" % [guess])
	if MpSetup.picks_why(seats, {1: ids[1], 5: ids[1]}, players) == "":
		errs.append("setup: two players could pick the same nation")
	if not MpSetup.picks_why(seats, {1: ids[1], 5: 0}, players).contains("Cy"):
		errs.append("setup: a player without a nation could start")
	if not MpSetup.picks_why(seats, {1: ids[1]}, {1: {"name": "Ann"}}).contains("first nation"):
		errs.append("setup: the first nation could be left without a player")
	var made := MpSetup.load_game(MpSetup.read_save(DIR, nm), {1: ids[1], 5: ids[0]}, players)
	if made.is_empty() or made[1].get(1) != ids[1] or made[1].get(5) != ids[0] or made[0].seat_names.get(ids[0]) != "Cy":
		errs.append("setup: a saved game didn't load with the picks")
	var made2 := MpSetup.load_game(MpSetup.read_save(DIR, nm), {5: ids[0]}, {5: {"name": "Cy"}})
	if made2.is_empty() or made2[0].seats.has(ids[1]) or not made2[0].nations.has(ids[1]):
		errs.append("setup: a nation nobody picked was not handed to the computer")
	MpSetup.delete_save(DIR, nm)
	return errs


# --- a game on the server ----------------------------------------------------------------------------------------
func _server_game() -> Array:
	var errs := []
	srv = MpServer.new()
	srv.on_quit = func(c): quit_code = c
	if srv.start(["--port=%d" % PORT, "--saves=" + DIR]) != "":
		return ["server: it didn't start"]
	if not srv.net.dedicated or not srv.net.players.is_empty():
		errs.append("server: it has a player of its own")
	var ann := _client("Ann", {"race": "realm", "color": 0, "nation": "Ann's Realm"})
	_run(func(): return ann.joined and srv.net.players.size() == 1 and ann.leader == ann.my_id, 4.0)
	if not ann.is_leader():
		return errs + ["server: the first player to join doesn't host the game"]
	var bo := _client("Bo", {"race": "swamp", "color": 1, "nation": "Bo's Bog"})
	var cy := _client("Cy", {"race": "wood", "color": 2, "nation": "Cy's Wood"})
	_run(func(): return srv.net.players.size() == 3 and bo.joined and cy.joined and bo.players.size() == 3, 4.0)
	if bo.is_leader() or cy.is_leader() or srv.net.leader != ann.my_id:
		errs.append("server: someone else hosts the game")
	# a password: newcomers need it
	ann.set_password("moss")
	_run(func(): return srv.net.password == "moss", 2.0)
	var dee := _client("Dee", {"race": "realm", "color": 3})
	var shut := []
	dee.closed.connect(func(why): shut.append(why))
	_run(func(): return not shut.is_empty(), 4.0)
	if shut.is_empty() or not str(shut[0]).contains("password"):
		errs.append("server: a player without the password got in (%s)" % [shut])
	clients.erase(dee)
	var dee2 := _client("Dee", {"race": "realm", "color": 3}, "moss")
	_run(func(): return dee2.joined and srv.net.players.size() == 4, 4.0)
	if srv.net.players.size() != 4:
		errs.append("server: the password didn't let Dee in")
	dee2.leave()
	clients.erase(dee2)
	_run(func(): return srv.net.players.size() == 3, 20.0)
	# only the host chooses: Bo's choices are ignored
	bo.send_to(1, {"t": "lset", "text": "Bo's island", "terms": "x"})
	ann.lead_info("Island: Classic, seed pine.", "pine")
	_run(func(): return bo.lobby_info == "Island: Classic, seed pine.", 3.0)
	if bo.lobby_info != "Island: Classic, seed pine.":
		errs.append("server: the host's choices didn't reach the players (%s)" % bo.lobby_info)
	# start: not before everyone is ready
	var o := {"seed": "pine", "slots": ["moderate", "moderate", "moderate", "closed", "closed", "closed", "closed"], "races": [], "start": "center", "map": {}}
	ann.send_to(1, {"t": "lstart", "o": o})
	_run(func(): return _heard(ann, "lnote") != {}, 3.0)
	if srv.lock != null or not str(_heard(ann, "lnote").get("text", "")).contains("ready"):
		errs.append("server: the game started before everyone was ready")
	bo.set_ready(true)
	cy.set_ready(true)
	_run(func(): return srv.net.all_ready(), 3.0)
	ann.send_to(1, {"t": "lstart", "o": o})
	_run(func(): return srv.lock != null and srv.lock.started and clients.all(func(c): return L.has(c) and L[c].game != null), 40.0)
	if srv.lock == null or not srv.lock.started:
		return errs + ["server: the game never started for everyone"]
	var hl: Lockstep = srv.lock
	if L[ann].me != Game.HOST or L[bo].me == Game.HOST or L[bo].me == L[cy].me:
		errs.append("server: the nations went to the wrong players (host %d, Bo %d, Cy %d)" % [L[ann].me, L[bo].me, L[cy].me])
	# orders from every player, in step
	_run(func(): return hl.step >= 40, 10.0)
	for c in clients:
		var G0: Game = L[c].game
		G0.do("train", ["capital", G0.capital, G0.trainable("capital", G0.capital)[0]])
	_run(func(): return hl.step >= 300, 30.0)
	_settle()
	for c in clients:
		var oo: int = L[c].me
		if hl.game.seats[oo].queues.values().all(func(q): return q.is_empty()) and hl.game.units.filter(func(u): return u.owner == oo).size() < 2:
			errs.append("server: %s's order never arrived" % c.my_name)
	errs.append_array(_same("after the first orders"))
	# the host saves on the server; a player who isn't hosting can't
	var before := MpSetup.list_saves(DIR).size()
	bo.send_to(1, {"t": "save_now"})
	ann.send_to(1, {"t": "save_now"})
	_run(func(): return MpSetup.list_saves(DIR).size() > before, 5.0)
	if MpSetup.list_saves(DIR).size() != before + 1:
		errs.append("server: the host's save wasn't kept (or Bo's was): %d saves, had %d" % [MpSetup.list_saves(DIR).size(), before])
	if MpSetup.read_save(DIR, MpSetup.AUTOSAVE) == "":
		errs.append("server: no autosave of the game in progress")
	# Bo drops out: the host is asked, and hands his nation to the computer
	var bo_nation: int = L[bo].me
	bo.leave()
	L.erase(bo)
	clients.erase(bo)
	_run(func(): return _heard(ann, "ask_drop") != {}, 25.0)
	var ask := _heard(ann, "ask_drop")
	if ask.is_empty() or int(ask.o) != bo_nation or not ask.can_ai:
		errs.append("server: the host wasn't asked about Bo (%s)" % [ask])
	else:
		ann.send_to(1, {"t": "hand_over", "o": bo_nation})
		_run(func(): return hl.game.nations.has(bo_nation) and L[ann].game.nations.has(bo_nation), 5.0)
		if not hl.game.nations.has(bo_nation):
			errs.append("server: Bo's nation wasn't handed to the computer")
	L[ann].game.do("set_paused", [false])
	_run(func(): return not hl.game.paused and hl.step >= 500, 15.0)
	_settle()
	errs.append_array(_same("after the hand-over"))
	# the host leaves: Cy hosts now, and is asked about Ann's nation (it can only wait)
	var keep := MpSetup.read_save(DIR, MpSetup.AUTOSAVE)
	got[cy] = []
	ann.leave()
	L.erase(ann)
	clients.erase(ann)
	_run(func(): return srv.net.leader == cy.my_id and cy.is_leader() and _heard(cy, "ask_drop") != {}, 25.0)
	if srv.net.leader != cy.my_id or not cy.is_leader():
		errs.append("server: nobody took over hosting when Ann left")
	var ask2 := _heard(cy, "ask_drop")
	if ask2.is_empty() or int(ask2.o) != Game.HOST or ask2.can_ai:
		errs.append("server: the new host wasn't asked about Ann's nation, or could hand it to the computer (%s)" % [ask2])
	# the host ends the game: everyone is told, a last save is kept, the autosave goes, the server stops
	var ends := []
	L[cy].ended.connect(func(why): ends.append(why))
	var n_saves := MpSetup.list_saves(DIR).size()
	cy.send_to(1, {"t": "end_game"})
	_run(func(): return quit_code != -99 and not ends.is_empty(), 8.0)
	if ends.is_empty() or not str(ends[0]).contains("ended the game"):
		errs.append("server: Cy wasn't told the game ended (%s)" % [ends])
	if quit_code != 0:
		errs.append("server: it didn't stop after the game ended (%d)" % quit_code)
	if MpSetup.read_save(DIR, MpSetup.AUTOSAVE) != "":
		errs.append("server: the finished game's autosave was kept (a restart would offer it again)")
	if MpSetup.list_saves(DIR).size() != n_saves:   # (the autosave went, a last save came)
		errs.append("server: the finished game wasn't kept")
	for c in clients:
		c.leave()
	clients.clear()
	L.clear()
	# (for the next part: as if the server had crashed in the middle of the game)
	var f := FileAccess.open("%s/%s.json" % [DIR, MpSetup.AUTOSAVE], FileAccess.WRITE)
	f.store_string(keep)
	f.close()
	return errs


# --- a restarted server offers the interrupted game; the players pick their nations from it ------------------------
func _resume() -> Array:
	var errs := []
	quit_code = -99
	srv = MpServer.new()
	srv.on_quit = func(c): quit_code = c
	if srv.start(["--port=%d" % (PORT + 1), "--saves=" + DIR, "--password=fern"]) != "":
		return ["resume: the server didn't start"]
	if srv.net.lobby_save.is_empty() or str(srv.net.lobby_save.name) != MpSetup.AUTOSAVE:
		return ["resume: the interrupted game wasn't offered"]
	var seats: Array = srv.net.lobby_save.seats
	var cy := _client("Cy", {"race": "wood"}, "fern", PORT + 1)
	var eve := _client("Eve", {"race": "realm"}, "fern", PORT + 1)
	_run(func(): return srv.net.players.size() == 2 and eve.players.size() == 2 and not eve.lobby_save.is_empty(), 5.0)
	if eve.lobby_save.is_empty():
		return errs + ["resume: the players weren't told about the saved game"]
	var cy_old := int(seats.filter(func(s): return str(s.player) == "Cy")[0].id)
	if int(srv.net.players[cy.my_id].get("pick", 0)) != cy_old:
		errs.append("resume: Cy wasn't given back the nation he played")
	# Cy joined first, so he hosts. Eve tries Cy's nation (taken), then takes the first nation
	eve.pick(cy_old)
	_run(func(): return false, 0.5)
	if int(srv.net.players[eve.my_id].get("pick", 0)) == cy_old:
		errs.append("resume: Eve could take a nation Cy had picked")
	cy.send_to(1, {"t": "lstart", "o": {}})
	_run(func(): return _heard(cy, "lnote") != {}, 3.0)
	if srv.lock != null:
		errs.append("resume: it started with Eve's nation not picked")
	eve.pick(Game.HOST)
	eve.set_ready(true)
	_run(func(): return srv.net.all_ready() and int(srv.net.players[eve.my_id].get("pick", 0)) == Game.HOST, 3.0)
	got[cy] = []
	cy.send_to(1, {"t": "lstart", "o": {}})
	_run(func(): return srv.lock != null and srv.lock.started and clients.all(func(c): return L.has(c) and L[c].game != null), 30.0)
	if srv.lock == null or not srv.lock.started:
		return errs + ["resume: the saved game didn't start (%s)" % [_heard(cy, "lnote")]]
	if L[cy].me != cy_old or L[eve].me != Game.HOST:
		errs.append("resume: the players didn't get the nations they picked")
	var computer := seats.filter(func(s): return int(s.id) != cy_old and int(s.id) != Game.HOST)
	for s in computer:
		if not srv.lock.game.nations.has(int(s.id)):
			errs.append("resume: %s, which nobody picked, isn't played by the computer" % s.nation)
	_run(func(): return srv.lock.step >= 100, 10.0)
	_settle()
	errs.append_array(_same("in the carried-on game"))
	srv.finish("test over")
	_run(func(): return quit_code != -99, 5.0)
	for c in clients:
		c.leave()
	clients.clear()
	L.clear()
	return errs


# --- helpers -----------------------------------------------------------------------------------------------------
func _client(nm: String, nation: Dictionary, pw := "", port := PORT) -> NetSession:
	var s := NetSession.new(nm, nation)
	s.pw = pw
	got[s] = []
	s.message.connect(func(from, m): _on_msg(from, m, s))
	s.join("127.0.0.1:%d" % port)
	clients.append(s)
	return s


func _on_msg(_from: int, m: Dictionary, s: NetSession) -> void:
	if m.get("t") == "start" and not (L.has(s) and L[s].game != null):
		var lk := Lockstep.new(s, null, false, int(m.seat))
		L[s] = lk
		lk.loaded(Game.load_text(str(m.save), srv.lock.game.world), int(m.s))
	elif m.get("t") in ["ask_drop", "lnote", "saves", "drop_done"]:
		got[s].append(m)


# the last message of kind t a player heard (and forget the older ones), or {}
func _heard(s: NetSession, t: String) -> Dictionary:
	var hits: Array = got.get(s, []).filter(func(m): return m.get("t") == t)
	return hits[-1] if not hits.is_empty() else {}


func _same(when: String) -> Array:
	var errs := []
	var k: int = srv.lock.game.checksum()
	for s in L:
		if L[s].game != null and L[s].step == srv.lock.step and L[s].game.checksum() != k:
			errs.append("server: %s's copy differs from the server's %s" % [s.my_name, when])
	return errs


func _settle() -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		if srv.net != null:
			srv.net.poll(0.01)
		for s in clients:
			if s.peer != null:
				s.poll(0.01)
		for s in L:
			L[s].process(0.0)
		if L.keys().all(func(s): return L[s].game == null or L[s].step == srv.lock.step):
			return
		OS.delay_msec(2)


func _run(done: Callable, secs := 30.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000:
		srv.tick(0.05 if srv.lock != null else 0.01)
		for s in clients:
			if s.peer != null:
				s.poll(0.01)
		for s in L.keys():
			if L.has(s):
				L[s].process(0.05)
		if done.call():
			return
		OS.delay_msec(1)


func _wipe() -> void:
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute("%s/%s" % [DIR, f])
