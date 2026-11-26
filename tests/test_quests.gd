extends RefCounted
## Quests, sessions 1–2 (docs/QUESTS_PLAN.md): the quests chosen for a map, their hidden dig sites, the Reliquary on
## the build lists, relics going into Reliquaries, scouts carrying the rest, chests (dropped and picked up), and all
## of it surviving a save. Godot only: there is nothing in the web game to compare with.

const SEED := "ember"
const SLOTS := ["moderate", "easy"]


func run() -> Array:
	var errs := []
	var was := Game.QUESTS
	Game.QUESTS = true
	_catalog(errs)
	_pick(errs)
	var g := Game.new_world(SEED, "cormac", SLOTS, "center")
	_map(g, errs)
	_reliquary(g, errs)
	_save(g, errs)
	_off(errs)
	_mason_pages(g, errs)
	_dig(errs)
	_stars(errs)
	_engine(errs)
	_race(errs)
	_armament(errs)
	_gear(errs)
	_beasts(errs)
	_arms(errs)
	_spells(errs)
	_dungeon(errs)
	_ransom(errs)
	_jailbreak(errs)
	_trade(errs)
	Game.QUESTS = was
	return errs


## Every quest's goals and triggers name relics that exist; every relic belongs to a quest (or is a Fallen Star).
func _catalog(errs: Array) -> void:
	var Q: Dictionary = Quests.data().QUESTS
	var I: Dictionary = Quests.data().ITEMS
	if Q.size() != 20 or I.size() != 34:
		errs.append("catalog: %d quests and %d relics, want 20 (19 and Jailbreak) and 34" % [Q.size(), I.size()])
	for id in Q:
		var q: Dictionary = Q[id]
		var goals: Array = q.goals + (q.part2.goals if q.has("part2") else [])
		for x in goals + q.trigger.items.map(func(i): return {"item": i}):
			if not I.has(x.item) and x.item != "_convict":
				errs.append("catalog: %s names a relic %s that doesn't exist" % [id, x.item])
	for id in I:
		if id != "star" and not Q.has(str(I[id].quest)):
			errs.append("catalog: relic %s belongs to no quest (%s)" % [id, I[id].quest])
		if not (str(I[id].rarity) in ["common", "uncommon", "rare", "drop"]):
			errs.append("catalog: relic %s has rarity %s" % [id, I[id].rarity])
	# the race words reach the quests' texts
	var t := str(Q.quarterroyal.text)
	if not Races.words(t, "swamp").contains("Warlocks") or not Races.words(t, "wood").contains("Druids"):
		errs.append("catalog: the Mage's Request doesn't speak the races' words: %s" % Races.words(t, "wood"))


## One quest of each single group and two of the Spell Books and Lost Armaments, the same for the same seed.
func _pick(errs: Array) -> void:
	for s in ["ember", "oak", "river", "moss", "crown"]:
		var p := Quests.pick(s)
		if p != Quests.pick(s):
			errs.append("pick %s: not the same twice" % s)
		var n := {}
		for id in p:
			var gr := str(Quests.quest(id).group)
			gr = "spell|arms" if gr in ["spell", "arms"] else gr
			n[gr] = int(n.get(gr, 0)) + 1
		if p.size() != 6 or n.get("library") != 1 or n.get("war") != 1 or n.get("herb") != 1 or n.get("gear") != 1 or n.get("spell|arms") != 2:
			errs.append("pick %s: %s" % [s, p])


## The chosen quests' relics lie hidden, one to a province, never where nothing may be placed.
func _map(g: Game, errs: Array) -> void:
	if not g.quests_on or g.quest_pick.size() != 6:
		errs.append("map: quests_on %s, %d quests" % [g.quests_on, g.quest_pick.size()])
		return
	var want := 0
	for id in Quests.data().ITEMS:
		var it: Dictionary = Quests.item(id)
		if str(it.quest) in g.quest_pick:
			want += int(it.sites)
	var free: int = g.world.provinces.size() - Quests.dig_ban(g).size()
	if g.digs.size() != mini(want, free):
		errs.append("map: %d dig sites, want %d" % [g.digs.size(), mini(want, free)])
	var ban := Quests.dig_ban(g)
	for p in g.digs:
		var d: Dictionary = g.digs[p]
		if ban.has(p):
			errs.append("map: a dig site at %d, where nothing may be buried" % p)
		if d.shown or d.star or not (str(Quests.item(d.item).quest) in g.quest_pick):
			errs.append("map: dig site %d is %s" % [p, d])
	if g.star_next != 1800.0:
		errs.append("map: the first Fallen Star falls at %s" % g.star_next)
	var g2 := Game.new_world(SEED, "cormac", SLOTS, "center")
	if g2.digs != g.digs or g2.quest_pick != g.quest_pick:
		errs.append("map: the same seed buries relics elsewhere")
	if not g.BUILD_ORDER.has("reliquary") or not g.BUILD_DEFS.has("reliquary"):
		errs.append("map: no Reliquary on the build lists")
	elif g.BUILD_DEFS.reliquary.cost != {"gold": 100, "wood": 100}:
		errs.append("map: the Reliquary costs %s" % g.BUILD_DEFS.reliquary.cost)
	# computer nations' tables are their own: only human seats get the build lists
	if Quests.reliquaries(g, Game.HOST).size() != 0:
		errs.append("map: a Reliquary before one was built")


func _scout(g: Game) -> Dictionary:
	for u in g.units:
		if u.owner == Game.HOST and u.kind == g.WAYFINDER:
			return u
	return {}


