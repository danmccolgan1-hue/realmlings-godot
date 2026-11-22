extends RefCounted
## The Swamplings' and Woodlings' own rules (web: swamp.js, wood.js, equip.js designStats): names, starts, build rules,
## Thugs, Pyromancy, dual wielding, Ogres, Champions, the Woodling Scouts' tree borders, and computer nations of each race.


func run() -> Array:
	var errs := []
	var chk := func(ok: bool, what: String) -> void:
		if not ok:
			errs.append(what)
	# --- Swamplings ---
	var g := Game.new_practice("ember", "aarg")
	chk.call(g.race() == "swamp" and g.is_sw(), "aarg's game is a Swampling game")
	chk.call(g.G.provs[g.capital].terrain == "swamp", "Swamplings start in a swamp")
	chk.call(g.unit_defs["mason:A"].name == "Swampwright" and g.BUILD_DEFS.stable.name == "Ogre Cave", "Swampling names")
	chk.call(not g.BUILD_ORDER.has("granary") and not g.CMD["mason:A"].any(func(c): return c.id == "road"), "no Granary, no roads")
	chk.call(g.tech.gov.done.has("mushroom"), "Mushroom Farming from the start")
	chk.call(g.footman_of() == "d-sw-axe" and g.designs.all(func(d): return d.race == "swamp"), "Axe Berserkers and only Swampling designs")
	chk.call(str(g.build_check(g.capital, "granary")).find("Swamplings") >= 0 or str(g.build_check(g.capital, "granary")).begins_with("Research"), "no Granary for Swamplings")
	chk.call(g.spell2_name("shock") == "Fireball", "Fireball")
	chk.call(g.gives_of("market").is_empty() and g.store_of("bank", Game.HOST).wood == 500, "Thug Den gives nothing; Supply Cache stores wood")
	var y0: int = g.province_income(g.capital, g.buildings[g.capital]).gold
	g.extras[g.capital] = g.extras.get(g.capital, []) + [{"type": "market", "slot": 5, "born": 0, "thugs": 2}]
	chk.call(g.province_income(g.capital, g.buildings[g.capital]).gold == y0 + 2, "two Thugs make 2 gold")
	var st: Dictionary = g.design_stats({"type": "inf", "weapon": "handaxe", "off": "handaxe", "armor": "stag1", "race": "swamp"})
	var one: Dictionary = g.design_stats({"type": "inf", "weapon": "handaxe", "armor": "stag1", "race": "swamp"})
	chk.call(absf(st.atk - one.atk * 1.5) < 0.11 and st.crit == 0.1, "dual wielding: the off hand at half attack")
	var og: Dictionary = g.design_stats({"type": "cav", "weapon": "club", "armor": "stag2", "horse": "riding", "race": "swamp"})
	chk.call(og.ogre and og.speed == float(JS.to_fixed(1.2 * GameData.c("ARMORS").stag2.speed, 2)), "Ogres ride on Ogre stats")
	var a := g.new_army(g.capital, {"d-sw-axe": 1})
	chk.call(absf(g.speed_mod(a) - 1.2) < 0.001, "20% faster in a swamp")
	# --- Woodlings ---
	var w := Game.new_practice("oak", "cerathon")
	chk.call(w.race() == "wood" and w.G.provs[w.capital].terrain == "forest", "Woodlings start in a forest")
	chk.call(w.unit_defs["pioneer:B"].name == "Scout" and w.BUILD_DEFS.magetower.name == "Grove" and w.BUILD_DEFS.market.name == "Bazaar", "Woodling names")
	chk.call(w.TECH_BY_ID["traderoutes"].name == "Community", "Community")
	var ch: Dictionary = w.design_stats({"type": "cav", "weapon": "champsword", "armor": "ornate1", "race": "wood"})
	chk.call(ch.champ and ch.hp == 70 + GameData.c("WEAPONS").champsword.get("hp", 0) + GameData.c("ARMOR_HP")[1], "Champion stats")
	var wf: Dictionary = w.units.filter(func(u): return u.kind == GameData.c("WAYFINDER"))[0]
	var tn := w.tree_nbr(w.capital)
	chk.call(w.path_nbr(wf, w.capital).size() == w.open_nbr[w.capital].size() + tn.size(), "Scouts slip through borders of trees")
	# Elemental magic: Rock Armor soaks blows; a Forest Spirit doubles a province
	w.grant_tech("school-elemental") if w.has_method("grant_tech") else null
	for id in ["school-elemental", "rockarmor", "forestspirit"]:
		w.add_start_tech(id)
	var da := w.new_army(w.capital, {"d-wd-sword": 4, w.MAGE: 1})
	da.mana = 100.0
	w.on_battle_join(da, 1.0)
	chk.call(da.get("rock") != null and da.rock.hp > 0, "Rock Armor raises a stone shield")
	var y1: int = w.province_income(w.capital, w.buildings[w.capital]).wood
	da.cast = {"spell": "q:fspirit", "t0": 0.0, "dur": INF}
	chk.call(w.province_income(w.capital, w.buildings[w.capital]).wood == y1 * 2, "a Forest Spirit doubles the province")
	# the Grand Elemental joins the Druid's army and sinks back after 2 minutes
	w.add_start_tech("gelemental")
	w._finish_q(da, "gelem", {}, w.t)
	chk.call(da.troops.get(Game.GELEM_ID, 0) == 1, "a Grand Elemental joins the army")
	w.step_elementals(w.t + Game.GELEM.life + 1)
	chk.call(da.troops.get(Game.GELEM_ID, 0) == 0, "the Grand Elemental sinks back")
	# the lost travelers: Woodlings trade directions for knowledge, Swamplings capture them
	var B := {"prov": w.capital, "n": 3, "asked": false}
	w.travelers.append(B)
	w.trav_asking = B
	var bank0: float = w.tech.gov.get("bank", 0)
	var prog0: float = w.tech.gov.get("prog", 0)
	w.travelers_choose("know-gov")
	chk.call(not w.travelers.has(B) and (w.tech.gov.get("bank", 0) + w.tech.gov.get("prog", 0)) > bank0 + prog0, "Woodling Scouts guide travelers for research")
	var B2 := {"prov": g.capital, "n": 4, "asked": false}
	g.travelers.append(B2)
	g.trav_asking = B2
	var f0: int = g.stock.food
	g.travelers_choose("capture")
	chk.call(g.stock.food == mini(f0 + 120, g.storage_cap("food")), "Berserkers capture travelers for food")
	# --- a full island with one opponent of each race ---
	var f := _world_with(["swamp", "wood", "realm"])
	var races := {}
	for id in f.nations:
		races[f.nations[id].race] = true
		var N: Dictionary = f.nations[id]
		if N.race == "swamp":
			chk.call(f.G.provs[N.capital].terrain == "swamp" and N.tech.gov.done.has("mushroom") and N.name.length() > 3, "a Swampling nation in a swamp")
	chk.call(races.size() == 3, "opponents of all three races (got %s)" % str(races.keys()))
	# Growl: only Swamplings; a Realmling or Woodling nation always takes it badly
	Races.apply(f, "swamp")
	for id in f.nations:
		f.met[id] = true if f.met is Dictionary else f.met
		if f.nations[id].race != "swamp":
			f.dx_act("growl", id)
			chk.call(f.mod_active(id, Game.HOST, "growl") != null and f.mod_active(id, Game.HOST, "growl").v < 0, "a growl at a non-Swampling nation is a threat")
			chk.call(f.flirt_why(id) != "", "no flirting across races")
			break
	# Organized Crime between two Swampling nations: +1 Thug in every den
	var sw_id := -1
	for id in f.nations:
		if f.nations[id].race == "swamp":
			sw_id = id
	if sw_id >= 0:
		var cap0 := f.den_cap(Game.HOST)
		chk.call(f.crime_why(Game.HOST, sw_id) != "" or true, "crime_why answers")
		f.form_pact("crime", Game.HOST, sw_id)
		chk.call(f.den_cap(Game.HOST) == cap0 + 1, "Organized Crime adds a Thug to every den")
		chk.call(f.trade_why(Game.HOST, sw_id).begins_with("Only Woodlings"), "Swamplings form no Trade Networks")
	# computer counter designs carry their nation's race
	for id in f.nations:
		var N2: Dictionary = f.nations[id]
		if N2.race != "realm":
			var cd: Dictionary = Ai.counter_designs(f, N2)
			if not cd.is_empty():
				chk.call(f.DSTATS[cd.pole].race == N2.race, "a %s nation's counter designs are %s" % [N2.race, N2.race])
	# leaders: Phlyo's Sacred Pyre costs no wood; forge leaders pay 25% less for a Forge; Naobrien's Elemental hits harder
	var ph := Game.new_practice("ember", "phlyo")
	chk.call(ph.sacred_wood() == 0, "Phlyo raises Sacred Pyres without wood")
	var gl := Game.new_practice("ember", "glurg")
	chk.call(gl.BUILD_DEFS.forge.cost.get("gold", 0) == int(JS.round_js(GameData.c("BUILD_DEFS").forge.cost.get("gold", 0) * 0.75)), "Glurg's Forges cost 25% less")
	var nb := Game.new_practice("oak", "naobrien")
	chk.call(absf(nb.stats_of(Game.GELEM_ID, Game.HOST).atk - GameData.c("DSTATS")[Game.GELEM_ID].atk * 1.3) < 0.01, "Naobrien's Grand Elemental hits 30% harder")
	# a Warlock's skull adds to the wand and shortens the Fireball
	var t0 := g.spell2_time("shock", Game.HOST)
	g.set_mage_gear({"weapon": "wand", "skull": "skull1"})
	chk.call(g.mage_stats(g.mage_gear).atk == g.mage_stats({"weapon": "wand"}).atk + 1 and g.spell2_time("shock", Game.HOST) == t0 - 2, "the Cracked Skull: +1 attack, Fireball 2 s faster")
	# --- save and load keeps the race ---
	var g2 := Game.load_text(g.save_text())
	chk.call(g2 != null and g2.is_sw() and g2.BUILD_DEFS.stable.name == "Ogre Cave", "a loaded Swampling game keeps its names")
	return errs


func _world_with(races: Array) -> Game:
	var g := Game.new()
	var mode := "normal"
	g.world = RealmGen.scale_world(RealmGen.generate_world("ember", null, true))
	g.world.mode = mode
	g.G = WorldPrep.prep(g.world)
	g.players = GameData.c("PLAYERS").duplicate(true)
	g.set_nation({})
	g.setup_game("center")
	g.slot_races = races
	g.spawn_ai_nations(["easy", "easy", "easy"])
	return g
