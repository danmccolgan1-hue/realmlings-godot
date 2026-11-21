class_name StartScreen
extends Control
## The title card over the island: the main menu (a little parade of your folk, music and sound, Continue, New Game,
## Tutorial, Multiplayer, Patch Notes, Load a save file, Recorded games, Settings, How to play), the Tutorial and
## Multiplayer screens, and the New Game page (seed, nation name, race, leader, start position, color, flag, island
## shape and sliders, the 7 opponent slots). Choices are remembered between games.
## web: game_shell.html #menu; menu.js; features.js renderNationPicker, randomNationName; v105.js renderLeaderPick

const INK := Color("#1d1a22")
const MUTED := Color("#5a6475")
const CARD := Color("#f3e4c4")
const CHIP_HI := Color("#faf1dc")
const BLUE := Color("#4a9be8")
const PURPLE := Color("#8a6fd0")
const SUN := Color("#ffc93c")
const SLOT_BG := {"closed": Color("#e3e6ec"), "easy": Color("#dff3e0"), "moderate": Color("#fff2c9"), "difficult": Color("#ffd9d2")}
const SLOT_TEXT := {"closed": "Closed", "easy": "Easy", "moderate": "Moderate", "difficult": "Difficult"}
const SLOT_CYCLE := ["closed", "easy", "moderate", "difficult"]
const SHAPES := [["classic", "Classic", "The island you know"], ["crescent", "Half-moon", "A half-moon arch"], ["ring", "Ring", "A ring of land around a great lake"], ["random", "Random", "Any outline, with forests, deserts and swamps scattered anywhere"]]
const TREE_WORDS := ["Classic", "More", "Many", "Lots", "Dense"]
const PARADE := ["pioneer:B", "mason:A", "d-sword", "d-spear", "d-rider", "mage:A"]

var main                    # the scene's entry node: starts games, loads saves, opens windows
var card: PanelContainer
var screens := {}           # name -> VBoxContainer
var opts := {}              # the New Game choices (Settings.menu)
var seed_edit: LineEdit
var nation_edit: LineEdit
var setup_box: VBoxContainer
var leader_info: RichTextLabel
var how_text: RichTextLabel
var cont_btn: Button
var status: Label
var start_btn: Button
var parade: Control


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	opts = _load_opts()
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _sb(CARD, 2, 4, 22))
	add_child(card)
	for n in ["main", "tut", "multi", "setup"]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 12)
		screens[n] = v
	_build_main()
	_build_tut()
	_build_multi()
	_build_setup()
	show_screen("main")


func _process(_dt: float) -> void:
	# the card stays in the middle of the screen
	card.reset_size()
	var vs := get_viewport_rect().size
	card.position = ((vs - card.size) / 2).floor()
	if parade and parade.is_visible_in_tree():
		parade.queue_redraw()


func show_screen(n: String) -> void:
	if card.get_child_count():
		card.remove_child(card.get_child(0))
	card.add_child(screens[n])
	if n == "main" and cont_btn:
		cont_btn.visible = FileAccess.file_exists(main.AUTOSAVE)
	if n == "setup":
		_refresh_setup()


# --- remembered choices (web: localStorage realm-map, realm-slots, realm-start, realm-nation, realm-leader) ---

func _load_opts() -> Dictionary:
	var NAT: Dictionary = GameData.c("NATION")
	var d := {"seed": random_seed(), "nation": {"name": NAT.name, "color": NAT.color, "emblem": NAT.emblem}, "leader": "random", "race": "realm", "races": ["random", "random", "random", "random", "random", "random", "random"], "start": "center", "practice": false,
		"map": {"shape": "classic", "pens": 2, "coves": 2, "trees": 0}, "slots": ["easy", "easy", "moderate", "closed", "closed", "closed", "closed"]}
	var m: Dictionary = Settings.menu
	for k in ["nation", "leader", "race", "races", "start", "practice", "map", "slots"]:
		if m.has(k) and typeof(m[k]) == typeof(d[k]):
			d[k] = m[k]
	if d.races.size() != 7:
		d.races = ["random", "random", "random", "random", "random", "random", "random"]
	if d.slots.size() != 7:
		d.slots = ["easy", "easy", "moderate", "closed", "closed", "closed", "closed"]
	return d


