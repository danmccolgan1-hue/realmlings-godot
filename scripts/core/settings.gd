class_name Settings
extends RefCounted
## The player's settings, remembered between games in user://settings.json (the web game keeps them in localStorage:
## realm-view, realm-record, the UI size). Not part of a saved game.

static var PATH := "user://settings.json"   # (tests point it elsewhere)

static var ui_scale := 1.0
static var calm_map := false        # web: v96.js Calm map (trees stand still; the web game also hides its villagers)
static var fullscreen := false
static var record_games := false    # web: v102.js Record games (off by default)
static var view := {"names": false, "realm": true, "res": true, "miniColor": false, "hideFull": false}   # web: v78.js VIEW (realm-view)
static var roster_tab := "units"     # web: game.js rosterTab (realm-roster-tab)
static var roster_folded := []       # web: v96.js RO_COL (realm-rocol)
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (d is Dictionary):
		return
	ui_scale = clampf(float(d.get("ui_scale", 1.0)), 0.7, 1.6)
	calm_map = bool(d.get("calm_map", false))
	fullscreen = bool(d.get("fullscreen", false))
	record_games = bool(d.get("record_games", false))
	var v = d.get("view", {})
	if v is Dictionary:
		for k in view:
			if v.has(k):
				view[k] = bool(v[k])
	roster_tab = str(d.get("roster_tab", "units"))
	var rf = d.get("roster_folded", [])
	roster_folded = rf if rf is Array else []


static func save_all() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"ui_scale": ui_scale, "calm_map": calm_map, "fullscreen": fullscreen, "record_games": record_games, "view": view, "roster_tab": roster_tab, "roster_folded": roster_folded}, " "))
	f.close()


## Put the window settings into effect (the UI size and full screen).
static func apply(tree: SceneTree) -> void:
	tree.root.content_scale_factor = ui_scale
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and not (want == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
		DisplayServer.window_set_mode(want)
