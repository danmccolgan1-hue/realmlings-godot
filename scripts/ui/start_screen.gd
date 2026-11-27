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
const PARADE := ["pioneer:B", "mason:A", "d-sword", "d-spear", "d-rider", "mage:A"]

var main                    # the scene's entry node: starts games, loads saves, opens windows
var card: PanelContainer
var holder: ScrollContainer
var screens := {}           # name -> VBoxContainer
var opts := {}              # the New Game choices (Settings.menu)
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
	holder = ScrollContainer.new()   # (a page taller than the screen scrolls inside the card)
	holder.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(holder)
	for n in ["main", "tut", "multi", "setup", "setup_map"]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 12)
		screens[n] = v
	_build_main()
	_build_tut()
	_build_multi()
	_build_setup()
	_build_setup_map()
	show_screen("main")


func _process(_dt: float) -> void:
	_mp_poll(_dt)
	# the card fits the screen (scrolling when its page is taller) and stays in the middle
	if holder.get_child_count():
		var need: Vector2 = holder.get_child(0).get_combined_minimum_size()
		var room: float = get_viewport_rect().size.y - 110
		holder.custom_minimum_size = Vector2(need.x + (16 if need.y > room else 0), minf(need.y, room))
	card.reset_size()
	var vs := get_viewport_rect().size
	card.position = ((vs - card.size) / 2).floor()
	if parade and parade.is_visible_in_tree():
		parade.queue_redraw()


func show_screen(n: String) -> void:
	if holder.get_child_count():
		holder.remove_child(holder.get_child(0))
	holder.add_child(screens[n])
	holder.scroll_vertical = 0
	if n == "main" and cont_btn:
		cont_btn.visible = FileAccess.file_exists(main.AUTOSAVE)
	if n == "setup":
		_refresh_setup()
	if n == "setup_map" and map_box:
		_refresh_map()


# --- remembered choices (web: localStorage realm-map, realm-slots, realm-start, realm-nation, realm-leader) ---

func _load_opts() -> Dictionary:
	var NAT: Dictionary = GameData.c("NATION")
	var d := {"seed": random_seed(), "nation": {"name": NAT.name, "color": NAT.color, "emblem": NAT.emblem, "secondary": "#faf1dc"}, "leader": "random", "race": "realm", "races": ["random", "random", "random", "random", "random", "random", "random"], "start": "center", "practice": false, "random_race": false,
		"map": {"shape": "classic", "pens": 2, "coves": 2, "trees": 0}, "slots": ["easy", "easy", "moderate", "closed", "closed", "closed", "closed"]}
	var m: Dictionary = Settings.menu
	for k in ["nation", "leader", "race", "races", "start", "practice", "map", "slots", "random_race"]:
		if m.has(k) and typeof(m[k]) == typeof(d[k]):
			d[k] = m[k]
	d.practice = false   # 0.19: every island is a full island (the Practice island choice is gone)
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


## web: features.js randomNationName: each race names its nations its own way
static func random_nation_name(race := "realm") -> String:
	var NP: Dictionary = GameData.c("NAME_PARTS")
	if race == "swamp" and NP.has("swamp"):   # "Bloodtusk Clan", "Legion of Skullmire"
		var S: Dictionary = NP.swamp
		return ("%s %s" % [S.places.pick_random(), S.titles.pick_random()]) if randf() < 0.5 else ("%s of %s" % [S.titles.pick_random(), S.places.pick_random()])
	if race == "wood" and NP.has("wood"):   # "Moonwatchers", "Hunters of the Dark", "Ancient Defenders"
		var W: Dictionary = NP.wood
		var r := randf()
		return (str(W.pre.pick_random()) + str(W.post.pick_random())) if r < 0.35 else ("%s of %s" % [W.groups.pick_random(), W.of.pick_random()]) if r < 0.75 else ("%s %s" % [W.adj.pick_random(), W.groups.pick_random()])
	var P: Dictionary = NP.realm
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


