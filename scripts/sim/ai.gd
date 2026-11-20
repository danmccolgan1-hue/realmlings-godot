class_name Ai
extends RefCounted
## The computer nations (web: ai.js and the wrappers in v95–v106 that replace its functions). Every function takes the
## Game it plays in (`g`) and, most of them, the nation's state (`N`, a dictionary in `g.nations`). Rules only: nothing
## here draws. Realmling nations only (the Swampling and Woodling branches come with those races).
##
## Port notes: each function says which web function it is and which wrappers it already includes ("+ v103" means the
## v103.js wrapper's behaviour is part of it). Where the web game replaced a function outright the last version is the
## one ported.

const KEY_BUILDINGS := ["barracks", "magetower", "forge", "temple", "goldmine"]
const AI_MAGIC_LATE := 1800.0
const AI_WAR_THINK := 60.0
const AI_WAR_MARGIN := 1000.0
const AI_TIER_CAP := {"easy": 2, "moderate": 3, "difficult": 9}
const AI_EARLY_POWER := 3000.0
const AI_CAP_RESERVE := ["barracks", "forge", "magetower"]
const AI_SCHOOL_GOLD := 1.3
const AI_SCHOOL_WOOD := 1.0
const AI_SWAP_INTO := ["temple", "forge", "magetower", "market"]
const SHIELD_TIER := {"s-round": 1, "s-kite": 2, "s-tower": 3}
const AI_SURGE := {"moderate": {"time": 12.0, "cost": 1.0}, "difficult": {"time": 6.0, "cost": 0.5}}
const AI_RAID_MIN_PUSH := 5
const AI_ENGAGE := 1.2
const AI_RNG_SHARE := {"easy": 0.15, "moderate": 0.25, "difficult": 0.3}
const AI_SIEGE_HOPS := 3
const BANK_STORE := {"gold": 1000}
const FORGE_LEADERS := ["finn", "glurg", "alathandrious"]
const LUMBER_LEADERS := ["weylyn", "roxx"]
const CROP_PLUS := {"staple": "food", "cash": "gold", "fiber": "wood"}
const CASH_GIVES := {"food": 3, "gold": 1}
const FIBER_GIVES := {"wood": 2}
const CROP_DELAY := 10.0
const CD_NAMES := ["Pikeman", "Maceman"]
# v104 stances and rivals
const V104_THINK := 10.0
const V104_LARGER := 1.15
const V104_ECON := 1.1
const V104_ARMY := 2.0
const V104_RIVAL_RATIO := {"easy": INF, "moderate": 1.3, "difficult": 1.0}
const V104_RIVAL_GOAL := 1.3
const V104_WARY_GOAL := 0.8
const V104_WAR_TYPES := ["farm", "lumber", "barracks", "forge", "magetower", "stable"]
const V104_DEMOLISH := ["bank", "storehouse", "granary", "market", "goldmine", "temple", "lumber"]
const V104_ECON_TECHS := ["advmills", "refmills", "sophmills", "advmines", "refmines", "sophmines", "market", "traderoutes",
	"rep-trade", "thugs2", "thugs3", "bank", "storehouse", "granary", "rep-storage", "rep-lumber", "retained", "retained2", "roads",
	"roads2", "roads3", "autoscout"]
const V104_DEFENSE_TECHS := ["walls", "walls2", "moat", "arrowslits"]
const V104_BATTLE_MAGIC := ["curse1", "curse2", "curse3", "risen", "necro", "armyofdeath", "fiery1", "fiery2", "fiery3", "firetrap",
	"blazetrap", "molttrap", "pathfire", "pathflame", "pathinferno", "wrocks", "gelemental"]
const V104_GUARD_MAGIC := ["skin", "stoneskin", "diamondskin", "mending", "rejuvenation", "restoration", "rockarmor", "stasis", "prison"]
const LINES_FOR_BATTLE := {"death": ["curse1", "risen", "curse2", "necro"], "pyro": ["fiery1", "firetrap", "fiery2"],
	"elemental": ["wrocks", "gelemental"], "life": ["skin", "mending", "stoneskin"], "arcane": ["stasis"]}
const AI_POWER_GOAL := {"easy": 4000.0, "moderate": 6000.0}


# ================================================================================================================
# small questions (web: ai.js top)

static func D(N: Dictionary) -> Dictionary:
	return GameData.c("AI_DIFF")[N.diff]


static func has(g: Game, N: Dictionary, id: String) -> bool:
	return g.ai_has(N, id)


static func rep(N: Dictionary, id: String) -> int:
	return int(N.rep.get(id, 0))


static func units_of(g: Game, N: Dictionary, kind: String) -> Array:
	return g.units.filter(func(v): return v.owner == N.id and v.kind == kind)


static func armies(g: Game, N: Dictionary) -> Array:
	return g.units.filter(func(v): return v.owner == N.id and v.kind == "army" and g.troop_count(v) > 0)


static func mages(g: Game, N: Dictionary) -> int:
	var n := 0
	for v in g.units:
		if v.owner == N.id and v.kind == "army":
			n += int(v.troops.get(Game.MAGE, 0))
	for q in N.queue:
		if q.kind == Game.MAGE:
			n += 1
	return n


## [[p, e], ...] for every building of the nation (web: aiExtraList)
static func extra_list(g: Game, N: Dictionary) -> Array:
	var out := []
	for p in g.extras:
		if g.nation_of(p) == N.id:
			for e in g.extras[p]:
				out.append([p, e])
	return out


static func has_building(g: Game, N: Dictionary, type: String) -> bool:
	for p in g.extras:
		if g.nation_of(p) == N.id and g.extras[p].any(func(e): return e.type == type):
			return true
	return g.units.any(func(u): return u.owner == N.id and u.build != null and u.build.type == type)


static func count(g: Game, N: Dictionary, type: String) -> int:
	var n := 0
	for pe in extra_list(g, N):
		if pe[1].type == type:
			n += 1
	for u in g.units:
		if u.owner == N.id and u.build != null and u.build.type == type:
			n += 1
	return n


# web: v103.js aiCountJ: buildings, building sites and Masons on their way to build one
static func count_j(g: Game, N: Dictionary, type: String) -> int:
	var n := count(g, N, type)
	for u in g.units:
		if u.owner == N.id and u.get("aiJob") != null and u.aiJob.type == type:
			n += 1
	return n


# web: ai.js armyPower / defPower, gpc.js nationPower
static func army_power(g: Game, o: int) -> float:
	if not o:
		return 0.0
	return g.raw_strength(g.units.filter(func(v): return v.kind == "army" and v.owner == o and g.troop_count(v) > 0))


static func def_power(g: Game, o: int) -> float:
	var n := army_power(g, o)
	for x in g.allies_of(o):
		n += army_power(g, x)
	return n


static func nation_power(g: Game, o: int) -> float:
	return JS.round_js(army_power(g, o) * 10)


static func can_pay(st: Dictionary, c: Dictionary) -> bool:
	for k in c:
		if st.get(k, 0) < c[k]:
			return false
	return true


static func pay(st: Dictionary, c: Dictionary) -> void:
	for k in c:
		st[k] -= c[k]


static func food(N: Dictionary) -> int:
	return int(N.get("income", {}).get("food", 0))


static func wood(N: Dictionary) -> int:
	return int(N.get("income", {}).get("wood", 0))


static func leader_id(g: Game, o: int) -> String:
	var L = g.leader_of(o)
	return L.id if L != null else ""


# web: v105.js BUILD_DEFS.forge.cost getter (costCtx): Forges cost 25% less for the forge leaders
static func build_cost(g: Game, N: Dictionary, type: String) -> Dictionary:
	var c: Dictionary = g.BUILD_DEFS[type].cost
	if type == "forge" and leader_id(g, N.id) in FORGE_LEADERS:
		var out := {}
		for k in c:
			out[k] = int(JS.round_js(c[k] * 0.75))
		return out
	return c


# ================================================================================================================
# forts and limits (web: ai.js aiForts / aiFortLimit / ..., govtech.js perFort / fortsHeldBy / provLimit)

static func forts(g: Game, N: Dictionary) -> int:
	var n := 0
	for p in g.buildings:
		if g.buildings[p].owner == N.id and g.buildings[p].stage == 1:
			n += 1
	return n


static func fort_limit(g: Game, N: Dictionary) -> int:
	var lv := 0
	for id in ["forts", "forts2", "forts3"]:
		if has(g, N, id):
			lv += 1
	return GameData.c("FORT_LIMIT")[lv] + 2 * rep(N, "rep-forts")


static func fort_count(g: Game, N: Dictionary) -> int:
	return forts(g, N) + N.ups.size()


static func outposts(g: Game, N: Dictionary) -> int:
	var n := 0
	for p in g.buildings:
		var b: Dictionary = g.buildings[p]
		if b.owner == N.id and b.stage == 0 and not N.ups.has(p):
			n += 1
	return n


static func per_fort(g: Game, o: int) -> int:
	return GameData.c("OUTPOSTS_PER_FORT") + (2 if g.tech_of(o, "effadmin") else 0) + 2 * (g.rep_lv("rep-admin") if o == Game.ME else rep(g.nations[o], "rep-admin"))


static func forts_held_by(g: Game, o: int) -> int:
	var n := 0
	for p in g.buildings:
		if g.buildings[p].owner == o and g.buildings[p].stage >= 1:
			n += 1
	return n


static func prov_limit(g: Game, o: int) -> int:
	return forts_held_by(g, o) * (1 + per_fort(g, o)) + g.dev_limit_bonus(o)


static func outpost_limit(g: Game, N: Dictionary) -> int:
	return per_fort(g, N.id) * forts_held_by(g, N.id) + g.dev_limit_bonus(N.id)


static func pending_outposts(g: Game, N: Dictionary, self_u = null) -> int:
	var n := 0
	for u in g.units:
		if u.owner == N.id and not is_same(u, self_u) and ((u.build != null and u.build.type == "outpost") or (u.get("aiJob") != null and u.aiJob.type == "outpost")):
			n += 1
	return n


static func prov_count(g: Game, N: Dictionary) -> int:
	return g.provs_of(N.id).size()


# ================================================================================================================
# the economy (same numbers as the player's)

# web: ai.js aiGives + swamp.js (Markets: MARKET_GIVES) + v105.js (Lumber leaders +1 wood)
static func gives(g: Game, N: Dictionary, type: String) -> Dictionary:
	if type == "market":
		return GameData.c("MARKET_GIVES").duplicate()
	var base: Dictionary = g.BUILD_DEFS[type].get("gives", {}).duplicate()
	var tg = GameData.c("TECH_GIVES").get(type)
	if tg != null:
		for id in tg[0]:
			if has(g, N, id):
				for k in tg[1]:
					base[k] = base.get(k, 0) + tg[1][k]
	if type == "lumber" and leader_id(g, N.id) in LUMBER_LEADERS:
		base.wood = base.get("wood", 0) + 1
	return base


# web: ai.js aiProvIncome + v106.js (a Deep Gold Deposit under a Gold Mine)
static func prov_income(g: Game, N: Dictionary, p: int, b: Dictionary) -> Dictionary:
	var y := {}
	for k in Game.RES:
		y[k] = g.yields[p][k] + (g.CAPITAL_BONUS[k] if b.stage == 2 or b.get("cc", false) else 0)
	var ex := g.extras_in(p)
	for e in ex:
		var gv := gives(g, N, e.type)
		for k in gv:
			y[k] += gv[k]
	if rep(N, "rep-lumber"):
		var lw := 0
		for e in ex:
			if e.type == "lumber":
				lw += int(gives(g, N, "lumber").get("wood", 0))
		y.wood += int(JS.round_js(lw * 0.05 * rep(N, "rep-lumber")))
	var r = g.dev_rec(p)
	if r != null and r.deep and ex.any(func(e): return e.type == "goldmine"):
		y.gold += GameData.c("DEV").deepGold
	return y


# web: ai.js aiUpkeep + v106.js upkeepAdjust (leader upkeep cuts, buildings that cost a nation nothing)
static func upkeep(g: Game, N: Dictionary) -> Dictionary:
	var u := {"gold": 0, "wood": 0, "food": 0}
	for v in g.units:
		if v.owner != N.id:
			continue
		if v.kind == "army":
			for tk in v.troops:
				var d = g.unit_defs.get(tk)
				if d != null:
					for k in d.get("upkeep", {}):
						u[k] += d.upkeep[k] * v.troops[tk]
			continue
		var d = g.unit_defs.get(v.kind)
		if d != null:
			for k in d.get("upkeep", {}):
				u[k] += d.upkeep[k]
	for p in g.buildings:
		var b: Dictionary = g.buildings[p]
		if b.owner != N.id:
			continue
		for e in g.extras_in(p):
			var up: Dictionary = g.BUILD_DEFS[e.type].get("upkeep", {})
			for k in up:
				u[k] += up[k]
		if b.stage == 0:
			for k in Game.OUTPOST_UPKEEP:
				u[k] += Game.OUTPOST_UPKEEP[k]
	for v in g.units:
		if v.owner == N.id and v.kind == "army":
			u.food -= g.leader_upkeep_cut(v.troops, N.id)
	for p in g.buildings:
		if g.buildings[p].owner == N.id:
			for e in g.extras_in(p):
				if e.has("freeFor") and e.freeFor == N.id:
					var up: Dictionary = g.BUILD_DEFS[e.type].get("upkeep", {})
					for k in up:
						u[k] -= up[k]
	for k in Game.RES:
		u[k] = maxi(0, u[k])
	return u


static func crop_of(e) -> String:
	return e.get("crop", "staple") if e != null else "staple"


static func crop_target(e) -> String:
	return e.get("cropNext", crop_of(e)) if e != null else "staple"


static func crop_gives(crop: String, staple: Dictionary) -> Dictionary:
	return CASH_GIVES.duplicate() if crop == "cash" else FIBER_GIVES.duplicate() if crop == "fiber" else staple.duplicate()


static func crop_up(g: Game, crop: String) -> int:
	return 0 if crop == "fiber" else int(g.BUILD_DEFS.farm.upkeep.get("wood", 0))


# web: v104.js fiberTaken: a province holds one Fiber crop (grown or on its way)
static func fiber_taken(g: Game, p: int, except = null) -> bool:
	return g.extras_in(p).any(func(x): return not is_same(x, except) and x.type == "farm" and ((crop_of(x) == "fiber" and not x.has("cropNext")) or x.get("cropNext") == "fiber"))


# web: v104.js setCrop
static func set_crop(g: Game, e: Dictionary, crop: String) -> void:
	if crop_of(e) == crop:
		e.erase("cropNext")
		e.erase("cropAt")
		return
	e.cropNext = crop
	e.cropAt = g.t + CROP_DELAY


