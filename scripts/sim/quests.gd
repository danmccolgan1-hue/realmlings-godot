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
	spawn_beasts(g)
	var sf: Array = c("STAR_FIRST")
	var r := Mulberry32.from_string(str(g.world.seed) + ":stars")
	g.star_next = float(sf[0]) + floor(r.next() * (float(sf[1]) - float(sf[0]) + 1.0))
	g.each_seat(func(): add_tables(g))


## The Reliquary on the current seat's tables (Races.apply builds them afresh, so it is called after that too).
static func add_tables(g) -> void:
	if not g.quests_on:
		return
	var D: Dictionary = {}
	for k in c("BUILD_DEFS"):   # (the Dungeon only in games with more than one human nation)
		if not c("BUILD_DEFS")[k].get("mp", false) or g.seats.size() > 1:
			D[k] = c("BUILD_DEFS")[k]
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


## A relic has just reached nation o's Reliquary: its quests may start or finish.
static func added(g, o: int, _id: String) -> void:
	check(g, o)


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
	Dungeons.lost(g, p, list)
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


## A message to nation o with a banner: clicking it looks at province p (the view's, if o is the player's own).
static func notice(g, o: int, msg: String, p: int) -> void:
	if g.seats.has(o):
		g.in_seat(o, func(): g.notice(msg, p))


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
	if not g.ransoms.is_empty():
		Dungeons.step(g)
	if not g.flame_walls.is_empty():
		step_flames(g)
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
	ai_payday(g)
	dig_payday(g)
	if not g.detained.is_empty():
		Dungeons.payday(g)
	Dungeons.events_payday(g)
	Dungeons.jail_payday(g)
	for o in g.seat_ids():   # (research cut for a while: an envoy left to die)
		var keep := []
		for pen in g.seats[o]["research_pen"]:
			pen.left = int(pen.left) - 1
			if pen.left > 0:
				keep.append(pen)
		g.seats[o]["research_pen"] = keep
	for o in g.seat_ids():   # (a Mage Tower built since: the quests waiting on one start)
		check(g, o)
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
	if d.get("only") != null and int(d.only) != g.ME:
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
	notice(g, u.owner, "%s found a dig site in %s! Select a %s there and press Dig." % [u.name, g.prov_name(p), _scout_word(g, u.owner)], p)


static func _scout_word(g, o: int) -> String:
	return Races.words("Wayfinder", g.race(o))


## Why unit u can't dig where it stands ("" when it can).
static func dig_why(g, u: Dictionary) -> String:
	if not is_scout(g, u):
		return "Only scouting units dig"
	var d = g.digs.get(u.prov)
	if d == null or not (d.get("shown", false) or d.get("star", false)) or (d.get("only") != null and int(d.only) != int(u.owner)):
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


## The failsafe: after `done` cycles of digging (18 = 3 minutes), a relic's chance is at least DIG_FAILSAFE's value
## for that time: 10% after 3 minutes, 20% after 4, 30% after 5, 50% after 6 and certain after 7.
static func dig_chance(id: String, done: int) -> float:
	var ch := chance_of(id)
	for step in c("DIG_FAILSAFE"):
		if done >= int(step[0]):
			ch = maxf(ch, float(step[1]))
	return ch


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
		var done := int(dg.n)   # cycles already dug before this roll
		dg.n = done + 1
		if dig_roll(str(g.world.seed), p, int(u.id), int(dg.n), dig_chance(str(d.item), done)):
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
# Fallen Stars (session 3): the first falls 30 minutes in, then one every 15–25 minutes, on any province but
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
		if seen:
			notice(g, o, "A star has fallen in %s! A silver X marks where it landed: send a %s to dig it up." % [g.prov_name(p), _scout_word(g, o)], p)
		else:
			tell(g, o, "A star streaks across the sky and falls somewhere beyond your maps.")
		if seen:
			g.in_seat(o, func(): g.sfx("wn_ally", p))


# ---------------------------------------------------------------------------------------------------------------
# the quest engine (session 4): a quest starts when one of its relics reaches a human nation's Reliquary (and, for
# some, once it has a Mage Tower); it is done when the Reliquaries hold everything it asks for. The first nation to
# finish wins it: everyone else who had it fails. Finishing destroys that quest's relics (and the Fallen Stars it used).

const LOG_TEXT := {"active": "", "done": "Complete", "failed": "Failed"}


static func has_tower(g, o: int) -> bool:
	for p in g.extras:
		if g.nation_of(p) == o and g.extras[p].any(func(e): return e.type == "magetower"):
			return true
	return false


static func log_of(g, o: int) -> Dictionary:
	return g.seats[o]["quest_log"] if g.seats.has(o) else {}


## The goals of a quest at the stage it has reached (a Lost Armament's map, then its prize).
static func goals_of(qid: String, st) -> Array:
	var q: Dictionary = quest(qid)
	if st is Dictionary and int(st.get("part", 1)) == 2 and q.has("part2"):
		return q.part2.goals
	return q.goals


