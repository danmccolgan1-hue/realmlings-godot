class_name Dungeons
extends RefCounted
## Dungeons and prisoners (Godot only, multiplayer only; docs/QUESTS_PLAN.md sessions 9–12). A Dungeon holds 3
## prisoners; a nation may build several. Prisoners come only from the Dungeon quests (the ransom events, Jailbreak).
## A prisoner with nowhere to go is Detained; after 3 cycles without a Dungeon with room, they escape.
## State on the Game: a Dungeon's `prisoners` on its building record, and `detained`. Rules only; never draws.
##
## A prisoner: {kind: "lady" | "envoy" | "general" | "noble" | "merchant" | "apprentice" | "convict", from: nation,
## name, id}.

const DUNGEON := "dungeon"
const SLOTS := 3
const ESCAPE_CYCLES := 3
## the prisoners who go home (not to the victor) when freed in a peace deal
const NOTABLE := ["lady", "envoy", "general", "noble", "merchant", "apprentice"]
const KIND_NAME := {"lady": "Noble Lady", "envoy": "Envoy", "general": "General", "noble": "Noble", "merchant": "Merchant",
	"apprentice": "Apprentice", "convict": "Convict"}


## Dungeons are for games with more than one human nation.
static func on(g) -> bool:
	return g.quests_on and g.seats.size() > 1


## Nation o's Dungeons, in province order: [{p, e}].
static func dungeons(g, o: int) -> Array:
	var ps: Array = g.extras.keys()
	ps.sort()
	var out := []
	for p in ps:
		if g.nation_of(p) != o:
			continue
		for e in g.extras[p]:
			if e.type == DUNGEON:
				out.append({"p": p, "e": e})
	return out


static func held_in(e: Dictionary) -> Array:
	var x = e.get("prisoners")
	return x if x is Array else []


static func _held_rw(e: Dictionary) -> Array:
	if not (e.get("prisoners") is Array):
		e["prisoners"] = []
	return e["prisoners"]


static func room(g, o: int):
	for r in dungeons(g, o):
		if held_in(r.e).size() < SLOTS:
			return r.e
	return null


## Every prisoner nation o holds (in its Dungeons).
static func prisoners_of(g, o: int) -> Array:
	var out := []
	for r in dungeons(g, o):
		out.append_array(held_in(r.e))
	return out


static func capacity(g, o: int) -> int:
	return dungeons(g, o).size() * SLOTS


## A new prisoner record.
static func make(g, kind: String, from: int, name := "") -> Dictionary:
	g.prisoner_seq += 1
	return {"id": g.prisoner_seq, "kind": kind, "from": from, "name": name if name != "" else KIND_NAME.get(kind, kind)}


## Nation o takes prisoner pr: into a Dungeon with room, else Detained. Returns "dungeon" or "detained".
static func jail(g, o: int, pr: Dictionary) -> String:
	var e = room(g, o)
	if e != null:
		_held_rw(e).append(pr)
		return "dungeon"
	g.detained.append({"owner": o, "prisoner": pr, "cycles": 0})
	Quests.tell(g, o, "%s is Detained: you have no Dungeon with room. Build one within %d cycles or they escape." % [pr.name, ESCAPE_CYCLES], true)
	return "detained"


## Take a prisoner out of nation o's Dungeons (or Detained) by id; returns the record or null.
static func release(g, o: int, id: int):
	for r in dungeons(g, o):
		var list: Array = held_in(r.e)
		for i in list.size():
			if int(list[i].id) == id:
				var pr: Dictionary = list[i]
				list.remove_at(i)
				return pr
	for i in g.detained.size():
		if int(g.detained[i].owner) == o and int(g.detained[i].prisoner.id) == id:
			var pr2: Dictionary = g.detained[i].prisoner
			g.detained.remove_at(i)
			return pr2
	return null


## Who holds prisoner id (a nation), or 0.
static func holder(g, id: int) -> int:
	for p in g.extras:
		for e in g.extras[p]:
			if e.type == DUNGEON and held_in(e).any(func(x): return int(x.id) == id):
				return g.nation_of(p)
	for d in g.detained:
		if int(d.prisoner.id) == id:
			return int(d.owner)
	return 0


