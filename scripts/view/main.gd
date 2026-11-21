extends Node2D
## Entry point. Milestone 1 so far: pick a seed and a Realmling leader, then play the Practice island.
## Space: pause / play. Left-click: select a unit or a province. Right-click: send the selected unit there.
## Command card keys: q w e r / a s d f / z x c v / u i o p. T: research (with no unit selected).
## F5: quick save, F9: quick load; an autosave every 5 minutes of play.
## Drag with the left mouse to box-select your units; drag with the right or middle mouse (or the arrow keys) to pan,
## wheel to zoom, Home: back to the capital. G: the Armory. Shift queues orders; Ctrl+right-click opens the survey /
## build menu. M: music on or off.
## Esc: close a window, or open the menu.

const SEED_WORDS := ["ember", "oak", "river", "banner", "moss", "crown", "lantern", "stone", "harbor", "thistle", "kettle", "saffron"]

var map: MapView
var cam: Camera2D
var hud: Hud
var menu: StartScreen        # the title card and the New Game page
var shot_slots := []        # (pictures: --world=moderate,easy… sets the opponent slots)
var status: Label
var thread: Thread
var game: Game
var dragging := false
var drag_moved := 0.0
var drag_btn := 0
var drag_from := Vector2.ZERO   # where a drag started (screen)
var box_on := false             # a left drag draws a selection box (web: game.js #box, finishBox)
var sound: Sound
var menu_settings: SettingsWindow
var patch_notes: PatchNotes
var recordings: RecordingsWindow
var replay: Replay
var replay_hud: ReplayHud


func _ready() -> void:
	Settings.load_all()
	Settings.apply(get_tree())
	# symbols the built-in font lacks (✓ ✗ ✕ ▸ ▾ ⚒ ⚔ ✦ ☐ ✔ …) come from DejaVu Sans, bundled, so they show on every PC
	var sym = load("res://assets/fonts/DejaVuSans.ttf")
	if sym != null and ThemeDB.fallback_font != null:
		ThemeDB.fallback_font.fallbacks = ThemeDB.fallback_font.fallbacks + [sym]
	map = MapView.new()
	add_child(map)
	cam = Camera2D.new()
	add_child(cam)
	sound = Sound.new()
	sound.main = self
	add_child(sound)
	hud = Hud.new()
	hud.main = self
	hud.map = map
	hud.cam = cam
	add_child(hud)
	_build_menu()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			menu.opts.seed = a.substr(7)
			menu.seed_edit.text = a.substr(7)
		elif a.begins_with("--leader="):
			menu.opts.leader = a.substr(9)
		elif a.begins_with("--world="):   # a full map: --world=moderate,difficult,easy
			shot_slots = a.substr(8).split(",")
		elif a == "--newgame":   # pictures: the New Game page
			menu.show_screen("setup")
		elif a == "--tutorial":
			start_tutorial.call_deferred()
		elif a == "--record":   # record this game (for pictures of a replay), without changing the saved setting
			Settings.record_games = true
		elif a.begins_with("--replay=") and Array(OS.get_cmdline_user_args()).any(func(x): return x.begins_with("--shot=")):
			start_replay.call_deferred(a.substr(9))
		elif a.begins_with("--shot=") and (OS.get_cmdline_user_args().has("--menu") or OS.get_cmdline_user_args().has("--newgame")):
			_menu_shot.call_deferred(a.substr(7), false)
		elif a.begins_with("--shot=") and (OS.get_cmdline_user_args().has("--patch") or Array(OS.get_cmdline_user_args()).any(func(x): return x.begins_with("--replay="))):
			if OS.get_cmdline_user_args().has("--patch"):
				_menu_shot.call_deferred(a.substr(7))
		elif a.begins_with("--shot=") and not OS.get_cmdline_user_args().has("--tutorial"):
			_start.call_deferred()


