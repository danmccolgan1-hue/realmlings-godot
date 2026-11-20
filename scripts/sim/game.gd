class_name Game
extends RefCounted
## One game's rules and state: the web game's `S` object plus the globals that live beside it (yields, income,
## treeBorder, openNbr). Rules only; never draws. Milestone 1: the Practice island, Realmlings, the player alone.
##
## Field names follow the web game (snake_case here), so `stock` is S.stock, `buildings` is S.buildings, and so on.
## Units are Dictionaries with the web fields: {id, owner, kind, name, prov, slot, x, y, troops (armies only), ...}.

const ME := 1
const RES := ["gold", "wood", "food"]
const MASON := "mason:A"
const MAGE := "mage:A"
const OUTPOST_UPKEEP := {"wood": 1}   # web: govtech.js (declared with OUTPOSTS_PER_FORT; not in the export)
## Designs a leader starts with that the Armory would create (web: v105.js leaderDesign → equip.js addDesign).
## Cost and upkeep as the web game computes them (tests/fixtures/econ); they move to the Armory port later.
const LEADER_DESIGNS := {
	"Shield Footman": {"name": "Shield Footman", "cost": {"gold": 90, "wood": 10}, "upkeep": {"food": 2}, "design": true, "speed": 0.83,
		"blurb": "Short Sword and Round Shield, Leather I armor. Parry: take 10% less damage.",
		"spec": {"type": "inf", "weapon": "shortsword", "shield": "round", "armor": "leather1", "race": "realm"}},
}

# --- world ---
var world: Dictionary
var G: Dictionary            # WorldPrep.prep(world): provs (pts, ic, coastal...), bounds
var open_nbr := []           # province -> [{q, m}] across open borders
var all_nbr := []
var yields := []             # province -> {gold, wood, food, bonus, deposit}
var tree_border := []

# --- the nation ---
var leader := ""
var capital := -1
var stock := {}
var income := {"gold": 0, "wood": 0, "food": 0}
var income_parts := {}
var buildings := {}          # province -> {stage (0 outpost, 1 fort, 2 capital), born, owner}
var extras := {}             # province -> [{type, slot, born, freeFor?}]
var occ := {}                # province -> the nation occupying it (wars)
var units := []
var next_id := 1
var army_counter := 0
var tech := {}               # tree -> {cur, prog, bank, opts, done, tier}
var rep := {}                # repeatable research levels
var surveyed := {}           # province -> time surveyed
var unit_defs := {}          # UNIT_DEFS plus designs made in this game
var designs := []
var exhaust := 0
var exhaust_ok := 0
var harvest = null
var devel := {}
var upgrades := {}           # province -> {t0, paid}: outposts becoming forts
var xup := {}                # "<p>@<slot>" -> {t0, paid, to}: a Forge or Mage Tower going up a level
var roads := {}              # "a_b" (a < b) -> true
var walls := {}              # edge index -> true
var wall_hp := {}
var gate_own := {}           # "a_b" -> {home, owner}
var fort_walled := {}        # "p>q" -> true: borders a fort or capital has walled once
var gpc_slow_t := -9.0
# magic (web: magic.js S.cd / S.paths / S.harvest / S.trap, v98.js S.reveals / S.eyes / S.haunts / S.manaPool)
var cd := {}                 # spell -> game time when ready again
var paths := {}              # edge index -> "forest" | "tunnel"
var harvest_by = null        # web: S.harvest
var trap = null
var reveals := []
var eyes := []
var haunts := []
var mana_pool := []
var mana_prev := {}
var mana_prev_t := -1.0
var mage_gear := {"weapon": "stave", "shield": null}
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
var auto_tech := {"gov": false, "mil": false, "mag": false}
var queues := {}             # "capital:<p>" / "barracks:<p>" / "magetower:<p>" -> [{kind, paid, t0}]
var rally := {}              # queue key -> {prov, x, y}
var military := {}           # unit kinds that are soldiers (web: game.js MILITARY)
var finds := {}              # province -> {id: "ruins" | "treasure", done}
var treasure_rolled := {}
var sp_found := {}

# --- fog (web: S.wf, S.known, S.explored, S.visible) ---
var wf := {}                 # provinces a Wayfinder has entered
var known := {}              # provinces kept discovered (armies, Far Sight)
var explored := {}
var visible := {}

# --- time ---
var t := 0.0
var next_tick := 0.0
var paused := true
var last := 0.0
var started := false

# --- constants ---
var BUILD_DEFS: Dictionary
var CAPITAL_BONUS: Dictionary
var TICK: float
var TECH_BY_ID := {}
var LEADERS: Dictionary
var DSTATS: Dictionary
var SLOTS: Array
var UNIT_SPEED: Dictionary
var SPEED: float
var WAYFINDER: String
var rng := RandomNumberGenerator.new()   # stands in for the web's Math.random (names, shuffles); not seeded by the map


func _init() -> void:
	BUILD_DEFS = GameData.c("BUILD_DEFS")
	CAPITAL_BONUS = GameData.c("CAPITAL_BONUS")
	TICK = GameData.c("TICK")
	for x in GameData.c("TECHS"):
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
	# the Realmlings' Armory starts with these designs (web: equip.js; the other races' designs never train here)
	for d in [["d-spear", "inf", "spear"], ["d-sword", "inf", "shortsword"], ["d-club", "inf", "club"], ["d-rider", "cav", "spear"]]:
		designs.append({"id": d[0], "name": unit_defs[d[0]].name, "type": d[1], "weapon": d[2], "shield": null, "armor": "leather1",
			"horse": "riding" if d[1] == "cav" else null, "builtin": true, "race": "realm"})
	stock = GameData.c("START_STOCK").duplicate()
	dev_rand = rng.randf
	battle_rand = rng.randf
	js_rand = rng.randf
	if test_random >= 0:
		js_rand = func() -> float: return test_random


## A new Practice-island game, as menu.js startGame() runs it for a Realmling player with every computer slot closed.
## leader: a Realmling leader id ("havva", "finn", ...) or "" for a random one.
static func new_practice(seed: String, leader_id := "", map: Dictionary = {}) -> Game:
	var g := Game.new()
	g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_practice(seed))
	g.G = WorldPrep.prep(g.world)
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


# ---------------------------------------------------------------------------------------------------------------
# setup

# web: game.js setupGame() (the player's land is grassland). where: "center", "edge" or "random" (menu Start position)
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
	var home_ter := "grassland"
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
	capital = best
	buildings[best] = {"stage": 2, "born": -10, "owner": ME}
	surveyed[best] = -10
	tech = {}
	for tr in ["gov", "mil", "mag"]:
		tech[tr] = {"cur": null, "prog": 0, "bank": 0, "opts": [], "done": [], "tier": 1 if tr == "gov" else 0, "sticky": []}
	draw_options("gov")
	units = [mk_unit(1, GameData.c("WAYFINDER"), "Wayfinder", best, 3), mk_unit(2, MASON, "Mason", best, 4)]
	next_id = maxi(next_id, 3)
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