## Every cycle: Detained prisoners go into a Dungeon with room; after 3 cycles without one, they escape.
static func payday(g) -> void:
	var keep := []
	for d in g.detained:
		var e = room(g, int(d.owner))
		if e != null:
			_held_rw(e).append(d.prisoner)
			Quests.tell(g, int(d.owner), "%s is now locked in your Dungeon." % d.prisoner.name)
			continue
		d.cycles = int(d.cycles) + 1
		if d.cycles >= ESCAPE_CYCLES:
			Quests.popup(g, int(d.owner), "Prisoner Escape!", "The detained prisoner escaped in the night!", "Oh Well")
			escaped(g, int(d.owner), d.prisoner)
			continue
		keep.append(d)
	g.detained = keep


## A prisoner got away (the Dungeon quests listen: session 10–11).
static func escaped(g, _o: int, pr: Dictionary) -> void:
	on_escape(g, pr)


## A Dungeon is gone (torn down, dismantled, shaken down, cut from a captured province): its prisoners are Detained
## by the nation that held them.
static func lost(g, p: int, list: Array) -> void:
	var o: int = g.nation_of(p)
	for e in list:
		if e is Dictionary and e.get("type") == DUNGEON:
			for pr in held_in(e).duplicate():
				g.detained.append({"owner": o, "prisoner": pr, "cycles": 0})
			held_in(e).clear()


# ---------------------------------------------------------------------------------------------------------------
# The ransom events (session 10): the Captured Royal Lady (once a game, 4% a cycle for a player with a Dungeon who
# borders a Realmling or Woodling player they aren't allied with) and the Captured Envoy (after 20 minutes, 1% a
# cycle for a player with a Dungeon who has met another player; one at a time, 10 minutes apart; an envoy, general,
# noble, merchant or apprentice). Player X decides first; then Player Y has 40 s to pay, go to war (or, for an envoy,
# ignore it). A ransom war ends only at 50% warscore: Player Y frees the prisoner, or Player X demands concession.
# State: g.ransoms (the open and past events) and g.quest_events (once-a-game flags, the envoy's cooldown).

const LADY_CHANCE := 0.04
const ENVOY_CHANCE := 0.01
const ENVOY_AFTER := 1200.0
const ENVOY_COOLDOWN := 600.0
const ANSWER_TIME := 40.0
const RANSOMS := [50, 100, 250, 500, 1000]
const VARIANTS := ["envoy", "general", "noble", "merchant", "apprentice"]
## what ignoring a captured envoy costs Player Y (research every cycle, for 10 cycles) and gives Player X (once)
const IGNORED := {"envoy": ["mil", 100, 10], "general": ["mil", 200, 20], "noble": ["gov", 200, 20], "merchant": ["gov", 100, 10], "apprentice": ["mag", 100, 10]}
const PENALTY_CYCLES := 10
const RACE_PLURAL := {"realm": "Realmlings", "swamp": "Swamplings", "wood": "Woodlings"}


static func _cycle(g) -> int:
	return int(round(g.t / g.TICK))


static func borders(g, x: int, y: int) -> bool:
	for p in g.provs_of(x):
		for q in g.all_nbr[p]:
			if g.nation_of(q) == y:
				return true
	return false


static func open_ransom(g):
	for r in g.ransoms:
		if r.stage != "done":
			return r
	return null


## Every cycle (multiplayer games with quests): the ransom events may begin.
static func events_payday(g) -> void:
	if not on(g):
		return
	var n := _cycle(g)
	var ids: Array = g.seat_ids()
	if not g.quest_events.get("lady", false):
		for x in ids:
			if g.seats[x].fallen or dungeons(g, x).is_empty():
				continue
			var ys: Array = ids.filter(func(y): return y != x and not g.seats[y].fallen and g.race(y) in ["realm", "wood"] and not g.allied(x, y) and borders(g, x, y))
			if ys.is_empty():
				continue
			var r := Mulberry32.from_string("%s:lady:%d:%d" % [str(g.world.seed), n, x])
			if r.next() < LADY_CHANCE:
				g.quest_events["lady"] = true
				start(g, "lady", x, ys[int(floor(r.next() * ys.size()))])
				break
	if g.t >= ENVOY_AFTER and g.t >= float(g.quest_events.get("envoy_next", 0.0)) and not g.ransoms.any(func(r): return r.stage != "done" and r.kind != "lady"):
		for x in ids:
			if g.seats[x].fallen or dungeons(g, x).is_empty():
				continue
			var ys: Array = ids.filter(func(y): return y != x and not g.seats[y].fallen and g.seats[x].met.has(y))
			if ys.is_empty():
				continue
			var r := Mulberry32.from_string("%s:envoy:%d:%d" % [str(g.world.seed), n, x])
			if r.next() < ENVOY_CHANCE:
				var kind: String = VARIANTS[int(floor(r.next() * VARIANTS.size()))]
				start(g, kind, x, ys[int(floor(r.next() * ys.size()))])
				break