## Each goal with what nation o has: [{label, item, have, n}] (have counts the relics in its Reliquaries).
static func progress(g, o: int, qid: String) -> Array:
	var out := []
	var st = log_of(g, o).get(qid)
	for x in goals_of(qid, st):
		var n := int(x.n)
		var have: int = Dungeons.recovered(g, o) if str(x.item) == "_convict" else count(g, o, str(x.item))   # (Jailbreak: convicts held)
		out.append({"label": str(x.label), "item": str(x.item), "have": mini(have, n), "n": n})
	return out


static func goals_met(g, o: int, qid: String) -> bool:
	return progress(g, o, qid).all(func(x): return x.have >= x.n)


## Whether quest qid starts for nation o now: one of its relics in a Reliquary (and a Mage Tower if it asks for one).
static func triggered(g, o: int, qid: String) -> bool:
	var tr: Dictionary = quest(qid).trigger
	if tr.get("tower", false) and not has_tower(g, o):
		return false
	return tr.items.any(func(i): return count(g, o, str(i)) > 0)


## Look over human nation o's quests: start the ones it has triggered, move on the ones it has finished.
static func check(g, o: int) -> void:
	if not g.quests_on or not g.seats.has(o):
		return
	var L: Dictionary = log_of(g, o)
	for qid in g.quest_pick:
		var st = L.get(qid)
		if st == null:
			if not _won_by_other(g, o, qid) and triggered(g, o, qid):
				acquire(g, o, qid)
				st = L.get(qid)
		if st != null and st.state == "active" and goals_met(g, o, qid):
			advance(g, o, qid)


static func _won_by_other(g, o: int, qid: String) -> bool:
	for o2 in g.seat_ids():
		if o2 != o and log_of(g, o2).get(qid, {}).get("state") == "done":
			return true
	return false


static func acquire(g, o: int, qid: String) -> void:
	log_of(g, o)[qid] = {"state": "active", "t0": g.t, "part": 1}
	var q: Dictionary = quest(qid)
	popup(g, o, "New quest: " + str(q.title), str(q.text) + "\n\n" + goal_text(g, o, qid), "Onward")


## A Lost Armament's map is whole (part 1 done): its pieces are used up, and the prize lies buried somewhere in the
## nation's own land, a site only it can see and dig.
static func advance(g, o: int, qid: String) -> void:
	var q: Dictionary = quest(qid)
	var st: Dictionary = log_of(g, o)[qid]
	if q.has("part2") and int(st.get("part", 1)) == 1:
		for x in q.goals:
			take_everywhere(g, o, str(x.item))
		st.part = 2
		var p := place_prize(g, o, str(q.part2.site))
		st.site = p
		popup(g, o, str(q.title), str(q.part2.text) + ("\n\nA dig site has appeared in %s." % g.prov_name(p) if p >= 0 else "") + "\n\n" + goal_text(g, o, qid), "Onward")
		if goals_met(g, o, qid):
			complete(g, o, qid)
		return
	complete(g, o, qid)


## The prize's dig site: a random province of nation o's without one (its own stream), seen only by o.
static func place_prize(g, o: int, id: String) -> int:
	var pool: Array = g.provs_of(o).filter(func(p): return not g.digs.has(p))
	pool.sort()
	if pool.is_empty():
		return -1
	var r := Mulberry32.from_string("%s:prize:%s:%d" % [str(g.world.seed), id, o])
	var p: int = pool[int(floor(r.next() * pool.size()))]
	g.digs[p] = {"item": id, "shown": true, "star": false, "only": o}
	return p


static func complete(g, o: int, qid: String) -> void:
	var q: Dictionary = quest(qid)
	var st: Dictionary = log_of(g, o)[qid]
	# the quest's own relics go, used or not; the Fallen Stars only as many as it asked for
	for id in data().ITEMS:
		if str(item(id).quest) == qid:
			take_everywhere(g, o, id)
	for x in goals_of(qid, st):
		if str(x.item) == "star":
			take(g, o, "star", int(x.n))
	st.state = "done"
	st.t1 = g.t
	var rw: Dictionary = q.get("reward", {})
	if rw.has("rate"):
		var R: Dictionary = g.seats[o]["quest_rate"]
		for tr in rw.rate:
			R[tr] = int(R.get(tr, 0)) + int(rw.rate[tr])
	if rw.has("unlock"):
		var U: Array = g.seats[o]["quest_unlocks"]
		if not U.has(str(rw.unlock)):
			U.append(str(rw.unlock))
	popup(g, o, "Quest complete: " + str(q.title), str(q.done_text) + "\n\n" + str(q.reward_text), "Splendid")
	# everyone else who had it fails
	for o2 in g.seat_ids():
		if o2 == o:
			continue
		var s2 = log_of(g, o2).get(qid)
		if s2 != null and s2.state == "active":
			s2.state = "failed"
			s2.t1 = g.t
			s2.by = o
			popup(g, o2, "Quest failed: " + str(q.title), "The %s finished it first." % g.player_info(o).name, "Oh well")
	# a part-2 site nobody can dig any more
	for p in g.digs.keys():
		if g.digs[p].get("only") != null and str(g.digs[p].item) == str(q.get("part2", {}).get("site", "")):
			g.digs.erase(p)


