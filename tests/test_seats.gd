extends RefCounted
## Multiplayer steps 1–3 without a network: several human nations in one game, each with its own fields (seats),
## played by orders that go through Game.apply, in two copies that must stay identical. Also: saving and loading
## every seat, the pause rule, and a dropped player's nation handed to the computer mid-game.

const SECONDS := 240.0
const CHECK_EVERY := 10.0
# (the Swampling's leader is pinned: a random one could be Zaarg, who starts at his Wayfinder limit and can't train
# the one this test orders)
const HUMANS := {0: {"nation": {"name": "Bog Kings", "emblem": "skull", "color": 3}, "race": "swamp", "leader": "glurg"},
	2: {"nation": {"name": "Leafholt", "emblem": "spiral", "color": 5}, "race": "wood"}}


func _new() -> Game:
	return Game.new_world("ember", "cormac", ["human", "moderate", "human"], "center", {}, {}, {"name": "Hosts"}, "realm", [], HUMANS.duplicate(true))


func run() -> Array:
	var errs := []
	var a := _new()
	var ids := a.seat_ids()
	if ids.size() != 3:
		return ["expected 3 human nations, got %s" % [ids]]
	var other: Array = ids.filter(func(o): return o != Game.HOST)
	# each seat is its own nation: capital, race, stock, flag, starting units
	var caps := {}
	for o in ids:
		var S: Dictionary = a.seats[o]
		if S.capital < 0 or not a.buildings.has(S.capital) or a.buildings[S.capital].owner != o:
			errs.append("nation %d does not own its capital" % o)
		caps[S.capital] = true
		if a.units.filter(func(u): return u.owner == o).size() < 3:
			errs.append("nation %d is missing its starting units" % o)
		if a.controller(o) != "human":
			errs.append("nation %d is not played by a human" % o)
	if caps.size() != 3:
		errs.append("two human nations share a capital")
	if a.race(other[0]) != "swamp" or a.race(other[1]) != "wood" or a.race(Game.HOST) != "realm":
		errs.append("the races are wrong: %s %s %s" % [a.race(Game.HOST), a.race(other[0]), a.race(other[1])])
	if a.player_info(other[0]).name != "Bog Kings" or a.seats[other[0]].my_nation.emblem != "skull":
		errs.append("a human nation's name or flag was not kept")
	if a.in_seat(other[0], func(): return a.BUILD_DEFS.market.has("gives")):
		errs.append("the Swampling seat has the Realmlings' Market")
	if a.nations.size() != 1:
		errs.append("expected one computer nation, got %d" % a.nations.size())
	if a.ME != Game.HOST:
		errs.append("the game did not come back to the host's seat")
	# the same orders in two copies
	var b := Game.load_text(a.save_text(), a.world)
	if b == null:
		return errs + ["the multiplayer save did not load"]
	if b.checksum() != a.checksum() or b.seat_ids() != ids:
		errs.append("the loaded copy differs before the first step")
	a.rng.seed = 99
	b.rng.seed = 99
	var steps := int(SECONDS / Game.STEP)
	var every := int(CHECK_EVERY / Game.STEP)
	var gold0 := {}
	var dropped := false
	for i in steps:
		for g in [a, b]:
			_orders(g, i, other)
			g.step_fixed()
		if i == 10:
			for o in ids:
				gold0[o] = a.seats[o].stock.gold
		if i == 40:
			# only the nation that trained paid for it
			if a.seats[other[0]].stock.gold >= gold0.get(other[0], 0) - 10:
				errs.append("the Swampling seat's training didn't cost it gold")
			if not a.seats[other[0]].queues.values().any(func(q): return not q.is_empty()):
				errs.append("the Swampling seat's training was not queued")
		if i == steps * 3 / 4 and not dropped:   # the Woodling player drops out: the host hands the nation to the computer
			for g in [a, b]:
				g.apply({"player": Game.HOST, "type": "set_paused", "args": [false]})
				g.hand_to_ai(other[1])
			dropped = true
			if a.controller(other[1]) != "ai" or a.seats.has(other[1]):
				errs.append("the dropped nation was not handed to the computer")
		if i % every == every - 1:
			if a.checksum() != b.checksum():
				errs.append("the copies fell out of step by %.1f s%s" % [a.t, _diff(a, b)])
				break
	if a.t < SECONDS * 0.9:
		errs.append("the game ran only %.1f s" % a.t)
	for o in [Game.HOST, other[0]]:
		if a.seats[o].explored.size() <= 1:
			errs.append("nation %d explored nothing" % o)
	if a.seats[Game.HOST].explored == a.seats[other[0]].explored:
		errs.append("two human nations share one fog")
	if not a.nations.has(other[1]) or a.units.filter(func(u): return u.owner == other[1]).is_empty():
		errs.append("the computer did not keep playing the dropped nation")
	# saved and loaded, the whole game comes back
	var c := Game.load_text(a.save_text(), a.world)
	if c == null or c.checksum() != a.checksum():
		errs.append("the multiplayer save did not load the same game")
	errs.append_array(_war())
	errs.append_array(_pause_rule())
	errs.append_array(_refs(a, other[0]))
	return errs


