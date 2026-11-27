class_name OnlinePorts
extends RefCounted
## Host online (0.19.3): find a game server on the online host (docs/SERVER.md: one server per port) whose lobby
## nobody is in yet. Every port is asked at once (a short "probe" message; nobody joins), and after a few seconds
## the answers are in: `free` lists the ports whose lobby is empty and not playing, in a random order. Call poll()
## every frame until `done`. No drawing here; the Multiplayer screen shows the result.

const HOST := "157.245.250.30"   # the Droplet (docs/HANDOFF_CLAUDE.md)
const PORTS := [24565, 24566, 24567, 24568, 24569]
const WAIT := 3.0                # seconds to wait for every server's answer

var address := HOST
var ports: Array = PORTS
var done := false
var free := []                   # ports with an empty lobby, shuffled
var answered := {}               # port -> {players, locked, version}
var _peers := {}                 # port -> ENetMultiplayerPeer
var _t := 0.0


## Ask every port of `addr` (the online host, unless a test points elsewhere).
func start(addr := HOST, port_list: Array = PORTS) -> void:
	address = addr
	ports = port_list
	done = false
	free = []
	answered = {}
	_t = 0.0
	for p in ports:
		var e := ENetMultiplayerPeer.new()
		if e.create_client(address, int(p)) == OK:
			_peers[int(p)] = {"peer": e, "asked": false}


func poll(dt: float) -> void:
	if done:
		return
	_t += dt
	for p in _peers.keys():
		var P: Dictionary = _peers[p]
		var e: ENetMultiplayerPeer = P.peer
		if answered.has(p) or P.get("dead", false):
			continue
		e.poll()
		if e.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:   # (no server there, or it hung up)
			P.dead = true
			continue
		if e.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and not P.asked:
			P.asked = true
			e.set_target_peer(1)
			e.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
			e.put_packet(var_to_bytes({"t": "probe"}))
		while e.get_available_packet_count() > 0:
			var m = bytes_to_var(e.get_packet())
			if m is Dictionary and str(m.get("t", "")) == "probe_ok":
				answered[p] = {"players": int(m.get("players", 0)), "locked": bool(m.get("locked", false)), "version": str(m.get("version", ""))}
				break
	if _t >= WAIT or _peers.keys().all(func(q): return answered.has(q) or _peers[q].get("dead", false)):
		_finish()


## The answers are in (or the time is up): the free ports, and every connection closed.
func _finish() -> void:
	done = true
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	for p in answered:
		var A: Dictionary = answered[p]
		if A.players == 0 and not A.locked and A.version == mine:
			free.append(p)
	free.shuffle()
	stop()


func stop() -> void:
	for p in _peers:
		_peers[p].peer.close()
	_peers.clear()


## Why no port is free, for the player (the servers that answered run another version, or none answered).
func why_none() -> String:
	var mine := str(ProjectSettings.get_setting("application/config/version", ""))
	var other: Array = answered.values().filter(func(A): return A.version != mine).map(func(A): return A.version)
	var s := "No ports available. Try hosting locally."
	if not other.is_empty() and other.size() == answered.size():
		s += " (The server runs version %s; you have %s.)" % [other[0], mine]
	return s
