class_name MpSetup
extends RefCounted
## Starting a multiplayer game, shared by a player who hosts from their own copy and by the dedicated server
## (MpServer): raising a new island from the lobby's choices, or loading a saved game with the nations the players
## picked from it, and keeping saved multiplayer games in a folder. No drawing, no network: the caller sends the game.


## A new island. o: the lobby's choices {seed, slots, races, start, map}; players: peer id -> {name, nation};
## host_pid: the player who plays the first nation (Game.HOST): the host, or on a server the player hosting the game.
## Everyone else takes the next slots, then the host's computer nations fill the rest. Returns [game, seat_of]
## (seat_of: peer id -> nation).
static func new_game(o: Dictionary, players: Dictionary, host_pid: int) -> Array:
	var ids := players.keys()
	ids.sort()
	var slots := []
	var humans := {}
	for pid in ids:
		if pid == host_pid:
			continue
		var n: Dictionary = players[pid].get("nation", {})
		humans[slots.size()] = {"race": str(n.get("race", "realm")), "leader": "" if str(n.get("leader", "random")) == "random" else str(n.get("leader", "")),
			"nation": {"name": str(n.get("nation", players[pid].name)), "color": int(n.get("color", 0)), "emblem": str(n.get("emblem", "crown")), "secondary": str(n.get("secondary", "#faf1dc"))},
			"pid": pid}
		slots.append("human")
	var cs: Array = o.get("slots", [])   # the host's computer nations, slot by slot (players take the first slots)
	var rs: Array = o.get("races", [])
	var races := []
	for i in 7:
		races.append("random" if i < slots.size() else (str(rs[i]) if i < rs.size() else "random"))
	for i in range(slots.size(), 7):
		slots.append(str(cs[i]) if i < cs.size() else "closed")
	var hn: Dictionary = players[host_pid].get("nation", {})
	var leader := "" if str(hn.get("leader", "random")) == "random" else str(hn.get("leader", ""))
	var g := Game.new_world(str(o.get("seed", "realm")), leader, slots, str(o.get("start", "center")), {}, o.get("map", {}),
		{"name": str(hn.get("nation", "My Realm")), "color": int(hn.get("color", 0)), "emblem": str(hn.get("emblem", "crown")), "secondary": str(hn.get("secondary", "#faf1dc"))},
		str(hn.get("race", "realm")), races, humans)
	var seat_of := {host_pid: Game.HOST}
	g.seat_names[Game.HOST] = str(players[host_pid].name)
	for i in humans:
		if humans[i].has("id"):
			seat_of[humans[i].pid] = humans[i].id
			g.seat_names[humans[i].id] = str(players[humans[i].pid].name)
	g.paused = false
	return [g, seat_of]


## The nations a player may pick in a saved game: every player nation still standing, the first one first.
## [{id, nation, race, player}] (player: who played it when it was saved).
static func save_seats(g: Game) -> Array:
	var out := []
	for o in g.seat_ids():
		if g.seats[o].get("fallen", false):
			continue
		out.append({"id": o, "nation": str(g.player_info(o).name), "race": g.race(o), "player": str(g.seat_names.get(o, ""))})
	return out


## Why the lobby can't start a saved game with these picks (peer id -> nation), or "".
static func picks_why(seats: Array, picks: Dictionary, players: Dictionary) -> String:
	var ids := seats.map(func(s): return int(s.id))
	var taken := {}
	for pid in players:
		var o := int(picks.get(pid, 0))
		if o == 0 or not ids.has(o):
			return "%s hasn't picked a nation from the saved game yet." % str(players[pid].name)
		if taken.has(o):
			return "%s and %s picked the same nation." % [taken[o], str(players[pid].name)]
		taken[o] = str(players[pid].name)
	if ids.has(Game.HOST) and not taken.has(Game.HOST):   # (the first nation can't be handed to the computer)
		var first: Dictionary = seats.filter(func(s): return int(s.id) == Game.HOST)[0]
		return "Someone has to play %s: the game's first nation can't be handed to the computer." % str(first.nation)
	return ""