# web: ai.js aiIncome + v104.js (crops, Harvest by crop) + v105.js (Ultanitous, Havva). v95.js artifacts come with them.
static func income(g: Game, N: Dictionary) -> Dictionary:
	var gross := {"gold": 0, "wood": 0, "food": 0}
	var up := upkeep(g, N)
	for p in g.buildings:
		var b: Dictionary = g.buildings[p]
		if b.owner == N.id and not g.occ.has(p):
			var y := prov_income(g, N, p, b)
			for k in Game.RES:
				gross[k] += y[k]
	var st := gives(g, N, "farm")
	var harvest_lv := 0
	for id in ["harvest", "bountiful", "magnificent"]:
		if has(g, N, id):
			harvest_lv += 1
	var harvesting: bool = N.school == "life" and has(g, N, "harvest") and mages(g, N) > 0
	if harvesting:
		var farm_food := 0
		for pe in extra_list(g, N):
			if pe[1].type == "farm":
				farm_food += int(st.get("food", 0))
		gross.food += int(JS.round_js(farm_food * (Game.HARVEST_PCT[harvest_lv] + 0.02 * rep(N, "rep-harvest"))))
	var inc := {}
	for k in Game.RES:
		inc[k] = gross[k] - up[k]
	# v104: crops
	var all := 0
	var cfood := 0
	var cgold := 0
	for pe in extra_list(g, N):
		var p: int = pe[0]
		var e: Dictionary = pe[1]
		if e.type != "farm":
			continue
		var c := crop_of(e)
		all += 1
		if c == "fiber":
			inc.wood += crop_up(g, "staple")
		if g.occ.has(p):
			continue
		var cg := crop_gives(c, st)
		cfood += int(cg.get("food", 0))
		cgold += int(cg.get("gold", 0))
		if c == "staple":
			continue
		for k in st:
			inc[k] -= st[k]
		for k in cg:
			inc[k] = inc.get(k, 0) + cg[k]
	if harvesting:
		var pct: float = Game.HARVEST_PCT[harvest_lv] + 0.02 * rep(N, "rep-harvest")
		inc.food += int(JS.round_js(cfood * pct)) - int(JS.round_js(all * st.get("food", 0) * pct))
		inc.gold += int(JS.round_js(cgold * pct))
	# v105: leaders
	var lid := leader_id(g, N.id)
	if lid == "ultanitous":
		for pe in extra_list(g, N):
			if pe[1].type == "farm" and not g.occ.has(pe[0]):
				inc[CROP_PLUS[crop_of(pe[1])]] += 1
	if lid == "havva" and harvesting:
		var f2 := 0
		var g2 := 0
		for pe in extra_list(g, N):
			if pe[1].type == "farm" and not g.occ.has(pe[0]):
				var cg := crop_gives(crop_of(pe[1]), st)
				f2 += int(cg.get("food", 0))
				g2 += int(cg.get("gold", 0))
		inc.food += int(JS.round_js(f2 * 0.05 * harvest_lv))
		inc.gold += int(JS.round_js(g2 * 0.05 * harvest_lv))
	return inc


# web: swamp.js aiStorage (a Realmling Bank stores 1000 gold)
static func storage(g: Game, N: Dictionary, k: String) -> int:
	var n: int = GameData.c("BASE_CAP") + 500 * rep(N, "rep-storage")
	for pe in extra_list(g, N):
		var type: String = pe[1].type
		var stv = BANK_STORE if type == "bank" else g.BUILD_DEFS[type].get("store")
		if stv != null and stv.has(k):
			n += stv[k]
	return n


# web: ai.js aiPayday: every payout (10 s), right after the player's
static func payday(g: Game) -> void:
	for id in g.nations:
		var N: Dictionary = g.nations[id]
		if not N.alive:
			continue
		var inc := income(g, N)
		N.income = inc
		var short: bool = N.stock.food + inc.food < 0
		for k in Game.RES:
			N.stock[k] = mini(storage(g, N, k), maxi(0, N.stock[k] + inc[k]))
		exhaustion(g, N, short)
		tech_payday(g, N)
		spells(g, N)


# web: ai.js aiExhaustion: every payout the army can't be fed adds 1; at 10 the whole army deserts
static func exhaustion(g: Game, N: Dictionary, short: bool) -> void:
	if short and g.soldier_count(N.id) > 0:
		N.exhaust += 1
		if N.exhaust >= GameData.c("EXHAUST_MAX"):
			for a in armies(g, N):
				g.remove_army(a)
			N.exhaust = 0
			if g.knows(N.id):
				g.toast("The %s couldn’t feed its soldiers: its whole army has deserted." % g.player_info(N.id).name)
		return
	if N.exhaust > 0 and N.income.food >= 0 and N.stock.food > 0:
		N.exhaust -= 1


# web: v98.js aiSpells (mana) + v105.js (Niall +100 gold, Alma +30%)
static func spells(g: Game, N: Dictionary) -> void:
	if N.school == null or not mages(g, N):
		return
	var sp: String = "graverob" if N.school == "death" else "trading" if N.school == "arcane" else ""
	if sp == "" or not has(g, N, sp):
		return
	N.spellT += g.TICK
	if N.spellT < Game.RES_CD:
		return
	var cs := g.units.filter(func(v): return v.owner == N.id and g.mages_in(v) > 0 and v.get("battle") == null and not v.get("quake"))
	cs = JS.stable_sort(cs, func(x, y): return Game.mana_of(y) - Game.mana_of(x))
	if cs.is_empty() or Game.mana_of(cs[0]) < 60:
		return
	var c: Dictionary = cs[0]
	N.spellT = 0
	var b0: Dictionary = N.stock.duplicate()
	var L := 0
	for id in (["graverob", "deathtax", "charon"] if sp == "graverob" else ["trading", "stockmarket", "planar"]):
		if has(g, N, id):
			L += 1
	var rp: float = 1 + 0.02 * rep(N, "rep-graverob" if sp == "graverob" else "rep-trading")
	var n := floori(Game.mana_of(c))
	c.mana = 0.0
	if sp == "graverob":
		N.stock.gold += int(JS.round_js(n * Game.GRAVE_RATE[L] * rp))
	else:
		for k in Game.RES:
			N.stock[k] += floori(n * Game.TRADE_RATE[L] * rp)
	var lid := leader_id(g, N.id)
	if lid == "niall" and N.school == "death" and N.stock.gold > b0.gold:
		N.stock.gold += 100
	if lid == "alma" and N.school == "arcane":
		for k in Game.RES:
			var d: int = N.stock[k] - b0[k]
			if d > 0:
				N.stock[k] += int(JS.round_js(d * 0.3))


# ================================================================================================================
# research (the player's trees, rules and costs)

# web: ai.js aiProvResearch + v105.js (a Mage leader: +1 Magic per tower)
static func prov_research(g: Game, N: Dictionary, p: int) -> Dictionary:
	var r := {"gov": 0, "mil": 0, "mag": 0}
	var b = g.buildings.get(p)
	if b == null or b.owner != N.id:
		return r
	var ex := g.extras_in(p)
	var LP: Array = GameData.c("LEVEL_POINTS")
	if not g.occ.has(p):
		if b.stage >= 1:
			r.gov += b.stage + 1
		r.gov += ex.filter(func(e): return e.type == "temple").size() * 2
	for e in ex:
		if e.type == "forge":
			r.mil += LP[e.get("level", 1)]
		elif e.type == "magetower":
			r.mag += LP[e.get("level", 1)]
	if not g.occ.has(p) and g.setpieces.has(p):
		var sp: Dictionary = g.SETPIECES[g.setpieces[p]]
		var tr: String = sp.tree
		if tr == "gov" or has_building(g, N, "forge" if tr == "mil" else "magetower"):
			r[tr] += sp.pts
	var L = g.leader_of(N.id)
	if L != null and L.get("start") == "mage":
		r.mag += ex.filter(func(e): return e.type == "magetower").size()
	return r


static func tech_rate(g: Game, N: Dictionary, tree: String) -> int:
	var n := 0
	for p in g.buildings:
		if g.buildings[p].owner == N.id:
			n += prov_research(g, N, p)[tree]
	return n


static func tier(g: Game, N: Dictionary, tree: String) -> int:
	if tree == "gov":
		var f := forts(g, N)
		return 1 + (1 if f >= 1 else 0) + (1 if f >= 2 else 0)
	var want := "forge" if tree == "mil" else "magetower"
	var best := 0
	for pe in extra_list(g, N):
		if pe[1].type == want:
			best = maxi(best, pe[1].get("level", 1))
	return best


static func tech_cost(g: Game, N: Dictionary, x: Dictionary) -> int:
	var rm := 1.0
	if x.get("rep", false) and not GameData.c("FLAT_REPS").has(x.id):
		rm = pow(GameData.c("REP_STEP"), rep(N, x.id))
	var tm: float = GameData.c("GOV_COST_MULT") if x.tree == "gov" else GameData.c("MIL_COST_MULT") if x.tree == "mil" else 1.0
	var n := prov_count(g, N)
	var cm := 1 + 0.05 * mini(10, maxi(0, n - 10)) + 0.15 * maxi(0, n - 20)
	return int(JS.round_js(x.cost * rm * tm * cm))


# web: wood.js techFor (raceIs: no race, the race, or a list that has it)
static func tech_for(x: Dictionary, race: String) -> bool:
	var r = x.get("race")
	if r is Array:
		return r.has(race)
	return r == null or r == race


# web: tech.js reqMet(x, st, all, race): every requirement done in this tree or any other
static func req_met(N: Dictionary, x: Dictionary, st: Dictionary) -> bool:
	var req = x.get("req")
	if req == null:
		return true
	for r in (req if req is Array else [req]):
		if st.done.has(r):
			continue
		var any := false
		for tr in N.tech:
			if N.tech[tr].done.has(r):
				any = true
		if not any:
			return false
	return true


# web: ai.js aiTechsLeft + v103.js (Military: gear over the difficulty's cap doesn't count)
static func techs_left(g: Game, N: Dictionary, tree: String) -> int:
	var st: Dictionary = N.tech[tree]
	var n := 0
	if tree == "mil":
		for x in GameData.c("TECHS"):
			if x.tree == "mil" and not x.get("rep", false) and not x.get("playerOnly", false) and tech_for(x, N.race) and not st.done.has(x.id) and not over_cap(N, x.id):
				n += 1
		return n
	var sc = N.school if tree == "mag" else null
	for x in GameData.c("TECHS"):
		if x.tree != tree or x.get("rep", false) or x.get("playerOnly", false) or not tech_for(x, N.race) or st.done.has(x.id) or x.id == "abandon":
			continue
		if tree == "mag":
			if x.id.begins_with("school-"):
				if sc != null:
					continue
			elif sc != null and x.get("school") != "*" and x.get("school") != sc:
				continue
		n += 1
	return n


static func retained(g: Game, N: Dictionary) -> int:
	return GameData.c("TECH_OPTIONS") + (1 if has(g, N, "retained") else 0) + (1 if has(g, N, "retained2") else 0)


# web: ai.js aiDrawOptions + v103.js (gear caps, a wanted technology in place of the least wanted) + v105.js (school locks)
static func draw_options(g: Game, N: Dictionary, tree: String) -> void:
	if tree == "mag" and N.school == null and N.diff == "difficult":
		N.wantSchool = dynamic_school(g, N)
	var st: Dictionary = N.tech[tree]
	var T := tier(g, N, tree)
	var n := retained(g, N)
	var rep_ok := techs_left(g, N, tree) < Game.REP_LEFT
	var avail := []
	for x in GameData.c("TECHS"):
		if x.tree == tree and x.tier <= T and tech_for(x, N.race) and not st.done.has(x.id) and x.id != st.cur and req_met(N, x, st) and g.forge_ready(x, st) and (not x.get("rep", false) or rep_ok) and x.id != "abandon" and not x.get("playerOnly", false):
			avail.append(x)
	if tree == "mag":
		if N.school != null:
			avail = avail.filter(func(x): return not x.id.begins_with("school-") and (x.get("school") == "*" or x.get("school") == N.school))
		else:
			avail = avail.filter(func(x): return x.id.begins_with("school-"))
	var keyed := []
	for x in avail:
		var w := 1.5 if x.id == "forge" and has_building(g, N, "barracks") else 1.0
		keyed.append({"x": x, "k": pow(g.js_rand.call(), 1.0 / w)})
	keyed = JS.stable_sort(keyed, func(a, b): return b.k - a.k)
	var sh: Array = keyed.map(func(o): return o.x)
	var top := sh.filter(func(x): return x.tier == T and not x.get("rep", false))
	var opts := []
	for x in sh:
		if st.sticky.has(x.id) and opts.size() < n:
			opts.append(x)
	for x in sh:
		if Game.UPGRADE_TECHS.has(x.id) and opts.size() < n and not opts.has(x):
			opts.append(x)
	if not top.is_empty() and not opts.has(top[0]) and opts.size() < n:
		opts.append(top[0])
	for x in sh:
		if opts.size() < n and not opts.has(x):
			opts.append(x)
	for x in opts:
		if GameData.c("STICKY_TECHS").has(x.id) and not st.sticky.has(x.id):
			st.sticky.append(x.id)
	st.opts = opts.map(func(x): return x.id)
	# v103
	st.opts = st.opts.filter(func(id): return not over_cap(N, id))
	var want := ""
	for id in priority_techs(g, N, tree):
		if not st.opts.has(id) and tech_open(g, N, tree, id):
			want = id
			break
	if want != "":
		if st.opts.size() >= n:
			var cands: Array = st.opts.filter(func(id): return not Game.UPGRADE_TECHS.has(id) and not st.sticky.has(id))
			cands = JS.stable_sort(cands, func(a, b): return tech_weight(g, N, tree, a) - tech_weight(g, N, tree, b))
			if not cands.is_empty():
				var drop: String = cands[0]
				st.opts = st.opts.filter(func(id): return id != drop)
		if st.opts.size() < n:
			st.opts.append(want)
	# v105: a leader locked to a school
	var lk = lock_of(g, N.id) if tree == "mag" else null
	if lk != null:
		N.wantSchool = lk
		var mst: Dictionary = N.tech.mag
		mst.opts = mst.opts.filter(func(id): return id != "abandon" and (not id.begins_with("school-") or id == "school-" + lk))
		if N.school == null and not mst.opts.has("school-" + lk) and mst.cur == null:
			mst.opts.append("school-" + lk)
		if mst.cur != null and str(mst.cur).begins_with("school-") and mst.cur != "school-" + lk:
			mst.cur = null


static func lock_of(g: Game, o: int):
	var L = g.leader_of(o)
	return L.school if L != null and L.get("school") != null else null


# web: v103.js aiOverCap: Easy Tier II gear, Moderate Tier III, Difficult everything
static func over_cap(N: Dictionary, id: String) -> bool:
	var cap: int = AI_TIER_CAP.get(N.diff, 9)
	if cap >= 9:
		return false
	if id.begins_with("w-"):
		var W = GameData.c("WEAPONS").get(GameData.c("TECH_EQUIP").get(id, ""))
		return W != null and W.tier > cap
	if id.begins_with("a-"):
		return int(id.right(1)) > cap
	if SHIELD_TIER.has(id):
		return SHIELD_TIER[id] > cap
	if id == "horse-training":
		return cap < 3
	return false


# web: v103.js aiTechOpen
static func tech_open(g: Game, N: Dictionary, tree: String, id: String) -> bool:
	var x = g.TECH_BY_ID.get(id)
	var st: Dictionary = N.tech[tree]
	return x != null and x.tree == tree and x.tier <= tier(g, N, tree) and tech_for(x, N.race) and not st.done.has(id) and st.cur != id and req_met(N, x, st) and g.forge_ready(x, st) and not x.get("playerOnly", false) and not over_cap(N, id) and (not x.get("rep", false) or techs_left(g, N, tree) < Game.REP_LEFT)


# web: v103.js aiPriorityTechs + v104.js (Threatened: walls and battle magic first)
static func priority_techs(g: Game, N: Dictionary, tree: String) -> Array:
	var st := stage(g, N)
	var L := []
	if tree == "gov":
		L = ["forts"]
		if st.noGold:
			L.append("market")
		if st.s2:
			L.append_array(["forge", "magetower"])
		if st.s4:
			L.append("forts2")
		if st.core:
			L.append_array(["effadmin", "forts3"])
		if st.core and st.free and fort_count(g, N) >= fort_limit(g, N):
			L.append("rep-forts")
	elif tree == "mil":
		var fam = GameData.c("FAMILY").get(N.family)
		var nxt = null
		if fam != null:
			for w in fam.order:
				var W: Dictionary = GameData.c("WEAPONS")[w]
				if W.get("tech") != null and not has(g, N, W.tech):
					nxt = W
					break
		L = ["battleforge"]
		if nxt != null:
			L.append(nxt.tech)
		for lv in range(1, 5):
			var id: String = "a-" + N.armorLine + str(lv)
			if g.TECH_BY_ID.has(id) and not has(g, N, id):
				L.append(id)
				break
		L.append("warforge")
	elif N.school == null:
		L = ["school-" + str(N.wantSchool)]
	else:
		L = {"death": ["graverob", "deathtax"], "arcane": ["trading", "stockmarket"], "life": ["harvest", "bountiful"], "pyro": ["sacredpyre"], "elemental": ["forestspirit"]}.get(N.school, []).duplicate()
	if N.get("stance", "normal") != "threatened":
		return L
	if tree == "gov":
		return ["walls", "walls2", "moat", "arrowslits"] + L.filter(func(id): return id != "market")
	if tree == "mag" and N.school != null:
		return LINES_FOR_BATTLE.get(N.school, []) + L
	return L