# web: equip.js footmanOf() (Realmlings)
func footman_of() -> String:
	return "d-sword"


# ---------------------------------------------------------------------------------------------------------------
# leaders (web: v105.js assignLeaders / applyLeaderStart, v106.js applyLeaderStart wrapper)

func assign_leader(id: String) -> void:
	if LEADERS.has(id) and LEADERS[id].race == "realm":
		leader = id
		return
	var pool := []
	for k in LEADERS:
		if LEADERS[k].race == "realm":
			pool.append(k)
	leader = pool[rng.randi() % pool.size()]


func leader_of(o := ME):
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
	var sc = null if o == ME else nations[o].school
	var ok := LEADERS.keys().filter(func(k): return LEADERS[k].race == "realm" and (LEADERS[k].get("school") == null or sc == null or LEADERS[k].school == sc))
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
			add_start_tech("autoscout", o)
			add_start_tech("stealth", o)
			add_start_tech("farsight", o)
	# v106: the Horsemistress starts with 4 riders, her Stable costs no upkeep, and the capital grows 7 more food
	if L.start == "stable":
		set_start_army({"d-rider": 4}, o)
		for e in extras_in(cap):
			if e.type == "stable":
				e.freeFor = o
				break
		yields[cap].food += GameData.c("LEADER_CAP_FOOD")
		compute_income()


func cap_of(o: int) -> int:
	return capital if o == ME else nations[o].capital if nations.has(o) else -1


func stock_of(o: int) -> Dictionary:
	return stock if o == ME else nations[o].stock if nations.has(o) else {"gold": 0, "wood": 0, "food": 0}


# a design for a leader's starting soldiers: the player's go into the Armory, a computer nation's are registered only
func leader_design_for(o: int, d: Dictionary) -> String:
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


# web: equip.js designStats (infantry and cavalry; Woodling Champions, Ogres and dual wielding belong to other races)
func design_stats(d: Dictionary) -> Dictionary:
	var B: Dictionary = GameData.c("UNIT_BASE")[d.type]
	var W: Dictionary = GameData.c("WEAPONS")[d.weapon]
	var A: Dictionary = GameData.c("ARMORS")[d.armor]
	var Sh = GameData.c("SHIELD_DEFS")[d.shield] if d.get("shield") != null and not W.twoH else null
	var H = GameData.c("HORSES")[d.get("horse", "riding") if d.get("horse") != null else "riding"] if d.type == "cav" else null
	var armor: float = A.armor + (Sh.armor if Sh else 0) + (H.armor if H else 0)
	var cost := {}
	for c in [B.cost, W.cost, A.cost, Sh.cost if Sh else {}, H.cost if H else {}]:
		for k in c:
			cost[k] = cost.get(k, 0) + c[k]
	cost.erase("food")
	var speed: float = float(JS.to_fixed((H.speed if H else B.speed) * A.speed * (Sh.speed if Sh else 1), 2))
	var lv: int = int(A.level)
	return {"cav": d.type == "cav", "ogre": false, "race": d.get("race", "realm"), "rough": H != null and H.get("rough", false),
		"plate": A.type in GameData.c("PLATE_TYPES"), "fam": W.fam, "atk": float(JS.to_fixed(W.atk + (H.get("atk", 0) if H else 0), 1)),
		"hp": B.hp + (H.get("hp", 0) if H else 0) + GameData.c("ARMOR_HP")[lv], "armor": armor, "shieldArmor": Sh.armor if Sh else 0,
		"red": armor / (armor + 12), "parry": 0.1 if W.fam == "sword" or W.fam == "thrust" else 0.0, "crit": 0.1 if W.fam == "axe" else 0.0,
		"speed": speed, "cost": cost, "upkeep": {"food": maxf(0, B.upkeep.food + (H.get("upFood", 0) if H else 0))}}


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
	var d := {"id": "d%d" % design_seq, "name": o.name, "type": o.type, "weapon": o.weapon, "shield": o.get("shield"),
		"armor": o.armor, "horse": o.get("horse", "riding") if o.type == "cav" else null, "builtin": false, "race": o.get("race", "realm")}
	if d.type == "cav" and d.horse == null:
		d.horse = "riding"
	designs.append(d)
	register_design(d)
	return d


func register_design(d: Dictionary) -> void:
	var st := design_stats(d)
	DSTATS[d.id] = st
	var W: Dictionary = GameData.c("WEAPONS")[d.weapon]
	var Sh = GameData.c("SHIELD_DEFS")[d.shield] if d.get("shield") != null and not W.twoH else null
	var H = GameData.c("HORSES")[d.horse] if d.get("horse") != null and d.type == "cav" else null
	var blurb: String = "%s%s, %s armor%s. %s." % [W.name, " and " + Sh.name if Sh else "", GameData.c("ARMORS")[d.armor].name,
		", " + H.name if H else "", GameData.c("FAMILY")[W.fam].note]
	if H and H.get("rough", false):
		blurb += " No cavalry penalty in forest or swamp."
	unit_defs[d.id] = {"name": d.name, "cost": st.cost, "upkeep": st.upkeep, "blurb": blurb, "design": true}
	military[d.id] = true
	UNIT_SPEED[d.id] = st.speed


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
	var table := {"weapon": "WEAPONS", "shield": "SHIELD_DEFS", "armor": "ARMORS", "horse": "HORSES"}
	var item = GameData.c(table[kind]).get(key)
	if item == null:
		return "Unknown"
	if item.get("tech") != null and not has_tech(item.tech):
		return "Research " + (TECH_BY_ID[item.tech].name if TECH_BY_ID.has(item.tech) else str(item.tech))
	return null


## Save the Armory draft: a design not in use is changed in place; a starting design or one in use is saved as a new
## design (named Footman II, III … when the name is unchanged). Returns the saved design.
func save_design(draft: Dictionary) -> Dictionary:
	var name: String = str(draft.name).strip_edges().left(24)
	if name == "":
		name = "Design"
	var cur: Variant = design_by_id(draft.id) if draft.get("id") != null else null
	if cur != null and not cur.builtin and not design_in_use(cur.id):
		for k in ["type", "weapon", "shield", "armor", "horse"]:
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
		return GameData.c("MARKET_GIVES").duplicate()
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


# web: game.js extrasBonus() (+ v104.js crops: every farm grows its staple until crops are ported;
# v106.js deep gold mines come with development)
func extras_bonus(p: int) -> Dictionary:
	var y := {"gold": 0, "wood": 0, "food": 0}
	for e in extras_in(p):
		var gv := gives_of(e.type)
		for k in gv:
			y[k] += gv[k]
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
	return y


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
	if L == null or L.id != "hisola":
		return 0
	var cut := 0
	for k in troops:
		var n: int = troops[k]
		if not n or not unit_defs.has(k) or not unit_defs[k].has("upkeep"):
			continue
		var f: int = unit_defs[k].upkeep.get("food", 0)
		if DSTATS.has(k) and DSTATS[k].get("cav", false):
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
	gross.food += harvest_food()
	income = {}
	for k in RES:
		income[k] = gross[k] - up[k]
	income_parts = {"gross": gross, "up": up}


