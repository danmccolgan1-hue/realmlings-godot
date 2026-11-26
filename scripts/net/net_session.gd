class_name NetSession
extends RefCounted
## The multiplayer connection: one player hosts, up to 7 join, over the local network or the internet (ENet, UDP).
## It carries the lobby (who is in it, their nation, chat, ping, the check that everyone runs the same version) and,
## once the game starts, Lockstep's messages (`message`). After the start only players returning to their seat may
## join (`reserved` names). No drawing here; the Multiplayer screen and the game show it. Call poll() every frame.

signal players_changed
signal chat(from_name: String, text: String)
signal status(text: String)
signal closed(why: String)
signal message(from: int, m: Dictionary)   # anything the lobby doesn't handle itself (the game's lockstep)
signal left(id: int, name: String)          # host: a player's connection is gone
signal rejoined(id: int, name: String)      # host: a player came back to their seat after the start
signal seat_offer(choices: Array)           # a player joining a game in progress: the nations they may take (0.19)
signal take_seat(id: int, name: String, nation: int)   # host: a player joining a game in progress chose a nation
signal lobby_info_changed                   # the host's summary of the game everyone is agreeing to (0.19)
signal lobby_save_changed                   # the host chose a saved game to carry on (or a new island again)
signal leader_changed                       # a dedicated server: the player hosting the game changed

const PORT := 24565            # the game's port (UDP); forward this one on the host's router
const DISCOVER_PORT := 24566   # LAN games announce themselves here (UDP broadcast)
const MAX_PLAYERS := 8
const PING_EVERY := 2.0

var peer: ENetMultiplayerPeer
var is_host := false
var my_id := 0
var my_name := "Player"
var nation := {}               # this player's lobby choices: race, color, emblem, emblem color
var players := {}              # peer id -> {"name", "nation", "ping"}
var version := ""
var joined := false            # a client's handshake was answered
var _udp: PacketPeerUDP        # LAN announcements (host) or listening (anyone on the Multiplayer screen)
var _announce_t := 0.0
var _ping_t := 0.0
var lan_games := {}            # "ip:port" -> {"name", "players", "version", "ip", "port", "seen"}
var external := ""             # what UPnP found: the address friends use over the internet
var upnp_note := ""
var _thread: Thread
var locked := false            # the game has started: only `reserved` names (players coming back) may join
var reserved := {}             # name -> true
var _closed_ids := {}          # host: peer ids ENet reported as disconnected
var _gone_ids := {}            # host: peer ids whose connection has closed (nothing more is sent to them)
var lobby_terms := ""          # host: what lobby_info's game is (its readiness resets when this changes)
var lobby_info := ""           # the host's summary of the game (island, seed, computer nations); changing it un-readies everyone
var seat_choices: Callable     # host, game in progress: () -> [{id, nation, player, state}] the nations a newcomer may take
var picking := {}              # host: peer id -> true while a player joining a game in progress chooses a nation
var in_progress := false       # a player: the host's game has already started (hot-join)
## The dedicated server (MpServer): this session runs the game for everyone but plays no nation and is not in
## `players`. The player hosting the game (`leader`, the first to join) chooses the island, starts it, saves it and
## decides about players who drop out, through messages to the server. When a player hosts from their own copy,
## leader is 1: that player.
var dedicated := false
var leader := 1
var password := ""             # the host: the password a player must give to join ("" for none)
var pw := ""                   # a player: the password they give when joining
## The saved game the host chose to carry on: {"name", "desc", "seats": MpSetup.save_seats} ({} for a new island).
## Each player picks one of its nations (players[id].pick).
var lobby_save := {}
var kicked := {}               # the host: names (lower case) removed from this lobby, who may not join again

## ENet's timeouts (0.19): generous, so a few seconds of a busy computer (loading a save, an autosave) or a wobbly
## connection don't throw a player out. ENet's own default gives up after as little as 5 s.
const TIMEOUT_LIMIT := 64
const TIMEOUT_MIN_MS := 15000
const TIMEOUT_MAX_MS := 60000
const LOG_PATH := "user://mp_log.txt"


func _init(player_name := "Player", nation_info := {}) -> void:
	my_name = player_name.strip_edges().substr(0, 24) if player_name.strip_edges() != "" else "Player"
	nation = nation_info
	version = str(ProjectSettings.get_setting("application/config/version", ""))


