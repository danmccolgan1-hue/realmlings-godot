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
	stock = GameData.c("START_STOCK").duplicate()


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
		tech[tr] = {"cur": null, "prog": 0, "bank": 0, "opts": [], "done": [], "tier": 1 if tr == "gov" else 0}
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
func new_army(prov: int, troops: Dictionary) -> Dictionary:
	army_counter += 1
	var a := mk_unit(next_id, "army", ordinal(army_counter) + " Army", prov, 0)
	next_id += 1
	a.troops = troops
	a.slot = free_slot(prov, a)
	var xy := slot_pos(prov, a.slot)
	a.x = xy[0]
	a.y = xy[1]
	units.append(a)
	return a


func cute_name() -> String:
	var names: Array = GameData.c("CUTE_NAMES")
	return names[rng.randi() % names.size()]


static func ordinal(n: int) -> String:
	var w := ["First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth", "Tenth"]
	if n <= w.size():
		return w[n - 1]
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		suf = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
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
	var id := "d%d" % (designs.size() + 1)
	designs.append({"id": id, "name": d.name, "spec": d.spec})
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
	clamp_stock()
	step_upgrades(t)
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
		for n in open_nbr[a]:
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
				sp = SPEED * unit_speed(u) / (SCOUT_SLOW if u.scouting != null else 1.0)
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
			add_start_tech(x.id)
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
	if b.type != "outpost":
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
	for p in vis:
		exp[p] = true
	visible = vis
	explored = exp


func fog_state(i: int) -> String:
	return "visible" if visible.has(i) else "explored" if explored.has(i) else "unexplored"
