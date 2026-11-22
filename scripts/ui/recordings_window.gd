class_name RecordingsWindow
extends Control
## The start screen's list of recorded games (user://recordings/): when, which map, who played, how long. Watch one,
## or delete it. Turn recording on in Settings → Record games.

var win: Dictionary
var box: VBoxContainer
var on_watch: Callable   # called with the file's path


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	win = UiKit.window("Recorded games", 760, func(): close())
	add_child(win.panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(740, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	win.body.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	win.panel.hide()


func open() -> void:
	_fill()
	win.panel.show()
	UiKit.center.call_deferred(win.panel)


func close() -> void:
	win.panel.hide()


## {path, made, seed, nations, length, events} for every recording, newest first.
static func list() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(Recorder.DIR):
		return out
	for f in DirAccess.get_files_at(Recorder.DIR):
		if not f.ends_with(".json"):
			continue
		var path: String = Recorder.DIR + f
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (d is Dictionary) or not d.has("header") or d.get("frames", []).is_empty():
			continue
		var you = d.header.nations.filter(func(n): return int(n.id) == Game.LOCAL)
		out.append({"path": path, "made": str(d.get("made", "")), "seed": str(d.header.seed), "nations": d.header.nations.size(),
			"length": float(d.frames[-1].t) - float(d.frames[0].t), "events": d.ev.size(), "leader": you[0].get("leader", "") if not you.is_empty() else ""})
	out.sort_custom(func(a, b): return a.made > b.made)
	return out


func _fill() -> void:
	UiKit.clear(box)
	var all := list()
	if all.is_empty():
		var l := UiKit.rich(18, 700)
		l.text = "No recorded games yet. Turn on [b]Record games[/b] in Settings: your next full-map game is recorded as you play, and shows up here."
		box.add_child(l)
		return
	for r in all:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := UiKit.rich(17, 470)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "[b]%s[/b] · seed %s\n%s · %d nations · %s long · %d events" % [r.made.replace("T", " ").left(16), r.seed, r.leader, r.nations, Game.fmt_time(r.length), r.events]
		row.add_child(l)
		var path: String = r.path
		row.add_child(UiKit.button("Watch", 18, func():
			close()
			if on_watch.is_valid():
				on_watch.call(path)))
		var del := UiKit.button("Delete", 18)
		del.pressed.connect(func():
			if del.text == "Delete":
				del.text = "Sure?"
				return
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			_fill())
		row.add_child(del)
		box.add_child(row)