## Host a lobby on PORT. With `upnp`, also ask the router to open the port (in the background). With `server`, the
## dedicated server: no player of its own (see `dedicated`).
func host(port := PORT, upnp := true, server := false) -> String:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		peer = null
		return "Can't open port %d (is another copy of the game hosting?)" % port
	is_host = true
	my_id = 1
	joined = true
	peer.peer_disconnected.connect(func(id): _closed_ids[id] = true)
	dedicated = server
	leader = 0 if server else 1
	players = {} if server else {1: {"name": my_name, "nation": nation, "ping": 0, "ready": true, "pick": 0}}
	log_line("%s on port %d (version %s)" % ["Server running" if server else "Hosting", port, version])
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", DISCOVER_PORT)
	if upnp:
		_thread = Thread.new()
		_thread.start(_open_port.bind(port))
	status.emit("Hosting on port %d. Friends on your network see this game in their list." % port)
	players_changed.emit()
	return ""


## Join a host by address ("192.168.1.20", "my.host.name", or "1.2.3.4:24565").
func join(address: String) -> String:
	var addr := address.strip_edges()
	var port := PORT
	if addr.count(":") == 1:
		port = int(addr.get_slice(":", 1))
		addr = addr.get_slice(":", 0)
	if addr == "":
		return "Type the host's address"
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, port)
	if err != OK:
		peer = null
		return "Can't reach %s" % address
	is_host = false
	log_line("Joining %s:%d as %s (version %s)" % [addr, port, my_name, version])
	status.emit("Connecting to %s:%d..." % [addr, port])
	return ""


## Listen for LAN games (the Multiplayer screen does this while open).
func listen_lan() -> void:
	if is_host or _udp != null:
		return
	_udp = PacketPeerUDP.new()
	if _udp.bind(DISCOVER_PORT) != OK:
		_udp = null


func leave() -> void:
	if peer != null:
		peer.close()
	peer = null
	if _udp != null:
		_udp.close()
	_udp = null
	players.clear()
	joined = false
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null


## A line in the multiplayer log (user://mp_log.txt, kept to its last 400 lines): who joined, left, was refused,
## dropped out or fell out of step, and why. For finding out why a player keeps losing the game.
static func log_line(text: String) -> void:
	var lines := []
	if FileAccess.file_exists(LOG_PATH):
		lines = Array(FileAccess.get_file_as_string(LOG_PATH).split("\n", false))
	lines.append("%s  %s" % [Time.get_datetime_string_from_system(false, true), text])
	if lines.size() > 400:
		lines = lines.slice(lines.size() - 400)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()


## The log's full path on this computer (to show the player where to find it).
static func log_path() -> String:
	return ProjectSettings.globalize_path(LOG_PATH)


## A player: ready (or not) to start. The host starts once every player is ready (0.19).
func set_ready(on: bool) -> void:
	if is_host:
		return
	if players.has(my_id):
		players[my_id].ready = on
	if joined:
		_send(1, {"t": "lready", "on": on})
	players_changed.emit()


## Is everyone but the host ready?
func all_ready() -> bool:
	for id in players:
		if id != leader and not players[id].get("ready", false):
			return false
	return true


## Is this player the one hosting the game (from their own copy, or on a server)?
func is_leader() -> bool:
	return joined and my_id != 0 and my_id == leader


## The host (or the player hosting on a server): a password for joining ("" for none). Players already in stay.
func set_password(p: String) -> void:
	if is_host:
		password = p.strip_edges()
		log_line("The password was %s" % ("set" if password != "" else "removed"))
	elif is_leader():
		_send(1, {"t": "lpass", "pw": p.strip_edges()})


## The host (or the player hosting on a server): the game everyone is agreeing to; see set_lobby_info.
func lead_info(text: String, terms := "") -> void:
	if is_host:
		set_lobby_info(text, terms)
	elif is_leader() and (text != lobby_info or terms != lobby_terms):
		lobby_terms = terms
		_send(1, {"t": "lset", "text": text, "terms": terms})