# web: govtech.js storageCap()
func storage_cap(k: String) -> int:
	var n: int = GameData.c("BASE_CAP") + 500 * rep_lv("rep-storage")
	for p in extras:
		if owned(p):
			for e in extras[p]:
				var st = BUILD_DEFS[e.type].get("store")
				if st != null and st.has(k):
					n += st[k]
	return n


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
	var short: bool = stock.food + income.food < 0
	for k in RES:
		stock[k] = maxi(0, stock[k] + income[k])
	step_exhaustion(short)
	if not nations.is_empty():
		Ai.payday(self)
	tech_payday()
	regen_mana()
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
	t += dt
	for u in units.duplicate():
		if not u.get("_gone", false):
			step_unit(u, dt)
	if next_tick == 0.0:
		next_tick = t + TICK
	while t >= next_tick:
		var nt := next_tick
		next_tick += TICK
		payday(nt)
	step_training(t)
	if not paused:
		meet_head_on()
		step_battles(t)
		if not nations.is_empty():
			step_war(t)
			step_ai(t)
		step_scouts(t)
		step_magic(t, dt)
		step_gpc(t)
		step_patrols(t, dt)
		step_travelers(dt)
	clamp_stock()
	step_upgrades(t)
	if started and uq() != null:
		step_boss_halt()
	# web: v96.js stepV96 (war timers, bandit waves, rally points), then v105.js stepDiplomacy, then v106.js
	if not paused:
		if not nations.is_empty():
			step_war_timers()
		step_bandit_waves(t)
		rally_arrivals()
	if not nations.is_empty():
		step_diplomacy()
	var d := 0.0
	if paused:
		dev_t = t
	elif not fallen:
		d = 0.0 if dev_t < 0 or t < dev_t else t - dev_t
		dev_t = t
		d = minf(d, 1.0)
		step_develop(d)
		if not nations.is_empty():
			Ai.step_enemies(self)
		step_orders()
		if not nations.is_empty():
			for id in nations:
				Ai.develop(self, nations[id])
	compute_fog()
	if not nations.is_empty():
		update_met()
	if tutorial != null:
		tutorial.step()


# ---------------------------------------------------------------------------------------------------------------
# movement (web: game.js findPath / order / walkHops and the unit loop in update())

const EXPLORE_TIME := 8.0
const SCOUT_SLOW := 4.0
const SURVEY_TIME := 30.0
const BUILD_TIME := 30.0
const TREASURE_GOLD := 200

## Messages for the player (the web game's toasts). The view shows them; tests can ignore them.
var on_toast: Callable


func toast(msg: String, warn := false) -> void:
	if on_toast.is_valid():
		on_toast.call(msg, warn)


func exploring(u: Dictionary) -> bool:
	return u.kind == WAYFINDER and u.owner == ME and u.scouting != null


# web: game.js busy()
func busy(u: Dictionary) -> bool:
	return u.moving or u.survey != null or u.build != null or u.pending != null or u.pendingSurvey >= 0 or not u.surveyQueue.is_empty()


# web: game.js canEnter() — on the Practice island there are no other nations, bandits or bosses to keep out of
func can_enter(u: Dictionary, q: int, tgt: int) -> bool:
	var ok: bool = u.owner != ME or u.get("exiting", false) or explored.has(q)
	if not ok and u.kind == WAYFINDER:
		ok = q == tgt or (u.autoWalk != null and q == u.autoWalk.to)
	elif not ok:
		ok = not wars.is_empty() and nation_of(q) != 0 and hostile(ME, nation_of(q))
	if not ok:
		return false
	if u.kind == WAYFINDER and u.owner == ME and bandits_seen_in(q):
		return false
	if u.kind == MASON and mason_danger(u, q):
		return false
	if not nation_ok(u, q):
		return false
	if boss_block(u, q, tgt):
		return false
	return true


# web: game.js nationOk: other nations' land only at war, in a truce, or with military access (v105)
func nation_ok(u: Dictionary, q: int) -> bool:
	if u.get("exiting", false) or u.owner == RAIDERS or (u.kind == WAYFINDER and (u.get("stealth", false) or u.get("detected", false))):
		return true
	var n := nation_of(q)
	return n == 0 or n == u.owner or hostile(u.owner, n) or truce_left(u.owner, n) > 0 or has_access(u.owner, n)


# web: game.js findPath / findPathVia (no walls yet): border crossings from u.prov to target, or null
func find_path(u: Dictionary, target: int):
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
		for n in path_nbr(u, a):
			if not prev.has(n.q) and (path_avoid == null or n.q == target or not path_avoid.has(n.q)) and can_enter(u, n.q, target):
				prev[n.q] = {"a": a, "m": n.m}
				q.append(n.q)
	if not prev.has(target):
		return null
	var hops := []
	var c := target
	while c != u.prov:
		var pr: Dictionary = prev[c]
		hops.push_front({"to": c, "m": pr.m})
		c = pr.a
	return hops


## web: v101.js pathAvoid: while a computer nation's army is ordered at war, paths avoid where an outmatching enemy
## stands or is heading (the destination excepted)
var path_avoid = null


# web: game.js order(u, target, quiet, pt) + v101.js (computer armies at war steer clear of armies that would crush them)
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
		wps.append({"x": h.m[0], "y": h.m[1], "enter": h.to})
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
		return UNIT_SPEED.get(u.kind, 1.0)
	var m := INF
	for k in u.troops:
		if u.troops[k] > 0:
			m = minf(m, UNIT_SPEED.get(k, 1.0))
	return m if m < INF else 1.0


static func facing(dx: float, dy: float) -> float:
	return JS.round_js(atan2(dx, dy) / (PI / 4)) * (PI / 4)


## One unit's share of a frame. web: the body of `for (const u of S.units)` in game.js update()
func step_unit(u: Dictionary, dt: float) -> void:
	if u.moving:
		var time := dt
		while time > 0 and not u.path.is_empty():
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
				toast("Survey complete: %d gold, %d wood, %d food every 10 s.%s" % [y.gold, y.wood, y.food, " Found a Hidden Gold Deposit!" if y.deposit else ""])
				sp_found[u.prov] = true
				if setpieces.has(u.prov):
					setpiece_found(u.prov, u)
				survey_finds(u)
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