func _reliquary(g: Game, errs: Array) -> void:
	var u := _scout(g)
	var cap: int = g.capital
	# no Reliquary: a relic goes into the scout's bag (one), the next into a chest
	if Quests.give(g, Game.HOST, "callum", u, u.prov) != "bag":
		errs.append("carry: the first relic didn't go into the bag")
	if Quests.give(g, Game.HOST, "callum", u, u.prov) != "chest" or g.chests.get(u.prov, []).size() != 1:
		errs.append("carry: a second relic didn't drop into a chest (%s)" % [g.chests])
	g.chests.clear()
	# build one at the capital, as a Mason would
	var m = null
	for v in g.units:
		if v.owner == Game.HOST and v.kind == Game.MASON:
			m = v
	g.stock.gold = 1000
	g.stock.wood = 1000
	var why = g.build_check(cap, "reliquary")
	if why != null or m == null or m.prov != cap:
		errs.append("build: can't build a Reliquary at the capital: %s" % why)
		return
	g.begin_extra(m, "reliquary")
	g.finish_build(m)
	m.build = null
	var R := Quests.reliquaries(g, Game.HOST)
	if R.size() != 1:
		errs.append("build: %d Reliquaries after building one" % R.size())
		return
	if g.build_check(cap, "reliquary") == null:
		errs.append("build: a second Reliquary in the same province")
	# what the scout carries goes in at the next payday
	g.payday(g.t)
	if not Quests.bag_of(u).is_empty() or Quests.count(g, Game.HOST, "callum") != 1:
		errs.append("deposit: bag %s, Reliquary %s" % [Quests.bag_of(u), Quests.items_of(g, Game.HOST)])
	# new relics go straight in, wherever they are found, until the 9 slots are full
	for i in 8:
		if Quests.give(g, Game.HOST, "brune", null, 0) != "reliquary":
			errs.append("deposit: relic %d didn't go in" % (i + 2))
	if Quests.room(g, Game.HOST) != null or Quests.items_of(g, Game.HOST).size() != 9:
		errs.append("deposit: %d relics, room left %s" % [Quests.items_of(g, Game.HOST).size(), Quests.room(g, Game.HOST) != null])
	# a chest where the scout stands: full Reliquary, so the scout takes it
	g.chests[u.prov] = ["coin"]
	Quests.step(g)
	if g.chests.has(u.prov) or Quests.bag_of(u) != ["coin"]:
		errs.append("chest: not picked up (%s, bag %s)" % [g.chests, Quests.bag_of(u)])
	# taking relics out makes room, and the bag empties into it
	if Quests.take(g, Game.HOST, "brune", 2) != 2:
		errs.append("take: didn't take 2")
	g.payday(g.t)
	if not Quests.bag_of(u).is_empty() or Quests.count(g, Game.HOST, "coin") != 1:
		errs.append("deposit after take: bag %s" % [Quests.bag_of(u)])
	# a scout who dies drops what he carries
	Quests.bag(u).append("signet")
	g.dismiss([u])
	if g.chests.get(u.prov, []) != ["signet"]:
		errs.append("lost scout: chests %s" % [g.chests])
	# tearing the Reliquary down spills it into a chest
	var n := Quests.items_of(g, Game.HOST).size()
	g.destroy_extra(cap, R[0].e.slot)
	if g.chests.get(cap, []).size() != n + (1 if u.prov == cap else 0):
		errs.append("torn down: chest at the capital %s, want %d relics" % [g.chests.get(cap), n])
	# build it again for the save test, with something in it and a chest about
	g.begin_extra(m, "reliquary")
	g.finish_build(m)
	m.build = null
	Quests.deposit(g, Game.HOST, "fskull")


func _save(g: Game, errs: Array) -> void:
	var text := g.save_text()
	var g2 := Game.load_text(text)
	if g2 == null:
		errs.append("save: doesn't load")
		return
	if g2.save_text() != text:
		errs.append("save: a loaded game saves differently")
	if g2.digs != g.digs or g2.chests != g.chests or g2.quest_pick != g.quest_pick or not g2.quests_on:
		errs.append("save: quests, digs or chests changed")
	if Quests.items_of(g2, Game.HOST) != Quests.items_of(g, Game.HOST):
		errs.append("save: Reliquary %s, want %s" % [Quests.items_of(g2, Game.HOST), Quests.items_of(g, Game.HOST)])
	if not g2.BUILD_ORDER.has("reliquary"):
		errs.append("save: the Reliquary is gone from the build list after loading")
	# a save from before quests: no quests, no Reliquary
	var d: Dictionary = SaveCodec.from_text(text)
	d.version = 2
	for f in ["quests_on", "quest_pick", "digs", "chests", "star_next", "quest_log"]:
		d.erase(f)
	var g3 := Game.from_save(d)
	if g3 == null or g3.quests_on or g3.BUILD_ORDER.has("reliquary") or not g3.digs.is_empty():
		errs.append("save: a version-2 save has quests")


## Quests off (the web-game tests), and the Practice island: none of it.
func _off(errs: Array) -> void:
	var p := Game.new_practice("moss", "cormac")
	if p.quests_on or not p.digs.is_empty() or p.BUILD_ORDER.has("reliquary"):
		errs.append("practice: has quests")
	Game.QUESTS = false
	var g := Game.new_world(SEED, "cormac", SLOTS, "center")
	if g.quests_on or not g.digs.is_empty() or g.BUILD_ORDER.has("reliquary"):
		errs.append("off: a game with QUESTS off has quests")
	Game.QUESTS = true


## The Mason's card in two pages: the buildings that need no research (and the Reliquary) on the first, with
## Advanced Buildings on cell 12; the ones research unlocks on the second, with Back on the same cell.
func _mason_pages(g: Game, errs: Array) -> void:
	var games := [g, Game.new_practice("moss", "", {}, {}, "swamp"), Game.new_practice("moss", "", {}, {}, "wood")]
	for x in games:
		var p1: Array = x.CMD[Game.MASON]
		var p2: Array = x.CMD[Game.MASON + Races.ADV]
		var b1 := p1.filter(func(c): return str(c.id).begins_with("build:") and c.id != "build:outpost").map(func(c): return str(c.id).substr(6))
		var b2 := p2.filter(func(c): return str(c.id).begins_with("build:")).map(func(c): return str(c.id).substr(6))
		var rc: String = x.race()
		for k in b1:
			if x.BUILD_DEFS[k].get("tech") != null:
				errs.append("mason %s: %s needs research but is on the first page" % [rc, k])
		for k in b2:
			if x.BUILD_DEFS[k].get("tech") == null:
				errs.append("mason %s: %s needs no research but is on Advanced Buildings" % [rc, k])
		for k in x.BUILD_ORDER:
			if not (k in b1) and not (k in b2):
				errs.append("mason %s: %s is on neither page" % [rc, k])
		if not p1.any(func(c): return c.id == "advanced" and int(c.cell) == Races.ADV_CELL) or not p2.any(func(c): return c.id == "basic" and int(c.cell) == Races.ADV_CELL):
			errs.append("mason %s: no Advanced / Back button on cell %d" % [rc, Races.ADV_CELL])
		var cells := {}
		for c in p1:
			if cells.has(int(c.cell)):
				errs.append("mason %s: two buttons on cell %d" % [rc, c.cell])
			cells[int(c.cell)] = true
	if not g.CMD[Game.MASON].any(func(c): return c.id == "build:reliquary"):
		errs.append("mason: the Reliquary isn't on the first page")