## The host: carry on a saved game (save: {name, desc, seats}), or a new island ({}). Each player then picks a nation
## from it (the one they played, when their name matches); everyone has to say they are ready again.
func set_lobby_save(save: Dictionary) -> void:
	if not is_host:
		return
	lobby_save = save.duplicate(true)
	for id in players:
		players[id].pick = 0
	if not save.is_empty():
		var guess := MpSetup.guess_picks(save.get("seats", []), players)
		for id in guess:
			players[id].pick = guess[id]
	for id in players:
		if id != leader:
			players[id].ready = false
	send_all({"t": "lsave", "save": lobby_save})
	lobby_save_changed.emit()
	_broadcast_players()


## The host (or the player hosting on a server): remove player id from the lobby. They are told, and may not join
## this lobby again under that name. Only before the game starts.
func kick(id: int) -> void:
	if is_host:
		_kick(id)
	elif is_leader():
		_send(1, {"t": "lkick", "id": id})


# the host: remove player id from the lobby
func _kick(id: int) -> void:
	if locked or not players.has(id) or id == leader or (id == 1 and not dedicated):
		return
	var nm := str(players[id].name)
	kicked[nm.to_lower()] = true
	_refuse(id, nm, "The host removed you from the lobby.")
	players.erase(id)
	picking.erase(id)
	_gone_ids[id] = true
	log_line("The host removed %s from the lobby" % nm)
	_relay_chat(0, "%s was removed by the host." % nm)
	_broadcast_players()


## A player: take nation o of the saved game the host chose (0: none).
func pick(o: int) -> void:
	if is_host:
		_pick(my_id, o)
	elif joined:
		_send(1, {"t": "lpick", "o": o})


# the host: player id picks nation o of the saved game, if nobody else has it
func _pick(id: int, o: int) -> void:
	if not players.has(id) or lobby_save.is_empty() or locked:
		return
	var ok: bool = o == 0 or lobby_save.get("seats", []).any(func(s): return int(s.id) == o)
	for other in players:
		if other != id and int(players[other].get("pick", 0)) == o and o != 0:
			ok = false
	if ok:
		players[id].pick = o
		if id != leader:
			players[id].ready = false
	_broadcast_players()


# a dedicated server: the player hosting the game is the first to have joined who is still here
func _update_leader() -> void:
	if not dedicated:
		return
	var was := leader
	if not players.has(leader):
		var ids := players.keys()
		ids.sort()
		leader = ids[0] if not ids.is_empty() else 0
	if leader != was:
		if leader != 0:
			players[leader].ready = true
			log_line("%s is now hosting the game" % players[leader].name)
			_relay_chat(0, "%s is now hosting the game." % players[leader].name)
		leader_changed.emit()


## Host: the game everyone is agreeing to. When it changes, everyone has to say they are ready again.
## terms: what the players agree to (the island, the computer nations); only a change of terms un-readies them, not
## a change of the text alone (another player joining).
func set_lobby_info(text: String, terms := "") -> void:
	if not is_host or (text == lobby_info and terms == lobby_terms):
		return
	var changed := terms != lobby_terms
	lobby_info = text
	lobby_terms = terms
	if changed:
		for id in players:
			if id != 1:
				players[id].ready = false
	send_all({"t": "linfo", "text": text})
	_broadcast_players()
	lobby_info_changed.emit()


## A player joining a game in progress takes nation o (one of the seat_offer choices).
func choose_seat(o: int) -> void:
	_send(1, {"t": "take_seat", "o": o})


# ENet's timeouts on one connection (see TIMEOUT_LIMIT)
func _patient(id: int) -> void:
	if peer == null:
		return
	var p := peer.get_peer(id)
	if p != null:
		p.set_timeout(TIMEOUT_LIMIT, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)


## A name nobody else in the lobby has: "Player" becomes "Player 2" if there is already a Player.
func _unique_name(nm: String, from: int) -> String:
	var taken := {}
	for id in players:
		if id != from:
			taken[str(players[id].name).to_lower()] = true
	if not taken.has(nm.to_lower()):
		return nm
	var n := 2
	while taken.has(("%s %d" % [nm, n]).to_lower()):
		n += 1
	return ("%s %d" % [nm.left(21), n])


func send_chat(text: String) -> void:
	var tx := text.strip_edges().substr(0, 200)
	if tx == "" or peer == null:
		return
	if is_host:
		_relay_chat(1, tx)
	else:
		_send(1, {"t": "chat", "text": tx})


