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
static func draw(ci: CanvasItem, sp: Dictionary, at: Vector2, size_mul := 1.0) -> void:
	var s: float = size_mul / sp.scale
	var tex: Texture2D = sp.tex
	ci.draw_set_transform(at - Vector2(sp.ax, sp.ay) * s, 0.0, Vector2(s, s))
	ci.draw_texture(tex, Vector2.ZERO)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The art file name of a unit kind: "pioneer:B" -> "pioneer_b", "d-sword" -> "d_sword".
static func unit_file(kind: String, dir := "d0") -> String:
	return "%s_%s.png" % [kind.replace(":", "_").replace("-", "_").to_lower(), dir]


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
		_flag_cache[key] = sp.tex if sp else null
	return _flag_cache[key]