## Take every relic `id` from nation o's Reliquaries and from what its scouting units carry.
static func take_everywhere(g, o: int, id: String) -> void:
	take(g, o, id)
	for u in g.units:
		if u.owner == o and u.get("bag") is Array:
			u.bag = u.bag.filter(func(x): return x != id)


## A quest's goal lines with counts, as the Quest Log shows them: "Find copies of Lord Callum's Lawbook 1/3".
static func goal_text(g, o: int, qid: String) -> String:
	return "\n".join(progress(g, o, qid).map(func(x): return "%s %d/%d" % [x.label, x.have, x.n]))


## A quest's text in nation o's race's words.
static func words(g, o: int, text: String) -> String:
	return Races.words(text, g.race(o))


static func popup(g, o: int, title: String, text: String, ok: String) -> void:
	if not g.seats.has(o):
		return
	tell(g, o, title)
	g.in_seat(o, func():
		if g.on_dialog.is_valid() and g.ME == g.view_seat:
			g.on_dialog.call(words(g, o, title), words(g, o, text), [{"id": "ok", "label": ok, "why": null}], Callable()))


# ---------------------------------------------------------------------------------------------------------------
# Battlegear (session 5): three armors a quest unlocks, one tier above Tier IV of their family, for every race's
# matching family. Added to the armor table once (GameData's ARMORS, Godot-only keys "<family>5"); the computer
# nations and the web-game tests never look past Tier IV, and the Armory shows them only once unlocked.

## family -> the armor its fifth tier is: light (leather and its twins), medium (chain...), heavy (plate...)
const GEAR_FAMILY := {"leather": "beastleather", "stag": "beastleather", "spirit": "beastleather",
	"chain": "bone_regalia", "wyvern": "bone_regalia", "mithril": "bone_regalia",
	"plate": "siegebreaker", "dragon": "siegebreaker", "ornate": "siegebreaker"}
const GEAR := {
	"beastleather": {"name": "Yenny's Beastleather", "hp": 60, "speed_mul": 1.2,
		"note": "+60 health, 20% faster on the march"},
	"bone_regalia": {"name": "Freak Man's Bone Regalia", "hp": 70, "speed_mul": 1.0,
		"note": "+70 health; in battle it steals the enemy's Hardened Skin and Cursed Weapons"},
	"siegebreaker": {"name": "Siegebreaker Runeplate", "hp": 80, "speed": 1.0,
		"note": "+80 health, no speed penalty, sieges 20% faster"},
}
const SIEGE_MUL := 1.25   # Siegebreaker Runeplate: walls fall in 80% of the time


static func install_gear() -> void:
	install_beasts()
	install_arms()
	var A: Dictionary = GameData.c("ARMORS")
	if A.has("leather5"):
		return
	for fam in GEAR_FAMILY:
		var a4 = A.get(fam + "4")
		var a3 = A.get(fam + "3")
		if a4 == null or a3 == null:
			continue
		var G: Dictionary = GEAR[GEAR_FAMILY[fam]]
		var x: Dictionary = a4.duplicate(true)
		x.name = G.name
		x.level = 5
		x.armor = float(a4.armor) + (float(a4.armor) - float(a3.armor))   # one more tier's step
		x.speed = float(G.get("speed", float(a4.speed) * float(G.get("speed_mul", 1.0))))
		x.hp = int(G.hp)
		x.tech = null
		x.quest = "armor:" + GEAR_FAMILY[fam]
		x.note = G.note
		A[fam + "5"] = x


## Whether nation o may use a piece of gear: quest gear only once its quest is done (computer nations never).
static func gear_unlocked(g, o: int, item: Dictionary) -> bool:
	var q = item.get("quest")
	if q == null:
		return true
	return g.seats.has(o) and g.seats[o]["quest_unlocks"].has(str(q))


## An army's soldiers wearing the quest armor `key` ("armor:siegebreaker"...).
static func wears(g, a: Dictionary, key: String) -> bool:
	if a.get("troops") == null:
		return false
	for k in a.troops:
		if a.troops[k] > 0 and g.DSTATS.has(k) and g.DSTATS[k].get("quest_armor") == key:
			return true
	return false


## The Bone Regalia in a battle: its wearers' side takes the enemy's Hardened Skin and Cursed Weapons.
static func steal_buffs(g, b: Dictionary) -> void:
	var here: Array = g.units.filter(func(a): return a.kind == "army" and is_same(a.get("battle"), b))
	for w in here:
		if not wears(g, w, "armor:bone_regalia"):
			continue
		for f in here:
			if not g.hostile(w.owner, f.owner):
				continue
			for buff in ["skin", "curse"]:
				var v: float = f.get(buff, 0.0)
				if v > 0:
					w[buff] = maxf(w.get(buff, 0.0), v)
					f[buff] = 0.0
					var nm: String = "Hardened Skin" if buff == "skin" else "Cursed Weapons"
					tell(g, w.owner, "%s's Bone Regalia drinks in the enemy's %s!" % [w.name, nm])
					tell(g, f.owner, "%s's Bone Regalia stole your %s's %s!" % [w.name, f.name, nm], true)


