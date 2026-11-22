extends RefCounted
## Multiplayer lockstep needs every copy of a game to compute exactly the same thing from the same start and the
## same orders. This plays one full-island game with three computer nations three times, in fixed steps, with the
## same scripted orders: the original game, a copy loaded from its save at the start (as a joining player gets it),
## and a copy loaded halfway through (as a player who fell out of step is resent it). Their fingerprints
## (Game.checksum) must match at every check.

const SECONDS := 240.0
const CHECK_EVERY := 10.0


func run() -> Array:
	var errs := []
	var a := Game.new_world("ember", "cormac", ["moderate", "moderate", "difficult"], "center")
	a.rng.seed = 4242   # (the same rolls in every copy from here on: they all load or keep this state)
	var b := Game.load_text(a.save_text(), a.world)
	if b == null:
		return ["the save at the start did not load"]
	if a.checksum() != b.checksum():
		errs.append("a game and its loaded copy differ before the first step")
	var c = null
	var steps := int(SECONDS / Game.STEP)
	var every := int(CHECK_EVERY / Game.STEP)
	for i in steps:
		for g in ([a, b] if c == null else [a, b, c]):
			_orders(g, i)
			g.step_fixed()
		if i == steps / 2:   # a copy resent the save halfway
			c = Game.load_text(a.save_text(), a.world)
			if c == null or c.checksum() != a.checksum():
				errs.append("the halfway save did not load the same game")
				c = null
		if i % every == every - 1:
			var ka := a.checksum()
			if b.checksum() != ka:
				errs.append("the copy loaded at the start fell out of step by %.1f s%s" % [a.t, _diff(a, b)])
				break
			if c != null and c.checksum() != ka:
				errs.append("the copy loaded halfway fell out of step by %.1f s%s" % [a.t, _diff(a, c)])
				break
	if a.t < SECONDS * 0.99:
		errs.append("the game ran only %.1f s" % a.t)
	return errs


## The same orders at the same steps in every copy, as the multiplayer command queue would apply them.
func _orders(g: Game, i: int) -> void:
	if g.trav_asking != null:   # lost travelers pause the game for an answer: the scripted player sends them on
		g.travelers_choose("leave")
	if g.paused:
		g.paused = false
	match i:
		20:
			g.train("capital", g.capital, g.footman_of())
		60:
			for u in g.units:
				if u.owner == Game.ME and u.kind == GameData.c("WAYFINDER"):
					g.order(u, g.all_nbr[g.capital][0], true)
					break
		200:
			for x in g.TECHS:
				if g.tech.gov.opts.has(x.id):
					g.pick_tech(x.id)
					break
		600:
			g.train("capital", g.capital, g.footman_of())


## Which saved fields differ, to point at the rule that drifted.
func _diff(x: Game, y: Game) -> String:
	var dx := x.to_save()
	var dy := y.to_save()
	var out := []
	for k in dx:
		if k in Game.CHECKSUM_SKIP:
			continue
		if SaveCodec.to_text({"v": dx[k]}) != SaveCodec.to_text({"v": dy.get(k)}):
			out.append(k)
	return " (fields: %s)" % ", ".join(out.slice(0, 8))