# web: v78.js surveyFinds(u): Intact Ruins give a Tier I Government technology; a desert may hide treasure
func survey_finds(u: Dictionary) -> void:
	var p: int = u.prov
	var f = finds.get(p)
	if f != null and f.id == "ruins" and not f.done:
		f.done = true
		var pick := []
		for x in TECH_BY_ID.values():
			if x.tree == "gov" and x.get("tier") == 1 and not x.get("rep", false) and not tech.gov.done.has(x.id) and req_met(x, tech.gov):
				pick.append(x)
		if not pick.is_empty():
			var x: Dictionary = pick[rng.randi() % pick.size()]
			grant_tech(x.id)
			toast("%s has found intact ruins of an ancient temple! Your nation gains %s." % [u.name, x.name])
	if world.provinces[p].terrain == "desert" and not finds.has(p) and not treasure_rolled.has(p):
		treasure_rolled[p] = true
		if Mulberry32.from_string(str(world.seed) + ":treasure:" + str(p)).next() < GameData.c("TREASURE_CHANCE"):
			finds[p] = {"id": "treasure", "done": true}
			stock.gold += TREASURE_GOLD
			toast("%s has found a forgotten treasure in the sand: +%d gold." % [u.name, TREASURE_GOLD])


# web: tech.js reqMet() for Realmlings (reqOf: `req`; `reqSw` is for the other races). The tech trees come in step 7.
func req_met(x: Dictionary, st: Dictionary) -> bool:
	var req = x.get("req")
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
	return units.filter(func(v): return v.pending != null and v.pending.prov == p and v.pending.type != "outpost")


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
		return lack_text(GameData.c("OUTPOST_COST"))
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
	return lack_text(d.cost)


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
func order_build(u: Dictionary, p: int, type: String, slot := -1) -> bool:
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
	var cost: Dictionary = GameData.c("OUTPOST_COST")
	for k in cost:
		stock[k] -= cost[k]
	u.build = {"prov": u.prov, "type": "outpost", "t0": t, "dur": build_time("outpost"), "paid": cost.duplicate()}
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
	for k in d.cost:
		stock[k] -= d.cost[k]
	var o := bslot_of(p, slot)
	u.build = {"prov": p, "type": type, "slot": slot, "ox": o[0], "oy": o[1], "t0": t, "dur": build_time(type), "paid": d.cost.duplicate()}
	u.th = atan2(o[0] + G.provs[p].ic[0] - u.x, o[1] + G.provs[p].ic[1] - u.y)
	toast("Building a %s… (−%s)" % [d.name, cost_text(d.cost)])
	return true


# web: game.js cancelBuild(u): the resources come back
func cancel_build(u: Dictionary) -> void:
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
	else:
		cancel_build(u)
		if mine:
			toast("Someone claimed this province first: outpost cancelled, resources refunded.", true)
	if not mine and u.build != null:
		Ai.built(self, u)
	u.build = null


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
	toast("Upgrading the outpost to a Fort… (−%s, %d s)" % [cost_text(FU.cost), FU.time])
	return true


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
	if reveal_all:
		for p in G.provs.size():
			vis[p] = true
	for p in vis:
		exp[p] = true
	visible = vis
	explored = exp


## Debug and pictures only (the view's --reveal): the whole map is seen. Not part of the web game's rules.
var reveal_all := false


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
	if src != "barracks":
		return []
	var has_stable := extras_in(prov).any(func(e): return e.type == "stable")
	var list := []
	for d in designs:
		if d.get("race", "realm") == "realm" and (d.type == "inf" or has_stable):
			list.append(d.id)
	list = list.slice(0, 12)
	if _has_forge():
		var k: String = GameData.c("RANGED").realm.id
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
	toast("%s queued at the %s." % [d.name, "capital" if src == "capital" else "barracks"])
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
			compute_income()
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
	var r = x.get("race")
	if r is Array:
		return r.has("realm")
	return r == null or r == "realm"


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
	return n


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
	for x in GameData.c("TECHS"):
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
	var tree_name: String = GameData.c("TECH_TREES")[tree].name
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
				var nm: String = GameData.c("TECH_TREES")[tree].name
				toast("%s research unlocked! Open Research (T) to pick a technology." % nm if st.tier == 0 else "%s Tier %s technologies are now available." % [nm, ["", "I", "II", "III"][T]])
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


func road_speed() -> float:
	return 1.0 + GameData.c("ROAD_BONUS")[road_tier()]


func wall_kind() -> String:
	return "stone" if has_tech("walls2") else "wood"


func on_road(u: Dictionary, wp: Dictionary) -> bool:
	if roads.is_empty():
		return false
	if wp.has("enter"):
		return roads.has(link_key(u.prov, wp.enter))
	return u.has("lastProv") and roads.has(link_key(u.lastProv, u.prov))


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


# web: govtech.js pathNbr(u, a): open borders, plus walls whose gate the unit's nation holds
func path_nbr(u: Dictionary, a: int) -> Array:
	if walls.is_empty():
		return open_nbr[a]
	var out: Array = open_nbr[a].duplicate()
	var V: Array = world.vertices
	for i in walls:
		var e: Dictionary = world.edges[i]
		if e.a != a and e.b != a:
			continue
		var q: int = e.b if e.a == a else e.a
		if gate_ctl(link_key(e.a, e.b)) == u.owner:
			var x: Array = V[e.v[0]]
			var y: Array = V[e.v[1]]
			out.append({"q": q, "m": [(x[0] + y[0]) / 2, (x[1] + y[1]) / 2]})
	return out


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


func finish_link(b: Dictionary) -> void:
	var p: int = b.prov
	var q: int = b.to
	if b.type == "road":
		roads[link_key(p, q)] = true
		toast("Road finished. Units move %d%% faster along it." % JS.round_js(GameData.c("ROAD_BONUS")[road_tier()] * 100))
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
		wall_hp[i] = GameData.c("WALL_HP")[wall_kind()]
	open_nbr[p] = open_nbr[p].filter(func(n): return n.q != q)
	open_nbr[q] = open_nbr[q].filter(func(n): return n.q != p)
	var np: int = buildings[p].owner if buildings.has(p) else 0
	var nq: int = buildings[q].owner if buildings.has(q) else 0
	if not (np == owner and nq == owner):
		roads.erase(link_key(p, q))   # v106: a road between two provinces of the wall's own nation goes through the gate
	gate_own[link_key(p, q)] = {"home": home, "owner": owner}
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
func step_gpc(now: float) -> void:
	if now - gpc_slow_t >= 1 or now < gpc_slow_t:
		gpc_slow_t = now
		for p in buildings:
			if explored.has(p) and not surveyed.has(p):
				surveyed[p] = now
			for id in nations:   # GPC04: a claimed province's resources are known to every other nation
				var N: Dictionary = nations[id]
				if N.alive and buildings[p].owner != N.id:
					N.surveyed[p] = true
		if not nations.is_empty():
			evict_strays()
	step_retrofits()
	step_rest(now)
	step_fort_gates()


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


func dismiss(list: Array) -> void:
	for u in list:
		if u.build != null:
			cancel_build(u)
		u._gone = true
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
	extras[p] = extras_in(p).filter(func(x): return not is_same(x, e))
	xup.erase("%d@%d" % [p, slot])
	compute_income()
	toast("%s torn down. Plot %d is free." % [BUILD_DEFS[e.type].name, slot + 1])


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
		toast("Developed to level %d: +1 gold, wood and food%s.%s" % [L, (", and a lucky +1 " + r.luck[L]) if r.luck[L] != null else "", " A Deep Gold Deposit was found!" if deep else ""])
		compute_income()


