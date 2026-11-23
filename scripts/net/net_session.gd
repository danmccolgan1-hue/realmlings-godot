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
var _gone_ids := {}            # host: peer ids whose connection has closed (nothing more is sent to them)


func _init(player_name := "Player", nation_info := {}) -> void:
	my_name = player_name.strip_edges().substr(0, 24) if player_name.strip_edges() != "" else "Player"
	nation = nation_info
	version = str(ProjectSettings.get_setting("application/config/version", ""))


## Host a lobby on PORT. With `upnp`, also ask the router to open the port (in the background).
func host(port := PORT, upnp := true) -> String:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		peer = null
		return "Can't open port %d (is another copy of the game hosting?)" % port
	is_host = true
	my_id = 1
	joined = true
	players = {1: {"name": my_name, "nation": nation, "ping": 0}}
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
	if is_host:
		players[1].name = my_name
		_broadcast_players()
	elif joined:
		_send(1, {"t": "name", "name": my_name})


func set_nation(n: Dictionary) -> void:
	nation = n
	if is_host:
		players[1].nation = n
		_broadcast_players()
	elif joined:
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
		_send(1, {"t": "hello", "name": my_name, "version": version, "nation": nation})
	while peer != null and peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var msg = bytes_to_var(peer.get_packet())
		if msg is Dictionary:
			_handle(from, msg)
	if peer == null:
		return
	if not is_host and st == MultiplayerPeer.CONNECTION_DISCONNECTED and my_id != 0:
		var why := "The host closed the game" if joined else "Couldn't connect"
		leave()
		closed.emit(why)
	_drop_gone()


func _handle(from: int, m: Dictionary) -> void:
	match str(m.get("t", "")):
		"hello":   # host: a player wants in
			if not is_host:
				return
			if str(m.get("version", "")) != version:
				_send(from, {"t": "refused", "why": "Different game versions: the host has %s, you have %s" % [version, m.get("version", "?")]})
				_kick_later(from)
				return
			var nm0 := str(m.get("name", "Player")).substr(0, 24)
			if locked and not reserved.has(nm0):
				_send(from, {"t": "refused", "why": "This game has already started"})
				_kick_later(from)
				return
			if locked:
				players[from] = {"name": nm0, "nation": m.get("nation", {}), "ping": 0}
				_send(from, {"t": "welcome", "id": from})
				_broadcast_players()
				rejoined.emit(from, nm0)
				return
			if players.size() >= MAX_PLAYERS:
				_send(from, {"t": "refused", "why": "The game is full (%d players)" % MAX_PLAYERS})
				_kick_later(from)
				return
			players[from] = {"name": str(m.get("name", "Player")).substr(0, 24), "nation": m.get("nation", {}), "ping": 0}
			_send(from, {"t": "welcome", "id": from})
			_broadcast_players()
			_relay_chat(0, "%s joined." % players[from].name)
		"welcome":
			joined = true
			my_id = int(m.get("id", my_id))
			status.emit("Connected.")
		"refused":
			var why := str(m.get("why", "The host refused"))
			leave()
			closed.emit(why)
		"players":
			players = {}
			for p in m.get("list", []):
				players[int(p.id)] = {"name": p.name, "nation": p.nation, "ping": p.ping}
			players_changed.emit()
		"nation":
			if is_host and players.has(from):
				players[from].nation = m.get("nation", {})
				_broadcast_players()
		"name":
			if is_host and players.has(from) and not locked:
				var nm := str(m.get("name", "Player")).strip_edges().left(24)
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
		list.append({"id": id, "name": players[id].name, "nation": players[id].nation, "ping": players[id].ping})
	players_changed.emit()
	for id in players:
		if id != 1:
			_send(id, {"t": "players", "list": list})


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
		_gone_ids[id] = true
		_broadcast_players()
		_relay_chat(0, "%s left." % nm)
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