# web: v103.js aiTechWeight + v104.js (stances) + v104.js (ranged soldiers' research)
static func tech_weight(g: Game, N: Dictionary, tree: String, id: String) -> float:
	var x = g.TECH_BY_ID.get(id)
	if x != null and x.get("ranged", false):
		return 14.0 if N.get("exp", false) else 4.0
	var w := tech_weight_v103(g, N, tree, id)
	var s: String = N.get("stance", "normal")
	if s == "normal" or id.begins_with("school-") or w <= 0.01:
		return w
	var T := s == "threatened"
	if tree == "gov":
		if V104_DEFENSE_TECHS.has(id):
			return w * (12 if T else 4) + (40 if T else 10)
		if V104_ECON_TECHS.has(id):
			return w * (0.15 if T else 0.6)
		return w
	if tree == "mil":
		return w * (3.0 if T else 1.6)
	if V104_BATTLE_MAGIC.has(id):
		return w * (6 if T else 2) + (30 if T else 8)
	if V104_GUARD_MAGIC.has(id):
		return w * (3.0 if T else 1.5) + (10 if T else 3)
	return w * (0.5 if T else 1.0)


static func tech_weight_v103(g: Game, N: Dictionary, tree: String, id: String) -> float:
	var x = g.TECH_BY_ID.get(id)
	if over_cap(N, id):
		return 0.01
	var is_rep: bool = x != null and x.get("rep", false)
	if tree == "gov":
		var st := stage(g, N)
		var dep := deposits(g, N)
		var W := {"forts": 200, "advmills": 25, "forge": 40 if st.s2 else 12, "magetower": 40, "market": 30 if st.noGold else 8, "effadmin": 40, "rep-admin": 15,
			"forts2": 70 if st.s4 else 25, "forts3": 50, "rep-forts": 30 if fort_count(g, N) >= fort_limit(g, N) else 6, "retained": 10, "retained2": 8,
			"refmills": 12, "sophmills": 10, "advmines": 14 if dep else 1, "refmines": 12 if dep else 1, "sophmines": 10 if dep else 1, "traderoutes": 3, "rep-trade": 3,
			"thugs2": 10 if st.noGold else 3, "thugs3": 8 if st.noGold else 2,
			"rep-masons": 5, "rep-lumber": 4, "rep-storage": 2, "stable": 15 if N.get("exp", false) else 1, "mushroom": 2, "advfarms": 2, "reffarms": 2, "sophfarms": 2,
			"walls": 6 if st.dev else 1, "walls2": 5 if st.dev else 1, "moat": 3 if st.dev else 1, "arrowslits": 3 if st.dev else 1, "granary": 1, "storehouse": 1,
			"bank": 3 if st.dev else 1, "roads": 1, "roads2": 1, "roads3": 1, "autoscout": 1, "bridges": 1}
		if magic_late(g, N):
			W.magetower = 500
		return float(W.get(id, 2))
	if tree == "mil":
		var exp: bool = N.get("exp", false)
		if id == "battleforge" or id == "warforge":
			return 30.0
		if id.begins_with("w-"):
			var Wp = GameData.c("WEAPONS").get(GameData.c("TECH_EQUIP").get(id, ""))
			return 25.0 if Wp != null and Wp.get("fam") == N.family else 10.0 if exp else 2.0
		if id.begins_with("a-"):
			return 22.0 if id.contains(N.armorLine) else 2.0
		if id.begins_with("s-"):
			return 14.0 if N.family == "sword" else 1.0
		if id == "dualwield":
			return 10.0 if N.race == "swamp" else 1.0
		if id == "twohand":
			return 4.0
		if id.begins_with("horse-"):
			return 10.0 if exp else 1.0
		if id == "rep-armor":
			return 6.0
		if id == "rep-" + ("sword" if N.family == "axe" or N.family == "thrust" else N.family):
			return 6.0
		return 2.0 if is_rep else 3.0
	if id.begins_with("school-"):
		return 100.0 if id == "school-" + str(N.wantSchool) else 1.0
	var P: Dictionary = GameData.c("AI_MAGIC_PREFS").get(N.school, {}) if N.school != null else {}
	if id == "sanctum" or id == "arcanum":
		return 10.0
	if id == "rep-magecap" or id == "apprentice":
		return 6.0
	return float(P.get(id, 2 if is_rep else 3))


# web: ai.js aiPick
static func pick(g: Game, N: Dictionary, tree: String) -> void:
	var st: Dictionary = N.tech[tree]
	if st.opts.is_empty():
		draw_options(g, N, tree)
	if st.opts.is_empty():
		return
	var ws := {}
	for id in st.opts:
		ws[id] = tech_weight(g, N, tree, id) * (0.75 + g.js_rand.call() * 0.5)
	var sorted: Array = JS.stable_sort(st.opts.duplicate(), func(a, b): return ws[b] - ws[a])
	var id: String = sorted[0]
	st.cur = id
	st.prog = st.bank
	st.bank = 0
	st.opts = st.opts.filter(func(o): return o != id)


# web: ai.js aiFinishTech
static func finish_tech(g: Game, N: Dictionary, tree: String) -> void:
	var st: Dictionary = N.tech[tree]
	var x: Dictionary = g.TECH_BY_ID[st.cur]
	var cost := tech_cost(g, N, x)
	if x.get("rep", false):
		N.rep[x.id] = rep(N, x.id) + 1
	else:
		st.done.append(x.id)
	st.bank = minf(st.prog - cost, tech_rate(g, N, tree) * GameData.c("BANK_SECONDS") / g.TICK)
	st.prog = 0
	st.cur = null
	if x.id.begins_with("school-"):
		N.school = x.id.substr(7)
	if tree == "mil":
		g.ai_redesign(N)
	draw_options(g, N, tree)


# web: ai.js aiTechPayday
static func tech_payday(g: Game, N: Dictionary) -> void:
	for tree in Game.TREE_KEYS:
		var st: Dictionary = N.tech[tree]
		var T := tier(g, N, tree)
		if T != st.tier:
			st.tier = T
			if st.cur == null:
				draw_options(g, N, tree)
		if not T:
			continue
		if st.cur == null:
			pick(g, N, tree)
		var pts := tech_rate(g, N, tree)
		if st.cur != null:
			st.prog += pts
			if st.prog >= tech_cost(g, N, g.TECH_BY_ID[st.cur]):
				finish_tech(g, N, tree)


# web: v103.js aiLandScore
static func land_score(g: Game, N: Dictionary) -> Dictionary:
	var set := {}
	var mine := g.provs_of(N.id)
	for p in mine:
		set[p] = true
	var sc = N.get("scouted")
	for p in mine:
		for q in g.all_nbr[p]:
			if not g.buildings.has(q) and (N.surveyed.has(q) or (sc != null and sc.has(q))):
				set[q] = true
	var gold := 0.0
	var dep := 0
	var wd := 0.0
	for p in set:
		gold += g.yields[p].gold
		if g.yields[p].deposit and N.surveyed.has(p):
			dep += 1
		wd += g.tree_border[p]
	var k := maxi(1, set.size())
	return {"gold": (gold + dep * 10) / k, "wood": wd / k, "k": k, "dep": dep}


# web: v103.js aiDynamicSchool (+ v105.js: a leader's school comes first). Realmlings: Herbomancy, Necromancy, Arcane.
static func dynamic_school(g: Game, N: Dictionary):
	var lk = lock_of(g, N.id)
	if lk != null:
		return lk
	var L := land_score(g, N)
	var ok := func(s): return GameData.c("SCHOOLS").has(s) and (s in ["life", "death", "arcane"])
	var poor: bool = L.gold < AI_SCHOOL_GOLD
	var woody: bool = L.wood >= AI_SCHOOL_WOOD
	var pk: String
	if poor:
		pk = "death" if ok.call("death") else (("elemental" if ok.call("elemental") and g.js_rand.call() < 0.5 else "life") if woody else "arcane")
	elif woody:
		pk = "elemental" if ok.call("elemental") and g.js_rand.call() < 0.5 else "life"
	else:
		pk = "arcane"
	if not ok.call(pk):
		pk = N.wantSchool
		for s in GameData.c("SCHOOLS"):
			if ok.call(s):
				pk = s
				break
	N.schoolWhy = {"gold": L.gold, "wood": L.wood, "poor": poor, "woody": woody, "pick": pk}
	return pk


static func magic_late(g: Game, N: Dictionary) -> bool:
	return (N.diff == "moderate" or N.diff == "difficult") and N.school == null and g.t >= AI_MAGIC_LATE


static func deposits(g: Game, N: Dictionary) -> int:
	return g.provs_of(N.id).filter(func(p): return g.yields[p].deposit and N.surveyed.has(p)).size()


# ================================================================================================================
# where to build (web: ai.js aiOutpostWhy / aiBuildWhy, v103.js aiWhyAt / aiCapReserved / aiUpkeepOk / aiCanBuild)

static func prov_value(g: Game, p: int, N = null) -> float:
	var y: Dictionary = g.yields[p]
	var woody: bool = N != null and wood(N) < 6
	return y.food * 1.2 + y.wood * (3 if woody else 1) + y.gold * 1.5 + (3 if y.deposit else 0) + (3 if g.setpieces.has(p) else 0) + ((4 if woody else 1) if g.tree_border[p] else 0)


static func outpost_why(g: Game, N: Dictionary, p: int, self_u = null) -> String:
	if g.buildings.has(p):
		return "taken"
	if not N.surveyed.has(p):
		return "unsurveyed"
	if not g.all_nbr[p].any(func(q): return g.nation_of(q) == N.id):
		return "not bordering"
	if g.bandits_in(p):
		return "bandits"
	if outposts(g, N) + pending_outposts(g, N, self_u) >= outpost_limit(g, N):
		return "limit"
	return "" if can_pay(N.stock, GameData.c("OUTPOST_COST")) else "cost"


static func job_count_at(g: Game, p: int, self_u, type := "") -> int:
	var n := 0
	for u in g.units:
		if not is_same(u, self_u) and u.get("aiJob") != null and u.aiJob.prov == p and u.aiJob.type != "outpost" and (type == "" or u.aiJob.type == type):
			n += 1
	return n


# web: ai.js aiBuildWhy (+ swamp.js: no Sacred Pyres for Realmlings)
static func build_why(g: Game, N: Dictionary, p: int, type: String, self_u = null) -> String:
	if type == "pyre":
		return "no"
	var d: Dictionary = g.BUILD_DEFS[type]
	if d.get("tech") != null and not has(g, N, d.tech):
		return "tech"
	if g.nation_of(p) != N.id or g.occ.has(p):
		return "not ours"
	if type == "farm":
		var ter: String = g.world.provinces[p].terrain
		if not (ter in ["grassland", "forest"] or (has(g, N, "mushroom") and ter == "swamp")):
			return "terrain"
	if type == "lumber" and not g.tree_border[p]:
		return "trees"
	if type == "goldmine" and not (g.yields[p].deposit and N.surveyed.has(p)):
		return "deposit"
	if g.count_of(p, type) >= g.build_cap(p, type):
		return "cap"
	if g.used_slots_all(p).size() + job_count_at(g, p, self_u) >= g.plot_cap(p):
		return "full"
	if job_count_at(g, p, self_u, type) > 0 and g.count_of(p, type) + 1 >= g.build_cap(p, type):
		return "cap"
	return ""


static func cap_reserved(g: Game, N: Dictionary, p: int) -> int:
	if p != g.capital_of(N.id):
		return 0
	var n := 0
	for t in AI_CAP_RESERVE:
		if g.extras_in(p).any(func(e): return e.type == t):
			continue
		if g.units.any(func(u): return u.owner == N.id and ((u.build != null and u.build.prov == p and u.build.type == t) or (u.get("aiJob") != null and u.aiJob.prov == p and u.aiJob.type == t))):
			continue
		n += 1
	return n


static func why_at(g: Game, N: Dictionary, p: int, type: String, self_u = null) -> String:
	var why := build_why(g, N, p, type, self_u)
	if why != "":
		return why
	if AI_CAP_RESERVE.has(type) or type == "stable":
		return ""
	var r := cap_reserved(g, N, p)
	if not r:
		return ""
	var used := g.used_slots_all(p).size() + job_count_at(g, p, self_u)
	return "reserved" if used + r >= g.plot_cap(p) else ""


static func upkeep_ok(g: Game, N: Dictionary, type: String) -> bool:
	var up := 0
	if g.BUILD_DEFS.has(type):
		up = int(g.BUILD_DEFS[type].get("upkeep", {}).get("wood", 0))
	return type == "lumber" or (type == "magetower" and magic_late(g, N)) or (type == "farm" and food(N) < 0) or wood(N) - up >= 1


static func can_build(g: Game, N: Dictionary, type: String) -> bool:
	if not upkeep_ok(g, N, type):
		return false
	for p in g.provs_of(N.id):
		if not g.occ.has(p) and why_at(g, N, p, type) == "":
			return true
	return false


# web: v103.js aiBorderFree / aiFreeLandNow: unclaimed land on the border it could settle
static func border_free(g: Game, N: Dictionary) -> bool:
	for p in g.provs_of(N.id):
		for q in g.all_nbr[p]:
			if not g.buildings.has(q) and not g.bandits_in(q) and not g.unique_ban(q):
				var why := outpost_why(g, N, q)
				if why == "" or why == "cost" or why == "limit" or why == "unsurveyed":
					return true
	return false


static func free_land_now(g: Game, N: Dictionary) -> bool:
	var k := floori(g.t / 5)
	var c = N.get("v103fl")
	if c != null and c.k == k:
		return c.v
	var v := border_free(g, N)
	N.v103fl = {"k": k, "v": v}
	return v


static func gold_poor(N: Dictionary, g: Game, k := 2.0) -> bool:
	return N.get("income", {}).get("gold", 0) < k * prov_count(g, N) + 5


# ================================================================================================================
# web: v103.js aiStage: the step of the build order the nation has reached (cached for the current moment)

static func stage(g: Game, N: Dictionary) -> Dictionary:
	var c = N.get("v103st")
	if c != null and c.t == g.t:
		return c
	if not N.has("v103"):
		N.v103 = {}
	var L: Dictionary = N.v103
	var n := prov_count(g, N)
	var wd := wood(N)
	var fts: int = forts_held_by(g, N.id) + N.ups.size()
	var free := free_land_now(g, N)
	var lumber_ok := can_build(g, N, "lumber")
	if n != L.get("lastN", -1):
		L.lastN = n
		L.grewAt = g.t
	var step := "s1" if not L.get("s1", false) else "s4" if L.get("s3", false) and not L.get("s4", false) else "dev" if L.get("core", false) and not L.get("dev", false) else ""
	if step != L.get("step", null):
		L.step = step
		L.stepAt = g.t
	var stalled: bool = g.t - maxf(L.get("grewAt", 0.0), L.get("stepAt", 0.0)) > 240
	var st := {"t": g.t, "n": n, "forts": fts, "free": free, "lumberOk": lumber_ok}
	if not L.get("s1", false) and (n >= 5 or (not free and n >= 2) or (stalled and n >= 2) or g.t > 1200):
		L.s1 = true
	if L.get("s1", false) and not L.get("s2", false) and (wd > 40 or not lumber_ok):
		L.s2 = true
	if fts >= 2:
		L.s3 = true
	if L.get("s3", false) and not L.get("s4", false) and (n >= 10 or not free or stalled):
		L.s4 = true
	if L.get("s4", false) and not L.get("s4b", false) and (wd > 60 or not lumber_ok):
		L.s4b = true
	st.fortBlocked = L.get("s2", false) and not L.get("s3", false) and fort_count(g, N) >= fort_limit(g, N)
	st.mid = L.get("s4b", false) or st.fortBlocked
	st.s5 = st.mid and not can_build(g, N, "goldmine")
	st.s6 = count_j(g, N, "barracks") > 0
	st.temples = floori(n / 4.0)
	st.s7 = count_j(g, N, "temple") >= st.temples or not can_build(g, N, "temple")
	st.s8 = not has(g, N, "forge") or count_j(g, N, "forge") > 0 or not can_build(g, N, "forge")
	st.s9 = not has(g, N, "magetower") or count_j(g, N, "magetower") > 0 or not can_build(g, N, "magetower")
	if not L.get("core", false) and L.get("s4b", false) and st.s5 and st.s6 and st.s7 and st.s8 and st.s9:
		L.core = true
		L.coreAt = g.t
	st.s11 = forts_held_by(g, N.id) >= 3
	st.noGold = (deposits(g, N) == 0 or gold_poor(N, g, 1.5)) and gold_poor(N, g, 2.5) and N.stock.gold < storage(g, N, "gold") * 0.5
	if L.get("core", false) and (n >= 20 or not free or stalled):
		L.dev = true
	st.atLimit = fort_count(g, N) >= fort_limit(g, N) and n >= prov_limit(g, N.id)
	st.full = L.get("dev", false) and (not free or st.atLimit or n >= D(N).maxProvs)
	for k in ["s1", "s2", "s3", "s4", "s4b", "core", "dev"]:
		st[k] = L.get(k, false)
	for k in L:
		if not st.has(k):
			st[k] = L[k]
	N.v103st = st
	return st