func step_develop(d: float) -> void:
	var DEV: Dictionary = GameData.c("DEV")
	for p in devel:
		var r: Dictionary = devel[p]
		var o: int = buildings[p].owner if buildings.has(p) else 0
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
	"eyes": ["eyesforest"], "haunt": ["haunt"]}
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
const SPELL_MANA := {"harvest": "drain", "mending": 25, "graverob": "all", "haunt": 25, "trading": "all", "mind": 50, "stasis": 50, "rift": 100, "eyes": 25}
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
const SPELLS := ["harvest", "mending", "graverob", "trading", "mind", "stasis", "rift", "eyes", "haunt"]


func lvl(line: String) -> int:
	var n := 0
	for id in LINES[line]:
		if has_tech(id):
			n += 1
	return n


func line_tech(line: String) -> String:
	return LINES[line][maxi(0, lvl(line) - 1)]


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


func mana_mult() -> float:
	return WAND_MANA.get(mage_gear.weapon, 1.0)


func mc(n) :
	return JS.round_js(n * mana_mult()) if (n is int or n is float) else n


func spend_mana(c: Dictionary, n) -> void:
	c.mana = maxf(0.0, mana_of(c) - mc(n))


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


func see_nbrs(c: Dictionary) -> Array:
	return all_nbr[c.prov].filter(func(q): return _edge_between(c.prov, q, "trees", null) >= 0)


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
			toast("Mending on %s." % a.name)
		"mind", "graverob", "trading", "stasis":
			begin_cast(c, k)
			toast("%s: 3 s of casting." % TECH_BY_ID[line_tech(k)].name)
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
		"rift":
			var rw = rift_why(c, target) if target >= 0 else "Pick the province to teleport to"
			if rw != null:
				toast("Teleportation Rift: %s." % str(rw).to_lower(), true)
				return false
			begin_cast(c, "rift", {"to": target})
			toast("%s opens a rift: 3 s of casting." % c.name)
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
	sync_mana(now)
	for c in units.duplicate():
		var cs = c.get("cast")
		if cs == null or not is_caster(c):
			continue
		if cs.spell == "harvest" and not c.moving:
			c.mana = maxf(0.0, mana_of(c) - dt)
			if c.mana <= 0:
				cancel_cast(c, "%s has run out of mana." % c.name)
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
	# healing over time
	for a in units:
		if a.get("heal") != null:
			var f := minf(1.0, (now - a.heal.t0) / a.heal.dur)
			a.wounds = a.heal.w0 * (1 - f)
			if f >= 1:
				a.heal = null
	if trap != null:
		for v in units:
			if v.kind == "army" and hostile(v.owner, ME) and v.prov == trap.prov and troop_count(v) > 0:
				var n: int = int(JS.round_js(STASIS[maxi(1, lvl("stasis"))] * pow(1.1, rep_lv("rep-stasis"))))
				v.stasisUntil = now + n
				v.path = []
				v.moving = false
				trap = null
				toast("%s is caught in the stasis trap for %d s!" % [v.name, n])
				break
	for a in units:
		if a.get("stasisUntil", 0.0) > now and a.moving:
			a.path = []
			a.moving = false
	reveals = reveals.filter(func(r): return r.until > now)
	cd.erase("stasis")
	var n0 := eyes.size() + haunts.size()
	eyes = eyes.filter(func(r): return r.until > now)
	haunts = haunts.filter(func(r): return r.until > now)
	if eyes.size() + haunts.size() != n0:
		compute_fog()


# ---------------------------------------------------------------------------------------------------------------
# saving and loading (web: save.js keeps the seed and regenerates the map; this is the Godot format)

const SAVE_VERSION := 1
## Everything a game is, besides the map (which comes back from the seed) and the callbacks.
const SAVE_FIELDS := ["battles", "bandit_count", "monster_count", "leader", "capital", "stock", "income", "income_parts", "buildings", "extras", "occ", "units", "next_id",
	"army_counter", "tech", "rep", "surveyed", "unit_defs", "designs", "exhaust", "exhaust_ok", "harvest", "devel", "upgrades",
	"xup", "auto_tech", "roads", "walls", "wall_hp", "gate_own", "fort_walled", "gpc_slow_t", "dev_t", "cd", "paths",
	"harvest_by", "trap", "reveals", "eyes", "haunts", "mana_pool", "mana_prev_t", "mage_gear", "finds", "treasure_rolled",
	"sp_found", "setpieces", "travelers", "train_orders", "train_order_seq", "design_seq", "prov_rename", "nations", "players", "race_of", "wars", "truces", "allies", "war_seq", "met", "occ", "occ_prog", "dipl", "war_log", "war_ever", "war_lock", "ai_met", "fallen", "ally_check", "bandit_next", "bandit_waves", "ally_ask", "crop_scan_at", "ai_scout_t", "wf", "known", "explored", "visible", "queues", "rally", "military", "UNIT_SPEED", "open_nbr", "all_nbr",
	"yields", "tree_border", "t", "next_tick", "paused", "last", "started"]


## The whole game as a plain Dictionary (see SaveCodec for the text form).
func to_save() -> Dictionary:
	var d := {"version": SAVE_VERSION, "seed": str(world.seed).trim_prefix("practice:"), "practice": world.get("practice", false), "mode": world.get("mode", "practice")}
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
	return d


func save_text() -> String:
	return SaveCodec.to_text(to_save())


## A game from to_save(); `map` may be a ready map for the same seed (tests reuse one).
static func from_save(d: Dictionary, map: Dictionary = {}) -> Game:
	if int(d.get("version", 0)) != SAVE_VERSION:
		push_error("Unknown save version %s" % d.get("version"))
		return null
	var g := Game.new()
	if d.get("mode", "practice") == "normal":
		g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_world(d.seed, null, true))
		g.world.mode = "normal"
	else:
		g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_practice(d.seed))
	g.G = WorldPrep.prep(g.world)   # province shapes come from the map as generated, before walls and paths
	for i in d.edges.size():
		g.world.edges[i].open = d.edges[i][0]
		g.world.edges[i].style = d.edges[i][1]
	for i in d.terrain.size():
		g.G.provs[i].terrain = d.terrain[i]
	for f in SAVE_FIELDS:
		g.set(f, d[f])
	for x in g.designs:
		if not x.get("builtin", false):
			g.register_design(x)
	for id in g.nations:   # the computer nations' own designs
		for x in g.nations[id].get("designs", []):
			g.register_design(x)
	for u in g.units:
		if u.get("battle") != null:
			u.battle = g.battles[u.battle]
		if u.get("retro") != null:   # the job in its building's queue is the same object
			for key in g.queues:
				for q in g.queues[key]:
					if q.get("retro", false) and q.army == u.id:
						u.retro = q
	g.mana_prev = {}
	for id in d.mana_prev:
		for u in g.units:
			if u.id == id:
				g.mana_prev[id] = u
	g.rng.seed = d.rng[0]
	g.rng.state = d.rng[1]
	return g


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
	var R = GameData.c("RNG_BY_KIND").get(k)
	if R != null:
		var tr := (2 if tech_of(o, R.techs[1]) else 1) if tech_of(o, R.techs[0]) else 0
		if tr:
			out = out.duplicate()
			out.atk = out.atk + RNG_ATK[tr] - RNG_ATK[0]
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