## This player's name in the lobby (Steam will give its own name, once the game is on Steam).
func set_name(nm: String) -> void:
	my_name = nm.strip_edges().left(24) if nm.strip_edges() != "" else "Player"
	if is_host and dedicated:
		return
	if is_host:
		players[1].name = my_name
		_broadcast_players()
	elif joined:
		_send(1, {"t": "name", "name": my_name})


func set_nation(n: Dictionary) -> void:
	nation = n
	if is_host and dedicated:
		return
	if is_host:
		players[1].nation = n
		_broadcast_players()
	elif joined:
		if players.has(my_id):
			players[my_id].ready = false   # (a changed nation: ready again when you are)
		_send(1, {"t": "nation", "nation": n})


## Read the network; call every frame (or in a loop in tests).
func poll(dt := 0.016) -> void:
	_lan(dt)
	if peer == null:
		return
	peer.poll()
	if is_host:
		_ping_t += dt
		if _ping_t >= PING_EVERY:
			_ping_t = 0.0
			for id in players:
				if id != 1:
					_send(id, {"t": "ping", "at": Time.get_ticks_msec()})
	var st := peer.get_connection_status()
	if not is_host and st == MultiplayerPeer.CONNECTION_CONNECTED and my_id == 0:
		my_id = peer.get_unique_id()
		_patient(1)
		_send(1, {"t": "hello", "name": my_name, "version": version, "nation": nation, "pw": pw})
	while peer != null and peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var msg = bytes_to_var(peer.get_packet())
		if msg is Dictionary:
			_handle(from, msg)
	if peer == null:
		return
	if not is_host and st == MultiplayerPeer.CONNECTION_DISCONNECTED and my_id != 0:
		var why := "The connection to the host was lost (the host left, or nothing came through for a while)" if joined else "Couldn't connect: check the address, that the host's game is open, and that UDP port %d is open on the host's router and firewall" % PORT
		log_line("Disconnected: " + why)
		leave()
		closed.emit(why)
	_drop_gone()