static func stage_text(g: Game, N: Dictionary) -> String:
	var s := stage(g, N)
	var out := []
	for k in ["s1", "s2", "s3", "s4", "s4b", "core", "dev"]:
		if s[k]:
			out.append(k)
	if s.full:
		out.append("full")
	if N.get("exp", false):
		out.append("exp")
	if N.get("aggro", false):
		out.append("AGGRO")
	return "[" + ",".join(out) + "]"


# ================================================================================================================
# the plan (web: v103.js aiPlan + v104.js stances)

static func plan(g: Game, N: Dictionary) -> Dictionary:
	var Dd := D(N)
	var st := stage(g, N)
	var n: int = st.n
	var P := {"maxProvs": Dd.maxProvs, "wf": Dd.wf, "masons": Dd.masons2 if n >= 6 else Dd.masons, "stage": st, "forts": 99}
	var enemies := g.enemies_of(N.id)
	var enemy_max := 0
	for o in enemies:
		var m := g.soldier_count(o)
		for x in g.allies_of(o):
			if x != N.id:
				m += g.soldier_count(x)
		enemy_max = maxi(enemy_max, m)
	var army := 3 if n < 4 else 3 + floori(n / 5.0)
	if not enemies.is_empty():
		army = maxi(army, int(JS.round_js(enemy_max * (0.7 if N.diff == "easy" else 1.1))))
	P.army = army
	P.late = st.dev
	P.powerGoal = INF if st.dev else AI_EARLY_POWER if st.s6 else 0.0
	P.useCav = N.get("exp", false)
	# v104
	var nb := v104_neighbors(g, N)
	P.stance = N.get("stance", "normal")
	if P.stance == "threatened":
		P.threat = true
		P.powerGoal = INF
		P.army = maxi(P.army, g.soldier_count(N.threatBy) if N.get("threatBy") != null else 0)
	else:
		if P.stance == "wary":
			var strongest := 0.0
			for o in nb:
				strongest = maxf(strongest, nation_power(g, o))
			if P.powerGoal != INF:
				P.powerGoal = maxf(P.powerGoal, strongest * V104_WARY_GOAL)
		if N.get("rival") != null and g.alive_nation(N.rival) and P.powerGoal != INF:
			P.powerGoal = maxf(P.powerGoal, def_power(g, N.rival) * 10 * V104_RIVAL_GOAL)
	return P


# ================================================================================================================
# the next building (web: v103.js aiNextBuilding + v104.js Threatened + v104.js Fiber crops)

static func next_building(g: Game, N: Dictionary, P: Dictionary, skip: Dictionary):
	# v104 Fiber: a new Farm for its Fiber crop when wood is scarce and no Farm can be switched to one
	if not skip.has("farm") and wood_scarce(g, N) and fiber_candidate(g, N) == null and not g.units.any(func(u): return u.owner == N.id and ((u.get("aiJob") != null and u.aiJob.type == "farm") or (u.build != null and u.build.type == "farm"))):
		for p in g.provs_of(N.id):
			if g.occ.has(p) or fiber_taken(g, p) or g.extras_in(p).any(func(e): return e.type == "farm"):
				continue
			if why_at(g, N, p, "farm") == "":
				return {"type": "farm", "prov": p, "urgent": true} if can_pay(N.stock, build_cost(g, N, "farm")) else {"type": "farm", "wait": true}
	# v104 Threatened
	if N.get("stance", "normal") == "threatened":
		if N.income.food < 0 and not can_build(g, N, "farm") and g.t >= N.get("v104demo", 0.0):
			v104_farm_room(g, N)
		if count_j(g, N, "barracks") < mini(3, maxi(1, floori(prov_count(g, N) / 5.0))) and not skip.has("barracks"):
			var cap := g.capital_of(N.id)
			var mine: Array = g.provs_of(N.id).filter(func(p): return not g.occ.has(p))
			mine = JS.stable_sort(mine, func(a, b): return (1 if b == cap else 0) - (1 if a == cap else 0))
			for p in mine:
				if why_at(g, N, p, "barracks") == "":
					if upkeep_ok(g, N, "barracks"):
						return {"type": "barracks", "prov": p, "urgent": true} if can_pay(N.stock, build_cost(g, N, "barracks")) else {"type": "barracks", "wait": true}
					break
		var b = next_building_v103(g, N, P, skip)
		return b if b != null and (V104_WAR_TYPES.has(b.type) or N.stock.gold > 400) else null
	return next_building_v103(g, N, P, skip)


static func next_building_v103(g: Game, N: Dictionary, P: Dictionary, skip: Dictionary):
	var st := stage(g, N)
	var inc: Dictionary = N.income
	var stk: Dictionary = N.stock
	var n: int = st.n
	var cap := g.capital_of(N.id)
	var mine: Array = g.provs_of(N.id).filter(func(p): return not g.occ.has(p))
	var hs := func(type): return count_j(g, N, type) + (1 if skip.has(type) else 0)
	var list := []   # [type, urgent, preferCapital]
	var expanding: bool = not st.s1 or (st.s3 and not st.s4)
	if inc.food < 0:
		var under := count_j(g, N, "farm") - count(g, N, "farm") + g.units.filter(func(u): return u.owner == N.id and u.build != null and u.build.type == "farm").size()
		if under < ceili(-inc.food / 5.0):
			list.append(["farm", true, false])
	if inc.wood < 2 or (st.s4b and inc.wood < 10):
		list.append(["lumber", true, false])
	if not st.s1:
		list.append(["lumber", false, false])
	elif not st.s2:
		list.append(["lumber", true, false])
	if st.s3 and not st.s4:
		list.append(["lumber", false, false])
	if st.s4 and not st.s4b:
		list.append(["lumber", true, false])
	if st.s4b and inc.wood < (40 if st.dev else 25):
		list.append(["lumber", true, false])
	if st.mid:
		list.append(["goldmine", true, false])
		if st.noGold and has(g, N, "market") and hs.call("market") < ceili(n / 2.0):
			list.append(["market", true, false])
		if not hs.call("barracks"):
			list.append(["barracks", true, true])
		if hs.call("temple") < st.temples:
			list.append(["temple", true, false])
		if has(g, N, "forge") and not hs.call("forge"):
			list.append(["forge", true, true])
		if has(g, N, "magetower") and not hs.call("magetower"):
			list.append(["magetower", true, true])
		if magic_late(g, N) and has(g, N, "magetower") and not hs.call("magetower"):
			make_room_for_tower(g, N)
	if st.core and st.s11:
		var per := ceili(n / 4.0)
		if has(g, N, "forge") and hs.call("forge") < per:
			list.append(["forge", true, false])
		if has(g, N, "magetower") and hs.call("magetower") < per:
			list.append(["magetower", true, false])
	if st.dev:
		list.append(["temple", true, false])
		if has(g, N, "forge"):
			list.append(["forge", true, false])
		if has(g, N, "magetower"):
			list.append(["magetower", true, false])
		list.append(["goldmine", true, false])
		if has(g, N, "market"):
			list.append(["market", true, false])
		if N.get("exp", false) and has(g, N, "stable") and not hs.call("stable"):
			list.append(["stable", false, true])
		for kt in [["gold", "bank"], ["wood", "storehouse"]]:
			if has(g, N, kt[1]) and stk[kt[0]] > storage(g, N, kt[0]) * 0.9 and hs.call(kt[1]) < 2:
				list.append([kt[1], false, false])
	var pv := {}
	for p in mine:
		pv[p] = prov_value(g, p, N)
	var order: Array = JS.stable_sort(mine.duplicate(), func(a, b): return pv[b] - pv[a])
	var cap_first: Array = ([cap] + order.filter(func(p): return p != cap)) if cap >= 0 and mine.has(cap) else order
	for item in list:
		var type: String = item[0]
		if skip.has(type) and not (type in ["farm", "lumber", "market", "temple", "goldmine"]):
			continue
		if not g.BUILD_DEFS.has(type):
			continue
		var cost := build_cost(g, N, type)
		var urgent: bool = item[1] and not (expanding and type != "farm" and inc.wood >= 2)
		if not upkeep_ok(g, N, type):
			continue
		if N.get("saveFort", false) and type != "lumber" and not (type == "farm" and inc.food < 0) and stk.wood - cost.get("wood", 0) < GameData.c("FORT_UPGRADE").cost.wood:
			continue
		var where := -1
		for p in (cap_first if item[2] or type == "lumber" else order):
			if why_at(g, N, p, type) == "":
				where = p
				break
		if where < 0:
			continue
		if urgent and type != "farm" and type != "lumber":
			N.v103need = cost
			N.v103needT = g.t
		if not can_pay(stk, cost):
			if urgent and type != "farm":
				return {"type": type, "wait": true}
			continue
		return {"type": type, "prov": where, "urgent": urgent}
	return null


# web: v104.js v104FarmRoom: food short and nowhere to put a Farm: tear down an economic building
static func v104_farm_room(g: Game, N: Dictionary) -> void:
	N.v104demo = g.t + 30
	var types: Array = V104_DEMOLISH.filter(func(t): return t != "lumber") if wood(N) < 15 else V104_DEMOLISH
	for type in types:
		for p in g.provs_of(N.id):
			if g.occ.has(p) or why_at(g, N, p, "farm") != "full":
				continue
			var e = null
			for x in g.extras_in(p):
				if x.type == type:
					e = x
					break
			if e == null:
				continue
			g.extras[p] = g.extras_in(p).filter(func(x): return not is_same(x, e))
			N.income = income(g, N)
			return


# web: ai.js aiMakeRoomForTower
static func make_room_for_tower(g: Game, N: Dictionary) -> void:
	if g.t < N.get("roomAt", 0.0) or not can_pay(N.stock, g.BUILD_DEFS.magetower.cost):
		return
	var mine: Array = g.provs_of(N.id).filter(func(p): return not g.occ.has(p))
	if mine.is_empty() or mine.any(func(p): return build_why(g, N, p, "magetower") == ""):
		return
	if not mine.any(func(p): return build_why(g, N, p, "magetower") == "full"):
		return
	N.roomAt = g.t + 30
	var inc: Dictionary = N.income
	var cap := g.capital_of(N.id)
	var lst: Array = extra_list(g, N).filter(func(pe): return build_why(g, N, pe[0], "magetower") == "full")
	var spare := ["market", "granary", "storehouse", "bank", "stable", "temple", "farm", "lumber", "goldmine"]
	var ok := func(pe): return (pe[1].type != "farm" or inc.food - int(g.BUILD_DEFS.farm.get("gives", {}).get("food", 3)) > 2) and (pe[1].type != "lumber" or inc.wood > 6) and (pe[1].type != "temple" or count(g, N, "temple") > 1)
	lst = lst.filter(ok)
	lst = JS.stable_sort(lst, func(a, b):
		var d := spare.find(a[1].type) - spare.find(b[1].type)
		if d != 0:
			return d
		return (1 if b[0] == cap else 0) - (1 if a[0] == cap else 0))
	for pe in lst:
		if spare.has(pe[1].type):
			var p: int = pe[0]
			var e: Dictionary = pe[1]
			g.extras[p] = g.extras_in(p).filter(func(x): return not is_same(x, e))
			N.income = income(g, N)
			return


# ================================================================================================================
# Masons: settle (the woodiest land first while opening), else build (web: v103.js aiMasons)

static func wood_score(g: Game, p: int) -> float:
	var y: Dictionary = g.yields[p]
	return y.wood * 1.5 + mini(g.tree_border[p], 2) * 4 + y.food * 0.3 + (1 if g.setpieces.has(p) else 0)


static func masons(g: Game, N: Dictionary, P: Dictionary) -> void:
	var st := stage(g, N)
	var n: int = st.n
	var Dd := D(N)
	var free: Array = units_of(g, N, Game.MASON).filter(func(u): return u.get("aiJob") == null and u.build == null and not u.moving and not u.get("exiting", false))
	if free.is_empty():
		return
	var pend := pending_outposts(g, N)
	var skip := {}
	var grew := 0
	for u in free:
		var job = null
		var b = next_building(g, N, P, skip)
		if b != null and not b.get("wait", false) and b.urgent:
			job = b
		elif b != null and b.get("wait", false):
			if N.income.wood >= 8 and N.stock.wood < build_cost(g, N, b.type).get("wood", 0) + GameData.c("OUTPOST_COST").wood:
				continue
		var want_grow: bool = job == null and n + pend + grew < P.maxProvs and g.t >= N.nextOutpost
		if want_grow:
			var d := reach(g, u, 14)
			var taken := {}
			for v in g.units:
				if v.get("aiJob") != null:
					taken[v.aiJob.prov] = true
				elif v.build != null and v.build.type == "outpost":
					taken[v.build.prov] = true
			var best := -1
			var bs := -INF
			for p in d:
				if outpost_why(g, N, p) != "" or taken.has(p):
					continue
				if N.income.wood < 2 and not g.yields[p].wood and not g.tree_border[p]:
					continue
				var v: float = wood_score(g, p) if n + grew < 5 else prov_value(g, p, N) + (4 if g.yields[p].deposit and N.surveyed.has(p) else 0) + mini(g.tree_border[p], 4) * 0.8
				var sc: float = v - d[p] * 0.8
				if sc > bs:
					bs = sc
					best = p
			if best >= 0:
				job = {"type": "outpost", "prov": best}
				grew += 1
		if job == null and b != null and not b.get("wait", false):
			job = b
		if job == null:
			continue
		if job.type == "outpost":
			N.nextOutpost = g.t + Dd.outpostGap
		else:
			skip[job.type] = true
		u.aiJob = {"type": job.type, "prov": job.prov}
		if u.prov != job.prov and not g.order(u, job.prov, true):
			u.aiJob = null