# ---------------------------------------------------------------------------------------------------------------
# Primal beasts (session 6): with Hides of Mythical Beasts on the map, primal creatures roam their own provinces
# (Meadows, Fae Forests, Drylands, Bogs; plain grassland, forest, desert or swamp when there are none). Each is one
# creature, patrols like a monster, and drops its hide when slain: into the victor's Reliquary, else a chest there.
# Their troop kinds and monster entries are added to the game's tables once (Godot-only keys, like the armors).

const BEASTS := {
	"knuckledragger": {"troop": "m-knuckledragger", "name": "Plains Knuckledragger", "variant": "meadow", "terrain": "grassland",
		"drop": "pscraps", "atk": 20, "hp": 300, "speed": 0.6, "names": ["Knuckledragger", "Meadow Brute", "Grass Ape"],
		"blurb": "A gorilla-like primal beast of the meadows. Drops Primal Scraps."},
	"ursacub": {"troop": "m-ursacub", "name": "Cub of Ursa", "variant": "fae", "terrain": "forest",
		"drop": "pscraps", "atk": 20, "hp": 300, "speed": 0.6, "names": ["Cub of Ursa", "Star Cub", "Moonpaw"],
		"blurb": "A small celestial bear from the Fae Forests. Drops Primal Scraps."},
	"dunestalker": {"troop": "m-dunestalker", "name": "Dunestalker", "variant": "drylands", "terrain": "desert",
		"drop": "phide", "atk": 25, "hp": 420, "speed": 0.75, "names": ["Dunestalker", "Long Wolf", "Sand Prowler"],
		"blurb": "A long, slender wolf of the Drylands. Drops a Primal Hide."},
	"bogwalker": {"troop": "m-bogwalker", "name": "Bogwalker", "variant": "bog", "terrain": "swamp",
		"drop": "phide", "atk": 25, "hp": 480, "speed": 0.5, "names": ["Bogwalker"],
		"blurb": "A moss-covered mushroom that walks on two legs, deep in the Bogs. Drops a Primal Hide."},
}


static func install_beasts() -> void:
	var M: Dictionary = GameData.c("MONSTERS")
	if M.has("knuckledragger"):
		return
	var DS: Dictionary = GameData.c("DSTATS")
	var UD: Dictionary = GameData.c("UNIT_DEFS")
	var US: Dictionary = GameData.c("UNIT_SPEED")
	for k in BEASTS:
		var B: Dictionary = BEASTS[k]
		M[k] = {"troop": B.troop, "sizes": [1], "terrain": B.terrain, "loot": {}, "cry": B.name + "!", "found": "a " + B.name, "names": B.names}
		DS[B.troop] = {"cav": false, "rough": true, "fam": "blunt", "armor": 0, "shieldArmor": 0, "red": 0.0, "parry": 0, "atk": B.atk,
			"hp": B.hp, "speed": B.speed, "cost": {}, "upkeep": {}, "blurb": ""}
		UD[B.troop] = {"name": B.name, "cost": {}, "upkeep": {}, "blurb": B.blurb}
		US[B.troop] = B.speed


## The beasts of Hides of Mythical Beasts, placed when the map is made (stream <seed>:beasts): away from capitals,
## settlements, other raiders and the unique provinces.
static func spawn_beasts(g) -> void:
	var q = quest("beastleather")
	if q == null or not g.quest_pick.has("beastleather"):
		return
	var r := Mulberry32.from_string(str(g.world.seed) + ":beasts")
	var ban: Dictionary = g.uq_skip()
	for p in g.buildings:
		ban[p] = true
		if g.buildings[p].stage == 2:
			for n in g.all_nbr[p]:
				ban[n] = true
	for u in g.units:
		ban[u.prov] = true
	var kinds: Array = q.beasts.keys()
	kinds.sort()
	for k in kinds:
		var B: Dictionary = BEASTS[k]
		var pool := []
		for i in g.world.provinces.size():
			if not ban.has(i) and i < g.variant.size() and g.variant[i] == B.variant:
				pool.append(i)
		if pool.size() < int(q.beasts[k]):   # (no such terrain on this map: its plain kind)
			for i in g.world.provinces.size():
				if not ban.has(i) and not pool.has(i) and g.world.provinces[i].terrain == B.terrain:
					pool.append(i)
		r.shuffle(pool)
		for n in mini(int(q.beasts[k]), pool.size()):
			var p: int = pool[n]
			var a: Dictionary = g.spawn_monster(p, k, 1)
			a["primal"] = true
			ban[p] = true


