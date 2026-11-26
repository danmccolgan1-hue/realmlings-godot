class_name SettingsWindow
extends Control
## Settings (from the in-game menu and the start screen): UI size, full screen, Calm map, Record games, and while a
## game is on, its map seed and the debug switches. web: page.html #settings, v78 / v96 / v102 toggles, swamp.js
## debug buttons. Settings are remembered (Settings, user://settings.json); the debug switches belong to the game.

var game: Game          # null on the start screen
var win: Dictionary
var body: VBoxContainer
var on_change: Callable  # called after a setting changes (the HUD re-applies the UI size)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win = UiKit.window("Settings", 520, func(): close())
	add_child(win.panel)
	body = win.body
	win.panel.hide()


func open(g: Game = null) -> void:
	game = g
	_fill()
	win.panel.show()
	UiKit.center.call_deferred(win.panel)


func close() -> void:
	win.panel.hide()


func toggle(g: Game = null) -> void:
	if win.panel.visible:
		close()
	else:
		open(g)


func _row(text: String, tip: String, ctl: Control) -> void:
	var r := HBoxContainer.new()
	var l := UiKit.ink(20)
	l.text = text
	l.tooltip_text = UiKit.wrap(tip)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	r.add_child(ctl)
	body.add_child(r)


func _switch(on: bool, f: Callable) -> Button:
	var b := UiKit.button("On" if on else "Off", 18)
	b.toggle_mode = true
	b.button_pressed = on
	b.custom_minimum_size = Vector2(70, 0)
	b.toggled.connect(func(v):
		b.text = "On" if v else "Off"
		f.call(v))
	return b


func _changed() -> void:
	Settings.save_all()
	Settings.apply(get_tree())
	if on_change.is_valid():
		on_change.call()