func _handle(from: int, m: Dictionary) -> void:
	match str(m.get("t", "")):
		"hello":   # host: a player wants in
			if not is_host:
				return
			_patient(from)
			var nm0 := str(m.get("name", "Player")).strip_edges().substr(0, 24)
			if nm0 == "":
				nm0 = "Player"
			if str(m.get("version", "")) != version:
				_refuse(from, nm0, "Different game versions: the host has %s, you have %s. Both of you need the same version." % [version, m.get("version", "?")])
				return
			if kicked.has(nm0.to_lower()) and not locked:
				_refuse(from, nm0, "The host removed you from this lobby.")
				return
			if password != "" and str(m.get("pw", "")) != password:
				_refuse(from, nm0, "This game needs a password: type it under Password and join again." if str(m.get("pw", "")) == "" else "Wrong password.")
				return
			if locked and reserved.has(nm0):   # coming back to their own nation
				players[from] = {"name": nm0, "nation": m.get("nation", {}), "ping": 0, "ready": true, "pick": 0}
				_send(from, {"t": "welcome", "id": from, "locked": true})
				_update_leader()
				_broadcast_players()
				log_line("%s is coming back to their nation" % nm0)
				rejoined.emit(from, nm0)
				return
			if locked:   # 0.19: hot-join: a newcomer may take a nation whose player is away or was handed to the computer
				var choices: Array = seat_choices.call() if seat_choices.is_valid() else []
				if choices.is_empty():
					_refuse(from, nm0, "This game has already started and every nation has a player. (Coming back? Join with the same name you played under.)")
					return
				nm0 = _unique_name(nm0, from)
				players[from] = {"name": nm0, "nation": m.get("nation", {}), "ping": 0, "ready": true, "pick": 0}
				picking[from] = true
				_update_leader()
				_send(from, {"t": "welcome", "id": from, "locked": true, "name": nm0})
				_send(from, {"t": "pick_seat", "choices": choices})
				log_line("%s joined the game in progress and is choosing a nation" % nm0)
				return
			if players.size() >= MAX_PLAYERS:
				_refuse(from, nm0, "The game is full (%d players)" % MAX_PLAYERS)
				return
			nm0 = _unique_name(nm0, from)   # 0.19: two players named alike would be mixed up (seats are kept by name)
			players[from] = {"name": nm0, "nation": m.get("nation", {}), "ping": 0, "ready": false, "pick": 0}
			_send(from, {"t": "welcome", "id": from, "name": nm0, "server": dedicated})
			if lobby_info != "":
				_send(from, {"t": "linfo", "text": lobby_info})
			if not lobby_save.is_empty():
				_send(from, {"t": "lsave", "save": lobby_save})
				var guess := MpSetup.guess_picks(lobby_save.get("seats", []), {from: players[from]})
				if guess.has(from) and players.keys().any(func(o2): return o2 != from and int(players[o2].get("pick", 0)) == int(guess[from])):
					guess.erase(from)   # (somebody already picked it)
				players[from].pick = int(guess.get(from, 0))
			_update_leader()
			_broadcast_players()
			_relay_chat(0, "%s joined." % players[from].name)
			log_line("%s joined the lobby" % nm0)
		"take_seat":   # host: a player joining a game in progress chose their nation
			if is_host and picking.has(from) and players.has(from):
				picking.erase(from)
				_broadcast_players()
				take_seat.emit(from, str(players[from].name), int(m.get("o", 0)))
		"pick_seat":
			if not is_host:
				seat_offer.emit(m.get("choices", []))
		"lready":
			if is_host and players.has(from):
				players[from].ready = bool(m.get("on", false))
				_broadcast_players()
		"lpick":
			if is_host:
				_pick(from, int(m.get("o", 0)))
		"lsave":
			if not is_host:
				lobby_save = m.get("save", {})
				lobby_terms = ""   # (the host's next summary of a new island goes out again)
				lobby_save_changed.emit()
		"lset":   # a server: the player hosting the game changed its choices
			if is_host and dedicated and from == leader and not locked:
				set_lobby_info(str(m.get("text", "")), str(m.get("terms", "")))
		"lkick":   # a server: the player hosting removes someone from the lobby
			if is_host and dedicated and from == leader:
				_kick(int(m.get("id", 0)))
		"lpass":
			if is_host and dedicated and from == leader:
				set_password(str(m.get("pw", "")))
				_relay_chat(0, "The host %s the password." % ("set" if password != "" else "removed"))
		"linfo":
			if not is_host:
				lobby_info = str(m.get("text", ""))
				lobby_info_changed.emit()
		"welcome":
			joined = true
			my_id = int(m.get("id", my_id))
			in_progress = bool(m.get("locked", false))
			dedicated = bool(m.get("server", dedicated))
			if m.has("name") and str(m.name) != my_name:   # (the host renamed you: someone already had your name)
				my_name = str(m.name)
				status.emit("Connected. Someone already had your name, so you are %s." % my_name)
			else:
				status.emit("Connected. The game is already under way: loading it…" if in_progress else "Connected.")
			log_line("Connected to the host as %s%s" % [my_name, " (game in progress)" if in_progress else ""])
		"refused":
			var why := str(m.get("why", "The host refused"))
			log_line("Refused by the host: " + why)
			leave()
			closed.emit(why)
		"players":
			players = {}
			for p in m.get("list", []):
				players[int(p.id)] = {"name": p.name, "nation": p.nation, "ping": p.ping, "ready": p.get("ready", false), "pick": int(p.get("pick", 0))}
			var ld := int(m.get("leader", 1))
			if ld != leader:
				leader = ld
				leader_changed.emit()
			players_changed.emit()
		"nation":
			if is_host and players.has(from):
				players[from].nation = m.get("nation", {})
				players[from].ready = false
				_broadcast_players()
		"name":
			if is_host and players.has(from) and not locked:
				var nm := _unique_name(str(m.get("name", "Player")).strip_edges().left(24), from)
				players[from].name = nm if nm != "" else "Player"
				_broadcast_players()
		"chat":
			if is_host:
				if players.has(from):
					_relay_chat(from, str(m.get("text", "")).substr(0, 200))
			else:
				chat.emit(str(m.get("name", "")), str(m.get("text", "")))
		"ping":
			_send(1, {"t": "pong", "at": m.get("at", 0)})
		"pong":
			if is_host and players.has(from):
				players[from].ping = Time.get_ticks_msec() - int(m.get("at", 0))
				_broadcast_players()
		_:
			message.emit(from, m)