## Session 3: a survey uncovers a dig site; the scout digs until the relic comes up; the odds follow its rarity.
func _dig(errs: Array) -> void:
	# the rolls: about 20% / 10% / 5% a cycle
	for rar in [["callum", 0.20], ["lionheart", 0.10], ["brune", 0.05]]:
		var hit := 0
		for n in 4000:
			if Quests.dig_roll("ember", 7, 3, n, Quests.chance_of(rar[0])):
				hit += 1
		if absf(hit / 4000.0 - rar[1]) > 0.02:
			errs.append("dig odds: %s came up %.3f of the time, want %.2f" % [rar[0], hit / 4000.0, rar[1]])
	var g := Game.new_world(SEED, "cormac", SLOTS, "center")
	var u := _scout(g)
	var p: int = u.prov
	g.digs[p] = {"item": "callum", "shown": false, "star": false}
	if Quests.dig_why(g, u) == "":
		errs.append("dig: could dig before the site was uncovered")
	Quests.uncover(g, u)
	if not g.digs[p].shown or Quests.dig_why(g, u) != "":
		errs.append("dig: a survey didn't uncover the site (%s)" % Quests.dig_why(g, u))
	if not g.start_dig(u) or g.unit_status(u) != "digging" or not g.busy(u):
		errs.append("dig: didn't start")
	var cycles := 0
	while g.digs.has(p) and cycles < 300:
		Quests.payday(g)
		cycles += 1
	if g.digs.has(p) or u.get("dig") != null:
		errs.append("dig: nothing after %d cycles" % cycles)
	elif Quests.bag_of(u) != ["callum"]:
		errs.append("dig: the relic went to %s (no Reliquary: the scout should carry it)" % [Quests.bag_of(u)])
	# a second site: moving off stops the digging
	g.digs[p] = {"item": "brune", "shown": true, "star": false}
	g.start_dig(u)
	u.moving = true
	Quests.step(g)
	if u.get("dig") != null:
		errs.append("dig: walking away didn't stop it")
	u.moving = false
	# the same seed digs the same way (each roll has its own stream)
	var a := []
	for k in 2:
		var g2 := Game.new_world(SEED, "cormac", SLOTS, "center")
		var u2 := _scout(g2)
		g2.digs[u2.prov] = {"item": "brune", "shown": true, "star": false}
		g2.start_dig(u2)
		var c2 := 0
		while g2.digs.has(u2.prov) and c2 < 500:
			Quests.payday(g2)
			c2 += 1
		a.append(c2)
	if a[0] != a[1]:
		errs.append("dig: the same game took %d and %d cycles" % a)


## Session 3: Fallen Stars fall when their time comes, never on the unique provinces, then 15–25 minutes later.
func _stars(errs: Array) -> void:
	var g := Game.new_world(SEED, "cormac", SLOTS, "center")
	var U = g.uq()
	for i in 6:
		var due: float = g.star_next
		var n0 := g.digs.size()
		g.t = due - 1.0
		Quests.step(g)
		if g.digs.size() != n0:
			errs.append("stars: one fell early")
		g.t = due
		Quests.step(g)
		var fresh := g.digs.keys().filter(func(q): return g.digs[q].get("star", false) and not g.digs[q].has("_seen"))
		if fresh.size() != 1:
			errs.append("stars: %d new stars at %.0f s" % [fresh.size(), due])
			return
		var p: int = fresh[0]
		g.digs[p]["_seen"] = true
		if U != null and (p in [U.death, U.oasis, U.heart] or g.uq_guards().has(p)):
			errs.append("stars: one fell on a unique province (%d)" % p)
		if not g.digs[p].shown:
			errs.append("stars: a star isn't marked")
		var gap: float = g.star_next - due
		if gap < 900 or gap > 1500:
			errs.append("stars: the next falls %.0f s later" % gap)
		if g.star_fx.is_empty():
			errs.append("stars: no shooting star for the view")
	if g.stars_fallen != 6:
		errs.append("stars: %d fallen, want 6" % g.stars_fallen)


## A Reliquary at nation o's capital, as if just built.
func _reliq(g: Game, o: int) -> Dictionary:
	var cap: int = g.seats[o].capital
	var e := {"type": "reliquary", "slot": 40 + o, "born": 0.0}
	if not g.extras.has(cap):
		g.extras[cap] = []
	g.extras[cap].append(e)
	return e


