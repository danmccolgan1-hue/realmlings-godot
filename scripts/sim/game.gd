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
var occ := {}                # province -> occupier (wars: always empty in milestone 1)
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
	DSTATS = GameData.c("DSTATS")
	SLOTS = GameData.c("SLOTS")
	UNIT_SPEED = GameData.c("UNIT_SPEED").duplicate()
	SPEED = GameData.c("SPEED")
	WAYFINDER = GameData.c("WAYFINDER")
	unit_defs = GameData.c("UNIT_DEFS").duplicate(true)
	for k in GameData.c("MILITARY"):
		military[k] = true
	# the Realmlings' Armory starts with these designs (web: equip.js; the other races' designs never train here)
	for d in [["d-spear", "inf"], ["d-sword", "inf"], ["d-club", "inf"], ["d-rider", "cav"]]:
		designs.append({"id": d[0], "name": unit_defs[d[0]].name, "type": d[1], "race": "realm"})
	stock = GameData.c("START_STOCK").duplicate()
	dev_rand = rng.randf


## A new Practice-island game, as menu.js startGame() runs it for a Realmling player with every computer slot closed.
## leader: a Realmling leader id ("havva", "finn", ...) or "" for a random one.
static func new_practice(seed: String, leader_id := "", map: Dictionary = {}) -> Game:
	var g := Game.new()
	g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_practice(seed))
	g.G = WorldPrep.prep(g.world)
	g.setup_game()
	g.place_ruins()
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

# web: game.js setupGame() (start position "center"; the player's land is grassland)
func setup_game() -> void:
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
	var cands := []
	for i in G.provs.size():
		if G.provs[i].terrain == home_ter:
			cands.append(i)
	if cands.is_empty():
		cands = range(G.provs.size())
	var best := -1
	var bs := -INF
	for i in cands:
		var P: Dictionary = G.provs[i]
		var fit: float = open_nbr[i].size() * 420 - (2000 if P.coastal or P.lakeside else 0)
		var d := JS.hypot(P.ic[0] - mx, P.ic[1] - my)
		var sc := fit - d
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


func leader_of():
	return LEADERS.get(leader)


func apply_leader_start() -> void:
	var L = leader_of()
	var cap := capital
	if L == null or cap < 0:
		return
	match L.start:
		"mage":
			add_start_extra(cap, "magetower")
			set_start_army({GameData.c("MAGE"): 1})
			for k in RES:
				stock[k] = stock.get(k, 0) + 200
		"stable":
			add_start_extra(cap, "stable")
			add_start_tech("stable")
			set_start_army({"d-rider": 2})
		"shield":
			add_start_extra(cap, "barracks")
			add_start_tech("s-round")
			set_start_army({leader_design(LEADER_DESIGNS["Shield Footman"]): 6})
		"forge":
			add_start_extra(cap, "forge")
			add_start_tech("forge")
		"lumber":
			ensure_woodlines(cap, 2)
			add_start_extra(cap, "lumber")
			add_start_extra(cap, "lumber")
		"scouts":
			add_start_scouts(2)
			add_start_tech("autoscout")
			add_start_tech("stealth")
			add_start_tech("farsight")
	# v106: the Horsemistress starts with 4 riders, her Stable costs no upkeep, and the capital grows 7 more food
	if L.start == "stable":
		set_start_army({"d-rider": 4})
		for e in extras_in(cap):
			if e.type == "stable":
				e.freeFor = ME
				break
		yields[cap].food += GameData.c("LEADER_CAP_FOOD")
		compute_income()


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
func add_start_tech(id: String) -> void:
	var x = TECH_BY_ID.get(id)
	if x == null:
		return
	var st: Dictionary = tech[x.tree]
	if not st.done.has(id):
		st.done.append(id)
	st.opts.erase(id)
	if st.cur == id:
		st.cur = null
		st.prog = 0


# web: v105.js setStartArmy()
func set_start_army(troops: Dictionary) -> void:
	units = units.filter(func(v): return not (v.owner == ME and v.kind == "army" and v.prov == capital))
	if troops.is_empty():
		return
	new_army(capital, troops.duplicate())


# web: v105.js addStartScouts()
func add_start_scouts(total: int) -> void:
	var wf: String = GameData.c("WAYFINDER")
	var have := 0
	for v in units:
		if v.owner == ME and v.kind == wf:
			have += 1
	while have < total:
		var u := mk_unit(next_id, wf, "", capital, 5 + have)
		next_id += 1
		units.append(u)
		have += 1


