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


## draw, stretched (sc: x and y) and turned by rot about the art's anchor (0.19: monsters on the move).
static func draw_xf(ci: CanvasItem, sp: Dictionary, at: Vector2, sc: Vector2, rot := 0.0, alpha := 1.0) -> void:
	var s: Vector2 = sc / float(sp.scale)
	var tex: Texture2D = sp.tex
	ci.draw_set_transform(at, rot, s)
	ci.draw_texture(tex, -Vector2(sp.ax, sp.ay), Color(1, 1, 1, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- armor on the map (0.19): the soldiers' art is drawn in leather; chain and plate (and the other races' twins)
# turn its leather browns to steel, darker for chain, brighter for plate ---

static var _armor_cache := {}

## How heavy a troop kind's armor looks: 0 leather, 1 chain, 2 plate.
static func armor_look(game, kind: String) -> int:
	if game == null or not game.DSTATS.has(kind):
		return 0
	return int(game.DSTATS[kind].get("look", 0))


## sp with its leather turned to the armor of `look` (sp itself for leather); made once per picture and kept.
static func armored(sp, look: int):
	if sp == null or look <= 0:
		return sp
	var tex: Texture2D = sp.tex
	var key := "%s#%d" % [tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id()), look]
	if _armor_cache.has(key):
		return _armor_cache[key]
	var img: Image = tex.get_image()
	if img == null:
		_armor_cache[key] = sp
		return sp
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.04:
				continue
			if c.h >= 0.02 and c.h <= 0.13 and c.s >= 0.38 and c.v <= 0.72:   # leather browns (not skin, not cloth)
				var n := Color.from_hsv(0.6, 0.10, minf(1.0, c.v * 1.15 + 0.05), c.a) if look == 1 else Color.from_hsv(0.58, 0.07, minf(1.0, c.v * 1.3 + 0.1), c.a)
				img.set_pixel(x, y, n)
	var out: Dictionary = sp.duplicate()
	out.tex = ImageTexture.create_from_image(img)
	_armor_cache[key] = out
	return out


## The art file name of a unit kind: "pioneer:B" -> "pioneer_b", "d-sword" -> "d_sword".
static func unit_file(kind: String, dir := "d0") -> String:
	return "%s_%s.png" % [kind.replace(":", "_").replace("-", "_").to_lower(), dir]


## The art an Armory design is drawn with. The port has art for the starting designs only, so a design made in the
## Armory shows the starting soldier of its weapon family (Rider for cavalry). Monsters ("m-") keep their own kind,
## so they are drawn as themselves (0.19: Zombies in a battle were drawn as club infantry).
static func design_art(game, kind: String) -> String:
	if kind.begins_with("d-") or kind.begins_with("m-") or not game.DSTATS.has(kind) or game.DSTATS[kind].get("fam") == "magic":
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
	var col := str(game.player_info(o).color)
	var em := "swords"
	var sec := "#faf1dc"
	if (game is Game and game.seats.has(o)) or (not game is Game and o == Game.LOCAL):   # a human nation's own flag
		var nat: Dictionary = game.seats[o].my_nation if game is Game else GameData.c("NATION")
		em = str(nat.get("emblem", "crown"))
		sec = str(nat.get("secondary", sec))
	elif game.nations.has(o):
		em = str(game.nations[o].get("emblem", "swords"))
		sec = str(game.nations[o].get("secondary", sec))
	return flag_texture(col, em, sec)


## A flag put together: the cloth in the nation's color, the emblem filled with the emblem color
## (tools/make_flags.py draws each emblem filled black and filled white: fill = black + (white - black) * color).
static func flag_texture(col: String, em: String, sec: String):
	var c := col.trim_prefix("#").to_lower()
	var key := "%s_%s_%s" % [c, em, sec.trim_prefix("#").to_lower()]
	if _flag_cache.has(key):
		return _flag_cache[key]
	var cloth = get_sprite("flags", "nations", "cloth_%s.png" % c)
	var k = get_sprite("flags", "nations", "emblem_%s_k.png" % em)
	var w = get_sprite("flags", "nations", "emblem_%s_w.png" % em)
	if k == null or w == null:   # an emblem no longer drawn (an older save): the crown
		k = get_sprite("flags", "nations", "emblem_crown_k.png")
		w = get_sprite("flags", "nations", "emblem_crown_w.png")
	if cloth == null or k == null or w == null:
		_flag_cache[key] = null
		return null
	var img: Image = cloth.tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var ik: Image = k.tex.get_image()
	ik.convert(Image.FORMAT_RGBA8)
	var iw: Image = w.tex.get_image()
	iw.convert(Image.FORMAT_RGBA8)
	var S := Color(sec)
	var em_img := Image.create(ik.get_width(), ik.get_height(), false, Image.FORMAT_RGBA8)
	for y in ik.get_height():
		for x in ik.get_width():
			var a := ik.get_pixel(x, y)
			if a.a <= 0.0:
				continue
			var b := iw.get_pixel(x, y)
			em_img.set_pixel(x, y, Color(a.r + (b.r - a.r) * S.r, a.g + (b.g - a.g) * S.g, a.b + (b.b - a.b) * S.b, a.a))
	img.blend_rect(em_img, Rect2i(Vector2i.ZERO, em_img.get_size()), Vector2i.ZERO)
	var tex := ImageTexture.create_from_image(img)
	_flag_cache[key] = tex
	return tex
