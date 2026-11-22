extends RefCounted
## The rules from the 0.17 playtest notes: a Mage (Warlock) joins an army and leaves it again; Death Mountain shows
## from any province beside it; allies share their sight; Grave Robbing keeps its name; tooltips in the race's words;
## random nation names in each race's style.


func run() -> Array:
	var errs := []
	# Join army / Detach
	var g := Game.new_world("ember", "", ["moderate"], "center", {}, {}, {}, "swamp")
	var cap: int = g.capital
	var m := g.mk_unit(g.next_id, g.MAGE, "Warlock", cap, 5)
	g.next_id += 1
	m.mana = 40.0
	g.units.append(m)
	var army = null
	for u in g.units:
		if u.kind == "army" and u.owner == Game.HOST:
			army = u
	if army == null:
		return ["no starting army"]
	army.prov = cap
	army.troops.erase(g.MAGE)   # (some leaders start with one in the army)
	army.battle = null
	for u in g.units:   # (and only this army stands here)
		if u.kind == "army" and u.owner == Game.HOST and not is_same(u, army) and u.prov == cap:
			u.prov = g.all_nbr[cap][0]
	if g.join_why(m) != "":
		errs.append("the Warlock can't join the army beside him: %s" % g.join_why(m))
	var a = g.mage_join([m])
	if a == null or army.troops.get(g.MAGE, 0) != 1 or g.units.any(func(v): return is_same(v, m)) or absf(Game.mana_of(army) - 40.0) > 0.01:
		errs.append("the Warlock did not join the army with his mana")
	var m2 = g.mage_detach(army)
	if m2 == null or army.troops.has(g.MAGE) or not g.units.any(func(v): return is_same(v, m2)) or m2.kind != g.MAGE:
		errs.append("the Warlock did not leave the army")
	# Death Mountain: seen from the province beside it
	var U = g.uq()
	if U != null and int(U.get("death", -1)) >= 0:
		var dm := int(U.death)
		var nb := int(g.world.provinces[dm].nbr[0])
		g.known[nb] = true
		var w := g.mk_unit(g.next_id, g.WAYFINDER, "Seer", nb, 2)
		g.next_id += 1
		g.units.append(w)
		g.compute_fog()
		if not g.visible.has(dm) or not g.explored.has(dm):
			errs.append("Death Mountain didn't show from the province beside it")
	# allies share sight
	var o: int = g.nations.keys()[0]
	var their: int = g.nations[o].capital
	g.compute_fog()
	var before: bool = g.visible.has(their)
	g.form_alliance(o, Game.HOST, 0)
	g.compute_fog()
	if before or not g.visible.has(their):
		errs.append("an ally's land was not shared (%s before, %s after)" % [before, g.visible.has(their)])
	# Grave Robbing keeps its name
	var gname: String = g.TECH_BY_ID["graverob"].name
	if g.spell_name("graverob") != gname:
		errs.append("Grave Robbing is called %s" % g.spell_name("graverob"))
	# tooltips in the race's words
	var t1: String = Races.words("The Mason builds a Stable, which lets a Barracks train cavalry.", "swamp")
	if t1.contains("Mason") or t1.contains("cavalry") or not t1.contains("Swampwright") or not t1.contains("Ogre"):
		errs.append("Swampling words: %s" % t1)
	var t2: String = Races.words("A Wayfinder and a Mage", "wood")
	if t2 != "A Scout and a Druid":
		errs.append("Woodling words: %s" % t2)
	if Races.words(t1, "swamp") != t1:
		errs.append("the race's words change twice")
	# random nation names in each race's style
	var NP: Dictionary = GameData.c("NAME_PARTS")
	for i in 20:
		var sw := StartScreen.random_nation_name("swamp")
		if not NP.swamp.titles.any(func(x): return sw.contains(x)):
			errs.append("a Swampling name without a Swampling title: %s" % sw)
			break
		var wd := StartScreen.random_nation_name("wood")
		if not (NP.wood.groups.any(func(x): return wd.contains(x)) or NP.wood.pre.any(func(x): return wd.begins_with(x))):
			errs.append("a Woodling name in another style: %s" % wd)
			break
	return errs