## A primal beast has fallen in battle b: its hide goes to the nation that slew it (the first human nation among the
## victors, else the first computer one).
static func beast_fell(g, a: Dictionary, b: Dictionary) -> void:
	var B = BEASTS.get(str(a.get("monster", "")))
	if B == null:
		return
	var winner := 0
	var ks: Array = b.get("start", {}).keys().map(func(x): return int(x))
	ks.sort()
	for o in ks:
		if g.seats.has(o):
			winner = o
			break
	if not winner:
		for o in ks:
			if g.is_nation(o):
				winner = o
				break
	if not winner:
		return
	var where := give(g, winner, str(B.drop), null, int(b.prov))
	tell(g, winner, "The %s falls: %s! %s" % [B.name, item_name(str(B.drop)), "It goes into your Reliquary." if where == "reliquary" else "No Reliquary has room: it lies in a chest where the beast fell."])


# ---------------------------------------------------------------------------------------------------------------
# Lost Armaments (session 7): weapons, a shield and a staff the quests unlock. Added to the gear tables once
# (Godot-only keys); shown in the Armory only once unlocked; every race can use them.

const ARMS := {
	"cutlass": {"table": "WEAPONS", "item": {"name": "Jagkara's Cutlass", "fam": "sword", "tier": 5, "atk": 25, "twoH": false,
		"cost": {"gold": 120}, "tech": null, "quest": "weapon:cutlass", "rows": ["sword", "axe", "thrust"]}},
	"freakaxe": {"table": "WEAPONS", "item": {"name": "The Freak Man's Axe", "fam": "axe", "tier": 5, "atk": 27, "twoH": false,
		"cost": {"gold": 120}, "tech": null, "quest": "weapon:freakaxe", "rows": ["sword", "axe", "thrust"]}},
	"greedmaul": {"table": "WEAPONS", "item": {"name": "The Maul of Greed", "fam": "blunt", "tier": 5, "atk": 35, "twoH": true,
		"cost": {"gold": 120}, "tech": null, "quest": "weapon:greedmaul", "rows": ["blunt"]}},
	"sham": {"table": "SHIELD_DEFS", "item": {"name": "Shield of Sham", "armor": 10, "speed": 0.92, "cost": {"gold": 35, "wood": 15},
		"tech": null, "quest": "shield:sham"}},
	"triune": {"table": "MAGE_WEAPONS", "item": {"name": "Triune Staff", "line": "stave", "atk": 12, "twoH": true, "tech": null,
		"quest": "staff:triune"}},
}
const TRIUNE_MANA := 100   # the Triune Staff: +100 mana, +10 mana every cycle (and spells 20% faster: Game.STAVE_CAST)
const TRIUNE_REGEN := 10


static func install_arms() -> void:
	for k in ARMS:
		var T: Dictionary = GameData.c(ARMS[k].table)
		if not T.has(k):
			T[k] = ARMS[k].item.duplicate(true)


## Nation o carries the Triune Staff (its Mages all carry the nation's Mage gear).
static func has_triune(g, o: int) -> bool:
	if not g.seats.has(o):
		return false
	return str(g.seats[o]["mage_gear"].get("weapon", "")) == "triune"


## A side whose whole front line carries the Shield of Sham: the first blow against it in a battle comes to nothing.
static func sham_front(g, armies: Array) -> bool:
	if armies.is_empty():
		return false
	for a in armies:
		var lay = g.row_sync(a)
		var pool: Dictionary = a.troops if lay == null or g.row_sum(lay.f) <= 0 else lay.f
		for k in pool:
			if pool[k] > 0 and not g.DSTATS.get(k, {}).get("sham", false):
				return false
	return true


## Before a blow lands on `armies` in battle b: true when the Shield of Sham turns it aside (once a side, a battle).
static func sham_blocks(g, b: Dictionary, armies: Array) -> bool:
	if armies.is_empty():
		return false
	var o: int = armies[0].owner
	if b.get("sham", []).has(o) or not sham_front(g, armies):
		return false
	if not b.has("sham"):
		b["sham"] = []
	b.sham.append(o)
	tell(g, o, "The Shield of Sham turns aside the enemy's first blow!")
	return true


# ---------------------------------------------------------------------------------------------------------------
# Spell Books (session 8): Wall of Flame and Time Warp, for the Mages, Warlocks and Druids of a human nation that
# finished the quest. 100 mana each, 10 s cooldown.
#
# Wall of Flame: a wall on the border between the caster's province and a neighbor, for 60 s. Its gate lets only the
# caster's nation through; siege, Shockwave, Fireball and Earthquake can't break it. One at a time: casting again
# puts out the last. Time Warp: one building in the caster's province works twice as well (twice the gold, wood or
# food, twice the research, soldiers trained in half the time) until Time Warp is cast on another.

const SPELL_MANA := 100
const SPELL_CD := 10.0
const FLAME_TIME := 60.0
const SPELLS := {"flamewall": {"name": "Wall of Flame", "unlock": "spell:flamewall"},
	"timewarp": {"name": "Time Warp", "unlock": "spell:timewarp"}}
const WARP_TYPES := ["farm", "lumber", "goldmine", "market", "forge", "magetower", "temple", "barracks"]


