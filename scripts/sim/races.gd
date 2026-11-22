class_name Races
extends RefCounted
## The three races' names and texts on one game's own copies of the tables (web: swamp.js applyRace + wood.js
## applyRace / applyWoodText). Rules only; never draws. Realmlings keep the exported texts as they are.

const NAME := {"realm": "Realmlings", "swamp": "Swamplings", "wood": "Woodlings"}   # web: swamp.js RACE_NAME
const HOME := {"realm": "grassland", "swamp": "swamp", "wood": "forest"}         # web: game.js setupGame homeTer
const FOOTMAN := {"realm": "d-sword", "swamp": "d-sw-axe", "wood": "d-wd-sword"}  # web: equip.js footmanOf
# The flags each race can fly (the web game's eight emblems trimmed to four, plus each race's own; drawn by
# tools/make_flags.py)
const EMBLEMS := {
	"realm": ["crown", "shield", "swords", "eagle", "fleur", "fist", "heart", "rose"],
	"swamp": ["crown", "shield", "swords", "eagle", "flame", "bleedeye", "beetle", "claw", "tooth", "skull", "axes", "pyramid"],
	"wood": ["crown", "shield", "swords", "eagle", "triskelion", "trinity", "spiral", "tree", "celtic", "shamrock", "dara", "shieldknot"],
}
# the emblem's color on the flag, in rows from light to deep; no black (the deepest neutral is a gray)
const EMBLEM_COLORS := [
	["#ffffff", "#faf1dc", "#e6e1d6", "#c9c6c0", "#a3a3ab", "#7c7d86"],
	["#fff6c8", "#f4d35e", "#e8b830", "#d29a1c", "#b07a20", "#8a6a3a"],
	["#ffd8c2", "#ffad7a", "#f08a3c", "#e06a2a", "#c25a2e", "#9c4a2e"],
	["#ffd1dc", "#ff9ab0", "#e86a84", "#d23b5b", "#b3263e", "#8e2a3e"],
	["#f0d7ff", "#cfaaf5", "#b07ae8", "#8a5ad0", "#6f45b0", "#583a8e"],
	["#d6ecff", "#a8d2ff", "#7ab2f2", "#4a8fe0", "#2f6fc0", "#2f5a9e"],
	["#c8f2ef", "#8ee0d8", "#5cc8c0", "#2fa8a0", "#238a85", "#2a6e6a"],
	["#dff7c8", "#b5e69a", "#8ccf6a", "#5fb04a", "#3f8f3a", "#3a6e34"],
]
const EMBLEM_NAMES := {"crown": "Crown", "shield": "Shield", "swords": "Crossed swords", "eagle": "Eagle", "fleur": "Fleur-de-lis",
	"fist": "Clenched fist", "heart": "Heart", "rose": "Rose", "flame": "Flame", "bleedeye": "Bleeding eye", "beetle": "Beetle",
	"claw": "Claw", "tooth": "Tooth", "skull": "Skull", "axes": "Crossed axes", "pyramid": "Upside-down pyramid",
	"triskelion": "Triskelion", "trinity": "Trinity knot", "spiral": "Celtic spiral", "tree": "Great tree", "celtic": "Celtic knot",
	"shamrock": "Shamrock", "dara": "Dara knot", "shieldknot": "Shield knot"}