static func start(g, kind: String, x: int, y: int) -> Dictionary:
	g.ransom_seq += 1
	var pr := make(g, kind, y)
	var r := {"id": g.ransom_seq, "kind": kind, "x": x, "y": y, "pr": pr, "stage": "x", "amount": 0, "until": -1.0, "war": -1, "asked": -1.0}
	g.ransoms.append(r)
	ask_x(g, r)
	return r


static func _who(kind: String) -> String:
	return "noble lady" if kind == "lady" else KIND_NAME[kind].to_lower()


static func _them(kind: String) -> String:
	return "her" if kind == "lady" else "him"


static func ask_x(g, r: Dictionary) -> void:
	r.asked = g.t
	var y: int = r.y
	var text := ""
	if r.kind == "lady":
		text = "The neighboring %s should really keep a better eye on their royalty! We found one of their noble-born ladies unattended, swimming in the calm river! Their carelessness will be our gain!" % RACE_PLURAL.get(g.race(y), "nation")
	else:
		text = "We have captured a wandering %s from %s. Shall we ransom %s?" % [_who(r.kind), g.player_info(y).name, _them(r.kind)]
	var ch := [{"id": "release", "label": "Release " + _them(r.kind), "why": null}]
	for a in RANSOMS:
		ch.append({"id": "r%d" % a, "label": "Ransom %s: %d gold" % [_them(r.kind), a], "why": null if not dungeons(g, int(r.x)).is_empty() else "You need a Dungeon"})
	if r.kind != "lady":
		ch.append({"id": "kill", "label": "Kill " + _them(r.kind), "why": null})
	ask(g, int(r.x), ("The Captured Royal Lady" if r.kind == "lady" else "Captured %s!" % KIND_NAME[r.kind]), text, ch, r)


static func ask_y(g, r: Dictionary) -> void:
	r.asked = g.t
	var x: int = r.x
	var text := "The neighboring nation of %s is holding one of our %ss for ransom! They demand %d gold!\n\n(%d s to answer: no answer is war.)" % [g.player_info(x).name, _who(r.kind), int(r.amount), int(ANSWER_TIME)]
	var gold: int = g.seats[int(r.y)].stock.get("gold", 0)
	var ch := [{"id": "pay", "label": "Pay Ransom (%d gold)" % int(r.amount), "why": null if gold >= int(r.amount) else "Not enough gold"},
		{"id": "war", "label": "Declare War", "why": null}]
	if r.kind != "lady":
		ch.append({"id": "ignore", "label": "Ignore them", "why": null})
	ask(g, int(r.y), "Ransom!", text, ch, r)


## A choice for human nation o about ransom r: its answer comes back as an order (answer_ransom).
static func ask(g, o: int, title: String, text: String, choices: Array, r: Dictionary) -> void:
	var rid: int = r.id
	Quests.tell(g, o, title)
	g.in_seat(o, func():
		if g.on_dialog.is_valid() and g.ME == g.view_seat:
			g.on_dialog.call(title, Quests.words(g, o, text), choices, func(id): g.do("answer_ransom", [rid, str(id)])))


static func ransom_by_id(g, id: int):
	for r in g.ransoms:
		if int(r.id) == id:
			return r
	return null