# web: v105.js leaderDesign() for the player: reuse a design of that name, else add it to the Armory
func leader_design(d: Dictionary) -> String:
	for x in designs:
		if x.name == d.name:
			return x.id
	var id := "d%d" % (designs.size() - 3)   # web ids: the built-in designs have names, new ones count from d1
	designs.append({"id": id, "name": d.name, "type": d.spec.type, "race": d.spec.race, "spec": d.spec})
	military[id] = true
	var def := d.duplicate(true)
	def.erase("spec")
	def.erase("speed")
	unit_defs[id] = def
	UNIT_SPEED[id] = d.speed
	return id


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


# web: game.js plotCap() (no conquered capitals, no Auto-build outposts yet)
func plot_cap(p: int) -> int:
	if not buildings.has(p):
		return 0
	return GameData.c("PLOTS_BY_STAGE")[buildings[p].stage]


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


func provs_of() -> Array:
	var out := []
	for p in buildings:
		if buildings[p].owner == ME:
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
func dev_limit_bonus() -> int:
	var dev := 0
	for p in devel:
		var r: Dictionary = devel[p]
		if r.get("lv", 0) and buildings.has(p) and buildings[p].owner == ME and buildings[p].stage >= 1:
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
func leader_upkeep_cut(troops: Dictionary) -> int:
	if leader != "hisola":
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
func soldier_count() -> int:
	var n := 0
	var mage: String = GameData.c("MAGE")
	for v in units:
		if v.kind == "army" and v.owner == ME:
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
		step_magic(t, dt)
		step_gpc(t)
	clamp_stock()
	step_upgrades(t)
	if not paused:
		rally_arrivals()
	var d := 0.0
	if paused:
		dev_t = t
	else:
		d = 0.0 if dev_t < 0 or t < dev_t else t - dev_t
		dev_t = t
		d = minf(d, 1.0)
		step_develop(d)
	compute_fog()


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
	if u.owner != ME or u.get("exiting", false) or explored.has(q):
		return true
	if u.kind == WAYFINDER:
		return q == tgt or (u.autoWalk != null and q == u.autoWalk.to)
	return false


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
			if not prev.has(n.q) and can_enter(u, n.q, target):
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


# web: game.js order(u, target, quiet, pt)
func order(u: Dictionary, target: int, quiet := false, pt = null) -> bool:
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
					u.scouting = wp.enter if (u.kind == WAYFINDER and u.owner == ME and not explored.has(wp.enter)) else null
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
func place_ruins() -> int:
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
		if world.provinces[i].terrain == "swamp" and not buildings.has(i):
			any.append(i)
			if not near.has(i):
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
	if type == "outpost":
		if buildings.has(p):
			return "Already has a settlement"
		if not surveyed.has(p):
			return "Survey it first"
		if not borders_owned(p):
			return "Must border your land"
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
		for k in u.build.paid:
			stock[k] += u.build.paid[k]
	u.build = null


# the end of a build (web: game.js update(), "if (u.build) ...")
func finish_build(u: Dictionary) -> void:
	var b: Dictionary = u.build
	if b.type in ["road", "wall"]:
		finish_link(b)
	elif b.type != "outpost":
		if owned(u.prov):
			if not extras.has(u.prov):
				extras[u.prov] = []
			extras[u.prov].append({"type": b.type, "slot": b.slot, "born": t})
			toast("%s built." % BUILD_DEFS[b.type].name)
			compute_income()
		else:
			cancel_build(u)
			toast("The province is no longer yours: construction cancelled, resources refunded.", true)
	elif not buildings.has(u.prov):
		buildings[u.prov] = {"stage": 0, "born": t, "owner": u.owner}
		compute_income()
		toast("Outpost built. Its neighbors are now explored.")
	else:
		cancel_build(u)
		toast("Someone claimed this province first: outpost cancelled, resources refunded.", true)
	u.build = null


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
	for p in vis:
		exp[p] = true
	visible = vis
	explored = exp


func fog_state(i: int) -> String:
	return "visible" if visible.has(i) else "explored" if explored.has(i) else "unexplored"


# ---------------------------------------------------------------------------------------------------------------
# training (web: game.js trainable / train / stepTraining, swamp.js and v104.js trainable, v96.js rally points)

const QUEUE_MAX := 10