## A small solid button (0.19.3: Join, Watch and Set were drawn as switches and looked like toggles).
func _btn(text: String, col: Color, f: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(96, 40)
	b.add_theme_font_size_override("font_size", 18)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in [["normal", col], ["hover", col.lightened(0.12)], ["pressed", col.darkened(0.12)], ["disabled", col.lerp(Color("#cfcfd6"), 0.6)]]:
		var sb := _sb(st[1], 2, 3, 6)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		b.add_theme_stylebox_override(st[0], sb)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(st, Color.WHITE)
	b.add_theme_color_override("font_outline_color", Color(INK, 0.45))
	b.add_theme_constant_override("outline_size", 3)
	if f.is_valid():
		b.pressed.connect(f)
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
func _row(label: String, content: Control, parent: Container, top := false) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := _lbl(label.to_upper(), 13, MUTED)
	l.custom_minimum_size = Vector2(130, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP if top else VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(content)
	parent.add_child(h)


# --- the main menu ---

func _build_main() -> void:
	var v: VBoxContainer = screens.main
	v.custom_minimum_size = Vector2(500, 0)
	var title := _lbl("Realmlings", 76, Color("#f2b632"))
	Fonts.title(title)
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
	v.add_child(_big("New Game", BLUE, func(): open_setup(false)))
	v.add_child(_big("Tutorial", PURPLE, func(): show_screen("tut")))
	v.add_child(_big("Multiplayer", PURPLE, func(): show_screen("multi")))
	v.add_child(_big("Patch Notes", PURPLE, func(): main.patch_notes.open()))
	v.add_child(_big("Quit", Color("#8a5a44"), func():
		Settings.save_all()
		get_tree().quit()))
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

func _sub_head(v: VBoxContainer, title: String, back_to := Callable()) -> Button:
	var h := HBoxContainer.new()
	var back := Button.new()
	back.text = "← Back"
	back.focus_mode = Control.FOCUS_NONE
	back.add_theme_font_size_override("font_size", 16)
	for st in ["normal", "hover", "pressed"]:
		back.add_theme_stylebox_override(st, _sb(CHIP_HI if st != "hover" else Color("#fff7d9"), 2, 2, 6))
	back.add_theme_color_override("font_color", INK)
	back.add_theme_color_override("font_hover_color", INK)
	back.pressed.connect(func():
		if back_to.is_valid():
			back_to.call()
		else:
			show_screen("main"))
	h.add_child(back)
	var t := _lbl(title, 34, Color("#f2b632"))
	Fonts.title(t)
	t.add_theme_color_override("font_outline_color", Color("#7a4a12"))
	t.add_theme_constant_override("outline_size", 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(back.get_combined_minimum_size().x, 0)
	h.add_child(pad)
	v.add_child(h)
	return back


func _build_tut() -> void:
	var v: VBoxContainer = screens.tut
	v.custom_minimum_size = Vector2(500, 0)
	_sub_head(v, "Tutorial")
	v.add_child(_big("Basic Tutorial", BLUE, func(): main.start_tutorial(), "Explore, expand and train your first army"))
	v.add_child(_big("Combat Tutorial", PURPLE, Callable(), "Coming later", true))


# The Multiplayer screen: host a lobby or join one over the local network or the internet, see who is in it and
# chat (scripts/net/net_session.gd). Playing a game together comes once the rules handle several human players.
var net: NetSession
var mp_box: VBoxContainer
var mp_status: Label
var mp_note: Label
var mp_lan: VBoxContainer
var mp_players: VBoxContainer
var mp_lan_sig := ""
var mp_lan_t := 0.0
var mp_opts_box: VBoxContainer   # the host's choices for the game (island, computer nations)
var mp_start: Button             # the host: Start Game; anyone else: Ready (0.19)
var mp_rows_sig := ""            # the players list as last drawn, without the pings (0.19: no redraw for a ping)
var mp_ping_l := {}              # peer id -> its ping label (updated in place)
var mp_taken_sig := ""           # the colors and leaders others have taken, as last shown on the Nation page
var mp_info_t := 0.0
var mp_debug_shown := false      # Allows Debug as the lobby last drew it
var mp_in_lobby := false
var mp_seeded := false           # this lobby's island got its fresh random seed (0.19.1)         # the lobby (not the Multiplayer menu) is showing
var mp_saves := []               # the host: the saved games offered under Load a saved game
var mp_saves_open := false
var online: OnlinePorts          # 0.19.3: Host online is asking the server's ports which lobby is free
var online_ports := []           # the free ports not tried yet
var online_name := ""
const WATCH_TIP := "Join as an observer: you play no nation and give no orders, but see the whole map and every player's resources, army and provinces"


func _build_multi() -> void:
	var v: VBoxContainer = screens.multi
	v.custom_minimum_size = Vector2(620, 0)
	v.add_theme_constant_override("separation", 8)
	_sub_head(v, "Multiplayer")
	mp_box = VBoxContainer.new()
	mp_box.add_theme_constant_override("separation", 8)
	v.add_child(mp_box)
	_mp_menu()


func _mp_clear() -> void:
	_clear_now(mp_box)


func _mp_nation() -> Dictionary:
	if opts.get("random_race", false):   # (0.19.3: Random: drawn once, and kept while the choices stay the same)
		if mp_rand.is_empty() or int(mp_rand.nation.color) != int(opts.nation.color) or str(mp_rand.nation.get("secondary", "")) != str(opts.nation.get("secondary", "")):
			mp_rand = resolved_nation()
		var R: Dictionary = mp_rand
		return {"race": R.race, "color": int(R.nation.color), "emblem": R.nation.emblem,
			"secondary": R.nation.get("secondary", "#faf1dc"), "nation": R.nation.name, "leader": "random"}
	return {"race": opts.get("race", "realm"), "color": int(opts.nation.color), "emblem": opts.nation.emblem,
		"secondary": opts.nation.get("secondary", "#faf1dc"), "nation": opts.nation.name, "leader": opts.leader}


func _mp_menu() -> void:
	_mp_clear()
	var name_edit := LineEdit.new()
	name_edit.text = str(Settings.menu.get("mp_name", "Player"))
	name_edit.max_length = 24
	_style_edit(name_edit)
	name_edit.text_changed.connect(func(t2):
		Settings.menu.mp_name = t2
		Settings.save_all())
	_row("Your name", name_edit, mp_box)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 8)
	var hl := _big("Host locally", BLUE, func(): _mp_host(name_edit.text))
	hl.tooltip_text = "Your computer runs the game and you play in it (up to 8 players): friends on your network, or over the internet if your router lets them in"
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(hl)
	var ho := _big("Host online", PURPLE, func(): _mp_host_online(name_edit.text))
	ho.tooltip_text = "Host on the Realmlings server: it finds a game nobody is in yet and you host it. Friends join the address and port it shows"
	ho.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(ho)
	mp_box.add_child(hr)
	var jr := HBoxContainer.new()
	jr.add_theme_constant_override("separation", 8)
	var addr := LineEdit.new()
	addr.placeholder_text = "Host's or server's address, e.g. 81.2.3.4 or 81.2.3.4:24566"
	addr.text = str(Settings.menu.get("mp_addr", ""))
	addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_edit(addr)
	jr.add_child(addr)
	var go := func(as_watcher: bool):
		Settings.menu.mp_addr = addr.text
		Settings.save_all()
		_mp_join(name_edit.text, addr.text, as_watcher)
	var jb := _btn("Join", Color("#3e9b4f"), func(): go.call(false), "Join this game and play a nation")
	jr.add_child(jb)
	jr.add_child(_btn("Watch", Color("#5a6475"), func(): go.call(true), WATCH_TIP))
	addr.text_submitted.connect(func(_t2): jb.pressed.emit())
	_row("Join by address", jr, mp_box)
	var pw_edit := LineEdit.new()
	pw_edit.placeholder_text = "Only if the game has one"
	pw_edit.secret = true
	pw_edit.max_length = 40
	pw_edit.text = str(Settings.menu.get("mp_pw", ""))
	_style_edit(pw_edit)
	pw_edit.text_changed.connect(func(t2):
		Settings.menu.mp_pw = t2
		Settings.save_all())
	pw_edit.text_submitted.connect(func(_t2): jb.pressed.emit())
	_row("Password", pw_edit, mp_box)
	mp_lan = VBoxContainer.new()
	_row("On your network", mp_lan, mp_box)
	var ips: Array = Array(IP.get_local_addresses()).filter(func(x): return x.count(".") == 3 and not x.begins_with("127.") and not x.begins_with("169.254."))
	mp_note = _lbl("Your address on this network: %s. Over the internet, the host opens UDP port %d (the game tries this itself) or everyone uses a virtual LAN such as Tailscale." % [", ".join(ips) if not ips.is_empty() else "unknown", NetSession.PORT], 14, MUTED)
	mp_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_note.custom_minimum_size = Vector2(600, 0)
	mp_box.add_child(mp_note)
	mp_status = _lbl("", 15, INK)
	mp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_status.custom_minimum_size = Vector2(600, 0)
	mp_box.add_child(mp_status)
	mp_in_lobby = false
	if net == null:
		net = NetSession.new(name_edit.text, _mp_nation())
	net.listen_lan()
	mp_lan_sig = "-"


func _mp_wire() -> void:
	net.status.connect(func(t2): if mp_status and is_instance_valid(mp_status): mp_status.text = t2)
	net.closed.connect(func(why):
		net = null
		mp_in_lobby = false
		main.hide_loading()
		show()
		_mp_menu()
		if why == NetSession.TAKEN:   # (Host online: someone took that lobby first: the next free one)
			if not online_ports.is_empty():
				_mp_online_next()
				return
			why = "No ports available. Try hosting locally."
		mp_status.text = why)
	net.players_changed.connect(_mp_players)
	net.lobby_info_changed.connect(func():
		if net != null and not net.is_host:
			if mp_in_lobby and mp_debug_shown != net.debug_ok:
				_mp_lobby()
			else:
				_mp_options())
	net.seat_offer.connect(_mp_pick_seat)
	net.leader_changed.connect(func():   # (a server: someone else hosts the game now; if it's us, a new island)
		if net != null and net.is_leader() and not mp_seeded:
			_mp_fresh_seed()
		if mp_in_lobby:
			_mp_lobby())
	net.lobby_save_changed.connect(func():
		mp_saves_open = false
		if mp_in_lobby:
			_mp_lobby())
	net.message.connect(_mp_message)


func _mp_message(_from: int, m: Dictionary) -> void:
	if net == null:
		return
	match str(m.get("t", "")):
		"start":   # the host started the game: main loads it and takes the connection over
			if not net.is_host:
				var nt := net
				net = null
				main.start_mp_client(nt, m)
		"lnote":   # a server's word to the player hosting (why it can't start yet, a save was refused...)
			if mp_status and is_instance_valid(mp_status):
				mp_status.text = str(m.get("text", ""))
			if main.loading.visible and main.lock == null and not str(m.get("text", "")).begins_with("Raising"):
				main.hide_loading()   # (the server couldn't build the game after all)
				show()
		"building":   # 0.19.3: the game is being built: everyone's loading screen
			main.show_loading()
		"saves":   # a server's saved games
			mp_saves = m.get("list", [])
			if mp_saves_open:
				_mp_options()


func _mp_host(nm: String) -> void:
	if net != null:
		net.leave()
	net = NetSession.new(nm, _mp_nation())
	_mp_wire()
	var w := net.host()
	if w != "":
		mp_status.text = w
		net = null
		return
	net.debug_ok = bool(Settings.menu.get("mp_debug", false))
	_mp_fresh_seed()
	_mp_lobby()
	mp_status.text = "Hosting on port %d. Friends on your network see this game in their list; over the internet they join your address." % NetSession.PORT
	mp_note.text = "Asking your router to open the port..."


## Host online (0.19.3): ask the server's ports which lobby nobody is in, then host one of them at random.
func _mp_host_online(nm: String) -> void:
	if online != null:
		return
	online_name = nm
	online_ports = []
	online = OnlinePorts.new()
	online.start()
	mp_status.text = "Looking for a free game on the server…"


# Host online: join the next free port as its first player (who hosts it)
func _mp_online_next() -> void:
	var port: int = online_ports.pop_front()
	_mp_join(online_name, "%s:%d" % [OnlinePorts.HOST, port], false, true)
	mp_status.text = "Hosting on the server: friends join %s:%d. Connecting…" % [OnlinePorts.HOST, port]


func _mp_join(nm: String, address: String, as_watcher := false, fresh := false) -> void:
	if net != null:
		net.leave()
	net = NetSession.new(nm, _mp_nation())
	net.watch = as_watcher
	net.fresh = fresh
	mp_seeded = false
	net.pw = str(Settings.menu.get("mp_pw", ""))
	_mp_wire()
	var w := net.join(address)
	if w != "":
		mp_status.text = w
		net = null
		return
	_mp_lobby()
	mp_status.text = ("Connecting to %s to watch..." if as_watcher else "Connecting to %s...") % address


## Is this player hosting the game: from their own copy, or as the player hosting on a dedicated server?
func _mp_lead() -> bool:
	return net != null and (net.is_host or net.is_leader())


func _mp_lobby() -> void:
	_mp_clear()
	mp_in_lobby = true
	mp_debug_shown = net != null and net.debug_ok
	var lead := _mp_lead()
	var watching: bool = net != null and net.watch
	var saved: bool = net != null and not net.lobby_save.is_empty()
	mp_status = _lbl("", 15, INK)
	mp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_status.custom_minimum_size = Vector2(600, 44)   # (fixed heights: rows coming and going don't move the page)
	mp_box.add_child(mp_status)
	mp_note = _lbl("", 14, MUTED)
	mp_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_note.custom_minimum_size = Vector2(600, 40)
	mp_box.add_child(mp_note)
	var name_edit := LineEdit.new()
	name_edit.text = str(Settings.menu.get("mp_name", "Player"))
	name_edit.max_length = 24
	_style_edit(name_edit)
	name_edit.text_changed.connect(func(t2):
		Settings.menu.mp_name = t2
		Settings.save_all()
		if net:
			net.set_name(t2.strip_edges() if t2.strip_edges() != "" else "Player"))
	_row("Your name", name_edit, mp_box)
	mp_players = VBoxContainer.new()
	mp_players.add_theme_constant_override("separation", 4)
	mp_players.custom_minimum_size = Vector2(0, 8 * 32)   # room for 8 players from the start
	_row("Players", mp_players, mp_box, true)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 8)
	if not watching:   # (an observer has no nation)
		var yb := _big("Your Nation", Color("#5aa05a"), func(): open_setup(true, "setup"), "", saved)
		yb.tooltip_text = "In a saved game you play one of its nations: pick it below" if saved else "Choose your nation's name, race, leader and flag for this game"
		yb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(yb)
	if lead:
		var mb := _big("Map Settings", PURPLE, func(): open_setup(true, "setup_map"), "", saved)
		mb.tooltip_text = "A saved game keeps its own island" if saved else "Choose the island and the computer nations"
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(mb)
		var sb := _big("New island" if saved else "Load a saved game", Color("#b07a2a"), func():
			if net == null:
				return
			if not net.lobby_save.is_empty():
				_mp_choose_save("")
				return
			mp_saves_open = not mp_saves_open
			if net.is_host:
				mp_saves = main.host_saves()
			else:
				mp_saves = []
				net.send_to(1, {"t": "lsaves"})
			_mp_options())
		sb.tooltip_text = "Raise a new island instead of the saved game" if saved else "Carry on a saved multiplayer game: each player picks one of its nations"
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(sb)
	mp_box.add_child(pr)
	if lead:   # an optional password for joining
		var pwr := HBoxContainer.new()
		pwr.add_theme_constant_override("separation", 8)
		var pe := LineEdit.new()
		pe.placeholder_text = "None: anyone with the address can join"
		pe.max_length = 40
		pe.text = net.password if net.is_host else str(Settings.menu.get("mp_host_pw", ""))
		pe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_edit(pe)
		pwr.add_child(pe)
		var setp := func():
			Settings.menu.mp_host_pw = pe.text.strip_edges()
			Settings.save_all()
			net.set_password(pe.text)
			mp_status.text = ("Password set: players joining from now on need it." if pe.text.strip_edges() != "" else "No password: anyone with the address can join.")
		pwr.add_child(_btn("Set", BLUE, setp, "Set the password (empty: none)"))
		pe.text_submitted.connect(func(_t2): setp.call())
		_row("Password", pwr, mp_box)
	if net != null:   # Allows Debug: the host switches it; everyone sees it
		mp_box.add_child(_tog("Allows Debug", net.debug_ok, func():
			if net and _mp_lead():
				Settings.menu.mp_debug = not net.debug_ok
				Settings.save_all()
				net.set_debug(not net.debug_ok)
				_mp_lobby(), not lead,
			"Every player may use Settings → Debug in the game: reveal the map and +2000 resources (for every player), and every technology (for themselves, in the Magic school they choose)" if lead else "The host decides whether Settings → Debug may be used in this game"))
	mp_opts_box = VBoxContainer.new()
	mp_opts_box.add_theme_constant_override("separation", 6)
	mp_opts_box.custom_minimum_size = Vector2(0, 64)
	mp_box.add_child(mp_opts_box)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 8)
	var lb := _big("Leave", Color("#8a5a44"), func():
		if net:
			net.leave()
		net = null
		mp_in_lobby = false
		_mp_menu())
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(lb)
	if watching:   # 0.19.3: an observer just waits for the host to start
		mp_start = _big("Watching", Color("#5a6475"), Callable(), "", true)
		mp_start.tooltip_text = "You are watching: the game opens for you when the host starts it"
	elif net == null or lead:
		mp_start = _big("Start Game", BLUE, _mp_begin)
	else:   # 0.19: everyone else says when they are ready; the host can't start until they all are
		mp_start = _big("Ready", Color("#3e9b4f"), func():
			if net and net.players.has(net.my_id):
				net.set_ready(not net.players[net.my_id].get("ready", false)))
		mp_start.tooltip_text = "Tell the host you are happy with your nation and the game, and ready to start"
	mp_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.add_child(mp_start)
	mp_box.add_child(br)
	mp_box.add_child(_link("Connection trouble?", func(): _mp_help(), "What to check when a player can't join or keeps being thrown out"))
	mp_rows_sig = ""
	_mp_players()
	_mp_options()