func _build_menu() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	menu = StartScreen.new()
	menu.main = self
	ui.add_child(menu)
	status = menu.status
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Realmlings %s" % ProjectSettings.get_setting("application/config/version"))
	menu_settings = SettingsWindow.new()
	ui.add_child(menu_settings)
	patch_notes = PatchNotes.new()
	ui.add_child(patch_notes)
	recordings = RecordingsWindow.new()
	ui.add_child(recordings)
	recordings.on_watch = start_replay
	how_to = HowToWindow.new()
	ui.add_child(how_to)
	files = FileDialog.new()
	files.access = FileDialog.ACCESS_FILESYSTEM
	files.use_native_dialog = true
	files.filters = PackedStringArray(["*.realmsave ; Realmlings saved game", "*.json ; Saved game (JSON)"])
	files.file_selected.connect(_on_file)
	ui.add_child(files)
	replay_hud = ReplayHud.new()
	add_child(replay_hud)
	_menu_backdrop()


var how_to: HowToWindow
var files: FileDialog
var files_mode := ""        # "import" or "export"
var backdrop_t := 0.0


## The title card's island: a practice island for a fixed seed, all of it shown, the camera drifting over it.
## web: menu.js bootMenu, showAllLand, menuDrift
func _menu_backdrop() -> void:
	var w := RealmGen.scale_world(RealmGen.generate_practice("lantern"))
	map.game = null
	map.set_world(w)
	backdrop_t = 0.0
	_drift(0.0)
	var z := map.fit_zoom() * 2.6   # (close enough that the drifting clouds have faded)
	cam.zoom = Vector2(z, z)


func _drift(dt: float) -> void:
	backdrop_t += dt
	var b := map.bounds()
	cam.position = b.get_center() + Vector2(cos(backdrop_t * 0.05) * b.size.x * 0.22, sin(backdrop_t * 0.07) * b.size.y * 0.18)


## Start a game with the New Game page's choices. web: menu.js startGame
func start_from_menu(o: Dictionary) -> void:
	if thread and thread.is_alive():
		return
	var practice: bool = o.practice and shot_slots.is_empty()
	var slots := Array(shot_slots) if not shot_slots.is_empty() else ([] if practice else Array(o.slots))
	var leader: String = "" if o.leader == "random" else o.leader
	status.text = "Raising the island…" if practice else "Raising the world and its nations…"
	thread = Thread.new()
	thread.start(_gen.bind(o.seed, leader, slots, o.start, o.map, o.nation, practice))


func start_tutorial() -> void:
	_on_ready(Tutorial.start(), false)


## Load a game from a file the player picks (web: save.js importSave, the menu's "Load a save file").
func import_save() -> void:
	files_mode = "import"
	files.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	files.title = "Load a saved game"
	files.popup_centered_ratio(0.6)


## Write the game to a file the player picks (web: save.js exportSave).
func export_save() -> void:
	if game == null:
		return
	files_mode = "export"
	files.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	files.title = "Export this game"
	var nm := str(game.player_info(Game.ME).name).to_lower()
	var safe := ""
	for ch in nm:
		safe += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "-"
	files.current_file = "realmlings-%s-%d.realmsave" % [safe, int(game.t)]
	files.popup_centered_ratio(0.6)


func _on_file(path: String) -> void:
	if files_mode == "export" and game != null:
		save_to(path)
	elif files_mode == "import":
		load_from(path)


## Leave the game for the start screen (from the in-game menu).
func to_main_menu() -> void:
	if game and game.tutorial == null:
		save_to(AUTOSAVE, true)
	save_recording()
	game = null
	hud.game = null
	hud.hide()
	map.game = null
	menu.show()
	menu.show_screen("main")
	_menu_backdrop()


