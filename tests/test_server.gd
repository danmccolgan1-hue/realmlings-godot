extends RefCounted
## The dedicated server (MpServer, docs/SERVER.md) over a real connection on this computer: the first player to join
## hosts the game; an optional password keeps others out; the host starts the game on the server and every copy
## stays in step; the host saves it on the server; a player who drops out is put to the host (wait, or the computer);
## the host removes a player from the lobby; when the host leaves, the next player hosts; the host ends the game and the server stops. Then a second server
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
	errs.append_array(_debug_rules())
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
	# a player hosting from their own copy removes someone too
	var h := NetSession.new("Host", {})
	h.host(PORT + 5, false)
	var al := NetSession.new("Al", {})
	al.join("127.0.0.1:%d" % (PORT + 5))
	var gone := []
	al.closed.connect(func(why): gone.append(why))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000 and h.players.size() < 2:
		h.poll(0.01); al.poll(0.01); OS.delay_msec(2)
	h.kick(al.my_id)
	h.kick(1)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000 and gone.is_empty():
		h.poll(0.01)
		if al.peer != null:
			al.poll(0.01)
		OS.delay_msec(2)
	if gone.is_empty() or h.players.size() != 1 or not h.players.has(1):
		errs.append("host: removing a player from the lobby didn't work (%s, %d players)" % [gone, h.players.size()])
	h.leave()
	return errs