## Session 4: a relic in the Reliquary starts its quest; filling it finishes it, takes its relics and pays for good.
func _engine(errs: Array) -> void:
	var g := Game.new_world(SEED, "cormac", SLOTS, "center")
	g.quest_pick = ["callum", "quarterroyal", "freakarmor"]
	_reliq(g, Game.HOST)
	var said := []
	g.on_dialog = func(title, _text, _ch, _f): said.append(title)
	Quests.deposit(g, Game.HOST, "callum")
	if g.quest_log.get("callum", {}).get("state") != "active" or said.is_empty() or not str(said[0]).begins_with("New quest"):
		errs.append("engine: one Lawbook didn't start its quest (%s, %s)" % [g.quest_log, said])
	var before := g.tech_rate("gov")
	Quests.deposit(g, Game.HOST, "callum")
	Quests.deposit(g, Game.HOST, "coin")   # (another quest's relic stays)
	if Quests.goal_text(g, Game.HOST, "callum") != "Find copies of Lord Callum's Lawbook 2/3":
		errs.append("engine: goal text '%s'" % Quests.goal_text(g, Game.HOST, "callum"))
	Quests.deposit(g, Game.HOST, "callum")
	if g.quest_log.callum.state != "done":
		errs.append("engine: three Lawbooks didn't finish it")
	if Quests.count(g, Game.HOST, "callum") != 0 or Quests.count(g, Game.HOST, "coin") != 1:
		errs.append("engine: relics left %s" % [Quests.items_of(g, Game.HOST)])
	if g.tech_rate("gov") != before + 6 or g.quest_rate.get("gov") != 6:
		errs.append("engine: Government research %d, want %d" % [g.tech_rate("gov"), before + 6])
	# extra copies found later start nothing again
	Quests.deposit(g, Game.HOST, "callum")
	if g.quest_log.callum.state != "done":
		errs.append("engine: a finished quest started again")
	# a Mage's Request waits for a Mage Tower
	Quests.deposit(g, Game.HOST, "quarterroyal")
	if g.quest_log.has("quarterroyal"):
		errs.append("engine: the Mage's Request started without a Mage Tower")
	g.extras[g.capital].append({"type": "magetower", "slot": 39, "born": 0.0})
	Quests.payday(g)
	if g.quest_log.get("quarterroyal", {}).get("state") != "active":
		errs.append("engine: the Mage's Request didn't start once a Mage Tower stood")
	# a Battlegear quest needs a Fallen Star too, and unlocks its armor
	var e2 := {"type": "reliquary", "slot": 38, "born": 0.0}   # (a second Reliquary: the first is nearly full)
	g.extras[g.capital].append(e2)
	for id in ["fbones", "fbones", "fbones", "fbones", "fribs", "fskull"]:
		Quests.deposit(g, Game.HOST, id)
	if g.quest_log.freakarmor.state != "active":
		errs.append("engine: the Freak Man finished without a Fallen Star")
	Quests.deposit(g, Game.HOST, "star")
	if g.quest_log.freakarmor.state != "done" or not g.quest_unlocks.has("armor:bone_regalia"):
		errs.append("engine: the Freak Man's Skeleton: %s, unlocks %s" % [g.quest_log.freakarmor, g.quest_unlocks])
	# the log: open quests first, every text, the race's words
	var ids := QuestLogWindow.entries(g)
	if ids[0] != "quarterroyal":
		errs.append("log: order %s" % [ids])
	if not QuestLogWindow.body_text(g, "callum").contains("+6 Government Research"):
		errs.append("log: the finished quest's text: %s" % QuestLogWindow.body_text(g, "callum"))
	# saved and loaded, the quests and their rewards come back
	var g2 := Game.load_text(g.save_text())
	if g2.quest_log != g.quest_log or g2.tech_rate("gov") != g.tech_rate("gov") or g2.quest_unlocks != g.quest_unlocks:
		errs.append("engine: quests changed in a save")


const HUMANS := {0: {"nation": {"name": "Bog Kings", "emblem": "skull", "color": 3}, "race": "swamp"}}

## Session 4: two players with the same quest; the first to finish wins it, the other fails. The words are each race's.
func _race(errs: Array) -> void:
	var g := Game.new_world(SEED, "cormac", ["human", "moderate"], "center", {}, {}, {"name": "Hosts"}, "realm", [], HUMANS.duplicate(true))
	var other: int = g.seat_ids().filter(func(o): return o != Game.HOST)[0]
	g.quest_pick = ["lionheart"]
	_reliq(g, Game.HOST)
	_reliq(g, other)
	Quests.deposit(g, Game.HOST, "lionheart")
	Quests.deposit(g, other, "lionheart")
	if Quests.log_of(g, other).get("lionheart", {}).get("state") != "active" or g.quest_log.get("lionheart", {}).get("state") != "active":
		errs.append("race: both should have the quest")
	for i in 3:
		Quests.deposit(g, other, "lionheart")
	if Quests.log_of(g, other).lionheart.state != "done" or g.quest_log.lionheart.state != "failed" or int(g.quest_log.lionheart.by) != other:
		errs.append("race: %s / %s" % [Quests.log_of(g, other).lionheart, g.quest_log.lionheart])
	if g.in_seat(other, func(): return g.tech_rate("gov")) == g.tech_rate("gov") + 8:
		pass
	if int(g.seats[other].quest_rate.get("gov", 0)) != 8 or int(g.quest_rate.get("gov", 0)) != 0:
		errs.append("race: the reward went to the wrong nation")
	# the Swampling reads Warlocks
	g.quest_pick = ["peacock"]
	if not Quests.words(g, other, str(Quests.quest("peacock").text)).contains("Warlocks"):
		errs.append("race: the Swampling's quest doesn't say Warlocks")


## Session 4: a Lost Armament's map, then its prize dug up in your own land (a site only you see), then the star.
func _armament(errs: Array) -> void:
	var g := Game.new_world(SEED, "cormac", SLOTS, "center")
	g.quest_pick = ["cutlass"]
	_reliq(g, Game.HOST)
	for i in 4:
		Quests.deposit(g, Game.HOST, "jmap")
	var st: Dictionary = g.quest_log.get("cutlass", {})
	if st.get("state") != "active" or int(st.get("part", 0)) != 2 or Quests.count(g, Game.HOST, "jmap") != 0:
		errs.append("armament: part 2 didn't start (%s)" % [st])
		return
	var p := int(st.get("site", -1))
	if p < 0 or g.nation_of(p) != Game.HOST or g.digs.get(p, {}).get("item") != "cutlass":
		errs.append("armament: the prize's site %d is %s" % [p, g.digs.get(p)])
		return
	if not Quests.dig_seen(g, p) and g.visible.has(p):
		errs.append("armament: the owner can't see the prize's site")
	Quests.deposit(g, Game.HOST, "star")
	if g.quest_log.cutlass.state != "active":
		errs.append("armament: finished without the Cutlass")
	g.digs.erase(p)
	Quests.deposit(g, Game.HOST, "cutlass")
	if g.quest_log.cutlass.state != "done" or not g.quest_unlocks.has("weapon:cutlass") or Quests.count(g, Game.HOST, "star") != 0:
		errs.append("armament: %s, unlocks %s, stars left %d" % [g.quest_log.cutlass, g.quest_unlocks, Quests.count(g, Game.HOST, "star")])