func side_strength(armies: Array, prov: int, defender: bool, foe: Dictionary) -> float:
	var ter: String = world.provinces[prov].terrain
	var s := 0.0
	for a in armies:
		for k in a.troops:
			var st := stats_of(k, a.owner)
			var blows := row_deal(a, k)
			if st.get("crit", 0) and blows:
				var c := 0
				for i in int(blows):
					if battle_rand.call() < st.crit:
						c += 1
				blows += c
			s += blows * st.atk * terrain_mod(ter, st.get("cav", false) and not st.get("rough", false), defender) \
				* ((1 + 0.5 * foe.cavFrac) if st.get("fam") == "pole" else 1.0) * ((1 + 0.5 * foe.plateFrac) if st.get("fam") == "blunt" else 1.0) \
				* (1 + a.get("curse", 0.0))
	return s


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
				toast("Battle in the %s! %s." % [world.provinces[p].terrain, TERRAIN_MOD[world.provinces[p].terrain]])
		for a in list:
			if a.get("battle") == null and pair.has(a.owner):
				on_battle_join(a, now)
				a.battle = b
				a.path = []
				a.moving = false
				a.retreatHome = false
				b.start[a.owner] = b.start.get(a.owner, 0) + troop_count(a)
	for b in battles.duplicate():
		var sides := {}
		for a in units:
			if a.kind == "army" and is_same(a.get("battle"), b) and not a.get("retreating", false) and troop_count(a) > 0:
				if not sides.has(a.owner):
					sides[a.owner] = []
				sides[a.owner].append(a)
		var owners: Array = sides.keys()
		place_sides(b, sides)
		if owners.size() < 2:
			end_battle(b, owners[0] if owners.size() else -1, sides)
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
		for o in owners:
			for a in sides[o]:
				if troop_count(a) <= 0:
					war_wipe(b, a)
					if a.get("bandit", false):
						bandit_slain(a, b)
					remove_army(a)


func remove_army(a: Dictionary) -> void:
	a._gone = true
	units = units.filter(func(v): return not is_same(v, a))
	if a.owner == ME:
		compute_income()


func apply_damage(b: Dictionary, armies: Array, dmg: float, now: float, pierce := 0.0) -> void:
	var total := 0
	for a in armies:
		total += troop_count(a)
	if not total:
		return
	var mix := side_mix(armies)
	dmg *= (1 - mix.red * (1 - 0.5 * pierce)) * (1 - mix.parry)
	var owner: int = armies[0].owner
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
			a.troops[k] -= 1
			if not a.troops[k]:
				a.troops.erase(k)
			if a.get("monster") != null:
				monster_loot(a, k, b)
			if a.has("fallen"):
				a.fallen[k] = a.fallen.get(k, 0) + 1
			b.lost[owner] = b.lost.get(owner, 0) + 1


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
	if winner == ME:
		toast("Victory in the %s! You lost %d, the enemy lost %d.%s" % [where, mine, theirs, " The Bandit Gang is broken: +%d gold bounty." % b.bounty if b.has("bounty") else ""])
	elif b.get("retreatedMe", false):
		toast("You withdrew from the %s. You lost %d, the enemy lost %d." % [where, mine, theirs], true)
	else:
		toast("Defeat in the %s. You lost %d, the enemy lost %d." % [where, mine, theirs], true)
	compute_income()


func bandit_slain(a: Dictionary, b: Dictionary) -> void:
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


func _auto_on(c: Dictionary, k: String) -> bool:
	return c.get("auto") == null or not (c.auto is Dictionary) or c.auto.get(k, true) != false


func on_battle_end(a: Dictionary, now: float) -> void:
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
	if world.get("mode", "") != "normal":
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
	for u in units:
		if not u.get("bandit", false) or u.kind != "army" or troop_count(u) <= 0:
			continue
		if u.get("battle") != null or u.moving or not hostiles_in(u.prov, u.owner).is_empty():
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
	return true


# web: govtech.js stepScouts: a Wayfinder or Mason who meets enemy soldiers runs back the way he came; marked for 15 s
# after, a second meeting gives a friendly army 5 s to reach him before he is caught (sneaking comes with Stealth)
const SCOUT_MARK := 15.0
const SCOUT_RESCUE := 5.0

func step_scouts(now: float) -> void:
	for u in units.duplicate():
		if u.kind != WAYFINDER and u.kind != MASON:
			continue
		var mine: bool = u.owner == ME
		if mine and u.get("stealth", false) and not has_tech("stealth"):
			u.stealth = false
		if u.get("stealth", false):
			continue
		if u.get("warFlee", false) and not u.get("fleeing", false) and not u.moving:
			u.warFlee = false
			u.markUntil = now + SCOUT_MARK
		var foe = null
		for v in units:
			if v.kind == "army" and (not v.get("bandit", false) or u.kind == MASON) and hostile(v.owner, u.owner) and v.prov == u.prov and not v.get("retreating", false) and troop_count(v) > 0:
				foe = v
				break
		if foe != null and foe.get("bandit", false) and mine:
			foe.seen = true
		var guard: bool = foe != null and units.any(func(v): return v.kind == "army" and v.owner == u.owner and v.prov == u.prov and troop_count(v) > 0)
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
			continue
		u.fleeing = true
		u.warFlee = true
		if mine:
			toast("%s spotted %s at %s and is running back to %s." % [u.name, foe.name, prov_name(u.prov), prov_name(back)], true)


# =================================================================================================================
# Army Training Orders (web: v106.js 50–54): soldiers ordered at once, trained by every Barracks, gathered in one province
var train_orders := []
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
	if on_dialog.is_valid():
		on_dialog.call("Discovery! %s at %s" % [D.name, prov_name(p)], text, [{"id": "ok", "label": "OK", "why": null}], Callable())
	else:
		toast("Discovery! %s at %s." % [D.name, prov_name(p)])


# =================================================================================================================
# lost bands of travelers (web: v78.js SMA01): fed, they join you as Footmen; an army can rob them instead
const TRAVELERS := {"foodEach": 20, "goldEach": 30, "sizes": [3, 4, 5]}
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


func step_travelers(dt: float) -> void:
	for B in travelers:
		# a slow amble about their province (looks only: the web game rolls Math.random here)
		if B.tx == null:
			B.wait -= dt
			if B.wait <= 0:
				var P: Dictionary = G.provs[B.prov]
				var q: Array = P.inner[randi() % P.inner.size()]
				var f := 0.35 + randf() * 0.3
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
				B.wait = 6 + randf() * 10
			else:
				B.x += dx / d * sp
				B.y += dy / d * sp
				B.dir = -1 if dx < 0 else 1
		var here := units.any(func(u): return u.owner == ME and u.prov == B.prov and not u.moving)
		if not here:
			B.asked = false
			continue
		if not B.asked and trav_asking == null and travelers_ask:
			B.asked = true
			ask_travelers(B)