## What the host chose: a saved game to carry on (everyone picks a nation from it), or a summary of the new island.
## Everyone else sees the host's summary (0.19), and has to be ready again whenever it changes.
func _mp_options() -> void:
	if mp_opts_box == null or not is_instance_valid(mp_opts_box) or net == null:
		return
	_clear_now(mp_opts_box)
	var lead := _mp_lead()
	if not net.lobby_save.is_empty():   # a saved game: pick your nation from it
		var head := _lbl("Carrying on a saved game: %s. Pick the nation you will play:" % str(net.lobby_save.get("desc", "")), 14, MUTED)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.custom_minimum_size = Vector2(600, 0)
		mp_opts_box.add_child(head)
		var by := {}
		for id in net.players:
			if int(net.players[id].get("pick", 0)) != 0:
				by[int(net.players[id].pick)] = id
		var mine := int(net.players.get(net.my_id, {}).get("pick", 0))
		if net.watch:
			head.text = "Carrying on a saved game: %s. You are watching it." % str(net.lobby_save.get("desc", ""))
		for st in (net.lobby_save.get("seats", []) if not net.watch else []):
			var o := int(st.id)
			var who := ""
			if by.has(o):
				who = "you" if by[o] == net.my_id else str(net.players[by[o]].name)
			var line := "%s · %s%s%s" % [str(st.nation), Races.NAME.get(str(st.race), ""), ("  (played by %s when saved)" % st.player) if str(st.player) != "" else "",
				("  · taken by " + who) if who != "" and who != "you" else ""]
			var tip := "The first nation: someone has to play it" if o == Game.HOST else "If nobody picks it, the computer plays it"
			mp_opts_box.add_child(_tog(line, o == mine, func():
				if net:
					net.pick(0 if o == mine else o), by.has(o) and by[o] != net.my_id, tip))
		if lead and net.is_host:
			net.set_lobby_info("Carrying on a saved game: %s. Pick your nation from it." % str(net.lobby_save.get("desc", "")), "save:" + str(net.lobby_save.get("name", "")))
		return
	if lead and mp_saves_open:   # the host chooses a saved game
		mp_opts_box.add_child(_lbl("Saved games%s:" % (" on the server" if not net.is_host else ""), 14, MUTED))
		if mp_saves.is_empty():
			mp_opts_box.add_child(_lbl("(none yet: save from the in-game menu)" if net.is_host else "(asking the server…)", 14, MUTED))
		for sv in mp_saves:
			var nm := str(sv.name)
			mp_opts_box.add_child(_tog(("Your last multiplayer game (saved %s)" % MpSetup.when_text(int(sv.when))) if nm == main.LAST_MP else MpSetup.save_label(sv), false, func(): _mp_choose_save(nm)))
		if not net.is_host and FileAccess.file_exists(main.MP_SAVE):
			mp_opts_box.add_child(_tog("Send your last multiplayer game from this computer (saved %s)" % MpSetup.when_text(FileAccess.get_modified_time(main.MP_SAVE)), false, func():
				mp_status.text = "Sending the saved game to the server…"
				net.send_to(1, {"t": "lupload", "save": FileAccess.get_file_as_string(main.MP_SAVE)}), false,
				"Carry on a game you played before on this computer (every player keeps the last one)"))
		return
	if not lead:
		var info := _lbl(("The game: " + net.lobby_info) if net.lobby_info != "" else "The host chooses the island and the computer nations, and starts the game once everyone is ready.", 14, MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.custom_minimum_size = Vector2(600, 0)
		mp_opts_box.add_child(info)
		return
	var l := _lbl(_mp_summary(), 14, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	mp_opts_box.add_child(l)
	net.lead_info(_mp_summary(), _mp_terms())


## The host chose saved game `name` to carry on ("" for a new island again). On a server, the server reads it.
func _mp_choose_save(name: String) -> void:
	mp_saves_open = false
	if net == null:
		return
	if not net.is_host:
		net.send_to(1, {"t": "lload", "name": name})
		return
	if name == "":
		net.set_lobby_save({})
		net.lobby_terms = ""
		return
	var text: String = main.host_save_text(name)
	var g := Game.load_text(text) if text != "" and Game.save_why(text) == "" else null
	if g == null:
		mp_status.text = "That saved game can't be read."
		return
	var sv: Array = main.host_saves().filter(func(x): return x.name == name)
	var desc := ("your last multiplayer game, saved %s" % MpSetup.when_text(int(sv[0].when))) if name == main.LAST_MP else MpSetup.save_label(sv[0]) if not sv.is_empty() else name
	net.set_lobby_save({"name": name, "desc": desc, "seats": MpSetup.save_seats(g)})


## How many computer nations the multiplayer map settings M have (the slots after the players' own).
func _mp_ais(M: Dictionary) -> int:
	var others := net.playing_count() - 1 if net != null else _mp_humans().size()
	return range(maxi(0, others), 7).filter(func(x): return x < M.slots.size() and str(M.slots[x]) != "closed").size()


## The host's game in a line: what everyone agrees to when they say they are ready.
func _mp_summary() -> String:
	var M := _mp_map()
	var humans := net.playing_count()
	var ais := []
	for i in range(humans - 1, 7):
		if i < M.slots.size() and str(M.slots[i]) != "closed":
			ais.append(str(M.slots[i]))
	return "Island: %s, seed %s%s. %d players and %d computer nation%s%s.%s" % [str(M.map.get("shape", "classic")).capitalize(), str(M.seed), "", humans, ais.size(), "" if ais.size() == 1 else "s", (" (" + ", ".join(ais) + ")") if not ais.is_empty() else "",
		" The players spawn near one another." if bool(M.get("near", false)) and ais.size() >= Game.NEAR_MIN_AI else ""]


## What the players agree to when they are ready: the host's island and computer nations (not how many have joined).
func _mp_terms() -> String:
	var M := _mp_map()
	return str([M.get("seed"), M.get("start"), M.get("map"), M.get("slots"), M.get("races"), M.get("near", false)])


## A player joining a game in progress (0.19 hot-join): the nations they may take.
func _mp_pick_seat(choices: Array) -> void:
	if mp_opts_box == null or not is_instance_valid(mp_opts_box):
		return
	_clear_now(mp_opts_box)
	mp_status.text = "This game is already under way. Choose the nation you will play:"
	for c in choices:
		var o := int(c.get("id", 0))
		var who := str(c.get("player", ""))
		var state := "its player is away" if str(c.get("state", "")) == "away" else "played by the computer"
		mp_opts_box.add_child(_tog("%s · %s%s" % [str(c.get("nation", "?")), Races.NAME.get(str(c.get("race", "realm")), ""), ("  (%s's, %s)" % [who, state]) if who != "" else "  (%s)" % state], false, func():
			if net:
				_clear_now(mp_opts_box)
				mp_status.text = "Taking up %s… the host is sending the game." % str(c.get("nation", "the nation"))
				net.choose_seat(o)))


## What to check when someone can't join or keeps being thrown out (0.19).
func _mp_help() -> void:
	mp_note.text = ("Can't join or keep being dropped? 1) Everyone needs the same version (%s). 2) Use different names: the game keeps each nation by its player's name. 3) The host's router and firewall must let UDP port %d through (Windows asks the first time the game hosts: allow Private and Public networks), or use a virtual LAN such as Tailscale or ZeroTier. 4) Wi-Fi that drops out for long stretches will drop the player: a cable helps. 5) Every join, refusal, drop-out and resync is written to %s on each computer: compare the host's and the player's after it happens.") % [net.version if net else "", NetSession.PORT, NetSession.log_path()]


## The multiplayer host's map settings (whichever page is open).
func _mp_map() -> Dictionary:
	var was := mp_mode
	mp_mode = true
	var M: Dictionary = _map_opts()
	mp_mode = was
	return M


## Two nations can't fly the same color or share a leader. Returns why not, or "".
func _mp_clash() -> String:
	return MpSetup.clash(net.players)


func _mp_begin() -> void:
	if net == null or not _mp_lead():
		return
	var saved := not net.lobby_save.is_empty()
	if net.is_host:
		net.set_nation(_mp_nation())
	var why := ""
	if saved:
		var picks := {}
		for id in net.players:
			picks[id] = int(net.players[id].get("pick", 0))
		why = MpSetup.picks_why(net.lobby_save.get("seats", []), picks, net.players)
	else:
		why = _mp_clash()
	if why != "":
		mp_status.text = why
		return
	if not net.all_ready():
		mp_status.text = "Not everyone is ready yet."
		return
	var M := _mp_map()
	var o := {"seed": str(M.get("seed", random_seed())).strip_edges(), "slots": M.slots.duplicate(), "races": M.races.duplicate(),
		"start": M.start, "map": M.map, "save": str(net.lobby_save.get("name", "")) if saved else "", "debug": net.debug_ok,
		"near": bool(M.get("near", false)) and _mp_ais(M) >= Game.NEAR_MIN_AI}
	if o.seed == "":
		o.seed = random_seed()
	if not net.is_host:   # a dedicated server: it builds the game and sends it to everyone
		mp_status.text = "Asking the server to start…"
		net.send_to(1, {"t": "lstart", "o": o})
		return
	mp_start.text = "Building the realm…"
	mp_start.disabled = true
	var nt := net
	net = null
	main.start_mp_host(nt, o)


func _mp_players() -> void:
	if net == null:
		return
	var tk := str(_mp_taken())
	if mp_mode and screens.setup.is_inside_tree() and tk != mp_taken_sig:   # (someone took a color or leader: gray it out now)
		_refresh_setup()
	mp_taken_sig = tk
	if mp_players == null or not is_instance_valid(mp_players):
		return
	if mp_start and is_instance_valid(mp_start):
		if _mp_lead():
			var waiting_for: Array = net.players.keys().filter(func(id): return int(id) != net.leader and not net.players[id].get("watch", false) and not net.players[id].get("ready", false)).map(func(id): return str(net.players[id].name))
			var few := false   # (0.19.1: one player may start alone, hosting or on a server, to test)
			mp_start.disabled = few or not waiting_for.is_empty()
			mp_start.tooltip_text = "Waiting for at least one more player" if few else ("Waiting for %s to be ready" % ", ".join(waiting_for)) if not waiting_for.is_empty() else "Everyone is ready: start the game for everyone"
		elif not net.watch:
			var me_ready: bool = net.players.has(net.my_id) and net.players[net.my_id].get("ready", false)
			mp_start.text = "Ready ✓ (click to cancel)" if me_ready else "Ready"
			mp_start.disabled = not net.joined
	var psig := str(net.players.size()) + str(net.players.values().map(func(P): return int(P.get("pick", 0))))
	if mp_opts_box and is_instance_valid(mp_opts_box) and str(mp_opts_box.get_meta("n", "")) != psig and (_mp_lead() or not net.lobby_save.is_empty()):
		mp_opts_box.set_meta("n", psig)
		_mp_options()
	# 0.19: the rows are drawn again only when who is there, their nation or their readiness changes; pings are
	# updated in place (they came every 2 s and redrew the whole list, so the lobby flickered)
	var sig := ""
	for id in net.players:
		var P: Dictionary = net.players[id]
		sig += "%s|%s|%s|%s|%s|%s;" % [id, P.name, str(P.get("nation", {})), P.get("ready", false), P.get("pick", 0), P.get("watch", false)]
	if sig == mp_rows_sig:
		for id in mp_ping_l:
			if net.players.has(id) and is_instance_valid(mp_ping_l[id]):
				mp_ping_l[id].text = "%d ms" % int(net.players[id].get("ping", 0))
		return
	mp_rows_sig = sig
	mp_ping_l = {}
	_clear_now(mp_players)
	for id in net.players:
		var P: Dictionary = net.players[id]
		var n: Dictionary = P.get("nation", {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size = Vector2(0, 30)
		var NC: Array = GameData.c("NATION_COLORS")
		var tex = Art.flag_texture(str(NC[int(n.get("color", 0)) % NC.size()][0]), str(n.get("emblem", "crown")), str(n.get("secondary", "#faf1dc")))
		var r := TextureRect.new()
		r.texture = tex if tex is Texture2D else null
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.custom_minimum_size = Vector2(40, 28)
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(r)
		var who := "%s%s · %s · %s" % [P.name, " (host)" if int(id) == net.leader else "", str(n.get("nation", "")), Races.NAME.get(str(n.get("race", "realm")), "")]
		if P.get("watch", false):   # 0.19.3: an observer
			r.texture = null
			who = "%s%s · watching" % [P.name, " (you)" if int(id) == net.my_id else ""]
		elif not net.lobby_save.is_empty():   # a saved game: the nation they picked from it
			var pk := int(P.get("pick", 0))
			var st: Array = net.lobby_save.get("seats", []).filter(func(x): return int(x.id) == pk)
			who = "%s%s · %s" % [P.name, " (host)" if int(id) == net.leader else "", (str(st[0].nation) + " · " + Races.NAME.get(str(st[0].race), "")) if not st.is_empty() else "no nation picked yet"]
		row.add_child(_lbl(who, 16, INK))
		if int(id) != net.leader:
			var rd: bool = P.get("ready", false)
			if not P.get("watch", false):
				row.add_child(_lbl("Ready" if rd else "Not ready", 14, Color("#3e9b4f") if rd else Color("#a0461e")))
			var pl := _lbl("%d ms" % int(P.get("ping", 0)), 14, MUTED)
			row.add_child(pl)
			mp_ping_l[id] = pl
			if _mp_lead() and int(id) != net.my_id:   # the host may remove a player from the lobby
				var kid := int(id)
				var pname := str(P.name)
				row.add_child(_link("Remove", func():
					if net:
						net.kick(kid)
						mp_status.text = "%s was removed from the lobby. They can't join it again under that name." % pname,
					"Remove %s from the lobby (they can't join it again under that name)" % pname))
		mp_players.add_child(row)


func _mp_poll(dt: float) -> void:
	if online != null:   # Host online: the ports' answers
		online.poll(dt)
		if online.done:
			var o := online
			online = null
			online_ports = o.free.duplicate()
			if online_ports.is_empty():
				if mp_status and is_instance_valid(mp_status):
					mp_status.text = o.why_none()
			else:
				_mp_online_next()
	if net == null:
		return
	net.poll(dt)
	if net == null:
		return
	mp_info_t -= dt
	if _mp_lead() and net.lobby_save.is_empty() and mp_info_t <= 0 and mp_players != null and is_instance_valid(mp_players):
		mp_info_t = 0.5
		net.lead_info(_mp_summary(), _mp_terms())   # (the host changed the map settings: everyone is asked again)
	if mp_note and is_instance_valid(mp_note) and net.is_host and net.upnp_note != "":
		mp_note.text = net.upnp_note
	mp_lan_t -= dt
	if mp_lan and is_instance_valid(mp_lan) and mp_lan_t <= 0:
		mp_lan_t = 0.5
		var sig := ",".join(net.lan_games.keys())
		if sig != mp_lan_sig:
			mp_lan_sig = sig
			_clear_now(mp_lan)
			if net.lan_games.is_empty():
				mp_lan.add_child(_lbl("No games found yet (looking...)", 14, MUTED))
			for k in net.lan_games:
				var gm: Dictionary = net.lan_games[k]
				var addr: String = k
				var lr := HBoxContainer.new()
				lr.add_theme_constant_override("separation", 8)
				var jl := _btn("Join %s's game (%d player%s)%s" % [gm.name, gm.players, "" if gm.players == 1 else "s", "" if gm.version == net.version else " · version " + gm.version], Color("#3e9b4f"),
					func(): _mp_join(str(Settings.menu.get("mp_name", "Player")), addr))
				jl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lr.add_child(jl)
				lr.add_child(_btn("Watch", Color("#5a6475"), func(): _mp_join(str(Settings.menu.get("mp_name", "Player")), addr, true), WATCH_TIP))
				mp_lan.add_child(lr)


# --- the New Game page ---

func _build_setup() -> void:
	var v: VBoxContainer = screens.setup
	v.custom_minimum_size = Vector2(760, 0)
	v.add_theme_constant_override("separation", 8)
	_sub_head(v, "New Game: Nation", func(): show_screen("multi" if mp_mode else "main"))
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
		var rc := str(opts.get("race", "realm"))
		var n := random_nation_name(rc)
		var k := 0
		while (n.length() > 24 or n == nation_edit.text) and k < 50:
			n = random_nation_name(rc)
			k += 1
		nation_edit.text = n
		opts.nation.name = n
		_save_opts(), "Random nation name"))
	_row("Nation", nh, v)
	setup_box = VBoxContainer.new()
	setup_box.add_theme_constant_override("separation", 8)
	v.add_child(setup_box)
	nation_next = _big("Continue", BLUE, _nation_done)
	nation_next.custom_minimum_size = Vector2(0, 62)
	v.add_child(nation_next)


# --- the New Game pages, for a single-player game or a multiplayer lobby ---

var mp_mode := false      # the New Game pages are open from the multiplayer lobby (their buttons lead back there)
var map_box: VBoxContainer
var seed_map_edit: LineEdit
var nation_next: Button   # Continue (or Done, in a lobby)
var map_back: Button


## Remove a container's children at once (queue_free alone leaves them for a frame, and the page jumps).
func _clear_now(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


## In a multiplayer lobby: the colors and leaders other players have chosen. {colors: {i: name}, leaders: {id: name}}
func _mp_taken() -> Dictionary:
	var out := {"colors": {}, "leaders": {}}
	if not mp_mode or net == null:
		return out
	for id in net.players:
		if int(id) == net.my_id or net.players[id].get("watch", false):
			continue
		var n: Dictionary = net.players[id].get("nation", {})
		out.colors[int(n.get("color", -1))] = str(net.players[id].name)
		if str(n.get("leader", "random")) != "random":
			out.leaders[str(n.leader)] = str(net.players[id].name)
	return out


## In a multiplayer lobby: the other players' names, in the order they take the slots.
func _mp_humans() -> Array:
	if not mp_mode or net == null:
		return []
	var ids := net.players.keys()
	ids.sort()
	return ids.filter(func(x): return int(x) != net.leader and not net.players[x].get("watch", false)).map(func(x): return str(net.players[x].name))


## 0.19.1: a lobby the player hosts starts on a new random island (the rest of Map Settings is kept): the seed
## used to carry over from the last game, the same island every time.
func _mp_fresh_seed() -> void:
	mp_seeded = true
	var M := _mp_map()
	M.seed = random_seed()
	Settings.menu.mp_map = M
	Settings.save_all()


## The map settings the page changes: the New Game ones, or the multiplayer host's own (kept apart).
func _map_opts() -> Dictionary:
	if not mp_mode:
		return opts
	var M: Dictionary = Settings.menu.get("mp_map", {})
	if not M.has("slots"):
		M = {"seed": random_seed(), "start": opts.start, "map": opts.map.duplicate(true), "slots": ["moderate", "moderate", "closed", "closed", "closed", "closed", "closed"],
			"races": ["random", "random", "random", "random", "random", "random", "random"], "practice": false, "cont": false}
		Settings.menu.mp_map = M
	return M


func _save_map() -> void:
	if mp_mode:
		Settings.menu.mp_map = _map_opts()
		Settings.save_all()
	else:
		_save_opts()


func _pick_map(k: String, val) -> void:
	_map_opts()[k] = val
	_save_map()
	_refresh_map()


## Open the New Game pages: from the main menu (lobby false) or from a multiplayer lobby.
func open_setup(lobby: bool, page := "setup") -> void:
	mp_mode = lobby
	nation_next.text = "Done" if lobby else "Continue"
	map_back.visible = true
	start_btn.text = "Done" if lobby else "Start Game"
	seed_map_edit.text = str(_map_opts().get("seed", ""))
	_refresh_setup()
	_refresh_map()
	show_screen(page)


func _nation_done() -> void:
	if mp_mode:
		if net != null:
			net.set_nation(_mp_nation())
		show_screen("multi")
		_mp_players()
	else:
		show_screen("setup_map")


func _map_done() -> void:
	if mp_mode:
		show_screen("multi")
		_mp_options()
	else:
		start_game()


func _build_setup_map() -> void:
	var v: VBoxContainer = screens.setup_map
	v.custom_minimum_size = Vector2(760, 0)
	v.add_theme_constant_override("separation", 8)
	map_back = _sub_head(v, "New Game: Map Settings", func(): show_screen("multi" if mp_mode else "setup"))
	var sh := HBoxContainer.new()
	seed_map_edit = LineEdit.new()
	seed_map_edit.text = str(opts.seed)
	seed_map_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_map_edit.add_theme_font_size_override("font_size", 18)
	seed_map_edit.text_changed.connect(func(t):
		_map_opts().seed = t
		_save_map())
	_style_edit(seed_map_edit)
	sh.add_child(seed_map_edit)
	sh.add_child(_dice(func():
		_map_opts().seed = random_seed()
		seed_map_edit.text = _map_opts().seed
		_save_map(), "Random seed"))
	_row("Map seed", sh, v)
	map_box = VBoxContainer.new()
	map_box.add_theme_constant_override("separation", 8)
	v.add_child(map_box)
	start_btn = _big("Start Game", BLUE, _map_done)
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
	if opts.get("race", "realm") != r or opts.get("random_race", false):
		opts.leader = "random"
	opts.race = r
	opts.random_race = false
	mp_rand = {}
	_save_opts()
	_refresh_setup()


## 0.19.3: Random: a random race, with a random leader, a nation name of that race and one of its flags, chosen when
## the game starts (in a lobby, when you press Done); the color stays yours.
func _pick_random_race() -> void:
	opts.random_race = not opts.get("random_race", false)
	opts.leader = "random"
	mp_rand = {}
	_save_opts()
	_refresh_setup()


var mp_rand := {}   # a lobby: the random nation drawn for this player (kept until they change their choices)


## The nation choices to play with: opts' own, or (Random) a race, leader, name and flag drawn now.
func resolved_nation() -> Dictionary:
	var o := {"race": str(opts.get("race", "realm")), "leader": str(opts.leader), "nation": opts.nation.duplicate()}
	if not opts.get("random_race", false):
		return o
	var rc: String = ["realm", "swamp", "wood"].pick_random()
	o.race = rc
	o.leader = "random"
	o.nation.name = random_nation_name(rc)
	while str(o.nation.name).length() > 24:
		o.nation.name = random_nation_name(rc)
	o.nation.emblem = Races.EMBLEMS[rc].pick_random()
	return o


## The New Game: Nation page's choices: race, leader, color, flag and emblem color (in a multiplayer lobby, colors and
## leaders other players have taken are grayed out).
func _refresh_setup() -> void:
	_clear_now(setup_box)
	var taken := _mp_taken()
	# race (web: menu.js #mRace): the leader list follows it
	var race := HBoxContainer.new()
	race.add_theme_constant_override("separation", 8)
	var rnd: bool = opts.get("random_race", false)
	for r in [["realm", "Realmlings", "Small, cheerful and sturdy: they start on grassland"], ["swamp", "Swamplings", "Fierce bog folk: they start in a swamp, fight and move better there, and raise Ogres"],
			["wood", "Woodlings", "Tall forest folk: they start in a forest, are tougher and quicker there, and need no roads"]]:
		race.add_child(_tog(r[1], not rnd and opts.get("race", "realm") == r[0], _pick_race.bind(r[0]), false, r[2]))
	race.add_child(_tog("Random", rnd, _pick_random_race, false, "Play a random game: a random race and leader, with a nation name and flag of that race, chosen when the game starts (your color stays yours)"))
	_row("Race", race, setup_box)
	if rnd:
		var rl := _lbl("Random: a leader of whichever race comes up", 16, MUTED)
		_row("Leader", rl, setup_box)
	else:
		_row("Leader", _leader_pick(), setup_box)
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
		b.disabled = taken.colors.has(i) and not on
		if b.disabled:   # (multiplayer: another nation flies this color)
			c = c.lerp(Color("#c8c8c8"), 0.75)
			b.tooltip_text = "Taken by %s" % taken.colors[i]
		for st in ["normal", "hover", "pressed", "disabled"]:
			var sb := _sb(c, 3 if on else 1, 17, 0, SUN if on else INK)
			b.add_theme_stylebox_override(st, sb)
		var ci := i
		b.pressed.connect(func():
			opts.nation.color = ci
			_save_opts()
			_refresh_setup())
		cols.add_child(b)
	_row("Color", cols, setup_box)
	var flags := HFlowContainer.new()
	flags.add_theme_constant_override("h_separation", 8)
	flags.add_theme_constant_override("v_separation", 6)
	flags.custom_minimum_size = Vector2(600, 0)
	var col_hex := str(NC[int(opts.nation.color)][0]).trim_prefix("#").to_lower()
	var FN: Dictionary = Races.EMBLEM_NAMES
	var ems: Array = Races.EMBLEMS[opts.get("race", "realm")]
	if not ems.has(opts.nation.emblem):   # each race flies its own flags
		opts.nation.emblem = ems[0]
	for em in ems:
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 46)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = FN.get(em, em)
		var on: bool = opts.nation.emblem == em
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, _sb(Color("#fff2c2") if on else Color(0, 0, 0, 0), 3 if on else 0, 4, 3, SUN))
		var ftex = Art.flag_texture(col_hex, em, str(opts.nation.get("secondary", "#faf1dc")))
		if ftex:
			var r := TextureRect.new()
			r.texture = ftex
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
	# the emblem's color, on top of the nation's color: a column per hue, light at the top to deep at the bottom
	# (no black: the deepest neutral is a gray)
	var sec_box := HBoxContainer.new()
	sec_box.add_theme_constant_override("separation", 5)
	for row in Races.EMBLEM_COLORS:
		var vc := VBoxContainer.new()
		vc.add_theme_constant_override("separation", 3)
		for cs in row:
			var sb := Button.new()
			sb.custom_minimum_size = Vector2(22, 18)
			sb.focus_mode = Control.FOCUS_NONE
			sb.tooltip_text = "Emblem color"
			var picked: bool = str(opts.nation.get("secondary", "#faf1dc")).to_lower() == cs
			for st in ["normal", "hover", "pressed"]:
				sb.add_theme_stylebox_override(st, _sb(Color(cs), 3 if picked else 1, 4, 0, SUN if picked else INK))
			var c2: String = cs
			sb.pressed.connect(func():
				opts.nation.secondary = c2
				_save_opts()
				_refresh_setup())
			vc.add_child(sb)
		sec_box.add_child(vc)
	_row("Emblem color", sec_box, setup_box)


## The New Game: Map Settings page's choices: the map, start position, island and the opponents. M: the settings it
## changes (the New Game ones, or the multiplayer host's own).
func _refresh_map() -> void:
	_clear_now(map_box)
	var M: Dictionary = _map_opts()
	var practice := false   # 0.19: every island is a full island; the Full/Practice choice is gone
	# (0.19.3: no Start position choice: the first capital is on or near the coast, the rest spread out; Game.spawn_pick)
	# the island
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 8)
	for s in SHAPES:
		sh.add_child(_tog(s[1], M.map.shape == s[0], func():
			M.map.shape = s[0]
			_save_map()
			_refresh_map(), practice, s[2]))
	_row("Island", sh, map_box)
	# 0.19.3: each a range, Min to Max: the island gets a value between them, drawn from its seed
	var lake_off: bool = M.map.shape == "ring"   # (the Ring has its great lake instead)
	for sl in [["Peninsulas", "pens", 5], ["Coves", "coves", 5], ["Trees", "trees", 5], ["Lakes", "lakes", 5]]:
		var key: String = sl[1]
		var top: int = sl[2]
		var rg := map_range(M.map, key)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		for side in 2:
			var tag := _lbl("Min" if side == 0 else "Max", 14, MUTED)
			tag.custom_minimum_size = Vector2(36 if side == 0 else 46, 0)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			h.add_child(tag)
			var v: int = rg[side]
			var off := practice or (key == "lakes" and lake_off)
			var step := func(by: int):
				var r2 := map_range(M.map, key)
				r2[side] = clampi(r2[side] + by, Game.TREE_MIN_STEP if key == "trees" else 0, top)
				if side == 0 and r2[0] > r2[1]:
					r2[1] = r2[0]
				if side == 1 and r2[1] < r2[0]:
					r2[0] = r2[1]
				M.map[key + "_min"] = r2[0]
				M.map[key + "_max"] = r2[1]
				M.map.erase(key)
				_save_map()
				_refresh_map()
			var minus := _btn("−", BLUE, step.bind(-1), "Less")
			minus.custom_minimum_size = Vector2(40, 34)
			minus.disabled = off or v <= (Game.TREE_MIN_STEP if key == "trees" else 0)
			h.add_child(minus)
			var val := _lbl(Game.MAP_WORDS[v], 17)   # (None, Few, Some, Normal, More, Lots)
			val.custom_minimum_size = Vector2(64, 0)
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.add_child(val)
			var plus := _btn("+", BLUE, step.bind(1), "More")
			plus.custom_minimum_size = Vector2(40, 34)
			plus.disabled = off or v >= top
			h.add_child(plus)
		if key == "trees":
			h.tooltip_text = "Normal; More: a fifth of the ruin borders are tree lines instead; Lots: a fifth of the ruin and a fifth of the mountain borders"
		if key == "lakes":
			h.tooltip_text = "Lakes inside the island, each 2 to 3 provinces" + (" (the Ring has its great lake instead)" if lake_off else "")
		var note := _lbl("random in between" if rg[0] != rg[1] else "", 13, MUTED)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(note)
		_row(sl[0], h, map_box)
	# the opponents
	var ob := VBoxContainer.new()
	ob.add_theme_constant_override("separation", 6)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	var humans := _mp_humans()
	for i in 7:
		var d: String = M.slots[i]
		var wrap := HBoxContainer.new()
		wrap.add_theme_constant_override("separation", 3)
		if i < humans.size():   # a player's nation takes this slot
			var hb := Button.new()
			hb.text = "%d   %s" % [i + 1, str(humans[i]).left(12)]
			hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			hb.custom_minimum_size = Vector2(159, 32)
			hb.disabled = true
			hb.tooltip_text = "%s plays this nation" % humans[i]
			hb.add_theme_font_size_override("font_size", 15)
			for st in ["normal", "disabled"]:
				hb.add_theme_stylebox_override(st, _sb(Color("#dbe8ff"), 1, 2, 4))
			hb.add_theme_color_override("font_disabled_color", INK)
			wrap.add_child(hb)
			grid.add_child(wrap)
			continue
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
				var k := SLOT_CYCLE.find(M.slots[si])
				M.slots[si] = SLOT_CYCLE[(k + (1 if ev.button_index == MOUSE_BUTTON_LEFT else SLOT_CYCLE.size() - 1)) % SLOT_CYCLE.size()]
				_save_map()
				_refresh_map.call_deferred()
				b.accept_event())
		wrap.add_child(b)
		# the opponent's race: Realmling, Swampling, Woodling or ? (random); web: menu.js slot race buttons
		var rb := Button.new()
		var sr: String = str(M.races[si])
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
			M.races[ri] = cyc[(cyc.find(str(M.races[ri])) + 1) % cyc.size()]
			_save_map()
			_refresh_map.call_deferred())
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
			M.slots = [qq, qq, qq, qq, qq, qq, qq]
			_save_map()
			_refresh_map())
		quick.add_child(b)
	ob.add_child(quick)
	var n: int = range(humans.size(), 7).filter(func(x): return M.slots[x] != "closed").size() + humans.size()
	_row("Opponents\n%s" % ("" if practice else "%d nation%s" % [n + 1, "s" if n else ""]), ob, map_box)
	if mp_mode:   # 0.19.3: Spawn near players, with 3 or more computer nations
		var ok := _mp_ais(M) >= Game.NEAR_MIN_AI
		var on: bool = ok and bool(M.get("near", false))
		_row("Players", _tog("Spawn near players", on, func():
			M.near = not bool(M.get("near", false))
			_save_map()
			_refresh_map(), not ok,
			"Each player starts as near the first player as the room around every capital allows, and no computer nation starts between two players" if ok else "Needs 3 or more computer nations"), map_box)




