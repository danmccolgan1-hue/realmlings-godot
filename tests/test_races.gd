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
	chk.call(g.gives_of("market").is_empty() and g.store_of("bank", Game.ME).wood == 500, "Thug Den gives nothing; Supply Cache stores wood")
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
	# --- a full island with one opponent of each race ---
	var f := _world_with(["swamp", "wood", "realm"])
	var races := {}
	for id in f.nations:
		races[f.nations[id].race] = true
		var N: Dictionary = f.nations[id]
		if N.race == "swamp":
			chk.call(f.G.provs[N.capital].terrain == "swamp" and N.tech.gov.done.has("mushroom") and N.name.length() > 3, "a Swampling nation in a swamp")
	chk.call(races.size() == 3, "opponents of all three races (got %s)" % str(races.keys()))
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
