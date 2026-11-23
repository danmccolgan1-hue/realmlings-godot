extends RefCounted
## The 0.18 terrain variants: a tenth of each terrain becomes Drylands, Meadow, Fae Forest or Bog with their own
## yields; Meadow Farms and Fae Forest Lumber Mills give more; a Bog halves everyone but Swamplings, helps its
## defenders and doubles building prices (halves them for Swamplings). Also: Swamplings and Woodlings fly their own
## emblems, and a nation of another race is liked less.


func run() -> Array:
	var errs := []
	Game.VARIANTS = true
	var g := Game.new_world("ember", "", ["moderate", "moderate"], "center", {}, {}, {}, "realm")
	var count := {}
	var total := {}
	for i in g.G.provs.size():
		var ter: String = g.G.provs[i].terrain
		total[ter] = total.get(ter, 0) + 1
		var v := g.variant_of(i)
		if v != "":
			count[v] = count.get(v, 0) + 1
			if Game.VARIANT_OF.get(ter, "") != v:
				errs.append("province %d is %s but its variant is %s" % [i, ter, v])
			var Y: Dictionary = Game.VARIANT_YIELD[v]
			for k in Y:
				var extra: int = int(g.yields[i].bonus.get(k, 0))
				if int(g.yields[i][k]) != int(Y[k]) + extra:
					errs.append("a %s yields %d %s, not %d" % [v, g.yields[i][k], k, Y[k]])
	for ter in Game.VARIANT_OF:
		var want := int(floor(total.get(ter, 0) * 0.1 + 0.5))
		var have: int = count.get(Game.VARIANT_OF[ter], 0)
		if absi(have - want) > 2:   # (unique sites and moved capitals can't be variants)
			errs.append("%d of %d %s provinces are variants (want about %d)" % [have, total.get(ter, 0), ter, want])
	# the same seed gives the same variants
	var g2 := Game.new_world("ember", "", ["moderate", "moderate"], "center", {}, {}, {}, "realm")
	if str(g2.variant) != str(g.variant):
		errs.append("the same seed gave different terrain variants")
	# and saving keeps them
	var g3 = Game.load_text(g.save_text())
	if g3 != null and str(g3.variant) != str(g.variant):
		errs.append("a saved game lost its terrain variants")
	# Bog: speed, prices, defence
	var bog := g.variant.find("bog")
	if bog < 0:
		bog = 0
		g.variant[bog] = "bog"
	var u := {"kind": "army", "owner": Game.HOST, "prov": bog, "troops": {}}
	var sp := g.speed_mod(u)
	g.variant[bog] = ""
	var sp0 := g.speed_mod(u)
	g.variant[bog] = "bog"
	if absf(sp - sp0 * 0.5) > 0.001:
		errs.append("a Realmling army in a Bog moves at %.2f, not half of %.2f" % [sp, sp0])
	var c := g.bog_cost(bog, Game.HOST, {"gold": 50, "wood": 30})
	if c.gold != 100 or c.wood != 60:
		errs.append("a Realmling building in a Bog costs %s, not double" % str(c))
	var sw := Game.new_world("ember", "", ["moderate"], "center", {}, {}, {}, "swamp")
	var sb := sw.variant.find("bog")
	if sb < 0:
		sb = 0
		sw.variant[sb] = "bog"
	var c2 := sw.bog_cost(sb, Game.HOST, {"gold": 50, "wood": 30})
	if c2.gold != 25 or c2.wood != 15:
		errs.append("a Swampling building in a Bog costs %s, not half" % str(c2))
	var su := {"kind": "army", "owner": Game.HOST, "prov": sb, "troops": {}}
	var ssp := sw.speed_mod(su)
	sw.variant[sb] = ""
	if ssp < sw.speed_mod(su) - 0.001:
		errs.append("Swamplings are slowed by a Bog")
	# Meadow Farms +3 food, Fae Forest Lumber Mills +3 wood
	var p := g.capital
	g.extras[p] = [{"type": "farm", "slot": 0}]
	g.variant[p] = ""
	var f0: int = g.extras_bonus(p).food
	g.variant[p] = "meadow"
	if g.extras_bonus(p).food != f0 + 3:
		errs.append("a Farm in a Meadow gives %d food, not %d" % [g.extras_bonus(p).food, f0 + 3])
	g.extras[p] = [{"type": "lumber", "slot": 0}]
	g.variant[p] = ""
	var w0: int = g.extras_bonus(p).wood
	g.variant[p] = "fae"
	if g.extras_bonus(p).wood != w0 + 3:
		errs.append("a Lumber Mill in a Fae Forest gives %d wood, not %d" % [g.extras_bonus(p).wood, w0 + 3])
	g.variant[p] = ""
	# emblems: Swamplings and Woodlings have none of the Realmlings' crowns, shields, swords or eagles
	for rc in ["swamp", "wood"]:
		for em in ["crown", "shield", "swords", "eagle"]:
			if Races.EMBLEMS[rc].has(em):
				errs.append("%s still fly the %s" % [Races.NAME[rc], em])
	Game.VARIANTS = false
	return errs