## Session 5: the Battlegear armors (Tier V of every family), hidden until their quest is done; armor 10% cheaper;
## the Bone Regalia's theft; Siegebreaker's soldiers found.
func _gear(errs: Array) -> void:
	var A: Dictionary = GameData.c("ARMORS")
	for fam in Quests.GEAR_FAMILY:
		var x = A.get(fam + "5")
		if x == null or int(x.level) != 5 or x.get("quest") == null:
			errs.append("gear: no %s5" % fam)
			continue
		if x.cost != A[fam + "4"].cost or float(x.armor) <= float(A[fam + "4"].armor):
			errs.append("gear: %s5 costs %s, armor %s" % [fam, x.cost, x.armor])
	if int(Game.armor_cost(A.chain4).gold) != (72 if Game.RULES19 else 80):
		errs.append("gear: Chain IV costs %s after the 10%% cut" % Game.armor_cost(A.chain4))
	var g := Game.new_world(SEED, "cormac", SLOTS, "center")
	if g.gear_why("armor", "plate5") == null:
		errs.append("gear: Siegebreaker Runeplate can be picked before its quest")
	g.quest_unlocks.append("armor:siegebreaker")
	g.quest_unlocks.append("armor:bone_regalia")
	if g.gear_why("armor", "plate5") != null:
		errs.append("gear: Siegebreaker Runeplate locked after its quest: %s" % g.gear_why("armor", "plate5"))
	var sb: Dictionary = g.save_design({"name": "Breaker", "type": "inf", "weapon": "shortsword", "shield": null, "armor": "plate5", "horse": null, "race": "realm"})
	var st: Dictionary = g.DSTATS[sb.id]
	var p4: Dictionary = g.design_stats({"type": "inf", "weapon": "shortsword", "shield": null, "armor": "plate4", "horse": null, "race": "realm"})
	if st.hp != p4.hp - Game.armor_hp(A.plate4) + 80 or st.speed <= p4.speed or st.get("quest_armor") != "armor:siegebreaker":
		errs.append("gear: Siegebreaker soldier hp %s speed %s (plate IV: %s, %s)" % [st.hp, st.speed, p4.hp, p4.speed])
	var bone: Dictionary = g.save_design({"name": "Bones", "type": "inf", "weapon": "shortsword", "shield": null, "armor": "chain5", "horse": null, "race": "realm"})
	# a battle: the Bone Regalia's wearers take the enemy's Hardened Skin and Cursed Weapons
	var b := {"prov": g.capital}
	var w := {"kind": "army", "owner": Game.HOST, "troops": {bone.id: 5}, "battle": b, "name": "Bones", "skin": 0.0, "curse": 0.0}
	var foe := {"kind": "army", "owner": Game.RAIDERS, "troops": {"d-sword": 5}, "battle": b, "name": "Gang", "skin": 0.1, "curse": 0.05}
	g.units.append(w)
	g.units.append(foe)
	Quests.steal_buffs(g, b)
	if w.skin != 0.1 or w.curse != 0.05 or foe.skin != 0.0 or foe.curse != 0.0:
		errs.append("gear: the Bone Regalia didn't steal (%s / %s)" % [[w.skin, w.curse], [foe.skin, foe.curse]])
	var br := {"kind": "army", "owner": Game.HOST, "troops": {sb.id: 10}}
	if not Quests.wears(g, br, "armor:siegebreaker") or Quests.wears(g, foe, "armor:siegebreaker"):
		errs.append("gear: Siegebreaker wearers not found")


## Session 6: with Hides of Mythical Beasts on the map, 3 + 3 + 2 + 1 primal beasts on their terrain, of the
## right strength; a slain beast's hide goes to the victor's Reliquary, else a chest where it fell.
func _beasts(errs: Array) -> void:
	var g := Game.new_world(SEED, "cormac", SLOTS, "center")
	g.quest_pick = ["beastleather"]
	Quests.spawn_beasts(g)
	var want := {"knuckledragger": [3, 2000], "ursacub": [3, 2000], "dunestalker": [2, 3500], "bogwalker": [1, 4000]}
	for k in want:
		var list: Array = g.units.filter(func(u): return u.get("monster") == k)
		if list.size() != want[k][0]:
			errs.append("beasts: %d %s, want %d" % [list.size(), k, want[k][0]])
			continue
		var B: Dictionary = Quests.BEASTS[k]
		for a in list:
			var t: String = g.world.provinces[a.prov].terrain
			var v: String = g.variant[a.prov] if a.prov < g.variant.size() else ""
			if v != B.variant and t != B.terrain:
				errs.append("beasts: a %s on %s / %s" % [k, t, v])
			var pw := int(round(g.raw_strength([a]) * 10))
			if pw != want[k][1]:
				errs.append("beasts: a %s has power %d, want %d" % [k, pw, want[k][1]])
	var a: Dictionary = g.units.filter(func(u): return u.get("monster") == "dunestalker")[0]
	var b := {"prov": a.prov, "start": {Game.HOST: 10, Game.RAIDERS: 1}}
	Quests.beast_fell(g, a, b)
	if g.chests.get(a.prov, []) != ["phide"]:
		errs.append("beasts: no Reliquary, but the hide isn't in a chest (%s)" % [g.chests])
	_reliq(g, Game.HOST)
	Quests.beast_fell(g, a, b)
	if Quests.count(g, Game.HOST, "phide") != 1:
		errs.append("beasts: the hide didn't go to the Reliquary")


