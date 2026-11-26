class_name Quests
extends RefCounted
## Quests, relics, dig sites, Reliquaries and chests (Godot only: not in the web game). The catalog is
## data/quests.json (written by hand); the state lives on the Game (quests_on, quest_pick, digs, chests, star_next,
## each human nation's quest_log, a unit's `bag`, a Reliquary's `items`) so it is saved and copied like the rest.
## Rules only; never draws. Every random draw comes from its own seeded stream, so every copy of a game agrees.
##
## Sessions 1–2 of docs/QUESTS_PLAN.md: the catalog, choosing quests, placing dig sites, Reliquaries, carrying and
## chests. Digging, Fallen Stars, the quest engine, gear, spells and Dungeons come later.

const PATH := "res://data/quests.json"
const RELIQUARY := "reliquary"
const STAR_FX_TIME := 3.0   # how long a falling star shows (the view's shooting star)

static var _data := {}


## The whole catalog (read once).
static func data() -> Dictionary:
	if _data.is_empty():
		var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = j if j is Dictionary else {"QUESTS": {}, "ITEMS": {}}
	return _data


## A catalog constant: RARITY_CHANCE, CARRY, RELIQUARY_SLOTS, STAR_FIRST, STAR_NEXT, PICK, BUILD_DEFS...
static func c(name: String):
	return data().get(name)


static func quest(id: String):
	return data().QUESTS.get(id)


static func item(id: String):
	return data().ITEMS.get(id)


static func item_name(id: String) -> String:
	var it = item(id)
	return str(it.name) if it != null else id


static func carry() -> int:
	return int(c("CARRY"))


static func slots() -> int:
	return int(c("RELIQUARY_SLOTS"))


# ---------------------------------------------------------------------------------------------------------------
# a new map: which quests, and where their relics lie buried

## The quests of a map with this seed: one of each single group, then two of "spell" and "arms" together.
## (PICK: [[groups, how many], ...]; groups joined with "|" share their draw.)
static func pick(seed: String) -> Array:
	var r := Mulberry32.from_string(seed + ":quests")
	var out := []
	for row in c("PICK"):
		var groups := Array(str(row[0]).split("|"))
		var pool := []
		for id in _sorted_ids():
			if str(quest(id).group) in groups:
				pool.append(id)
		r.shuffle(pool)
		out.append_array(pool.slice(0, mini(int(row[1]), pool.size())))
	return out


static func _sorted_ids() -> Array:
	var ids: Array = data().QUESTS.keys()
	ids.sort()
	return ids


## Where nothing is buried: the unique provinces and the bosses' (with their neighbors), capitals, the Intact Ruins.
static func dig_ban(g) -> Dictionary:
	var out: Dictionary = g.uq_skip()
	for p in g.buildings:
		if g.buildings[p].stage == 2:
			out[p] = true
	for p in g.finds:
		out[p] = true
	return out


## The hidden dig sites of the chosen quests' items, one relic to a province (as many as there are provinces).
## digs: province -> {item, shown (uncovered by a survey: seen by anyone with vision), star (a Fallen Star)}
static func place_digs(g, picked: Array) -> void:
	var ban := dig_ban(g)
	var pool := []
	for i in g.world.provinces.size():
		if not ban.has(i) and not g.digs.has(i):
			pool.append(i)
	Mulberry32.from_string(str(g.world.seed) + ":digs").shuffle(pool)
	var ids: Array = data().ITEMS.keys()
	ids.sort()
	for qid in picked:
		for id in ids:
			var it: Dictionary = item(id)
			if str(it.quest) != qid:
				continue
			for _k in int(it.sites):
				if pool.is_empty():
					return
				g.digs[pool.pop_back()] = {"item": id, "shown": false, "star": false}


## A new full-map game's quests: chosen, buried, and the Reliquary on every human nation's build lists.
static func setup(g) -> void:
	g.quests_on = true
	g.quest_pick = pick(str(g.world.seed))
	place_digs(g, g.quest_pick)
	var sf: Array = c("STAR_FIRST")
	var r := Mulberry32.from_string(str(g.world.seed) + ":stars")
	g.star_next = float(sf[0]) + floor(r.next() * (float(sf[1]) - float(sf[0]) + 1.0))
	g.each_seat(func(): add_tables(g))