# web: ai.js aiReach + v104.js: a breadth-first walk over the provinces this unit may enter (province -> hops). An army at
# war big enough to batter a wall counts a hostile wall as passable at AI_SIEGE_HOPS extra provinces of marching.
static func reach(g: Game, u: Dictionary, limit := 12) -> Dictionary:
	if u.kind == "army" and not g.walls.is_empty() and g.is_nation(u.owner) and g.troop_count(u) >= Game.SIEGE_MIN and not g.enemies_of(u.owner).is_empty():
		var dd := {u.prov: 0}
		var qq := [[0, u.prov]]
		while not qq.is_empty():
			var bi := 0
			for k in range(1, qq.size()):
				if qq[k][0] < qq[bi][0]:
					bi = k
			var it: Array = qq[bi]
			qq.remove_at(bi)
			var da0: int = it[0]
			var a0: int = it[1]
			if da0 > dd[a0] or da0 >= limit:
				continue
			for nb in g.path_nbr(u, a0, true):
				if not g.can_enter(u, nb.q, -1):
					continue
				var nd: int = da0 + 1 + (AI_SIEGE_HOPS if nb.has("siege") else 0)
				if not dd.has(nb.q) or nd < dd[nb.q]:
					dd[nb.q] = nd
					qq.append([nd, nb.q])
		return dd
	var d := {u.prov: 0}
	var q := [u.prov]
	var i := 0
	while i < q.size():
		var a: int = q[i]
		i += 1
		var da: int = d[a]
		if da >= limit:
			continue
		for nb in g.path_nbr(u, a):
			if not d.has(nb.q) and g.can_enter(u, nb.q, -1):
				d[nb.q] = da + 1
				q.append(nb.q)
	return d


# ================================================================================================================
# forts (web: v103.js aiFortUp), Lumber Mills swapped for research (v103.js aiSwapLumber), wood relief (ai.js)

static func fort_up(g: Game, N: Dictionary, P: Dictionary) -> void:
	var st := stage(g, N)
	var stk: Dictionary = N.stock
	var mine := g.provs_of(N.id)
	var hv := fort_count(g, N)
	var limit := fort_limit(g, N)
	var FU: Dictionary = GameData.c("FORT_UPGRADE")
	var need := false
	if hv < limit and prov_limit(g, N.id) < D(N).maxProvs + 1:
		if forts_held_by(g, N.id) + N.ups.size() < 2:
			need = st.s2
		else:
			need = st.core and st.free and outposts(g, N) + pending_outposts(g, N) >= outpost_limit(g, N) - 1
		if not need and st.dev and stk.gold > 900 and stk.wood > FU.cost.wood + 200 and outposts(g, N) > 0:
			need = true
	N.saveFort = need and not can_pay(stk, FU.cost)
	if need and can_pay(stk, FU.cost):
		var cap := g.capital_of(N.id)
		var d := g.hops_list(cap if cap >= 0 else N.capital, g.all_nbr)
		var site := func(p): 
			var ter: String = g.G.provs[p].terrain
			return (6 if ter == "grassland" or ter == "forest" else 0) + ((4 + mini(g.tree_border[p], 4)) if g.tree_border[p] else 0) + prov_value(g, p, N) * 0.3 - absf(d[p] - 2)
		var al := g.allies_of(N.id)
		var c: Array = mine.filter(func(p): return g.buildings[p].stage == 0 and not N.ups.has(p) and not g.occ.has(p) and not al.any(func(x): return g.all_nbr[p].any(func(q): return g.nation_of(q) == x)))
		var sv := {}
		for p in c:
			sv[p] = site.call(p)
		c = JS.stable_sort(c, func(a, b): return sv[b] - sv[a])
		if not c.is_empty():
			pay(stk, FU.cost)
			N.ups[c[0]] = {"t0": g.t}
	for tid in [["forge", ["battleforge", "warforge"]], ["magetower", ["sanctum", "arcanum"]]]:
		for pe in extra_list(g, N):
			var e: Dictionary = pe[1]
			if e.type != tid[0]:
				continue
			var lv: int = e.get("level", 1)
			var key := "%d@%d" % [pe[0], e.slot]
			if lv >= 3 or N.xups.has(key) or not has(g, N, tid[1][lv - 1]):
				continue
			var up: Dictionary = g.BUILD_DEFS[tid[0]].ups[lv]
			if not can_pay(stk, up.cost) or (N.get("saveFort", false) and stk.wood - up.cost.get("wood", 0) < FU.cost.wood):
				continue
			pay(stk, up.cost)
			N.xups[key] = {"t0": g.t, "to": lv + 1, "time": up.time}


static func swap_lumber(g: Game, N: Dictionary) -> void:
	var st := stage(g, N)
	if not st.full or wood(N) <= 50 or g.t < N.get("swapAt", 0.0) or not g.enemies_of(N.id).is_empty():
		return
	var mine: Array = g.provs_of(N.id).filter(func(p): return not g.occ.has(p))
	var allowed := func(t): return (t != "forge" or has(g, N, "forge")) and (t != "magetower" or has(g, N, "magetower")) and (t != "market" or has(g, N, "market"))
	for t in AI_SWAP_INTO:
		if allowed.call(t) and mine.any(func(p): return why_at(g, N, p, t) == ""):
			return
	if g.units.any(func(u): return u.owner == N.id and (u.get("aiJob") != null or u.build != null)):
		return
	var lumber_n := func(q): return g.extras_in(q).filter(func(e): return e.type == "lumber").size()
	var c: Array = mine.filter(func(q): return lumber_n.call(q) > 0 and AI_SWAP_INTO.any(func(t): return allowed.call(t) and why_at(g, N, q, t) == "full"))
	c = JS.stable_sort(c, func(a, b): return lumber_n.call(b) - lumber_n.call(a))
	N.swapAt = g.t + 45
	if c.is_empty():
		return
	var p: int = c[0]
	var e = null
	for x in g.extras_in(p):
		if x.type == "lumber":
			e = x
			break
	g.extras[p] = g.extras_in(p).filter(func(x): return not is_same(x, e))
	N.income = income(g, N)


static func relieve_wood(g: Game, N: Dictionary) -> void:
	if N.income.wood >= 0 or N.stock.wood >= 25 or g.t < N.get("relieveAt", 0.0):
		return
	N.relieveAt = g.t + 60
	var war := not g.enemies_of(N.id).is_empty()
	var lst := extra_list(g, N)
	var find := func(f): 
		for pe in lst:
			if f.call(pe[1]):
				return pe
		return null
	var pk = find.call(func(e): return e.type == "stable")
	if pk == null and not war and lst.filter(func(pe): return pe[1].type == "barracks").size() > 1:
		pk = find.call(func(e): return e.type == "barracks")
	if pk == null:
		pk = find.call(func(e): return e.type in ["granary", "storehouse", "bank"])
	if pk == null and N.income.food > 8:
		pk = find.call(func(e): return e.type == "farm")
	if pk == null:
		return
	var p: int = pk[0]
	var e: Dictionary = pk[1]
	g.extras[p] = g.extras_in(p).filter(func(x): return not is_same(x, e))
	N.income = income(g, N)


# ================================================================================================================
# training (web: v103.js aiTrain, v100.js the war surge and unit counters, v103.js / v104.js the mix and ranged share)

static func busy_at(N: Dictionary, prov: int) -> bool:
	return N.queue.any(func(q): return q.prov == prov)


static func queued(N: Dictionary, kind: String) -> int:
	return N.queue.filter(func(q): return q.kind == kind).size()


static func surge(g: Game, N: Dictionary) -> bool:
	return N.get("surge", false) and AI_SURGE.has(N.diff) and not g.allied(N.id, Game.ME)


static func is_military(g: Game, kind: String) -> bool:
	return g.military.has(kind)


static func train_time(g: Game, N: Dictionary, kind: String) -> float:
	if surge(g, N) and is_military(g, kind) and kind != Game.MAGE:
		return AI_SURGE[N.diff].time
	return Game.train_time(kind)


static func unit_cost(g: Game, N: Dictionary, kind: String) -> Dictionary:
	var c: Dictionary = g.unit_defs[kind].cost
	var m: float = AI_SURGE[N.diff].cost if surge(g, N) and is_military(g, kind) and kind != Game.MAGE else 1.0
	if m == 1.0:
		return c
	var out := {}
	for k in c:
		out[k] = ceili(c[k] * m)
	return out


static func unit_limit(g: Game, N: Dictionary, kind: String) -> int:
	return GameData.c("UNIT_LIMIT")[kind] + rep(N, "rep-masons" if kind == Game.MASON else "rep-wayfinders")


static func train(g: Game, N: Dictionary, P: Dictionary) -> void:
	var st: Dictionary = N.stock
	var cap := g.capital_of(N.id)
	var reserve := 25
	var war := not g.enemies_of(N.id).is_empty()
	if cap >= 0 and not busy_at(N, cap):
		for kw in [[Game.MASON, P.masons], [g.WAYFINDER, P.wf]]:
			var kind: String = kw[0]
			var hv := units_of(g, N, kind).size() + queued(N, kind)
			if hv < mini(kw[1], unit_limit(g, N, kind)) and st.gold >= g.unit_defs[kind].cost.gold + reserve:
				pay(st, g.unit_defs[kind].cost)
				N.queue.append({"kind": kind, "prov": cap, "t0": g.t})
				break
	if N.school != null:
		var towers := []
		for pe in extra_list(g, N):
			if pe[1].type == "magetower" and not busy_at(N, pe[0]):
				towers.append(pe[0])
		var mc: Dictionary = g.unit_defs[Game.MAGE].cost
		if not towers.is_empty() and mages(g, N) < 1 + (1 if has(g, N, "apprentice") else 0) + rep(N, "rep-magecap") and can_pay(st, mc) and (N.income.food >= 2 or (N.stock.food > 300 and N.income.food >= 0) or not mages(g, N)):
			pay(st, mc)
			N.queue.append({"kind": Game.MAGE, "prov": towers[0], "t0": g.t})
	var nq: int = N.queue.filter(func(q): return is_military(g, q.kind)).size()
	var soldiers := g.soldier_count(N.id) + nq
	var fd: int = N.income.food
	var farms_ok: bool = wood(N) >= 8 and N.stock.wood >= g.BUILD_DEFS.farm.cost.wood
	var want: bool
	if war:
		want = fd >= 0 or (fd >= -6 and N.stock.food > 150)
	elif soldiers < P.army:
		want = fd >= 2 or (N.stock.food > 400 and fd >= -2 and farms_ok)
	elif P.late:
		want = fd >= 2
	else:
		want = P.powerGoal > 0 and nation_power(g, N.id) + nq * 75 < P.powerGoal and (fd >= 2 or (N.stock.food > 400 and fd >= -3 and farms_ok))
	if P.get("threat", false):
		want = fd >= -8 or N.stock.food > 200
	if not want:
		return
	if not war and soldiers >= P.army and not P.get("threat", false):
		if N.get("saveFort", false):
			return
		var need: int = N.v103need.get("gold", 0) if N.get("v103need") != null and g.t - N.get("v103needT", 0.0) < 15 else 0
		if need and st.gold - unit_cost(g, N, N.design.inf).get("gold", 0) < need:
			return
	for pe in extra_list(g, N):
		if pe[1].type != "barracks":
			continue
		var p: int = pe[0]
		if busy_at(N, p):
			continue
		var stable := g.extras_in(p).any(func(e): return e.type == "stable")
		var kind := pick_kind(g, N, P, stable)
		var cost := unit_cost(g, N, kind)
		if not can_pay(st, cost) or st.gold - cost.get("gold", 0) < (0 if war or P.get("threat", false) else 40):
			if kind != N.design.inf and can_pay(st, unit_cost(g, N, N.design.inf)) and war:
				pay(st, unit_cost(g, N, N.design.inf))
				N.queue.append({"kind": N.design.inf, "prov": p, "t0": g.t})
			continue
		pay(st, cost)
		N.queue.append({"kind": kind, "prov": p, "t0": g.t})


# web: v104.js ranged share → v103.js mixed armies → v100.js counters → the standard design
static func pick_kind(g: Game, N: Dictionary, P: Dictionary, stable: bool) -> String:
	var rk: String = GameData.c("RANGED").realm.id
	if rng_forge(g, N.id):
		var hv := 0
		var tot := 0
		for v in g.units:
			if v.owner == N.id and v.kind == "army":
				for k in v.troops:
					if k != Game.MAGE and is_military(g, k):
						tot += v.troops[k]
						if g.is_rng(k):
							hv += v.troops[k]
		for q in N.queue:
			if is_military(g, q.kind) and q.kind != Game.MAGE:
				tot += 1
				if g.is_rng(q.kind):
					hv += 1
		if tot >= 3 and float(hv) / tot < AI_RNG_SHARE.get(N.diff, 0.25):
			return rk
	if not N.get("exp", false):
		return N.design.inf
	var C = N.get("counter")
	if N.get("mix") == null or (C != null and C.base < 0.999):
		return pick_kind_v100(g, N, P, stable)
	var cd := counter_designs(g, N)
	var hv2 := {"pole": 0, "blunt": 0, "cav": 0, "base": 0}
	var tot2 := [0]
	var add := func(k, n):
		if k == Game.MAGE or not is_military(g, k) or not g.DSTATS.has(k):
			return
		var f: String = "cav" if g.DSTATS[k].get("cav", false) else "pole" if k == cd.pole else "blunt" if k == cd.blunt else "base"
		hv2[f] += n
		tot2[0] += n
	for v in g.units:
		if v.owner == N.id and v.kind == "army":
			for k in v.troops:
				add.call(k, v.troops[k])
	for q in N.queue:
		add.call(q.kind, 1)
	var pk := "base"
	var gap := -INF
	for f in ["base", "pole", "blunt", "cav"]:
		if f == "cav" and not stable:
			continue
		var gg: float = N.mix[f] - (float(hv2[f]) / tot2[0] if tot2[0] else 0.0)
		if N.mix[f] > 0.02 and gg > gap:
			gap = gg
			pk = f
	return cd.pole if pk == "pole" else cd.blunt if pk == "blunt" else N.design.cav if pk == "cav" else N.design.inf


static func pick_kind_v100(g: Game, N: Dictionary, P: Dictionary, stable: bool) -> String:
	var normal := func(): return N.design.cav if P.get("useCav", false) and stable and g.js_rand.call() < 0.3 else N.design.inf
	var C = N.get("counter")
	if C == null or C.base >= 0.999:
		return normal.call()
	var cd := counter_designs(g, N)
	var hv := {"pole": 0, "blunt": 0, "base": 0}
	var tot := [0]
	var add := func(k, n):
		if k == Game.MAGE or not is_military(g, k) or not g.DSTATS.has(k):
			return
		var s: Dictionary = g.DSTATS[k]
		var f: String = "pole" if not s.get("cav", false) and s.get("fam") == "pole" else "blunt" if not s.get("cav", false) and s.get("fam") == "blunt" else "base"
		hv[f] += n
		tot[0] += n
	for v in g.units:
		if v.owner == N.id and v.kind == "army":
			for k in v.troops:
				add.call(k, v.troops[k])
	for q in N.queue:
		add.call(q.kind, 1)
	var pk := "base"
	var gap := -INF
	for f in ["pole", "blunt", "base"]:
		var gg: float = C[f] - (float(hv[f]) / tot[0] if tot[0] else 0.0)
		if C[f] > 0 and gg > gap:
			gap = gg
			pk = f
	return cd.pole if pk == "pole" else cd.blunt if pk == "blunt" else normal.call()


static func rng_forge(g: Game, o: int) -> bool:
	for p in g.extras:
		if g.nation_of(p) == o and g.extras[p].any(func(e): return e.type == "forge"):
			return true
	return false