## Session 7: the Lost Armaments' gear, locked until its quest; the Shield of Sham for every race and its first blow;
## the Triune Staff's mana, regeneration and casting speed.
func _arms(errs: Array) -> void:
	var g := Game.new_world(SEED, "cormac", SLOTS, "center")
	if g.gear_why("weapon", "cutlass") == null or g.mage_gear_why("weapon", "triune") == null:
		errs.append("arms: quest gear usable before its quest")
	g.quest_unlocks.append_array(["weapon:cutlass", "weapon:greedmaul", "shield:sham", "staff:triune"])
	if g.gear_why("weapon", "cutlass") != null or g.gear_why("shield", "sham") != null or g.mage_gear_why("weapon", "triune") != null:
		errs.append("arms: quest gear still locked after its quest")
	var d: Dictionary = g.save_design({"name": "Jag", "type": "inf", "weapon": "cutlass", "shield": "sham", "armor": "leather1", "horse": null, "race": "realm"})
	var st: Dictionary = g.DSTATS[d.id]
	if st.atk != 25 or not st.get("sham", false) or st.shieldArmor != 10:
		errs.append("arms: Cutlass and Sham soldier %s" % [[st.atk, st.get("sham"), st.shieldArmor]])
	var mg: Dictionary = g.design_stats({"type": "inf", "weapon": "greedmaul", "shield": "sham", "armor": "leather1", "horse": null, "race": "realm"})
	if mg.atk != 35 or mg.get("sham", false):
		errs.append("arms: the Maul of Greed takes no shield (%s)" % [mg])
	# the Swamplings and Woodlings carry the Shield of Sham too, but not with two weapons or a two-handed grip
	var sw: Dictionary = g.design_stats({"type": "inf", "weapon": "handaxe", "off": "handaxe", "shield": "sham", "armor": "stag1", "horse": null, "race": "swamp"})
	if not sw.get("sham", false) or sw.atk != 6:
		errs.append("arms: a Swampling with the Shield of Sham fights with two weapons (%s)" % [[sw.atk, sw.get("sham")]])
	var wd: Dictionary = g.design_stats({"type": "inf", "weapon": "dirk", "shield": "sham", "armor": "spirit1", "horse": null, "race": "wood", "two": true})
	if not wd.get("sham", false) or wd.get("two", false):
		errs.append("arms: a Woodling with the Shield of Sham two-hands (%s)" % [[wd.get("sham"), wd.get("two")]])
	# the first blow against an all-Sham front line comes to nothing, once a battle
	var b := {"prov": g.capital, "start": {}}
	var a := {"kind": "army", "owner": Game.HOST, "troops": {d.id: 6}, "name": "Shields", "wounds": 0.0}
	if not Quests.sham_blocks(g, b, [a]) or Quests.sham_blocks(g, b, [a]):
		errs.append("arms: the Shield of Sham should turn aside the first blow, and only the first")
	var mixed := {"kind": "army", "owner": Game.HOST, "troops": {d.id: 1, "d-sword": 1}, "name": "Mixed", "wounds": 0.0}
	if Quests.sham_blocks(g, {"prov": g.capital}, [mixed]):
		errs.append("arms: a front line not all carrying the Shield of Sham was shielded")
	# the Triune Staff
	var cap0 := g.mana_cap()
	var reg0 := g.mana_regen(Game.HOST)
	g.set_mage_gear({"weapon": "triune"})
	if g.mana_cap() != cap0 + 100 or g.mana_regen(Game.HOST) != reg0 + 10 or Game.STAVE_CAST.get("triune") != 0.8:
		errs.append("arms: Triune Staff mana %d (was %d), regen %d (was %d)" % [g.mana_cap(), cap0, g.mana_regen(Game.HOST), reg0])


## Session 8: Wall of Flame (a border closed for 60 s to all but the caster's nation, unbreakable, one at a time)
## and Time Warp (one building works twice as well).
func _spells(errs: Array) -> void:
	var g := Game.new_world(SEED, "cormac", SLOTS, "center")
	var cap: int = g.capital
	var c: Dictionary = g.new_army(cap, {Game.MAGE: 1})
	c.mana = 300.0
	var q: int = g.open_nbr[cap][0].q
	if Quests.flamewall_why(g, c, q) == "":
		errs.append("spells: Wall of Flame before its quest")
	g.quest_unlocks.append_array(["spell:flamewall", "spell:timewarp"])
	if not g.cast_flamewall(c, q):
		errs.append("spells: Wall of Flame failed: %s" % Quests.flamewall_why(g, c, q))
		return
	if g.open_between(cap, q) or g.flame_walls.is_empty() or c.mana != 200.0:
		errs.append("spells: the border is still open (%s), mana %s" % [g.flame_walls, c.mana])
	var i: int = g.flame_walls.keys()[0]
	if g.damage_wall(i, 10000.0) or not g.walls.has(i):
		errs.append("spells: the Wall of Flame was broken")
	if Quests.flamewall_why(g, c, g.open_nbr[cap][0].q) != "Ready in 10 s":
		errs.append("spells: no cooldown: '%s'" % Quests.flamewall_why(g, c, g.open_nbr[cap][0].q))
	# a second wall puts out the first
	g.t += 11.0
	var q2: int = g.open_nbr[cap][0].q
	g.cast_flamewall(c, q2)
	if not g.open_between(cap, q) or g.flame_walls.values().any(func(f): return false) or g.flame_walls.size() < 1:
		errs.append("spells: the first Wall of Flame didn't go out")
	g.t += 61.0
	Quests.step(g)
	if not g.flame_walls.is_empty() or not g.open_between(cap, q2):
		errs.append("spells: the Wall of Flame didn't burn out")
	# Time Warp on a Farm: its food twice
	var farm := {"type": "farm", "slot": 5, "born": 0.0}
	g.extras[cap].append(farm)
	g.compute_income()
	var food0: int = g.income.food
	g.t += 11.0
	if not g.cast_timewarp(c, 5):
		errs.append("spells: Time Warp failed: %s" % Quests.spell_why(g, c, "timewarp"))
	var per: int = Ai.crop_gives(Ai.crop_of(farm), g.gives_of("farm")).get("food", 0)
	if g.income.food != food0 + per:
		errs.append("spells: Time Warp's Farm: food %d, want %d" % [g.income.food, food0 + per])
	# on a Barracks: soldiers in half the time; on a Forge: its research twice
	var bar := {"type": "barracks", "slot": 4, "born": 0.0}
	g.extras[cap].append(bar)
	g.t += 11.0
	c.mana = 300.0
	g.cast_timewarp(c, 4)
	if Quests.warp_train_mul(g, "barracks:%d" % cap) != 0.5 or Quests.warp_train_mul(g, "magetower:%d" % cap) != 1.0:
		errs.append("spells: Time Warp's Barracks doesn't train faster")
	if g.income.food != food0:
		errs.append("spells: the Farm stayed warped after warping the Barracks")