## The scripted players' orders: the same at the same step in every copy, as lockstep would apply them.
func _orders(g: Game, i: int, other: Array) -> void:
	if g.trav_asking != null:
		g.apply({"player": g.trav_asking.get("by", Game.HOST), "type": "travelers_choose", "args": ["leave"]})
	if g.paused:
		g.apply({"player": Game.HOST, "type": "set_paused", "args": [false]})
	var all: Array = [Game.HOST] + other.filter(func(o): return g.seats.has(o))
	for o in all:
		var S: Dictionary = g.seats[o]
		match i:
			20:
				g.apply({"player": o, "type": "train", "args": ["capital", S.capital, g.trainable("capital", S.capital)[0]]})
			60:
				for u in g.units:
					if u.owner == o and u.kind == GameData.c("WAYFINDER"):
						g.apply({"player": o, "type": "order", "args": [g.pack_args([u])[0], g.all_nbr[S.capital][0], true]})
						break
			200:
				var opts: Array = S.tech.gov.opts
				if not opts.is_empty():
					g.apply({"player": o, "type": "pick_tech", "args": [opts[0]]})
			900:
				for u in g.units:
					if u.owner == o and u.kind == GameData.c("WAYFINDER"):
						g.apply({"player": o, "type": "order", "args": [{"_u": u.id}, g.all_nbr[S.capital][-1], true]})
						break


## Two human nations at war, and a computer nation at war with a human that isn't the host: armies meet, fight and
## occupy, in two copies that stay identical.
func _war() -> Array:
	var errs := []
	var a := _new()
	var b := Game.load_text(a.save_text(), a.world)
	var o: int = a.seat_ids()[1]
	var ai: int = a.nations.keys()[0]
	var cap_o: int = a.seats[o].capital
	var cap_ai: int = a.nations[ai].capital
	var fought := false
	for g in [a, b]:
		g.paused = false
		g.new_war(Game.HOST, o, null)   # (they don't border yet: the war is made directly)
		g.new_war(ai, o, null)
		for u in g.units:   # the host's army stands in the Swamplings' capital; theirs in the computer's
			if u.kind == "army" and (u.owner == Game.HOST or u.owner == o):
				var at: int = cap_o if u.owner == Game.HOST else cap_ai
				var xy: Array = g.slot_pos(at, 6)
				u.prov = at
				u.x = xy[0]
				u.y = xy[1]
				u.troops[u.troops.keys()[0]] = 20
	if not a.at_war(Game.HOST, o) or not a.at_war(ai, o):
		errs.append("the wars were not declared")
	for i in int(90.0 / Game.STEP):
		for g in [a, b]:
			if g.trav_asking != null:
				g.apply({"player": g.trav_asking.get("by", Game.HOST), "type": "travelers_choose", "args": ["leave"]})
			if g.paused:
				g.apply({"player": Game.HOST, "type": "set_paused", "args": [false]})
			g.step_fixed()
		if not a.battles.is_empty():
			fought = true
		if i % 100 == 99 and a.checksum() != b.checksum():
			errs.append("the copies at war fell out of step by %.1f s%s" % [a.t, _diff(a, b)])
			break
	if not fought:
		errs.append("the armies of two human nations never fought")
	for w in a.wars.duplicate():
		if (w.a == Game.HOST and w.b == o) or (w.a == o and w.b == Game.HOST):
			for g in [a, b]:   # a white peace between players is offered, and the other accepts
				g.apply({"player": Game.HOST, "type": "make_peace", "args": [g.pack_args([w])[0], Game.HOST, {"kind": "white"}]})
				var rid: int = g.in_seat(o, func(): return g.dipl_state().reqs.filter(func(r): return r.kind == "h_peace")[0].id)
				g.apply({"player": o, "type": "answer_request", "args": [{"_r": rid}, true]})
	if a.at_war(Game.HOST, o):
		errs.append("the human nations could not make peace")
	if a.checksum() != b.checksum():
		errs.append("the copies differ after the peace")
	return errs


## Any player may pause; only the host or whoever paused may go on.
func _pause_rule() -> Array:
	var errs := []
	var g := _new()
	var o: Array = g.seat_ids().filter(func(x): return x != Game.HOST)
	g.paused = false
	g.apply({"player": o[0], "type": "set_paused", "args": [true]})
	if not g.paused or g.paused_by != o[0]:
		errs.append("a player could not pause")
	g.apply({"player": o[1], "type": "set_paused", "args": [false]})
	if not g.paused:
		errs.append("a player unpaused someone else's pause")
	g.apply({"player": o[0], "type": "set_paused", "args": [false]})
	if g.paused:
		errs.append("the player who paused could not go on")
	g.apply({"player": o[1], "type": "set_paused", "args": [true]})
	g.apply({"player": Game.HOST, "type": "set_paused", "args": [false]})
	if g.paused:
		errs.append("the host could not unpause")
	if g.apply({"player": 9, "type": "set_paused", "args": [true]}) != null or g.apply({"player": o[0], "type": "save_text", "args": []}) != null:
		errs.append("an order from nobody, or one that isn't an order, was applied")
	return errs


## Units, wars and requests travel as references and come back as the same objects.
func _refs(g: Game, o: int) -> Array:
	var errs := []
	var u: Dictionary = g.units.filter(func(x): return x.owner == o)[0]
	var packed := g.pack_args([u, [u], 5, "x"])
	if not (packed[0] is Dictionary and packed[0].has("_u")) or var_to_bytes(packed).size() > 200:
		errs.append("a unit did not travel as a reference: %s" % [packed])
	var back := g.unpack_args(packed)
	if not is_same(back[0], u) or not is_same(back[1][0], u) or back[2] != 5:
		errs.append("a unit reference did not come back as the same unit")
	return errs


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