func trav_army_here(B: Dictionary) -> bool:
	return units.any(func(u): return u.owner == ME and u.kind == "army" and u.prov == B.prov and troop_count(u) > 0 and u.get("battle") == null)


func ask_travelers(B: Dictionary) -> void:
	trav_asking = B
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
	if on_dialog.is_valid():
		on_dialog.call("A lost band of travelers at %s" % prov_name(B.prov), text, choices, travelers_choose)
	else:
		travelers_choose("leave")


func travelers_choose(how: String) -> void:
	var B = trav_asking
	if B == null:
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

func player_info(o: int) -> Dictionary:
	var k := str(o)
	if players.has(k):
		return players[k]
	return GameData.c("PLAYERS").get(k, {"name": "?", "color": "#888888", "light": "#cccccc"})


## A full-size game: the island with its unique provinces, you, and the computer nations in `slots`
## ("easy" / "moderate" / "difficult" / "closed"). web: menu.js startGame
static func new_world(seed: String, leader_id := "", slots := [], start := "center", map: Dictionary = {}) -> Game:
	var g := Game.new()
	g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_world(seed, null, true))
	g.world.mode = "normal"
	g.G = WorldPrep.prep(g.world)
	g.players = GameData.c("PLAYERS").duplicate(true)
	var NC: Array = GameData.c("NATION_COLORS")
	var NAT: Dictionary = GameData.c("NATION")
	g.players["1"] = {"name": NAT.get("name", "My Realm"), "color": NC[NAT.color][0], "light": NC[NAT.color][1]}
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
	g.assign_leader(leader_id)
	g.assign_ai_leaders()
	g.apply_leader_start(ME)
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
func spawn_ai_nations(slots: Array) -> void:
	nations.clear()
	var key := ",".join(slots.map(func(x): return str(x)))
	var r := Mulberry32.from_string(str(world.seed) + ":nations:" + key)
	var NC: Array = GameData.c("NATION_COLORS")
	var NAT: Dictionary = GameData.c("NATION")
	var colors := range(NC.size()).filter(func(i): return i != NAT.color)
	# Array.sort(() => r() - 0.5): V8's TimSort with a random comparator, reproduced by JS.sort_random
	var places: Array = JS.sort_random(GameData.c("AI_PLACES").duplicate(), r)
	var sw_places: Array = JS.sort_random(GameData.c("SW_AI_PLACES").duplicate(), r)
	var emblems: Array = JS.sort_random(GameData.c("FLAG_EMBLEMS").filter(func(e): return e != NAT.emblem), r)
	var caps := [capital]
	var reach := hops_list(capital)
	var k := 0
	var kr := 0
	var wd_names: Array = JS.sort_random(GameData.c("WD_AI_NAMES").duplicate(), r)
	var AI_IDS: Array = GameData.c("AI_IDS")
	var DIFF: Dictionary = GameData.c("AI_DIFF")
	var TITLES: Array = GameData.c("AI_TITLES")
	for i in slots.size():
		var diff: String = slots[i]
		if not GameData.c("DIFF_NAME").has(diff):
			continue
		var id: int = AI_IDS[i]
		var rc := "realm"
		var cap := pick_ai_capital(caps, reach, r, "grassland")
		race_of[id] = rc
		caps.append(cap)
		var cl: Array = NC[colors[k % colors.size()]]
		var name: String = TITLES[int(floor(r.next() * TITLES.size()))] + " of " + places[kr % places.size()]
		kr += 1
		players[str(id)] = {"name": name, "color": cl[0], "light": cl[1]}
		var D: Dictionary = DIFF[diff]
		var tech_state := {}
		for tr in GameData.c("TREE_KEYS"):
			tech_state[tr] = {"cur": null, "prog": 0, "bank": 0, "opts": [], "done": [], "tier": 0, "sticky": []}
		var warc := t + 60 + r.next() * 60
		var fam: String = D.family if D.get("family") != null else ["sword", "pole", "blunt"][int(floor(r.next() * 3))]
		var school = D.school if D.get("school") != null else ["life", "death", "arcane"][int(floor(r.next() * 3))]
		var N := {"id": id, "diff": diff, "name": name, "emblem": emblems[k % emblems.size()] if k < emblems.size() else GameData.c("FLAG_EMBLEMS")[k % GameData.c("FLAG_EMBLEMS").size()],
			"alive": true, "capital": cap, "stock": GameData.c("START_STOCK").duplicate(), "rep": {}, "surveyed": {cap: true}, "exhaust": 0,
			"ups": {}, "xups": {}, "tech": tech_state, "queue": [], "think": t + 1 + i * 0.37, "nextOutpost": 0, "phase": "grow",
			"stuckSince": null, "warCheck": warc, "family": fam, "armorLine": D.armor, "race": rc, "school": null, "wantSchool": school,
			"spellT": 0, "dv": 0, "design": {"inf": "d-sword", "cav": "d-rider"}, "armyN": 0, "income": {"gold": 0, "wood": 0, "food": 0}}
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
		ai_new_army(N, cap, {"d-sword": 3})
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



# =================================================================================================================
# war state and the basic questions about it (web: war.js); the rules of war follow in the next step
var wars := []              # {id, a, b, by, base, since, nextTick, battles, active, winStart, peak, parent, demandAt}
var truces := {}            # "x:y" -> the time the truce ends
var allies := []            # {a, b}
var war_seq := 0
var met := {}               # nations the player has met
var dipl := {"access": []}  # v105: military access given {from, to}

func nation_of(p: int) -> int:
	return buildings[p].owner if buildings.has(p) else 0


func is_nation(o: int) -> bool:
	return o == ME or nations.has(o)


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
var demand = null           # a computer nation's demand to the player, waiting for an answer
var ally_offer = null
var ally_ask := {}          # nation -> when it may offer an alliance again
var fallen := false
var war_last_t := -1.0
var met_at := -9.0
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
	return (not fallen) if o == ME else (nations.has(o) and nations[o].alive)


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
	return has_tech(id) if o == ME else (ai_has(nations[o], id) if nations.has(o) else false)


func moat_delay(b: Dictionary, by: int) -> float:
	return 10.0 if by != b.owner and b.stage >= 1 and is_nation(b.owner) and tech_of(b.owner, "moat") else 0.0


func news(msg: String, warn := false) -> void:
	toast(msg, warn)


# --- v105 opinion: what a computer nation thinks of another ---
const DIPL := {"ally": 50, "trade": 25, "crime": 25, "war": -200, "race": -200, "fort": -25, "den": -25, "difficult": -25,
	"like": 50, "dislike": -25, "boss": 25, "threat": -100, "threatProvs": 100, "exhPer": 2, "exhDeclare": 50}