const HOME_ARMOR := {"realm": "leather1", "swamp": "stag1", "wood": "spirit1"}
const SUPPLY_STORE := {"gold": 500, "wood": 500, "food": 500}                     # web: swamp.js (the Supply Cache)
const BANK_STORE := {"gold": 1000}
# web: equip.js — the other races' starting designs (the Armory shows only the player's race)
const BUILTIN := {
	"swamp": [["d-sw-spear", "Spear Berserker", "inf", "spear", "stag1", null], ["d-sw-axe", "Axe Berserker", "inf", "handaxe", "stag1", null],
		["d-sw-club", "Club Berserker", "inf", "club", "stag1", null], ["d-sw-ogre", "Ogre", "cav", "club", "stag1", "riding"]],
	"wood": [["d-wd-sword", "Sword Protector", "inf", "dirk", "spirit1", null], ["d-wd-spear", "Spear Protector", "inf", "spear", "spirit1", null],
		["d-wd-club", "Club Protector", "inf", "club", "spirit1", null], ["d-wd-champ", "Champion", "cav", "champsword", "ornate1", null]],
}
# web: wood.js WD_WORDS (the Woodlings' words for the Realmlings' things)
const WD_WORDS := [["Mage Towers", "Groves"], ["Mage Tower", "Grove"], ["Mage Sanctums", "Majestic Grove"], ["Mage Sanctum", "Majestic Grove"],
	["Mage Arcanums", "Magnificent Grove"], ["Mage Arcanum", "Magnificent Grove"], ["Mages", "Druids"], ["Mage", "Druid"],
	["Wayfinders", "Scouts"], ["Wayfinder", "Scout"], ["Masons", "Architects"], ["Mason", "Architect"], ["Marketplaces", "Bazaars"],
	["Marketplace", "Bazaar"], ["Temples", "Shrines"], ["Temple", "Shrine"], ["Trade Routes", "Community"]]


static func race_is(r, race: String) -> bool:
	if r is Array:
		return r.has(race)
	return r == null or r == race


# web: wood.js wdWords
static func wd_words(s):
	if not (s is String):
		return s
	for w in WD_WORDS:
		var re := RegEx.create_from_string("\\b" + w[0] + "\\b")
		s = re.sub(s, w[1], true)
	return s