# web: v104.js aiCounterDesigns: the nation's best polearm (two-handed, no shield) and blunt weapon (with a shield)
static func counter_designs(g: Game, N: Dictionary) -> Dictionary:
	var Wd: Dictionary = GameData.c("WEAPONS")
	var F: Dictionary = GameData.c("FAMILY")
	var best := func(fam):
		var out = null
		for w in (F[fam].order if F.has(fam) else []):
			if Wd.has(w) and (Wd[w].get("tech") == null or has(g, N, Wd[w].tech)):
				out = w
		return out
	var main = g.design_by_id(N.design.inf) if g.DSTATS.has(N.design.inf) else null
	if main == null:
		for d in N.get("designs", []):
			if d.id == N.design.inf:
				main = d
	var armor: String = main.armor if main != null else "leather1"
	var pole = best.call("pole")
	var blunt = best.call("blunt")
	var shield = null
	if blunt != null and not Wd[blunt].get("twoH", false):
		for x in ["tower", "kite", "round"]:
			var SD: Dictionary = GameData.c("SHIELD_DEFS")
			if SD.has(x) and has(g, N, SD[x].tech):
				shield = x
				break
	var sig := "|".join(["realm", armor, str(pole), str(blunt), str(shield), "blunt1h", "dw" if has(g, N, "dualwield") else ""])
	var cdes = N.get("cdes")
	if N.get("cdSig") == sig and cdes != null and g.DSTATS.has(cdes.pole) and g.DSTATS.has(cdes.blunt):
		return cdes
	N.cdSig = sig
	N.cdv = N.get("cdv", 0) + 1
	var pd := {"id": "ai%dp%d" % [N.id, N.cdv], "name": CD_NAMES[0], "type": "inf", "weapon": pole if pole != null else "spear", "shield": null, "armor": armor, "horse": null, "race": "realm"}
	var bd := {"id": "ai%db%d" % [N.id, N.cdv], "name": CD_NAMES[1], "type": "inf", "weapon": blunt if blunt != null else "club", "shield": shield, "armor": armor, "horse": null, "race": "realm"}
	g.register_design(pd)
	g.register_design(bd)
	if not N.has("designs"):
		N.designs = []
	N.designs.append(pd)
	N.designs.append(bd)
	N.cdes = {"pole": pd.id, "blunt": bd.id}
	return N.cdes


# web: v100.js aiNoteDefeat: what beat the army decides the counters it trains
static func note_defeat(g: Game, a: Dictionary, b) -> void:
	var N = g.nations.get(a.owner)
	if N == null or b == null:
		return
	var cav := 0
	var plate := 0
	var other := 0
	for v in g.units:
		if v.kind != "army" or not is_same(v.get("battle"), b) or v.owner == a.owner or not g.is_nation(v.owner) or not g.hostile(v.owner, a.owner):
			continue
		for k in v.troops:
			if k == Game.MAGE:
				continue
			var n: int = v.troops[k]
			var s := g.stats_of(k, v.owner)
			if s.get("cav", false) and not s.get("champ", false):
				cav += n
			elif s.get("plate", false) and s.get("shieldArmor", 0) > 0:
				plate += n
			else:
				other += n
	var tot := cav + plate + other
	if not tot:
		return
	N.counter = {"pole": float(cav) / tot, "blunt": float(plate) / tot, "base": float(other) / tot, "t": g.t}


# web: v103.js aiCheckExperimental / aiRollMix (rule 16)
static func check_experimental(g: Game, N: Dictionary) -> void:
	if N.get("exp", false):
		if g.t >= N.get("mixAt", 0.0):
			roll_mix(g, N)
		return
	var st := stage(g, N)
	if st.dev and mages(g, N) > 0 and food(N) <= 1 and g.soldier_count(N.id) >= 8:
		N.exp = true
		roll_mix(g, N)


static func roll_mix(g: Game, N: Dictionary) -> void:
	var r := g.js_rand
	var w := {"base": 0.35 + r.call() * 0.4, "pole": r.call() * 0.4, "blunt": r.call() * 0.4, "cav": r.call() * 0.35}
	var tot: float = w.base + w.pole + w.blunt + w.cav
	for k in w:
		w[k] /= tot
	N.mix = w
	N.mixAt = g.t + 300


# web: v103.js aiCheckAggro (rule 19)
static func check_aggro(g: Game, N: Dictionary) -> void:
	if N.get("aggro", false) or N.diff != "difficult" or not N.get("exp", false):
		return
	var st := stage(g, N)
	if st.full and food(N) <= 1:
		N.aggro = true


# ================================================================================================================
# every frame: training queues, workers, upgrades (web: ai.js aiQueueStep + v101.js + v102.js, aiWorkersStep, aiUpgradesStep)

static func queue_step(g: Game, N: Dictionary, now: float) -> void:
	# v102: training in an occupied province waits
	for q in N.queue:
		if g.occ.has(q.prov) and g.occ[q.prov] != N.id:
			if q.has("held"):
				q.t0 += now - q.held
			q.held = now
		else:
			q.erase("held")
	# v101: a soldier who finishes where the enemy stands waits in the barracks
	var held: Array = N.queue.filter(func(q): return is_military(g, q.kind) and g.hostiles_in(q.prov, N.id).any(func(v): return v.kind == "army"))
	if not held.is_empty():
		N.queue = N.queue.filter(func(q): return not held.has(q))
	for q in N.queue.duplicate():
		if now - q.t0 < train_time(g, N, q.kind):
			continue
		N.queue = N.queue.filter(func(x): return not is_same(x, q))
		if not g.buildings.has(q.prov) or g.nation_of(q.prov) != N.id:
			continue
		if q.kind == g.WAYFINDER or q.kind == Game.MASON:
			var u := g.mk_unit(g.next_id, q.kind, "", q.prov, 0)
			g.next_id += 1
			u.owner = N.id
			u.slot = g.free_slot(q.prov, u)
			var xy := g.slot_pos(q.prov, u.slot)
			u.x = xy[0]
			u.y = xy[1]
			u.born = now
			g.units.append(u)
			continue
		var a = null
		for v in g.units:
			if v.kind == "army" and v.owner == N.id and v.prov == q.prov and not v.moving and v.get("battle") == null and not v.get("exiting", false) and not (q.kind == Game.MAGE and v.troops.get(Game.MAGE, 0) > 0):
				a = v
				break
		if a != null:
			a.troops[q.kind] = a.troops.get(q.kind, 0) + 1
			a.grew = now
		else:
			g.ai_new_army(N, q.prov, {q.kind: 1})
	for q in held:
		N.queue.append(q)


static func workers_step(g: Game, N: Dictionary, now: float) -> void:
	for u in g.units.duplicate():
		if u.owner != N.id:
			continue
		if u.kind == g.WAYFINDER and u.get("aiSurvey") != null:
			if u.moving or u.prov != u.aiSurvey.prov:
				u.aiSurvey = null
				continue
			if now - u.aiSurvey.t0 >= Game.SURVEY_TIME:
				N.surveyed[u.prov] = true
				u.aiSurvey = null
				u.erase("aiTarget")
			continue
		if u.kind != Game.MASON or u.get("aiJob") == null or u.moving or u.build != null:
			continue
		var j: Dictionary = u.aiJob
		if u.prov != j.prov:
			if not g.order(u, j.prov, true):
				u.aiJob = null
			continue
		if j.type == "outpost":
			var why := "taken" if g.units.any(func(v): return not is_same(v, u) and v.build != null and v.build.type == "outpost" and v.build.prov == j.prov) else outpost_why(g, N, j.prov, u)
			if why != "":
				if why != "cost":
					u.aiJob = null
				else:
					u.aiWait = u.get("aiWait", 0) + 1
					if u.aiWait > 600:
						u.aiJob = null
						u.aiWait = 0
				continue
			var oc: Dictionary = GameData.c("OUTPOST_COST")
			pay(N.stock, oc)
			u.build = {"prov": j.prov, "type": "outpost", "t0": now, "dur": g.build_time("outpost"), "paid": oc.duplicate()}
		else:
			var cost := build_cost(g, N, j.type)
			var why := build_why(g, N, j.prov, j.type, u)
			if why != "" or not can_pay(N.stock, cost):
				var drop := why != ""
				if not drop:
					u.aiWait = u.get("aiWait", 0) + 1
					drop = u.aiWait > 600
				if drop:
					u.aiJob = null
					u.aiWait = 0
				continue
			var used := g.used_slots_all(j.prov)
			var slot := 0
			while used.has(slot):
				slot += 1
			pay(N.stock, cost)
			var o := g.bslot_of(j.prov, slot)
			u.build = {"prov": j.prov, "type": j.type, "slot": slot, "ox": o[0], "oy": o[1], "t0": now, "dur": g.build_time(j.type), "paid": cost.duplicate()}
			var ic: Array = g.G.provs[j.prov].ic
			u.th = atan2(o[0] + ic[0] - u.x, o[1] + ic[1] - u.y)
		u.aiJob = null
		u.aiWait = 0


static func upgrades_step(g: Game, N: Dictionary, now: float) -> void:
	for p in N.ups.keys():
		var x: Dictionary = N.ups[p]
		if now - x.t0 < GameData.c("FORT_UPGRADE").time:
			continue
		N.ups.erase(p)
		var b = g.buildings.get(p)
		if b != null and b.owner == N.id and b.stage == 0:
			b.stage = 1
			b.born = now
	for k in N.xups.keys():
		var x: Dictionary = N.xups[k]
		if now - x.t0 < x.time:
			continue
		N.xups.erase(k)
		var parts: PackedStringArray = k.split("@")
		var p := int(parts[0])
		var slot := int(parts[1])
		for e in g.extras_in(p):
			if e.slot == slot:
				if g.nation_of(p) == N.id:
					e.level = x.to
					e.born = now
				break


# web: ai.js aiBuilt: a Mason finished (the shared build code calls this)
static func built(g: Game, u: Dictionary) -> void:
	var N = g.nations.get(u.owner)
	if N == null or u.build == null:
		return
	if u.build.type == "outpost":
		N.surveyed[u.build.prov] = true
	if u.build.type == "magetower" and N.school == null:
		draw_options(g, N, "mag")


# web: ai.js aiOnTransfer: a province changed hands
static func on_transfer(g: Game, p: int, from: int, to: int) -> void:
	var F = g.nations.get(from)
	if F != null:
		F.ups.erase(p)
		for k in F.xups.keys():
			if str(k).begins_with("%d@" % p):
				F.xups.erase(k)
		F.queue = F.queue.filter(func(q): return q.prov != p)
	var T = g.nations.get(to)
	if T != null:
		T.surveyed[p] = true


# ================================================================================================================
# Wayfinders: survey the land around the nation (web: ai.js aiWayfinders)

static func wayfinders(g: Game, N: Dictionary, P: Dictionary) -> void:
	var mine := g.provs_of(N.id)
	var near := g.hops_list(mine, g.all_nbr)
	var wfs := units_of(g, N, g.WAYFINDER)
	for u in wfs:
		if u.moving or u.get("aiSurvey") != null or u.get("exiting", false):
			continue
		if u.has("aiTarget") and u.aiTarget == u.prov and not N.surveyed.has(u.prov):
			u.aiSurvey = {"prov": u.prov, "t0": g.t}
			continue
		var taken := {}
		for v in wfs:
			if not is_same(v, u) and v.has("aiTarget"):
				taken[v.aiTarget] = true
		var d := reach(g, u)
		var best := -1
		var bs := INF
		for p in d:
			if N.surveyed.has(p) or taken.has(p) or g.buildings.has(p) or g.bandits_in(p) or near[p] > 3:
				continue
			var sc: float = d[p] + near[p] * 2
			if sc < bs:
				bs = sc
				best = p
		if best < 0:
			u.erase("aiTarget")
			var cap := g.capital_of(N.id)
			if cap >= 0 and u.prov != cap and not u.moving:
				g.order(u, cap, true)
			continue
		u.aiTarget = best
		if best == u.prov:
			u.aiSurvey = {"prov": best, "t0": g.t}
		elif not g.order(u, best, true):
			u.erase("aiTarget")


# ================================================================================================================
# armies (web: ai.js aiArmyOrders + v101.js, aiBanditGoal; v100.js aiWarPlan + v101.js rally; aiWarGoal ai.js → v100 →
# v101 → v103)

static func army_orders(g: Game, N: Dictionary, P: Dictionary, now: float) -> void:
	var enemies := g.enemies_of(N.id)
	# v101: re-plan threatened armies at once
	if not enemies.is_empty():
		for a in armies(g, N):
			if a.moving and a.get("battle") == null and not a.get("retreating", false):
				var d := danger_for(g, N, g.raw_strength([a]))
				if d.has(a.get("final", -1)) or (not a.path.is_empty() and d.has(a.prov)):
					a.aiPlanT = -99.0
	var mine := armies(g, N)
	var cap := g.capital_of(N.id)
	if cap < 0:
		var pl := g.provs_of(N.id)
		cap = pl[0] if not pl.is_empty() else -1
	var by_prov := {}
	for a in mine:
		if a.moving or a.get("battle") != null or a.get("retreating", false) or a.get("exiting", false):
			continue
		var o = by_prov.get(a.prov)
		if o != null and o.troops.get(Game.MAGE, 0) > 0 and a.troops.get(Game.MAGE, 0) > 0:
			continue
		if o != null:
			for k in a.troops:
				o.troops[k] = o.troops.get(k, 0) + a.troops[k]
			o.grew = now
			a._gone = true
			g.units = g.units.filter(func(v): return not is_same(v, a))
		else:
			by_prov[a.prov] = a
	for a in armies(g, N):
		if a.get("battle") != null:
			var foes := g.units.filter(func(v): return v.kind == "army" and is_same(v.get("battle"), a.battle) and v.owner != N.id and not v.get("retreating", false))
			if g.raw_strength([a]) < 0.35 * g.raw_strength(foes) and g.retreat_to(a) >= 0:
				g.retreat(a)
			continue
		if a.get("retreating", false) or a.get("exiting", false) or a.get("retreatHome", false):
			continue
		if enemies.is_empty():
			var goal := bandit_goal(g, N, a) if N.diff != "easy" else -1
			var tgt := goal if goal >= 0 else cap
			if tgt >= 0 and a.prov != tgt and not (a.moving and a.get("final", -1) == tgt):
				g.order(a, tgt, true)
			continue
		if a.moving and a.get("aiPlanT", -INF) > now - 5:
			continue
		a.aiPlanT = now
		var best := war_goal(g, N, a, enemies)
		var tgt2 := best if best >= 0 else cap
		if (a.moving and a.get("final", -1) == tgt2) or (not a.moving and a.prov == tgt2):
			continue
		g.order(a, tgt2, true)


static func bandit_goal(g: Game, N: Dictionary, a: Dictionary) -> int:
	var st := g.raw_strength([a])
	var d := reach(g, a, 4)
	var best := -1
	var bd := INF
	for p in d:
		if not g.bandits_in(p) or g.buildings.has(p) or not g.all_nbr[p].any(func(q): return g.nation_of(q) == N.id):
			continue
		var gang := g.raw_strength(g.units.filter(func(v): return v.get("bandit", false) and v.prov == p))
		if st < gang * 2:
			continue
		if d[p] < bd:
			bd = d[p]
			best = p
	return best


static func stack_of(W: Dictionary, p: int) -> float:
	return W.stacks.get(p, 0.0)


# web: v100.js aiWarPlan (+ v101.js the rally point), recomputed twice a second
static func war_plan(g: Game, N: Dictionary, enemies: Array) -> Dictionary:
	var key := floori(g.t * 2)
	var old = g.ai_war_plans.get(N.id)
	if old != null and old.key == key:
		return old
	var mine: Array = armies(g, N).filter(func(v): return not v.get("retreating", false) and not v.get("exiting", false))
	var main = null
	var ms := -1.0
	for a in mine:
		var s := g.raw_strength([a])
		if s > ms:
			ms = s
			main = a
	var my_total := g.raw_strength(mine)
	var stacks := {}
	for v in g.units:
		if v.kind == "army" and enemies.has(v.owner) and g.troop_count(v) > 0 and not v.get("retreating", false):
			stacks[v.prov] = stacks.get(v.prov, 0.0) + g.raw_strength([v])
	var foe_main := 0.0
	var foe_prov := -1
	for p in stacks:
		if stacks[p] > foe_main:
			foe_main = stacks[p]
			foe_prov = p
	var cap := g.capital_of(N.id)
	if cap < 0:
		var pl := g.provs_of(N.id)
		cap = pl[0] if not pl.is_empty() else -1
	var strong := foe_main < my_total * AI_ENGAGE
	var home = g.hops_list(cap, g.all_nbr) if cap >= 0 else null
	var pushing := false
	for v in g.units:
		if v.kind != "army" or not enemies.has(v.owner) or g.troop_count(v) <= 0 or v.get("retreating", false) or g.raw_strength([v]) < foe_main * 0.5:
			continue
		var f: int = v.get("final", -1)
		if v.moving and f >= 0 and (g.nation_of(f) == N.id or (home != null and home[f] != INF and home[v.prov] != INF and home[f] < home[v.prov])):
			pushing = true
			break
	var W := {"key": key, "main": main, "mainStr": ms, "myTotal": my_total, "stacks": stacks, "foeMain": foe_main, "foeProv": foe_prov, "cap": cap, "strong": strong, "pushing": pushing}
	g.ai_war_plans[N.id] = W
	W.rally = rally(g, N, W)
	return W