## An answer (the order answer_ransom, from player g.ME).
static func answer(g, id: int, choice: String) -> void:
	var rv = ransom_by_id(g, id)
	if rv == null:
		return
	var r: Dictionary = rv
	if r.stage == "done":
		return
	var me: int = g.ME
	if choice == "leave":   # (Player X closed the box without a choice: asked again in a few seconds)
		if r.stage == "x" and me == int(r.x):
			r["reask"] = g.t + 5.0
		return
	if r.stage == "x" and me == int(r.x):
		if choice == "release":
			Quests.popup(g, r.x, "Released", "You are hoping that our enemies are as merciful as us. I pray you're right." if r.kind == "lady" else "He was not worth the trouble.", "Very well")
			Quests.popup(g, r.y, "Returned", ("The neighboring nation of %s has returned one of our lost noble ladies. We are grateful, yet suspicious..." if r.kind == "lady" else "The neighboring nation of %s has returned our " + _who(r.kind) + " unharmed.") % g.player_info(r.x).name, "Good")
			finish(g, r)
		elif choice == "kill" and r.kind != "lady":
			Quests.popup(g, r.x, "Executed", "He will trouble us no more.", "So be it")
			Quests.popup(g, r.y, "Executed", "The %s have executed our %s." % [g.player_info(r.x).name, _who(r.kind)], "We mourn him")
			finish(g, r)
		elif choice.begins_with("r") and choice.substr(1).is_valid_int() and not dungeons(g, int(r.x)).is_empty():
			r.amount = clampi(int(choice.substr(1)), 10, 1000)
			jail(g, int(r.x), r.pr)
			r.stage = "y"
			r.until = g.t + ANSWER_TIME
			ask_y(g, r)
		return
	if r.stage == "y" and me == int(r.y):
		if choice == "pay" and g.seats[me].stock.get("gold", 0) >= int(r.amount):
			g.seats[me].stock.gold -= int(r.amount)
			g.seats[int(r.x)].stock.gold = int(g.seats[int(r.x)].stock.get("gold", 0)) + int(r.amount)
			release(g, int(r.x), int(r.pr.id))
			Quests.popup(g, r.y, "Ransom paid", "We yield to these fiends and send them their gold.", "Grr")
			Quests.popup(g, r.x, "Ransom paid", "Our ransom was effective! We bankrupt our competition with their own carelessness.", "Splendid")
			finish(g, r)
		elif choice == "war":
			ransom_war(g, r)
		elif choice == "ignore" and r.kind != "lady":
			var I: Array = IGNORED[r.kind]
			release(g, int(r.x), int(r.pr.id))
			g.in_seat(int(r.x), func(): g.add_research(I[0], int(I[1])))
			g.seats[me]["research_pen"].append({"tree": I[0], "n": int(I[2]), "left": PENALTY_CYCLES})
			var tree_name: String = {"gov": "Government", "mil": "Military", "mag": "Magic"}[I[0]]
			Quests.popup(g, r.x, "Worthless", "The %s is worthless. Dispose of him.\n\n+%d %s Research" % [_who(r.kind), int(I[1]), tree_name], "Very well")
			Quests.popup(g, r.y, "Murdered", "The beasts have murdered him, we mourn his loss.\n\n−%d %s Research every cycle for %d cycles" % [int(I[2]), tree_name, PENALTY_CYCLES], "We mourn him")
			finish(g, r)


## Player Y goes to war over the prisoner (their answer, or 40 s without one): a ransom war, Y's allies with them.
static func ransom_war(g, r: Dictionary) -> void:
	var y: int = r.y
	var x: int = r.x
	var w = g.war_between(x, y)
	if w == null:
		w = g.in_seat(y, func(): return g.declare_war(y, x))
	if w == null:   # (a truce or the war cost stood in the way: the ransom war starts all the same)
		w = g.new_war(y, x, null)
		for j in g.allies_of(y):
			if j != x and not g.at_war(x, j):
				g.new_war(j, x, w.id)
	w["ransom"] = int(r.id)
	r.war = int(w.id)
	r.stage = "war"
	Quests.popup(g, y, "War!", "We shall send a message to every black hearted monster that we do not play games. Their cities shall burn for this!", "To arms")
	Quests.popup(g, x, "War!", "They overreact and have declared war over a woman! They shall pay for their foolishness." if r.kind == "lady" else "We both know this was an excuse for war. Let us end them.", "To arms")


static func finish(g, r: Dictionary) -> void:
	r.stage = "done"
	if r.kind != "lady":
		g.quest_events["envoy_next"] = g.t + ENVOY_COOLDOWN


## Every frame: Player Y's 40 s, unanswered choices asked again, a ransom war that ended some other way.
static func step(g) -> void:
	for r in g.ransoms:
		if r.stage == "y" and g.t >= float(r.until):
			ransom_war(g, r)
		elif r.stage == "x" and float(r.get("reask", -1.0)) >= 0.0 and g.t >= float(r.reask):
			r.reask = -1.0
			ask_x(g, r)
		elif r.stage == "war" and not g.wars.any(func(w): return int(w.id) == int(r.war)):
			finish(g, r)


## A prisoner escaped: a ransom waiting on them is over.
static func on_escape(g, pr: Dictionary) -> void:
	for r in g.ransoms:
		if r.stage != "done" and int(r.pr.id) == int(pr.id):
			finish(g, r)


# --- peace (sessions 10 and 12): the ransom war's two endings, and Raid Reliquary / Free Prisoners in any war ---

const PEACE := ["freeprisoner", "concession", "raid", "freeall"]
const PEACE_SCORE := 50