## The Reliquary on the current seat's tables (Races.apply builds them afresh, so it is called after that too).
static func add_tables(g) -> void:
	if not g.quests_on:
		return
	var D: Dictionary = c("BUILD_DEFS")
	for k in D:
		if not g.BUILD_DEFS.has(k):
			var d: Dictionary = D[k].duplicate(true)
			for f in ["name", "note", "blurb"]:
				if d.get(f) != null:
					d[f] = Races.words(str(d[f]), g.race())   # (the race's words: Swampstriders, Scouts...)
			var nm = c("BUILD_NAMES").get(g.race(), {}).get(k)
			if nm != null:
				d.name = nm
			# JSON numbers are floats: costs are whole numbers
			for part in ["cost", "upkeep"]:
				var cc: Dictionary = d.get(part, {})
				for r in cc:
					cc[r] = int(cc[r])
			d.variant = int(d.get("variant", 0))
			g.BUILD_DEFS[k] = d
		if not g.BUILD_ORDER.has(k):
			g.BUILD_ORDER.append(k)
	# the Mason's card: a free cell on its first page (the buildings that need no research)
	var M: String = Game.MASON
	if g.CMD.has(M):
		var used := {}
		for x in g.CMD[M]:
			used[int(x.cell)] = true
		for k in D:
			if g.CMD[M].any(func(x): return x.id == "build:" + k):
				continue
			for cell in range(1, Races.ADV_CELL):
				if not used.has(cell):
					g.CMD[M].append({"id": "build:" + k, "cell": cell, "key": ""})
					used[cell] = true
					break


# ---------------------------------------------------------------------------------------------------------------
# Reliquaries

## Nation o's Reliquaries, in province order: [{p, e}] (e: the building record; its `items` the relics inside).
static func reliquaries(g, o: int) -> Array:
	var ps: Array = g.extras.keys()
	ps.sort()
	var out := []
	for p in ps:
		if g.nation_of(p) != o:
			continue
		for e in g.extras[p]:
			if e.type == RELIQUARY:
				out.append({"p": p, "e": e})
	return out


## The relics in a Reliquary (read only: views call this too, and must not add fields to the state).
static func items_in(e: Dictionary) -> Array:
	var x = e.get("items")
	return x if x is Array else []


static func _items_rw(e: Dictionary) -> Array:
	if not (e.get("items") is Array):
		e["items"] = []
	return e["items"]


## The first of nation o's Reliquaries with an empty slot, or null.
static func room(g, o: int):
	for r in reliquaries(g, o):
		if items_in(r.e).size() < slots():
			return r.e
	return null


## Every relic in nation o's Reliquaries.
static func items_of(g, o: int) -> Array:
	var out := []
	for r in reliquaries(g, o):
		out.append_array(items_in(r.e))
	return out


## How many of relic `id` nation o keeps in its Reliquaries.
static func count(g, o: int, id: String) -> int:
	return items_of(g, o).filter(func(x): return x == id).size()


## Put a relic into one of nation o's Reliquaries; false when none has room.
static func deposit(g, o: int, id: String) -> bool:
	var e = room(g, o)
	if e == null:
		return false
	_items_rw(e).append(id)
	added(g, o, id)
	return true


## A relic has just reached nation o's Reliquary (the quest engine listens here: session 4).
static func added(_g, _o: int, _id: String) -> void:
	pass


## Take relics out of nation o's Reliquaries (a finished quest, a trade, a raid); how many were taken.
static func take(g, o: int, id: String, n := 1 << 30) -> int:
	var taken := 0
	for r in reliquaries(g, o):
		var list: Array = items_in(r.e)
		var i := list.size() - 1
		while i >= 0 and taken < n:
			if list[i] == id:
				list.remove_at(i)
				taken += 1
			i -= 1
	return taken


# ---------------------------------------------------------------------------------------------------------------
# carrying and chests

static func is_scout(g, u: Dictionary) -> bool:
	return u.kind == g.WAYFINDER


## What a unit carries (read only).
static func bag_of(u: Dictionary) -> Array:
	var b = u.get("bag")
	return b if b is Array else []


static func bag(u: Dictionary) -> Array:
	if not (u.get("bag") is Array):
		u["bag"] = []
	return u["bag"]


## A relic for nation o, found by unit u (or null) in province p: into a Reliquary with room, else u's bag, else a
## chest on the ground. Returns where it went: "reliquary", "bag" or "chest".
static func give(g, o: int, id: String, u, p: int) -> String:
	if deposit(g, o, id):
		return "reliquary"
	if u != null and is_scout(g, u) and bag(u).size() < carry():
		bag(u).append(id)
		return "bag"
	drop(g, p, [id])
	return "chest"


## Relics left on the ground in province p: a chest with a gold lock, for the first scouting unit to come by.
static func drop(g, p: int, ids: Array) -> void:
	if ids.is_empty() or p < 0:
		return
	if not g.chests.has(p):
		g.chests[p] = []
	g.chests[p].append_array(ids)


## A scouting unit is gone (killed, dismissed, its nation fallen): what it carried drops where it stood.
static func unit_lost(g, u: Dictionary) -> void:
	var b = u.get("bag")
	if b is Array and not b.is_empty():
		drop(g, int(u.prov), b.duplicate())
		b.clear()


