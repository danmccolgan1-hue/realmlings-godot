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
	"Shield Footman": {"name": "Shield Footman", "cost": {"gold": 90, "wood": 10}, "upkeep": {"food": 2}, "design": true,
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
	unit_defs = GameData.c("UNIT_DEFS").duplicate(true)
	stock = GameData.c("START_STOCK").duplicate()


## A new Practice-island game, as menu.js startGame() runs it for a Realmling player with every computer slot closed.
## leader: a Realmling leader id ("havva", "finn", ...) or "" for a random one.
static func new_practice(seed: String, leader_id := "", map: Dictionary = {}) -> Game:
	var g := Game.new()
	g.world = map if not map.is_empty() else RealmGen.scale_world(RealmGen.generate_practice(seed))
	g.G = WorldPrep.prep(g.world)
	g.setup_game()
	g.assign_leader(leader_id)
	g.apply_leader_start()
	g.compute_income()
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
		"path": [], "moving": false, "build": null, "survey": null, "scouting": null, "surveyQueue": [], "pendingSurvey": -1}


# web: game.js slotPos()
func slot_pos(prov: int, k: int) -> Array:
	var ic: Array = G.provs[prov].ic
	var o: Array = SLOTS[k % SLOTS.size()]
	return [ic[0] + o[0], ic[1] + o[1]]


# web: game.js freeSlot()
func free_slot(prov: int, u) -> int:
	var used := {}
	for v in units:
		if v != u and v.prov == prov and v.slot >= 0:
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
	unit_defs[id] = def
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
	var dev := 0
	for p in devel:
		var r: Dictionary = devel[p]
		if r.get("lv", 0) and buildings.has(p) and buildings[p].owner == ME and buildings[p].stage >= 1:
			dev += r.lv
	return forts * (1 + per_fort) + dev


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
	if next_tick == 0.0:
		next_tick = t + TICK
	while t >= next_tick:
		var nt := next_tick
		next_tick += TICK
		payday(nt)
	clamp_stock()