## The extra peace buttons for war w, seen by nation o: [label, kind].
static func peace_options(g, w: Dictionary, o: int) -> Array:
	var out := []
	var foe: int = Game.foe_of(w, o)
	var r = ransom_by_id(g, int(w.get("ransom", -1)))
	if r != null:
		if o == int(r.y):
			out.append(["Free the prisoner", "freeprisoner"])
		if o == int(r.x):
			out.append(["Demand concession", "concession"])
	if g.quests_on:
		out.append(["Raid Reliquary", "raid"])
		if on(g):
			out.append(["Free Prisoners", "freeall"])
	return out


## Why nation o can't end war w with peace kind k ("" when it can); for the usual kinds, whether a ransom war allows them.
static func peace_why(g, w: Dictionary, o: int, k: String) -> String:
	var r = ransom_by_id(g, int(w.get("ransom", -1)))
	if not PEACE.has(k):
		return "" if r == null else "This war ends only at %d%% warscore: free the prisoner, or demand concession" % PEACE_SCORE
	var s: int = g.warscore(w, o)
	if s < PEACE_SCORE:
		return "Needs +%d warscore" % PEACE_SCORE
	var foe: int = Game.foe_of(w, o)
	match k:
		"freeprisoner":
			return "" if r != null and o == int(r.y) else "Not this war"
		"concession":
			return "" if r != null and o == int(r.x) else "Not this war"
		"raid":
			return "" if not Quests.items_of(g, foe).is_empty() else "They keep no relics"
		"freeall":
			return "" if not prisoners_of(g, foe).is_empty() else "They hold no prisoners"
	return ""


static func peace_tip(k: String) -> String:
	match k:
		"freeprisoner":
			return "Your prisoner comes home and the war ends in your favor."
		"concession":
			return "They concede: the war ends in your favor, and the prisoner stays yours."
		"raid":
			return "Take 1 to 4 of the relics in their Reliquaries, and peace."
		"freeall":
			return "Their prisoners become yours (envoys, generals, nobles, ladies, apprentices and merchants go home), and peace."
	return ""


## The peace's effect, before the war ends (Game.make_peace then makes it a peace with a truce).
static func special_peace(g, w: Dictionary, winner: int, terms: Dictionary) -> void:
	var loser: int = Game.foe_of(w, winner)
	var r = ransom_by_id(g, int(w.get("ransom", -1)))
	match str(terms.kind):
		"freeprisoner":
			if r != null:
				release(g, int(r.x), int(r.pr.id))
				g.seats[winner].stock.gold = int(g.seats[winner].stock.get("gold", 0)) + 1000
				Quests.popup(g, winner, "Victory", ("The noble houses appreciate us, our allies respect us, and our enemies fear us. The rescued lady's wealthy family has donated to our cause." if r.kind == "lady" else "Our %ss can safely travel knowing we have their back, their guild has donated to us." % _who(r.kind)) + "\n\n+1000 gold", "Splendid")
				finish(g, r)
		"concession":
			if r != null:
				Quests.popup(g, winner, "Victory", "Their overconfidence was their undoing. We shall keep the woman as a trophy." if r.kind == "lady" else "Their towers collapsed quicker than their armies.", "Splendid")
				finish(g, r)
		"raid":
			var loot: Array = Quests.items_of(g, loser)
			var rr := Mulberry32.from_string("%s:raid:%d" % [str(g.world.seed), int(w.id)])
			var n := mini(loot.size(), 1 + int(floor(rr.next() * 4)))
			var got := []
			for i in n:
				var pool: Array = Quests.items_of(g, loser)
				var id: String = pool[int(floor(rr.next() * pool.size()))]
				Quests.take(g, loser, id, 1)
				Quests.give(g, winner, id, null, g.capital_of(winner))
				got.append(Quests.item_name(id))
			Quests.tell(g, winner, "You raid their Reliquary: " + ", ".join(got) + ".")
			Quests.tell(g, loser, "The %s raided your Reliquary: %s." % [g.player_info(winner).name, ", ".join(got)], true)
		"freeall":
			var freed := []
			for pr in prisoners_of(g, loser).duplicate():
				release(g, loser, int(pr.id))
				if NOTABLE.has(str(pr.kind)):
					freed.append("%s (home)" % pr.name)
					on_escape(g, pr)
				else:
					jail(g, winner, pr)
					freed.append(str(pr.name))
			Quests.tell(g, winner, "You free their prisoners: " + ", ".join(freed) + ".")