func _mp() -> Game:
	return Game.new_world(SEED, "cormac", ["human", "moderate"], "center", {}, {}, {"name": "Hosts"}, "realm", [], HUMANS.duplicate(true))


## Session 9: Dungeons in multiplayer only; 3 cells each; a prisoner with no cell is Detained and escapes after 3 cycles.
func _dungeon(errs: Array) -> void:
	var solo := Game.new_world(SEED, "cormac", SLOTS, "center")
	if solo.BUILD_ORDER.has("dungeon"):
		errs.append("dungeon: on the build list in single player")
	var g := _mp()
	if not g.BUILD_ORDER.has("dungeon") or not g.CMD[Game.MASON].any(func(c): return c.id == "build:dungeon"):
		errs.append("dungeon: not on the build lists in multiplayer")
	var other: int = g.seat_ids().filter(func(o): return o != Game.HOST)[0]
	var said := []
	g.on_dialog = func(title, _t, _c, _f): said.append(title)
	var pr := Dungeons.make(g, "envoy", other)
	if Dungeons.jail(g, Game.HOST, pr) != "detained" or g.detained.size() != 1:
		errs.append("dungeon: no cell, but not Detained")
	for i in 3:
		Dungeons.payday(g)
	if not g.detained.is_empty() or not said.has("Prisoner Escape!"):
		errs.append("dungeon: the Detained prisoner didn't escape after 3 cycles (%s)" % [said])
	var e := {"type": "dungeon", "slot": 41, "born": 0.0}
	g.extras[g.capital].append(e)
	for i in 4:
		Dungeons.jail(g, Game.HOST, Dungeons.make(g, "convict", 0))
	if Dungeons.held_in(e).size() != 3 or g.detained.size() != 1:
		errs.append("dungeon: %d in the cells, %d Detained (want 3, 1)" % [Dungeons.held_in(e).size(), g.detained.size()])
	var id: int = Dungeons.held_in(e)[0].id
	if Dungeons.holder(g, id) != Game.HOST or Dungeons.release(g, Game.HOST, id) == null:
		errs.append("dungeon: can't find or release a prisoner")
	Dungeons.payday(g)
	if not g.detained.is_empty() or Dungeons.held_in(e).size() != 3:
		errs.append("dungeon: the Detained prisoner didn't take the free cell")
	g.destroy_extra(g.capital, 41)
	if g.detained.size() != 3:
		errs.append("dungeon: a torn-down Dungeon's prisoners aren't Detained (%d)" % g.detained.size())


## Session 10: the ransom events: X ransoms, Y pays; X ransoms, Y lets 40 s pass (war), and the ransom war's endings;
## an ignored envoy; Raid Reliquary and Free Prisoners at 50% warscore.
func _ransom(errs: Array) -> void:
	var g := _mp()
	var x: int = Game.HOST
	var y: int = g.seat_ids().filter(func(o): return o != Game.HOST)[0]
	var said := []
	g.on_dialog = func(title, _t, _c, _f): said.append(title)
	g.extras[g.capital].append({"type": "dungeon", "slot": 41, "born": 0.0})
	# a lady, ransomed for 250 and paid
	var r: Dictionary = Dungeons.start(g, "lady", x, y)
	g.in_seat(x, func(): g.answer_ransom(r.id, "r250"))
	if r.stage != "y" or Dungeons.prisoners_of(g, x).size() != 1:
		errs.append("ransom: X's ransom didn't reach Y (%s)" % r.stage)
	g.seats[y].stock.gold = 1000
	var xg: int = g.seats[x].stock.gold
	g.in_seat(y, func(): g.answer_ransom(r.id, "pay"))
	if r.stage != "done" or g.seats[y].stock.gold != 750 or g.seats[x].stock.gold != xg + 250 or not Dungeons.prisoners_of(g, x).is_empty():
		errs.append("ransom: paying didn't settle it (%s, gold %d / %d)" % [r.stage, g.seats[y].stock.gold, g.seats[x].stock.gold])
	# an envoy: Y doesn't answer within 40 s: a ransom war, where only the ransom endings make peace
	var r2: Dictionary = Dungeons.start(g, "envoy", x, y)
	g.in_seat(x, func(): g.answer_ransom(r2.id, "r100"))
	g.t += 41.0
	Dungeons.step(g)
	var w = g.war_between(x, y)
	if r2.stage != "war" or w == null or w.get("ransom") != r2.id:
		errs.append("ransom: no war after 40 s without an answer (%s)" % r2.stage)
		return
	if g.in_seat(y, func(): return g.peace_check(w, "white")) == "":
		errs.append("ransom: a white peace in a ransom war")
	if g.in_seat(y, func(): return g.peace_check(w, "freeprisoner")) == "":
		errs.append("ransom: freed at 0 warscore")
	g.add_score(w, y, 60.0)
	if g.in_seat(y, func(): return g.peace_check(w, "freeprisoner")) != "":
		errs.append("ransom: Y can't free the prisoner at +60: %s" % g.in_seat(y, func(): return g.peace_check(w, "freeprisoner")))
	var yg: int = g.seats[y].stock.gold
	g.in_seat(y, func(): g.make_peace(w, y, {"kind": "freeprisoner"}))
	if g.war_between(x, y) != null or r2.stage != "done" or g.seats[y].stock.gold != yg + 1000 or not Dungeons.prisoners_of(g, x).is_empty():
		errs.append("ransom: freeing the prisoner didn't end it (%s, gold %d)" % [r2.stage, g.seats[y].stock.gold - yg])
	# an ignored general: X gains 200 Military research once, Y loses 20 a cycle for 10 cycles
	g.quest_events.erase("envoy_next")
	var r3: Dictionary = Dungeons.start(g, "general", x, y)
	g.in_seat(x, func(): g.answer_ransom(r3.id, "r50"))
	var bank0: float = g.seats[x].tech.mil.bank + g.seats[x].tech.mil.prog
	g.in_seat(y, func(): g.answer_ransom(r3.id, "ignore"))
	if g.seats[y].research_pen.size() != 1 or int(g.seats[y].research_pen[0].n) != 20:
		errs.append("ransom: no research cut for ignoring the general")
	for i in 10:
		Quests.payday(g)
	if not g.seats[y].research_pen.is_empty():
		errs.append("ransom: the research cut outlasted 10 cycles")
	# Raid Reliquary and Free Prisoners in an ordinary war
	_reliq(g, y)
	for id in ["callum", "coin", "signet"]:
		Quests.deposit(g, y, id)
	Dungeons.jail(g, y, Dungeons.make(g, "convict", 0))
	g.extras[g.seats[y].capital].append({"type": "dungeon", "slot": 42, "born": 0.0})
	Dungeons.payday(g)
	var w2 = g.new_war(x, y, null)
	g.add_score(w2, x, 60.0)
	var n0: int = Quests.items_of(g, y).size()
	g.make_peace(w2, x, {"kind": "raid"})
	var taken: int = n0 - Quests.items_of(g, y).size()
	if taken < 1 or taken > 3 or g.war_between(x, y) != null:
		errs.append("ransom: Raid Reliquary took %d relics" % taken)
	var w3 = g.new_war(x, y, null)
	g.add_score(w3, x, 60.0)
	g.make_peace(w3, x, {"kind": "freeall"})
	if not Dungeons.prisoners_of(g, y).is_empty() or Dungeons.prisoners_of(g, x).filter(func(p): return p.kind == "convict").size() != 1:
		errs.append("ransom: Free Prisoners didn't move the convict")