func dipl_state() -> Dictionary:
	for kv in [["decl", {}], ["boss", {}], ["mods", []], ["access", []], ["trade", []], ["crime", []], ["lost", {}], ["news", []], ["enemy", {}]]:
		if not dipl.has(kv[0]):
			dipl[kv[0]] = kv[1].duplicate()
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
		D[kind] = D[kind].filter(func(P): return not ((P.a == att and P.b == def) or (P.a == def and P.b == att)))
	if parent != null:
		w.proxy = def
		w.cost0 = army_value(def)
		w.lost0 = D.lost.get(def, 0)
		w.exhB = 0
	else:
		for c in wars:
			if not is_same(c, w) and c.get("proxy") == def:
				c.exhB = c.get("exhB", 0) + DIPL.exhDeclare
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
	upgrades.erase(p)
	occ.erase(p)
	occ_prog.erase(p)
	for k in xup.keys():
		if str(k).begins_with("%d@" % p):
			xup.erase(k)
	for u in units:
		if u.build != null and u.build.prov == p:
			cancel_build(u)
		if u.get("pending") != null and u.pending.prov == p:
			u.pending = null
	if to == ME:
		surveyed[p] = t
		known[p] = true
	if has_method("ai_on_transfer"):
		call("ai_on_transfer", p, from, to)
	# v102: a conquered capital stays a Conquered Capital (a fort), and becomes the capital again when won back
	if was_cap:
		if cc.of == to and is_nation(to) and capital_of(to) < 0:
			b.stage = 2
			b.cc = false
			if to == ME:
				capital = p
		else:
			b.stage = 1
			b.cc = true
			b.ccOf = cc.of
	else:
		b.cc = false
	var list := extras_in(p)
	var cap := plot_cap(p)
	if list.size() > cap:
		list = JS.stable_sort(list.duplicate(), func(x, y): return x.slot - y.slot).slice(0, cap)
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
	var loser := foe_of(w, winner)
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
		toast("Peace with the %s! %s. Truce for %d minutes." % [player_info(foe_of(w, ME)).name, ". ".join(lines), W("truce") / 60])
	elif knows(winner) or knows(loser):
		news("The %s and the %s made peace. %s." % [Wn, player_info(loser).name, ". ".join(lines)])


func kill_nation(o: int, by: int) -> void:
	if not nations.has(o) or not nations[o].alive:
		return
	nations[o].alive = false
	units = units.filter(func(v): return v.owner != o)
	for w in wars_of(o):
		end_war(w)
	allies = allies.filter(func(A): return A.a != o and A.b != o)
	for p in provs_of(o):
		if by:
			transfer_prov(p, by)
		else:
			buildings.erase(p)
			extras.erase(p)
	if knows(o):
		toast("The %s is no more%s." % [player_info(o).name, (": its land now belongs to %s" % the_name(by)) if by and by != o else ""])


func game_over(winner: int) -> void:
	fallen = true
	units = units.filter(func(v): return v.owner != ME)
	for w in wars_of(ME):
		end_war(w)
	allies = allies.filter(func(A): return A.a != ME and A.b != ME)
	if on_game_over.is_valid():
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
	if on_dialog.is_valid():
		on_dialog.call("The %s demands peace" % player_info(foe).name, "They are winning the war and demand peace. They want %s." % what,
			[{"id": "yes", "label": "Accept", "why": null}, {"id": "no", "label": "Refuse", "why": null}], func(id): answer_demand(id == "yes"))


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


func offer_alliance(from: int, vs: int) -> bool:
	if ally_offer != null or demand != null:
		return false
	ally_offer = {"from": from, "vs": vs, "t": t}
	if on_dialog.is_valid():
		on_dialog.call("The %s proposes an alliance" % player_info(from).name,
			"They fear the %s (%d provinces) and propose an alliance: if anyone declares war on one of you, the other joins the war." % [player_info(vs).name, provs_of(vs).size()],
			[{"id": "yes", "label": "Ally", "why": null}, {"id": "no", "label": "Decline", "why": null}], func(id): answer_alliance(id == "yes"))
	return true


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
		if o != ME and nations.has(o) and not met.has(o) and explored.has(p):
			meet_nation(o)
	for u in units:
		if u.owner == ME and u.kind == WAYFINDER:
			for q in all_nbr[u.prov]:
				var o := nation_of(q)
				if o and o != ME and nations.has(o) and not met.has(o):
					meet_nation(o)


func meet_nation(o: int) -> void:
	if met.has(o):
		return
	met[o] = true
	if on_dialog.is_valid():
		var N: Dictionary = nations[o]
		var al := allies_of(o)
		on_dialog.call("You have met the %s" % player_info(o).name, "%d province%s · %s%s%s. You can see them now in Diplomacy." % [provs_of(o).size(), "" if provs_of(o).size() == 1 else "s",
			GameData.c("DIFF_NAME")[N.diff], (" · allied with " + the_name(al[0])) if not al.is_empty() else "", " · at war with you" if at_war(ME, o) else ""],
			[{"id": "ok", "label": "OK", "why": null}], Callable())


# --- every half second (web: v105.js stepDiplomacy, without the player's diplomatic actions yet) ---
var dx_step_t := -1.0

func step_diplomacy() -> void:
	if not started or fallen:
		return
	if t - dx_step_t < 0.5 and t >= dx_step_t:
		return
	dx_step_t = t
	var D := dipl_state()
	D.mods = D.mods.filter(func(m): return m.until > t)
	for A in allies.duplicate():
		for xy in [[A.a, A.b], [A.b, A.a]]:
			if nations.has(xy[0]) and alive_nation(xy[0]) and alive_nation(xy[1]) and opinion(xy[0], xy[1]) < 0 and allies.has(A):
				end_alliance(A, "the %s’s opinion of you fell below zero" % player_info(xy[0]).name if xy[1] == ME else "opinion fell below zero")
	for kind in ["trade", "crime"]:
		for P in D[kind].duplicate():
			if not alive_nation(P.a) or not alive_nation(P.b) or at_war(P.a, P.b) or (kind == "trade" and not nations_border(P.a, P.b)):
				D[kind].erase(P)
	D.access = D.access.filter(func(g): return alive_nation(g.from) and alive_nation(g.to) and not at_war(g.from, g.to))



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
	var D := enemy_state()
	D.enemy[o] = {"t": t2, "since": t}
	D.enemyAt[o] = t
	if o == ME:
		toast("You proclaim the %s your enemy: %d opinion with them for as long as it stands. Nations with the same enemy like you more (+%d)." % [player_info(t2).name, DIPL_ENEMY, DIPL_SHARED])
	elif t2 == ME:
		toast("The %s proclaimed you their enemy!" % player_info(o).name, true)


func renounce_enemy(o: int) -> void:
	var D := enemy_state()
	var r = D.enemy.get(o)
	if r == null:
		return
	D.enemy.erase(o)
	if o == ME:
		toast("You renounce your proclamation against the %s." % player_info(r.t).name)
	elif r.t == ME:
		toast("The %s no longer proclaims you their enemy." % player_info(o).name)
