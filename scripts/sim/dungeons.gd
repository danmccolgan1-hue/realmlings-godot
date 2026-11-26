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
static func escaped(g, o: int, pr: Dictionary) -> void:
	if g.has_method("prisoner_escaped"):
		g.call("prisoner_escaped", o, pr)


## A Dungeon is gone (torn down, dismantled, shaken down, cut from a captured province): its prisoners are Detained
## by the nation that held them.
static func lost(g, p: int, list: Array) -> void:
	var o: int = g.nation_of(p)
	for e in list:
		if e is Dictionary and e.get("type") == DUNGEON:
			for pr in held_in(e).duplicate():
				g.detained.append({"owner": o, "prisoner": pr, "cycles": 0})
			held_in(e).clear()