## The game's own copies of the race-textured tables, then the race's names over them.
## web: swamp.js applyRace (+ the wood.js wrapper)
static func apply(g, race: String) -> void:
	g.race_of[g.ME] = race
	g.BUILD_DEFS = GameData.c("BUILD_DEFS").duplicate(true)
	g.TECHS = GameData.c("TECHS").duplicate(true)
	g.TECH_BY_ID = {}
	for x in g.TECHS:
		g.TECH_BY_ID[x.id] = x
	g.TECH_TREES = GameData.c("TECH_TREES").duplicate(true)
	g.UNIT_BASE = GameData.c("UNIT_BASE").duplicate(true)
	var UD: Dictionary = GameData.c("UNIT_DEFS")
	for k in ["pioneer:B", "mason:A", "mage:A"]:
		g.unit_defs[k].name = UD[k].name
		g.unit_defs[k].blurb = UD[k].get("blurb", "")
	var order: Array = GameData.c("BUILD_ORDER").duplicate()
	var road := true
	if race == "swamp":
		var T: Dictionary = GameData.c("SW_TEXT")
		for k in T.units:
			g.unit_defs[k].name = T.units[k][0]
			g.unit_defs[k].blurb = T.units[k][1]
		for k in T.builds:
			g.BUILD_DEFS[k].merge(T.builds[k].duplicate(true), true)
		g.BUILD_DEFS.market.erase("gives")
		g.BUILD_DEFS.bank.store = SUPPLY_STORE.duplicate()
		for k in T.techs:
			var x = g.TECH_BY_ID.get(k)
			if x != null:
				if T.techs[k][0] != null:
					x.name = T.techs[k][0]
				if T.techs[k][1] != null:
					x.blurb = T.techs[k][1]
		_reps(g, T.reps)
		for k in T.trees:
			g.TECH_TREES[k].merge(T.trees[k].duplicate(true), true)
		g.UNIT_BASE.inf.name = "Berserkers"
		g.UNIT_BASE.cav.name = "Ogres"
		order = order.filter(func(k): return k != "granary" and k != "storehouse")
		road = false
	elif race == "wood":
		var T: Dictionary = GameData.c("WD_TEXT")
		for k in T.units:
			g.unit_defs[k].name = T.units[k][0]
			g.unit_defs[k].blurb = T.units[k][1]
		for k in g.BUILD_DEFS:
			var d: Dictionary = g.BUILD_DEFS[k]
			for f in ["name", "note", "blurb"]:
				if d.get(f) != null:
					d[f] = wd_words(d[f])
			if d.get("levels") is Array:
				d.levels = d.levels.map(func(s): return wd_words(s))
			if T.builds.has(k):
				d.merge(T.builds[k].duplicate(true), true)
		for x in g.TECHS:
			if not x.get("rep", false):
				x.name = wd_words(x.name)
				x.blurb = wd_words(x.get("blurb", ""))
				var o = T.techs.get(x.id)
				if o != null:
					if o[0] != null:
						x.name = o[0]
					if o[1] != null:
						x.blurb = o[1]
		_reps(g, T.reps)
		for k in g.TECH_TREES:
			var TT: Dictionary = g.TECH_TREES[k]
			for f in ["locked", "rate"]:
				if TT.get(f) != null:
					TT[f] = wd_words(TT[f])
			if TT.get("tiers") is Array:
				TT.tiers = TT.tiers.map(func(s): return wd_words(s))
		g.UNIT_BASE.inf.name = "Protectors"
		g.UNIT_BASE.cav.name = "Champions"
		road = false
	g.BUILD_ORDER = order
	# web: swamp.js / wood.js CMD[MASON]: the buildings in order, no roads for Swamplings or Woodlings
	g.CMD = GameData.c("CMD").duplicate(true)
	var cm := [{"id": "build:outpost", "cell": 0, "key": "Q"}]
	for i in order.size():
		cm.append({"id": "build:" + order[i], "cell": i + 1, "key": ""})
	if road:
		cm.append({"id": "road", "cell": 13, "key": ""})
	cm.append({"id": "cancelbuild", "cell": 14, "key": ""})
	cm.append({"id": "dismiss", "cell": 15, "key": ""})
	g.CMD[g.MASON] = cm
	# the player's starting designs: the race's own (the Armory shows only these)
	g.designs = g.designs.filter(func(d): return not d.get("builtin", false))
	var keep: Array = g.designs
	g.designs = []
	if race == "realm":
		for d in [["d-spear", "inf", "spear"], ["d-sword", "inf", "shortsword"], ["d-club", "inf", "club"], ["d-rider", "cav", "spear"]]:
			g.designs.append({"id": d[0], "name": UD[d[0]].name, "type": d[1], "weapon": d[2], "shield": null, "armor": "leather1",
				"horse": "riding" if d[1] == "cav" else null, "builtin": true, "race": "realm"})
	for r in [race] if BUILTIN.has(race) else []:
		for d in BUILTIN[r]:
			g.designs.append({"id": d[0], "name": d[1], "type": d[2], "weapon": d[3], "shield": null, "off": null, "armor": d[4], "horse": d[5],
				"builtin": true, "race": r})
	g.designs += keep
	# Swamplings know Mushroom Farming from the start; forget the options of another race
	if g.tech.has("gov"):
		if race == "swamp" and not g.tech.gov.done.has("mushroom"):
			g.tech.gov.done.append("mushroom")
		if race != "swamp":
			g.tech.gov.done.erase("mushroom")
		for t in ["gov", "mil", "mag"]:
			var st: Dictionary = g.tech[t]
			st.opts = st.opts.filter(func(id): return g.TECH_BY_ID.has(id) and race_is(g.TECH_BY_ID[id].get("race"), race))
			if st.cur != null and not race_is(g.TECH_BY_ID[st.cur].get("race"), race):
				st.cur = null


static func _reps(g, reps: Dictionary) -> void:
	for id in reps:
		var x = g.TECH_BY_ID.get(id)
		if x != null:
			x.name = reps[id][0] + " 1"
			x.blurb = "Repeatable. " + reps[id][1]