## Why caster c can't cast quest spell k now ("" when it can).
static func spell_why(g, c: Dictionary, k: String) -> String:
	if not g.quests_on or not g.seats.has(int(c.owner)) or not g.seats[c.owner]["quest_unlocks"].has(SPELLS[k].unlock):
		return "Finish its quest first"
	if g.mages_in(c) <= 0:
		return "No " + Races.words("Mage", g.race(c.owner))
	if c.get("cast") != null or c.get("quake"):
		return "Already casting"
	var left: float = g.in_seat(c.owner, func(): return g.cd_left(k))
	if left > 0:
		return "Ready in %d s" % ceili(left)
	if Game.mana_of(c) < float(g.mc(SPELL_MANA, c.owner)):
		return "Needs %d mana" % SPELL_MANA
	return ""


static func _spent(g, c: Dictionary, k: String) -> void:
	g.spend_mana(c, SPELL_MANA)
	g.in_seat(c.owner, func(): g.cd[k] = g.t + SPELL_CD)


## Why caster c can't raise a Wall of Flame toward province q.
static func flamewall_why(g, c: Dictionary, q: int) -> String:
	var why := spell_why(g, c, "flamewall")
	if why != "":
		return why
	if q < 0 or not g.all_nbr[c.prov].has(q):
		return "Pick a province next to the caster"
	if not g.open_between(c.prov, q):
		return "That border is already closed"
	return ""


static func cast_flamewall(g, c: Dictionary, q: int) -> bool:
	var why := flamewall_why(g, c, q)
	if why != "":
		tell(g, c.owner, why + ".", true)
		return false
	for i in g.flame_walls.keys():   # one at a time
		if int(g.flame_walls[i].owner) == int(c.owner):
			put_out(g, int(i))
	_spent(g, c, "flamewall")
	var p: int = c.prov
	var had_road: bool = g.roads.has(Game.link_key(p, q))
	var before := {}
	for i in g.walls:
		before[i] = true
	g.raise_wall(p, q, int(c.owner), -1)
	for i in g.walls:
		if not before.has(i):
			g.flame_walls[i] = {"owner": int(c.owner), "until": g.t + FLAME_TIME, "road": had_road}
	tell(g, c.owner, "%s raises a Wall of Flame between %s and %s." % [c.name, g.prov_name(p), g.prov_name(q)])
	return true


## A Wall of Flame burns out: the border opens again (and a road there comes back).
static func put_out(g, i: int) -> void:
	var F = g.flame_walls.get(i)
	if F == null:
		return
	g.flame_walls.erase(i)
	var e: Dictionary = g.world.edges[i]
	var k: String = Game.link_key(e.a, e.b)
	var V: Array = g.world.vertices
	var a: Array = V[e.v[0]]
	var b: Array = V[e.v[1]]
	e.open = true
	e.style = "open"
	g.walls.erase(i)
	g.wall_hp.erase(i)
	g.wall_crack.erase(i)
	g.wall_max.erase(i)
	g.gate_own.erase(k)
	g.walls_ver += 1
	g.open_nbr[e.a].append({"q": e.b, "m": [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]})
	g.open_nbr[e.b].append({"q": e.a, "m": [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]})
	if F.get("road", false):
		g.roads[k] = true


static func step_flames(g) -> void:
	for i in g.flame_walls.keys():
		if g.t >= float(g.flame_walls[i].until):
			put_out(g, int(i))


## The buildings in caster c's province that Time Warp can speed up.
static func warp_targets(g, c: Dictionary) -> Array:
	if g.nation_of(c.prov) != int(c.owner):
		return []
	return g.extras_in(c.prov).filter(func(e): return WARP_TYPES.has(str(e.type)))


static func cast_timewarp(g, c: Dictionary, slot: int) -> bool:
	var why := spell_why(g, c, "timewarp")
	var e = null
	for x in warp_targets(g, c):
		if int(x.slot) == slot:
			e = x
	if why == "" and e == null:
		why = "No building there to warp"
	if why != "":
		tell(g, c.owner, why + ".", true)
		return false
	_spent(g, c, "timewarp")
	g.seats[c.owner]["time_warp"] = {"p": int(c.prov), "slot": slot}
	g.in_seat(c.owner, func(): g.compute_income())
	tell(g, c.owner, "%s bends time around the %s in %s: it works twice as fast." % [c.name, g.BUILD_DEFS[e.type].name, g.prov_name(c.prov)])
	return true


## The building nation o has warped (if it still stands and is still o's), or null.
static func warped(g, o: int):
	if not g.seats.has(o):
		return null
	var tw = g.seats[o].get("time_warp")
	if tw == null or g.nation_of(int(tw.p)) != o or g.occ.has(int(tw.p)):
		return null
	for e in g.extras_in(int(tw.p)):
		if int(e.slot) == int(tw.slot):
			return e
	return null