func _dark(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", Color("#1d1a22"))
	l.add_theme_font_size_override("font_size", 22)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _start() -> void:
	menu.start_game()


func _gen(seed: String, leader_id: String, slots := [], start := "center", opts := {}, nation := {}, practice := false) -> void:
	var g := Game.new_practice(seed, leader_id, {}, nation) if practice else Game.new_world(seed, leader_id, slots, start, {}, opts, nation)
	if Settings.record_games and not slots.is_empty():
		Recorder.start(g, "new game")
	call_deferred("_on_ready", g)


func _on_ready(g: Game, from_thread := true) -> void:
	if from_thread:
		thread.wait_to_finish()
	game = g
	menu.reset_start()
	next_autosave = (floor(g.t / AUTOSAVE_EVERY) + 1) * AUTOSAVE_EVERY
	menu.hide()
	map.set_game(g)
	hud.set_game(g)
	g.on_sfx = Sound.play
	var b := map.bounds()
	cam.position = b.get_center()
	var vp := get_viewport_rect().size
	var z := minf(vp.x / b.size.x, vp.y / b.size.y) * 0.8
	cam.zoom = Vector2(z, z)
	_maybe_screenshot()


const QUICKSAVE := "user://quicksave.json"
const AUTOSAVE := "user://autosave.json"
const AUTOSAVE_EVERY := 300.0   # web: an autosave every 5 minutes of play
var next_autosave := AUTOSAVE_EVERY


func save_to(path: String, quiet := false) -> void:
	if game.tutorial != null:
		if not quiet:
			hud.add_toast("Saving is turned off in the tutorial.", true)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		hud.add_toast("Couldn't save: %s" % error_string(FileAccess.get_open_error()), true)
		return
	f.store_string(game.save_text())
	f.close()
	if not quiet:
		hud.add_toast("Saved.")


func load_from(path: String) -> void:
	if not FileAccess.file_exists(path):
		if hud.visible:
			hud.add_toast("No saved game yet.", true)
		else:
			status.text = "No saved game yet."
		return
	var txt := FileAccess.get_file_as_string(path)
	var why := Game.save_why(txt)
	var g := Game.load_text(txt) if why == "" else null
	if g == null:
		why = why if why != "" else "That save can't be read."
		if hud.visible:
			hud.add_toast(why, true)
		else:
			status.text = why
		return
	g.paused = true
	g.last = 0.0
	map.selected_unit = null
	hud.select_unit(null)
	hud.select_province(-1)
	_on_ready(g, false)
	hud.add_toast("Loaded. The game is paused: press Space to go on.")


# --- watching a recording ---

## Raise the recorded map and start playing it back (from Recorded games).
func start_replay(path: String) -> void:
	if thread and thread.is_alive():
		return
	status.text = "Raising the recorded map…"
	thread = Thread.new()
	thread.start(func(): call_deferred("_on_replay", Replay.load_file(path)))


func _on_replay(r) -> void:
	thread.wait_to_finish()
	if r == null:
		status.text = "That recording can't be read."
		return
	status.text = ""
	replay = r
	menu.hide()
	map.selected_unit = null
	map.selected_prov = -1
	map.set_game(r.g)
	replay_hud.setup(r, self, map, cam)
	var b := map.bounds()
	cam.position = b.get_center()
	var z := map.fit_zoom()
	cam.zoom = Vector2(z, z)
	for a in OS.get_cmdline_user_args():   # a picture of the replay: --replay=<file> --at=<seconds> --shot=<png>
		if a.begins_with("--shot="):
			replay_hud.playing = false
			var at: float = r.t1 * 0.6
			for x in OS.get_cmdline_user_args():
				if x.begins_with("--at="):
					at = float(x.substr(5))
			r.seek(at)
			replay_hud.step(0.0)
			for x in OS.get_cmdline_user_args():
				if x.begins_with("--zoom="):
					cam.zoom = Vector2(float(x.substr(7)), float(x.substr(7)))
					for u in r.g.units:
						if u.owner == Game.ME:
							cam.position = Vector2(u.x, u.y)
			for i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(a.substr(7))
			get_tree().quit()


func exit_replay() -> void:
	replay = null
	replay_hud.hide()
	map.game = null
	menu.show()
	_menu_backdrop()


func _process(delta: float) -> void:
	if replay != null:
		_camera(delta)
		replay_hud.step(delta)
		return
	if game == null and menu.visible:
		_drift(delta)
	if game:
		_camera(delta)
		game.update(Time.get_ticks_msec() / 1000.0)
		if game.t >= next_autosave:
			next_autosave = (floor(game.t / AUTOSAVE_EVERY) + 1) * AUTOSAVE_EVERY
			if game.tutorial == null:
				save_to(AUTOSAVE, true)
				save_recording()
				hud.add_toast("Autosaved.")


## The game's recording, if it has one, goes to user://recordings/ (on every autosave, on leaving and on quitting).
func save_recording() -> void:
	if game == null or game.rec.is_empty() or game.rec.get("frames", []).is_empty():
		return
	DirAccess.make_dir_recursive_absolute(Recorder.DIR)
	var f := FileAccess.open(Recorder.path_of(game), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(Recorder.export(game)))
	f.close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_recording()


## For checking the view without a person: godot --path . -- --shot=/tmp/a.png [--seed=ember] [--leader=finn]
## [--play=25] starts a game, lets it run that many game seconds, saves a picture and quits.
func _maybe_screenshot() -> void:
	var shot := ""
	var play := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--play="):
			play = float(a.substr(7))
	if shot == "":
		return
	map.selected_prov = game.capital
	hud.select_province(game.capital, "settlement" if OS.get_cmdline_user_args().has("--capital") else "")
	if OS.get_cmdline_user_args().has("--farm"):   # pictures: a Farm selected, its crop on the card
		game.extras[game.capital] = game.extras_in(game.capital) + [{"type": "farm", "slot": 3}]
		game.compute_income()
		hud.select_province(game.capital, "farm@3")
	var mason = null
	var wfu = null
	for u in game.units:
		if u.kind == Game.MASON and mason == null:
			mason = u
		elif u.kind == game.WAYFINDER and wfu == null:
			wfu = u
	var demo := OS.get_cmdline_user_args().has("--demo")
	var q1: int = game.open_nbr[game.capital][0].q
	var spells := OS.get_cmdline_user_args().has("--spells")
	var army = null
	for u in game.units:
		if u.kind == "army":
			army = u
	var battle := OS.get_cmdline_user_args().has("--battle")
	if play > 0 and OS.get_cmdline_user_args().has("--siege") and not game.nations.is_empty():
		# as in tests/fixtures/siege/siege.json: a walled capital next door, 20 Footmen battering their way in
		var foe: int = game.nations.keys()[0]
		var fc := game.capital_of(foe)
		var qs: Array = game.open_nbr[fc].map(func(n): return n.q).filter(func(p): return not game.buildings.has(p) and not game.unique_ban(p))
		game.ai_frozen = true
		game.nations[foe].tech.gov.done.append("walls")
		game.buildings[qs[0]] = {"stage": 0, "born": 0, "owner": Game.ME}
		game.surveyed[qs[0]] = 0
		game.stock.gold += 500
		game.stock.food += 3000
		for o in game.nations:
			game.met[o] = true
		game.compute_income()
		game.compute_fog()
		game.update(1.0)
		game.declare_war(Game.ME, foe)
		army = game.new_army(qs[0], {"d-sword": 20})
		game.order(army, fc)
		battle = true
	if play > 0 and battle and not OS.get_cmdline_user_args().has("--siege"):   # Cormac's Shield Footmen against a Bandit Gang next door, as in tests/fixtures/play/*_battle.json
		var gang := game.spawn_bandit(q1)
		gang.troops = {"d-sword": 5}
		game.order(army, q1)
	elif play > 0 and spells:   # Havva's Herbomancy, as in tests/fixtures/play/*_life.json
		game.grant_tech("school-life")
		for id in ["harvest", "mending", "forest", "eyesforest"]:
			game.grant_tech(id)
		game.order_build(mason, game.capital, "farm")
	elif play > 0 and demo:   # roads, walls and development: the scripted game of tests/fixtures/play/*_roads.json
		for k in Game.RES:
			game.stock[k] += 3000
		game.grant_tech("roads")
		game.queue_survey(wfu, q1)
		game.start_develop(game.capital)
	elif play > 0 and game.tutorial == null:
		game.queue_survey(wfu, game.open_nbr[game.capital][0].q)
		game.order_build(mason, game.capital, "farm")
	if play > 0:
		game.paused = false
		var real := 1.0
		var step := 0
		while game.t < play:
			real += 0.1
			if spells and step == 350:
				game.cast_spell(army, "harvest")
			if demo:
				if step == 400:
					game.order_build(mason, q1, "outpost")
				elif step == 900:
					game.start_link(mason, game.capital, "road")
				elif step == 1010:
					game.grant_tech("walls")
				elif step == 1020:
					for u in game.units:
						if u.kind == "army":
							game.order(u, q1)
			step += 1
			game.update(real)
		game.paused = true
		game.last = 0.0
		game.update(Time.get_ticks_msec() / 1000.0)
	if OS.get_cmdline_user_args().has("--reveal"):   # see the whole map (for pictures of the other nations)
		game.reveal_all = true
		game.compute_fog()
		for o in game.nations:
			game.met[o] = true
		map.layers.refresh()
	if OS.get_cmdline_user_args().has("--request") and not game.nations.is_empty():   # a computer nation's alliance offer
		var ids: Array = game.nations.keys()
		game.dip_request(ids[0], "alliance", {"vs": ids[-1]})
	if OS.get_cmdline_user_args().has("--dip"):   # the first nation's section open
		hud.diplomacy.open(game.nations.keys()[0] if not game.nations.is_empty() else 0)
	if OS.get_cmdline_user_args().has("--queue"):   # pictures: several units selected, queued orders, a move marker and a box
		var ws: Array = game.units.filter(func(v): return v.owner == Game.ME and v.kind != "army")
		var nb: Array = game.open_nbr[game.capital].map(func(n): return n.q)
		for q in nb:
			game.explored[q] = true
		game.queue_survey_on(ws.filter(func(v): return v.kind == game.WAYFINDER), nb[0], true)
		game.queue_survey_on(ws.filter(func(v): return v.kind == game.WAYFINDER), nb[1], true)
		game.order_group(ws.filter(func(v): return v.kind == Game.MASON), nb[2], false, null)
		game.order_group(ws.filter(func(v): return v.kind == Game.MASON), nb[1], true, null)
		hud.set_selection(ws + game.units.filter(func(v): return v.kind == "army" and v.owner == Game.ME))
		var c: Array = game.G.provs[nb[2]].ic
		mark_move(Vector2(c[0], c[1]))
		map.marks[-1].t0 += 0.25
		map.box = Rect2(Vector2(c[0] - 260, c[1] - 200), Vector2(220, 150))
		if OS.get_cmdline_user_args().has("--bmenu"):   # the Ctrl+right-click menu on the capital's neighbor
			game.stock.gold += 500
			game.stock.wood += 500
			game.grant_tech("roads")
			hud.open_build_menu(nb[0], Vector2(1150, 260), false, Vector2(c[0], c[1]))
	if OS.get_cmdline_user_args().has("--fx"):   # pictures: a battle at the capital, a Mage casting, an Earthquake striking
		var gang := game.spawn_bandit(game.capital)
		gang.troops = {"d-sword": 6}
		gang.seen = true
		for i in 40:
			game.paused = false
			game.update(200.0 + i * 0.1)
		var mg = game.new_army(game.open_nbr[game.capital][0].q, {game.MAGE: 1})
		game.explored[mg.prov] = true
		game.visible[mg.prov] = true
		mg.cast = {"spell": "harvest", "t0": game.t - 2, "dur": INF}
		game.add_spell_fx("quake", mg, mg.prov)
		game.spell_fx[-1].t0 = game.t - 1.0
		game.paused = true
		var c: Array = game.G.provs[game.capital].ic
		cam.position = Vector2(c[0] + 150, c[1] + 120)
	if OS.get_cmdline_user_args().has("--research"):
		hud.toggle_research()
	elif spells or battle:
		map.selected_unit = army
		hud.select_unit(army)
	elif not (OS.get_cmdline_user_args().has("--capital") or OS.get_cmdline_user_args().has("--farm") or OS.get_cmdline_user_args().has("--queue") or OS.get_cmdline_user_args().has("--fx")):
		map.selected_unit = mason
		hud.select_unit(mason)
	if OS.get_cmdline_user_args().has("--record"):
		save_recording()
	if OS.get_cmdline_user_args().has("--settings"):
		hud.settings.open(game)
	if OS.get_cmdline_user_args().has("--armory"):
		hud.armory.open()
	if OS.get_cmdline_user_args().has("--orders"):
		hud.armory.open(1)
	if OS.get_cmdline_user_args().has("--school"):
		hud.school.open()
	if OS.get_cmdline_user_args().has("--country"):
		hud.country.open()
	var b := map.bounds()
	go_home()   # the game opens on your capital, as the web game's home button frames it
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zoom="):
			cam.zoom = Vector2(float(a.substr(7)), float(a.substr(7)))
	if OS.get_cmdline_user_args().has("--siege") and army != null:
		cam.position = Vector2(army.x, army.y)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--look="):   # the n-th computer nation's capital
			var ids: Array = game.nations.keys()
			var o: int = ids[mini(int(a.substr(7)), ids.size() - 1)]
			var c := game.capital_of(o)
			if c >= 0:
				cam.position = Vector2(game.G.provs[c].ic[0], game.G.provs[c].ic[1])
		if a.begins_with("--rtab="):   # pictures: the outliner's tab
			Settings.roster_tab = a.substr(7)
		if a.begins_with("--landmark="):   # pictures: death | oasis | heart | setpiece | ruins | travelers | lair
			var what := a.substr(11)
			var p := -1
			var U = game.uq()
			if what in ["death", "oasis", "heart"] and U != null:
				p = U[what]
			elif what == "setpiece" and not game.setpieces.is_empty():
				for q in game.setpieces:
					game.sp_found[q] = true
				p = game.setpieces.keys()[0]
			elif what == "ruins" and not game.finds.is_empty():
				p = game.finds.keys()[0]
			elif what == "travelers" and not game.travelers.is_empty():
				p = game.travelers[0].prov
			elif what == "lair":
				for u in game.units:
					if u.get("bandit", false):
						u.seen = true
						p = u.prov
			if p >= 0:
				cam.position = Vector2(game.G.provs[p].ic[0], game.G.provs[p].ic[1] - 80)
	for i in 3:
		await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--fps"):   # how long frames take, playing at full speed, the whole map in view
		game.paused = false
		cam.zoom = Vector2(map.fit_zoom(), map.fit_zoom())
		cam.position = map.bounds().get_center()
		var t0 := Time.get_ticks_usec()
		var worst := 0.0
		var proc := 0.0
		for i in 240:
			var a0 := Time.get_ticks_usec()
			await get_tree().process_frame
			worst = maxf(worst, (Time.get_ticks_usec() - a0) / 1000.0)
			proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		print("FPS-CHECK avg frame %.1f ms, worst %.1f ms, process %.1f ms" % [(Time.get_ticks_usec() - t0) / 240000.0, worst, proc / 240.0])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hover="):   # hold the mouse over a spot until its tooltip shows
			var xy := a.substr(8).split(",")
			var at := Vector2(float(xy[0]), float(xy[1]))
			for i in 90:
				var mv := InputEventMouseMotion.new()
				mv.position = at + Vector2(i % 2, 0)
				mv.global_position = mv.position
				Input.parse_input_event(mv)
				await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()


## A picture of the start screen with the Patch Notes open (--patch), for checking the view.
func _menu_shot(path: String, notes := true) -> void:
	if notes:
		patch_notes.open()
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


var zoom_to := 0.0


## The camera: a smooth zoom toward the target, arrows / WASD-free panning (the letter keys are the command card's),
## kept within reach of the island. web: page.html zoomAt / clampCam
func _camera(dt: float) -> void:
	if zoom_to > 0:
		var z := lerpf(cam.zoom.x, zoom_to, minf(1.0, dt * 12))
		var before := get_global_mouse_position()
		cam.zoom = Vector2(z, z)
		cam.position += before - get_global_mouse_position()
		if absf(z - zoom_to) < 0.0005:
			zoom_to = 0.0
	var pan := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if pan != Vector2.ZERO and not (get_viewport().gui_get_focus_owner() is LineEdit):
		cam.position += pan * 900.0 * dt / cam.zoom.x
	var b := map.bounds().grow(850)
	cam.position = cam.position.clamp(b.position, b.end)


## Back to your capital (Home, and the house button top right).
## Frame your capital's province at 62% of the screen. web: game.js home, fitView
const MAX_Z := 6.0   # web: game.js MAX_Z


func go_home() -> void:
	if game == null or game.capital < 0:
		return
	var r := Rect2(map.polys[game.capital][0], Vector2.ZERO)
	for v in map.polys[game.capital]:
		r = r.expand(v)
	var vs := get_viewport().get_visible_rect().size
	var z := clampf(minf(vs.x * 0.62 / r.size.x, vs.y * 0.62 / r.size.y), map.fit_zoom() * 0.6, MAX_Z)
	zoom_to = 0.0
	cam.zoom = Vector2(z, z)
	cam.position = r.get_center()


func zoom_by(f: float) -> void:
	var lo := map.fit_zoom() * 0.6
	zoom_to = clampf((zoom_to if zoom_to > 0 else cam.zoom.x) * f, lo, MAX_Z)


func _unhandled_input(ev: InputEvent) -> void:
	if replay != null and ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE:
			exit_replay()
			get_viewport().set_input_as_handled()
			return
		if ev.keycode == KEY_SPACE:
			replay_hud.toggle_play()
			get_viewport().set_input_as_handled()
			return
	if ev is InputEventKey and ev.pressed and not ev.echo and game:
		if ev.keycode == KEY_ESCAPE:
			if hud.settings.win.panel.visible:
				hud.settings.close()
			elif hud.dialog.visible:
				hud.dialog.pick("close")
			elif hud.school.visible:
				hud.school.hide()
			elif hud.country.visible:
				hud.country.hide()
			elif hud.armory.visible:
				hud.armory.close()
			elif hud.diplomacy.win.panel.visible:
				hud.diplomacy.close()
			elif hud.aim != null:
				hud.aim = null
			else:
				hud.toggle_menu()
			get_viewport().set_input_as_handled()
			return
		if ev.keycode == KEY_Y and not ev.ctrl_pressed:
			hud.diplomacy.toggle()
			get_viewport().set_input_as_handled()
			return
		if ev.keycode == KEY_G and not ev.ctrl_pressed:
			hud.armory.toggle()
			get_viewport().set_input_as_handled()
			return
		if ev.keycode == KEY_HOME:
			go_home()
			return
		if ev.keycode == KEY_F11:
			hud.toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
		if ev.keycode == KEY_SPACE:
			game.paused = not game.paused
			get_viewport().set_input_as_handled()
			return
		if ev.keycode == KEY_F5:
			save_to(QUICKSAVE)
			return
		if ev.keycode == KEY_F9:
			load_from(QUICKSAVE)
			return
		if ev.keycode == KEY_T and hud.unit == null:
			hud.toggle_research()
			get_viewport().set_input_as_handled()
			return
		if hud.key(OS.get_keycode_string(ev.keycode).to_lower()):
			get_viewport().set_input_as_handled()
			return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			zoom_by(1.2)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			zoom_by(1 / 1.2)
		elif ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if ev.pressed:
				dragging = true
				drag_moved = 0.0
				drag_btn = ev.button_index
				drag_from = ev.position
				box_on = false
				if hud.pick.visible:
					hud.pick.hide()
			elif dragging and ev.button_index == drag_btn:
				dragging = false
				if box_on:
					_finish_box(ev.position, ev.shift_pressed)
				elif drag_moved < 7.0 and game:
					var ctrl: bool = ev.ctrl_pressed or ev.meta_pressed
					if ev.button_index == MOUSE_BUTTON_RIGHT or (ev.button_index == MOUSE_BUTTON_LEFT and ctrl and not hud.selection.is_empty()):
						_right_click(ev.position, ev.shift_pressed, ctrl)
					elif ev.button_index == MOUSE_BUTTON_LEFT:
						_left_click(ev.shift_pressed)
				box_on = false
				map.box = Rect2()
	elif ev is InputEventMouseMotion and dragging:
		drag_moved += ev.relative.length()
		if drag_btn == MOUSE_BUTTON_LEFT and game != null and hud.aim == null:
			if drag_moved > 6.0:   # left drag draws a selection box
				box_on = true
				var a := _to_world(drag_from)
				var b := _to_world(ev.position)
				map.box = Rect2(a, Vector2.ZERO).expand(b)
		else:
			cam.position -= ev.relative / cam.zoom


func _to_world(s: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * s


# web: game.js finishBox: your units inside the box (Shift adds them to the selection)
func _finish_box(at: Vector2, shift: bool) -> void:
	var x0 := minf(drag_from.x, at.x) - 6
	var x1 := maxf(drag_from.x, at.x) + 6
	var y0 := minf(drag_from.y, at.y) - 6
	var y1 := maxf(drag_from.y, at.y) + 6
	var ct := get_canvas_transform()
	var hit := []
	for u in game.units:
		if u.owner != Game.ME or u.get("exiting", false):
			continue
		var s: Vector2 = ct * Vector2(u.x, u.y - 8)
		if s.x >= x0 and s.x <= x1 and s.y >= y0 and s.y <= y1:
			hit.append(u)
	var list := hud.selection.duplicate() if shift else []
	for u in hit:
		if not list.any(func(v): return is_same(v, u)):
			list.append(u)
	hud.set_selection(list)
	if not list.is_empty():
		map.selected_prov = -1
		map.selected_part = ""
		hud.select_province(-1)


# web: game.js clickAt (a left click): the spell or Slippers aim, a unit (Shift adds or removes it), a building, the province
func _left_click(shift: bool) -> void:
	var at := get_global_mouse_position()
	if hud.aim != null:
		var tp := map.province_at(at)
		if tp >= 0:
			if hud.aim.spell == "fly":
				game.fly_army(hud.aim.unit, tp)
			elif hud.aim.spell == "shock":
				game.start_spell2(hud.aim.unit, "shock", tp)
			else:
				game.cast_spell(hud.aim.unit, hud.aim.spell, tp)
		hud.aim = null
		return
	var u = map.unit_at(at)
	if u != null and u.owner == Game.ME:
		if shift:
			var list: Array = hud.selection.filter(func(v): return not is_same(v, u)) if hud.is_selected(u) else hud.selection + [u]
			hud.set_selection(list)
		else:
			hud.set_selection([u])
		map.selected_prov = u.prov
		map.selected_part = ""
		hud.select_province(u.prov)
		return
	var hit = map.part_at(at)
	hud.set_selection([u] if u != null else [])
	var p: int = u.prov if u != null else hit.prov if hit != null else map.province_at(at)
	if hit == null and p >= 0 and not game.explored.has(p):
		p = -1
	map.selected_prov = p
	map.selected_part = hit.part if hit != null else ""
	hud.select_province(p, map.selected_part)


# web: game.js clickAt (a right click): orders for the selected units; Ctrl (or Quick queue) opens the survey / build menu
func _right_click(screen: Vector2, shift: bool, ctrl: bool) -> void:
	if hud.aim != null:
		hud.aim = null
		hud.add_toast("Cancelled.")
		return
	var at := _to_world(screen)
	var p := map.province_at(at)
	var sel: Array = hud.selection.filter(func(v): return v.owner == Game.ME)
	if sel.is_empty() or p < 0:
		return
	var workers := func(v): return v.kind == Game.MASON or v.kind == game.WAYFINDER
	var quick: bool = not ctrl and Settings.view.get("quickQueue", false) and sel.all(workers)
	if (ctrl or quick) and sel.any(func(v): return workers.call(v) or game.is_caster(v)):
		hud.open_build_menu(p, screen, shift, at)
		return
	var moved := game.order_group(sel, p, shift, [at.x, at.y])
	if not moved.is_empty() or shift:
		mark_move(at)
	Sound.move(moved)


## The marker where you sent your units: a ring that shrinks and fades in a second. web: v78.js moveMarks
func mark_move(at: Vector2) -> void:
	map.marks.append({"x": at.x, "y": at.y, "t0": Time.get_ticks_msec() / 1000.0})
	if map.marks.size() > 8:
		map.marks.pop_front()


func _exit_tree() -> void:
	if thread and thread.is_started():
		thread.wait_to_finish()