# web: v101.js aiDangerFor: where enemy forces (and bandit gangs) that would beat this strength stand or march to
static func danger_for(g: Game, N: Dictionary, st: float) -> Dictionary:
	var W = g.ai_war_plans.get(N.id)
	var stacks: Dictionary = W.stacks if W != null else {}
	var out := {}
	for p in stacks:
		if stacks[p] >= st * AI_ENGAGE:
			out[p] = true
	var gangs := {}
	for v in g.units:
		if v.kind == "army" and v.get("bandit", false) and g.troop_count(v) > 0:
			gangs[v.prov] = gangs.get(v.prov, 0.0) + g.raw_strength([v])
	for p in gangs:
		if gangs[p] >= st * AI_ENGAGE:
			out[p] = true
	for v in g.units:
		if v.kind == "army" and v.moving and v.get("final", -1) >= 0 and g.hostile(v.owner, N.id) and g.is_nation(v.owner) and g.raw_strength([v]) >= st * AI_ENGAGE:
			out[v.final] = true
	return out


# web: v101.js aiRally: the capital unless an outmatching enemy stands in or next to it, else the safest own province
static func rally(g: Game, N: Dictionary, W: Dictionary) -> int:
	var total := maxf(1.0, W.myTotal)
	var bad := {}
	for p in W.stacks:
		if W.stacks[p] >= total * AI_ENGAGE:
			bad[p] = true
			for q in g.all_nbr[p]:
				bad[q] = true
	if W.cap >= 0 and not bad.has(W.cap):
		return W.cap
	var from = g.hops_list(W.foeProv, g.all_nbr) if W.foeProv >= 0 else null
	var best := -1
	var bd := -1.0
	for p in g.provs_of(N.id):
		if bad.has(p) or g.occ.has(p):
			continue
		var d: float = from[p] if from != null and from[p] != INF else 0.0
		var v := d * 10 + (5 if g.extras_in(p).any(func(e): return e.type == "barracks") else 0)
		if v > bd:
			bd = v
			best = p
	return best if best >= 0 else W.cap


# web: ai.js aiWarGoal (aiWarGoal0): defend, take back what was lost, occupy the enemy's land when strong enough
static func war_goal0(g: Game, N: Dictionary, a: Dictionary, enemies: Array, diff: String) -> int:
	var st := g.raw_strength([a])
	var d := reach(g, a, 16)
	var goals := []
	var foe_in := func(p): return g.raw_strength(g.units.filter(func(v): return v.kind == "army" and v.prov == p and enemies.has(v.owner) and not v.get("retreating", false)))
	var my_pow := army_power(g, N.id)
	var their := 0.0
	for o in enemies:
		their += army_power(g, o)
	var offense := diff == "moderate" or my_pow > their * 1.5
	for p in g.buildings:
		if not d.has(p):
			continue
		var b: Dictionary = g.buildings[p]
		if b.owner == N.id:
			var f: float = foe_in.call(p)
			if f and f <= st * 1.3:
				goals.append([p, 0.0])
			elif g.occ.has(p) and not f:
				goals.append([p, 1.0])
		elif offense and enemies.has(b.owner) and g.occ.get(p, 0) != N.id:
			var f2: float = foe_in.call(p)
			if f2 <= st * 0.9:
				goals.append([p, 1.5 if b.stage == 2 else 2.0])
	var best := -1
	var bd := INF
	for gl in goals:
		var v: float = d[gl[0]] + gl[1] * 3
		if v < bd:
			bd = v
			best = gl[0]
	return best


static func war_goal_v100(g: Game, N: Dictionary, a: Dictionary, enemies: Array) -> int:
	var W := war_plan(g, N, enemies)
	var st := g.raw_strength([a])
	var soldiers: int = g.troop_count(a) - a.troops.get(Game.MAGE, 0)
	var is_main := is_same(a, W.main)
	var cap_foe := stack_of(W, W.cap)
	if W.strong:
		if is_main or W.foeMain < st * AI_ENGAGE:
			var gl := war_goal0(g, N, a, enemies, N.diff)
			return W.cap if gl >= 0 and stack_of(W, gl) >= st * AI_ENGAGE else gl
		var m = W.main
		if m == null or m.get("battle") != null or m.moving or g.nation_of(m.prov) != N.id or stack_of(W, m.prov) > 0:
			return W.cap
		return m.prov
	if not is_main:
		return W.cap
	if cap_foe and cap_foe < st * AI_ENGAGE:
		return W.cap
	if not W.pushing:
		return W.cap
	if soldiers < AI_RAID_MIN_PUSH:
		return W.cap
	var d := reach(g, a, 16)
	var danger := {}
	for p in W.stacks:
		if W.stacks[p] >= st * AI_ENGAGE:
			danger[p] = true
			for q in g.all_nbr[p]:
				danger[q] = true
	var best := -1
	var bd := INF
	for p in g.buildings:
		if not d.has(p) or danger.has(p):
			continue
		var held := stack_of(W, p)
		if held > st * 0.5:
			continue
		var b: Dictionary = g.buildings[p]
		var w: float
		if b.owner == N.id:
			if not g.occ.has(p):
				continue
			w = 0.0
		elif enemies.has(b.owner) and g.occ.get(p, 0) != N.id:
			w = 0.5 if b.stage == 2 else 1.0 if b.stage == 1 else 2.0
		else:
			continue
		var v: float = d[p] + w * 3
		if v < bd:
			bd = v
			best = p
	return best if best >= 0 else W.cap


static func war_goal_v101(g: Game, N: Dictionary, a: Dictionary, enemies: Array) -> int:
	var W := war_plan(g, N, enemies)
	var st := g.raw_strength([a])
	var danger := danger_for(g, N, st)
	var threatened: bool = danger.has(a.prov) or g.all_nbr[a.prov].any(func(q): return stack_of(W, q) >= st * AI_ENGAGE)
	if threatened and a.prov != W.rally:
		return W.rally
	var gl := war_goal_v100(g, N, a, enemies)
	if gl == W.cap and W.rally != W.cap and not (stack_of(W, W.cap) and stack_of(W, W.cap) < st * AI_ENGAGE):
		return W.rally
	return gl


static func war_goal(g: Game, N: Dictionary, a: Dictionary, enemies: Array) -> int:
	if not N.get("aggro", false):
		return war_goal_v101(g, N, a, enemies)
	var W := war_plan(g, N, enemies)
	var st := g.raw_strength([a])
	if not is_same(a, W.main) or not W.strong or danger_for(g, N, st).has(a.prov):
		return war_goal_v101(g, N, a, enemies)
	var gl := war_goal0(g, N, a, enemies, "moderate")
	return gl if gl >= 0 and stack_of(W, gl) < st * AI_ENGAGE else war_goal_v101(g, N, a, enemies)


# web: v100.js stepAISurge: once a nation has lost half its army or more in a war, it trains faster
static func step_surge(g: Game) -> void:
	for id in g.nations:
		var N: Dictionary = g.nations[id]
		if not N.alive:
			continue
		if g.enemies_of(N.id).is_empty():
			N.warPeak = 0
			N.surge = false
			continue
		var n := g.soldier_count(N.id)
		N.warPeak = maxi(N.get("warPeak", 0), n)
		if not N.get("surge", false) and N.warPeak >= 4 and n <= N.warPeak * 0.5:
			N.surge = true


# ================================================================================================================
# declaring war (web: ai.js aiConsiderWar → v103.js aggressive Difficult → v104.js the Rival first)

static func consider_war(g: Game, N: Dictionary, P: Dictionary) -> void:
	if N.diff == "easy":
		return
	if N.get("stance", "normal") == "threatened":
		N.warPlan = null
		return
	var r = N.get("rival")
	if r == null or not g.alive_nation(r):
		consider_war_v103(g, N, P)
		return
	var partners: Array = g.allies_of(N.id).filter(func(o): return g.nations.has(o) and g.nations[o].alive and g.nations[o].get("rival") == r and g.nations[o].diff != "easy" and g.nations[o].get("stance", "normal") != "threatened")
	if not g.at_war(N.id, r) and partners.any(func(o): return g.at_war(o, r)) and g.nations_border(N.id, r) and g.declare_why(N.id, r) == "":
		N.warPlan = null
		g.declare_war(N.id, r)
		return
	if not g.enemies_of(N.id).is_empty():
		if N.get("warPlan") != null and N.warPlan.target != r:
			N.warPlan = null
		return
	var my_pow := army_power(g, N.id)
	for o in partners:
		my_pow += army_power(g, o)
	var ok := func(): return not g.allied(N.id, r) and g.nations_border(N.id, r) and g.declare_why(N.id, r) == "" and my_pow > 0 and my_pow >= def_power(g, r) * V104_RIVAL_RATIO[N.diff]
	if N.get("warPlan") != null:
		if g.t < N.warPlan.at:
			N.warCheck = N.warPlan.at
			return
		N.warPlan = null
		if ok.call() and g.declare_war(N.id, r):
			for o in partners:
				if not g.at_war(o, r) and g.nations_border(o, r) and g.declare_why(o, r) == "":
					g.declare_war(o, r)
		return
	if N.stock.gold < g.W("declareCost").gold + 20 or g.t < N.get("peaceUntil", 0.0) or not ok.call():
		return
	N.warPlan = {"target": r, "at": g.t + AI_WAR_THINK}
	N.warCheck = N.warPlan.at
	if r == Game.ME and g.knows(N.id):
		var pn := ""
		if not partners.is_empty():
			pn = " and its ally, the %s," % g.player_info(partners[0]).name
		g.toast("The %s%s %s gathering armies on your border…" % [g.player_info(N.id).name, pn, "are" if not partners.is_empty() else "is"], true)


static func consider_war_v103(g: Game, N: Dictionary, P: Dictionary) -> void:
	if not N.get("aggro", false):
		consider_war_base(g, N, P)
		return
	if not g.enemies_of(N.id).is_empty():
		N.warPlan = null
		return
	var my_pow := army_power(g, N.id)
	var ok := func(o): return o != N.id and g.alive_nation(o) and not g.allied(N.id, o) and g.nations_border(N.id, o) and g.declare_why(N.id, o) == "" and my_pow >= def_power(g, o)
	if N.get("warPlan") != null:
		if g.t < N.warPlan.at:
			N.warCheck = N.warPlan.at
			return
		var tg: int = N.warPlan.target
		N.warPlan = null
		if ok.call(tg):
			g.declare_war(N.id, tg)
		return
	if my_pow <= 0 or N.stock.gold < g.W("declareCost").gold + 20 or g.t < N.get("peaceUntil", 0.0):
		return
	var cands: Array = g.live_nations().filter(ok)
	if cands.is_empty():
		return
	cands = JS.stable_sort(cands, func(x, y): return (my_pow - def_power(g, x)) - (my_pow - def_power(g, y)))
	_plan_war(g, N, cands[0])


static func consider_war_base(g: Game, N: Dictionary, P: Dictionary) -> void:
	if not g.enemies_of(N.id).is_empty():
		N.warPlan = null
		return
	var my_pow := army_power(g, N.id)
	var ok := func(o): return o != N.id and g.alive_nation(o) and not g.allied(N.id, o) and g.nations_border(N.id, o) and g.declare_why(N.id, o) == "" and my_pow >= 2 * maxf(1.0, def_power(g, o)) and (my_pow - def_power(g, o)) * 10 >= AI_WAR_MARGIN
	if N.get("warPlan") != null:
		if g.t < N.warPlan.at:
			N.warCheck = N.warPlan.at
			return
		var tg: int = N.warPlan.target
		N.warPlan = null
		if ok.call(tg):
			g.declare_war(N.id, tg)
		return
	if my_pow <= 0 or N.stock.gold < g.W("declareCost").gold + 20:
		return
	var cands: Array = g.live_nations().filter(ok)
	if cands.is_empty():
		return
	cands = JS.stable_sort(cands, func(x, y): return def_power(g, x) - def_power(g, y))
	_plan_war(g, N, cands[0])


static func _plan_war(g: Game, N: Dictionary, tg: int) -> void:
	N.warPlan = {"target": tg, "at": g.t + AI_WAR_THINK}
	N.warCheck = N.warPlan.at
	if tg == Game.ME and g.knows(N.id):
		g.toast("The %s is gathering its armies on your border…" % g.player_info(N.id).name, true)


# ================================================================================================================
# v104: stances (Normal / Wary / Threatened) and Rivals

static func v104_maps(g: Game) -> Dictionary:
	var k := floori(g.t / 5)
	if g.v104_cache.get("k", -1) != k:
		g.v104_cache = {"k": k, "B": g.border_sets(), "N": g.nation_sizes()}
	return g.v104_cache


static func v104_size(g: Game, o: int) -> int:
	return v104_maps(g).N.get(o, 0)


static func v104_econ(g: Game, o: int) -> float:
	if o == Game.ME:
		return g.income.get("gold", 0) + g.tech_rate("gov") + g.tech_rate("mil") + g.tech_rate("mag")
	var N = g.nations.get(o)
	if N == null:
		return 0.0
	return N.get("income", {}).get("gold", 0) + tech_rate(g, N, "gov") + tech_rate(g, N, "mil") + tech_rate(g, N, "mag")


static func v104_neighbors(g: Game, N: Dictionary) -> Array:
	var B: Dictionary = v104_maps(g).B.get(N.id, {})
	return B.keys().filter(func(o): return o != N.id and g.alive_nation(o) and g.has_met(N.id, o))


static func v104_threatens(g: Game, N: Dictionary, o: int) -> bool:
	if g.allied(N.id, o) or o == Game.ME or not g.nations.has(o):
		return false
	if g.enemies_of(o).any(func(x): return x != N.id):
		return false
	var side := [N.id] + g.allies_of(N.id).filter(func(x): return x != o and g.alive_nation(x))
	var mine := 0
	var econ := 0.0
	var pow := 0.0
	for x in side:
		mine += v104_size(g, x)
		econ += v104_econ(g, x)
		pow += army_power(g, x)
	var theirs := v104_size(g, o)
	if theirs < maxf(mine + 1, mine * V104_LARGER):
		return false
	return v104_econ(g, o) >= econ * V104_ECON or army_power(g, o) >= maxf(1.0, pow) * V104_ARMY


static func v104_think(g: Game, N: Dictionary) -> void:
	if g.t < N.get("v104at", 0.0):
		return
	N.v104at = g.t + V104_THINK
	if not N.has("stance"):
		N.stance = "normal"
	if N.get("rival") != null and not g.alive_nation(N.rival):
		N.rivalWas = N.rival
		N.rival = null
	var nb := v104_neighbors(g, N)
	var threats: Array = nb.filter(func(o): return v104_threatens(g, N, o))
	if not threats.is_empty():
		N.stance = "threatened"
		threats = JS.stable_sort(threats, func(a, b): return army_power(g, b) - army_power(g, a))
		N.threatBy = threats[0]
	elif N.stance == "threatened":
		N.stance = "wary"
		N.threatBy = null
	var calm: Array = nb.filter(func(o): return not threats.has(o))
	if N.get("rival") == null and calm.size() >= 2:
		v104_pick_rival(g, N, calm)
	if N.stance == "threatened":
		return
	var has_ally := not g.allies_of(N.id).is_empty()
	var my_size := v104_size(g, N.id)
	var bigger := nb.all(func(o): return my_size > v104_size(g, o))
	var hunted := nb.any(func(o): return o != Game.ME and g.nations.has(o) and g.nations[o].get("rival") == N.id)
	if has_ally or bigger:
		N.stance = "normal"
		return
	if not hunted:
		return
	var cands: Array = g.live_nations().filter(func(x): return x != N.id and g.ally_why(N.id, x) == "")
	cands = JS.stable_sort(cands, func(a, b): return army_power(g, b) - army_power(g, a))
	if cands.is_empty():
		N.stance = "wary"
		return
	var f: int = cands[0]
	for x in cands:
		if x != Game.ME:
			f = x
			break
	var hunter := -1
	for o in nb:
		if g.nations.has(o) and g.nations[o].get("rival") == N.id:
			hunter = o
			break
	if f == Game.ME:
		if g.ally_ask.get(N.id, 0.0) <= g.t and g.offer_alliance(N.id, hunter):
			g.ally_ask[N.id] = g.t + g.W("allyAskAgain")
	else:
		g.form_alliance(N.id, f, hunter)