func _fill() -> void:
	UiKit.clear(body)
	var size := HBoxContainer.new()
	var val := UiKit.ink(18)
	val.text = "%d%%" % int(round(Settings.ui_scale * 100))
	size.add_child(UiKit.button("−", 18, func():
		Settings.ui_scale = clampf(snappedf(Settings.ui_scale - 0.1, 0.1), 0.7, 1.6)
		val.text = "%d%%" % int(round(Settings.ui_scale * 100))
		_changed()))
	size.add_child(val)
	size.add_child(UiKit.button("+", 18, func():
		Settings.ui_scale = clampf(snappedf(Settings.ui_scale + 0.1, 0.1), 0.7, 1.6)
		val.text = "%d%%" % int(round(Settings.ui_scale * 100))
		_changed()))
	size.add_child(UiKit.button("Reset", 18, func():
		Settings.ui_scale = 1.0
		val.text = "100%"
		_changed()))
	_row("Interface size", "Makes every window, button and label bigger or smaller.", size)
	for au in [["Music", "music_on", "music_vol", "The tavern music, and its volume. M turns it on or off."], ["Sound effects", "sfx_on", "sfx_vol", "Clicks, footsteps, battles, spells and alarms, and their volume."]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.value = Settings.audio(au[2]) * 100
		sl.custom_minimum_size = Vector2(140, 0)
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var vk: String = au[2]
		sl.value_changed.connect(func(x):
			Settings.set_audio(vk, x / 100.0)
			Settings.save_all())
		h.add_child(sl)
		var ok: String = au[1]
		h.add_child(_switch(Settings.audio(ok), func(v):
			Settings.set_audio(ok, v)
			Settings.save_all()))
		_row(au[0], au[3], h)
	_row("Full screen", "Play in full screen, or in a window.", _switch(Settings.fullscreen, func(v):
		Settings.fullscreen = v
		_changed()))
	_row("Quick queue", "When on, right-clicking a province with only Wayfinders and Masons selected opens their survey / build menu without holding Ctrl.", _switch(Settings.view.get("quickQueue", false), func(v):
		Settings.view.quickQueue = v
		_changed()))
	_row("Players box", "Multiplayer: the box listing who is playing, their nation and connection. Off hides it (a message still shows while the game waits for someone).", _switch(Settings.view.get("players", true), func(v):
		Settings.view.players = v
		_changed()))
	_row("Calm map", "Trees stand still on the map (for a quieter screen).", _switch(Settings.calm_map, func(v):
		Settings.calm_map = v
		_changed()))
	_row("Record games", "Records new full-map games (and this one, from now on) so you can watch them back from the start screen: the map as it changed, every nation's growth, and the decisions that shaped it. Practice and tutorial games aren't recorded.", _switch(Settings.record_games, func(v):
		Settings.record_games = v
		_changed()
		if game != null and game.has_method("rec_toggle"):
			game.do("rec_toggle", [v])))
	var tok := LineEdit.new()
	tok.secret = true
	tok.text = Settings.bug_token
	tok.placeholder_text = "GitHub token"
	tok.custom_minimum_size = Vector2(200, 0)
	tok.text_changed.connect(func(v):
		Settings.bug_token = v.strip_edges()
		Settings.save_all())
	_row("Bug reports", "The bug button (top right in a game) sends your report and a screenshot to GitHub (%s, the bug_reports folder). Paste a GitHub token that may write to that repository (a fine-grained token with Contents: read and write). Without one, reports are saved on this computer instead." % Settings.bug_repo, tok)
	if game == null:
		return
	var seed := UiKit.ink(18)
	seed.text = str(game.world.seed).trim_prefix("practice:")
	_row("Map seed", "The word this map was raised from: the same seed gives the same map.", seed)
	var dbg := UiKit.ink(22)
	dbg.text = "Debug"
	body.add_child(dbg)
	var mp: bool = game.seats.size() > 1
	if not game.debug_ok:   # a multiplayer game whose lobby didn't allow it
		var off := UiKit.ink(16)
		off.text = "Turned off in this game: the host didn't allow debug in the lobby."
		body.add_child(off)
		return
	if mp:
		var note := UiKit.ink(16)
		note.text = "Allowed by the host. Revealing the map and +2000 resources apply to every player."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(note)
	var reveal := CheckBox.new()
	reveal.text = "Reveal the map"
	reveal.add_theme_color_override("font_color", UiKit.INK)
	reveal.button_pressed = game.reveal_all
	reveal.tooltip_text = "Lift the fog over the whole map (untick to put it back)"
	reveal.toggled.connect(func(v): game.do("debug_reveal", [v]))
	body.add_child(reveal)
	body.add_child(_debug_btn("+2000 resources", "Adds 2000 gold, wood and food (and 2000 storage of each so it fits)%s; press again for more" % (" to every player" if mp else ""), func(): game.do("debug_resources", [])))
	var schools: Array = game.debug_schools()
	if schools.size() == 1:   # (your school is chosen, or only one is open to you)
		var techs := _debug_btn("Every technology", "Every technology of your race in all three trees (Magic: %s)" % GameData.c("SCHOOLS")[schools[0]].name, func(): game.do("debug_all_tech", [schools[0]]))
		techs.disabled = game.debug_tech and not mp and game.current_school() != null
		body.add_child(techs)
	else:   # choose the Magic school first
		var lab := UiKit.ink(16)
		lab.text = "Every technology of your race in all three trees, with the Magic school:"
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(lab)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		for k in schools:
			var sk: String = k
			row.add_child(_debug_btn(str(GameData.c("SCHOOLS")[sk].name), "Every technology, following the School of %s" % GameData.c("SCHOOLS")[sk].name, func(): game.do("debug_all_tech", [sk])))
		body.add_child(row)


func _debug_btn(text: String, tip: String, f: Callable) -> Button:
	var b := UiKit.button(text, 18)
	b.tooltip_text = UiKit.wrap(tip)
	b.pressed.connect(func():
		f.call()
		_fill())
	return b
