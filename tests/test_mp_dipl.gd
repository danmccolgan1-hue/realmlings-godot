extends RefCounted
## Diplomacy between human players (multiplayer step 11), through orders as the network applies them: messages,
## proclamations, barter (accepted, and declined when the 30 s run out), Flirt and Growl that only tell, gifts,
## access and alliances the other player chooses (across races), Proclaim Enemy heard by everyone who met the
## proclaimer, no Bribe between players, a white peace offered and accepted, all in two copies that stay alike.

const HUMANS := {0: {"nation": {"name": "Bog Kings"}, "race": "swamp"}, 1: {"nation": {"name": "Leafholt"}, "race": "wood"}}

var copies: Array = []


func run() -> Array:
	var errs := []
	var a := Game.new_world("ember", "cormac", ["human", "human", "moderate"], "center", {}, {}, {"name": "Hosts"}, "realm", [], HUMANS.duplicate(true))
	var b := Game.load_text(a.save_text(), a.world)
	copies = [a, b]
	var ids := a.seat_ids()
	var H: int = Game.HOST
	var S: int = ids[1]
	var W: int = ids[2]
	for g in copies:
		g.paused = false
		for x in ids:   # everyone has met everyone
			for y in ids:
				if x != y:
					g.seats[x].met[y] = true
		for o in ids:
			g.seats[o].stock = {"gold": 1500, "wood": 500, "food": 500}
	# a message: 50 gold, 80 letters, for one player
	_do(H, "send_message", [S, "Hello neighbor! " + "x".repeat(200)])
	var n = _news(a, S, "msg")
	if n == null or a.seats[H].stock.gold != 1450 or n.text.length() > 120 or not n.text.contains("Hello neighbor"):
		errs.append("a message did not arrive, cost 50 gold, or was not cut to 80 letters")
	if _news(a, W, "msg") != null:
		errs.append("a message reached someone else")
	# a proclamation: 100 gold, to everyone the sender met
	_do(S, "issue_proclamation", ["The swamp rises!"])
	if _news(a, H, "procl") == null or _news(a, W, "procl") == null or a.seats[S].stock.gold != 1400:
		errs.append("a proclamation did not reach every player met, or didn't cost 100 gold")
	# barter, accepted
	_do(H, "offer_barter", [S, {"gold": 200}, {"wood": 100}])
	var r = _req(a, S, "barter")
	if r == null:
		errs.append("the barter offer did not arrive")
	else:
		_do(S, "answer_request", [{"_r": r.id}, true])
		if a.seats[H].stock.gold != 1250 or a.seats[H].stock.wood != 600 or a.seats[S].stock.gold != 1600 or a.seats[S].stock.wood != 400:
			errs.append("the accepted barter did not trade: host %s, swamp %s" % [a.seats[H].stock, a.seats[S].stock])
	# barter, unanswered: declined after 30 s
	_do(W, "offer_barter", [H, {"food": 50}, {"gold": 10}])
	if _req(a, H, "barter") == null:
		errs.append("the second barter offer did not arrive")
	_steps(int(32.0 / Game.STEP))
	if _req(a, H, "barter") != null or _news(a, W, "answer") == null or a.seats[W].stock.food < 400:
		errs.append("an unanswered barter was not declined after 30 s")
	# Flirt and Growl only tell
	_do(S, "dx_act", ["growl", H])
	_do(H, "dx_act", ["flirt", W])
	if _news(a, H, "growl") == null or _news(a, W, "flirt") == null:
		errs.append("Flirt or Growl did not reach the other player")
	# a gift goes straight to the treasury
	var g0: int = a.seats[W].stock.gold
	_do(H, "dx_act", ["gift", W])
	if a.seats[W].stock.gold + a.seats[W].gift_vault != g0 + Game.DIPL.gift.gold:
		errs.append("a gift between players did not arrive")
	# access and an alliance across races: the other player chooses
	_do(H, "dx_act", ["ask", S])
	r = _req(a, S, "h_access")
	if r != null:
		_do(S, "answer_request", [{"_r": r.id}, true])
	if not a.access_given(S, H):
		errs.append("access asked for and granted did not take effect")
	_do(H, "dx_act", ["ally", W])
	r = _req(a, W, "h_ally")
	if r != null:
		_do(W, "answer_request", [{"_r": r.id}, true])
	if not a.allied(H, W):
		errs.append("a Realmling and a Woodling player could not ally")
	# no bribing between players
	var bw: String = a.in_seat(S, func(): return a.player_act_why("bribe", H))
	if bw == "":
		errs.append("a player could bribe another player")
	# Proclaim Enemy: heard by everyone who met the proclaimer
	_do(S, "dx_act", ["proclaim", W])
	if a.enemy_of(S) != W or _news(a, H, "enemy") == null or _news(a, W, "enemy") == null:
		errs.append("a proclaimed enemy was not heard by every player who met them")
	# a white peace between players is offered, and the other chooses
	for g in copies:
		g.new_war(S, H, null)
	var w: Dictionary = a.war_between(S, H)
	_do(S, "make_peace", [{"_w": w.id}, S, {"kind": "white"}])
	if not a.at_war(S, H):
		errs.append("a white peace was forced on another player")
	r = _req(a, H, "h_peace")
	if r == null:
		errs.append("the white peace offer did not arrive")
	else:
		_do(H, "answer_request", [{"_r": r.id}, true])
		if a.at_war(S, H):
			errs.append("an accepted white peace did not end the war")
	_steps(40)
	if a.checksum() != b.checksum():
		errs.append("the two copies differ after the diplomacy")
	var c := Game.load_text(a.save_text(), a.world)
	if c == null or c.checksum() != a.checksum():
		errs.append("the game with diplomacy between players did not save and load alike")
	return errs


func _do(o: int, type: String, args: Array) -> void:
	for g in copies:
		g.apply({"player": o, "type": type, "args": args.duplicate(true)})


func _steps(n: int) -> void:
	for i in n:
		for g in copies:
			if g.trav_asking != null:
				g.apply({"player": g.trav_asking.get("by", Game.HOST), "type": "travelers_choose", "args": ["leave"]})
			g.paused = false
			g.step_fixed()


func _news(g: Game, o: int, kind: String):
	return g.in_seat(o, func():
		for n in g.dipl_state().news:
			if n.kind == kind:
				return n
		return null)


func _req(g: Game, o: int, kind: String):
	return g.in_seat(o, func():
		for r in g.dipl_state().reqs:
			if r.kind == kind:
				return r
		return null)