# --- Settings → Debug in a multiplayer game ----------------------------------------------------------------------
func _debug_rules() -> Array:
	var errs := []
	var g := Game.new_world("fern", "cormac", ["human", "moderate"], "center", {}, {}, {"name": "Hosts"}, "realm", [], {0: {"nation": {"name": "Bog"}, "race": "swamp", "leader": "glurg"}})
	var ids := g.seat_ids()
	var a: int = ids[0]
	var b: int = ids[1]
	# not allowed: nobody's debug order does anything, the host's neither
	g.debug_ok = false
	var gold: int = g.in_seat(b, func(): return int(g.stock.gold))
	g.apply({"player": a, "type": "debug_resources", "args": []})
	if g.in_seat(b, func(): return int(g.stock.gold)) != gold or g.debug_cap != 0:
		errs.append("debug: it worked in a game whose lobby didn't allow it")
	g.debug_ok = true
	# +2000: every player; reveal: every player's fog
	var ga: int = g.in_seat(a, func(): return int(g.stock.gold))
	g.apply({"player": b, "type": "debug_resources", "args": []})
	if g.in_seat(a, func(): return int(g.stock.gold)) != ga + 2000 or g.in_seat(b, func(): return int(g.stock.gold)) != gold + 2000:
		errs.append("debug: +2000 didn't go to every player")
	g.apply({"player": b, "type": "debug_reveal", "args": [true]})
	for o in ids:
		if g.in_seat(o, func(): return g.visible.size()) < g.G.provs.size():
			errs.append("debug: the map wasn't revealed to nation %d" % o)
	# every technology: only the player who asked, in the school they chose
	var sw_schools: Array = g.in_seat(b, func(): return g.debug_schools())
	if not sw_schools.has("pyro") or sw_schools.has("life"):
		errs.append("debug: the Swampling's schools are wrong: %s" % [sw_schools])
	var a_gov: int = g.in_seat(a, func(): return g.tech.gov.done.size())
	g.apply({"player": b, "type": "debug_all_tech", "args": ["pyro"]})
	if g.in_seat(b, func(): return g.current_school()) != "pyro":
		errs.append("debug: the chosen school wasn't taken (%s)" % g.in_seat(b, func(): return g.current_school()))
	if g.in_seat(a, func(): return g.tech.gov.done.size()) != a_gov or g.in_seat(a, func(): return g.current_school()) != null:
		errs.append("debug: every technology reached a player who didn't ask")
	g.apply({"player": a, "type": "debug_all_tech", "args": ["pyro"]})   # (not a Realmling school: the first open one)
	if not g.in_seat(a, func(): return g.current_school()) in ["life", "death", "arcane"]:
		errs.append("debug: a school the race can't take was given")
	if g.in_seat(a, func(): return g.debug_schools()).size() != 1:
		errs.append("debug: a player with a school could choose another")
	# the lobby's switch: only the host's counts, and it reaches the players
	var h := NetSession.new("Host", {})
	h.host(PORT + 6, false)
	var al := NetSession.new("Al", {})
	al.join("127.0.0.1:%d" % (PORT + 6))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000 and h.players.size() < 2:
		h.poll(0.01); al.poll(0.01); OS.delay_msec(2)
	al.set_debug(true)
	h.set_debug(true)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000 and not al.debug_ok:
		h.poll(0.01); al.poll(0.01); OS.delay_msec(2)
	if not al.debug_ok:
		errs.append("debug: the host's Allows Debug didn't reach the players")
	al.leave()
	h.leave()
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
	# kicking: only the host may; Dee is told, is gone, and can't come back under that name
	bo.send_to(1, {"t": "lkick", "id": cy.my_id})
	_run(func(): return false, 0.3)
	if not srv.net.players.has(cy.my_id):
		errs.append("server: a player who isn't hosting removed someone")
	var kicked := []
	dee2.closed.connect(func(why): kicked.append(why))
	ann.kick(dee2.my_id)
	_run(func(): return not kicked.is_empty() and srv.net.players.size() == 3 and ann.players.size() == 3, 5.0)
	if kicked.is_empty() or not str(kicked[0]).contains("removed"):
		errs.append("server: Dee wasn't told she was removed (%s)" % [kicked])
	if srv.net.players.size() != 3:
		errs.append("server: Dee is still in the lobby after the host removed her")
	clients.erase(dee2)
	var dee3 := _client("Dee", {"race": "realm", "color": 3}, "moss")
	var back := []
	dee3.closed.connect(func(why): back.append(why))
	_run(func(): return not back.is_empty() or srv.net.players.size() == 4, 4.0)
	if srv.net.players.size() != 3 or back.is_empty():
		errs.append("server: Dee came back after being removed")
	clients.erase(dee3)
	ann.kick(ann.my_id)
	_run(func(): return false, 0.3)
	if not srv.net.players.has(ann.my_id):
		errs.append("server: the host removed themself")
	# only the host chooses: Bo's choices are ignored
	bo.send_to(1, {"t": "lset", "text": "Bo's island", "terms": "x"})
	bo.send_to(1, {"t": "ldebug", "on": true})
	ann.set_debug(true)
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
	if not hl.game.debug_ok or not L[bo].game.debug_ok:
		errs.append("server: the host's Allows Debug didn't reach the game")
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
	# Cy comes back after a drop: he is told it's a server (so his menu offers to end the game)
	var eve_seat: int = L[eve].me
	cy.leave()
	L.erase(cy)
	clients.erase(cy)
	var cy2 := _client("Cy", {"race": "wood"}, "fern", PORT + 1)
	_run(func(): return cy2.joined and cy2.dedicated, 6.0)
	if not cy2.dedicated:
		errs.append("resume: a player coming back to a game in progress wasn't told it's a server")
	# everyone leaves the game: after a while the server keeps it and asks to be started again (a fresh lobby)
	srv.idle_reset = 1.0
	for c in clients:
		c.leave()
	clients.clear()
	L.clear()
	_run(func(): return quit_code != -99, 30.0)
	if quit_code != MpServer.EXIT_RESTART:
		errs.append("resume: a game everyone left didn't send the server back to a new lobby (exit %d)" % quit_code)
	if MpSetup.read_save(DIR, MpSetup.AUTOSAVE) == "":
		errs.append("resume: the game everyone left wasn't kept")
	if eve_seat != Game.HOST:
		errs.append("resume: Eve's nation changed")
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