func _save_opts() -> void:
	var m := opts.duplicate(true)
	m.erase("seed")
	Settings.menu = m
	Settings.save_all()


static func random_seed() -> String:
	var W: Array = GameData.c("MENU_WORDS")
	return "%s-%s-%d" % [W.pick_random(), W.pick_random(), randi_range(10, 99)]


## web: features.js randomNationName (the Realmlings' style)
static func random_nation_name() -> String:
	var P: Dictionary = GameData.c("NAME_PARTS").realm
	return "%s of %s" % [P.titles.pick_random(), P.places.pick_random()]


# --- pieces ---

static func _sb(bg: Color, border := 2, radius := 4, pad := 6, bc := INK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = bc
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func _lbl(t: String, sz: int, c := INK) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	return l


## A big menu button (web: .menu-start): blue for the main action, purple for the others.
func _big(text: String, col: Color, f: Callable, small := "", disabled := false) -> Button:
	var b := Button.new()
	b.text = text + (("\n" + small) if small != "" else "")
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 58 if small == "" else 72)
	b.add_theme_font_size_override("font_size", 26 if small == "" else 22)
	var base := col if not disabled else col.lerp(Color("#cfcfd6"), 0.6)
	b.add_theme_stylebox_override("normal", _sb(base, 2, 2, 6))
	b.add_theme_stylebox_override("hover", _sb(base.lightened(0.12), 2, 2, 6))
	b.add_theme_stylebox_override("pressed", _sb(base.darkened(0.1), 2, 2, 6))
	b.add_theme_stylebox_override("disabled", _sb(base, 2, 2, 6))
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(st, Color.WHITE if not disabled else Color(1, 1, 1, 0.8))
	b.add_theme_color_override("font_outline_color", Color(INK, 0.45))
	b.add_theme_constant_override("outline_size", 3)
	b.disabled = disabled
	if f.is_valid():
		b.pressed.connect(f)
	return b


## An underlined text link (web: .menu-how)
func _link(text: String, f: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 18)
	for st in ["font_color", "font_pressed_color"]:
		b.add_theme_color_override(st, Color("#4a4f5c"))
	b.add_theme_color_override("font_hover_color", INK)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(f)
	b.draw.connect(func():
		var w := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var x0 := (b.size.x - w) / 2
		b.draw_line(Vector2(x0, b.size.y - 7), Vector2(x0 + w, b.size.y - 7), Color("#4a4f5c"), 1.5))
	return b


## A pill switch with its words (web: .menu-tog)
func _tog(text: String, on: bool, f: Callable, disabled := false, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.disabled = disabled
	b.add_theme_font_size_override("font_size", 17)
	var bg := CHIP_HI if not disabled else Color("#ebe6da")
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := _sb(bg if st != "hover" else Color("#fff7d9"), 1, 2, 6)
		sb.content_margin_left = 50
		sb.content_margin_right = 10
		b.add_theme_stylebox_override(st, sb)
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, INK)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.4))
	b.draw.connect(func():
		var r := Rect2(Vector2(8, b.size.y / 2 - 9), Vector2(34, 18))
		var sb := _sb(Color("#3e9b4f") if on else Color("#d9dce3"), 1, 9, 0)
		b.draw_style_box(sb, r)
		b.draw_circle(Vector2(r.position.x + (25.0 if on else 9.0), r.get_center().y), 6.5, Color.WHITE)
		b.draw_arc(Vector2(r.position.x + (25.0 if on else 9.0), r.get_center().y), 6.5, 0, TAU, 20, Color(INK, 0.5), 1.0, true))
	if f.is_valid():
		b.pressed.connect(f)
	return b