## Buildings gone from province p (torn down, dismantled, shaken down, lost with the province): the relics in any
## Reliquary among them spill into a chest there.
static func extras_lost(g, p: int, list: Array) -> void:
	for e in list:
		if e is Dictionary and e.get("type") == RELIQUARY:
			var it: Array = items_in(e)
			if not it.is_empty():
				drop(g, p, it.duplicate())
				it.clear()


## A message for human nation o (computer nations get none).
static func tell(g, o: int, msg: String, warn := false) -> void:
	if g.seats.has(o):
		g.in_seat(o, func(): g.toast(msg, warn))


static func _where_text(where: String, u: Dictionary) -> String:
	if where == "reliquary":
		return "It goes into your Reliquary."
	if where == "bag":
		return "No Reliquary has room, so %s carries it." % u.name
	return "No Reliquary has room and %s can carry no more: it stays here in a chest." % u.name


## Every frame (not while paused): Fallen Stars, diggers who walked off, and scouting units opening the chests in
## the provinces they stand in.
static func step(g) -> void:
	step_stars(g)
	if not g.star_fx.is_empty():
		g.star_fx = g.star_fx.filter(func(f): return g.t - f.t0 < STAR_FX_TIME)
	for u in g.units:
		var dg = u.get("dig")
		if dg != null and (u.moving or u.prov != int(dg.prov) or not g.digs.has(int(dg.prov))):
			u["dig"] = null
	if g.chests.is_empty():
		return
	for u in g.units:
		if u.get("_gone", false) or not is_scout(g, u) or not g.chests.has(u.prov):
			continue
		if not g.is_nation(u.owner):
			continue
		var p: int = u.prov
		var list: Array = g.chests[p]
		g.chests.erase(p)
		var left := []
		var got := []
		for id in list:
			# (a full bag and no Reliquary room: the rest stays in the chest)
			if room(g, u.owner) == null and bag(u).size() >= carry():
				left.append(id)
				continue
			var where := give(g, u.owner, id, u, p)
			got.append([id, where])
		if not left.is_empty():
			g.chests[p] = left
		for x in got:
			tell(g, u.owner, "%s opens a chest in %s: %s. %s" % [u.name, g.prov_name(p), item_name(x[0]), _where_text(x[1], u)])
		if not got.is_empty() and g.seats.has(u.owner):
			g.in_seat(u.owner, func(): g.sfx("wn_ally", p))


## Every payday: diggers roll; what scouting units carry moves into a Reliquary as soon as one has room.
static func payday(g) -> void:
	dig_payday(g)
	for u in g.units:
		var b = u.get("bag")
		if not (b is Array) or b.is_empty() or u.get("_gone", false):
			continue
		var moved := 0
		while not b.is_empty() and room(g, u.owner) != null:
			deposit(g, u.owner, b.pop_front())
			moved += 1
		if moved:
			tell(g, u.owner, "%s's relic%s went into your Reliquary." % [u.name, "" if moved == 1 else "s"])


# ---------------------------------------------------------------------------------------------------------------
# what a player may see

## Whether the current seat sees the dig site in province p: an uncovered one where it has vision, a Fallen Star
## anywhere it has explored.
static func dig_seen(g, p: int) -> bool:
	var d = g.digs.get(p)
	if d == null:
		return false
	if d.get("star", false):
		return g.explored.has(p) or g.reveal_all
	return d.get("shown", false) and (g.visible.has(p) or g.reveal_all)


## Whether the current seat sees the chest in province p (where it has vision).
static func chest_seen(g, p: int) -> bool:
	return g.chests.has(p) and not g.chests[p].is_empty() and (g.visible.has(p) or g.reveal_all)


# ---------------------------------------------------------------------------------------------------------------
# digging (session 3): a survey uncovers a dig site; a scouting unit standing on one digs; every cycle it rolls the
# relic's rarity (common 20%, uncommon 10%, rare 5%) until the relic comes up

## A survey of province p by unit u: a hidden dig site there is uncovered (anyone with vision sees it from now on).
static func uncover(g, u: Dictionary) -> void:
	var p: int = u.prov
	var d = g.digs.get(p)
	if d == null or d.get("shown", false):
		return
	d["shown"] = true
	tell(g, u.owner, "%s found signs of something buried in %s: a dig site! Select a %s there and press Dig." % [u.name, g.prov_name(p), _scout_word(g, u.owner)])


static func _scout_word(g, o: int) -> String:
	return Races.words("Wayfinder", g.race(o))