## A map setting's range [min, max] (0.19.3); an older remembered single value is both. Lakes: 1-3 at first, as
## islands always had.
static func map_range(m: Dictionary, key: String) -> Array:
	if m.has(key + "_min") or m.has(key + "_max"):
		var lo := int(m.get(key + "_min", m.get(key + "_max", 0)))
		return [lo, maxi(lo, int(m.get(key + "_max", lo)))]
	if m.has(key):   # (an older single value; trees: the old density 0-4 as a step)
		var v := int(m[key])
		if key == "trees":
			v = [3, 4, 4, 5, 5][clampi(v, 0, 4)]
		return [v, v]
	if key == "trees" and (m.has("trees_min") or m.has("trees_max")):   # (never below Normal)
		var r3 := [maxi(Game.TREE_MIN_STEP, int(m.get("trees_min", 3))), maxi(Game.TREE_MIN_STEP, int(m.get("trees_max", 3)))]
		return [r3[0], maxi(r3[0], r3[1])]
	return [1, 3] if key == "lakes" else [2, 2] if key in ["pens", "coves"] else [3, 3]


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
	var taken: Dictionary = _mp_taken().leaders
	for id in ids:
		var on: bool = opts.leader == id
		var b := Button.new()
		b.custom_minimum_size = Vector2(66, 104)
		if taken.has(id) and not on:   # (multiplayer: another player leads with them)
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0.35)
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
		if b.disabled:
			b.tooltip_text = "Taken by %s" % taken[id]
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
		"scouts": return "Starts with 2 Wayfinders, Wayfinder Stealth and Far-Seeing Wayfinders (Automating Wayfinders is left for you to research)."
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
	var seed := seed_map_edit.text.strip_edges() if seed_map_edit else str(opts.seed)
	if seed == "":
		seed = random_seed()
		if seed_map_edit:
			seed_map_edit.text = seed
	opts.seed = seed
	_save_opts()
	if start_btn:
		start_btn.text = "Building the realm…"
		start_btn.disabled = true
	var o := opts.duplicate(true)
	var R := resolved_nation()   # (0.19.3: Random draws the race, leader, name and flag now)
	o.race = R.race
	o.leader = R.leader
	o.nation = R.nation
	main.start_from_menu(o)


func reset_start() -> void:
	if start_btn:
		start_btn.text = "Done" if mp_mode else "Start Game"
		start_btn.disabled = false