## A small die drawn in code (the 🎲 button)
func _dice(f: Callable, tip: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(42, 38)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, _sb(CHIP_HI if st != "hover" else Color("#fff7d9"), 1, 2, 2))
	b.draw.connect(func():
		var c := b.size / 2
		var face := Rect2(c - Vector2(11, 11), Vector2(22, 22))
		b.draw_style_box(_sb(Color.WHITE, 2, 4, 0), face)
		for d in [Vector2(-5, -5), Vector2(5, 5), Vector2(0, 0), Vector2(5, -5), Vector2(-5, 5)]:
			b.draw_circle(c + d, 2.0, Color("#c7362b")))
	b.pressed.connect(f)
	return b


## A labelled row of the New Game page (web: .menu-row)
func _row(label: String, content: Control, parent: Container) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := _lbl(label.to_upper(), 13, MUTED)
	l.custom_minimum_size = Vector2(130, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(content)
	parent.add_child(h)


# --- the main menu ---

func _build_main() -> void:
	var v: VBoxContainer = screens.main
	v.custom_minimum_size = Vector2(500, 0)
	var title := _lbl("Realmlings", 76, Color("#f2b632"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color("#7a4a12"))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_shadow_color", Color(INK, 0.5))
	title.add_theme_constant_override("shadow_offset_y", 4)
	v.add_child(title)
	var tag := _lbl("Explore, settle, research and defend a little fantasy realm.", 17, Color("#4a4f5c"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	parade = Control.new()
	parade.custom_minimum_size = Vector2(460, 104)
	parade.draw.connect(_draw_parade)
	v.add_child(parade)
	for a in [["Music", "music_on", "music_vol"], ["Sound effects", "sfx_on", "sfx_vol"]]:
		_audio_row(v, a[0], a[1], a[2])
	cont_btn = _big("Continue", Color("#3e9b4f"), func(): main.load_from(main.AUTOSAVE), "your last autosave")
	v.add_child(cont_btn)
	v.add_child(_big("New Game", BLUE, func(): show_screen("setup")))
	v.add_child(_big("Tutorial", PURPLE, func(): show_screen("tut")))
	v.add_child(_big("Multiplayer", PURPLE, func(): show_screen("multi")))
	v.add_child(_big("Patch Notes", PURPLE, func(): main.patch_notes.open()))
	var links := HFlowContainer.new()
	links.alignment = FlowContainer.ALIGNMENT_CENTER
	links.add_theme_constant_override("h_separation", 18)
	links.add_child(_link("Load a save file", func(): main.import_save(), "Load a game exported from the menu (a .realmsave file)"))
	links.add_child(_link("Recorded games", func(): main.recordings.open()))
	links.add_child(_link("Settings", func(): main.menu_settings.toggle(null)))
	links.add_child(_link("How to play", func(): how_text.visible = not how_text.visible))
	v.add_child(links)
	how_text = RichTextLabel.new()
	how_text.bbcode_enabled = true
	how_text.fit_content = true
	how_text.custom_minimum_size = Vector2(480, 0)
	how_text.add_theme_color_override("default_color", INK)
	how_text.add_theme_font_size_override("normal_font_size", 15)
	how_text.text = "\n".join(GameData.c("HOWTO_SHORT").map(func(s): return "• " + s))
	how_text.hide()
	v.add_child(how_text)
	status = _lbl("", 15, Color("#4a4f5c"))
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(status)
	var foot := _lbl("Version %s · follows the web game %s · the same seed always makes the same island" % [ProjectSettings.get_setting("application/config/version"), GameData.c("GAME_VERSION")], 13, MUTED)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(foot)


func _audio_row(v: VBoxContainer, label: String, on_key: String, vol_key: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := _lbl(label.to_upper(), 13, MUTED)
	l.custom_minimum_size = Vector2(130, 0)
	h.add_child(l)
	var holder := HBoxContainer.new()
	h.add_child(holder)
	var rebuild := func(): pass
	rebuild = func():
		UiKit.clear(holder)
		holder.add_child(_tog("On" if Settings.audio(on_key) else "Off", Settings.audio(on_key), func():
			Settings.set_audio(on_key, not Settings.audio(on_key))
			rebuild.call(), false, "Sound and music come in a later batch; this is remembered for then"))
	rebuild.call()
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.value = Settings.audio(vol_key) * 100
	s.custom_minimum_size = Vector2(120, 0)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(x): Settings.set_audio(vol_key, x / 100.0))
	h.add_child(s)
	v.add_child(h)


## A little parade of the realm's folk, hopping in place. web: menu.js menuParade
func _draw_parade() -> void:
	var w := parade.size.x
	var h := parade.size.y
	var t := Time.get_ticks_msec() / 1000.0
	for i in PARADE.size():
		var x := w * (i + 0.5) / PARADE.size()
		var hop := -absf(sin(t * 6 + i * 1.1)) * 6
		var pts := PackedVector2Array()
		for k in 25:
			var a := TAU * k / 24
			pts.append(Vector2(x + cos(a) * 30, h - 10 + sin(a) * 8))
		parade.draw_colored_polygon(pts, Color(INK, 0.18))
		var sp = Art.get_sprite("units", "realm", Art.unit_file(PARADE[i], MapView._dir(0.6 if i % 2 else -0.6)))
		if sp == null:
			sp = Art.get_sprite("units", "realm", Art.unit_file(PARADE[i], "d0"))
		if sp:
			Art.draw(parade, sp, Vector2(x, h - 10 + hop), (0.82 if PARADE[i] == "d-rider" else 1.05) * 1.6)


# --- Tutorial and Multiplayer ---

func _sub_head(v: VBoxContainer, title: String) -> void:
	var h := HBoxContainer.new()
	var back := Button.new()
	back.text = "← Back"
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 16)
	for st in ["normal", "hover", "pressed"]:
		back.add_theme_stylebox_override(st, _sb(CHIP_HI if st != "hover" else Color("#fff7d9"), 2, 2, 6))
	back.add_theme_color_override("font_color", INK)
	back.add_theme_color_override("font_hover_color", INK)
	back.pressed.connect(func(): show_screen("main"))
	h.add_child(back)
	var t := _lbl(title, 34, Color("#f2b632"))
	t.add_theme_color_override("font_outline_color", Color("#7a4a12"))
	t.add_theme_constant_override("outline_size", 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(back.get_combined_minimum_size().x, 0)
	h.add_child(pad)
	v.add_child(h)


func _build_tut() -> void:
	var v: VBoxContainer = screens.tut
	v.custom_minimum_size = Vector2(500, 0)
	_sub_head(v, "Tutorial")
	v.add_child(_big("Basic Tutorial", BLUE, func(): main.start_tutorial(), "Explore, expand and train your first army"))
	v.add_child(_big("Combat Tutorial", PURPLE, Callable(), "Coming later", true))


func _build_multi() -> void:
	var v: VBoxContainer = screens.multi
	v.custom_minimum_size = Vector2(500, 0)
	_sub_head(v, "Multiplayer")
	var l := _lbl("Coming Soon", 30, MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, 120)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(l)


# --- the New Game page ---

func _build_setup() -> void:
	var v: VBoxContainer = screens.setup
	v.custom_minimum_size = Vector2(760, 0)
	v.add_theme_constant_override("separation", 8)
	_sub_head(v, "New Game")
	# seed and nation name, each with its dice
	var sh := HBoxContainer.new()
	seed_edit = LineEdit.new()
	seed_edit.text = opts.seed
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.add_theme_font_size_override("font_size", 18)
	seed_edit.text_changed.connect(func(t): opts.seed = t)
	seed_edit.text_submitted.connect(func(_t): start_game())
	_style_edit(seed_edit)
	sh.add_child(seed_edit)
	sh.add_child(_dice(func():
		opts.seed = random_seed()
		seed_edit.text = opts.seed, "Random seed"))
	_row("Map seed", sh, v)
	var nh := HBoxContainer.new()
	nation_edit = LineEdit.new()
	nation_edit.text = opts.nation.name
	nation_edit.max_length = 24
	nation_edit.placeholder_text = "My Realm"
	nation_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nation_edit.add_theme_font_size_override("font_size", 18)
	nation_edit.text_changed.connect(func(t):
		opts.nation.name = t.strip_edges().left(24)
		_save_opts())
	_style_edit(nation_edit)
	nh.add_child(nation_edit)
	nh.add_child(_dice(func():
		var n := random_nation_name()
		var k := 0
		while (n.length() > 24 or n == nation_edit.text) and k < 50:
			n = random_nation_name()
			k += 1
		nation_edit.text = n
		opts.nation.name = n
		_save_opts(), "Random nation name"))
	_row("Nation", nh, v)
	setup_box = VBoxContainer.new()
	setup_box.add_theme_constant_override("separation", 8)
	v.add_child(setup_box)
	start_btn = _big("Start game", BLUE, start_game)
	start_btn.custom_minimum_size = Vector2(0, 62)
	v.add_child(start_btn)
	var foot := _lbl("The same seed always makes the same island", 13, MUTED)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(foot)


func _style_edit(e: LineEdit) -> void:
	e.add_theme_stylebox_override("normal", _sb(CHIP_HI, 1, 2, 8))
	e.add_theme_stylebox_override("focus", _sb(Color("#fffaf0"), 2, 2, 8, Color("#e8a817")))
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", Color(INK, 0.4))
	e.add_theme_color_override("caret_color", INK)


func _pick(k: String, val) -> void:
	opts[k] = val
	_save_opts()
	_refresh_setup()


func _pick_race(r: String) -> void:
	if opts.get("race", "realm") != r:
		opts.leader = "random"
	opts.race = r
	_save_opts()
	_refresh_setup()


func _refresh_setup() -> void:
	UiKit.clear(setup_box)
	var practice: bool = opts.practice
	# race (web: menu.js #mRace): the leader list follows it
	var race := HBoxContainer.new()
	race.add_theme_constant_override("separation", 8)
	for r in [["realm", "Realmlings", "Small, cheerful and sturdy: they start on grassland"], ["swamp", "Swamplings", "Fierce bog folk: they start in a swamp, fight and move better there, and raise Ogres"],
			["wood", "Woodlings", "Tall forest folk: they start in a forest, are tougher and quicker there, and need no roads"]]:
		race.add_child(_tog(r[1], opts.get("race", "realm") == r[0], _pick_race.bind(r[0]), false, r[2]))
	_row("Race", race, setup_box)
	_row("Leader", _leader_pick(), setup_box)
	var mp := HBoxContainer.new()
	mp.add_theme_constant_override("separation", 8)
	mp.add_child(_tog("Full island", not practice, _pick.bind("practice", false), false, "Computer nations, wars and diplomacy"))
	mp.add_child(_tog("Practice island", practice, _pick.bind("practice", true), false, "10 provinces, just you: explore, settle and try things out"))
	_row("Map", mp, setup_box)
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", 8)
	for s in [["center", "Center"], ["edge", "Edge"], ["random", "Random"]]:
		sp.add_child(_tog(s[1], opts.start == s[0], _pick.bind("start", s[0]), practice, "Where your capital starts: %s always start on %s" % [Races.NAME[opts.get("race", "realm")], Races.HOME[opts.get("race", "realm")]]))
	_row("Start position", sp, setup_box)
	# color and flag
	var NC: Array = GameData.c("NATION_COLORS")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	for i in NC.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(34, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Color %d" % (i + 1)
		var on: bool = int(opts.nation.color) == i
		var c := Color(NC[i][0])
		for st in ["normal", "hover", "pressed"]:
			var sb := _sb(c, 3 if on else 1, 17, 0, SUN if on else INK)
			b.add_theme_stylebox_override(st, sb)
		var ci := i
		b.pressed.connect(func():
			opts.nation.color = ci
			_save_opts()
			_refresh_setup())
		cols.add_child(b)
	_row("Color", cols, setup_box)
	var flags := HBoxContainer.new()
	flags.add_theme_constant_override("separation", 8)
	var col_hex := str(NC[int(opts.nation.color)][0]).trim_prefix("#").to_lower()
	var FN: Dictionary = GameData.c("FLAG_NAMES")
	for em in GameData.c("FLAG_EMBLEMS"):
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = FN.get(em, em)
		var on: bool = opts.nation.emblem == em
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, _sb(Color("#fff2c2") if on else Color(0, 0, 0, 0), 3 if on else 0, 4, 3, SUN))
		var sp2 = Art.get_sprite("flags", "nations", "flag_%s_%s.png" % [col_hex, em])
		if sp2:
			var r := TextureRect.new()
			r.texture = sp2.tex
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(r)
			r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
		var e2: String = em
		b.pressed.connect(func():
			opts.nation.emblem = e2
			_save_opts()
			_refresh_setup())
		flags.add_child(b)
	_row("Flag", flags, setup_box)
	# the island
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 8)
	for s in SHAPES:
		sh.add_child(_tog(s[1], opts.map.shape == s[0], func():
			opts.map.shape = s[0]
			_save_opts()
			_refresh_setup(), practice, s[2]))
	_row("Island", sh, setup_box)
	for sl in [["Peninsulas", "pens", 5], ["Coves", "coves", 5], ["Trees", "trees", 4]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var s := HSlider.new()
		s.min_value = 0
		s.max_value = sl[2]
		s.step = 1
		s.value = opts.map[sl[1]]
		s.editable = not practice
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var val := _lbl(TREE_WORDS[int(s.value)] if sl[1] == "trees" else str(int(s.value)), 17)
		val.custom_minimum_size = Vector2(70, 0)
		var key: String = sl[1]
		s.value_changed.connect(func(x):
			opts.map[key] = int(x)
			val.text = TREE_WORDS[int(x)] if key == "trees" else str(int(x))
			_save_opts())
		h.add_child(s)
		h.add_child(val)
		_row(sl[0], h, setup_box)
	# the opponents
	var ob := VBoxContainer.new()
	ob.add_theme_constant_override("separation", 6)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	for i in 7:
		var d: String = opts.slots[i]
		var wrap := HBoxContainer.new()
		wrap.add_theme_constant_override("separation", 3)
		var b := Button.new()
		b.text = "%d   %s" % [i + 1, SLOT_TEXT[d]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(130, 32)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = practice
		b.tooltip_text = "Opponent %d: %s. Click to change (right-click goes back)" % [i + 1, SLOT_TEXT[d]]
		b.add_theme_font_size_override("font_size", 15)
		for st in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(st, _sb(SLOT_BG[d] if st != "hover" else SLOT_BG[d].lightened(0.3), 1, 2, 4))
		for st in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(st, INK if d != "closed" else MUTED)
		b.add_theme_color_override("font_disabled_color", Color(INK, 0.35))
		var si := i
		b.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and not practice:
				var k := SLOT_CYCLE.find(opts.slots[si])
				opts.slots[si] = SLOT_CYCLE[(k + (1 if ev.button_index == MOUSE_BUTTON_LEFT else SLOT_CYCLE.size() - 1)) % SLOT_CYCLE.size()]
				_save_opts()
				_refresh_setup.call_deferred()
				b.accept_event())
		wrap.add_child(b)
		# the opponent's race: Realmling, Swampling, Woodling or ? (random); web: menu.js slot race buttons
		var rb := Button.new()
		var sr: String = str(opts.races[si])
		rb.text = {"realm": "R", "swamp": "S", "wood": "W"}.get(sr, "?")
		rb.disabled = d == "closed" or practice
		rb.focus_mode = Control.FOCUS_NONE
		rb.custom_minimum_size = Vector2(26, 32)
		rb.tooltip_text = {"realm": "Realmlings", "swamp": "Swamplings", "wood": "Woodlings"}.get(sr, "A random race") + " · click to change"
		rb.add_theme_font_size_override("font_size", 13)
		for st in ["normal", "hover", "pressed", "disabled"]:
			rb.add_theme_stylebox_override(st, _sb({"realm": Color("#e9e2f6"), "swamp": Color("#dcebc8"), "wood": Color("#d6eedf")}.get(sr, Color("#f3ead4")) if d != "closed" else Color("#eeeeee"), 1, 2, 2))
		rb.add_theme_color_override("font_color", INK)
		rb.add_theme_color_override("font_disabled_color", Color(INK, 0.6 if d != "closed" else 0.25))
		var ri: int = si
		rb.pressed.connect(func():
			var cyc := ["realm", "swamp", "wood", "random"]
			opts.races[ri] = cyc[(cyc.find(str(opts.races[ri])) + 1) % cyc.size()]
			_save_opts()
			_refresh_setup.call_deferred())
		wrap.add_child(rb)
		grid.add_child(wrap)
	ob.add_child(grid)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 6)
	for q in [["easy", "All Easy"], ["moderate", "All Moderate"], ["difficult", "All Difficult"], ["closed", "Close all"]]:
		var b := Button.new()
		b.text = q[1]
		b.disabled = practice
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		for st in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(st, _sb(CHIP_HI if st != "hover" else Color("#fff7d9"), 1, 2, 4))
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_disabled_color", Color(INK, 0.35))
		var qq: String = q[0]
		b.pressed.connect(func():
			opts.slots = [qq, qq, qq, qq, qq, qq, qq]
			_save_opts()
			_refresh_setup())
		quick.add_child(b)
	ob.add_child(quick)
	var n: int = opts.slots.filter(func(x): return x != "closed").size()
	_row("Opponents\n%s" % ("" if practice else "%d nation%s" % [n + 1, "s" if n else ""]), ob, setup_box)


## Portrait cards for every Realmling leader, and Random; the chosen one's start, bonus, likes and dislikes.
## web: v105.js renderLeaderPick, leaderStartText, leaderLikeText (+ v106.js)
func _leader_pick() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var L: Dictionary = GameData.c("LEADERS")
	var ids := ["random"]
	for id in L:
		if L[id].race == opts.get("race", "realm"):
			ids.append(id)
	for id in ids:
		var on: bool = opts.leader == id
		var b := Button.new()
		b.custom_minimum_size = Vector2(66, 104)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "A random %s leader" % CountryWindow.RACE_WORD[opts.get("race", "realm")] if id == "random" else str(L[id].full)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, _sb(SUN if on else (Color("#fff7d9") if st == "hover" else CHIP_HI), 2, 2, 3))
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", -2)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(c)
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
		if id == "random":
			var q := _lbl("?", 34, MUTED)
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q.custom_minimum_size = Vector2(56, 66)
			q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q.add_theme_stylebox_override("normal", _sb(Color.WHITE, 1, 0, 0))
			c.add_child(q)
		else:
			var r := TextureRect.new()
			var lp := "res://assets/art/icons/%s/leader_%s.png" % [L[id].race, id]
			r.texture = load(lp) if ResourceLoader.exists(lp) else null
			r.custom_minimum_size = Vector2(56, 66)
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.add_child(r)
		var nl := _lbl("Random" if id == "random" else str(L[id].name), 13)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(nl)
		if id != "random":
			var tl := _lbl(str(L[id].title), 9, MUTED)
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tl.clip_text = true
			c.add_child(tl)
		for k in c.get_children():
			k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lid: String = id
		b.pressed.connect(_pick.bind("leader", lid))
		row.add_child(b)
	v.add_child(row)
	leader_info = RichTextLabel.new()
	leader_info.bbcode_enabled = true
	leader_info.fit_content = true
	leader_info.custom_minimum_size = Vector2(590, 0)
	leader_info.add_theme_color_override("default_color", INK)
	leader_info.add_theme_font_size_override("normal_font_size", 14)
	leader_info.add_theme_font_size_override("bold_font_size", 15)
	var cur = L.get(opts.leader)
	if cur == null:
		leader_info.text = "A random " + CountryWindow.RACE_WORD[opts.get("race", "realm")] + " leader. Each leader has a start, a bonus and likes and dislikes that sway other nations’ opinion."
	else:
		var likes: Array = leader_like_text(cur).map(func(x): return "[color=%s][b]%s[/b][/color] %s" % ["#1f7a2e" if x[0].begins_with("+") else "#b3261e", x[0], x[1]])
		leader_info.text = "[b]%s[/b] (%s) · %s %s\nOpinion of other nations: %s" % [cur.full, "woman" if cur.sex == "f" else "man", cur.bonus, leader_start_text(cur), " · ".join(likes)]
	v.add_child(leader_info)
	return v


static func leader_start_text(L: Dictionary) -> String:
	var r: String = str(L.get("race", "realm"))
	var tower: String = {"swamp": "Warlock Tower", "wood": "Grove"}.get(r, "Mage Tower")
	match str(L.get("start", "")):
		"mage": return "Starts with a %s, a %s and 200 more gold, wood and food, but no soldiers (and the %s technology not researched)." % [tower, {"swamp": "Warlock", "wood": "Druid"}.get(r, "Mage"), tower]
		"ogres": return "Starts with an Ogre Cave (technology researched, no upkeep) and 4 Ogres as its only soldiers."
		"twin": return "Starts with a Barracks and 6 Berserkers wielding two axes (Dual Wielding researched)."
		"navigator": return "Starts with 3 Swampstriders, and 3 Slingers as its only soldiers."
		"champion": return "Starts with a Champion as its only soldier, and the Hall of Champions researched."
		"twohand": return "Starts with a Barracks and 6 Protectors fighting two-handed (Two-Handed Grip researched)."
		"ranger": return "Starts with 2 Scouts, and 6 Archers as its only soldiers."
		"stable": return "Starts with a Stable (technology researched, no upkeep) and 4 Riders as its only soldiers."
		"shield": return "Starts with a Barracks and 6 Footmen carrying Round Shields (researched)."
		"forge": return "Starts with a Forge (technology researched)."
		"lumber": return "Mountain or ruin borders of the capital turn into tree borders (up to 2), and it starts with 2 Lumber Mills."
		"scouts": return "Starts with 2 Wayfinders and Far-Seeing Wayfinders researched (and the Automating Wayfinders and Wayfinder Stealth it needs)."
		"farms": return "Starts with 2 Farms in the capital."
	return ""


static func leader_like_text(L: Dictionary) -> Array:
	var SW: Dictionary = GameData.c("SCHOOL_WORD")
	match str(L.get("like", "")):
		"school": return [["+50", "has adopted %s" % SW.get(L.get("school", ""), "its school")], ["−25", "has adopted another school of magic"]]
		"cav": return [["+50", "more cavalry than infantry in its armies (archers aren’t infantry)"], ["−25", "no cavalry in its armies"]]
		"nocav": return [["+50", "no cavalry at all"], ["−25", "more cavalry than infantry"]]
		"forges": return [["+50", "a Forge for every 3 provinces (rounded down)"], ["−25", "no Forge at all"]]
		"lumber3": return [["+50", "a province with 3 Lumber Mills"], ["−25", "no province with more than 1 Lumber Mill"]]
		"farms3": return [["+50", "a province with 3 Farms"], ["−25", "no province with more than 1 Farm"]]
		"scouts": return [["+50", "3 or more fully upgraded explorers (Wayfinders with Automating, Far-Seeing and Scout Sight researched)"], ["−25", "only 1 explorer (or none)"]]
	return []


func start_game() -> void:
	var seed := seed_edit.text.strip_edges() if seed_edit else ""
	if seed == "":
		seed = random_seed()
		if seed_edit:
			seed_edit.text = seed
	opts.seed = seed
	_save_opts()
	if start_btn:
		start_btn.text = "Building the realm…"
		start_btn.disabled = true
	main.start_from_menu(opts.duplicate(true))


func reset_start() -> void:
	if start_btn:
		start_btn.text = "Start game"
		start_btn.disabled = false