## Session 11: Jailbreak: 8 Convict Gangs; beaten ones fill the Dungeons; 8/8 and the choice.
func _jailbreak(errs: Array) -> void:
	var g := _mp()
	var x: int = Game.HOST
	var y: int = g.seat_ids().filter(func(o): return o != Game.HOST)[0]
	for s in [40, 41, 42]:
		g.extras[g.capital].append({"type": "dungeon", "slot": s, "born": 0.0})
	Dungeons.jailbreak(g, x)
	var gangs: Array = g.units.filter(func(u): return u.get("convict", false))
	if gangs.size() != 8 or gangs.any(func(a): return a.troops != {Dungeons.CONVICT: 4}):
		errs.append("jail: %d Convict Gangs" % gangs.size())
		return
	if g.quest_log.get("jailbreak", {}).get("state") != "active" or Quests.goal_text(g, x, "jailbreak") != "Recover Criminals 0/8":
		errs.append("jail: no quest (%s)" % Quests.goal_text(g, x, "jailbreak"))
	# another player beats one: it's theirs (no cell: it escapes to a new gang)
	Dungeons.convict_beaten(g, gangs[0], {"prov": gangs[0].prov, "start": {y: 5, Game.RAIDERS: 4}})
	if g.units.filter(func(u): return u.get("convict", false)).size() != 9:
		errs.append("jail: a convict with no cell to go to didn't form a new gang")
	for i in 7:
		Dungeons.convict_beaten(g, gangs[i + 1], {"prov": gangs[i + 1].prov, "start": {x: 5, Game.RAIDERS: 4}})
	if Dungeons.recovered(g, x) != 7 or g.quest_events.jail.state != "active":
		errs.append("jail: %d recovered after 7" % Dungeons.recovered(g, x))
	Dungeons.convict_beaten(g, gangs[0], {"prov": gangs[0].prov, "start": {x: 5, Game.RAIDERS: 4}})
	if g.quest_events.jail.state != "deciding":
		errs.append("jail: 8/8 but no choice (%s)" % g.quest_events.jail.state)
	var n0: int = g.units.filter(func(u): return u.kind == "army" and u.owner == x).size()
	g.in_seat(x, func(): g.answer_jailbreak("pardon"))
	var arm: Array = g.units.filter(func(u): return u.kind == "army" and u.owner == x and u.troops.get(Dungeons.CONVICT, 0) == 8)
	if arm.size() != 1 or Dungeons.recovered(g, x) != 0 or g.quest_log.jailbreak.state != "done":
		errs.append("jail: pardon didn't give 8 Convicts (%d armies)" % arm.size())
	var g2 := Game.load_text(g.save_text())
	if g2 == null or not g2.DSTATS.has(Dungeons.CONVICT):
		errs.append("jail: the Convicts' soldier is gone after loading")


## Session 12: Trade between players carries relics and prisoners (and still resources), and starts their quests.
func _trade(errs: Array) -> void:
	var g := _mp()
	var x: int = Game.HOST
	var y: int = g.seat_ids().filter(func(o): return o != Game.HOST)[0]
	g.met[y] = true
	g.seats[y].met[x] = true
	g.quest_pick = ["callum"]
	_reliq(g, x)
	_reliq(g, y)
	g.extras[g.seats[y].capital].append({"type": "dungeon", "slot": 43, "born": 0.0})
	Quests.deposit(g, x, "coin")
	Quests.deposit(g, y, "callum")
	var pr := Dungeons.make(g, "convict", 0)
	Dungeons.jail(g, y, pr)
	g.extras[g.capital].append({"type": "dungeon", "slot": 44, "born": 0.0})
	g.stock.gold = 500
	if not g.offer_barter(y, {"gold": 100}, {}, {"gi": ["coin"], "wi": ["callum"], "wp": [pr.id]}):
		errs.append("trade: the offer wasn't sent")
		return
	var reqs: Array = g.in_seat(y, func(): return g.dipl_state().reqs)
	if reqs.is_empty():
		errs.append("trade: no request reached them")
		return
	var rq: Dictionary = reqs[-1]
	g.in_seat(y, func(): g.answer_request(rq, true))
	if Quests.count(g, x, "callum") != 1 or Quests.count(g, y, "coin") != 1 or Dungeons.holder(g, pr.id) != x:
		errs.append("trade: relics %s / %s, prisoner with %d" % [Quests.items_of(g, x), Quests.items_of(g, y), Dungeons.holder(g, pr.id)])
	if g.quest_log.get("callum", {}).get("state") != "active":
		errs.append("trade: a traded Lawbook didn't start its quest")
	if g.offer_barter(y, {}, {}, {"wi": ["brune"]}):
		errs.append("trade: asked for a relic they don't keep")