# web: game.js trainTime()
static func train_time(kind: String) -> float:
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
		if now - q.t0 < train_time(q.kind):
			continue
		Q.pop_front()
		var spot := src_spot(key)
		var d: Dictionary = unit_defs[q.kind]
		var rp = rally.get(key)
		if military.has(q.kind):
			var a = null
			if rp == null:
				for v in units:
					if v.kind == "army" and v.owner == ME and v.prov == spot.prov and not v.moving:
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
	for a in units.duplicate():
		if a.get("_gone", false) or a.kind != "army" or a.get("rallyTo") == null or a.owner != ME:
			continue
		if a.moving:
			continue
		if a.prov != a.rallyTo:
			a.rallyTo = null
			continue
		a.rallyTo = null
		var host = null
		for v in units:
			if not is_same(v, a) and v.kind == "army" and v.owner == ME and v.prov == a.prov and not v.moving and not v.get("exiting", false) \
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
	step_fort_gates()


func step_fort_gates() -> void:
	if not has_tech("walls"):
		return
	for p in buildings:
		var b: Dictionary = buildings[p]
		if b.stage < 1 or b.owner != ME:
			continue
		for n in open_nbr[p].duplicate():
			var key := "%d>%d" % [p, n.q]
			if fort_walled.has(key):
				continue
			fort_walled[key] = true
			if raise_wall(p, n.q, b.owner, p) and explored.has(p):
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


func dev_why(p: int):
	if not buildings.has(p):
		return "Needs an outpost, fort or capital"
	if buildings[p].owner != ME:
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
	return lack_text(dev_cost(lv))


func start_develop(p: int) -> bool:
	var why = dev_why(p)
	if why != null:
		toast("Can’t develop: %s." % str(why).to_lower(), true)
		return false
	var r: Dictionary = dev_rec(p, true)
	var c := dev_cost(r.lv)
	for k in c:
		stock[k] -= c[k]
	r.owner = ME
	r.job = {"done": 0.0, "paid": c, "by": ME}
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


func mana_cap() -> int:
	return MANA_CAPS[2] if has_tech("magicabund") else MANA_CAPS[1] if has_tech("magicwell") else MANA_CAPS[0]


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
	var r := 0
	for p in extras:
		if not owned(p) or occ.has(p):
			continue
		for e in extras[p]:
			if e.type == "magetower":
				r += MANA_REGEN[mini(3, e.get("level", 1))]
	var L = leader_of()
	if L != null and L.start == "mage":
		r += 4   # v105: a Mage leader's Mages regain 4 more
	for c in units:
		if mages_in(c) <= 0 or c.get("cast") != null:
			continue
		c.mana = minf(mana_cap(), mana_of(c) + r)


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
const SAVE_FIELDS := ["leader", "capital", "stock", "income", "income_parts", "buildings", "extras", "occ", "units", "next_id",
	"army_counter", "tech", "rep", "surveyed", "unit_defs", "designs", "exhaust", "exhaust_ok", "harvest", "devel", "upgrades",
	"xup", "auto_tech", "roads", "walls", "wall_hp", "gate_own", "fort_walled", "gpc_slow_t", "dev_t", "cd", "paths",
	"harvest_by", "trap", "reveals", "eyes", "haunts", "mana_pool", "mana_prev_t", "mage_gear", "finds", "treasure_rolled",
	"sp_found", "wf", "known", "explored", "visible", "queues", "rally", "military", "UNIT_SPEED", "open_nbr", "all_nbr",
	"yields", "tree_border", "t", "next_tick", "paused", "last", "started"]


## The whole game as a plain Dictionary (see SaveCodec for the text form).
func to_save() -> Dictionary:
	var d := {"version": SAVE_VERSION, "seed": str(world.seed).trim_prefix("practice:"), "practice": world.get("practice", false)}
	var edges := []
	for e in world.edges:
		edges.append([e.open, e.style])
	d.edges = edges
	d.terrain = G.provs.map(func(P): return P.terrain)
	for f in SAVE_FIELDS:
		d[f] = get(f)
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
	g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_practice(d.seed))
	g.G = WorldPrep.prep(g.world)   # province shapes come from the map as generated, before walls and paths
	for i in d.edges.size():
		g.world.edges[i].open = d.edges[i][0]
		g.world.edges[i].style = d.edges[i][1]
	for i in d.terrain.size():
		g.G.provs[i].terrain = d.terrain[i]
	for f in SAVE_FIELDS:
		g.set(f, d[f])
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