## Why unit u can't dig where it stands ("" when it can).
static func dig_why(g, u: Dictionary) -> String:
	if not is_scout(g, u):
		return "Only scouting units dig"
	var d = g.digs.get(u.prov)
	if d == null or not (d.get("shown", false) or d.get("star", false)):
		return "No dig site here"
	if not d.get("star", false) and not g.in_seat(u.owner, func(): return g.visible.has(u.prov)) and g.seats.has(u.owner):
		return "No dig site here"
	if u.get("dig") != null:
		return "Already digging"
	if u.moving or u.survey != null:
		return "Stand still first"
	if u.get("build") != null:
		return "Busy"
	return ""


## Start digging (an order: Game.start_dig).
static func start_dig(g, u: Dictionary) -> bool:
	var why := dig_why(g, u)
	if why != "":
		tell(g, u.owner, why + ".", true)
		return false
	u["dig"] = {"prov": u.prov, "n": 0, "t0": g.t}
	u.surveyQueue = []
	u.pendingSurvey = -1
	u.autoWalk = null
	tell(g, u.owner, "%s starts digging in %s." % [u.name, g.prov_name(u.prov)])
	return true


static func stop_dig(_g, u: Dictionary) -> void:
	u["dig"] = null


## Whether a roll of `chance` comes up for the n-th cycle of unit `id` digging in province p (its own stream, so
## every copy of a game agrees and a loaded game goes on the same).
static func dig_roll(seed: String, p: int, id: int, n: int, chance: float) -> bool:
	return Mulberry32.from_string("%s:dig:%d:%d:%d" % [seed, p, id, n]).next() < chance


static func chance_of(id: String) -> float:
	var it = item(id)
	var rar := str(it.rarity) if it != null else "rare"
	return float(c("RARITY_CHANCE").get(rar, 0.05))


## Every cycle: each digging unit rolls; the first to succeed in a province uncovers its relic.
static func dig_payday(g) -> void:
	for u in g.units.duplicate():
		var dg = u.get("dig")
		if dg == null or u.get("_gone", false):
			continue
		var p: int = dg.prov
		var d = g.digs.get(p)
		if d == null or u.prov != p or u.moving:
			u["dig"] = null
			continue
		dg.n = int(dg.n) + 1
		if dig_roll(str(g.world.seed), p, int(u.id), int(dg.n), chance_of(str(d.item))):
			dug_up(g, u, p)


static func dug_up(g, u: Dictionary, p: int) -> void:
	var id := str(g.digs[p].item)
	g.digs.erase(p)
	for v in g.units:
		if v.get("dig") != null and int(v.dig.prov) == p:
			v["dig"] = null
	var where := give(g, u.owner, id, u, p)
	tell(g, u.owner, "%s dug up %s in %s! %s" % [u.name, item_name(id), g.prov_name(p), _where_text(where, u)])
	if g.seats.has(u.owner):
		g.in_seat(u.owner, func(): g.sfx("wn_ally", p))


# ---------------------------------------------------------------------------------------------------------------
# Fallen Stars (session 3): the first falls 45–55 minutes in, then one every 15–25 minutes, on any province but
# the unique ones and their bosses'. Anyone who has explored the province sees its silver X.

## Where a star may fall: not Death Mountain, the Oasis, the Heart of the Forest or their boss provinces, nor where
## something is already buried.
static func star_ok(g, p: int) -> bool:
	if g.digs.has(p):
		return false
	var U = g.uq()
	if U != null:
		for k in ["death", "oasis", "heart"]:
			if int(U.get(k, -1)) == p:
				return false
		if g.uq_guards().has(p):
			return false
	return true


static func step_stars(g) -> void:
	if g.star_next < 0 or g.t < g.star_next:
		return
	var n: int = g.stars_fallen
	var r := Mulberry32.from_string("%s:star:%d" % [str(g.world.seed), n])
	var pool := []
	for i in g.world.provinces.size():
		if star_ok(g, i):
			pool.append(i)
	g.stars_fallen = n + 1
	var sn: Array = c("STAR_NEXT")
	g.star_next = g.star_next + float(sn[0]) + floor(r.next() * (float(sn[1]) - float(sn[0]) + 1.0))
	if pool.is_empty():
		return
	var p: int = pool[int(floor(r.next() * pool.size()))]
	g.digs[p] = {"item": "star", "shown": true, "star": true}
	g.star_fx.append({"prov": p, "t0": g.t})
	for o in g.seat_ids():
		var seen: bool = g.seats[o].explored.has(p) or g.reveal_all
		tell(g, o, ("A star has fallen in %s! A silver X marks where it landed: send a %s to dig it up." % [g.prov_name(p), _scout_word(g, o)]) if seen
			else "A star streaks across the sky and falls somewhere beyond your maps.")
		if seen:
			g.in_seat(o, func(): g.sfx("wn_ally", p))
