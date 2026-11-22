class_name Art
extends RefCounted
## Images exported from the web game (assets/art/<category>/<race>/, see docs/NAMING.md). Each comes with its anchor
## (ax, ay: the pixel the game places on the spot) and scale (image pixels per world unit) from manifest.json, so
## swapping in other art (pixel art later) only means replacing the files and their manifest entries.

static var _manifests := {}
static var _cache := {}


## {tex: Texture2D, ax, ay, scale} or null when there is no such image.
static func get_sprite(category: String, race: String, file: String):
	var key := "%s/%s/%s" % [category, race, file]
	if _cache.has(key):
		return _cache[key]
	var dir := "res://assets/art/%s/%s/" % [category, race]
	if not _manifests.has(dir):
		var txt := FileAccess.get_file_as_string(dir + "manifest.json")
		_manifests[dir] = (JSON.parse_string(txt) if txt != "" else {}).get("images", {})
	var m = _manifests[dir].get(file)
	var out = null
	if m != null and ResourceLoader.exists(dir + file):
		out = {"tex": load(dir + file), "ax": float(m.get("ax", 0)), "ay": float(m.get("ay", 0)), "scale": float(m.get("scale", 1))}
	_cache[key] = out
	return out


## Draw a sprite on a CanvasItem with its anchor on `at` (world units).
static func draw(ci: CanvasItem, sp: Dictionary, at: Vector2, size_mul := 1.0, alpha := 1.0) -> void:
	var s: float = size_mul / sp.scale
	var tex: Texture2D = sp.tex
	ci.draw_set_transform(at - Vector2(sp.ax, sp.ay) * s, 0.0, Vector2(s, s))
	ci.draw_texture(tex, Vector2.ZERO, Color(1, 1, 1, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The art file name of a unit kind: "pioneer:B" -> "pioneer_b", "d-sword" -> "d_sword".
static func unit_file(kind: String, dir := "d0") -> String:
	return "%s_%s.png" % [kind.replace(":", "_").replace("-", "_").to_lower(), dir]


## The art an Armory design is drawn with. The port has art for the starting designs only, so a design made in the
## Armory shows the starting soldier of its weapon family (Rider for cavalry); a gear-accurate look comes later.
static func design_art(game, kind: String) -> String:
	if kind.begins_with("d-") or not game.DSTATS.has(kind) or game.DSTATS[kind].get("fam") == "magic":
		return kind
	var st: Dictionary = game.DSTATS[kind]
	var rc: String = str(st.get("race", "realm"))
	var A: Dictionary = DESIGN_ART.get(rc, DESIGN_ART.realm)
	if st.get("cav", false):
		return A.cav
	var base: String = A.get(st.get("fam"), A.other)
	if rc == "swamp" and _has_off(game, kind):   # a Berserker with two weapons (tools/export_art.js dualwield)
		return base + "-dw"
	return base


static func _has_off(game, kind: String) -> bool:
	var d = game.design_by_id(kind) if game.has_method("design_by_id") else null
	if d == null and game.get("nations") != null:
		for id in game.nations:
			for x in game.nations[id].get("designs", []):
				if x.id == kind:
					d = x
	return d != null and d.get("off") != null


# the starting design whose figure an Armory design borrows, by race and weapon family
const DESIGN_ART := {"realm": {"cav": "d-rider", "pole": "d-spear", "blunt": "d-club", "other": "d-sword"},
	"swamp": {"cav": "d-sw-ogre", "pole": "d-sw-spear", "blunt": "d-sw-club", "other": "d-sw-axe"},
	"wood": {"cav": "d-wd-champ", "pole": "d-wd-spear", "blunt": "d-wd-club", "other": "d-wd-sword"}}
## the player's race: whose icons the interface shows (set when a game starts)
static var player_race := "realm"


## A sprite from a race's folder, else the Realmlings' (the races share what they don't draw differently).
static func race_sprite(category: String, race: String, file: String):
	if race != "realm":
		var sp = get_sprite(category, race, file)
		if sp != null:
			return sp
	return get_sprite(category, "realm", file)


static var _flag_cache := {}

## A nation's flag image: its color with its emblem (web: v78.js ownerFlag / features.js flagURL); null if none.
static func nation_flag(game, o: int):
	var col := str(game.player_info(o).color).trim_prefix("#").to_lower()
	var em := "swords"
	if o == Game.ME:
		em = str(game.my_nation.get("emblem", "crown")) if game is Game else str(GameData.c("NATION").get("emblem", "crown"))
	elif game.nations.has(o):
		em = str(game.nations[o].get("emblem", "swords"))
	var key := col + "_" + em
	if not _flag_cache.has(key):
		var sp = get_sprite("flags", "nations", "flag_%s.png" % key)
		if sp == null:   # an emblem no longer drawn (an older save): the crown
			sp = get_sprite("flags", "nations", "flag_%s_crown.png" % col)
		_flag_cache[key] = sp.tex if sp else null
	return _flag_cache[key]