## Time Warp's income for the current seat: the warped building's gold, wood or food once more.
static func warp_income(g) -> Dictionary:
	var out := {"gold": 0, "wood": 0, "food": 0}
	var e = warped(g, g.ME)
	if e == null:
		return out
	var gv: Dictionary = Ai.crop_gives(Ai.crop_of(e), g.gives_of("farm")) if e.type == "farm" else g.gives_of(str(e.type))
	for k in gv:
		if out.has(k):
			out[k] += int(gv[k])
	return out


## Time Warp's research for the current seat: the warped Forge's, Mage Tower's or Temple's points once more.
static func warp_research(g, tree: String) -> int:
	var e = warped(g, g.ME)
	if e == null:
		return 0
	var LP: Array = GameData.c("LEVEL_POINTS")
	if e.type == "forge" and tree == "mil":
		return int(LP[e.get("level", 1)])
	if e.type == "magetower" and tree == "mag":
		return int(LP[e.get("level", 1)])
	if e.type == "temple" and tree == "gov":
		return 2
	return 0


## Time Warp's training: a queue in the warped building trains in half the time.
static func warp_train_mul(g, key: String) -> float:
	var e = warped(g, g.ME)
	if e == null:
		return 1.0
	var tw: Dictionary = g.seats[g.ME].time_warp
	return 0.5 if key == "%s:%d" % [str(e.type), int(tw.p)] else 1.0


# ---------------------------------------------------------------------------------------------------------------
# Trade (session 12): Diplomacy's barter between players also carries relics and prisoners. extra: {gi: relics the
# offering nation gives, wi: relics it asks for, gp / wp: prisoner ids given / asked}.

static func trade_clean(x: Dictionary) -> Dictionary:
	var out := {}
	for k in ["gi", "wi"]:
		out[k] = Array(x.get(k, [])).map(func(v): return str(v))
	for k in ["gp", "wp"]:
		out[k] = Array(x.get(k, [])).map(func(v): return int(v))
	return out


static func trade_any(x: Dictionary) -> bool:
	return ["gi", "wi", "gp", "wp"].any(func(k): return not Array(x.get(k, [])).is_empty())


## Whether `from` (offering) and `to` still have what the trade names ("" when they do).
static func trade_why(g, from: int, to: int, x: Dictionary) -> String:
	for side in [["gi", from, "You"], ["wi", to, "They"]]:
		var need := {}
		for id in x.get(side[0], []):
			need[id] = int(need.get(id, 0)) + 1
		for id in need:
			if count(g, side[1], id) < need[id]:
				return "%s don't keep %s" % [side[2], item_name(id)]
	for side in [["gp", from, "You"], ["wp", to, "They"]]:
		for pid in x.get(side[0], []):
			if Dungeons.holder(g, int(pid)) != side[1]:
				return "%s don't hold that prisoner" % side[2]
	return ""


## Carry out the relics and prisoners of an accepted trade.
static func trade_do(g, from: int, to: int, x: Dictionary) -> void:
	for side in [["gi", from, to], ["wi", to, from]]:
		for id in x.get(side[0], []):
			if take(g, side[1], id, 1) == 1:
				give(g, side[2], id, null, g.capital_of(side[2]))
	for side in [["gp", from, to], ["wp", to, from]]:
		for pid in x.get(side[0], []):
			var pr = Dungeons.release(g, side[1], int(pid))
			if pr != null:
				Dungeons.jail(g, side[2], pr)
	for o in [from, to]:
		check(g, o)
		Dungeons.check_jail(g)


## What one side of a trade holds, in words: "100 gold, Lord Callum's Lawbook and a Convict".
static func trade_text(g, res: Dictionary, x: Dictionary, giving: bool) -> String:
	var parts := []
	var rt: String = g.res_text(res)
	if rt != "" and rt != "nothing":
		parts.append(rt)
	for id in x.get("gi" if giving else "wi", []):
		parts.append(item_name(id))
	for pid in x.get("gp" if giving else "wp", []):
		for pr in g.ransoms.map(func(r): return r.pr) + _all_prisoners(g):
			if int(pr.id) == int(pid):
				parts.append("the prisoner " + str(pr.name))
				break
	return ", ".join(parts) if not parts.is_empty() else "nothing"


static func _all_prisoners(g) -> Array:
	var out := []
	for o in g.seat_ids():
		out.append_array(Dungeons.prisoners_of(g, o))
	return out


# ---------------------------------------------------------------------------------------------------------------
# Computer nations (session 13): no quests, but they keep what they find. Their scouting units dig at an uncovered
# site (or a Fallen Star) they stand on, an idle one walks to the nearest such site in its nation's land, and a
# nation holding a relic with nowhere to keep it raises a Reliquary at its capital when it can pay for it.