# turn a player away, telling them why (and keeping it in the log)
func _refuse(id: int, nm: String, why: String) -> void:
	log_line("Turned %s away: %s" % [nm, why])
	_send(id, {"t": "refused", "why": why})
	_kick_later(id)


# drop a player once the reason has reached them
func _kick_later(id: int) -> void:
	var p := peer.get_peer(id)
	if p != null:
		p.peer_disconnect_later()


func _relay_chat(from: int, text: String) -> void:
	var nm: String = players[from].name if players.has(from) else ""
	chat.emit(nm, text)
	for id in players:
		if id != 1:
			_send(id, {"t": "chat", "name": nm, "text": text})


func _broadcast_players() -> void:
	var list := []
	for id in players:
		list.append({"id": id, "name": players[id].name, "nation": players[id].nation, "ping": players[id].ping, "ready": players[id].get("ready", id == leader), "pick": int(players[id].get("pick", 0))})
	players_changed.emit()
	for id in players:
		if id != 1:
			_send(id, {"t": "players", "list": list, "leader": leader})


func _drop_gone() -> void:
	if not is_host:
		return
	var gone := []
	for id in players:
		if id != 1 and not _connected(id):
			gone.append(id)
	for id in gone:
		var nm: String = players[id].name
		players.erase(id)
		picking.erase(id)
		_gone_ids[id] = true
		log_line("%s's connection closed (they left, or nothing came through for %d s)" % [nm, TIMEOUT_MIN_MS / 1000])
		_broadcast_players()
		_relay_chat(0, "%s left." % nm)
		_update_leader()
		left.emit(id, nm)


## A message to one player (the host is 1).
func send_to(id: int, m: Dictionary) -> void:
	_send(id, m)


## A message from the host to every other player.
func send_all(m: Dictionary) -> void:
	for id in players:
		if id != 1:
			_send(id, m)


## A chat line from the game itself (a player dropped, came back...), to everyone.
func announce(text: String) -> void:
	if is_host:
		_relay_chat(0, text)


func _connected(id: int) -> bool:
	if _closed_ids.has(id):   # (asking ENet about a connection it has already let go of logs an error)
		return false
	var p := peer.get_peer(id)
	return p != null and p.get_state() == ENetPacketPeer.STATE_CONNECTED


func _send(to: int, m: Dictionary) -> void:
	if peer == null or _gone_ids.has(to):
		return
	peer.set_target_peer(to)
	peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	peer.put_packet(var_to_bytes(m))


# --- LAN: the host announces its game every second; everyone else lists what they hear ---
func _lan(dt: float) -> void:
	if _udp == null:
		return
	if is_host:
		_announce_t -= dt
		if _announce_t <= 0:
			_announce_t = 1.0
			_udp.put_packet(var_to_bytes({"game": "realmlings", "name": my_name, "players": players.size(), "version": version, "port": PORT}))
		return
	var now := Time.get_ticks_msec() / 1000.0
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var m = bytes_to_var(pkt)
		if m is Dictionary and m.get("game") == "realmlings":
			var key := "%s:%d" % [ip, int(m.get("port", PORT))]
			lan_games[key] = {"name": str(m.get("name", "")), "players": int(m.get("players", 1)), "version": str(m.get("version", "")),
				"ip": ip, "port": int(m.get("port", PORT)), "seen": now}
	for k in lan_games.keys():
		if now - lan_games[k].seen > 4.0:
			lan_games.erase(k)


# --- the internet: ask the router to open the port (UPnP), and learn the address friends should use ---
func _open_port(port: int) -> void:
	var u := UPNP.new()
	if u.discover(2000, 2) != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
		upnp_note = "Your router didn't answer for automatic port opening (UPnP). Forward UDP port %d to this computer, or use a virtual LAN (see the multiplayer plan)." % port
		return
	var r := u.add_port_mapping(port, port, "Realmlings", "UDP")
	external = u.query_external_address()
	if r == UPNP.UPNP_RESULT_SUCCESS:
		upnp_note = "Port %d opened on your router. Friends over the internet join %s" % [port, external]
	else:
		upnp_note = "Your router refused to open port %d automatically. Forward UDP port %d to this computer; friends then join %s" % [port, port, external]
