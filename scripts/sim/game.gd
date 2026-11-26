class_name Game
extends RefCounted
## One game's rules and state: the web game's `S` object plus the globals that live beside it (yields, income,
## treeBorder, openNbr). Rules only; never draws. Milestone 1: the Practice island, Realmlings, the player alone.
##
## Field names follow the web game (snake_case here), so `stock` is S.stock, `buildings` is S.buildings, and so on.
## Units are Dictionaries with the web fields: {id, owner, kind, name, prov, slot, x, y, troops (armies only), ...}.

## The host's seat: the player of a single-player game. Computer nations are 4–10, raiders 3.
const HOST := 1
## The seat whose fields the properties below read and write (see use_seat); a single-player game is always HOST.
var ME := HOST
## The seat this copy's player plays: what the views show and whose orders this copy sends (multiplayer).
static var LOCAL := HOST
## Each human nation's record of its own fields (SEAT_FIELDS), by nation id; `cur` is seats[ME].
var cur := seat_defaults()
var seats := {HOST: cur}
## The seat the fields return to after each step and order: the seat this copy shows (LOCAL in a real game;
## tests running several copies in one process give each its own).
var view_seat := HOST
## Multiplayer: each human nation's player's name (nation id -> name), so a saved game can be continued by the same
## players and a player who drops out can come back to their own nation.
var seat_names := {}
const RES := ["gold", "wood", "food"]
const MASON := "mason:A"
const MAGE := "mage:A"
const OUTPOST_UPKEEP := {"wood": 1}
const THUG := "thug:A"
const TWO_BURST := 2.5   # web: equip.js   # web: govtech.js (declared with OUTPOSTS_PER_FORT; not in the export)
## Designs a leader starts with that the Armory would create (web: v105.js leaderDesign → equip.js addDesign).
## Cost and upkeep as the web game computes them (tests/fixtures/econ); they move to the Armory port later.
const LEADER_DESIGNS := {
	"Shield Footman": {"name": "Shield Footman", "cost": {"gold": 90, "wood": 10}, "upkeep": {"food": 2}, "design": true, "speed": 0.83,
		"blurb": "Short Sword and Round Shield, Leather I armor. Parry: take 10% less damage.",
		"spec": {"type": "inf", "weapon": "shortsword", "shield": "round", "armor": "leather1", "race": "realm"}},
	"Twin-Axe Berserker": {"name": "Twin-Axe Berserker", "spec": {"type": "inf", "weapon": "handaxe", "off": "handaxe", "armor": "stag1", "race": "swamp"}},
	"Two-Handed Protector": {"name": "Two-Handed Protector", "spec": {"type": "inf", "weapon": "dirk", "armor": "spirit1", "race": "wood", "two": true}},
}

# --- world ---
var world: Dictionary
var G: Dictionary            # WorldPrep.prep(world): provs (pts, ic, coastal...), bounds
var open_nbr := []           # province -> [{q, m}] across open borders
var all_nbr := []
var yields := []             # province -> {gold, wood, food, bonus, deposit}
var variant := []            # province -> "" or a terrain variant ("drylands", "meadow", "fae", "bog"), Godot 0.18
static var VARIANTS := true  # tests that compare against the web game's numbers turn the variants off
static var RULES19 := true   # 0.19's rule changes (Aithne's kit, faster and wider roads); off in the same tests
var tree_border := []

# --- the nation ---
var leader: String:
	get: return cur["leader"]
	set(v): cur["leader"] = v
var capital: int:
	get: return cur["capital"]
	set(v): cur["capital"] = v
var stock: Dictionary:
	get: return cur["stock"]
	set(v): cur["stock"] = v
var income: Dictionary:
	get: return cur["income"]
	set(v): cur["income"] = v
var income_parts: Dictionary:
	get: return cur["income_parts"]
	set(v): cur["income_parts"] = v
var buildings := {}          # province -> {stage (0 outpost, 1 fort, 2 capital), born, owner}
var extras := {}             # province -> [{type, slot, born, freeFor?}]
var occ := {}                # province -> the nation occupying it (wars)
var units := []
var next_id := 1
var army_counter: int:
	get: return cur["army_counter"]
	set(v): cur["army_counter"] = v
var tech: Dictionary:  # tree -> {cur, prog, bank, opts, done, tier}
	get: return cur["tech"]
	set(v): cur["tech"] = v
var rep: Dictionary:  # repeatable research levels
	get: return cur["rep"]
	set(v): cur["rep"] = v
var surveyed: Dictionary:  # province -> time surveyed
	get: return cur["surveyed"]
	set(v): cur["surveyed"] = v
var unit_defs := {}          # UNIT_DEFS plus designs made in this game
var designs: Array:
	get: return cur["designs"]
	set(v): cur["designs"] = v
var exhaust: int:
	get: return cur["exhaust"]
	set(v): cur["exhaust"] = v
var exhaust_ok: int:
	get: return cur["exhaust_ok"]
	set(v): cur["exhaust_ok"] = v
var harvest:
	get: return cur["harvest"]
	set(v): cur["harvest"] = v
var devel := {}
var upgrades: Dictionary:  # province -> {t0, paid}: outposts becoming forts
	get: return cur["upgrades"]
	set(v): cur["upgrades"] = v
var xup: Dictionary:  # "<p>@<slot>" -> {t0, paid, to}: a Forge or Mage Tower going up a level
	get: return cur["xup"]
	set(v): cur["xup"] = v
var roads := {}              # "a_b" (a < b) -> true
var walls := {}              # edge index -> true
var wall_hp := {}
var gate_own := {}           # "a_b" -> {home, owner}
var fort_walled := {}        # "p>q" -> true: borders a fort or capital has walled once
var gpc_slow_t := -9.0
# magic (web: magic.js S.cd / S.paths / S.harvest / S.trap, v98.js S.reveals / S.eyes / S.haunts / S.manaPool)
var cd: Dictionary:  # spell -> game time when ready again
	get: return cur["cd"]
	set(v): cur["cd"] = v
var paths := {}              # edge index -> "forest" | "tunnel"
var harvest_by:  # web: S.harvest
	get: return cur["harvest_by"]
	set(v): cur["harvest_by"] = v
var trap:
	get: return cur["trap"]
	set(v): cur["trap"] = v
var school_popup: bool:  # the view should offer the school choice (web: setTimeout(openSchoolPopup))
	get: return cur["school_popup"]
	set(v): cur["school_popup"] = v
var reveals: Array:
	get: return cur["reveals"]
	set(v): cur["reveals"] = v
var eyes: Array:
	get: return cur["eyes"]
	set(v): cur["eyes"] = v
var haunts: Array:
	get: return cur["haunts"]
	set(v): cur["haunts"] = v
var mana_pool: Array:
	get: return cur["mana_pool"]
	set(v): cur["mana_pool"] = v
var mana_prev: Dictionary:
	get: return cur["mana_prev"]
	set(v): cur["mana_prev"] = v
var mana_prev_t: float:
	get: return cur["mana_prev_t"]
	set(v): cur["mana_prev_t"] = v
var mage_gear: Dictionary:
	get: return cur["mage_gear"]
	set(v): cur["mage_gear"] = v
# battles and the island's raiders (web: S.battles, content.js / v78.js Bandit Gangs and monsters)
var battles := []
var bandit_count := 0
var monster_count := 0
## the battles' and patrols' dice (web: Math.random); tests pin it
var battle_rand: Callable
var js_rand: Callable        # the web game's other Math.random draws (tests pin it)
static var test_random := -1.0   # tests: every new game's js_rand returns this
var tutorial = null          # a Tutorial while the Basic Tutorial runs
var dev_t := -1.0            # web: V106.t (development's own clock)
## development's lucky finds (web: Math.random); tests replace it
var dev_rand: Callable
var auto_tech: Dictionary:
	get: return cur["auto_tech"]
	set(v): cur["auto_tech"] = v
var queues: Dictionary:  # "capital:<p>" / "barracks:<p>" / "magetower:<p>" -> [{kind, paid, t0}]
	get: return cur["queues"]
	set(v): cur["queues"] = v
var rally: Dictionary:  # queue key -> {prov, x, y}
	get: return cur["rally"]
	set(v): cur["rally"] = v
var military := {}           # unit kinds that are soldiers (web: game.js MILITARY)
var finds := {}              # province -> {id: "ruins" | "treasure", done}
var treasure_rolled := {}
var sp_found := {}
# quests, relics and dig sites (Godot only; docs/QUESTS_PLAN.md, scripts/sim/quests.gd)
static var QUESTS := true    # tests that compare against the web game turn quests off
var quests_on := false       # this game has quests (full maps only)
var quest_pick := []         # the quests chosen for this map
var digs := {}               # province -> {item, shown, star}: a relic buried there
var chests := {}             # province -> [item ids]: relics left on the ground
var star_next := -1.0        # when the next Fallen Star falls
var stars_fallen := 0        # how many have fallen (each draws from its own stream)
var star_fx := []            # the view's shooting stars: {prov, t0} (not saved)
var quest_log: Dictionary:   # this human nation's quests: id -> {state: active|done|failed, t0, part, t1, by}
	get: return cur["quest_log"]
	set(v): cur["quest_log"] = v
var quest_rate: Dictionary:  # research points every cycle won from quests, for good: tree -> points
	get: return cur["quest_rate"]
	set(v): cur["quest_rate"] = v
var quest_unlocks: Array:    # what quests have unlocked: "armor:bone_regalia", "spell:flamewall", ...
	get: return cur["quest_unlocks"]
	set(v): cur["quest_unlocks"] = v

# --- fog (web: S.wf, S.known, S.explored, S.visible) ---
var wf: Dictionary:  # provinces a Wayfinder has entered
	get: return cur["wf"]
	set(v): cur["wf"] = v
var known: Dictionary:  # provinces kept discovered (armies, Far Sight)
	get: return cur["known"]
	set(v): cur["known"] = v
var explored: Dictionary:
	get: return cur["explored"]
	set(v): cur["explored"] = v
var visible: Dictionary:
	get: return cur["visible"]
	set(v): cur["visible"] = v

# --- time ---
var t := 0.0
var next_tick := 0.0
var paused := true
var last := 0.0
var started := false

# --- constants ---
var BUILD_DEFS: Dictionary:
	get: return cur["BUILD_DEFS"]
	set(v): cur["BUILD_DEFS"] = v
var CAPITAL_BONUS: Dictionary
var TICK: float
var TECH_BY_ID: Dictionary:
	get: return cur["TECH_BY_ID"]
	set(v): cur["TECH_BY_ID"] = v
# this game's own copies, with the player's race's names (web: swamp.js / wood.js applyRace change the globals)
var TECHS: Array:
	get: return cur["TECHS"]
	set(v): cur["TECHS"] = v
var TECH_TREES: Dictionary:
	get: return cur["TECH_TREES"]
	set(v): cur["TECH_TREES"] = v
var UNIT_BASE: Dictionary:
	get: return cur["UNIT_BASE"]
	set(v): cur["UNIT_BASE"] = v
var BUILD_ORDER: Array:
	get: return cur["BUILD_ORDER"]
	set(v): cur["BUILD_ORDER"] = v
var CMD: Dictionary:
	get: return cur["CMD"]
	set(v): cur["CMD"] = v
var LEADERS: Dictionary
var DSTATS: Dictionary
var SLOTS: Array
var UNIT_SPEED: Dictionary
var SPEED: float
var WAYFINDER: String
var rng := RandomNumberGenerator.new()   # stands in for the web's Math.random (names, shuffles); not seeded by the map

# --- seats (multiplayer step 1): each human nation's own fields ---
## The fields each human nation has its own copy of. The properties above read and write the current seat's
## record (`cur`); use_seat() switches it. A single-player game has one seat, HOST.
const SEAT_FIELDS := ["leader", "capital", "stock", "income", "income_parts", "army_counter", "tech", "rep", "surveyed", "designs", "exhaust", "exhaust_ok", "harvest", "upgrades", "xup", "cd", "harvest_by", "trap", "school_popup", "reveals", "eyes", "haunts", "mana_pool", "mana_prev", "mana_prev_t", "mage_gear", "auto_tech", "queues", "rally", "wf", "known", "explored", "visible", "my_nation", "train_orders", "met", "fallen", "ally_ask", "met_at", "dx_step_t", "gift_vault", "demand", "ally_offer", "quest_log", "quest_rate", "quest_unlocks", "BUILD_DEFS", "TECH_BY_ID", "TECHS", "TECH_TREES", "UNIT_BASE", "BUILD_ORDER", "CMD"]

## A new seat's record: every seat field at its starting value.
static func seat_defaults() -> Dictionary:
	return {
		"leader": "",
		"capital": -1,
		"stock": {},
		"income": {"gold": 0, "wood": 0, "food": 0},
		"income_parts": {},
		"army_counter": 0,
		"tech": {},
		"rep": {},
		"surveyed": {},
		"designs": [],
		"exhaust": 0,
		"exhaust_ok": 0,
		"harvest": null,
		"upgrades": {},
		"xup": {},
		"cd": {},
		"harvest_by": null,
		"trap": null,
		"school_popup": false,
		"reveals": [],
		"eyes": [],
		"haunts": [],
		"mana_pool": [],
		"mana_prev": {},
		"mana_prev_t": -1.0,
		"mage_gear": {"weapon": "stave", "shield": null},
		"auto_tech": {"gov": false, "mil": false, "mag": false},
		"queues": {},
		"rally": {},
		"wf": {},
		"known": {},
		"explored": {},
		"visible": {},
		"BUILD_DEFS": {},
		"TECH_BY_ID": {},
		"TECHS": [],
		"TECH_TREES": {},
		"UNIT_BASE": {},
		"BUILD_ORDER": [],
		"CMD": {},
		"my_nation": {"name": "My Realm", "color": 0, "emblem": "crown", "secondary": "#faf1dc"},
		"train_orders": [],
		"met": {},
		"demand": null,
		"ally_offer": null,
		"ally_ask": {},
		"fallen": false,
		"met_at": -9.0,
		"gift_vault": 0,
		"dx_step_t": -1.0,
		"quest_log": {},
		"quest_rate": {},
		"quest_unlocks": [],
	}


## Switch the seat fields to human nation o's; for anyone else (a computer nation, raiders) they stay as they are.
func use_seat(o) -> void:
	if o != ME and seats.has(o):
		_swap_dipl(o)
		ME = o
		cur = seats[o]


static func _sorted(d: Dictionary) -> Dictionary:
	var ks := d.keys()
	ks.sort_custom(func(x, y): return str(x) < str(y))
	var out := {}
	for k in ks:
		out[k] = d[k]
	return out


# use_seat: the seat in use's own diplomacy (requests, news, spies) out of `dipl`, seat o's in
func _swap_dipl(o: int) -> void:
	var park := {}
	for k in DIPL_SEAT_KEYS:
		if dipl.has(k):
			park[k] = dipl[k]
	seat_dipl[ME] = park
	var mine: Dictionary = seat_dipl.get(o, {})
	for k in DIPL_SEAT_KEYS:
		if mine.has(k):
			dipl[k] = mine[k]
		else:
			dipl.erase(k)
	seat_dipl.erase(o)


func is_human(o) -> bool:
	return seats.has(o)


## The human nations' ids, smallest first (the order every copy runs them in).
func seat_ids() -> Array:
	var ks := seats.keys()
	ks.sort()
	return ks


## f's result with seat o's fields (o a human nation), switching back afterwards.
func in_seat(o, f: Callable):
	var keep: int = ME
	use_seat(o)
	var r = f.call()
	use_seat(keep)
	return r


## f once for each human nation, each with its own fields, then back to the seat it started in.
func each_seat(f: Callable) -> void:
	var keep: int = ME
	for o in seat_ids():
		use_seat(o)
		f.call()
	use_seat(keep)


## Who plays nation o (multiplayer step 2): "human" (a seat), "ai" (a computer nation) or "" (raiders, nobody).
func controller(o) -> String:
	return "human" if seats.has(o) else "ai" if nations.has(o) else ""


func _init() -> void:
	BUILD_DEFS = GameData.c("BUILD_DEFS")
	Quests.install_gear()   # (the quest armors, Tier V: Godot only)
	CAPITAL_BONUS = GameData.c("CAPITAL_BONUS")
	TICK = GameData.c("TICK")
	for x in TECHS:
		TECH_BY_ID[x.id] = x
	LEADERS = GameData.c("LEADERS")
	DSTATS = GameData.c("DSTATS").duplicate()   # this game's designs are added to it
	# the data dump was taken during a game: drop the computer nations' designs it happened to hold
	for k in DSTATS.keys():
		if str(k).begins_with("ai") and str(k).substr(2, 1).is_valid_int():
			DSTATS.erase(k)
	SLOTS = GameData.c("SLOTS")
	UNIT_SPEED = GameData.c("UNIT_SPEED").duplicate()
	SPEED = GameData.c("SPEED")
	WAYFINDER = GameData.c("WAYFINDER")
	unit_defs = GameData.c("UNIT_DEFS").duplicate(true)
	for k in GameData.c("MILITARY"):
		military[k] = true
	seat_start("realm")
	dev_rand = rng.randf
	battle_rand = rng.randf
	js_rand = rng.randf
	if test_random >= 0:
		js_rand = func() -> float: return test_random


## The current seat's starting Armory, race tables and stock.
func seat_start(rc: String) -> void:
	# the Realmlings' Armory starts with these designs (web: equip.js; the other races' designs never train here)
	designs = []
	for d in [["d-spear", "inf", "spear"], ["d-sword", "inf", "shortsword"], ["d-club", "inf", "club"], ["d-rider", "cav", "spear"]]:
		designs.append({"id": d[0], "name": unit_defs[d[0]].name, "type": d[1], "weapon": d[2], "shield": null, "armor": "leather1",
			"horse": "riding" if d[1] == "cav" else null, "builtin": true, "race": "realm"})
	Races.apply(self, rc)
	stock = GameData.c("START_STOCK").duplicate()


## A second (third, ...) human nation at capital `cap` (multiplayer): its own seat, started like the host's.
## nation: {name, color, emblem, secondary} as on the New Game page.
func add_seat(o: int, cap: int, rc: String, nation: Dictionary = {}) -> void:
	var keep: int = ME
	seats[o] = seat_defaults()
	use_seat(o)
	var names := {}   # (the unit table is shared: it keeps the host's race's names)
	for k in unit_defs:
		names[k] = [unit_defs[k].get("name"), unit_defs[k].get("blurb")]
	seat_start(rc if rc in ["realm", "swamp", "wood"] else "realm")
	Quests.add_tables(self)   # (a player joining a game under way gets the Reliquary too)
	for k in names:
		unit_defs[k].name = names[k][0]
		if names[k][1] != null:
			unit_defs[k].blurb = names[k][1]
	set_nation(nation)
	start_capital(cap, false)
	use_seat(keep)


## A new Practice-island game, as menu.js startGame() runs it for a Realmling player with every computer slot closed.
## leader: a Realmling leader id ("havva", "finn", ...) or "" for a random one.
static func new_practice(seed: String, leader_id := "", map: Dictionary = {}, nation: Dictionary = {}, race := "") -> Game:
	var g := Game.new()
	g.pick_race(race, leader_id)
	g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_practice(seed))
	g.G = WorldPrep.prep(g.world)
	g.set_nation(nation)
	g.setup_game()
	g.place_setpieces()
	var skip := {}
	var ruins := g.place_ruins()
	if ruins >= 0:
		skip[ruins] = true
	g.spawn_lairs(skip)
	for u in g.units:
		if u.get("bandit", false):
			skip[u.prov] = true
	g.place_travelers(skip)
	g.assign_leader(leader_id)
	g.apply_leader_start()
	g.compute_income()
	g.compute_fog()
	g.started = true
	g.last = 0.0
	g.next_tick = 0.0
	return g


## The player's race: the one asked for, else the leader's, else Realmlings (web: menu.js startGame → applyRace)
func pick_race(race: String, leader_id := "") -> void:
	if race == "" and LEADERS.has(leader_id):
		race = LEADERS[leader_id].race
	if not race in ["realm", "swamp", "wood"]:
		race = "realm"
	Races.apply(self, race)


# --- races (web: swamp.js raceOf / isSw, wood.js isWd) ---
func race(o := ME) -> String:
	return race_of.get(o, "realm")


func is_sw(o := ME) -> bool:
	return race(o) == "swamp"


func is_wd(o := ME) -> bool:
	return race(o) == "wood"


# ---------------------------------------------------------------------------------------------------------------
# setup

# web: game.js setupGame() (the player's land is grassland). where: "center", "edge" or "random" (menu Start position)
# web: features.js NATION / applyNation: your nation's name, color and flag (chosen on the New Game page)
var my_nation: Dictionary:
	get: return cur["my_nation"]
	set(v): cur["my_nation"] = v


func set_nation(n: Dictionary) -> void:
	var NAT: Dictionary = GameData.c("NATION")
	var em := str(n.get("emblem", NAT.emblem))
	if not em in Races.EMBLEMS.get(race(), Races.EMBLEMS.realm):   # (each race flies its own flags)
		em = Races.EMBLEMS.get(race(), Races.EMBLEMS.realm)[0]
	my_nation = {"name": str(n.get("name", NAT.get("name", "My Realm"))).strip_edges().left(24), "color": int(n.get("color", NAT.color)), "emblem": em, "secondary": str(n.get("secondary", "#faf1dc"))}
	if my_nation.name == "":
		my_nation.name = "My Realm"
	var NC: Array = GameData.c("NATION_COLORS")
	var c: Array = NC[clampi(my_nation.color, 0, NC.size() - 1)]
	if players.is_empty():
		players = GameData.c("PLAYERS").duplicate(true)
	players[str(ME)] = {"name": my_nation.name, "color": c[0], "light": c[1]}


# web: menu.js mapMode / mapOptsOf: "normal" is the classic island (2 peninsulas, 2 coves, the usual trees);
# anything else is "map:<shape>:<peninsulas>:<coves>:<trees>"
static func map_mode(o: Dictionary) -> String:
	if o.is_empty():
		return "normal"
	var shape: String = o.get("shape", "classic")
	var pens: int = o.get("pens", 2)
	var coves: int = o.get("coves", 2)
	var trees: int = o.get("trees", 0)
	return "normal" if shape == "classic" and pens == 2 and coves == 2 and trees == 0 else "map:%s:%d:%d:%d" % [shape, pens, coves, trees]


static func map_opts_of(mode: String) -> Dictionary:
	var m := mode.split(":")
	if m.size() == 5 and m[0] == "map":
		return {"shape": m[1], "pens": int(m[2]), "coves": int(m[3]), "trees": int(m[4])}
	return {"shape": "classic", "pens": 2, "coves": 2, "trees": 0}


func setup_game(where := "center") -> void:
	open_nbr = []
	all_nbr = []
	for p in world.provinces:
		open_nbr.append([])
		all_nbr.append(p.nbr)
	for e in world.edges:
		if not e.open:
			continue
		var a: Array = world.vertices[e.v[0]]
		var b: Array = world.vertices[e.v[1]]
		var m := [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0]
		open_nbr[e.a].append({"q": e.b, "m": m})
		open_nbr[e.b].append({"q": e.a, "m": m})
	var bd: Array = G.bounds
	var mx: float = (bd[0] + bd[2]) / 2.0
	var my: float = (bd[1] + bd[3]) / 2.0
	var home_ter: String = Races.HOME[race()]
	var home := []
	for i in G.provs.size():
		if G.provs[i].terrain == home_ter:
			home.append(i)
	var home2 := home.filter(func(i): return not unique_ban(i))
	var cands: Array = home2 if not home2.is_empty() else home if not home.is_empty() else range(G.provs.size()).filter(func(i): return not unique_ban(i))
	var fit := func(i: int) -> float: return open_nbr[i].size() * 420 - (2000 if G.provs[i].coastal or G.provs[i].lakeside else 0)
	var best := -1
	if where == "random":
		var good := cands.filter(func(i): return open_nbr[i].size() >= 2 and not G.provs[i].coastal and not G.provs[i].lakeside)
		var pool := good if not good.is_empty() else cands.filter(func(i): return open_nbr[i].size() >= 1)
		if pool.is_empty():
			pool = cands
		best = pool[int(floor(js_rand.call() * pool.size()))]
	else:
		var bs := -INF
		var inland := cands.filter(func(i): return not G.provs[i].coastal and not G.provs[i].lakeside and open_nbr[i].size() >= 2)
		for i in (inland if where == "edge" and not inland.is_empty() else cands):
			var P: Dictionary = G.provs[i]
			var d := JS.hypot(P.ic[0] - mx, P.ic[1] - my)
			var sc: float = fit.call(i) + (d * 1.5 if where == "edge" else -d)
			if sc > bs:
				bs = sc
				best = i
	if G.provs[best].terrain != home_ter:
		G.provs[best].terrain = home_ter
	roll_yields()
	start_capital(best, true)


## The current seat's start at province best: its capital, research, Wayfinder, Mason and first army.
## first: the host's (the unit list starts here); later seats add to it.
func start_capital(best: int, first: bool) -> void:
	if G.provs[best].terrain != Races.HOME[race()]:
		G.provs[best].terrain = Races.HOME[race()]
		if best < variant.size():
			variant[best] = ""   # (a capital moved onto its race's home terrain is plain)
	capital = best
	buildings[best] = {"stage": 2, "born": -10, "owner": ME}
	surveyed[best] = -10
	tech = {}
	for tr in ["gov", "mil", "mag"]:
		tech[tr] = {"cur": null, "prog": 0, "bank": 0, "opts": [], "done": [], "tier": 1 if tr == "gov" else 0, "sticky": []}
	if is_sw():   # web: swamp.js applyRace (Swamplings know Mushroom Farming from the start)
		tech.gov.done.append("mushroom")
	draw_options("gov")
	if first:
		units = [mk_unit(1, GameData.c("WAYFINDER"), unit_defs[GameData.c("WAYFINDER")].name, best, 3), mk_unit(2, MASON, unit_defs[MASON].name, best, 4)]
		next_id = maxi(next_id, 3)
	else:
		units.append(mk_unit(next_id, GameData.c("WAYFINDER"), unit_defs[GameData.c("WAYFINDER")].name, best, 3))
		units.append(mk_unit(next_id + 1, MASON, unit_defs[MASON].name, best, 4))
		next_id += 2
	new_army(best, {footman_of(): 3})
	compute_income()
	compute_fog()


# web: game.js rollYields() (+ v95.js uniques and tutorial.js shore trees: neither exists on the Practice island)
func roll_yields() -> void:
	var r := Mulberry32.from_string(str(world.seed) + ":resources")
	yields = []
	for p in world.provinces:
		var y := {"gold": 0, "wood": 0, "food": 0}
		var bonus := {"gold": 0, "wood": 0, "food": 0}
		var roll := func(k: String, chance: float) -> void:
			if r.next() < chance:
				y[k] += 1
				bonus[k] += 1
		match p.terrain:
			"grassland":
				y.gold = 1; y.wood = 2; y.food = 3
				roll.call("food", 0.5); roll.call("wood", 0.25); roll.call("gold", 0.1)
			"forest":
				y.gold = 1; y.wood = 3; y.food = 2
				roll.call("wood", 0.5); roll.call("food", 0.25); roll.call("gold", 0.1)
			"desert":
				y.gold = 1
				roll.call("gold", 0.25)
			"swamp":
				y.wood = 2; y.food = 1
				if r.next() < 0.25:
					var k := "wood" if r.next() < 0.5 else "food"
					y[k] += 1
					bonus[k] += 1
		# a hidden gold deposit (25% in deserts, 5% elsewhere), found by surveying
		var deposit := r.next() < (0.25 if p.terrain == "desert" else 0.05)
		y.bonus = bonus
		y.deposit = deposit
		yields.append(y)
	refresh_tree_borders()


# web: v105.js refreshTreeBorders() (same count as rollYields' treeBorder)
	# v95: the Oasis and the Heart have their own; every province around Death Mountain gets +5 gold
	var U = uq()
	if U != null:
		var set_y := func(p: int, y: Dictionary) -> void:
			if p >= 0 and p < yields.size():
				yields[p].merge(y, true)
				yields[p].bonus = {"gold": 0, "wood": 0, "food": 0}
				yields[p].deposit = false
		set_y.call(U.oasis, {"gold": 10, "wood": 10, "food": 10})
		set_y.call(U.heart, {"gold": 6, "wood": 20, "food": 6})
		if U.death >= 0:
			set_y.call(U.death, {"gold": 0, "wood": 0, "food": 0})
			for q in world.provinces[U.death].nbr:
				yields[q].gold += 5
				yields[q].bonus.gold += 5
	roll_variants()


## Terrain variants (Godot 0.18, not in the web game): a tenth of each terrain is Drylands, Meadow, Fae Forest or Bog,
## picked with their own random numbers so the island and every other roll stay as the web game makes them.
const VARIANT_OF := {"desert": "drylands", "grassland": "meadow", "forest": "fae", "swamp": "bog"}
const VARIANT_NAME := {"drylands": "Drylands", "meadow": "Meadow", "fae": "Fae Forest", "bog": "Bog"}
const VARIANT_YIELD := {"drylands": {"gold": 1, "food": 1, "wood": 1}, "meadow": {"gold": 2, "food": 3, "wood": 3},
	"fae": {"gold": 1, "food": 3, "wood": 5}, "bog": {"gold": 2, "food": 2, "wood": 2}}
const VARIANT_LUCK := {"meadow": 0.25, "fae": 0.25}   # a chance of +1 in a random resource
const VARIANT_TEXT := {"drylands": "Golden grass over dry ground: a little of everything.",
	"meadow": "Flowering meadow: Farms here give +3 food each.",
	"fae": "An old, enchanted wood: Lumber Mills here harvest +3 wood each.",
	"bog": "Deep bog: everyone but Swamplings moves at half speed, defenders +30%. Buildings cost double (Swamplings: half)."}
const BOG_DEF := 1.3


func roll_variants() -> void:
	variant = []
	variant.resize(world.provinces.size())
	variant.fill("")
	if not VARIANTS:
		return
	var r := Mulberry32.from_string(str(world.seed) + ":variants")
	var U = uq()
	var skip := {}
	if U != null:
		for k in ["death", "oasis", "heart"]:
			skip[int(U.get(k, -1))] = true
		for q in (world.provinces[U.oasis].nbr if int(U.get("oasis", -1)) >= 0 else []):
			skip[q] = true   # (the deserts round the Oasis border forests and mountains: they stay plain desert)
	for ter in VARIANT_OF:
		var cands := []
		for i in world.provinces.size():
			if G.provs[i].terrain == ter and not skip.has(i) and not (ter == "desert" and _by_woods_or_peaks(i)):
				cands.append(i)
		var n := int(floor(cands.size() * 0.1 + 0.5))
		for k in n:
			var j := k + int(floor(r.next() * (cands.size() - k)))
			var tmp = cands[k]
			cands[k] = cands[j]
			cands[j] = tmp
			var p: int = cands[k]
			var v: String = VARIANT_OF[ter]
			variant[p] = v
			var y: Dictionary = yields[p]
			for res in VARIANT_YIELD[v]:
				y[res] = VARIANT_YIELD[v][res]
			y.bonus = {"gold": 0, "wood": 0, "food": 0}
			if r.next() < VARIANT_LUCK.get(v, 0.0):
				var res: String = ["gold", "wood", "food"][int(floor(r.next() * 3))]
				y[res] += 1
				y.bonus[res] = 1


## Drylands never border a forest or a mountain range.
func _by_woods_or_peaks(p: int) -> bool:
	for q in world.provinces[p].nbr:
		if G.provs[q].terrain == "forest":
			return true
	for id in world.provinces[p].edges:
		if world.edges[id].style == "mountains":
			return true
	return false


func variant_of(p: int) -> String:
	return str(variant[p]) if p >= 0 and p < variant.size() else ""


## A building's price in province p for nation o: double in a Bog, half for Swamplings.
func bog_cost(p: int, o: int, cost: Dictionary) -> Dictionary:
	if variant_of(p) != "bog":
		return cost
	var m := 0.5 if is_sw(o) else 2.0
	var out := {}
	for k in cost:
		out[k] = int(ceil(cost[k] * m))
	return out


## The terrain's name with its variant, e.g. "Fae Forest" or "grassland".
func terrain_name(p: int) -> String:
	var v := variant_of(p)
	return VARIANT_NAME[v] if v != "" else str(G.provs[p].terrain)


func refresh_tree_borders() -> void:
	tree_border = []
	for i in world.provinces.size():
		var n := 0
		for e in world.edges:
			if (e.a == i or e.b == i) and not e.open and (e.style == "trees" or e.style == "palms"):
				n += 1
		tree_border.append(n)


# web: game.js mkUnit()
func mk_unit(id: int, kind: String, name: String, prov: int, slot: int) -> Dictionary:
	var xy := slot_pos(prov, slot)
	if kind == GameData.c("WAYFINDER") or kind == MASON:
		name = cute_name()
	return {"id": id, "owner": ME, "kind": kind, "name": name, "prov": prov, "slot": slot, "x": xy[0], "y": xy[1], "th": 0.0,
		"path": [], "moving": false, "build": null, "survey": null, "scouting": null, "surveyQueue": [], "pendingSurvey": -1,
		"pending": null, "autoWalk": null, "exploreSp": 0.0, "nextAuto": 0.0}


# web: game.js slotPos()
func slot_pos(prov: int, k: int) -> Array:
	var ic: Array = G.provs[prov].ic
	var o: Array = SLOTS[k % SLOTS.size()]
	return [ic[0] + o[0], ic[1] + o[1]]


# web: game.js freeSlot()
func free_slot(prov: int, u) -> int:
	var used := {}
	for v in units:
		if not is_same(v, u) and v.prov == prov and v.slot >= 0:
			used[v.slot] = true
	var k := 0
	while used.has(k):
		k += 1
	return k


# web: game.js newArmy() (without `near`)
func new_army(prov: int, troops: Dictionary, near = null) -> Dictionary:
	army_counter += 1
	var a := mk_unit(next_id, "army", ordinal(army_counter) + " Army", prov, 0)
	next_id += 1
	a.troops = troops
	a.slot = free_slot(prov, a)
	var xy := slot_pos(prov, a.slot)
	a.x = xy[0]
	a.y = xy[1]
	if near != null:
		a.x = near.x + 10
		a.y = near.y + 8
		order(a, prov, true)
	units.append(a)
	return a


func cute_name() -> String:
	var names: Array = GameData.c("CUTE_NAMES")
	return names[rng.randi() % names.size()]


# web: game.js ORD(n): 1st, 2nd, 3rd, 4th, 11th, 21st...
static func ordinal(n: int) -> String:
	var suf := "th"
	if not (n % 100 >= 11 and n % 100 <= 13):
		suf = ["th", "st", "nd", "rd"][n % 10] if n % 10 < 4 else "th"
	return str(n) + suf


# web: equip.js footmanOf()
func footman_of(o := ME) -> String:
	return Races.FOOTMAN[race(o)]


# ---------------------------------------------------------------------------------------------------------------
# leaders (web: v105.js assignLeaders / applyLeaderStart, v106.js applyLeaderStart wrapper)

func assign_leader(id: String) -> void:
	assign_leader0(id)
	if leader in Ai.FORGE_LEADERS:   # web: v105.js (Forges cost 25% less for Finn, Glurg and Alathandrious)
		var c := {}
		for k in GameData.c("BUILD_DEFS").forge.cost:
			c[k] = int(JS.round_js(GameData.c("BUILD_DEFS").forge.cost[k] * 0.75))
		BUILD_DEFS.forge.cost = c


func assign_leader0(id: String) -> void:
	if LEADERS.has(id) and LEADERS[id].race == race():
		leader = id
		return
	var pool := []
	for k in LEADERS:
		if LEADERS[k].race == race():
			pool.append(k)
	leader = pool[rng.randi() % pool.size()]


func leader_of(o := ME):
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return leader_of(o))
	if o == ME:
		return LEADERS.get(leader)
	return LEADERS.get(nations[o].get("leader", "")) if nations.has(o) else null


# web: v105.js dxShuffle: sorted by Math.random keys
func dx_shuffle(arr: Array) -> Array:
	var keyed := arr.map(func(x): return [js_rand.call(), x])
	keyed = JS.stable_sort(keyed, func(p, q): return signf(p[0] - q[0]))
	return keyed.map(func(p): return p[1])


# web: v105.js pickLeader / assignLeaders: every computer nation gets a leader nobody else has
func pick_leader(o: int, taken: Dictionary) -> String:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return pick_leader(o, taken))
	var sc = null if o == ME else nations[o].school
	var ok := LEADERS.keys().filter(func(k): return LEADERS[k].race == race(o) and (LEADERS[k].get("school") == null or sc == null or LEADERS[k].school == sc))
	var fresh := ok.filter(func(k): return not taken.has(k))
	var pool: Array = fresh if not fresh.is_empty() else ok
	return dx_shuffle(pool)[0]


func assign_ai_leaders() -> void:
	var taken := {leader: true}
	for id in nations:
		var N: Dictionary = nations[id]
		N.leader = pick_leader(id, taken)
		taken[N.leader] = true
	for id in nations:
		var L = LEADERS.get(nations[id].leader)
		if L != null and L.get("school") != null and nations[id].school == null:
			nations[id].wantSchool = L.school


## web: v105.js applyLeaderStart(o) with the v106.js wrapper (the Horsemistress), for any nation
func apply_leader_start(o := ME) -> void:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		in_seat(o, func(): apply_leader_start(o))
		return
	apply_leader_start0(o)
	if o != ME and nations.has(o):
		nations[o].income = Ai.income(self, nations[o])


func apply_leader_start0(o := ME) -> void:
	var L = leader_of(o)
	var cap := cap_of(o)
	if L == null or cap < 0:
		return
	match L.start:
		"mage":
			add_start_extra(cap, "magetower")
			set_start_army({GameData.c("MAGE"): 1}, o)
			var st: Dictionary = stock_of(o)
			for k in RES:
				st[k] = st.get(k, 0) + 200
		"stable":
			add_start_extra(cap, "stable")
			add_start_tech("stable", o)
			set_start_army({"d-rider": 2}, o)
		"shield":
			add_start_extra(cap, "barracks")
			add_start_tech("s-round", o)
			set_start_army({leader_design_for(o, LEADER_DESIGNS["Shield Footman"]): 6}, o)
		"forge":
			add_start_extra(cap, "forge")
			add_start_tech("forge", o)
		"lumber":
			ensure_woodlines(cap, 2)
			add_start_extra(cap, "lumber")
			add_start_extra(cap, "lumber")
		"scouts":
			add_start_scouts(2, o)
			if not RULES19:   # (0.19: no Automating Wayfinders in her kit any more)
				add_start_tech("autoscout", o)
			add_start_tech("stealth", o)
			add_start_tech("farsight", o)
		"ogres":
			add_start_tech("stable", o)
			set_start_army({"d-sw-ogre": 2}, o)
		"twin":
			add_start_extra(cap, "barracks")
			add_start_tech("dualwield", o)
			set_start_army({leader_design_for(o, LEADER_DESIGNS["Twin-Axe Berserker"]): 6}, o)
		"navigator":
			add_start_scouts(3, o)
			set_start_army({"rng-swamp": 3}, o)
		"champion":
			add_start_tech("stable", o)
			set_start_army({"d-wd-champ": 1}, o)
		"twohand":
			add_start_extra(cap, "barracks")
			add_start_tech("twohand", o)
			set_start_army({leader_design_for(o, LEADER_DESIGNS["Two-Handed Protector"]): 6}, o)
		"farms":
			add_start_extra(cap, "farm")
			add_start_extra(cap, "farm")
		"ranger":
			add_start_scouts(2, o)
			set_start_army({"rng-wood": 6}, o)
	# v106: the Horsemistress starts with 4 riders, her Stable costs no upkeep, and the capital grows 7 more food
	if L.start == "stable" or L.start == "ogres":
		set_start_army({"d-rider" if L.start == "stable" else "d-sw-ogre": 4}, o)
		var found := false
		for e in extras_in(cap):
			if e.type == "stable":
				e.freeFor = o
				found = true
				break
		if not found and L.start == "ogres":
			var e = add_start_extra(cap, "stable")
			if e != null:
				e.freeFor = o
		yields[cap].food += GameData.c("LEADER_CAP_FOOD")
		compute_income()


func cap_of(o: int) -> int:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return cap_of(o))
	return capital if o == ME else nations[o].capital if nations.has(o) else -1


func stock_of(o: int) -> Dictionary:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return stock_of(o))
	return stock if o == ME else nations[o].stock if nations.has(o) else {"gold": 0, "wood": 0, "food": 0}


# a design for a leader's starting soldiers: the player's go into the Armory, a computer nation's are registered only
func leader_design_for(o: int, d: Dictionary) -> String:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return leader_design_for(o, d))
	if o == ME:
		return leader_design(d)
	var spec: Dictionary = d.spec.duplicate()
	spec.id = "ai%dlead" % o
	spec.name = d.name
	register_design(spec)
	return spec.id


# web: v105.js addStartExtra()
func add_start_extra(p: int, type: String):
	var slot := free_plot(p)
	if slot < 0:
		return null
	var e := {"type": type, "slot": slot, "born": -10}
	if not extras.has(p):
		extras[p] = []
	extras[p].append(e)
	return e


# web: v105.js addStartTech()
func add_start_tech(id: String, o := ME) -> void:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		in_seat(o, func(): add_start_tech(id, o))
		return
	var x = TECH_BY_ID.get(id)
	if x == null:
		return
	var st: Dictionary = tech[x.tree] if o == ME else nations[o].tech[x.tree]
	if not st.done.has(id):
		st.done.append(id)
	st.opts.erase(id)
	if st.cur == id:
		st.cur = null
		st.prog = 0
	if st.has("sticky"):
		st.sticky.erase(id)


# web: v105.js setStartArmy()
func set_start_army(troops: Dictionary, o := ME) -> void:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		in_seat(o, func(): set_start_army(troops, o))
		return
	var cap := cap_of(o)
	units = units.filter(func(v): return not (v.owner == o and v.kind == "army" and v.prov == cap))
	if troops.is_empty():
		return
	if o == ME:
		new_army(cap, troops.duplicate())
	else:
		ai_new_army(nations[o], cap, troops)


# web: v105.js addStartScouts()
func add_start_scouts(total: int, o := ME) -> void:
	var wf: String = GameData.c("WAYFINDER")
	var have := 0
	for v in units:
		if v.owner == o and v.kind == wf:
			have += 1
	while have < total:
		var u := mk_unit(next_id, wf, "", cap_of(o), 5 + have)
		next_id += 1
		u.owner = o
		units.append(u)
		have += 1


# web: equip.js designStats + champStats (Swampling dual wielding and Ogres, Woodling Champions and two-handing)
const OGRE_ARMOR := 0.8
const CHAMP := {"hp": 70, "speed": 0.72, "armor": 4, "cost": {"gold": 300}, "upkeep": {"food": 4}}

func design_stats(d: Dictionary) -> Dictionary:
	var rc: String = d.get("race", "realm") if d.get("race") != null else "realm"
	var WS: Dictionary = GameData.c("WEAPONS")
	var AS: Dictionary = GameData.c("ARMORS")
	var FAM: Dictionary = GameData.c("FAMILY")
	var ak: float = GameData.c("ARMOR_K")
	if rc == "wood" and d.type == "cav":
		var W: Dictionary = WS[d.weapon] if WS.has(d.weapon) and WS[d.weapon].get("champ", false) else WS.champsword
		var A: Dictionary = AS[d.armor] if AS.has(d.armor) and AS[d.armor].type == "ornate" else AS.ornate1
		var armor: float = A.armor + CHAMP.armor
		var cost := _add_cost(_add_cost(CHAMP.cost, W.cost), armor_cost(A))
		var st := {"cav": true, "champ": true, "ogre": false, "race": "wood", "rough": true, "plate": true, "fam": W.fam, "atk": W.atk,
			"hp": CHAMP.hp + W.get("hp", 0) + armor_hp(A), "armor": armor, "shieldArmor": 0, "red": armor / (armor + ak),
			"parry": 0.1 if W.fam == "thrust" or W.fam == "sword" else 0.0, "crit": 0.1 if W.fam == "axe" else 0.0,
			"speed": float(JS.to_fixed(CHAMP.speed * A.speed * W.get("spd", 1.0), 2)), "cost": cost, "upkeep": CHAMP.upkeep.duplicate(), "two": d.get("two", false)}
		st.blurb = "%s, %s armor. %s.%s" % [W.name, A.name, FAM[W.fam].note, " Two-handed swings: heavy blows every other round (125% damage over time)." if d.get("two", false) else ""]
		return st
	var sw := rc == "swamp"
	var B: Dictionary = UNIT_BASE[d.type] if UNIT_BASE else GameData.c("UNIT_BASE")[d.type]
	var W: Dictionary = WS[d.weapon]
	var A: Dictionary = AS[d.armor]
	var Sh = GameData.c("SHIELD_DEFS")[d.shield] if rc == "realm" and d.get("shield") != null and not W.twoH else null
	var H = (GameData.c("OGRES") if sw else GameData.c("HORSES"))[d.get("horse") if d.get("horse") != null else "riding"] if d.type == "cav" else null
	var Off = WS[d.off] if sw and d.get("off") != null and not W.twoH and WS.has(d.off) and not WS[d.off].twoH else null
	var armor: float = A.armor * (OGRE_ARMOR if sw and d.type == "cav" else 1.0) + (Sh.armor if Sh else 0) + (H.armor if H else 0)
	var cost := {}
	for c in [B.cost, W.cost, armor_cost(A), Sh.cost if Sh else {}, H.cost if H else {}, Off.cost if Off else {}]:
		cost = _add_cost(cost, c)
	cost.erase("food")
	var speed: float = float(JS.to_fixed((H.speed if H else B.speed) * A.speed * (Sh.speed if Sh else 1), 2))
	var lv: int = int(A.level)
	var st := {"cav": d.type == "cav", "ogre": sw and d.type == "cav", "race": rc, "rough": H != null and H.get("rough", false),
		"plate": A.type in GameData.c("PLATE_TYPES"), "fam": W.fam, "atk": float(JS.to_fixed(W.atk + (Off.atk * 0.5 if Off else 0.0) + (H.get("atk", 0) if H else 0), 1)),
		"hp": B.hp + (H.get("hp", 0) if H else 0) + armor_hp(A), "armor": armor, "shieldArmor": Sh.armor if Sh else 0,
		"red": armor / (armor + ak), "parry": 0.1 if W.fam == "sword" or W.fam == "thrust" else 0.0, "crit": 0.1 if W.fam == "axe" else 0.0,
		"speed": speed, "cost": cost, "upkeep": {"food": maxf(0, B.upkeep.food + (H.get("upFood", 0) if H else 0))}}
	st.blurb = "%s%s%s, %s armor%s. %s.%s" % [W.name, (" and " + Off.name + " (off hand, half damage)") if Off else "", (" and " + Sh.name) if Sh else "",
		A.name, (", " + H.name) if H else "", FAM[W.fam].note, (" No " + ("Ogre" if sw else "cavalry") + " penalty in forest or swamp.") if H and H.get("rough", false) else ""]
	if rc == "wood" and d.get("two", false):
		st.two = true
		st.blurb += " Two-handed grip: heavy blows every other round (125% damage over time)."
	return st


## An armor's health: its tier's (ARMOR_HP), or its own (the quest armors, Tier V).
static func armor_hp(A: Dictionary) -> int:
	return int(A.hp) if A.has("hp") else int(GameData.c("ARMOR_HP")[int(A.level)])


## An armor's price: 0.19 makes every armor 10% cheaper (RULES19; the web-game tests keep the old prices).
static func armor_cost(A: Dictionary) -> Dictionary:
	var c: Dictionary = A.get("cost", {})
	if not RULES19:
		return c
	var out := {}
	for k in c:
		out[k] = int(JS.round_js(float(c[k]) * 0.9))
	return out


static func _add_cost(a: Dictionary, b: Dictionary) -> Dictionary:
	var c := a.duplicate()
	for k in b:
		c[k] = c.get(k, 0) + b[k]
	return c


# web: v105.js leaderDesign() for the player: reuse a design of that name, else add it to the Armory
func leader_design(d: Dictionary) -> String:
	for x in designs:
		if x.name == d.name:
			return x.id
	var spec: Dictionary = d.spec.duplicate()
	spec.name = d.name
	return add_design(spec).id


# --- the Armory (web: equip.js addDesign / registerDesign / saveDraft / deleteDesign, v78.js nextDesignName) ---
var design_seq := 0

func add_design(o: Dictionary) -> Dictionary:
	design_seq += 1
	var rc: String = o.get("race", "realm") if o.get("race") != null else "realm"
	var d := {"id": "d%d" % design_seq, "name": o.name, "type": o.type, "weapon": o.weapon, "shield": o.get("shield") if rc == "realm" else null,
		"off": o.get("off"), "armor": o.armor, "horse": o.get("horse", "riding") if o.type == "cav" and rc != "wood" else null, "builtin": false, "race": rc}
	if o.get("two", false):
		d.two = true
	if d.type == "cav" and d.horse == null and rc != "wood":
		d.horse = "riding"
	designs.append(d)
	register_design(d)
	return d


func register_design(d: Dictionary) -> void:
	var st := design_stats(d)
	# 0.19: how heavy its armor looks on the map (0 leather, 1 chain, 2 plate, and the other races' twins)
	var A = GameData.c("ARMORS").get(str(d.get("armor", "")))
	st["look"] = {"chain": 1, "wyvern": 1, "mithril": 1, "plate": 2, "dragon": 2, "ornate": 2}.get(str(A.type), 0) if A is Dictionary else 0
	if A is Dictionary and A.get("quest") != null:   # (quests: which Battlegear its soldiers wear)
		st["quest_armor"] = str(A.quest)
	DSTATS[d.id] = st
	var blurb: String = st.blurb
	unit_defs[d.id] = {"name": d.name, "cost": st.cost, "upkeep": st.upkeep, "blurb": blurb, "design": true}
	military[d.id] = true
	UNIT_SPEED[d.id] = st.speed


# web: magic.js mageStats (+ v102.js the stave's and wand's spell bonus in the blurb)
func mage_stats(gear: Dictionary) -> Dictionary:
	var MW: Dictionary = GameData.c("MAGE_WEAPONS")
	var W: Dictionary = MW[gear.weapon]
	var Sh = GameData.c("SHIELD_DEFS")[gear.shield] if gear.get("shield") != null and not W.twoH and race() == "realm" else null
	var armor: float = 1 + (Sh.armor if Sh else 0)
	var md: Dictionary = unit_defs[MAGE]
	var st := {"cav": false, "rough": false, "fam": "magic", "line": W.line, "atk": W.atk, "hp": 25, "armor": armor, "shieldArmor": Sh.armor if Sh else 0,
		"red": armor / (armor + float(GameData.c("ARMOR_K"))), "parry": 0, "speed": 0.8 * (Sh.speed if Sh else 1.0), "cost": md.cost, "upkeep": md.upkeep,
		"blurb": "%s%s." % [W.name, (" and " + Sh.name) if Sh else ""]}
	var add := []
	if STAVE_CAST.has(gear.weapon):
		add.append("Spells cast %d%% faster." % roundi((1 - STAVE_CAST[gear.weapon]) * 100))
	if WAND_MANA.has(gear.weapon):
		add.append("Spells cost %d%% less mana." % roundi((1 - WAND_MANA[gear.weapon]) * 100))
	# web: v95.js / v102.js — a Swampling Warlock holds a skull, never a shield: it adds to the wand's attack and
	# shortens the Fireball
	var Sk = GameData.c("SKULLS").get(gear.get("skull")) if is_sw() and gear.get("skull") != null and not W.twoH else null
	if Sk != null:
		st.atk += Sk.atk
		st.blurb = "%s and %s." % [W.name, Sk.name]
		add.append("The Fireball casts %d s faster." % (2 * int(Sk.get("lv", 1))))
	if not add.is_empty():
		st.blurb += " " + " ".join(add)
	return st


func skull_cut(o: int) -> float:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return skull_cut(o))
	if o != ME or not is_sw():
		return 0.0
	var W: Dictionary = GameData.c("MAGE_WEAPONS")[mage_gear.weapon]
	var Sk = GameData.c("SKULLS").get(mage_gear.get("skull")) if mage_gear.get("skull") != null else null
	return 2.0 * int(Sk.get("lv", 1)) if Sk != null and not W.twoH else 0.0


## Equip every Mage with this gear (the Armory's "Equip all Mages"). web: equip.js saveDraft (type mage), magic.js registerMage
func set_mage_gear(gear: Dictionary) -> void:
	var W: Dictionary = GameData.c("MAGE_WEAPONS")[gear.weapon]
	mage_gear = {"weapon": gear.weapon, "shield": null if W.twoH or race() != "realm" else gear.get("shield")}
	if is_sw() and not W.twoH and gear.get("skull") != null:
		mage_gear.skull = gear.skull
	register_mage()
	var sh = mage_gear.shield
	var nm: String = GameData.c("SHIELD_DEFS")[sh].name if sh != null else GameData.c("SKULLS")[mage_gear.skull].name if mage_gear.get("skull") != null else ""
	toast("%ss now carry a %s%s." % [unit_defs[MAGE].name, W.name, (" and a " + nm) if nm != "" else ""])


func register_mage() -> void:
	DSTATS[MAGE] = mage_stats(mage_gear)
	UNIT_SPEED[MAGE] = DSTATS[MAGE].speed


## Why a Mage weapon or shield can't be chosen yet (a technology to research), or null.
func mage_gear_why(kind: String, k: String):
	var item: Dictionary = GameData.c("MAGE_WEAPONS")[k] if kind == "weapon" else GameData.c("SKULLS")[k] if kind == "skull" else GameData.c("SHIELD_DEFS")[k]
	var tch = item.get("tech")
	return null if tch == null or has_tech(tch) else "Research " + TECH_BY_ID[tch].name


func design_by_id(id: String):
	for d in designs:
		if d.id == id:
			return d
	return null


func design_in_use(id: String) -> bool:
	if units.any(func(u): return u.kind == "army" and u.troops.get(id, 0) > 0):
		return true
	for key in queues:
		if queues[key].any(func(q): return q.kind == id):
			return true
	return false


## Why a piece of gear can't be picked yet (null: it can). web: equip.js lockWhy
func gear_why(kind: String, key: String):
	var table := {"weapon": "WEAPONS", "off": "WEAPONS", "shield": "SHIELD_DEFS", "armor": "ARMORS", "horse": "OGRES" if is_sw() else "HORSES"}
	if kind == "off" and not has_tech("dualwield"):
		return "Research " + TECH_BY_ID.dualwield.name
	var item = GameData.c(table[kind]).get(key)
	if item == null:
		return "Unknown"
	if item.get("tech") != null and not has_tech(item.tech):
		return "Research " + (TECH_BY_ID[item.tech].name if TECH_BY_ID.has(item.tech) else str(item.tech))
	if not Quests.gear_unlocked(self, ME, item):
		return "Locked: finish its quest"
	return null


## Save the Armory draft: a design not in use is changed in place; a starting design or one in use is saved as a new
## design (named Footman II, III … when the name is unchanged). Returns the saved design.
func save_design(draft: Dictionary) -> Dictionary:
	var name: String = str(draft.name).strip_edges().left(24)
	if name == "":
		name = "Design"
	var cur: Variant = design_by_id(draft.id) if draft.get("id") != null else null
	if cur != null and not cur.builtin and not design_in_use(cur.id):
		for k in ["type", "weapon", "shield", "off", "armor", "horse", "two"]:
			cur[k] = draft.get(k)
		cur.name = name
		if GameData.c("WEAPONS")[cur.weapon].twoH:
			cur.shield = null
		register_design(cur)
		toast("%s saved." % cur.name)
		return cur
	if cur != null and cur.name == name:
		name = next_design_name(name)
	var o := draft.duplicate()
	o.name = name
	if GameData.c("WEAPONS")[o.weapon].twoH:
		o.shield = null
	var d := add_design(o)
	if cur != null:
		toast("%s: saved as a new design, %s." % ["Starting designs can't be changed" if cur.builtin else cur.name + " is in use", d.name])
	else:
		toast("%s added to the Armory. Train it at a Barracks%s." % [d.name, " with a Stable" if d.type == "cav" else ""])
	return d


func delete_design(id: String) -> bool:
	var d = design_by_id(id)
	if d == null or d.builtin:
		return false
	if design_in_use(id):
		toast("%s can't be deleted while soldiers of that design are alive or in training." % d.name, true)
		return false
	designs.erase(d)
	military.erase(id)
	toast("%s deleted." % d.name)
	return true


static func _to_roman(n: int) -> String:
	var out := ""
	for vr in [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"], [50, "L"], [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]:
		while n >= vr[0]:
			out += vr[1]
			n -= vr[0]
	return out


static func _from_roman(t: String) -> int:
	var V := {"I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000}
	var n := 0
	for i in t.length():
		var a: int = V[t[i]]
		var b: int = V.get(t[i + 1], 0) if i + 1 < t.length() else 0
		n += -a if a < b else a
	return n


func next_design_name(name: String) -> String:
	var re := RegEx.create_from_string("^(.*?)((?:\\s+[IVXLCDM]+)+)$")
	var m := re.search(name)
	var base := m.get_string(1) if m else name
	var n := 1
	if m:
		for w in m.get_string(2).strip_edges().split(" ", false):
			n = maxi(n, _from_roman(w))
	var k := n + 1
	var out := ""
	while true:
		out = (base + " " + _to_roman(k)).left(24)
		k += 1
		if not designs.any(func(d): return d.name == out) or k >= 200:
			break
	return out


# web: v105.js ensureWoodlines(): turn mountain or ruin borders of the capital into tree borders (random order)
func ensure_woodlines(p: int, n: int) -> void:
	var have := 0
	var cands := []
	for e in world.edges:
		if (e.a == p or e.b == p) and not e.open:
			if e.style == "trees" or e.style == "palms":
				have += 1
			elif e.style == "mountains" or e.style == "ruins":
				cands.append(e)
	var need := n - have
	if need <= 0:
		return
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	for e in cands:
		if need <= 0:
			break
		e.style = "trees"
		need -= 1
	refresh_tree_borders()


# ---------------------------------------------------------------------------------------------------------------
# provinces and plots

func owned(i: int) -> bool:
	return buildings.has(i) and buildings[i].owner == ME


func extras_in(p: int) -> Array:
	return extras.get(p, [])


# web: game.js plotCap(): Conquered Capitals have 6 plots, Auto-build outposts one more
func plot_cap(p: int) -> int:
	if not buildings.has(p):
		return 0
	var b: Dictionary = buildings[p]
	if b.get("cc", false):
		return 6
	return GameData.c("PLOTS_BY_STAGE")[b.stage] + (1 if b.stage == 0 and tech_of(b.owner, "autobuild") else 0)


# web: game.js usedSlots() (building sites and pending orders come with the Mason)
func used_slots(p: int) -> Dictionary:
	var used := {}
	for e in extras_in(p):
		used[e.slot] = true
	return used


# web: flags.js freePlot()
func free_plot(p: int) -> int:
	var used := used_slots(p)
	for k in plot_cap(p):
		if not used.has(k):
			return k
	return -1


# web: game.js buildCap()
func build_cap(p: int, type: String) -> int:
	return 4 if type == "farm" else tree_border[p] if type == "lumber" else 1


## Your upkeep split into units and buildings (the Country Breakdown's table). web: v78.js upkeepSplit
func upkeep_split() -> Dictionary:
	var us := {"gold": 0, "wood": 0, "food": 0}
	var bl := {"gold": 0, "wood": 0, "food": 0}
	for v in units:
		if v.owner != ME:
			continue
		if v.kind == "army":
			for tk in v.troops:
				var d = unit_defs.get(tk)
				if d != null:
					for k in d.get("upkeep", {}):
						us[k] += d.upkeep[k] * v.troops[tk]
			continue
		var d = unit_defs.get(v.kind)
		if d != null:
			for k in d.get("upkeep", {}):
				us[k] += d.upkeep[k]
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.owner != ME:
			continue
		for e in extras_in(p):
			var up: Dictionary = BUILD_DEFS[e.type].get("upkeep", {})
			for k in up:
				bl[k] += up[k]
		if b.stage == 0:
			for k in OUTPOST_UPKEEP:
				bl[k] += OUTPOST_UPKEEP[k]
	return {"units": us, "blds": bl}


func provs_of(o := ME) -> Array:
	var out := []
	for p in buildings:
		if buildings[p].owner == o:
			out.append(p)
	return out


# web: govtech.js provLimit / perFort / fortsHeldBy, v106.js devLimitBonus
func prov_limit() -> int:
	var forts := 0
	for p in buildings:
		if buildings[p].owner == ME and buildings[p].stage >= 1:
			forts += 1
	var per_fort: int = GameData.c("OUTPOSTS_PER_FORT") + (2 if has_tech("effadmin") else 0) + 2 * rep_lv("rep-admin")
	return forts * (1 + per_fort) + dev_limit_bonus()


# web: v106.js devLimitBonus(): developed forts and capitals hold more provinces
func dev_limit_bonus(o := ME) -> int:
	var dev := 0
	for p in devel:
		var r: Dictionary = devel[p]
		if r.get("lv", 0) and buildings.has(p) and buildings[p].owner == o and buildings[p].stage >= 1:
			dev += r.lv
	return dev


# web: v106.js overLimit()
func over_limit() -> int:
	return maxi(0, provs_of().size() - prov_limit())


# ---------------------------------------------------------------------------------------------------------------
# research (only what the economy reads; the tech trees are ported in step 7)

func has_tech(id: String) -> bool:
	var x = TECH_BY_ID.get(id)
	return x != null and tech[x.tree].done.has(id)


func rep_lv(id: String) -> int:
	return rep.get(id, 0)


# web: tech.js techBonus()
func tech_bonus() -> Dictionary:
	var y := {"gold": 0, "wood": 0, "food": 0}
	for k in tech:
		for id in tech[k].done:
			var g: Dictionary = TECH_BY_ID[id].get("gives", {})
			for r in g:
				y[r] += g[r]
	return y


# ---------------------------------------------------------------------------------------------------------------
# income and upkeep

# web: govtech.js givesOf() + swamp.js (Markets: MARKET_GIVES for Realmlings) + v105.js (Lumber leaders +1 wood)
func gives_of(type: String) -> Dictionary:
	if type == "market":
		return {} if is_sw() else GameData.c("MARKET_GIVES").duplicate()
	var base: Dictionary = BUILD_DEFS[type].get("gives", {}).duplicate()
	var tg = GameData.c("TECH_GIVES").get(type)
	if tg != null:
		for id in tg[0]:
			if has_tech(id):
				for k in tg[1]:
					base[k] = base.get(k, 0) + tg[1][k]
	if type == "lumber" and leader in ["weylyn", "roxx"]:
		base.wood = base.get("wood", 0) + 1
	return base


# web: game.js extrasBonus() + v104.js crops (a Farm gives its crop's resources) + v105.js Ultanitous (+1 by crop)
# + v106.js deep gold mines
func extras_bonus(p: int) -> Dictionary:
	var y := {"gold": 0, "wood": 0, "food": 0}
	for e in extras_in(p):
		var gv := gives_of(e.type)
		for k in gv:
			y[k] += gv[k]
	var st := gives_of("farm")
	for e in extras_in(p):
		if e.type == "farm" and Ai.crop_of(e) != "staple":
			var g := Ai.crop_gives(Ai.crop_of(e), st)
			for k in st:
				y[k] -= st[k]
			for k in g:
				y[k] = y.get(k, 0) + g[k]
	if leader == "ultanitous":
		for e in extras_in(p):
			if e.type == "farm":
				y[Ai.CROP_PLUS[Ai.crop_of(e)]] += 1
	var v := variant_of(p)
	if v == "meadow" or v == "fae":   # 0.18: Farms in a Meadow +3 food, Lumber Mills in a Fae Forest +3 wood
		for e in extras_in(p):
			if v == "meadow" and e.type == "farm":
				y.food += 3
			elif v == "fae" and e.type == "lumber":
				y.wood += 3
	var r = devel.get(p)
	if r != null and r.deep and extras_in(p).any(func(e): return e.type == "goldmine"):
		y.gold += GameData.c("DEV").deepGold   # v106: a Deep Gold Deposit
	return y


# web: game.js provinceIncome() (Trade Routes come with roads and markets)
func province_income(p: int, b: Dictionary) -> Dictionary:
	var x := extras_bonus(p)
	var y := {}
	for k in RES:
		y[k] = yields[p][k] + (CAPITAL_BONUS[k] if b.stage == 2 or b.get("cc", false) else 0) + x[k]
	if b.stage == 2 and b.owner == ME:
		y.gold += trade_gold()   # Trade Routes: markets the capital reaches by road
	if units.any(func(c): return c.owner == b.owner and c.prov == p and c.get("cast") != null and c.cast.spell == "q:fspirit"):   # web: v98.js Forest Spirit
		for k in y:
			if y[k] > 0:
				y[k] *= 2
	for P in sacreds:   # web: v98.js (a Sacred Pyre: +110 gold there every payout)
		if P.prov == p and P.owner == b.owner and P.until > t:
			y.gold += SACRED.gold
			break
	if is_sw(b.owner):   # web: swamp.js provinceIncome (Swamp Taxes, Thugs)
		var tx = swamp_tax(p, b)
		if tx != null:
			y.gold += tx.gold
			y.food += tx.food
		y.gold += thug_gold(p, b.owner)
	return y


# web: swamp.js swampTax: a Swampling settlement in a swamp makes +1 gold and +2 food per level
func swamp_tax(p: int, b: Dictionary):
	if is_sw(b.owner) and world.provinces[p].terrain == "swamp":
		return {"gold": b.stage + 1, "food": 2 * (b.stage + 1)}
	return null


# web: swamp.js denCap / thugGold (v105: +1 per Organized Crime Agreement)
func den_cap(o := ME) -> int:
	var n := 2 + (1 if tech_of(o, "thugs2") else 0) + (1 if tech_of(o, "thugs3") else 0)
	n += crime_slots(o)
	return n


func den_borders(p: int, o: int) -> bool:
	for q in all_nbr[p]:
		var n := nation_of(q)
		if n >= 0 and n != o and is_nation(n):
			return true
	return false


func thug_gold(p: int, o: int, full := false) -> int:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return thug_gold(p, o, full))
	var g := 0
	for e in extras_in(p):
		if e.type == "market":
			g += (den_cap(o) if full else int(e.get("thugs", 0))) * (2 if tech_of(o, "traderoutes") and den_borders(p, o) else 1)
	var rp: int = rep_lv("rep-trade") if o == ME else (int(nations[o].rep.get("rep-trade", 0)) if nations.has(o) else 0)
	return int(JS.round_js(g * (1 + 0.05 * rp)))


# web: content.js tradeMarkets / tradeGold + v105.js (a Trade Network: +10% each): the capital earns +1 gold for every
# Marketplace it reaches along roads, through your own unoccupied provinces
func trade_gold() -> int:
	if is_sw():   # web: swamp.js (Highwaymen: no roads, no market gold)
		return 0
	if is_wd():   # web: wood.js (Community: +1 gold per Bazaar for each other building in its province)
		if not has_tech("traderoutes"):
			return 0
		var nb := 0
		for p in extras:
			if not owned(p) or occ.has(p):
				continue
			var bz: int = extras[p].filter(func(e): return e.type == "market").size()
			if bz:
				nb += bz * (extras[p].size() - 1)
		return int(JS.round_js(nb * (1 + 0.05 * rep_lv("rep-trade"))))
	if not has_tech("traderoutes") or capital < 0 or not owned(capital):
		return 0
	var adj := {}
	for k in roads:
		var ab: PackedStringArray = k.split("_")
		var a := int(ab[0])
		var q := int(ab[1])
		if not adj.has(a):
			adj[a] = []
		if not adj.has(q):
			adj[q] = []
		adj[a].append(q)
		adj[q].append(a)
	var seen := {capital: true}
	var queue := [capital]
	var n := 0
	while not queue.is_empty():
		var a: int = queue.pop_front()
		for q in adj.get(a, []):
			if seen.has(q) or not owned(q) or occ.has(q):
				continue
			seen[q] = true
			queue.append(q)
			n += extras_in(q).filter(func(e): return e.type == "market").size()
	var g := int(JS.round_js(n * (1 + 0.05 * rep_lv("rep-trade"))))
	var tc := trade_count(ME)
	return int(JS.round_js(g * (1 + DIPL.tradeBonus * tc))) if tc and g else g


# web: content.js lumberBonus: Sawyer Guilds, +5% wood from every Lumber Mill per level, added up across the nation
func lumber_bonus() -> int:
	var n := rep_lv("rep-lumber")
	if not n:
		return 0
	var w := 0
	var per: int = int(gives_of("lumber").get("wood", 0))
	for p in extras:
		if owned(p) and not occ.has(p):
			for e in extras[p]:
				if e.type == "lumber":
					w += per
	return int(JS.round_js(w * 0.05 * n))


func troop_upkeep(kind: String) -> Dictionary:
	var d = unit_defs.get(kind)
	return d.get("upkeep", {}) if d != null else {}


# web: game.js upkeep() + v106.js upkeepAdjust() (+ v104.js fiber crops and v95.js the Crown come later)
func upkeep() -> Dictionary:
	var u := {"gold": 0, "wood": 0, "food": 0}
	for v in units:
		if v.owner != ME:
			continue
		if v.kind == "army":
			for tk in v.troops:
				var up := troop_upkeep(tk)
				for k in up:
					u[k] += up[k] * v.troops[tk]
			continue
		var up := troop_upkeep(v.kind)
		for k in up:
			u[k] += up[k]
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.owner != ME:
			continue
		for e in extras_in(p):
			var up: Dictionary = BUILD_DEFS[e.type].get("upkeep", {})
			for k in up:
				u[k] += up[k]
		if b.stage == 0:
			for k in OUTPOST_UPKEEP:
				u[k] += OUTPOST_UPKEEP[k]
	if has_art(ME, "crown"):   # v95: the King’s Crown, 20% off
		for k in u:
			u[k] = int(JS.round_js(u[k] * 0.8))
	for p in buildings:   # v104: a Fiber crop needs no wood upkeep
		if buildings[p].owner == ME:
			for e in extras_in(p):
				if e.type == "farm" and Ai.crop_of(e) == "fiber":
					u.wood -= Ai.crop_up(self, "staple")
	# v106: leader upkeep cuts, buildings that cost a leader nothing, over the province limit
	for v in units:
		if v.owner == ME and v.kind == "army":
			u.food -= leader_upkeep_cut(v.troops)
	for p in buildings:
		if buildings[p].owner == ME:
			for e in extras_in(p):
				if e.has("freeFor") and buildings[p].owner == e.freeFor:
					var up: Dictionary = BUILD_DEFS[e.type].get("upkeep", {})
					for k in up:
						u[k] -= up[k]
	var n := over_limit()
	if n:
		for k in RES:
			u[k] += GameData.c("OVER_UPKEEP") * n
	for k in RES:
		u[k] = maxi(0, u[k])
	return u


# web: v106.js leaderUpkeepCut(): the Horsemistress' cavalry eat at most 3 food each
func leader_upkeep_cut(troops: Dictionary, o := ME) -> int:
	var L = leader_of(o)
	if L == null or not (L.id in ["hisola", "taal"]):
		return 0
	var cut := 0
	for k in troops:
		var n: int = troops[k]
		if not n or not unit_defs.has(k) or not unit_defs[k].has("upkeep"):
			continue
		var f: int = unit_defs[k].upkeep.get("food", 0)
		if DSTATS.has(k) and DSTATS[k].get("cav", false) and (L.id == "hisola" or DSTATS[k].get("ogre", false)):
			cut += maxi(0, f - 3) * n
	return cut


# web: game.js computeIncome() (+ v104.js / magic.js Harvest, content.js Sawyer Guilds: off until those are ported)
func compute_income() -> void:
	var gross := {"gold": 0, "wood": 0, "food": 0}
	var up := upkeep()
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.owner == ME and not occ.has(p):
			var y := province_income(p, b)
			for k in RES:
				gross[k] += y[k]
	var tb := tech_bonus()
	for k in RES:
		gross[k] += tb[k]
	if harvest_by != null:   # v104: Harvest by crop, food from every crop and gold from Cash crops
		var pct := harvest_pct()
		var st := gives_of("farm")
		var food := 0
		var gold := 0
		for p in extras:
			if owned(p) and not occ.has(p):
				for e in extras[p]:
					if e.type == "farm":
						var g := Ai.crop_gives(Ai.crop_of(e), st)
						food += g.get("food", 0)
						gold += g.get("gold", 0)
		gross.food += int(JS.round_js(food * pct))
		gross.gold += int(JS.round_js(gold * pct))
	gross.wood += lumber_bonus()   # Sawyer Guilds
	income = {}
	for k in RES:
		income[k] = gross[k] - up[k]
	income_parts = {"gross": gross, "up": up}
	for kv in [["gold", "goldskull"], ["wood", "stump"]]:   # v95: the Gold Dragon Skull and the Enchanted Stump
		if has_art(ME, kv[1]):
			income[kv[0]] += 50
			gross[kv[0]] += 50


# web: govtech.js storageCap()
func storage_cap(k: String) -> int:
	var n: int = GameData.c("BASE_CAP") + 500 * rep_lv("rep-storage") + (2000 if k == "gold" and has_art(ME, "goldskull") else 0) + debug_cap
	for p in extras:
		if owned(p):
			for e in extras[p]:
				var st = store_of(e.type, ME)
				if st != null and st.has(k):
					n += st[k]
	return n


# web: swamp.js storeOf: a Swampling Bank is a Supply Cache
func store_of(type: String, o: int):
	if type == "bank":
		return Races.SUPPLY_STORE if is_sw(o) else Races.BANK_STORE
	return BUILD_DEFS[type].get("store") if BUILD_DEFS.has(type) else null


# web: govtech.js clampStock()
func clamp_stock() -> void:
	for k in RES:
		var c := storage_cap(k)
		if stock[k] > c:
			stock[k] = c


# web: govtech.js soldierCount() (Mages don't count)
func soldier_count(o := ME) -> int:
	var n := 0
	var mage: String = GameData.c("MAGE")
	for v in units:
		if v.kind == "army" and v.owner == o:
			for k in v.troops:
				if k != mage:
					n += v.troops[k]
	return n


# web: game.js payday(t) (+ gpc.js Army Exhaustion; research points and mana come with tech and magic)
func payday(_t: float) -> void:
	each_seat(func():
		var short: bool = stock.food + income.food < 0
		for k in RES:
			stock[k] = maxi(0, stock[k] + income[k])
		step_exhaustion(short))
	if not nations.is_empty():
		Ai.payday(self)
	each_seat(func():
		tech_payday()
		regen_mana())
	if quests_on:
		Quests.payday(self)
	if on_payday.is_valid():
		on_payday.call(_t)


## Called after every payday with its time (tests and the view listen here).
var on_payday: Callable


# web: govtech.js stepExhaustion(short)
func step_exhaustion(short: bool) -> void:
	if short and soldier_count() > 0:
		exhaust += 1
		exhaust_ok = 0
		if exhaust >= GameData.c("EXHAUST_MAX"):
			for v in units:
				if v.kind == "army" and v.owner == ME:
					v._gone = true
			units = units.filter(func(v): return not (v.kind == "army" and v.owner == ME))
			compute_income()
			exhaust = 0
			sfx("wn_unrest")
		elif exhaust == 5:
			sfx("wn_exhaust")
		return
	if exhaust > 0 and income.food >= 0 and stock.food > 0:
		exhaust_ok += 1
		if exhaust_ok >= 1:
			exhaust_ok = 0
			exhaust -= 1
	else:
		exhaust_ok = 0


# ---------------------------------------------------------------------------------------------------------------
# time

## One frame. web: game.js update(realT): real time in seconds; the game clock only runs while unpaused, at most
## 0.1 s per frame. Paydays fall every TICK seconds of game time.
func update(real_t: float) -> void:
	if not started:
		last = real_t
		return
	var rdt := minf(0.1, real_t - last if last != 0.0 else 0.0)
	last = real_t
	var dt := 0.0 if paused else rdt
	use_seat(HOST)
	t += dt
	# (multiplayer: a human nation's units move with its own fields; everything else with the host's)
	for u in units.duplicate():
		if not u.get("_gone", false):
			use_seat(u.owner if seats.has(u.owner) else HOST)
			step_unit(u, dt)
	use_seat(HOST)
	if next_tick == 0.0:
		next_tick = t + TICK
	while t >= next_tick:
		var nt := next_tick
		next_tick += TICK
		payday(nt)
	each_seat(func(): step_training(t))
	if not paused:
		meet_head_on()
		step_battles(t)
		if not nations.is_empty():
			step_war(t)
			step_ai(t)
		step_arrows(t)
		step_pyromancy(t)
		step_scouts(t)
		step_magic(t, dt)
		step_gpc(t, dt)
		step_patrols(t, dt)
		step_travelers(dt)
		if quests_on:
			Quests.step(self)
		use_seat(HOST)
	each_seat(clamp_stock)
	each_seat(func(): step_upgrades(t))
	if started and uq() != null:
		step_boss_halt()
	if started:
		step_flights()
	# web: v96.js stepV96 (war timers, bandit waves, rally points), then v105.js stepDiplomacy, then v106.js
	if not paused:
		if not nations.is_empty():
			step_war_timers()
		step_bandit_waves(t)
		each_seat(rally_arrivals)
	if not nations.is_empty():
		each_seat(step_diplomacy)
	var d := 0.0
	if paused:
		dev_t = t
	elif not each_fallen():
		d = 0.0 if dev_t < 0 or t < dev_t else t - dev_t
		dev_t = t
		d = minf(d, 1.0)
		step_develop(d)
		use_seat(HOST)
		if not nations.is_empty():
			Ai.step_enemies(self)
		each_seat(step_gift_vaults)
		each_seat(step_orders)
		if not nations.is_empty():
			for id in nations:
				Ai.develop(self, nations[id])
	each_seat(compute_fog)
	if not nations.is_empty():
		each_seat(update_met)
	if tutorial != null:
		tutorial.step()
	if not rec.is_empty():
		Recorder.step(self)   # web: v102.js stepRecord
	use_seat(view_seat)


## Development stops once every human nation has fallen (single-player: once you have).
func each_fallen() -> bool:
	for o in seats:
		if not seats[o].fallen:
			return false
	return true


# ---------------------------------------------------------------------------------------------------------------
# movement (web: game.js findPath / order / walkHops and the unit loop in update())

const EXPLORE_TIME := 8.0
const SCOUT_SLOW := 4.0
const SURVEY_TIME := 30.0
const BUILD_TIME := 30.0
const TREASURE_GOLD := 200

## Messages for the player (the web game's toasts). The view shows them; tests can ignore them.
var on_toast: Callable
var on_sfx: Callable        # the view's sound effects (web: sound.js sfx); the rules only name them
var fx := []                # what the view shows for a moment: blows (num), falling soldiers (fall), arrows (web: S.fx)
var spell_fx := []          # the moment a Fireball, Shockwave or Earthquake strikes (web: gpc.js S.spellFx)
var arrow_at := {}          # fort or capital -> when its arrowslits loose next (web: govtech.js S.arrowAt)
var _fx_n := 0


## A number between 0 and 1 for an effect's look only (never the rules' random numbers).
func fx_rand() -> float:
	_fx_n += 1
	return fposmod(sin(float(_fx_n) * 12.9898 + t * 78.233) * 43758.5453, 1.0)


## A sound effect for the view to play: its name (web: SFX_FILES), the province it comes from (quieter far from the
## camera; -1: everywhere) and its volume. web: sound.js sfx
func sfx(name: String, prov := -1, vol := 1.0) -> void:
	if on_sfx.is_valid():
		on_sfx.call(name, prov, vol)


func toast(msg: String, warn := false) -> void:
	if on_toast.is_valid() and ME == view_seat:   # (multiplayer: each copy shows its own player's messages)
		on_toast.call(msg, warn)


func exploring(u: Dictionary) -> bool:
	return u.kind == WAYFINDER and u.owner == ME and u.scouting != null


# web: game.js busy()
func busy(u: Dictionary) -> bool:
	return u.moving or u.survey != null or u.build != null or u.pending != null or u.pendingSurvey >= 0 or not u.surveyQueue.is_empty() or u.get("dig") != null


# web: game.js canEnter() — on the Practice island there are no other nations, bandits or bosses to keep out of
## `seen` (from enter_cache) answers the unit-scanning checks for a walk over many provinces; same answers.
func can_enter(u: Dictionary, q: int, tgt: int, seen := {}) -> bool:
	var ok: bool = u.owner != ME or u.get("exiting", false) or explored.has(q)
	if not ok and u.kind == WAYFINDER:
		ok = q == tgt or (u.autoWalk != null and q == u.autoWalk.to)
	elif not ok:
		ok = not wars.is_empty() and nation_of(q) != 0 and hostile(ME, nation_of(q))
	if not ok:
		return false
	if u.kind == WAYFINDER and u.owner == ME and (seen.bandits.has(q) if not seen.is_empty() else bandits_seen_in(q)):
		return false
	if u.kind == MASON and (seen.danger.has(q) if not seen.is_empty() else mason_danger(u, q)):
		return false
	if not nation_ok(u, q):
		return false
	if seen.is_empty():
		if boss_block(u, q, tgt):
			return false
	elif is_death_mtn(q) or (nations.has(u.owner) and q != tgt and seen.boss.has(q)):
		return false
	return true


## The provinces where can_enter's unit checks say no for this unit, worked out in one pass over the units:
## {bandits: seen Bandit Gangs, danger: a Mason's danger (mason_danger), boss: a boss standing there (boss_in)}.
func enter_cache(u: Dictionary) -> Dictionary:
	var bandits := {}
	var danger := {}
	var boss := {}
	for v in units:
		if v.get("bandit", false) and v.get("seen", false) and troop_count(v) > 0:
			bandits[v.prov] = true
		if v.get("boss") != null and troop_count(v) > 0:
			boss[v.prov] = true
		if u.kind == MASON and v.kind == "army" and troop_count(v) > 0 and not v.get("retreating", false) and hostile(v.owner, u.owner) \
				and (u.owner != ME or (v.get("seen", false) if v.get("bandit", false) else visible.has(v.prov))):
			danger[v.prov] = true
	return {"bandits": bandits, "danger": danger, "boss": boss}


# web: game.js nationOk: other nations' land only at war, in a truce, or with military access (v105)
func nation_ok(u: Dictionary, q: int) -> bool:
	if u.get("exiting", false) or u.owner == RAIDERS or (u.kind == WAYFINDER and (u.get("stealth", false) or u.get("detected", false))):
		return true
	var n := nation_of(q)
	return n == 0 or n == u.owner or hostile(u.owner, n) or truce_left(u.owner, n) > 0 or has_access(u.owner, n)


# web: game.js findPath: an army that finds no open way tries again through hostile walls it can batter
func find_path(u: Dictionary, target: int):
	var p = find_path_via(u, target, false)
	if p != null or u.kind != "army" or walls.is_empty():
		return p
	return find_path_via(u, target, true)


# web: game.js findPathVia: border crossings from u.prov to target, or null
func find_path_via(u: Dictionary, target: int, siege: bool):
	if target == u.prov:
		return []
	if not can_enter(u, target, target):
		return null
	var prev := {u.prov: null}
	var q := [u.prov]
	var h := 0
	while h < q.size():
		var a: int = q[h]
		h += 1
		if a == target:
			break
		for n in path_nbr(u, a, siege):
			if not prev.has(n.q) and (path_avoid == null or n.q == target or not path_avoid.has(n.q)) and can_enter(u, n.q, target):
				prev[n.q] = {"a": a, "m": n.m, "siege": n.get("siege", -1)}
				q.append(n.q)
	if not prev.has(target):
		return null
	var hops := []
	var c := target
	while c != u.prov:
		var pr: Dictionary = prev[c]
		var hop := {"to": c, "m": pr.m}
		if pr.siege >= 0:
			hop.siege = pr.siege
		hops.push_front(hop)
		c = pr.a
	return hops


## web: v101.js pathAvoid: while a computer nation's army is ordered at war, paths avoid where an outmatching enemy
## stands or is heading (the destination excepted)
var path_avoid = null


# web: game.js order(u, target, quiet, pt) + v101.js (computer armies at war steer clear of armies that would crush them)
## Quests: a scouting unit digs where it stands, or stops (orders; the rules are in Quests).
func start_dig(u: Dictionary) -> bool:
	return Quests.start_dig(self, u)


func stop_dig(u: Dictionary) -> void:
	Quests.stop_dig(self, u)


func order(u: Dictionary, target: int, quiet := false, pt = null) -> bool:
	if u.kind == "army" and nations.has(u.owner) and not enemies_of(u.owner).is_empty():
		path_avoid = Ai.danger_for(self, nations[u.owner], raw_strength([u]))
		var r := order0(u, target, quiet, pt)
		path_avoid = null
		return r
	return order0(u, target, quiet, pt)


func order0(u: Dictionary, target: int, quiet := false, pt = null) -> bool:
	if u.get("fleeing", false):
		if not quiet:
			toast("%s is running from bandits. He takes orders again once he is back." % u.name, true)
		return false
	if u.get("stasisUntil", 0.0) > t:
		return false
	if u.get("battle") != null and not u.get("retreating", false):
		if not quiet:
			toast("%s is in battle. Use Retreat to pull out." % u.name, true)
		return false
	if u.get("retreatHome", false):
		if not quiet:
			toast("%s is retreating and takes orders again once it gets there." % u.name, true)
		return false
	if exploring(u):
		if not quiet:
			toast("%s is exploring. Shift-click to queue orders for afterwards." % u.name, true)
		return false
	var hops = find_path(u, target)
	if hops == null:
		if not quiet:
			if u.kind == WAYFINDER:
				toast("No open route there. Trees, mountains, rivers and ruins block the way." if explored.has(target) else "He can only explore a province next to land you know. Explore the land in between first.", true)
			else:
				toast("The %s can only enter explored provinces, and needs an open route." % u.name, true)
		return false
	if u.build != null:
		cancel_build(u)
		toast("Construction cancelled. Resources refunded.")
	u.pending = null
	u.erase("roadPlan")
	if u.survey != null:
		u.survey = null
		toast("Survey cancelled.")
	walk_hops(u, hops, target, pt)
	return true


# web: game.js walkHops()
func walk_hops(u: Dictionary, hops: Array, target: int, pt = null) -> void:
	var wps := []
	var dest = Geo.clamp_into(G.provs[target], pt[0], pt[1]) if pt != null else null
	var at := [u.x, u.y]
	var in_prov: int = u.prov
	for h in hops:
		if not Geo.seg_clear(G.provs[in_prov], at, h.m):
			for qq in Geo.nav_route(G.provs[in_prov], at, h.m):
				wps.append({"x": qq[0], "y": qq[1]})
		var w := {"x": h.m[0], "y": h.m[1], "enter": h.to}
		if h.has("siege"):
			w.siege = h.siege
		wps.append(w)
		at = h.m
		in_prov = h.to
	if dest != null:
		if not Geo.seg_clear(G.provs[in_prov], at, dest):
			for qq in Geo.nav_route(G.provs[in_prov], at, dest):
				wps.append({"x": qq[0], "y": qq[1]})
		wps.append({"x": dest[0], "y": dest[1], "slot": true})
	u.path = wps
	u.moving = true
	u.slot = -1
	u.final = target
	if hops.is_empty() and dest == null:
		u.slot = free_slot(u.prov, u)
		var xy := slot_pos(u.prov, u.slot)
		u.path = [{"x": xy[0], "y": xy[1], "slot": true}]


# web: game.js haltUnit()
func halt_unit(u: Dictionary) -> void:
	u.path = []
	u.moving = false
	u.erase("final")
	u.pending = null
	u.surveyQueue = []
	u.pendingSurvey = -1
	u.autoWalk = null
	u.slot = -1


# web: game.js unitSpeed() / content.js troopSpeed() (speedMod: Aithne's sneaking Wayfinders come with stealth)
func unit_speed(u: Dictionary) -> float:
	if u.kind != "army":
		return UNIT_SPEED.get(u.kind, 1.0) * speed_mod(u)
	var m := INF
	for k in u.troops:
		if u.troops[k] > 0:
			m = minf(m, UNIT_SPEED.get(k, 1.0))
	return (m if m < INF else 1.0) * speed_mod(u)


# web: swamp.js speedMod + v95.js (Red Dragon Skull: 25% faster) + v105.js (Cerathon's Champions)
func speed_mod(u: Dictionary) -> float:
	var m := 1.0
	var L = leader_of(u.owner) if is_nation(u.owner) else null
	if L != null and L.id == "cerathon" and u.kind == "army":
		var a := INF
		var b := INF
		for k in u.troops:
			if u.troops[k] > 0:
				var sp: float = UNIT_SPEED.get(k, 1.0)
				a = minf(a, sp)
				b = minf(b, sp * (1.2 if DSTATS.has(k) and DSTATS[k].get("champ", false) else 1.0))
		if a > 0 and a < INF:
			m *= b / a
	if has_art(u.owner, "redskull"):
		m *= 1.25
	if u.get("pathFire") != null and u.pathFire.until > t:   # web: swamp.js speedMod (Path of Fire)
		m *= u.pathFire.mult
	var ter: String = world.provinces[u.prov].terrain if u.prov >= 0 and u.prov < world.provinces.size() else ""
	if ter == "swamp" and is_sw(u.owner):   # Swamplings: 20% faster in a swamp
		m *= 1.2
	if ter == "forest" and is_wd(u.owner):   # web: wood.js (Woodlings: 10% faster in a forest)
		m *= 1.1
	if u.prov >= 0 and variant_of(u.prov) == "bog" and not is_sw(u.owner):   # 0.18: a Bog halves everyone else
		m *= 0.5
	return m


static func facing(dx: float, dy: float) -> float:
	return JS.round_js(atan2(dx, dy) / (PI / 4)) * (PI / 4)


## One unit's share of a frame. web: the body of `for (const u of S.units)` in game.js update()
func step_unit(u: Dictionary, dt: float) -> void:
	if u.moving:
		var time := dt
		while time > 0 and not u.path.is_empty():
			if siege_hold(u, time):
				time = 0
				break
			var wp: Dictionary = u.path[0]
			var sp: float
			if u.scouting != null and u.exploreSp:
				sp = u.exploreSp
			else:
				sp = SPEED * unit_speed(u) / (SCOUT_SLOW if u.scouting != null else 1.0) * (road_speed() if on_road(u, wp) else 1.0)
			var dx: float = wp.x - u.x
			var dy: float = wp.y - u.y
			var d := JS.hypot(dx, dy)
			if d > 0.5:
				u.th = facing(dx, dy)
			if d <= sp * time:
				u.x = wp.x
				u.y = wp.y
				time -= d / sp
				u.path.pop_front()
				if wp.has("enter"):
					u.lastProv = u.prov
					u.prov = wp.enter
					if u.kind == "army" and not u.get("retreating", false) and not hostiles_in(u.prov, u.owner).is_empty():
						u.path = []
						u.moving = false
						u.slot = -1
						time = 0
						continue
					if u.get("retreating", false) and hostiles_in(u.prov, u.owner).is_empty():
						u.retreating = false
					u.scouting = wp.enter if (u.kind == WAYFINDER and u.owner == ME and not explored.has(wp.enter)) else null
					if u.kind == WAYFINDER and u.owner == ME and bandit_flee(u):
						time = 0
						continue
					if u.scouting != null:
						# into the fog: paced so that every province takes EXPLORE_TIME to explore
						var P: Dictionary = G.provs[u.prov]
						var c := Geo.clamp_into(P, P.ic[0], P.ic[1])
						var from := [u.x, u.y]
						var pts: Array = ([] if Geo.seg_clear(P, from, c) else Geo.nav_route(P, from, c)) + [c]
						var L := 0.0
						var at := from
						for qq in pts:
							L += JS.hypot(qq[0] - at[0], qq[1] - at[1])
							at = qq
						u.path = []
						for i in pts.size():
							u.path.append({"x": pts[i][0], "y": pts[i][1], "explore": i == pts.size() - 1})
						u.exploreSp = maxf(L, 1.0) / EXPLORE_TIME
						u.exploreT0 = t
						u.slot = -1
				elif u.scouting != null and u.scouting == u.prov and (wp.get("explore", false) or not u.exploreSp):
					# at the middle: the province is explored
					wf[u.prov] = true
					u.scouting = null
					u.exploreSp = 0.0
					if u.has("final") and u.final != u.prov and order(u, u.final, true):
						time = 0
						continue
				if u.path.is_empty() and not wp.get("slot", false):
					u.slot = free_slot(u.prov, u)
					var xy := slot_pos(u.prov, u.slot)
					u.path.append({"x": xy[0], "y": xy[1], "slot": true})
				elif u.path.is_empty() and wp.get("slot", false):
					u.moving = false
					u.th = 0.0
					u.arrived = t
					if u.get("fleeing", false):
						u.fleeing = false
					if u.get("retreating", false):
						u.retreating = false
					if u.get("retreatHome", false):
						u.retreatHome = false
						toast("%s is back under your command." % u.name)
					if u.get("exiting", false) and (nation_of(u.prov) == u.owner or u.get("exitTo", -1) == u.prov):
						u.exiting = false
						u.erase("exitTo")
			else:
				u.x += dx / d * sp * time
				u.y += dy / d * sp * time
				time = 0
	if u.kind == WAYFINDER and u.owner == ME and u.scouting == null:
		wf[u.prov] = true
	if u.survey != null:
		if u.moving or u.prov != u.survey.prov:
			u.survey = null
		else:
			var f := minf(1.0, (t - u.survey.t0) / u.survey.dur)
			var h := route_at(u.survey, f)
			var dx: float = h[0] - u.x
			var dy: float = h[1] - u.y
			if JS.hypot(dx, dy) > 0.3:
				u.th = facing(dx, dy)
			u.x = h[0]
			u.y = h[1]
			if f >= 1:
				surveyed[u.prov] = t
				var y: Dictionary = yields[u.prov]
				sfx("pr_survey", u.prov)
				toast("Survey complete: %d gold, %d wood, %d food every 10 s.%s" % [y.gold, y.wood, y.food, " Found a Hidden Gold Deposit!" if y.deposit else ""])
				sp_found[u.prov] = true
				if setpieces.has(u.prov):
					setpiece_found(u.prov, u)
				survey_finds(u)
				if quests_on:
					Quests.uncover(self, u)
				u.survey = null
				if u.surveyQueue.is_empty() or not (u.surveyQueue[0] is int):
					order(u, u.prov, true)
	auto_survey(u)
	step_survey_queue(u)
	if u.pending != null and not u.moving:
		var pb: Dictionary = u.pending
		u.pending = null
		if u.prov == pb.prov:
			if pb.type == "outpost":
				start_build(u)
			elif pb.type == "road":   # 0.19: the next stretch of a planned road
				road_next(u)
			else:
				begin_extra(u, pb.type, pb.get("slot", -1))
	if u.build != null:
		if u.moving or u.prov != u.build.prov:
			cancel_build(u)
		elif t - u.build.t0 >= u.build.get("dur", BUILD_TIME):
			finish_build(u)


# ---------------------------------------------------------------------------------------------------------------
# Wayfinders: surveys, exploring, automation

# web: game.js surveyRoute(u): a lap of the province's open ground, sized to take SURVEY_TIME at his pace
func survey_route(u: Dictionary) -> Dictionary:
	var P: Dictionary = G.provs[u.prov]
	var want := SPEED * unit_speed(u) * SURVEY_TIME
	var build := func(sc: float) -> Dictionary:
		var loop := []
		for v in P.inner:
			loop.append([P.ic[0] + (v[0] - P.ic[0]) * sc, P.ic[1] + (v[1] - P.ic[1]) * sc])
		var k0 := 0
		var bd := INF
		for i in loop.size():
			var d := JS.hypot(loop[i][0] - u.x, loop[i][1] - u.y)
			if d < bd:
				bd = d
				k0 = i
		loop = loop.slice(k0) + loop.slice(0, k0)
		loop.append(loop[0])
		var seg := []
		var L := 0.0
		for i in loop.size() - 1:
			var d := JS.hypot(loop[i + 1][0] - loop[i][0], loop[i + 1][1] - loop[i][1])
			seg.append(d)
			L += d
		return {"prov": u.prov, "t0": t, "loop": loop, "seg": seg, "L": L, "from": [u.x, u.y], "lead": bd, "total": bd + L}
	var lo := 0.05
	var hi := 0.92
	var r: Dictionary = build.call(hi)
	if r.total > want:
		for i in 24:
			var m := (lo + hi) / 2
			r = build.call(m)
			if r.total > want:
				hi = m
			else:
				lo = m
		r = build.call(lo)
	r.dur = r.total / (SPEED * unit_speed(u))
	return r


# web: game.js routeAt(site, f)
static func route_at(site: Dictionary, f: float) -> Array:
	var need: float = f * site.total
	if need <= site.lead:
		var a: Array = site.from
		var b: Array = site.loop[0]
		var k: float = need / site.lead if site.lead else 1.0
		return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k]
	need -= site.lead
	for i in site.seg.size():
		if need <= site.seg[i]:
			var a: Array = site.loop[i]
			var b: Array = site.loop[i + 1]
			var k: float = need / site.seg[i]
			return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k]
		need -= site.seg[i]
	var e: Array = site.loop[site.loop.size() - 1]
	return [e[0], e[1]]


# web: game.js startSurvey(u)
func start_survey(u: Dictionary) -> bool:
	if u.moving:
		toast("The Wayfinder has to stop walking before he can survey.", true)
		return false
	if u.survey != null:
		return false
	if surveyed.has(u.prov):
		toast("This province has already been surveyed.")
		return false
	for v in units:
		if not is_same(v, u) and v.survey != null and v.survey.prov == u.prov:
			toast("Someone is already surveying this province.")
			return false
	u.survey = survey_route(u)
	u.th = 0.0
	toast("Surveying the land…")
	return true


# web: game.js surveyQueued(p)
func survey_queued(p: int) -> bool:
	for v in units:
		if v.kind == WAYFINDER and v.owner == ME and (v.surveyQueue.has(p) or v.pendingSurvey == p or (v.survey != null and v.survey.prov == p)):
			return true
	return false


# --- orders for a group (web: game.js formation / orderGroup / queueSurvey / surveyWhy) ---

## Spots around a point for n units, in rings, so a group spreads out instead of stacking. web: game.js formation
static func formation(n: int, gap := 30.0) -> Array:
	var out := [[0.0, 0.0]]
	var ring := 1
	while out.size() < n:
		var k := 0
		while k < 6 * ring and out.size() < n:
			var a := float(k) / (6 * ring) * TAU + ring * 0.5
			out.append([cos(a) * gap * ring, sin(a) * gap * ring * 0.8])
			k += 1
		ring += 1
	return out


## Queued actions on a unit's list (surveys and moves). web: game.js queueLen
func queue_len(u: Dictionary) -> int:
	return u.surveyQueue.size() + (1 if u.pendingSurvey >= 0 else 0)


## Send the selected units to a province; with append (Shift) the move goes to the end of each busy unit's list.
## pt: the clicked point; each unit gets its own spot around it. Returns the units that set off (for their sound).
## web: game.js orderGroup
func order_group(units: Array, target: int, append := false, pt = null) -> Array:
	units = units.duplicate()
	if units.is_empty():
		return []
	var spots := {}
	if pt != null:
		var f := formation(units.size())
		var by := units.duplicate()
		by.sort_custom(func(a, b): return Vector2(a.x - pt[0], a.y - pt[1]).length() < Vector2(b.x - pt[0], b.y - pt[1]).length())
		for i in by.size():
			spots[by[i].id] = [pt[0] + f[i][0], pt[1] + f[i][1]]
	if append:
		var now := units.filter(func(u): return not busy(u))
		var later := units.filter(func(u): return busy(u))
		var full := later.filter(func(u): return queue_len(u) >= QUEUE_MAX)
		if not full.is_empty():
			toast("%s already %s %d queued actions, the most allowed." % [" and ".join(full.map(func(u): return u.name)), "have" if full.size() > 1 else "has", QUEUE_MAX], true)
		var ok := later.filter(func(u): return queue_len(u) < QUEUE_MAX)
		for u in ok:
			u.surveyQueue.append({"move": target, "pt": spots.get(u.id)})
		if not ok.is_empty() and full.is_empty():
			toast("Move queued (%s)." % ", ".join(ok.map(func(u): return "%s: %d orders" % [u.name, queue_len(u)])))
		return order_group(now, target, false, pt) if not now.is_empty() else []
	var busy_x := units.filter(func(u): return exploring(u))
	if not busy_x.is_empty():
		# exploring Wayfinders finish first: the order waits in their queue (a plain click replaces what was queued)
		for u in busy_x:
			u.surveyQueue = [{"move": target, "pt": spots.get(u.id)}]
			u.pendingSurvey = -1
			u.autoWalk = null
		toast("%s %s exploring and will go there once the province is explored." % [" and ".join(busy_x.map(func(u): return u.name)), "are" if busy_x.size() > 1 else "is"])
		var rest := units.filter(func(u): return not exploring(u))
		return order_group(rest, target, false, pt) if not rest.is_empty() else []
	for u in units:
		u.surveyQueue = []
		u.pendingSurvey = -1
		u.autoWalk = null
	if units.size() == 1:
		return units if order(units[0], target, false, spots.get(units[0].id)) else []
	var moved := units.filter(func(u): return order(u, target, true, spots.get(u.id)))
	var failed := units.filter(func(u): return not moved.has(u))
	if not failed.is_empty():
		toast(" and ".join(failed.map(func(u): return u.name)) + " can’t reach that province. Only a Wayfinder can enter unexplored land.", true)
	return moved


## Why the selected Wayfinders can't survey p, or null. web: game.js surveyWhy
func survey_why(p: int, ws: Array):
	if not explored.has(p):
		return "Explore it first"
	if surveyed.has(p):
		return "Already surveyed"
	if survey_queued(p):
		return "Already on a survey list"
	if not ws.any(func(w): return find_path(w, p) != null):
		return "No open route"
	return null


## Put p on the survey list of the selected Wayfinder with the fewest surveys to do; append (Shift) keeps what is
## already queued. web: game.js queueSurvey
func queue_survey_on(ws: Array, p: int, append := false) -> bool:
	if ws.is_empty():
		return false
	if not explored.has(p):
		toast("Only explored land can be queued. Walk him into the fog first.", true)
		return false
	if surveyed.has(p):
		toast("That province is already surveyed.", true)
		return false
	if survey_queued(p):
		toast("That province is already on a survey list.")
		return false
	var w: Dictionary = ws[0]
	for b in ws:
		if _surveys_in(b) < _surveys_in(w):
			w = b
	if find_path(w, p) == null:
		toast("No open route there.", true)
		return false
	if append and queue_len(w) >= QUEUE_MAX:
		toast("%s already has %d queued actions, the most allowed." % [w.name, QUEUE_MAX], true)
		return false
	w.autoWalk = null
	if not append:
		w.surveyQueue = []
		w.pendingSurvey = -1
		w.survey = null
	w.surveyQueue.append(p)
	toast("Survey %s (%d orders on %s’s list)." % ["queued" if append else "ordered", queue_len(w), w.name])
	return true


func _surveys_in(u: Dictionary) -> int:
	return u.surveyQueue.filter(func(e): return e is int).size() + (1 if u.pendingSurvey >= 0 else 0)


## Ask a Wayfinder to survey p (walking there first if needed). web: the Survey command queues it the same way.
func queue_survey(u: Dictionary, p: int) -> void:
	u.surveyQueue.append(p)


# web: game.js stepSurveyQueue(u)
func step_survey_queue(u: Dictionary) -> void:
	if u.owner != ME or u.survey != null or u.build != null or u.pending != null:
		return
	if u.pendingSurvey >= 0:
		if u.moving:
			return
		var p: int = u.pendingSurvey
		u.pendingSurvey = -1
		if u.prov == p and not surveyed.has(p):
			start_survey(u)
			return
	if u.moving or u.surveyQueue.is_empty():
		return
	while not u.surveyQueue.is_empty() and u.surveyQueue[0] is int and surveyed.has(u.surveyQueue[0]):
		u.surveyQueue.pop_front()
	if u.surveyQueue.is_empty():
		return
	var p = u.surveyQueue.pop_front()
	if not (p is int):
		if (u.prov != p.move or p.get("pt") != null) and not order(u, p.move, true, p.get("pt")):
			toast("%s skipped a queued move: no route there." % u.name, true)
		return
	if u.prov == p:
		start_survey(u)
		return
	if order(u, p, true):
		u.pendingSurvey = p


# web: govtech.js autoSurvey(u, t): with Automated Scouting, idle Wayfinders survey the nearest known province,
# then explore the nearest unknown one
func auto_survey(u: Dictionary) -> void:
	if u.kind != WAYFINDER or u.owner != ME or u.get("auto", true) == false or not has_tech("autoscout") or busy(u) or u.nextAuto > t:
		return
	u.nextAuto = t + 1
	var best := -1
	var bd := INF
	u.autoWalk = {"to": -1}
	for p in explored:
		if surveyed.has(p) or survey_queued(p):
			continue
		var hops = [] if p == u.prov else find_path(u, p)
		if hops == null:
			continue
		var d: float = hops.size() * 1000 + JS.hypot(G.provs[p].ic[0] - u.x, G.provs[p].ic[1] - u.y)
		if d < bd:
			bd = d
			best = p
	if best >= 0:
		u.surveyQueue.append(best)
		return
	var next := -1
	bd = INF
	for p in explored:
		for n in open_nbr[p]:
			var q: int = n.q
			if explored.has(q):
				continue
			var taken := false
			for v in units:
				if not is_same(v, u) and v.autoWalk != null and v.autoWalk.to == q:
					taken = true
					break
			if taken:
				continue
			u.autoWalk = {"to": q}
			var hops = find_path(u, q)
			u.autoWalk = {"to": -1}
			if hops == null:
				continue
			var d: float = hops.size() * 1000 + JS.hypot(G.provs[q].ic[0] - u.x, G.provs[q].ic[1] - u.y)
			if d < bd:
				bd = d
				next = q
	if next >= 0:
		u.autoWalk = {"to": next}
		order(u, next, true)
	else:
		u.autoWalk = null


# web: v78.js placeRuins(): Intact Ruins in a swamp away from the capital (seeded by the map)
func place_ruins(avoid := {}) -> int:
	var r := Mulberry32.from_string(str(world.seed) + ":ruins")
	var near := {}
	for p in buildings:
		if buildings[p].stage == 2:
			near[p] = true
			for q in all_nbr[p]:
				near[q] = true
	var ok := []
	var any := []
	for i in world.provinces.size():
		if world.provinces[i].terrain == "swamp" and not buildings.has(i) and not avoid.has(i):
			any.append(i)
			if not near.has(i) and not setpieces.has(i):
				ok.append(i)
	var pool := ok if not ok.is_empty() else any
	if pool.is_empty():
		return -1
	var p: int = pool[int(floor(r.next() * pool.size()))]
	finds[p] = {"id": "ruins", "done": false}
	return p


# web: v78.js surveyFinds(u): Intact Ruins give a random Tier I Government technology (or 3 minutes of Government
# research when none is left); a desert may hide treasure
const RUINS_MINUTES := 3
func survey_finds(u: Dictionary) -> void:
	var p: int = u.prov
	var f = finds.get(p)
	if f != null and f.id == "ruins" and not f.done:
		f.done = true
		var pick := []
		for x in TECHS:
			if x.tree == "gov" and x.get("tier") == 1 and not x.get("rep", false) and not tech.gov.done.has(x.id) and req_met(x, tech.gov):
				pick.append(x)
		var note := ""
		if not pick.is_empty():
			var x: Dictionary = pick[floori(js_rand.call() * pick.size())]
			grant_tech(x.id)
			note = "Your nation has just gained the technology %s." % x.name
		else:
			var pts := int(JS.round_js(tech_rate("gov") * RUINS_MINUTES * 60 / TICK))
			add_research("gov", pts)
			note = "Your scholars already know every Tier I Government technology, so they gain %d Government research points instead (%d minutes’ worth)." % [pts, RUINS_MINUTES]
		toast("%s has found intact ruins of an ancient temple in %s! %s" % [u.name, prov_name(p), note])
		sfx("wn_ally")
		if on_dialog.is_valid() and ME == view_seat:
			on_dialog.call("Intact Ruins", "%s has found intact ruins of an ancient temple in %s! Our findings here will give us a leap forward!\n\n%s" % [u.name, prov_name(p), note], [{"id": "ok", "label": "Splendid", "why": null}], func(_x): pass)
	if world.provinces[p].terrain == "desert" and not finds.has(p) and not treasure_rolled.has(p):
		treasure_rolled[p] = true
		if Mulberry32.from_string(str(world.seed) + ":treasure:" + str(p)).next() < GameData.c("TREASURE_CHANCE"):
			finds[p] = {"id": "treasure", "done": true}
			stock.gold += TREASURE_GOLD
			toast("%s has found a forgotten treasure in the sand: +%d gold." % [u.name, TREASURE_GOLD])


# web: tech.js reqMet() for Realmlings (reqOf: `req`; `reqSw` is for the other races). The tech trees come in step 7.
func req_met(x: Dictionary, st: Dictionary) -> bool:
	var req = x.get("reqSw") if x.get("reqSw") != null and race() != "realm" else x.get("req")   # web: tech.js reqOf
	if req == null:
		return true
	for r in (req if req is Array else [req]):
		if not st.done.has(r):
			return false
	return true


# ---------------------------------------------------------------------------------------------------------------
# settlements and buildings (web: game.js startBuild / beginExtra / orderBuild / buildCheck, govtech.js limits)

func build_time(type: String) -> float:
	return 60.0 if GameData.c("SLOW_BUILD").has(type) else BUILD_TIME


func borders_owned(i: int) -> bool:
	for q in all_nbr[i]:
		if owned(q):
			return true
	return false


func lack_text(cost: Dictionary):
	var short := []
	for k in cost:
		if stock[k] < cost[k]:
			short.append("%d %s" % [cost[k], k])
	return "Need " + ", ".join(short) if not short.is_empty() else null


static func cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in cost:
		parts.append("%d %s" % [cost[k], k])
	return ", ".join(parts)


# web: govtech.js outpostLimit / outpostCount / pendingOutposts / outpostWhy
func outpost_why():
	var forts := 0
	for p in buildings:
		if buildings[p].owner == ME and buildings[p].stage >= 1:
			forts += 1
	var per_fort: int = GameData.c("OUTPOSTS_PER_FORT") + (2 if has_tech("effadmin") else 0) + 2 * rep_lv("rep-admin")
	var lim := per_fort * forts + dev_limit_bonus()
	var n := 0
	for p in buildings:
		if buildings[p].owner == ME and buildings[p].stage == 0 and not upgrades.has(p):
			n += 1
	for u in units:
		if u.owner == ME and ((u.build != null and u.build.type == "outpost") or (u.pending != null and u.pending.type == "outpost")):
			n += 1
	return "Outpost limit reached (%d/%d) · each Fort allows %d more" % [n, lim, per_fort] if n >= lim else null


func sites_in(p: int) -> Array:
	return units.filter(func(v): return v.build != null and v.build.prov == p and BUILD_DEFS.has(v.build.type))


func pending_in(p: int) -> Array:
	return units.filter(func(v): return v.pending != null and v.pending.prov == p and not (v.pending.type in ["outpost", "road"]))


# web: game.js countOf()
func count_of(p: int, type: String) -> int:
	var n := 0
	for e in extras_in(p):
		if e.type == type:
			n += 1
	for v in sites_in(p):
		if v.build.type == type:
			n += 1
	for v in pending_in(p):
		if v.pending.type == type:
			n += 1
	return n


# web: game.js farmLand()
func farm_land(p: int) -> bool:
	var ter: String = world.provinces[p].terrain
	return ter in ["grassland", "forest"] or (has_tech("mushroom") and ter == "swamp")


## Why the player can't build `type` in province p now, or null. web: game.js buildCheck (+ swamp.js race rules:
## none apply to Realmlings)
func build_check(p: int, type: String):
	var why = build_check0(p, type)
	if type == "outpost":
		return why
	if why != null and not str(why).begins_with("Need "):   # research, ownership and room come first; then the race's own rules; then the cost
		return why
	var r = race_build_why(p, type, ME)
	return r if r != null else why


# web: swamp.js raceBuildWhy
func race_build_why(p: int, type: String, o: int):
	var sw := is_sw(o)
	if type == "pyre":
		if not sw:
			return "Swamplings only"
		var w := warlock_count(o)
		var n := pyre_count(o)
		if n >= w:
			return "One Sacred Pyre per living Warlock (%d/%d)" % [n, w]
	if not sw:
		return null
	if type == "granary" or type == "storehouse":
		return "Swamplings don’t build these"
	if type == "stable" and not mountain_border(p):
		return "An Ogre Cave needs a mountain border"
	if type == "temple" and world.provinces[p].terrain != "swamp":
		return "Hot Springs only bubble up in a swamp"
	return null


func mountain_border(p: int) -> bool:
	for e in world.edges:
		if e.style == "mountains" and (e.a == p or e.b == p):
			return true
	return false


func warlock_count(o: int) -> int:
	var n := 0
	for v in units:
		if v.owner == o:
			if v.kind == MAGE:
				n += 1
			elif v.kind == "army":
				n += int(v.troops.get(MAGE, 0))
	return n


func pyre_count(o: int) -> int:
	var n := 0
	for p in extras:
		if nation_of(p) == o:
			n += extras[p].filter(func(e): return e.type == "pyre").size()
	for u in units:
		if u.owner == o and ((u.get("build") != null and u.build.get("type") == "pyre") or (u.get("pending") != null and u.pending.get("type") == "pyre")):
			n += 1
	return n


func build_check0(p: int, type: String):
	if tutorial != null and tutorial.build_why(type) != null:
		return tutorial.build_why(type)
	if type == "outpost":
		if buildings.has(p):
			return "Already has a settlement"
		if not surveyed.has(p):
			return "Survey it first"
		if not borders_owned(p):
			return "Must border your land"
		if bandits_in(p):
			return "A Bandit Gang holds it"
		var lim = outpost_why()
		if lim != null:
			return lim
		return lack_text(bog_cost(p, ME, GameData.c("OUTPOST_COST")))
	var d: Dictionary = BUILD_DEFS[type]
	if d.has("tech") and d.tech != null and not has_tech(d.tech):
		return "Research " + str(TECH_BY_ID[d.tech].name).replace("Building: ", "") + " first"
	if not owned(p):
		return "Needs an outpost first"
	if type == "farm" and not farm_land(p):
		return "Only on grassland, forest or swamp" if has_tech("mushroom") else "Only on grassland or forest (Mushroom Farming adds swamps)"
	if type == "lumber" and not tree_border[p]:
		return "Needs a border of trees"
	if type == "goldmine" and not (yields[p].deposit and surveyed.has(p)):
		return "Needs a Hidden Gold Deposit"
	var cap := build_cap(p, type)
	var have := count_of(p, type)
	if have >= cap:
		if cap == 1:
			for e in extras_in(p):
				if e.type == type:
					return "Already built here"
			return "One is already on the way"
		return "All %d built or under way" % cap
	var waiting := 0
	for v in pending_in(p):
		if v.pending.get("slot", -1) < 0:
			waiting += 1
	if used_slots(p).size() + waiting >= plot_cap(p):
		return "Province full (%d/%d)" % [plot_cap(p), plot_cap(p)] + (" · upgrade to a Fort for 4" if buildings[p].stage == 0 else "")
	return lack_text(bog_cost(p, ME, d.cost))


# used_slots with building sites and pending orders (web: game.js usedSlots)
func used_slots_all(p: int) -> Dictionary:
	var used := used_slots(p)
	for v in sites_in(p):
		used[v.build.slot] = true
	for v in pending_in(p):
		if v.pending.get("slot", -1) >= 0:
			used[v.pending.slot] = true
	return used


# web: game.js orderBuild(u, p, type, slot)
## 0.19: the knock that confirms a player's order to build or upgrade (only for orders the player gave)
func confirm_sfx() -> void:
	if _from_order and ME == view_seat:
		sfx("ui_confirm")


func order_build(u: Dictionary, p: int, type: String, slot := -1) -> bool:
	var ok := _order_build(u, p, type, slot)
	if ok:
		confirm_sfx()
	return ok


func _order_build(u: Dictionary, p: int, type: String, slot := -1) -> bool:
	if u.prov != p:
		if not order(u, p):
			return false
		u.pending = {"prov": p, "type": type, "slot": slot}
		toast("%s is heading out to build %s." % [u.name, "an outpost" if type == "outpost" else "a " + BUILD_DEFS[type].name])
		return true
	if u.moving:
		order(u, p, true)
		u.pending = {"prov": p, "type": type, "slot": slot}
		return true
	if type == "outpost":
		start_build(u)
	else:
		begin_extra(u, type, slot)
	return true


# web: game.js startBuild(u): the Mason starts an outpost where he stands
func start_build(u: Dictionary) -> bool:
	if u.moving:
		halt_unit(u)
	var why = build_check(u.prov, "outpost")
	if why != null:
		toast("Can’t build an outpost here: %s." % str(why).to_lower(), true)
		return false
	if u.build != null:
		return false
	var cost: Dictionary = bog_cost(u.prov, ME, GameData.c("OUTPOST_COST"))
	for k in cost:
		stock[k] -= cost[k]
	u.build = {"prov": u.prov, "type": "outpost", "t0": t, "dur": build_time("outpost"), "paid": cost.duplicate()}
	sfx("bld_work", u.prov)
	var c: Array = G.provs[u.prov].ic
	u.th = atan2(c[0] - u.x, c[1] - u.y)
	toast("Building an outpost… (−%s)" % cost_text(cost))
	return true


# web: game.js beginExtra(u, type, want)
func begin_extra(u: Dictionary, type: String, want := -1) -> bool:
	var p: int = u.prov
	var why = build_check(p, type)
	if why != null:
		toast("Can’t build a %s here: %s." % [BUILD_DEFS[type].name, str(why).to_lower()], true)
		return false
	var d: Dictionary = BUILD_DEFS[type]
	var used := used_slots_all(p)
	var slot := want if want >= 0 and not used.has(want) else 0
	while used.has(slot):
		slot += 1
	var cost := bog_cost(p, ME, d.cost)
	for k in cost:
		stock[k] -= cost[k]
	var o := bslot_of(p, slot)
	u.build = {"prov": p, "type": type, "slot": slot, "ox": o[0], "oy": o[1], "t0": t, "dur": build_time(type), "paid": cost.duplicate()}
	sfx("bld_work", p)
	u.th = atan2(o[0] + G.provs[p].ic[0] - u.x, o[1] + G.provs[p].ic[1] - u.y)
	toast("Building a %s… (−%s)" % [d.name, cost_text(cost)])
	return true


# web: game.js cancelBuild(u): the resources come back
func cancel_build(u: Dictionary) -> void:
	u.erase("roadPlan")   # 0.19: cancelling stops a planned road too
	if u.get("pending") != null and u.pending.get("type") == "road":
		u.pending = null
	if u.build != null and u.build.has("paid"):
		var st := stock_of(u.owner)
		for k in u.build.paid:
			st[k] += u.build.paid[k]
	u.build = null


# the end of a build (web: game.js update(), "if (u.build) ...") — any owner's Mason
func finish_build(u: Dictionary) -> void:
	var b: Dictionary = u.build
	var mine: bool = u.owner == ME
	if b.type in ["road", "wall"]:
		finish_link(b)
	elif b.type != "outpost":
		if nation_of(u.prov) == u.owner:
			if not extras.has(u.prov):
				extras[u.prov] = []
			extras[u.prov].append({"type": b.type, "slot": b.slot, "born": t})
			if mine:
				toast("%s built." % BUILD_DEFS[b.type].name)
				sfx("bld_done", u.prov)
				compute_income()
		else:
			cancel_build(u)
			if mine:
				toast("The province is no longer yours: construction cancelled, resources refunded.", true)
	elif not buildings.has(u.prov):
		buildings[u.prov] = {"stage": 0, "born": t, "owner": u.owner}
		compute_income()
		outpost_claimed(u.prov, u.owner)
		if mine:
			toast("Outpost built. Its neighbors are now explored.")
			sfx("bld_outpost", u.prov)
	else:
		cancel_build(u)
		if mine:
			toast("Someone claimed this province first: outpost cancelled, resources refunded.", true)
	if not mine and u.build != null:
		Ai.built(self, u)
	u.build = null
	if b.type == "road" and u.get("roadPlan") != null:   # 0.19: on to the next stretch
		in_seat(u.owner, func(): road_next(u))


# web: gpc.js outpostClaimed(p, by): another nation's Wayfinders standing there withdraw
func outpost_claimed(p: int, by: int) -> void:
	for u in units.duplicate():
		if u.kind != WAYFINDER or u.owner == by or u.prov != p or u.get("exiting", false) or u.get("stealth", false):
			continue
		var back = u.get("lastProv")
		var bo := nation_of(back) if back != null else 0
		var ok_back: bool = back != null and back != p and (bo == u.owner or (bo != 0 and hostile(u.owner, bo)))
		u.path = []
		u.moving = false
		u.scouting = null
		u.survey = null
		u.aiSurvey = null
		u.erase("aiTarget")
		u.aiJob = null
		u.surveyQueue = []
		u.pendingSurvey = -1
		u.autoWalk = null
		u.pending = null
		var dest: int = back if ok_back else capital_of(u.owner)
		if dest < 0:
			var own := provs_of(u.owner)
			if own.is_empty():
				continue
			var d := hops_list(p, all_nbr)
			own = JS.stable_sort(own, func(x, y): return d[x] - d[y])
			dest = own[0]
		u.exiting = true
		if not order(u, dest, true):
			u.prov = dest
			u.slot = free_slot(dest, u)
			var xy := slot_pos(dest, u.slot)
			u.x = xy[0]
			u.y = xy[1]
			u.exiting = false
		elif ok_back:
			u.exitTo = dest
		if u.owner == ME:
			toast("The %s finished an outpost at %s: %s withdraws to %s." % [player_info(by).name, prov_name(p), u.name, prov_name(dest) if ok_back else "your capital"], true)


# web: game.js bslotOf(p, slot): where building plot `slot` sits, as an offset from the province centre (seeded)
func bslot_of(p: int, slot: int) -> Array:
	var P: Dictionary = G.provs[p]
	if not P.has("_bslots"):
		var BS: Array = GameData.c("BSLOTS")
		var r := Mulberry32.from_string(str(world.seed) + ":plots:" + str(p))
		var c: Array = P.ic
		var list := []
		for k in BS.size():
			var bx: float = BS[k][0]
			var by: float = BS[k][1]
			var a0 := atan2(by, bx)
			var r0 := JS.hypot(bx, by)
			var pick = null
			var tries := 0
			while tries < 40 and pick == null:
				tries += 1
				var a := a0 + (r.next() - 0.5) * 0.8
				var rad := maxf(112.0, r0 * (0.95 + r.next() * 0.55))
				var x := cos(a) * rad
				var y := sin(a) * rad * 0.92
				if not Geo.in_poly(c[0] + x, c[1] + y, P.inner) or Geo.dist_to_edges(c[0] + x, c[1] + y, P.inner) < 46:
					continue
				var clash := false
				for q in list:
					if JS.hypot(q[0] - x, (q[1] - y) * 1.3) < 84:
						clash = true
						break
				if clash:
					continue
				for s in SLOTS:
					if JS.hypot(s[0] - x, s[1] - y) < 44:
						clash = true
						break
				if clash:
					continue
				if absf(x) < 100 and y > 84 and y < 170:
					continue
				pick = [JS.round_js(x), JS.round_js(y)]
			list.append(pick if pick != null else [bx, by])
		P._bslots = list
	return P._bslots[slot] if slot < P._bslots.size() else GameData.c("BSLOTS")[slot]


# --- outpost to fort (web: game.js upgradeWhy / startUpgrade / stepUpgrades) ---

func fort_limit() -> int:
	var n := 0
	for id in ["forts", "forts2", "forts3"]:
		if has_tech(id):
			n += 1
	return GameData.c("FORT_LIMIT")[n] + 2 * rep_lv("rep-forts")


func fort_count() -> int:
	var n := 0
	for p in buildings:
		if buildings[p].owner == ME and buildings[p].stage == 1:
			n += 1
	return n


func upgrade_why(p: int):
	if not owned(p):
		return "Not yours"
	var b: Dictionary = buildings[p]
	if b.stage != 0:
		return "Already a Fort" if b.stage == 1 else "Capitals can’t be upgraded yet"
	if upgrades.has(p):
		return "Already upgrading"
	if fort_count() + upgrades.size() >= fort_limit():
		return "Fort limit reached (%d/%d)" % [fort_count(), fort_limit()] + ("" if has_tech("forts") else " · research Fort Charters for 3")
	return lack_text(GameData.c("FORT_UPGRADE").cost)


func start_upgrade(p: int) -> bool:
	var why = upgrade_why(p)
	if why != null:
		toast("Can’t upgrade: %s." % str(why).to_lower(), true)
		return false
	var FU: Dictionary = GameData.c("FORT_UPGRADE")
	for k in FU.cost:
		stock[k] -= FU.cost[k]
	upgrades[p] = {"t0": t, "paid": FU.cost.duplicate()}
	confirm_sfx()
	toast("Upgrading the outpost to a Fort… (−%s, %d s)" % [cost_text(FU.cost), FU.time])
	return true


# web: game.js cancelUpgrade
func cancel_upgrade(p: int) -> void:
	var u = upgrades.get(p)
	if u == null:
		return
	for k in u.paid:
		stock[k] += u.paid[k]
	upgrades.erase(p)
	toast("Upgrade cancelled. Resources refunded.")


# v96: dismantle a fort back to an outpost; every building in the province is torn down (web: v96.js dismantleWhy)
func dismantle_why(p: int):
	var b = buildings.get(p)
	if b == null or b.owner != ME:
		return "Not yours"
	if b.stage != 1:
		return "Only a fort can be dismantled"
	if occ.has(p):
		return "The province is occupied"
	if battles.any(func(x): return x.prov == p):
		return "Not during a battle"
	return null


# web: v96.js dismantleFort (the click-twice confirmation is the interface's)
func dismantle_fort(p: int) -> void:
	var why = dismantle_why(p)
	if why != null:
		toast("Can’t dismantle the fort: %s." % str(why).to_lower(), true)
		return
	var lost := extras_in(p).size()
	Quests.extras_lost(self, p, extras_in(p))
	extras.erase(p)
	for k in xup.keys():
		if int(k.split("@")[0]) == p:
			xup.erase(k)
	for v in units:
		if v.owner == ME and v.build != null and v.build.prov == p and BUILD_DEFS.has(v.build.type) and v.build.type != "outpost":
			cancel_build(v)
	for key in queues.keys():
		var parts: PackedStringArray = key.split(":")
		if int(parts[1]) == p and parts[0] != "capital":
			for e in queues[key]:
				if e.get("paid") != null and not e.get("retro", false):
					for r in e.paid:
						stock[r] += e.paid[r]
			queues.erase(key)
	buildings[p].stage = 0
	buildings[p].born = t
	clamp_stock()
	compute_income()
	toast("The fort at %s is dismantled: it is an outpost again%s." % [prov_name(p), (", and its %d building%s gone" % [lost, " is" if lost == 1 else "s are"]) if lost else ""])
	sfx("bld_work", p)


func step_upgrades(now: float) -> void:
	for k in xup.keys():
		var parts: PackedStringArray = k.split("@")
		var p := int(parts[0])
		var slot := int(parts[1])
		var e = null
		for x in extras_in(p):
			if x.slot == slot:
				e = x
				break
		if e == null:
			xup.erase(k)
			continue
		var d: Dictionary = BUILD_DEFS[e.type]
		var xu: Dictionary = xup[k]
		if now - xu.t0 < d.ups[xu.to - 1].time:
			continue
		xup.erase(k)
		e.level = xu.to
		e.born = now
		sfx("bld_done", int(k.split("@")[0]))
		toast("%s upgraded to a %s! %s research reaches Tier %s." % [d.levels[xu.to - 2], d.levels[xu.to - 1], "Military" if e.type == "forge" else "Magic", ["", "I", "II", "III"][xu.to]])
	var FU: Dictionary = GameData.c("FORT_UPGRADE")
	for p in upgrades.keys():
		if now - upgrades[p].t0 < FU.time:
			continue
		upgrades.erase(p)
		if not buildings.has(p):
			continue
		buildings[p].stage = 1
		buildings[p].born = now
		sfx("bld_done", p)
		toast("Outpost upgraded to a Fort. 4 building plots are now open.")
		compute_income()


# ---------------------------------------------------------------------------------------------------------------
# fog (web: game.js computeFog + magic.js towerSight)

func compute_fog() -> void:
	var vis := {}
	var exp := {}
	for p in wf:
		exp[p] = true
	for p in known:
		exp[p] = true
	for u in units:
		if u.owner == ME and u.kind == "army" and not known.has(u.prov):
			known[u.prov] = true
			exp[u.prov] = true
	for u in units:
		if u.owner == ME and u.scouting != u.prov:
			vis[u.prov] = true
			if u.kind == WAYFINDER and has_tech("farsight"):
				for n in open_nbr[u.prov]:
					vis[n.q] = true
					if not known.has(n.q):
						known[n.q] = true
						exp[n.q] = true
	for p in buildings:
		if buildings[p].owner != ME:
			continue
		vis[p] = true
		for n in open_nbr[p]:
			exp[n.q] = true
	# allies share their sight: their land and where their units stand (not part of the web game; asked for in 0.17)
	var al := allies_of(ME)
	if not al.is_empty():
		for p in buildings:
			if buildings[p].owner in al:
				vis[p] = true
				known[p] = true
				exp[p] = true
		for u in units:
			if u.owner in al and u.get("scouting") != u.prov:
				vis[u.prov] = true
				known[u.prov] = true
				exp[u.prov] = true
	if has_tech("arcscouts"):
		for p in extras:
			if owned(p) and extras[p].any(func(e): return e.type == "magetower"):
				vis[p] = true
				for n in open_nbr[p]:
					vis[n.q] = true
	for r in eyes:
		if r.until > t:
			vis[r.a] = true
			vis[r.b] = true
	for h in haunts:
		if h.until > t:
			vis[h.prov] = true
	for r in wrocks:
		if r.owner == ME and r.until > t:
			vis[r.a] = true
			vis[r.b] = true
	for P in spyres:   # web: swamp.js pyreSight
		if P.owner == ME and P.until > t:
			vis[P.prov] = true
			for n in open_nbr[P.prov]:
				vis[n.q] = true
	# web: v95.js towerSight: Death Mountain is seen from any province next to it
	var U = uq()
	if U != null and int(U.get("death", -1)) >= 0 and world.provinces[int(U.death)].nbr.any(func(q): return vis.has(int(q))):
		vis[int(U.death)] = true
		known[int(U.death)] = true
	if has_art(ME, "eye"):   # v95: the Lidless Eye shows every army
		for u in units:
			if u.kind == "army" and troop_count(u) > 0:
				vis[u.prov] = true
	if reveal_all:
		for p in G.provs.size():
			vis[p] = true
	for p in vis:
		exp[p] = true
	visible = vis
	explored = exp


## Debug and pictures only (the view's --reveal): the whole map is seen. Not part of the web game's rules.
var reveal_all := false
var rec := {}                # the game's recording (Recorder), when Settings → Record games is on
var rec_prev := {}           # Recorder's working state: what it saw a second ago (not saved)
var rec_map := {}            # ...and the map in its last frame
var rec_t := -9.0
var debug_cap := 0           # web: S.debugCap, the Settings debug button's extra storage
var debug_tech := false      # web: S.debugTech


func fog_state(i: int) -> String:
	return "visible" if visible.has(i) else "explored" if explored.has(i) else "unexplored"


# ---------------------------------------------------------------------------------------------------------------
# training (web: game.js trainable / train / stepTraining, swamp.js and v104.js trainable, v96.js rally points)

const QUEUE_MAX := 10


# web: game.js trainTime()
static func train_time(kind: String, q = null) -> float:
	if q != null and q.get("retro", false):
		return q.dur
	if kind == "mage:A":
		return 30.0
	if kind == "pioneer:B" or kind == MASON:
		return 12.0
	return 18.0


## What a building trains. src: "capital", "barracks" or "magetower". web: game.js trainable + swamp.js (Realmlings:
## Barracks soldiers from the Armory, cavalry only with a Stable in the province) + v104.js (a Forge adds the
## Crossbowman)
func trainable(src: String, prov: int) -> Array:
	if src == "capital":
		return GameData.c("TRAINS").capital
	if src == "magetower":
		return [GameData.c("MAGE")]
	if src == "market":   # web: swamp.js trainable (a Thug Den trains Thugs)
		return [THUG] if is_sw() else []
	if src == "stable":   # Swamplings: Ogres at the Ogre Cave (no Barracks needed there)
		return designs.filter(func(d): return d.get("race", "realm") == "swamp" and d.type == "cav").slice(0, 12).map(func(d): return d.id) if is_sw() else []
	if src != "barracks":
		return []
	var has_stable: bool = not is_sw() and extras_in(prov).any(func(e): return e.type == "stable")
	var list := []
	for d in designs:
		if d.get("race", "realm") == race() and (d.type == "inf" or has_stable):
			list.append(d.id)
	list = list.slice(0, 12)
	if _has_forge():
		var k: String = GameData.c("RANGED")[race()].id
		if not list.has(k):
			list = (list.slice(0, 11) if list.size() >= 12 else list) + [k]
			military[k] = true
			UNIT_SPEED[k] = GameData.c("UNIT_SPEED").get(k, UNIT_SPEED.get(k, 1.0))
	return list


func _has_forge() -> bool:
	for p in extras:
		if owned(p) and extras[p].any(func(e): return e.type == "forge"):
			return true
	return false


# web: game.js unitLimit() / content.js mageCap()
func unit_limit(kind: String) -> int:
	if kind == GameData.c("MAGE"):
		return 1 + (1 if has_tech("apprentice") else 0) + rep_lv("rep-magecap")
	if kind == MASON:
		return GameData.c("UNIT_LIMIT")[kind] + rep_lv("rep-masons")
	if kind == WAYFINDER:
		return GameData.c("UNIT_LIMIT")[kind] + rep_lv("rep-wayfinders")
	return 0


# web: game.js unitTotal(): units, queued ones, and (for Mages) those inside armies
func unit_total(kind: String) -> int:
	var n := 0
	for v in units:
		if v.owner == ME and v.kind == kind:
			n += 1
		if kind == GameData.c("MAGE") and v.owner == ME and v.kind == "army":
			n += v.troops.get(kind, 0)
	for key in queues:
		for e in queues[key]:
			if e.kind == kind:
				n += 1
	return n


func limit_why(kind: String):
	var L := unit_limit(kind)
	if L and unit_total(kind) >= L:
		return "Limit reached: %d %s%s" % [L, unit_defs[kind].name, "s" if L > 1 else ""]
	return null


## Why `kind` can't be trained at src:prov now, or null.
func train_why(src: String, prov: int, kind: String):
	if not trainable(src, prov).has(kind):
		return "Not trained here"
	var lw = limit_why(kind)
	if lw != null:
		return lw
	return lack_text(unit_defs[kind].cost)


# web: game.js train(kind) with S.selKind = src, S.selBuilding = prov
func train(src: String, prov: int, kind: String) -> bool:
	var d: Dictionary = unit_defs.get(kind, {})
	if not trainable(src, prov).has(kind):
		return false
	if limit_why(kind) != null:
		var L := unit_limit(kind)
		toast("You can have at most %d %s%s at a time (including any in training%s)." % [L, d.name, "s" if L > 1 else "", " or in armies" if kind == GameData.c("MAGE") else ""], true)
		return false
	var short := []
	for k in d.cost:
		if stock[k] < d.cost[k]:
			short.append(k)
	if not short.is_empty():
		toast("Not enough %s to train a %s." % [" and ".join(short), d.name], true)
		return false
	for k in d.cost:
		stock[k] -= d.cost[k]
	var key := "%s:%d" % [src, prov]
	if not queues.has(key):
		queues[key] = []
	queues[key].append({"kind": kind, "paid": d.cost.duplicate(), "t0": null})
	toast("%s queued at the %s." % [d.name, "capital" if src == "capital" else str(BUILD_DEFS[src].name if BUILD_DEFS.has(src) else src)])
	return true


## Take the last unit out of a queue, refunding it (web: the queue's cancel button).
func cancel_training(key: String, i: int) -> void:
	var Q: Array = queues.get(key, [])
	if i < 0 or i >= Q.size():
		return
	var q: Dictionary = Q[i]
	for k in q.paid:
		stock[k] += q.paid[k]
	Q.remove_at(i)
	if i == 0 and not Q.is_empty():
		Q[0].t0 = null
	if q.get("retro", false):
		for a in units:
			if a.id == q.army and is_same(a.get("retro"), q):
				a.retro = null


# web: game.js srcSpot(key)
func src_spot(key: String) -> Dictionary:
	var parts := key.split(":")
	var kind := parts[0]
	var prov := int(parts[1])
	var c: Array = G.provs[prov].ic
	if kind == "capital":
		return {"prov": prov, "x": c[0], "y": c[1]}
	var want := kind if kind in ["magetower", "market", "stable"] else "barracks"
	var slot := 0
	for e in extras_in(prov):
		if e.type == want:
			slot = e.slot
			break
	var o := bslot_of(prov, slot)
	return {"prov": prov, "x": c[0] + o[0], "y": c[1] + o[1]}


# web: game.js stepTraining(t) (+ v102.js: an occupied building holds its queue; no wars yet)
func step_training(now: float) -> void:
	for key in queues:
		var Q: Array = queues[key]
		if Q.is_empty():
			continue
		var q: Dictionary = Q[0]
		if q.t0 == null:
			q.t0 = now
		if now - q.t0 < train_time(q.kind, q):
			continue
		Q.pop_front()
		if q.get("retro", false):
			finish_retro(q)
			continue
		var spot := src_spot(key)
		var d: Dictionary = unit_defs[q.kind]
		var rp = q.get("rally") if q.get("rally") != null else rally.get(key)   # v106: an Army Training Order's own rally point first
		if military.has(q.kind):
			var a = null
			if rp == null:
				for v in units:
					if v.kind == "army" and v.owner == ME and v.prov == spot.prov and not v.moving and v.get("battle") == null:
						a = v
						break
			if a != null:
				a.troops[q.kind] = a.troops.get(q.kind, 0) + 1
				a.grew = now
				var n := 0
				for k in a.troops:
					n += a.troops[k]
				toast("%s joined %s (%d soldiers)." % [d.name, a.name, n])
			else:
				a = new_army(spot.prov, {q.kind: 1})
				a.born = now
				if q.get("order") != null:
					a.trainOrder = q.order
				toast("%s is ready and marches to the rally point." % d.name if rp != null else "%s is ready and formed %s." % [d.name, a.name])
				if rp != null:
					rally_go(a, rp)
			sfx("pr_trained", spot.prov)
			compute_income()
			continue
		if q.kind == THUG and thug_into_den(spot.prov):   # web: swamp.js thugIntoDen: a new Thug settles into a den with room
			compute_income()
			toast("A Thug settles into the Thug Den.")
			continue
		var n := 1
		for v in units:
			if v.kind == q.kind and v.owner == ME:
				n += 1
		var u := mk_unit(next_id, q.kind, d.name + (" %d" % n if n > 1 else ""), spot.prov, 0)
		next_id += 1
		u.slot = free_slot(spot.prov, u)
		var xy := slot_pos(spot.prov, u.slot)
		u.x = xy[0]
		u.y = xy[1]
		u.born = now
		units.append(u)
		sfx("pr_trained", spot.prov)
		if rp != null:
			rally_go(u, rp)
		compute_income()
		toast("%s is ready." % u.name)


# web: v96.js rallyGo(u, rp)
func rally_go(u: Dictionary, rp: Dictionary) -> void:
	if u.kind == "army":
		u.rallyTo = rp.prov
	if u.prov == rp.prov and JS.hypot(u.x - rp.x, u.y - rp.y) < 40:
		return
	order(u, rp.prov, true, [rp.x, rp.y])


## Set (or clear, with prov < 0) the rally point of a training building. web: v96.js rally command
func set_rally(key: String, prov: int, x := 0.0, y := 0.0) -> void:
	if prov < 0:
		rally.erase(key)
	else:
		rally[key] = {"prov": prov, "x": x, "y": y}


# web: v96.js rallyArrivals() (v106 Army Training Orders come later): an army reaching its rally point joins an
# army already standing there
func rally_arrivals() -> void:
	order_arrivals()
	for a in units.duplicate():
		if a.get("_gone", false) or a.kind != "army" or a.get("rallyTo") == null or a.owner != ME:
			continue
		if a.moving or a.get("battle") != null:
			continue
		if a.prov != a.rallyTo:
			a.rallyTo = null
			continue
		a.rallyTo = null
		var host = null
		for v in units:
			if not is_same(v, a) and v.kind == "army" and v.owner == ME and v.prov == a.prov and not v.moving and not v.get("exiting", false) \
					and v.get("battle") == null and v.get("retro") == null and v.get("retroWant") == null \
					and not (v.troops.get(GameData.c("MAGE"), 0) > 0 and a.troops.get(GameData.c("MAGE"), 0) > 0):
				host = v
				break
		if host == null:
			continue
		for k in a.troops:
			host.troops[k] = host.troops.get(k, 0) + a.troops[k]
		host.grew = t
		a._gone = true
		units = units.filter(func(v): return not is_same(v, a))
		compute_income()


# ---------------------------------------------------------------------------------------------------------------
# research (web: tech.js techPayday / pickTech / finishTech / drawOptions / topUpOptions, v96.js auto-research,
# v105.js the leader's school, v78.js grantTech / addResearch)

const TREE_KEYS := ["gov", "mil", "mag"]
const UPGRADE_TECHS := ["battleforge", "warforge", "sanctum", "arcanum"]
const REP_LEFT := 5


func tech_for(x: Dictionary) -> bool:
	return Races.race_is(x.get("race"), race())


# web: game.js levelsOf(type)
func levels_of(type: String) -> Array:
	var out := []
	for p in extras:
		if owned(p):
			for e in extras[p]:
				if e.type == type:
					out.append(e.get("level", 1))
	return out


# web: tech.js techTier(tree): Government by forts, Military and Magic by the Forge / Mage Tower level
func tech_tier(tree: String) -> int:
	if tree == "gov":
		var forts := 0
		for p in buildings:
			if buildings[p].owner == ME and buildings[p].stage == 1:
				forts += 1
		return 1 + int(forts >= 1) + int(forts >= 2)
	var lv := levels_of("forge" if tree == "mil" else "magetower")
	return lv.max() if not lv.is_empty() else 0


# web: tech.js provResearch(p) (+ v105.js: a Mage leader's Mage Towers give +1 Magic each)
func prov_research(p: int) -> Dictionary:
	var r := {"gov": 0, "mil": 0, "mag": 0}
	if not owned(p):
		return r
	var b: Dictionary = buildings[p]
	var LP: Array = GameData.c("LEVEL_POINTS")
	if not occ.has(p):
		if b.stage >= 1:
			r.gov += b.stage + 1
		for e in extras_in(p):
			if e.type == "temple":
				r.gov += 2
	for e in extras_in(p):
		if e.type == "forge":
			r.mil += LP[e.get("level", 1)]
		elif e.type == "magetower":
			r.mag += LP[e.get("level", 1)]
	if not occ.has(p) and setpieces.has(p) and setpiece_on(setpieces[p]):
		r[SETPIECES[setpieces[p]].tree] += SETPIECES[setpieces[p]].pts
	var L = leader_of()
	if L != null and L.start == "mage":
		for e in extras_in(p):
			if e.type == "magetower":
				r.mag += 1
	return r


func tech_rate(tree: String) -> int:
	var n := 0
	for p in buildings:
		if buildings[p].owner == ME:
			n += prov_research(p)[tree]
	return n + int(quest_rate.get(tree, 0))   # (quests: research won for good)


func bank_cap(tree: String) -> float:
	return tech_rate(tree) * GameData.c("BANK_SECONDS") / TICK


# web: tech.js techCost(x)
func tech_cost(x: Dictionary) -> int:
	var rep_mult := 1.0
	if x.get("rep", false) and not GameData.c("FLAT_REPS").has(x.id):
		rep_mult = pow(GameData.c("REP_STEP"), rep_lv(x.id))
	var tree_mult: float = GameData.c("GOV_COST_MULT") if x.tree == "gov" else GameData.c("MIL_COST_MULT") if x.tree == "mil" else 1.0
	var n := provs_of().size()
	var cost_mult := 1 + 0.05 * mini(10, maxi(0, n - 10)) + 0.15 * maxi(0, n - 20)
	return int(JS.round_js(x.cost * rep_mult * tree_mult * cost_mult))


func current_school():
	for id in tech.mag.done:
		if id.begins_with("school-"):
			return id.substr(7)
	return null


# web: magic.js abandonSchool: the school, its spells and its repeatables are forgotten; choose a new school
func abandon_school() -> void:
	var sc = current_school()
	if sc == null:
		return
	var st: Dictionary = tech.mag
	st.done = st.done.filter(func(id): return not (TECH_BY_ID[id].get("school") == sc or id == "school-" + sc or id == "abandon"))
	for x in TECH_BY_ID.values():
		if x.get("rep", false) and x.get("school") == sc:
			rep.erase(x.id)
	for c in units:
		if c.get("cast") != null:
			cancel_cast(c)
	harvest_by = null
	if sc == "arcane":
		trap = null
	draw_options("mag")
	compute_income()
	toast("The School of %s is abandoned and its spells forgotten. Choose a new school." % GameData.c("SCHOOLS")[sc].name, true)
	school_popup = true


# web: magic.js pickSchool (+ v105.js a school-locked leader allows only his school)
func pick_school(k: String) -> bool:
	var L = leader_of(ME)
	if L != null and L.get("school") != null and L.school != k:
		toast("%s only allows %s." % [L.full, GameData.c("SCHOOL_WORD")[L.school]], true)
		return false
	var id := "school-" + k
	if not TECH_BY_ID.has(id) or not tech_for(TECH_BY_ID[id]):
		return false
	var st: Dictionary = tech.mag
	if not st.opts.has(id) and st.cur != id:
		draw_options("mag")
	if not st.opts.has(id) and st.cur != id:
		st.opts.append(id)
	if st.cur != id and not pick_tech(id):
		return false
	sfx("mg_school")
	toast("Researching the School of %s. You can switch in the Research panel until it finishes." % GameData.c("SCHOOLS")[k].name)
	return true


func techs_left(tree: String) -> int:
	var st: Dictionary = tech[tree]
	var sc = current_school() if tree == "mag" else null
	var n := 0
	for x in TECH_BY_ID.values():
		if x.tree != tree or x.get("rep", false) or not tech_for(x) or st.done.has(x.id) or x.id == "abandon":
			continue
		if tree == "mag":
			if x.id.begins_with("school-"):
				if sc != null:
					continue
			elif sc != null and x.get("school") != "*" and x.get("school") != sc:
				continue
		n += 1
	return n


func tier3_done(tree: String) -> bool:
	for x in TECH_BY_ID.values():
		if x.tree == tree and x.get("tier") == 3 and not x.get("rep", false) and not x.get("afterT3", false) and tech_for(x) and not tech[tree].done.has(x.id):
			return false
	return true


func forge_ready(x: Dictionary, st: Dictionary) -> bool:
	if x.id != "battleforge":
		return true
	var n := 0
	for id in st.done:
		var y = TECH_BY_ID.get(id)
		if y != null and y.get("tier") == 1 and not y.get("rep", false) and y.tree == "mil":
			n += 1
	return n >= 2


# web: tech.js availTechs(tree) + v105.js (a leader locked to a school offers only that school)
func avail_techs(tree: String) -> Array:
	var st: Dictionary = tech[tree]
	var T := tech_tier(tree)
	var rep_open := techs_left(tree) < REP_LEFT
	var out := []
	for x in TECHS:
		if x.tree == tree and x.get("tier", 0) <= T and tech_for(x) and not st.done.has(x.id) and x.id != st.cur and req_met(x, st) \
				and forge_ready(x, st) and (not x.get("rep", false) or rep_open) and (not x.get("afterT3", false) or tier3_done(tree)):
			out.append(x)
	if tree == "mag":
		var sc = current_school()
		if sc != null:
			out = out.filter(func(x): return not x.id.begins_with("school-") and (x.get("school") == "*" or x.get("school") == sc))
		else:
			out = out.filter(func(x): return x.id.begins_with("school-"))
		var L = leader_of()
		if L != null and L.get("school") != null:
			out = out.filter(func(x): return x.id != "abandon" and (not x.id.begins_with("school-") or x.id == "school-" + L.school))
	return out


func tech_options() -> int:
	return GameData.c("TECH_OPTIONS") + int(has_tech("retained")) + int(has_tech("retained2"))


static func _opt_order(a: Dictionary, b: Dictionary) -> bool:
	var ra := int(a.get("rep", false))
	var rb := int(b.get("rep", false))
	if ra != rb:
		return ra < rb
	if a.tier != b.tier:
		return a.tier < b.tier
	return a.id < b.id


# web: tech.js drawOptions(tree): a fresh random offer (Forge and Mage Tower stay once seen; the next building upgrade
# always; one of the newest tier)
func draw_options(tree: String) -> void:
	var st: Dictionary = tech[tree]
	var T := tech_tier(tree)
	var N := tech_options()
	var has_barracks := false
	for p in extras:
		if owned(p) and extras[p].any(func(e): return e.type == "barracks"):
			has_barracks = true
	var keyed := []
	for x in avail_techs(tree):
		var w := 1.5 if x.id == "forge" and has_barracks else 1.0
		keyed.append([pow(rng.randf(), 1.0 / w), x])
	keyed.sort_custom(func(a, b): return a[0] > b[0])
	var shuffled := keyed.map(func(o): return o[1])
	var top := shuffled.filter(func(x): return x.tier == T and not x.get("rep", false))
	var opts := []
	for x in shuffled:
		if st.sticky.has(x.id) and opts.size() < N:
			opts.append(x)
	for x in shuffled:
		if UPGRADE_TECHS.has(x.id) and opts.size() < N and not opts.has(x):
			opts.append(x)
	if not top.is_empty() and not opts.has(top[0]) and opts.size() < N:
		opts.append(top[0])
	for x in shuffled:
		if opts.size() < N and not opts.has(x):
			opts.append(x)
	for x in opts:
		if GameData.c("STICKY_TECHS").has(x.id) and not st.sticky.has(x.id):
			st.sticky.append(x.id)
	opts.sort_custom(_opt_order)
	st.opts = opts.map(func(x): return x.id)


# web: tech.js topUpOptions(tree)
func top_up_options(tree: String) -> void:
	var st: Dictionary = tech[tree]
	if not st.tier:
		return
	var N := tech_options()
	var keyed := []
	for x in avail_techs(tree):
		if not st.opts.has(x.id):
			keyed.append([rng.randf() + (2.0 if st.sticky.has(x.id) else 0.0), x])
	keyed.sort_custom(func(a, b): return a[0] > b[0])
	var added := false
	while st.opts.size() < N and not keyed.is_empty():
		st.opts.append(keyed.pop_front()[1].id)
		added = true
	if added:
		var xs: Array = st.opts.map(func(id): return TECH_BY_ID[id])
		xs.sort_custom(_opt_order)
		st.opts = xs.map(func(x): return x.id)


## Start researching `id` (it must be on offer). Points already earned stay in the bank when switching.
## web: tech.js pickTech(id)
func pick_tech(id: String) -> bool:
	var x = TECH_BY_ID.get(id)
	if x == null:
		return false
	var st: Dictionary = tech[x.tree]
	if not st.opts.has(id):
		toast("That technology isn’t on offer right now.", true)
		return false
	if x.get("gold", 0) and stock.gold < x.gold:
		toast("%s needs %d gold to begin." % [x.name, x.gold], true)
		return false
	if st.cur != null:
		st.bank += st.prog
		var old: Dictionary = TECH_BY_ID[st.cur]
		if old.get("gold", 0):
			stock.gold += old.gold
			toast("%s set aside: %d gold refunded." % [old.name, old.gold])
	if x.get("gold", 0):
		stock.gold -= x.gold
	var prev = st.cur
	st.cur = id
	st.prog = st.bank
	st.bank = 0
	st.opts.erase(id)
	if prev != null and prev != id and not st.opts.has(prev):
		st.opts.append(prev)
	top_up_options(x.tree)
	if st.prog >= tech_cost(x):
		finish_tech(x.tree)
	return true


# web: tech.js finishTech(tree)
func finish_tech(tree: String) -> void:
	var st: Dictionary = tech[tree]
	var x: Dictionary = TECH_BY_ID[st.cur]
	var cost := tech_cost(x)
	if x.get("rep", false):
		rep[x.id] = rep_lv(x.id) + 1
	else:
		st.done.append(x.id)
	st.bank = minf(st.prog - cost, bank_cap(tree))
	st.prog = 0
	st.cur = null
	if not x.id.begins_with("school-"):
		sfx("pr_research_magic" if tree == "mag" else "pr_research")
	var tree_name: String = TECH_TREES[tree].name
	if x.get("rep", false):
		draw_options(tree)
		compute_income()
		clamp_stock()
		toast("%s research complete: %s. %s" % [tree_name, x.name, x.get("baseBlurb", "")])
		return
	if x.id == "retained" or x.id == "retained2":
		for t2 in TREE_KEYS:
			if t2 != tree and tech[t2].tier:
				if tech[t2].cur != null:
					top_up_options(t2)
				else:
					draw_options(t2)
	if x.id == "abandon":
		abandon_school()
		return
	if x.id.begins_with("school-"):
		draw_options(tree)
		compute_income()
		toast("You follow the %s. Its spells can now be researched, and your Mages can cast them." % x.name)
		return
	draw_options(tree)
	compute_income()
	var what: String = x.get("blurb", "")
	if x.get("gives") != null:
		var parts := []
		for k in x.gives:
			parts.append("+%d %s" % [x.gives[k], k])
		what = "(" + ", ".join(parts) + " every 10 s)"
	toast("%s research complete: %s. %s" % [tree_name, x.name, what])


# web: tech.js techPayday() + v96.js auto-research before and after
func tech_payday() -> void:
	auto_research()
	for tree in TREE_KEYS:
		var st: Dictionary = tech[tree]
		var T := tech_tier(tree)
		if T != st.tier:
			if T > st.tier:
				var nm: String = TECH_TREES[tree].name
				toast("%s research unlocked! Open Research (T) to pick a technology." % nm if st.tier == 0 else "%s Tier %s technologies are now available." % [nm, ["", "I", "II", "III"][T]])
			if tree == "mag" and st.tier == 0 and T > 0 and current_school() == null:
				school_popup = true
			st.tier = T
			if st.cur == null or st.opts.is_empty():
				draw_options(tree)
		if not T:
			continue
		var pts := tech_rate(tree)
		if st.cur != null:
			st.prog += pts
			if st.prog >= tech_cost(TECH_BY_ID[st.cur]):
				finish_tech(tree)
		else:
			st.bank = maxf(st.bank, minf(st.bank + pts, bank_cap(tree)))
		if st.cur == null and st.opts.is_empty():
			draw_options(tree)
		top_up_options(tree)
	auto_research()


# web: v96.js autoResearch(): a tree set to auto picks its cheapest offer (no gold-costing ones, no schools)
func auto_research() -> void:
	for tree in TREE_KEYS:
		var st: Dictionary = tech[tree]
		if not auto_tech[tree] or not st.tier or st.cur != null:
			continue
		if st.opts.is_empty():
			draw_options(tree)
		var cands := []
		for id in st.opts:
			var x = TECH_BY_ID.get(id)
			if x != null and not id.begins_with("school-") and id != "abandon" and not x.get("gold", 0):
				cands.append(x)
		cands.sort_custom(func(a, b): return tech_cost(a) < tech_cost(b) or (tech_cost(a) == tech_cost(b) and a.tier < b.tier))
		if not cands.is_empty():
			pick_tech(cands[0].id)


# web: v78.js grantTech(id): a technology for free (Intact Ruins)
func grant_tech(id: String) -> void:
	var x: Dictionary = TECH_BY_ID[id]
	var st: Dictionary = tech[x.tree]
	if st.done.has(id):
		return
	if st.cur == id:
		st.bank = st.prog
		st.prog = 0
		st.cur = null
	st.done.append(id)
	st.opts.erase(id)
	st.sticky.erase(id)
	top_up_options(x.tree)
	compute_income()
	sfx("pr_research")


# web: v78.js addResearch(tree, pts): research points out of the blue
func add_research(tree: String, pts: int) -> void:
	var st: Dictionary = tech[tree]
	if st.cur != null:
		st.prog += pts
		var cost := tech_cost(TECH_BY_ID[st.cur])
		if st.prog >= cost:
			var left: int = st.prog - cost
			finish_tech(tree)
			st.bank = maxf(st.bank, left)
	else:
		st.bank += pts


# --- Forge / Mage Tower levels (web: game.js cmdInfo('xup'), startXup, cancelXup) ---

func xup_why(p: int, e: Dictionary):
	var d: Dictionary = BUILD_DEFS[e.type]
	var lv: int = e.get("level", 1)
	if not d.has("levels") or lv >= d.levels.size():
		return "Already at the highest level"
	var need = (["battleforge", "warforge"] if e.type == "forge" else ["sanctum", "arcanum"])[lv - 1]
	if need != null and not has_tech(need):
		return "Research " + TECH_BY_ID[need].name + " first"
	return lack_text(d.ups[lv].cost)


func start_xup(p: int, slot: int) -> bool:
	var e = null
	for x in extras_in(p):
		if x.slot == slot:
			e = x
	if e == null or xup.has("%d@%d" % [p, slot]):
		return false
	var why = xup_why(p, e)
	if why != null:
		toast("Upgrade: %s." % why, true)
		return false
	var d: Dictionary = BUILD_DEFS[e.type]
	var up: Dictionary = d.ups[e.get("level", 1)]
	for k in up.cost:
		stock[k] -= up.cost[k]
	xup["%d@%d" % [p, slot]] = {"t0": t, "paid": up.cost.duplicate(), "to": e.get("level", 1) + 1}
	confirm_sfx()
	toast("Upgrading to a %s… (−%s, %d s)" % [d.levels[e.get("level", 1)], cost_text(up.cost), up.time])
	return true


func cancel_xup(p: int, slot: int) -> void:
	var k := "%d@%d" % [p, slot]
	if not xup.has(k):
		return
	for r in xup[k].paid:
		stock[r] += xup[k].paid[r]
	xup.erase(k)
	toast("Upgrade cancelled. Resources refunded.")


# ---------------------------------------------------------------------------------------------------------------
# roads and walls (web: govtech.js linkWhy / startLink / finishLink / raiseWall / gateCtl / pathNbr / onRoad,
# gpc.js stepFortGates, v106.js roads between two walled provinces of your own)

const ROAD_TIME := 8.0
const WALL_TIME := 12.0


static func link_key(a: int, b: int) -> String:
	return "%d_%d" % [a, b] if a < b else "%d_%d" % [b, a]


func open_between(p: int, q: int) -> bool:
	return open_nbr[p].any(func(n): return n.q == q)


func road_tier() -> int:
	return 3 if has_tech("roads3") else 2 if has_tech("roads2") else 1


## 0.19: every kind of road is a quarter faster again than it was (Dirt +50%, then +60%, then +75%)
const ROAD_EXTRA := 0.25

func road_speed() -> float:
	return 1.0 + road_bonus()


func road_bonus() -> float:
	return GameData.c("ROAD_BONUS")[road_tier()] + (ROAD_EXTRA if RULES19 else 0.0)


func wall_kind() -> String:
	return "stone" if has_tech("walls2") else "wood"


func on_road(u: Dictionary, wp: Dictionary) -> bool:
	if roads.is_empty():
		return false
	if wp.has("enter") and roads.has(link_key(u.prov, wp.enter)):
		return true
	if not wp.has("enter") and u.has("lastProv") and roads.has(link_key(u.lastProv, u.prov)):
		return true
	return RULES19 and near_road(float(u.x), float(u.y))   # 0.19: anyone walking along a road, not only from end to end


## 0.19: how far from a road's middle a unit still walks on it: three times the road's drawn width (20), which
## stays as it is
const ROAD_HALF := 30.0
var _road_lines := {}   # link key -> [a, middle of the border, b] (from the map: not saved)

## A road's line, as it is drawn: from one province's middle, through the middle of their border, to the other's.
func road_line(k: String) -> Array:
	if _road_lines.has(k):
		return _road_lines[k]
	var ab := k.split("_")
	var p := int(ab[0])
	var q := int(ab[1])
	var a := Vector2(G.provs[p].ic[0], G.provs[p].ic[1])
	var b := Vector2(G.provs[q].ic[0], G.provs[q].ic[1])
	var m := (a + b) / 2
	for e in world.edges:
		if (e.a == p and e.b == q) or (e.a == q and e.b == p):
			var va: Array = world.vertices[e.v[0]]
			var vb: Array = world.vertices[e.v[1]]
			m = Vector2((va[0] + vb[0]) / 2.0, (va[1] + vb[1]) / 2.0)
			break
	_road_lines[k] = [a, m, b]
	return _road_lines[k]


## Is (x, y) on one of the roads (within ROAD_HALF of its line)?
func near_road(x: float, y: float) -> bool:
	var pt := Vector2(x, y)
	for k in roads:
		var L := road_line(k)
		if Geometry2D.get_closest_point_to_segment(pt, L[0], L[1]).distance_to(pt) <= ROAD_HALF \
				or Geometry2D.get_closest_point_to_segment(pt, L[1], L[2]).distance_to(pt) <= ROAD_HALF:
			return true
	return false


# --- roads from one province to another (0.19): the player picks where a road starts and ends, and the Mason
# paves every border along the way, one after another ---

## The provinces a road from a to b would follow: a chain of your own provinces, each next to the next across an
## open border or the gate of your own wall. [] when there is none.
func road_path(a: int, b: int) -> Array:
	if a == b or not owned(a) or not owned(b):
		return []
	var prev := {a: -1}
	var q0 := [a]
	while not q0.is_empty():
		var p: int = q0.pop_front()
		if p == b:
			break
		for q in all_nbr[p]:
			if prev.has(q) or not owned(q):
				continue
			if not (open_between(p, q) or walled_own(p, q)):
				continue
			prev[q] = p
			q0.append(q)
	if not prev.has(b):
		return []
	var out := [b]
	while out[0] != a:
		out.push_front(prev[out[0]])
	return out


## Why a road can't be planned along `path` by Mason m ("" when it can).
func road_plan_why(m: Dictionary, path: Array) -> String:
	if not has_tech("roads"):
		return "Research Dirt Roads first"
	if m.kind != MASON or m.owner != ME:
		return "Only your Mason builds roads"
	if path.size() < 2:
		return "No way for a road through your own provinces"
	var todo := 0
	for i in path.size() - 1:
		var p: int = path[i]
		var q: int = path[i + 1]
		if not owned(p) or not owned(q) or not all_nbr[p].has(q) or not (open_between(p, q) or walled_own(p, q)):
			return "No way for a road through your own provinces"
		if not roads.has(link_key(p, q)):
			todo += 1
	if todo == 0:
		return "There is already a road all the way"
	return ""


## The Mason paves a road along `path` (provinces), border after border; each costs what a road costs when he starts it.
func plan_road(m: Dictionary, path: Array) -> bool:
	var why := road_plan_why(m, path)
	if why != "":
		toast("Can’t build that road: %s." % (why[0].to_lower() + why.substr(1)), true)
		return false
	if m.build != null:
		cancel_build(m)
	var plan := path.map(func(x): return int(x))
	m.surveyQueue = []
	m.roadPlan = plan
	var n := 0
	for i in plan.size() - 1:
		if not roads.has(link_key(plan[i], plan[i + 1])):
			n += 1
	toast("%s will pave a road from %s to %s: %d border%s, %s each." % [m.name, prov_name(plan[0]), prov_name(plan[-1]), n, "" if n == 1 else "s", cost_text(GameData.c("ROAD_COST"))])
	road_next(m)
	return true


## The Mason's next stretch of his road: walk to its start, or start paving it.
func road_next(m: Dictionary) -> void:
	var plan = m.get("roadPlan")
	if plan == null:
		return
	while plan.size() >= 2 and roads.has(link_key(plan[0], plan[1])):
		plan.pop_front()
	if plan.size() < 2:
		m.roadPlan = null
		if m.owner == ME:
			toast("%s finished the road." % m.name)
		return
	var p: int = plan[0]
	var q: int = plan[1]
	if not owned(p) or not owned(q):
		m.roadPlan = null
		toast("The road can’t go on: %s or %s is no longer yours." % [prov_name(p), prov_name(q)], true)
		return
	if m.prov != p:
		if not order(m, p):
			m.roadPlan = null
			return
		m.roadPlan = plan   # (a new order forgets the plan: it is the plan's own)
		m.pending = {"prov": p, "type": "road", "to": q}
		return
	if not start_link(m, q, "road"):
		m.roadPlan = null


func wall_between(p: int, q: int):
	for i in walls:
		var e: Dictionary = world.edges[i]
		if (e.a == p and e.b == q) or (e.a == q and e.b == p):
			return e
	return null


# who controls a wall's gate: the nation of its home province (web: gateCtl)
func gate_ctl(k: String) -> int:
	var g = gate_own.get(k)
	if g == null:
		return 0
	if g.home >= 0 and buildings.has(g.home):
		return occ.get(g.home, buildings[g.home].owner)
	return g.owner


# web: govtech.js pathNbr(u, a, siege): open borders, walls whose gate the unit's nation holds, and (for armies of
# SIEGE_MIN soldiers or more, when `siege` is set) hostile walls to batter down
func path_nbr(u: Dictionary, a: int, siege := false) -> Array:
	if u.kind == WAYFINDER and is_wd(u.owner):
		var tn := tree_nbr(a)
		if not tn.is_empty():
			return path_nbr0(u, a, siege) + tn
	return path_nbr0(u, a, siege)


func path_nbr0(u: Dictionary, a: int, siege := false) -> Array:
	if walls.is_empty():
		return open_nbr[a]
	var ws := walls_at(a)
	if ws.is_empty():
		return open_nbr[a]
	var out: Array = open_nbr[a].duplicate()
	for w in ws:
		var c := gate_ctl(link_key(world.edges[w.i].a, world.edges[w.i].b))
		if c == u.owner:
			out.append({"q": w.q, "m": w.m})
		elif siege and u.kind == "army" and troop_count(u) >= SIEGE_MIN and c and hostile(u.owner, c):
			out.append({"q": w.q, "m": w.m, "siege": w.i})
	return out


# web: govtech.js wallsAt(a): the walls touching each province, rebuilt whenever a wall goes up or comes down
var walls_ver := 0
var _wall_adj := {}
var _wall_adj_ver := -1

func walls_at(a: int) -> Array:
	if _wall_adj_ver != walls_ver:
		_wall_adj = {}
		_wall_adj_ver = walls_ver
		var V: Array = world.vertices
		for i in walls:
			var e: Dictionary = world.edges[i]
			var x: Array = V[e.v[0]]
			var y: Array = V[e.v[1]]
			var m := [(x[0] + y[0]) / 2, (x[1] + y[1]) / 2]
			for so in [[e.a, e.b], [e.b, e.a]]:
				if not _wall_adj.has(so[0]):
					_wall_adj[so[0]] = []
				_wall_adj[so[0]].append({"q": so[1], "m": m, "i": i})
	return _wall_adj.get(a, [])


# =================================================================================================================
# sieges (web: gpc.js siegeHold / stepSiege / breakWall, v102.js wall health by kind, stepSiege and damageWall)
const SIEGE_MIN := 10
const SIEGE_STAND := 34.0
const WALL_MAX := {"wood": 40.0, "spiky": 80.0, "stone": 120.0}
const WALL_SPELL := {"shock": 40.0, "quake": 120.0}
var wall_max := {}          # edge -> the health it was last measured against
var wall_crack := {}        # edge -> true below half health
var broken_walls := {}      # "a_b" -> {home, owner} of a wall broken in a siege
var rewall_jobs := {}       # province -> {t0, qs, paid}
const REWALL_COST := {"wood": 50}
const REWALL_TIME := 15.0

func wall_owner(i: int) -> int:
	var e: Dictionary = world.edges[i]
	var g = gate_own.get(link_key(e.a, e.b))
	return g.owner if g != null else ME


# web: v102.js wallType: Stone Walls once the builder has researched them, a wooden palisade before
func wall_type(i: int) -> String:
	var o = wall_owner(i)
	return ("spiky" if is_sw(o) else "stone") if tech_of(o, "walls2") else "wood"   # web: v102.js wallType (Spiked Walls)


func wall_life(i: int) -> Dictionary:
	var mx: float = WALL_MAX[wall_type(i)]
	var was = wall_max.get(i)
	var hp = wall_hp.get(i)
	if hp == null or was == null:
		hp = mx if hp == null or hp > mx else hp
	elif was != mx:
		hp = hp * mx / was
	wall_hp[i] = hp
	wall_max[i] = mx
	return {"hp": hp, "max": mx}


## true when the wall comes down
func damage_wall(i: int, dmg: float, by = null) -> bool:
	if not walls.has(i):
		return false
	var w := wall_life(i)
	wall_hp[i] = w.hp - dmg
	if wall_hp[i] <= 0:
		wall_crack.erase(i)
		wall_max.erase(i)
		break_wall(i, by)
		return true
	wall_crack[i] = wall_hp[i] <= w.max / 2
	return false


# web: v96.js spellHitWall (Shockwave 40, Earthquake 120)
func spell_hit_wall(i: int, by, dmg := 40.0) -> bool:
	if not walls.has(i):
		return false
	var gone := damage_wall(i, dmg, by)
	if not gone:
		var e: Dictionary = world.edges[i]
		var w := wall_life(i)
		if gate_ctl(link_key(e.a, e.b)) == ME and (by == null or by.owner != ME):
			toast("The wall between %s and %s was hit by a spell: %d/%d wall health left." % [prov_name(e.a), prov_name(e.b), ceili(w.hp), int(w.max)], true)
	return gone


func break_wall(i: int, by = null) -> void:
	var e: Dictionary = world.edges[i]
	var k := link_key(e.a, e.b)
	var ctl := gate_ctl(k)
	var g = gate_own.get(k)
	if g != null:
		broken_walls[k] = g.duplicate()
	var V: Array = world.vertices
	var a: Array = V[e.v[0]]
	var b: Array = V[e.v[1]]
	var mid := [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]
	e.open = true
	e.style = "open"
	walls.erase(i)
	wall_hp.erase(i)
	gate_own.erase(k)
	walls_ver += 1
	open_nbr[e.a].append({"q": e.b, "m": mid})
	open_nbr[e.b].append({"q": e.a, "m": mid})
	for u in units:
		if u.get("sieging") == i:
			u.sieging = null
		for w in u.get("path", []):
			if w.get("siege") == i:
				w.erase("siege")
	if by != null and by.owner == ME:
		toast("%s broke through the wall between %s and %s!" % [by.name, prov_name(e.a), prov_name(e.b)])
		sfx("war_fort_win", -1, 0.7)
	elif ctl == ME:
		toast("The wall between %s and %s has fallen to the %s!" % [prov_name(e.a), prov_name(e.b), player_info(by.owner).name if by != null else "enemy"], true)
		sfx("war_fort_lose", -1, 0.7)


## The movement loop asks first: true while the army stands battering a hostile wall (it walks up to it first).
func siege_hold(u: Dictionary, time: float) -> bool:
	var wp = u.path[0] if not u.path.is_empty() else null
	if u.kind != "army" or wp == null or not wp.has("siege"):
		if u.get("sieging") != null:
			u.sieging = null
		return false
	var i: int = wp.siege
	var ctl: int = gate_ctl(link_key(world.edges[i].a, world.edges[i].b)) if walls.has(i) else u.owner
	if ctl == u.owner:
		u.sieging = null
		wp.erase("siege")
		return false
	if not ctl or not hostile(u.owner, ctl) or troop_count(u) < SIEGE_MIN:
		if troop_count(u) < SIEGE_MIN and u.owner == ME and u.get("sieging") != null:
			toast("%s has too few soldiers to batter the wall (it takes %d)." % [u.name, SIEGE_MIN], true)
		u.sieging = null
		var fin = u.get("final")
		u.path = []
		u.moving = false
		if fin == null or not order(u, fin, true):
			u.slot = free_slot(u.prov, u)
			var xy := slot_pos(u.prov, u.slot)
			u.path = [{"x": xy[0], "y": xy[1], "slot": true}]
			u.moving = true
		return true
	var d := JS.hypot(wp.x - u.x, wp.y - u.y)
	if d > SIEGE_STAND + 1:
		var step := minf(SPEED * unit_speed(u) * time, d - SIEGE_STAND)
		u.x += (wp.x - u.x) / d * step
		u.y += (wp.y - u.y) / d * step
		u.th = facing(wp.x - u.x, wp.y - u.y)
		if d - step > SIEGE_STAND + 1:
			return true
	if u.get("sieging") != i:
		u.sieging = i
		var e: Dictionary = world.edges[i]
		var other: int = e.b if e.a == u.prov else e.a
		if u.owner == ME:
			toast("%s is battering down the %s into %s." % [u.name, "stone wall" if wall_type(i) == "stone" else "palisade", prov_name(other)])
		elif ctl == ME:
			toast("The %s is battering down your wall at %s!" % [player_info(u.owner).name, prov_name(other)], true)
			sfx("wn_enemy")
	return true


# =================================================================================================================
# Earthquake and Shockwave (web: gpc.js Z11 / Z12 + v98.js mana + v102.js staves). Shockwave: any Mage, at a wall on
# the border with a nation at war with the caster, 15 s, 40 wall damage. Earthquake: Tier III Magic, cast in an
# enemy province your army occupies, 30 s: every building there falls and every wall around takes 120.
const QUAKE_TIME := 30.0     # v98: 30 s (was 120)
const SHOCK_TIME := 15.0     # v98: 15 s (was 120)
const SPELL2_MANA := {"shock": 50, "quake": 200}
var quakes := []        # the banners: {id, from, to, by, kind} of casts by nations at war with you
var quake_seq := 0

func spell2_name(k: String) -> String:
	return "Earthquake" if k == "quake" else "Fireball" if is_sw() else "Shockwave"   # web: gpc.js SHOCK


func rep_of(o: int, id: String) -> int:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return rep_of(o, id))
	return rep_lv(id) if o == ME else (int(nations[o].rep.get(id, 0)) if nations.has(o) else 0)


func spell2_time(k: String, o: int) -> float:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return spell2_time(k, o))
	var mult: float = STAVE_CAST.get(mage_gear.weapon, 1.0) if o == ME else 1.0
	return maxf(1.0, (QUAKE_TIME if k == "quake" else SHOCK_TIME) * pow(0.95, rep_of(o, "rep-quakecast" if k == "quake" else "rep-shockcast")) * mult - (skull_cut(o) if k == "shock" else 0.0))


func cast_len(T: float) -> String:
	if T >= 60:
		var m := T / 60.0
		return "%s minute%s" % [str(snappedf(m, 0.1)) if fmod(T, 60) else str(int(m)), "" if T == 60 else "s"]
	return "%d seconds" % JS.round_js(T)


func quake_why(c):
	if c == null or mages_in(c) <= 0:
		return "No Mage selected"
	if not tech_of(c.owner, "earthquake"):
		return "Research Earthquake (Magic Tier III) first"
	if occ.get(c.prov, -1) != c.owner:
		return "Cast it in an enemy province your army occupies"
	if c.moving:
		return "Stop moving first"
	if c.get("battle") != null:
		return "Not during battle"
	if units.any(func(v): return not is_same(v, c) and v.get("quake") and v.quake.kind == "quake" and v.prov == c.prov):
		return "An Earthquake is already being cast here"
	var need = mc(SPELL2_MANA.quake, c.owner)
	if mana_of(c) < need:
		return "Not enough mana (%d/%d)%s" % [floori(mana_of(c)), need, "" if tech_of(c.owner, "magicabund") else " · it needs Magic Abundance"]
	return null


func shock_why(c, q: int):
	if c == null or mages_in(c) <= 0:
		return "No Mage selected"
	if q == c.prov or not all_nbr[c.prov].has(q):
		return "The Mage must stand next door"
	var n := nation_of(q)
	if not n or not hostile(c.owner, n):
		return "Only against a province of a nation you are at war with"
	if wall_between(c.prov, q) == null:
		return "There is no wall on that border"
	if c.moving:
		return "Stop moving first"
	if c.get("battle") != null:
		return "Not during battle"
	var need = mc(SPELL2_MANA.shock, c.owner)
	if mana_of(c) < need:
		return "Not enough mana (%d/%d)" % [floori(mana_of(c)), need]
	return null


func start_spell2(c: Dictionary, kind: String, q := -1) -> bool:
	var why = quake_why(c) if kind == "quake" else shock_why(c, q)
	if why != null:
		if c.owner == ME:
			toast("%s: %s." % [spell2_name(kind), str(why).to_lower()], true)
		return false
	if c.get("cast") != null:
		cancel_cast(c)
	quake_seq += 1
	c.quake = {"kind": kind, "t0": t, "to": q, "id": quake_seq, "T": spell2_time(kind, c.owner)}
	var where := prov_name(c.prov) if kind == "quake" else prov_name(q)
	if c.owner == ME:
		toast(("%s begins an Earthquake in %s: %s of casting. Moving or fighting stops it." if kind == "quake" else "%s begins a Shockwave at the wall toward %s: %s of casting. Moving or fighting stops it.") % [c.name, where, cast_len(c.quake.T)])
		sfx("mg_arcane", c.prov)
	elif at_war(ME, c.owner):
		quakes.append({"id": c.quake.id, "from": c.prov, "to": q, "by": c.owner, "kind": kind})
		toast("%s at %s! A Mage of the %s is casting." % [spell2_name(kind), prov_name(c.prov), player_info(c.owner).name], true)
	spend_mana(c, SPELL2_MANA[kind])
	return true


func end_quake(c: Dictionary, why := "") -> void:
	if not c.get("quake"):
		return
	var id: int = c.quake.id
	c.quake = null
	quakes = quakes.filter(func(x): return x.id != id)
	if why != "" and c.owner == ME:
		toast(why, true)


func quake_strike(c: Dictionary) -> void:
	var p: int = c.prov
	var lost := extras_in(p).size()
	Quests.extras_lost(self, p, extras_in(p))
	extras.erase(p)
	for k in xup.keys():
		if int(str(k).split("@")[0]) == p:
			xup.erase(k)
	for v in units:
		if v.build != null and v.build.prov == p and BUILD_DEFS.has(v.build.type):
			cancel_build(v)
	var ws := walls.keys().filter(func(i): return world.edges[i].a == p or world.edges[i].b == p)
	var broke := 0
	var cracked := 0
	for i in ws:
		if spell_hit_wall(i, c, WALL_SPELL.quake):
			broke += 1
		else:
			cracked += 1
	compute_income()
	var o := nation_of(p)
	if nations.has(o):
		nations[o].income = Ai.income(self, nations[o])
	var msg := "The earth splits at %s: %d building%s and %d wall%s destroyed%s." % [prov_name(p), lost, "" if lost == 1 else "s", broke, "" if broke == 1 else "s",
		("; %d wall%s damaged" % [cracked, "" if cracked == 1 else "s"]) if cracked else ""]
	if c.owner == ME:
		toast(msg)
		sfx("war_fort_win", -1, 0.7)
	elif o == ME or explored.has(p):
		toast(msg, o == ME)


func step_quakes(now: float) -> void:
	for c in units.duplicate():
		if not c.get("quake"):
			continue
		if mages_in(c) <= 0:
			end_quake(c)
			continue
		var k: String = c.quake.kind
		if c.moving or c.get("battle") != null:
			end_quake(c, "%s stopped casting the %s." % [c.name, spell2_name(k)])
			continue
		if now - c.quake.t0 < c.quake.get("T", QUAKE_TIME):
			continue
		var q: int = c.quake.to
		end_quake(c)
		if k == "quake":
			if occ.get(c.prov, -1) == c.owner:
				add_spell_fx("quake", c, c.prov)
				quake_strike(c)
			continue
		var e = wall_between(c.prov, q)
		var i: int = world.edges.find(e) if e != null else -1
		if i >= 0:
			add_spell_fx("shock", c, q, e)
			var gone := spell_hit_wall(i, c, WALL_SPELL.shock)
			var w := wall_life(i) if not gone else {}
			if c.owner == ME:
				toast(("The Shockwave shatters the wall between %s and %s." % [prov_name(c.prov), prov_name(q)]) if gone else ("The Shockwave hits the wall between %s and %s: %d/%d wall health left." % [prov_name(c.prov), prov_name(q), ceili(w.hp), int(w.max)]))
	if not quakes.is_empty():
		quakes = quakes.filter(func(x): return at_war(ME, x.by) and units.any(func(v): return v.get("quake") and v.quake.id == x.id))


# web: v102.js stepSiege: ten or more soldiers at a wall take 1 health a second off it (Spiked Walls come with Swamplings)
func step_siege(dt: float) -> void:
	if not dt:
		return
	var at := {}
	for a in units:
		if a.kind != "army" or a.get("sieging") == null or a.get("battle") != null or troop_count(a) < SIEGE_MIN:
			continue
		if not walls.has(a.sieging):
			a.sieging = null
			continue
		if not at.has(a.sieging):
			at[a.sieging] = []
		at[a.sieging].append(a)
	for i in at:
		var alive: Array = at[i].filter(func(a): return units.has(a))
		var n := 0
		for a in alive:
			n += troop_count(a)
		if n >= SIEGE_MIN:   # (Siegebreaker Runeplate: 20% faster)
			damage_wall(i, dt * (Quests.SIEGE_MUL if quests_on and alive.any(func(a): return Quests.wears(self, a, "armor:siegebreaker")) else 1.0), alive[0])


# web: gpc.js rebuilding broken walls: select the fort (or capital), at peace only, 50 wood a wall, 15 s
func rewall_rec(p: int, q: int):
	var r = broken_walls.get(link_key(p, q))
	if r == null:
		return null
	return r if r.owner == ME or (r.home >= 0 and nation_of(r.home) == ME) else null


func rewalls_at(p: int) -> Array:
	return all_nbr[p].filter(func(q): return rewall_rec(p, q) != null and open_between(p, q))


func rewalls_why(p: int):
	var n := rewalls_at(p).size()
	if not owned(p):
		return "Not yours"
	if occ.has(p):
		return "Occupied by the enemy"
	if not n:
		return "No broken walls here"
	if not wars_of(ME).is_empty():
		return "Only at peace"
	return lack_text({"wood": REWALL_COST.wood * n})


func rebuild_walls(p: int) -> void:
	if rewall_jobs.has(p):
		toast("The walls of %s are already being rebuilt." % prov_name(p))
		return
	var why = rewalls_why(p)
	if why != null:
		toast("Can’t rebuild the walls: %s." % str(why).to_lower(), true)
		return
	var qs := rewalls_at(p)
	var paid: int = REWALL_COST.wood * qs.size()
	stock.wood -= paid
	rewall_jobs[p] = {"t0": t, "qs": qs, "paid": paid}
	sfx("bld_work", p)
	toast("Rebuilding %d wall%s around %s: %d s (−%d wood)." % [qs.size(), "s" if qs.size() > 1 else "", prov_name(p), REWALL_TIME, paid])


func step_rewalls(now: float) -> void:
	for p in rewall_jobs.keys():
		var j: Dictionary = rewall_jobs[p]
		var stop := "the province is no longer yours" if not owned(p) else "the province is occupied" if occ.has(p) else "you are at war" if not wars_of(ME).is_empty() else ""
		if stop != "":
			rewall_jobs.erase(p)
			stock.wood += j.paid
			toast("Wall rebuilding at %s stopped: %s. Wood refunded." % [prov_name(p), stop], true)
			continue
		if now - j.t0 < REWALL_TIME:
			continue
		rewall_jobs.erase(p)
		var n := 0
		for q in j.qs:
			var r = rewall_rec(p, q)
			if raise_wall(p, q, ME, r.home if r != null and r.home >= 0 and nation_of(r.home) == ME else p):
				n += 1
		if n < j.qs.size():
			stock.wood += REWALL_COST.wood * (j.qs.size() - n)
		toast("%d wall%s rebuilt around %s, gates and all." % [n, "" if n == 1 else "s", prov_name(p)])
		sfx("bld_done", p)


func walled_own(p: int, q: int) -> bool:
	return not open_between(p, q) and wall_between(p, q) != null and owned(p) and owned(q)


## Why the Mason can't build a road or wall from his province to q, or null.
func link_why(type: String, m: Dictionary, q: int):
	var p: int = m.prov
	if type == "road" and walled_own(p, q):   # v106: a road through your own gate
		if not has_tech("roads"):
			return "Research Dirt Roads first"
		if not all_nbr[p].has(q):
			return "The Mason must stand next door"
		if m.moving:
			return "He is walking"
		if m.build != null:
			return "He is already building"
		if _link_under_way(p, q, ["road"]):
			return "Already under way"
		if roads.has(link_key(p, q)):
			return "There is already a road"
		return lack_text(GameData.c("ROAD_COST"))
	if type == "road" and not has_tech("roads"):
		return "Research Dirt Roads first"
	if type == "wall" and not has_tech("walls"):
		return "Research Wooden Walls first"
	if p == q:
		return "Pick a neighboring province"
	if not all_nbr[p].has(q):
		return "The Mason must stand next door"
	if not open_between(p, q):
		return "That border is already closed"
	if not explored.has(q):
		return "Explore it first"
	if type == "road" and (not owned(p) or not owned(q)):
		return "A road must join two of your own provinces"
	if not owned(p) and not owned(q):
		return "One side must be your land"
	if m.moving:
		return "He is walking"
	if m.build != null:
		return "He is already building"
	if _link_under_way(p, q, ["road", "wall", "rewall"]):
		return "Already under way"
	if type == "road":
		if roads.has(link_key(p, q)):
			return "There is already a road"
		return lack_text(GameData.c("ROAD_COST"))
	return lack_text(GameData.c("WALL_COST"))


func _link_under_way(p: int, q: int, types: Array) -> bool:
	for u in units:
		if u.build != null and types.has(u.build.type) and link_key(u.build.prov, u.build.to) == link_key(p, q):
			return true
	return false


func start_link(m: Dictionary, q: int, type: String) -> bool:
	var why = link_why(type, m, q)
	if why != null:
		toast("Can’t build a %s there: %s." % [type, str(why).to_lower()], true)
		return false
	var cost: Dictionary = GameData.c("ROAD_COST") if type == "road" else GameData.c("WALL_COST")
	for k in cost:
		stock[k] -= cost[k]
	m.surveyQueue = []
	m.pending = null
	m.build = {"prov": m.prov, "to": q, "type": type, "t0": t, "paid": cost.duplicate(), "dur": ROAD_TIME if type == "road" else WALL_TIME, "owner": m.owner}
	toast("Building a %s… (−%s, %d s)" % [type, cost_text(cost), m.build.dur])
	return true


## The open border a Mason stands next to (within ROAD_REACH), or -1. web: features.js masonBorder()
func mason_border(m: Dictionary) -> int:
	var best := -1
	var bd: float = GameData.c("ROAD_REACH")
	for n in open_nbr[m.prov]:
		var d := JS.hypot(n.m[0] - m.x, n.m[1] - m.y)
		if d < bd:
			bd = d
			best = n.q
	return best


## The border a Mason would build a road across from where he stands: the nearest open border within reach, or,
## failing that, the nearest wall between two of your provinces (v106: a road through your own gate; the web game
## offers it in the Ctrl+right-click build menu, the port on the Road button).
func mason_road_border(m: Dictionary) -> int:
	var q := mason_border(m)
	if q >= 0:
		return q
	var best := -1
	var bd: float = GameData.c("ROAD_REACH")
	for i in walls:
		var e: Dictionary = world.edges[i]
		if e.a != m.prov and e.b != m.prov:
			continue
		var other: int = e.b if e.a == m.prov else e.a
		if not walled_own(m.prov, other):
			continue
		var va: Array = world.vertices[e.v[0]]
		var vb: Array = world.vertices[e.v[1]]
		var d := JS.hypot((va[0] + vb[0]) / 2.0 - m.x, (va[1] + vb[1]) / 2.0 - m.y)
		if d < bd:
			bd = d
			best = other
	return best


func finish_link(b: Dictionary) -> void:
	var p: int = b.prov
	var q: int = b.to
	if b.type == "road":
		roads[link_key(p, q)] = true
		toast("Road finished. Units move %d%% faster along it." % JS.round_js(road_bonus() * 100))
		return
	var o: int = b.get("owner", ME)
	var home := p if (buildings.has(p) and buildings[p].owner == o) else q if (buildings.has(q) and buildings[q].owner == o) else -1
	if raise_wall(p, q, o, home):
		toast("%s finished. Its gate lets only your units through." % ("Stone wall" if wall_kind() == "stone" else "Palisade"))


# web: govtech.js raiseWall(p, q, owner, home)
func raise_wall(p: int, q: int, owner: int, home: int) -> bool:
	if not open_between(p, q):
		return false
	for i in world.edges.size():
		var e: Dictionary = world.edges[i]
		if not e.open or not ((e.a == p and e.b == q) or (e.a == q and e.b == p)):
			continue
		e.open = false
		e.style = "wall"
		walls[i] = true
		wall_hp[i] = GameData.c("WALL_HP")[wall_kind()]   # wallLife brings it down to its kind's health
		wall_crack.erase(i)
		walls_ver += 1
	open_nbr[p] = open_nbr[p].filter(func(n): return n.q != q)
	open_nbr[q] = open_nbr[q].filter(func(n): return n.q != p)
	var np: int = buildings[p].owner if buildings.has(p) else 0
	var nq: int = buildings[q].owner if buildings.has(q) else 0
	if not (np == owner and nq == owner):
		roads.erase(link_key(p, q))   # v106: a road between two provinces of the wall's own nation goes through the gate
	gate_own[link_key(p, q)] = {"home": home, "owner": owner}
	broken_walls.erase(link_key(p, q))
	# anyone marching through that border finds another way
	for u in units:
		if not u.moving:
			continue
		var prev: int = u.prov
		var hit := false
		for w in u.path:
			if w.has("enter"):
				if link_key(prev, w.enter) == link_key(p, q):
					hit = true
				prev = w.enter
		if not hit:
			continue
		var fin = u.get("final")
		u.path = []
		u.moving = false
		if fin == null or not order(u, fin, true):
			u.slot = free_slot(u.prov, u)
			var xy := slot_pos(u.prov, u.slot)
			u.path = [{"x": xy[0], "y": xy[1], "slot": true}]
			u.moving = true
	return true


# web: gpc.js stepGPC: once a second, owned provinces show their resources; forts and capitals wall their open
# borders once walls are researched (no retrofits, rest, quakes or sieges on the Practice island yet)
func step_gpc(now: float, gpc_dt := 0.0) -> void:
	if now - gpc_slow_t >= 1 or now < gpc_slow_t:
		gpc_slow_t = now
		each_seat(func():
			for p in buildings:
				if explored.has(p) and not surveyed.has(p):
					surveyed[p] = now)
		for p in buildings:
			for id in nations:   # GPC04: a claimed province's resources are known to every other nation
				var N: Dictionary = nations[id]
				if N.alive and buildings[p].owner != N.id:
					N.surveyed[p] = true
		if not nations.is_empty():
			evict_strays()
	step_retrofits()
	step_rest(now)
	step_quakes(now)
	step_fort_gates()
	step_siege(gpc_dt)
	step_rewalls(now)


# web: gpc.js evictStrays: units left in land they may no longer be in (a truce ran out, a border moved) march home
func evict_strays() -> void:
	var mine := 0
	for a in units.duplicate():
		if not is_nation(a.owner) or a.get("exiting", false) or a.moving or a.get("battle") != null or a.get("fleeing", false) or a.get("retreatHome", false):
			continue
		if nation_ok(a, a.prov):
			continue
		var own := provs_of(a.owner)
		if own.is_empty():
			continue
		a.exiting = true
		a.retreating = false
		a.surveyQueue = []
		a.survey = null
		a.aiSurvey = null
		a.scouting = null
		a.pendingSurvey = -1
		a.pending = null
		a.aiJob = null
		if a.build != null:
			cancel_build(a)
		if a.get("cast") != null:
			cancel_cast(a)
		var d := hops_list(a.prov)
		own = JS.stable_sort(own, func(x, y): return d[x] - d[y])
		var dest: int = own[0]
		if not order(a, dest, true):
			a.prov = dest
			a.slot = free_slot(dest, a)
			var xy := slot_pos(dest, a.slot)
			a.x = xy[0]
			a.y = xy[1]
			a.path = []
			a.moving = false
			a.exiting = false
		elif a.owner == ME:
			mine += 1
	if mine:
		toast("%d of your unit%s in a nation’s land without a truce or a war and will march home." % [mine, "s are" if mine > 1 else " is"])


## a forest path or tunnel runs along the p–q border
func path_edge(p: int, q: int) -> bool:
	for i in paths:
		var e: Dictionary = world.edges[i]
		if (e.a == p and e.b == q) or (e.a == q and e.b == p):
			return true
	return false


# web: gpc.js stepFortGates: every nation's forts and capitals wall their borders once Palisades are researched
func step_fort_gates() -> void:
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.stage < 1 or not is_nation(b.owner) or not tech_of(b.owner, "walls"):
			continue
		for n in open_nbr[p].duplicate():
			var key := "%d>%d" % [p, n.q]
			if fort_walled.has(key):
				continue
			if path_edge(p, n.q):
				continue   # forest paths and tunnels stay open
			fort_walled[key] = true
			if raise_wall(p, n.q, b.owner, p) and b.owner == ME and explored.has(p):
				toast("The %s raised a %s with a gate." % ["capital" if b.stage == 2 else "fort", "stone wall" if wall_kind() == "stone" else "palisade"])


# ---------------------------------------------------------------------------------------------------------------
# armies and units: split, combine, dismiss; buildings: destroy (web: game.js splitArmy / combineArmies,
# v102.js one Mage per army, features.js dismiss / destroy)

func troop_count(a: Dictionary) -> int:
	var n := 0
	for k in a.troops:
		n += a.troops[k]
	return n


func split_army(a: Dictionary):
	if troop_count(a) < 2:
		toast("An army needs at least two soldiers to split.", true)
		return null
	var keep := {}
	var give := {}
	var ks: Array = a.troops.keys().filter(func(k): return a.troops[k] > 0)
	var odd: int = ks.filter(func(k): return a.troops[k] % 2).size()
	var odd_seen := 0
	for k in ks:
		var n: int = a.troops[k]
		var h := n / 2
		keep[k] = h
		give[k] = h
		if n % 2:
			if odd_seen < ceili(odd / 2.0):
				keep[k] += 1
			else:
				give[k] += 1
			odd_seen += 1
	for side in [keep, give]:
		for k in side.keys():
			if not side[k]:
				side.erase(k)
	if give.is_empty():
		var k = null
		for kk in keep:
			if keep[kk] > 1:
				k = kk
				break
		if k == null:
			k = keep.keys()[0]
		keep[k] -= 1
		give[k] = 1
		if not keep[k]:
			keep.erase(k)
	a.troops = keep
	var b := new_army(a.prov, give, a)
	compute_income()
	toast("%s split." % a.name)
	return b


func combine_armies(list: Array) -> void:
	if list.size() < 2:
		return
	var prov: int = list[0].prov
	if list.any(func(a): return a.prov != prov):
		toast("Armies must be in the same province to combine.", true)
		return
	var mage: String = GameData.c("MAGE")
	var mages := 0
	for a in list:
		mages += a.troops.get(mage, 0)
	if mages > 1:
		toast("An army can have only one Mage.", true)   # (v102 steps the extra Mages out: comes with magic)
		return
	var main: Dictionary = list[0]
	for a in list.slice(1):
		for k in a.troops:
			main.troops[k] = main.troops.get(k, 0) + a.troops[k]
		a._gone = true
		units = units.filter(func(v): return not is_same(v, a))
	main.grew = t
	compute_income()
	toast("%d armies combined into %s (%d soldiers)." % [list.size(), main.name, troop_count(main)])


## Join army: each selected Mage joins the army of yours in his province (one Mage per army); his mana and autocast
## go with him. web: magic.js magicCmdUse 'join' + v98.js (mana follows the Magic User)
func mage_join(list: Array):
	var n := 0
	var last = null
	for m in list:
		if m == null or m.kind != MAGE or m.owner != ME:
			continue
		var a = null
		var full := false
		for v in units:
			if v.kind == "army" and v.owner == ME and v.prov == m.prov and v.get("battle") == null:
				if v.troops.get(MAGE, 0) > 0:
					full = true
				elif a == null:
					a = v
		if a == null:
			if full:
				toast("An army can have only one %s." % unit_defs[MAGE].name, true)
			continue
		cancel_cast(m)
		a.troops[MAGE] = a.troops.get(MAGE, 0) + 1
		a.auto = m.get("auto", {}).duplicate()
		a.mana = mana_of(m)   # (one Mage per army: his mana is the army's)
		a.grew = t
		m._gone = true
		units = units.filter(func(v): return not is_same(v, m))
		n += 1
		last = a
	if n:
		compute_income()
		toast("%s joined the army." % (("%d %ss" % [n, unit_defs[MAGE].name]) if n > 1 else "The " + unit_defs[MAGE].name))
	return last


func join_why(m) -> String:
	if m == null or m.kind != MAGE:
		return "No %s selected" % unit_defs[MAGE].name
	if m.moving:
		return "Stop moving first"
	if not units.any(func(v): return v.kind == "army" and v.owner == ME and v.prov == m.prov and v.get("battle") == null):
		return "No army of yours here"
	return ""


## Detach: the army's Mage leaves it and stands on his own (with the army's mana). web: magic.js magicCmdUse 'detach'
func mage_detach(a: Dictionary):
	if a.kind != "army" or a.owner != ME or a.troops.get(MAGE, 0) <= 0 or a.get("battle") != null:
		return null
	cancel_cast(a)
	a.troops[MAGE] -= 1
	if a.troops[MAGE] <= 0:
		a.troops.erase(MAGE)
	var k := units.filter(func(v): return v.kind == MAGE and v.owner == ME).size() + 1
	var m := mk_unit(next_id, MAGE, unit_defs[MAGE].name + ("" if k == 1 else " %d" % k), a.prov, 0)
	next_id += 1
	m.owner = ME
	m.slot = free_slot(a.prov, m)
	var xy: Array = slot_pos(a.prov, m.slot)
	m.x = xy[0]
	m.y = xy[1]
	m.born = t
	m.mana = mana_of(a)
	a.mana = 0.0
	m.auto = a.get("auto", {}).duplicate()
	units.append(m)
	if troop_count(a) <= 0:
		remove_army(a)
	compute_income()
	toast("The %s leaves the army." % unit_defs[MAGE].name)
	return m


func dismiss(list: Array) -> void:
	for u in list:
		if u.build != null:
			cancel_build(u)
		u._gone = true
		Quests.unit_lost(self, u)
	units = units.filter(func(v): return not list.any(func(u): return is_same(u, v)))
	compute_income()


## Tear a building down: no refund, its upkeep stops, its plot is free.
func destroy_extra(p: int, slot: int) -> void:
	var e = null
	for x in extras_in(p):
		if x.slot == slot:
			e = x
	if e == null or not owned(p):
		return
	Quests.extras_lost(self, p, [e])
	extras[p] = extras_in(p).filter(func(x): return not is_same(x, e))
	xup.erase("%d@%d" % [p, slot])
	compute_income()
	toast("%s torn down. Plot %d is free." % [BUILD_DEFS[e.type].name, slot + 1])
	sfx("bld_work", p)


# ---------------------------------------------------------------------------------------------------------------
# development (web: v106.js devWhy / startDevelop / finishDevelop / stepDevelop / resetDevelop)

func dev_rec(p: int, make := false):
	if not devel.has(p) and make:
		devel[p] = {"lv": 0, "add": {"gold": 0, "wood": 0, "food": 0}, "luck": {}, "deep": false, "owner": buildings[p].owner if buildings.has(p) else 0, "job": null}
	return devel.get(p)


func dev_cost(lv: int) -> Dictionary:
	var c: int = GameData.c("DEV").cost[lv]
	return {"gold": c, "wood": c, "food": c}


func dev_why(p: int, o := ME):
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return dev_why(p, o))
	if not buildings.has(p):
		return "Needs an outpost, fort or capital"
	if buildings[p].owner != o:
		return "Not yours"
	var r = dev_rec(p)
	var lv: int = r.lv if r != null else 0
	var DEV: Dictionary = GameData.c("DEV")
	if lv >= DEV.max:
		return "Fully developed (%d/%d)" % [DEV.max, DEV.max]
	if r != null and r.job != null:
		return "Already developing"
	if occ.has(p):
		return "Occupied by the enemy"
	if o != ME:
		var st := stock_of(o)
		var c := dev_cost(lv)
		for k in c:
			if st[k] < c[k]:
				return "Not enough resources"
		return null
	return lack_text(dev_cost(lv))


func start_develop(p: int, o := ME) -> bool:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return start_develop(p, o))
	var why = dev_why(p, o)
	if why != null:
		if o == ME:
			toast("Can’t develop: %s." % str(why).to_lower(), true)
		return false
	var r: Dictionary = dev_rec(p, true)
	var c := dev_cost(r.lv)
	var st := stock_of(o)
	for k in c:
		st[k] -= c[k]
	r.owner = o
	r.job = {"done": 0.0, "paid": c, "by": o}
	if o != ME:
		return true
	sfx("bld_work", p)
	toast("Developing to level %d: %d minutes (−%s)." % [r.lv + 1, GameData.c("DEV").time / 60, cost_text(c)])
	compute_income()
	return true


func finish_develop(p: int) -> void:
	var r = dev_rec(p)
	if r == null:
		return
	var DEV: Dictionary = GameData.c("DEV")
	r.job = null
	r.lv = mini(DEV.max, r.lv + 1)
	var y: Dictionary = yields[p]
	for k in RES:
		y[k] += 1
		r.add[k] += 1
	var L: int = r.lv
	if not r.luck.has(L):
		r.luck[L] = RES[int(floor(dev_rand.call() * RES.size()))] if dev_rand.call() < DEV.luck else null
	if r.luck[L] != null:
		y[r.luck[L]] += 1
		r.add[r.luck[L]] += 1
	var deep := false
	if not r.deep and dev_rand.call() < DEV.deep:
		r.deep = true
		deep = true
		y.deposit = true
	if owned(p):
		if not surveyed.has(p):
			surveyed[p] = t
		sfx("bld_done", p)
		toast("Developed to level %d: +1 gold, wood and food%s.%s" % [L, (", and a lucky +1 " + r.luck[L]) if r.luck[L] != null else "", " A Deep Gold Deposit was found!" if deep else ""])
		compute_income()


func step_develop(d: float) -> void:
	var DEV: Dictionary = GameData.c("DEV")
	for p in devel:
		var r: Dictionary = devel[p]
		var o: int = buildings[p].owner if buildings.has(p) else 0
		use_seat(o if seats.has(o) else HOST)
		if not r.lv and r.job == null:
			r.owner = o
			continue
		if o != r.owner:
			reset_develop(p, r, true)
			continue
		if r.job == null or not d:
			continue
		r.job.done += d
		if r.job.done >= DEV.time:
			finish_develop(p)


func reset_develop(p: int, r: Dictionary, lost: bool) -> void:
	var y: Dictionary = yields[p]
	for k in RES:
		y[k] = maxi(0, y[k] - r.add[k])
		r.add[k] = 0
	r.lv = 0
	if lost:
		r.job = null
		r.owner = buildings[p].owner if buildings.has(p) else 0
	compute_income()


# ---------------------------------------------------------------------------------------------------------------
# magic (web: magic.js CAST / castWhy / castSpell / startPath / stepMagic, v98.js mana, 3-second casts and the
# reworked spells, v102.js mage gear, v105.js the Mage leaders' bonuses). Battle spells (Hardened Skin, Cursed
# Weapons, Risen Dead) and the stasis trap's catch come with battles.

const LINES := {"harvest": ["harvest", "bountiful", "magnificent"], "skin": ["skin", "stoneskin", "diamondskin"],
	"mending": ["mending", "rejuvenation", "restoration"], "forest": ["forest", "commune", "arboreal"],
	"curse": ["curse1", "curse2", "curse3"], "tunnel": ["underworld", "hallways", "sealed"], "risen": ["risen", "necro", "armyofdeath"],
	"graverob": ["graverob", "deathtax", "charon"], "scouts": ["arcscouts", "arcvision"], "mind": ["clearthoughts", "mindread"],
	"trading": ["trading", "stockmarket", "planar"], "stasis": ["stasis", "prison"], "rift": ["rift", "portal"],
	"eyes": ["eyesforest"], "haunt": ["haunt"],
	"fiery": ["fiery1", "fiery2", "fiery3"], "ftrap": ["firetrap", "blazetrap", "molttrap"], "spyre": ["scoutpyre"], "pfire": ["pathfire", "pathflame", "pathinferno"],
	"sacred": ["sacredpyre"], "rock": ["rockarmor"], "wrocks": ["wrocks"], "tportal": ["townportal"], "fspirit": ["forestspirit"], "gelem": ["gelemental"]}
const GELEM_ID := "wd-elem"
const GELEM := {"life": 120.0, "cd": 300.0}
const TRAV_KNOW := 30   # web: wood.js (the lost travelers share what they know)
# web: wood.js Elemental magic (+ v98.js mana and casting times)
const ROCK_PCT := 0.1
const PORTAL_CD := 300.0
# web: swamp.js / v98.js Pyromancy
const FIERY := [0.0, 0.05, 0.10, 0.15]
const FIRE_DMG := [0, 150, 300, 450]
const PATH_FIRE := [{}, {"mult": 2.0, "dur": 10.0}, {"mult": 2.25, "dur": 15.0}, {"mult": 2.5, "dur": 20.0}]
const SPYRE := {"dur": 60.0, "cd": 60.0}
const PATH_CD := 60.0
const SACRED := {"dur": 60.0, "gold": 110, "wood": 200, "cd": 180.0}
const HARVEST_PCT := [0, 0.1, 0.2, 0.3]
const MEND := [{}, {"dur": 60, "cd": 180}, {"dur": 30, "cd": 120}, {"dur": 0, "cd": 0}]
const RES_SPELL := {"graverob": "gold", "trading": "all"}
const RES_CD := 180.0
const PATH_OPEN := [0, 20, 10, 10]
const PATH_CLOSE := 10
const STASIS := [0, 10, 20]
const MANA_START := 25.0
const MANA_CAPS := [100, 150, 200]
const MANA_REGEN := [0, 1, 2, 3]
const SPELL_MANA := {"harvest": "drain", "mending": 25, "graverob": "all", "haunt": 25, "trading": "all", "mind": 50, "stasis": 50, "rift": 100, "eyes": 25,
	"spyre": 25, "ftrap": 50, "pfire": 50, "sacred": 100, "wrocks": 25, "tportal": 100, "fspirit": "drain", "gelem": 100}
const PATHS_MANA := 200
const CAST_TIME := 3.0
const GRAVE_RATE := [0, 1, 2, 3]
const TRADE_RATE := [0, 1.0 / 3, 2.0 / 3, 1]
const MIND := {"show": 20, "cd": 40}
const RIFT_CD := [0, 120, 15]
const SEE_TIME := 60.0
const STAVE_CAST := {"grandstave": 0.9, "mythicstave": 0.8}
const WAND_MANA := {"crypticwand": 0.9, "enigmaticwand": 0.8}
## The spells a caster can cast from the command card, in order.
const SPELLS := ["harvest", "mending", "graverob", "trading", "mind", "stasis", "rift", "eyes", "haunt", "spyre", "ftrap", "pfire", "sacred", "wrocks", "tportal", "fspirit", "gelem"]
var gelems := []    # Grand Elementals {owner, until}
var portal_fx := [] # Town Portal and Grand Elemental splashes {x, y, prov, t0, water}
var wrocks := []    # Whispering Rocks {owner, a, b, edge, t0, until}
var spyres := []    # Scouting Pyres {prov, owner, t0, until}
var ftraps := []    # fire traps {prov, owner, lv, mult, t0, ignore}
var sacreds := []   # Sacred Pyres {prov, owner, t0, until}
var trap_booms := []


func lvl(line: String) -> int:
	var n := 0
	for id in LINES[line]:
		if has_tech(id):
			n += 1
	return n


func line_tech(line: String) -> String:
	return LINES[line][maxi(0, lvl(line) - 1)]


## A spell's name. Grave Robbing keeps its name: Death Taxes and Charon's Riches are its upgrades.
func spell_name(line: String) -> String:
	return str(TECH_BY_ID[LINES[line][0]].name) if line == "graverob" else str(TECH_BY_ID[line_tech(line)].name)


func mages_in(u: Dictionary) -> int:
	var mage: String = GameData.c("MAGE")
	if u.kind == mage:
		return 1
	if u.kind == "army":
		return u.troops.get(mage, 0)
	return 0


func is_caster(u) -> bool:
	return u != null and u.owner == ME and mages_in(u) > 0


func mana_cap(o := ME) -> int:
	return MANA_CAPS[2] if tech_of(o, "magicabund") else MANA_CAPS[1] if tech_of(o, "magicwell") else MANA_CAPS[0]


static func mana_of(c) -> float:
	return 0.0 if c == null else c.get("mana", MANA_START)


func mana_mult(o := ME) -> float:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return mana_mult(o))
	return WAND_MANA.get(mage_gear.weapon, 1.0) if o == ME else 1.0


func mc(n, o := ME):
	return JS.round_js(n * mana_mult(o)) if (n is int or n is float) else n


func spend_mana(c: Dictionary, n) -> void:
	c.mana = maxf(0.0, mana_of(c) - mc(n, c.owner))


func mana_need(k: String) -> int:
	var m = SPELL_MANA.get(k, 0)
	return 1 if (m is String) else m


func harvest_pct() -> float:
	var L := lvl("harvest")
	if not L:
		return 0.0
	var p: float = HARVEST_PCT[L] + 0.02 * rep_lv("rep-harvest")
	if leader == "havva":
		p += 0.05 * L
	return p


# web: magic.js harvestFood() as the v104 crops wrapper computes it (every Farm grows its staple)
func harvest_food() -> int:
	if harvest_by == null:
		return 0
	var food := 0
	var per: int = gives_of("farm").get("food", 0)
	for p in extras:
		if owned(p) and not occ.has(p):
			for e in extras[p]:
				if e.type == "farm":
					food += per
	return int(JS.round_js(food * harvest_pct()))


func cd_left(k: String) -> float:
	return maxf(0.0, cd.get(k, 0.0) - t)


func start_cast(c: Dictionary, spell: String, dur: float, data := {}) -> void:
	if spell == "pathopen" or spell == "pathclose":
		spend_mana(c, PATHS_MANA)
	var m: float = STAVE_CAST.get(mage_gear.weapon, 1.0)
	if is_finite(dur) and m != 1.0:
		dur = JS.round_js(dur * m * 10) / 10.0
	if c.get("cast") != null:
		cancel_cast(c)
	c.cast = {"spell": spell, "t0": t, "dur": dur}
	c.cast.merge(data)


func begin_cast(c: Dictionary, k: String, data := {}) -> void:
	var m = SPELL_MANA.get(k, 0)
	if (m is int) and m:
		spend_mana(c, m)
	start_cast(c, "q:" + k, CAST_TIME, data)


func cancel_cast(c: Dictionary, why := "") -> void:
	if c.get("cast") == null:
		return
	var sp: String = c.cast.spell
	c.cast = null
	if sp == "q:fspirit":
		compute_income()
	if sp == "harvest":
		harvest_by = null
		compute_income()
	if why != "":
		toast(why)


func _others_casting(c: Dictionary, spell: String) -> bool:
	return units.any(func(v): return not is_same(v, c) and v.get("cast") != null and v.cast.spell == spell)


func mending_target(c: Dictionary):
	if c.kind == "army":
		return c
	for v in units:
		if v.kind == "army" and v.owner == ME and v.prov == c.prov:
			return v
	return null


func see_nbrs(c: Dictionary, style := "trees") -> Array:
	return all_nbr[c.prov].filter(func(q): return _edge_between(c.prov, q, style, null) >= 0)


func _edge_between(p: int, q: int, style, open) -> int:
	for i in world.edges.size():
		var e: Dictionary = world.edges[i]
		if ((e.a == p and e.b == q) or (e.a == q and e.b == p)) and (style == null or e.style == style) and (open == null or e.open == open):
			return i
	return -1


func haunt_why(p: int):
	if not explored.has(p):
		return "Explore that province first"
	if haunts.any(func(h): return h.prov == p and h.until > t):
		return "Already haunted"
	return null


func rift_why(c: Dictionary, p: int):
	if p == c.prov:
		return "Already here"
	if not explored.has(p):
		return "Explore that province first"
	return null


func _spell_why(c: Dictionary, k: String):
	match k:
		"harvest":
			return "Another Mage is already casting this" if _others_casting(c, "harvest") else null
		"mending":
			return "No army of yours here to heal" if mending_target(c) == null else null
		"graverob", "trading":
			return "Another Mage is already casting this" if _others_casting(c, "q:" + k) else null
		"stasis":
			return "A trap is already set" if trap != null else null
		"haunt":
			return haunt_why(c.prov)
		"eyes":
			return null if not see_nbrs(c).is_empty() else "No border of trees here"
		"spyre":
			return "Ready in %d s" % ceili(cd_left("spyre%d" % c.id)) if cd_left("spyre%d" % c.id) > 0 else null
		"wrocks":
			return null if not see_nbrs(c, "mountains").is_empty() else "No mountain border here"
		"tportal":
			if capital < 0 or c.prov == capital:
				return "Already at the capital"
			return "Ready in %d s" % ceili(cd_left("tportal%d" % c.id)) if cd_left("tportal%d" % c.id) > 0 else null
		"gelem":
			return "Ready in %d s" % ceili(cd_left("gelem%d" % c.id)) if cd_left("gelem%d" % c.id) > 0 else null
		"fspirit":
			if not owned(c.prov) or occ.has(c.prov):
				return "Channel it in a province of yours"
			if units.any(func(v): return v != c and v.get("cast") != null and v.cast.spell == "q:fspirit" and v.prov == c.prov):
				return "A Forest Spirit is already channeled here"
		"ftrap":
			var mine := ftraps.filter(func(x): return x.owner == ME)
			if mine.any(func(x): return x.prov == c.prov):
				return "A fire trap is already set here"
			if mine.size() >= warlock_count(ME):
				return "One trap per Warlock (%d/%d)" % [mine.size(), warlock_count(ME)]
		"pfire":
			return "Ready in %d s" % ceili(cd_left("pfire%d" % c.id)) if cd_left("pfire%d" % c.id) > 0 else null
		"sacred":
			if not owned(c.prov) or occ.has(c.prov):
				return "Only in one of your provinces"
			if sacreds.any(func(x): return x.prov == c.prov and x.until > t):
				return "A Sacred Pyre already burns here"
			if stock.wood < sacred_wood():
				return "Needs %d wood" % sacred_wood()
	return null


## Why caster c can't cast spell k now, or null. web: magic.js castWhy + v98.js (mana)
func cast_why(c: Dictionary, k: String):
	var cast = c.get("cast")
	if cast != null and cast.spell == "q:" + k:
		return null
	if current_school() == null:
		return "Choose a school of magic first"
	if not lvl(k):
		return "Not researched"
	if cast != null and cast.spell == k:
		return null
	if c.moving:
		return "Stop moving first"
	if cd_left(k) > 0:
		return "Ready in %d s" % ceili(cd_left(k))
	var w = _spell_why(c, k)
	if w != null:
		return w
	var need := mana_need(k)
	if need and mana_of(c) < mc(need):
		var m = SPELL_MANA.get(k)
		return "No mana left" if m is String else "Not enough mana (%d/%d)" % [int(floor(mana_of(c))), mc(need)]
	return null


## Cast (or stop casting) spell k. Spells that need a target (rift, eyes) take it as `target`.
## web: magic.js castSpell + CAST[k].go, v98.js AIMED
func cast_spell(c: Dictionary, k: String, target := -1) -> bool:
	var cast = c.get("cast")
	if cast != null and (cast.spell == "q:" + k or cast.spell == k):
		cancel_cast(c, "Casting stopped.")
		return false
	var why = cast_why(c, k)
	if why != null:
		toast(str(why) + ".", true)
		return false
	match k:
		"harvest":
			start_cast(c, "harvest", INF)
			harvest_by = c.id
			compute_income()
			toast("Harvest: your Farms give %d%% more food while %s keeps casting. Moving stops it." % [JS.round_js(harvest_pct() * 100), c.name])
		"mending":
			spend_mana(c, SPELL_MANA.mending)
			var a: Dictionary = mending_target(c)
			var M: Dictionary = MEND[lvl("mending")]
			if M.dur:
				a.heal = {"t0": t, "dur": M.dur, "w0": a.get("wounds", 0.0)}
			else:
				a.wounds = 0.0
			a.healFx = t
			toast("Mending on %s." % a.name)
			if leader == "sariel":   # web: v105.js (Sariel: +10% health for 30 s afterwards)
				c.mendUntil = t + 30
				toast("%s: %s has 10%% more health for 30 seconds." % [leader_of().full, c.name])
		"mind", "graverob", "trading", "stasis":
			begin_cast(c, k)
			toast("%s: 3 s of casting." % spell_name(k))
		"haunt":
			spend_mana(c, SPELL_MANA.haunt)
			haunts.append({"prov": c.prov, "owner": ME, "t0": t, "until": t + SEE_TIME})
			compute_fog()
			toast("A restless spirit haunts this province: you see it for 1 minute.")
		"eyes":
			var list := see_nbrs(c)
			var q: int = target if target >= 0 else (list[0] if list.size() == 1 else -1)
			if q < 0 or not list.has(q):
				toast("Eyes of the Forest: pick the neighbouring province across the trees.", true)
				return false
			begin_cast(c, "eyes", {"to": q})
			toast("Eyes of the Forest: 3 s of casting.")
		"wrocks":
			var wl := see_nbrs(c, "mountains")
			var wq: int = target if target >= 0 else (wl[0] if wl.size() == 1 else -1)
			if wq < 0 or not wl.has(wq):
				toast("Whispering Rocks: pick the neighbouring province across the mountains.", true)
				return false
			begin_cast(c, "wrocks", {"to": wq})
			toast("Whispering Rocks toward %s: 3 s of casting." % prov_name(wq))
		"tportal":
			spend_mana(c, SPELL_MANA.tportal)
			start_cast(c, "q:tportal", CAST_TIME)
			toast("%s opens a Town Portal to %s: 3 s of casting." % [c.name, prov_name(capital)])
		"gelem":
			spend_mana(c, SPELL_MANA.gelem)
			start_cast(c, "q:gelem", CAST_TIME)
			toast("%s begins to call up a Grand Elemental: 3 s of casting." % c.name)
		"fspirit":
			start_cast(c, "q:fspirit", INF)
			compute_income()
			toast("%s channels a Forest Spirit: %s makes twice the resources while he keeps it up (1 mana a second)." % [c.name, prov_name(c.prov)])
		"spyre":
			begin_cast(c, "spyre")
			toast("%s builds up a Scouting Pyre: 3 s of casting." % c.name)
		"ftrap":
			begin_cast(c, "ftrap")
			toast("%s buries a fire trap: 3 s of casting." % c.name)
		"pfire":   # web: swamp.js CAST.pfire (instant) + v98.js (50 mana)
			spend_mana(c, SPELL_MANA.pfire)
			var P: Dictionary = PATH_FIRE[lvl("pfire")]
			var a = c
			if c.kind != "army":
				for v in units:
					if v.kind == "army" and v.owner == ME and v.prov == c.prov and v.get("battle") == null:
						a = v
						break
			for u in ([c] if a == c else [a, c]):
				u.pathFire = {"until": t + P.dur, "mult": P.mult, "t0": t}
			cd["pfire%d" % c.id] = t + PATH_CD / maxf(1, mages_in(c))
			toast("%s: %s runs %d%% faster for %d s." % [TECH_BY_ID[line_tech("pfire")].name, a.name, JS.round_js((P.mult - 1) * 100), P.dur])
		"sacred":
			stock.wood -= sacred_wood()
			begin_cast(c, "sacred", {"to": c.prov, "wood": sacred_wood()})
			toast("%s raises a Sacred Pyre in %s: 3 s of casting." % [c.name, prov_name(c.prov)])
		"rift":
			var rw = rift_why(c, target) if target >= 0 else "Pick the province to teleport to"
			if rw != null:
				toast("Teleportation Rift: %s." % str(rw).to_lower(), true)
				return false
			begin_cast(c, "rift", {"to": target})
			toast("%s opens a rift: 3 s of casting." % c.name)
	var sc = current_school()
	sfx("mg_rift" if k == "rift" else "mg_" + ("arcane" if sc == "pyro" else "life" if sc == "elemental" else str(sc)), c.prov)
	return true


# web: magic.js pathWhy + v98.js (200 mana)
func path_why(c: Dictionary, q: int, kind: String, close: bool):
	var line := "forest" if kind == "forest" else "tunnel"
	var L := lvl(line)
	if not L:
		return "Not researched"
	if close and L < 3:
		return "Research %s first" % TECH_BY_ID[LINES[line][2]].name
	if not all_nbr[c.prov].has(q):
		return "The Mage must stand next door"
	var style := "trees" if kind == "forest" else "mountains"
	if close:
		if _path_edge(c.prov, q, kind) < 0:
			return "No %s on that border" % ("forest path" if kind == "forest" else "tunnel")
	elif _edge_between(c.prov, q, style, false) < 0:
		return "No border of trees there" if kind == "forest" else "No mountain border there"
	if c.moving:
		return "Stop moving first"
	if not owned(c.prov):
		return "Only from a province you own or occupy"
	if mana_of(c) < mc(PATHS_MANA):
		return "Not enough mana (%d/%d)" % [int(floor(mana_of(c))), mc(PATHS_MANA)]
	return null


func _path_edge(p: int, q: int, kind: String) -> int:
	for i in paths:
		var e: Dictionary = world.edges[i]
		if paths[i] == kind and [e.a, e.b].has(q) and [e.a, e.b].has(p):
			return i
	return -1


func start_path(c: Dictionary, q: int, kind: String, close := false) -> bool:
	var why = path_why(c, q, kind, close)
	if why != null:
		toast(str(why) + ".", true)
		return false
	var dur: float = PATH_CLOSE if close else PATH_OPEN[lvl("forest" if kind == "forest" else "tunnel")]
	start_cast(c, "pathclose" if close else "pathopen", dur, {"to": q, "kind": kind})
	toast("%s %s: %d s of casting." % ["Closing" if close else "Opening", "a path through the trees" if kind == "forest" else "a tunnel under the mountains", dur])
	return true


func open_edge(i: int, kind: String) -> void:
	var e: Dictionary = world.edges[i]
	var a: Array = world.vertices[e.v[0]]
	var b: Array = world.vertices[e.v[1]]
	var m := [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]
	e.open = true
	paths[i] = kind
	open_nbr[e.a].append({"q": e.b, "m": m})
	open_nbr[e.b].append({"q": e.a, "m": m})


func close_edge(i: int) -> void:
	var e: Dictionary = world.edges[i]
	e.open = false
	paths.erase(i)
	open_nbr[e.a] = open_nbr[e.a].filter(func(n): return n.q != e.b)
	open_nbr[e.b] = open_nbr[e.b].filter(func(n): return n.q != e.a)


func teleport(c: Dictionary, to: int) -> void:
	c.path = []
	c.moving = false
	c.surveyQueue = []
	c.lastProv = c.prov
	c.prov = to
	c.slot = free_slot(to, c)
	var xy := slot_pos(to, c.slot)
	c.x = xy[0]
	c.y = xy[1]
	sfx("mg_rift", to)
	c.erase("final")
	compute_fog()


func _finish_q(c: Dictionary, k: String, cs: Dictionary, now: float) -> void:
	match k:
		"mind":
			reveals.append({"prov": c.prov, "all": lvl("mind") >= 2, "until": now + MIND.show})
			cd["mind"] = now + MIND.cd
			toast("Clear Thoughts: armies nearby are revealed for 20 s.")
		"graverob":
			var n := int(floor(mana_of(c)))
			var g := int(JS.round_js(n * GRAVE_RATE[lvl("graverob")] * (1 + 0.02 * rep_lv("rep-graverob"))))
			spend_mana(c, n)
			stock.gold += g
			cd["graverob"] = now + RES_CD
			toast("Grave Robbing: %d mana became %d gold." % [n, g])
			sfx("mg_death", c.prov)
			if leader == "niall" and g > 0:
				stock.gold += 100
				toast("Necromancer Niall: +100 gold from the graves.")
		"trading":
			var n := int(floor(mana_of(c)))
			var each := int(floor(n * TRADE_RATE[lvl("trading")] * (1 + 0.02 * rep_lv("rep-trading"))))
			spend_mana(c, n)
			for r in RES:
				stock[r] += each
			cd["trading"] = now + RES_CD
			toast("Trading across worlds: %d mana became %d of each resource." % [n, each])
			sfx("mg_arcane", c.prov)
			if leader == "alma" and each > 0:
				var x := int(JS.round_js(each * 0.3))
				for r in RES:
					stock[r] += x
				toast("Arcanist Alma: +30%% from the trade (+%d of each)." % x)
		"stasis":
			if trap == null:
				trap = {"prov": c.prov, "t0": now}
				toast("Stasis trap set.")
		"rift":
			var why = rift_why(c, cs.to)
			if why != null:
				toast("The rift collapses: %s." % str(why).to_lower(), true)
				return
			teleport(c, cs.to)
			cd["rift"] = now + RIFT_CD[maxi(1, lvl("rift"))]
			toast("%s steps through the rift." % c.name)
		"wrocks":
			if not see_nbrs(c, "mountains").has(cs.to):
				return
			wrocks.append({"owner": ME, "a": c.prov, "b": cs.to, "edge": _edge_between(c.prov, cs.to, "mountains", null), "t0": now, "until": now + SEE_TIME})
			compute_fog()
			toast("Whispering Rocks: %s and %s are in sight for 1 minute." % [prov_name(c.prov), prov_name(cs.to)])
		"gelem":   # web: wood.js finishElemental
			var a = c if c.kind == "army" else null
			if a == null:
				for v in units:
					if v.kind == "army" and v.owner == ME and v.prov == c.prov and v.get("battle") == null and not v.moving:
						a = v
						break
			if a != null:
				a.troops[GELEM_ID] = a.troops.get(GELEM_ID, 0) + 1
				a.grew = now
			else:
				a = new_army(c.prov, {GELEM_ID: 1})
				a.born = now
			gelems.append({"owner": ME, "until": now + GELEM.life})
			cd["gelem%d" % c.id] = now + GELEM.cd / maxf(1, mages_in(c))
			portal_fx.append({"x": a.x, "y": a.y, "prov": a.prov, "t0": now, "water": true})
			compute_income()
			sfx("mg_life", c.prov)
			toast("A Grand Elemental rises from the earth’s waters and joins %s. It lasts %d minutes." % [a.name, int(GELEM.life / 60)])
		"tportal":
			if capital < 0 or capital == c.prov:
				return
			portal_fx.append({"x": c.x, "y": c.y, "prov": c.prov, "t0": now})
			teleport(c, capital)
			portal_fx.append({"x": c.x, "y": c.y, "prov": capital, "t0": now})
			cd["tportal%d" % c.id] = now + PORTAL_CD / maxf(1, mages_in(c))
			toast("%s steps through the Town Portal to %s." % [c.name, prov_name(capital)])
		"spyre":
			spyres.append({"prov": c.prov, "owner": ME, "t0": now, "until": now + SPYRE.dur})
			cd["spyre%d" % c.id] = now + SPYRE.cd / maxf(1, mages_in(c))
			compute_fog()
			toast("A Scouting Pyre blazes up in %s: for 1 minute it sees every neighboring province in its line of sight." % prov_name(c.prov))
		"ftrap":
			var w = _spell_why(c, "ftrap")
			if w != null:
				toast("Fire Trap: %s." % str(w).to_lower(), true)
				return
			var L := lvl("ftrap")
			var ign := []
			for v in units:
				if v.kind == "army" and v.prov == c.prov and hostile(v.owner, ME):
					ign.append(v.id)
			ftraps.append({"prov": c.prov, "owner": ME, "lv": L, "mult": pow(1.1, rep_lv("rep-ftrap")), "t0": now, "ignore": ign})
			toast("%s set in %s. The next enemy army to enter is engulfed: %d damage to its front line, armor or not." % [TECH_BY_ID[line_tech("ftrap")].name, prov_name(c.prov), FIRE_DMG[L]])
		"sacred":
			var p: int = cs.get("to", c.prov)
			if not owned(p) or occ.has(p) or sacreds.any(func(x): return x.prov == p and x.until > now):
				stock.wood += cs.get("wood", SACRED.wood)
				toast("Sacred Pyre: it can't burn there (wood refunded).", true)
				return
			sacreds.append({"prov": p, "owner": ME, "t0": now, "until": now + SACRED.dur})
			cd["sacred"] = now + SACRED.cd
			compute_income()
			toast("A Sacred Pyre burns in %s: +%d gold every 10 s there for 1 minute." % [prov_name(p), SACRED.gold])
		"eyes":
			if not see_nbrs(c).has(cs.to):
				return
			eyes.append({"owner": ME, "a": c.prov, "b": cs.to, "edge": _edge_between(c.prov, cs.to, "trees", null), "t0": now, "until": now + SEE_TIME})
			compute_fog()
			toast("Eyes of the Forest: both provinces are in sight for 1 minute.")


# web: v98.js syncMana(t): mana follows a Mage from one unit to the next
func sync_mana(now: float) -> void:
	if now < mana_prev_t:
		mana_prev = {}
	mana_prev_t = now
	var cur := {}
	for u in units:
		if mages_in(u) > 0:
			cur[u.id] = u
		elif u.has("mana"):
			mana_pool.append({"owner": u.owner, "prov": u.prov, "mana": u.mana, "t": now})
			u.erase("mana")
	for id in mana_prev:
		var u: Dictionary = mana_prev[id]
		if not cur.has(id) and not units.any(func(v): return is_same(v, u)) and u.has("mana"):
			mana_pool.append({"owner": u.owner, "prov": u.prov, "mana": u.mana, "t": now})
	for u in cur.values():
		if not u.has("mana"):
			var found := -1
			for i in mana_pool.size():
				if mana_pool[i].owner == u.owner and mana_pool[i].prov == u.prov:
					found = i
					break
			if found >= 0:
				u.mana = mana_pool[found].mana
				mana_pool.remove_at(found)
			else:
				u.mana = MANA_START
	mana_prev = cur
	if not mana_pool.is_empty():
		mana_pool = mana_pool.filter(func(r): return now - r.t < 2)


# web: v98.js regenMana() at every payday: each Mage not casting regains mana for every Mage Tower (by level)
func regen_mana() -> void:
	var per := {}
	for c in units:
		if mages_in(c) <= 0 or c.get("cast") != null or c.get("quake"):
			continue
		if not per.has(c.owner):
			per[c.owner] = [mana_regen(c.owner), mana_cap(c.owner)]
		c.mana = minf(per[c.owner][1], mana_of(c) + per[c.owner][0])


# web: v98.js manaRegen(o) + v105.js (a Mage leader's Mages regain 4 more)
func mana_regen(o: int) -> int:
	var r := 0
	for p in extras:
		if nation_of(p) != o or (occ.has(p) and occ[p] != o):
			continue
		for e in extras[p]:
			if e.type == "magetower":
				r += MANA_REGEN[mini(3, e.get("level", 1))]
	var L = leader_of(o)
	if L != null and L.get("start") == "mage":
		r += 4
	return r


# web: magic.js stepMagic(t, dt) + v98.js wrapper
func step_magic(now: float, dt: float) -> void:
	each_seat(func(): sync_mana(now))
	for c in units.duplicate():
		var cs = c.get("cast")
		if cs == null or not is_caster(c):
			continue
		use_seat(c.owner if seats.has(c.owner) else HOST)
		if (cs.spell == "harvest" or cs.spell == "q:fspirit") and not c.moving:   # (a Forest Spirit drains 1 mana a second too)
			c.mana = maxf(0.0, mana_of(c) - dt)
			if c.mana <= 0:
				cancel_cast(c, "%s has run out of mana." % c.name)
				compute_income()
				continue
		if not cs.spell.begins_with("q:") or not is_finite(cs.dur) or c.moving or now - cs.t0 < cs.dur:
			continue
		c.cast = null
		_finish_q(c, cs.spell.substr(2), cs, now)
	# the original channels
	for c in units:
		var cs = c.get("cast")
		if cs == null:
			continue
		use_seat(c.owner if seats.has(c.owner) else HOST)
		if not is_caster(c):
			cancel_cast(c)
			continue
		if c.moving:
			cancel_cast(c, "%s stopped casting." % c.name)
			continue
		if now - cs.t0 < cs.dur:
			continue
		if cs.spell == "pathopen":
			c.cast = null
			var i := _edge_between(c.prov, cs.to, "trees" if cs.kind == "forest" else "mountains", false)
			if i >= 0:
				open_edge(i, cs.kind)
				toast("The trees part: a path opens." if cs.kind == "forest" else "A tunnel opens under the mountains.")
		elif cs.spell == "pathclose":
			c.cast = null
			var i := _path_edge(c.prov, cs.to, cs.kind)
			if i >= 0:
				close_edge(i)
	use_seat(HOST)
	# healing over time
	for a in units:
		if a.get("heal") != null:
			var f := minf(1.0, (now - a.heal.t0) / a.heal.dur)
			a.wounds = a.heal.w0 * (1 - f)
			if f >= 1:
				a.heal = null
	each_seat(func(): _spring_trap(now))
	for a in units:
		if a.get("stasisUntil", 0.0) > now and a.moving:
			a.path = []
			a.moving = false
	each_seat(func(): _magic_timers(now))


# step_magic, for the current seat: its stasis trap
func _spring_trap(now: float) -> void:
	if trap != null:
		for v in units:
			if v.kind == "army" and hostile(v.owner, ME) and v.prov == trap.prov and troop_count(v) > 0:
				var n: int = int(JS.round_js(STASIS[maxi(1, lvl("stasis"))] * pow(1.1, rep_lv("rep-stasis"))))
				v.stasisUntil = now + n
				v.path = []
				v.moving = false
				trap = null
				toast("%s is caught in the stasis trap for %d s!" % [v.name, n])
				if leader == "aarg":   # web: v105.js stepLeaderEffects (Aarg: the trap burns for 100)
					var nk := pure_damage(v, 100)
					toast("%s’s trap burns %s: 100 damage%s." % [leader_of().full, v.name, (", %d soldier%s fall" % [nk, "s" if nk > 1 else ""]) if nk else ""])
				if leader == "eliwen":   # Eliwen: weak for 10 s once it lets go
					v.weakUntil = v.stasisUntil + 10
				break


# step_magic, for the current seat: its reveals, sights and hauntings run out
func _magic_timers(now: float) -> void:
	reveals = reveals.filter(func(r): return r.until > now)
	cd.erase("stasis")
	var n0 := eyes.size() + haunts.size()
	eyes = eyes.filter(func(r): return r.until > now)
	haunts = haunts.filter(func(r): return r.until > now)
	if eyes.size() + haunts.size() != n0:
		compute_fog()


# ---------------------------------------------------------------------------------------------------------------
# saving and loading (web: save.js keeps the seed and regenerates the map; this is the Godot format)

## 1: Godot 0.1–0.4. 2: Godot 0.5 (the build that wrote it, recordings, debug switches). 3: quests, relics, dig
## sites, chests and Reliquaries. Older saves load: fields they don't have keep a new game's defaults (see
## migrate_save). A save from a newer build is refused.
const SAVE_VERSION := 3
## Everything a game is, besides the map (which comes back from the seed) and the callbacks.
const SAVE_FIELDS := ["battles", "bandit_count", "monster_count", "leader", "capital", "stock", "income", "income_parts", "buildings", "extras", "occ", "units", "next_id",
	"army_counter", "tech", "rep", "surveyed", "unit_defs", "designs", "exhaust", "exhaust_ok", "harvest", "devel", "upgrades",
	"xup", "auto_tech", "roads", "walls", "wall_hp", "artifacts", "gift_vault", "quakes", "quake_seq", "wall_max", "wall_crack", "broken_walls", "rewall_jobs", "gate_own", "fort_walled", "gpc_slow_t", "dev_t", "cd", "paths",
	"harvest_by", "trap", "reveals", "eyes", "haunts", "mana_pool", "mana_prev_t", "mage_gear", "finds", "treasure_rolled",
	"sp_found", "slot_races", "spyres", "ftraps", "sacreds", "wrocks", "gelems", "setpieces", "travelers", "train_orders", "train_order_seq", "design_seq", "prov_rename", "nations", "players", "my_nation", "race_of", "wars", "truces", "allies", "war_seq", "met", "occ", "occ_prog", "dipl", "war_log", "war_ever", "war_lock", "ai_met", "fallen", "ally_check", "bandit_next", "bandit_waves", "ally_ask", "crop_scan_at", "ai_scout_t", "wf", "known", "explored", "visible", "queues", "rally", "military", "UNIT_SPEED", "open_nbr", "all_nbr",
	"yields", "look_seed", "tree_border", "debug_cap", "debug_tech", "reveal_all", "rec", "t", "next_tick", "paused", "last", "started", "seat_names", "paused_by", "seat_dipl", "mp_cd", "variant",
	"quests_on", "quest_pick", "digs", "chests", "star_next", "stars_fallen", "quest_log", "quest_rate", "quest_unlocks"]


## The whole game as a plain Dictionary (see SaveCodec for the text form).
func to_save() -> Dictionary:
	var keep: int = ME
	use_seat(HOST)
	var d := _to_save()
	use_seat(keep)
	return d


## The tables a seat's race gives it: not saved (Races.apply makes them again on loading).
const SEAT_RACE_TABLES := ["BUILD_DEFS", "TECH_BY_ID", "TECHS", "TECH_TREES", "UNIT_BASE", "BUILD_ORDER", "CMD"]

func _to_save() -> Dictionary:
	var d := {"version": SAVE_VERSION, "build": str(ProjectSettings.get_setting("application/config/version", "")), "seed": str(world.seed).trim_prefix("practice:"), "practice": world.get("practice", false), "mode": world.get("mode", "practice")}
	var edges := []
	for e in world.edges:
		edges.append([e.open, e.style])
	d.edges = edges
	d.terrain = G.provs.map(func(P): return P.terrain)
	for f in SAVE_FIELDS:
		d[f] = get(f)
	# a unit's battle is saved as the battle's place in the list (and linked up again on loading)
	d.units = []
	for u in units:
		var c: Dictionary = u.duplicate()
		if c.get("battle") != null:
			c.battle = battles.find(u.battle)
		d.units.append(c)
	d.mana_prev = mana_prev.keys()   # unit ids
	d.rng = [rng.seed, rng.state]
	d.dipl = _sorted(dipl)   # (seats swap parts of it in and out: saved in one order, so copies compare alike)
	d.seat_dipl = _sorted(seat_dipl)
	if seats.size() > 1:   # multiplayer: the other human nations' own fields (the host's are the ones above)
		var ss := {}
		for o in seat_ids():
			if o == HOST:
				continue
			var r := {}
			for f in SEAT_FIELDS:
				if not f in SEAT_RACE_TABLES:
					r[f] = seats[o][f]
			r.mana_prev = seats[o].mana_prev.keys()
			ss[str(o)] = r
		d.seats = ss
	return d


func save_text() -> String:
	return SaveCodec.to_text(to_save())


# --- multiplayer: fixed steps and the game's fingerprint ---

## Every copy of a multiplayer game advances in the same fixed steps, never by the real time between frames, so
## all copies compute exactly the same thing (update() caps a real frame at 0.1 s; a fixed step is always STEP).
const STEP := 0.05

func step_fixed(dt := STEP) -> void:
	update(last + dt)


## What doesn't count toward the fingerprint: the moment the game was saved, its version, the recording, and the
## pause flag (each copy shows pause its own way).
const CHECKSUM_SKIP := ["version", "build", "rec", "last", "paused"]

## A fingerprint of the whole game state (the lossless save, in its fixed order): two copies of a multiplayer game
## in step have the same one. Copies compare it every few seconds; a mismatch means one fell out of step and
## gets the host's save.
func checksum() -> int:
	var d := to_save()
	for k in CHECKSUM_SKIP:
		d.erase(k)
	return SaveCodec.to_text(d).hash()


## A game from to_save(); `map` may be a ready map for the same seed (tests reuse one).
static func from_save(d: Dictionary, map: Dictionary = {}) -> Game:
	if not migrate_save(d):
		return null
	var g := Game.new()
	var md: String = d.get("mode", "practice")
	if md == "normal" or md.begins_with("map:"):
		g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_world(d.seed, null if md == "normal" else map_opts_of(md), true))
		g.world.mode = md
	else:
		g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_practice(d.seed))
	g.G = WorldPrep.prep(g.world)   # province shapes come from the map as generated, before walls and paths
	for i in d.edges.size():
		g.world.edges[i].open = d.edges[i][0]
		g.world.edges[i].style = d.edges[i][1]
	for i in d.terrain.size():
		g.G.provs[i].terrain = d.terrain[i]
	for f in SAVE_FIELDS:
		if d.has(f):   # (an older save may not have every field: the new game's default stays)
			g.set(f, d[f])
	var rof := {}
	for k in g.race_of:
		rof[int(k)] = g.race_of[k]
	g.race_of = rof
	for u in g.units:
		if u.get("battle") != null:
			u.battle = g.battles[u.battle]
	for id in g.nations:   # the computer nations' own designs
		for x in g.nations[id].get("designs", []):
			g.register_design(x)
	# multiplayer: the other human nations, then the host's last (its Mage and names are what the shared tables keep)
	var sd: Dictionary = d.get("seats", {})
	for k in sd:
		var o := int(k)
		g.seats[o] = seat_defaults()
		g.use_seat(o)
		for f in sd[k]:
			if f != "mana_prev":
				g.set(f, sd[k][f])
		g._load_seat(sd[k].get("mana_prev", []))
	g.use_seat(HOST)
	g._load_seat(d.mana_prev)
	g.rng.seed = d.rng[0]
	g.rng.state = d.rng[1]
	return g


## from_save, for the current seat: its race's tables, Forge discount, Mage, designs and the links back to units.
func _load_seat(mana_ids: Array) -> void:
	var keep_designs: Array = designs
	var keep_tech: Dictionary = tech
	Races.apply(self, race())   # the race's names on this game's tables (web: save.js → applyRace)
	Quests.add_tables(self)     # (the Reliquary, when this game has quests)
	if leader in Ai.FORGE_LEADERS:
		for k in BUILD_DEFS.forge.cost:
			BUILD_DEFS.forge.cost[k] = int(JS.round_js(GameData.c("BUILD_DEFS").forge.cost[k] * 0.75))
	designs = keep_designs
	tech = keep_tech
	my_nation.color = int(my_nation.get("color", 0))   # (JSON numbers come back as floats)
	if mage_gear.weapon != "stave" or mage_gear.get("shield") != null or mage_gear.get("skull") != null:
		register_mage()
	for x in designs:
		if not x.get("builtin", false):
			register_design(x)
	for u in units:
		if u.get("retro") != null and u.owner == ME:   # the job in its building's queue is the same object
			for key in queues:
				for q in queues[key]:
					if q.get("retro", false) and q.army == u.id:
						u.retro = q
	mana_prev = {}
	for id in mana_ids:
		for u in units:
			if u.id == id:
				mana_prev[id] = u


## Bring an older save up to this build's format, in place; false when it can't be read (a newer build's save).
static func migrate_save(d: Dictionary) -> bool:
	var v := int(d.get("version", 0))
	if v < 1 or v > SAVE_VERSION:
		push_error("Can't read save version %s (this build reads 1 to %d)" % [d.get("version"), SAVE_VERSION])
		return false
	# 1 -> 2: new fields only (debug_cap, debug_tech, reveal_all, rec and the Batch A/B fields); their defaults hold
	# 2 -> 3: new fields only (quests_on false: an older game has no quests, relics or Reliquaries)
	d.version = SAVE_VERSION
	return true


## Why a save can't be loaded, for the player: "" when it can.
static func save_why(text: String) -> String:
	var d = SaveCodec.from_text(text)
	if not (d is Dictionary):
		return "That save can't be read."
	var v := int(d.get("version", 0))
	if v > SAVE_VERSION:
		return "That save was made by a newer version of Realmlings (%s). Update the game to load it." % d.get("build", "?")
	if v < 1:
		return "That save can't be read."
	return ""


static func load_text(text: String, map: Dictionary = {}) -> Game:
	var d = SaveCodec.from_text(text)
	return from_save(d, map) if d is Dictionary else null


# ---------------------------------------------------------------------------------------------------------------
# battles (web: game.js stepBattles / sideStrength / applyDamage / endBattle / retreat, equip.js sideMix,
# v97.js front and back rows, v104.js / v106.js ranged soldiers, v98.js battle spells and mana, v102.js meetHeadOn)
# Not yet: wars between nations, sieges, lone Mages standing alone (v102), Fiery Weapons / Rock Armor (other races).

const RAIDERS := 3
const ROUND := 0.8
const DMG_RATE := 0.22
const RETREAT_LOSS := 0.6
const RETREAT_LOCK := 10.0
const MEET_DIST := 60.0
const ROW_MIN := 6
const BACK_DEAL := 0.5
const BACK_TAKE := 0.5
const RNG_FRONT := 0.4
const RNG_BACK_DR := 0.8
const SKIN := [{}, {"pct": 0.05, "cd": 300}, {"pct": 0.10, "cd": 180}, {"pct": 0.15, "cd": 90}]
const CURSE := [{}, {"pct": 0.05, "cd": 300}, {"pct": 0.10, "cd": 180}, {"pct": 0.15, "cd": 90}]
const RISEN_N := [0, 5, 7, 10]
const RISEN_CD := 120.0
const AUTO_MANA := 50
const BANDIT := {"troops": {"d-sword": 2}, "bounty": 50}
const TERRAIN_MOD := {"grassland": "Open ground: cavalry +20%", "forest": "Forest: defenders +25%, cavalry −25%",
	"swamp": "Swamp: everyone −20%, cavalry −30%", "desert": "Desert: no modifiers"}


static func terrain_mod(ter: String, cav: bool, def: bool) -> float:
	match ter:
		"grassland":
			return 1.2 if cav else 1.0
		"forest":
			return (1.25 if def else 1.0) * (0.75 if cav else 1.0)
		"swamp":
			return 0.8 * (0.7 if cav else 1.0)
	return 1.0


func hostile(a: int, b: int) -> bool:
	return a != b and (a == RAIDERS or b == RAIDERS or (not wars.is_empty() and at_war(a, b)))


## Every army with soldiers, by the province it stands in, in the units' order (for loops that would otherwise scan
## all units for each unit; same answers).
func armies_by_prov() -> Dictionary:
	var out := {}
	for v in units:
		if v.kind == "army" and troop_count(v) > 0:
			if not out.has(v.prov):
				out[v.prov] = []
			out[v.prov].append(v)
	return out


func hostiles_in(p: int, owner: int) -> Array:
	return units.filter(func(v): return v.kind == "army" and hostile(v.owner, owner) and v.prov == p and not v.get("retreating", false) and troop_count(v) > 0)


func bandits_in(p: int) -> bool:
	return units.any(func(v): return v.get("bandit", false) and v.prov == p and troop_count(v) > 0)


func bandits_seen_in(p: int) -> bool:
	return units.any(func(v): return v.get("bandit", false) and v.get("seen", false) and v.prov == p and troop_count(v) > 0)


func mason_danger(u: Dictionary, q: int) -> bool:
	return units.any(func(v): return v.kind == "army" and v.prov == q and troop_count(v) > 0 and not v.get("retreating", false) \
		and hostile(v.owner, u.owner) and (u.owner != ME or (v.get("seen", false) if v.get("bandit", false) else visible.has(q))))


# web: equip.js statsOf (no artifacts on the Practice island) + content.js boostStats (repeatable research)
func stats_of(k: String, o: int) -> Dictionary:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return stats_of(k, o))
	var st: Dictionary = DSTATS.get(k, GameData.c("STATS0"))
	if o != ME:
		return art_stats(k, st, o)
	var out := st.duplicate()
	var fam_rep = GameData.c("REP_FAM").get(st.get("line") if st.get("fam") == "magic" else st.get("fam"))
	if fam_rep != null:
		out.atk = st.atk * (1 + 0.05 * rep_lv(fam_rep))
	if st.get("armor", 0) > 0 and st.get("red", 0) > 0:
		var sh: float = st.get("shieldArmor", 0)
		var ar: float = st.armor - sh
		out.red = minf(0.85, st.red * (ar / st.armor) * (1 + 0.05 * rep_lv("rep-armor")) + st.red * (sh / st.armor) * (1 + 0.05 * rep_lv("rep-shield")))
	if st.get("cav", false):
		out.hp = st.hp * (1 + 0.05 * rep_lv("rep-cavhp"))
	return art_stats(k, out, o)


# web: v104.js / v105.js artStats wrappers for any owner (artifacts and the Grand Elemental come later):
# crossbows by the researched tier, then the leader's bonus to health, attack or critical blows
const RNG_ATK := [6, 9, 12]

func art_stats(k: String, st: Dictionary, o := ME) -> Dictionary:
	var out := st
	# v95: the Blue Dragon Skull (+15% health), the Essence of Flame (+10 attack), the Grips of the Beast (+15 for maces)
	var A = artifacts.get(o)
	if o and o != RAIDERS and A != null and not A.is_empty() and st.get("fam") != "boss":
		out = st.duplicate()
		if A.has("blueskull"):
			out.hp = st.hp * 1.15
		if A.has("flame") and st.atk > 0:
			out.atk += 10
		if A.has("grips") and st.get("fam") == "blunt":
			out.atk += 15
	var R = GameData.c("RNG_BY_KIND").get(k)
	if R != null:
		var tr := (2 if tech_of(o, R.techs[1]) else 1) if tech_of(o, R.techs[0]) else 0
		if tr:
			out = out.duplicate()
			out.atk = out.atk + RNG_ATK[tr] - RNG_ATK[0]
	if k == GELEM_ID and o and o != RAIDERS:   # web: v105.js artStats (Naobrien: the Grand Elemental hits 30% harder)
		var LG = leader_of(o)
		if LG != null and LG.id == "naobrien":
			out = out.duplicate()
			out.atk = out.atk * 1.3
		return out
	if k == MAGE or out.get("fam") == "boss" or out.get("fam") == "water":
		return out
	if not o or o == RAIDERS:
		return out
	var L = leader_of(o)
	if L == null:
		return out
	var inf: bool = not out.get("cav", false) and not out.get("ranged", false)
	var r := out
	match L.id:
		"hisola":
			if r.get("cav", false) and not r.get("ogre", false) and not r.get("champ", false):
				out = r.duplicate(); out.hp = r.hp * 1.1
		"cormac":
			if inf:
				out = r.duplicate(); out.hp = r.hp * 1.1
		"aithne":
			if r.get("ranged", false) and r.get("race") == "realm":
				out = r.duplicate(); out.atk = r.atk + 1
		"taal":
			if r.get("ogre", false):
				out = r.duplicate(); out.atk = r.atk * 1.1
		"marl":
			if inf and r.get("race") == "swamp":
				out = r.duplicate(); out.crit = r.get("crit", 0.0) + 0.1
		"zaarg":
			if r.get("ranged", false) and r.get("race") == "swamp":
				out = r.duplicate(); out.atk = r.atk + 3
		"zariel":
			if r.get("ranged", false) and r.get("race") == "wood":
				out = r.duplicate(); out.atk = r.atk + 2
	return out


func hp_of(a: Dictionary, k: String) -> float:
	return stats_of(k, a.owner).hp


func is_rng(k: String) -> bool:
	return GameData.c("RNG_BY_KIND").has(k)


func side_mix(armies: Array) -> Dictionary:
	var n := 0.0
	var cav := 0.0
	var red := 0.0
	var parry := 0.0
	var blunt := 0.0
	var atk := 0.0
	var plate := 0.0
	for a in armies:
		for k in a.troops:
			var c: float = a.troops[k]
			var st := stats_of(k, a.owner)
			n += c
			if st.get("plate", false):
				plate += c
			if st.get("cav", false) and not st.get("champ", false):
				cav += c
			red += c * st.get("red", 0.0)
			parry += c * st.get("parry", 0.0)
			if st.get("fam") == "blunt":
				blunt += c * st.atk
			atk += c * st.atk
	if not n:
		return {"n": 0, "cavFrac": 0.0, "plateFrac": 0.0, "red": 0.0, "parry": 0.0, "pierce": 0.0}
	return {"n": n, "cavFrac": cav / n, "plateFrac": plate / n, "red": red / n, "parry": parry / n, "pierce": blunt / atk if atk else 0.0}


# --- rows (v97, v104): armies of 6 or more fight in a front and a back row ---

static func row_sum(o: Dictionary) -> int:
	var n := 0
	for k in o:
		n += o[k]
	return n


func row_join_sync(a: Dictionary) -> Array:
	var j: Array = a.get("rowJoin", []).filter(func(k): return a.troops.get(k, 0) > 0)
	for k in a.troops:
		if a.troops[k] > 0 and not j.has(k):
			j.append(k)
	a.rowJoin = j
	return j


func row_layout(a: Dictionary) -> Dictionary:
	var mage: String = GameData.c("MAGE")
	var N := troop_count(a)
	var F := ceili(N / 2.0)
	var f := {}
	var b := {}
	var ks: Array = row_join_sync(a).filter(func(k): return k != mage)
	var none := ks.filter(func(k): return not is_rng(k))
	var rng_k := ks.filter(func(k): return is_rng(k))
	var room := F
	var rng_major := false   # (v104 rngMajor: rows ordered by the player come later)
	for k in none + rng_k if not rng_major else none + rng_k:
		var n := mini(room, a.troops[k])
		if n:
			f[k] = n
		room -= n
		if a.troops[k] - n:
			b[k] = a.troops[k] - n
	if a.troops.get(mage, 0):
		b[mage] = a.troops[mage]
	return {"f": f, "b": b}


func row_reconcile(a: Dictionary, lay: Dictionary) -> void:
	var mage: String = GameData.c("MAGE")
	var N := troop_count(a)
	var F := ceili(N / 2.0)
	var keys := {}
	for k in lay.f:
		keys[k] = true
	for k in lay.b:
		keys[k] = true
	for k in a.troops:
		keys[k] = true
	for k in keys:
		var tt: int = a.troops.get(k, 0)
		var have: int = lay.f.get(k, 0) + lay.b.get(k, 0)
		while have > tt:
			if lay.f.get(k, 0):
				lay.f[k] -= 1
			else:
				lay.b[k] -= 1
			have -= 1
		while have < tt:
			if k != mage and not is_rng(k) and row_sum(lay.f) < F:
				lay.f[k] = lay.f.get(k, 0) + 1
			else:
				lay.b[k] = lay.b.get(k, 0) + 1
			have += 1
		if not lay.f.get(k, 0):
			lay.f.erase(k)
		if not lay.b.get(k, 0):
			lay.b.erase(k)


func row_sync(a) :
	if a == null or a.kind != "army" or troop_count(a) < ROW_MIN:
		if a != null:
			a.rowLay = null
		return null
	if a.get("battle") == null:
		var key := _row_key(a)
		if a.get("rowLay") == null or a.get("rowLayKey") != key:
			a.rowLay = row_layout(a)
			a.rowLayKey = key
		return a.rowLay
	if a.get("rowLay") == null:
		a.rowLay = row_layout(a)
	row_reconcile(a, a.rowLay)
	a.rowLayKey = null
	return a.rowLay


static func _row_key(a: Dictionary) -> String:
	var ks: Array = a.troops.keys()
	ks.sort()
	return ",".join(ks.map(func(k): return "%s%d" % [k, a.troops[k]]))


func row_fall(a: Dictionary, lay: Dictionary, k: String, front: bool) -> void:
	var mage: String = GameData.c("MAGE")
	if front:
		if lay.f.get(k, 0):
			lay.f[k] -= 1
			if not lay.f[k]:
				lay.f.erase(k)
		var all: Array = lay.b.keys().filter(func(kk): return kk != mage and lay.b[kk] > 0)
		var mel := all.filter(func(kk): return not is_rng(kk))
		var pool: Array = mel if not mel.is_empty() else all
		var tot := 0
		for kk in pool:
			tot += lay.b[kk]
		if tot:
			var r: float = battle_rand.call() * tot
			var pick = pool[0]
			for kk in pool:
				r -= lay.b[kk]
				if r <= 0:
					pick = kk
					break
			lay.b[pick] -= 1
			if not lay.b[pick]:
				lay.b.erase(pick)
			lay.f[pick] = lay.f.get(pick, 0) + 1
	elif lay.b.get(k, 0):
		lay.b[k] -= 1
		if not lay.b[k]:
			lay.b.erase(k)


func row_deal(a: Dictionary, k: String) -> float:
	var n: int = a.troops.get(k, 0)
	var lay = row_sync(a)
	if is_rng(k):
		if lay == null:
			return n * RNG_FRONT
		return lay.f.get(k, 0) * RNG_FRONT + lay.b.get(k, 0)
	if lay == null or k == GameData.c("MAGE"):
		return n
	return lay.f.get(k, 0) + lay.b.get(k, 0) * BACK_DEAL


# web: v105.js sideStrength wrapper: a weakened army (Eliwen's stasis) deals 25% less
func side_strength(armies: Array, prov: int, defender: bool, foe: Dictionary) -> float:
	var weak := armies.filter(func(a): return a.get("weakUntil", 0.0) > t)
	if weak.is_empty():
		return side_strength0(armies, prov, defender, foe)
	var strong := armies.filter(func(a): return not (a.get("weakUntil", 0.0) > t))
	return (side_strength0(strong, prov, defender, foe) if not strong.is_empty() else 0.0) + 0.75 * side_strength0(weak, prov, defender, foe)


func side_strength0(armies: Array, prov: int, defender: bool, foe: Dictionary) -> float:
	var ter: String = world.provinces[prov].terrain
	var s := 0.0
	var bog := BOG_DEF if defender and variant_of(prov) == "bog" else 1.0   # 0.18: defenders +30% in a Bog
	for a in armies:
		var home: bool = ter == "swamp" and is_sw(a.owner)   # web: game.js sideStrength (Swamplings at home in a swamp)
		var crit := 1.0
		if a.get("fiery", 0.0) and battle_rand.call() < a.fiery:   # web: swamp.js Fiery Weapons: a round's blows land twice as hard
			crit = 2.0
			a.fieryHit = t
			a.fieryHits = a.get("fieryHits", 0) + 1
		for k in a.troops:
			var st := stats_of(k, a.owner)
			var blows := row_deal(a, k)
			if st.get("crit", 0) and blows:
				var c := 0
				for i in int(blows):
					if battle_rand.call() < st.crit:
						c += 1
				blows += c
			s += blows * st.atk * terrain_mod(ter, st.get("cav", false) and not st.get("rough", false) and not home, defender) * (1.2 if home else 1.0) * crit \
				* ((1 + 0.5 * foe.cavFrac) if st.get("fam") == "pole" else 1.0) * ((1 + 0.5 * foe.plateFrac) if st.get("fam") == "blunt" else 1.0) \
				* (1 + a.get("curse", 0.0)) * (two_mul(a) if st.get("two", false) else 1.0) * bog
	return s


# web: wood.js twoMul: a two-handed grip lands heavy blows every other round (150%, then 100%: 125% over time)
func two_mul(a: Dictionary) -> float:
	if a.get("twoT") != t:
		a.twoT = t
		a.twoOn = not a.get("twoOn", false)
		if a.twoOn:
			a.twoHit = t
	return TWO_BURST if a.twoOn else 0.0


func raw_strength(armies: Array) -> float:
	var n := 0.0
	for a in armies:
		for k in a.troops:
			var st := stats_of(k, a.owner)
			n += a.troops[k] * st.atk * (hp_of(a, k) / 30.0) / (1 - st.get("red", 0.0))
	return n


func battle_center(p: int) -> Array:
	var c: Array = G.provs[p].ic
	return [c[0], c[1] + (96 if buildings.has(p) else 34)]


func place_sides(b: Dictionary, sides: Dictionary) -> void:
	var bc := battle_center(b.prov)
	var c := [bc[0], bc[1] - 34]
	var owners: Array = sides.keys()
	owners.sort_custom(func(x, y): return x == ME or (y != ME and x < y))
	for i in owners.size():
		var dir := -1 if i == 0 else 1
		var j := 0
		for a in sides[owners[i]]:
			a.x = c[0] + dir * 62
			a.y = c[1] + 34 + j * 14
			a.th = PI / 2 if dir < 0 else -PI / 2
			j += 1
	b.order = owners


func step_battles(now: float) -> void:
	var by_prov := {}
	for a in units:
		if a.kind != "army" or a.get("retreating", false) or a.get("exiting", false) or troop_count(a) <= 0:
			continue
		if not by_prov.has(a.prov):
			by_prov[a.prov] = []
		by_prov[a.prov].append(a)
	for p in by_prov:
		var list: Array = by_prov[p]
		var os := []
		for a in list:
			if not os.has(a.owner):
				os.append(a.owner)
		var pair = null
		for x in os:
			for y in os:
				if pair == null and hostile(x, y):
					pair = [x, y]
		if pair == null:
			continue
		var b = null
		for x in battles:
			if x.prov == p:
				b = x
		if b == null:
			var first: Dictionary = list[0]
			var sorted_list := list.duplicate()
			sorted_list.sort_custom(func(x, y): return x.get("arrived", 0.0) < y.get("arrived", 0.0))
			first = sorted_list[0]
			b = {"prov": p, "t0": now, "next": now + ROUND, "defender": buildings[p].owner if buildings.has(p) else first.owner, "start": {}, "lost": {}, "hits": {}}
			# remember any capture under way: if the capturing side wins this battle, its progress comes back
			if occ_prog.has(p):
				b.prog = occ_prog[p].duplicate()
			battles.append(b)
			if list.any(func(a): return a.owner == ME):
				sfx("bat_loop", p)
				toast("Battle in the %s! %s." % [terrain_name(p), TERRAIN_MOD[world.provinces[p].terrain] + (", defenders +30%" if variant_of(p) == "bog" else "")])
		for a in list:
			if a.get("battle") == null and pair.has(a.owner):
				on_battle_join(a, now)
				a.battle = b
				a.path = []
				a.moving = false
				a.retreatHome = false
				b.start[a.owner] = b.start.get(a.owner, 0) + troop_count(a)
		if quests_on:   # the Freak Man's Bone Regalia takes the enemy's battle spells
			Quests.steal_buffs(self, b)
	for b in battles.duplicate():
		var sides := {}
		for a in units:
			if a.kind == "army" and is_same(a.get("battle"), b) and not a.get("retreating", false) and troop_count(a) > 0:
				if not sides.has(a.owner):
					sides[a.owner] = []
				sides[a.owner].append(a)
		var owners: Array = sides.keys()
		owners.sort()   # web: Object.keys(sides) lists number keys in ascending order
		place_sides(b, sides)
		if owners.size() < 2:
			end_battle(b, owners[0] if owners.size() else -1, sides)
			continue
		if not hostile(owners[0], owners[1]):   # a peace was made mid-battle
			b.peace = true
			end_battle(b, -1, sides)
			continue
		if now < b.next:
			continue
		b.next = now + ROUND
		var A: int = owners[0]
		var B2: int = owners[1]
		var mix_a := side_mix(sides[A])
		var mix_b := side_mix(sides[B2])
		var dmg_a: float = side_strength(sides[A], b.prov, A == b.defender, mix_b) * DMG_RATE * (0.85 + battle_rand.call() * 0.3)
		var dmg_b: float = side_strength(sides[B2], b.prov, B2 == b.defender, mix_a) * DMG_RATE * (0.85 + battle_rand.call() * 0.3)
		apply_damage(b, sides[B2], dmg_a, now, mix_a.pierce)
		apply_damage(b, sides[A], dmg_b, now, mix_b.pierce)
		b.hits[A] = now
		b.hits[B2] = now
		_bleed(b, sides, owners, now)
		for o in owners:
			for a in sides[o]:
				if troop_count(a) <= 0:
					war_wipe(b, a)
					if a.get("bandit", false):
						bandit_slain(a, b)
					remove_army(a)


# web: v105.js Bleeding (Paladomis): each two-handed Protector's blow has a 20% chance to deal its damage again over
# the next 4 rounds
func _bleed(b: Dictionary, sides: Dictionary, owners: Array, now: float) -> void:
	if not b.has("bleed"):
		b.bleed = {}
	for o in owners:
		var foe = null
		for x in owners:
			if x != o and hostile(x, o):
				foe = x
				break
		if foe == null:
			continue
		var L = leader_of(o) if is_nation(o) else null
		if L != null and L.id == "paladomis":
			for a in sides[o]:
				for k in a.troops:
					var st := stats_of(k, o)
					if not st.get("two", false) or st.get("cav", false) or st.get("ranged", false):
						continue
					var n := 0
					for i in int(a.troops[k]):
						if js_rand.call() < 0.2:
							n += 1
					if n:
						if not b.bleed.has(foe):
							b.bleed[foe] = []
						b.bleed[foe].append({"per": n * st.atk * DMG_RATE * two_mul(a) / 4, "left": 4})
		var lst: Array = b.bleed.get(o, [])
		if lst.is_empty():
			continue
		var dmg := 0.0
		for x in lst:
			dmg += x.per
			x.left -= 1
		b.bleed[o] = lst.filter(func(x): return x.left > 0)
		if dmg > 0:
			apply_damage(b, sides[o], dmg, now, 1.0)
			for a in sides[o]:
				if troop_count(a) <= 0:
					war_wipe(b, a)
					remove_army(a)


# web: v105.js pureDamage: wounds that ignore armor, to random soldiers (not Mages)
func pure_damage(a: Dictionary, dmg: float) -> int:
	a.wounds = a.get("wounds", 0.0) + dmg
	var n := 0
	while true:
		var ks: Array = a.troops.keys().filter(func(k): return a.troops[k] > 0 and k != MAGE)
		if ks.is_empty():
			break
		var k = ks[int(floor(js_rand.call() * ks.size()))]
		if a.wounds < hp_of(a, k):
			break
		a.wounds -= hp_of(a, k)
		a.troops[k] -= 1
		if a.troops[k] <= 0:
			a.troops.erase(k)
		n += 1
	if troop_count(a) <= 0:
		remove_army(a)
	return n


func remove_army(a: Dictionary) -> void:
	a._gone = true
	units = units.filter(func(v): return not is_same(v, a))
	if a.owner == ME:
		compute_income()


func apply_damage(b: Dictionary, armies: Array, dmg: float, now: float, pierce := 0.0) -> void:
	var boosted := armies.filter(func(a): return a.get("mendUntil", 0.0) > t)   # web: v105.js (Sariel's Mending works like a little Hardened Skin)
	for a in boosted:
		a.skin = a.get("skin", 0.0) + 0.1
	apply_damage0(b, armies, dmg, now, pierce)
	for a in boosted:
		a.skin -= 0.1


func apply_damage0(b: Dictionary, armies: Array, dmg: float, now: float, pierce := 0.0) -> void:
	var bd := boss_damage(b, armies, dmg)
	if bd >= 0:
		dmg = bd
		pierce = 0.0
	var total := 0
	for a in armies:
		total += troop_count(a)
	if not total:
		return
	var sh := armies.filter(func(x): return x.get("rock") != null and x.rock.hp > 0)
	if not sh.is_empty() and dmg > 0:   # web: wood.js applyDamage (Rock Armor soaks the blows first)
		var mx := side_mix(armies)
		if is_wd(armies[0].owner) and world.provinces[b.prov].terrain == "forest" and mx.red > 0 and mx.red < 1:
			var ak0: float = GameData.c("ARMOR_K")
			var A0: float = mx.red * ak0 / (1 - mx.red) * 1.2
			mx.red = A0 / (A0 + ak0)
		var fct := maxf(0.01, (1 - mx.red * (1 - 0.5 * pierce)) * (1 - mx.parry))
		var pool := 0.0
		for x in sh:
			pool += x.rock.hp
		var post := dmg * fct
		var soak := minf(pool, post)
		for x in sh:
			x.rock.hp -= soak * x.rock.hp / pool
			x.rockHit = now
			if x.rock.hp < 0.5:
				x.rock.hp = 0
				x.rockBroke = now
				if x.owner == ME:
					toast("%s: the Rock Armor shatters." % x.name, true)
		dmg = (post - soak) / fct
		if dmg <= 0.001:
			return
	var mix := side_mix(armies)
	if is_wd(armies[0].owner) and world.provinces[b.prov].terrain == "forest" and mix.red > 0 and mix.red < 1:   # web: game.js applyDamage (Woodlings: +20% armor in a forest)
		var ak: float = GameData.c("ARMOR_K")
		var A: float = mix.red * ak / (1 - mix.red) * 1.2
		mix.red = A / (A + ak)
	dmg *= (1 - mix.red * (1 - 0.5 * pierce)) * (1 - mix.parry)
	var owner: int = armies[0].owner
	fx.append({"kind": "num", "prov": b.prov, "owner": owner, "n": roundi(dmg), "t0": now})
	for a in armies:
		var share: float = dmg * troop_count(a) / total / (1 + a.get("skin", 0.0))
		var lay = row_sync(a)
		var halved: bool = lay != null and row_sum(lay.f) <= 0
		a.wounds = a.get("wounds", 0.0) + (share * BACK_TAKE if halved else share)
		while true:
			var kinds: Array = a.troops.keys().filter(func(k): return a.troops[k] > 0)
			if kinds.is_empty():
				break
			lay = row_sync(a)
			var front: bool = lay != null and row_sum(lay.f) > 0
			if lay != null and not front and not halved:
				a.wounds *= BACK_TAKE
				halved = true
			var pool: Dictionary = a.troops if lay == null else (lay.f if front else lay.b)
			var tot := 0.0
			for kk in kinds:
				tot += pool.get(kk, 0)
			var r: float = battle_rand.call() * tot
			var k = null
			for kk in kinds:
				if pool.get(kk, 0) > 0:
					k = kk
					break
			if k == null:
				k = kinds[0]
			for kk in kinds:
				r -= pool.get(kk, 0)
				if r <= 0 and pool.get(kk, 0) > 0:
					k = kk
					break
			var take := (1.0 / (1 - RNG_BACK_DR)) if (not (lay == null or front) and is_rng(k)) else 1.0
			var hk := hp_of(a, k) * take
			if a.wounds < hk:
				break
			a.wounds -= hk
			if risen_rise(a, k, b, now):
				continue
			ghoul_fall(a, k)
			if lay != null:
				row_fall(a, lay, k, front)
			fx.append({"kind": "fall", "prov": b.prov, "owner": a.owner, "unit": k, "t0": now, "r": fx_rand()})
			a.troops[k] -= 1
			if not a.troops[k]:
				a.troops.erase(k)
			if a.get("monster") != null:
				monster_loot(a, k, b)
			if a.has("fallen"):
				a.fallen[k] = a.fallen.get(k, 0) + 1
			b.lost[owner] = b.lost.get(owner, 0) + 1
			if owner == ME or b.get("start", {}).has(ME):
				sfx("bat_fall", b.prov)


func end_battle(b: Dictionary, winner: int, sides: Dictionary) -> void:
	battles = battles.filter(func(x): return not is_same(x, b))
	war_battle_check(b)
	for a in units:
		if is_same(a.get("battle"), b):
			on_battle_end(a, t)
	for a in units:
		if is_same(a.get("battle"), b):
			a.battle = null
			if not a.get("retreating", false):
				a.slot = free_slot(a.prov, a)
				var xy := slot_pos(a.prov, a.slot)
				a.path = [{"x": xy[0], "y": xy[1], "slot": true}]
				a.moving = true
	# the capture under way when the battle began comes back if the capturing side won, and is lost if it didn't
	if b.get("prog") != null:
		var cur = occ_prog.get(b.prov)
		if winner == b.prog.by:
			if cur == null or cur.by != b.prog.by or cur.f < b.prog.f:
				occ_prog[b.prov] = b.prog.duplicate()
			if winner == ME:
				toast("The capture of %s resumes where it left off." % prov_name(b.prov))
		elif cur != null and cur.by == b.prog.by:
			occ_prog.erase(b.prov)
	if not b.start.has(ME):
		return
	var mine: int = b.lost.get(ME, 0)
	var theirs := 0
	for o in b.lost:
		if o != ME:
			theirs += b.lost[o]
	var where: String = world.provinces[b.prov].terrain
	sfx("bat_win" if winner == ME else "bat_lose")
	if winner == ME:
		toast("Victory in the %s! You lost %d, the enemy lost %d.%s" % [where, mine, theirs, " The Bandit Gang is broken: +%d gold bounty." % b.bounty if b.has("bounty") else ""])
	elif b.get("retreatedMe", false):
		toast("You withdrew from the %s. You lost %d, the enemy lost %d." % [where, mine, theirs], true)
	else:
		toast("Defeat in the %s. You lost %d, the enemy lost %d." % [where, mine, theirs], true)
	compute_income()


func bandit_slain(a: Dictionary, b: Dictionary) -> void:
	if a.get("boss") != null:
		boss_slain(a, b)
	if a.get("monster") != null:
		return
	if b.start.has(ME):
		stock.gold += BANDIT.bounty
		b.bounty = b.get("bounty", 0) + BANDIT.bounty
	else:
		var o := first_nation_in(b.start)
		if o:
			nations[o].stock.gold += BANDIT.bounty


func monster_loot(a: Dictionary, k: String, b: Dictionary) -> void:
	var L = GameData.c("MONSTER_LOOT").get(k)
	if L == null:
		return
	if b.start.has(ME) and a.owner != ME:
		if not b.has("loot"):
			b.loot = {}
		for r in L:
			stock[r] = stock.get(r, 0) + L[r]
			b.loot[r] = b.loot.get(r, 0) + L[r]
		return
	var o := first_nation_in(b.start)
	if o:
		for r in L:
			nations[o].stock[r] = nations[o].stock.get(r, 0) + L[r]


## the lowest computer nation id among a battle's sides (web: Object.keys(b.start) lists number keys in order)
func first_nation_in(d: Dictionary) -> int:
	var ks := d.keys().map(func(x): return int(x))
	ks.sort()
	for o in ks:
		if nations.has(o):
			return o
	return 0


# --- battle spells (magic.js onBattleJoin / onBattleEnd + v96 / v98 / v105 wrappers) ---

func on_battle_join(a: Dictionary, now: float) -> void:
	# v99: warscore for beating an army depends on its size and its nation's whole army
	if a.kind == "army":
		a.wsSize = troop_count(a) - a.troops.get(MAGE, 0)
		a.wsTotal = soldier_count(a.owner)
	a.fallen = {}
	a.skin = 0.0
	a.curse = 0.0
	a.risen = 0
	if a.kind != "army" or mages_in(a) <= 0:
		a.risenArm = 0
		return
	var poor: bool = mana_of(a) < mc(AUTO_MANA)
	if is_caster(a) and not poor:
		var sk := lvl("skin")
		var cu := lvl("curse")
		var ri := lvl("risen")
		if sk and _auto_on(a, "skin") and a.get("skinCd", 0.0) <= now:
			a.skin = SKIN[sk].pct
			a.skinCd = now + SKIN[sk].cd
			toast("%s: %s (+%d%% health)." % [a.name, TECH_BY_ID[line_tech("skin")].name, JS.round_js(SKIN[sk].pct * 100)])
		if cu and _auto_on(a, "curse") and a.get("curseCd", 0.0) <= now:
			a.curse = CURSE[cu].pct
			a.curseCd = now + CURSE[cu].cd
			toast("%s: %s (+%d%% damage)." % [a.name, TECH_BY_ID[line_tech("curse")].name, JS.round_js(CURSE[cu].pct * 100)])
		if ri and _auto_on(a, "risen") and a.get("risenCd", 0.0) <= now:
			a.risen = 1
	a.rock = null
	a.twoOn = true
	a.twoT = -1.0
	if is_caster(a) and not poor and lvl("rock") and _auto_on(a, "rock"):   # web: wood.js raiseRock + v98.js (50 mana, no cooldown)
		var hp := 0.0
		for k in a.troops:
			if a.troops[k] > 0:
				hp += a.troops[k] * hp_of(a, k)
		var rh := JS.round_js(hp * ROCK_PCT * pow(1.1, rep_lv("rep-rock")))
		if rh > 0:
			a.rock = {"hp": rh, "max": rh, "t0": now}
			spend_mana(a, AUTO_MANA)
			toast("%s: Rock Armor (a stone shield worth %d health)." % [a.name, rh])
	a.fiery = 0.0
	if is_caster(a) and not poor and lvl("fiery") and _auto_on(a, "fiery"):   # web: swamp.js onBattleJoin (Fiery Weapons) + v98.js (50 mana, no cooldown)
		a.fiery = FIERY[lvl("fiery")] * (1 + 0.1 * rep_lv("rep-fiery"))
		a.fieryHits = 0
		spend_mana(a, AUTO_MANA)
		toast("%s: %s (%d%% chance of double blows)." % [a.name, TECH_BY_ID[line_tech("fiery")].name, JS.round_js(a.fiery * 100)])
	if a.owner == ME:
		if a.skin:
			a.skin *= 1 + 0.1 * rep_lv("rep-skin")
		if a.curse:
			a.curse *= 1 + 0.1 * rep_lv("rep-curse")
	var fired := int(a.skin > 0) + int(a.curse > 0)
	if fired:
		spend_mana(a, AUTO_MANA * fired)
	if a.skin > 0:
		a.skinCd = 0.0
	a.risenArm = RISEN_N[maxi(1, lvl("risen"))] if a.risen else 0
	a.risen = 0
	a.risenUsed = false
	a.risenLeft = 0
	if leader == "havva" and a.owner == ME and a.skin > 0:
		a.skin *= 1.2
	var LJ = leader_of(a.owner) if is_nation(a.owner) else null
	if LJ != null and LJ.id == "nihaarg" and a.get("curse", 0.0) > 0:   # web: v105.js (Nihaarg: Cursed Weapons +10% damage)
		a.curse += 0.1


func _auto_on(c: Dictionary, k: String) -> bool:
	return c.get("auto") == null or not (c.auto is Dictionary) or c.auto.get(k, true) != false


func on_battle_end(a: Dictionary, now: float) -> void:
	if a.get("fiery", 0.0) and a.owner == ME and a.get("fieryHits", 0):
		toast("%s: Fiery Weapons struck %d double blow%s in that battle." % [a.name, a.fieryHits, "s" if a.fieryHits > 1 else ""])
	a.fiery = 0.0
	a.fieryHits = 0
	if a.get("risenUsed", false):
		a.risenCd = now + RISEN_CD
	a.risenArm = 0
	a.risenUsed = false
	a.risenLeft = 0
	a.skin = 0.0
	a.curse = 0.0
	a.risen = 0


func risen_rise(a: Dictionary, k: String, b: Dictionary, now: float) -> bool:
	if not a.get("risenArm", 0) or k == GameData.c("MAGE") or mages_in(a) <= 0:
		return false
	if not a.get("risenUsed", false):
		if mana_of(a) < mc(AUTO_MANA):
			return false
		spend_mana(a, AUTO_MANA)
		a.risenUsed = true
		a.risenLeft = a.risenArm
		toast("%s: the fallen rise again (%d)." % [a.name, a.risenArm])
	if a.risenLeft <= 0:
		return false
	a.risenLeft -= 1
	a.ghouls = a.get("ghouls", 0) + 1
	if a.owner == ME:
		sfx("mg_risen", a.prov)
	if a.risenLeft <= 0:
		a.risenArm = 0
	return true


func ghoul_fall(a: Dictionary, k: String) -> void:
	if not a.get("ghouls", 0) or k == GameData.c("MAGE"):
		return
	var n: int = troop_count(a) - a.troops.get(GameData.c("MAGE"), 0)
	if n > 0 and battle_rand.call() < float(a.ghouls) / n:
		a.ghouls -= 1


# --- retreat (game.js retreat / retreatLoss / retreatTo, gpc.js retreatHome) ---

func retreat_lock_left(a: Dictionary) -> float:
	return maxf(0.0, RETREAT_LOCK - (t - a.battle.t0)) if a.get("battle") != null else 0.0


func retreat_loss(a: Dictionary) -> int:
	var b = a.get("battle")
	if b == null:
		return 0
	var enemy := raw_strength(units.filter(func(v): return v.kind == "army" and is_same(v.get("battle"), b) and v.owner != a.owner and not v.get("retreating", false)))
	var mine := raw_strength([a])
	return mini(troop_count(a), int(JS.round_js(troop_count(a) * RETREAT_LOSS * enemy / maxf(1, enemy + mine))))


func retreat_to(a: Dictionary) -> int:
	var nb := []
	for n in path_nbr(a, a.prov):
		if can_enter(a, n.q, n.q) and hostiles_in(n.q, a.owner).is_empty():
			nb.append(n.q)
	if nb.is_empty():
		return -1
	if a.has("lastProv") and nb.has(a.lastProv):
		return a.lastProv
	nb.sort_custom(func(x, y): return int(owned(x)) > int(owned(y)))
	return nb[0]


func retreat_home(a: Dictionary):
	var start: int = a.prov
	var prev := {start: null}
	var dist := {start: 0}
	var q := [start]
	var h := 0
	while h < q.size():
		var x: int = q[h]
		h += 1
		for n in path_nbr(a, x):
			var y: int = n.q
			if prev.has(y) or not can_enter(a, y, y):
				continue
			if x == start and not hostiles_in(y, a.owner).is_empty():
				continue
			prev[y] = {"a": x, "m": n.m}
			dist[y] = dist[x] + 1
			q.append(y)
	dist.erase(start)
	if dist.is_empty():
		return null
	var to := -1
	if capital >= 0 and dist.has(capital):
		to = capital
	else:
		var dc := hops_from(capital)
		var bk = null
		for p in dist:
			var k0: int = dc.get(p, 0)
			if bk == null or k0 < bk[0] or (k0 == bk[0] and dist[p] > bk[1]):
				bk = [k0, dist[p]]
				to = p
	var hops := []
	var c := to
	while c != start:
		var pr: Dictionary = prev[c]
		hops.push_front({"to": c, "m": pr.m})
		c = pr.a
	return {"to": to, "hops": hops}


func hops_from(p: int) -> Dictionary:
	var d := {p: 0}
	var q := [p]
	var h := 0
	while h < q.size():
		var x: int = q[h]
		h += 1
		for y in all_nbr[x]:
			if not d.has(y):
				d[y] = d[x] + 1
				q.append(y)
	return d


## Pull an army out of its battle: it loses soldiers on the way and walks home. web: game.js retreat(a)
func retreat(a: Dictionary) -> void:
	if a.get("battle") == null:
		return
	if nations.has(a.owner) and retreat_lock_left(a) <= 0:
		Ai.note_defeat(self, a, a.battle)   # v100: what beat it decides the counters it trains
	if retreat_lock_left(a) > 0:
		toast("%s can’t pull out yet: the lines are locked for %d s more." % [a.name, ceili(retreat_lock_left(a))], true)
		return
	var dest := retreat_to(a)
	if dest < 0:
		toast("%s is surrounded and can’t retreat." % a.name, true)
		return
	var n := retreat_loss(a)
	for i in n:
		var kinds: Array = a.troops.keys().filter(func(k): return a.troops[k] > 0)
		var k: String = kinds[int(floor(battle_rand.call() * kinds.size()))]
		a.troops[k] -= 1
		if not a.troops[k]:
			a.troops.erase(k)
		fx.append({"kind": "fall", "prov": a.prov, "owner": a.owner, "unit": k, "t0": t, "r": fx_rand()})
	var b: Dictionary = a.battle
	b.lost[a.owner] = b.lost.get(a.owner, 0) + n
	if a.owner == ME:
		b.retreatedMe = true
	if troop_count(a) <= 0:
		war_wipe(b, a)
		remove_army(a)
		toast("%s was cut down while retreating." % a.name, true)
		return
	a.retreating = true
	a.battle = null
	var home = retreat_home(a)
	if home != null:
		if a.get("cast") != null:
			cancel_cast(a)
		a.surveyQueue = []
		walk_hops(a, home.hops, home.to)
		a.retreatHome = true
	else:
		order(a, dest, true)
	toast("%s retreats, losing %d soldier%s." % [a.name, n, "" if n == 1 else "s"])
	compute_income()


# web: v102.js meetHeadOn(): two hostile armies walking into each other's province meet at the border
func meet_head_on() -> void:
	var movers := units.filter(func(a): return a.kind == "army" and a.moving and a.get("battle") == null and not a.get("retreating", false) and not a.get("exiting", false) and troop_count(a) > 0)
	for x in movers.size():
		for y in range(x + 1, movers.size()):
			var A: Dictionary = movers[x]
			var B: Dictionary = movers[y]
			if A.prov == B.prov or not hostile(A.owner, B.owner) or not all_nbr[A.prov].has(B.prov):
				continue
			if JS.hypot(A.x - B.x, A.y - B.y) > MEET_DIST:
				continue
			var mover = A if _next_enter(A) == B.prov else B if _next_enter(B) == A.prov else null
			if mover == null:
				continue
			var other: Dictionary = B if is_same(mover, A) else A
			mover.lastProv = mover.prov
			mover.prov = other.prov
			mover.path = []
			mover.moving = false


static func _next_enter(u: Dictionary):
	for w in u.path:
		if w.has("enter"):
			return w.enter
	return null


# ---------------------------------------------------------------------------------------------------------------
# Bandit Gangs and monsters (web: v78.js spawnLairs / spawnMonster / stepPatrols / patrolPoint, content.js spawnBandit /
# banditFlee). Bandit waves (v96) never come to the Practice island.

const LAIR_CHANCE := 1.0 / 7


func spawn_lairs(skip: Dictionary) -> void:
	var r := Mulberry32.from_string(str(world.seed) + ":lairs")
	monster_count = 0
	bandit_count = 0
	var near := {}
	for p in buildings:
		if buildings[p].stage == 2:
			near[p] = true
			for q in all_nbr[p]:
				near[q] = true
	var MOT: Dictionary = GameData.c("MONSTER_OF_TERRAIN")
	for i in world.provinces.size():
		var roll := r.next()
		var coin := r.next()
		var size := r.next()
		if roll >= LAIR_CHANCE or near.has(i) or skip.has(i) or buildings.has(i) or units.any(func(u): return u.prov == i):
			continue
		var ter: String = world.provinces[i].terrain
		var kind = MOT.get(ter) if ter != "grassland" and coin < 0.5 else null
		if kind == null:
			spawn_bandit(i)
			continue
		var M: Dictionary = GameData.c("MONSTERS")[kind]
		spawn_monster(i, kind, M.sizes[int(floor(size * M.sizes.size()))])


func spawn_bandit(p: int) -> Dictionary:
	var names: Array = GameData.c("GANG_NAMES")
	var n := bandit_count
	bandit_count += 1
	var a := mk_unit(next_id, "army", names[n % names.size()] + (" %d" % (n / names.size() + 1) if n >= names.size() else ""), p, 0)
	next_id += 1
	a.owner = RAIDERS
	a.troops = BANDIT.troops.duplicate()
	a.bandit = true
	a.seen = false
	a.arrived = -100.0
	a.slot = free_slot(p, a)
	var xy := slot_pos(p, a.slot)
	a.x = xy[0]
	a.y = xy[1]
	a.th = 0.0
	units.append(a)
	return a


# web: v96.js stepBanditWaves: from 30 minutes on, a bigger gang turns up in an unclaimed province every 3 minutes
const BANDIT_WAVE := {"start": 1800.0, "every": 180.0, "power": 1000, "grow": 300, "cap": 50}
const WAVE_NAMES := ["Marauders", "Brigands", "Reavers", "Cutthroats", "Outlaws", "Raiders", "Freebooters", "Highwaymen"]
var bandit_next := -1.0
var bandit_waves := 0

func step_bandit_waves(now: float) -> void:
	if world.get("mode", "practice") == "practice":   # web: v96.js (every full map, whatever its shape)
		return
	if bandit_next < 0:
		bandit_next = BANDIT_WAVE.start
	if now < bandit_next:
		return
	var n := bandit_waves
	bandit_waves = n + 1
	bandit_next += BANDIT_WAVE.every
	var skip := uq_skip()
	var free := []
	for i in world.provinces.size():
		if buildings.has(i) or skip.has(i) or units.any(func(u): return u.prov == i and u.kind == "army"):
			continue
		if G.provs[i].has("inner") and not G.provs[i].inner.is_empty():
			free.append(i)
	if free.is_empty():
		return
	var p: int = free[int(floor(js_rand.call() * free.size()))]
	var power: int = BANDIT_WAVE.power + BANDIT_WAVE.grow * n
	var a := spawn_bandit(p)
	var R := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	var k := n / WAVE_NAMES.size() + 1
	a.name = "The " + WAVE_NAMES[n % WAVE_NAMES.size()] + ((" " + (R[k] if k < R.size() else str(k))) if n >= WAVE_NAMES.size() else "")
	var fp := maxf(1.0, JS.round_js(raw_strength([{"owner": RAIDERS, "troops": {"d-sword": 1}, "kind": "army"}]) * 10))
	a.troops = {"d-sword": mini(BANDIT_WAVE.cap, maxi(2, ceili(power / fp)))}
	a.wave = n + 1


func spawn_monster(p: int, kind: String, n: int) -> Dictionary:
	var M: Dictionary = GameData.c("MONSTERS")[kind]
	var c := monster_count
	monster_count += 1
	var a := mk_unit(next_id, "army", prov_name(p) + " " + M.names[c % M.names.size()], p, 0)
	next_id += 1
	a.owner = RAIDERS
	a.troops = {M.troop: n if n else M.sizes[0]}
	a.bandit = true
	a.monster = kind
	a.seen = false
	a.arrived = -100.0
	a.slot = free_slot(p, a)
	var xy := slot_pos(p, a.slot)
	a.x = xy[0]
	a.y = xy[1]
	a.th = 0.0
	units.append(a)
	return a


func patrol_point(p: int) -> Array:
	var P: Dictionary = G.provs[p]
	var q: Array = P.inner
	var i := int(floor(battle_rand.call() * q.size()))
	var j := (i + 1) % q.size()
	var f: float = battle_rand.call()
	var ex: float = q[i][0] + (q[j][0] - q[i][0]) * f
	var ey: float = q[i][1] + (q[j][1] - q[i][1]) * f
	var pull: float = 0.14 + battle_rand.call() * 0.14
	return Geo.clamp_into(P, ex + (P.ic[0] - ex) * pull, ey + (P.ic[1] - ey) * pull)


func step_patrols(now: float, dt: float) -> void:
	var at := armies_by_prov()
	for u in units:
		if not u.get("bandit", false) or u.kind != "army" or troop_count(u) <= 0:
			continue
		if u.get("battle") != null or u.moving or at.get(u.prov, []).any(func(v): return hostile(v.owner, u.owner) and not v.get("retreating", false)):
			u.patrolling = false
			u.pt = null
			continue
		if u.get("pt") == null:
			if u.get("ptWait", 0.0) > now:
				continue
			u.pt = patrol_point(u.prov)
		var dx: float = u.pt[0] - u.x
		var dy: float = u.pt[1] - u.y
		var d := JS.hypot(dx, dy)
		var sp := SPEED * unit_speed(u) * 0.45 * dt
		if d > 0.5:
			u.th = facing(dx, dy)
		if d <= sp:
			u.x = u.pt[0]
			u.y = u.pt[1]
			u.pt = null
			u.patrolling = false
			u.ptWait = now + 2 + battle_rand.call() * 6
			u.th = 0.0
		else:
			u.x += dx / d * sp
			u.y += dy / d * sp
			u.patrolling = true


# web: content.js banditFlee(u): a Wayfinder stepping into a gang's province sees them and runs back
func bandit_flee(u: Dictionary) -> bool:
	var p: int = u.prov
	if not bandits_in(p) or not u.has("lastProv"):
		return false
	for v in units:
		if v.get("bandit", false) and v.prov == p:
			v.seen = true
	wf[p] = true
	var back: int = u.lastProv
	u.path = []
	u.moving = false
	u.scouting = null
	u.survey = null
	u.surveyQueue = []
	u.pendingSurvey = -1
	u.autoWalk = null
	u.fleeing = false
	if not order(u, back, true):
		u.prov = back
		var xy := slot_pos(back, free_slot(back, u))
		u.x = xy[0]
		u.y = xy[1]
	else:
		u.fleeing = true
	toast("%s ran into a Bandit Gang and is scurrying back, unharmed. Wayfinders can't go there until the gang is gone." % u.name, true)
	sfx("wn_enemy")
	return true


# web: govtech.js stepScouts: a Wayfinder or Mason who meets enemy soldiers runs back the way he came; marked for 15 s
# after, a second meeting gives a friendly army 5 s to reach him before he is caught (sneaking comes with Stealth)
const SCOUT_MARK := 15.0
const SCOUT_RESCUE := 5.0

# --- arrowslits (web: govtech.js ARROW, arrowDmg, stepArrows): a fort or capital with Arrowslits shoots the hostile
# armies standing in its province, every 10 s, as long as no battle is being fought there

func arrow_dmg() -> float:
	var s = DSTATS.get("d-sword")
	return s.hp / maxf(0.05, (1 - s.red) * (1 - s.get("parry", 0.0))) + 0.01 if s != null else 30.0


func step_arrows(now: float) -> void:
	fx = fx.filter(func(f): return now - f.t0 < 1.4)
	spell_fx = spell_fx.filter(func(f): return now - f.t0 < SPELL_FX_TIME.get(f.kind, 2.0) + 0.1)
	for p in buildings.keys():
		var b: Dictionary = buildings[p]
		if b.stage < 1 or not is_nation(b.owner) or not tech_of(b.owner, "arrowslits") or occ.has(p) or battles.any(func(x): return x.prov == p):
			arrow_at.erase(p)
			continue
		var foes := units.filter(func(v): return v.kind == "army" and hostile(v.owner, b.owner) and v.prov == p and not v.moving and not v.get("retreating", false) and v.get("battle") == null and troop_count(v) > 0)
		if foes.is_empty():
			arrow_at.erase(p)
			continue
		if not arrow_at.has(p):
			arrow_at[p] = now + 10.0
			if visible.has(p) and (b.owner == ME or foes.any(func(a): return a.owner == ME)):
				toast("The %s at %s looses arrows at the invaders!" % ["capital" if b.stage == 2 else "fort", prov_name(p)])
			continue
		if now < arrow_at[p]:
			continue
		arrow_at[p] = now + 10.0
		apply_damage({"prov": p, "lost": {}}, foes, arrow_dmg(), now)
		var c: Array = G.provs[p].ic
		var top := [c[0], c[1] - (110 if b.stage == 2 else 75)]
		for a in foes:
			for k in 3:
				fx.append({"kind": "arrow", "prov": p, "owner": a.owner, "x0": top[0] + (k - 1) * 8, "y0": top[1], "x1": a.x + (k - 1) * 6, "y1": a.y - 8, "t0": now + k * 0.08})
		for a in foes:
			if troop_count(a) <= 0:
				remove_army(a)
				if a.owner == ME or b.owner == ME:
					toast("%s was shot down by the arrowslits." % a.name)


# web: gpc.js SPELL_FX_TIME, spellFx: the moment a Shockwave or Earthquake strikes, for the view
const SPELL_FX_TIME := {"fireball": 2.2, "shock": 1.8, "quake": 3.0}

func add_spell_fx(kind: String, c: Dictionary, q: int, edge = null) -> void:
	var to = null
	if edge != null:
		var a: Array = world.vertices[edge.v[0]]
		var b: Array = world.vertices[edge.v[1]]
		to = [(a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0]
	spell_fx.append({"kind": kind, "t0": t, "prov": c.prov, "to": q, "from": [c.x, c.y - 40], "at": to, "seed": fx_rand() * 100})
	if kind != "quake" and (c.owner == ME or visible.has(c.prov)):
		sfx("war_declare" if kind == "fireball" else "mg_arcane", c.prov)


func step_scouts(now: float) -> void:
	var at := armies_by_prov()
	for u in units.duplicate():
		if u.kind != WAYFINDER and u.kind != MASON:
			continue
		use_seat(u.owner if seats.has(u.owner) else HOST)
		var mine: bool = u.owner == ME
		if mine and u.get("stealth", false) and not has_tech("stealth"):
			u.stealth = false
		if u.get("stealth", false):
			continue
		if u.get("warFlee", false) and not u.get("fleeing", false) and not u.moving:
			u.warFlee = false
			u.markUntil = now + SCOUT_MARK
		var foe = null
		var here: Array = at.get(u.prov, [])
		for v in here:
			if (not v.get("bandit", false) or u.kind == MASON) and hostile(v.owner, u.owner) and not v.get("retreating", false):
				foe = v
				break
		if foe != null and foe.get("bandit", false) and mine:
			foe.seen = true
		var guard: bool = foe != null and here.any(func(v): return v.owner == u.owner)
		if foe == null or guard:
			if u.get("doomAt", 0.0):
				u.doomAt = 0.0
				if mine:
					toast("%s is safe: your army reached him." % u.name if guard else "%s got away." % u.name)
			continue
		if u.get("fleeing", false):
			continue
		if u.get("doomAt", 0.0):
			if now < u.doomAt:
				continue
			u._gone = true
			if visible.has(u.prov):
				fx.append({"kind": "fall", "prov": u.prov, "owner": u.owner, "unit": u.kind, "t0": now, "r": 0.5})
			Quests.unit_lost(self, u)   # (what he carried drops where he fell)
			units = units.filter(func(v): return not is_same(v, u))
			if u.build != null:
				cancel_build(u)
			if mine:
				compute_income()
				toast("%s was caught by %s and killed." % [u.name, foe.name], true)
			continue
		var back = u.get("lastProv")
		if now < u.get("markUntil", 0.0) or back == null or back == u.prov:
			u.doomAt = now + SCOUT_RESCUE
			u.path = []
			u.moving = false
			if u.build != null:
				cancel_build(u)
			u.pending = null
			u.aiJob = null
			if mine:
				toast("%s is cornered by %s at %s! Get an army there within %d seconds to save him." % [u.name, foe.name, prov_name(u.prov), SCOUT_RESCUE], true)
				sfx("wn_enemy")
			continue
		u.path = []
		u.moving = false
		u.scouting = null
		u.survey = null
		u.aiSurvey = null
		u.erase("aiTarget")
		u.surveyQueue = []
		u.pendingSurvey = -1
		u.autoWalk = null
		if u.build != null:
			cancel_build(u)
		u.pending = null
		u.aiJob = null
		u.fleeing = false
		if not order(u, back, true):
			u.doomAt = now + SCOUT_RESCUE
			if mine:
				toast("%s is cornered by %s at %s! Get an army there within %d seconds to save him." % [u.name, foe.name, prov_name(u.prov), SCOUT_RESCUE], true)
				sfx("wn_enemy")
			continue
		u.fleeing = true
		u.warFlee = true
		if mine:
			toast("%s spotted %s at %s and is running back to %s." % [u.name, foe.name, prov_name(u.prov), prov_name(back)], true)
			sfx("wn_enemy")


# =================================================================================================================
# Army Training Orders (web: v106.js 50–54): soldiers ordered at once, trained by every Barracks, gathered in one province
var train_orders: Array:
	get: return cur["train_orders"]
	set(v): cur["train_orders"] = v
var train_order_seq := 1

func to_buildings() -> Array:
	var out := []
	for p in extras:
		if not owned(p) or occ.has(p):
			continue
		if extras[p].any(func(e): return e.type == "barracks"):
			out.append({"key": "barracks:%d" % p, "p": p, "kinds": trainable("barracks", p)})
	return out


func to_kinds() -> Array:
	var out := []
	for b in to_buildings():
		for k in b.kinds:
			if military.has(k) and not out.has(k):
				out.append(k)
	return out


func to_cost(draft: Dictionary) -> Dictionary:
	var c := {"gold": 0, "wood": 0, "food": 0}
	for k in draft:
		var u = unit_defs.get(k)
		if u != null:
			for r in u.cost:
				c[r] += u.cost[r] * draft[k]
	for r in c.keys():
		if not c[r]:
			c.erase(r)
	return c


func to_why(draft: Dictionary, rally_p: int):
	var n := 0
	for k in draft:
		n += draft[k]
	if not n:
		return "Add some soldiers to the order"
	if to_buildings().is_empty():
		return "You need a Barracks"
	if rally_p < 0 or not owned(rally_p):
		return "Pick a province to gather in"
	var kinds := to_kinds()
	for k in draft:
		if draft[k] and not kinds.has(k):
			return "None of your buildings can train %s" % unit_defs[k].name
	return lack_text(to_cost(draft))


## Place an order (web: purchaseOrder): paid at once; each soldier goes to the least busy building that trains it,
## the kinds fewest buildings train first. Returns the order's id, or -1.
func purchase_order(draft: Dictionary, rally_p: int) -> int:
	var why = to_why(draft, rally_p)
	if why != null:
		toast("Can't place the order: %s." % (why[0].to_lower() + why.substr(1)), true)
		return -1
	var c := to_cost(draft)
	for k in c:
		stock[k] -= c[k]
	var id := train_order_seq
	train_order_seq += 1
	var P: Dictionary = G.provs[rally_p]
	var rp := {"prov": rally_p, "x": P.ic[0] + 10, "y": P.ic[1] + 46}
	var blds := to_buildings()
	var load := {}
	for b in blds:
		load[b.key] = queues.get(b.key, []).size()
	var kinds := draft.keys().filter(func(k): return draft[k] > 0)
	var nb := func(k): return blds.filter(func(x): return x.kinds.has(k)).size()
	kinds = JS.stable_sort(kinds, func(a, b): return nb.call(a) - nb.call(b))
	var n := 0
	for k in kinds:
		for i in draft[k]:
			var can := blds.filter(func(b): return b.kinds.has(k))
			if can.is_empty():
				continue
			can = JS.stable_sort(can, func(a, b): return load[a.key] - load[b.key])
			var B: Dictionary = can[0]
			load[B.key] += 1
			if not queues.has(B.key):
				queues[B.key] = []
			queues[B.key].append({"kind": k, "paid": unit_defs[k].cost.duplicate(), "t0": null, "order": id, "rally": rp.duplicate()})
			n += 1
	train_orders.append({"id": id, "rally": rp, "total": n, "mix": draft.duplicate(), "t": t, "done": false})
	sfx("pr_trained")
	toast("Army Training Order %d placed: %d soldiers, gathering in %s (−%s)." % [id, n, prov_name(rally_p), cost_text(c)])
	return id


# the order's armies only join each other at its rally point (web: v106.js rallyArrivals wrapper)
func order_arrivals() -> void:
	for a in units.duplicate():
		if a.get("_gone", false) or a.kind != "army" or a.owner != ME or a.get("trainOrder") == null or a.get("rallyTo") == null \
				or a.moving or a.get("battle") != null:
			continue
		if a.prov != a.rallyTo:
			a.rallyTo = null
			continue
		a.rallyTo = null
		var host = null
		for v in units:
			if not is_same(v, a) and v.kind == "army" and v.owner == ME and v.get("trainOrder") == a.trainOrder and v.prov == a.prov \
					and not v.moving and v.get("battle") == null and v.get("rallyTo") == null:
				host = v
				break
		if host == null:
			continue
		for k in a.troops:
			host.troops[k] = host.troops.get(k, 0) + a.troops[k]
		host.grew = t
		a._gone = true
		units = units.filter(func(v): return not is_same(v, a))
		compute_income()


func order_queued(id: int) -> int:
	var n := 0
	for key in queues:
		for q in queues[key]:
			if q.get("order") == id:
				n += 1
	return n


func step_orders() -> void:
	for O in train_orders:
		if O.done:
			continue
		var armies := units.filter(func(a): return a.kind == "army" and a.owner == ME and a.get("trainOrder") == O.id)
		if order_queued(O.id) or armies.any(func(a): return a.moving or a.get("rallyTo") != null):
			continue
		O.done = true
		O.doneT = t
		var at := armies.filter(func(a): return a.prov == O.rally.prov)
		var n := 0
		for a in at:
			n += troop_count(a)
		for a in armies:
			a.trainOrder = null
		if n:
			sfx("wn_ally", -1, 0.5)
			toast("Army Training Order %d is complete: %s (%d soldiers) stands ready in %s." % [O.id, at[0].name, n, prov_name(O.rally.prov)])
	if train_orders.size() > 12:
		train_orders = train_orders.filter(func(O): return not O.done or t - O.doneT < 300)


func order_progress(O: Dictionary) -> Dictionary:
	var queued := order_queued(O.id)
	var there := 0
	for a in units:
		if a.kind == "army" and a.owner == ME and a.get("trainOrder") == O.id and a.prov == O.rally.prov and not a.moving:
			there += troop_count(a)
	return {"queued": queued, "made": O.total - queued, "there": there}


# =================================================================================================================
# retrofitting (web: features.js retroPlan / retrofitNow / retrofitArmies, gpc.js GPC14): an army re-equipped with
# another design of the same kind at a Barracks (cavalry: a Barracks with a Stable), 2 s a soldier, queued like training
const RETRO_TIME := 2.0

func barracks_ok(p: int, cav: bool) -> bool:
	if not extras.has(p) or not owned(p) or occ.has(p):
		return false
	var l: Array = extras[p]
	if cav and is_sw(nation_of(p)):   # web: gpc.js barracksOk (Swamplings retrofit Ogres at an Ogre Cave)
		return l.any(func(e): return e.type == "stable")
	return l.any(func(e): return e.type == "barracks") and (not cav or l.any(func(e): return e.type == "stable"))


func retro_cost(from: String, to: String) -> Dictionary:
	var a: Dictionary = unit_defs[from].get("cost", {})
	var b: Dictionary = unit_defs[to].get("cost", {})
	var c := {}
	for r in RES:
		var d: float = b.get(r, 0) - a.get(r, 0)
		if d > 0:
			c[r] = d
	return c


func retro_plan(a: Dictionary, to: String) -> Dictionary:
	var cav: bool = DSTATS[to].get("cav", false)
	var total := {}
	var n := 0
	for k in a.troops:
		var c: int = a.troops[k]
		if k == to or k == MAGE or not DSTATS.has(k) or DSTATS[k].get("cav", false) != cav or not c:
			continue
		n += c
		var rc := retro_cost(k, to)
		for r in rc:
			total[r] = total.get(r, 0) + rc[r] * c
	return {"n": n, "cost": total}


func retrofit_why(a):
	if a == null or a.kind != "army":
		return "No army selected"
	if a.get("battle") != null:
		return "Not during battle"
	if a.get("retro") != null:
		return "Waiting its turn to retrofit" if a.retro.t0 == null else "Retrofitting: %d s left" % ceili(a.retro.dur - (t - a.retro.t0))
	return null


func retrofit_now(a: Dictionary, to: String) -> int:
	var cav: bool = DSTATS[to].get("cav", false)
	var n := 0
	for k in a.troops.keys():
		if k == to or k == MAGE or not DSTATS.has(k) or DSTATS[k].get("cav", false) != cav:
			continue
		n += a.troops[k]
		a.troops[to] = a.troops.get(to, 0) + a.troops[k]
		a.troops.erase(k)
	compute_income()
	return n


func retro_site(a: Dictionary, to: String) -> int:
	var cav: bool = DSTATS[to].get("cav", false)
	if barracks_ok(a.prov, cav):
		return a.prov
	var best := -1
	var bd := INF
	for p in extras:
		if not barracks_ok(p, cav):
			continue
		var h = find_path(a, p)
		if h != null and h.size() < bd:
			bd = h.size()
			best = p
	return best


func retrofit_armies(armies: Array, to: String) -> void:
	var none := 0
	var sent := 0
	for a in armies:
		if not retro_plan(a, to).n:
			continue
		var dest := retro_site(a, to)
		if dest < 0:
			none += 1
			continue
		if a.get("retro") != null:
			cancel_retro(a, true)
		a.retroWant = {"to": to, "prov": dest}
		if a.prov == dest and not a.moving:
			begin_retro(a)
		elif order(a, dest, true):
			sent += 1
		else:
			a.retroWant = null
			none += 1
	if none:
		toast("No Barracks of yours can be reached to retrofit %s." % ("%d armies" % none if none > 1 else "that army"), true)
	if sent:
		toast("%s to the nearest Barracks to retrofit." % ("%d armies march" % sent if sent > 1 else "The army marches"))


func begin_retro(a: Dictionary) -> bool:
	var w = a.get("retroWant")
	a.retroWant = null
	if w == null:
		return false
	var plan := retro_plan(a, w.to)
	if not plan.n:
		return false
	var cav: bool = DSTATS[w.to].get("cav", false)
	if not barracks_ok(a.prov, cav):
		return false
	if lack_text(plan.cost) != null:
		toast("Retrofitting %s needs %s." % [a.name, cost_text(plan.cost)], true)
		return false
	for r in plan.cost:
		stock[r] -= plan.cost[r]
	var key := "barracks:%d" % a.prov
	if not queues.has(key):
		queues[key] = []
	var q := {"kind": w.to, "retro": true, "army": a.id, "n": plan.n, "dur": plan.n * RETRO_TIME, "paid": plan.cost, "t0": null, "prov": a.prov, "key": key}
	queues[key].append(q)
	a.retro = q
	toast("%s retrofits %d soldier%s to %s: %d s. Moving or fighting cancels it." % [a.name, plan.n, "s" if plan.n > 1 else "", unit_defs[w.to].name, int(plan.n * RETRO_TIME)])
	return true


func cancel_retro(a: Dictionary, quiet := false) -> void:
	var q = a.get("retro")
	if q == null:
		return
	a.retro = null
	var Q: Array = queues.get(q.key, [])
	var i := -1
	for j in Q.size():
		if is_same(Q[j], q):
			i = j
	if i < 0:
		return
	Q.remove_at(i)
	if i == 0 and not Q.is_empty():
		Q[0].t0 = null
	for r in q.paid:
		stock[r] += q.paid[r]
	if not quiet:
		toast("%s stopped retrofitting. Resources refunded." % a.name, true)


func finish_retro(q: Dictionary) -> void:
	for a in units:
		if a.id == q.army and is_same(a.get("retro"), q):
			a.retro = null
			var n := retrofit_now(a, q.kind)
			toast("%s: %d soldier%s retrofitted to %s." % [a.name, n, "" if n == 1 else "s", unit_defs[q.kind].name])
			sfx("bld_done", a.prov)
			return


func step_retrofits() -> void:
	for a in units:
		if a.kind != "army":
			continue
		var w = a.get("retroWant")
		if w != null:
			if a.get("battle") != null or a.get("exiting", false) or (a.moving and a.get("final") != w.prov):
				a.retroWant = null
			elif not a.moving:
				if a.prov == w.prov:
					begin_retro(a)
				else:
					a.retroWant = null
		if a.get("retro") == null:
			continue
		if not queues.get(a.retro.key, []).any(func(q): return is_same(q, a.retro)):
			a.retro = null
			continue
		if a.moving or a.get("battle") != null or a.prov != a.retro.prov:
			cancel_retro(a)
	# an army that is gone leaves its job behind: dropped with a refund
	for key in queues:
		var Q: Array = queues[key]
		for i in range(Q.size() - 1, -1, -1):
			var q: Dictionary = Q[i]
			if not q.get("retro", false):
				continue
			if units.any(func(v): return v.id == q.army and is_same(v.get("retro"), q)):
				continue
			Q.remove_at(i)
			if i == 0 and not Q.is_empty():
				Q[0].t0 = null
			for r in q.paid:
				stock[r] += q.paid[r]


# resting at a Barracks (web: gpc.js GPC15): 5 s for every wounded soldier, back to full health
const REST_TIME := 5.0

func step_rest(now: float) -> void:
	for a in units:
		if a.kind != "army":
			continue
		if a.moving or a.get("battle") != null or a.get("heal") != null or not (a.get("wounds", 0.0) > 0.01) or not barracks_ok_for(a):
			a.rest = null
			continue
		if a.get("rest") == null:
			a.rest = {"t0": now, "w0": a.wounds, "dur": REST_TIME * troop_count(a)}
		var f := minf(1.0, (now - a.rest.t0) / a.rest.dur)
		a.wounds = a.rest.w0 * (1 - f)
		if f >= 1:
			a.wounds = 0.0
			a.rest = null
			if a.owner == ME:
				toast("%s has rested: back to full health." % a.name)


func barracks_ok_for(a: Dictionary) -> bool:
	# web: barracksOk(p, o, false) checks the province's nation is the army's
	if not extras.has(a.prov) or occ.has(a.prov) or not buildings.has(a.prov) or buildings[a.prov].owner != a.owner:
		return false
	return extras[a.prov].any(func(e): return e.type == "barracks")


# =================================================================================================================
# set pieces (web: content.js SETPIECES / setupContent, gpc.js GPC07): one province in ten may hold a landmark that
# gives research while you hold it
const SETPIECE_CHANCE := 0.1
var SETPIECES: Dictionary = {
	"battlesite": {"name": "Ancient Battle Site", "tree": "mil", "pts": 1, "terrain": ["desert"], "need": "a Forge", "blurb": "Rusted blades and old bones half-buried in the sand."},
	"library": {"name": "Forgotten Library", "tree": "gov", "pts": 1, "terrain": ["swamp", "desert"], "need": null, "blurb": "Shelves of crumbling scrolls, still legible to a patient scholar."},
	"rift": {"name": "Closed Interdimensional Rift", "tree": "mag", "pts": 1, "terrain": ["swamp"], "need": "a Mage Tower", "blurb": "A seam in the air where another world once broke through."},
}
const SP_FOUND_TEXT := {
	"battlesite": "%s has found evidence of a massive battle dating back thousands of years in %s. Our own Forges could learn from this site.",
	"library": "%s has found the remains of a library forgotten to time in %s. Our scholars will rejoice.",
	"rift": "%s has found a strange rift of magical origin in %s. Our Mages could learn from the long dead spells of the Archmages of Ages past.",
}
var setpieces := {}
## a pop-up for the player: func(title: String, text: String, choices: Array[{id, label, why}], on_pick: Callable)
var on_dialog: Callable

func place_setpieces() -> void:
	setpieces = {}
	var r := Mulberry32.from_string(str(world.seed) + ":setpieces")
	for i in world.provinces.size():
		var roll := r.next()
		var pick := r.next()
		var ok := SETPIECES.keys().filter(func(k): return SETPIECES[k].terrain.has(world.provinces[i].terrain))
		if roll < SETPIECE_CHANCE and not ok.is_empty() and not (buildings.has(i) and buildings[i].stage == 2):
			setpieces[i] = ok[int(floor(pick * ok.size()))]


func setpiece_on(id: String) -> bool:
	var tr: String = SETPIECES[id].tree
	return tr == "gov" or extras_in_mine(tr).size() > 0


func extras_in_mine(tree: String) -> Array:
	var want := "forge" if tree == "mil" else "magetower"
	var out := []
	for p in extras:
		if owned(p):
			for e in extras[p]:
				if e.type == want:
					out.append(e)
	return out


func sp_known(p: int) -> bool:
	return sp_found.has(p) or owned(p)


## Why a set piece gives nothing right now (null: it is working)
func setpiece_why(p: int):
	if not setpieces.has(p):
		return null
	var D: Dictionary = SETPIECES[setpieces[p]]
	if not owned(p):
		return "hold the province"
	if occ.has(p):
		return "occupied"
	if not setpiece_on(setpieces[p]):
		return "needs " + D.need
	return null


func setpiece_found(p: int, u: Dictionary) -> void:
	var D: Dictionary = SETPIECES[setpieces[p]]
	var said: String = SP_FOUND_TEXT[setpieces[p]] % [u.name, prov_name(p)]
	var text := "%s\n\n%s While you hold this province it gives +%d %s research every 10 s%s." % [said, D.blurb, D.pts,
		{"gov": "Government", "mil": "Military", "mag": "Magic"}[D.tree], " (you also need %s)" % D.need if D.need != null else ""]
	sfx("wn_ally")
	if on_dialog.is_valid() and ME == view_seat:
		on_dialog.call("Discovery! %s at %s" % [D.name, prov_name(p)], text, [{"id": "ok", "label": "OK", "why": null}], Callable())
	else:
		toast("Discovery! %s at %s." % [D.name, prov_name(p)])


# =================================================================================================================
# lost bands of travelers (web: v78.js SMA01): fed, they join you as Footmen; an army can rob them instead
const TRAVELERS := {"foodEach": 20, "goldEach": 30, "foodCaught": 30, "sizes": [3, 4, 5]}
var travelers := []
var travelers_ask := true    # tests turn the question off
var trav_asking = null
var trav_paused := false

func place_travelers(skip: Dictionary) -> void:
	travelers = []
	var r := Mulberry32.from_string(str(world.seed) + ":travelers")
	var want := maxi(2, roundi(world.provinces.size() / 40.0))
	var near := {}
	for p in buildings:
		if buildings[p].stage == 2:
			near[p] = true
			for q in all_nbr[p]:
				near[q] = true
	var ok := []
	for i in world.provinces.size():
		if not near.has(i) and not skip.has(i) and not buildings.has(i) and not units.any(func(u): return u.prov == i):
			ok.append(i)
	for k in want:
		if ok.is_empty():
			break
		var p: int = ok.pop_at(int(floor(r.next() * ok.size())))
		var sizes: Array = TRAVELERS.sizes
		var n: int = sizes[int(floor(r.next() * sizes.size()))]
		var c: Array = G.provs[p].ic
		travelers.append({"id": k, "prov": p, "n": n, "x": c[0] - 60, "y": c[1] + 40, "tx": null, "ty": null, "wait": 2 + r.next() * 6, "asked": false, "dir": 1})


# A seeded draw for what only looks random (the travelers' amble): the same in every copy of the game, and saved,
# so multiplayer copies and loaded games stay in step (it was Godot's unseeded randf()).
var look_seed := 0

func look_rand() -> float:
	var m := Mulberry32.new(look_seed if look_seed else hash(str(world.seed)))
	var v := m.next()
	look_seed = m.a if m.a else 1
	return v


func step_travelers(dt: float) -> void:
	for B in travelers:
		# a slow amble about their province (looks only: the web game rolls Math.random here)
		if B.tx == null:
			B.wait -= dt
			if B.wait <= 0:
				var P: Dictionary = G.provs[B.prov]
				var q: Array = P.inner[int(look_rand() * P.inner.size())]
				var f := 0.35 + look_rand() * 0.3
				var at = Geo.clamp_into(P, P.ic[0] + (q[0] - P.ic[0]) * f, P.ic[1] + (q[1] - P.ic[1]) * f)
				B.tx = at[0]
				B.ty = at[1]
		else:
			var dx: float = B.tx - B.x
			var dy: float = B.ty - B.y
			var d := JS.hypot(dx, dy)
			var sp := 9.0 * 0.8 * dt
			if d <= sp:
				B.x = B.tx
				B.y = B.ty
				B.tx = null
				B.wait = 6 + look_rand() * 10
			else:
				B.x += dx / d * sp
				B.y += dy / d * sp
				B.dir = -1 if dx < 0 else 1
		# 0.19: any human nation may find them, not only the host: the first one to stand in their province is asked
		var here := -1
		for u in units:
			if seats.has(u.owner) and u.prov == B.prov and not u.moving:
				here = u.owner
				break
		if here < 0:
			B.asked = false
			continue
		if not B.asked and trav_asking == null and travelers_ask:
			B.asked = true
			in_seat(here, func(): ask_travelers(B))


func trav_army_here(B: Dictionary) -> bool:
	return units.any(func(u): return u.owner == ME and u.kind == "army" and u.prov == B.prov and troop_count(u) > 0 and u.get("battle") == null)


func ask_travelers(B: Dictionary) -> void:
	trav_asking = B
	if seats.size() > 1:   # multiplayer: only the nation they asked may answer
		B.by = ME
	if not paused:
		paused = true
		trav_paused = true
	var food: int = B.n * TRAVELERS.foodEach
	var gold: int = B.n * TRAVELERS.goldEach
	var choices := [
		{"id": "feed", "label": "Share %d food\n%d Footmen join you" % [food, B.n], "why": null if stock.food >= food else "Not enough food"},
		{"id": "rob", "label": "Rob them\n+%d gold" % gold, "why": null if trav_army_here(B) else "You need an army in this province"},
		{"id": "leave", "label": "Leave them be\nThey ask again next time", "why": null}]
	var text := "%d weary travelers have lost their way. They are hungry, and ask if you can spare them some food. Fed, they would gladly take up arms for you." % B.n
	if is_sw():   # web: v78.js (Swamplings capture travelers for food)
		choices[0] = {"id": "capture", "label": "Capture them\n+%d food" % (B.n * TRAVELERS.foodCaught), "why": null if trav_army_here(B) else "You need Berserkers in this province"}
		text = "%d weary travelers have lost their way. They eye your Swamplings fearfully and won’t take up arms for you, but your Berserkers could drag them off to the larder." % B.n
	elif is_wd():   # web: wood.js (Woodlings give directions in exchange for knowledge)
		var has := trav_units(B)
		var M: String = unit_defs[MAGE].name
		choices = [
			{"id": "know-gov", "label": "Your %s guides them\n+%d Government research" % [unit_defs[WAYFINDER].name, TRAV_KNOW], "why": null if has.scout else "Needs a %s here" % unit_defs[WAYFINDER].name},
			{"id": "know-mil", "label": "Your soldiers escort them\n+%d Military research" % TRAV_KNOW, "why": null if has.army else "Needs an army here"},
			{"id": "know-mag", "label": "Your %s leads them\n+%d Magic research" % [M, TRAV_KNOW], "why": null if has.druid else "Needs a %s here" % M},
			{"id": "leave", "label": "Leave them be\nThey ask again next time", "why": null}]
		text = "%d weary travelers have lost their way in the woods. Show them the path home, and they will gladly share what they know in return." % B.n
	sfx("wn_ally")
	if on_dialog.is_valid():
		if ME == view_seat:
			on_dialog.call("A lost band of travelers at %s" % prov_name(B.prov), text, choices, func(id): do("travelers_choose", [id]))
	else:
		travelers_choose("leave")


func travelers_choose(how: String) -> void:
	var B = trav_asking
	if B == null or B.get("by", ME) != ME:
		return
	if how == "feed":
		var food: int = B.n * TRAVELERS.foodEach
		if stock.food < food:
			toast("Not enough food to share.", true)
			return
		stock.food -= food
		var a = null
		for u in units:
			if u.owner == ME and u.kind == "army" and u.prov == B.prov and u.get("battle") == null and not u.moving:
				a = u
				break
		if a != null:
			a.troops["d-sword"] = a.troops.get("d-sword", 0) + B.n
			a.grew = t
		else:
			a = new_army(B.prov, {"d-sword": B.n})
		travelers.erase(B)
		compute_income()
		toast("The travelers eat their fill and swear to serve you: %d Footmen join %s." % [B.n, a.name])
	elif how == "capture":
		if not trav_army_here(B):
			toast("You need Berserkers in this province to capture them.", true)
			return
		var fc: int = B.n * TRAVELERS.foodCaught
		stock.food += fc
		clamp_stock()
		travelers.erase(B)
		toast("Your Berserkers round up the travelers and haul them off to the larder: +%d food." % fc)
	elif how.begins_with("know-"):
		var tree := how.substr(5)
		var has := trav_units(B)
		if not (has.scout if tree == "gov" else has.army if tree == "mil" else has.druid):
			toast("Nobody of yours here can do that.", true)
			return
		add_research(tree, TRAV_KNOW)
		travelers.erase(B)
		toast("%s the travelers onto the path home. In thanks they share what they know: +%d %s research." % ["Your %s shows" % unit_defs[WAYFINDER].name if tree == "gov" else "Your soldiers escort" if tree == "mil" else "Your %s leads" % unit_defs[MAGE].name, TRAV_KNOW, TECH_TREES[tree].name])
	elif how == "rob":
		if not trav_army_here(B):
			toast("You need an army in this province to rob them.", true)
			return
		var gold: int = B.n * TRAVELERS.goldEach
		stock.gold += gold
		travelers.erase(B)
		toast("Your soldiers rob the travelers of %d gold. They flee into the wilds." % gold)
	trav_asking = null
	if trav_paused and paused:
		paused = false
	trav_paused = false


# province names (web: war.js provName; v95's unique provinces come with the full-size world)
const NAME_A := ["Ash", "Bram", "Cald", "Dun", "Elm", "Fen", "Gal", "Hol", "Iver", "Kel", "Lor", "Mar", "Nor", "Oak", "Pell", "Quen", "Ros", "Stan", "Thorn", "Ul", "Vel", "Wyn", "Yar", "Brin", "Cor", "Del", "Gorm", "Hart", "Lin", "Mor"]
const NAME_B := {"grassland": ["dale", "field", "ford", "stead", "meadow", "wold", "hill", "ton"], "forest": ["wood", "holt", "shaw", "glen", "hollow", "grove", "thicket", "wald"], "desert": ["sand", "dune", "reach", "mesa", "rock", "waste", "flats", "spire"], "swamp": ["marsh", "mire", "fen", "bog", "moss", "mere", "sump", "wash"]}
var prov_names := []
var prov_rename := {}

func prov_name(p: int) -> String:
	if p < 0:
		return "?"
	if prov_names.is_empty():
		var r := Mulberry32.from_string(str(world.seed) + ":names")
		var used := {}
		for P in world.provinces:
			var B: Array = NAME_B.get(P.terrain, NAME_B.grassland)
			var n := ""
			var k := 0
			while true:
				n = NAME_A[int(floor(r.next() * NAME_A.size()))] + B[int(floor(r.next() * B.size()))]
				k += 1
				if not used.has(n) or k >= 30:
					break
			used[n] = true
			prov_names.append(n)
		var U = uq()
		if U != null:
			for k in UQ_NAME:
				if U[k] >= 0:
					prov_names[U[k]] = UQ_NAME[k]
	return prov_rename.get(p, prov_names[p])


# web: gpc.js sendToRest / restSite: march a wounded army to the nearest of your Barracks
func rest_site(a: Dictionary) -> int:
	if barracks_ok_for(a):
		return a.prov
	var best := -1
	var bd := INF
	for p in extras:
		if not barracks_ok(p, false):
			continue
		var h = find_path(a, p)
		if h != null and h.size() < bd:
			bd = h.size()
			best = p
	return best


func send_to_rest(a: Dictionary) -> void:
	if not (a.get("wounds", 0.0) > 0.01):
		toast("%s isn’t hurt." % a.name)
		return
	var p := rest_site(a)
	if p < 0:
		toast("None of your Barracks can be reached.", true)
	elif p == a.prov and not a.moving:
		toast("%s is resting at the Barracks." % a.name)
	elif order(a, p, true):
		toast("%s marches to the Barracks at %s to rest." % [a.name, prov_name(p)])



# =================================================================================================================
# v95: the unique provinces of a full-size world (web: v95.js uq, uqSkip, uniqueBan, spawnBosses, bossBlock)
const UQ_NAME := {"death": "Death Mountain", "oasis": "Desert Oasis", "heart": "Heart of the Forest"}

func uq():
	return world.get("unique") if world.get("mode", "practice") != "practice" else null


func uq_kind(p: int):
	var U = uq()
	if U == null:
		return null
	return "death" if p == U.death else "oasis" if p == U.oasis else "heart" if p == U.heart else null


func is_death_mtn(p: int) -> bool:
	var U = uq()
	return U != null and U.death >= 0 and p == U.death


func uq_guards() -> Array:
	var U = uq()
	if U == null:
		return []
	return [U.deathGuard, U.oasisGuard, U.heartGuard].filter(func(x): return x >= 0)


## the unique provinces, the bosses' provinces and their neighbors: nothing else is placed there
func uq_skip() -> Dictionary:
	var U = uq()
	var out := {}
	if U == null:
		return out
	for k in ["death", "oasis", "heart"]:
		if U[k] >= 0:
			out[U[k]] = true
	for g in uq_guards():
		out[g] = true
		for q in world.provinces[g].nbr:
			out[q] = true
	return out


func unique_ban(i: int) -> bool:
	return uq_skip().has(i)


func boss_in(p: int):
	for v in units:
		if v.get("boss") != null and v.prov == p and troop_count(v) > 0:
			return v
	return null


## nobody enters Death Mountain; computer nations only walk into a boss's province on purpose
func boss_block(u: Dictionary, q: int, tgt: int) -> bool:
	return is_death_mtn(q) or (nations.has(u.owner) and q != tgt and boss_in(q) != null)


func spawn_bosses() -> void:
	var U = uq()
	if U == null:
		return
	var B: Dictionary = GameData.c("BOSSES")
	for site in ["death", "oasis", "heart"]:
		var g: int = U[("death" if site == "death" else site) + "Guard"]
		if g < 0 or U[site] < 0:
			continue
		for p in [g, U[site]]:
			units = units.filter(func(v): return not (v.get("bandit", false) and v.prov == p))
			setpieces.erase(p)
			finds.erase(p)
		travelers = travelers.filter(func(T): return T.prov != g and T.prov != U[site])
		var r := Mulberry32.from_string(str(world.seed) + ":boss:" + site)
		var id: String = GameData.c("BOSS_SITES")[site][int(floor(r.next() * 3))]
		var a := spawn_monster(g, "boss-" + id, 1)
		a.name = B[id].short + (", " + B[id].sub if B[id].get("sub") != null else "")
		a.boss = id
		a.guards = U[site]


# =================================================================================================================
# boss fights and artifacts (web: v95.js applyDamage wrapper, bossFortune, banditSlain, grantArtifact; v105.js opinion)
const BOSS_K := 0.045
const ARTIFACTS := {
	"redskull": {"name": "Red Dragon Skull", "desc": "all your units are 25% faster."},
	"blueskull": {"name": "Blue Dragon Skull", "desc": "all your soldiers have 15% more health."},
	"goldskull": {"name": "Gold Dragon Skull", "desc": "+50 gold every payout, and 2000 more gold storage."},
	"crown": {"name": "King’s Crown", "desc": "your upkeep is 20% lower."},
	"flame": {"name": "Essence of Flame", "desc": "every weapon you carry has +10 attack."},
	"eye": {"name": "Lidless Eye", "desc": "you always see every army on the map and the province it stands in."},
	"stump": {"name": "Enchanted Stump", "desc": "+50 wood every payout."},
	"grips": {"name": "Grips of the Beast", "desc": "maces of every level (clubs, maces, morning stars, war hammers) deal 15 more damage."},
	"slippers": {"name": "Winged Slippers", "desc": "your armies can fly over any border into a neighboring province (an ability on the army’s card, 1-minute cooldown for your whole nation)."}}
var artifacts := {}   # owner -> [artifact ids]

func has_art(o: int, id: String) -> bool:
	var A = artifacts.get(o)
	return A != null and A.has(id)


func grant_artifact(o: int, id: String, boss: Dictionary) -> void:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		in_seat(o, func(): grant_artifact(o, id, boss))
		return
	if not artifacts.has(o):
		artifacts[o] = []
	if artifacts[o].has(id):
		return
	artifacts[o].append(id)
	var B: Dictionary = GameData.c("BOSSES")[boss.boss]
	if o == ME:
		compute_income()
		clamp_stock()
		compute_fog()
		toast("Artifact! %s has fallen. You claim the %s: %s" % [B.name.capitalize() if B.name.begins_with("the ") else B.name, ARTIFACTS[id].name, ARTIFACTS[id].desc])
		sfx("war_fort_win")
		if on_dialog.is_valid() and ME == view_seat:
			on_dialog.call("Artifact: " + ARTIFACTS[id].name, "%s has fallen. You claim the %s: %s" % [B.name.substr(4).capitalize() if B.name.begins_with("the ") else B.name, ARTIFACTS[id].name, ARTIFACTS[id].desc], [{"id": "ok", "label": "Splendid", "why": null}], func(_x): pass)
	else:
		if nations.has(o):
			nations[o].income = Ai.income(self, nations[o])
		if knows(o):
			toast("The %s slew %s and claimed the %s." % [player_info(o).name, B.name, ARTIFACTS[id].name])


func boss_slain(a: Dictionary, b: Dictionary) -> void:
	var owner := ME if b.start.has(ME) else first_nation_in(b.start)
	if not owner:
		return
	grant_artifact(owner, GameData.c("BOSSES")[a.boss].art, a)
	var D := dipl_state()
	D.boss[owner] = D.boss.get(owner, 0) + 1
	if owner == ME:
		toast("Word of your victory spreads: every nation thinks better of you (+%d opinion, for good)." % DIPL.boss)


func boss_fortune(b: Dictionary) -> float:
	if not b.has("fortune"):
		var sm := 0.0
		for i in 6:
			sm += battle_rand.call()
		b.fortune = maxf(0.75, minf(1.25, 1 + (sm - 3) * 0.141))
	return b.fortune


## Damage in a boss fight, or -1 when no boss stands in the battle: decided by power, not by rows and weapons.
func boss_damage(b: Dictionary, armies: Array, dmg: float) -> float:
	var boss = null
	for v in units:
		if v.get("boss") != null and is_same(v.get("battle"), b) and troop_count(v) > 0:
			boss = v
			break
	if boss == null:
		return -1.0
	var foes := units.filter(func(v): return v.kind == "army" and is_same(v.get("battle"), b) and not v.get("retreating", false) and troop_count(v) > 0 and not v.get("bandit", false))
	var noise: float = 0.85 + battle_rand.call() * 0.3
	var k: String = boss.troops.keys()[0]
	var H: float = DSTATS[k].hp
	var R0: float = H * DSTATS[k].atk / 30.0
	if armies.has(boss):
		return BOSS_K * raw_strength(foes) * noise / R0 * H
	var f := boss_fortune(b)
	var Rb: float = R0 * maxf(0, 1 - boss.get("wounds", 0.0) / H) * f * f
	var raw := raw_strength(armies)
	if raw <= 0:
		return 0.0
	var hp := 0.0
	for a in armies:
		for kk in a.troops:
			hp += a.troops[kk] * hp_of(a, kk)
	var mix := side_mix(armies)
	var keep := maxf(0.05, (1 - mix.red) * (1 - mix.parry))
	return BOSS_K * Rb * noise / raw * hp / keep


# --- v95: Winged Slippers: an army flies over any border into a neighboring province ---
const FLY_CD := 60.0
const FLY_TIME := 1.6

func fly_why(a, q := -2):
	if not has_art(ME, "slippers"):
		return "Needs the Winged Slippers"
	if a == null:
		return "No army selected"
	if a.get("battle") != null:
		return "Not during battle"
	if a.get("flyT") != null:
		return "Already flying"
	var left: float = cd.get("fly", 0.0) - t
	if left > 0:
		return "Ready in %d s" % ceili(left)
	if q == -2:
		return null
	if q < 0 or q == a.prov or not all_nbr[a.prov].has(q):
		return "Pick a province next to the army"
	if is_death_mtn(q):
		return "Nothing can land on Death Mountain"
	if not can_enter(a, q, q):
		return "Your army may not go there"
	return null


func fly_army(a: Dictionary, q: int) -> bool:
	var why = fly_why(a, q)
	if why != null:
		toast(str(why) + ".", true)
		return false
	var x0: float = a.x
	var y0: float = a.y
	a.path = []
	a.moving = false
	a.surveyQueue = []
	a.sieging = null
	a.lastProv = a.prov
	a.prov = q
	a.slot = free_slot(q, a)
	var xy := slot_pos(q, a.slot)
	a.flyT = {"x0": x0, "y0": y0, "x1": xy[0], "y1": xy[1], "t0": t}
	a.arrived = t + FLY_TIME
	cd.fly = t + FLY_CD
	toast("%s takes wing over the border to %s." % [a.name, prov_name(q)])
	sfx("mv_cavalry", q)
	compute_fog()
	return true


func step_flights() -> void:
	for a in units:
		var F = a.get("flyT")
		if F == null:
			continue
		var f := minf(1.0, (t - F.t0) / FLY_TIME)
		a.x = F.x0 + (F.x1 - F.x0) * f
		a.y = F.y0 + (F.y1 - F.y0) * f
		a.th = atan2(F.y1 - F.y0, F.x1 - F.x0)
		a.flyH = sin(f * PI) * 140
		if f >= 1:
			a.flyT = null
			a.flyH = 0.0
			a.x = F.x1
			a.y = F.y1


# a moving army that steps into a boss's province is stopped there and has to fight
func step_boss_halt() -> void:
	for a in units:
		if a.kind != "army" or not a.moving or a.owner == RAIDERS or a.get("retreating", false) or a.get("exiting", false) \
				or a.get("retreatHome") != null or a.get("battle") != null or a.get("flyT") != null:
			continue
		var B = boss_in(a.prov)
		if B == null:
			continue
		a.path = []
		a.moving = false
		a.surveyQueue = []
		a.arrived = t
		if a.owner == ME and not a.get("bossWarned", false):
			a.bossWarned = true
			toast("%s is stopped by %s at %s!" % [a.name, GameData.c("BOSSES")[B.boss].name, prov_name(a.prov)], true)


# =================================================================================================================
# nations (web: war.js NATIONS / PLAYERS, ai.js spawnAINations): the player is ME = 1, raiders 3, computer nations 4–10
var nations := {}           # id -> the computer nation's state
var players := {}           # id (as text) -> {name, color, light}
var race_of := {}           # id -> "realm"

## A nation's second color (its flag's emblem): human nations' from the New Game page, computer nations' their own.
func secondary_of(o: int) -> Color:
	if seats.has(o):
		return Color(str(seats[o].my_nation.get("secondary", "#faf1dc")))
	if nations.has(o):
		return Color(str(nations[o].get("secondary", "#faf1dc")))
	return Color(str(player_info(o).get("light", "#cccccc")))


func player_info(o: int) -> Dictionary:
	var k := str(o)
	if players.has(k):
		return players[k]
	return GameData.c("PLAYERS").get(k, {"name": "?", "color": "#888888", "light": "#cccccc"})


## A full-size game: the island with its unique provinces, you, and the computer nations in `slots`
## ("easy" / "moderate" / "difficult" / "closed"). web: menu.js startGame
## humans (multiplayer): slot index -> {nation, race, leader} for each slot marked "human" in `slots`: another human
## nation, started at that slot's capital with its own seat.
static func new_world(seed: String, leader_id := "", slots := [], start := "center", map: Dictionary = {}, opts: Dictionary = {}, nation: Dictionary = {}, race := "", races := [], humans: Dictionary = {}) -> Game:
	var g := Game.new()
	g.pick_race(race, leader_id)
	g.slot_races = races
	g.seat_wants = humans
	var mode := map_mode(opts)
	g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_world(seed, map_opts_of(mode) if mode != "normal" else null, true))
	g.world.mode = mode
	g.G = WorldPrep.prep(g.world)
	g.players = GameData.c("PLAYERS").duplicate(true)
	g.set_nation(nation)
	g.setup_game(start)
	g.spawn_ai_nations(slots)
	g.place_setpieces()
	var uqs := g.uq_skip()
	var ruins := g.place_ruins(uqs)
	var skip := uqs.duplicate()
	if ruins >= 0:
		skip[ruins] = true
	g.spawn_lairs(skip)
	for u in g.units:
		if u.get("bandit", false):
			skip[u.prov] = true
	g.place_travelers(skip)
	g.spawn_bosses()
	if QUESTS:
		Quests.setup(g)
	g.assign_leader(leader_id)
	for o in g.seat_ids():
		if o != HOST:
			g.in_seat(o, func(): g.assign_leader(str(g.seat_wants.values().filter(func(h): return h.get("id") == o)[0].get("leader", ""))))
	g.assign_ai_leaders()
	g.apply_leader_start(HOST)
	for o in g.seat_ids():
		if o != HOST:
			g.apply_leader_start(o)
	for id in g.nations:
		g.apply_leader_start(id)
	g.compute_income()
	g.compute_fog()
	g.started = true
	g.last = 0.0
	g.next_tick = 0.0
	return g


# web: war.js hopsFrom
func hops_list(src, nbr_list = null) -> Array:
	var nb: Array = nbr_list if nbr_list != null else open_nbr
	var d := []
	d.resize(G.provs.size())
	d.fill(INF)
	var q: Array = src.duplicate() if src is Array else [src]
	for s0 in q:
		d[s0] = 0
	var i := 0
	while i < q.size():
		var a: int = q[i]
		i += 1
		for n in nb[a]:
			var b: int = n if n is int else n.q
			if d[b] == INF:
				d[b] = d[a] + 1
				q.append(b)
	return d


# web: ai.js spawnAINations (computer nations are Realmlings for now) and the v96.js wrapper
# a computer nation's flag: the next of its race's emblems in a seeded order, not one already flown
func race_emblem(rc: String, used: Dictionary) -> String:
	var list: Array = Races.EMBLEMS.get(rc, Races.EMBLEMS.realm).duplicate()
	var rr := Mulberry32.from_string(str(world.seed) + ":emblems:" + rc)
	for i in range(list.size() - 1, 0, -1):
		var jj := int(floor(rr.next() * (i + 1)))
		var tmp = list[i]
		list[i] = list[jj]
		list[jj] = tmp
	for em in list:
		if not used.has(em):
			used[em] = true
			return em
	return list[0]


# a computer nation's emblem color, seeded by the map: a light shade (the first two of a row) of any row
func ai_emblem_color(id: int) -> String:
	var rr := Mulberry32.from_string(str(world.seed) + ":emblemcolor:%d" % id)
	var row: Array = Races.EMBLEM_COLORS[int(floor(rr.next() * Races.EMBLEM_COLORS.size()))]
	return row[int(floor(rr.next() * 2))]


var slot_races := []   # the New Game page's race for each opponent slot: "realm", "swamp", "wood" or "random"
var seat_wants := {}   # multiplayer: slot index -> {nation, race, leader} of each human slot (new_world's humans)

func spawn_ai_nations(slots: Array) -> void:
	nations.clear()
	var key := ",".join(slots.map(func(x): return str(x)))
	var r := Mulberry32.from_string(str(world.seed) + ":nations:" + key)
	var NC: Array = GameData.c("NATION_COLORS")
	var NAT: Dictionary = my_nation
	var colors := range(NC.size()).filter(func(i): return i != NAT.color)
	# Array.sort(() => r() - 0.5): V8's TimSort with a random comparator, reproduced by JS.sort_random
	var places: Array = JS.sort_random(GameData.c("AI_PLACES").duplicate(), r)
	var sw_places: Array = JS.sort_random(GameData.c("SW_AI_PLACES").duplicate(), r)
	var emblems: Array = JS.sort_random(GameData.c("FLAG_EMBLEMS").filter(func(e): return e != NAT.emblem), r)   # (kept: it draws from the map's random stream)
	var used_emblems := {NAT.emblem: true}
	var caps := [capital]
	var reach := hops_list(capital)
	var k := 0
	var kr := 0
	var ks := 0
	var kw := 0
	var wd_names: Array = JS.sort_random(GameData.c("WD_AI_NAMES").duplicate(), r)
	var AI_IDS: Array = GameData.c("AI_IDS")
	var DIFF: Dictionary = GameData.c("AI_DIFF")
	var TITLES: Array = GameData.c("AI_TITLES")
	for i in slots.size():
		var diff: String = slots[i]
		if diff == "human":   # multiplayer: another human nation takes this slot (its race, capital and flag)
			var H: Dictionary = seat_wants.get(i, seat_wants.get(str(i), {}))
			var hid: int = AI_IDS[i]
			var hrc: String = str(H.get("race", "realm"))
			hrc = hrc if hrc in ["realm", "swamp", "wood"] else "realm"
			var hcap := pick_ai_capital(caps, reach, r, Races.HOME[hrc])
			if hcap < 0:
				continue
			caps.append(hcap)
			race_of[hid] = hrc
			H.id = hid
			var hn: Dictionary = H.get("nation", {}).duplicate()
			if not hn.has("color"):
				hn.color = (k + 1) % GameData.c("NATION_COLORS").size()
			used_emblems[str(hn.get("emblem", ""))] = true
			add_seat(hid, hcap, hrc, hn)
			k += 1
			continue
		if not GameData.c("DIFF_NAME").has(diff):
			continue
		var id: int = AI_IDS[i]
		# each opponent is Realmling, Swampling, Woodling or (Random) any of them (web: ai.js spawnAINations races[i])
		var want: String = str(slot_races[i]) if i < slot_races.size() else "realm"
		var rc: String = want if want in ["realm", "swamp", "wood"] else ["realm", "swamp", "wood"][int(floor(r.next() * 3))]
		var cap := pick_ai_capital(caps, reach, r, Races.HOME[rc])
		if cap < 0:
			continue
		race_of[id] = rc
		caps.append(cap)
		var cl: Array = NC[colors[k % colors.size()]]
		var name: String
		if rc == "wood":
			name = wd_names[kw % wd_names.size()]
			kw += 1
		elif rc == "swamp":
			var SWT: Array = GameData.c("SW_AI_TITLES")
			var tl: String = SWT[int(floor(r.next() * SWT.size()))]
			var pl: String = sw_places[ks % sw_places.size()]
			ks += 1
			name = (pl + " " + tl) if r.next() < 0.5 else (tl + " of " + pl)
		else:
			name = TITLES[int(floor(r.next() * TITLES.size()))] + " of " + places[kr % places.size()]
			kr += 1
		players[str(id)] = {"name": name, "color": cl[0], "light": cl[1]}
		var D: Dictionary = DIFF[diff]
		var tech_state := {}
		for tr in GameData.c("TREE_KEYS"):
			tech_state[tr] = {"cur": null, "prog": 0, "bank": 0, "opts": [], "done": [], "tier": 0, "sticky": []}
		var warc := t + 60 + r.next() * 60
		var fam: String = D.family if D.get("family") != null else ["sword", "pole", "blunt"][int(floor(r.next() * 3))]
		fam = "axe" if rc == "swamp" and fam == "sword" else "thrust" if rc == "wood" and fam == "sword" else fam   # web: swamp.js swFamily
		var school = D.school if D.get("school") != null else ["life", "death", "arcane"][int(floor(r.next() * 3))]
		if rc == "swamp" and school == "life":   # web: swamp.js swSchool (no Herbomancy for Swamplings, no Necromancy for Woodlings)
			school = ["death", "arcane", "pyro"][int(floor(r.next() * 3))]
		elif rc == "wood" and (school == "death" or school == "pyro"):
			school = ["life", "arcane", "elemental"][int(floor(r.next() * 3))]
		var aline: String = D.armor
		if rc == "swamp":   # web: swamp.js swArmorLine
			aline = {"leather": "stag", "chain": "wyvern", "plate": "dragon"}.get(aline, "stag")
		elif rc == "wood":
			aline = {"leather": "spirit", "chain": "mithril", "plate": "ornate"}.get(aline, "spirit")
		var N := {"id": id, "diff": diff, "name": name, "emblem": race_emblem(rc, used_emblems), "secondary": ai_emblem_color(id),
			"alive": true, "capital": cap, "stock": GameData.c("START_STOCK").duplicate(), "rep": {}, "surveyed": {cap: true}, "exhaust": 0,
			"ups": {}, "xups": {}, "tech": tech_state, "queue": [], "think": t + 1 + i * 0.37, "nextOutpost": 0, "phase": "grow",
			"stuckSince": null, "warCheck": warc, "family": fam, "armorLine": aline, "race": rc, "school": null, "wantSchool": school,
			"spellT": 0, "dv": 0, "design": {"inf": "d-sw-axe", "cav": "d-sw-ogre"} if rc == "swamp" else {"inf": "d-sword", "cav": "d-rider"}, "armyN": 0, "income": {"gold": 0, "wood": 0, "food": 0}}
		if rc == "swamp":
			N.tech.gov.done.append("mushroom")
		nations[id] = N
		buildings[cap] = {"stage": 2, "born": -10, "owner": id}
		var wf := mk_unit(next_id, GameData.c("WAYFINDER"), "", cap, 0)
		next_id += 1
		wf.owner = id
		units.append(wf)
		var ms := mk_unit(next_id, MASON, "", cap, 1)
		next_id += 1
		ms.owner = id
		units.append(ms)
		ai_new_army(N, cap, {footman_of(id): 3})
		ai_redesign(N)
		k += 1
	# v96: Moderate and Difficult nations pick their school at random
	for id in nations:
		var N: Dictionary = nations[id]
		if N.diff != "moderate" and N.diff != "difficult":
			continue
		var ok := ["life", "death", "arcane"]   # the Realmlings' schools, in the web's order
		N.wantSchool = ok[int(floor(js_rand.call() * ok.size()))]
	compute_fog()


# web: v103.js aiWoodAround: the wood within two provinces (rule 1 of the build order needs wood nearby)
func ai_wood_around(i: int) -> float:
	var d := hops_list(i, all_nbr)
	var w := 0.0
	var k := 0
	for p in G.provs.size():
		if d[p] <= 2:
			w += yields[p].wood + 2 * mini(tree_border[p], 3)
			k += 1
	return w / k if k else 0.0


# web: v103.js pickAICapital (ai.js, plus the wood around)
func pick_ai_capital(caps: Array, reach: Array, r: Mulberry32, terrain := "grassland") -> int:
	var all := range(G.provs.size()).filter(func(i): return not buildings.has(i) and reach[i] < INF and not unique_ban(i))
	var cands := all.filter(func(i): return G.provs[i].terrain == terrain and open_nbr[i].size() >= 2)
	if cands.size() < 8:
		cands = all.filter(func(i): return open_nbr[i].size() >= 2)
	if cands.is_empty():
		return -1
	var ds := caps.map(func(c): return hops_list(c, all_nbr))
	var best := -1
	var bs := -INF
	for i in cands:
		var md := INF
		for d in ds:
			md = minf(md, d[i])
		if md < 3:
			continue
		var sc: float = minf(md, 9) * 10 + open_nbr[i].size() * 2 - (3 if G.provs[i].coastal else 0) + minf(ai_wood_around(i), 6) * 3 + r.next() * 4
		if sc > bs:
			bs = sc
			best = i
	return best


# web: ai.js aiNewArmy: "<place> Host", "<place> Host 2", …
func ai_new_army(N: Dictionary, prov: int, troops: Dictionary) -> Dictionary:
	var a := mk_unit(next_id, "army", "", prov, 0)
	next_id += 1
	a.owner = N.id
	a.troops = troops.duplicate()
	N.armyN += 1
	a.name = str(player_info(N.id).name).split(" of ")[-1] + " Host" + (" %d" % N.armyN if N.armyN > 1 else "")
	a.slot = free_slot(prov, a)
	var xy := slot_pos(prov, a.slot)
	a.x = xy[0]
	a.y = xy[1]
	a.born = t
	units.append(a)
	return a


func ai_has(N: Dictionary, id: String) -> bool:
	var x = TECH_BY_ID.get(id)
	return x != null and N.tech[x.tree].done.has(id)


# web: ai.js aiRedesign: the best gear the nation has researched in its weapon family and armor line
func ai_redesign(N: Dictionary) -> void:
	var W: Dictionary = GameData.c("WEAPONS")
	var A: Dictionary = GameData.c("ARMORS")
	var F: Dictionary = GameData.c("FAMILY")
	var ok_w := func(w): return W[w].get("tech") == null or ai_has(N, W[w].tech)
	if N.get("race") == "swamp" or N.get("race") == "wood":
		_ai_redesign_race(N, W, A, F, ok_w)
		return
	var weapon: String = F[N.family].order.filter(ok_w).back()
	var armor: String = N.armorLine + "1"
	for lv in range(4, 0, -1):
		var aid: String = N.armorLine + str(lv)
		if A[aid].get("tech") == null or ai_has(N, A[aid].tech):
			armor = aid
			break
	if not A.has(armor) or (A[armor].get("tech") != null and not ai_has(N, A[armor].tech)):
		armor = "leather1"
	var shield = null
	if not W[weapon].twoH:
		for sh in ["tower", "kite", "round"]:
			if ai_has(N, GameData.c("SHIELD_DEFS")[sh].tech):
				shield = sh
				break
	var cav_w: String = F.pole.order.filter(ok_w).back()
	var horse := "friesian" if ai_has(N, "horse-training") else "mongolian" if ai_has(N, "horse-breeding") else "riding"
	var sig := "|".join([weapon, armor, str(shield), cav_w, horse])
	if sig == N.get("designSig", ""):
		return
	N.designSig = sig
	N.dv += 1
	var role: String = {"pole": "Pikeman", "sword": "Swordsman", "blunt": "Maceman"}[N.family]
	var inf := {"id": "ai%di%d" % [N.id, N.dv], "name": role, "type": "inf", "weapon": weapon, "shield": shield, "armor": armor, "horse": null, "race": "realm"}
	var cav := {"id": "ai%dc%d" % [N.id, N.dv], "name": "Lancer", "type": "cav", "weapon": cav_w, "shield": null, "armor": armor, "horse": horse, "race": "realm"}
	register_design(inf)
	register_design(cav)
	N.design = {"inf": inf.id, "cav": cav.id}
	if not N.has("designs"):
		N.designs = []
	N.designs.append(inf)
	N.designs.append(cav)



# web: swamp.js / wood.js aiRedesign: Berserkers and Ogres; Protectors and Champions
func _ai_redesign_race(N: Dictionary, W: Dictionary, A: Dictionary, F: Dictionary, ok_w: Callable) -> void:
	var sw: bool = N.race == "swamp"
	var fam: Dictionary = F.get(N.family, F.axe if sw else F.thrust)
	var weapon: String = fam.order.filter(ok_w).back()
	var armor := "stag1" if sw else "spirit1"
	for lv in range(4, 0, -1):
		var aid: String = N.armorLine + str(lv)
		if A.has(aid) and (A[aid].get("tech") == null or ai_has(N, A[aid].tech)):
			armor = aid
			break
	var inf: Dictionary
	var cav: Dictionary
	var sig: String
	if sw:
		var off = weapon if ai_has(N, "dualwield") and not W[weapon].twoH else null
		var cav_w: String = F.blunt.order.filter(ok_w).back()
		var horse := "friesian" if ai_has(N, "horse-training") else "mongolian" if ai_has(N, "horse-breeding") else "riding"
		sig = "|".join([weapon, armor, str(off), cav_w, horse])
		if sig == N.get("designSig", ""):
			return
		N.dv += 1
		var role: String = {"pole": "Spear Berserker", "axe": "Axe Berserker", "blunt": "Club Berserker"}.get(N.family, "Berserker")
		inf = {"id": "ai%di%d" % [N.id, N.dv], "name": role, "type": "inf", "weapon": weapon, "shield": null, "off": off, "armor": armor, "horse": null, "race": "swamp"}
		cav = {"id": "ai%dc%d" % [N.id, N.dv], "name": GameData.c("OGRES")[horse].name, "type": "cav", "weapon": cav_w, "shield": null, "off": null, "armor": armor, "horse": horse, "race": "swamp"}
	else:
		var champ_a := "ornate1"
		for lv in range(4, 0, -1):
			if ai_has(N, "a-ornate%d" % lv):
				champ_a = "ornate%d" % lv
				break
		var champ_w := ("oblivion" if N.family == "thrust" else "worldaxe") if ai_has(N, "horse-training") else ("wrathspear" if N.family == "pole" else "ancienthammer") if ai_has(N, "horse-breeding") else "champsword"
		sig = "|".join([weapon, armor, champ_a, champ_w])
		if sig == N.get("designSig", ""):
			return
		N.dv += 1
		var role: String = {"pole": "Spear Protector", "thrust": "Sword Protector", "blunt": "Club Protector"}.get(N.family, "Protector")
		inf = {"id": "ai%di%d" % [N.id, N.dv], "name": role, "type": "inf", "weapon": weapon, "shield": null, "off": null, "armor": armor, "horse": null, "race": "wood"}
		if W[weapon].fam == "blunt" and not W[weapon].twoH:
			inf.two = true
		cav = {"id": "ai%dc%d" % [N.id, N.dv], "name": "Champion", "type": "cav", "weapon": champ_w, "shield": null, "off": null, "armor": champ_a, "horse": null, "race": "wood"}
	N.designSig = sig
	register_design(inf)
	register_design(cav)
	N.design = {"inf": inf.id, "cav": cav.id}
	if not N.has("designs"):
		N.designs = []
	N.designs.append(inf)
	N.designs.append(cav)


# =================================================================================================================
# war state and the basic questions about it (web: war.js); the rules of war follow in the next step
var wars := []              # {id, a, b, by, base, since, nextTick, battles, active, winStart, peak, parent, demandAt}
var truces := {}            # "x:y" -> the time the truce ends
var allies := []            # {a, b}
var war_seq := 0
var met: Dictionary:  # nations the player has met
	get: return cur["met"]
	set(v): cur["met"] = v
var dipl := {"access": []}  # v105: military access given {from, to}; shared by every nation, except DIPL_SEAT_KEYS
## The parts of `dipl` that are each human nation's own (its requests, news, spies and what they found). The seat in
## use has them in `dipl`; the others' wait in seat_dipl (use_seat swaps them).
const DIPL_SEAT_KEYS := ["reqs", "news", "spies", "spyLock", "intel"]
var seat_dipl := {}

func nation_of(p: int) -> int:
	return buildings[p].owner if buildings.has(p) else 0


func is_nation(o: int) -> bool:
	return seats.has(o) or nations.has(o)


static func pair_key(x: int, y: int) -> String:
	return "%d:%d" % [mini(x, y), maxi(x, y)]


func war_between(x: int, y: int):
	for w in wars:
		if (w.a == x and w.b == y) or (w.a == y and w.b == x):
			return w
	return null


func at_war(x: int, y: int) -> bool:
	return war_between(x, y) != null


func truce_left(x: int, y: int) -> float:
	return maxf(0.0, truces.get(pair_key(x, y), 0.0) - t)


func allied(x: int, y: int) -> bool:
	return allies.any(func(A): return (A.a == x and A.b == y) or (A.a == y and A.b == x))


# web: v105.js hasAccess
func has_access(x: int, n: int) -> bool:
	if x == n or not is_nation(x) or not is_nation(n):
		return false
	return allied(x, n) or dipl.access.any(func(g): return g.from == n and g.to == x)



# =================================================================================================================
# the rules of war (web: war.js, with v78 war log, v95 peace rework, v96 timers, v99 meetings and warscore, v102
# conquered capitals, v105 opinion / access / Proxy Wars, v106 alliances)
var occ_prog := {}          # province -> {by, f}
var war_log := []
var war_ever := {}          # pair keys of nations that have ever been at war
var war_lock := {}          # nation -> the time it may declare war again (it surrendered)
var ai_met := {}            # pair keys of computer nations that have met
var demand:  # a computer nation's demand to the player, waiting for an answer
	get: return cur["demand"]
	set(v): cur["demand"] = v
var ally_offer:
	get: return cur["ally_offer"]
	set(v): cur["ally_offer"] = v
var ally_ask: Dictionary:  # nation -> when it may offer an alliance again
	get: return cur["ally_ask"]
	set(v): cur["ally_ask"] = v
var fallen: bool:
	get: return cur["fallen"]
	set(v): cur["fallen"] = v
var war_last_t := -1.0
var met_at: float:
	get: return cur["met_at"]
	set(v): cur["met_at"] = v
var ai_met_at := -9.0
var on_game_over: Callable  # the view's "your realm has fallen"

func W(k: String):
	return GameData.c("WAR")[k]


func forts_held(o: int) -> int:
	var n := 0
	for p in buildings:
		if buildings[p].owner == o and buildings[p].stage == 1:
			n += 1
	return n


func max_take0(o: int) -> int:
	return maxi(1, 2 * forts_held(o))


func max_take(o: int) -> int:
	return max_take0(o)


func war_lock_left(o: int) -> float:
	return maxf(0.0, war_lock.get(o, 0.0) - t)


func alive_nation(o: int) -> bool:
	return (not seats[o].fallen) if seats.has(o) else (nations.has(o) and nations[o].alive)


func ai_ids() -> Array:
	return nations.keys()


func live_nations() -> Array:
	return ([ME] + ai_ids()).filter(func(o): return alive_nation(o))


func the_name(o: int) -> String:
	return "you" if o == ME else "the " + player_info(o).name


func wars_of(o: int) -> Array:
	return wars.filter(func(w): return w.a == o or w.b == o)


static func foe_of(w: Dictionary, o: int) -> int:
	return w.b if w.a == o else w.a


func enemies_of(o: int) -> Array:
	return wars_of(o).map(func(w): return foe_of(w, o))


func allies_of(o: int) -> Array:
	var out := []
	for A in allies:
		if A.a == o:
			out.append(A.b)
		elif A.b == o:
			out.append(A.a)
	return out


func treaty_count(o: int) -> int:
	return allies_of(o).size()


func capital_of(o: int) -> int:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return capital_of(o))
	if o == ME and buildings.has(capital) and buildings[capital].owner == ME and buildings[capital].stage == 2:
		return capital
	for p in buildings:
		if buildings[p].owner == o and buildings[p].stage == 2:
			return p
	return -1


func soldiers_in(o: int, p: int) -> int:
	var n := 0
	for v in units:
		if v.kind == "army" and v.owner == o and v.prov == p and not v.get("retreating", false) and not v.moving and v.get("battle") == null:
			n += troop_count(v)
	return n


func occ_time_for(n: int, stage: int) -> float:
	var T: Array = W("occTimes")
	return (T[2] if n >= 6 else T[1] if n >= 2 else T[0]) * (W("occCapital") if stage == 2 else 1)


func knows(o: int) -> bool:
	return o == ME or met.has(o)


func has_met(a: int, b: int) -> bool:
	return a == b or (met.has(b) if a == ME else met.has(a) if b == ME else ai_met.has(pair_key(a, b)))


func tech_of(o: int, id: String) -> bool:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return tech_of(o, id))
	return has_tech(id) if o == ME else (ai_has(nations[o], id) if nations.has(o) else false)


func moat_delay(b: Dictionary, by: int) -> float:
	return 10.0 if by != b.owner and b.stage >= 1 and is_nation(b.owner) and tech_of(b.owner, "moat") else 0.0


func news(msg: String, warn := false) -> void:
	toast(msg, warn)


# --- v105 opinion: what a computer nation thinks of another ---
const DIPL := {"ally": 50, "trade": 25, "crime": 25, "war": -200, "race": -200, "fort": -25, "den": -25, "difficult": -25,
	"like": 50, "dislike": -25, "boss": 25, "threat": -100, "threatProvs": 100, "exhPer": 2, "exhDeclare": 50,
	"flirt": {"v": 25, "dur": 600}, "growl": {"v": 25, "dur": 600}, "gift": {"v": 25, "dur": 600, "gold": 1000}, "bribe": {"gold": 2000}, "offer": -50,
	"spy": {"gold": 200, "dur": 180, "fail": 0.1, "cost": -50, "lock": 600, "provs": 0.3, "power": 0.3, "show": 3},
	"reqTime": 30, "tradeBonus": 0.1}

func dipl_state() -> Dictionary:
	for kv in [["decl", {}], ["boss", {}], ["mods", []], ["access", []], ["trade", []], ["crime", []], ["lost", {}], ["news", []], ["enemy", {}],
			["spies", {}], ["spyLock", {}], ["intel", {}], ["reqs", []]]:
		if not dipl.has(kv[0]):
			dipl[kv[0]] = kv[1].duplicate()
	if not dipl.get("seq", 0):
		dipl.seq = 1
	return dipl


func troop_mix(o: int) -> Dictionary:
	var m := {"inf": 0, "cav": 0, "rng": 0}
	for a in units:
		if a.kind != "army" or a.owner != o:
			continue
		for k in a.troops:
			var c: int = a.troops[k]
			if not c or k == MAGE:
				continue
			var st = DSTATS.get(k)
			if st == null or st.get("fam") == "boss" or st.get("fam") == "water":
				continue
			if st.get("ranged", false):
				m.rng += c
			elif st.get("cav", false):
				m.cav += c
			else:
				m.inf += c
	return m


func extras_of_nation(o: int, type: String) -> Array:
	var per := []
	for p in buildings:
		if buildings[p].owner == o:
			per.append(extras_in(p).filter(func(e): return e.type == type).size())
	return per


func school_of_nation(o: int):
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return school_of_nation(o))
	return current_school() if o == ME else nations[o].school if nations.has(o) else null


func leader_like(L: Dictionary, t2: int) -> int:
	match L.get("like"):
		"school":
			var sc = school_of_nation(t2)
			return 0 if sc == null else DIPL.like if sc == L.school else DIPL.dislike
		"cav":
			var m := troop_mix(t2)
			return DIPL.like if m.cav > m.inf else DIPL.dislike if m.cav == 0 else 0
		"nocav":
			var m := troop_mix(t2)
			return DIPL.like if m.cav == 0 else DIPL.dislike if m.cav > m.inf else 0
		"forges":
			var per := extras_of_nation(t2, "forge")
			var f := 0
			for x in per:
				f += x
			return DIPL.dislike if f == 0 else DIPL.like if f >= maxi(1, per.size() / 3) else 0
		"lumber3", "farms3":
			var per := extras_of_nation(t2, "lumber" if L.like == "lumber3" else "farm")
			var mx := 0
			for x in per:
				mx = maxi(mx, x)
			return DIPL.like if mx >= 3 else DIPL.dislike if mx <= 1 else 0
		"scouts":
			var n := units.filter(func(u): return u.owner == t2 and u.kind == WAYFINDER).size()
			var need := ["autoscout", "farsight"] + ([] if t2 != ME else ["scoutsight"])
			var full: int = n if need.all(func(id): return tech_of(t2, id)) else 0
			return DIPL.like if full >= 3 else DIPL.dislike if n <= 1 else 0
	return 0


func opinion_parts(o: int, t2: int) -> Array:
	if not nations.has(o) or o == t2 or not alive_nation(t2):
		return []
	var D := dipl_state()
	var out := []
	var dc: int = D.decl.get("%d>%d" % [t2, o], 0)
	if dc:
		out.append(["Declared war on them" + (" (×%d)" % dc if dc > 1 else ""), DIPL.war * dc])
	var forts := 0
	for p in buildings:
		if buildings[p].owner == t2 and buildings[p].stage == 1 and all_nbr[p].any(func(q): return nation_of(q) == o):
			forts += 1
	if forts:
		out.append(["%d fort%s on their border" % [forts, "s" if forts > 1 else ""], DIPL.fort * forts])
	if race(o) != race(t2):   # (0.18: every computer nation distrusts another race)
		out.append(["Another race (%s)" % Races.NAME.get(race(t2), "others"), DIPL_OTHER_RACE])
	if t2 == ME and nations[o].diff == "difficult":
		out.append(["Difficult nation", DIPL.difficult])
	if provs_of(t2).size() >= DIPL.threatProvs:
		out.append(["Existential Threat", DIPL.threat])
	var L = leader_of(o)
	if L != null:
		var v := leader_like(L, t2)
		if v:
			out.append([L.full, v])
	var bk: int = D.boss.get(t2, 0)
	if bk:
		out.append(["Slew a boss", DIPL.boss * bk])
	for m in D.mods:
		if m.o == o and m.t == t2 and m.until > t:
			out.append([m.kind, m.v])
	# v106: access they give, Trade Networks, proclaimed enemies, shared enemies
	if D.access.any(func(g): return g.from == t2 and g.to == o) and not allied(o, t2):
		out.append(["Grants you military access", DIPL_ACCESS_OP])
	if D.get("trade", []).any(func(P): return (P.a == o and P.b == t2) or (P.a == t2 and P.b == o)):
		out.append(["Trade Network", DIPL_TRADE_OP])
	if enemy_of(t2) == o:
		out.append(["Proclaimed you their enemy", DIPL_ENEMY])
	var eo := enemy_of(o)
	if eo and eo != t2 and enemy_of(t2) == eo:
		out.append(["Shared Enemies: the %s" % player_info(eo).name, DIPL_SHARED])
	return out


const DIPL_OTHER_RACE := -100

func opinion(o: int, t2: int) -> int:
	var v := 0
	for part in opinion_parts(o, t2):
		v += part[1]
	return v


func enemy_of(o: int) -> int:
	var r = dipl_state().enemy.get(o)
	return r.t if r is Dictionary and alive_nation(r.t) else 0


func access_given(from: int, to: int) -> bool:
	return dipl_state().access.any(func(g): return g.from == from and g.to == to)


func end_access(from: int, to: int, why := "") -> void:
	var D := dipl_state()
	var had := access_given(from, to)
	D.access = D.access.filter(func(g): return not (g.from == from and g.to == to))
	if had and from == ME:
		toast("The %s may no longer march through your land%s." % [player_info(to).name, ": " + why if why != "" else ""])
	elif had and to == ME:
		toast("The %s withdrew your military access%s." % [player_info(from).name, ": " + why if why != "" else ""], true)


func troop_value(k: String) -> int:
	var d = unit_defs.get(k)
	return 0 if d == null or not d.has("cost") else int(d.cost.get("gold", 0) + d.cost.get("wood", 0))


func army_value(o: int) -> int:
	var n := 0
	for a in units:
		if a.kind == "army" and a.owner == o:
			for k in a.troops:
				n += a.troops[k] * troop_value(k)
	return n


func parent_war(w):
	if w == null or w.get("parent") == null:
		return null
	for x in wars:
		if x.id == w.parent:
			return x
	return null


func proxy_shield(o: int, f: int) -> bool:
	var w = war_between(o, f)
	return w != null and w.get("proxy") == o


func exhaustion_of(w: Dictionary) -> int:
	if w.get("proxy") == null:
		return 0
	var lost := maxf(0, dipl_state().lost.get(w.proxy, 0) - w.get("lost0", 0))
	var pct: float = lost / w.cost0 * 100 if w.get("cost0", 0) > 0 else 0.0
	return mini(100, roundi(pct * DIPL.exhPer + w.get("exhB", 0)))


# --- declaring war ---
func cap_break(pairs: Array) -> bool:
	if seats.size() > 1:   # multiplayer: a player may be at war with as many nations as they like (0.18)
		return false
	var foes := {}
	for f in enemies_of(ME):
		foes[f] = true
	for pr in pairs:
		if pr[0] == ME:
			foes[pr[1]] = true
		if pr[1] == ME:
			foes[pr[0]] = true
	return foes.size() > W("maxVsPlayer")


func nations_border(a: int, b: int) -> bool:
	for p in buildings:
		if buildings[p].owner == a and all_nbr[p].any(func(q): return nation_of(q) == b):
			return true
	return false


static func fmt_time(s: float) -> String:
	var n := ceili(s)
	return "%d:%02d" % [n / 60, n % 60]


func declare_why(att: int, def: int) -> String:
	if att == def or not alive_nation(att) or not alive_nation(def):
		return "There is no one to declare war on"
	if at_war(att, def):
		return "Already at war"
	if allied(att, def):
		return "Allies can’t go to war with each other"
	var wl := war_lock_left(att)
	if wl > 0:
		return "You surrendered: no wars for %s" % fmt_time(wl) if att == ME else "They surrendered recently"
	var tl := truce_left(att, def)
	if tl > 0:
		return "Truce: %s left" % fmt_time(tl)
	if not nations_border(att, def):
		return "You can only declare war on a nation that borders you" if att == ME else "They don’t border each other"
	var pairs := [[att, def]]
	for j in allies_of(def):
		if j != att and not allied(att, j) and not at_war(att, j):
			pairs.append([att, j])
	if cap_break(pairs):
		return "At most %d nations can be at war with you at once" % W("maxVsPlayer") if att == ME else "%s already faces %d enemies" % [player_info(ME).name, W("maxVsPlayer")]
	var st := stock_of(att)
	var short := []
	for k in W("declareCost"):
		if st.get(k, 0) < W("declareCost")[k]:
			short.append("%d %s" % [W("declareCost")[k], k])
	return "Need " + ", ".join(short) if not short.is_empty() else ""


func new_war(att: int, def: int, parent) -> Dictionary:
	war_seq += 1
	var w := {"id": war_seq, "a": att, "b": def, "by": att, "base": 0.0, "since": t, "nextTick": t + W("tickEvery"), "battles": 0,
		"active": false, "winStart": t, "peak": 0.0, "parent": parent, "demandAt": t + 30}
	wars.append(w)
	war_ever[pair_key(att, def)] = true
	# v78: the war log
	if att == ME or def == ME:
		var foe := def if att == ME else att
		war_log.append({"id": w.id, "foe": foe, "foeName": player_info(foe).name, "start": t, "end": null, "result": null, "joined": parent != null})
	# v105: a war ends military access and agreements between the two; a war joined through an alliance is a Proxy War
	var D := dipl_state()
	end_access(att, def, "you are at war")
	end_access(def, att, "you are at war")
	for kind in ["trade", "crime"]:
		var P = pair_has(D[kind], att, def)
		if P != null:
			end_pact(kind, P, "war")
	if parent != null:
		w.proxy = def
		w.cost0 = army_value(def)
		w.lost0 = D.lost.get(def, 0)
		w.exhB = 0
	else:
		for c in wars:
			if not is_same(c, w) and c.get("proxy") == def:
				c.exhB = c.get("exhB", 0) + DIPL.exhDeclare
		if att != ME and def != ME and (knows(att) or knows(def)):
			news_add("war", att, def)
	return w


func declare_war(att: int, def: int):
	var why := declare_why(att, def)
	if why != "":
		if att == ME:
			toast("Can’t declare war: %s." % (why[0].to_lower() + why.substr(1)), true)
		return null
	var st := stock_of(att)
	for k in W("declareCost"):
		st[k] -= W("declareCost")[k]
	var w := new_war(att, def, null)
	var joins := allies_of(def).filter(func(j): return j != att and not allied(att, j) and not at_war(att, j))
	for j in joins:
		new_war(att, j, w.id)
	var jn := " and ".join(joins.map(func(j): return "the " + player_info(j).name))
	if att == ME or def == ME or joins.has(ME):
		sfx("war_declare")
	if att == ME:
		met[def] = true
		toast("You declared war on the %s!%s (−%s)" % [player_info(def).name, (" Their %s, %s, %s the war against you." % ["allies" if joins.size() > 1 else "ally", jn, "join" if joins.size() > 1 else "joins"]) if not joins.is_empty() else "", cost_text(W("declareCost"))], true)
	elif def == ME:
		met[att] = true
		toast("The %s has declared war on you!" % player_info(att).name, true)
	elif joins.has(ME):
		met[att] = true
		toast("The %s attacked your ally, the %s: you are at war with them too!" % [player_info(att).name, player_info(def).name], true)
	elif knows(att) or knows(def):
		news("The %s declared war on the %s." % [player_info(att).name, player_info(def).name])
	var D := dipl_state()
	D.decl["%d>%d" % [att, def]] = D.decl.get("%d>%d" % [att, def], 0) + 1
	return w


# --- warscore ---
func occ_score(w: Dictionary) -> float:
	if w.get("proxy") != null:
		return 0.0
	var s := 0.0
	var V: Array = W("occVal")
	for p in occ:
		if not buildings.has(p):
			continue
		var b: Dictionary = buildings[p]
		if b.owner == w.b and occ[p] == w.a:
			s += V[b.stage]
		elif b.owner == w.a and occ[p] == w.b:
			s -= V[b.stage]
	var kids := wars.filter(func(c): return c.get("parent") == w.id and c.get("proxy") != null)
	if not kids.is_empty():
		for p in occ:
			if buildings.has(p) and buildings[p].owner == w.a and kids.any(func(c): return c.proxy == occ[p]):
				s -= V[buildings[p].stage]
	return s


static func clamp_ws(n: float) -> float:
	return clampf(n, -100, 100)


func warscore(w, side: int) -> int:
	if w == null or w.get("proxy") != null:
		return 0
	var s := int(clamp_ws(JS.round_js(w.base + occ_score(w))))
	return -s if side == w.b else s


func add_score(w: Dictionary, side: int, n: float) -> void:
	w.base = clamp_ws(w.base + (n if side == w.a else -n))


func battle_war(b):
	if b == null or b.get("order") == null or b.order.size() < 2:
		return null
	return war_between(b.order[0], b.order[1])


func war_wipe(b: Dictionary, a: Dictionary) -> void:
	if nations.has(a.owner) and has_method("ai_note_defeat"):
		call("ai_note_defeat", a, b)
	var w = battle_war(b)
	if w == null:
		return
	if w.get("proxy") != null:
		if a.owner == w.proxy:
			return
		var P = parent_war(w)
		if P == null:
			return
		var n2: int = a.get("wsSize", b.lost.get(a.owner, 0))
		var all2: int = maxi(n2, a.get("wsTotal", 0))
		var pts2: int = W("wipe") if n2 > all2 / 2.0 else W("wipeBig") if n2 > W("wipeMin") else 0
		if pts2:
			add_score(P, P.b, pts2)
			P.battles += pts2 if P.b == P.a else -pts2
		return
	if a.owner != w.a and a.owner != w.b:
		return
	var foe := foe_of(w, a.owner)
	var n: int = a.wsSize if a.get("wsSize", 0) else b.lost.get(a.owner, 0)
	var all: int = maxi(n, a.get("wsTotal", 0))
	var pts: int = W("wipe") if n > all / 2.0 else W("wipeBig") if n > W("wipeMin") else 0
	if not pts:
		return
	add_score(w, foe, pts)
	w.battles += pts if foe == w.a else -pts


func war_battle_check(b: Dictionary) -> void:
	var w = battle_war(b)
	if w == null or w.active:
		return
	for o in [w.a, w.b]:
		var lost: int = b.lost.get(o, 0)
		if lost and lost > W("heavyLoss") * (soldier_count(o) + lost):
			w.active = true
			if w.a == ME or w.b == ME:
				toast("A bloody battle: the war has turned serious, and the side ahead now gains warscore over time.")
			return


# --- occupation, the time tick, AI peace ---
func step_war(now: float) -> void:
	var dt := maxf(0.0, minf(0.5, now - (war_last_t if war_last_t >= 0 else now)))
	war_last_t = now
	if wars.is_empty() and occ.is_empty():
		return
	var stand := {}
	for v in units:
		if v.kind == "army" and not v.get("retreating", false) and not v.moving and v.get("battle") == null:
			var n := troop_count(v)
			if n > 0:
				stand[v.prov * 16 + v.owner] = stand.get(v.prov * 16 + v.owner, 0) + n
	var has := func(o: int, p: int) -> int: return stand.get(p * 16 + o, 0)
	var near := {}
	for v in units:
		if v.kind == "army" and not v.get("retreating", false) and troop_count(v) > 0:
			near[v.prov * 16 + v.owner] = true
	var fighting := {}
	for b in battles:
		fighting[b.prov] = true
	var mine_changed := false
	for p in buildings.keys():
		if not buildings.has(p):
			continue
		var b: Dictionary = buildings[p]
		if not is_nation(b.owner):
			continue
		var O: int = b.owner
		var occ_by = occ.get(p)
		if occ_by != null and not at_war(O, occ_by):
			occ.erase(p)
			continue
		var foes := enemies_of(O).filter(func(f): return not proxy_shield(O, f))
		if foes.is_empty():
			occ_prog.erase(p)
			continue
		var goal = null
		if not fighting.has(p):
			if occ_by == null:
				if not has.call(O, p):
					for f in foes:
						if has.call(f, p):
							goal = f
							break
			elif has.call(O, p) and not foes.any(func(f): return has.call(f, p)):
				goal = O
		var pr = occ_prog.get(p)
		if goal == null:
			if pr != null and (fighting.has(p) or (near.has(p * 16 + pr.by) and not enemies_of(pr.by).any(func(f): return has.call(f, p)))):
				continue
			occ_prog.erase(p)
			continue
		var cur: Dictionary = pr if pr != null and pr.by == goal else {"by": goal, "f": 0.0}
		cur.f += dt / (occ_time_for(has.call(goal, p), b.stage) + moat_delay(b, goal))
		occ_prog[p] = cur
		if cur.f < 1:
			continue
		occ_prog.erase(p)
		var name := prov_name(p)
		var what: String = ["outpost", "fort", "capital"][b.stage]
		var mine: bool = O == ME or goal == ME or occ_by == ME
		if goal == O:
			occ.erase(p)
			if mine:
				toast("%s liberated!" % name if goal == ME else "The enemy has retaken %s." % name, goal != ME)
		else:
			occ[p] = goal
			var w = war_between(goal, O)
			if mine and b.stage >= 1:
				sfx("war_fort_win" if goal == ME else "war_fort_lose")
			if w != null and b.stage >= 1 and not w.active:
				w.active = true
				if mine:
					toast("A %s has fallen: the war has turned serious, and the side ahead now gains warscore over time." % what)
			if mine:
				toast("%s occupied! +%d warscore while you hold this %s." % [name, W("occVal")[b.stage], what] if goal == ME else "The %s has occupied your %s at %s! (−%d)" % [player_info(goal).name, what, name, W("occVal")[b.stage]], goal != ME)
		if mine:
			mine_changed = true
	if mine_changed:
		compute_income()
	for w in wars.duplicate():
		if wars.has(w):
			step_one_war(w, now)
	check_ai_demands(now)


func step_one_war(w: Dictionary, now: float) -> void:
	if w.get("proxy") != null:
		# v105: a Proxy War ends when its nation is exhausted
		if exhaustion_of(w) >= 100:
			end_war(w)
			if w.proxy == ME:
				sfx("war_peace")
				toast("Your nation is exhausted: you make a white peace with the %s and leave your ally’s war." % player_info(w.a).name, true)
			elif w.a == ME:
				toast("The %s is exhausted: it makes a white peace with you and leaves the war." % player_info(w.proxy).name)
		return
	for L in [w.a, w.b]:
		if all_occupied(L, foe_of(w, L)) and not w.get("broken"):
			w.broken = L
			var win := foe_of(w, L)
			add_score(w, win, 200)
			if w.a == ME or w.b == ME:
				toast("Every province you hold is occupied: the %s is at 100 warscore." % player_info(win).name if L == ME else "Every province of the %s is occupied: warscore 100%%. Call for peace in Diplomacy." % player_info(L).name, L == ME)
	var tick: Array = W("occTick")
	while now >= w.nextTick:
		for p in occ:
			if not buildings.has(p):
				continue
			var b: Dictionary = buildings[p]
			if not tick[b.stage]:
				continue
			if b.owner == w.b and occ[p] == w.a:
				add_score(w, w.a, tick[b.stage])
			elif b.owner == w.a and occ[p] == w.b:
				add_score(w, w.b, tick[b.stage])
		w.nextTick += W("tickEvery")
	w.peak = maxf(w.peak, absi(warscore(w, w.a)))
	if now - w.winStart >= W("stallWindow"):
		if w.peak <= W("stallScore"):
			if w.a == ME or w.b == ME:
				toast("Neither side got past %d warscore in %d minutes. The war with the %s ends in white peace." % [W("stallScore"), W("stallWindow") / 60, player_info(foe_of(w, ME)).name])
			make_peace(w, w.a, {"kind": "white"})
			return
		w.winStart = now
		w.peak = absi(warscore(w, w.a))
	if w.a != ME and w.b != ME:
		ai_peace(w, now)


func all_occupied(o: int, by: int) -> bool:
	var own := provs_of(o)
	return not own.is_empty() and own.all(func(p): return occ.get(p) == by)


func ai_peace(w: Dictionary, now: float) -> void:
	var s := warscore(w, w.a)
	var lead: int = w.a if s > 0 else w.b
	var loser := foe_of(w, lead)
	var sc := absi(s)
	if sc >= W("provs") and now >= w.demandAt:
		w.demandAt = now + 60
		var provs: Array = provs_of(loser) if sc >= W("total") and annexable(lead, loser) and provs_of(loser).size() <= demand_max(sc, lead) else connected_pick(lead, loser, demand_max(sc, lead))
		make_peace(w, lead, {"kind": "provs", "provs": provs} if not provs.is_empty() else {"kind": "gold"})


# v96 (v101: 20 minutes): every war ends in white peace after a while unless a deal is made first
const WAR_TIMER := 1200.0

func step_war_timers() -> void:
	for w in wars.duplicate():
		if not wars.has(w) or WAR_TIMER - (t - w.since) > 0:
			continue
		if w.a == ME or w.b == ME:
			toast("The war with the %s has gone on too long: it ends in white peace." % player_info(foe_of(w, ME)).name)
		make_peace(w, w.a, {"kind": "white"})


# --- peace ---
func takeable(p: int, winner: int) -> bool:
	var o = occ.get(p)
	return o == null or o == winner


func scouted_by(o: int, p: int) -> bool:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		return in_seat(o, func(): return scouted_by(o, p))
	if nation_of(p) == o:
		return true
	if o == ME:
		return wf.has(p) or known.has(p)
	var L = nations[o].get("scouted") if nations.has(o) else null
	return L == null or L.has(p)


func demand_max0(s: int, o := ME) -> int:
	if s >= W("total"):
		return maxi(1 + (W("total") - W("provs")) / 5, max_take0(o))
	return 1 + (s - W("provs")) / 5 if s >= W("provs") else 0


func demand_max(s: int, o := ME) -> int:
	return demand_max0(s, o)


func annexable(winner: int, loser: int) -> bool:
	return provs_of(loser).all(func(p): return takeable(p, winner))


func capital_land(o: int) -> Dictionary:
	var cap := capital_of(o)
	var set := {}
	if cap < 0:
		return set
	var q := [cap]
	set[cap] = true
	var i := 0
	while i < q.size():
		for n in all_nbr[q[i]]:
			if not set.has(n) and nation_of(n) == o:
				set[n] = true
				q.append(n)
		i += 1
	return set


func seize_why(winner: int, loser: int, provs: Array) -> String:
	var land := capital_land(winner)
	var left := {}
	for p in provs:
		left[p] = true
	var grew := true
	while grew and not left.is_empty():
		grew = false
		for p in left.keys():
			if all_nbr[p].any(func(n): return land.has(n)):
				land[p] = true
				left.erase(p)
				grew = true
	if left.is_empty():
		return ""
	return "%s %s connect to your capital" % [", ".join(left.keys().map(func(p): return prov_name(p))), "don’t" if left.size() > 1 else "doesn’t"]


func connected_pick(winner: int, loser: int, n := -1) -> Array:
	if n < 0:
		n = W("maxProvs")
	var land := capital_land(winner)
	var cap := capital_of(loser)
	var out := []
	var cand := provs_of(loser).filter(func(p): return p != cap and takeable(p, winner) and scouted_by(winner, p))
	while out.size() < n:
		var ok := cand.filter(func(p): return not out.has(p) and all_nbr[p].any(func(q): return land.has(q)))
		if ok.is_empty():
			break
		ok = JS.stable_sort(ok, func(a, b):
			var d := int(occ.get(b) == winner) - int(occ.get(a) == winner)
			return d if d != 0 else a - b)
		out.append(ok[0])
		land[ok[0]] = true
	return out


func peace_check(w, kind: String, provs := []) -> String:
	if w == null or not wars.has(w):
		return "Not at war"
	var s := warscore(w, ME)
	var foe := foe_of(w, ME)
	match kind:
		"white":
			if t - w.since < W("whiteAfter"):
				return "No white peace in the first %d minutes (%s left)" % [W("whiteAfter") / 60, fmt_time(W("whiteAfter") - (t - w.since))]
			if s < 0:
				return "Losing: you can only surrender"
			return ""
		"surrender":
			return "" if s < 0 else "Only the losing side can surrender"
		"gold":
			return "" if s >= W("gold") else "Needs +%d warscore" % W("gold")
		"provs":
			if s < W("provs"):
				return "Needs +%d warscore" % W("provs")
			if provs.is_empty():
				return "Pick at least one province"
			var un := provs.filter(func(p): return not scouted_by(ME, p))
			if not un.is_empty():
				return "%s %s been explored by a scout or an army" % [", ".join(un.map(func(p): return prov_name(p))), "haven’t" if un.size() > 1 else "hasn’t"]
			var dm := demand_max(s)
			if provs.size() > dm:
				return "At most %d province%s at %d warscore (1 at 50, +1 for every 5 more)" % [dm, "s" if dm > 1 else "", s]
			if provs.any(func(p): return nation_of(p) != foe):
				return "Only their provinces can be demanded"
			if provs.any(func(p): return buildings[p].stage == 2) and not (s >= W("total") and provs_of(foe).all(func(p): return provs.has(p))):
				return "Their capital can only be taken with every other province (annexation)" if s >= W("total") else "Capitals can’t be demanded below 100 warscore"
			var held := provs.filter(func(p): return not takeable(p, ME))
			if not held.is_empty():
				return "%s occupied by another nation" % ", ".join(held.map(func(p): return prov_name(p)))
			return seize_why(ME, foe, provs)
	return "Unknown term"


func transfer_prov(p: int, to: int) -> void:
	if not buildings.has(p):
		return
	var b: Dictionary = buildings[p]
	var was_cap: bool = b.stage == 2 or b.get("cc", false)
	var from: int = b.owner
	var cc := {"of": b.ccOf if b.get("cc", false) else from}
	b.stage = 0
	b.owner = to
	b.born = t
	occ.erase(p)
	occ_prog.erase(p)
	for o in seats:   # (every human nation's own upgrade jobs there stop)
		seats[o].upgrades.erase(p)
		for k in seats[o].xup.keys():
			if str(k).begins_with("%d@" % p):
				seats[o].xup.erase(k)
	for u in units:
		if u.build != null and u.build.prov == p:
			cancel_build(u)
		if u.get("pending") != null and u.pending.prov == p:
			u.pending = null
	if seats.has(to):
		seats[to].surveyed[p] = t
		seats[to].known[p] = true
	if has_method("ai_on_transfer"):
		call("ai_on_transfer", p, from, to)
	# v102: a conquered capital stays a Conquered Capital (a fort), and becomes the capital again when won back
	if was_cap:
		if cc.of == to and is_nation(to) and capital_of(to) < 0:
			b.stage = 2
			b.cc = false
			if seats.has(to):
				seats[to].capital = p
		else:
			b.stage = 1
			b.cc = true
			b.ccOf = cc.of
	else:
		b.cc = false
	var list := extras_in(p)
	var cap := plot_cap(p)
	if list.size() > cap:
		var kept := JS.stable_sort(list.duplicate(), func(x, y): return x.slot - y.slot).slice(0, cap)
		Quests.extras_lost(self, p, list.filter(func(x): return not kept.any(func(k): return is_same(k, x))))
		list = kept
		extras[p] = list


# after a peace deal, anyone left in a foreign nation's land marches home
func evict_armies() -> void:
	var mine := 0
	for a in units:
		if not is_nation(a.owner):
			continue
		var n := nation_of(a.prov)
		if n == 0 or n == a.owner or hostile(a.owner, n) or allied(a.owner, n):
			continue
		var own := provs_of(a.owner)
		if own.is_empty():
			continue
		a.exiting = true
		a.battle = null
		a.retreating = false
		a.retreatHome = null
		a.surveyQueue = []
		a.survey = null
		a.scouting = null
		a.pendingSurvey = -1
		a.pending = null
		if a.build != null:
			cancel_build(a)
		var d := hops_list(a.prov)
		own = JS.stable_sort(own, func(x, y): return signf(d[x] - d[y]))
		var dest: int = own[0]
		if not order(a, dest, true):
			a.prov = dest
			a.slot = free_slot(dest, a)
			var xy := slot_pos(dest, a.slot)
			a.x = xy[0]
			a.y = xy[1]
			a.path = []
			a.moving = false
			a.exiting = false
		elif a.owner == ME:
			mine += 1
	if mine:
		toast("%d of your unit%s in foreign land and will march home. They can’t be commanded until they reach your territory." % [mine, "s are" if mine > 1 else " is"])


func end_war(w: Dictionary) -> void:
	var live := wars.has(w)
	end_war0(w)
	if live and w.get("parent") == null and w.a != ME and w.b != ME and (knows(w.a) or knows(w.b)):
		news_add("peace", w.a, w.b)


func end_war0(w: Dictionary) -> void:
	var rec = null
	for r in war_log:
		if r.id == w.id and r.end == null:
			rec = r
	wars = wars.filter(func(x): return not is_same(x, w))
	var pair := func(o) -> bool: return o == w.a or o == w.b
	for p in occ.keys():
		if not buildings.has(p) or (pair.call(occ[p]) and pair.call(buildings[p].owner)):
			occ.erase(p)
	for p in occ_prog.keys():
		if not buildings.has(p) or (pair.call(occ_prog[p].by) and pair.call(buildings[p].owner)):
			occ_prog.erase(p)
	for b in battles.duplicate():
		if b.get("order") != null and b.order.size() >= 2 and pair.call(b.order[0]) and pair.call(b.order[1]):
			b.peace = true
			end_battle(b, -1, {})
	truces[pair_key(w.a, w.b)] = t + W("truce")
	if demand != null and demand.war == w.id:
		demand = null
	for c in wars.filter(func(x): return x.get("parent") == w.id):
		end_war(c)
		if c.a == ME or c.b == ME:
			toast("The war that drew you in is over: white peace with the %s." % player_info(foe_of(c, ME)).name)
	if rec != null:
		rec.end = t
		rec.result = rec.get("result_pending", "White peace · the ally’s war ended" if rec.joined else "Ended")


func make_peace(w, winner: int, terms: Dictionary) -> void:
	if w == null or not wars.has(w):
		return
	# multiplayer: a white peace between two players is offered, and the other player chooses (step 11)
	if _from_order and terms.get("kind") == "white" and seats.has(foe_of(w, ME)) and not terms.get("agreed", false):
		_ask_player(foe_of(w, ME), "h_peace", {"war": w.id})
		toast("You offered the %s a white peace." % player_info(foe_of(w, ME)).name)
		return
	Recorder.peace(self, w, winner, terms)   # web: v102.js makePeace wrapper
	var loser := foe_of(w, winner)
	# (multiplayer: the peace is told from a human side's view, the loser's when both are human)
	if loser != ME and winner != ME:
		use_seat(loser if seats.has(loser) else winner)
	elif winner == ME and seats.has(loser):
		use_seat(loser)
	var me := winner == ME or loser == ME
	var lines := []
	var fell := false
	var annexed := 0
	var Wn: String = player_info(winner).name
	match terms.kind:
		"gold":
			var ls := stock_of(loser)
			var ws := stock_of(winner)
			var g := mini(W("goldTerm"), int(floor(ls.gold)))
			ls.gold -= g
			ws.gold += g
			lines.append("You take %d gold" % g if winner == ME else "You pay %d gold" % g if loser == ME else "The %s takes %d gold" % [Wn, g])
		"provs":
			var provs: Array = terms.provs.filter(func(p): return nation_of(p) == loser and takeable(p, winner))
			if provs_of(loser).all(func(p): return provs.has(p)):
				if loser == ME:
					fell = true
				else:
					annexed = loser
			for p in provs:
				transfer_prov(p, winner)
			var lst := ", ".join(provs.map(func(p): return prov_name(p)))
			lines.append("You gain %d province%s: %s" % [provs.size(), "s" if provs.size() > 1 else "", lst] if winner == ME else "You cede %d province%s: %s" % [provs.size(), "s" if provs.size() > 1 else "", lst] if loser == ME else "The %s takes %d province%s" % [Wn, provs.size(), "s" if provs.size() > 1 else ""])
		"surrender":
			var provs := connected_pick(winner, loser, max_take(winner))
			for p in provs:
				transfer_prov(p, winner)
			war_lock[loser] = t + W("surrenderLock")
			lines.append("The war ends in surrender: %d province%s change hands" % [provs.size(), "" if provs.size() == 1 else "s"])
		_:
			lines.append("White peace: no one gains anything")
	# v78: the war's result for the log
	for r in war_log:
		if r.id == w.id and r.end == null:
			var K := {"gold": "gold", "provs": "provinces", "surrender": "surrender"}
			r.result_pending = "White peace" if terms.kind == "white" or not K.has(terms.kind) else ("Victory · " if winner == ME else "Defeat · ") + K[terms.kind]
	end_war(w)
	if annexed:
		kill_nation(annexed, winner)
	evict_armies()
	compute_income()
	compute_fog()
	if fell:
		game_over(winner)
		return
	if me:
		sfx("war_peace")
		toast("Peace with the %s! %s. Truce for %d minutes." % [player_info(foe_of(w, ME)).name, ". ".join(lines), W("truce") / 60])
	elif knows(winner) or knows(loser):
		news("The %s and the %s made peace. %s." % [Wn, player_info(loser).name, ". ".join(lines)])


func kill_nation(o: int, by: int) -> void:
	if not nations.has(o) or not nations[o].alive:
		return
	nations[o].alive = false
	for v in units:
		if v.owner == o:
			Quests.unit_lost(self, v)
	units = units.filter(func(v): return v.owner != o)
	for w in wars_of(o):
		end_war(w)
	allies = allies.filter(func(A): return A.a != o and A.b != o)
	for p in provs_of(o):
		if by:
			transfer_prov(p, by)
		else:
			Quests.extras_lost(self, p, extras_in(p))
			buildings.erase(p)
			extras.erase(p)
	if knows(o):
		toast("The %s is no more%s." % [player_info(o).name, (": its land now belongs to %s" % the_name(by)) if by and by != o else ""])


func game_over(winner: int) -> void:
	fallen = true
	for v in units:
		if v.owner == ME:
			Quests.unit_lost(self, v)
	units = units.filter(func(v): return v.owner != ME)
	for w in wars_of(ME):
		end_war(w)
	allies = allies.filter(func(A): return A.a != ME and A.b != ME)
	if on_game_over.is_valid() and ME == view_seat:
		on_game_over.call(winner)


# --- a computer nation's demands to the player ---
func check_ai_demands(now: float) -> void:
	if demand != null or fallen:
		return
	for w in wars_of(ME):
		var s := warscore(w, ME)
		if s <= -W("provs") and now >= w.demandAt:
			w.demandAt = now + 60
			ai_demand(w)
			return


func ai_demand(w: Dictionary) -> void:
	var foe := foe_of(w, ME)
	var sc := -warscore(w, ME)
	var mine: Array = provs_of(ME) if sc >= W("total") and annexable(foe, ME) and provs_of(ME).size() <= demand_max(sc, foe) else connected_pick(foe, ME, demand_max(sc, foe))
	var terms := {"kind": "provs", "provs": mine} if not mine.is_empty() else {"kind": "gold"}
	demand = terms.duplicate()
	demand.war = w.id
	demand.from = foe
	var what: String = "%d of your provinces: %s" % [mine.size(), ", ".join(mine.map(func(p): return prov_name(p)))] if not mine.is_empty() else "%d gold" % mini(W("goldTerm"), int(stock.gold))
	toast("The %s demands peace." % player_info(foe).name, true)
	if on_dialog.is_valid() and ME == view_seat:
		on_dialog.call("The %s demands peace" % player_info(foe).name, "They are winning the war and demand peace. They want %s." % what,
			[{"id": "yes", "label": "Accept", "why": null}, {"id": "no", "label": "Refuse", "why": null}], func(id): do("answer_demand", [id == "yes"]))


func answer_demand(yes: bool) -> void:
	var d = demand
	if d == null:
		return
	var w = null
	for x in wars:
		if x.id == d.war:
			w = x
	demand = null
	if yes and w != null:
		make_peace(w, d.from, d)
	elif w != null:
		toast("You refused. The war goes on.")


# --- alliances (v105 rules, v106 for the player) ---
func ally_why(a: int, b: int) -> String:
	if (a == ME or b == ME) and alive_nation(a) and alive_nation(b) and a != b:
		var o := b if a == ME else a
		if allied(a, b):
			return "Already allies"
		if treaty_count(o) >= 1:
			return "They already have an ally"
		if at_war(a, b):
			return "You are at war"
		if truce_left(a, b) > 0:
			return "Truce: %s left" % fmt_time(truce_left(a, b))
		if nations.has(o) and nations[o].get("rival") == ME:
			return "They see you as their rival"
		if enemy_of(o) == ME or enemy_of(ME) == o:
			return "One of you proclaims the other an enemy"
		if opinion(o, ME) < DIPL.ally:
			return "Their opinion of you is %d (needs +%d)" % [opinion(o, ME), DIPL.ally]
		return ""
	if a != b and not has_met(a, b):
		return "They haven’t met each other"
	if not alive_nation(a) or not alive_nation(b) or a == b:
		return "Not possible"
	if allied(a, b):
		return "Already allies"
	if treaty_count(a) >= 1 or treaty_count(b) >= 1:
		return "They already have an ally"
	if at_war(a, b):
		return "You are at war"
	if truce_left(a, b) > 0:
		return "Truce"
	if (nations.has(a) and nations[a].get("rival") == b) or (nations.has(b) and nations[b].get("rival") == a):
		return "They are rivals"
	for xy in [[a, b], [b, a]]:
		if nations.has(xy[0]) and opinion(xy[0], xy[1]) < DIPL.ally:
			return "Their opinion is too low"
	if enemy_of(a) == b or enemy_of(b) == a:
		return "They proclaim each other enemies"
	return ""


func border_sets() -> Dictionary:
	var B := {}
	for p in buildings:
		var o: int = buildings[p].owner
		if not is_nation(o):
			continue
		for q in all_nbr[p]:
			if buildings.has(q) and buildings[q].owner != o and is_nation(buildings[q].owner):
				if not B.has(o):
					B[o] = {}
				B[o][buildings[q].owner] = true
	return B


func nation_sizes() -> Dictionary:
	var n := {}
	for p in buildings:
		n[buildings[p].owner] = n.get(buildings[p].owner, 0) + 1
	return n


func common_threat(a: int, b: int, B: Dictionary, N: Dictionary) -> int:
	var best := 0
	for c in live_nations():
		if c == a or c == b:
			continue
		var bc = B.get(c)
		if bc == null or not bc.has(a) or not bc.has(b):
			continue
		var n: int = N.get(c, 0)
		if n < 1.25 * N.get(a, 0) or n < 1.25 * N.get(b, 0):
			continue
		if not best or n > N.get(best, 0):
			best = c
	return best


func form_alliance(a: int, b: int, vs: int) -> void:
	allies.append({"a": a, "b": b, "vs": vs, "since": t})
	var against := " against the %s" % player_info(vs).name if vs else ""
	if a == ME or b == ME:
		var o := b if a == ME else a
		met[o] = true
		sfx("wn_ally")
		toast("You are now allied with the %s%s. If anyone declares war on one of you, the other joins the war." % [player_info(o).name, against])
		# v99: the player meets everyone his new ally has met, and his ally meets everyone he has
		for x in met.keys():
			if x != o and nations.has(x) and alive_nation(x):
				ai_met[pair_key(o, x)] = true
		for x in ai_ids():
			if x != o and alive_nation(x) and not met.has(x) and ai_met.has(pair_key(o, x)):
				meet_nation(x)
	elif knows(a) or knows(b):
		news("The %s and the %s formed an alliance%s." % [player_info(a).name, player_info(b).name, against])


func end_alliance(A: Dictionary, why: String) -> void:
	allies = allies.filter(func(x): return not is_same(x, A))
	if alive_nation(A.a) and alive_nation(A.b):
		truces[pair_key(A.a, A.b)] = maxf(truces.get(pair_key(A.a, A.b), 0.0), t + W("allyTruce"))
	if A.a == ME or A.b == ME:
		toast("Your alliance with the %s has ended: %s." % [player_info(B_of(A)).name, why])
		if why != "you ended it":
			sfx("war_peace")
	elif knows(A.a) or knows(A.b):
		news("The alliance of the %s and the %s has ended." % [player_info(A.a).name, player_info(A.b).name])


func B_of(A: Dictionary) -> int:
	return A.b if A.a == ME else A.a


func step_ai_met() -> void:
	if t - ai_met_at < 2:
		return
	ai_met_at = t
	for p in buildings:
		var a: int = buildings[p].owner
		if not nations.has(a):
			continue
		for q in all_nbr[p]:
			var o := nation_of(q)
			if o and o != a and o != ME and nations.has(o):
				ai_met[pair_key(a, o)] = true
	for w in wars:
		if w.a != ME and w.b != ME:
			ai_met[pair_key(w.a, w.b)] = true
	for A in allies:
		if A.a != ME and A.b != ME:
			ai_met[pair_key(A.a, A.b)] = true


func step_alliances() -> void:
	step_ai_met()
	var B := border_sets()
	var N := nation_sizes()
	for A in allies.duplicate():
		if not alive_nation(A.a) or not alive_nation(A.b):
			end_alliance(A, "an ally fell")
	var live := live_nations()
	for a in live:
		for b in live:
			if a >= b or ally_why(a, b) != "":
				continue
			var vs := common_threat(a, b, B, N)
			if not vs:
				continue
			if a == ME or b == ME:
				var o: int = b if a == ME else a
				if ally_ask.get(o, 0.0) > t:
					continue
				if offer_alliance(o, vs):
					ally_ask[o] = t + W("allyAskAgain")
				continue
			form_alliance(a, b, vs)


# web: v105.js offerAlliance = dipRequest(from, 'alliance', {vs})
func offer_alliance(from: int, vs: int) -> bool:
	return dip_request(from, "alliance", {"vs": vs}) != null


func answer_alliance(yes: bool) -> void:
	var o = ally_offer
	if o == null:
		return
	ally_offer = null
	if yes and ally_why(ME, o.from) == "":
		form_alliance(ME, o.from, o.vs)
	else:
		ally_ask[o.from] = t + W("allyAskAgain")


# --- meeting nations (web: war.js updateMet / meetNation) ---
func update_met() -> void:
	if not started or fallen or t - met_at < 1:
		return
	met_at = t
	for p in buildings:
		var o: int = buildings[p].owner
		if o != ME and is_nation(o) and not met.has(o) and explored.has(p):
			meet_nation(o)
	for u in units:
		if u.owner == ME and u.kind == WAYFINDER:
			for q in all_nbr[u.prov]:
				var o := nation_of(q)
				if o and o != ME and is_nation(o) and not met.has(o):
					meet_nation(o)


func meet_nation(o: int) -> void:
	if met.has(o):
		return
	met[o] = true
	if ME == view_seat:
		sfx("wn_meet")   # 0.19: a fanfare for a new nation
	if on_dialog.is_valid() and ME == view_seat:
		var N: Dictionary = nations[o] if nations.has(o) else {"diff": "human"}
		var al := allies_of(o)
		dialog_nation = o   # (the pop-up shows their flag and leader)
		on_dialog.call("You have met the %s" % player_info(o).name, "%d province%s · %s%s%s. You can see them now in Diplomacy." % [provs_of(o).size(), "" if provs_of(o).size() == 1 else "s",
			GameData.c("DIFF_NAME").get(N.diff, "Player"), (" · allied with " + the_name(al[0])) if not al.is_empty() else "", " · at war with you" if at_war(ME, o) else ""],
			[{"id": "ok", "label": "OK", "why": null}], Callable())
		dialog_nation = 0


# =================================================================================================================
# the player's diplomatic actions (web: v105.js dxAct and its reasons, v106.js wrappers). Realmlings: Flirt, Gift,
# Bribe, military access (offer / ask / give back), Trade Network, alliance, spies, Proclaim Enemy, declare war.
var gift_vault: int:  # v106: gifted gold over the storage limit, waiting for room
	get: return cur["gift_vault"]
	set(v): cur["gift_vault"] = v

func add_mod(o: int, t2: int, kind: String, v: int, dur: float) -> void:
	dipl_state().mods.append({"o": o, "t": t2, "kind": kind, "v": v, "until": t + dur})


func mod_active(o: int, t2: int, kind: String):
	for m in dipl_state().mods:
		if m.o == o and m.t == t2 and m.kind == kind and m.until > t:
			return m
	return null


func pair_has(list: Array, a: int, b: int):
	for x in list:
		if (x.a == a and x.b == b) or (x.a == b and x.b == a):
			return x
	return null


func sex_of(o: int):
	var L = leader_of(o)
	return L.get("sex") if L != null else null


func fmt_left(sec: float) -> String:
	return "%s left" % fmt_time(maxf(0, sec))


func sgn(v: int) -> String:
	return ("+%d" % v) if v > 0 else str(v)


func flirt_why(o: int) -> String:
	if race_of.get(ME, "realm") != race_of.get(o, "realm"):
		return "Only with a leader of your own race"
	if sex_of(ME) == null or sex_of(o) == null or sex_of(ME) == sex_of(o):
		return "Swampling leaders are all men: no flirting" if is_sw() else "Only with a leader of the opposite sex"
	var m = mod_active(o, ME, "flirt")
	if m != null:
		return "Still charmed: %s" % fmt_left(m.until - t)
	return ""


# web: v105.js growlWhy: Swamplings growl at anyone
func growl_why(o: int) -> String:
	if not is_sw():
		return "Swamplings only"
	var m = mod_active(o, ME, "growl")
	if m != null:
		return "They’re still reeling: %s" % fmt_left(m.until - t)
	return ""


func gift_why(o: int) -> String:
	if race_of.get(ME, "realm") != race_of.get(o, "realm"):
		return "Only to a nation of your own race"
	if stock.gold < DIPL.gift.gold:
		return "Needs %d gold" % DIPL.gift.gold
	return ""


func bloc(o: int) -> int:
	var n := provs_of(o).size()
	for x in allies_of(o):
		n += provs_of(x).size()
	return n


func bribe_why_for(payer: int, x: int, y: int) -> String:
	if y == x or y == payer or not alive_nation(y) or not alive_nation(x):
		return "Not possible"
	if allied(x, y):
		return "They are allies"
	if at_war(x, y):
		return "Already at war"
	if bloc(y) >= bloc(x):
		return "Not smaller than them (with allies)"
	var st := stock_of(x)
	var give := {}
	var dc: Dictionary = W("declareCost")
	for k in dc:
		give[k] = maxi(0, dc[k] - st.get(k, 0))
		st[k] = st.get(k, 0) + give[k]
	var why := declare_why(x, y)
	for k in give:
		st[k] -= give[k]
	return why


func bribe_targets(o: int) -> Array:
	return live_nations().filter(func(y): return y != ME and met.has(y) and bribe_why_for(ME, o, y) == "")


func bribe_why(o: int) -> String:
	if not nations.has(o):
		return "Not possible"
	if dipl_state().decl.get("%d>%d" % [ME, o], 0) > 0:
		return "You have declared war on them"
	if not wars_of(o).is_empty():
		return "They are at war"
	if stock.gold < DIPL.bribe.gold:
		return "Needs %d gold" % DIPL.bribe.gold
	if bribe_targets(o).is_empty():
		return "No smaller nation they could attack"
	return ""


func do_bribe(payer: int, x: int, y: int) -> bool:
	var why := (bribe_why(x) if bribe_why(x) != "" else bribe_why_for(ME, x, y)) if payer == ME else bribe_why_for(payer, x, y)
	if why != "":
		if payer == ME:
			toast("Can’t bribe: %s." % (why[0].to_lower() + why.substr(1)), true)
		return false
	stock_of(payer).gold -= DIPL.bribe.gold
	var st := stock_of(x)
	var dc: Dictionary = W("declareCost")
	for k in dc:
		st[k] = st.get(k, 0) + dc[k]   # the bribe pays their war fee
	var w = declare_war(x, y)
	if payer == ME:
		toast(("The %s took your %d gold and declared war on the %s." % [player_info(x).name, DIPL.bribe.gold, player_info(y).name]) if w else "The bribe fell through.", not w)
		sfx("war_declare")
	return w != null and w != false


func grant_why(o: int) -> String:
	if access_given(ME, o):
		return ""
	if allied(ME, o):
		return "Allies already have access"
	if at_war(ME, o):
		return "You are at war"
	if opinion(o, ME) < DIPL.offer:
		return "They refuse: their opinion of you is %s (needs %d or better)" % [sgn(opinion(o, ME)), DIPL.offer]
	return ""


func ask_why(o: int) -> String:
	if access_given(o, ME):
		return "They already let you through"
	if allied(ME, o):
		return "Allies already have access"
	if at_war(ME, o):
		return "You are at war"
	if opinion(o, ME) <= 0:
		return "Their opinion of you is %s (needs to be positive)" % sgn(opinion(o, ME))
	return ""


# --- Request Share Contacts (0.19) ---

## The living nations o has met (a human nation: its own list; a computer nation: whom it has met).
func contacts_of(o: int) -> Array:
	var out := []
	for x0 in nations.keys() + seats.keys():
		var x := int(x0)
		if x == o or not alive_nation(x) or out.has(x):
			continue
		var k := false
		if seats.has(o):
			k = seats[o].met.has(x) or seats[o].met.has(str(x))
		elif seats.has(x):
			k = seats[x].met.has(o) or seats[x].met.has(str(o))
		else:
			k = ai_met.has(pair_key(o, x))
		if k:
			out.append(x)
	return out


## The nations human nation `to` would meet if o shared its contacts with them.
func contacts_new_for(to: int, o := ME) -> Array:
	if not seats.has(to):
		return []
	var S: Dictionary = seats[to]
	return contacts_of(o).filter(func(x): return x != to and not S.met.has(x) and not S.met.has(str(x)))


## o shares its contacts with human nation `to`: to meets them all (quietly: one message, not a pop-up each).
## Returns the nations met.
func share_contacts(o: int, to: int) -> Array:
	var got := contacts_new_for(to, o)
	for x in got:
		seats[to].met[x] = true
	if not got.is_empty() and to == view_seat:
		sfx("wn_meet")
	return got


## Why a computer nation won't share its contacts ("" when it will): it must like you and not be at war with you.
func share_why(o: int) -> String:
	if at_war(ME, o):
		return "You are at war"
	if contacts_new_for(ME, o).is_empty():
		return "They know no nation you haven't met"
	if opinion(o, ME) <= 0:
		return "Their opinion of you is %s (needs to be positive)" % sgn(opinion(o, ME))
	return ""


func trade_why(a: int, b: int) -> String:
	if is_sw(a) or is_sw(b):   # web: v105.js tradeRaces
		return "Only Woodlings and Realmlings form Trade Networks"
	if pair_has(dipl_state().trade, a, b) != null:
		return "Already trading"
	if at_war(a, b):
		return "You are at war"
	if not nations_border(a, b):
		return "Needs a shared border"
	for xy in [[a, b], [b, a]]:
		if nations.has(xy[0]) and opinion(xy[0], xy[1]) < DIPL.trade:
			return "Their opinion of you is %s (needs +%d)" % [sgn(opinion(xy[0], xy[1])), DIPL.trade]
	return ""


# web: v105.js crimeWhy / crimeSlots: Organized Crime, between two Swampling nations: +1 Thug in every Thug Den
func crime_why(a: int, b: int) -> String:
	if not is_sw(a) or not is_sw(b):
		return "Only between two Swampling nations"
	if pair_has(dipl_state().crime, a, b) != null:
		return "Already in business"
	if at_war(a, b):
		return "You are at war"
	for xy in [[a, b], [b, a]]:
		if nations.has(xy[0]) and opinion(xy[0], xy[1]) < DIPL.crime:
			return "Their opinion of you is %s (needs +%d)" % [sgn(opinion(xy[0], xy[1])), DIPL.crime]
	return ""


func crime_slots(o: int) -> int:
	if dipl.is_empty() or not dipl.has("crime"):
		return 0
	return dipl.crime.filter(func(c): return c.a == o or c.b == o).size()


# web: v105.js ejectThugs: after a crime agreement ends, Thugs beyond a den's room step out
func eject_thugs() -> void:
	var n := 0
	for p in extras:
		if not owned(p):
			continue
		for e in extras[p]:
			while e.type == "market" and int(e.get("thugs", 0)) > den_cap(ME):
				e.thugs -= 1
				var u := mk_unit(next_id, THUG, "Thug", p, 0)
				next_id += 1
				u.slot = free_slot(p, u)
				var xy := slot_pos(p, u.slot)
				u.x = xy[0]
				u.y = xy[1]
				u.born = t
				units.append(u)
				n += 1
	if n:
		compute_income()
		toast("%d Thug%s stepped out of the Thug Dens: there is no longer room for them." % [n, "s" if n > 1 else ""])


func trade_count(o: int) -> int:
	return dipl_state().trade.filter(func(c): return c.a == o or c.b == o).size()


func form_pact(kind: String, a: int, b: int) -> void:
	var D := dipl_state()
	D[kind].append({"a": a, "b": b, "since": t})
	var o := b if a == ME else a if b == ME else 0
	var what := "a Trade Network" if kind == "trade" else "an Organized Crime Agreement"
	if o:
		sfx("wn_ally")
		toast("You and the %s formed %s. %s" % [player_info(o).name, what, "Community and Trade Routes give both of you 10% more gold." if kind == "trade" else "Every Thug Den of both nations holds one more Thug."])
	elif knows(a) or knows(b):
		toast("The %s and the %s formed %s." % [player_info(a).name, player_info(b).name, what])
	compute_income()


func end_pact(kind: String, P: Dictionary, why := "") -> void:
	var D := dipl_state()
	D[kind] = D[kind].filter(func(x): return not is_same(x, P))
	var o: int = P.b if P.a == ME else P.a if P.b == ME else 0
	if kind == "crime":
		if not D.has("crimeEnd"):
			D.crimeEnd = []
		D.crimeEnd.append({"at": t + 10.0, "a": P.a, "b": P.b})   # web: DIPL.crimeOut
	if o:
		toast("Your %s with the %s has ended%s.%s" % ["Trade Network" if kind == "trade" else "Organized Crime Agreement", player_info(o).name, (": " + why) if why != "" else "",
			" Thugs over the limit leave their dens in 10 seconds." if kind == "crime" and is_sw() else ""], why != "you ended it")
	compute_income()


func spy_why(o: int) -> String:
	var D := dipl_state()
	if D.spies.has(o):
		return "Spying: %s" % fmt_left(D.spies[o].until - t)
	if D.spyLock.get(o, 0.0) > t:
		return "Your spies were caught: %s" % fmt_left(D.spyLock[o] - t)
	if stock.gold < DIPL.spy.gold:
		return "Needs %d gold" % DIPL.spy.gold
	return ""


func finish_spy(o: int) -> void:
	var D := dipl_state()
	D.spies.erase(o)
	if not alive_nation(o):
		return
	if not D.intel.has(o):
		D.intel[o] = {}
	var I: Dictionary = D.intel[o]
	var nm: String = player_info(o).name
	if js_rand.call() < DIPL.spy.fail:
		add_mod(o, ME, "spy", DIPL.spy.cost, DIPL.spy.lock)
		D.spyLock[o] = t + DIPL.spy.lock
		toast("Your spies were caught by the %s! Their opinion of you drops by %d for %d minutes, and you can’t spy on them for as long." % [nm, -DIPL.spy.cost, DIPL.spy.lock / 60], true)
		return
	var r: float = js_rand.call()
	if r < DIPL.spy.provs:
		var own := provs_of(o)
		var hidden := own.filter(func(p): return not explored.has(p))
		var pool: Array = dx_shuffle(hidden if not hidden.is_empty() else own).slice(0, DIPL.spy.show)
		for p in pool:
			known[p] = true
		I.provs = pool
		I.provsT = t
		compute_fog()
		toast("Your spies mapped %d province%s of the %s: %s." % [pool.size(), "" if pool.size() == 1 else "s", nm, ", ".join(pool.map(func(p): return prov_name(p)))])
	elif r < DIPL.spy.provs + DIPL.spy.power:
		I.power = Ai.nation_power(self, o)
		I.powerT = t
		toast("Your spies counted the %s’s armies: total power %d." % [nm, I.power])
	else:
		toast("Your spies came back from the %s with nothing useful." % nm)


## web: v105.js dxAct + v106.js: the player's request to a computer nation
func dx_act(act: String, o: int, arg := -1) -> void:
	if seats.has(o) and o != ME and not act in ["proclaim", "declare", "giveback"]:   # another player (step 11)
		_dx_player(act, o)
		return
	var D := dipl_state()
	var nm: String = player_info(o).name if is_nation(o) else ""
	var why := ""
	match act:
		"growl":   # web: v105.js dxAct 'growl' + v106.js (a nation that isn't Swampling always takes it badly)
			why = growl_why(o)
			if why == "":
				var N: String = player_info(o).name
				if not is_sw(o):
					add_mod(o, ME, "growl", -DIPL.growl.v, DIPL.growl.dur)
					toast("The %s aren’t Swamplings: they took that growl as a threat (−%d opinion for %d minutes)." % [N, DIPL.growl.v, DIPL.growl.dur / 60], true)
				else:
					var up: bool = js_rand.call() < 0.5
					add_mod(o, ME, "growl", DIPL.growl.v if up else -DIPL.growl.v, DIPL.growl.dur)
					toast(("The %s liked that growl: +%d opinion for %d minutes." if up else "The %s took that growl badly: −%d opinion for %d minutes.") % [N, DIPL.growl.v, DIPL.growl.dur / 60], not up)
				sfx("ui_click")
		"flirt":
			why = flirt_why(o)
			if why == "":
				add_mod(o, ME, "flirt", DIPL.flirt.v, DIPL.flirt.dur)
				toast("%s blushes: +%d opinion for %d minutes." % [leader_of(o).full, DIPL.flirt.v, DIPL.flirt.dur / 60])
		"gift":
			why = gift_why(o)
			if why == "":
				stock.gold -= DIPL.gift.gold
				var N: Dictionary = nations[o]
				N.stock.gold += DIPL.gift.gold
				add_mod(o, ME, "gift", DIPL.gift.v, DIPL.gift.dur)
				toast("You sent the %s %d gold: +%d opinion for %d minutes." % [nm, DIPL.gift.gold, DIPL.gift.v, DIPL.gift.dur / 60])
				var over: int = N.stock.gold - Ai.storage(self, N, "gold")   # v106: over the limit it waits in a vault
				if over > 0:
					N.stock.gold -= over
					N.giftVault = N.get("giftVault", 0) + over
		"bribe":
			do_bribe(ME, o, arg)
			return
		"grant":
			if access_given(ME, o):
				end_access(ME, o, "you revoked it")
				return
			why = grant_why(o)
			if why == "":
				D.access.append({"from": ME, "to": o})
				toast("The %s accepts your offer: their armies may now march through your land. You can revoke it at any time." % nm)
		"share":   # 0.19: Request Share Contacts: a nation that likes you shows you every nation it knows
			why = share_why(o)
			if why == "":
				var got := share_contacts(o, ME)
				toast("The %s share their contacts: you have met %s." % [nm, ", ".join(got.map(func(x): return the_name(x)))])
		"ask":
			why = ask_why(o)
			if why == "":
				D.access.append({"from": o, "to": ME})
				sfx("wn_ally")
				toast("The %s grants you military access: your armies may march through their land." % nm)
		"giveback":
			end_access(o, ME, "you gave it back")
			return
		"ally":
			if allied(ME, o):
				for A in allies:
					if (A.a == ME and A.b == o) or (A.b == ME and A.a == o):
						end_alliance(A, "you ended it")
						return
			why = ally_why(ME, o)
			if why == "":
				form_alliance(ME, o, 0)
		"trade", "crime":
			var P = pair_has(D[act], ME, o)
			if P != null:
				end_pact(act, P, "you ended it")
				return
			why = trade_why(ME, o) if act == "trade" else crime_why(ME, o)
			if why == "":
				form_pact(act, ME, o)
		"spy":
			why = spy_why(o)
			if why == "":
				stock.gold -= DIPL.spy.gold
				D.spies[o] = {"t0": t, "until": t + DIPL.spy.dur}
				toast("Spies sent into the %s. They report back in %d minutes." % [nm, DIPL.spy.dur / 60])
		"proclaim":
			if enemy_of(ME) == o:
				renounce_enemy(ME)
				return
			why = proclaim_why(ME, o)
			if why == "":
				proclaim_enemy(ME, o)
		"declare":
			declare_war(ME, o)
			return
	if why != "":
		toast(why, true)


# --- requests from computer nations (web: v105.js dipRequest / answerRequest / stepRequests): 30 s, then declined ---
const REQ_NAME := {"flirt": "Flirting", "gift": "Gift", "access": "Access request", "alliance": "Alliance offer", "trade": "Trade Network", "crime": "Organized Crime",
	"h_access": "Access request", "h_ally": "Alliance offer", "h_trade": "Trade Network", "h_crime": "Organized Crime", "barter": "Barter", "h_peace": "Peace offer", "h_share": "Contacts request"}

func req_text(r: Dictionary) -> Array:
	var o: int = r.from
	match r.kind:
		"h_access":
			return ["They ask for military access: their armies would march through your land (you can revoke it at any time).", "Grant", "Refuse"]
		"h_ally":
			return ["They propose an alliance: if anyone declares war on one of you, the other joins (a Proxy War).", "Ally", "Decline"]
		"h_trade":
			return ["They propose a Trade Network: Community and Trade Routes give both nations 10% more gold.", "Agree", "Decline"]
		"h_crime":
			return ["They propose an Organized Crime Agreement: every Thug Den of both nations holds one more Thug.", "Agree", "Decline"]
		"h_share":   # 0.19
			var n := contacts_new_for(o).size()
			return ["They ask you to share your contacts: they would meet the %d nation%s you know that they haven't met." % [n, "" if n == 1 else "s"], "Share", "Refuse"]
		"h_peace":
			return ["They offer a white peace: the war ends, no one gains anything, and a truce follows.", "Make peace", "Fight on"]
		"barter":
			return ["They offer %s for %s." % [res_text(r.data.give), res_text(r.data.want)], "Accept", "Decline"]
		"flirt":
			return ["%s is flirting with you." % (leader_of(o).full if leader_of(o) != null else "Their leader"), "Flirt back", "Ignore"]
		"gift":
			return ["They offer you a gift of %d gold." % r.data.gold, "Accept", "Refuse"]
		"access":
			return ["They ask for military access: their armies would march through your land (you can revoke it at any time).", "Grant", "Refuse"]
		"alliance":
			var vs = r.data.get("vs", 0)
			return ["They propose an alliance%s: if anyone declares war on one of you, the other joins (a Proxy War)." % ((" against the " + player_info(vs).name) if vs else ""), "Ally", "Decline"]
		"trade":
			return ["They propose a Trade Network: Community and Trade Routes give both nations 10% more gold.", "Agree", "Decline"]
		"crime":
			return ["They propose an Organized Crime Agreement: every Thug Den of both nations holds one more Thug.", "Agree", "Decline"]
	return ["", "Yes", "No"]


func dip_request(from: int, kind: String, data := {}):
	var D := dipl_state()
	if not is_nation(from) or not alive_nation(from) or fallen or D.reqs.any(func(r): return r.from == from and r.kind == kind):
		return null
	var r := {"id": D.seq, "from": from, "kind": kind, "data": data, "t": t, "until": t + DIPL.reqTime, "min": false}
	D.seq += 1
	D.reqs.append(r)
	sfx("wn_ally")
	met[from] = true
	return r


func answer_request(r: Dictionary, yes: bool, quiet := false) -> void:
	var D := dipl_state()
	D.reqs = D.reqs.filter(func(x): return not is_same(x, r))
	if seats.has(r.from):   # (from another player: multiplayer step 11)
		_answer_player(r, yes, quiet)
		return
	var o: int = r.from
	var nm: String = player_info(o).name
	if not alive_nation(o):
		return
	if not yes:
		toast(("No answer to the %s’s %s: declined." if quiet else "You declined the %s’s %s.") % [nm, REQ_NAME[r.kind].to_lower()])
		return
	match r.kind:
		"flirt":
			if mod_active(o, ME, "flirt") == null:
				add_mod(o, ME, "flirt", DIPL.flirt.v, DIPL.flirt.dur)
			toast("You flirt back: the %s likes you more (+%d for %d minutes)." % [nm, DIPL.flirt.v, DIPL.flirt.dur / 60])
		"gift":
			var st: Dictionary = nations[o].stock
			var g := mini(r.data.gold, floori(st.gold))
			st.gold -= g
			var had: int = stock.gold
			stock.gold += g
			toast("You accepted %d gold from the %s." % [g, nm])
			var room: int = storage_cap("gold") - had   # v106: over your storage it waits in your treasury
			if g > room and room >= 0:
				gift_vault += g - room
				stock.gold = had + room
				toast("The gift is in your treasury: %d gold waits for room in your stores." % (g - room))
		"access":
			if at_war(ME, o):
				toast("Not while you are at war.", true)
				return
			if not access_given(ME, o):
				D.access.append({"from": ME, "to": o})
			toast("The %s may now march through your land." % nm)
		"alliance":
			var why := ally_why(ME, o)
			if why != "":
				toast("The alliance is no longer possible: %s." % (why[0].to_lower() + why.substr(1)), true)
				return
			form_alliance(ME, o, r.data.get("vs", 0))
		"trade", "crime":
			var why := trade_why(ME, o) if r.kind == "trade" else crime_why(ME, o)
			if why != "":
				toast("No longer possible: %s." % (why[0].to_lower() + why.substr(1)), true)
				return
			form_pact(r.kind, ME, o)


func step_requests() -> void:
	for r in dipl_state().reqs.duplicate():
		if t >= r.until or not alive_nation(r.from):
			answer_request(r, false, true)


# web: v105.js newsAdd: wars starting and ending between nations you know (the six latest)
func news_add(kind: String, a: int, b: int) -> void:
	var D := dipl_state()
	D.news.append({"id": D.seq, "kind": kind, "a": a, "b": b, "t": t})
	D.seq += 1
	if D.news.size() > 6:
		D.news = D.news.slice(D.news.size() - 6)


# web: v106.js stepGiftVaults: vaulted gift gold moves into storage as room opens
func step_gift_vaults() -> void:
	for id in nations:
		var N: Dictionary = nations[id]
		if N.get("giftVault", 0) > 0 and N.alive:
			var room := maxi(0, Ai.storage(self, N, "gold") - N.stock.gold)
			var m := mini(room, N.giftVault)
			N.stock.gold += m
			N.giftVault -= m
	if gift_vault > 0:
		var room := maxi(0, storage_cap("gold") - stock.gold)
		var m := mini(room, gift_vault)
		stock.gold += m
		gift_vault -= m


# --- every half second (web: v105.js stepDiplomacy) ---
var dx_step_t: float:
	get: return cur["dx_step_t"]
	set(v): cur["dx_step_t"] = v

func step_diplomacy() -> void:
	if not started or fallen:
		return
	var D := dipl_state()
	if not paused:
		step_requests()
	if t - dx_step_t < 0.5 and t >= dx_step_t:
		return
	dx_step_t = t
	D.mods = D.mods.filter(func(m): return m.until > t)
	for o in D.spies.keys():
		if not alive_nation(o):
			D.spies.erase(o)
		elif t >= D.spies[o].until:
			finish_spy(o)
	for A in allies.duplicate():
		for xy in [[A.a, A.b], [A.b, A.a]]:
			if nations.has(xy[0]) and alive_nation(xy[0]) and alive_nation(xy[1]) and opinion(xy[0], xy[1]) < 0 and allies.has(A):
				end_alliance(A, "the %s’s opinion of you fell below zero" % player_info(xy[0]).name if xy[1] == ME else "opinion fell below zero")
	for kind in ["trade", "crime"]:
		for P in D[kind].duplicate():
			var why := ""
			if not alive_nation(P.a) or not alive_nation(P.b):
				why = "a nation fell"
			elif at_war(P.a, P.b):
				why = "war"
			elif kind == "trade" and not nations_border(P.a, P.b):
				why = "you no longer share a border"
			else:
				for xy in [[P.a, P.b], [P.b, P.a]]:
					if nations.has(xy[0]) and opinion(xy[0], xy[1]) < 0:
						why = "opinion fell below zero"
			if why != "":
				end_pact(kind, P, why)
	D.access = D.access.filter(func(g): return alive_nation(g.from) and alive_nation(g.to) and not at_war(g.from, g.to))
	var ce: Array = D.get("crimeEnd", [])   # Thugs leave the dens 10 s after a crime agreement ends
	if not ce.is_empty():
		var due := ce.filter(func(c): return t >= c.at)
		if not due.is_empty():
			D.crimeEnd = ce.filter(func(c): return t < c.at)
			if due.any(func(c): return c.a == ME or c.b == ME):
				eject_thugs()
	D.news = D.news.filter(func(n): return is_nation(n.a) and is_nation(n.b))



# =================================================================================================================
# the computer players (web: ai.js stepAI and its wrappers): the rules are in ai.gd (class Ai)
var ally_check := 0.0
var ai_frozen := false          # tests: the brains are off (alliances are still checked), like the web fixtures' frozen stepAI
var ai_war_plans := {}          # web: v100.js aiWarPlans (kept off the save)
var v104_cache := {"k": -1}
var crop_scan_at := 0.0
var wilds_t := -1
var wilds = null
var ai_scout_t := -9.0
const DIPL_ENEMY_EVERY := 600.0
const DIPL_ENEMY := -300
const DIPL_SHARED := 50
const DIPL_ACCESS_OP := 25
const DIPL_TRADE_OP := 25

func step_ai(now: float) -> void:
	if not started:
		return
	if ai_frozen:
		if now >= ally_check:
			ally_check = now + 5
			step_alliances()
		return
	Ai.step(self, now)


func ai_note_defeat(a: Dictionary, b) -> void:
	Ai.note_defeat(self, a, b)


func ai_on_transfer(p: int, from: int, to: int) -> void:
	Ai.on_transfer(self, p, from, to)


# --- v106 Proclaim Enemy ---
func enemy_state() -> Dictionary:
	var D := dipl_state()
	if not D.has("enemy"):
		D.enemy = {}
	if not D.has("enemyAt"):
		D.enemyAt = {}
	return D


func proclaim_why(o: int, t2: int) -> String:
	var D := enemy_state()
	if o == t2 or not alive_nation(t2):
		return "Not possible"
	if enemy_of(o) == t2:
		return ""
	if enemy_of(o):
		return "%s the %s (renounce first)" % ["You already proclaim" if o == ME else "They already proclaim", player_info(enemy_of(o)).name]
	if allied(o, t2):
		return "Not your ally"
	var left: float = D.enemyAt.get(o, -1e9) + DIPL_ENEMY_EVERY - t
	if left > 0:
		return "One proclamation every %d minutes: %s left" % [int(DIPL_ENEMY_EVERY / 60), fmt_time(left)]
	return ""


func proclaim_enemy(o: int, t2: int) -> void:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		in_seat(o, func(): proclaim_enemy(o, t2))
		return
	var D := enemy_state()
	D.enemy[o] = {"t": t2, "since": t}
	D.enemyAt[o] = t
	if seats.size() > 1:   # multiplayer: every player who has met them hears of it
		for h in seat_ids():
			if h != o and (seats[h].met.has(o) or h == t2):
				notify(h, "enemy", o, "The %s proclaim %s their enemy!" % [player_info(o).name, "you" if h == t2 else "the " + player_info(t2).name], h == t2)
	if o == ME:
		sfx("war_declare", -1, 0.5)
		toast("You proclaim the %s your enemy: %d opinion with them for as long as it stands. Nations with the same enemy like you more (+%d)." % [player_info(t2).name, DIPL_ENEMY, DIPL_SHARED])
	elif t2 == ME:
		sfx("wn_enemy")
		toast("The %s proclaimed you their enemy!" % player_info(o).name, true)


func renounce_enemy(o: int) -> void:
	if o != ME and seats.has(o):   # another human nation: the same, with its own fields
		in_seat(o, func(): renounce_enemy(o))
		return
	var D := enemy_state()
	var r = D.enemy.get(o)
	if r == null:
		return
	D.enemy.erase(o)
	if o == ME:
		toast("You renounce your proclamation against the %s." % player_info(r.t).name)
	elif r.t == ME:
		toast("The %s no longer proclaims you their enemy." % player_info(o).name)


# --- notification flags: what the flag bar asks of the rules (read only, except the two dismissals) ---

# web: game.js unitStatus(u)
func unit_status(u: Dictionary) -> String:
	if u.get("stealth", false) and u.moving:
		return "sneaking"
	if u.get("scouting") != null:
		return "scouting"
	if u.get("survey") != null:
		return "surveying"
	if u.get("build") != null:
		return "building"
	if u.get("dig") != null:
		return "digging"
	if u.get("pending") != null:
		return "going to build"
	if not u.get("surveyQueue", []).is_empty():
		return "to survey"
	if u.moving:
		return "walking"
	return "idle"


# web: game.js nearestMason(): your closest Mason with no building job who can walk to p, or null
func nearest_mason(p: int):
	var best = null
	var bd := INF
	for u in units:
		if u.kind != MASON or u.owner != ME or u.build != null or u.get("pending") != null:
			continue
		var hops = find_path(u, p)
		if hops == null:
			continue
		var d: float = Vector2(u.x - G.provs[p].ic[0], u.y - G.provs[p].ic[1]).length() * 0.01 + hops.size()
		if d < bd:
			bd = d
			best = u
	return best


# web: v106.js outpostBtnWhy(): why the province menu's Build Outpost can't send a Mason ("" when it can)
func outpost_btn_why(p: int) -> String:
	if buildings.has(p):
		return "Already has a settlement"
	if over_limit() > 0 or provs_of(ME).size() >= prov_limit():
		return "Province limit reached (%d/%d)" % [provs_of(ME).size(), prov_limit()]
	if units.any(func(u): return u.owner == ME and ((u.build != null and u.build.type == "outpost" and u.build.prov == p) or (u.get("pending") != null and u.pending.type == "outpost" and u.pending.prov == p))):
		return "A Mason is already on it"
	if nearest_mason(p) == null:
		return "No free %s" % unit_defs[MASON].name
	var why = build_check(p, "outpost")
	return "" if why == null else str(why)


# web: flags.js freeMasons(): a Mason with nothing to do
func free_masons() -> Array:
	return units.filter(func(u): return u.kind == MASON and u.owner == ME and not u.get("exiting", false) and unit_status(u) == "idle")


# web: v102.js openPlots(): your provinces with an open plot you can afford to build on, while a Mason is free
func open_plots() -> Array:
	if free_masons().is_empty():
		return []
	var order: Array = BUILD_ORDER
	return provs_of(ME).filter(func(p): return used_slots(p).size() < plot_cap(p) and order.any(func(type): return BUILD_DEFS.has(type) and build_check(p, type) == null))


# web: v102.js allUpgradable(): outposts that can become forts, Forges and Mage Towers you can afford to raise a level
func all_upgradable() -> Array:
	var out := []
	for p in provs_of(ME):
		if buildings[p].stage == 0 and upgrade_why(p) == null:
			out.append({"p": p, "part": "settlement"})
		for e in extras_in(p):
			var d: Dictionary = BUILD_DEFS[e.type]
			var lv: int = e.get("level", 1)
			if not d.has("levels") or lv >= d.levels.size() or xup.has("%d@%d" % [p, e.slot]):
				continue
			if xup_why(p, e) == null:
				out.append({"p": p, "part": "%s@%d" % [e.type, e.slot]})
	return out


# web: v98.js readyCaster(k, mana): a caster who could cast this economic spell now
func ready_caster(k: String, need_mana: bool):
	for c in units:
		if c.owner == ME and is_caster(c) and c.get("cast") == null and c.get("battle") == null and not c.get("quake") and not c.get("exiting", false) \
				and (not need_mana or mana_of(c) >= 25) and cast_why(c, k) == null:
			return c
	return null


# web: flags.js / v105.js the flags' right-click: an earthquake's or a news item's flag goes away for good
func dismiss_quake(id: int) -> void:
	quakes = quakes.filter(func(q): return q.id != id)


func dismiss_news(id: int) -> void:
	var D := dipl_state()
	D.news = D.news.filter(func(n): return n.id != id)


# --- Settings → Debug (web: swamp.js #dbgReveal, #dbgRes, #dbgTech) ---

func debug_reveal(on: bool) -> void:
	reveal_all = on
	compute_fog()
	toast("Debug: the whole map is revealed." if on else "Debug: the fog is back.")


func debug_resources() -> void:
	debug_cap += 2000
	for k in RES:
		stock[k] += 2000
	compute_income()
	toast("Debug: +2000 gold, wood and food (storage raised by 2000 each to hold it).")


func debug_all_tech() -> void:
	var sc = current_school()
	if sc == null:
		sc = "death" if is_sw() else "life"   # the first of SCHOOLS the race can take
		tech.mag.done.append("school-" + sc)
	var n := 0
	for x in TECHS:
		if x.get("rep") or x.id == "abandon" or not tech_for(x):
			continue
		if x.tree == "mag" and (x.id.begins_with("school-") or (x.get("school") != null and x.school != "*" and x.school != sc)):
			continue
		var st: Dictionary = tech[x.tree]
		if st.done.has(x.id):
			continue
		st.done.append(x.id)
		n += 1
	for tr in tech:
		var st: Dictionary = tech[tr]
		if st.cur != null and st.done.has(st.cur):
			st.cur = null
			st.prog = 0
		st.opts = st.opts.filter(func(id): return not st.done.has(id))
		if st.tier:
			draw_options(tr)
	compute_income()
	clamp_stock()
	debug_tech = true
	toast("Debug: %d technologies researched (Magic school: %s)." % [n, GameData.c("SCHOOLS")[sc].name])


## Settings → Record games turned on or off during a game (web: v102.js #recBtn)
func rec_toggle(v: bool) -> void:
	if nations.is_empty() or tutorial != null:
		return
	if v:
		if not rec.is_empty():
			rec.on = true
		else:
			Recorder.start(self, "turned on at " + fmt_time(t))
		toast("Recording this game.")
	elif not rec.is_empty():
		rec.on = false
		toast("Recording stopped. What was recorded so far is kept.")


# ---------------------------------------------------------------------------------------------------------------
# Swamplings: Thugs and Pyromancy (web: swamp.js thugIntoDen / thugsEnter / stepThugs / thugOut, stepPyromancy;
# v98.js pureFront)

func den_room_in(p: int):
	if not owned(p) or occ.has(p):
		return null
	for e in extras_in(p):
		if e.type == "market" and int(e.get("thugs", 0)) < den_cap(ME):
			return e
	return null


func thug_into_den(p: int) -> bool:
	var e = den_room_in(p)
	if e == null:
		return false
	e.thugs = int(e.get("thugs", 0)) + 1
	return true


## Thugs go into a den: the one they stand in, or they walk to the nearest with room.
func thugs_enter(list: Array) -> void:
	var n := 0
	var sent := 0
	for u in list:
		var e = den_room_in(u.prov)
		if e != null and not u.moving:
			e.thugs = int(e.get("thugs", 0)) + 1
			units.erase(u)
			n += 1
			continue
		var d := hops_list(u.prov, all_nbr)
		var best := -1
		for p in extras:
			if den_room_in(p) != null and (best < 0 or d[p] < d[best]):
				best = p
		if best >= 0 and order(u, best):
			u.denGoal = best
			sent += 1
	if n:
		compute_income()
		toast("%s into the Thug Den." % ("%d Thugs settle" % n if n > 1 else "The Thug settles"))
	if sent:
		toast("%s for the nearest Thug Den with room." % ("%d Thugs head" % sent if sent > 1 else "The Thug heads"))
	if not n and not sent:
		toast("No Thug Den with room. Build another, or research the Thugging technologies.", true)


## A Thug steps out of the den (web: swamp.js thugOut)
func thug_out(p: int, e: Dictionary) -> void:
	if int(e.get("thugs", 0)) <= 0:
		return
	e.thugs -= 1
	var u := mk_unit(next_id, THUG, "Thug", p, 0)
	next_id += 1
	u.slot = free_slot(p, u)
	var xy := slot_pos(p, u.slot)
	u.x = xy[0]
	u.y = xy[1]
	u.born = t
	units.append(u)
	compute_income()
	toast("A Thug steps out of the den.")


# web: v105.js (Phlyo raises Sacred Pyres without wood)
func sacred_wood() -> int:
	return 0 if leader == "phlyo" else SACRED.wood


func step_pyromancy(now: float) -> void:
	var before := spyres.size()
	spyres = spyres.filter(func(P): return P.until > now)
	if spyres.size() != before:
		compute_fog()
	sacreds = sacreds.filter(func(P): return P.until > now - 20)
	step_elementals(now)
	portal_fx = portal_fx.filter(func(f): return now - f.t0 < 1.5)
	trap_booms = trap_booms.filter(func(f): return now - f.t0 < 2.0)
	var nw := wrocks.size()
	wrocks = wrocks.filter(func(r): return r.until > now)
	if wrocks.size() != nw:
		compute_fog()
	for T in ftraps.duplicate():
		T.ignore = T.ignore.filter(func(id): return units.any(func(v): return v.id == id and v.prov == T.prov))
		var foe = null
		for v in units:
			if v.kind == "army" and v.prov == T.prov and hostile(v.owner, T.owner) and troop_count(v) > 0 and not v.get("retreating", false) and not T.ignore.has(v.id):
				foe = v
				break
		if foe == null:
			continue
		ftraps.erase(T)
		var killed := pure_front(foe, FIRE_DMG[T.lv] * T.get("mult", 1.0))
		trap_booms.append({"x": foe.x, "y": foe.y, "t0": now, "prov": T.prov})
		if T.owner == ME:
			toast("Your fire trap in %s engulfs %s: %d soldier%s burned." % [prov_name(T.prov), foe.get("name", "an enemy army"), killed, "" if killed == 1 else "s"])
		elif foe.owner == ME:
			toast("%s walks into a fire trap in %s: %d soldier%s lost." % [foe.name, prov_name(T.prov), killed, "" if killed == 1 else "s"], true)
	for u in units:
		if u.get("pathFire") != null and u.pathFire.until <= now:
			u.pathFire = null
		if u.kind == THUG and u.get("denGoal") != null and not u.moving and u.prov == u.denGoal:
			u.denGoal = null
			if thug_into_den(u.prov):
				units.erase(u)
				compute_income()
				break


# web: v98.js pureFront: damage that ignores armor, to the front line only
func pure_front(a: Dictionary, dmg: float) -> int:
	var killed := 0
	var front := {}
	for k in a.troops:
		if k != MAGE and a.troops[k] > 0:
			front[k] = a.troops[k]
	while true:
		var ks := front.keys().filter(func(k): return front[k] > 0 and a.troops.get(k, 0) > 0)
		if ks.is_empty():
			break
		var tot := 0.0
		for k in ks:
			tot += front[k]
		var r: float = battle_rand.call() * tot
		var k = ks[0]
		for kk in ks:
			r -= front[kk]
			if r <= 0:
				k = kk
				break
		var hp := hp_of(a, k)
		if dmg < hp * 0.99:
			break
		dmg -= hp
		front[k] -= 1
		a.troops[k] -= 1
		if a.troops[k] <= 0:
			a.troops.erase(k)
		killed += 1
	if troop_count(a) <= 0:
		remove_army(a)
	if a.owner == ME:
		compute_income()
	return killed


# web: wood.js treeNbr / pathNbr: Woodling Scouts slip through closed borders of trees
func tree_nbr(a: int) -> Array:
	var out := []
	for e in world.edges:
		if e.style == "trees" and not e.open and (e.a == a or e.b == a):
			var A: Array = world.vertices[e.v[0]]
			var B: Array = world.vertices[e.v[1]]
			out.append({"q": e.b if e.a == a else e.a, "m": [(A[0] + B[0]) / 2.0, (A[1] + B[1]) / 2.0]})
	return out


# web: wood.js stepElementals: each Grand Elemental sinks back after 2 minutes (the ones that fell are gone already)
func step_elementals(now: float) -> void:
	if gelems.is_empty():
		return
	var owners := {}
	for x in gelems:
		owners[x.owner] = true
	for o in owners:
		var mine := gelems.filter(func(x): return x.owner == o)
		mine.sort_custom(func(x, y): return x.until < y.until)
		var alive := 0
		for u in units:
			if u.owner == o and u.kind == "army":
				alive += int(u.troops.get(GELEM_ID, 0))
		while mine.size() > alive:
			gelems.erase(mine.pop_front())
		for x in mine:
			if x.until > now:
				continue
			gelems.erase(x)
			var best = null
			for u in units:
				if u.owner == o and u.kind == "army" and u.troops.get(GELEM_ID, 0) > 0 and (best == null or u.troops[GELEM_ID] > best.troops[GELEM_ID]):
					best = u
			if best == null:
				continue
			best.troops[GELEM_ID] -= 1
			if best.troops[GELEM_ID] <= 0:
				best.troops.erase(GELEM_ID)
			portal_fx.append({"x": best.x, "y": best.y, "prov": best.prov, "t0": now, "water": true})
			if troop_count(best) <= 0:
				remove_army(best)
			if o == ME:
				compute_income()
				toast("The Grand Elemental in %s sinks back into the earth." % prov_name(best.prov))


# web: wood.js travUnits: who of yours stands with the travelers
func trav_units(B: Dictionary) -> Dictionary:
	var out := {"scout": false, "army": false, "druid": false}
	for u in units:
		if u.owner != ME or u.prov != B.prov:
			continue
		if u.kind == WAYFINDER:
			out.scout = true
		if u.kind == MAGE or (u.kind == "army" and int(u.troops.get(MAGE, 0)) > 0):
			out.druid = true
		if u.kind == "army" and u.get("battle") == null and u.troops.keys().any(func(k): return k != MAGE and u.troops[k] > 0):
			out.army = true
	return out


# =================================================================================================================
# orders (multiplayer step 3): every order a player gives goes through one door, as a small command
# {player, type, args}. Single-player applies it at once; a multiplayer game sends it to every copy, which all apply
# it at the same step. Units, wars, requests and buildings' extras travel as references and are looked up again.

## The orders a player may give: the game's own functions (with the same arguments), plus the few below
## (set_paused, set_auto_tech, rename_prov, close_school_popup).
const COMMANDS := ["order", "order_group", "order_build", "cancel_build", "queue_survey", "queue_survey_on", "train",
	"cancel_training", "purchase_order", "start_upgrade", "cancel_upgrade", "start_xup", "cancel_xup", "start_develop",
	"rebuild_walls", "plan_road", "start_link", "pick_tech", "pick_school", "cast_spell", "start_spell2", "end_quake", "start_path", "set_mage_gear",
	"save_design", "delete_design", "retrofit_armies", "split_army", "combine_armies", "mage_join", "mage_detach", "dismiss", "send_to_rest",
	"retreat", "retreat_to", "fly_army", "thugs_enter", "thug_out", "dx_act", "answer_request", "make_peace",
	"declare_war", "proclaim_enemy", "renounce_enemy", "travelers_choose", "dismiss_quake", "dismiss_news",
	"answer_demand", "set_crop", "hand_to_ai", "take_from_ai", "send_message", "issue_proclamation", "offer_barter", "show_request", "set_paused", "set_auto_tech", "rename_prov", "close_school_popup",
	"debug_reveal", "debug_resources", "debug_all_tech", "grant_tech", "rec_toggle", "start_dig", "stop_dig"]

## Multiplayer: hands a command to the network instead of applying it here (it comes back through apply()).
var on_command: Callable
## Who paused the game (multiplayer: any player may pause; only the host or that player may go on). 0: nobody.
var paused_by := 0
var _from_order := false
var mp_cd := {}            # multiplayer: "<from>><to>:<flirt|growl>" -> when (the 10-minute wait between players)
var dialog_nation := 0     # while a pop-up about meeting a nation opens: that nation (the view shows its flag and leader)   # apply() is running a player's order (not the game's own rules)


## A player's order, from the interface: applied now (single-player), or sent to every copy (multiplayer, where
## the answer isn't known yet: null).
func do(type: String, args := []):
	var cmd := {"player": view_seat, "type": type, "args": pack_args(args)}
	if on_command.is_valid():
		on_command.call(cmd)
		return null
	return apply(cmd)


## One command, applied with its player's own fields (the same in every copy). Returns what the order returns.
func apply(cmd: Dictionary):
	var type := str(cmd.get("type", ""))
	var o := int(cmd.get("player", 0))
	if not type in COMMANDS or not seats.has(o):
		push_warning("Ignored an order: %s from %d" % [type, o])
		return null
	use_seat(o)
	var args: Array = unpack_args(cmd.get("args", []))
	var r = null
	if args.has(null) and type in ["order", "order_build", "cancel_build", "queue_survey", "cast_spell", "start_spell2",
			"end_quake", "start_path", "split_army", "dismiss", "send_to_rest", "retreat", "retreat_to", "fly_army",
			"answer_request", "make_peace", "thug_out", "start_dig", "stop_dig"] and args.size() > 0 and args[0] == null:
		r = null   # (what it was about is gone: a unit died, a war ended, a request ran out)
	else:
		_from_order = true
		r = callv("_cmd_" + type, args) if has_method("_cmd_" + type) else callv(type, args)
		_from_order = false
	use_seat(view_seat)
	return r


func _cmd_set_paused(on: bool) -> void:
	if on:
		if not paused:
			paused_by = ME
		paused = true
	elif not paused or paused_by == 0 or paused_by == ME or ME == HOST or not seats.has(paused_by):
		paused = false
		paused_by = 0


## Only the host hands a dropped player's nation to the computer.
func _cmd_hand_to_ai(o: int) -> void:
	if ME == HOST:
		hand_to_ai(o, "difficult")


func _cmd_set_auto_tech(tr: String, on: bool) -> void:
	auto_tech[tr] = on


func _cmd_rename_prov(id, v: String) -> void:
	prov_rename[id] = v


func _cmd_close_school_popup() -> void:
	school_popup = false


func _cmd_set_crop(p: int, slot: int, crop: String) -> void:
	for e in extras_in(p):
		if e.slot == slot:
			Ai.set_crop(self, e, crop)


## A command's arguments as plain data: units, wars, requests and extras become references.
func pack_args(args: Array) -> Array:
	return args.map(func(v): return _pack(v))


func _pack(v):
	if v is Array:
		return v.map(func(x): return _pack(x))
	if v is Dictionary:
		if v.has("owner") and v.has("kind") and v.has("prov") and v.has("id"):
			return {"_u": v.id}
		if v.has("a") and v.has("b") and v.has("since") and v.has("id"):
			return {"_w": v.id}
		if v.has("from") and v.has("kind") and v.has("until") and v.has("id"):
			return {"_r": v.id}
		if v.has("type") and v.has("slot") and not v.has("owner"):
			for p in extras:
				for e in extras[p]:
					if is_same(e, v):
						return {"_x": [p, v.slot]}
	return v


func unpack_args(args: Array) -> Array:
	return args.map(func(v): return _unpack(v))


func _unpack(v):
	if v is Array:
		return v.map(func(x): return _unpack(x))
	if v is Dictionary and v.size() == 1:
		if v.has("_u"):
			for u in units:
				if u.id == v._u and not u.get("_gone", false):
					return u
			return null
		if v.has("_w"):
			for w in wars:
				if w.id == v._w:
					return w
			return null
		if v.has("_r"):
			for r in dipl_state().reqs:
				if r.id == v._r:
					return r
			return null
		if v.has("_x"):
			for e in extras_in(int(v._x[0])):
				if e.slot == v._x[1]:
					return e
			return null
	return v


## Multiplayer step 2: a human nation whose player has gone is handed to the computer, at `diff` (Difficult when
## the host drops a player). Its land, units, stock and research carry over; its queues are refunded.
func hand_to_ai(o: int, diff := "difficult") -> void:
	if not seats.has(o) or o == HOST:
		return
	var S: Dictionary = seats[o]
	var rc := race(o)
	for key in S.queues:
		for q in S.queues[key]:
			for k in q.get("paid", {}):
				S.stock[k] = S.stock.get(k, 0) + q.paid[k]
	var tech_state := {}
	for tr in GameData.c("TREE_KEYS"):
		var st: Dictionary = S.tech.get(tr, {})
		tech_state[tr] = {"cur": st.get("cur"), "prog": st.get("prog", 0), "bank": st.get("bank", 0), "opts": st.get("opts", []),
			"done": st.get("done", []).duplicate(), "tier": st.get("tier", 0), "sticky": st.get("sticky", [])}
	var D: Dictionary = GameData.c("AI_DIFF")[diff]
	var fam: String = D.family if D.get("family") != null else "sword"
	fam = "axe" if rc == "swamp" and fam == "sword" else "thrust" if rc == "wood" and fam == "sword" else fam
	var aline: String = D.armor
	if rc == "swamp":
		aline = {"leather": "stag", "chain": "wyvern", "plate": "dragon"}.get(aline, "stag")
	elif rc == "wood":
		aline = {"leather": "spirit", "chain": "mithril", "plate": "ornate"}.get(aline, "spirit")
	var school = in_seat(o, current_school)
	var N := {"id": o, "diff": diff, "name": S.my_nation.name, "emblem": S.my_nation.emblem, "secondary": S.my_nation.get("secondary", "#faf1dc"),
		"alive": not S.fallen, "capital": S.capital, "stock": S.stock.duplicate(), "rep": S.rep.duplicate(), "surveyed": S.surveyed.duplicate(),
		"exhaust": S.exhaust, "ups": {}, "xups": {}, "tech": tech_state, "queue": [], "think": t + 1, "nextOutpost": 0, "phase": "grow",
		"stuckSince": null, "warCheck": t + 60, "family": fam, "armorLine": aline, "race": rc, "school": school,
		"wantSchool": school if school != null else "arcane", "spellT": 0, "dv": 0,
		"design": {"inf": "d-sw-axe", "cav": "d-sw-ogre"} if rc == "swamp" else {"inf": "d-sword", "cav": "d-rider"}, "armyN": S.army_counter,
		"income": S.income.duplicate(), "leader": S.leader, "fromHuman": true, "my_nation": S.my_nation.duplicate(),
		"auto_tech": S.auto_tech.duplicate(), "designs": S.designs.duplicate(true)}
	if ME == o:
		use_seat(HOST)
	seats.erase(o)
	seat_dipl.erase(o)
	if view_seat == o:
		view_seat = HOST
	nations[o] = N
	for u in units:   # its builders' and scouts' own jobs stop: the computer gives its own
		if u.owner == o and u.kind != "army":
			u.surveyQueue = []
			u.autoWalk = null
	for id in S.met:   # the computer nations it had met (computer nations keep that in ai_met)
		if nations.has(int(id)) and int(id) != o:
			ai_met[pair_key(o, int(id))] = true
	ai_redesign(N)
	for x in N.get("designs", []):   # (as loading a save does: a saved and loaded copy stays the same game)
		register_design(x)
	N.income = Ai.income(self, N)
	toast("%s is now played by the computer (%s)." % [N.name, GameData.c("DIFF_NAME").get(diff, diff)])



## Multiplayer hot-join (0.19): a player takes nation o back from the computer (a nation a player had before it was
## handed over). It gets its own seat again, with the computer's treasury, research, land and armies as they are.
func take_from_ai(o: int, player_name := "") -> void:
	if not nations.has(o) or seats.has(o) or o == HOST:
		return
	var N: Dictionary = nations[o]
	var rc := race(o)
	var keep: int = ME
	seats[o] = seat_defaults()
	use_seat(o)
	var unames := {}   # (the unit table is shared: it keeps the host's race's names, as add_seat does)
	for k in unit_defs:
		unames[k] = [unit_defs[k].get("name"), unit_defs[k].get("blurb")]
	seat_start(rc if rc in ["realm", "swamp", "wood"] else "realm")
	for k in unames:
		unit_defs[k].name = unames[k][0]
		if unames[k][1] != null:
			unit_defs[k].blurb = unames[k][1]
	var nat: Dictionary = N.get("my_nation", {})
	if nat.is_empty():
		var ci := 0
		var NC: Array = GameData.c("NATION_COLORS")
		for i in NC.size():
			if str(NC[i][0]) == str(player_info(o).get("color", "")):
				ci = i
		nat = {"name": str(N.get("name", "Realm")), "color": ci, "emblem": str(N.get("emblem", "crown")), "secondary": str(N.get("secondary", "#faf1dc"))}
	set_nation(nat)
	leader = str(N.get("leader", leader))
	capital = int(N.get("capital", -1))
	stock = N.get("stock", {}).duplicate()
	rep = N.get("rep", {}).duplicate()
	surveyed = N.get("surveyed", {}).duplicate()
	exhaust = int(N.get("exhaust", 0))
	army_counter = int(N.get("armyN", 0))
	fallen = not bool(N.get("alive", true))
	if N.get("designs") is Array and not N.designs.is_empty():
		designs = N.designs.duplicate(true)
	if N.get("auto_tech") is Dictionary:
		for tr in N.auto_tech:
			auto_tech[tr] = bool(N.auto_tech[tr])
	tech = {}
	var ts: Dictionary = N.get("tech", {})
	for tr in ["gov", "mil", "mag"]:
		var st: Dictionary = ts.get(tr, {})
		tech[tr] = {"cur": st.get("cur"), "prog": st.get("prog", 0), "bank": st.get("bank", 0), "opts": Array(st.get("opts", [])).duplicate(),
			"done": Array(st.get("done", [])).duplicate(), "tier": int(st.get("tier", 1 if tr == "gov" else 0)), "sticky": Array(st.get("sticky", [])).duplicate()}
	for id in nations:   # whom it had met
		if int(id) != o and ai_met.has(pair_key(o, int(id))):
			met[int(id)] = true
	for s2 in seats:
		if s2 != o and (seats[s2].met.has(o) or seats[s2].met.has(str(o))):
			met[s2] = true
	compute_income()
	use_seat(keep)
	nations.erase(o)
	if player_name != "":
		seat_names[o] = player_name
	in_seat(o, compute_fog)
	toast("%s is played by %s again." % [player_info(o).name, player_name if player_name != "" else "a player"])


# =================================================================================================================
# diplomacy between human players (multiplayer step 11): no opinion between players, so Flirt and Growl only tell
# the other player; no Bribe; access, alliances and pacts are the other player's choice (a request, 30 s); any two
# human nations may ally whatever their race. New: Send Message, Barter and Issue Proclamation.

const MSG_COST := {"gold": 50}
const PROCLAIM_COST := {"gold": 100}
const MSG_LEN := 80

## A note on player o's flags (and a message on their screen): kind is "msg", "procl", "enemy", "growl", "flirt",
## "gift", "answer" or "access"; from: the nation it's about.
func notify(o: int, kind: String, from: int, text: String, warn := false) -> void:
	if not seats.has(o):
		return
	var keep: int = ME
	use_seat(o)
	var D := dipl_state()
	D.news.append({"id": D.seq, "kind": kind, "a": from, "b": o, "t": t, "text": text})
	D.seq += 1
	if D.news.size() > 8:
		D.news = D.news.slice(D.news.size() - 8)
	sfx("wn_ally")
	toast(text, warn)
	use_seat(keep)


func res_text(r: Dictionary) -> String:
	var parts := []
	for k in RES:
		if int(r.get(k, 0)) > 0:
			parts.append("%d %s" % [int(r[k]), k])
	return " and ".join(parts) if not parts.is_empty() else "nothing"


func _pays(c: Dictionary) -> bool:
	for k in c:
		if stock.get(k, 0) < c[k]:
			return false
	return true


func message_why(o: int) -> String:
	if not seats.has(o) or o == ME or not seats[o].met.has(ME) and not met.has(o):
		return "Only to a player you have met"
	if not _pays(MSG_COST):
		return "Needs %d gold" % MSG_COST.gold
	return ""


## Send Message: 50 gold, up to 80 characters, to one player you have met.
func send_message(o: int, text: String) -> bool:
	var tx := text.strip_edges().replace("\n", " ").left(MSG_LEN)
	var why := message_why(o)
	if why == "" and tx == "":
		why = "Write something first"
	if why != "":
		toast(why, true)
		return false
	stock.gold -= MSG_COST.gold
	notify(o, "msg", ME, "%s: “%s”" % [player_info(ME).name, tx])
	toast("Your message is on its way to the %s." % player_info(o).name)
	return true


func proclamation_why() -> String:
	if not _pays(PROCLAIM_COST):
		return "Needs %d gold" % PROCLAIM_COST.gold
	if seat_ids().filter(func(h): return h != ME and met.has(h)).is_empty():
		return "You haven’t met another player yet"
	return ""


## Issue Proclamation: 100 gold, a message to every player you have met.
func issue_proclamation(text: String) -> bool:
	var tx := text.strip_edges().replace("\n", " ").left(MSG_LEN)
	var why := proclamation_why()
	if why == "" and tx == "":
		why = "Write something first"
	if why != "":
		toast(why, true)
		return false
	stock.gold -= PROCLAIM_COST.gold
	var n := 0
	for h in seat_ids():
		if h != ME and met.has(h):
			notify(h, "procl", ME, "Proclamation of the %s: “%s”" % [player_info(ME).name, tx])
			n += 1
	toast("Your proclamation is read in %d court%s." % [n, "" if n == 1 else "s"])
	return true


func barter_why(o: int, give: Dictionary, want: Dictionary) -> String:
	if not seats.has(o) or o == ME or not met.has(o):
		return "Only with a player you have met"
	var any := false
	for d in [give, want]:
		for k in d:
			if not k in RES or int(d[k]) < 0:
				return "Not a fair offer"
			any = any or int(d[k]) > 0
	if not any:
		return "Offer or ask for something"
	if not _pays(give):
		return "You don’t have %s" % res_text(give)
	if dipl_state().reqs.any(func(r): return r.kind == "barter" and r.from == o) or in_seat(o, func(): return dipl_state().reqs.any(func(r): return r.kind == "barter" and r.from == ME)):
		return "An offer is already waiting"
	return ""


## Barter: any amounts of gold, wood and food for any amounts in return. The other player has 30 s to accept.
func offer_barter(o: int, give: Dictionary, want: Dictionary) -> bool:
	var g2 := {}
	var w2 := {}
	for k in RES:
		g2[k] = maxi(0, int(give.get(k, 0)))
		w2[k] = maxi(0, int(want.get(k, 0)))
	var why := barter_why(o, g2, w2)
	if why != "":
		toast(why, true)
		return false
	_ask_player(o, "barter", {"give": g2, "want": w2})
	toast("Your offer is on its way to the %s: %s for %s." % [player_info(o).name, res_text(g2), res_text(w2)])
	return true


# a request to another player (it waits 30 s in their requests)
func _ask_player(o: int, kind: String, data := {}) -> void:
	var from: int = ME
	var keep: int = ME
	use_seat(o)
	dip_request(from, kind, data)
	use_seat(keep)


# answer_request for a request from another player (this player is the one answering)
func _answer_player(r: Dictionary, yes: bool, quiet: bool) -> void:
	var o: int = r.from
	var nm: String = player_info(o).name
	var what: String = REQ_NAME.get(r.kind, "offer").to_lower()
	if not yes:
		toast(("No answer to the %s’s %s: declined." if quiet else "You declined the %s’s %s.") % [nm, what])
		notify(o, "answer", ME, ("The %s didn’t answer your %s." if quiet else "The %s declined your %s.") % [player_info(ME).name, what], true)
		return
	var why := ""
	match r.kind:
		"h_share":
			var got := share_contacts(ME, o)
			if got.is_empty():
				why = "They already know every nation you know"
			else:
				notify(o, "answer", ME, "The %s shared their contacts: you have met %s." % [player_info(ME).name, ", ".join(got.map(func(x): return the_name(x)))])
		"h_access":
			if not access_given(ME, o):
				dipl_state().access.append({"from": ME, "to": o})
		"h_ally":
			why = player_ally_why(o)
			if why == "":
				form_alliance(o, ME, 0)
		"h_trade", "h_crime":
			var k: String = r.kind.substr(2)
			why = trade_why(ME, o) if k == "trade" else crime_why(ME, o)
			if why == "":
				form_pact(k, o, ME)
		"h_peace":
			var wp = null
			for w in wars:
				if w.id == r.data.war:
					wp = w
			if wp == null:
				why = "That war is already over"
			else:
				make_peace(wp, ME, {"kind": "white", "agreed": true})
		"barter":
			var give: Dictionary = r.data.give
			var want: Dictionary = r.data.want
			var S: Dictionary = seats[o].stock
			if not _pays(want):
				why = "You don’t have %s any more" % res_text(want)
			elif RES.any(func(k): return S.get(k, 0) < give.get(k, 0)):
				why = "They don’t have %s any more" % res_text(give)
			else:
				for k in RES:
					S[k] = S.get(k, 0) - give.get(k, 0) + want.get(k, 0)
					stock[k] = stock.get(k, 0) + give.get(k, 0) - want.get(k, 0)
				in_seat(o, compute_income)
	if why != "":
		toast("It can’t be done: %s." % (why[0].to_lower() + why.substr(1)), true)
		notify(o, "answer", ME, "The %s agreed to your %s, but it can’t be done: %s." % [player_info(ME).name, what, why[0].to_lower() + why.substr(1)], true)
		return
	toast("You accepted the %s’s %s." % [nm, what])
	notify(o, "answer", ME, "The %s accepted your %s!" % [player_info(ME).name, what])


## Alliances between players: no opinion and no race rule; one ally at a time, no war, truce or proclaimed enmity.
func player_ally_why(o: int) -> String:
	if allied(ME, o):
		return "Already allies"
	if treaty_count(o) >= 1 or treaty_count(ME) >= 1:
		return "One of you already has an ally"
	if at_war(ME, o):
		return "You are at war"
	if truce_left(ME, o) > 0:
		return "Truce: %s left" % fmt_time(truce_left(ME, o))
	if enemy_of(o) == ME or enemy_of(ME) == o:
		return "One of you proclaims the other an enemy"
	return ""


## Why a diplomatic action can't be taken toward another player ("" when it can). The window asks this.
## Flirt and Growl between players wait this long before the same player can be flirted with or growled at again.
const MP_SWAY_CD := 600.0

func player_act_why(act: String, o: int) -> String:
	match act:
		"growl", "flirt":
			# Swamplings growl, the others flirt (0.18); each once in 10 minutes toward the same player
			if act == "growl" and race() != "swamp":
				return "Only Swamplings growl"
			if act == "flirt" and race() == "swamp":
				return "Swamplings don’t flirt"
			var left: float = float(mp_cd.get("%d>%d:%s" % [ME, o, act], -INF)) + MP_SWAY_CD - t
			return "Again in %s" % fmt_time(left) if left > 0 else ""
		"gift":
			return "" if _pays({"gold": DIPL.gift.gold}) else "Needs %d gold" % DIPL.gift.gold
		"bribe", "spy":
			return "Not between players"
		"grant":
			return "" if access_given(ME, o) else "You are at war" if at_war(ME, o) else "Allies already have access" if allied(ME, o) else ""
		"share":
			return "You are at war" if at_war(ME, o) else "They know no nation you haven't met" if contacts_new_for(ME, o).is_empty() else _waiting(o, "h_share")
		"ask":
			return "They already let you through" if access_given(o, ME) else "You are at war" if at_war(ME, o) else "Allies already have access" if allied(ME, o) else _waiting(o, "h_access")
		"ally":
			return "" if allied(ME, o) else (player_ally_why(o) if player_ally_why(o) != "" else _waiting(o, "h_ally"))
		"trade":
			return "" if pair_has(dipl_state().trade, ME, o) != null else (trade_why(ME, o) if trade_why(ME, o) != "" else _waiting(o, "h_trade"))
		"crime":
			return "" if pair_has(dipl_state().crime, ME, o) != null else (crime_why(ME, o) if crime_why(ME, o) != "" else _waiting(o, "h_crime"))
	return ""


func _waiting(o: int, kind: String) -> String:
	var me0: int = ME
	return "Waiting for their answer" if in_seat(o, func(): return dipl_state().reqs.any(func(r): return r.kind == kind and r.from == me0)) else ""


# dx_act toward another player
func _dx_player(act: String, o: int) -> void:
	var nm: String = player_info(o).name
	var me_nm: String = player_info(ME).name
	var why := player_act_why(act, o)
	if why != "":
		toast(why, true)
		return
	match act:
		"growl":
			mp_cd["%d>%d:growl" % [ME, o]] = t
			toast("You growl at the %s. Players aren’t swayed by growls, but they heard it." % nm)
			notify(o, "growl", ME, "The %s growl at you!" % me_nm)
		"flirt":
			mp_cd["%d>%d:flirt" % [ME, o]] = t
			toast("You flirt with the %s. Players aren’t swayed by it, but they noticed." % nm)
			notify(o, "flirt", ME, "%s flirts with you." % (leader_of(ME).full if leader_of(ME) != null else "The " + me_nm))
		"gift":
			var gold: int = DIPL.gift.gold
			stock.gold -= gold
			var S: Dictionary = seats[o]
			var room: int = maxi(0, int(in_seat(o, func(): return storage_cap("gold"))) - int(S.stock.gold))
			S.stock.gold += mini(room, gold)
			S.gift_vault += gold - mini(room, gold)
			toast("You sent the %s %d gold." % [nm, gold])
			notify(o, "gift", ME, "The %s sent you a gift of %d gold." % [me_nm, gold])
		"grant":
			if access_given(ME, o):
				end_access(ME, o, "you revoked it")
				notify(o, "access", ME, "The %s withdrew your military access." % me_nm, true)
			else:
				dipl_state().access.append({"from": ME, "to": o})
				toast("The %s’s armies may now march through your land. You can revoke it at any time." % nm)
				notify(o, "access", ME, "The %s give you military access: your armies may march through their land." % me_nm)
		"ask":
			_ask_player(o, "h_access")
			toast("You asked the %s for military access." % nm)
		"share":   # 0.19: they are asked, and choose
			_ask_player(o, "h_share")
			toast("You asked the %s to share their contacts." % nm)
		"ally":
			if allied(ME, o):
				for A in allies:
					if (A.a == ME and A.b == o) or (A.b == ME and A.a == o):
						end_alliance(A, "you ended it")
						notify(o, "answer", ME, "The %s ended your alliance." % me_nm, true)
						return
			_ask_player(o, "h_ally")
			toast("You proposed an alliance to the %s." % nm)
		"trade", "crime":
			var P = pair_has(dipl_state()[act], ME, o)
			if P != null:
				end_pact(act, P, "you ended it")
				return
			_ask_player(o, "h_" + act)
			toast("You proposed %s to the %s." % ["a Trade Network" if act == "trade" else "Organized Crime", nm])


func _cmd_show_request(id: int, on_screen: bool) -> void:
	var D := dipl_state()
	var pick = null
	for r in D.reqs:
		if r.id == id:
			pick = r
	if pick == null:
		return
	if not on_screen:
		pick.min = true
		return
	for r in D.reqs:
		r.min = not is_same(r, pick)
	D.reqs = [pick] + D.reqs.filter(func(r): return not is_same(r, pick))