static func ai_payday(g) -> void:
	if g.nations.is_empty():
		return
	var R: Dictionary = c("BUILD_DEFS").reliquary
	for o in g.nations:
		var N: Dictionary = g.nations[o]
		if not N.get("alive", true) or not reliquaries(g, int(o)).is_empty():
			continue
		# a Reliquary at the capital as soon as the nation knows of a relic in its land, or is carrying one
		var wants: bool = g.digs.keys().any(func(p): return g.nation_of(p) == int(o) and _ai_can_dig(g.digs[p]))
		if not wants:
			wants = g.units.any(func(u): return u.owner == int(o) and not bag_of(u).is_empty())
		var cap: int = g.capital_of(int(o))
		if not wants or cap < 0 or g.extras_in(cap).size() >= g.plot_cap(cap):
			continue
		if not R.cost.keys().all(func(k): return int(N.stock.get(k, 0)) >= int(R.cost[k])):
			continue
		for k in R.cost:
			N.stock[k] = int(N.stock[k]) - int(R.cost[k])
		var used := {}
		for e in g.extras_in(cap):
			used[int(e.slot)] = true
		var slot := 0
		while used.has(slot):
			slot += 1
		if not g.extras.has(cap):
			g.extras[cap] = []
		g.extras[cap].append({"type": RELIQUARY, "slot": slot, "born": g.t})
		for u in g.units:   # (what its scouts were carrying goes in at once)
			if u.owner == int(o):
				for id in bag_of(u).duplicate():
					if deposit(g, int(o), id):
						bag(u).erase(id)


static func _ai_can_dig(d: Dictionary) -> bool:
	return d.get("only") == null and (d.get("shown", false) or d.get("star", false))


## A computer nation's scout and the dig sites in its own land (from ai.gd wayfinders): standing on one, it digs;
## otherwise it walks to the nearest one no other scout of the nation has taken. True when it has its orders.
static func ai_dig_step(g, N: Dictionary, u: Dictionary, wfs: Array) -> bool:
	var d = g.digs.get(u.prov)
	if d != null and _ai_can_dig(d) and g.nation_of(u.prov) == int(N.id):
		u["dig"] = {"prov": u.prov, "n": 0, "t0": g.t}
		u.erase("aiTarget")
		u.erase("aiDig")
		return true
	var taken := {}
	for v in wfs:
		if not is_same(v, u) and v.get("aiDig") != null:
			taken[int(v.aiDig)] = true
	var best := -1
	var hops: Array = []
	for p in g.digs:
		if taken.has(int(p)) or not _ai_can_dig(g.digs[p]) or g.nation_of(p) != int(N.id):
			continue
		if hops.is_empty():
			hops = g.hops_list(u.prov)
		if hops[p] != INF and (best < 0 or hops[p] < hops[best] or (hops[p] == hops[best] and p < best)):
			best = p
	if best < 0:
		u.erase("aiDig")
		return false
	u["aiDig"] = best
	u.erase("aiTarget")
	g.order(u, best, true)
	return true


## Whether a computer nation still has to look over province p of its own for a buried relic (it owns it, but no
## scout of its own has surveyed it since: its capital, land it took).
static func ai_needs_survey(g, N: Dictionary, p: int) -> bool:
	return g.quests_on and g.nation_of(p) == int(N.id) and not N.get("qsurv", {}).has(str(p))


## Its nearest own province still to be looked over, that no other scout has taken (reach: hops from u), or -1.
static func ai_own_survey_target(g, N: Dictionary, u: Dictionary, reach: Dictionary, taken: Dictionary) -> int:
	var best := -1
	var bs := INF
	for p in reach:
		if taken.has(p) or not ai_needs_survey(g, N, int(p)):
			continue
		if float(reach[p]) < bs:
			bs = float(reach[p])
			best = int(p)
	return best


## How to Play's quest lines (Godot only), after the web game's guide.
const HOWTO := [
	"[b]Quests and relics[/b] (full maps): each map hides the relics of six quests. A Wayfinder's survey uncovers a province's dig site (a red X, seen by anyone with vision); stand on it and press [b]Dig[/b]: every 10 s there is a chance to unearth the relic (common 20%, uncommon 10%, rare 5%). The longer a Wayfinder keeps digging, the better its odds: at least 10% after 3 minutes, 20% after 4, 30% after 5, 50% after 6, and after 7 minutes the relic is certain.",
	"[b]Reliquary[/b]: 100 gold and 100 wood, 9 slots, one per province. Relics go straight into a Reliquary with room, wherever they are found; with none, the Wayfinder carries one, and the rest wait in a chest. A relic in a Reliquary starts its quest; the [b]Quest Log[/b] (L, under Diplomacy) shows every text and what is left to find.",
	"[b]Fallen Stars[/b]: the first falls 30 minutes in, then one every 15 to 25 minutes, marked by a silver X for anyone who has explored the province. Battlegear, Spell Books and Lost Armaments need them.",
	"[b]Rewards[/b]: research every 10 s for good, Tier V armor, new weapons, the Shield of Sham, the Triune Staff, and the spells Wall of Flame and Time Warp. The first nation to finish a quest wins it; everyone else who had it fails.",
	"[b]Mason[/b]: the buildings that need no research come first; [b]Advanced Buildings[/b] (U) opens the ones research unlocks.",
	"[b]Multiplayer[/b]: Dungeons hold prisoners from the ransom events and Jailbreak; Diplomacy's barter trades relics and prisoners; at 50% warscore you may Raid a Reliquary or Free Prisoners.",
]