## A saved game, carried on with the players' picks (peer id -> nation; check picks_why first). The nations nobody
## picked are played by the computer. Returns [game, seat_of], or [] when the save can't be read.
static func load_game(text: String, picks: Dictionary, players: Dictionary) -> Array:
	var g := Game.load_text(text)
	if g == null:
		return []
	var seat_of := {}
	for pid in picks:
		var o := int(picks[pid])
		if g.seats.has(o):
			seat_of[pid] = o
			g.seat_names[o] = str(players[pid].name) if players.has(pid) else str(g.seat_names.get(o, ""))
	var held: Array = seat_of.values()
	for o in g.seat_ids():
		if not held.has(o) and o != Game.HOST:
			g.hand_to_ai(o)
	g.paused = false
	return [g, seat_of]


## The nation each player probably wants in a saved game: the one they played when it was saved (by name).
static func guess_picks(seats: Array, players: Dictionary) -> Dictionary:
	var out := {}
	for pid in players:
		for s in seats:
			if str(s.player) == str(players[pid].name) and not out.values().has(int(s.id)):
				out[pid] = int(s.id)
	return out


## Two nations can't fly the same color or share a leader. Returns why not, or "".
static func clash(players: Dictionary) -> String:
	var colors := {}
	var leaders := {}
	for id in players:
		var P: Dictionary = players[id]
		var n: Dictionary = P.get("nation", {})
		var c := int(n.get("color", 0))
		if colors.has(c):
			return "%s and %s fly the same color: one of you picks another under Your Nation." % [colors[c], P.name]
		colors[c] = P.name
		var ld := str(n.get("leader", "random"))
		if ld != "random":
			if leaders.has(ld):
				return "%s and %s chose the same leader: one of you picks another under Your Nation." % [leaders[ld], P.name]
			leaders[ld] = P.name
	return ""


# --- saved multiplayer games: <dir>/<name>.json, with a one-line description in <name>.txt ---

const HOST_DIR := "user://mp_saves"
const AUTOSAVE := "autosave"   # the game in progress (the server picks it up again after a restart)


## Save g into dir. name: AUTOSAVE, or "" for a new name from the date. Returns the name, or "" when it failed.
static func write_save(dir: String, g: Game, name := "") -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	if name == "":
		name = "game-" + Time.get_datetime_string_from_system(false, false).replace("-", "").replace(":", "").replace("T", "-")
	var text := g.save_text()
	var f := FileAccess.open("%s/%s.json.tmp" % [dir, name], FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute("%s/%s.json.tmp" % [dir, name], "%s/%s.json" % [dir, name])   # (never half a save)
	var names := []
	for o in g.seat_ids():
		names.append("%s (%s)" % [str(g.player_info(o).name), str(g.seat_names.get(o, "?"))])
	var d := FileAccess.open("%s/%s.txt" % [dir, name], FileAccess.WRITE)
	if d != null:
		d.store_string("Seed %s, %d min in: %s" % [str(g.world.get("seed", "?")), int(g.t / 60.0), ", ".join(names)])
		d.close()
	return name


## The saved games in dir, newest first: [{name, when (unix time), desc}].
static func list_saves(dir: String) -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var nm := f.trim_suffix(".json")
		var p := "%s/%s" % [dir, f]
		var desc := ""
		if FileAccess.file_exists("%s/%s.txt" % [dir, nm]):
			desc = FileAccess.get_file_as_string("%s/%s.txt" % [dir, nm]).strip_edges()
		out.append({"name": nm, "when": FileAccess.get_modified_time(p), "desc": desc})
	out.sort_custom(func(a, b): return int(a.when) > int(b.when))
	return out


## A save's text, or "" (only plain names: nothing outside the folder).
static func read_save(dir: String, name: String) -> String:
	if name == "" or name.contains("/") or name.contains("\\") or name.contains(".."):
		return ""
	var p := "%s/%s.json" % [dir, name]
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""


static func delete_save(dir: String, name: String) -> void:
	for ext in [".json", ".txt"]:
		if FileAccess.file_exists("%s/%s%s" % [dir, name, ext]):
			DirAccess.remove_absolute("%s/%s%s" % [dir, name, ext])


## When a save was made, for the lobby: "2026-11-26 07:00".
static func when_text(unix: int) -> String:
	return Time.get_datetime_string_from_unix_time(unix).replace("T", " ").left(16)


## The lobby's line for a saved game.
static func save_label(s: Dictionary) -> String:
	var nm := "Autosave (the game in progress)" if str(s.name) == AUTOSAVE else "Saved %s" % when_text(int(s.when))
	return nm + ((" · " + str(s.desc)) if str(s.get("desc", "")) != "" else "")