static func v104_pick_rival(g: Game, N: Dictionary, calm: Array) -> void:
	var race: String = g.race_of.get(N.id, "realm")
	var rof := func(o): return g.race_of.get(o, "realm")
	var same: Array = calm.filter(func(o): return rof.call(o) == race)
	var other: Array = calm.filter(func(o): return rof.call(o) != race)
	var border := func(o):
		var n := 0
		for p in g.provs_of(N.id):
			n += g.all_nbr[p].filter(func(q): return g.nation_of(q) == o).size()
		return n
	var al := g.allies_of(N.id)
	var pickf := func(lst: Array):
		var c: Array = lst.filter(func(o): return not g.allied(N.id, o))
		c = JS.stable_sort(c, func(a, b):
			var ra := 0 if al.any(func(x): return g.nations.has(x) and g.nations[x].get("rival") == a) else 1
			var rb := 0 if al.any(func(x): return g.nations.has(x) and g.nations[x].get("rival") == b) else 1
			if ra != rb:
				return ra - rb
			var dp := def_power(g, a) - def_power(g, b)
			if dp != 0:
				return dp
			return border.call(b) - border.call(a))
		return c[0] if not c.is_empty() else null
	var rv = null
	var team := []
	if not same.is_empty() and not other.is_empty():
		rv = pickf.call(other)
		team = same
	elif same.size() >= 2:
		var met_other := g.live_nations().any(func(o): return o != N.id and rof.call(o) != race and g.has_met(N.id, o))
		if met_other:
			return
		rv = pickf.call(same)
		team = same.filter(func(o): return o != rv)
	else:
		return
	if rv == null:
		return
	N.rival = rv
	N.rivalSince = g.t
	for f in team:
		v104_ally(g, N, f, rv)


static func v104_ally(g: Game, N: Dictionary, f: int, rv: int) -> void:
	if not g.allied(N.id, f):
		if g.ally_why(N.id, f) != "":
			return
		if f == Game.ME:
			if g.ally_ask.get(N.id, 0.0) <= g.t and g.offer_alliance(N.id, rv):
				g.ally_ask[N.id] = g.t + g.W("allyAskAgain")
			return
		g.form_alliance(N.id, f, rv)
	var F = g.nations.get(f)
	if F != null and F.get("rival") == null and rv != f and not g.allied(f, rv):
		F.rival = rv
		F.rivalSince = g.t


# web: v104.js v104Dismiss: Wary, at peace and short of food: soldiers go home
static func v104_dismiss(g: Game, N: Dictionary) -> void:
	if N.get("stance", "normal") != "wary" or not g.enemies_of(N.id).is_empty() or food(N) >= 0 or N.stock.food > 300:
		return
	var short := -food(N)
	var lst := g.units.filter(func(v): return v.kind == "army" and v.owner == N.id and v.get("battle") == null and not v.moving and g.troop_count(v) > 0)
	var fo := func(k): return int(g.unit_defs[k].get("upkeep", {}).get("food", 0)) if g.unit_defs.has(k) else 0
	for a in lst:
		var ks: Array = a.troops.keys().filter(func(k): return k != Game.MAGE)
		ks = JS.stable_sort(ks, func(x, y): return fo.call(x) - fo.call(y))
		for k in ks:
			var f: int = fo.call(k) if g.unit_defs.has(k) and g.unit_defs[k].has("upkeep") and g.unit_defs[k].upkeep.get("food", 0) else 2
			while short > 0 and a.troops.get(k, 0) > 0:
				a.troops[k] -= 1
				short -= f
			if not a.troops.get(k, 0):
				a.troops.erase(k)
			if short <= 0:
				break
		if g.troop_count(a) == 0:
			g.remove_army(a)
		if short <= 0:
			break
	N.income = income(g, N)


# ================================================================================================================
# v104 crops: a change of crop counts after 10 seconds; computer nations switch to Fiber when wood is scarce

static func step_crops(g: Game) -> void:
	if g.t < g.crop_scan_at:
		return
	g.crop_scan_at = g.t + 0.5
	var touched := {}
	for p in g.extras:
		for e in g.extras[p]:
			if e.has("cropNext") and g.t >= e.cropAt:
				e.crop = e.cropNext
				e.erase("cropNext")
				e.erase("cropAt")
				var o := g.nation_of(p)
				if o == Game.ME:
					g.compute_income()
				elif g.nations.has(o):
					touched[o] = true
	for o in touched:
		g.nations[o].income = income(g, g.nations[o])


static func wood_scarce(g: Game, N: Dictionary) -> bool:
	return wood(N) < 3 or (wood(N) < 10 and not can_build(g, N, "lumber"))


static func farms(g: Game, N: Dictionary) -> Array:
	return extra_list(g, N).filter(func(pe): return pe[1].type == "farm" and not g.occ.has(pe[0]))


static func fiber_candidate(g: Game, N: Dictionary):
	var st := gives(g, N, "farm")
	var c: Array = farms(g, N).filter(func(pe): return crop_target(pe[1]) != "fiber" and not fiber_taken(g, pe[0], pe[1]) and food(N) - crop_gives(crop_target(pe[1]), st).get("food", 0) >= 0)
	c = JS.stable_sort(c, func(a, b): return crop_gives(crop_target(a[1]), st).get("food", 0) - crop_gives(crop_target(b[1]), st).get("food", 0))
	return c[0] if not c.is_empty() else null


static func v104_crops(g: Game, N: Dictionary) -> void:
	if g.t < N.get("cropThink", 0.0):
		return
	N.cropThink = g.t + 10
	var fs := farms(g, N)
	if fs.is_empty() or fs.any(func(pe): return pe[1].has("cropNext")):
		return
	var st := gives(g, N, "farm")
	var fd := food(N)
	var wd := wood(N)
	var T: bool = N.get("stance", "normal") == "threatened"
	var find := func(c):
		for pe in fs:
			if crop_of(pe[1]) == c:
				return pe
		return null
	if fd < 0:
		var f = find.call("cash")
		if f == null and wd >= 10:
			f = find.call("fiber")
		if f != null:
			set_crop(g, f[1], "staple")
		return
	if wood_scarce(g, N) and not (T and wd >= 2):
		var f = fiber_candidate(g, N)
		if f != null:
			set_crop(g, f[1], "fiber")
			return
	if wd > 25 and fd < 6:
		var f = find.call("fiber")
		if f != null:
			set_crop(g, f[1], "staple")
			return
	var gold_short: bool = N.stock.gold < 150 or stage(g, N).noGold
	if not T and gold_short and fd - (st.get("food", 5) - CASH_GIVES.food) >= 4:
		var f = find.call("staple")
		if f != null:
			set_crop(g, f[1], "cash")
			return
	if (T or not gold_short) and fd < 4:
		var f = find.call("cash")
		if f != null:
			set_crop(g, f[1], "staple")


# ================================================================================================================
# v106: proclaimed enemies, and developing provinces when nothing else is left to do

static func wilds_shared(g: Game) -> Array:
	var k := floori(g.t / 5)
	if g.wilds_t == k and g.wilds != null:
		return g.wilds
	var comp := {}
	var touch := []
	for p in g.G.provs.size():
		if g.buildings.has(p) or g.world.provinces[p].get("sealed", false) or comp.has(p):
			continue
		var id := touch.size()
		var set := {}
		var stack := [p]
		comp[p] = id
		while not stack.is_empty():
			var x: int = stack.pop_back()
			for q in g.all_nbr[x]:
				if not g.buildings.has(q) and not g.world.provinces[q].get("sealed", false):
					if not comp.has(q):
						comp[q] = id
						stack.append(q)
				else:
					var o := g.nation_of(q)
					if o:
						set[o] = true
		touch.append(set)
	g.wilds_t = k
	g.wilds = touch
	return touch


static func enemy_neighbor(g: Game, o: int, t2: int) -> bool:
	return g.alive_nation(t2) and g.has_met(o, t2) and (g.nations_border(o, t2) or wilds_shared(g).any(func(s): return s.has(o) and s.has(t2)))


static func pick_enemy(g: Game, N: Dictionary) -> int:
	var o: int = N.id
	var c: Array = g.live_nations().filter(func(x): return x != o and not g.allied(o, x) and enemy_neighbor(g, o, x) and g.opinion(o, x) < 0)
	if c.is_empty():
		return 0
	c = JS.stable_sort(c, func(x, y):
		var d := g.opinion(o, x) - g.opinion(o, y)
		if d != 0:
			return d
		var rx := 1 if g.race_of.get(x, "realm") != g.race_of.get(o, "realm") else 0
		var ry := 1 if g.race_of.get(y, "realm") != g.race_of.get(o, "realm") else 0
		if ry != rx:
			return ry - rx
		return nation_power(g, y) - nation_power(g, x))
	return c[0]


static func enemy_think(g: Game, N: Dictionary) -> void:
	if not N.alive or N.get("v106en", 0.0) > g.t:
		return
	N.v106en = g.t + 20 + g.js_rand.call() * 10
	var o: int = N.id
	var cur := g.enemy_of(o)
	var D := g.enemy_state()
	if cur and (not enemy_neighbor(g, o, cur) or g.opinion(o, cur) >= 0 or g.allied(o, cur)):
		g.renounce_enemy(o)
		return
	if D.enemy.has(o) and not cur:
		D.enemy.erase(o)
	var pk := pick_enemy(g, N)
	if not pk or pk == cur:
		return
	if cur and g.opinion(o, pk) > g.opinion(o, cur) - 100:
		return
	var why := g.proclaim_why(o, pk)
	if why != "" and not (cur and why.contains("renounce first")):
		return
	if D.enemyAt.get(o, -1e9) + g.DIPL_ENEMY_EVERY > g.t:
		return
	if cur:
		g.renounce_enemy(o)
	g.proclaim_enemy(o, pk)
	if pk != Game.ME and (g.knows(o) or g.knows(pk)) and g.met.has(o):
		g.toast("The %s proclaimed the %s their enemy." % [g.player_info(o).name, g.player_info(pk).name])


# web: v106.js stepEnemies
static func step_enemies(g: Game) -> void:
	var D := g.enemy_state()
	for k in D.enemy.keys():
		var r: Dictionary = D.enemy[k]
		if not g.alive_nation(int(k)) or not g.alive_nation(r.t):
			D.enemy.erase(k)
	if g.ai_frozen:
		return
	for id in g.nations:
		if g.nations[id].alive:
			enemy_think(g, g.nations[id])


# web: v106.js aiDevelop
static func develop(g: Game, N: Dictionary) -> void:
	if not N.alive or N.get("v106dev", 0.0) > g.t:
		return
	N.v106dev = g.t + 30 + g.js_rand.call() * 15
	var st := stage(g, N)
	if not st.full:
		return
	var mine: Array = g.provs_of(N.id).filter(func(p): return not g.occ.has(p))
	if mine.any(func(p): return g.free_plot(p) >= 0):
		return
	if N.get("income", income(g, N)).food >= 1:
		return
	for p in g.devel:
		var r: Dictionary = g.devel[p]
		if r.job != null and r.owner == N.id:
			return
	var ok: Array = mine.filter(func(p): return g.dev_why(p, N.id) == null)
	if ok.is_empty():
		return
	var lv0 := 99
	for p in ok:
		lv0 = mini(lv0, dev_lv(g, p))
	var c := g.dev_cost(lv0)
	for k in c:
		if N.stock[k] < c[k] + 200:
			return
	ok = JS.stable_sort(ok, func(a, b):
		var d := dev_lv(g, a) - dev_lv(g, b)
		if d != 0:
			return d
		return g.buildings[b].stage - g.buildings[a].stage)
	g.start_develop(ok[0], N.id)


static func dev_lv(g: Game, p: int) -> int:
	var r = g.dev_rec(p)
	return r.lv if r != null else 0


# web: gpc.js aiQuake: at war, a still Mage army casts an Earthquake where it occupies buildings, else a Shockwave at
# a hostile wall next door
static func quake(g: Game, N: Dictionary, now: float) -> void:
	if N.get("quakeAt", 0.0) > now or g.enemies_of(N.id).is_empty():
		return
	for a in g.units.duplicate():
		if a.owner != N.id or a.kind != "army" or not a.troops.get(Game.MAGE, 0) > 0 or a.moving or a.get("battle") != null or a.get("exiting", false) or a.get("cast") != null or a.get("quake"):
			continue
		if g.tech_of(N.id, "earthquake") and g.quake_why(a) == null and not g.extras_in(a.prov).is_empty():
			if g.start_spell2(a, "quake"):
				N.quakeAt = now + 10
				return
		for q in g.all_nbr[a.prov]:
			if g.shock_why(a, q) == null:
				if g.start_spell2(a, "shock", q):
					N.quakeAt = now + 10
					return
				break
	N.quakeAt = now + 3


# web: v102.js stepAiScouted: where each computer nation's scouts and armies have been
static func step_scouted(g: Game, now: float) -> void:
	if now - g.ai_scout_t < 0.5 and now >= g.ai_scout_t:
		return
	g.ai_scout_t = now
	for u in g.units:
		if u.owner == Game.ME or not g.is_nation(u.owner) or (u.kind != "army" and u.kind != g.WAYFINDER):
			continue
		var N = g.nations.get(u.owner)
		if N == null:
			continue
		if not N.has("scouted"):
			N.scouted = {}
		N.scouted[u.prov] = true


# ================================================================================================================
# web: stepAI(t) with its wrappers, outermost first: v104 (crops; stance and Rival; dismissing), v103 (experimental armies,
# aggression, swapping Lumber Mills), v100 (the war surge), ai.js (the brain), v102 (where the scouts have been)

static func step(g: Game, now: float) -> void:
	if not g.started:
		return
	var due := func(N): return N.alive and now >= N.think
	step_crops(g)
	for id in g.nations:
		var N: Dictionary = g.nations[id]
		if due.call(N):
			v104_crops(g, N)
	for id in g.nations:
		var N: Dictionary = g.nations[id]
		if due.call(N):
			v104_think(g, N)
			v104_dismiss(g, N)
	for id in g.nations:
		var N: Dictionary = g.nations[id]
		if due.call(N):
			check_experimental(g, N)
			check_aggro(g, N)
			swap_lumber(g, N)
	step_surge(g)
	if now >= g.ally_check:
		g.ally_check = now + 5
		g.step_alliances()
	for id in g.nations.keys():
		var N: Dictionary = g.nations[id]
		if not N.alive:
			continue
		queue_step(g, N, now)
		workers_step(g, N, now)
		upgrades_step(g, N, now)
		if now < N.think:
			continue
		N.think = now + D(N).think
		if g.provs_of(N.id).is_empty():
			g.kill_nation(N.id, 0)
			continue
		var P := plan(g, N)
		fort_up(g, N, P)
		relieve_wood(g, N)
		train(g, N, P)
		masons(g, N, P)
		wayfinders(g, N, P)
		army_orders(g, N, P, now)
		quake(g, N, now)
		if N.diff != "easy" and now >= N.warCheck:
			N.warCheck = now + 15 + g.js_rand.call() * 10
			consider_war(g, N, P)
	step_scouted(g, now)
